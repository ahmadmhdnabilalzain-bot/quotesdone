-- THE COMPANY RECORDS THE FOUNDER'S DECISIONS OF 6 SEP 2026 (verbatim in substance, never to be asked again).
--
--   "corporate tax is not registered and not needed till we reach the threshold which i will update about
--    it later. could take a year. no auditor name and not needed. meta token is already with you, and the
--    daily budget cap is 30 AED per day. that target you ingested i never actually mentioned it [the AED 150
--    cost-per-lead target]. open router credit will be recharged by me always and i will send the receipts
--    to the same email as always for the records to be always updated. for now open router shouldnt be
--    running since the code is not fixed yet. once everything is fixed i will ask you to activate it. no
--    discounts and no caps for reveals. a category count is open after having 10 verified registered
--    suppliers. finance budget has no limit at the moment as its mainly coming from subscriptions cost at
--    the moment. once we are profitable, a budget should be set ... supplier registration is free for the
--    first 1000 registration. after that its 1000 AED per year. dont use a deadline with dates. these are
--    my decisions so never ask about them again. make sure everything is in sync"
--
-- Applies AFTER scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (it reads the category threshold
-- column that file adds). The refund decisions and the supplier-acquisition decisions are sibling packets;
-- this file does not touch refund mechanics, refund text, public.pages, legal_documents or WhatsApp.
--
-- WHAT WAS MEASURED BEFORE THIS FILE. company_registration.corporate_tax_note said "not yet recorded
-- (finance to record when known)" and had no auditor column; no table held a founder decision as a
-- decision; company_faq rows 50, 91, 95, 159 and 169 and the _global rows "Company primer", "Penalty &
-- collections model" and "canon:money" all stated "free until 31 July 2027 / from 1 August 2027";
-- canon:money said a lower cap / first-reveal-free was "discussed, not live"; fn_company_hard_rules read
-- the charging date and printed it; fn_finance_ai raised a 'budget_overrun' finance alert against
-- budget_vs_actual_summary whenever a line passed 110% (0 budget lines exist, so it was silent by
-- accident, not by policy); qd-company:financials carried no budget policy at all.
--
-- WHAT THIS FILE DOES, BY MECHANISM.
--   * company_registration: corporate_tax_note = the ruling; auditor column added = none / not required.
--   * company_policy_decision: every decision above as a row (decision_key, decided_on, decided_by,
--     decision_text, applies_to, never_ask_again). company_financial_stance: is_profitable=false,
--     budget_mode='unlimited_until_profitable' with the policy text.
--   * fn_company_self_knowledge_sync: registration record carries Corporate Tax and the auditor;
--     commercials carries no-date / no-discount / no-cap / category-open; financials carries the budget
--     stance; a new qd-company:decisions record renders every row of company_policy_decision.
--   * fn_company_hard_rules: rule 1 says no cap, no discount, no promo; supplier pricing 1,000 free then
--     AED 1,000/year with no date; a fifth line carries the category-open threshold. Every agent head
--     (fn_agent_context, both overloads unchanged) therefore opens with them.
--   * fn_finance_ai: the budget_overrun alert and the budget health penalty are inert until
--     company_financial_stance says the company is profitable or budgeted. fn_marketing_ai: its
--     "set a marketing media budget" escalation (a budget ask to the founder) is inert the same way.
--   * The decisions record is rendered LAST (the renderer is code-driven; sibling packets add refunds,
--     brand and messaging records before it). company_faq row 500 and five profession rows (ceo,
--     contract_specialist, financial_analyst, partnerships_mgr, sales_director) lose the date too.
--   * company_faq (6 approved rows) and the three _global canon rows: the date sentence is replaced by the
--     cohort rule; the trigger recompiles the canonical FAQ, and the self-knowledge sync re-renders the
--     qd-company:faq-* records from the same rows.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql --apply --ddl
begin;

-- 1. REGISTRATION: Corporate Tax ruling and the auditor.
alter table public.company_registration add column if not exists auditor text;
update public.company_registration
   set corporate_tax_note = 'Corporate Tax: NOT registered and NOT required until QuotesDone reaches the UAE Corporate Tax registration threshold (founder ruling 6 Sep 2026). The founder will update the company when it applies - possibly a year or more away. Do not ask the founder about Corporate Tax registration, the first tax period or Small Business Relief; when revenue approaches the threshold the CFO opens a registration task.',
       auditor = 'None appointed and none required (founder ruling 6 Sep 2026). There is no external auditor and no auditor name to record; do not ask for one.'
 where license_no = '1633275';

