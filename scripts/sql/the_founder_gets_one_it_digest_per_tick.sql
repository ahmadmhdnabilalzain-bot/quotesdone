-- THE FOUNDER GETS ONE IT DIGEST PER TICK, NOT ONE EMAIL PER FINDING.
--
-- Assigned: customer_support (the hold, the digest, the send). The tick that releases it is the
-- it_engineer's (fn_it_loop_tick). 15 Sep 2026.
--
-- MEASURED BEFORE WRITING (15 Sep 2026, production, public.agent_actions and public.notifications):
--   * A new duty raised one it_engineer_finding per column ('duty:backup_gap:<table.column>'). The IT loop
--     escalated each one on its own: fn_ceo_it_escalation_decide opens one customer_support delivery.request
--     per issue (kind it_new_bug, dedupe_key 'it_new_bug:<issue_key>'), and fn_customer_support_acts_on_handoff
--     called fn_notify_founder once per request -- one email AND one WhatsApp each. The dedupe is per issue,
--     so N simultaneous issues were N messages on each channel.
--   * 82 it_new_bug delivery requests in 3 days: 55 in the single minute 23:10 UTC on 14 Sep, then 3, 2, 1,
--     7 (05:01, nightly journeys), 1 and 12 (05:31, slow statements). 50 emails and 1 WhatsApp were SENT
--     (the founder received 45 between 23:10 and 01:03); 111 more (31 email, 80 WhatsApp) were set to
--     'skipped' by hand. They are not resent: this file touches only requests still pending a digest,
--     and every one of those 82 is already 'done'.
--
-- WHAT THIS CHANGES (one door, so every writer is covered -- fn_ceo_it_escalation_decide,
-- fn_it_ceo_silence_watch, and the accountant's findings, which reach the founder only through the
-- same IT loop (the_accountant_raises_its_findings_into_the_loop_the_it_engineer_runs.sql)):
--   1. HOLD. fn_customer_support_acts_on_handoff no longer sends a founder it_new_bug request. It answers
--      'waiting', so fn_seat_handoff_act leaves the request pending: the delivery watch reads only done or
--      failed requests, so a held request is never reported as 'not_sent'.
--   2. DIGEST. fn_customer_support_sends_the_it_digest sends everything held as ONE fn_notify_founder call
--      (kind it_new_bug, so founder_mail_policy still decides; one email + one WhatsApp): "N new problems
--      the IT engineer could not fix", one line per problem with its reference. A family -- the issue_key
--      up to its last ':' when that prefix still has a ':' of its own, e.g. duty:backup_gap -- raised
--      together is ONE line with its count. A single problem keeps the old single-problem email.
--      * floor: at most one digest per 60 minutes; anything held meanwhile folds into the next one.
--      * the per-issue 24-hour dedupe fn_notify_founder used to apply is kept: a problem already told within
--        24 hours is logged 'deduped' and left out.
--      * each held request is then completed with the digest's notification ids, so the delivery watch
--        returns a delivery.result to the seat that asked exactly as before (delivered / routed / stubbed).
--   3. TICK. fn_it_loop_tick runs the digest as its last step, so a tick's new bugs leave as one message,
--      and anything held by the floor or raised outside the tick leaves on the next tick (every 15 minutes).
--
-- REDEFINED HERE (MANIFEST order makes this file canonical): fn_customer_support_acts_on_handoff (body
-- otherwise byte-identical to every_send_comes_back_to_whoever_asked.sql, as live on 15 Sep 2026) and
-- fn_it_loop_tick (otherwise byte-identical to the_it_engineer_closes_every_loop_it_opens.sql, as live).
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: the per-issue it.finding handoffs, the CEO's decision, the
-- incident record, re-verification and closing (the tracking loop is untouched -- only the founder
-- delivery is batched); fn_notify_founder; every other founder kind.
-- Known ceiling: if the IT tick stops, held problems wait with it. That stage failing is itself a finding
-- (fn_it_loop_stage 'digest').
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_gets_one_it_digest_per_tick.sql --apply --ddl

