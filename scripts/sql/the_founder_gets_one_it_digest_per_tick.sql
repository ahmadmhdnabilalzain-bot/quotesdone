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

-- ── 2. SUPPORT SENDS WHAT IS HELD AS ONE DIGEST ───────────────────────────────────────────────────
-- p_floor: no digest within this long of the last one actually emailed (a stubbed test sends nothing and
-- writes no founder_alerts row, so it never moves the floor). The probe passes interval '0'.
create or replace function public.fn_customer_support_sends_the_it_digest(p_floor interval default interval '60 minutes')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_stub boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_ids bigint[]; v_dup bigint[]; v_send bigint[]; v_last timestamptz; v_n int; v_lines int := 0;
  v_event text; v_detail text; v_key text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint; x record;
begin
  -- Two ticks at once must not both send: the second waits, then finds nothing pending.
  perform pg_advisory_xact_lock(hashtext('fn_customer_support_sends_the_it_digest'));

  select coalesce(array_agg(a.id order by a.id), '{}') into v_ids
    from public.agent_actions a
   where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
     and a.detail->>'type' = 'delivery.request' and a.detail->>'recipient_role' = 'founder'
     and a.detail->>'kind' = 'it_new_bug' and a.evidence->>'digest' = 'pending';
  if cardinality(v_ids) = 0 then return jsonb_build_object('sent', false, 'held', 0); end if;

  select max(f.created_at) into v_last from public.founder_alerts f
   where f.dedupe_key like 'it_new_bug_digest:%' and f.channel in ('email', 'whatsapp');
  if v_last > now() - p_floor then
    return jsonb_build_object('sent', false, 'held', cardinality(v_ids), 'next_after', v_last + p_floor);
  end if;

  -- The per-issue promise fn_notify_founder kept: one message per problem per 24 hours.
  select coalesce(array_agg(a.id order by a.id) filter (where exists (
           select 1 from public.founder_alerts f
            where f.dedupe_key = a.detail->>'dedupe_key' and f.channel in ('email', 'whatsapp', 'digested')
              and f.created_at > now() - interval '24 hours')), '{}'),
         coalesce(array_agg(a.id order by a.id) filter (where not exists (
           select 1 from public.founder_alerts f
            where f.dedupe_key = a.detail->>'dedupe_key' and f.channel in ('email', 'whatsapp', 'digested')
              and f.created_at > now() - interval '24 hours')), '{}')
    into v_dup, v_send
    from public.agent_actions a where a.id = any(v_ids);
  v_n := cardinality(v_send);

  if v_n = 1 then
    -- One problem reads as it always did.
    select a.detail->>'event', a.detail->>'detail' into v_event, v_detail from public.agent_actions a where a.id = v_send[1];
  elsif v_n > 1 then
    with items as (
      select a.id,
             regexp_replace(coalesce(a.detail->>'dedupe_key', 'handoff:' || a.id), '^it_new_bug:', '') as ref,
             regexp_replace(coalesce(a.detail->>'event', ''), '^New problem the IT engineer could not fix: ', '') as title
        from public.agent_actions a where a.id = any(v_send)),
    fam as (
      select i.*, case when regexp_replace(i.ref, ':[^:]*$', '') ~ ':' then regexp_replace(i.ref, ':[^:]*$', '') else i.ref end as family
        from items i),
    g as (
      select family, count(distinct ref) as n, min(title) as title, min(ref) as ref, min(id) as first_id,
             row_number() over (order by min(id)) as rn
        from fam group by family)
    select count(*)::int,
           string_agg(case when n = 1 then '- ' || left(title, 140) || ' (reference ' || ref || ')'
                           else '- ' || n || ' problems of one kind, ' || family || ', e.g. ' || left(title, 110)
                                || ' (references ' || family || ':...)' end,
                      E'\n' order by rn) filter (where rn <= 15)
      into v_lines, v_detail
      from g;
    -- ponytail: 15 lines keep the WhatsApp twin readable; the rest is on each handoff in the OS.
    v_event := v_n || ' new problems the IT engineer could not fix';
    v_detail := 'Raised since the last message, one line each; problems of one kind raised together are one line with their count.'
             || E'\n\n' || v_detail
             || case when v_lines > 15 then E'\n- and ' || (v_lines - 15) || ' more lines, each on its handoff in the OS' else '' end
             || E'\n\nNothing inside the company fixed these, so each needs a code or configuration change. '
             || 'Each stays tracked until the IT engineer confirms it is gone.';
  end if;

  if v_n > 0 then
    v_key := 'it_new_bug_digest:' || v_send[1] || '-' || v_send[v_n];
    if v_stub then
      -- A TEST NEVER REACHES HIM: nothing is queued and nothing is logged as told.
      v_res := jsonb_build_object('stubbed', true);
    else
      select coalesce(max(id), 0) into v_before from public.notifications;
      perform set_config('app.qd_delivery_tracked', 'on', true);
      v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'high',
                                        p_kind => 'it_new_bug', p_dedupe_key => v_key, p_owner_agent => 'customer_support');
      select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
       where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
      perform set_config('app.qd_delivery_tracked', 'off', true);
      -- Each problem is recorded as told, under its own key, so the 24-hour promise holds next tick.
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      select 'high', a.detail->>'event', 'told in ' || v_key, 'digested', a.detail->>'dedupe_key'
        from public.agent_actions a where a.id = any(v_send);
    end if;
  end if;
  if not v_stub and cardinality(v_dup) > 0 then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    select 'high', a.detail->>'event', a.detail->>'detail', 'deduped', a.detail->>'dedupe_key'
      from public.agent_actions a where a.id = any(v_dup);
  end if;

  -- Every held request is completed with what became of it; the delivery watch takes it from there.
  for x in select a.id, a.evidence from public.agent_actions a where a.id = any(v_ids) order by a.id loop
    if x.id = any(v_dup) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'deduped',
        'notify', jsonb_build_object('emailed', false, 'deduped', true, 'kind', 'it_new_bug')));
    else
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'sent',
        'digest_key', v_key, 'digest_size', v_n, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
        || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
    end if;
  end loop;

  return jsonb_build_object('sent', v_n > 0, 'items', cardinality(v_ids), 'problems', v_n, 'lines', v_lines,
                            'deduped', cardinality(v_dup), 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $fn$;
revoke execute on function public.fn_customer_support_sends_the_it_digest(interval) from public, anon, authenticated;

-- ── 3. THE TICK SENDS THE DIGEST LAST ─────────────────────────────────────────────────────────────
-- Called by fn_it_engineer_alert_tick every 15 minutes, after it has pulled the detectors. Each step
-- is its own sub-transaction so one failing step is REPORTED in the result and does not stop the rest.
create or replace function public.fn_it_loop_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f record; o jsonb := '{}'::jsonb; n_open int := 0; v_err jsonb := '[]'::jsonb; v_step text;
begin
  for f in select x.issue_key, x.started_at from public.it_engineer_finding x
            where x.closed_at is null and public.fn_it_engineer_severity(x.blast, x.affected, x.started_at) <> 'warn'
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
                                 and a.detail->>'issue_key' = x.issue_key
                                 and (a.detail->>'occurrence_started_at')::timestamptz = x.started_at)
            order by x.started_at loop
    begin
      -- The playbook first: a known remedy runs once per occurrence, and the finding is handed on
      -- only if it is still open on the next tick.
      continue when public.fn_it_playbook_first(f.issue_key, f.started_at);
      perform public.fn_it_loop_open(f.issue_key);
      n_open := n_open + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('step', 'open', 'issue_key', f.issue_key, 'error', sqlerrm);
    end;
  end loop;
  o := o || jsonb_build_object('opened', n_open);

  begin o := o || jsonb_build_object('reverify', public.fn_it_loop_reverify());
  exception when others then v_err := v_err || jsonb_build_object('step', 'reverify', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_it_reports_sweep());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_silence', public.fn_it_ceo_silence_watch());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_silence', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('daily', public.fn_it_daily_line());
  exception when others then v_err := v_err || jsonb_build_object('step', 'daily', 'error', sqlerrm); end;
  -- Last, so everything this tick escalated leaves in the one message.
  begin o := o || jsonb_build_object('digest', public.fn_customer_support_sends_the_it_digest());
  exception when others then v_err := v_err || jsonb_build_object('step', 'digest', 'error', sqlerrm); end;

  foreach v_step in array array['open', 'reverify', 'ceo', 'ceo_silence', 'daily', 'digest'] loop
    perform public.fn_it_loop_stage(v_step,
      (select string_agg(coalesce(e->>'issue_key' || ': ', '') || (e->>'error'), '; ')
         from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_it_loop_tick() from public, anon, authenticated;

-- ── 4. THE POLICY SAYS WHAT IT NOW DOES ───────────────────────────────────────────────────────────
update public.founder_mail_policy
   set reason = 'Founder, 14 Sep 2026: "for new bugs i just need to be notified on email". Sent by customer_support only after the owning seat and the CEO could not fix it, as ONE digest per IT tick and at most one per 60 minutes (the_founder_gets_one_it_digest_per_tick.sql); each problem deduped for 24 hours, repeats folded into the IT daily line.',
       updated_at = now()
 where kind = 'it_new_bug';
