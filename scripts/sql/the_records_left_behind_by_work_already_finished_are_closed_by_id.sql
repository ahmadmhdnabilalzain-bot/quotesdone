-- THE RECORDS LEFT BEHIND BY WORK ALREADY FINISHED ARE CLOSED BY ID.
-- Assigned: it_engineer. 22 September 2026.
--
-- This file changes DATA ONLY. It defines no routine, creates no table, and every statement names the
-- exact rows it touches — by primary key, or by a predicate that cannot widen (a date strictly before
-- today). NOTHING here is closed by matching a title: on 15 Sep an ilike sweep closed a Stripe finding
-- that was never fixed, and that is the failure this file is written to not repeat.
--
-- ══ WHAT IS CLOSED, AND WHAT WAS MEASURED FIRST (production, 22 Sep 2026 ~17:50Z, read-only) ══════
--
-- 1. DEAD LETTERS 141 AND 142 (UNSOLVED-07). Both were written by fn_action_invoke_collect at
--    2026-09-03 20:29:00Z, kind 'incident_fix', payload {"executor":"os_incidents","http_status":403,
--    "body":"{\"error\":\"forbidden\"}"}, attempts 1, resolved_at null. The os_incidents executor was
--    REMOVED on 7 Sep 2026 when the founder dismantled the organisation ("remove everything except the
--    company knowledge, terms and conditions and website related stuff and my decisions"), so there is
--    nothing left to retry them against and nothing left that could produce a third. They are the only
--    two unresolved rows in public.dead_letter (measured: 2 of 2).
--    BEFORE: dead_letter unresolved = 2 (ids 141, 142).  AFTER: 0.
--
-- 2. PAST-DAY INVITE PLANS STILL 'pending' (UNSOLVED-10). fn_supplier_invites_plan writes one row a day
--    with status 'approved' when the campaign is open and 'pending' when it is held. The founder's hold
--    (app_secrets.supplier_outreach_golive = false) has never been lifted, so a 'pending' row for a day
--    that has passed is not a plan waiting to run — that day is over and its batch will never be sent.
--    Left as 'pending' it reads as a queue backing up. 'held' says what actually happened.
--    BEFORE: 6 rows with status 'pending' and day < today (2026-09-03, -04, -05, -06, -07 and -21; each
--    planned 50, sent 0).  AFTER: 0 such rows; the same 6 rows read 'held'. TODAY'S row is deliberately
--    NOT touched — the predicate is `day < (now() at time zone 'Asia/Dubai')::date`, so a plan that could
--    still run today keeps its status, and tomorrow's planner writes its own row as it always has.
--
-- 3. THE FOUR CEO REPORTS 3075, 3076, 3084 AND 3085 (UNSOLVED-06). Each reads "A supplier_invite for the
--    supplier did not arrive (not_sent)". Measured: their requests (agent_actions 42578, 42579, 42595,
--    42596) each carry evidence.queued = true and a notification id (36988, 36989, 37002, 37003), and
--    none of those notification rows exists any more — every one addressed a
--    zz-demo-supplier-invite-…@example.invalid fixture and the demo hygiene sweep deleted them between
--    19:11-19:15Z and the watch tick at 19:30Z on 21 Sep. So support DID queue each message; its record
--    was removed afterwards, and the watch reported the absence as "nothing was queued".
--    The classifier is fixed in every_whatsapp_says_whether_it_arrived.sql (a queued row that no longer
--    exists answers 'record_removed', and a message held by the founder's own switch answers 'held';
--    neither escalates). These four predate that fix, so they are closed here BY ID with the finding
--    written into the completion note. No other report is touched, and no title is matched.
--    BEFORE: these 4 at status 'sent', completed_at null.  AFTER: 4 'completed' with the note below.
--
-- ══ NOT DONE HERE ════════════════════════════════════════════════════════════════════════════════
-- Nothing is deleted. No notification, agent_action or finding is back-dated. The 33 WhatsApp rows with
-- no provider_message_id are marked 'unrecorded' by their own subject's file
-- (every_whatsapp_says_whether_it_arrived.sql owns the provider_status vocabulary), not here.
--
--   node scripts/apply_sql.mjs scripts/sql/the_records_left_behind_by_work_already_finished_are_closed_by_id.sql --apply

-- ── 1. THE TWO DEAD LETTERS ──────────────────────────────────────────────────────────────────────
update public.dead_letter
   set resolved_at = now(),
       resolved_by = 'it_engineer',
       resolution  = 'Closed 22 Sep 2026 by it_engineer: the incident_fix executor (os_incidents) was removed on '
                     || '7 Sep 2026 when the founder dismantled the organisation, so this 403 cannot be retried and '
                     || 'cannot recur. No work is outstanding behind these two rows.'
 where id in (141, 142)
   and resolved_at is null;

-- ── 2. THE PAST-DAY INVITE PLANS ─────────────────────────────────────────────────────────────────
update public.invite_schedule
   set status = 'held',
       note   = coalesce(note, '') || '; held: the day passed with the campaign still closed '
                || '(app_secrets.supplier_outreach_golive = false). Marked held by it_engineer on 22 Sep 2026 '
                || 'so a finished day stops reading as a batch still waiting to go out.'
 where status = 'pending'
   and day < (now() at time zone 'Asia/Dubai')::date;

-- ── 3. THE FOUR FALSE-ALARM CEO REPORTS ──────────────────────────────────────────────────────────
update public.support_ceo_report
   set status = 'completed',
       completed_at = now(),
       completion_note = 'Closed 22 Sep 2026 by it_engineer. Not a delivery failure: each of these requests '
                         || '(agent_actions 42578, 42579, 42595, 42596) queued a notification (36988, 36989, 37002, '
                         || '37003) and every one of those rows was a zz-demo…@example.invalid fixture deleted by the '
                         || 'demo hygiene sweep before the 19:30Z watch tick on 21 Sep read it. The watch called the '
                         || 'missing row "nothing was queued"; it now answers record_removed for a queued row that no '
                         || 'longer exists, and held for an invitation the founder''s own switch is holding '
                         || '(every_whatsapp_says_whether_it_arrived.sql, same apply). No supplier was left uncontacted.'
 where id in (3075, 3076, 3084, 3085)
   and status <> 'completed';

-- ══ VERDICT ══════════════════════════════════════════════════════════════════════════════════════
-- Data only, so the verdict reads the rows back. Each clause names the exact subjects above.
select case
  when (select count(*) from public.dead_letter where id in (141, 142) and resolved_at is not null) = 2
   and (select count(*) from public.dead_letter where resolved_at is null) = 0
   and (select count(*) from public.invite_schedule
         where status = 'pending' and day < (now() at time zone 'Asia/Dubai')::date) = 0
   and (select count(*) from public.support_ceo_report
         where id in (3075, 3076, 3084, 3085) and status = 'completed' and completed_at is not null) = 4
  then 'PROBE OK: the two dead letters are resolved, no past day is still a pending invite plan, and the four false-alarm reports are closed by id'
  else 'PROBE FAILED: the records this file names are not in the state it describes' end as verdict;
