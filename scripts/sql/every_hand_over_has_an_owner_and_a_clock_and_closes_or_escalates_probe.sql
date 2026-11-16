-- every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates_probe.sql (ceo, L4_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs). It always aborts
-- (raise 'CHK<<...>>'), so nothing it writes survives. The CEO model's answers are stubs handed to the apply routine; nothing is
-- sent to anyone, and every party is a ZZ DEMO probe row on reserved example data.
-- What it proves:
--   1. a hand-over whose kind has no handler is closed 'no handler: ...', and the sweep closes NO row whose handler lives:
--      every live-handler row it closed is a test row or a later duplicate whose first copy is still open;
--   2. every open row carries an owner seat and a due time; an unregistered non-handoff kind is never closed;
--   3. a late row is escalated ONCE, to the CEO, never the founder, and a second tick escalates it again never;
--   4. the CEO's escalated rows are filed on their own room even when the shared room is spent, and each choice CLOSES the row:
--      close, chase (a ceo.order carries the work), answer; an answer that is not offered closes nothing;
--   5. a directive missed after its re-issue becomes one CEO case (no ceo_task, no automatic re-issue) and the CEO's 'reissue'
--      issues it once more; a check that errors issues no directive; the seat_audit check counts only what the seat owes.
do $probe$
declare
  v_live bigint; v_dead bigint; v_test bigint; v_dup1 bigint; v_dup2 bigint; v_unreg bigint; v_answered bigint; v_ceo_own bigint;
  v_late bigint; v_hq bigint; r jsonb; n int; v_q bigint; v_d bigint; v_d2 bigint; v_case bigint; v_status text; v_order bigint;
  v_fixed timestamptz := now();
