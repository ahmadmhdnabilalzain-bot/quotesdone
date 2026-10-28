-- THE INVITATION BATCH RUNS ON ITS OWN CLOCK, AND THE GUARD TAKES THE LINK-LESS COPY.
-- Assigned: sales_engineer (supplier invitations). 28 Oct 2026.
--
-- MEASURED 28 Oct 2026, the first open day after the resume at 03:51Z (ledger 1377, warm-up plan "To resume"):
-- 0 supplier_invite rows by 06:13Z. Two defects, each enough on its own to stop the batch; both were hidden while
-- invite_enabled was false, because the held path never reaches them.
--
--   1. THE TICK RAN UNDER AN 8-SECOND LIMIT. fn_sales_engineer_supplier_outreach_tick was called only by
--      resilience_ping's step `supplierOutreach`, through PostgREST, where the authenticator role carries
--      statement_timeout=8s. The held path fits (step ewma 5.8 s). An open day does not: in a rolled-back replay on
--      28 Oct the eligible-pool count took 5.8 s and fn_supplier_invite_candidates(20, {google}) 5.5 s, and the whole
--      enqueue_supplier_invites(null) 13.4 s. From 05:16Z (09:16 Dubai, the first beat past the tick's 09:00 gate)
--      every beat was cancelled — finding duty:heartbeat:supplierOutreach, "canceling statement due to statement
--      timeout", seen 20 times by 06:16Z — and the cancel rolled back the agent_runs row too, so no Dubai day was
--      ever marked done and the same failure repeated every 30 minutes for the rest of the day.
--      FIX: the tick becomes the seat duty `sales_engineer.supplier_outreach` with its OWN pg_cron job
--      (fn_seat_duty_isolate: `set statement_timeout = '60s'`), the established shape for a duty too slow for the
--      shared tick. The resilience_step row goes, so resilience_ping no longer plans the step, and the step is
--      removed from STEP_RUN in the same PR. Nothing about WHAT the tick does changes: its body below is the
--      canonical one from the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql, verbatim,
--      redefined here only because a seat-duty file must define the routine it registers. It still gates itself
--      to once a Dubai day from 09:00 and holds on every switch, brake, cap, holiday, weekend, window and the
--      per-provider GlockApps gate exactly as before.
--
--   2. THE GUARD STILL DEMANDED A PORTAL LINK. a07_notifications_supplier_invite_is_whole refused any
--      supplier_invite whose body had no `/(en|ar)/portal?t=<uuid>`. #1614 (27 Oct,
--      the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql) made the
--      approved copy link-less on the founder's instruction ("safer to not send links") and changed the candidate
--      picker, but not this trigger. Replayed 28 Oct with a 60 s limit: SUPPLIER_INVITE_REFUSED "the invitation to
--      info@alqama.ae carries no portal link" — the whole batch aborts on its first row.
--      FIX: the guard refuses an EMPTY body and a body still carrying an unfilled {{placeholder}} instead of a body
--      without a link. Every other refusal (Arabic without Arabic, no lead, an ineligible or mismatched lead) is
--      unchanged. CREATE OR REPLACE keeps the routine's closed ACL; the revoke below restates it for the check.
--
-- Replayed together in one rolled-back transaction on 28 Oct 2026 ~06:20Z: 20 queued of 20 planned (pool 17,401,
-- cap 20), every recipient on a Google-hosted domain (the only class the 27 Oct 22:50 verdict opens), not_before
-- spread 06:20Z..12:40Z (the window to 17:00 Dubai), 13.4 s, app_secrets byte-identical before and after.
-- Probe: probe_the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql.
-- Prevented by: scripts/checks/the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.test.mjs
-- Nothing here writes app_secrets or changes a campaign switch, cap, brake, gate or window.

