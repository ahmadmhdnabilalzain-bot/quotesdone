-- A SUPPLIER REGISTRATION RECORD CLOSES ON ITS LEAD, NOT ON A LICENCE LINE.
--
-- Assigned: it_engineer (the org_task consumer; the tasks it closes belong to sales_engineer). 21 Sep 2026.
--
-- ══ MEASURED, 21 Sep 2026 ~18:30 UTC, htdblwldjkcgjvmqkbeh (read-only) ═══════════════════════
-- The founder's 17:46 and 19:01 emails ("N org_task(s) of class routine_operational_decision are
-- queued on the sales_engineer seat and the consumer cannot finish them"; the same for knowledge_gap
-- on customer_support) were raised by fn_org_task_consume_tick v1, which had no handler for either
-- class. v2 (every_queued_org_task_class_has_a_deterministic_end.sql, applied 15:32Z) closed all six
-- of those rows. The finding REOPENED at 17:00Z on two NEW rows, both kind supplier_registered:
--   579041  "New supplier \"ZZ DEMO Registration Walk EN LLC\" ... Decision: approved. No action
--           needed; this is a record."                                      (seen_count 7)
--   579076  "... Decision: action_required — the signed terms certificate is being issued. ..."
-- v2's reason on both: "the task does not carry the supplier name, licence and decision". Cause:
--   1. v2 required a "Licence X," line. supplier_api/index.ts (save_profile, firstSubmit) appends
--      that line ONLY when the lead has a trade_license_no; otherwise licInfo is ''. So every
--      registration announced without a licence stays queued for ever.
--   2. v2 closed only when leads.approval_status equalled the announced decision. 'action_required'
--      with the certificate on its way is a record ("No action needed"), and the status moves on
--      (to approved) as soon as the certificate issues -- so an honest announcement read as a
--      disagreement.
--   3. Both announced ZZ DEMO registration walks whose leads the walk had already deleted: 0 rows in
--      public.leads for either name. A removed fixture was reported as "a supplier the register does
--      not hold" -- a real-looking discrepancy made of a rehearsal.
--
-- ══ WHAT THIS FILE CHANGES ═══════════════════════════════════════════════════════════════════
-- fn_org_task_consume_tick v3 -- ONLY the supplier_registered branch and the version stamp:
--   * the name identifies the lead; the licence narrows the match when the announcement carries one;
--     two leads of one name with no licence stay queued ("the seat identifies which one").
--   * a ZZ DEMO name with no lead left closes as "the condition is gone" (a removed fixture).
--   * approved / action_required close on the record; 'pending' stays queued while the lead is still
--     pending (auto-approve off: that IS the seat's decision); banned or an approved announcement the
--     register contradicts stay queued, as before.
--   * version 'v3': rows parked by a v2 verdict are retried on the next tick, not after their back-off.
-- NOT CHANGED: every other branch (knowledge_gap, expense_logged, rfq_no_supplier, sales_rating) is
-- byte-identical to v2; the per-class census and fn_it_duty_settle; supplier_api's announcement text.
-- RECURRENCE: the probe below replays both failing announcements (no licence line; action_required;
-- fixture removed) and a pending one, and answers PROBE FAILED if any ends the wrong way.
--
--   node scripts/apply_sql.mjs scripts/sql/a_supplier_registration_record_closes_on_its_lead_not_on_a_licence_line.sql --apply --ddl

create or replace function public.fn_org_task_consume_tick(p_limit integer DEFAULT 4, p_task_id bigint DEFAULT NULL::bigint, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
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
            or o.last_run_at < now() - make_interval(mins => (15 * power(2, least(o.attempts, 6)))::int)
            -- A BACK-OFF EARNED UNDER OTHER HANDLERS DOES NOT BIND THESE. Measured on apply,
            -- 21 Sep 2026: the first v2 tick scanned 0 of 8 assigned rows, because every one was
            -- inside a 4h/16h window earned from a v1 "not_yet" -- a verdict v2 no longer gives.
            -- A row whose last verdict came from an older consumer version is retried at once.
            or coalesce(o.result->'consumer'->>'version', '') <> 'v3')
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
    -- The task announces a decision already taken ("... No action needed; this is a record."). The
    -- decider checks the record against public.leads and closes on it.
    --
    -- 21 SEP 2026 — THE LICENCE IS NOT PART OF THE ANNOUNCEMENT'S IDENTITY. Measured on
    -- htdblwldjkcgjvmqkbeh: org_tasks 579041 and 579076 stayed 'assigned' and re-raised
    -- duty:org_task_queue:routine_operational_decision:sales_engineer to the founder because v2
    -- required a "Licence X," line, and supplier_api/index.ts writes that line only when the lead has
    -- a trade_license_no (its licInfo is '' otherwise). Both announcements named ZZ DEMO registration
    -- walks whose leads the walk had already deleted, and 579076 announced 'action_required' (the
    -- terms certificate on its way) -- a record, not a pending decision, which v2 also refused as
    -- "the register disagrees". Now: the name identifies the lead (the licence narrows it when the
    -- announcement carries one); a removed ZZ DEMO fixture is a condition that is gone; only a
    -- 'pending' announcement still waiting on the seat stays queued, because that one IS a decision.
    elsif r.action_class = 'routine_operational_decision'
          and coalesce(r.result->'founder_mail'->>'kind', '') = 'supplier_registered' then
      v_handler  := 'leads';
      v_vendor   := substring(r.detail from 'New supplier "([^"]+)"');
      v_lic      := nullif(btrim(substring(r.detail from 'Licence ([^,]+),')), '');
      v_decision := lower(substring(r.detail from 'Decision: ([A-Za-z_]+)'));

      select count(*)::int into v_matches
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic);

      select l.id, l.company_name, l.trade_license_no, l.approval_status, l.approval_decided_by,
             l.approved_at, coalesce(l.banned, false) as banned, l.license_expiry, l.is_demo
        into v_lead
        from public.leads l
       where l.company_name = v_vendor and (v_lic is null or l.trade_license_no = v_lic)
       order by l.id desc limit 1;

      if v_vendor is null or v_decision is null then
        v_reason := 'the task does not carry the supplier name and decision in the form '
          || 'supplier_api writes them ("New supplier \"<name>\" ... Decision: <status>"), so the '
          || 'record cannot be checked';
      elsif v_matches = 0 and v_vendor ~ '^ZZ DEMO' then
        v_deliv := 'THE CONDITION IS GONE. The task announced the ZZ DEMO fixture supplier "' || v_vendor
          || '" as ' || v_decision || '. public.leads no longer holds it: the rehearsal that registered '
          || 'it removed its own fixture, so there is no supplier to welcome and no record to reconcile.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_present', false, 'fixture', true,
                                      'announced', v_decision);
      elsif v_matches = 0 then
        v_reason := 'no public.leads row is named "' || v_vendor || '"'
          || coalesce(' with licence ' || v_lic, '')
          || ': the announcement names a supplier the register does not hold';
      elsif v_matches > 1 then
        v_reason := v_matches || ' public.leads rows are named "' || v_vendor || '" and the announcement '
          || 'carries no licence to tell them apart; the seat identifies which one registered';
      elsif v_lead.banned then
        v_reason := 'leads #' || v_lead.id || ' is BANNED while the task announced "' || v_decision
          || '". That is the seat''s to reconcile.';
      elsif v_decision = 'pending' and coalesce(v_lead.approval_status, 'pending') = 'pending' then
        v_reason := 'leads #' || v_lead.id || ' is still pending: auto-approve is off and the approval '
          || 'is the ' || coalesce(r.assigned_agent, '?') || ' seat''s decision, not a record';
      elsif v_decision = 'approved' and v_lead.approval_status is distinct from 'approved' then
        v_reason := 'the register disagrees with the announcement: leads #' || v_lead.id
          || ' has approval_status ' || coalesce(v_lead.approval_status, 'null')
          || ' while the task announced "approved". That is the seat''s to reconcile.';
      else
        v_deliv := 'RECORD CONFIRMED -- NO DECISION WAS PENDING. The task announced supplier "'
          || v_vendor || '"' || coalesce(' (licence ' || v_lic || ')', '') || ' as ' || v_decision
          || '. public.leads #' || v_lead.id || ' holds it: approval_status '
          || coalesce(v_lead.approval_status, 'null') || coalesce(' by ' || v_lead.approval_decided_by, '')
          || coalesce(' at ' || v_lead.approved_at::text, '')
          || ', licence ' || coalesce(v_lead.trade_license_no, '(none recorded)')
          || coalesce(' expiring ' || v_lead.license_expiry::text, '') || ', not banned.'
          || E'\n\nThe task''s own words are "No action needed; this is a record": the record exists, '
          || 'so it closes on that fact. What the supplier still owes is on its own registration '
          || 'email and portal, not on this seat.';
        v_basis := jsonb_build_object('answered_by', 'leads', 'lead_id', v_lead.id, 'announced', v_decision,
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
                   'at', now(), 'version', 'v3', 'handler', v_handler, 'verdict', 'not_yet', 'reason', v_reason,
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

revoke execute on function public.fn_org_task_consume_tick(integer, bigint, boolean) from public, anon, authenticated;

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW. Every write (the ZZ DEMO org_tasks rows) happens inside an
-- inner block that ends by raising 'zz_probe_rollback', which undoes that subtransaction and keeps
-- the definition. The consumer runs in DRY-RUN mode on each probe row: it reads, never closes.
-- One real approved lead is READ (never written) to prove a record without a licence line closes.
create temp table if not exists zz_probe_verdict (verdict text, detail jsonb) on commit drop;
do $probe$
declare
  v_ok boolean := true; v_notes jsonb := '[]'::jsonb; v_id bigint; v_r jsonb;
  v_before int; v_after int; v_lead record; v_nonce text := substr(md5(clock_timestamp()::text), 1, 8);
  c record;
begin
  select count(*) into v_before from public.org_tasks where status = 'assigned';
  select l.company_name, count(*) over (partition by l.company_name) as n into v_lead
    from public.leads l where l.approval_status = 'approved' and not coalesce(l.banned, false)
   order by l.id limit 1;

  begin
    for c in
      select * from (values
        -- 579041's shape: approved, no licence line, fixture already removed           -> close
        ('fixture approved', 'ZZ DEMO Probe ' || v_nonce || ' EN LLC', 'approved', true),
        -- 579076's shape: action_required with the certificate on its way, removed      -> close
        ('fixture action_required', 'ZZ DEMO Probe ' || v_nonce || ' ar desktop', 'action_required — the signed terms certificate is being issued', true),
        -- a real-looking name the register does not hold                                 -> stays queued
        ('absent non-fixture', 'Zz Probe Absent Trading ' || v_nonce, 'approved', false),
        -- a live approved lead announced without a licence line                          -> close
        ('live lead, no licence line', v_lead.company_name, 'approved', v_lead.n = 1)
      ) as t(label, name, decision, expect_close)
      where t.name is not null
    loop
      insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                    priority, requires_evidence, needs_founder, result)
      values ('ZZ DEMO consumer probe: ' || c.label,
              '[founder_mail:supplier_registered] New supplier "' || c.name || '" (Dubai) registered. Decision: '
                || c.decision || '. No action needed; this is a record.',
              'assigned', 'advisory', 'routine_operational_decision', 'sales_engineer', 1, true, false,
              jsonb_build_object('founder_mail', jsonb_build_object('kind', 'supplier_registered')))
      returning id into v_id;
      v_r := public.fn_org_task_consume_tick(1, v_id, true);
      if ((v_r->>'closed')::int = 1) is distinct from c.expect_close then
        v_ok := false;
        v_notes := v_notes || jsonb_build_object('case', c.label, 'expected_close', c.expect_close,
                     'got', coalesce(v_r->'done'->0->'basis', v_r->'queued'->0->'reason'));
      else
        v_notes := v_notes || jsonb_build_object('case', c.label, 'ok', true);
      end if;
    end loop;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then
      v_ok := false; v_notes := v_notes || to_jsonb('probe raised: ' || sqlerrm);
    end if;
  end;

  select count(*) into v_after from public.org_tasks where status = 'assigned';
  if v_after <> v_before or exists (select 1 from public.org_tasks where title like 'ZZ DEMO consumer probe:%') then
    v_ok := false; v_notes := v_notes || to_jsonb('probe left a trace'::text);
  end if;
  insert into zz_probe_verdict values (case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, v_notes);
end
$probe$;

select verdict, detail from zz_probe_verdict;