-- 2. THE DECISIONS TABLE.
create table if not exists public.company_policy_decision (
  decision_key     text primary key,
  decided_on       date not null,
  decided_by       text not null default 'founder',
  decision_text    text not null,
  applies_to       text[] not null default '{}',
  never_ask_again  boolean not null default true,
  recorded_at      timestamptz not null default now()
);
alter table public.company_policy_decision enable row level security;
revoke all on public.company_policy_decision from public, anon, authenticated;
comment on table public.company_policy_decision is
  'Founder decisions, verbatim in substance. Rendered as qd-company:decisions by fn_company_self_knowledge_sync; never_ask_again means exactly that.';

insert into public.company_policy_decision (decision_key, decided_on, decided_by, decision_text, applies_to, never_ask_again) values
  ('corporate_tax', date '2026-09-06', 'founder',
   'Corporate Tax is NOT registered and is NOT needed until the company reaches the Corporate Tax threshold. The founder will update the company about it later - it could take a year. No agent asks about it; when revenue approaches the threshold the CFO opens a registration task.',
   array['cfo','bookkeeper','financial_analyst','legal','compliance_mgr'], true),
  ('auditor', date '2026-09-06', 'founder',
   'There is no auditor name and no auditor is needed. No agent records, requests or waits for an auditor.',
   array['cfo','bookkeeper','legal'], true),
  ('meta_token_and_daily_cap', date '2026-09-06', 'founder',
   'The founder states the Meta access token is already with the company. The daily Meta ad budget cap is AED 30 per day (app_secrets.meta_daily_budget_cap_aed and ad_spend_policy.daily_cap_aed). Autospend go-live (meta_autospend_golive) stays false until the founder switches it on. Measured 6 Sep 2026 14:18 UTC: app_secrets holds no meta_access_token row under any key and fn_ads_autospend_state reports token_present=false, so placing the token he holds under app_secrets.meta_access_token is a configuration action for IT operations before go-live - never a question to him.',
   array['marketing','sales_director','marketing_analyst','cfo'], true),
  ('no_founder_cpl_target', date '2026-09-06', 'founder',
   'There is NO founder cost-per-lead target. The AED 150 cost-per-lead figure the system had ingested was never stated by the founder and has been removed (ad_spend_policy.target_cpl_aed is NULL). The target CPL is derived from measured campaign data after go-live: the ad manager judges campaigns against the median measured cost per lead of the active set, and against nothing until leads are measured.',
   array['marketing','sales_director','marketing_analyst','cfo','ceo'], true),
  ('openrouter_credit', date '2026-09-06', 'founder',
   'OpenRouter credit is always recharged by the founder. He sends the receipts to the expenses mailbox (the same address as always), which is the source of truth for expenses, so the books stay current from those receipts. Paid inference (OpenRouter) is HELD: it must not be running until the code is fixed; once everything is fixed the founder will say when to activate it. No agent asks him to recharge, and no agent activates paid inference.',
   array['cfo','bookkeeper','cto','it_operations_engineer','ceo'], true),
  ('reveal_no_discount_no_cap', date '2026-09-06', 'founder',
   'The reveal fee is 3% of the selected quotation value with NO discounts and NO caps: no promotional rate, no coupon, no free reveal, no ceiling on the fee. pricing_config forbids any of them by constraint (pricing_config_no_discount_no_cap_ck) and reveal_fee() computes 3% and nothing else.',
   array['cfo','sales_director','cs_retention','followup','payments_manager','billing_specialist','ceo'], true),
  ('category_open_threshold', date '2026-09-06', 'founder',
   'A category counts as OPEN once it has 10 verified registered suppliers (pricing_config.category_open_min_suppliers; public.v_category_open lists every category with its count). Matching an RFQ to suppliers is a separate rule and still needs at least one confirmed supplier.',
   array['ceo','bd','procurement','supplier_coverage','marketing','sales_director'], true),
  ('finance_budget', date '2026-09-06', 'founder',
   'The finance budget has NO limit at the moment, because costs are mainly subscriptions. Once the company is profitable a budget must be set, and the finance team must set budgets intelligently to maintain profitability out of the income then coming in. Until company_financial_stance.is_profitable is true, budget-variance alerts and budget-limit checks are inert.',
   array['cfo','bookkeeper','financial_analyst','ceo'], true),
  ('supplier_pricing', date '2026-09-06', 'founder',
   'Supplier registration is free for the first 1,000 registrations. After that it is AED 1,000 per year. There is NO deadline and NO calendar date: charging begins with registration number 1,001, whenever that happens (pricing_config.supplier_charging_starts is NULL and stays NULL).',
   array['bd','billing_specialist','payments_manager','partnerships_mgr','cfo','onboarding'], true),
  ('never_ask_again', date '2026-09-06', 'founder',
   'These are the founder''s decisions. Never ask about them again. Keep every table, document, knowledge record and agent head in sync with them.',
   array['*'], true)
