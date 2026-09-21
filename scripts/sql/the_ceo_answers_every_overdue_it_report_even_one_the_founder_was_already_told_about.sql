-- THE CEO ANSWERS EVERY OVERDUE IT REPORT, EVEN ONE THE FOUNDER WAS ALREADY TOLD ABOUT.
--
-- Assigned: ceo (the decider), it_engineer (the silence watch). 21 Sep 2026.
--
-- ══ MEASURED, 21 Sep 2026 ~18:40 UTC, htdblwldjkcgjvmqkbeh (read-only + rolled-back) ════════
-- The founder's 13:16 Dubai email "The CEO has not answered an IT report: A founder_alert for the
-- founder did not arrive (sent_unconfirmed)" is support_ceo_report 2571, paged at 09:16Z. Later the
-- same day the_ceo_answers_the_report_families_it_had_no_answer_for.sql gave that family a decider
-- (fn_ceo_delivery_undelivered_decide). At 18:40Z 2571 was STILL 'sent', with 12 more of its family:
--   1. fn_it_ceo_silence_watch selects only reports with NO delivery.request handoff yet. Every
--      report paged before the decider existed already has one, so the watch never visits it again
--      and the decider is never called for it: 13 reports answered by nobody, for ever. In a
--      rolled-back run the decider ACCEPTS 5 of them at once (1677, 2146, 2485, 2532, 2571: WhatsApp
--      handed to Twilio without a SID, email twin sent and confirmed).
--   2. The other 8 (1984-1987, 1989-1992, filed 18 Sep) answer "the report names no notification":
--      their request's subject, notifications 32524-32527 and 32544-32547, no longer exists -- the
--      whole id range 32518-32550 is gone from public.notifications (a probe batch; two of them were
--      addressed to zz.demo.fallback@example.invalid). A founder alert that no longer exists can
--      never be re-checked, so the decider could never answer and the report could never close.
--
-- ══ WHAT THIS FILE CHANGES ═══════════════════════════════════════════════════════════════════
-- 1. fn_ceo_delivery_undelivered_decide: when the report's own evidence names no notification, it
--    reads the request handoff (verified_evidence.request_id) for its subject; when that subject
--    notification does not exist in public.notifications the CEO accepts with a receipt naming the
--    missing id -- the condition cannot be re-checked and nothing is left to deliver. Every other
--    branch is unchanged: a subject that exists and was not delivered on any channel stays undecided.
-- 2. fn_it_ceo_silence_watch: the CEO's decider runs for EVERY overdue 'sent' it_engineer report;
--    the "already paged" test now guards only the page, not the answer. The page, its dedupe key
--    (it_ceo_silent:<family>:<Dubai day>) and the window are unchanged.
-- NOT CHANGED: fn_ceo_decide_report's dispatch, fn_originator_checks_delivery, the digest, and the
-- by-design pair behind every founder alert (fn_notify_founder writes one email and one WhatsApp twin
-- in the same statement -- measured: every founder notification today is exactly that pair).
-- RECURRENCE: the probe below builds an ALREADY-PAGED overdue report and a report whose subject
-- notification is gone, runs the watch, and answers PROBE FAILED if either is left 'sent'.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_answers_every_overdue_it_report_even_one_the_founder_was_already_told_about.sql --apply --ddl

