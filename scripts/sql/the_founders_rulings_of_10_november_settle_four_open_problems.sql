-- THE FOUNDER'S RULINGS OF 10 NOVEMBER SETTLE FOUR OPEN PROBLEMS.
-- Seat: ceo (the founder's rulings). The accountant's parts: items 1 and 2. The it_engineer's: item 4. Item 3 is the
-- sales_engineer's queue, closed under the ceo's ruling. 10 Nov 2026.
--
-- The founder ruled on 10 Nov 2026, recorded in public.founder_instruction:
--   1558  "The seven Stripe TEST-mode payments of 3 Nov were made by Claude sessions' tests, not by customers."
--   1559  "No bank statement reconciliation. Near each month end the founder will tell the session to scan his email and
--          check the receipts there." (supersedes the bank-statement parts of 369 and 1011)
--   1560  "The founder does not know about the 25 database routines changed outside apply_sql. Find out who changed them
--          and settle them."
--   1561  "All data so far is demo: the CAD/drawing jobs, customers and suppliers are not real."
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026 ~01:00-02:00Z). 29 open findings, every
-- one with an it_incident and a pending it.finding handoff to a seat, and an accepted 'it_loop:<handoff>' CEO report:
--
--   1. acct:reveal_reconcile:test_mode_not_demo:<pi> x7, customer_facing, open since 4 Nov 05:50Z, seen 139 times each.
--      Stripe TEST mode (livemode false), paid 3 Nov 09:10:54Z-09:25:22Z, AED 614.04 in all: pi_3UXdk2C45SqX5pVb0pULMNhu
--      74.04, pi_3UXdk2C45SqX5pVb1G6cBfjq 30.00, pi_3UXdr9C45SqX5pVb3dW8oeLF 150.00, pi_3UXdy2C45SqX5pVb037Pk7d2 150.00,
--      pi_3UXdy2C45SqX5pVb1NN05C7Q 150.00, pi_3UXdy2C45SqX5pVb2mhf67d4 30.00, pi_3UXdy2C45SqX5pVb2TTxlJtu 30.00. Each is a
--      bare PaymentIntent: no receipt e-mail, no customer id, and its quote no longer exists in public.quotes (a test
--      teardown deleted it). So fn_is_demo_email(null) is false and the sweep cannot prove it demo. The other 40 rows of
--      accountant_reveal_reconcile_item are test payments the sweep already marks demo (example.invalid addresses).
--      WHY IT KEEPS COMING BACK: the hourly sweep reads the same test payment for 30 days (to 3 Dec), and the record
--      routine's upsert sets resolved_at to NULL for every outcome it does not name, test_mode_not_demo included, while
--      fn_it_engineer_finding_upsert reopens a closed finding and wipes its close note. A close by hand lasts one hour.
--      There is no resolve routine in this subsystem: the record routine is the item's only writer.
--   2. acct:bank_statement_2026_09:* x6, agent_facing, raised once on 4 Oct 20:38Z and never seen again. No routine in
--      production (pg_proc searched) and no file in this repository names duty 'bank_statement_2026_09': a session read
--      the September statement by hand (intake 'chat:mashreq-statement-2026-09') and filed them through
--      fn_accountant_duty_settle. Nothing re-raises them. What WOULD ask for a statement, all dormant today:
--        * fn_accountant_bank_reconcile item 'statement:<YYYY-MM>' ("forward the statement ... to expenses@") once a month
--          has live payouts (0 live payouts of 7), and 'unreadable:<ref>' (asks for the CSV);
--        * fn_accountant_bank_balance_tick item 'bank_balance:<YYYY-MM>' (the closing balance) once a later month closes;
--        * fn_accountant_cash_truth_check: an elevated CEO report "the books' bank account differs from the bank statement"
--          every month the gap passes AED 1 (sent 28 Sep, 5 Oct and 1 Nov: -187.85, 523.71, -782.39).
--      The one SCHEDULED reconciliation duty is seat_duty accountant.receipt_bank_match (daily, its own pg_cron job
--      'seat_duty:accountant.receipt_bank_match'): every expense receipt paired with the Mashreq debit that paid it.
--      notifications of the last 60 days: no message asks the founder for a statement (the weekly report and the close
--      pack only SAY a figure is a book balance or name the statement).
--   3. sales_engineer:cad_read_held:<hour> x10 (27 Oct 07Z to 3 Nov 15Z) and cad_read_worker:job_failed (14 Oct), all
--      customer_facing. All ten held jobs are gone from public.cad_read_jobs: rows there are removed only by the demo
--      purge (fn_demo_purge_run, demo customers and demo addresses only), the e2e teardown of
--      scripts/e2e/every_drawing_format_is_read.mjs (its own ZZ DEMO customer) and a probe. Every held finding says
--      why = over_edge_ceiling, the e2e's 'ZZ DEMO large.dwg' (2,179,278 bytes). The failed job ad92cb2d is
--      'ZZ DEMO large.dwg' of qd-06872a42-cust0@example.invalid. cad_read_jobs holds 4 rows, all ZZ DEMO.
--   4. duty:unsigned_change:tx13968927 (30 Sep 00:44Z, 21 log rows = 12 routines), tx17314797 (27 Oct, 2), tx18281068
--      (1 Nov, 1), tx18310487 (1 Nov, 1): application_name mgmt-api as postgres, a Claude session's SQL through the
--      Supabase management API instead of scripts/apply_sql.mjs. duty:unsigned_revision:rev:5ec4ba8: txid 15743633,
--      19 Oct 12:47Z, 'qd-apply 5ec4ba8 it_engineer ... a_seats_own_pack_fills_ha...', a local commit GitHub places on no
--      merged or open pull request (compare: diverged); two of its six changes were never re-applied from main.
--      VERIFIED PER ROUTINE (the canonical_routine_manifest.mjs rule: the canonical file is the last MANIFEST file that
--      defines it, compared on tokens with the live prosrc, every overload both ways) against origin/main 17098f34b:
--      all 17 routines these five transactions created are IDENTICAL to their canonical reviewed file, and the two
--      overloads txid 15743633 dropped are absent live. The whole check on the same day: REPOSITORY->PRODUCTION drift
--      0, PRODUCTION->REPOSITORY drift 0. Nothing here is "not identical", so nothing is left unaccepted.
--
-- WHAT THIS FILE DOES (one transaction; the applier adds none):
--   1. TEST PAYMENTS. fn_accountant_reveal_reconcile_record (canonical body of
--      a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql, byte for byte but one case arm): a TEST-mode
--      payment the accountant resolved STAYS resolved when the sweep reads it again. The seven are resolved by exact key,
--      each re-checked at apply (test mode, outcome test_mode_not_demo, quote absent, no sale holds its PaymentIntent),
--      and their findings closed citing ruling 1558. NOT ADOPTED, NOTED: a rule that would have classified them as test
--      automatically ("a test-mode payment whose quote is not in public.quotes revealed nothing") reverses the #1841
--      review's "an unanswerable check is no", the check's pinned demo contract, and the reveal probe's case 3, which uses
--      a quote id that does not exist to stand for a real quote. A future bare test PaymentIntent on a deleted quote is
--      therefore still filed once, for the accountant to resolve, and from now on it stays resolved.
--   2. NO BANK STATEMENT RECONCILIATION. The ruling is recorded once, as company_policy_decision
--      'no_bank_statement_reconciliation' (the register fn_accountant_duty_settle already reads for ruling 585; lifting the
--      rule is deleting that row). seat_duty accountant.receipt_bank_match is RETIRED the way it_engineer.knowledge_exam
--      was (routine_work_is_code_and_the_model_answers_only_real_judgement.sql: enabled false, its `what` says why) and its
--      pg_cron job is unscheduled. fn_accountant_duty_settle (canonical body of
--      a_missing_receipt_the_founder_ruled_a_waiting_item_leaves_no_open_handoff.sql plus one gate): while the decision
--      stands, the bank duty's two asks (statement:<month> "forward the statement", unreadable:<ref> "forward the CSV")
--      and every bank_balance item (the closing balance only a statement gives) are the accountant's `waiting` items,
--      never findings. What statements already held show (missing:, unexplained:) and every payout fact Stripe states
--      (failed, transit, breakdown, currency) stay findings: they ask nobody for anything, and the IT loop's own probes
--      use acct:bank:missing: as their fixture. fn_accountant_cash_truth_check keeps its forecast-against-position check and
--      sends no books-against-statement report. The six findings close citing ruling 1559.
--   3. DEMO CAD JOBS. The eleven findings close citing ruling 1561, each only when its job is gone or is demo (a demo
--      address, a demo customer or a ZZ DEMO file); a job that looked real would be skipped and named. No job row changes:
--      the ten held jobs no longer exist and the failed one is finished. The 3 ZZ DEMO jobs left (1 failed 13 Oct, 2 queued
--      10 Nov 00:44Z and 00:50Z by a demo customer) are the demo purge's to remove.
--   4. UNSIGNED CHANGES. Each transaction is accepted with public.fn_it_change_accept(txid, 'ceo', why) only when, at
--      apply, every routine it created still has the md5(pg_get_functiondef) measured today and every routine it dropped
--      is still absent; a transaction whose routines moved since is skipped and named. fn_it_change_watch then closes the
--      four unsigned_change findings ('accepted by the ceo: ...') and, through its SETTLED rule
--      (a_revision_off_main_is_settled_once_its_routines_are_reapplied_or_accepted.sql), the 5ec4ba8 revision finding.
--      No verdict is rewritten: 5ec4ba8 stays not_on_main in it_change_revision.
--   5. THE LOOPS. Each of the 29 handoffs is closed through the learning gate's own door, fn_it_attach_learning (z62 is
--      not bypassed), with the ruling as its cause, by exact handoff id and issue key, only once its finding is closed; an
--      earlier note on the incident is kept inside the new cause. Its 'it_loop:<id>' CEO report completes by exact key.
--
-- DELIBERATELY LEFT ALONE (named so it is not lost):
--   * The accountant's MONTH CLOSE still waits for a Mashreq statement (fn_accountant_month_close_status
--     'waiting_for_statement'): the October close has waited since 5 Nov (CEO report 24071), so no October close pack
--     reaches the founder. Closing a month on receipts instead is the accountant's redesign under ruling 1559, not a
--     settlement; fn_accountant_close_by_day_5 keeps saying so to the CEO, which is the signal that it is owed.
--   * The cash figures (fn_accountant_cash_position, fn_finance_forecast, the 13-week forecast) still open from the last
--     statement (30 Sep, AED 59.25). Same redesign.
--   * fn_accountant_bank_reconcile, fn_accountant_bank_balance_tick and the bank statement reader are not redefined:
--     the gate above silences what they would ask, and lifting the decision row restores them unchanged.
--   * The 40 demo reveal items, 2 queued ZZ DEMO CAD jobs and every other open finding: untouched.
--
-- Prevented by: scripts/checks/the_founders_rulings_of_10_november_settle_four_open_problems.test.mjs (fails if the
-- retired duty is scheduled again, or a later definition drops the bank gate, the cash-truth gate or the stay-resolved
-- rule) and the verdict row at the end of this file (read-only; it never raises).
--   applied at merge: node scripts/apply_sql.mjs scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql --apply --ddl --seat ceo

