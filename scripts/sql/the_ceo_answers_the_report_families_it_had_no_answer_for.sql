-- THE CEO ANSWERS THE REPORT FAMILIES IT HAD NO ANSWER FOR, AND THE FOUNDER HEARS A FAMILY ONCE A DAY.
--
-- Assigned: ceo (the two deciders), it_engineer (the silence watch). 21 Sep 2026.
--
-- ══ WHAT WAS MEASURED, 21 Sep 2026, against htdblwldjkcgjvmqkbeh (read-only) ═══════════════════
--
-- 8 of the 25 IT emails the founder received between 18 and 21 Sep say "The CEO has not answered an
-- IT report", plus 9 more lines of the same inside two digests. Every it_engineer report the CEO
-- DID answer in the window (56 rows, status accepted/completed) has an idempotency_key of the form
-- it_loop:<handoff> or it_daily:<day> or backup_escalation:<handoff>: fn_ceo_it_escalation_decide,
-- fn_it_daily_line and fn_ceo_backup_escalation_decide answer those. Every report still 'sent' past
-- its review window belongs to one of TWO families no routine in public.* answers:
--   dropbox_backup_escalation:<day>   3 reports (1702, 2444, 2501) — fn_backup_watch files one per
--                                     day while fn_backup_coverage fails; the arm failing was always
--                                     refile_not_verified_in_48h (two backup.refile handoffs pending
--                                     since 15 and 18 Sep, see the sibling file on abandoned sources).
--   delivery_undelivered:<request>    10 reports (1984-1992, 2146, 2485, 2532, 2571) —
--                                     fn_originator_checks_delivery files one when a founder alert's
--                                     WhatsApp twin comes back not_sent (queued for hours on 17 Sep
--                                     while send_whatsapp was starved — fixed by #745's plan) or
--                                     sent_unconfirmed: every WhatsApp row in the window is 'sent' with
--                                     provider_message_id NULL (24 of 24), because send_whatsapp never
--                                     stored Twilio's SID. The email twin of every one of them was sent
--                                     and confirmed (has a provider id, 0 of 25 without).
-- fn_it_ceo_silence_watch then pages the founder once per report id ('it_ceo_silent:<id>'), so a
-- family with no decider becomes one founder email per report per day, for ever.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- 1. fn_ceo_delivery_undelivered_decide(report): the CEO reads the notification the report is about.
--      sent + provider id ..................... accept: the provider confirmed it.
--      sent, no provider id, WhatsApp ......... accept when the email twin (same type, same
--                                               created_at, channel email) is sent: the alert reached
--                                               him; the WhatsApp handed to Twilio without a SID is
--                                               recorded, and send_whatsapp stores the SID from the
--                                               same PR so the case cannot recur.
--      failed / skipped / suppressed .......... accept when the email twin is sent (the compensating
--                                               control worked and is on the record); otherwise NOT
--                                               decided — that is a founder alert nobody delivered,
--                                               and the silence watch takes it to him.
--      queued / held / anything else .......... not decided; re-read next tick.
-- 2. fn_ceo_backup_coverage_decide(report): the CEO runs the remedy it owns — fn_it_backup_recheck()
--    — then re-measures fn_backup_coverage() and accepts with the measurement as the receipt. The
--    per-file remediation (backup_escalation:<handoff>) is untouched and still carries the work.
-- 3. fn_ceo_decide_report(report) dispatches on the idempotency_key family, and answers 'no decider'
--    for a family this file does not know: a future family with no answer is visible as that string
--    in the founder's page, not as silence.
-- 4. fn_it_ceo_silence_watch gives the CEO its answer FIRST (fn_ceo_decide_report) and pages the
--    founder only for a report still 'sent' after that. The page's dedupe key is now
--    it_ceo_silent:<family>:<Dubai day> — one email per family per day, however many reports it
--    holds — where it was one per report id. The 4-hour window and the handoff shape are unchanged.
--    Body otherwise byte-identical to the_it_learning_gate_closes_what_the_playbook_already_knows.sql.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: fn_ceo_it_escalation_decide, fn_ceo_backup_escalation_decide,
-- fn_originator_checks_delivery (it still files the report: a founder alert that may not have arrived
-- is still reported, it is now also ANSWERED), the digest, founder_mail_policy.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_answers_the_report_families_it_had_no_answer_for.sql --apply --ddl

-- ── 1. A FOUNDER ALERT THAT "DID NOT ARRIVE" ────────────────────────────────────────────────────
create or replace function public.fn_ceo_delivery_undelivered_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; n public.notifications; twin public.notifications; v_receipt text;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  select * into n from public.notifications
   where id = coalesce((r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                       (r.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
  if n.id is null then
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

-- ── 2. THE DAILY BACKUP-COVERAGE REPORT ─────────────────────────────────────────────────────────
create or replace function public.fn_ceo_backup_coverage_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; v_re jsonb; v_cov jsonb; v_receipt text;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  v_re  := public.fn_it_backup_recheck();
  v_cov := public.fn_backup_coverage();
  v_receipt := 'ceo: ran the IT backup re-check (closed ' || coalesce(v_re ->> 'closed', '0') || ', second refiles '
               || coalesce(v_re ->> 'second_refiles', '0') || ', escalated ' || coalesce(v_re ->> 'escalated', '0')
               || '); coverage now ok=' || coalesce(v_cov ->> 'ok', '?') || ', failing=' || coalesce(v_cov ->> 'failing', '[]')
               || ', refiles open past 48h=' || coalesce(v_cov ->> 'refiles_open_past_48h', '?')
               || ', not done after 48h=' || coalesce(v_cov ->> 'not_done_after_48h', '?')
               || '. Each file still missing is carried by its own backup_escalation report.';
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo',
         completed_at = case when coalesce((v_cov ->> 'ok')::boolean, false) then now() else completed_at end,
         completion_note = case when coalesce((v_cov ->> 'ok')::boolean, false) then 'coverage measured ok after the re-check' else completion_note end
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'recheck', v_re, 'coverage', v_cov);
end $fn$;
revoke execute on function public.fn_ceo_backup_coverage_decide(bigint) from public, anon, authenticated;

-- ── 3. ONE DOOR: THE FAMILY DECIDES THE DECIDER ─────────────────────────────────────────────────
create or replace function public.fn_ceo_decide_report(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_key text; v_family text;
begin
  select idempotency_key into v_key from public.support_ceo_report where id = p_report_id;
  if v_key is null then return jsonb_build_object('ok', false, 'reason', 'no report ' || p_report_id); end if;
  v_family := split_part(v_key, ':', 1);
  return case v_family
    when 'backup_escalation'         then public.fn_ceo_backup_escalation_decide(p_report_id)
    when 'dropbox_backup_escalation' then public.fn_ceo_backup_coverage_decide(p_report_id)
    when 'delivery_undelivered'      then public.fn_ceo_delivery_undelivered_decide(p_report_id)
    else jsonb_build_object('ok', false, 'report_id', p_report_id, 'family', v_family, 'reason', 'no decider for this family')
  end;
end $fn$;
revoke execute on function public.fn_ceo_decide_report(bigint) from public, anon, authenticated;

-- ── 4. THE SILENCE WATCH LETS THE CEO ANSWER FIRST, AND PAGES A FAMILY ONCE A DAY ─────────────
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
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent'
              and least(next_review_at, created_at + v_window) < now()
              and not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.target_id = 'delivery.request:' || support_ceo_report.id)
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
-- DDL above, so the verdict is a ROW and every write below is undone by the block itself. It creates
-- ZZ DEMO reports and notifications addressed to @example.invalid, decides them, reads the outcome,
-- deletes them, and asserts nothing is left. No real row is read for a decision.
create temp table if not exists it_probe_verdict (verdict text) on commit drop;
do $probe$
declare
  v_nid bigint; v_tid bigint; v_rep bigint; v_rep2 bigint; v_out jsonb; v_out2 jsonb; v_st text; v_st2 text;
  v_left int; v_fam text;
begin
  -- a WhatsApp founder alert 'sent' with no provider id, and its email twin sent and confirmed
  insert into public.notifications (type, kind, to_email, to_role, channel, subject, body, status, sent_at, requested_by)
  values ('founder_alert', 'it_new_bug', 'zz-demo-founder@example.invalid', 'founder', 'email', 'ZZ DEMO probe', 'ZZ DEMO', 'sent', now(), 'platform')
  returning id into v_tid;
  update public.notifications set provider_message_id = 'zz-demo-pmid' where id = v_tid;
  insert into public.notifications (type, kind, to_email, to_role, channel, to_phone, subject, body, status, sent_at, requested_by, created_at)
  select 'founder_alert', 'it_new_bug', 'zz-demo-founder@example.invalid', 'founder', 'whatsapp', '+971500000099', 'ZZ DEMO probe', 'ZZ DEMO', 'sent', now(), 'platform', created_at
    from public.notifications where id = v_tid
  returning id into v_nid;
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
  values ('delivery_undelivered:zzprobe' || v_nid, 'it_engineer', 'elevated', 'ZZ DEMO a founder_alert did not arrive (sent_unconfirmed)',
          jsonb_build_object('rechecked', jsonb_build_object('notification_id', v_nid), 'result', 'sent_unconfirmed'), '[]'::jsonb,
          'probe', now() - interval '1 minute', 'sent', 'ceo')
  returning id into v_rep;
  v_out := public.fn_ceo_decide_report(v_rep);
  select status into v_st from public.support_ceo_report where id = v_rep;

  -- a family nobody decides: must be answered 'no decider', and left 'sent'
  insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions, requested_outcome, next_review_at, status, owner_role_id)
  values ('zz_probe_family:' || v_nid, 'it_engineer', 'elevated', 'ZZ DEMO unknown family', jsonb_build_object('probe', true, 'note', 'ZZ DEMO'), '[]'::jsonb, 'probe', now() - interval '1 minute', 'sent', 'ceo')
  returning id into v_rep2;
  v_out2 := public.fn_ceo_decide_report(v_rep2);
  select status into v_st2 from public.support_ceo_report where id = v_rep2;
  v_fam := v_out2 ->> 'reason';

  delete from public.support_ceo_report where id in (v_rep, v_rep2);
  delete from public.notifications where id in (v_nid, v_tid);
  select count(*) into v_left from public.notifications where to_email = 'zz-demo-founder@example.invalid';
  select v_left + count(*) into v_left from public.support_ceo_report where subject like 'ZZ DEMO%';

  insert into it_probe_verdict values (
    case when coalesce((v_out ->> 'ok')::boolean, false) and v_st = 'accepted'
          and not coalesce((v_out2 ->> 'ok')::boolean, true) and v_st2 = 'sent' and v_fam = 'no decider for this family'
          and v_left = 0
         then 'PROBE OK: a sent_unconfirmed WhatsApp founder alert with a confirmed email twin is accepted by the CEO with a receipt; '
              || 'an unknown family answers "no decider for this family" and stays sent; 0 probe rows left behind.'
         else 'PROBE FAILED: decided=' || coalesce(v_out::text, 'null') || ' status=' || coalesce(v_st, 'null')
              || ' unknown_family=' || coalesce(v_out2::text, 'null') || ' status2=' || coalesce(v_st2, 'null')
              || ' rows_left=' || v_left end);
end $probe$;
select verdict from it_probe_verdict;