on conflict (decision_key) do update set
  decided_on = excluded.decided_on, decided_by = excluded.decided_by, decision_text = excluded.decision_text,
  applies_to = excluded.applies_to, never_ask_again = excluded.never_ask_again, recorded_at = now();

-- 3. THE FINANCIAL STANCE the budget machinery reads.
create table if not exists public.company_financial_stance (
  id            integer primary key default 1 check (id = 1),
  is_profitable boolean not null default false,
  budget_mode   text not null default 'unlimited_until_profitable'
                check (budget_mode in ('unlimited_until_profitable','budgeted')),
  policy_text   text not null,
  decided_on    date not null,
  updated_at    timestamptz not null default now()
);
alter table public.company_financial_stance enable row level security;
revoke all on public.company_financial_stance from public, anon, authenticated;
insert into public.company_financial_stance (id, is_profitable, budget_mode, policy_text, decided_on) values
  (1, false, 'unlimited_until_profitable',
   'No budget limit while the company''s costs are mainly subscriptions (founder, 6 Sep 2026). Once profitable, finance sets budgets - intelligently, to maintain profitability out of the income coming in. Budget-variance alerts and budget-limit checks are inert until is_profitable is true.',
   date '2026-09-06')
on conflict (id) do update set is_profitable = excluded.is_profitable, budget_mode = excluded.budget_mode,
  policy_text = excluded.policy_text, decided_on = excluded.decided_on, updated_at = now();

-- 4. THE HARD RULES every head opens with (fn_agent_context, both overloads, read this unchanged).
--    MERGED 6 Sep 2026 (14:20 and 14:23 UTC): the refund-ladder packet (every_employee_knows_the_refund_ladder.sql)
--    and then the brand packet (the_company_knows_its_own_brand.sql) restated the renderer below (and the
--    first also this routine) from the cf34c63 baseline while this packet was being applied, which dropped
--    these lines from production each time. Both definitions here are the LIVE text of those packets with
--    this packet's lines re-applied on top; rule 3 (the ladder), the refunds record and the brand record are
--    the siblings', untouched.
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
    ||'THE LADDER (founder ruling 6 Sep 2026, final; pricing_config): the supplier has '||v_win||' working days from payment. No response by working day '||v_chase||' - the Customer Success Director chases the supplier, customer copied; still silent on working day '||v_win||' - the founder is notified for his final call; no response to that - the refund is issued. '
    ||'Every refund of any amount is the founder''s decision, never automatic. The customer gets the FULL reveal fee back (the '||v_pct||'% paid, nothing deducted) and is told banks take '||coalesce(v_bmin,7)||'-'||coalesce(v_bmax,14)||' working days. '
    ||'The supplier then owes that reveal fee ('||v_pct||'%) + AED '||v_admin||' administrative fee + '||v_int||'% per annum simple interest (UAE statutory maximum), and is blocked from matching until it is paid. Never ask the founder about any of this again.'||E'\n'
    ||'4. ANTI-CIRCUMVENTION: identities stay anonymous until the reveal and there is no off-platform contact before it. A supplier that takes an introduced customer off-platform within 24 months owes AED '||coalesce(v_aed, '15,000')||' per incident OR '||coalesce(v_mult, 'three (3)')||' times the fee, whichever is higher, plus the unpaid fee.'||E'\n'
    ||'5. CATEGORY OPENING (founder''s standing decision, 6 Sep 2026): a category is OPEN once it has '||v_cat_min||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. Never ask the founder about any figure in these five lines.'||E'\n';
end $function$;

