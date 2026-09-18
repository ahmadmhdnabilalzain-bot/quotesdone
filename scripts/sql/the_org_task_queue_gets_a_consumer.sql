-- ---------------------------------------------------------------------------------------------
-- THE QUEUE THAT EVERYTHING WRITES TO AND NOTHING READS.            sales_engineer, 18 Sep 2026
-- ---------------------------------------------------------------------------------------------
-- MEASURED BEFORE WRITING A LINE (production, 18 Sep 2026 04:04 UTC):
--
--   public.org_tasks holds 20 rows. 16 are status='assigned'; every one of the 16 has
--   last_run_at IS NULL and attempts = 0, the oldest raised 9 days ago. 46 routines mention
--   org_tasks; NONE selects status='assigned' to EXECUTE it. public.org_action_executor has no
--   row for either action_class present, so fn_org_task_promote's lane can only reach the model
--   path, which is on the paid hold. Everything writes to this table and nothing reads it.
--
--   The 16 are exactly two classes:
--     knowledge_gap                  10  (7 sales_engineer, 3 customer_support -- 2 in Arabic)
--     routine_operational_decision    6  (4 accountant "Expense logged: ...", 2 ceo "reached no suppliers")
--
-- This is the founder's own rule broken -- a status column is not a delivery record -- on rows
-- that carry real customer questions.
--
-- WHAT THIS FILE ADDS: one routine, fn_org_task_consume_tick, wired as ONE step of the
-- resilience_ping tick that already runs every 15 minutes. It routes each class to the handler
-- THAT ALREADY EXISTS, stamps every attempt, backs off rather than hammering, and raises ONE
-- deduplicated finding per class for the owning seat when it cannot finish the work.
--
-- IT ADDS NO ANSWERING LOGIC AND CALLS NO MODEL. Every verdict below is a call into a routine
-- this estate already ships, and every close cites the routine that produced it.
--
-- ---------------------------------------------------------------------------------------------
-- THE ROUTING TABLE, AND WHY EACH ROUTE IS THE HANDLER THE WRITER MEANT
-- ---------------------------------------------------------------------------------------------
-- knowledge_gap  (written by fn_sales_assist and fn_support_knowledge_gap)
--   Both writers state the close condition in the task's own detail, verbatim:
--     "DONE MEANS: the knowledge exists in a searchable corpus and this question returns it.
--      Then set sales_knowledge_gap.status to knowledge_added."
--   So the handler is: ASK THE QUESTION AGAIN, against the estate's existing deterministic
--   answerers, and close only if one of them answers it today.
--
--     1. public.fn_price_guidance(question, 6) -- the estate's refusing price answerer. It is
--        used ONLY when it resolved a trade AND returned no unmatched_terms, i.e. it matched the
--        actual subject rather than one trade word. MEASURED, and this is why the bar exists:
--        "what technical information do you need from me to price an HVAC chiller replacement"
--        returns ok=true trade=hvac with unmatched_terms ["chiller","information","technical"] --
--        a price band is the WRONG answer to a spec question, and unmatched_terms is the
--        function's own signal that it matched the trade and missed the subject. The same call on
--        "what should a gypsum false ceiling cost per square metre in Dubai" returns
--        unmatched_terms [] with a published AED 35-70/sqm band. A deliberate recorded gap
--        (reason='trade_has_a_recorded_gap') is ALSO an answer, and the better one: it is the
--        company saying out loud that it publishes no range for that trade.
--
--     2. public.fn_support_corpus_search(question, true, 3) -- pure SQL, STABLE, no side effects,
--        and the only answerer in the estate that is Arabic-aware end to end (fn_ar_norm, the
--        'arabic' text search configuration, and a language bonus for the script the asker typed
--        in). It reads v_support_corpus = company_faq + support_knowledge + ops_knowledge, which
--        is the corpus the support writer names by name. p_public => true deliberately: these
--        questions came from customers and suppliers, and only rows with a recorded promotion in
--        support_public_override may answer one.
--
--        THE RANK FLOOR IS 1.5 AND IT IS MEASURED, NOT CHOSEN. Run over all 10 live questions,
--        the top hit's rank is bimodal with nothing in between: 1.989 and 1.964 for the two that
--        hit their own FAQ entry verbatim, and 1.008-1.022 for the eight that matched noise. The
--        rank carries a flat +1.0 language bonus, so those eight are ts_rank 0.008-0.022 -- the
--        tail of a fulltext match, not an answer. A floor of 1.5 sits in an empty band 0.94 wide.
--
--        WHY THIS FINDS WHAT fn_sales_assist COULD NOT, which is the real defect underneath two of
--        these rows: fn_sales_assist searches sales_knowledge, ops_knowledge, kb_chunks,
--        agent_knowledge, support_knowledge, category_specs and category_quote_specs. It does NOT
--        search company_faq. "Does a Dubai supplier cover Abu Dhabi as well?" and "What documents
--        does a supplier need for verification?" are APPROVED company_faq entries, titled almost
--        word for word as asked -- and both were filed as knowledge gaps because the seat that was
--        asked cannot see that corpus.
--
-- routine_operational_decision / accountant  (written by fn_founder_mail_route, kind expense_logged)
--   The task's own detail says what it is: "a booked expense is a record, not a decision". And it
--   is booked BEFORE the task is written -- supabase/functions/resend_inbound books the row into
--   public.expense_entries and posts it to the GL through fn_expense_post_to_gl, and only then
--   requests the notification that becomes this task. The handler is therefore: find the booked
--   entry this task is the receipt for, and close on it. If no entry matches, the task stays
--   queued -- that would mean the accountant's duty did NOT run, which is a finding, not a close.
--
-- routine_operational_decision / ceo  (written by fn_founder_mail_route, kind rfq_no_supplier)
--   "The customer is waiting" is the claim the task makes. It is checkable: the detail names the
--   inquiry. If that inquiry no longer exists, or it now has rows in inquiry_matches, the
--   condition the task was raised for is gone and the task closes on that fact. If the inquiry is
--   still live and still matches zero suppliers, THERE IS NO HANDLER AND THIS FILE DOES NOT
--   INVENT ONE: onboarding suppliers in a trade and emirate is a commercial act, fn_supply_gap_scan
--   was dropped on 7 Sep 2026, and no live routine owns it. The row stays queued with that reason
--   and the class raises its finding for the ceo seat.
--
-- ---------------------------------------------------------------------------------------------
-- STAMPING, BACK-OFF, AND THE ONE FINDING PER CLASS
-- ---------------------------------------------------------------------------------------------
-- Every attempt stamps last_run_at and increments attempts, whether it closed the row or not, so
-- a second failure is visible instead of silent. (On a close, fn_org_task_close_as_fact does the
-- stamping itself; this routine does not double-count it.)
--
-- Back-off is 15 minutes doubled per attempt, capped at 16 hours: a class nothing can finish is
-- retried roughly twice a day instead of 96 times, and a row that has never been tried goes
-- first. The tick's whole budget is p_limit rows, default 4.
--
-- The finding goes through public.fn_it_duty_settle, which is the estate's existing deduplicated
-- per-item ledger: the key is duty:org_task_queue:<action_class>:<seat>, so it is ONE finding per
-- class however many rows or ticks it covers, and the settle call auto-closes a class the moment
-- it empties. The census is taken over the WHOLE table, not over this tick's batch, or a class
-- outside the batch would be closed as if it had cleared. blast is 'agent_facing': the accurate
-- description of this is work sitting in a seat's queue that the seat cannot complete, and
-- fn_it_loop_tick routes an agent_facing finding to its owning seat rather than to the founder.
--
-- ---------------------------------------------------------------------------------------------
-- MEASURED COST (production, in a rolled-back transaction, 18 Sep 2026): the dry run over all 16
-- rows is reported in the PR. The live tick is bounded to p_limit=4 rows and is called from
-- resilience_ping through PostgREST, which runs RPC as `authenticator` with statement_timeout=8s.
-- ---------------------------------------------------------------------------------------------