-- ── 1. the decider reads the request when the report names no notification ──
create or replace function public.fn_ceo_delivery_undelivered_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; n public.notifications; twin public.notifications; v_receipt text;
  v_req public.agent_actions; v_subject bigint;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  select * into n from public.notifications
   where id = coalesce((r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                       (r.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
  if n.id is null then
    -- The report may name the notification only through its request (18 Sep reports did: the
    -- recheck found "nothing was queued"). A subject that no longer exists cannot be re-checked.
    select * into v_req from public.agent_actions
     where id = nullif(r.verified_evidence ->> 'request_id', '')::bigint and kind = 'handoff';
    v_subject := coalesce(nullif(v_req.detail ->> 'subject_id', '')::bigint,
                          (r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint);
    if v_req.id is not null and v_req.detail ->> 'subject_table' = 'notifications' and v_subject is not null
       and not exists (select 1 from public.notifications x where x.id = v_subject) then
      v_receipt := 'ceo: the founder alert this report is about (notification ' || v_subject || ', request '
                   || v_req.id || ') no longer exists in public.notifications, so its delivery can never be '
                   || 're-checked and there is nothing left to deliver. Closed on that fact rather than left open for ever.';
      update public.support_ceo_report
         set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
       where id = r.id;
      return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', v_subject, 'subject_present', false, 'receipt', v_receipt);
    end if;
    return jsonb_build_object('ok', false, 'report_id', r.id, 'reason', 'the report names no notification');
  end if;
  -- The email twin fn_notify_founder writes in the same statement as the WhatsApp fan-out.
  select * into twin from public.notifications t
   where t.channel = 'email' and t.type = n.type and t.created_at = n.created_at
     and t.to_role is not distinct from n.to_role and t.id <> n.id and t.status = 'sent'
   order by t.id limit 1;

  if n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> '' then
    v_receipt := 'ceo: the provider confirmed notification ' || n.id || ' (' || n.channel || ', message '
                 || n.provider_message_id || ', sent ' || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai)';
  elsif n.status = 'sent' and n.channel = 'whatsapp' and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' was handed to Twilio at '
                 || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai without a provider id on record; '
                 || 'the email twin ' || twin.id || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || '). '
                 || 'send_whatsapp stores the SID from 21 Sep 2026, so a WhatsApp send is confirmed or failed, never unconfirmed.';
  elsif n.status in ('failed', 'skipped', 'suppressed') and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' (' || n.channel || ') ended ' || n.status
                 || coalesce(' — ' || left(n.last_error, 160), '') || '; the email twin ' || twin.id
                 || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || '), so the alert reached the founder.';
  else
    -- A founder alert with no delivered twin, or still in the queue: not the CEO's to wave through.
    return jsonb_build_object('ok', false, 'report_id', r.id, 'notification_id', n.id, 'status', n.status,
                              'reason', 'undecided: no confirmed delivery on any channel');
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', n.id, 'receipt', v_receipt);
end $fn$;
revoke execute on function public.fn_ceo_delivery_undelivered_decide(bigint) from public, anon, authenticated;

-- ── 2. the watch answers first for every overdue report; "already paged" guards only the page ──
create or replace function public.fn_it_ceo_silence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n_told int := 0; n_answered int := 0; v_window interval; v_dec jsonb; v_status text;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Same fault, same answer as fn_it_loop_reverify above: a hardcoded 4 h fallback here would keep
  -- policing to a number nobody can see, after the row that is supposed to hold it had gone.
  if v_window is null then
    raise exception 'fn_it_ceo_silence_watch: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  -- 21 Sep 2026: the "no page yet" test used to sit in this WHERE, so a report paged before its
  -- family had a decider was never offered to the decider again (13 stuck; see this file's header).
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent'
              and least(next_review_at, created_at + v_window) < now()
            order by id loop
    -- The CEO's answer comes before the founder's page (21 Sep 2026). A family this dispatcher does
    -- not know answers 'no decider for this family', and that string travels in the page below.
    begin
      v_dec := public.fn_ceo_decide_report(r.id);
    exception when others then
      v_dec := jsonb_build_object('ok', false, 'reason', 'decider raised: ' || sqlerrm);
    end;
    select status into v_status from public.support_ceo_report where id = r.id;
    if v_status <> 'sent' then n_answered := n_answered + 1; continue; end if;

    -- the founder hears about a report once; the CEO keeps being asked every tick
    continue when exists (select 1 from public.agent_actions a
                           where a.kind = 'handoff' and a.target_id = 'delivery.request:' || r.id);

    perform public.fn_seat_handoff('it_engineer', 'customer_support', 'delivery.request', 'support_ceo_report', r.id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
        'event', 'The CEO has not answered an IT report: ' || left(r.subject, 120),
        'detail', 'The IT engineer reported this to the CEO at '
                  || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai) and it was due an answer by '
                  || to_char(least(r.next_review_at, r.created_at + v_window) at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || E'. Nobody has answered.\n\n'
                  || 'Report: ' || r.subject || E'\n\nThe CEO''s decider said: ' || coalesce(v_dec ->> 'reason', 'nothing')
                  || E'.\n\nIt stays open until the CEO answers it. Reference: support_ceo_report ' || r.id || '.',
        'dedupe_key', 'it_ceo_silent:' || split_part(r.idempotency_key, ':', 1) || ':'
                      || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD')));
    n_told := n_told + 1;
  end loop;
  return jsonb_build_object('founder_told', n_told, 'ceo_answered_first', n_answered);
end $fn$;
revoke execute on function public.fn_it_ceo_silence_watch() from public, anon, authenticated;

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW. Every write happens inside an inner block that ends by raising
-- 'zz_probe_rollback': the ZZ DEMO notifications (@example.invalid, +9715000000XX), reports and the
-- "already paged" handoff are undone with that subtransaction while the definitions stand. The watch
-- is then called for real inside the block, so it also answers the live overdue reports -- and that,
-- too, is undone; the probe only reads the two ZZ DEMO reports' outcome.
create temp table if not exists zz_probe_verdict2 (verdict text, detail jsonb) on commit drop;
do $probe$
declare
  v_ok boolean := true; v_notes jsonb := '[]'::jsonb;
  v_tid bigint; v_nid bigint; v_rep bigint; v_rep2 bigint; v_req bigint; v_gone bigint;
  v_st text; v_st2 text; v_w jsonb; v_before int; v_after int;
begin
  select count(*) into v_before from public.support_ceo_report where status = 'sent';
  begin
    -- (a) an ALREADY-PAGED overdue report whose alert did reach the founder by email
    insert into public.notifications (type, kind, to_email, to_role, channel, subject, body, status, sent_at, requested_by)
    values ('founder_alert', 'it_new_bug', 'zz-demo-founder@example.invalid', 'founder', 'email', 'ZZ DEMO probe', 'ZZ DEMO', 'sent', now(), 'platform')
    returning id into v_tid;
    update public.notifications set provider_message_id = 'zz-demo-pmid' where id = v_tid;
    insert into public.notifications (type, kind, to_email, to_role, channel, to_phone, subject, body, status, sent_at, requested_by, created_at)
    select 'founder_alert', 'it_new_bug', 'zz-demo-founder@example.invalid', 'founder', 'whatsapp', '+971500000099', 'ZZ DEMO probe', 'ZZ DEMO', 'sent', now(), 'platform', created_at
      from public.notifications where id = v_tid
    returning id into v_nid;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id, created_at)
    values ('delivery_undelivered:zzprobe' || v_nid, 'it_engineer', 'elevated', 'ZZ DEMO a founder_alert did not arrive (sent_unconfirmed)',
            jsonb_build_object('rechecked', jsonb_build_object('notification_id', v_nid), 'result', 'sent_unconfirmed'), '[]'::jsonb,
            'probe', now() - interval '2 days', 'sent', 'ceo', now() - interval '2 days')
    returning id into v_rep;
    insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id)
    values ('it_engineer', 'handoff', 'done', 'ZZ DEMO probe page', jsonb_build_object('probe', true), 'support_ceo_report', 'delivery.request:' || v_rep);

    -- (b) a report whose request's subject notification no longer exists
    select coalesce(max(id), 0) + 1000000 into v_gone from public.notifications;
    insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id)
    values ('it_engineer', 'handoff', 'done', 'ZZ DEMO probe request',
            jsonb_build_object('subject_table', 'notifications', 'subject_id', v_gone::text, 'probe', true),
            'notifications', 'delivery.request:notification:' || v_gone)
    returning id into v_req;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id, created_at)
    values ('delivery_undelivered:zzprobe' || v_req, 'it_engineer', 'elevated', 'ZZ DEMO a founder_alert did not arrive (not_sent)',
            jsonb_build_object('request_id', v_req, 'result', 'not_sent',
                               'rechecked', jsonb_build_object('notification_id', null),
                               'support_evidence', jsonb_build_object('notification', null)), '[]'::jsonb,
            'probe', now() - interval '2 days', 'sent', 'ceo', now() - interval '2 days')
    returning id into v_rep2;

    v_w := public.fn_it_ceo_silence_watch();
    select status into v_st from public.support_ceo_report where id = v_rep;
    select status into v_st2 from public.support_ceo_report where id = v_rep2;
    v_notes := jsonb_build_object('already_paged_report', v_st, 'gone_subject_report', v_st2);
    if v_st is distinct from 'accepted' or v_st2 is distinct from 'accepted' then v_ok := false; end if;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then
      v_ok := false; v_notes := v_notes || jsonb_build_object('probe_raised', sqlerrm);
    end if;
  end;
  select count(*) into v_after from public.support_ceo_report where status = 'sent';
  if v_after <> v_before
     or exists (select 1 from public.support_ceo_report where idempotency_key like 'delivery_undelivered:zzprobe%')
     or exists (select 1 from public.notifications where to_email = 'zz-demo-founder@example.invalid') then
    v_ok := false; v_notes := v_notes || jsonb_build_object('left_a_trace', true);
  end if;
  insert into zz_probe_verdict2 values (case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, v_notes);
end
$probe$;

select verdict, detail from zz_probe_verdict2;