begin
  -- a clean start: the local cluster's open rows would only blur the counts
  update public.agent_actions set status = 'done', evidence = coalesce(evidence, '{}'::jsonb) || '{"not_cited":{"reason":"probe clean start","by":"probe"}}'
   where status in ('pending', 'open') and kind <> 'handoff';
  delete from public.agent_actions where status in ('pending', 'open') and kind = 'handoff';
  -- a conversation whose handler was retired: the probe points event.act at a routine that does not exist (rolled back)
  update public.seat_handoff_kind set handler = 'fn_probe_handler_that_does_not_exist'
   where type = 'event.act' and from_seat = 'sales_engineer' and to_seat = 'sales_engineer';

  -- 1. the rows. A dead letter, a live late row answered by its receiver (the sender owes the close), a test row, two copies of
  --    one subject, a row of an unregistered kind, the CEO's own late row, a parked question of a seat
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'probe dead letter',
          jsonb_build_object('type', 'event.act', 'from', 'sales_engineer', 'to', 'sales_engineer', 'subject_table', 'probe', 'subject_id', 'dead:1'), 'probe', 'event.act:dead:1', now() - interval '3 days')
  returning id into v_dead;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'probe live answered',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'sales_engineer', 'subject_table', 'probe', 'subject_id', 'live:1',
                             'replied_at', now() - interval '2 days', 'awaiting', 'it_engineer re-verification'), 'probe', 'it.finding:live:1', now() - interval '2 days')
  returning id into v_live;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'ZZ DEMO probe test row',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'sales_engineer', 'subject_table', 'probe', 'subject_id', 'test:1', 'demo', true), 'probe', 'it.finding:test:1', now() - interval '2 days')
  returning id into v_test;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'probe copy 1',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'sales_engineer', 'subject_table', 'probe', 'subject_id', 'dup:1'), 'probe', 'it.finding:dup:1', now() - interval '1 hour')
  returning id into v_dup1;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'low', 'probe copy 2',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'sales_engineer', 'subject_table', 'probe', 'subject_id', 'dup:1'), 'probe', 'it.finding:dup:1:second-filer', now() - interval '30 minutes')
  returning id into v_dup2;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'probe_new_kind', 'pending', 'low', 'probe work of a kind nobody registered', '{"waiting_for":"someone"}'::jsonb, null, null, now() - interval '2 days')
  returning id into v_unreg;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('ceo', 'held_question', 'pending', 'low', 'probe: the CEO''s own parked question',
          jsonb_build_object('owner_seat', 'ceo', 'surface', 'ceo.knowledge_refresh', 'question', 'ZZ DEMO probe?', 'needs_founder', true), null, null, now() - interval '20 days')
  returning id into v_ceo_own;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('accountant', 'held_question', 'pending', 'low', 'probe: a seat''s parked question, recent',
          jsonb_build_object('owner_seat', 'accountant', 'surface', 'accountant.document_kind', 'question', 'ZZ DEMO probe?'), null, null, now() - interval '2 days')
  returning id into v_hq;

  -- 2. the clock
  r := public.fn_handover_clock_tick();
  if (select status from public.agent_actions where id = v_dead) <> 'dismissed'
     or (select evidence->>'verdict' from public.agent_actions where id = v_dead) not like 'no handler: fn_probe_handler_that_does_not_exist does not exist%' then
    raise exception 'CHK<<PROBE FAILED: the dead letter was not closed with its reason: %>>', (select evidence->>'verdict' from public.agent_actions where id = v_dead); end if;
  if (select status from public.agent_actions where id = v_test) <> 'dismissed'
     or (select evidence->>'verdict' from public.agent_actions where id = v_test) not like 'test row: %' then
    raise exception 'CHK<<PROBE FAILED: the test row was not closed as one>>'; end if;
  if (select status from public.agent_actions where id = v_dup2) <> 'dismissed' or (select status from public.agent_actions where id = v_dup1) <> 'pending'
     or (select evidence->>'verdict' from public.agent_actions where id = v_dup2) not like 'duplicate of #' || v_dup1 || '%' then
    raise exception 'CHK<<PROBE FAILED: the later copy was not closed as a duplicate of the first, or the first did not stay open>>'; end if;
  -- NO LIVE-HANDLER ROW WAS CLOSED except as a test row or a duplicate whose first copy is open
  select count(*) into n from public.agent_actions a
   where a.evidence ? 'closed_by_the_clock'
     and (a.kind <> 'handoff' or exists (select 1 from public.seat_handoff_kind k join pg_catalog.pg_proc p on p.proname = k.handler and p.pronamespace = 'public'::regnamespace
                                          where k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent))
     and not (a.evidence->>'verdict' like 'test row: %')
     and not (a.evidence->>'verdict' like 'duplicate of #%'
              and exists (select 1 from public.agent_actions x where x.id = (a.evidence->'closed_by_the_clock'->>'kept_open')::bigint and x.status = 'pending'));
  if n <> 0 then raise exception 'CHK<<PROBE FAILED: % live-handler rows were closed by the sweep>>', n; end if;
  if (select status from public.agent_actions where id = v_unreg) <> 'pending' or (select status from public.agent_actions where id = v_live) <> 'pending'
     or (select status from public.agent_actions where id = v_hq) <> 'pending' then
    raise exception 'CHK<<PROBE FAILED: a row with work still to do was closed>>'; end if;
  -- every open row carries an owner and a due time
  if exists (select 1 from public.agent_actions where status = 'pending' and not (detail->'clock' ?& array['owner_seat', 'due_at'])) then
    raise exception 'CHK<<PROBE FAILED: an open row carries no owner or due time>>'; end if;
  if (select detail->'clock'->>'owner_seat' from public.agent_actions where id = v_live) <> 'it_engineer' then
    raise exception 'CHK<<PROBE FAILED: an answered hand-over is not owed by its sender>>'; end if;

  -- 3. escalated once, to the CEO, never the founder; the recent parked question is not late yet
  if (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_live) is distinct from 'ceo'
     or (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_unreg) is distinct from 'ceo'
     or (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_ceo_own) is distinct from 'ceo' then
    raise exception 'CHK<<PROBE FAILED: a late row was not escalated to the CEO>>'; end if;
  if (select detail ? 'silence' from public.agent_actions where id = v_hq) then
    raise exception 'CHK<<PROBE FAILED: a parked question inside its 14 days was escalated>>'; end if;
  if exists (select 1 from public.agent_actions where detail->'silence'->>'escalated_to' ~* 'founder') then
    raise exception 'CHK<<PROBE FAILED: something was escalated to the founder>>'; end if;
  r := public.fn_handover_clock_tick();
  if jsonb_array_length(r->'escalated'->'ids') <> 0 then
    raise exception 'CHK<<PROBE FAILED: a second tick escalated again: %>>', r->'escalated'->'ids'; end if;

  -- 4. the CEO's room for late rows is its own: spend the shared room first
  insert into public.decision_policy (key, value) values ('ceo_daily_judgements', '{"items": 0}'::jsonb)
  on conflict (key) do update set value = excluded.value;
  r := public.fn_ceo_files_judgements();
  if coalesce((r->>'filed_overdue')::int, 0) < 3 then
    raise exception 'CHK<<PROBE FAILED: the late rows were not filed on their own room: %>>', r; end if;
  -- 4a. an answer that is not offered closes nothing
  select id into v_q from public.reasoning_held_question where surface = 'ceo.overdue_handoff' and (subject->>'handoff_id')::bigint = v_live;
  if public.fn_reason_apply_ceo__overdue_handoff(v_q, '{"answer":"wait for it, it will come later","decision":{"choice":"wait"}}'::jsonb) is not null
     or (select status from public.agent_actions where id = v_live) <> 'pending' then
    raise exception 'CHK<<PROBE FAILED: an answer that was not offered decided something>>'; end if;
  -- 4b. chase: the late row closes and an order carries the work
  r := public.fn_reason_apply_ceo__overdue_handoff(v_q, '{"answer":"The IT engineer re-checks the fault and closes it within two days.","decision":{"choice":"chase"},"model":"stub"}'::jsonb);
  v_order := (r->>'order_handoff')::bigint;
  if (select status from public.agent_actions where id = v_live) not in ('done', 'dismissed') or v_order is null
     or (select detail->>'type' || '>' || agent from public.agent_actions where id = v_order) <> 'ceo.order>it_engineer' then
    raise exception 'CHK<<PROBE FAILED: chase did not close the late row and order its owner: %>>', r; end if;
  if (select status from public.agent_actions where id = v_live) = 'done' then
    raise exception 'CHK<<PROBE FAILED: a hand-over its sender closes was shown as finished by the CEO''s decision>>'; end if;
  -- 4c. close (an unregistered kind) and answer (the CEO's own)
  select id into v_q from public.reasoning_held_question where surface = 'ceo.overdue_handoff' and (subject->>'handoff_id')::bigint = v_unreg;
  r := public.fn_reason_apply_ceo__overdue_handoff(v_q, '{"answer":"Nothing is owed: this was a one-off check that is no longer needed.","decision":{"choice":"close"},"model":"stub"}'::jsonb);
  select id into v_q from public.reasoning_held_question where surface = 'ceo.overdue_handoff' and (subject->>'handoff_id')::bigint = v_ceo_own;
  r := public.fn_reason_apply_ceo__overdue_handoff(v_q, '{"answer":"The entry stays as written; its source has not changed.","decision":{"choice":"answer"},"model":"stub"}'::jsonb);
  if exists (select 1 from public.agent_actions where id in (v_unreg, v_ceo_own) and status = 'pending')
     or exists (select 1 from public.agent_actions where id in (v_live, v_unreg, v_ceo_own) and not (detail->'silence' ? 'ceo_decision')) then
    raise exception 'CHK<<PROBE FAILED: the CEO''s decision did not close every escalated row>>'; end if;

  -- 5. directives. A miss after the re-issue becomes one CEO case, and no ceo_task
  insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, issued_at, status)
  values ('marketing', 'improvement_backlog', 'probe:1', 'ZZ DEMO probe: do the thing', 'the probe thing is done.', 'false', now() - interval '1 day', null, now() - interval '9 days', 'escalated')
  returning id into v_d;
  insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, issued_at)
  values ('marketing', 'improvement_backlog', 'probe:1', 'RE-ISSUED: ZZ DEMO probe: do the thing', 'the probe thing is done.', 'false', now() - interval '1 hour', v_d, now() - interval '8 days')
  returning id into v_d2;
  select count(*) into n from public.ceo_task;
  r := public.fn_ceo_directive_run(now());
  if (select status from public.ceo_directive where id = v_d2) <> 'missed' then
    raise exception 'CHK<<PROBE FAILED: the re-issued directive did not close missed>>'; end if;
  if (select count(*) from public.ceo_task) <> n then raise exception 'CHK<<PROBE FAILED: a miss still opens a ceo_task>>'; end if;
  select id into v_case from public.agent_actions where kind = 'directive_missed' and target_id = v_d2::text and status = 'pending';
  if v_case is null then raise exception 'CHK<<PROBE FAILED: the miss is not a case in the CEO''s queue>>'; end if;
  r := public.fn_ceo_directive_review();
  if (select count(*) from public.ceo_directive where source_ref = 'probe:1') <> 2
     or (select count(*) from public.agent_actions where kind = 'directive_missed' and target_id = v_d2::text) <> 1 then
    raise exception 'CHK<<PROBE FAILED: the review re-issued the directive or filed a second case>>'; end if;
  -- the clock escalates it once its hour is up, and the CEO's 'reissue' issues it once more
  update public.agent_actions set created_at = now() - interval '2 hours' where id = v_case;
  r := public.fn_handover_clock_tick();
  r := public.fn_ceo_files_judgements();
  select id into v_q from public.reasoning_held_question where surface = 'ceo.overdue_handoff' and (subject->>'handoff_id')::bigint = v_case;
  if v_q is null then raise exception 'CHK<<PROBE FAILED: the directive case was not put to the CEO>>'; end if;
  r := public.fn_reason_apply_ceo__overdue_handoff(v_q, '{"answer":"Marketing does it again this week, starting with the oldest item.","decision":{"choice":"reissue"},"model":"stub"}'::jsonb);
  if (select count(*) from public.ceo_directive where source_ref = 'probe:1' and status = 'open' and escalated_from = v_d2) <> 1
     or (select status from public.agent_actions where id = v_case) = 'pending'
     or not (select evidence ? 'ceo_case' from public.ceo_directive where id = v_d2) then
    raise exception 'CHK<<PROBE FAILED: the CEO''s reissue did not issue the directive once more and close the case: %>>', r; end if;
  -- a check that cannot run issues nothing
  if public.fn_ceo_directive_issue('marketing', 'improvement_backlog', 'probe:2', 'ZZ DEMO probe', 'never', 'select from nowhere_at_all', now() + interval '1 day', '{}'::jsonb) is not null then
    raise exception 'CHK<<PROBE FAILED: a directive was issued with a check that cannot run>>'; end if;
  -- the seat_audit check: the receiver that answered is not late; the sender that has not closed is
  if exists (select 1 from public.v_handover_open h where h.owner_seat = 'sales_engineer' and h.id = v_dup1 and h.overdue) then
    raise exception 'CHK<<PROBE FAILED: an hour-old hand-over reads late>>'; end if;
  update public.agent_actions set created_at = now() - interval '2 days', detail = detail || jsonb_build_object('replied_at', now() - interval '2 days', 'awaiting', 'it_engineer re-verification')
   where id = v_dup1;
  if exists (select 1 from public.v_handover_open h where h.owner_seat = 'sales_engineer' and h.id = v_dup1)
     or not exists (select 1 from public.v_handover_open h where h.owner_seat = 'it_engineer' and h.id = v_dup1 and h.overdue) then
    raise exception 'CHK<<PROBE FAILED: an answered hand-over is still counted against its receiver>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