-- THE QUEUE PREDICATE GETS AN INDEX. public.org_tasks carried ix_org_tasks_dept_status
-- (dept_key, status), which a bare status='assigned' filter cannot use, plus indexes on
-- objective_id and assigned_agent. Both scans this file adds -- the picker and the per-class
-- census -- filter on status='assigned' and would sequential-scan. At 20 rows that is free; this
-- routine runs 96 times a day forever, so the index goes in with it rather than after the table
-- grows. The column order matches the picker's ORDER BY.
create index if not exists org_tasks_assigned_queue_idx
  on public.org_tasks (priority desc, id)
  where status = 'assigned';

create or replace function public.fn_org_task_consume_tick(
  p_limit    integer default 4,
  p_task_id  bigint  default null,   -- process exactly this row and take no census (probes, replays)
  p_dry_run  boolean default false   -- decide and report, write nothing at all
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r          record;
  v_q        text;
  v_pg       jsonb;
  v_best     record;
  v_deliv    text;
  v_reason   text;
  v_handler  text;
  v_basis    jsonb;
  v_close    jsonb;
  v_gap_id   bigint;
  v_gap_status text;
  v_exp      record;
  v_inq      uuid;
  v_inq_seen boolean;
  v_matches  int;
  v_vendor   text;
  v_amount   numeric;
  v_ccy      text;
  v_charged  date;
  v_back     interval;
  v_done     jsonb := '[]'::jsonb;
  v_left     jsonb := '[]'::jsonb;
  v_items    jsonb := '[]'::jsonb;
  v_settled  jsonb;
  v_seen     int := 0;
  v_refused  int := 0;
  v_raised   int := 0;
  v_t0       timestamptz := clock_timestamp();
begin
  for r in
    select o.*
      from public.org_tasks o
     where o.status = 'assigned'
       and (p_task_id is null or o.id = p_task_id)
       and (p_task_id is not null
            or o.last_run_at is null
            or o.last_run_at < now() - make_interval(mins => (15 * power(2, least(o.attempts, 6)))::int))
     order by (o.last_run_at is null) desc, o.priority desc, o.id
     limit greatest(1, least(coalesce(p_limit, 4), 25))
     -- TWO TICKS MUST NOT PICK THE SAME ROW. The 15-minute cron can double-fire or retry, and a
     -- p_task_id replay can be issued by hand while a batch tick is in flight. Without this, both
     -- callers select the row under READ COMMITTED; the loser's fn_org_task_close_as_fact refuses
     -- (it guards on status='done') but its earlier result-merge update still lands on top of the
     -- winner's. skip locked rather than for update: a row another tick is already working is not
     -- this tick's work, and waiting on it would spend the budget queueing.
       for update of o skip locked
  loop
    v_seen   := v_seen + 1;
    v_deliv  := null;
    v_reason := null;
    v_basis  := '{}'::jsonb;
    v_gap_id := null;
    v_gap_status := null;
    v_handler := null;
    v_close  := null;

    -- ONE BAD ROW MUST NOT TAKE THE BATCH, AND MUST NOT TAKE THE FINDING. Everything from routing
    -- to the close runs inside this block, so a handler that raises -- a ::date cast on a captured
    -- "Date: 2026-13-45", a ::uuid cast on 36 hex characters with the dashes in the wrong places, a
    -- trigger refusing a close -- rolls back to the point this row was picked up instead of
    -- aborting fn_org_task_consume_tick. Without it, one poisoned row would undo every close
    -- already made in the same batch AND skip the per-class census at the end, so the tick would
    -- lose the finding that says the queue is stuck, stamp nothing, and re-select the same poisoned
    -- batch every 15 minutes with no forward progress and no explanation. The row itself is then
    -- stamped and parked on the queued path below, carrying SQLERRM as its reason.
    begin

    -- ── knowledge_gap ─────────────────────────────────────────────────────────────────────────
    if r.action_class = 'knowledge_gap' then
      v_q := nullif(btrim(coalesce(substring(r.detail from 'QUESTION: ([^\n]+)'), '')), '');

      -- THE GAP LEDGER IS THE WRITER'S OWN RECORD, SO READ IT FIRST. Measured 18 Sep 2026:
      -- sales_knowledge_gap #13 ("how much does it cost to charter a helicopter to the moon") has
      -- carried status='not_a_gap' since it was judged, while org_task 578944 stayed 'assigned'
      -- for nine days -- the founder's own rule, a status column is not a delivery record, showing
      -- up inside the very table that records the judgement. A question already judged out of
      -- scope has nothing left to answer, and the judgement is the fact the close cites.
      select g.id, g.status into v_gap_id, v_gap_status
        from public.sales_knowledge_gap g where g.task_id = r.id;

      if v_gap_status = 'not_a_gap' then
        v_handler := 'sales_knowledge_gap';
        v_deliv := 'ALREADY JUDGED. public.sales_knowledge_gap #' || v_gap_id || ', the record this '
          || 'task''s own detail points at, carries status = ''not_a_gap'': the question was reviewed '
          || 'and found not to be a gap in company knowledge.'
          || E'\n\nQUESTION: ' || coalesce(v_q, '(none recorded on the task)')
          || E'\n\nThere is nothing to answer and nothing to add to a corpus. The task stayed open '
          || 'only because the judgement was written to the gap ledger and never carried back to the '
          || 'queue -- which is the defect this consumer exists to end.';
        v_basis := jsonb_build_object('answered_by', 'sales_knowledge_gap',
                                      'sales_knowledge_gap_id', v_gap_id, 'gap_status', v_gap_status);

      elsif v_q is null then
        v_handler := 'none';
        v_reason  := 'the task carries no "QUESTION:" line, so there is nothing to ask again';

      else
        -- 1. the price answerer, admitted only when it matched the subject and not just the trade
        v_pg := public.fn_price_guidance(v_q, 6);

        if coalesce((v_pg->>'ok')::boolean, false)
           and jsonb_array_length(coalesce(v_pg->'unmatched_terms', '[]'::jsonb)) = 0 then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance, the published-price answerer.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE RESOLVED: ' || coalesce(v_pg->>'trade', '?')
            || ' (via ' || coalesce(v_pg->>'resolved_via', '?') || '), '
            || coalesce(v_pg->>'band_count', '0') || ' published UAE bands, and every substantive '
            || 'term in the question matched -- unmatched_terms is empty, so this is the subject '
            || 'that was asked about and not a trade-level substitute.'
            || E'\n\nBANDS: ' || coalesce(v_pg->'bands', '[]'::jsonb)::text
            || E'\n\nThese are published guide ranges in AED, never a quotation: QuotesDone does not '
            || 'price the work, suppliers do.';
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg);

        elsif coalesce(v_pg->>'reason', '') = 'trade_has_a_recorded_gap' then
          v_handler := 'fn_price_guidance';
          v_deliv := 'ANSWERED TODAY by public.fn_price_guidance: the company holds a DELIBERATE '
            || 'recorded gap for this trade, which is an answer and not a silence.'
            || E'\n\nQUESTION: ' || v_q
            || E'\n\nTRADE: ' || coalesce(v_pg->>'trade', '?')
            || E'\nRECORDED GAP: ' || coalesce(v_pg->>'gap_reason', '')
            || E'\n\nTHE ANSWER TO GIVE: QuotesDone publishes no price range for this trade. Say so '
            || 'plainly, never estimate one, and offer to put the job out to suppliers for real '
            || 'quotes. ' || coalesce(v_pg->>'note', '');
          v_basis := jsonb_build_object('answered_by', 'fn_price_guidance', 'price_guidance', v_pg);

        else
          -- 2. the corpus the writer named. Arabic-aware, read-only, public rows only.
          select s.src, s.src_id, s.title, s.content, s.citation, s.rank
            into v_best
            from public.fn_support_corpus_search(v_q, true, 3) s
           order by s.rank desc
           limit 1;

          if found and v_best.rank >= 1.5 then
            v_handler := 'fn_support_corpus_search';
            v_deliv := 'ANSWERED TODAY by public.fn_support_corpus_search over v_support_corpus '
              || '(company_faq + support_knowledge + ops_knowledge) -- the corpus this task names.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: ' || v_best.src || ':' || v_best.src_id
              || ' -- ' || coalesce(v_best.citation, coalesce(v_best.title, ''))
              || ' (rank ' || round(v_best.rank::numeric, 3) || ', floor 1.5)'
              || E'\n\nANSWER: ' || left(coalesce(v_best.content, ''), 4000);
            v_basis := jsonb_build_object(
              'answered_by', 'fn_support_corpus_search',
              'src', v_best.src, 'src_id', v_best.src_id, 'rank', round(v_best.rank::numeric, 4));
          else
            v_handler := 'fn_price_guidance + fn_support_corpus_search';
            v_reason  := 'still unanswered: fn_price_guidance returned '
              || coalesce(nullif(v_pg->>'reason', ''),
                          case when coalesce((v_pg->>'ok')::boolean, false)
                               then 'a trade-level match with unmatched terms '
                                    || coalesce(v_pg->'unmatched_terms', '[]'::jsonb)::text
                               else 'nothing' end)
              || ', and the best company-knowledge hit ranked '
              || coalesce(round(v_best.rank::numeric, 3)::text, 'nothing') || ' against a floor of 1.5. '
              || 'The knowledge does not exist yet -- this needs a person to write it into a corpus, '
              || 'not another search.';
          end if;
        end if;
      end if;

    -- ── routine_operational_decision ──────────────────────────────────────────────────────────
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'expense_logged' then
      v_handler := 'expense_entries';
      v_vendor := btrim(coalesce(substring(r.title from '^Expense logged: (.+) [0-9.]+ [A-Za-z]{3}$'), ''));
      v_amount := nullif(coalesce(substring(r.title from '([0-9]+\.?[0-9]*) [A-Za-z]{3}$'), ''), '')::numeric;
      v_ccy    := upper(coalesce(substring(r.title from '([A-Za-z]{3})$'), ''));
      -- THE DATE IS PART OF THE IDENTITY, AND LEAVING IT OUT CITED THE WRONG RECEIPT. Measured in
      -- the rolled-back dry run of 18 Sep 2026: matching on vendor + amount + currency alone closed
      -- "Expense logged: GoDaddy 93.8 AED" (announced 10 Sep) on expense_entries #62 charged
      -- 10 AUGUST, and "Resend 20 USD" (15 Sep) on #52 charged 15 August -- because a monthly
      -- subscription bills the same vendor the same amount every month and the oldest row won.
      -- A close that cites the wrong month's receipt is worse than an open task. The announced date
      -- is in the task's own body and matched exactly on all four live rows, so it is required: no
      -- exact match means the row stays queued and says why, rather than closing on a near miss.
      v_charged := nullif(coalesce(substring(r.detail from 'Date: ([0-9]{4}-[0-9]{2}-[0-9]{2})'), ''), '')::date;

      select e.id, e.vendor, e.amount, e.currency, e.charged_on, e.source, e.category, e.doc_path
        into v_exp
        from public.expense_entries e
       where e.vendor = v_vendor and e.amount = v_amount and upper(e.currency) = v_ccy
         and v_charged is not null and e.charged_on = v_charged
       order by e.id
       limit 1;

      if found then
        v_deliv := 'ALREADY DONE BEFORE THIS TASK EXISTED. The expense is booked: '
          || 'public.expense_entries #' || v_exp.id || ' -- ' || v_exp.vendor || ' '
          || v_exp.amount || ' ' || v_exp.currency || ' charged on ' || v_exp.charged_on
          || ', category ' || coalesce(v_exp.category, '(none)') || ', source ' || coalesce(v_exp.source, '?')
          || ', document ' || coalesce(v_exp.doc_path, '(none -- founder-reported)') || '.'
          || E'\n\nsupabase/functions/resend_inbound books the entry and posts it to the general '
          || 'ledger through fn_expense_post_to_gl at intake, and only THEN requests the notification '
          || 'that became this task. The task''s own words are "a booked expense is a record, not a '
          || 'decision": the record exists, so the condition it was raised for is resolved and there '
          || 'was never a decision to take.'
          || case when coalesce((r.result->'founder_mail'->>'seen_count')::int, 1) > 1
                  then E'\n\nThis signal recurred ' || (r.result->'founder_mail'->>'seen_count')
                       || ' times; each recurrence is its own booked entry.'
                  else '' end;
        v_basis := jsonb_build_object('answered_by', 'expense_entries', 'expense_entry_id', v_exp.id,
                                      'vendor', v_exp.vendor, 'amount', v_exp.amount, 'currency', v_exp.currency);
      else
        v_reason := 'no row in public.expense_entries matches ' || coalesce(v_vendor, '?') || ' '
          || coalesce(v_amount::text, '?') || ' ' || coalesce(v_ccy, '?') || ' charged on '
          || coalesce(v_charged::text, '(the task carries no "Date:" line)')
          || '. Either the receipt was announced and never booked -- which is the accountant''s duty '
          || 'failing rather than a task waiting -- or the booked entry carries a different date. Do '
          || 'NOT close this until the exact entry exists: a monthly subscription bills the same '
          || 'vendor the same amount every month, so vendor and amount alone identify nothing.';
      end if;

    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'rfq_no_supplier' then
      v_handler := 'inquiries + inquiry_matches';
      v_inq := nullif(coalesce(substring(r.detail from 'Inquiry: ([0-9a-fA-F-]{36})'), ''), '')::uuid;

      if v_inq is null then
        v_reason := 'the task names no inquiry id, so the claim "the customer is waiting" cannot be checked';
      else
        select true into v_inq_seen from public.inquiries i where i.id = v_inq;
        v_inq_seen := coalesce(v_inq_seen, false);
        select count(*) into v_matches from public.inquiry_matches m where m.inquiry_id = v_inq;

        if not v_inq_seen then
          v_deliv := 'THE CONDITION IS GONE. This task was raised because inquiry ' || v_inq
            || ' matched zero suppliers and a customer was waiting. That inquiry no longer exists in '
            || 'public.inquiries, so there is no customer waiting on it and nothing to route.'
            || E'\n\nThe underlying supply-coverage gap is NOT closed by this and is not claimed to '
            || 'be: it remains recorded in public.agent_actions under kind=''coverage_gap'', which is '
            || 'where a coverage decision belongs. What closes here is this signal, which named a '
            || 'request that is no longer live.';
          v_basis := jsonb_build_object('answered_by', 'inquiries', 'inquiry_id', v_inq, 'inquiry_present', false);
        elsif v_matches > 0 then
          v_deliv := 'THE CONDITION IS GONE. Inquiry ' || v_inq || ' now has ' || v_matches
            || ' row(s) in public.inquiry_matches, so it no longer matches zero suppliers and the '
            || 'signal this task carries is out of date.';
          v_basis := jsonb_build_object('answered_by', 'inquiry_matches', 'inquiry_id', v_inq, 'matches', v_matches);
        else
          v_reason := 'inquiry ' || v_inq || ' is still live and still matches zero suppliers. There is '
            || 'NO handler for this and this tick will not invent one: onboarding or contacting '
            || 'suppliers in a trade and emirate is a commercial act, fn_supply_gap_scan was dropped '
            || 'on 7 Sep 2026, and no live routine owns supply coverage. It stays queued for the ceo '
            || 'seat, and the class carries a finding saying exactly this.';
        end if;
      end if;

    else
      v_handler := 'none';
      v_reason  := 'no handler is mapped for action_class ' || coalesce(r.action_class, '(null)')
        || ' on seat ' || coalesce(r.assigned_agent, '(unassigned)')
        || '. Mapping one is a deliberate act, not a default.';
    end if;

    ------------------------------------------------------------------------------------------
    -- SETTLE THE ROW
    ------------------------------------------------------------------------------------------
      if v_deliv is not null and not p_dry_run then
        -- z50_task_close_needs_an_act refuses a close on a requires_evidence task whose result
        -- records facts but no act. Flipping the knowledge gap and citing the source IS the act,
        -- and it is written before the close so fn_org_task_close_as_fact merges onto it.
        update public.org_tasks
           set result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'change_made', jsonb_build_object(
                   'what', 'the condition this task was raised for was re-checked against the handler '
                           || 'the writer named, and it is resolved',
                   'handler', v_handler, 'basis', v_basis, 'at', now()))
         where id = r.id;

        v_close := public.fn_org_task_close_as_fact(r.id, 'fn_org_task_consume_tick', v_deliv,
                     v_basis || jsonb_build_object('owner', r.assigned_agent, 'handler', v_handler));

        -- A REFUSAL IS RETURNED, NOT RAISED, AND IT IS NOT A CLOSE. fn_org_task_close_as_fact
        -- answers {ok:false, reason} when the task is already done, the resolver is unnamed or the
        -- deliverable is too short. Flipping the gap ledger on that return would mark a customer's
        -- question knowledge_added while the task never left 'assigned' -- the exact shape of "a
        -- status column is not a delivery record", and worse: the refusal paths return before
        -- stamping last_run_at, so the row would keep sorting first on every tick and re-run the
        -- search forever behind a ledger already claiming success. So the refusal becomes the
        -- reason and the row falls through to the queued path, where it is stamped and backs off.
        if coalesce((v_close->>'ok')::boolean, false) then
          -- what both writers asked for in words, done in one place at last
          if r.action_class = 'knowledge_gap' then
            update public.sales_knowledge_gap
               set status = 'knowledge_added', closed_at = now()
             where task_id = r.id and status = 'open'
            returning id into v_gap_id;
          end if;
        else
          v_reason := 'fn_org_task_close_as_fact REFUSED this close: '
            || coalesce(nullif(btrim(v_close->>'reason'), ''), '(no reason given)')
            || '. The handler had an answer and the close path rejected it, so nothing is recorded '
            || 'as delivered and the row backs off instead.';
          v_deliv  := null;
          v_refused := v_refused + 1;
        end if;
      end if;

    exception when others then
      v_deliv  := null;
      v_close  := null;
      v_reason := 'the handler RAISED and this row was rolled back to the point it was picked up: '
        || sqlerrm || ' (SQLSTATE ' || sqlstate || '). The rest of this batch and the per-class '
        || 'finding are unaffected; this row is stamped and backs off so the failure is visible '
        || 'rather than repeating every 15 minutes.';
      v_raised := v_raised + 1;
    end;

    v_back := make_interval(mins => (15 * power(2, least(r.attempts + 1, 6)))::int);

    if v_deliv is not null then
      if p_dry_run then
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'close', 'basis', v_basis, 'deliverable', left(v_deliv, 1200));
      else
        v_done := v_done || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'closed', true,
                    'close', v_close, 'sales_knowledge_gap', v_gap_id);
      end if;

    else
      if p_dry_run then
        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'would', 'stay queued', 'reason', v_reason,
                    'attempts_would_be', r.attempts + 1, 'next_attempt_after', now() + v_back);
      else
        update public.org_tasks
           set last_run_at = now(),
               attempts    = coalesce(attempts, 0) + 1,
               updated_at  = now(),
               result      = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'consumer', jsonb_build_object(
                   'at', now(), 'handler', v_handler, 'verdict', 'not_yet', 'reason', v_reason,
                   'attempts', coalesce(r.attempts, 0) + 1, 'next_attempt_after', now() + v_back))
         where id = r.id;

        v_left := v_left || jsonb_build_object('id', r.id, 'class', r.action_class, 'seat', r.assigned_agent,
                    'handler', v_handler, 'reason', v_reason, 'attempts', r.attempts + 1,
                    'next_attempt_after', now() + v_back);
      end if;
    end if;
  end loop;

  ------------------------------------------------------------------------------------------------
  -- ONE FINDING PER CLASS, OVER THE WHOLE TABLE. Not one per row, not one per tick.
  ------------------------------------------------------------------------------------------------
  if p_task_id is null and not p_dry_run then
    select coalesce(jsonb_agg(jsonb_build_object(
             'item',  x.action_class || ':' || x.seat,
             'title', x.n || ' org_task(s) of class ' || x.action_class || ' are queued on the '
                      || x.seat || ' seat and the consumer cannot finish them; the oldest has waited '
                      || x.age_days || ' day(s)',
             'owner_seat', x.seat,
             'subject', 'org_tasks',
             'blast',  'agent_facing',
             'affected', x.n,
             'evidence', jsonb_build_object(
               'ids', x.ids, 'oldest_created_at', x.oldest, 'max_attempts', x.max_attempts,
               'last_reason', x.reason,
               'look_at', 'select id, title, result->''consumer'' from public.org_tasks where status = ''assigned'''))), '[]'::jsonb)
      into v_items
      from (
        select o.action_class,
               coalesce(o.assigned_agent, 'unassigned')          as seat,
               count(*)::int                                     as n,
               array_agg(o.id order by o.id)                     as ids,
               min(o.created_at)                                 as oldest,
               (extract(epoch from (now() - min(o.created_at))) / 86400)::int as age_days,
               max(o.attempts)                                   as max_attempts,
               max(o.result->'consumer'->>'reason')              as reason
          from public.org_tasks o
         where o.status = 'assigned'
         group by 1, 2
      ) x;

    v_settled := public.fn_it_duty_settle('org_task_queue', v_items);
  end if;

  -- THE STEP RUNNER ONLY COUNTS {ok:false, error:'<string>'} AS A FAILURE (resilience_ping/steps.ts,
  -- failureOf). A hardcoded ok:true would mean a refused close or a raising handler never reaches
  -- settleFailures and never becomes duty:heartbeat:orgtasks -- a broken consumer reporting health.
  -- So a tick that could not finish what it started says so in the shape the runner reads.
  return jsonb_build_object(
    'ok', (v_refused + v_raised) = 0,
    'error', case when (v_refused + v_raised) > 0
                  then v_refused || ' close(s) refused and ' || v_raised || ' handler(s) raised; '
                       || 'see result->''consumer''->>''reason'' on the rows still at status=''assigned'''
                  else null end,
    'refused', v_refused,
    'raised', v_raised,
    'dry_run', p_dry_run,
    'scanned', v_seen,
    'closed', jsonb_array_length(v_done),
    'still_queued', jsonb_array_length(v_left),
    'done', v_done,
    'queued', v_left,
    'findings', v_settled,
    'ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));
end
$fn$;

revoke execute on function public.fn_org_task_consume_tick(integer, bigint, boolean)
  from public, anon, authenticated;
grant  execute on function public.fn_org_task_consume_tick(integer, bigint, boolean)
  to service_role;

-- ---------------------------------------------------------------------------------------------
-- PROBE. This file carries DDL, so the probe CLEANS UP AFTER ITSELF and ends in a notice: a
-- `raise exception` here would roll the routine above back out with it.
--
-- It runs DRY, so it writes nothing to decision_trace, review_chain or agent_runs and cannot
-- close a real row. It uses a ZZ DEMO task addressed by p_task_id, so it cannot reach the 16
-- real rows either, and it counts them before and after to prove it did not.
-- ---------------------------------------------------------------------------------------------
do $probe$
declare
  v_id      bigint;
  v_before  int;
  v_after   int;
  v_r       jsonb;
  v_r2      jsonb;
begin
  select count(*) into v_before from public.org_tasks where status = 'assigned';

  -- (a) a question company knowledge answers today
  insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                priority, requires_evidence, needs_founder)
  values ('ZZ DEMO consumer probe: answerable portal question',
          'ZZ DEMO row raised by scripts/sql/the_org_task_queue_gets_a_consumer.sql.' || E'\n\n'
          || 'QUESTION: does a Dubai supplier cover Abu Dhabi as well' || E'\n'
          || 'REFUSAL: probe',
          'assigned', 'advisory', 'knowledge_gap', 'sales_engineer', 1, true, false)
  returning id into v_id;

  v_r := public.fn_org_task_consume_tick(p_limit => 1, p_task_id => v_id, p_dry_run => true);

  if coalesce((v_r->>'closed')::int, 0) <> 1
     or (v_r->'done'->0->>'handler') <> 'fn_support_corpus_search' then
    raise notice 'PROBE FAILED (answerable): %', v_r;
  end if;

  -- (b) the same row asked a question nothing answers: it must stay queued WITH a reason
  update public.org_tasks
     set detail = 'ZZ DEMO row.' || E'\n\nQUESTION: zzdemo unanswerable question about nothing at all'
                  || E'\nREFUSAL: probe'
   where id = v_id;

  v_r2 := public.fn_org_task_consume_tick(p_limit => 1, p_task_id => v_id, p_dry_run => true);

  if coalesce((v_r2->>'still_queued')::int, 0) <> 1
     or coalesce(btrim(v_r2->'queued'->0->>'reason'), '') = '' then
    raise notice 'PROBE FAILED (unanswerable): %', v_r2;
  end if;

  -- CLEAN UP. The dry run wrote nothing, so the demo row is the only thing to remove.
  delete from public.org_tasks where id = v_id;
  if exists (select 1 from public.org_tasks where id = v_id) then
    raise notice 'PROBE FAILED: the ZZ DEMO row %  did not delete', v_id;
  end if;

  select count(*) into v_after from public.org_tasks where status = 'assigned';
  if v_after <> v_before then
    raise notice 'PROBE FAILED: assigned org_tasks moved from % to %', v_before, v_after;
  end if;

  raise notice 'PROBE OK: answerable -> % ; unanswerable -> % ; assigned rows untouched at %',
    v_r->'done'->0->>'handler', left(v_r2->'queued'->0->>'reason', 80), v_after;
end
$probe$;
