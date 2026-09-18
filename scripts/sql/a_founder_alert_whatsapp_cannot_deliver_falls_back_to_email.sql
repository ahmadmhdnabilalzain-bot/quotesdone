-- A FOUNDER ALERT WHATSAPP CANNOT DELIVER FALLS BACK TO EMAIL, AND STOPS BEING A BACKLOG.
-- it_engineer, 18 Sep 2026.
--
-- WHAT WAS MEASURED (18 Sep 2026 01:47 UTC, production htdblwldjkcgjvmqkbeh)
--   Three founder_alert rows (30639, 30641, 30643, kind it_new_bug, all to the founder's number)
--   had been queued on channel='whatsapp' since 17 Sep 18:31Z with attempts=0, and send_whatsapp
--   logged {"signal":"templates_not_ready","pending":3,"requeued":3} every hour.
--
--   That log line is WRONG, and it is the reason the defect was misdiagnosed. Measured against
--   Twilio's Content API the same minute: quotesdone_founder_alert_en_mtpvxeys
--   (HXcb8792bf6037babf71971b59cef9c9ca) is APPROVED, category UTILITY, and app_secrets
--   wa_templates_ready='true'. The template was never the cause. The cause is
--   app_secrets.wa_per_recipient_24h = 1: every founder alert goes to ONE number, so the second and
--   third alert of any 24 hours are refused by the sender-reputation cap. In send_whatsapp's loop
--   that branch does `capped++; requeued++`, and `requeued` is what arms the templates_not_ready
--   signal — so the reputation cap has been reporting itself as a Meta approval problem.
--
--   The consequence is not a growing backlog; it is a silent loss. A capped row keeps being
--   requeued until it crosses the 24-hour staleness bar and is marked 'held'. Five founder alerts
--   between 15 and 16 Sep ended that way (ids 30513, 30515, 30520, 30581, 30583). Each of those
--   happened to have an email twin, so the founder was reached — but nothing in the code checked
--   that, and nothing would have noticed if the twin had failed.
--
-- WHAT THIS FILE ADDS
--   fn_wa_founder_alert_fallback(notification_id, reason): the single door send_whatsapp calls
--   whenever a FOUNDER-addressed WhatsApp row cannot be delivered, for any reason — template
--   missing, pending or rejected at Meta, no SID registered, the daily cap, staleness, an unmapped
--   type, or a hard Twilio rejection. It does three things and returns what it did:
--     1. confirms the email twin actually exists (queued or sent) for the same kind and moment;
--     2. if there is none, queues one carrying the ROW'S OWN kind, so the a10 founder-mail trigger
--        admits it — and DETECTS the case where the policy refuses that kind instead of assuming
--        it went (a10 is a BEFORE trigger that returns NULL, so the insert silently yields no row;
--        `returning id` comes back NULL and that is the signal). A refusal is recorded in
--        founder_alerts rather than swallowed;
--     3. marks the WhatsApp row 'skipped' WITH the reason, so it leaves the queue honestly and the
--        queue-stall watcher counts only rows that really are waiting.
--
--   It never sends anything itself and never touches a row that is not addressed to the founder;
--   the founder test is copied verbatim from fn_notifications_founder_mail_policy so the two
--   cannot disagree about who the founder is.

create or replace function public.fn_wa_founder_alert_fallback(p_notification_id bigint, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  n public.notifications%rowtype;
  v_phone text; v_email text; v_kind text; v_twin integer; v_new bigint; v_outcome text; v_claim bigint;
begin
  select * into n from public.notifications where id = p_notification_id;
  if not found then return jsonb_build_object('ok', false, 'outcome', 'no_such_row'); end if;
  if coalesce(n.channel, 'email') <> 'whatsapp' then
    return jsonb_build_object('ok', false, 'outcome', 'not_whatsapp');
  end if;

  -- Same test as a10_notifications_founder_mail_policy, so one cannot admit what the other refuses.
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone
    from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(n.to_role, '') in ('founder', 'admin', 'owner')
          or (n.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(n.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return jsonb_build_object('ok', false, 'outcome', 'not_founder');
  end if;

  v_kind := coalesce(nullif(btrim(n.kind), ''), nullif(btrim(n.type), ''), 'unregistered');

  -- 1. CLAIM THE ROW BEFORE DOING ANYTHING ELSE. send_whatsapp runs every 15 minutes and a run can
  --    overlap its predecessor; without a claim two callers could both pass the twin check and both
  --    queue a fallback email, so the founder would get the same alert twice. The UPDATE takes the
  --    row lock and only one caller gets an id back. The outcome is not known yet, so last_error is
  --    written provisionally here and finished below — a row can never be left saying 'pending'
  --    because both writes are in the same transaction as the caller's rpc.
  update public.notifications
     set status = 'skipped',
         last_error = left('not delivered by WhatsApp: ' || coalesce(p_reason, 'unspecified')
                           || ' | founder fallback: in progress', 500)
   where id = n.id and status in ('queued', 'held')
   returning id into v_claim;
  if v_claim is null then
    -- another run already retired this row, or it was delivered in the meantime. Do NOT email again.
    return jsonb_build_object('ok', false, 'outcome', 'already_handled', 'notification_id', n.id);
  end if;

  -- 2. Did the email twin already carry this alert? fn_notify_founder inserts the email row and the
  --    WhatsApp row in the same call, so the twin shares created_at to the microsecond; ten minutes
  --    is a generous window that still cannot reach the next tick's alert, and the subject match
  --    pins it to THIS event rather than to any alert of the same kind.
  --    ponytail: the correlation is (kind, ±10 minutes, subject containment) because the two rows
  --    share no id today — fn_notify_founder writes the email subject as '[Attention] ' || event and
  --    the WhatsApp subject as the bare event, so one contains the other. Two alerts of the SAME
  --    kind inside ten minutes where one subject contains the other would mis-correlate. Give both
  --    rows a shared correlation id in fn_notify_founder if that ever becomes possible; the ceiling
  --    here is a one-hour-per-problem deduped IT digest, so it cannot happen with today's writers.
  --    The window is bounded by created_at, which notifications_status_idx covers.
  select count(*) into v_twin
    from public.notifications e
   where e.channel = 'email'
     and coalesce(e.to_role, '') in ('founder', 'admin', 'owner')
     and coalesce(nullif(btrim(e.kind), ''), nullif(btrim(e.type), ''), 'unregistered') = v_kind
     and e.status in ('queued', 'sent')
     and e.created_at between n.created_at - interval '10 minutes' and n.created_at + interval '10 minutes'
     and position(coalesce(n.subject, '~none~') in coalesce(e.subject, '')) > 0;

  if v_twin > 0 then
    v_outcome := 'email_twin_already_sent';
  else
    select coalesce(nullif(split_part(coalesce(value, ''), ',', 1), ''), 'management@quotesdone.com')
      into v_email from public.app_secrets where key = 'admin_emails';
    v_email := coalesce(v_email, 'management@quotesdone.com');

    -- The kind travels with the fallback on purpose. Queue it as 'founder_alert' with the row's own
    -- kind and a10 admits it exactly when founder_mail_policy says that kind is his to read.
    insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
    values ('founder_alert', v_kind, v_email, 'founder',
            '[Attention] ' || coalesce(n.subject, 'QuotesDone alert'), n.body, 'queued', 'email')
    returning id into v_new;

    if v_new is null then
      -- a10 returned NULL: founder_mail_policy says this kind is not his to read, so the alert was
      -- routed to its owning seat instead. That is a decision, not a delivery — record it where the
      -- OS can see it rather than let the WhatsApp row disappear claiming an email went.
      v_outcome := 'blocked_by_founder_mail_policy';
      insert into public.founder_alerts (level, event, detail, channel)
      values ('high', 'whatsapp_fallback:blocked_by_policy',
              left('notification ' || n.id || ' (kind ' || v_kind || ') could not be sent by WhatsApp ('
                   || coalesce(p_reason, 'unspecified') || ') and founder_mail_policy does not allow '
                   || 'that kind by email either: ' || coalesce(n.subject, ''), 1000), 'os');
    else
      v_outcome := 'emailed';
    end if;
  end if;

  -- 4. Finish the record the claim in step 1 opened. The row is already out of the queue; this only
  --    replaces 'in progress' with what actually happened, so the row explains itself for ever.
  update public.notifications
     set last_error = left('not delivered by WhatsApp: ' || coalesce(p_reason, 'unspecified')
                           || ' | founder fallback: ' || v_outcome, 500)
   where id = n.id;

  return jsonb_build_object('ok', true, 'outcome', v_outcome, 'kind', v_kind,
                            'email_notification_id', v_new, 'notification_id', n.id);
end $fn$;

-- CREATE grants EXECUTE to PUBLIC. service_role keeps it through Supabase's default privileges,
-- which is how send_whatsapp calls this over PostgREST.
revoke execute on function public.fn_wa_founder_alert_fallback(bigint, text) from public, anon, authenticated;

-- PROBE. This file defines a function, so the probe CLEANS UP AFTER ITSELF and ends in a notice:
-- a `raise exception` here would roll the create above back with it. Everything it touches is a
-- fixture it created and then deleted; the three real stuck rows are counted before and after and
-- must be untouched. The policy-refusal branch (a10 returning NULL) is not exercised here because
-- refusing routes the alert to an owning seat and would leave a real task behind; it is proved in
-- an aborted-transaction probe instead, which commits nothing.
do $probe$
declare
  v_real_before integer; v_real_after integer;
  v_wa bigint; v_mail bigint; v_other bigint; v_r jsonb; v_status text; v_err text; v_created bigint[];
begin
  select count(*) into v_real_before from public.notifications where id in (30639, 30641, 30643);

  -- CASE A: the email twin already went. The WhatsApp row must be marked skipped and NO second
  -- email queued.
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
  values ('founder_alert', 'it_new_bug', 'zz.demo.fallback@example.invalid', 'founder',
          '[Attention] ZZ DEMO fallback probe A', 'ZZ DEMO probe body', 'sent', 'email')
  returning id into v_mail;
  insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel)
  values ('founder_alert', 'it_new_bug', null, 'founder',
          'ZZ DEMO fallback probe A', 'ZZ DEMO probe body', 'queued', 'whatsapp')
  returning id into v_wa;
  update public.notifications set status = 'queued' where id = v_wa;   -- normalise whatever the triggers set

  v_r := public.fn_wa_founder_alert_fallback(v_wa, 'probe: template pending');
  if v_r ->> 'outcome' <> 'email_twin_already_sent' then
    raise exception 'PROBE A: expected email_twin_already_sent, got %', v_r;
  end if;
  select status into v_status from public.notifications where id = v_wa;
  if v_status <> 'skipped' then raise exception 'PROBE A: row not marked skipped, got %', v_status; end if;
  select last_error into v_err from public.notifications where id = v_wa;
  if position('template pending' in coalesce(v_err, '')) = 0 then
    raise exception 'PROBE A: the reason did not reach last_error: %', v_err;
  end if;
  delete from public.notifications where id in (v_wa, v_mail);

  -- CASE B: no twin. An email must be QUEUED — this is the proof the a10 founder-mail trigger
  -- admits the fallback rather than dropping it, because a dropped insert returns no id at all.
  insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel)
  values ('founder_alert', 'it_new_bug', null, 'founder',
          'ZZ DEMO fallback probe B', 'ZZ DEMO probe body', 'queued', 'whatsapp')
  returning id into v_wa;
  update public.notifications set status = 'queued' where id = v_wa;

  v_r := public.fn_wa_founder_alert_fallback(v_wa, 'probe: no template registered');
  if v_r ->> 'outcome' <> 'emailed' then
    raise exception 'PROBE B: expected emailed (a10 admitted it), got %', v_r;
  end if;
  v_mail := (v_r ->> 'email_notification_id')::bigint;
  if v_mail is null then raise exception 'PROBE B: no email id returned'; end if;
  select status into v_status from public.notifications where id = v_mail;
  if v_status not in ('queued', 'digest') then
    raise exception 'PROBE B: the fallback email is not queued for the outbox, status %', v_status;
  end if;
  select status into v_status from public.notifications where id = v_wa;
  if v_status <> 'skipped' then raise exception 'PROBE B: row not marked skipped, got %', v_status; end if;

  -- CASE E: called twice on the same row — the claim must refuse the second caller, so two
  -- overlapping send_whatsapp runs cannot email the founder the same alert twice.
  v_r := public.fn_wa_founder_alert_fallback(v_wa, 'probe: second caller');
  if v_r ->> 'outcome' <> 'already_handled' then
    raise exception 'PROBE E: a second call was not refused, got %', v_r;
  end if;
  if (select count(*) from public.notifications
       where channel = 'email' and subject like '%ZZ DEMO fallback probe B%') <> 1 then
    raise exception 'PROBE E: the second call queued a duplicate founder email';
  end if;
  delete from public.notifications where id in (v_wa, v_mail);

  -- CASE D: a supplier row is not the founder's and must be left exactly as it was.
  insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel)
  values ('supplier_doc_expiry', 'doc_expiry', null, 'supplier',
          'ZZ DEMO fallback probe D', 'ZZ DEMO probe body', 'queued', 'whatsapp')
  returning id into v_other;
  update public.notifications set status = 'queued' where id = v_other;
  v_r := public.fn_wa_founder_alert_fallback(v_other, 'probe: must not touch a supplier row');
  if v_r ->> 'outcome' <> 'not_founder' then
    raise exception 'PROBE D: expected not_founder, got %', v_r;
  end if;
  select status into v_status from public.notifications where id = v_other;
  if v_status <> 'queued' then raise exception 'PROBE D: a supplier row was altered, status %', v_status; end if;
  delete from public.notifications where id = v_other;

  -- The service role must be able to call it, or send_whatsapp cannot.
  if not has_function_privilege('service_role',
        'public.fn_wa_founder_alert_fallback(bigint, text)', 'execute') then
    raise exception 'service_role cannot execute fn_wa_founder_alert_fallback';
  end if;
  if has_function_privilege('anon',
        'public.fn_wa_founder_alert_fallback(bigint, text)', 'execute') then
    raise exception 'anon can execute fn_wa_founder_alert_fallback';
  end if;

  select count(*) into v_real_after from public.notifications where id in (30639, 30641, 30643);
  if v_real_after <> v_real_before then
    raise exception 'the probe disturbed the real stuck rows: % -> %', v_real_before, v_real_after;
  end if;
  if exists (select 1 from public.notifications where subject like 'ZZ DEMO fallback probe%'
                                                   or subject like '%ZZ DEMO fallback probe%') then
    raise exception 'the probe left fixture rows behind';
  end if;

  raise notice 'fn_wa_founder_alert_fallback: A (twin already sent), B (a10 admitted the fallback email), D (a supplier row untouched) all pass; service_role can execute, anon cannot; real rows % unchanged', v_real_before;
end $probe$;