-- 5. THE FINANCE AGENT: budget alerts are inert until the company is profitable or budgeted.
-- ROUTINE REMOVED 7 September 2026. public.fn_finance_ai was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 5b. THE MARKETING AGENT: its "set a marketing media budget" escalation asks the founder for a figure he has
--     decided (AED 30/day) - inert until company_financial_stance says budgeted. Every other line unchanged.
-- ROUTINE REMOVED 7 September 2026. public.fn_marketing_ai was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 5c. THE OWNERSHIP LEDGER follows the manifest for the two agent routines this file defines.
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public', 'fn_finance_ai', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql (6 Sep 2026): budget alerts inert until company_financial_stance says budgeted.', 'MANIFEST', 'scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql'),
  ('public', 'fn_marketing_ai', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql (6 Sep 2026): the media-budget ask is inert until company_financial_stance says budgeted.', 'MANIFEST', 'scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql')
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule, evidence = excluded.evidence,
  source_kind = excluded.source_kind, source_file = excluded.source_file, justification = null, recorded_at = now();

-- 6. THE SELF-KNOWLEDGE RENDERER (full definition; every other line unchanged from the live routine).
CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_funnel text;
  v_founder text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
begin
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company)
  select string_agg(identity, ' / ' order by identity) into v_founder
    from public.phase_c_founder_identity where active and kind = 'email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  select string_agg('  ' || workflow_id || ' — ' || workflow_name, E'\n' order by workflow_id)
    into v_funnel from public.phase_b_workflow
   where workflow_id in ('W04','W05','W06','W07','W08','W09','W10','W12','W13','W14','W15','W16','W17','W18');

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then. The 30 workflows that run this: ' || coalesce(v_funnel,'(registry)') ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'CATEGORY OPENING: a category is OPEN once it has ' || v_cat_min || ' verified registered suppliers (public.v_category_open); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes that fee + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (fn_refund_amount_aed). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: 9% per annum (UAE Federal Decree-Law 50/2022).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the refunded fee (the 3%) + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the UAE statutory maximum), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;

-- 7. THE CANONICAL FAQ (founder-approved answers) and the three _global canon rows: the date sentence
--    becomes the cohort rule. The company_faq trigger recompiles the canonical FAQ row on each update.
update public.company_faq set updated_at = now(), answer =
  'You pay nothing to quote and nothing when you win — there is no commission. Registration is free for the first 1,000 suppliers who register, and those suppliers stay free permanently. Every supplier who registers after them pays an annual subscription of AED 1,000; there is no fixed start date — it simply applies from the 1,001st registration onward. The subscription is paid on the supplier portal via secure Stripe checkout. The only other possible charge is a non-response fee if you ignore a customer who has already paid to reveal your details.'
 where id = 50;
update public.company_faq set updated_at = now(), answer =
  'When a customer pays a reveal fee, an invoice for that fee is generated automatically and available in the app. Suppliers who are liable for the annual subscription (that is, those outside the first 1,000 registered) receive an invoice for it when it falls due. All invoices are issued by QuotesDone Technologies (see the VAT note below on current tax treatment).'
 where id = 91;
update public.company_faq set updated_at = now(), answer =
  'There are no commissions — suppliers keep 100% of their won jobs. The only amounts ever collected from suppliers are the annual subscription (AED 1,000/year, which never applies to the first 1,000 suppliers who registered and has no fixed start date — it applies from the 1,001st registration onward) and any non-response fee. Both are paid on the supplier portal via Stripe. Unpaid amounts are followed up and the account is paused from new matches until they are settled.'
 where id = 95;
update public.company_faq set updated_at = now(), answer =
  'Suppliers self-register or claim an existing listing, submit their trade licence and KYC documents, and are verified before going live (verification within a maximum of 3 working days; suppliers are not auto-approved). Approval is merit-based — there is no paid ranking or advertising. Registration is free for the first 1,000 registered suppliers, who remain free permanently; every supplier after them pays an annual subscription of AED 1,000, with no fixed start date.'
 where id = 159;
update public.company_faq set updated_at = now(), answer =
  'QuotesDone charges suppliers no commission on won jobs — suppliers keep 100% of the job value. The only amounts collected from suppliers are the annual subscription (AED 1,000/year, never applicable to the first 1,000 suppliers who registered, applying from the 1,001st registration onward with no fixed start date) and a non-response fine (equal to the customer''s reveal fee) if a supplier ignores a customer who paid to reveal them, applied except where not permitted under UAE law. The customer separately pays a 3% facilitation fee only when they choose to reveal a supplier''s contact details.'
 where id = 169;
