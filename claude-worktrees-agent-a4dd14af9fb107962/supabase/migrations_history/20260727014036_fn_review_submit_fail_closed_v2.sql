-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727014036   name: fn_review_submit_fail_closed_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
returns jsonb
language plpgsql security definer set search_path = 'public'
as $function$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_unenforced  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_pick        jsonb;
  v_head        text;
  v_deleg_from  text;
  v_deleg_basis text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
  v_res         jsonb;
begin
  -- Who is actually able to approve for this department right now.
  v_pick        := fn_pick_reviewer(p_dept_key);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  -- No available approver at all: hold and escalate rather than forging an approval.
  if v_head is null then
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                              decision, reason, confidence, delegated_from, delegation_basis)
    values (p_subject_type, p_subject_id, p_dept_key, p_author, null, 'dept_review',
            'escalate', 'No available approver in ' || p_dept_key || ': ' || coalesce(v_deleg_basis,''), 1.0,
            v_deleg_from, v_deleg_basis);
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'escalate',
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'reason', coalesce(v_deleg_basis,''));
  end if;

  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop

      if (v_rule ? 'check_fn') then
        -- Data-driven check. A check that cannot run is a failure, never a pass.
        begin
          execute format('select %I($1,$2)', v_rule->>'check_fn')
            into v_res using p_subject_id, p_content;
        exception when others then
          v_res := jsonb_build_object('passed', false, 'detail', 'check ' || (v_rule->>'check_fn') || ' errored: ' || sqlerrm);
        end;
        if not coalesce((v_res->>'passed')::boolean, false) then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity',
            'why', v_rule->>'why', 'detail', v_res->>'detail');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      elsif (v_rule ? 'pattern') and (v_rule ? 'fails_when') then
        if (v_rule->>'fails_when') = 'match' and p_content ~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        elsif (v_rule->>'fails_when') = 'no_match' and p_content !~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      else
        -- A criterion with no executable check. It must not silently pass.
        v_unenforced := v_unenforced || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
      end if;

    end loop;
  end if;

  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) - ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) - ' || (v_violations::text);
    v_conf     := 0.9;
  elsif jsonb_array_length(v_unenforced) > 0
        and exists (select 1 from jsonb_array_elements(v_unenforced) u where u->>'severity' = 'critical') then
    -- FAIL CLOSED. A critical criterion nobody can check is a reason to involve a person,
    -- not a reason to publish. This is the defect the Layer-4 run found.
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no executable check exists for critical criteria - ' || (v_unenforced::text);
    v_conf     := 1.0;
    v_first_rule := (select u->>'rule' from jsonb_array_elements(v_unenforced) u where u->>'severity'='critical' limit 1);
  elsif v_crit is null then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no quality standard is defined for work type "' || p_subject_type || '"';
    v_conf     := 1.0;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; every criterion was checked and passed';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf, v_deleg_from,
          case when v_deleg_from is not null then v_deleg_basis else null end);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'unenforceable', v_unenforced,
                              'reviewer', v_head, 'delegated_from', v_deleg_from);
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve', 'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('content.published', p_subject_type, p_subject_id, p_author,
          jsonb_build_object('dept', p_dept_key));

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations,
                            'unenforceable', v_unenforced,
                            'reviewer', v_head, 'delegated_from', v_deleg_from);
end;
$function$;

revoke execute on function public.fn_review_submit(text,text,text,text,text) from anon, authenticated, public;
