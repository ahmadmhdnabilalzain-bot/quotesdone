-- THE CEO ANSWERS EVERY REPORT IT IS SENT, THE DAY IT ARRIVES — A FAMILY WITH NO DECIDER IS STILL ANSWERED.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 1 (ledger 983; founder instructions 29 and 642:
-- "the CEO ... knows every task", IT email noise). Approved job description: "Answer every IT report the same day."
--
-- ══ MEASURED, read-only against htdblwldjkcgjvmqkbeh, 24 Sep 2026 ══════════════════════════════════════
--   select split_part(idempotency_key,':',1), status, count(*) from public.support_ceo_report
--    where status <> 'completed' group by 1,2;
--     it_backup_heartbeat  sent 1      (report 3470, 21 Sep 23:31 UTC, review date 22 Sep, never answered)
--     dropbox_backup_daily sent 1      (report 4541, 22 Sep, "NOTHING IS REQUESTED", never answered)
--     delivery_undelivered sent 2      (reports 5309 / 5322, from customer_support, past their review date)
--     dropbox_backup_daily accepted 1, it_loop accepted 31
--   fn_ceo_decide_report (the_ceo_answers_the_report_families_it_had_no_answer_for.sql) knows three families:
--   backup_escalation, dropbox_backup_escalation, delivery_undelivered. For it_backup_heartbeat and
--   dropbox_backup_daily it answers {ok:false, reason:'no decider for this family'}, the report stays 'sent',
--   and fn_it_ceo_silence_watch pages the founder "The CEO has not answered an IT report" — 14 such mails
--   between 17 and 21 Sep (notifications, kind it_new_bug). A decider that returns ok:false (a notification the
--   report does not name) also left its report 'sent'. And the CEO only ever answered when the IT watch asked,
--   after the 4-hour window, so an answer "the same day" was an accident of the watch's clock.
--
-- ══ WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════
--   1. fn_ceo_backup_heartbeat_decide: the heartbeat report says "the daily Dropbox check has not run". Its cause
--      is measured by the check's own product: a dropbox_backup_daily report created AFTER the heartbeat report
--      means the check ran again -> completed, measured. Otherwise the CEO accepts it, names the chain the IT
--      engineer must repair (the report's own requested_outcome), and re-measures it every hour (duty below).
--   2. fn_ceo_backup_daily_decide: the daily report requests nothing (its requested_outcome says so in words the
--      IT engineer wrote). The CEO completes it as noted. A backup case that is failing reaches the CEO as its own
--      backup_escalation / dropbox_backup_escalation report, which keeps its decider.
--   3. fn_ceo_report_default_decide: ANY report still 'sent' after its family decider — a family nobody has coded
--      yet, or a decider that could not decide — is ACCEPTED with a receipt naming what the decider said, the seat
--      that carries the work, and a review in 24 hours. The IT engineer's accepted-report review
--      (fn_it_accepted_report_review) re-measures it on that date; one it cannot measure stays in its one finding
--      addressed to the CEO. A report is never closed by this path: accepting is an answer, not a verdict.
--   4. fn_ceo_decide_report routes the two new families and falls back to (3) whenever the report is still 'sent'.
--   5. ceo.report_answer, a CEO duty every hour (fn_ceo_report_answer_sweep): answers every 'sent' report of every
--      source the hour it arrives — not only IT's, not only after the watch's window — and re-measures accepted
--      heartbeat reports. The IT silence watch still runs and still pages when the CEO is silent; after this it
--      finds nothing to page about.
--
-- NOT CHANGED: fn_it_ceo_silence_watch, fn_it_accepted_report_review, the three existing family deciders, the
-- founder's mail policy. Nothing here calls a model or reads a report's text for meaning: families are keys the
-- reporting routine wrote.
--
-- Pending: scripts/sql/pending/the_ceo_answers_every_report_it_is_sent_the_day_it_arrives.txt.
-- Prevented by: scripts/checks/the_ceo_job_description_gaps_are_closed.test.mjs.

-- ── 1. the daily Dropbox check has not run ────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_backup_heartbeat_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; v_after public.support_ceo_report;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status not in ('sent', 'accepted') then
    return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id);
  end if;
  -- the check's own product, written after the alarm: the daily check ran again
  select * into v_after from public.support_ceo_report
   where idempotency_key like 'dropbox\_backup\_daily:%' and created_at > r.created_at order by created_at limit 1;
  if v_after.id is not null then
    update public.support_ceo_report
       set status = 'completed', completed_at = now(), owner_role_id = 'ceo',
           accepted_at = coalesce(accepted_at, now()),
           acceptance_receipt = coalesce(acceptance_receipt, 'ceo: measured the daily Dropbox check'),
           completion_note = 'ceo: the daily Dropbox check ran again after this alarm: it filed report ' || v_after.id
             || ' (' || v_after.idempotency_key || ') at ' || to_char(v_after.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
             || ' Dubai. Closed as measured.'
     where id = r.id;
    return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'completed', 'evidence_report', v_after.id);
  end if;
  if r.status = 'sent' then
    update public.support_ceo_report
       set status = 'accepted', accepted_at = now(), owner_role_id = 'it_engineer', next_review_at = now() + interval '24 hours',
           acceptance_receipt = 'ceo: accepted. The daily Dropbox check has filed no report since this alarm, so the cause is still there. '
             || 'it_engineer repairs the chain it named: ' || left(coalesce(r.requested_outcome, 'the daily check'), 400)
             || ' The CEO re-measures it every hour (ceo.report_answer) and closes it when the check reports again.'
     where id = r.id;
  end if;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'accepted', 'cause', 'no daily report since the alarm');