update public.company_faq set updated_at = now(), answer =
  'Not for the first 1,000 suppliers who register — and never for them. Registration is free for the first 1,000 registered suppliers, who are exempt permanently. Every supplier who registers after them pays an annual subscription of AED 1,000 per year; there is no fixed start date — it applies from the 1,001st registration onward. There is never any commission on the jobs you win.'
 where id = 500;

-- The five profession rows that stated the date (measured: ceo, contract_specialist, financial_analyst,
-- partnerships_mgr, sales_director). Each sentence is replaced with the cohort rule.
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'suppliers pay nothing until 31 Jul 2027 (the first 1,000 registrants never pay)',
  'suppliers pay nothing while registrations are inside the first 1,000 (those registrants never pay; AED 1,000/year applies from registration 1,001, on no calendar date - founder, 6 Sep 2026)')
 where agent_key = 'ceo' and topic = 'Running a marketplace that has not launched';
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'no registration fee until 31 Jul 2027 (first 1,000 registrants permanently exempt)',
  'no registration fee for the first 1,000 registrants (permanently exempt); AED 1,000/year from registration 1,001, on no calendar date (founder, 6 Sep 2026)')
 where agent_key = 'contract_specialist' and topic = 'Contract review for the supplier and customer agreements';
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'Suppliers contribute nothing until 1 Aug 2027, and the first 1,000 registrants never contribute, so do not model supplier subscription in year one.',
  'Suppliers contribute nothing while registrations are inside the first 1,000 (those registrants never contribute); AED 1,000/year starts with registration 1,001 on no calendar date (founder, 6 Sep 2026), so model supplier subscription from the registration count, never from a date.')
 where agent_key = 'financial_analyst' and topic = 'Financial analysis of a pre-revenue marketplace';
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'free supplier registration until 31 Jul 2027, and the permanent exemption for the first 1,000 registrants',
  'free supplier registration for the first 1,000 registrants (a permanent exemption; AED 1,000/year applies from registration 1,001, on no calendar date - founder, 6 Sep 2026)')
 where agent_key = 'partnerships_mgr' and topic = 'Partnerships that add supply, not logos';
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'nothing to pay until 31 Jul 2027 and never for the first 1,000',
  'nothing to pay, ever, for the first 1,000 registrants (AED 1,000/year applies from registration 1,001, on no calendar date - founder, 6 Sep 2026)')
 where agent_key = 'sales_director' and topic = 'Selling a marketplace that has not launched';

update public.agent_knowledge set updated_at = now(), content = replace(content,
  'no registration fee until 31 July 2027 (AED 1,000/year begins 1 August 2027; the first 1,000 registered suppliers are exempt permanently and never pay it)',
  'no registration fee for the first 1,000 registered suppliers, who are exempt permanently; every supplier after them pays AED 1,000/year, with NO calendar start date (founder, 6 Sep 2026)')
 where agent_key = '_global' and topic = 'Company primer';
update public.agent_knowledge set updated_at = now(), content = replace(content,
  'no registration fee today: registration is free until 31 July 2027, the first 1,000 registrants are permanently exempt, and AED 1,000/year applies from 1 August 2027 for everyone else.',
  'no registration fee for the first 1,000 registrants, who are permanently exempt; AED 1,000/year applies to everyone after them, with NO calendar start date (founder, 6 Sep 2026).')
 where agent_key = '_global' and topic = 'Penalty & collections model';
update public.agent_knowledge set updated_at = now(), content = replace(replace(content,
  'buyer REVEAL FEE = 3% of quote value, currently effectively UNCAPPED (lower cap / first-reveal-free discussed, not live).',
  'buyer REVEAL FEE = 3% of quote value with NO cap, NO discount, NO promotional rate and NO free reveal (founder, 6 Sep 2026; pricing_config forbids them by constraint).'),
  'Supplier registration FREE for EVERY supplier until 31 July 2027; AED 1,000/year begins 1 August 2027; the first 1,000 registered suppliers are exempt PERMANENTLY.',
  'Supplier registration FREE for the first 1,000 registered suppliers, who are exempt PERMANENTLY; AED 1,000/year for every supplier after them, with NO calendar start date (founder, 6 Sep 2026).')
 where agent_key = '_global' and topic = 'canon:money';

-- 8. RENDER, then PROVE.
select public.fn_company_self_knowledge_sync();

