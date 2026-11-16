-- EVERY SEAT STATES THE SUPPLIER AGREEMENT'S OWN CIRCUMVENTION FIGURES (16 Nov 2026, ceo; simplification wave B, SITE-01).
--
-- MEASURED (SELECT, production, 16 Nov 2026): fn_company_context(8000,'public') - the company block every seat carries -
-- said "owes AED 15,000 per incident OR five (5) times the fee" under the header "the Supplier Agreement text did not
-- match the expected clause wording, so the last published figures are stated". The published Supplier Agreement v18
-- (pages.legal_supplier_body, md5 831fadd60169fd9fc3c5a47f6e198267, byte-equal to signedBody(legal.json, '18')) says
-- "agreed compensation of AED 20,000 per incident, or five (5) times the fee", as do src/content/company_facts.json
-- (circumvention_min_aed 20000, was 15000), the accountant card and the certificate. Cause: fn_company_hard_rules read
-- the sum with the v13 word 'liquidated' and fell back to a hard-coded '15,000'.
--
-- WHAT THIS CHANGES: fn_company_hard_rules only, rebuilt from PRODUCTION's body (pg_get_functiondef md5
-- 794c31783611a8a151ac2ea07a8efa12, read 16 Nov 2026), not from the 12 Nov mirror. Three edits, nothing else:
--   1. the sum and the multiple are read together from the one clause-24 sentence that carries both;
--   2. the 24-month window is read from the text too ("For 24 months from such introduction");
--   3. no fallback figure: a clause that cannot be read is stated as unreadable, and the header says so.
-- CREATE OR REPLACE of an existing routine: its ACL (postgres, service_role only) and pinned search_path are kept.
-- Probe: every_seat_states_the_supplier_agreements_own_circumvention_figures_probe.sql (local database only).
-- Prevented by: scripts/checks/the_hard_rules_read_the_circumvention_clause_the_agreement_prints.test.mjs.

CREATE OR REPLACE FUNCTION public.fn_company_hard_rules()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pct numeric; v_free date; v_fee numeric; v_win int; v_chase int; v_bmin int; v_bmax int; v_admin numeric; v_int numeric;
  v_free_n int; v_cat_min int;
  v_txt text; v_days text; v_aed text; v_mult text; v_tail text; v_clause text[]; v_src text;
