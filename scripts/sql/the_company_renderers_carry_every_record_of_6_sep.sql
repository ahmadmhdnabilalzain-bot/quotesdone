-- THE COMPANY RENDERERS CARRY EVERY RECORD OF 6 SEP (6 Sep 2026).
--
-- Seven branches restated fn_company_self_knowledge_sync, fn_company_hard_rules and fn_agent_context on
-- the same afternoon (registration, decisions, refunds, brand, messaging templates, supplier loops) and
-- each apply dropped the others' records from production for a while. At 15:10Z the last restatement
-- carried the union and production has held it since: the self-knowledge array renders registration,
-- identity, financials, operating-model, commercials, comparison-report, quotation-format, terms,
-- governance, organization, live-state, stage, refunds, brand, decisions, supplier-loops and
-- messaging-templates; the hard rules carry the reveal fee with no cap/discount, the five-working-day
-- ladder with the chase at three and the founder's call at five, and category opening at ten; the
-- 2-argument context opens with the hard rules, the LICENCE & TAX line and the BRAND line, and the
-- 3-argument overload delegates.
--
-- This file is that union, read from production, so the repository records what the company runs and
-- the manifest engine has ONE canonical file for all four definitions. It must stay the LAST manifest
-- file naming any of the three routines; a later restatement must restate the whole union again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_renderers_carry_every_record_of_6_sep.sql --apply --ddl

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
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_bd text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'bd' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_bd from public.org_role where role_id = 'business_development';
  select display_name into v_co from public.org_role where role_id = 'compliance_and_privacy_officer';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
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

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

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
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_bd, 'Business Development Manager') || ' (org_role business_development, agent bd, department supply) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the BD manager; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake; lead sourcing). '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Compliance & Privacy Officer') || ' (org_role compliance_and_privacy_officer, agent compliance_mgr, '
        'department legal — the actor of supplier_onboarding step 4 "Compliance screen before anything is activated"). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE task on the compliance officer with the evidence and ONE hold on the BD manager — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the compliance officer decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
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

CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int;
        c_keep constant int := 19500;   -- what fn_agent_context_capped keeps of the head at 24,000
        v_room int; l2_cap int; l1_cap int; l3_cap int; l4_cap int; v_used int; v_first boolean;
        v_ops jsonb; v_ops_txt text;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_loop text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text;
        v_genome text;
        v_risks text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';

    -- ---- THE COMPANY GENOME (spec layer 9: every employee inherits all eleven attributes) -----
    -- A LIST OF HEADINGS WOULD SATISFY THE CHECK AND TEACH NOBODY ANYTHING, so each line carries the
    -- doctrine itself. 170 characters of it (was 220): the 550 characters bought back are what pay
    -- for the first profession row in the head.
    select string_agg('- '||c.title||': '||left(regexp_replace(c.body, '\s+', ' ', 'g'), 170),
                      E'\n' order by c.article_no)
      into v_genome
      from public.company_constitution c
     where c.title in ('Core values','Vision','Decision principles','Risk appetite',
                       'Hiring philosophy','Brand personality','Customer promises',
                       'Supplier promises','Ethics','Leadership style','Growth strategy');
    if v_genome is not null then
      out := out || '# THE COMPANY GENOME - you inherit every line of this'||E'\n'||v_genome||E'\n\n';
    end if;

    -- ---- WHAT THE COMPANY IS WORRIED ABOUT --------------------------------------------------
    -- RENDERED RAW: the check matches left(risk, 50) verbatim. Highest impact and likelihood first;
    -- capped at 12 entries so the register cannot crowd the profession out of the head.
    -- ALIAS rr, NOT r: `r record` is declared above and plpgsql resolves the identifier to it.
    select string_agg('- ['||coalesce(z.impact,'?')||' impact / '||coalesce(z.probability,'?')
                      ||' likelihood] '||z.risk
                      ||case when coalesce(z.mitigation,'') <> ''
                             then '  -> mitigating: '||left(z.mitigation, 120) else '' end,
                      E'\n' order by z.ord)
      into v_risks
      from (select rr.impact, rr.probability, rr.risk, rr.mitigation,
                   row_number() over (order by case coalesce(rr.impact,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               case coalesce(rr.probability,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               rr.id) ord
              from public.risk_register rr
             where coalesce(rr.status,'open') in ('open','mitigating') and length(rr.risk) > 20) z
     where z.ord <= 12;
    if v_risks is not null then
      out := out || '# WHAT THE COMPANY IS WORRIED ABOUT - its own live risk register'||E'\n'
                 || v_risks||E'\n\n';
    end if;

    -- ---- THE EMPLOYEE OBJECT (spec line 372) --------------------------------------------------
    select a.title, a.responsibilities, a.manager_key, a.seniority, a.improvement_plan, a.max_open_tasks
      into v_title, v_resp, v_mgr, v_sen, v_plan, v_cap_tasks
      from org_agents a where a.agent_key = p_agent_key;

    v_emp := '# YOUR EMPLOYEE RECORD'||E'\n'
      ||'Job title: '||coalesce(v_title,'(untitled)')
      ||'  |  Department: '||coalesce(v_dept,'(unassigned)')
      ||'  |  Seniority: '||coalesce(v_sen,'(unset)')||E'\n';

    if v_mgr is not null then
      select 'Reports to: '||m.agent_key||' — '||coalesce(m.title, m.role, 'manager') into v_line
        from org_agents m where m.agent_key = v_mgr;
      v_emp := v_emp || coalesce(v_line, 'Reports to: '||v_mgr) || E'\n';
    else
      v_emp := v_emp || 'Reports to: nobody — you are the top of the reporting line.'||E'\n';
    end if;

    select count(*), string_agg(x.agent_key||' ('||coalesce(x.title, x.role, 'specialist')||')', '; ' order by x.agent_key)
      into v_n, v_line
      from (select b.agent_key, b.title, b.role from org_agents b
             where b.manager_key = p_agent_key and b.active order by b.agent_key limit 12) x;
    if coalesce(v_n,0) > 0 then
      v_emp := v_emp || 'Your direct reports ('||v_n||'): '||v_line||E'\n'
        ||'You are accountable for their output: review it, return poor work for revision, and coach them.'||E'\n';
    end if;

    if v_resp is not null then v_emp := v_emp || 'Your responsibilities: '||left(v_resp, 600)||E'\n'; end if;
    if v_plan is not null then v_emp := v_emp || 'Your improvement plan: '||left(v_plan, 300)||E'\n'; end if;

    -- ---- AUTHORITY LIMITS ----------------------------------------------------------------------
    select string_agg(z.action_class||' -> '||z.max_tier
             ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
             order by z.action_class)
      into v_line
      from (select e.action_class, e.max_tier, e.threshold_aed from employee_authority e
             where e.agent_key = p_agent_key order by e.action_class limit 14) z;
    if v_line is null then
      select string_agg(z.action_class||' -> '||z.max_tier
               ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
               order by z.action_class)
        into v_line
        from (select o.action_class, o.max_tier, o.threshold_aed from org_authority o
               where o.dept_key = v_dept order by o.action_class limit 14) z;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (delegated to '||v_dept||', no personal grant on file)'||E'\n';
      end if;
    else
      v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (granted to you personally)'||E'\n';
    end if;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n'
        ||'Anything not on that list is GATED: propose it, do not do it.'||E'\n';
    end if;

    -- ---- ESCALATION RULES (blueprint component 5) ----------------------------------------------
    select string_agg(distinct '- when ' || replace(e.escalation_rule->>'when','_',' ')
                             || ' -> ' || replace(e.escalation_rule->>'action','_',' '), E'\n')
      into v_line
      from (select escalation_rule from ops_knowledge
             where dept_key = v_dept
               and escalation_rule is not null
               and escalation_rule ? 'when' and escalation_rule ? 'action'
             limit 40) e;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHEN TO ESCALATE (your department''s recorded rules)'||E'\n'||left(v_line, 700)||E'\n';
    end if;

    -- ---- KPIs: how this employee's work is judged ----------------------------------------------
    select string_agg(z.kpi||' — target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
             ||' ('||coalesce(z.cadence,'ongoing')
             ||case when z.serves_goal is not null then '; serves company goal '||z.serves_goal else '' end||')', E'\n- '
             order by z.kpi)
      into v_line
      from (select k.kpi, k.target_value, k.unit, k.cadence, k.serves_goal from employee_kpi k
             where k.agent_key = p_agent_key and k.active order by k.kpi limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR KPIs — this is how your work is measured'||E'\n- '||v_line||E'\n';
    end if;

    -- ---- CURRENT WORKLOAD, measured rather than assumed -----------------------------------------
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' proposed (held for review with '
           ||coalesce((select d.lead_agent from org_departments d where d.dept_key = v_dept), 'the department lead')
           ||', not the founder — a refund is the only decision that goes to him). Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
      into v_line
      from org_tasks t where t.dept_key = v_dept and t.status in ('assigned','in_progress');
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR CURRENT WORKLOAD (live)'||E'\n'||v_line||E'\n';
      select string_agg('- ['||z.status||'] '||left(z.title,90), E'\n' order by z.id)
        into v_line
        from (select t.id, t.status, t.title from org_tasks t
               where t.dept_key = v_dept and t.status in ('assigned','in_progress')
               order by t.id limit 6) z;
      if v_line is not null then v_emp := v_emp || v_line || E'\n'; end if;
    end if;

    -- ---- WHICH OPERATING SYSTEM YOU BELONG TO (spec file #2) ------------------------------------
    for r in
      select o.os_key, o.name, o.charter, o.mandate, o.mission, o.owner_agent,
             (select coalesce(w.title, w.role) from org_agents w
               where w.agent_key = o.owner_agent and w.active) owner_title,
             (select string_agg(x.responsibility, ', ' order by x.responsibility)
                from (select responsibility from os_responsibility where os_key = o.os_key
                       order by responsibility limit 12) x) resp,
             (select string_agg(y.horizon || ': ' || y.objective, E'\n- '
                       order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                               when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
                from (select horizon, objective from os_objective
                       where os_key = o.os_key and coalesce(active,true)) y) objectives
        from os_department d
        join operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
       where d.dept_key = v_dept
       limit 1
    loop
      v_os := r.os_key;
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
      v_emp := v_emp || E'\n'||'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)||E'\n'
        ||case when r.charter is not null then 'Purpose: '||left(r.charter,300)||E'\n' else '' end
        ||case when r.mission is not null then 'Mission: '||left(r.mission,240)||E'\n' else '' end
        ||case when r.mandate is not null then 'Mandate: '||left(r.mandate,240)||E'\n' else '' end
        ||v_line
        ||case when r.resp is not null
               then 'Your OS OWNS, and no other OS may own: '||r.resp||E'\n'
                 ||'If work belongs to another OS, hand it over — do not duplicate it.'||E'\n'
               else '' end
        ||case when r.objectives is not null
               then 'Your OS objectives by horizon:'||E'\n- '||r.objectives||E'\n' else '' end;
    end loop;

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
    select string_agg(z.goal||' ('||coalesce(z.metric,'no metric')
             ||case when z.target_value is not null then '; target '||z.target_value||' '||coalesce(z.unit,'') else '' end
             ||case when z.actual_value is not null
                    then '; CURRENTLY '||z.actual_value||coalesce(' ('||z.status||')','') else '; not yet measured' end||')', E'\n- '
             order by z.sort nulls last)
      into v_line
      from (select g.goal, g.metric, g.target_value, g.unit, g.sort, gp.actual_value, gp.status
              from company_goals g
              left join lateral (select p.actual_value, p.status from goal_period p
                                  where p.goal_key = g.key
                                  order by p.updated_at desc nulls last limit 1) gp on true
             where g.active and (g.owner_dept is null or g.owner_dept = v_dept or g.owner_dept = 'exec')
             order by g.sort nulls last limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# COMPANY GOALS YOUR WORK MUST MOVE'||E'\n- '||v_line||E'\n';
    end if;

    select string_agg('- '||z.objective, E'\n' order by z.sort nulls last)
      into v_line
      from (select o.objective, o.sort from department_objective o
             where o.dept_key = v_dept and coalesce(o.active,true) order by o.sort nulls last limit 6) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR DEPARTMENT''S OBJECTIVES'||E'\n'||v_line||E'\n';
    end if;

    -- ---- THE IMPROVEMENT LOOP, WHICH WROTE WHERE NOTHING READ -------------------------------
    -- Collected into v_loop and emitted AFTER LAYER 4 (see below): still read by every uncapped
    -- caller, no longer paid for out of the head that carries the profession and the live state.
    select string_agg(z.line, E'\n' order by z.ord, z.line)
      into v_line
      from (
        select 1 ord, '- OPEN FINDING ('||s.review_type||'): '||left(s.finding, 160)
               ||coalesce(' — proposed: '||left(s.proposal,120), '') line
          from self_review s
         where coalesce(s.status,'open') not in ('done','implemented','rejected')
         order by s.created_at desc limit 3
      ) z;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_loop := v_loop || v_line || E'\n';
    end if;

    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_loop := v_loop || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 5200) || E'\n\n';

    -- ---- YOUR THRESHOLDS: the decision_policy rows the gates enforce for this department ---------
    v_line := public.fn_dept_decision_thresholds(v_dept);
    if v_line is not null then out := out || v_line || E'\n\n'; end if;
  end if;

  -- ================= THE BUDGETED LAYERS. Everything below is measured against c_keep. ============
  -- v_room is what is left of the 19,500 the capped path keeps. LAYER 2 takes its share first (and the
  -- first row is admitted unconditionally); the remainder is re-split among LAYER 1, 3 and 4 after
  -- LAYER 2 has actually been emitted, so an employee with one 700-character profession row hands the
  -- slack on rather than leaving it empty.
  v_room := greatest(c_keep - length(out), 3200);
  l2_cap := greatest(1200, v_room * 27 / 100);

  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    v_used := 0; v_first := true;
    for r in select topic,content,review_due,validation_status from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and coalesce(validation_status,'') <> 'quarantined'
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if v_first then
        -- the first profession row ALWAYS lands: truncated to the budget if it is longer than the budget
        if length(piece) > l2_cap then
          piece := left(piece, l2_cap - 90)||E'\n'||'[… profession row truncated to the LAYER 2 budget; the full row is in agent_knowledge.]'||E'\n\n';
        end if;
        out := out || piece; v_used := v_used + length(piece); v_first := false;
      elsif v_used + length(piece) <= l2_cap then
        out := out || piece; v_used := v_used + length(piece);
      end if;
    end loop;
    if v_first then
      out := out || '(no profession row is on file for you or your department yet; ask people_ops to seed one)'||E'\n\n';
    end if;
  end if;

  -- re-split what is left among LAYER 1 / 3 / 4
  v_room := greatest(c_keep - length(out), 2400);
  l1_cap := greatest(800, v_room * 36 / 100);
  l3_cap := greatest(700, v_room * 28 / 100);
  l4_cap := greatest(700, v_room - l1_cap - l3_cap - 160);

  -- ---- LAYER 1: the four hard rules, the LIVE company rows, then the _global canon ----------------
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  piece := coalesce(public.fn_company_hard_rules(), '');
  out := out || piece || E'\n';
  -- 6 SEP 2026: the company's licence and tax status in one line, read from company_registration
  -- (the founder supplied the licence and ruled on VAT that day; the full record is qd-company:registration).
  select 'LICENCE & TAX: ' || cr.authority || ' ' || cr.license_type || ' no. ' || cr.license_no || ' "' || cr.trade_name || '", expires '
         || to_char(cr.expires_on, 'DD Mon YYYY') || '; activities ' || left(cr.activities, 90) || '. '
         || case when cr.vat_registered then 'VAT-registered, TRN ' || coalesce(cr.trn, '?') || '.'
                 else 'NOT VAT-registered: no VAT is charged or shown until AED ' || to_char(cr.vat_threshold_aed, 'FM999,999,999')
                      || ' taxable supplies in 12 months (founder ruling ' || to_char(cr.vat_ruling_on, 'DD Mon YYYY') || '; never ask the founder about VAT or the TRN).' end
    into piece from public.company_registration cr order by cr.recorded_at desc limit 1;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  -- 6 SEP 2026: the brand in one line, read from company_brand (the founder's kit is on file; the full record
  -- is qd-company:brand). Every head carries it so no employee ever asks him for a hex, a font or a logo.
  piece := null;
  select 'BRAND: teal ' || t.v || ' (primary), gold ' || g.v || ' (secondary), navy ' || n.v || ' (background), ink ' || i.v
         || ' (print); typeface ' || d.v || '; logo = teal Q-ring + gold check, clear space = the ring height, mark never below 24 px, '
         || 'lockup never below 120 px wide; files in the brand bucket kit/ (public.brand_assets), rules in public.company_brand '
         || '(qd-company:brand); the guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md. Never ask the founder for brand assets.'
    into piece
    from (select value as v from public.company_brand where key = 'colour.teal') t,
         (select value as v from public.company_brand where key = 'colour.gold') g,
         (select value as v from public.company_brand where key = 'colour.navy') n,
         (select value as v from public.company_brand where key = 'colour.ink') i,
         (select value as v from public.company_brand where key = 'type.display') d;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  v_used := 0;
  for r in select o.record_id, o.title, o.content, o.effective_date
             from ops_knowledge o
            where o.record_id in ('qd-company:stage','qd-company:live-state')
            order by case o.record_id when 'qd-company:stage' then 1 else 2 end loop
    piece := '## '||coalesce(r.title, r.record_id)||' (live, effective '||coalesce(to_char(r.effective_date,'DD Mon YYYY'),'?')||')'||E'\n'
             ||left(regexp_replace(coalesce(r.content,''), E'\n\nYou can answer questions about:.*$', ''), 700)||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out || piece; v_used := v_used + length(piece); end if;
  end loop;
  -- The _global canon, highest priority first, each cut at 500 inside the head. company:self_knowledge
  -- is skipped here (the live rows above replaced it); the untruncated remainder follows LAYER 4.
  for r in select id, topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 500
                  then left(r.content, 500)||E'\n'||'[… cut at 500 of '||length(r.content)||' characters; the full item is in agent_knowledge.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out||piece; v_used := v_used + length(piece); end if;
  end loop;

  -- ---- LAYER 3: live operational state, inside the head -----------------------------------------
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), l3_cap - 160)||E'\n\n';
      out := out || piece;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;

  -- ---- LAYER 4: what the organisation has learned, inside the head --------------------------------
  if p_agent_key is not null then
    for r in select topic, content, review_due, validation_status from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
               and coalesce(validation_status,'') <> 'quarantined'
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, l4_cap - 60) || E'\n';
    end if;
  end if;

  -- ================= AFTER THE HEAD. Reaches the uncapped callers; bounded by cap. ==============
  -- The improvement loop, then the rest of the _global canon in full.
  if v_loop <> '' then out := out || v_loop || E'\n'; end if;

  out := out || '# LAYER 1 (continued) - THE REST OF THE COMPANY CANON'||E'\n\n';
  for r in select topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;

  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  if v_os is not null then
    select string_agg(z.horizon||': '||z.objective||' — reads '
             ||coalesce(z.actual_value::text,'no value')
             ||coalesce(' (measured '||to_char(z.measured_at,'DD Mon')||')', ' (measure failed)'),
             E'\n- '
             order by case z.horizon when 'strategic' then 1 when 'annual' then 2
                                     when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
      into v_line
      from (select horizon, objective, actual_value, measured_at from os_objective
             where os_key = v_os and coalesce(active,true)) z;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS OBJECTIVES, MEASURED (the number, not the aspiration)'
             ||E'\n- '||left(v_line, 1600)||E'\n';
    end if;

    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
      from (select r2.id, r2.workflow_key, r2.current_step, r2.status, r2.started_at
              from workflow_run r2 join workflow w2 on w2.workflow_key = r2.workflow_key
             where r2.status in ('queued','running') and w2.os_key = v_os
             order by r2.started_at desc nulls last limit 8) x
      join workflow w on w.workflow_key = x.workflow_key
     where w.os_key = v_os;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS''S WORKFLOWS IN FLIGHT (workflow_run)'||E'\n'
             ||left(v_line, 900)||E'\n'
             ||'Close a step with fn_workflow_step_done(run, step_no, output).'||E'\n';
    end if;
  end if;

  -- ---- THE TARGET OPERATING MODEL — the Company Operations pack, finally addressed to a person ---
  if v_dept is not null then
    v_ops := public.fn_ops_department_context(v_dept, null, 2);
    if v_ops is not null and jsonb_array_length(coalesce(v_ops->'target_departments','[]'::jsonb)) > 0 then
      v_ops_txt := 'Your department maps to '
        || (select string_agg(t, ', ') from jsonb_array_elements_text(v_ops->'target_departments') t)
        || ' in the target operating model: '
        || jsonb_array_length(v_ops->'sops') || ' SOP(s), '
        || jsonb_array_length(v_ops->'decision_rules') || ' decision rule(s), '
        || jsonb_array_length(v_ops->'exception_playbooks') || ' exception playbook(s), '
        || jsonb_array_length(v_ops->'kpis') || ' KPI(s), '
        || jsonb_array_length(v_ops->'handoffs') || ' handoff(s), '
        || jsonb_array_length(v_ops->'templates') || ' template(s).' || E'\n';

      select coalesce(string_agg('- RULE ' || coalesce(d->>'rule_id','?') || ': when ' ||
               left(coalesce(d->>'when',''),110) || ' -> ' || left(coalesce(d->>'then',''),110) ||
               case when coalesce((d->>'requires_human_review')::boolean,false)
                    then ' [needs human review]' else '' end, E'\n'), '')
        into v_line from (select d from jsonb_array_elements(v_ops->'decision_rules') d limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg('- ' || (h->>'direction') || ' ' || coalesce(h->>'workflow','') ||
               ' (' || coalesce(h->>'from','?') || ' -> ' || coalesce(h->>'to','?') || '): ' ||
               left(coalesce(h->>'you_must',''),90), E'\n'), '')
        into v_line from (select h from jsonb_array_elements(v_ops->'handoffs') h limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg(e->>'event', ', '), '')
        into v_line from (select e from jsonb_array_elements(v_ops->'event_subscriptions') e limit 6) z;
      if coalesce(v_line,'') <> '' then
        v_ops_txt := v_ops_txt || 'Events your target model consumes (NOT yet activated on the live bus): '
                     || v_line || E'\n';
      end if;

      out := out || E'\n' || '# HOW YOUR DEPARTMENT IS DEFINED IN THE TARGET OPERATING MODEL'
             || E'\n' || left(v_ops_txt, 900) || E'\n'
             || 'Full text: select fn_ops_department_context(''' || v_dept || ''', <your topic>).' || E'\n';
    end if;
  end if;

  return out;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record; v_cat text; catx text := '';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  -- THE CATEGORY, derived from the task itself (inquiry / run reference, a key, or a catalogue name).
  v_cat := public.fn_category_key_from_text(p_query);

  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  -- THE MARKER IS ALWAYS EMITTED. fn_agent_context_capped splits the standing head from the retrieved
  -- tail on '# LAYER 2b'; when the library had no match there was no marker, and the whole retrieved
  -- tail fell past a positional cut instead of being kept inside the 4,500-character reserve.
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  else
    out := out || E'\n' || '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY: no dept_library row matched this task.' || E'\n\n';
  end if;

  -- LAYER 2d/2e/2f/2g: the V3 delivery, now WITH the category key when the task names one.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, v_cat, 9000);

    -- LAYER 2e first: the category pack has to sit inside the reserve the capped path keeps.
    if v_cat is not null and v3 ? 'category_knowledge' then
      for itm in select * from jsonb_array_elements(coalesce(v3->'category_knowledge','[]'::jsonb)) loop
        exit when length(catx) > 1800;
        catx := catx || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
              || left(regexp_replace(coalesce(itm->>'content',''), '\s+', ' ', 'g'), 600) || E'\n\n';
      end loop;
      if catx <> '' then
        out := out || E'\n' ||
          '# LAYER 2e - THE CATEGORY PACK FOR THIS TASK (' || v_cat || '): the route''s qualification playbook, ' ||
          'field and question bank, quality gate and comparison contract. This task is category-scoped; these records ' ||
          'decide what to ask, what may never be inferred and how quotes in this route are compared. Cite the [record_id].' ||
          E'\n\n' || catx;
      end if;
    end if;

    for r2 in
      select title, content, record_type, authority_tier, implementation_status, rank
        from public.fn_ops_knowledge_search(v_dept, p_query, 5)
       order by rank desc
    loop
      exit when length(ops) > 2400;
      ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
             coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
             coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
    end loop;
    if ops <> '' then
      out := out || E'\n' ||
        '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
        'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
        'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
        'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
        E'\n\n' || ops;
    end if;

    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
            || left(coalesce(itm->>'content',''), 700) || E'\n\n';
      end loop;
      if sec <> '' then
        out := out || E'\n' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'\n\n' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'\n\n' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'\n\n' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$;

-- ownership follows the manifest: every overload of the three routines is defined by this file
update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_company_renderers_carry_every_record_of_6_sep.sql',
       evidence = 'the union of the 6 Sep 2026 restatements, read from production at 15:2xZ and recorded in one canonical file'
 where schema_name = 'public' and routine_name in ('fn_company_self_knowledge_sync', 'fn_company_hard_rules', 'fn_agent_context');

-- proof: every record of the day renders, the hard rules carry the day's rulings, both context overloads exist
do $$
declare n int; v text;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = 'fn_agent_context';
  if n <> 2 then raise exception 'fn_agent_context overloads: % (expected 2)', n; end if;
  v := public.fn_company_hard_rules();
  if v not like '%NO discount%' or v not like '%CATEGORY OPENING%' or v not like '%THE LADDER%' then raise exception 'hard rules missing a 6 Sep ruling'; end if;
  select prosrc into v from pg_proc where proname = 'fn_company_self_knowledge_sync' limit 1;
  if v not like '%''messaging-templates''%' or v not like '%''supplier-loops''%' or v not like '%''brand''%' or v not like '%''decisions''%' or v not like '%''refunds''%' then
    raise exception 'self-knowledge renderer missing a 6 Sep record';
  end if;
end $$;
