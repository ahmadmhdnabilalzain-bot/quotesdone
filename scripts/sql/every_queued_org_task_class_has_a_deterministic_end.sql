-- ---------------------------------------------------------------------------------------------
-- EVERY QUEUED ORG_TASK CLASS HAS A DETERMINISTIC END, AND PITR IS A DECISION NOT AN ALARM.
--                                                                    it_engineer, 21 Sep 2026
-- ---------------------------------------------------------------------------------------------
-- MEASURED (production, read-only, 21 Sep 2026 ~15:30 UTC):
--   * Two IT emails reached the founder: notifications 35432 (duty:org_task_queue:
--     routine_operational_decision:sales_engineer) and 35568 (a digest: four app dependency
--     advisories, duty:db_backup:pitr, duty:org_task_queue:knowledge_gap:customer_support).
--   * 11 org_tasks sit at status='assigned', not the 6 the emails named: 9 knowledge_gap
--     (5 sales_engineer, oldest 9 Sep with attempts=9; 4 customer_support) and 2
--     routine_operational_decision on sales_engineer (579020 founder_mail kind
--     supplier_registered; 579021 a customer rating, result->'sales_rating'->review_id 64).
--   * WHY THE CONSUMER CANNOT FINISH knowledge_gap: when neither fn_price_guidance nor
--     fn_support_corpus_search (rank floor 1.5) answers, the row is re-asked for ever. Its only
--     exit is knowledge nobody has written, so the queue finding never clears. Every one of the 9
--     already HAS its sales_knowledge_gap row (ids 2,3,4,5,16,17,18,19,20, all status open): the
--     gap ledger already tracks the question; the org_task duplicating it is what pages.
--   * A lexeme test of all 9 live questions against company_faq's questions (to_tsvector english
--     or arabic by script) is bimodal: the two known FAQ duplicates cover 1.00/1.00 both ways; the
--     best of the 9 live ones covers 0.33 of the question. A 0.75 floor both ways admits exactly
--     the real duplicates. (sales_knowledge is NOT used: its rows are whole documents, where lexeme
--     coverage of a 1-3 lexeme question means nothing.)
--   * WHY IT CANNOT FINISH routine_operational_decision on sales_engineer: only founder_mail kinds
--     expense_logged and rfq_no_supplier are mapped; everything else falls to "no handler".
--     579020: lead 126512 exists, trade_license_no matches, approval_status='approved' by
--     sales_engineer -- the task says "Decision: approved. No action needed; this is a record."
--     579021: review 64 rating 4; leads.app_rating 4.00 / app_reviews 1 equal avg/count of
--     reviews, i.e. recompute_supplier_rating already ran, as the task says.
--   * duty:db_backup:pitr: seen_count 1, raised 21 Sep 10:06. PITR is a PAID add-on (Supabase
--     docs platform/backups, read 21 Sep 2026: ~$100/month for 7 days, ~$200 for 14, ~$400 for 28;
--     needs at least the Small compute add-on; not covered by the Spend Cap). Enabling it is
--     spending money, i.e. the founder's call, and it must not read as a defect IT "could not fix".
--
-- WHAT CHANGES: fn_org_task_consume_tick v2 (supersedes the_org_task_queue_gets_a_consumer.sql)
--   and fn_it_platform_ingest v2 (supersedes its body in the_it_engineer_takes_on_seven_more_duties).
-- NOT CHANGED: rfq_no_supplier and expense_logged handlers, back-off, the per-class census,
--   fn_it_duty_settle, the dependency and daily-backup detectors. No detector is muted.
-- ---------------------------------------------------------------------------------------------
--
-- 1. knowledge_gap: (a) a company_faq lexeme answerer runs between price guidance and the corpus
--    search; (b) when nothing answers, the task CLOSES AS A TRACKED GAP citing its open
--    sales_knowledge_gap row (created if missing). That row stays 'open' for the owning seat and
--    is never flipped to knowledge_added on this path; a repeat ask increments its asks count.
-- 2. routine_operational_decision: two deterministic deciders. supplier_registered closes when the
--    announced record matches public.leads (same licence and name, approval_status equals the
--    announced decision, not banned). sales_rating closes when the review is present, the aggregate
--    equals avg/count of reviews, and the rating is >= 3 (no change to standing). A rating <= 2 or
--    any mismatch stays queued with its reason -- no suspension policy is invented here.
-- 3. PITR off is recorded ONCE as "awaiting the founder's decision on a paid add-on" ('config' =>
--    true, so fn_it_duty_settle holds it rather than re-raising) until a company_policy_decision
--    row decides it: 'supabase_pitr_addon:declined' closes the finding citing the decision;
--    'supabase_pitr_addon:approved' with PITR still off becomes a real, non-config defect.

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
  v_qlx      text[];
  v_faq_id   bigint;
  v_faq_q    text;
  v_faq_a    text;
  v_cov_q    numeric;
  v_cov_f    numeric;
  v_lead     record;
  v_rev      record;
  v_agg      record;
  v_lic      text;
  v_decision text;
  v_tracked  boolean;
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
    v_tracked := false;

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
          -- 2. company_faq by LEXEMES, both directions. Measured 21 Sep 2026: real duplicates cover
          --    1.00/1.00, the 9 live unanswered questions at most 0.33, so 0.75 both ways sits in an
          --    empty band. Public approved rows only: these questions came from customers.
          v_qlx := array(select t.lexeme from unnest(to_tsvector(
                     (case when v_q ~ '[؀-ۿ]' then 'arabic' else 'english' end)::regconfig, v_q)) t);
          v_faq_id := null;
          if cardinality(v_qlx) > 0 then
            select s.id, s.question, s.answer, s.cov_q, s.cov_f into v_faq_id, v_faq_q, v_faq_a, v_cov_q, v_cov_f
              from (select f.id, f.question, f.answer,
                           (select count(*) from unnest(v_qlx) x where x = any (fl.lx))::numeric
                             / cardinality(v_qlx) as cov_q,
                           (select count(*) from unnest(fl.lx) x where x = any (v_qlx))::numeric
                             / greatest(cardinality(fl.lx), 1) as cov_f
                      from public.company_faq f
                      cross join lateral (select array(select t.lexeme from unnest(to_tsvector(
                             (case when f.question ~ '[؀-ۿ]' then 'arabic' else 'english' end)::regconfig,
                             f.question)) t) as lx) fl
                     where f.public and f.status = 'approved') s
             where s.cov_q >= 0.75 and s.cov_f >= 0.75
             order by s.cov_q + s.cov_f desc, s.id
             limit 1;
          end if;

          -- 3. the corpus the writer named. Arabic-aware, read-only, public rows only.
          if v_faq_id is null then
            select s.src, s.src_id, s.title, s.content, s.citation, s.rank
              into v_best
              from public.fn_support_corpus_search(v_q, true, 3) s
             order by s.rank desc
             limit 1;
          end if;

          if v_faq_id is not null then
            v_handler := 'company_faq';
            v_deliv := 'ANSWERED TODAY by an approved public company_faq entry whose question carries '
              || 'the same lexemes as the one asked (' || round(v_cov_q * 100) || '% of the question, '
              || round(v_cov_f * 100) || '% of the FAQ question; floor 75% both ways).'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nSOURCE: company_faq #' || v_faq_id || ' -- ' || v_faq_q
              || E'\n\nANSWER: ' || left(coalesce(v_faq_a, ''), 4000);
            v_basis := jsonb_build_object('answered_by', 'company_faq', 'company_faq_id', v_faq_id,
                                          'coverage_question', round(v_cov_q, 3),
                                          'coverage_faq', round(v_cov_f, 3));

          elsif v_best.rank is not null and v_best.rank >= 1.5 then
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
            -- 4. NOTHING ANSWERS: CLOSE AS A TRACKED GAP. Re-asking every few hours cannot create
            --    knowledge; it only kept a duplicate of the gap ledger in the queue and paged about
            --    it. The gap row IS the seat's record of the unanswered question (the writers bump
            --    its asks on every repeat and reuse this task), so the task ends by citing it and
            --    the row stays 'open' -- it is NOT marked knowledge_added.
            v_handler := 'sales_knowledge_gap';
            v_tracked := true;
            if v_gap_id is null and not p_dry_run then
              insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
              values (lower(btrim(v_q)), v_q, 'consumer_tracked_gap', 'support_corpus', r.id)
              on conflict (question_norm) do nothing;
              select g.id, g.status into v_gap_id, v_gap_status
                from public.sales_knowledge_gap g where g.question_norm = lower(btrim(v_q));
            end if;
            v_deliv := 'NOT ANSWERED -- FILED AS A TRACKED KNOWLEDGE GAP. No corpus answers this today: '
              || 'fn_price_guidance returned '
              || coalesce(nullif(v_pg->>'reason', ''),
                          case when coalesce((v_pg->>'ok')::boolean, false)
                               then 'a trade-level match with unmatched terms '
                                    || coalesce(v_pg->'unmatched_terms', '[]'::jsonb)::text
                               else 'nothing' end)
              || ', no approved public company_faq question shares 75% of its lexemes, and the best '
              || 'company-knowledge hit ranked ' || coalesce(round(v_best.rank::numeric, 3)::text, 'nothing')
              || ' against a floor of 1.5.'
              || E'\n\nQUESTION: ' || v_q
              || E'\n\nTRACKED AT: public.sales_knowledge_gap #' || coalesce(v_gap_id::text, '(filed on the live run)')
              || ', status ' || coalesce(v_gap_status, 'open') || ', owned by the ' || coalesce(r.assigned_agent, '?')
              || ' seat. It stays open until the answer is written into company_faq or support_knowledge; '
              || 'this task closes because re-running the same search cannot produce that answer.';
            v_basis := jsonb_build_object('answered_by', 'none', 'outcome', 'tracked_gap',
                                          'sales_knowledge_gap_id', v_gap_id,
                                          'best_corpus_rank', round(v_best.rank::numeric, 4));
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

    -- ── routine_operational_decision / supplier_registered (fn_founder_mail_route) ─────────────
    -- The task announces a decision already taken ("Decision: approved. No action needed; this is
    -- a record."). The decider checks the record against public.leads and closes on the match.
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'supplier_registered' then
      v_handler  := 'leads';
      v_vendor   := substring(r.detail from 'New supplier "([^"]+)"');
      v_lic      := btrim(substring(r.detail from 'Licence ([^,]+),'));
      v_decision := lower(substring(r.detail from 'Decision: ([A-Za-z_]+)'));

      select l.id, l.company_name, l.trade_license_no, l.approval_status, l.approval_decided_by,
             l.approved_at, coalesce(l.banned, false) as banned, l.license_expiry, l.is_demo
        into v_lead
        from public.leads l
       where l.trade_license_no = v_lic and l.company_name = v_vendor
       order by l.id limit 1;

      if v_vendor is null or v_lic is null or v_decision is null then
        v_reason := 'the task does not carry the supplier name, licence and decision in the form '
          || 'fn_founder_mail_route writes them, so the record cannot be checked';
      elsif not found then
        v_reason := 'no public.leads row has licence ' || v_lic || ' and name "' || v_vendor
          || '": the announcement names a supplier the register does not hold';
      elsif v_lead.approval_status is distinct from v_decision or v_lead.banned then
        v_reason := 'the register disagrees with the announcement: leads #' || v_lead.id
          || ' has approval_status ' || coalesce(v_lead.approval_status, 'null')
          || case when v_lead.banned then ' and is BANNED' else '' end
          || ' while the task announced "' || v_decision || '". That is the seat''s to reconcile.';
      else
        v_deliv := 'RECORD CONFIRMED -- NO DECISION WAS PENDING. The task announced supplier "'
          || v_vendor || '" (licence ' || v_lic || ') as ' || v_decision || '. public.leads #'
          || v_lead.id || ' agrees: approval_status ' || v_lead.approval_status || ' by '
          || coalesce(v_lead.approval_decided_by, '?') || ' at ' || coalesce(v_lead.approved_at::text, '?')
          || ', licence expires ' || coalesce(v_lead.license_expiry::text, '?') || ', not banned.'
          || E'\n\nThe task''s own words are "No action needed; this is a record": the record exists '
          || 'and matches, so it closes on that fact.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_id', v_lead.id,
                                      'approval_status', v_lead.approval_status, 'is_demo', v_lead.is_demo);
      end if;

    -- ── routine_operational_decision / sales_rating (the rating trigger's task) ────────────────
    -- The judgement asked: does this rating change the supplier's standing, capability or
    -- eligibility? Deterministic rule: a rating of 3-5 changes none of them (the aggregate already
    -- carries it). A rating of 1-2 is a standing judgement with no written policy, so it stays
    -- queued with that reason rather than having a suspension rule invented here.
    elsif r.action_class = 'routine_operational_decision' and r.result ? 'sales_rating' then
      v_handler := 'reviews + leads';
      select rv.id, rv.rating, rv.supplier_id into v_rev
        from public.reviews rv
       where rv.id = nullif(r.result->'sales_rating'->>'review_id', '')::bigint;

      if not found then
        v_deliv := 'THE CONDITION IS GONE. Review #' || coalesce(r.result->'sales_rating'->>'review_id', '?')
          || ' no longer exists in public.reviews, so there is no rating left to incorporate into the '
          || 'supplier record.';
        v_basis := jsonb_build_object('answered_by', 'reviews', 'review_present', false);
      else
        select round(avg(x.rating)::numeric, 2) as avg_rating, count(*)::int as n
          into v_agg from public.reviews x where x.supplier_id = v_rev.supplier_id;
        select l.id, l.company_name, l.app_rating, l.app_reviews into v_lead
          from public.leads l where l.id = v_rev.supplier_id;

        if not found then
          v_reason := 'review #' || v_rev.id || ' names supplier ' || v_rev.supplier_id
            || ' and public.leads has no such row';
        elsif v_lead.app_rating is distinct from v_agg.avg_rating
              or v_lead.app_reviews is distinct from v_agg.n then
          v_reason := 'the supplier aggregate is stale: leads #' || v_lead.id || ' shows '
            || coalesce(v_lead.app_rating::text, 'null') || ' over ' || coalesce(v_lead.app_reviews::text, 'null')
            || ' review(s) but public.reviews holds ' || coalesce(v_agg.avg_rating::text, 'null') || ' over '
            || v_agg.n || '. recompute_supplier_rating did not run, which is a defect, not a decision.';
        elsif v_rev.rating >= 3 then
          v_deliv := 'DECIDED: NO CHANGE TO STANDING, CAPABILITY OR ELIGIBILITY. Review #' || v_rev.id
            || ' rates ' || v_lead.company_name || ' ' || v_rev.rating || '/5. The supplier aggregate '
            || 'already carries it (' || v_lead.app_rating || ' over ' || v_lead.app_reviews
            || ' review(s), equal to public.reviews). Rule applied: a rating of 3 to 5 does not change a '
            || 'supplier''s standing, declared capability or trade eligibility; only a rating of 1 or 2 '
            || 'is held for the seat''s judgement.';
          v_basis := jsonb_build_object('answered_by', 'reviews', 'review_id', v_rev.id,
                                        'rating', v_rev.rating, 'supplier_id', v_rev.supplier_id,
                                        'app_rating', v_lead.app_rating, 'app_reviews', v_lead.app_reviews,
                                        'rule', 'rating >= 3 => no change to standing');
        else
          v_reason := 'review #' || v_rev.id || ' rates the supplier ' || v_rev.rating || '/5. A rating '
            || 'of 1 or 2 may change the supplier''s standing and no written policy decides that, so it '
            || 'stays with the ' || coalesce(r.assigned_agent, '?') || ' seat.';
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
          -- (a tracked-gap close answered nothing, so its gap row stays 'open')
          if r.action_class = 'knowledge_gap' and not v_tracked then
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
             -- A STANDING GAP, NOT A FRESH FAILURE EVERY FIFTEEN MINUTES. This is the convention
             -- #744 added on 18 Sep 2026 after duty:renewal:...:date_unknown was re-raised 320
             -- times in four days: fn_it_duty_settle holds an already-open finding carrying
             -- 'config' => true, refreshing its title and evidence to today's reading while
             -- seen_count, last_seen_at and started_at stand still. That is exactly this subject.
             -- Nothing about the running system changes between two ticks over the same queue;
             -- what is missing is knowledge nobody has written or a supplier nobody has onboarded.
             -- Without the flag this finding's seen_count would climb 96 times a day and bury
             -- every finding that did move. A CLOSED one still reopens, because a class that
             -- emptied and came back IS news.
             'config', true,
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
-- fn_it_platform_ingest v2. Only the PITR item changes; the daily-backup, disk and members
-- readings are the v1 body verbatim.
--
-- PITR is a PAID Supabase add-on (https://supabase.com/docs/guides/platform/backups, read 21 Sep
-- 2026: 7 days ~$100/month ($0.137/h), 14 days ~$200 ($0.274/h), 28 days ~$400 ($0.55/h); Pro plan
-- or above; at least the Small compute add-on; outside the Spend Cap). Turning it on spends money,
-- so it is the founder's decision and the duty records it as awaiting that decision -- ONCE:
-- 'config' => true makes fn_it_duty_settle hold the open finding instead of raising it again.
-- The decision register is public.company_policy_decision:
--   no 'supabase_pitr_addon:%' row          -> held finding "awaiting the founder's decision"
--   'supabase_pitr_addon:declined' present  -> no item; settle closes the finding on the next reading
--   'supabase_pitr_addon:approved' present  -> PITR still off is a real defect (not config, not held)
-- The detector still reads pitr_enabled on every run; nothing is suppressed, only classified.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_it_platform_ingest(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; v_out jsonb := '{}'::jsonb; v_pitr_decision text;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then raise exception 'fn_it_platform_ingest takes the platform readings object'; end if;
  if p_r->'backups'->>'basis' = 'measured' then
    if not coalesce((p_r->'backups'->>'pitr_enabled')::boolean, false) then
      select split_part(d.decision_key, ':', 2) into v_pitr_decision
        from public.company_policy_decision d
       where d.decision_key in ('supabase_pitr_addon:declined', 'supabase_pitr_addon:approved')
       order by d.recorded_at desc limit 1;
      if v_pitr_decision is null then
        v_items := v_items || jsonb_build_object('item', 'pitr', 'owner_seat', 'ceo', 'subject', 'database',
          'title', 'Point-in-time recovery is off: a paid Supabase add-on (from ~$100/month) awaiting the founder''s decision',
          'blast', 'agent_facing', 'affected', 1, 'config', true,
          'evidence', coalesce(p_r->'backups', '{}'::jsonb) || jsonb_build_object(
            'awaiting', 'founder decision on a paid add-on',
            'price_usd_per_month', jsonb_build_object('7_days', 100, '14_days', 200, '28_days', 400),
            'price_usd_per_hour', jsonb_build_object('7_days', 0.137, '14_days', 0.274, '28_days', 0.55),
            'requires', 'Pro plan or above and at least the Small compute add-on; not covered by the Spend Cap',
            'source', 'https://supabase.com/docs/guides/platform/backups (read 2026-09-21)',
            'decide_with', 'insert into public.company_policy_decision (decision_key, decided_on, decision_text) values (''supabase_pitr_addon:declined'' or ''supabase_pitr_addon:approved'', current_date, ''<his words>'')'));
      elsif v_pitr_decision = 'approved' then
        v_items := v_items || jsonb_build_object('item', 'pitr', 'owner_seat', 'ceo', 'subject', 'database',
          'title', 'Point-in-time recovery is still off although the founder approved the add-on',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', coalesce(p_r->'backups', '{}'::jsonb) || jsonb_build_object('decision', 'supabase_pitr_addon:approved'));
      end if;
      -- 'declined': no item. fn_it_duty_settle closes duty:db_backup:pitr as no longer found, and
      -- the decision row is where the reason lives.
    end if;
    if (p_r->'backups'->>'latest_backup_at') is null or (p_r->'backups'->>'latest_backup_at')::timestamptz < now() - interval '26 hours' then
      v_items := v_items || jsonb_build_object('item', 'daily_backup', 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'The newest database backup is ' || coalesce('from ' || (p_r->'backups'->>'latest_backup_at'), 'missing'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'backups');
    end if;
    v_out := v_out || jsonb_build_object('db_backup', public.fn_it_duty_settle('db_backup', v_items));
  end if;
  if p_r->'disk'->>'basis' = 'measured' and (p_r->'disk'->>'size_bytes') is not null then
    update public.it_threshold set value = (p_r->'disk'->>'size_bytes')::numeric,
           basis = 'management API disk size, read ' || now()::date where key = 'db_disk_limit_bytes';
  end if;
  if p_r->'members'->>'basis' = 'measured' then
    v_out := v_out || jsonb_build_object('supabase_access',
      public.fn_it_duty_settle('supabase_access', public.fn_it_access_items(jsonb_build_object('supabase', p_r->'members'))));
  end if;
  perform public.fn_it_duty_ran('platform', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_platform_ingest(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- PROBE -> one verdict row. Every write happens inside an inner block that ends by raising
-- 'zz_probe_rollback', so that subtransaction (the ZZ DEMO task, the settle writes, the decision
-- row) is rolled back while the definitions above stand. The dry run over the live queue writes
-- nothing. The probe then counts the real assigned tasks and open gaps to prove it left no trace.
-- ---------------------------------------------------------------------------------------------
create temp table zz_probe_verdict (verdict text, detail jsonb) on commit drop;

do $probe$
declare
  v_assigned int; v_would_close int; v_dry jsonb := '[]'::jsonb;
  v_ok boolean := true; v_notes jsonb := '[]'::jsonb;
  v_id bigint; v_r jsonb; v_f record; v_after int; v_gaps_before int; v_gaps_after int;
begin
  select count(*) into v_assigned from public.org_tasks where status = 'assigned';
  select count(*) into v_gaps_before from public.sales_knowledge_gap where status = 'open';

  -- (1) DRY RUN over every live assigned row: each must now have a deterministic end.
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id,
           'closes', (x.j->>'closed')::int = 1,
           'handler', coalesce(x.j->'done'->0->>'handler', x.j->'queued'->0->>'handler'),
           'outcome', coalesce(x.j->'done'->0->'basis'->>'outcome', x.j->'done'->0->'basis'->>'answered_by'),
           'reason', x.j->'queued'->0->>'reason')), '[]'::jsonb),
         count(*) filter (where (x.j->>'closed')::int = 1)
    into v_dry, v_would_close
    from public.org_tasks o
    cross join lateral (select public.fn_org_task_consume_tick(1, o.id, true) as j) x
   where o.status = 'assigned';
  if v_would_close <> v_assigned then
    v_ok := false; v_notes := v_notes || to_jsonb('dry run: ' || v_would_close || ' of ' || v_assigned || ' would close');
  end if;

  begin
    -- (2) LIVE close of an unanswerable ZZ DEMO question: closes as a tracked gap, gap stays open.
    insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                  priority, requires_evidence, needs_founder)
    values ('ZZ DEMO consumer probe: unanswerable question',
            'ZZ DEMO row.' || E'\n\nQUESTION: zzdemo quux frobnicate the wibble' || E'\nREFUSAL: probe',
            'assigned', 'advisory', 'knowledge_gap', 'customer_support', 1, true, false)
    returning id into v_id;
    v_r := public.fn_org_task_consume_tick(1, v_id, false);
    if (select status from public.org_tasks where id = v_id) <> 'done'
       or not exists (select 1 from public.sales_knowledge_gap where task_id = v_id and status = 'open') then
      v_ok := false; v_notes := v_notes || jsonb_build_object('tracked_gap_live', v_r);
    end if;

    -- (3) PITR: undecided -> one held 'awaiting' finding; declined -> closed.
    perform public.fn_it_platform_ingest(jsonb_build_object('backups',
      jsonb_build_object('basis', 'measured', 'pitr_enabled', false, 'latest_backup_at', now())));
    select * into v_f from public.it_engineer_finding where issue_key = 'duty:db_backup:pitr';
    if v_f.closed_at is not null or v_f.title not like '%awaiting the founder%' then
      v_ok := false; v_notes := v_notes || to_jsonb('pitr undecided: ' || coalesce(v_f.title, 'no finding'));
    end if;
    insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text)
    values ('supabase_pitr_addon:declined', current_date, 'founder', 'ZZ DEMO probe decision');
    perform public.fn_it_platform_ingest(jsonb_build_object('backups',
      jsonb_build_object('basis', 'measured', 'pitr_enabled', false, 'latest_backup_at', now())));
    if (select closed_at from public.it_engineer_finding where issue_key = 'duty:db_backup:pitr') is null then
      v_ok := false; v_notes := v_notes || to_jsonb('pitr declined: finding did not close'::text);
    end if;

    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then
      v_ok := false; v_notes := v_notes || to_jsonb('probe raised: ' || sqlerrm);
    end if;
  end;

  select count(*) into v_after from public.org_tasks where status = 'assigned';
  select count(*) into v_gaps_after from public.sales_knowledge_gap where status = 'open';
  if v_after <> v_assigned or v_gaps_after <> v_gaps_before
     or exists (select 1 from public.company_policy_decision where decision_key like 'supabase_pitr_addon:%') then
    v_ok := false; v_notes := v_notes || to_jsonb('probe left a trace'::text);
  end if;

  insert into zz_probe_verdict values (
    case when v_ok then 'PROBE OK' else 'PROBE FAILED' end,
    jsonb_build_object('assigned', v_assigned, 'would_close', v_would_close, 'notes', v_notes, 'dry', v_dry));
end
$probe$;

select verdict, detail from zz_probe_verdict;