begin
  select round(coalesce(standard_reveal_rate, 0.03) * 100, 2), supplier_charging_starts, supplier_reg_fee,
         refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count, 1000), coalesce(category_open_min_suppliers, 10)
    into v_pct, v_free, v_fee, v_win, v_chase, v_bmin, v_bmax, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  v_pct := coalesce(v_pct, 3); v_win := coalesce(v_win, 5); v_chase := coalesce(v_chase, 3);
  v_free_n := coalesce(v_free_n, 1000); v_cat_min := coalesce(v_cat_min, 10);
  -- 6 Sep 2026: the money side of the ladder, from decision_policy (founder ruling, verbatim there)
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_int   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);

  v_txt := regexp_replace(coalesce((select p.html from public.pages p where p.slug = 'legal_supplier_body'), ''),
                          '<[^>]+>', ' ', 'g');
  v_days := substring(v_txt from 'begin responding to the Customer within\s+([0-9]+)\s+working days');
  -- 16 Nov 2026 (ceo): the circumvention sum and its multiple are read TOGETHER, from the one sentence that carries
  -- both (clause 24: "agreed compensation of AED 20,000 per incident, or five (5) times the fee"). Until today the sum
  -- was read with the v13 word 'liquidated'; v18 says 'agreed', so it never matched and a hard-coded AED 15,000 (the
  -- v12 figure) went to every seat beside the live five (5). Anchoring on the multiple also keeps the three other
  -- 'agreed compensation of AED ... per incident' clauses of v18 (anonymity 10,000, data 25,000, fake accounts 20,000)
  -- from being read as this one. A figure that cannot be read is NEVER replaced by a remembered one.
  v_clause := regexp_match(v_txt, 'compensation of AED\s+([0-9,]+)\s+per incident, or\s+([a-z]+ \([0-9]+\)|[0-9]+)\s+times the fee');
  v_aed  := v_clause[1];
  v_mult := v_clause[2];
  v_tail := substring(v_txt from 'For\s+([0-9]+)\s+months from such introduction');
  v_src  := case when v_days is not null and v_aed is not null and v_mult is not null and v_tail is not null
                 then 'read from the published Supplier Agreement and pricing_config just now'
                 else 'pricing_config live; the Supplier Agreement text could NOT be read for every clause, and a clause that could not be read states no figure: answer from the published Supplier Agreement, never from memory' end;

  return '# THE FOUR HARD RULES - the published Terms and Supplier Agreement; the founder''s ONLY rules ('||v_src||'). No employee may relax them.'||E'\n'
    ||'1. REVEAL FEE: the CUSTOMER pays '||v_pct||'% of the selected quotation value - NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal (founder, 6 Sep 2026; pricing_config forbids them by constraint) - ex-VAT, once per reveal, to reveal a supplier. Comparing quotes is FREE. Suppliers pay NO commission, ever'
    ||case when v_free is not null
           then '; supplier registration is free until '||to_char(v_free - 1, 'DD Mon YYYY')||', then AED '||coalesce(v_fee::text,'1000')||'/year (first '||v_free_n||' registrants permanently exempt)'
           else '; supplier registration is FREE for the first '||v_free_n||' registrations (permanently exempt), then AED '||coalesce(v_fee::text,'1000')||'/year - there is NO calendar start date: charging begins with registration '||(v_free_n + 1)||', whenever that happens (founder, 6 Sep 2026)' end||'.'||E'\n'
    ||'2. TOP-3 COMPARISON REPORT: however many quotations arrive (3 or 100+), the report ranks them ALL and shows the best THREE on technical AND commercial merit - never cheapest-wins.'||E'\n'
    ||'3. SUPPLIER NON-RESPONSE: a revealed supplier must begin responding within '||coalesce(v_days, v_win::text)||' working days of the customer''s PAYMENT (UAE week: Mon-Fri, Sat+Sun off, public holidays excluded). '
    ||'THE LADDER (founder ruling 6 Sep 2026, final; pricing_config): the supplier has '||v_win||' working days from payment. No response by working day '||v_chase||' - the Customer Success Director chases the supplier, customer copied; still silent on working day '||v_win||' - the CEO is notified for the final call; no response to that - the refund is issued. '
    ||'Every refund of any amount is the CEO''s decision and never automatic (founder, 8 Sep 2026: "refunds belong to the CEO from now on" and "all approvals are from CEO. nothing goes to me" - this SUPERSEDES the 6 Sep ruling; public.refunds enforces it with triggers z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval, which refuse a refund with no matching ceo_approval row). The customer gets the FULL reveal fee back (the '||v_pct||'% paid, nothing deducted) and is told banks take '||coalesce(v_bmin,7)||'-'||coalesce(v_bmax,14)||' working days. '
    ||'The supplier then owes the exact amount refunded (the '||v_pct||'%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED '||v_admin||' administrative fee + '||v_int||'% per annum simple interest (the rate AGREED in v14 clauses 31 and 33, Commercial Transactions Law 50/2022 Arts. 73 and 84; a supplier charged under v13 or earlier pays 9%, under v12 or earlier AED 250) + if unpaid the official recovery fees, and is blocked from matching until it is paid. Never ask the founder about any of this again.'||E'\n'
    ||'4. ANTI-CIRCUMVENTION: identities stay anonymous until the reveal and there is no off-platform contact before it. A supplier that takes an introduced customer off-platform within '||coalesce(v_tail||' months', 'the protected period of clause 24 (its length could not be read just now)')||' owes '
    ||case when v_aed is not null and v_mult is not null
           then 'AED '||v_aed||' per incident OR '||v_mult||' times the fee, whichever is higher'
           else 'the agreed compensation of clause 24 of the published Supplier Agreement (the figures could not be read from its text just now; state none until they are)' end
    ||', plus the unpaid fee.'||E'\n'
    ||'5. CATEGORY OPENING (founder''s standing decision, 6 Sep 2026): a category is OPEN once it has '||v_cat_min||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. Never ask the founder about any figure in these five lines.'||E'\n';
end $function$
;
