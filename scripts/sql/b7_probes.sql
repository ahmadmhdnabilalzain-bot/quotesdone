-- Stage B.7 post-fix probes: activation, drift, fixtures, evidence.
select 'ROUTES ------------------------------------------------' as line
union all select 'mep_trade_route rows: ' || count(*)::text from public.mep_trade_route
union all select 'kb_operational_route rows: ' || count(*)::text from public.kb_operational_route
union all select 'live inquiry_workstream rows: ' || count(*)::text from public.inquiry_workstream
union all select 'live inquiry_workstream_group rows: ' || count(*)::text from public.inquiry_workstream_group
union all select 'live inquiry_scope_disposition rows: ' || count(*)::text from public.inquiry_scope_disposition
union all select 'live inquiry_trade_candidate rows: ' || count(*)::text from public.inquiry_trade_candidate
union all select 'live inquiry_trade_clarification rows: ' || count(*)::text from public.inquiry_trade_clarification

union all select 'EXPECTATION DRIFT -------------------------------------'
union all select 'v_scenario_expectation_drift rows: ' || count(*)::text from public.v_scenario_expectation_drift
union all select 'scenario_expectation_change rows: ' || count(*)::text from public.scenario_expectation_change
union all select 'holdout seal checksum: ' || (public.fn_p2c1_holdout_verify_seal() ->> 'current_checksum')
union all select 'holdout seal intact: ' || (public.fn_p2c1_holdout_verify_seal() ->> 'intact')
union all select 'holdout cases: ' || count(*)::text from public.p2c1_holdout_case
union all select 'holdout result_of_record rows: ' || count(*)::text from public.p2c1_holdout_result_of_record
union all select 'disposition cases: ' || count(*)::text from public.p2c1_disposition_case
union all select 'lang cases: ' || count(*)::text from public.p2c1_lang_case
union all select 'scope negative cases: ' || count(*)::text from public.p2c1_scope_case
union all select 'B.7 cases: ' || count(*)::text from public.p2c1_b7_case

union all select 'FIXTURES ----------------------------------------------'
union all select 'groups with no matching inquiry_intake: ' || count(*)::text
  from public.inquiry_workstream_group g
 where not exists (select 1 from public.inquiry_intake i where i.id::text = g.inquiry_id::text)
union all select 'inquiry_state_audit rows: ' || count(*)::text from public.inquiry_state_audit

union all select 'VOCABULARY --------------------------------------------'
union all select 'scope_marker by type: ' || (select string_agg(marker_type || '=' || n::text, ', ' order by marker_type)
                   from (select marker_type, count(*) n from public.scope_marker group by marker_type) q)
union all select 'party markers by class: ' || (select string_agg(party_class || '=' || n::text, ', ' order by party_class)
                   from (select party_class, count(*) n from public.scope_marker where marker_type='party' group by party_class) q)
union all select 'party_dependent disposition markers: ' || count(*)::text
  from public.scope_marker where resolution = 'party_dependent'
union all select 'mep_trade_pattern by kind: ' || (select string_agg(kind || '=' || n::text, ', ' order by kind)
                   from (select kind, count(*) n from public.mep_trade_pattern group by kind) q)
union all select 'evidence weights: ' || (select string_agg(weight_key || '=' || evidence_score::text, ', ' order by weight_key)
                   from public.mep_evidence_weight)

union all select 'ROLLBACK INSTRUMENTS ----------------------------------'
union all select 'rollback functions present: ' || (select string_agg(p.proname, ', ' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in
        ('fn_p2c1_rollback_stage_b','fn_p2c1_rollback_stage_b6','fn_p2c1_rollback_stage_b7'));