-- ── 2. the ruling, recorded once where the accountant's settle reads rulings ─────────────────────────────────────
insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text, applies_to, never_ask_again)
values ('no_bank_statement_reconciliation', date '2026-11-10', 'founder',
  'Founder ruling 1559, 10 Nov 2026: "No bank statement reconciliation. Near each month end the founder will tell the session to scan his email and check the receipts there." It supersedes the bank-statement parts of rulings 369 and 1011. No seat asks him for a bank statement; the receipt-to-bank-line duty is retired, and the bank duties hold what a statement would have answered as waiting, not as findings.',
  array['accountant', 'ceo'], true)
on conflict (decision_key) do update set decided_on = excluded.decided_on, decided_by = excluded.decided_by,
  decision_text = excluded.decision_text, applies_to = excluded.applies_to, never_ask_again = excluded.never_ask_again;

-- ── 1. a resolved test-mode payment stays resolved ───────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_reveal_reconcile_record(p_run_id bigint, p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_run bigint; x jsonb; n_kept int := 0; n_refused int := 0; n_resolved int := 0; v_demo boolean; v_qid uuid;
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if jsonb_typeof(p_r) is distinct from 'object' or jsonb_typeof(coalesce(p_r->'outcomes', '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_accountant_reveal_reconcile_record(run, readings): readings must be an object with an outcomes array';
  end if;
  select id into v_run from public.accountant_reveal_reconcile_run where id = p_run_id;
  if v_run is null then   -- a call the duty did not dispatch (the founder, by hand): it is a run of its own
    insert into public.accountant_reveal_reconcile_run (window_days)
    values (greatest(1, least(90, coalesce(nullif(p_r->>'days', '')::int, 30)))) returning id into v_run;
  end if;
  update public.accountant_reveal_reconcile_run
     set reported_at = now(),
         result = (p_r - 'outcomes') || jsonb_build_object('reported', jsonb_array_length(coalesce(p_r->'outcomes', '[]'::jsonb)))
   where id = v_run;

  for x in select e from jsonb_array_elements(coalesce(p_r->'outcomes', '[]'::jsonb)) e loop
    if coalesce(x->>'key', '') !~ '^(in|pi)_[A-Za-z0-9_]+$' or coalesce(btrim(x->>'quote_id'), '') = ''
       or coalesce(x->>'outcome', '') not in ('recovered', 'second_payment', 'refunded', 'refunded_unrecorded', 'failed', 'deferred', 'test_mode_not_demo')
       or coalesce(x->>'source', '') not in ('invoice', 'payment_intent') then
      n_refused := n_refused + 1;   -- 'recorded' (a plain match) never needs a row; anything malformed is refused, not guessed
      continue;
    end if;
    v_qid := case when x->>'quote_id' ~ c_uuid then (x->>'quote_id')::uuid end;
    -- DEMO: a test-mode payment, an email the one demo rule names, or a customer the database marks is_demo.
    -- 'test_mode_not_demo': a test payment whose quote is not provably a demo account's. It reaches the findings,
    -- unless Stripe's own customer e-mail is a demo address (fn_is_demo_email, the identity that picks the Stripe test
    -- key, #1835): the e2e teardown deletes a demo quote while its paid test invoice stays in the window, and that is
    -- demo, not a finding.
    v_demo := case when x->>'outcome' = 'test_mode_not_demo' then public.fn_is_demo_email(x->>'customer_email')
      else (not coalesce((x->>'livemode')::boolean, false)
           or public.fn_is_demo_email(x->>'customer_email')
           or exists (select 1 from public.customers c where c.is_demo and c.id::text = x->>'customer_id')
           or exists (select 1 from public.quotes q join public.inquiries iq on iq.id = q.inquiry_id
                        join public.customers c on c.id = iq.customer_id where q.id = v_qid and c.is_demo)) end;
    insert into public.accountant_reveal_reconcile_item as it (key, livemode, source, quote_id, invoice_id, payment_intent,
        customer_id, customer_email, amount_fils, currency, paid_at, demo, outcome, transaction_id, error, last_run_id, resolved_at)
    values (x->>'key', coalesce((x->>'livemode')::boolean, false), x->>'source', x->>'quote_id', nullif(x->>'invoice_id', ''),
        nullif(x->>'payment_intent', ''), nullif(x->>'customer_id', ''), lower(nullif(x->>'customer_email', '')),
        nullif(x->>'amount_fils', '')::bigint, nullif(x->>'currency', ''),
        case when x->>'paid_at' ~ '^[0-9]+$' then to_timestamp((x->>'paid_at')::bigint) end,
        v_demo, x->>'outcome', case when x->>'transaction_id' ~ c_uuid then (x->>'transaction_id')::uuid end,
        left(nullif(x->>'error', ''), 1000), v_run,
        case when x->>'outcome' in ('recovered', 'refunded') then now() end)
    -- 'deferred' says only "not looked at this run": it never overwrites what an earlier run found (failed, second payment).
    on conflict (key) do update set
        outcome = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.outcome else excluded.outcome end,
        error = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.error else excluded.error end,
        demo = excluded.demo,
        payment_intent = coalesce(excluded.payment_intent, it.payment_intent),
        customer_email = coalesce(excluded.customer_email, it.customer_email),
        transaction_id = coalesce(excluded.transaction_id, it.transaction_id),
        attempts = it.attempts + 1, last_seen_at = now(), last_run_id = excluded.last_run_id,
        resolved_at = case when excluded.outcome in ('recovered', 'refunded') then coalesce(it.resolved_at, now())
                           when excluded.outcome = 'deferred' then null
                           -- Founder ruling 1558 (10 Nov 2026): a TEST-mode payment the accountant resolved stays resolved.
                           -- Test mode moves no money, and the sweep reads the same payment every hour for 30 days.
                           when excluded.outcome = 'test_mode_not_demo' and not excluded.livemode then it.resolved_at end
    -- 10 Nov 2026: after 10 attempts (ten hourly sweeps) an item still open as failed / test_mode_not_demo /
    -- refunded_unrecorded is not rewritten again. Its finding stays open, built from the unresolved item. A result
    -- that resolves it or changes what it is (recovered, refunded, second_payment) is still written.
    -- (Carried from the_it_engineers_detectors_stop_counting_finished_work_as_problems.sql, the line before this file in
    -- MANIFEST.txt: without it this later definition would win at merge and drop that rule. Added by the ceo seat's
    -- seats-act build, 10 Nov 2026, when the_it_engineers_detectors_stop_counting_finished_work_as_problems.test.mjs read
    -- this body and failed.)
    where not (it.resolved_at is null and it.attempts >= 10
               and it.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded')
               and excluded.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded', 'deferred'));
    n_kept := n_kept + 1;
  end loop;

  -- A payment the books now hold by another path (the webhook, a by-hand recording) is resolved, whatever this run saw.
  update public.accountant_reveal_reconcile_item i
     set outcome = 'recorded_elsewhere', resolved_at = now(), transaction_id = t.id
    from public.transactions t
   where i.resolved_at is null and i.outcome in ('failed', 'refunded_unrecorded', 'deferred')
     and ((i.invoice_id is not null and t.stripe_invoice_id = i.invoice_id) or (i.payment_intent is not null and t.payment_ref = i.payment_intent));
  get diagnostics n_resolved = row_count;

  return jsonb_build_object('run', v_run, 'kept', n_kept, 'refused', n_refused, 'resolved_elsewhere', n_resolved,
    'findings', public.fn_accountant_reveal_reconcile_findings());
end $fn$;
revoke execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) to service_role;

-- ── 2. the accountant's settle holds statement items as waiting while the ruling stands ────────────────────────
create or replace function public.fn_accountant_duty_settle(p_duty text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text;
        v_waiting jsonb := '[]'::jsonb; v_receipts_wait boolean; v_no_statement boolean;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_accountant_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  -- Founder instruction 585 (21 Sep 2026): receipts arrive when he forwards them; a missing one is
  -- the accountant's waiting item, not a founder alarm. Read from the decision register, so the rule
  -- is a reviewable row and lifting it is deleting that row.
  v_receipts_wait := p_duty = 'expenses' and exists (select 1 from public.company_policy_decision d
                       where d.decision_key = 'expenses_receipts_are_an_ongoing_routine');
  -- Founder ruling 1559 (10 Nov 2026): no bank statement reconciliation. While its decision row stands, what the bank
  -- duty would ask a statement for (a month's statement not arrived, a statement that could not be read) and every
  -- bank_balance item (the closing balance only a statement gives) is the accountant's waiting item, never a finding,
  -- so no seat asks the founder for a statement. What the statements already held show, and every payout fact Stripe
  -- states, stay findings.
  v_no_statement := p_duty in ('bank', 'bank_balance') and exists (select 1 from public.company_policy_decision d
                       where d.decision_key = 'no_bank_statement_reconciliation');
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_accountant_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    if coalesce(x->>'owner_seat', '') not in ('accountant', 'sales_engineer', 'customer_support', 'ceo') then
      raise exception 'fn_accountant_duty_settle: item % names owner seat %, which is not a seat the loop can hand to', x->>'item', x->>'owner_seat';
    end if;
    v_key := 'acct:' || p_duty || ':' || (x->>'item');
    if v_no_statement and (p_duty = 'bank_balance'
                           or split_part(x->>'item', ':', 1) in ('statement', 'unreadable')) then
      v_waiting := v_waiting || jsonb_build_object('item', x->>'item', 'title', x->>'title', 'evidence', x->'evidence',
                                                   'why', 'founder ruling 1559: no bank statement reconciliation');
      if exists (select 1 from public.it_engineer_finding f where f.issue_key = v_key and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close(v_key,
          'Waiting, not a finding (founder ruling 1559, 10 Nov 2026): no bank statement reconciliation; the accountant '
          || 'tracks this item in its duty result.');
      end if;
      continue;
    end if;
    if v_receipts_wait and (x->>'item') in ('cadence_gaps', 'never_billed', 'renewal_receipt') then
      v_waiting := v_waiting || jsonb_build_object('item', x->>'item', 'title', x->>'title', 'evidence', x->'evidence');
      if exists (select 1 from public.it_engineer_finding f where f.issue_key = v_key and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close(v_key,
          'Waiting, not an alarm (founder instruction 585, 21 Sep 2026): receipts are an ongoing routine the '
          || 'founder forwards to the expenses mailbox; the accountant tracks this item in its duty result.');
      end if;
      -- 21 Sep 2026: a loop escalated before the ruling holds an incident with no learning record, and
      -- fn_it_loop_reverify parks it for ever. The ruling IS the record; the IT engineer still closes.
      perform public.fn_accountant_receipt_incident_learning(v_key);
      continue;
    end if;
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'Accountant duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', coalesce(x->>'subject', 'accountant'),
        'raised_by_seat', 'accountant', 'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'accountant.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'acct:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the accountant''s ' || p_duty || ' duty re-checked and no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0), 'closed', n_closed,
                            'waiting', v_waiting);
end $fn$;
revoke execute on function public.fn_accountant_duty_settle(text, jsonb) from public, anon, authenticated;

-- ── 2. the cash truth check keeps its agreement check and sends no books-against-statement report ──────────────
create or replace function public.fn_accountant_cash_truth_check()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_f jsonb := public.fn_finance_forecast(); v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
        v_a numeric; v_b numeric; v_gap numeric; v_rep jsonb;
begin
  v_a := (v_f->>'cash_now')::numeric; v_b := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  if v_a is distinct from v_b and abs(coalesce(v_a, 0) - coalesce(v_b, 0)) > 1 then
    raise exception 'the forecast cash (%) and the cash position (%) disagree by more than AED 1', v_a, v_b;
  end if;
  v_gap := (v_f->>'gl_minus_bank_aed')::numeric;
  -- Founder ruling 1559 (10 Nov 2026): no bank statement reconciliation, so no books-against-statement report while
  -- its decision row stands. The agreement check above stays: two cash figures that disagree are still a failure.
  if abs(coalesce(v_gap, 0)) > 1 and not exists (select 1 from public.company_policy_decision d
                                                  where d.decision_key = 'no_bank_statement_reconciliation') then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_gl_vs_bank:' || to_char(current_date, 'YYYY-MM'),
      p_severity => 'elevated',
      p_subject => 'The books'' bank account differs from the bank statement by AED ' || v_gap,
      p_evidence => jsonb_build_object('gl_cash_aed', v_f->'gl_cash_aed', 'bank_statement_aed', v_b,
                                       'statement_as_of', v_cp #> '{cash_in_bank,as_of}', 'difference_aed', v_gap),
      p_attempted => '[]'::jsonb,
      p_requested => 'None from you. The accountant reconciles GL account 1000 to the statement line by line; every cash figure already reads the statement.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('forecast_cash_aed', v_a, 'cash_position_aed', v_b, 'agree', true,
                            'gl_minus_bank_aed', v_gap, 'reported_to_ceo', v_rep is not null);
end $fn$;
revoke execute on function public.fn_accountant_cash_truth_check() from public, anon, authenticated;
update public.seat_duty
   set what = 'the forecast and the cash position read the same bank balance (within AED 1). The books-against-statement report to the CEO is off: founder ruling 1559 (10 Nov 2026), no bank statement reconciliation.'
 where duty = 'accountant.cash_truth';

-- ── 2. the scheduled reconciliation duty is retired ──────────────────────────────────────────────────────────────
update public.seat_duty
   set enabled = false, own_job = false,
       what = 'RETIRED 10 Nov 2026 (ceo): founder ruling 1559, no bank statement reconciliation. It paired every expense receipt with the Mashreq debit that paid it. Month-end receipts are checked from the founder''s email when he asks. See scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql.'
 where duty = 'accountant.receipt_bank_match';

create temp table if not exists _qd_resolution (subject text, outcome text, evidence jsonb) on commit drop;

do $retire$
declare v_job bigint;
begin
  for v_job in select jobid from cron.job where jobname = 'seat_duty:accountant.receipt_bank_match' loop
    perform cron.unschedule(v_job);
  end loop;
  insert into _qd_resolution values ('seat_duty accountant.receipt_bank_match', 'RETIRED',
    jsonb_build_object('cron_jobs_left', (select count(*) from cron.job where jobname = 'seat_duty:accountant.receipt_bank_match')));
end
$retire$;

-- ── 1 to 4. the findings, by exact key ───────────────────────────────────────────────────────────────────────────
do $settle$
declare
  v record; o record; f public.it_engineer_finding; it public.accountant_reveal_reconcile_item; j public.cad_read_jobs;
  v_ok boolean; v_why text; r jsonb;
  c_1558 constant text := 'Founder ruling 1558 (10 Nov 2026): a Stripe TEST-mode payment made by a Claude session''s test on 3 Nov, not by a customer. Test mode moves no money and nothing was recorded. Resolved as a test payment by the ceo (scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql).';
  c_1559 constant text := 'Founder ruling 1559 (10 Nov 2026): no bank statement reconciliation; month-end receipts are checked from his email when he asks. This finding came from a one-off hand reading of the September statement on 4 Oct that no duty re-checks. Closed by the ceo (scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql).';
  c_1561 constant text := 'Founder ruling 1561 (10 Nov 2026): all CAD/drawing jobs, customers and suppliers so far are demo. This job is a ZZ DEMO upload of the e2e run, already removed by its own teardown or the demo purge, or finished. Closed by the ceo (scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql).';
begin
  -- 1. the seven test payments
  for v in select * from (values
    ('pi_3UXdk2C45SqX5pVb0pULMNhu'), ('pi_3UXdk2C45SqX5pVb1G6cBfjq'), ('pi_3UXdr9C45SqX5pVb3dW8oeLF'),
    ('pi_3UXdy2C45SqX5pVb037Pk7d2'), ('pi_3UXdy2C45SqX5pVb1NN05C7Q'), ('pi_3UXdy2C45SqX5pVb2mhf67d4'),
    ('pi_3UXdy2C45SqX5pVb2TTxlJtu')) t(k) loop
    select * into it from public.accountant_reveal_reconcile_item where key = v.k;
    v_why := case
      when it.key is null then 'no such item'
      when it.livemode then 'it is a LIVE payment'
      when it.outcome <> 'test_mode_not_demo' then 'its outcome is ' || it.outcome
      when exists (select 1 from public.quotes q where q.id::text = it.quote_id) then 'its quote exists'
      when exists (select 1 from public.transactions t where t.payment_ref = v.k) then 'a sale holds its PaymentIntent' end;
    if v_why is not null then
      insert into _qd_resolution values ('reveal ' || v.k, 'SKIPPED: ' || v_why, null); continue;
    end if;
    update public.accountant_reveal_reconcile_item set resolved_at = coalesce(resolved_at, now()) where key = v.k;
    r := public.fn_it_engineer_finding_close('acct:reveal_reconcile:test_mode_not_demo:' || v.k, c_1558);
    insert into _qd_resolution values ('reveal ' || v.k, 'RESOLVED', jsonb_build_object('amount_fils', it.amount_fils,
      'paid_at', it.paid_at, 'quote_id', it.quote_id, 'finding', r));
  end loop;

  -- 2. the six one-off statement findings
  for v in select * from (values ('books_vs_bank_0930'), ('card:2265'), ('card:2266'), ('october_credit'),
                                 ('uncollected_aug_fee'), ('unreasoned_charges')) t(k) loop
    select * into f from public.it_engineer_finding where issue_key = 'acct:bank_statement_2026_09:' || v.k;
    if f.issue_key is null or f.raised_by is distinct from 'accountant.bank_statement_2026_09' then
      insert into _qd_resolution values ('bank_statement ' || v.k, 'SKIPPED: no such finding from accountant.bank_statement_2026_09', null); continue;
    end if;
    r := public.fn_it_engineer_finding_close(f.issue_key, c_1559);
    insert into _qd_resolution values ('bank_statement ' || v.k, 'CLOSED', r);
  end loop;

  -- 3. the demo CAD jobs
  for v in select * from (values
    ('cad_read_worker:job_failed', 'ad92cb2d-b0f3-42ad-8a0b-93da6814d667'),
    ('sales_engineer:cad_read_held:2026-10-27T07', 'aba1f872-c963-45f9-9f1a-72d83f392395'),
    ('sales_engineer:cad_read_held:2026-10-27T23', 'ef547f9a-c6c6-42d9-8f18-964e13305a3a'),
    ('sales_engineer:cad_read_held:2026-11-01T22', '4aa91363-219f-451d-94c4-d99068b175c2'),
    ('sales_engineer:cad_read_held:2026-11-01T23', '7e968bf9-a819-4c9a-b093-5246be303941'),
    ('sales_engineer:cad_read_held:2026-11-02T08', '3da043fa-84d2-42e4-bb89-5b00a7699a3c'),
    ('sales_engineer:cad_read_held:2026-11-03T08', '904dd897-e59d-4989-ada0-bafd1309af9c'),
    ('sales_engineer:cad_read_held:2026-11-03T11', '5c088fe3-f5d4-4b59-895a-2c9a76aa3427'),
    ('sales_engineer:cad_read_held:2026-11-03T12', 'aa1f664d-c2e2-4a59-be54-d4f20c8c46aa'),
    ('sales_engineer:cad_read_held:2026-11-03T13', '509172bb-54d6-4550-b8fa-73249da7df28'),
    ('sales_engineer:cad_read_held:2026-11-03T15', 'f88d24df-6204-43e7-969b-557bed0803fe')) t(k, job) loop
    select * into f from public.it_engineer_finding where issue_key = v.k;
    if f.issue_key is null or f.evidence->>'job_id' is distinct from v.job then
      insert into _qd_resolution values ('cad ' || v.k, 'SKIPPED: no such finding naming job ' || v.job, null); continue;
    end if;
    select * into j from public.cad_read_jobs where id = v.job::uuid;
    if j.id is not null and not (public.fn_is_demo_email(j.owner_email) or coalesce(public.fn_customer_is_demo(j.customer_id), false)
                                 or j.file_name like 'ZZ DEMO%') then
      insert into _qd_resolution values ('cad ' || v.k, 'SKIPPED: the job looks real, so it is left for the sales_engineer',
        jsonb_build_object('job', j.id, 'file_name', j.file_name, 'status', j.status)); continue;
    end if;
    r := public.fn_it_engineer_finding_close(v.k, c_1561);
    insert into _qd_resolution values ('cad ' || v.k, 'CLOSED', jsonb_build_object('job', v.job,
      'job_row', case when j.id is null then 'gone (teardown or demo purge)' else j.status || ', ' || j.file_name end, 'finding', r));
  end loop;

  -- 4. the unsigned changes: accepted only while every routine is still what was verified today
  for v in select * from (values
    (13968927::bigint, 'Founder ruling 1560 (10 Nov 2026): a Claude session''s SQL through the Supabase management API (mgmt-api as postgres, 30 Sep 00:44Z), not the founder''s and not apply_sql. Verified 10 Nov 2026 against origin/main 17098f34b with the canonical_routine_manifest rule: all 12 routines it touched are identical to their canonical reviewed files - fn_ai_route_review_for = gemini_only_hears_and_every_other_class_runs_luna_pro_and_the_5_6_generation_leaves.sql, fn_mail_sender_known = the_account_holder_of_a_supplier_company_is_a_known_sender.sql, fn_quote_spec_mismatches, fn_routine_judgement_defer/_due/_enqueue/_resolve, fn_routine_quote_spec_supersede, fn_support_wire_email, fn_taxonomy_trades_active, trg_routine_repeat_request_enqueue and trg_routine_trade_words_enqueue = the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql; each live pg_get_functiondef md5 re-checked at apply.'),
    (17314797, 'Founder ruling 1560 (10 Nov 2026): a Claude session''s SQL through the Supabase management API (mgmt-api as postgres, 27 Oct 20:20Z). Verified 10 Nov 2026 against origin/main 17098f34b: fn_support_reply_watch_close_note is identical to support_reply_watch_exempts_machine_senders_and_says_why_it_closed.sql and fn_support_reply_watch_tick to the_reply_watch_and_the_customer_contact_test_share_one_machine_sender_rule.sql; each live md5 re-checked at apply.'),
    (18281068, 'Founder ruling 1560 (10 Nov 2026): a Claude session''s SQL through the Supabase management API (mgmt-api as postgres, 1 Nov 18:38Z). Verified 10 Nov 2026 against origin/main 17098f34b: fn_supplier_invite_nudges_due is identical to a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.sql; its live md5 re-checked at apply.'),
    (18310487, 'Founder ruling 1560 (10 Nov 2026): a Claude session''s SQL through the Supabase management API (mgmt-api as postgres, 1 Nov 20:32Z). Verified 10 Nov 2026 against origin/main 17098f34b: fn_mail_sender_known is identical to the_account_holder_of_a_supplier_company_is_a_known_sender.sql; its live md5 re-checked at apply.'),
    (15743633, 'Founder ruling 1560 (10 Nov 2026): applied 19 Oct 12:47Z by an it_engineer session from local revision 5ec4ba8, which GitHub places on no merged or open pull request. Verified 10 Nov 2026 against origin/main 17098f34b: fn_seat_exam_grade and fn_it_engineer_knowledge_recall_exam are identical to a_seats_own_pack_fills_half_of_every_retrieval.sql, fn_reason_retrieve and fn_reason_retrieve_ml to customers_and_suppliers_are_never_given_internal_knowledge.sql, and the two overloads it dropped are absent; each live md5 re-checked at apply.')
  ) t(txid, why) loop
    v_ok := true; v_why := null;
    for o in select * from (values
      (13968927::bigint, 'public.fn_ai_route_review_for(pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text[])', 'd46ea53fe5310bdd18506401103f86a5'),
      (13968927, 'public.fn_mail_sender_known(pg_catalog.text)', '675e5f607f9ad089e279a00ab952d358'),
      (13968927, 'public.fn_quote_spec_mismatches(pg_catalog.text)', '5aca8fcdd611f809f6c448eadfd19f74'),
      (13968927, 'public.fn_routine_judgement_defer(bigint,pg_catalog.text,boolean)', 'a9c4f0f9319866cfe79bc23341bd6383'),
      (13968927, 'public.fn_routine_judgement_due(integer,bigint[])', 'ed8000cdd06a38e919e54b3350a27d70'),
      (13968927, 'public.fn_routine_judgement_enqueue(pg_catalog.text,pg_catalog.text,pg_catalog.jsonb)', '2f42469120345249aef1f0774eb4f2a1'),
      (13968927, 'public.fn_routine_judgement_resolve(bigint,pg_catalog.jsonb,pg_catalog.text)', '7d1249633fa26c7f5e322c323cdc009d'),
      (13968927, 'public.fn_routine_quote_spec_supersede(pg_catalog.text,pg_catalog.text[])', 'c3f8b31b11bab91e38b45dfa1d92a860'),
      (13968927, 'public.fn_support_wire_email()', 'd97f2f56c9b91e211aa1f406894e45c5'),
      (13968927, 'public.fn_taxonomy_trades_active()', '28a2d9842437cf83b5b51c7067455800'),
      (13968927, 'public.trg_routine_repeat_request_enqueue()', '70a3ba470f79adc1bb490b244f684436'),
      (13968927, 'public.trg_routine_trade_words_enqueue()', '8af0d2b2f8e62f77083a16c724e1a918'),
      (17314797, 'public.fn_support_reply_watch_close_note(pg_catalog.text,pg_catalog.jsonb,numeric)', '8d73d6b22169cf6f642f913a6b37cd5b'),
      (17314797, 'public.fn_support_reply_watch_tick()', 'eda4acb92de34d9eab72ad2737ead34e'),
      (18281068, 'public.fn_supplier_invite_nudges_due(timestamp with time zone,boolean)', '89ab54f8d8d147d24d255f2c8820ab3f'),
      (18310487, 'public.fn_mail_sender_known(pg_catalog.text)', '675e5f607f9ad089e279a00ab952d358'),
      (15743633, 'public.fn_seat_exam_grade(pg_catalog.text)', 'c0b54ea5d4914c623a9d4aefec09878b'),
      (15743633, 'public.fn_it_engineer_knowledge_recall_exam()', 'b470cf9f5d9e47166d0585140196750d'),
      (15743633, 'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)', '76559369723563d94b4bbd947b59faa3'),
      (15743633, 'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)', '3b05d39dace67fbb6df9cbbac1afc589'),
      (15743633, 'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)', null),
      (15743633, 'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)', null)
    ) t(txid, obj, md5) where t.txid = v.txid loop
      if o.md5 is null and to_regprocedure(o.obj) is not null then
        v_ok := false; v_why := coalesce(v_why || '; ', '') || o.obj || ' was dropped and exists again';
      elsif o.md5 is not null and md5(coalesce(pg_get_functiondef(to_regprocedure(o.obj)), '')) is distinct from o.md5 then
        v_ok := false; v_why := coalesce(v_why || '; ', '') || o.obj || ' changed since it was verified on 10 Nov';
      end if;
    end loop;
    -- every routine the transaction logged must be one listed above, so nothing it touched goes unverified
    if exists (select 1 from public.routine_change_log c where c.txid = v.txid
                and c.object_identity not in (select x from unnest(array[
                  'public.fn_ai_route_review_for(pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text[])',
                  'public.fn_mail_sender_known(pg_catalog.text)', 'public.fn_quote_spec_mismatches(pg_catalog.text)',
                  'public.fn_routine_judgement_defer(bigint,pg_catalog.text,boolean)', 'public.fn_routine_judgement_due(integer,bigint[])',
                  'public.fn_routine_judgement_enqueue(pg_catalog.text,pg_catalog.text,pg_catalog.jsonb)',
                  'public.fn_routine_judgement_resolve(bigint,pg_catalog.jsonb,pg_catalog.text)',
                  'public.fn_routine_quote_spec_supersede(pg_catalog.text,pg_catalog.text[])', 'public.fn_support_wire_email()',
                  'public.fn_taxonomy_trades_active()', 'public.trg_routine_repeat_request_enqueue()', 'public.trg_routine_trade_words_enqueue()',
                  'public.fn_support_reply_watch_close_note(pg_catalog.text,pg_catalog.jsonb,numeric)', 'public.fn_support_reply_watch_tick()',
                  'public.fn_supplier_invite_nudges_due(timestamp with time zone,boolean)', 'public.fn_seat_exam_grade(pg_catalog.text)',
                  'public.fn_it_engineer_knowledge_recall_exam()',
                  'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
                  'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
                  'public.fn_reason_retrieve(pg_catalog.text,public.vector,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)',
                  'public.fn_reason_retrieve_ml(pg_catalog.text,public.vector,public.vector,integer,integer,pg_catalog.text,pg_catalog.text,pg_catalog.text)']) x)) then
      v_ok := false; v_why := coalesce(v_why || '; ', '') || 'the transaction logged a routine this file did not verify';
    end if;
    if not exists (select 1 from public.routine_change_log c where c.txid = v.txid) then
      v_ok := false; v_why := coalesce(v_why || '; ', '') || 'routine_change_log no longer holds the transaction';
    end if;
    if not v_ok then
      insert into _qd_resolution values ('tx' || v.txid, 'NOT ACCEPTED: ' || v_why, null); continue;
    end if;
    r := public.fn_it_change_accept(v.txid, 'ceo', v.why);
    insert into _qd_resolution values ('tx' || v.txid, 'ACCEPTED', r);
  end loop;
end
$settle$;

-- ── 5. the 29 loops close through the learning gate's own door ─────────────────────────────────────────────────
do $loops$
declare
  v record; h public.agent_actions; f public.it_engineer_finding; i public.it_incident; r jsonb; n_rep int; v_cause text;
  c_by constant text := 'ceo (the_founders_rulings_of_10_november_settle_four_open_problems.sql, 10 Nov 2026)';
  c_rc constant text := 'scripts/checks/the_founders_rulings_of_10_november_settle_four_open_problems.test.mjs; the verdict row of scripts/sql/the_founders_rulings_of_10_november_settle_four_open_problems.sql';
begin
  for v in select * from (values
    (128464::bigint, 'acct:bank_statement_2026_09:books_vs_bank_0930', 'bank'), (128465, 'acct:bank_statement_2026_09:card:2265', 'bank'),
    (128466, 'acct:bank_statement_2026_09:card:2266', 'bank'), (128467, 'acct:bank_statement_2026_09:october_credit', 'bank'),
    (128468, 'acct:bank_statement_2026_09:uncollected_aug_fee', 'bank'), (128469, 'acct:bank_statement_2026_09:unreasoned_charges', 'bank'),
    (356853, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdk2C45SqX5pVb0pULMNhu', 'reveal'),
    (356854, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdk2C45SqX5pVb1G6cBfjq', 'reveal'),
    (356855, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdr9C45SqX5pVb3dW8oeLF', 'reveal'),
    (356856, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb037Pk7d2', 'reveal'),
    (356857, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb1NN05C7Q', 'reveal'),
    (356858, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb2mhf67d4', 'reveal'),
    (356928, 'acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb2TTxlJtu', 'reveal'),
    (254955, 'cad_read_worker:job_failed', 'cad_failed'),
    (296083, 'sales_engineer:cad_read_held:2026-10-27T07', 'cad'), (314071, 'sales_engineer:cad_read_held:2026-10-27T23', 'cad'),
    (333915, 'sales_engineer:cad_read_held:2026-11-01T22', 'cad'), (334006, 'sales_engineer:cad_read_held:2026-11-01T23', 'cad'),
    (343594, 'sales_engineer:cad_read_held:2026-11-02T08', 'cad'), (348334, 'sales_engineer:cad_read_held:2026-11-03T08', 'cad'),
    (350089, 'sales_engineer:cad_read_held:2026-11-03T11', 'cad'), (350358, 'sales_engineer:cad_read_held:2026-11-03T12', 'cad'),
    (351202, 'sales_engineer:cad_read_held:2026-11-03T13', 'cad'), (353656, 'sales_engineer:cad_read_held:2026-11-03T15', 'cad'),
    (121690, 'duty:unsigned_change:tx13968927', 'unsigned'), (311594, 'duty:unsigned_change:tx17314797', 'unsigned'),
    (329104, 'duty:unsigned_change:tx18281068', 'unsigned'), (330667, 'duty:unsigned_change:tx18310487', 'unsigned'),
    (269841, 'duty:unsigned_revision:rev:5ec4ba8', 'revision')
  ) as t(id, issue_key, kind) loop
    begin
      select * into h from public.agent_actions where id = v.id;
      if h.id is null or h.kind <> 'handoff' or h.detail->>'type' is distinct from 'it.finding' then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: not an it.finding handoff', null); continue;
      end if;
      if h.status = 'done' then
        insert into _qd_resolution values ('handoff ' || v.id, 'ALREADY CLOSED', jsonb_build_object('decided_at', h.decided_at)); continue;
      end if;
      if h.status <> 'pending' or h.detail->>'issue_key' is distinct from v.issue_key then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: status or issue key differs from the list',
          jsonb_build_object('status', h.status, 'issue_key', h.detail->>'issue_key', 'listed', v.issue_key)); continue;
      end if;
      select * into f from public.it_engineer_finding where issue_key = v.issue_key;
      if f.issue_key is not null and f.closed_at is null then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: its finding is still open', jsonb_build_object('issue_key', v.issue_key)); continue;
      end if;
      select * into i from public.it_incident where handoff_id = v.id;
      if i.id is null then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: no incident; fn_it_loop_reverify closes it on its next tick', null); continue;
      end if;
      v_cause := case v.kind
        when 'bank' then 'Not a fault: on 4 Oct 2026 a Claude session read the September Mashreq statement by hand and filed reconciliation findings under a one-off duty name (bank_statement_2026_09) that no routine re-checks. Founder ruling 1559 (10 Nov 2026): no bank statement reconciliation; month-end receipts are checked from his email when he asks.'
        when 'reveal' then 'Not a customer payment: a Claude session''s Stripe TEST-mode checkout of 3 Nov 2026 (founder ruling 1558). A bare test PaymentIntent with no receipt e-mail and no customer, naming a quote its test teardown deleted, so the hourly sweep could not prove it demo and filed test_mode_not_demo. Test mode moves no money; nothing was recorded.'
        when 'cad' then 'Not a customer drawing: a ZZ DEMO CAD upload of the e2e run (scripts/e2e/every_drawing_format_is_read.mjs, ''ZZ DEMO large.dwg'', over the edge ceiling) queued for a reader with no runner since GitHub Actions went off on 26 Oct. Founder ruling 1561 (10 Nov 2026): all CAD/drawing jobs, customers and suppliers so far are demo. The job was removed by its own teardown or the demo purge.'
        when 'cad_failed' then 'Not a customer drawing: job ad92cb2d, ''ZZ DEMO large.dwg'' of a demo address (example.invalid), whose stored file was already gone when the reader fetched it (HTTP 400); fn_cad_read_claim failed it after 3 attempts. Founder ruling 1561 (10 Nov 2026): all CAD/drawing jobs so far are demo.'
        when 'unsigned' then 'A Claude session ran SQL through the Supabase management API (application_name mgmt-api, as postgres) instead of scripts/apply_sql.mjs, so routine_change_log recorded no reviewed revision. The founder neither made nor knew of the change (ruling 1560, 10 Nov 2026).'
        else 'An it_engineer session applied with scripts/apply_sql.mjs from local revision 5ec4ba8 on 19 Oct 2026, a commit GitHub places on no merged or open pull request; two of its six changes were never re-applied from main. Founder ruling 1560 (10 Nov 2026): find who changed them and settle them.' end;
      if coalesce(btrim(i.cause), '') <> '' then v_cause := v_cause || ' Earlier note on this incident: ' || i.cause; end if;
      r := public.fn_it_attach_learning(v.id, v_cause,
        coalesce(nullif(btrim(i.fix), ''), case v.kind
          when 'bank' then 'Closed under ruling 1559. company_policy_decision no_bank_statement_reconciliation is recorded; seat_duty accountant.receipt_bank_match is retired and its pg_cron job unscheduled; fn_accountant_duty_settle holds the bank duty''s asks for a statement (statement:, unreadable:) and every bank_balance item as waiting while the decision stands; fn_accountant_cash_truth_check sends no books-against-statement report.'
          when 'reveal' then 'Resolved as a test payment under ruling 1558 (accountant_reveal_reconcile_item.resolved_at set). fn_accountant_reveal_reconcile_record now keeps a resolved TEST-mode payment resolved when the sweep reads it again, so the finding does not reopen for the 30 days Stripe keeps it in the window.'
          when 'unsigned' then 'Accepted by the ceo with fn_it_change_accept after every routine it touched was verified identical to its canonical reviewed file on origin/main 17098f34b (10 Nov 2026), each live pg_get_functiondef md5 re-checked at apply.'
          when 'revision' then 'Its transaction 15743633 accepted by the ceo with fn_it_change_accept after all four routines it created were verified identical to their canonical reviewed files on origin/main 17098f34b and the two it dropped absent; fn_it_change_watch''s SETTLED rule then stops raising the revision. The verdict stays not_on_main.'
          else 'Closed under ruling 1561. No job row was changed: the job no longer exists, or is finished.' end),
        coalesce(nullif(btrim(i.regression_check), ''), case
          when v.kind in ('unsigned', 'revision') then 'duty it_engineer.unsigned_change (trigger z10 on routine_change_log, fn_it_change_watch); scripts/checks/canonical_routine_manifest.mjs; ' || c_rc
          when v.kind like 'cad%' then 'scripts/checks/a_cad_upload_reaches_the_cad_reader.test.mjs (a new queued job raises its own hourly finding); ' || c_rc
          when v.kind = 'reveal' then 'supabase/functions/_shared/reveal_reconcile.test.ts; the hourly duty accountant.reveal_reconcile; ' || c_rc
          else c_rc end),
        case when v.kind in ('unsigned', 'revision') then 'unsigned_routine_change' end,
        case when v.kind in ('unsigned', 'revision') then null
             when v.kind = 'reveal' then 'A founder''s ruling, not a fault: a test payment on a deleted quote cannot be told from a real quote paid through the test key without the quote, so the classifier still files any new one for the accountant; these seven are settled by ruling 1558.'
             when v.kind = 'bank' then 'Nothing to automate: the founder ruled bank statement reconciliation out (1559).'
             else 'A founder''s ruling, not a fault: demo jobs are demo by ruling 1561, and a real queued drawing must still raise its finding.' end,
        c_by);
      n_rep := 0;
      if coalesce((r->>'closed')::boolean, false) then
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'Closed under the founder''s ruling of 10 Nov 2026: handoff ' || v.id || ' closed with its learning recorded (' || c_by || ').'
         where idempotency_key = 'it_loop:' || v.id and status = 'accepted';
        get diagnostics n_rep = row_count;
      end if;
      insert into _qd_resolution values ('handoff ' || v.id,
        case when coalesce((r->>'closed')::boolean, false) then 'CLOSED' else 'LEARNING RECORDED, NOT CLOSED' end,
        jsonb_build_object('issue_key', v.issue_key, 'incident_id', i.id, 'report_completed', n_rep));
    exception when others then
      insert into _qd_resolution values ('handoff ' || v.id, 'ERROR: ' || left(sqlerrm, 300), null);
    end;
  end loop;
end
$loops$;

-- ── VERDICT (read-only; never raises) ────────────────────────────────────────────────────────────────────────────
with keys(k) as (values
    ('acct:bank_statement_2026_09:books_vs_bank_0930'), ('acct:bank_statement_2026_09:card:2265'), ('acct:bank_statement_2026_09:card:2266'),
    ('acct:bank_statement_2026_09:october_credit'), ('acct:bank_statement_2026_09:uncollected_aug_fee'), ('acct:bank_statement_2026_09:unreasoned_charges'),
    ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdk2C45SqX5pVb0pULMNhu'), ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdk2C45SqX5pVb1G6cBfjq'),
    ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdr9C45SqX5pVb3dW8oeLF'), ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb037Pk7d2'),
    ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb1NN05C7Q'), ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb2mhf67d4'),
    ('acct:reveal_reconcile:test_mode_not_demo:pi_3UXdy2C45SqX5pVb2TTxlJtu'), ('cad_read_worker:job_failed'),
    ('sales_engineer:cad_read_held:2026-10-27T07'), ('sales_engineer:cad_read_held:2026-10-27T23'), ('sales_engineer:cad_read_held:2026-11-01T22'),
    ('sales_engineer:cad_read_held:2026-11-01T23'), ('sales_engineer:cad_read_held:2026-11-02T08'), ('sales_engineer:cad_read_held:2026-11-03T08'),
    ('sales_engineer:cad_read_held:2026-11-03T11'), ('sales_engineer:cad_read_held:2026-11-03T12'), ('sales_engineer:cad_read_held:2026-11-03T13'),
    ('sales_engineer:cad_read_held:2026-11-03T15'), ('duty:unsigned_change:tx13968927'), ('duty:unsigned_change:tx17314797'),
    ('duty:unsigned_change:tx18281068'), ('duty:unsigned_change:tx18310487'), ('duty:unsigned_revision:rev:5ec4ba8')),
fx as (select string_agg(problem, '; ') problems from (
  select 'findings still open: ' || count(*) problem from public.it_engineer_finding f join keys on keys.k = f.issue_key
   where f.closed_at is null having count(*) > 0
  union all select 'handoffs not closed: ' || count(*) from public.agent_actions a
   where a.id in (128464, 128465, 128466, 128467, 128468, 128469, 356853, 356854, 356855, 356856, 356857, 356858, 356928, 254955, 296083,
                  314071, 333915, 334006, 343594, 348334, 350089, 350358, 351202, 353656, 121690, 311594, 329104, 330667, 269841)
     and a.status <> 'done' having count(*) > 0
  union all select 'transactions not accepted: ' || (5 - count(*)) from public.it_change_acceptance
   where txid in (13968927, 17314797, 18281068, 18310487, 15743633) having count(*) <> 5
  union all select 'test payments not resolved: ' || count(*) from public.accountant_reveal_reconcile_item
   where key in ('pi_3UXdk2C45SqX5pVb0pULMNhu', 'pi_3UXdk2C45SqX5pVb1G6cBfjq', 'pi_3UXdr9C45SqX5pVb3dW8oeLF', 'pi_3UXdy2C45SqX5pVb037Pk7d2',
                 'pi_3UXdy2C45SqX5pVb1NN05C7Q', 'pi_3UXdy2C45SqX5pVb2mhf67d4', 'pi_3UXdy2C45SqX5pVb2TTxlJtu') and resolved_at is null having count(*) > 0
  union all select 'another reveal item was resolved by this file: ' || count(*) from public.accountant_reveal_reconcile_item
   where resolved_at = now() and key not in ('pi_3UXdk2C45SqX5pVb0pULMNhu', 'pi_3UXdk2C45SqX5pVb1G6cBfjq', 'pi_3UXdr9C45SqX5pVb3dW8oeLF',
     'pi_3UXdy2C45SqX5pVb037Pk7d2', 'pi_3UXdy2C45SqX5pVb1NN05C7Q', 'pi_3UXdy2C45SqX5pVb2mhf67d4', 'pi_3UXdy2C45SqX5pVb2TTxlJtu') having count(*) > 0
  union all select 'a finding outside the list was closed by this file: ' || string_agg(f.issue_key, ', ') from public.it_engineer_finding f
   where f.closed_at = now() and not exists (select 1 from keys where keys.k = f.issue_key)
     and f.issue_key not like 'duty:unsigned\_%' having count(*) > 0
  union all select 'the decision row is missing' where not exists (select 1 from public.company_policy_decision where decision_key = 'no_bank_statement_reconciliation')
  union all select 'accountant.receipt_bank_match is not retired' where exists (select 1 from public.seat_duty where duty = 'accountant.receipt_bank_match' and enabled)
  union all select 'its pg_cron job is still scheduled' where exists (select 1 from cron.job where jobname = 'seat_duty:accountant.receipt_bank_match')
  union all select 'a routine lost its rule: ' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and (
         (p.proname = 'fn_accountant_duty_settle' and position('no_bank_statement_reconciliation' in p.prosrc) = 0)
      or (p.proname = 'fn_accountant_cash_truth_check' and position('no_bank_statement_reconciliation' in p.prosrc) = 0)
      or (p.proname = 'fn_accountant_reveal_reconcile_record' and position('when excluded.outcome = ''test_mode_not_demo'' and not excluded.livemode then it.resolved_at' in p.prosrc) = 0))
  union all select 'a routine is open or unpinned: ' || p.oid::regprocedure::text from pg_proc p
   where p.oid in ('public.fn_accountant_duty_settle(text,jsonb)'::regprocedure, 'public.fn_accountant_cash_truth_check()'::regprocedure,
                   'public.fn_accountant_reveal_reconcile_record(bigint,jsonb)'::regprocedure)
     and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
          or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  union all select 'the runtime lost its grant on the record routine'
   where not has_function_privilege('service_role', 'public.fn_accountant_reveal_reconcile_record(bigint,jsonb)', 'execute')
  union all select 'a step did not finish: ' || string_agg(subject || ' ' || outcome, '; ') from _qd_resolution
   where outcome like 'SKIPPED%' or outcome like 'NOT ACCEPTED%' or outcome like 'ERROR%' or outcome like 'LEARNING RECORDED, NOT%' having count(*) > 0
) z)
select case when fx.problems is null then 'PROBE OK' else 'PROBE FAILED: ' || fx.problems end as verdict,
       (select jsonb_object_agg(outcome, n) from (select regexp_replace(outcome, ':.*$', '') outcome, count(*) n from _qd_resolution group by 1) s) as steps
  from fx;
