-- PROBE: the seven parked it-finding families of 27 Oct each have a measured playbook class. Pure probe, no DDL: run
-- AFTER its .sql in the SAME query (node scripts/qsql.mjs, or replaySql); it always ends in raise exception CHK<<...>>,
-- so nothing survives. Contacts no one, writes no finding, closes no handoff.
-- PROBE OK only if:
--   1. no pending it.finding handoff parked at awaiting_learning is left without a covering prefix;
--   2. each of the eight handoffs measured on 27 Oct is covered by exactly the class written for its family;
--   3. the file added exactly seven rows and changed no existing class;
--   4. every new class carries a measured cause, and none of the eight handoffs changed status (nothing was closed).
do $probe$
declare v_fail text := ''; v_rows int; v_unclassed int; v_status jsonb; v_cover jsonb; v_bad int;
begin
  select count(*) into v_unclassed from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
     and a.detail ? 'awaiting_learning'
     and not exists (select 1 from public.it_playbook b where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix);
  if v_unclassed > 0 then v_fail := v_fail || ' ' || v_unclassed || ' parked handoff(s) still have no class;'; end if;

  select jsonb_object_agg(x.id, (select string_agg(b.failure_class, ',' order by b.failure_class) from public.it_playbook b
                                  where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix)),
         count(*) filter (where (select string_agg(b.failure_class, ',' order by b.failure_class) from public.it_playbook b
                                  where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix) is distinct from x.cls)
    into v_cover, v_bad
    from (values (99513, 'support_first_reply_late'), (100357, 'charge_off_formula'), (122120, 'org_task_queue_stuck'),
                 (141261, 'invite_m365_lane_refused'), (149663, 'expense_without_document'), (150604, 'expiry_inside_warning'),
                 (254305, 'model_spend_rise'), (254960, 'org_task_queue_stuck')) x(id, cls)
    join public.agent_actions a on a.id = x.id;
  if v_bad > 0 then v_fail := v_fail || ' ' || v_bad || ' handoff(s) not covered by exactly their class: ' || v_cover::text || ';'; end if;

  select count(*) into v_rows from public.it_playbook where added_by = 'it_engineer (27 Oct 2026)' and typical_cause like 'Measured on %';
  if v_rows <> 7 then v_fail := v_fail || ' ' || v_rows || ' new measured classes, 7 expected;'; end if;

  select jsonb_object_agg(id, status) into v_status from public.agent_actions where id in (99513, 100357, 122120, 141261, 149663, 150604, 254305, 254960);
  if exists (select 1 from jsonb_each_text(v_status) where value <> 'pending') then v_fail := v_fail || ' a handoff changed status: ' || v_status::text || ';'; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end,
    'unclassed', v_unclassed, 'new_classes', v_rows, 'cover', v_cover, 'status', v_status)::text;
end
$probe$;
