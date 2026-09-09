-- THE CEO CAN SEE WHAT EVERY SEAT DID AND WHAT IS WAITING ON IT.
--
-- The founder, 9 September 2026: "support and CEO need to be connected so that the CEO is aware of
-- all his tasks and achievement."
--
-- WHAT WAS ALREADY THERE, AND WHY IT WAS NOT ENOUGH. customer_support can file a report to the CEO
-- (fn_support_report_to_ceo), and the CEO's inbox now reads that tray. But a report is something a
-- seat chooses to send when it wants a decision. Nothing showed the CEO what a seat was ORDINARILY
-- doing, what it had produced, or what was sitting unanswered on its desk. Measured before building
-- this: 7 tasks assigned to sales_engineer and 1 to the accountant, all open, none of them visible
-- to the CEO through any surface; 7 knowledge gaps recorded by support that nobody had read; and 2
-- reports filed to the CEO of which 0 had been accepted.
--
-- A chief executive whose only view of the company is what people choose to escalate is managing by
-- exception with no baseline. The founder's phrase — "tasks AND achievement" — is exactly the two
-- halves that were missing.
--
-- WHAT COUNTS AS AN ACHIEVEMENT IS PER-SEAT AND MEASURED, NEVER SCORED. Each seat is asked the
-- question its own job answers, and the answer is a count of things that exist:
--
--   accountant        expense records with a document, journals posted, reports delivered
--   customer_support  conversations answered, questions it could not answer and recorded,
--                     supplier contact attempts logged (the evidence refunds rest on)
--   sales_engineer    assists given, knowledge gaps found, quotes and comparisons produced
--   it_engineer       findings raised, findings closed, alerts actually delivered
--   ceo               approvals decided, reports accepted, weekly reports delivered
--
-- There is no rating and no score. A number a seat cannot dispute is worth more to a chief
-- executive than a grade it can argue with, and this estate has already been bitten by instruments
-- that judged instead of measured.
--
-- ZERO IS SAID OUT LOUD. Every seat is two days old and the company has no customers, so most of
-- these are 0. The routine reports `basis` alongside each block so an idle seat is never read as a
-- broken one — the distinction that this estate keeps paying for when it is lost.

create or replace function public.fn_ceo_seat_board(p_days int default 7)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all five, so the
        -- comparison between seats is honest.
        'runs',        (select count(*) from agent_runs r
                         where regexp_replace(r.agent,'^fn:','') = s.seat and r.started_at >= v_from),
        'errors',      (select count(*) from agent_runs r
                         where regexp_replace(r.agent,'^fn:','') = s.seat
                           and r.status = 'error' and r.started_at >= v_from),
        'last_seen',   (select max(r.started_at) from agent_runs r
                         where regexp_replace(r.agent,'^fn:','') = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unaccepted report is
        -- the CEO's own backlog, not the seat's.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'awaiting_my_acceptance', (select count(*) from support_ceo_report c
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
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $fn$;
revoke execute on function public.fn_ceo_seat_board(int) from public, anon, authenticated;

do $do$
declare v jsonb; s jsonb;
begin
  v := public.fn_ceo_seat_board(7);

  -- All five seats present, or the CEO is blind to one of its own reports.
  if (select count(*) from jsonb_object_keys(v->'seats')) <> 5 then
    raise exception 'the board shows % seats, not 5', (select count(*) from jsonb_object_keys(v->'seats'));
  end if;

  -- POSITIVE CONTROL: it must surface the work that is actually waiting. sales_engineer has open
  -- tasks right now; a board that reports 0 for it is reading the wrong table.
  s := v->'seats'->'sales_engineer';
  if (s->>'open_tasks')::int = 0 then
    raise exception 'sales_engineer shows 0 open tasks, but org_tasks holds %',
      (select count(*) from org_tasks where assigned_agent='sales_engineer' and status in ('assigned','in_progress'));
  end if;

  -- Every seat must carry an achievement block, even an empty-valued one — a missing key reads as
  -- "not measured" and that is the ambiguity this whole routine exists to remove.
  if (v->'seats'->'ceo'->'achievement') is null
     or (v->'seats'->'it_engineer'->'achievement') is null then
    raise exception 'a seat has no achievement block';
  end if;

  raise notice 'SEAT BOARD LIVE. sales_engineer: % open task(s), oldest % day(s). accountant: % expense record(s) with a document. it_engineer: % finding(s) closed, % alert(s) delivered. ceo: % report(s) still awaiting its acceptance.',
    v->'seats'->'sales_engineer'->>'open_tasks',
    v->'seats'->'sales_engineer'->>'oldest_open_task_days',
    v->'seats'->'accountant'->'achievement'->>'expense_records_with_a_document',
    v->'seats'->'it_engineer'->'achievement'->>'findings_closed',
    v->'seats'->'it_engineer'->'achievement'->>'alerts_delivered',
    v->'seats'->'ceo'->>'awaiting_my_acceptance';
end
$do$;
