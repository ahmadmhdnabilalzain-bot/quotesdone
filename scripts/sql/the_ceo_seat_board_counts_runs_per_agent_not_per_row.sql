-- THE CEO'S SEAT BOARD ANSWERS INSIDE THE STATEMENT TIMEOUT.
-- Seat: it_engineer (the board belongs to ceo; this changes how it counts, not what it shows).
--
-- MEASURED 7 Oct 2026 on production (stage-2 run fe7ba9c4, S20): ceo_agent actions 'board' and 'seats'
-- both answered 500 "canceling statement due to statement timeout". fn_ceo_seat_board(7) took 31.0 s
-- against the 8 s statement_timeout of authenticator/authenticated. Cause: runs, errors and last_seen
-- each filtered agent_runs (~269k rows, 107 MB) by public.fn_run_seat(r.agent) = s.seat. A function
-- around the column defeats agent_runs_agent_started_idx, last_seen had no time bound, and fn_run_seat
-- does its own function_owner lookup -- 18 full scans and ~4.8M calls per board.
-- No index fixes that (fn_run_seat reads another table, so it cannot be an expression index).
--
-- THE FIX: roll agent_runs up per agent once, then map ~110 agents to seats. The same grouped query,
-- run on production in a rolled-back transaction: 0.178 s, same per-seat figures. Every other line of
-- the routine is the deployed body (schema mirror, 7 Oct 2026). CREATE OR REPLACE keeps the ACL, so
-- there is no revoke here (a revoke on a replace is a no-op at best and the wrong habit at worst).
--
-- Prevented by: scripts/checks/ceo_seat_board_never_maps_agent_runs_row_by_row.test.mjs

CREATE OR REPLACE FUNCTION public.fn_ceo_seat_board(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  -- agent_runs is rolled up per AGENT first (~110 distinct), then mapped to a seat: fn_run_seat runs
  -- ~110 times instead of once per row per subquery (3 x 6 seats x ~269k rows = ~4.8M calls).
  with ar as (
    select public.fn_run_seat(a.agent) as seat,
           sum(a.runs)::bigint as runs, sum(a.errors)::bigint as errors, max(a.last_seen) as last_seen
      from (select r.agent,
                   count(*) filter (where r.started_at >= v_from)                      as runs,
                   count(*) filter (where r.status = 'error' and r.started_at >= v_from) as errors,
                   max(r.started_at)                                                     as last_seen
              from agent_runs r group by r.agent) a
     group by 1)
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all six, so the
        -- comparison between seats is honest.
        'runs',        coalesce((select ar.runs   from ar where ar.seat = s.seat), 0),
        'errors',      coalesce((select ar.errors from ar where ar.seat = s.seat), 0),
        'last_seen',   (select ar.last_seen from ar where ar.seat = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unread report is the
        -- CEO's own backlog, not the seat's.
        --
        -- THE NAME OF THIS FIGURE WAS WRONG AND THE FOUNDER CAUGHT IT. It read
        -- 'awaiting_my_acceptance', and on 9 September he read the board and asked "wait is the CEO
        -- basically waiting to approve the accountant report" -- a fair reading of that phrase, and
        -- not what the number means. Measured: three routines read accepted_at
        -- (fn_ceo_weekly_figures, fn_ceo_seat_board, fn_customer_mandatory_check) and all three only
        -- COUNT it for display. Nothing gates on it. Both accountant reports say in their own
        -- requested_outcome field "NOTHING IS REQUESTED", and one had already reached the founder.
        -- It is a read receipt, not an approval queue, and the label now says which. A number whose
        -- name implies work is blocked, on a board built so the chief executive knows what is
        -- waiting on whom, is worse than no number.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'filed_but_not_yet_read_by_ceo', (select count(*) from support_ceo_report c
                                    where c.source_agent = s.seat and c.accepted_at is null),

        -- WHAT IT ACHIEVED: the question this seat's own job answers.
        'achievement', case s.seat
          when 'accountant' then jsonb_build_object(
            'expense_records_with_a_document', (select count(*) from expense_entries where doc_path is not null),
            'journals_posted',                 (select count(*) from gl_journal where status = 'posted'),
            'weekly_reports_delivered',        (select count(*) from accountant_weekly_report where founder_submitted_at is not null))
          when 'customer_support' then jsonb_build_object(
            'conversations_answered',          (select count(*) from assistant_logs where created_at >= v_from),
            'questions_it_could_not_answer',   (select count(*) from sales_knowledge_gap where status = 'open'),
            'supplier_contacts_logged',        (select count(*) from supplier_response_watch))
          when 'sales_engineer' then jsonb_build_object(
            'assists_given',                   (select count(*) from sales_decision_log where created_at >= v_from),
            'quotes',                          (select count(*) from quotes),
            'comparisons',                     (select count(*) from quote_comparisons))
          when 'it_engineer' then jsonb_build_object(
            'findings_open',                   (select count(*) from it_watch_finding where status = 'open'),
            'findings_closed',                 (select count(*) from it_watch_finding where status = 'resolved'),
            'alerts_delivered',                (select count(*) from notifications
                                                 where kind like 'it_%' and status = 'sent'))
          -- 22 Sep 2026 (founder instruction 721): the marketing seat reports the overall picture to the CEO.
          -- Its reports are READ, never approved; 'read_by_ceo' counts the CEO's read receipts.
          when 'marketing' then jsonb_build_object(
            'reports_filed',                   (select count(*) from marketing_report),
            'reports_read_by_ceo',             (select count(*) from marketing_report where read_by_ceo_at is not null),
            'ad_spend_reported_aed',           (select coalesce(sum(amount_aed), 0) from ad_spend_reported),
            'latest_report',                   (select jsonb_build_object('date', m.report_date, 'headline', m.figures->'headline',
                                                                          'no_data_yet', m.no_data_yet)
                                                  from marketing_report m order by m.report_date desc limit 1))
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $function$;