-- ── 1. SUPPORT HOLDS A NEW BUG FOR THE DIGEST ─────────────────────────────────────────────────────
create or replace function public.fn_customer_support_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; v_ar boolean; v_subject text; v_body text; v_nid bigint; v_fan jsonb; v_cc text[]; v_res jsonb;
  p public.notifications; v_before bigint; v_from text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; v_from := d->>'from';
  if d->>'type' <> 'delivery.request' then raise exception 'customer_support has no handler for %', d->>'type'; end if;

  if d ? 'prepared' then
    p := jsonb_populate_record(null::public.notifications, d->'prepared');
    if p.to_role in ('customer', 'supplier') and v_from not in ('sales_engineer', 'customer_support') then
      raise exception 'only the sales engineer and support address customers and suppliers; % may address the founder only', v_from;
    end if;
    -- The caller chooses the words and the address. It never chooses the status, the sender or the
    -- requester: those are support's record of what it was asked and what it did.
    -- Tracked by THIS request, so the adoption trigger (section 5) must not open a second one.
    perform set_config('app.qd_delivery_tracked', 'on', true);
    insert into public.notifications (type, kind, to_email, cc_emails, to_role, to_phone, lead_id, inquiry_id, quote_id,
                                      channel, subject, body, html, attachments, lang, status, requested_by)
    values (p.type, p.kind, p.to_email, coalesce(p.cc_emails, '{}'), p.to_role, p.to_phone, p.lead_id, p.inquiry_id, p.quote_id,
            coalesce(p.channel, 'email'), p.subject, p.body, p.html, p.attachments, p.lang, 'queued', v_from)
    returning id into v_nid;
    select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.channel = 'whatsapp' and n.id > v_nid and n.created_at = now() and n.type = p.type
       and n.to_email is not distinct from p.to_email;
    perform set_config('app.qd_delivery_tracked', 'off', true);
    return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                              'channel', coalesce(p.channel, 'email'), 'prepared', true);
  end if;

  if d->>'recipient_role' = 'founder' then
    -- A NEW BUG WAITS FOR THE DIGEST (the_founder_gets_one_it_digest_per_tick.sql). 55 requests in one
    -- minute were 55 emails and 55 WhatsApp messages; fn_customer_support_sends_the_it_digest sends them
    -- as one. 'waiting' keeps the request pending, so the watch does not read it until it is sent.
    if d->>'kind' = 'it_new_bug' then
      return jsonb_build_object('channel', 'founder', 'digest', 'pending', 'event', d->>'event',
                                'waiting', 'the next IT digest (fn_customer_support_sends_the_it_digest)');
    end if;
    -- A TEST NEVER REACHES HIM. The fixture ladder sets app.qd_stub_founder_notify; the probe also
    -- aborts its transaction, so even the queued rows are never committed.
    if coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on' then
      return jsonb_build_object('channel', 'founder', 'stubbed', true, 'event', d->>'event');
    end if;
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => d->>'event', p_detail => d->>'detail', p_level => coalesce(d->>'level', 'high'),
                                      p_kind => d->>'kind', p_dedupe_key => d->>'dedupe_key', p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
    return jsonb_build_object('channel', 'founder', 'notify', v_res, 'notification_ids', v_fan,
                              'notification_id', v_fan->0);
  end if;

  if v_from <> 'sales_engineer' then
    raise exception 'only the sales engineer addresses customers and suppliers; % may address the founder only', v_from;
  end if;
  if coalesce(d->>'to_email', '') !~ '@' then
    return jsonb_build_object('delivered', false, 'reason', 'no email address on file for the ' || coalesce(d->>'recipient_role', 'recipient'));
  end if;

  v_ar := d->>'locale' = 'ar' and d->>'body_ar' is not null;
  v_subject := case when v_ar then coalesce(d->>'subject_ar', d->>'subject_en') else d->>'subject_en' end;
  v_body    := case when v_ar then d->>'body_ar' else d->>'body_en' end;
  select coalesce(array_agg(x), '{}') into v_cc from jsonb_array_elements_text(coalesce(d->'cc', '[]'::jsonb)) x;

  perform set_config('app.qd_delivery_tracked', 'on', true);
  -- requested_by names the seat that asked (customer_support_is_the_only_sender_on_email_and_whatsapp.sql);
  -- sender stays customer_support by that file's default and check.
  insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
  values (d->>'msg_type', d->>'msg_type', d->>'to_email', v_cc, d->>'recipient_role',
          (d->>'supplier_id')::bigint, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, 'email', v_subject, v_body, 'queued',
          v_from)
  returning id into v_nid;
  select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
   where n.channel = 'whatsapp' and n.type = d->>'msg_type' and n.id > v_nid
     and n.to_email = d->>'to_email' and n.created_at >= now() - interval '1 minute';
  perform set_config('app.qd_delivery_tracked', 'off', true);

  return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                            'language', case when v_ar then 'ar' else 'en' end,
                            'watch_until', d->'watch_until', 'watching', (d->>'watch_until') is not null);
