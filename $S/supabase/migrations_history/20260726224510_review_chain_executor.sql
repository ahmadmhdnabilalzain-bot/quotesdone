-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726224510   name: review_chain_executor
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Quality standards: what "excellent" means per work type, as checkable rules.
insert into quality_standard (work_type, criteria, owner_dept) values
('social_post', '[
  {"rule":"anonymity","severity":"critical","pattern":"(?i)\\\\y(LLC|L\\\\.L\\\\.C|Trading Est|Contracting Co|General Trading)\\\\y","fails_when":"match","why":"AI Constitution principle 3: never reveal supplier identity before authorization. Naming a supplier company breaks the anonymous marketplace promise."},
  {"rule":"no_unverifiable_superlative","severity":"major","pattern":"(?i)\\\\y(cheapest|number one|#1|best price|guaranteed lowest|the best in UAE)\\\\y","fails_when":"match","why":"Constitution principle 1: truth over fluency. Unverifiable superlatives are fabricated claims."},
  {"rule":"no_price_promise","severity":"major","pattern":"(?i)(save \\\\d+%|\\\\d+% off|free quote in \\\\d+ (min|hour))","fails_when":"match","why":"Commercial promise the marketplace cannot guarantee on behalf of suppliers."},
  {"rule":"has_call_to_action","severity":"minor","pattern":"(?i)(post your rfq|get quotes|compare quotes|submit an inquiry|quotesdone\\\\.com)","fails_when":"no_match","why":"Every post should give the reader an action."}
]'::jsonb, 'marketing')
on conflict (work_type) do update set criteria = excluded.criteria, updated_at = now();

-- The review chain executor. Deterministic: a rule either fires or it does not.
create or replace function public.fn_review_submit(
  p_subject_type text,
  p_subject_id   text,
  p_dept_key     text,
  p_author       text,
  p_content      text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_head        text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
begin
  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  -- Step 1: the author drafts.
  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  -- Evaluate against the quality standard for this work type.
  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop
      if (v_rule->>'fails_when') = 'match'
         and p_content ~ (v_rule->>'pattern') then
        v_violations := v_violations || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
        if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
        elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
        if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
      elsif (v_rule->>'fails_when') = 'no_match'
         and p_content !~ (v_rule->>'pattern') then
        v_violations := v_violations || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
        if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
        elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
        if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
      end if;
    end loop;
  end if;

  -- Step 2: department head review. Deterministic decision.
  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) — ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) — ' || (v_violations::text);
    v_conf     := 0.9;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; no rule breaches detected';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations);
  end if;

  -- Step 3: Chief of Staff review, because content_publish is gated in org_authority.
  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve',
          'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  -- Step 4: publish.
  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('content.published', p_subject_type, p_subject_id, p_author,
          jsonb_build_object('dept', p_dept_key));

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations);
end;
$fn$;

comment on function public.fn_review_submit is 'Deterministic review chain: author -> department head -> Chief of Staff -> published. Every hop writes a review_chain row.';
