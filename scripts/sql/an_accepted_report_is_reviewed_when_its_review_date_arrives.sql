-- AN ACCEPTED REPORT IS REVIEWED WHEN ITS REVIEW DATE ARRIVES.
--
-- Assigned: ceo (the answer), it_engineer (the watch). 22 Sep 2026, SEATS-01.
-- Founder, 14 Sep 2026: "nothing literally should ever be a one way communication."
--
-- ══ MEASURED, read-only against htdblwldjkcgjvmqkbeh, 22 Sep 2026 ══════════════════════════
--   select status, count(*) from public.support_ceo_report group by 1;
--     sent 5 | accepted 26 | completed 2258
--   All 26 'accepted' rows have next_review_at in the PAST (earliest 15 Sep, latest 22 Sep) —
--   every accepted report the estate holds is overdue its own review. fn_it_ceo_silence_watch,
--   the one routine that looks at an overdue report, selects `status = 'sent'` only, so an
--   accepted report's next_review_at is a date nothing reads. The three families:
--     12 delivery_undelivered:<action id>   a founder alert that was not confirmed delivered
--      6 dropbox_backup_escalation / _daily / backup_escalation   backup coverage
--      7 it_loop:<handoff id>                an IT finding parked at the learning gate
--     (+ 1 backup_escalation:28974)
--   'accepted' means the CEO answered; next_review_at is the promise to look again. Nobody did.
--
-- ══ WHAT THIS FILE CHANGES ═══════════════════════════════════════════════════════════════════
--   1. fn_it_accepted_report_review(p_dry_run): for every accepted report past its review date it
--      MEASURES THE CAUSE that report was about, per family:
--        delivery_undelivered  the notification named in verified_evidence — gone from
--                              public.notifications (can never be re-checked), or now carrying a
--                              provider id / provider_status delivered|read, or with a sent+
--                              confirmed twin, means the cause is gone.
--        backup families       public.fn_backup_coverage() — ok = the cause is gone. Called at
--                              most ONCE per run, and only when such a report is due.
--        it_loop               public.fn_it_loop_reverify() is the owner of that family and
--                              already completes an accepted report whose handoff is done; this
--                              calls it once and then re-reads the report.
--      Cause gone -> status 'completed' with completed_at and a completion_note carrying the
--      measurement. Cause still there -> next_review_at moves 24 h and the report is named in ONE
--      aggregate finding for the CEO.
--      A CLOSE IS NEVER ONE NUMBER: the return splits closed_measured (the cause was measured
--      gone) from closed_unmeasurable (its subject is not there to re-check — the report names no
--      notification, or the notification row is gone), and the completion_note says which. On the
--      dry run of 22 Sep that is 11 measured and 8 unmeasurable, and an auditor reading a
--      completion record must not be told the absence of evidence was evidence.
--   2. ONE finding, not one per report: 'monitor:ceo_accepted_report_review_overdue', owner_seat
--      ceo, listing every report still unanswered. 20 separate findings in a tick is the 15 Sep
--      alert storm (~50 founder emails) rebuilt by hand.
--   3. fn_it_ceo_silence_watch calls it at the end of its own run and returns its counts, so this
--      needs no new schedule: the watch already runs on the heartbeat
--      (the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql).
--      Its 'sent' loop, its page, its dedupe key and its window are unchanged.
--
-- NOT CHANGED: fn_ceo_decide_report and every family decider, fn_it_loop_reverify, the digest.
-- A report is never closed because it is old — only because its cause was measured gone.
--
--   node scripts/apply_sql.mjs scripts/sql/an_accepted_report_is_reviewed_when_its_review_date_arrives.sql --apply --ddl