do $proof$
declare v text; v_n int; v_head text; k text; v_dec text;
begin
  select content into v from public.ops_knowledge where record_id = 'qd-company:registration';
  if v is null then raise exception 'qd-company:registration was not written'; end if;
  if position('CORPORATE TAX: Corporate Tax: NOT registered and NOT required' in v) = 0 then raise exception 'registration record lacks the Corporate Tax ruling'; end if;
  if position('AUDITOR: None appointed and none required' in v) = 0 then raise exception 'registration record lacks the auditor ruling'; end if;

  select content into v_dec from public.ops_knowledge where record_id = 'qd-company:decisions';
  if v_dec is null then raise exception 'qd-company:decisions was not written'; end if;
  foreach k in array array['CORPORATE_TAX','AUDITOR','META_TOKEN_AND_DAILY_CAP','AED 30 per day','NO_FOUNDER_CPL_TARGET','AED 150','OPENROUTER_CREDIT','REVEAL_NO_DISCOUNT_NO_CAP','CATEGORY_OPEN_THRESHOLD','10 verified registered suppliers','FINANCE_BUDGET','SUPPLIER_PRICING','first 1,000 registrations','NEVER_ASK_AGAIN'] loop
    if position(k in v_dec) = 0 then raise exception 'qd-company:decisions lacks "%"', k; end if;
  end loop;

  select content into v from public.ops_knowledge where record_id = 'qd-company:commercials';
  if v ~ '2027' or position('NO calendar start date' in v) = 0 or position('NO cap, NO discount' in v) = 0 or position('CATEGORY OPENING' in v) = 0 then
    raise exception 'qd-company:commercials still names a date, or lacks the no-discount / category-open rules';
  end if;
  select content into v from public.ops_knowledge where record_id = 'qd-company:financials';
  if position('BUDGET POLICY' in v) = 0 or position('unlimited_until_profitable' in v) = 0 then raise exception 'qd-company:financials lacks the budget policy'; end if;

  -- no company record and no canonical row still states the retired date or the retired target
  select count(*) into v_n from public.ops_knowledge
   where record_id like 'qd-company:%' and content ~* '31 Jul(y)? 2027|(^|[^0-9])1 Aug(ust)? 2027|150 AED target|AED 150 target';
  if v_n <> 0 then raise exception '% qd-company record(s) still state the retired date or CPL target', v_n; end if;
  select count(*) into v_n from public.agent_knowledge
   where content ~* '31 Jul(y)? 2027|(^|[^0-9])1 Aug(ust)? 2027';
  if v_n <> 0 then raise exception '% agent_knowledge row(s) still state the retired date', v_n; end if;
  select count(*) into v_n from public.company_faq where (question || ' ' || answer) ~* '31 Jul(y)? 2027|(^|[^0-9])1 Aug(ust)? 2027';
  if v_n <> 0 then raise exception '% FAQ row(s) still state the retired date', v_n; end if;
  -- the decisions record is the LAST qd-company record the renderer writes (siblings add theirs before it)
  select count(*) into v_n from public.company_economics where id = 2 and formula ~* 'capped at';
  if v_n <> 0 then raise exception 'company_economics row 2 still says the reveal fee is capped'; end if;
  select count(*) into v_n from public.kernel_routine_ownership
   where routine_name in ('fn_finance_ai','fn_marketing_ai') and ownership_class = 'QUOTESDONE_APPLICATION'
     and source_file = 'scripts/sql/the_company_records_the_founders_decisions_of_6_sep_2026.sql';
  if v_n <> 2 then raise exception 'expected 2 ledger rows to follow this file, got %', v_n; end if;

  -- every head carries the hard ones: the CFO, business development (resolves to bd) and marketing
  foreach k in array array['cfo','business_development','marketing'] loop
    v_head := public.fn_agent_context(k, 6000);
    if position('NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal' in v_head) = 0 then raise exception 'head of % lacks the no-discount / no-cap rule', k; end if;
    if position('NO calendar start date' in v_head) = 0 then raise exception 'head of % lacks the no-date supplier pricing rule', k; end if;
    if position('CATEGORY OPENING' in v_head) = 0 or position('10 verified registered suppliers' in v_head) = 0 then raise exception 'head of % lacks the category-open rule', k; end if;
  end loop;

  select count(*) into v_n from public.company_policy_decision where never_ask_again;
  raise notice 'proof: registration carries Corporate Tax + auditor; qd-company:decisions carries % never-ask-again decisions; commercials/financials carry no date, no discount, category-open and the budget policy; heads of cfo, business_development and marketing carry the hard ones (cfo head % chars)', v_n, length(public.fn_agent_context('cfo', 6000));
end $proof$;

commit;