-- 2. the guard
create or replace function public.fn_notifications_supplier_invite_is_whole()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare l public.leads;
begin
  if coalesce(new.type, '') <> 'supplier_invite' then return new; end if;
  -- 28 Oct 2026: the approved invitation carries no link (#1614). An empty body, or one with a placeholder the
  -- composer never filled, is refused instead.
  if btrim(coalesce(new.body, '')) = '' then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % has no body', new.to_email using errcode = 'check_violation';
  end if;
  if position('{{' in coalesce(new.body, '')) > 0 then
    raise exception 'SUPPLIER_INVITE_REFUSED: the invitation to % still carries an unfilled placeholder', new.to_email using errcode = 'check_violation';
  end if;
  if coalesce(new.lang, 'en') = 'ar' and coalesce(new.body, '') !~ '[؀-ۿ]' then
    raise exception 'SUPPLIER_INVITE_REFUSED: an Arabic invitation to % has no Arabic in it', new.to_email using errcode = 'check_violation';
  end if;
  if public.fn_is_demo_email(new.to_email) then return new; end if;   -- the test path
  if new.lead_id is null then
    raise exception 'SUPPLIER_INVITE_REFUSED: an invitation to % names no lead', new.to_email using errcode = 'check_violation';
  end if;
  select * into l from public.leads where id = new.lead_id;
  if not found or lower(btrim(coalesce(l.email, ''))) <> lower(btrim(coalesce(new.to_email, '')))
     or not public.fn_supplier_invite_eligible(l) then
    raise exception 'SUPPLIER_INVITE_REFUSED: lead #% is not eligible for an invitation (demo, banned, screened, closed, already invited, unsendable, or the address is not the lead''s)', new.lead_id
      using errcode = 'check_violation';
  end if;
  return new;
end
$function$;
revoke execute on function public.fn_notifications_supplier_invite_is_whole() from public, anon, authenticated;

-- 1. the tick, unchanged (see the header), and its own clock
create or replace function public.fn_sales_engineer_supplier_outreach_tick(p_force boolean DEFAULT false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
begin
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date)
    into v_daily_done, v_batch_done;
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if v_daily_done and v_batch_done then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. THE BATCH, behind the PLACEMENT GATE (24 Sep 2026, it_engineer). On an open day it goes only after that
  --    morning's seed landed in the Inbox of both seed mailboxes; while the check can still finish it waits (the
  --    next beat asks again); any other answer holds it (fail closed). enqueue_supplier_invites asks the same gate.
  if p_force or not v_batch_done then
    v_batch_why := v_why;
    if v_why is null then
      -- 27 Oct 2026: the GlockApps verdict, per mailbox class. The batch is held only when no class passes;
      -- enqueue_supplier_invites invites the passing classes and skips the rest. It never answers 'wait'.
      if cardinality(public.fn_invite_placement_open_providers(v_now_dxb::date)) = 0 then
        v_batch_why := 'the GlockApps inbox placement verdict cleared no mailbox class ('
                       || (public.fn_invite_placement_class_verdicts(now()) ->> 'strict') || ')';
      end if;
      v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
    end if;
    if not v_batch_wait then
      -- THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of bounces and
      -- complaints. Open days only: a held day sends nothing, so it must not move the cap.
      if v_batch_why is null then v_cap := public.fn_invite_ramp(); end if;
      -- enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
      v_invited := public.enqueue_supplier_invites(null);
    end if;
  end if;

  -- A later beat of the same day: the daily work is done, only the batch was owed.
  if v_daily_done and not p_force then
    if v_batch_wait then
      return jsonb_build_object('due', false, 'reason', 'the batch waits for the morning inbox placement check');
    end if;
    v_out := jsonb_build_object('job', 'supplier_outreach_batch', 'dubai_day', v_now_dxb::date, 'held', v_batch_why is not null,
      'held_because', v_batch_why, 'placement_gate', v_gate, 'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap));
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('sales_engineer', 'ok', now(), now(), v_out,
            case when v_batch_why is not null
                 then 'Supplier invitation batch HELD (' || v_batch_why || '): ' || coalesce(v_invited, 0) || ' queued.'
                 else 'Supplier invitation batch: ' || coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || '.' end);
    return v_out;
  end if;

  -- 2. Reminders: always counted; written only on an open weekday (the campaign gates, not the placement gate).
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'placement_gate', v_gate, 'batch_waiting', v_batch_wait, 'batch_held_because', v_batch_why,
    'invites', jsonb_build_object('queued', coalesce(v_invited, 0), 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || coalesce(v_invited, 0) || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$function$;
revoke execute on function public.fn_sales_engineer_supplier_outreach_tick(boolean) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, own_job)
values ('sales_engineer.supplier_outreach', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_supplier_outreach_tick',
        'The daily supplier invitation batch, the registration reminders and the 24-hour clock on a submitted registration. '
        || 'The routine gates itself to once a Dubai day from 09:00 and holds on every campaign switch, brake, cap, holiday, '
        || 'weekend, window and the per-provider GlockApps gate. Its own job (60 s): an open day measured 13.4 s, past the 8 s an RPC gets.',
        'scripts/sql/the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql', false)
on conflict (duty) do nothing;

select public.fn_seat_duty_isolate('sales_engineer.supplier_outreach')
 where not exists (select 1 from cron.job where jobname = 'seat_duty:sales_engineer.supplier_outreach');

delete from public.resilience_step where step = 'supplierOutreach';

-- VERDICT (structural; the behaviour is the probe file's, rolled back). Nothing is written here.
select case
  when not exists (select 1 from cron.job where jobname = 'seat_duty:sales_engineer.supplier_outreach' and active
                     and command like '%statement_timeout = ''60s''%' and command like '%sales_engineer.supplier_outreach%')
    then 'PROBE FAILED: no active 60 s job runs sales_engineer.supplier_outreach'
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.supplier_outreach' and enabled and own_job
                     and routine = 'fn_sales_engineer_supplier_outreach_tick')
    then 'PROBE FAILED: the seat duty is missing, disabled or not on its own job'
  when exists (select 1 from public.resilience_step where step = 'supplierOutreach')
    then 'PROBE FAILED: resilience_ping still plans supplierOutreach under the 8 s RPC limit'
  when pg_get_functiondef('public.fn_notifications_supplier_invite_is_whole()'::regprocedure) like '%portal[?]t=%'
    then 'PROBE FAILED: the invitation guard still demands a portal link'
  else 'PROBE OK' end as verdict;
