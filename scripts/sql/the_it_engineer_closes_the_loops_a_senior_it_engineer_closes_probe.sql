-- PROBE for the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql (it_engineer, ledger 1003 stage 2). Never
-- applied: it always raises CHK<<...>>, so every row the five duties write is rolled back. Run after the file is applied
-- (or concatenated after it, in one transaction): node scripts/qsql.mjs <file + this probe>.
-- It runs each duty against production as it stands, reads what each wrote, and asserts that none reached the founder.
do $probe$
declare h0 bigint := (select coalesce(max(id), 0) from public.agent_actions);
  r jsonb := '{}'::jsonb; w1 jsonb; w2 jsonb; v_fail text := '';
begin
  r := r || jsonb_build_object('C02', public.fn_it_engineer_latency_closure());
  r := r || jsonb_build_object('C06', public.fn_it_engineer_model_spend_closure());
  perform public.fn_it_duty_ran('otp', '{"probe": true}'::jsonb);
  r := r || jsonb_build_object('C13', public.fn_it_engineer_perimeter_freshness(),
          'C13_stamped', (select count(*) from public.it_duty_schedule where last_ok_at is not null),
          'C13_otp_stamped_now', (select last_ok_at = now() from public.it_duty_schedule where duty = 'otp'));
  w1 := public.fn_it_workflow_audit_ingest('{"files": 1, "violations": [{"file": "probe.yml", "rule": "unpinned_action", "message": "uses: actions/checkout@v7 is not pinned to a commit SHA"}]}'::jsonb);
  w2 := public.fn_it_workflow_audit_ingest('{"files": 1, "violations": []}'::jsonb);
  r := r || jsonb_build_object('C15_open_then_close', jsonb_build_array(w1, w2), 'C15', public.fn_it_engineer_advisory_triage());
  r := r || jsonb_build_object('C16', public.fn_it_engineer_load_test());
  r := r || jsonb_build_object('C16_rows', (select count(*) from public.it_load_test_run where run_at = now()));
  r := r || jsonb_build_object(
        'closure_rows', (select jsonb_object_agg(duty, n) from (select duty, count(*) n from public.it_finding_closure group by 1) x),
        -- only this transaction's own rows (created_at = now()): the company keeps sending while the probe runs
        'notifications_added', (select coalesce(jsonb_object_agg(coalesce(to_role, '?') || '/' || coalesce(kind, type, '?'), n), '{}'::jsonb) from (select to_role, kind, type, count(*) n from public.notifications where created_at = now() group by 1, 2, 3) x),
        'founder_notifications_added', (select count(*) from public.notifications where created_at = now() and to_role = 'founder'),
        'handoffs_added', (select jsonb_object_agg(agent, n) from (select agent, count(*) n from public.agent_actions where id > h0 and kind = 'handoff' group by 1) x),
        'handoffs_to_founder_added', (select count(*) from public.agent_actions where id > h0 and kind = 'handoff' and (agent = 'founder' or detail->>'recipient_role' = 'founder')));
  if (r->>'founder_notifications_added')::int <> 0 or (r->>'handoffs_to_founder_added')::int <> 0 then v_fail := v_fail || 'reached the founder; '; end if;
  if coalesce((r->'C02'->>'open')::int, 0) = 0 then v_fail := v_fail || 'no latency finding under closure; '; end if;
  if coalesce((r->'C06'->'model_spend'->>'open')::int, 0) = 0 then v_fail := v_fail || 'no spend finding under closure; '; end if;
  if not coalesce((r->>'C13_otp_stamped_now')::boolean, false) then v_fail := v_fail || 'fn_it_duty_ran did not stamp the schedule; '; end if;
  if (w1->>'failing')::int <> 1 or (w2->>'closed')::int <> 1 then v_fail := v_fail || 'workflow finding did not open and close; '; end if;
  if (r->>'C16_rows')::int = 0 then v_fail := v_fail || 'load test recorded no step; '; end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || r::text;
end $probe$;
