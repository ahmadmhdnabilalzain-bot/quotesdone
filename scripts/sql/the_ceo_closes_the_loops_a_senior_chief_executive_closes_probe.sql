-- PROBE for the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql (ceo, ledger 1003 stage 2). Never applied: it
-- always raises CHK<<...>>, so every row the eight duties write is rolled back. Run after the file is applied (or
-- concatenated after it, in one transaction): node scripts/qsql.mjs <file + this probe>.
-- It runs each duty against production as it stands, reads what each one wrote, and asserts that none of them
-- reached the founder: notifications and handoffs to the founder are counted before and after.
do $probe$
declare n0 bigint := (select count(*) from public.notifications); h0 bigint := (select count(*) from public.agent_actions where kind = 'handoff');
  d0 bigint := (select coalesce(max(id), 0) from public.ceo_directive); r jsonb := '{}'::jsonb; v_fail text := '';
begin
  r := r || jsonb_build_object('C03', public.fn_ceo_directive_review());
  r := r || jsonb_build_object('C04', public.fn_ceo_month_close());
  r := r || jsonb_build_object('C05', public.fn_ceo_forecast_counter_action());
  r := r || jsonb_build_object('C06', public.fn_ceo_improvement_burn_down());
  r := r || jsonb_build_object('C08', public.fn_ceo_pricing_evidence());
  r := r || jsonb_build_object('C09', public.fn_ceo_experiment_month());
  r := r || jsonb_build_object('C13', public.fn_ceo_refund_decision_metric());
  r := r || jsonb_build_object('C14', public.fn_ceo_register_review());
  r := r || jsonb_build_object('directives_written', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from
          (select source_kind || '>' || seat k, count(*) n from public.ceo_directive where id > d0 group by 1) x),
        'missed_reviewed', (select count(*) from public.ceo_directive where status = 'missed' and evidence ? 'review'),
        'month_close_rows', (select count(*) from public.ceo_month_close),
        'month_report_internal', (select count(*) from public.ceo_month_report where handoff_id is null),
        'pricing_rows', (select count(*) from public.ceo_pricing_evidence),
        'refund_rows', (select count(*) from public.ceo_refund_decision_metric),
        'experiments_running', (select count(*) from public.ceo_experiment where status = 'running'),
        'founder_notifications_added', (select count(*) from public.notifications) - n0,
        'handoffs_added', (select count(*) from public.agent_actions where kind = 'handoff') - h0,
        'handoffs_to_founder_added', (select count(*) from public.agent_actions where kind = 'handoff' and created_at = now() and detail->>'recipient_role' = 'founder'));
  if (r->>'founder_notifications_added')::int <> 0 or (r->>'handoffs_to_founder_added')::int <> 0 then v_fail := v_fail || 'reached the founder; '; end if;
  if (r->>'month_close_rows')::int = 0 then v_fail := v_fail || 'no seat month closed; '; end if;
  if (r->>'pricing_rows')::int = 0 or (r->>'refund_rows')::int = 0 then v_fail := v_fail || 'a metric row is missing; '; end if;
  if (r->>'experiments_running')::int = 0 then v_fail := v_fail || 'no experiment running; '; end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || r::text;
end $probe$;