end $fn$;
revoke execute on function public.fn_customer_support_acts_on_handoff(bigint) from public, anon, authenticated;

-- ── 2. SUPPORT SENDS WHAT IS HELD AS ONE DIGEST — OWNED ELSEWHERE SINCE 22 SEP 2026 ─────────────
-- THE DEFINITION THAT USED TO SIT HERE WAS REMOVED ON 22 SEP 2026 (it_engineer), AND THIS IS WHY.
-- scripts/sql/the_founder_hears_from_it_once_a_day.sql (later in MANIFEST, so the canonical winner) DROPS
-- fn_customer_support_sends_the_it_digest(interval) and defines fn_customer_support_sends_the_it_digest(
-- p_now timestamptz default now()) in its place. Re-applying THIS file on 22 Sep re-created the dropped
-- overload, and because both carry a default the one call the estate makes -
-- fn_customer_support_sends_the_it_digest() inside fn_it_loop_tick - became ambiguous: agent_runs at
-- 2026-09-22 20:01:27Z, "function public.fn_customer_support_sends_the_it_digest() is not unique", so the
-- founder got no IT digest at all. A superseded definition left in an older file is a live routine waiting
-- for somebody to re-apply the file, so it is gone from here rather than commented into a corner.
-- The resurrected overload is dropped by scripts/sql/the_it_digest_has_one_signature_again.sql.


-- ── 2b. WHAT "AN OPEN TECHNICAL PROBLEM" MEANS — ONE DEFINITION, EVERY READER ─────────────────────
-- 22 Sep 2026 (it_engineer, UNSOLVED-11). The founder's brief counted every unclosed it_engineer_finding
-- while the IT loop skips the ones its own severity function calls 'warn', so the brief said 9-10 where the
-- digest he gets minutes later said 8. Copying the predicate into the brief would have made them agree
-- today and drift again tomorrow — they were already two hand-copies. It is one function now, and both
-- callers select from it: fn_it_loop_tick (in the file named below, which owns the tick) adds its OWN extra
-- condition — a finding it has not handed off for this occurrence yet — because "is this problem open" and
-- "must I raise it on this tick" are different questions. That condition stays with the tick.
-- It is defined HERE, and here is deliberate: this file sorts before every file that reads it
-- (MANIFEST 1434, against 1451 for the tick and 1532 for the founder's brief).
create or replace function public.fn_it_open_findings()
returns setof public.it_engineer_finding
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select f.* from public.it_engineer_finding f
   where f.closed_at is null
     and public.fn_it_engineer_severity(f.blast, f.affected, f.started_at) <> 'warn'
$fn$;
revoke execute on function public.fn_it_open_findings() from public, anon, authenticated;

-- ── 3. THE TICK — OWNED ELSEWHERE SINCE 22 SEP 2026 ──────────────────────────────────────────────
-- fn_it_loop_tick was removed from this file for the same reason, and its removal is the more serious of
-- the two: the canonical winner is
-- scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql, whose
-- body runs nine steps (the originators sweep, the CEO sales and accountant sweeps, the silence watch and
-- the daily line among them). The copy that used to live here predates those steps, so re-applying this
-- file on 22 Sep did not merely drift the routine - it took those steps OFF production until the winner
-- was re-applied. The shared open-findings definition this loop now reads stays here (above), because it
-- is defined before every file that reads it.


-- ── 4. THE POLICY SAYS WHAT IT NOW DOES ───────────────────────────────────────────────────────────
update public.founder_mail_policy
   set reason = 'Founder, 14 Sep 2026: "for new bugs i just need to be notified on email". Sent by customer_support only after the owning seat and the CEO could not fix it, as ONE digest per IT tick and at most one per 60 minutes (the_founder_gets_one_it_digest_per_tick.sql); each problem deduped for 24 hours, repeats folded into the IT daily line.',
       updated_at = now()
 where kind = 'it_new_bug';
