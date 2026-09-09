-- THE HARD RULES STOP TELLING FIVE SEATS THAT THE FOUNDER DECIDES REFUNDS.
--
-- Founder, 8 September 2026: "refunds belong to the CEO from now on" and "all approvals are from
-- CEO. nothing goes to me." The DATABASE changed the same hour -- public.refunds carries
-- z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval, and neither will let
-- a refund exist or execute without a ceo_approval row. The PUBLIC wording was corrected the next
-- day in scripts/sql/the_knowledge_stops_saying_the_founder_decides.sql.
--
-- Two INTERNAL statements were missed, and today they stopped being harmless. fn_company_context()
-- now pins fn_company_hard_rules() into every one of the five seats on every answer, so rule 3's
-- "the founder is notified for his final call ... Every refund of any amount is the founder's
-- decision" would be read by the accountant, the sales engineer, the CEO, support and the IT
-- engineer as current policy -- a superseded ruling, broadcast wider than it ever was before.
--
-- ONLY THE DECIDER CHANGES. The five working days, the chase on day three with the customer copied,
-- the full un-deducted refund of the reveal fee, 7-14 working days for the bank, and the supplier's
-- debt afterwards are untouched and still true. The escalation on day five now names the CEO,
-- which is what the triggers already enforce.
--
--   node scripts/apply_sql.mjs scripts/sql/the_hard_rules_stop_saying_the_founder_decides_refunds.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_company_hard_rules()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pct numeric; v_free date; v_fee numeric; v_win int; v_chase int; v_bmin int; v_bmax int; v_admin numeric; v_int numeric;
  v_free_n int; v_cat_min int;
  v_txt text; v_days text; v_aed text; v_mult text; v_src text;
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
  v_aed  := substring(v_txt from 'liquidated compensation of AED\s+([0-9,]+)\s+per incident');
  v_mult := substring(v_txt from 'per incident, or\s+([a-z]+ \([0-9]+\)|[0-9]+)\s+times the fee');
  v_src  := case when v_days is not null and v_aed is not null and v_mult is not null
                 then 'read from the published Supplier Agreement and pricing_config just now'
                 else 'pricing_config live; the Supplier Agreement text did not match the expected clause wording, so the last published figures are stated' end;

  return '# THE FOUR HARD RULES - the published Terms and Supplier Agreement; the founder''s ONLY rules ('||v_src||'). No employee may relax them.'||E'\n'
    ||'1. REVEAL FEE: the CUSTOMER pays '||v_pct||'% of the selected quotation value - NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal (founder, 6 Sep 2026; pricing_config forbids them by constraint) - ex-VAT, once per reveal, to reveal a supplier. Comparing quotes is FREE. Suppliers pay NO commission, ever'
    ||case when v_free is not null
           then '; supplier registration is free until '||to_char(v_free - 1, 'DD Mon YYYY')||', then AED '||coalesce(v_fee::text,'1000')||'/year (first '||v_free_n||' registrants permanently exempt)'
           else '; supplier registration is FREE for the first '||v_free_n||' registrations (permanently exempt), then AED '||coalesce(v_fee::text,'1000')||'/year - there is NO calendar start date: charging begins with registration '||(v_free_n + 1)||', whenever that happens (founder, 6 Sep 2026)' end||'.'||E'\n'
    ||'2. TOP-3 COMPARISON REPORT: however many quotations arrive (3 or 100+), the report ranks them ALL and shows the best THREE on technical AND commercial merit - never cheapest-wins.'||E'\n'
    ||'3. SUPPLIER NON-RESPONSE: a revealed supplier must begin responding within '||coalesce(v_days, v_win::text)||' working days of the customer''s PAYMENT (UAE week: Mon-Fri, Sat+Sun off, public holidays excluded). '
    ||'THE LADDER (founder ruling 6 Sep 2026, final; pricing_config): the supplier has '||v_win||' working days from payment. No response by working day '||v_chase||' - the Customer Success Director chases the supplier, customer copied; still silent on working day '||v_win||' - the CEO is notified for the final call; no response to that - the refund is issued. '
    ||'Every refund of any amount is the CEO''s decision and never automatic (founder, 8 Sep 2026: "refunds belong to the CEO from now on" and "all approvals are from CEO. nothing goes to me" - this SUPERSEDES the 6 Sep ruling; public.refunds enforces it with triggers z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval, which refuse a refund with no matching ceo_approval row). The customer gets the FULL reveal fee back (the '||v_pct||'% paid, nothing deducted) and is told banks take '||coalesce(v_bmin,7)||'-'||coalesce(v_bmax,14)||' working days. '
    ||'The supplier then owes that reveal fee ('||v_pct||'%) + AED '||v_admin||' administrative fee + '||v_int||'% per annum simple interest (UAE statutory maximum), and is blocked from matching until it is paid. Never ask the founder about any of this again.'||E'\n'
    ||'4. ANTI-CIRCUMVENTION: identities stay anonymous until the reveal and there is no off-platform contact before it. A supplier that takes an introduced customer off-platform within 24 months owes AED '||coalesce(v_aed, '15,000')||' per incident OR '||coalesce(v_mult, 'three (3)')||' times the fee, whichever is higher, plus the unpaid fee.'||E'\n'
    ||'5. CATEGORY OPENING (founder''s standing decision, 6 Sep 2026): a category is OPEN once it has '||v_cat_min||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. Never ask the founder about any figure in these five lines.'||E'\n';
end $function$;


-- THE STANDING-DECISION ROW SAID IT TOO, AND ITS KEY SAID IT LOUDEST. Nothing in the repository or
-- the database reads 'every_refund_is_the_founders' as a lookup key -- only the file that inserted
-- it -- so the row is replaced rather than patched: a key that asserts the opposite of its own
-- corrected text is worse than either, and this row is printed verbatim into section 6 of the block
-- every seat now carries.
begin;
delete from public.company_policy_decision where decision_key = 'every_refund_is_the_founders';
insert into public.company_policy_decision
  (decision_key, decision_text, decided_by, decided_on, applies_to, never_ask_again)
values (
  'every_refund_is_the_ceos',
  'Every refund, of any amount, is the CEO seat''s decision. Founder, 8 September 2026: "refunds '
  || 'belong to the CEO from now on" and "all approvals are from CEO. nothing goes to me." This '
  || 'SUPERSEDES the 6 September ruling that every refund was the founder''s. No employee issues a '
  || 'refund autonomously and nothing routes to the founder for it: employees prepare the case, '
  || 'chase the supplier, and put the final call to the CEO on day five of the ladder. '
  || 'public.refunds enforces this -- triggers z00_refund_ceo_approval_only and '
  || 'z05_refund_execution_requires_ceo_approval refuse a refund without a matching ceo_approval row.',
  'founder', date '2026-09-08', array['ceo','accountant','customer_support','sales_engineer','it_engineer'], true)
on conflict (decision_key) do update
  set decision_text = excluded.decision_text,
      decided_by = excluded.decided_by,
      decided_on = excluded.decided_on,
      applies_to = excluded.applies_to,
      never_ask_again = excluded.never_ask_again;
commit;