end $fn$;
revoke execute on function public.fn_ceo_backup_heartbeat_decide(bigint) from public, anon, authenticated;

-- ── 2. the daily Dropbox confirmation (requests nothing) ──────────────────────────────────────────────
create or replace function public.fn_ceo_backup_daily_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  update public.support_ceo_report
     set status = 'completed', accepted_at = now(), completed_at = now(), owner_role_id = 'ceo',
         acceptance_receipt = 'ceo: noted the day''s backup position',
         completion_note = 'ceo: noted. The IT engineer''s daily confirmation requests nothing; a backup case still failing after two '
           || 'refiles or 48 hours reaches the CEO as its own backup escalation report, which has its own decider. Position noted: '
           || left(r.subject, 600)
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'completed');
end $fn$;
revoke execute on function public.fn_ceo_backup_daily_decide(bigint) from public, anon, authenticated;

-- ── 3. every other report still unanswered: accepted, owned, reviewed in 24 hours ─────────────────────
create or replace function public.fn_ceo_report_default_decide(p_report_id bigint, p_why text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; v_owner text;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  -- the seat that carries the work: the report's own owner when it names a live seat other than the CEO, else its source
  select o.role_id into v_owner from public.org_role o
   where o.status = 'active' and o.role_id = any(array[nullif(r.owner_role_id, 'ceo'), r.source_agent]) order by o.role_id = r.source_agent limit 1;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), next_review_at = now() + interval '24 hours',
         owner_role_id = coalesce(v_owner, r.owner_role_id),
         acceptance_receipt = 'ceo: accepted on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai. '
           || coalesce(v_owner, 'the reporting seat') || ' carries: ' || left(coalesce(r.requested_outcome, r.subject), 400)
           || '. No coded decider could close it (' || left(coalesce(p_why, 'no reason given'), 300) || '), so it is reviewed again at '
           || to_char((now() + interval '24 hours') at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai and closed only when its cause is measured gone.'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'decision', 'accepted', 'owner', coalesce(v_owner, r.owner_role_id), 'why', p_why);
end $fn$;
revoke execute on function public.fn_ceo_report_default_decide(bigint, text) from public, anon, authenticated;

-- ── 4. one door: the family decides the decider, and nothing leaves it unanswered ─────────────────────
create or replace function public.fn_ceo_decide_report(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_key text; v_family text; v jsonb;
begin
  select idempotency_key into v_key from public.support_ceo_report where id = p_report_id;
  if v_key is null then return jsonb_build_object('ok', false, 'reason', 'no report ' || p_report_id); end if;
  v_family := split_part(v_key, ':', 1);
  v := case v_family
    when 'backup_escalation'         then public.fn_ceo_backup_escalation_decide(p_report_id)
    when 'dropbox_backup_escalation' then public.fn_ceo_backup_coverage_decide(p_report_id)
    when 'delivery_undelivered'      then public.fn_ceo_delivery_undelivered_decide(p_report_id)
    when 'it_backup_heartbeat'       then public.fn_ceo_backup_heartbeat_decide(p_report_id)
    when 'dropbox_backup_daily'      then public.fn_ceo_backup_daily_decide(p_report_id)
    else jsonb_build_object('ok', false, 'report_id', p_report_id, 'family', v_family, 'reason', 'no decider for this family')
  end;
  -- A decider that answered 'undecided' refused on purpose (a founder alert with no confirmed delivery on any channel
  -- is "not the CEO's to wave through"): it stays 'sent' so the IT silence watch still tells the founder.
  if exists (select 1 from public.support_ceo_report where id = p_report_id and status = 'sent')
     and coalesce(v ->> 'reason', '') not like 'undecided%' then
    v := public.fn_ceo_report_default_decide(p_report_id, v_family || ': ' || coalesce(v ->> 'reason', 'the decider left it open'))
         || jsonb_build_object('family_answer', v);
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_ceo_decide_report(bigint) from public, anon, authenticated;

-- ── 5. the CEO answers the hour a report arrives, and re-measures what it accepted ────────────────────
create or replace function public.fn_ceo_report_answer_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v jsonb; n_answered int := 0; n_closed int := 0; n_failed int := 0; v_errors jsonb := '[]'::jsonb;
begin
  for r in select id from public.support_ceo_report where status = 'sent' order by id limit 200 loop
    begin
      v := public.fn_ceo_decide_report(r.id);
      n_answered := n_answered + (coalesce((v ->> 'ok')::boolean, false))::int;
    exception when others then
      n_failed := n_failed + 1;
      v_errors := v_errors || jsonb_build_object('report_id', r.id, 'error', left(sqlerrm, 200));
    end;
  end loop;
  for r in select id from public.support_ceo_report
            where status = 'accepted' and idempotency_key like 'it\_backup\_heartbeat:%' order by id loop
    v := public.fn_ceo_backup_heartbeat_decide(r.id);
    n_closed := n_closed + (v ->> 'decision' = 'completed')::int;
  end loop;
  -- a report the CEO could not answer is a finding, not a silence: the IT watch would page the founder for it
  if n_failed > 0 then
    perform public.fn_it_engineer_finding_upsert('ceo:report_answer_failed',
      n_failed || ' report(s) to the CEO raised in their decider and stay unanswered',
      'public.fn_ceo_report_answer_sweep', 'agent_facing', n_failed,
      jsonb_build_object('errors', v_errors, 'owner_seat', 'ceo'), '{}'::text[], array['why each decider raised'], 'ceo');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'every report to the CEO was answered (fn_ceo_report_answer_sweep)'
     where issue_key = 'ceo:report_answer_failed' and closed_at is null;
  end if;
  return jsonb_build_object('answered', n_answered, 'failed', n_failed, 'heartbeat_closed', n_closed,
    'still_sent', (select count(*) from public.support_ceo_report where status = 'sent'));
end $fn$;
revoke execute on function public.fn_ceo_report_answer_sweep() from public, anon, authenticated;
grant execute on function public.fn_ceo_report_answer_sweep() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.report_answer', 'ceo', interval '1 hour', 'fn_ceo_report_answer_sweep',
   'Every report sent to the CEO is answered the hour it arrives (decided, accepted with an owner and a review date, or closed as measured); accepted heartbeat reports are re-measured.',
   'scripts/sql/the_ceo_answers_every_report_it_is_sent_the_day_it_arrives.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