-- ── 1. the review ────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_accepted_report_review(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  rep public.support_ceo_report;
  v_family text; v_gone boolean; v_note text;
  -- HOW a report closed, never collapsed into one number (22 Sep 2026, review of PR #852):
  --   'measured'     the cause was measured GONE — a provider id, a delivered status, a confirmed
  --                  twin, coverage ok, a closed handoff.
  --   'unmeasurable' the cause can never be re-checked because its subject is not there: the
  --                  report names no notification, or the notification row no longer exists. That
  --                  is the ABSENCE of evidence, not evidence, and an auditor reading the
  --                  completion record must be able to tell the two apart.
  v_kind text;
  v_closed_measured int := 0; v_closed_unmeasurable int := 0;
  v_cov jsonb; v_cov_read boolean := false; v_loop_run boolean := false;
  v_nid bigint; v_notif public.notifications; v_twin public.notifications;
  v_status text; v_open bigint[] := '{}'; v_closed int := 0; v_due int := 0;
begin
  for rep in select * from public.support_ceo_report
              where status = 'accepted' and next_review_at is not null and next_review_at < now()
              order by id loop
    v_due := v_due + 1;
    v_family := split_part(rep.idempotency_key, ':', 1);
    v_gone := false; v_note := null; v_kind := null;

    if v_family = 'delivery_undelivered' then
      v_nid := coalesce((rep.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                        (rep.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
      if v_nid is null then
        v_gone := true; v_kind := 'unmeasurable';
        v_note := 'the report names no notification at all, so its delivery can never be re-checked; '
                  || 'nothing is left to deliver and nothing can recur under this id.';
      else
        select * into v_notif from public.notifications where id = v_nid;
        if v_notif.id is null then
          v_gone := true; v_kind := 'unmeasurable';
          v_note := 'notification ' || v_nid || ' no longer exists in public.notifications, so its delivery can never be re-checked.';
        elsif coalesce(btrim(v_notif.provider_message_id), '') <> ''
              or v_notif.provider_status in ('delivered', 'read') then
          v_gone := true; v_kind := 'measured';
          v_note := 'notification ' || v_nid || ' (' || v_notif.channel || ') now carries provider id '
                    || coalesce(v_notif.provider_message_id, '-') || ' and provider status '
                    || coalesce(v_notif.provider_status, '-') || ': the alert reached the founder.';
        else
          select * into v_twin from public.notifications t
           where t.channel = 'email' and t.type = v_notif.type and t.created_at = v_notif.created_at
             and t.to_role is not distinct from v_notif.to_role and t.id <> v_notif.id and t.status = 'sent'
           order by t.id limit 1;
          if v_twin.id is not null and coalesce(btrim(v_twin.provider_message_id), '') <> '' then
            v_gone := true; v_kind := 'measured';
            v_note := 'notification ' || v_nid || ' is still unconfirmed on ' || v_notif.channel
                      || ', but its email twin ' || v_twin.id || ' was sent and confirmed ('
                      || v_twin.provider_message_id || '): the alert reached the founder.';
          end if;
        end if;
      end if;

    elsif v_family in ('dropbox_backup_escalation', 'dropbox_backup_daily', 'backup_escalation') then
      if not v_cov_read then
        -- once per run: this reads the whole backup queue and rolls back its own enqueue probe
        begin v_cov := public.fn_backup_coverage();
        exception when others then v_cov := jsonb_build_object('ok', null, 'error', left(sqlerrm, 200)); end;
        v_cov_read := true;
      end if;
      if coalesce((v_cov ->> 'ok')::boolean, false) then
        v_gone := true; v_kind := 'measured';
        v_note := 'backup coverage measured ok at review (' || left(v_cov::text, 400) || ').';
      end if;

    elsif v_family = 'it_loop' then
      if not p_dry_run and not v_loop_run then
        begin perform public.fn_it_loop_reverify(); exception when others then null; end;
        v_loop_run := true;
      end if;
      select status into v_status from public.support_ceo_report where id = rep.id;
      if v_status = 'completed' then v_closed := v_closed + 1; v_closed_measured := v_closed_measured + 1; continue; end if;
      -- still accepted: its handoff has not closed, so the finding behind it is still open
    end if;

    if v_gone then
      v_closed := v_closed + 1;
      if v_kind = 'unmeasurable' then v_closed_unmeasurable := v_closed_unmeasurable + 1;
      else v_closed_measured := v_closed_measured + 1; end if;
      if not p_dry_run then
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer reviewed this accepted report at its review date ('
                 || to_char(now() at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai, closed as ' || v_kind || '): ' || v_note
         where id = rep.id and status = 'accepted';
      end if;
    else
      v_open := v_open || rep.id;
      if not p_dry_run then
        update public.support_ceo_report set next_review_at = now() + interval '24 hours' where id = rep.id;
      end if;
    end if;
  end loop;

  -- ONE finding for everything still unanswered, named by id so the CEO can answer them.
  if cardinality(v_open) > 0 and not p_dry_run then
    perform public.fn_it_engineer_finding_upsert(
      'monitor:ceo_accepted_report_review_overdue',
      cardinality(v_open) || ' accepted CEO report(s) passed their review date and their cause is still there',
      'public.support_ceo_report (status accepted, next_review_at past)', 'agent_facing', cardinality(v_open),
      jsonb_build_object('report_ids', to_jsonb(v_open), 'owner_seat', 'ceo',
        'measured', 'the cause each report was about was measured at review and is still present; each review date moved 24 h',
        'fix', 'the CEO answers each report — complete it with what changed, or say what is still being done and why'),
      '{}'::text[], array['what the CEO intends to do about each report still open'], 'fn_it_accepted_report_review');
  end if;

  return jsonb_build_object('due', v_due, 'closed', v_closed,
                            'closed_measured', v_closed_measured, 'closed_unmeasurable', v_closed_unmeasurable,
                            'still_open', cardinality(v_open),
                            'open_ids', to_jsonb(v_open), 'dry_run', p_dry_run,
                            'coverage_read', v_cov_read, 'coverage_ok', v_cov -> 'ok');
end $fn$;
revoke execute on function public.fn_it_accepted_report_review(boolean) from public, anon, authenticated;

comment on function public.fn_it_accepted_report_review(boolean) is
  'Reviews every accepted support_ceo_report whose next_review_at has passed: measures the cause per family (delivery_undelivered / backup / it_loop), completes the report when the cause is gone, otherwise moves the review 24 h and names it in one finding for the CEO. Called by fn_it_ceo_silence_watch. p_dry_run measures and writes nothing. 22 Sep 2026, it_engineer (SEATS-01).';

-- ── 2. the watch calls it, so this needs no new schedule ────────────────────────────────────
-- Identical to the_ceo_answers_every_overdue_it_report_even_one_the_founder_was_already_told_about.sql
-- except for the two marked lines at the end.
create or replace function public.fn_it_ceo_silence_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n_told int := 0; n_answered int := 0; v_window interval; v_dec jsonb; v_status text;
        v_review jsonb;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  if v_window is null then
    raise exception 'fn_it_ceo_silence_watch: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  for r in select * from public.support_ceo_report
            where source_agent = 'it_engineer' and status = 'sent'
              and least(next_review_at, created_at + v_window) < now()
            order by id loop
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
  -- ADDED 22 Sep 2026 (SEATS-01): an ACCEPTED report is reviewed too. Swallowed on purpose — the
  -- silence watch must keep answering 'sent' reports even if the review pass hits a bad row.
  begin v_review := public.fn_it_accepted_report_review();
  exception when others then v_review := jsonb_build_object('error', left(sqlerrm, 300)); end;
  return jsonb_build_object('founder_told', n_told, 'ceo_answered_first', n_answered, 'accepted_review', v_review);
end $fn$;
revoke execute on function public.fn_it_ceo_silence_watch() from public, anon, authenticated;

-- ══ DRY-RUN PROBE ═══════════════════════════════════════════════════════════════════════════
-- This file defines routines, so the probe MUST NOT raise: a raise here would roll the definitions
-- back with it. It writes nothing (p_dry_run) and reaches nobody: no handoff, no notification, no
-- finding. It prints what the review would do the moment this file is applied.
do $$
declare v jsonb; v_before int; v_after int;
begin
  select count(*) into v_before from public.support_ceo_report where status = 'accepted';
  v := public.fn_it_accepted_report_review(true);
  select count(*) into v_after from public.support_ceo_report where status = 'accepted';
  if v_before <> v_after then
    raise exception 'the dry run changed % accepted report(s) — it must write nothing', v_before - v_after;
  end if;
  raise notice 'DRY RUN: % accepted report(s) past review, % would be completed now, % still open (ids %); coverage ok=%',
    v ->> 'due', v ->> 'closed', v ->> 'still_open', v ->> 'open_ids', coalesce(v ->> 'coverage_ok', 'not read');
end $$;
