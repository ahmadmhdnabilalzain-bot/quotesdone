-- P2-C1 STAGE B.5 (4/4) - ONE operator-safe rollback entry point.
-- Applied as p2_c1_stage_b5_operator_rollback. Supersedes supabase/rollback/p2_c1_stage_b_down.sql.
--
-- Stage B's rollback was previously a script plus "now re-apply these five files in order". That is
-- a procedure an operator executes at 2am during an incident, and half-executed procedures are how
-- incidents get worse. This function does the whole thing in ONE transaction: it removes Stage B,
-- restores the Stage A objects Stage B modified, checks the object counts it expects, and then RUNS
-- the Stage A self-test. If any of that fails the transaction aborts and nothing has changed.
--
--   select public.fn_p2c1_rollback_stage_b('rehearse','ops:you');  -- always safe: aborts
--   select public.fn_p2c1_rollback_stage_b('commit','ops:you');    -- performs it
--
-- 'rehearse' deliberately ends in an exception. That is the mechanism, not a failure: raising is how
-- a function rolls back its own transaction. The report travels in the exception message.

create or replace function public.fn_p2c1_rollback_stage_b(
  p_mode text default 'rehearse', p_actor text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_b_rel_before int; v_b_rel_after int; v_b_fn_before int; v_b_fn_after int;
  v_a_rel int; v_brand_defs int; v_brand_src int; v_selftest text; v_fail int;
  v_report jsonb;
begin
  if p_mode not in ('rehearse','commit') then
    return jsonb_build_object('ok', false, 'error','mode must be rehearse or commit');
  end if;
  if coalesce(btrim(p_actor),'') = '' then
    return jsonb_build_object('ok', false, 'error','actor_required',
      'message','Rolling back a stage is a decision. It carries a name.');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                  where n.nspname='public' and t.typname='gate_state') then
    return jsonb_build_object('ok', false, 'error','stage_b_not_present',
      'message','gate_state is absent, so Stage B is already rolled back.');
  end if;

  select count(*) into v_b_rel_before from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('brand_acceptance_policy_value','field_question_variant',
     'subcategory_trade_contribution','field_definition_reference','mep_trade_pattern',
     'inquiry_trade_candidate','inquiry_trade_candidate_evidence','inquiry_trade_clarification',
     'mep_evidence_weight','p2c1_lang_case','p2c1_scope_case',
     'v_workstream_brand_policy','v_inquiry_trade_status');
  select count(*) into v_b_fn_before from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('fn_trade_identify','fn_trade_confirm','fn_trade_reject',
     'fn_trade_remove','fn_text_matches_pattern','fn_term_matches','fn_norm_text','fn_mep_full_scope',
     'fn_gate_state_satisfies','fn_field_value_allowed','fn_group_dispatch_report',
     'trg_inquiry_gate_state_sync','trg_inquiry_answer_value_domain','trg_mep_pattern_norm',
     'fn_p2c1_stage_b_selftest','fn_p2c1_stage_b_regression','fn_p2c1_lang_parity_suite',
     'fn_p2c1_run_lang_case','fn_p2c1_scope_rule_tests');

  -- 1. Stage B objects
  drop view if exists public.v_inquiry_trade_status cascade;
  drop view if exists public.v_workstream_brand_policy cascade;
  drop function if exists public.fn_p2c1_scope_rule_tests() cascade;
  drop function if exists public.fn_p2c1_lang_parity_suite() cascade;
  drop function if exists public.fn_p2c1_run_lang_case(text,text) cascade;
  drop function if exists public.fn_p2c1_stage_b_regression() cascade;
  drop function if exists public.fn_p2c1_stage_b_selftest() cascade;
  drop function if exists public.fn_group_dispatch_report(bigint) cascade;
  drop function if exists public.fn_trade_identify(bigint,text,jsonb,jsonb,text) cascade;
  drop function if exists public.fn_trade_confirm(bigint,text,text,text) cascade;
  drop function if exists public.fn_trade_reject(bigint,text,text,text) cascade;
  drop function if exists public.fn_trade_remove(bigint,text,text,text) cascade;
  drop function if exists public.fn_mep_full_scope(text) cascade;
  drop table if exists public.p2c1_scope_case cascade;
  drop table if exists public.p2c1_lang_case cascade;
  drop table if exists public.inquiry_trade_candidate_evidence cascade;
  drop table if exists public.inquiry_trade_clarification cascade;
  drop table if exists public.inquiry_trade_candidate cascade;
  drop trigger if exists mep_trade_pattern_norm on public.mep_trade_pattern;
  drop function if exists public.trg_mep_pattern_norm() cascade;
  drop table if exists public.mep_trade_pattern cascade;
  drop table if exists public.mep_evidence_weight cascade;
  drop table if exists public.field_definition_reference cascade;
  drop table if exists public.subcategory_trade_contribution cascade;
  drop table if exists public.field_question_variant cascade;
  drop table if exists public.brand_acceptance_policy_value cascade;
  drop function if exists public.fn_term_matches(text,text,text) cascade;
  drop function if exists public.fn_norm_text(text) cascade;
  drop function if exists public.fn_text_matches_pattern(text,text) cascade;

  -- 2. shared-table modifications
  drop trigger if exists inquiry_answer_value_domain on public.inquiry_answer;
  drop function if exists public.trg_inquiry_answer_value_domain() cascade;
  drop function if exists public.fn_field_value_allowed(text,text) cascade;
  drop trigger if exists inquiry_gate_state_sync on public.inquiry_gate;
  drop function if exists public.trg_inquiry_gate_state_sync() cascade;
  alter table public.inquiry_gate drop column if exists state;
  alter table public.inquiry_gate drop column if exists state_reason;
  drop function if exists public.fn_gate_state_satisfies(public.gate_state) cascade;
  drop type if exists public.gate_state cascade;
  update public.inquiry_gate set passed = false where passed is null;
  alter table public.inquiry_gate alter column passed set default false;
  alter table public.inquiry_gate alter column passed set not null;
  alter table public.field_definition drop column if exists allowed_values;
  alter table public.field_definition drop column if exists supersedes_field_ids;
  alter table public.mep_trade drop column if exists is_core;

  -- 3. brand policy: remove the Stage B identities, restore the Stage A ones and their mappings
  delete from public.field_definition where field_id like '%.brand_acceptance_policy%';

  insert into public.field_definition
    (field_id, scope, trade_key, label_en, label_ar, unit, answer_type,
     evidence_rule, review_status, review_note)
  select distinct on (tr.trade_key)
         tr.trade_key || '.brand_policy', 'trade_specific', tr.trade_key,
         q.question_en, q.question_ar, q.unit, q.answer_type,
         'Trade-specific: this identity may only satisfy the ' || tr.trade_key || ' workstream.',
         'question_for_founder',
         'Restored by fn_p2c1_rollback_stage_b. Stage B had merged these into shared.brand_acceptance_policy.'
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug and q.field_key = 'brand_policy'
   order by tr.trade_key, q.subcategory_slug
  on conflict (field_id) do nothing;

  insert into public.field_definition_source (subcategory_slug, source_field_key, field_id)
  select distinct m.subcategory_slug, 'brand_policy', tr.trade_key || '.brand_policy'
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug and q.field_key = 'brand_policy'
  on conflict (subcategory_slug, source_field_key) do nothing;

  -- 4. Stage A view chain
  execute $q1$ drop view if exists public.v_group_dispatch cascade $q1$;
  execute $q1$ drop view if exists public.v_group_completeness cascade $q1$;
  execute $q1$ drop view if exists public.v_workstream_dispatch cascade $q1$;
  execute $q1$ drop view if exists public.v_workstream_completeness cascade $q1$;
  execute $q1$ drop view if exists public.v_workstream_answer cascade $q1$;

  execute $q2$
    create view public.v_workstream_answer as
    select w.id as workstream_id, w.group_id, w.trade_key, w.active,
           a.id as answer_id, a.field_id, a.value, a.unit, a.scope, a.precedence, a.source_kind,
           a.confirmed_at,
           (a.value is not null and btrim(a.value) <> ''
            and a.precedence not in ('model_inference','unknown')) as satisfies_mandatory
      from public.inquiry_workstream w
      join public.inquiry_answer a on a.group_id = w.group_id and a.superseded_by is null
     where a.scope = 'inquiry_shared'
        or exists (select 1 from public.inquiry_answer_scope s
                    where s.answer_id = a.id and s.workstream_id = w.id)
  $q2$;

  execute $q3$
    create view public.v_workstream_completeness as
    select w.id as workstream_id, w.group_id, w.trade_key, w.active,
           count(*) filter (where r.mandatory) as required_mandatory,
           count(*) filter (where r.mandatory and va.satisfies_mandatory) as answered_mandatory,
           count(*) filter (where not r.mandatory) as required_optional,
           count(*) filter (where not r.mandatory and va.satisfies_mandatory) as answered_optional,
           coalesce(array_agg(r.field_id order by r.field_id)
                    filter (where r.mandatory and not coalesce(va.satisfies_mandatory,false)),
                    '{}'::text[]) as missing_mandatory,
           coalesce((select array_agg(distinct vc.field_id)
                       from public.v_workstream_conflict vc where vc.workstream_id = w.id),
                    '{}'::text[]) as blocked_by
      from public.inquiry_workstream w
      left join public.inquiry_workstream_requirement r on r.workstream_id = w.id
      left join public.v_workstream_answer va on va.workstream_id = w.id and va.field_id = r.field_id
     group by w.id, w.group_id, w.trade_key, w.active
  $q3$;

  execute $q4$
    create view public.v_workstream_dispatch as
    select c.workstream_id, c.group_id, c.trade_key, c.active,
           c.required_mandatory, c.answered_mandatory, c.missing_mandatory, c.blocked_by,
           (cardinality(c.missing_mandatory) = 0) as mandatory_complete,
           (cardinality(c.blocked_by) = 0)        as no_unresolved_conflict,
           not exists (select 1 from public.inquiry_gate_required gr
                        where gr.level = 'workstream'
                          and not exists (select 1 from public.inquiry_gate g
                                           where g.workstream_id = c.workstream_id
                                             and g.gate_key = gr.gate_key and g.passed)) as gates_passed,
           (c.active and cardinality(c.missing_mandatory) = 0 and cardinality(c.blocked_by) = 0
            and not exists (select 1 from public.inquiry_gate_required gr
                             where gr.level = 'workstream'
                               and not exists (select 1 from public.inquiry_gate g
                                                where g.workstream_id = c.workstream_id
                                                  and g.gate_key = gr.gate_key and g.passed))) as dispatch_eligible
      from public.v_workstream_completeness c
  $q4$;

  execute $q5$
    create view public.v_group_completeness as
    select g.id as group_id, g.inquiry_id, g.rfq_mode,
           count(*) filter (where sr.mandatory) as shared_required_mandatory,
           count(*) filter (where sr.mandatory and a.id is not null) as shared_answered_mandatory,
           coalesce(array_agg(sr.field_id order by sr.field_id)
                    filter (where sr.mandatory and a.id is null), '{}'::text[]) as shared_missing_mandatory,
           (select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active) as active_workstreams,
           (select count(*) from public.inquiry_answer_conflict c
             join public.field_definition fd on fd.field_id = c.field_id
            where c.group_id = g.id and c.resolved_at is null and fd.scope = 'shared') as open_shared_conflicts
      from public.inquiry_workstream_group g
      left join lateral (
        select r.field_id, bool_or(r.mandatory) as mandatory
          from public.inquiry_workstream_requirement r
          join public.inquiry_workstream w on w.id = r.workstream_id
          join public.field_definition fd on fd.field_id = r.field_id
         where w.group_id = g.id and w.active and fd.scope = 'shared'
         group by r.field_id
      ) sr on true
      left join public.inquiry_answer a
        on a.group_id = g.id and a.field_id = sr.field_id and a.superseded_by is null
       and a.value is not null and btrim(a.value) <> ''
       and a.precedence not in ('model_inference','unknown')
     group by g.id, g.inquiry_id, g.rfq_mode
  $q5$;

  execute $q6$
    create view public.v_group_dispatch as
    select gc.group_id, gc.inquiry_id, gc.rfq_mode, gc.active_workstreams,
           gc.shared_missing_mandatory,
           (cardinality(gc.shared_missing_mandatory) = 0) as shared_complete,
           (gc.open_shared_conflicts = 0)                 as no_unresolved_shared_conflict,
           coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                      where wd.group_id = gc.group_id and wd.active), false) as all_active_workstreams_eligible,
           coalesce((select array_agg(wd.trade_key order by wd.trade_key) from public.v_workstream_dispatch wd
                      where wd.group_id = gc.group_id and wd.active and not wd.dispatch_eligible),
                    '{}'::text[]) as blocking_trades,
           not exists (select 1 from public.inquiry_gate_required gr
                        where gr.level = 'group'
                          and not exists (select 1 from public.inquiry_gate g
                                           where g.group_id = gc.group_id and g.workstream_id is null
                                             and g.gate_key = gr.gate_key and g.passed)) as group_gates_passed,
           (gc.active_workstreams > 0
            and cardinality(gc.shared_missing_mandatory) = 0
            and gc.open_shared_conflicts = 0
            and coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                           where wd.group_id = gc.group_id and wd.active), false)
            and not exists (select 1 from public.inquiry_gate_required gr
                             where gr.level = 'group'
                               and not exists (select 1 from public.inquiry_gate g
                                                where g.group_id = gc.group_id and g.workstream_id is null
                                                  and g.gate_key = gr.gate_key and g.passed))) as overall_dispatch_eligible
      from public.v_group_completeness gc
  $q6$;

  -- 5. Stage A functions Stage B replaced
  execute $q7$
    create or replace function public.fn_inquiry_workstream_activate(
      p_group_id bigint, p_trade_key text, p_actor text default 'system')
    returns jsonb language plpgsql security definer set search_path to 'public' as $inner$
    declare v_ws_id bigint; v_route integer; v_reactivated boolean := false; v_reqs integer;
    begin
      if not exists (select 1 from public.mep_trade where trade_key = p_trade_key) then
        return jsonb_build_object('ok', false, 'error', 'unknown_trade', 'trade_key', p_trade_key);
      end if;
      if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
        return jsonb_build_object('ok', false, 'error', 'unknown_group');
      end if;
      select catalog_num into v_route from public.mep_trade_route
       where trade_key = p_trade_key and is_primary order by catalog_num limit 1;
      select id into v_ws_id from public.inquiry_workstream
       where group_id = p_group_id and trade_key = p_trade_key;
      if v_ws_id is null then
        insert into public.inquiry_workstream (group_id, trade_key, route_catalog_num)
        values (p_group_id, p_trade_key, v_route) returning id into v_ws_id;
      else
        update public.inquiry_workstream set active = true, activated_at = now(), deactivated_at = null
         where id = v_ws_id and active = false;
        v_reactivated := found;
        update public.inquiry_workstream set active = true where id = v_ws_id;
      end if;
      insert into public.inquiry_workstream_requirement (workstream_id, question_id, field_id, mandatory)
      select v_ws_id, min(q.question_id), s.field_id, bool_or(q.mandatory)
        from public.mep_trade_route tr
        join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
        join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
        join public.field_definition_source s
          on s.subcategory_slug = q.subcategory_slug and s.source_field_key = q.field_key
       where tr.trade_key = p_trade_key and q.field_key is not null
       group by s.field_id
      on conflict (workstream_id, field_id) do update
         set mandatory = public.inquiry_workstream_requirement.mandatory or excluded.mandatory;
      get diagnostics v_reqs = row_count;
      insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
      values (p_group_id, v_ws_id,
              case when v_reactivated then 'workstream_reactivated' else 'workstream_activated' end,
              jsonb_build_object('trade_key', p_trade_key, 'route_catalog_num', v_route,
                                 'requirements', v_reqs), p_actor);
      return jsonb_build_object('ok', true, 'workstream_id', v_ws_id, 'trade_key', p_trade_key,
                                'reactivated', v_reactivated, 'requirements', v_reqs);
    end $inner$
  $q7$;

  execute $q8$
    create or replace function public.fn_p2c1_fixture_satisfy(
      p_group bigint, p_ws bigint, p_actor text default 'selftest')
    returns integer language plpgsql security definer set search_path to 'public' as $inner$
    declare rec record; n integer := 0;
    begin
      for rec in
        select r.field_id, fd.scope from public.inquiry_workstream_requirement r
          join public.field_definition fd on fd.field_id = r.field_id
         where r.workstream_id = p_ws and r.mandatory
      loop
        if rec.scope = 'shared' then
          perform public.fn_inquiry_answer_set(p_group, rec.field_id, 'fixture-value',
                    'customer_confirmed', 'customer', p_actor);
        else
          perform public.fn_inquiry_answer_set(p_group, rec.field_id, 'fixture-value',
                    'customer_confirmed', 'customer', p_actor, null, array[p_ws]);
        end if;
        n := n + 1;
      end loop;
      insert into public.inquiry_gate (group_id, workstream_id, gate_key, passed, asserted_by)
      select p_group, p_ws, gr.gate_key, true, p_actor
        from public.inquiry_gate_required gr where gr.level = 'workstream'
      on conflict do nothing;
      return n;
    end $inner$
  $q8$;

  -- 6. checks
  select count(*) into v_b_rel_after from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('brand_acceptance_policy_value','field_question_variant',
     'subcategory_trade_contribution','field_definition_reference','mep_trade_pattern',
     'inquiry_trade_candidate','inquiry_trade_candidate_evidence','inquiry_trade_clarification',
     'mep_evidence_weight','p2c1_lang_case','p2c1_scope_case',
     'v_workstream_brand_policy','v_inquiry_trade_status');
  select count(*) into v_b_fn_after from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('fn_trade_identify','fn_trade_confirm','fn_trade_reject',
     'fn_trade_remove','fn_text_matches_pattern','fn_term_matches','fn_norm_text','fn_mep_full_scope',
     'fn_gate_state_satisfies','fn_field_value_allowed','fn_group_dispatch_report',
     'trg_inquiry_gate_state_sync','trg_inquiry_answer_value_domain','trg_mep_pattern_norm',
     'fn_p2c1_stage_b_selftest','fn_p2c1_stage_b_regression','fn_p2c1_lang_parity_suite',
     'fn_p2c1_run_lang_case','fn_p2c1_scope_rule_tests');
  select count(*) into v_a_rel from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('inquiry_answer','inquiry_workstream','field_definition',
     'field_definition_source','inquiry_answer_conflict','inquiry_state_audit','mep_subcategory_review',
     'v_workstream_answer','v_workstream_dispatch','v_group_dispatch');
  select count(*) into v_brand_defs from public.field_definition where field_id like '%.brand_policy';
  select count(*) into v_brand_src from public.field_definition_source where source_field_key = 'brand_policy';

  if v_b_rel_after <> 0 then raise exception 'ROLLBACK ABORTED: % Stage B relations survived', v_b_rel_after; end if;
  if v_b_fn_after <> 0 then raise exception 'ROLLBACK ABORTED: % Stage B functions survived', v_b_fn_after; end if;
  if v_a_rel <> 10 then raise exception 'ROLLBACK ABORTED: expected 10 Stage A objects, found %', v_a_rel; end if;
  if v_brand_defs = 0 then raise exception 'ROLLBACK ABORTED: *.brand_policy identities were not restored'; end if;
  if v_brand_src = 0 then raise exception 'ROLLBACK ABORTED: brand_policy source mappings were not restored'; end if;

  -- 7. the real check: does Stage A still work?
  select count(*) filter (where not passed) into v_fail from public.fn_p2c1_stage_a_selftest();
  select count(*) filter (where passed)||'/'||count(*) into v_selftest from public.fn_p2c1_stage_a_selftest();
  if v_fail > 0 then
    raise exception 'ROLLBACK ABORTED: Stage A self-test is % after rollback', v_selftest;
  end if;

  v_report := jsonb_build_object(
    'ok', true, 'mode', p_mode, 'actor', p_actor,
    'stage_b_relations', v_b_rel_before || ' -> ' || v_b_rel_after,
    'stage_b_functions', v_b_fn_before || ' -> ' || v_b_fn_after,
    'stage_a_objects_present', v_a_rel || '/10',
    'brand_policy_identities_restored', v_brand_defs,
    'brand_policy_source_mappings_restored', v_brand_src,
    'stage_a_selftest', v_selftest);

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (null, 'p2c1_stage_b_rollback_' || p_mode, v_report, p_actor);

  if p_mode = 'rehearse' then
    raise exception 'REHEARSAL COMPLETE (nothing committed): %', v_report::text;
  end if;

  return v_report;
end $fn$;

comment on function public.fn_p2c1_rollback_stage_b(text, text) is
  'The single entry point for removing Stage B. One transaction: drop Stage B, restore the Stage A objects Stage B modified, verify object counts, run the Stage A self-test, abort on any failure. Mode rehearse always aborts and reports; mode commit performs it. No separate manual sequence of migration files.';

revoke all on function public.fn_p2c1_rollback_stage_b(text, text) from public, anon, authenticated;
