-- A RESUMED INVITATION DAY SENDS THE SAME DAY (2 Nov 2026, founder ledger 1486: "the email campaign should focus on addresses
-- that go to inbox. ignore microsoft. and resume invitations").
-- Seat: sales_engineer
--
-- MEASURED on production, 2 Nov 2026, 11:16-11:30 Dubai, after the founder's resume (invite_brake 4, resumed 11:07):
--  * 18 supplier_invite rows (ids 116650-116668), all Google-hosted MX, queued 28 Oct 06:45Z and moved to not_before 2 Nov
--    11:07 Dubai, were claimed by send_outbox at 11:16 and set to 'held' with NO last_error (agent_runs: "18 held (supplier
--    sending gate or stale)"). Cause: send_outbox's stale guard (email_stale_hours = 72) measured age from created_at, so a
--    row the brake had deferred was 120 h "old" though it had been due for 9 minutes. 'held' is terminal: nothing sends it.
--    The code fix is in supabase/functions/send_outbox (channels.ts hoursPastDue); this file releases what it held.
--  * The producer queued nothing new: the 09:00 beat ran the day's batch, the bounce brake fired inside it (2 of 30 over
--    3 days), and the tick then answered "already ran this Dubai day" for the rest of the day, resume or not.
--
-- WHAT THIS DOES
--  1. fn_sales_engineer_supplier_outreach_tick: a resume (invite_brake.resumed_at) later than the day's batch run reopens the
--     batch. While the 3-day bounce window the brake reads is still over its limit, the reopened batch WAITS (nothing is
--     queued, no row is logged) instead of firing the brake again on the bounces it already braked on; once the window is
--     under the limit, enqueue_supplier_invites runs with every one of its own gates (placement, cap, window, brake).
--     The brake itself is unchanged.
--  2. Releases the supplier invitations the old stale rule held: status 'held' with no last_error, never sent, the lead still
--     reachable, and its mailbox class open today (fn_invite_placement_open_providers). They are spread across the current
--     Dubai sending window, or the next weekday's when it has closed. The outbox's daily cap still governs how many leave.
-- Prevented by: supabase/functions/send_outbox/channels.test.ts (the stale rule) and
--   scripts/checks/a_resumed_invitation_day_sends_the_same_day.test.mjs (the tick reads the resume).
-- Probe: a_resumed_invitation_day_sends_the_same_day_probe.sql

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_outreach_tick(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
  v_resumed timestamptz; v_hs int; v_hb int; v_max numeric;
begin
  -- A RESUME REOPENS THE DAY'S BATCH (2 Nov 2026, ledger 1486). The latest brake resumed today (Dubai); a batch run before it
  -- does not count as today's batch.
  select max(b.resumed_at) into v_resumed from public.invite_brake b
   where b.resumed_at > now() - interval '1 day' and (b.resumed_at at time zone 'Asia/Dubai')::date = v_now_dxb::date;
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date
                    and (v_resumed is null or a.started_at > v_resumed))
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
    -- A batch a resume reopened waits while enqueue_supplier_invites' own 3-day brake would fire on it (the same reading,
    -- the same limit), so the resume is not undone by the bounces it was given on. The brake is not changed.
    if v_batch_why is null and v_resumed is not null and v_daily_done then
      v_max := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
      select h.sent, h.bounced into v_hs, v_hb from public.fn_invite_send_health(now() - interval '3 days') h;
      if (v_hs >= 15 and round(v_hb::numeric / greatest(v_hs, 1), 3) > v_max) or v_hb >= greatest(5, ceil(v_hs * v_max)::int) then
        v_batch_wait := true;
      end if;
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
      return jsonb_build_object('due', false, 'reason', 'a resume reopened today''s batch; it waits while the 3-day bounce window reads '
                                || v_hb || ' bounced of ' || v_hs || ' sent, over the limit');
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
    -- 2 Nov 2026 (ledger 1449): a pause holds cold mail. A supplier who already started still hears from us, on a weekday inside
    -- the sending window, unless a complaint stopped the campaign (fn_supplier_reminder_is_open).
    if v_why is not null and (v_weekend or not public.fn_supplier_reminder_is_open(r.stage)
         or extract(hour from v_now_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17)) then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
      if v_why is not null then
        update public.notifications set not_before = greatest(now(), (v_now_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai')
         where id = (s->'delivery'->>'notification_id')::bigint and type = 'supplier_registration_reminder';
      end if;
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
                    || ' reminder(s) due, ' || v_sent || ' written to suppliers who already started; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$function$;

-- 2. THE INVITATIONS THE OLD STALE RULE HELD GO BACK TO THE QUEUE, inside a sending window, only where they may still go.
do $release$
declare
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_sh int := coalesce((v_cfg->>'window_start_hour')::int, 9);
  v_eh int := coalesce((v_cfg->>'window_end_hour')::int, 17);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_start timestamptz; v_end timestamptz;
begin
  loop
    v_start := greatest(now(), (v_day + make_interval(hours => v_sh)) at time zone 'Asia/Dubai');
    v_end := (v_day + make_interval(hours => v_eh)) at time zone 'Asia/Dubai';
    exit when extract(isodow from v_day) not in (6, 7) and v_end >= v_start + interval '30 minutes';
    v_day := v_day + 1;
  end loop;
  with r as (
    select n.id, row_number() over (order by n.id) as rn, count(*) over () as c
      from public.notifications n
      join public.leads l on l.id = n.lead_id
      left join public.email_domain_mx m on m.domain = split_part(lower(btrim(n.to_email)), '@', 2)
     where n.type = 'supplier_invite' and n.status = 'held' and n.last_error is null
       and n.sent_at is null and n.provider_message_id is null
       and public.fn_supplier_outreach_reachable(l, lower(btrim(n.to_email)))
       and public.fn_mail_provider_class(m.domain, m.hosts) = any(public.fn_invite_placement_open_providers(v_day))
  )
  update public.notifications n
     set status = 'queued', claimed_at = null,
         not_before = v_start + (r.rn - 1) * ((v_end - v_start) / greatest(r.c, 1)),
         last_error = 'released 2 Nov 2026: held by the created_at stale rule while not_before deferred it; send_outbox now ages a row from when it fell due'
    from r
   where n.id = r.id;
end
$release$;
