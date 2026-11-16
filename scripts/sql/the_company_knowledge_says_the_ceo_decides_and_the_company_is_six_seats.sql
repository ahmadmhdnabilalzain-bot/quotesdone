-- THE COMPANY KNOWLEDGE SAYS THE CEO DECIDES, AND THE COMPANY IS SIX SEATS, NOT TEN DEPARTMENTS.
--
-- Assigned: ceo (company knowledge). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers 1714/1715 (audit the code for
-- assumptions that no longer hold; remove what is unnecessary and prove it). Audit: scratchpad audit_simplify/STALE.md S2.
--
-- MEASURED BEFORE WRITING (16 Nov 2026; light SELECTs on production; routine bodies by pg_get_functiondef):
--   * fn_company_self_knowledge_sync (md5 f026a9a056f7be813d61fee198e762b3) and fn_company_org_directory_sync (md5
--     1c425234ef42fef01469d5873b52ea22) write the public.ops_knowledge rows 'qd-company:*' (effective 12 Nov 2026) that
--     fn_reason_retrieve_ml hands every internal seat. They said, in the routine's own literals:
--       commercials  "the Customer Success Director chases the supplier" / "the founder is notified for his final call" /
--                    "EVERY refund of any amount is the founder's approval"
--       refunds      title "founder's final call at 5"; "final call + approval = the founder"; chase by the "Customer Success
--                    Director (runtime agent followup, customer_experience)"
--       terms        "founder's final call on day 5"
--       governance   "ten autonomous AI departments (90 brain agents)"; "every refund, any amount, needs his approval"
--       identity     "he is the ONLY approver of refunds"; "Every department is an autonomous AI expert"
--       organization "THE TEN DEPARTMENTS:" (read from the departments table, which has 0 rows)
--       stage        "10 departments and 6 AI agents, 30 workflows"; "funded AI inference" still pending
--       legal        "EVERY refund is founder-approved"
--     and the decisions row rendered public.company_policy_decision, whose rows said "Paid inference (OpenRouter) is HELD"
--     (openrouter_credit), "nothing needs the founder's approval except Stripe refunds" (founder_standing_rules), "On the
--     fifth day the founder is notified to make the final call ... AED 250 ... 9%" (refund_ladder), "None of it runs until
--     the founder says the app is perfect" (supplier_acquisition_and_screening; app_secrets.supplier_outreach_golive is
--     'true'), a category opens at a fixed 10 (category_open_threshold), and named departments that do not exist in
--     applies_to (cfo, bookkeeper, sales_director, followup ...). The eleven qd-company:org-<dept> rows (7 Sep 2026) are
--     still current and runtime-eligible. The public FAQ row 167 (and its Arabic twin 616) says "our Customer Success
--     Director chases them" and "every refund is decided by a person here".
--   * The refund ladder as it runs (fn_refund_ladder_sweep, production): 'sales_engineer writes, customer_support
--     delivers, ceo decides'; founder_mail_policy refund_final_call / refund_approval / refund_decision are retired.
--
-- THE RULINGS THAT MAKE THE OLD TEXT WRONG (public.founder_instruction, quoted):
--   8 Sep 2026 (company_policy_decision every_refund_is_the_ceos): "refunds belong to the CEO from now on" and "all
--     approvals are from CEO. nothing goes to me."
--   1696 (15 Nov): "CEO is having full authority. He can do whatever is needed to achieve the target we have for the
--     company. He doesnt rely on me in anything." 1710 (15 Nov): "I don't want you to wait on me ... don't rely on me."
--   7 Sep 2026 and 907: seats, no departments (the six seats of public.org_role).
--   1175 (7 Oct): "from now on keep open router always on". 1205 (12 Oct): leads are sourced monthly by Claude "not by the
--     automated daily lead_sourcing job". 1614: "open a trade to customers as soon as it has enough verified suppliers".
--
-- WHAT THIS DOES (text only; no money path, no permission, no schedule changes):
--   1. fn_company_self_knowledge_sync: the CEO decides refunds and every approval; the sales engineer chases through
--      customer support; the seats are read live from org_role; the stage names seats and says paid inference is on; the
--      trade-opening level is read from trade_opening_rule; the founder's 6 Sep verbatim words (which said he decides) are
--      no longer printed as the current rule. Starts from the production body above (md5 matched before the edit).
--   2. fn_company_org_directory_sync: the per-department loop is removed (0 rows since 7 Sep; it also lets the departments
--      table be retired), and the legal posture says the CEO decides refunds.
--   3. company_policy_decision: the five rows above restated from the rulings that superseded them, each saying so; every
--      applies_to names seats.
--   4. company_faq 167 / 616: no Customer Success Director, no "a person decides".
--   5. The eleven qd-company:org-* rows are marked superseded; the sync is run once so every qd-company row is rewritten.
-- prevented by: the_company_knowledge_says_the_ceo_decides_and_the_company_is_six_seats_probe.sql (LOCAL Postgres 16: it runs
-- the sync and fails on any of the stale phrases above, or on a missing CEO / seats sentence).
-- LOCKS: two routines replaced in place; a few rows of company_policy_decision, company_faq and ops_knowledge updated.
set local lock_timeout = '3s';

create or replace function public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  -- 16 NOV 2026 (ceo, wave D): fn_company_brief printed a department roster; the seats are read from org_role below.
  v_seats text; v_seat_n int; v_open_at int; v_cat_n int;
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_supply_owner text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'sales_engineer' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_supply_owner from public.org_role where role_id = 'sales_engineer';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company). 9 SEP 2026 -- PHASE MACHINERY REMOVED: this read
  -- the founder-identity register, which is deleted in this sweep. It was never an authority
  -- check here, only the address printed in the "who we are" knowledge record, so it is read from
  -- app_secrets.founder_email -- the same place fn_page_high_agent_action already reads it -- and
  -- falls back to the same literal the record already carried.
  select value into v_founder from public.app_secrets where key = 'founder_email';
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

  -- the six seats (rulings of 7 Sep 2026 and 907: seats, no departments), live from org_role
  select count(*), string_agg('  - ' || r.role_id || ' (' || coalesce(r.display_name, r.role_id) || '): ' || left(coalesce(r.responsibilities, ''), 320), E'\n' order by r.role_id)
    into v_seat_n, v_seats from public.org_role r where r.status = 'active';
  -- the CEO-tuned opening level (ruling 1614: trade by trade), else the platform's own level
  select t.open_at_suppliers into v_open_at from public.trade_opening_rule t order by t.id limit 1;
  v_open_at := coalesce(v_open_at, v_cat_min);
  select count(*) into v_cat_n from public.catalog_supplier_categories;

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

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. v_funnel was a listing of W04..W18 read from
  -- the programme workflow registry, appended to the marketplace knowledge record as "The 30 workflows
  -- that run this". The workflow registry is deleted in this sweep and the company is two agents
  -- with no departments and no W-numbered programme, so the sentence is dropped rather than left
  -- describing an organisation that no longer exists. The prose above still explains the funnel in
  -- plain words, which is what an agent answering a question actually needs.

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
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the accountant opens a registration task.' end || E'\n' ||
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
          ' — every seat''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Six AI seats (ceo, sales_engineer, customer_support, accountant, it_engineer, marketing; no departments) plan and execute toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries. The CEO seat has full authority within them and decides '
        'every approval, refunds of any amount included (rulings of 8 Sep 2026, 1696 and 1710); the founder is told the result and is never waited on.'),

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
        'masked until then.' ),

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
        'TRADE OPENING: a trade opens to customers trade by trade once it has ' || v_open_at || ' verified registered suppliers, the level the CEO tunes weekly (trade_opening_rule, ruling 1614); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the sales engineer chases the supplier through customer support, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the sales engineer makes the final call and the CEO seat decides. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the CEO''s decision (8 Sep 2026), the founder is told the result - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (the agreed rate of v14; 9% under v13 or earlier), per the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: ' || v_pct::text || '% per annum simple, the rate agreed in Supplier Agreement v14 clause 31 (Federal Decree-Law 50/2022 Arts. 73 and 84; 9% for amounts due under v13 or earlier).'),

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
        || coalesce(v_chase_wd::text,'3') || ', the CEO''s decision on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','who decides','autonomy','refund approval','founder','ceo authority','escalation','boundaries','decisions','authority','seats']),
      'content',
        'QuotesDone runs as ' || coalesce(v_seat_n, 6) || ' AI seats and no departments (rulings of 7 Sep 2026 and 907): '
        'ceo, sales_engineer, customer_support, accountant, it_engineer and marketing. The CEO seat has full authority to reach '
        'the company target and is responsible for its decisions and their outcomes (ruling 1696): it decides every approval '
        'a seat needs, refunds of any amount included (8 Sep 2026), and the marketing month (15 Nov 2026), and it does not '
        'wait on the founder (ruling 1710). The founder sets the vision, the target and the boundaries, keeps his emergency '
        'stops and is told results; he is asked only what is truly his, such as a fact or a credential only he holds (ruling 1706). '
        'Seats hand work to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: the Seats, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','seats','how many agents','who works here','colleagues','roles','team','who does what','are there departments','departments','list the seats','who decides']),
      'content', 'THE COMPANY YOU WORK IN (live roster from org_role — these are your colleagues; know who does what).' || E'\n' ||
        'THERE ARE NO DEPARTMENTS: the company is ' || coalesce(v_seat_n, 0) || ' seats (rulings of 7 Sep 2026 and 907). The CEO seat leads and decides (ruling 1696).' || E'\n' ||
        coalesce(v_seats, '  (org_role is empty)')),

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
        '  Seats: ' || coalesce(v_seat_n::text, v_snap->>'employees', '6') || ' (no departments)' || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || E'\n' ||
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
        || coalesce(v_seat_n, 6) || ' AI seats (no departments), ' || coalesce(v_cat_n, 0) || ' supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','0') || ' approved supplier(s); paid model inference is on (ruling 1175). '
        'The order is: enough registered suppliers first, then a customer campaign (ruling 1701). '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, the CEO decides at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','who decides a refund','ceo decides the refund','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (the founder''s ruling of 6 Sep 2026 for the days and the money; the authority is the CEO''s since 8 Sep 2026; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the sales engineer writes the chase and customer support delivers it to the supplier, customer copied, WhatsApp when opted in. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door), the sales engineer makes the final call through customer support, and the CEO seat decides on what comes back.' || E'\n' ||
        '  No response to that call: the CEO approves the refund (fn_refund_decide; every refund, any amount, is the CEO''s decision, never automatic; public.refunds refuses a refund without a ceo_approval row). The founder is told the result, never asked (8 Sep 2026; rulings 1696, 1710).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the rate agreed in v14; 9% under v13 or earlier), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase and final call = the sales engineer, delivered by customer support; the decision = the CEO; execution on Stripe, reconciliation and recovery from the supplier = the accountant. Never ask the founder about refunds.'),

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
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_supply_owner, 'Sales Engineer') || ' (org_agents.sales_engineer; there are no departments) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the sales engineer; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake). New leads are sourced once a month by Claude on the subscription and ingested (ruling 1205), not by an automated job. '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Chief Executive (AI)') || ' (org_agents.ceo — a confirmed hit removes a supplier and every approval is the CEO''s; '
        'the sales engineer holds the outreach while the decision is open). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE decision task on the ceo with the evidence and ONE hold on the sales engineer — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the ceo decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
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
end $function$
;

create or replace function public.fn_company_org_directory_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_social text; v_blog text; v_web text; v_cat text;
        v_legal text; v_compl text; v_biz jsonb; v_n int := 0;
begin
  -- 1. 16 NOV 2026 (ceo, wave D) -- REMOVED. This loop wrote one qd-company:org-<dept> record per row of
  --    the departments table. There are no departments (rulings of 7 Sep 2026 and 907); the table has 0 rows, so the loop
  --    wrote nothing since 7 Sep and the eleven org-* records it left are marked superseded by the file that carries
  --    this routine. The seats are described once, in qd-company:organization (fn_company_self_knowledge_sync).

  -- 2. THE PUBLISHED FAQ — grouped by section; the 484 answers a colleague could give a customer or supplier.
  for s in select coalesce(nullif(btrim(section),''),'general') sec, string_agg('Q: '||question||E'\n'||'A: '||coalesce(answer,''), E'\n' order by sort nulls last, id) qa
             from public.company_faq where coalesce(public,true) and coalesce(status,'approved') <> 'rejected'
             group by 1 loop
    perform public.fn_company_knowledge_upsert(
      'faq-' || regexp_replace(lower(s.sec),'[^a-z0-9]+','-','g'), 'faq',
      'QuotesDone FAQ — ' || s.sec,
      'FREQUENTLY ASKED (published answers — you may give these to customers and suppliers):' || E'\n' || left(s.qa, 6000),
      array['faq', 'frequently asked', s.sec, 'question', 'answer', 'how do i', 'what is', 'customer question', 'supplier question']);
    v_n := v_n + 1;
  end loop;

  -- 3. SOCIAL, BLOG, WEBSITE — the company's own published content.
  select string_agg('  - ['||to_char(created_at,'DD Mon YYYY')||', '||coalesce(channels::text,'')||', '||coalesce(status,'')||'] '
                    || left(coalesce(content->>'text', content->>'body', content::text), 200), E'\n' order by created_at desc)
    into v_social from public.social_posts;
  perform public.fn_company_knowledge_upsert('content-social','content','QuotesDone — Our Social Media Posts',
    'SOCIAL MEDIA POSTS (most recent first):' || E'\n' || coalesce(v_social,'(none yet)'),
    array['social media','social post','last post','latest post','instagram','linkedin','what did we post','our content','marketing post']);
  v_n := v_n + 1;

  select string_agg('  - ['||coalesce(to_char(published_at,'DD Mon YYYY'),'draft')||', '||coalesce(category,'')||'] '||title
                    ||coalesce(' — '||excerpt,''), E'\n' order by published_at desc nulls last)
    into v_blog from public.blog_posts where published;
  perform public.fn_company_knowledge_upsert('content-blog','content','QuotesDone — Our Blog Articles',
    'BLOG ARTICLES (published):' || E'\n' || left(coalesce(v_blog,'(none yet)'), 6000),
    array['blog','article','blog post','our articles','what have we written','content','seo','latest blog']);
  v_n := v_n + 1;

  select string_agg('  - /'||slug, E'\n' order by slug) into v_web from public.pages;
  perform public.fn_company_knowledge_upsert('content-website','content','QuotesDone — Our Website Pages',
    'WEBSITE PAGES we publish (the public site an agent should know exists):' || E'\n' || coalesce(v_web,'(none)')
    || E'\n\nThe published legal terms, services and marketing copy live on these pages; the terms and commercials are also summarised in the company terms and commercials knowledge.',
    array['website','web page','our site','pages','website content','what is on our website','public site']);
  v_n := v_n + 1;

  -- 4. THE SUPPLIER CATEGORY TAXONOMY — every category an RFQ can be routed to.
  select string_agg('  ' || num || '. ' || name || case when regulated then ' (regulated)' else '' end, E'\n' order by sort, num)
    into v_cat from public.catalog_supplier_categories;
  perform public.fn_company_knowledge_upsert('categories', 'taxonomy',
    'QuotesDone — The Supplier Categories We Cover',
    'SUPPLIER CATEGORIES (' || (select count(*) from public.catalog_supplier_categories)::text
      || ' in total) — every category an RFQ can be routed to, in order:' || E'\n' || coalesce(v_cat, '(none)'),
    array['categories','supplier categories','what do we cover','category list','taxonomy','trades','how many categories','what categories','regulated categories','which category','list the categories']);
  v_n := v_n + 1;

  -- 5. 9 SEP 2026 -- PHASE MACHINERY REMOVED. Section 5 published a company knowledge record
  --    titled "The 30 Workflows We Run", built by reading the programme workflow registry. That registry
  --    is deleted in this sweep, and the company is two agents (ceo, customer_support) with no
  --    departments and no W-numbered programme, so the record described an organisation that does
  --    not exist. The whole section is removed; the already-published copy is deleted below, in
  --    this same transaction, so no agent keeps reciting it out of ops_knowledge. Sections 1-4 and
  --    6-7 are unchanged and the record count in the return value simply drops by one.

  -- 6. LEGAL, COMPLIANCE AND POLICY FRAMEWORK.
  select string_agg('  - ' || coalesce(title, slug) || case when coalesce(category,'') <> '' then ' [' || category || ']' else '' end
         || case when coalesce(summary,'') <> '' then ': ' || left(summary,140) else '' end, E'\n' order by category, title)
    into v_legal from public.legal_documents;
  select string_agg('  - ' || requirement || ' (' || case when present then 'in place' else 'pending' end || ')', E'\n' order by priority nulls last, id)
    into v_compl from public.legal_checklist;
  perform public.fn_company_knowledge_upsert('legal', 'legal_compliance',
    'QuotesDone — Legal, Compliance and Policy Framework',
    'LEGAL & COMPLIANCE. QuotesDone operates under UAE law (Asia/Dubai; PDPL data protection). Published legal documents:' || E'\n'
    || coalesce(v_legal,'(none)') || E'\n' || 'Compliance checklist:' || E'\n' || coalesce(v_compl,'(none)') || E'\n'
    || 'Posture: anonymous marketplace, buyer/supplier identities protected until reveal, every refund is the CEO seat''s decision (8 Sep 2026), '
    || 'late fees under UAE Federal Decree-Law 50/2022, disputes handled through a defined escalation ladder.',
    array['legal','compliance','regulatory','policy','terms of service','privacy policy','pdpl','data protection','uae law','are we compliant','legal documents','what laws apply','governing law','gdpr']);
  v_n := v_n + 1;

  -- 7. THE BUSINESS ENTITIES — the live customer/supplier/order landscape, and HOW to look up any one.
  begin v_biz := public.fn_business_entity_summary(); exception when others then v_biz := '{}'::jsonb; end;
  perform public.fn_company_knowledge_upsert('business-entities', 'business_data',
    'QuotesDone — Our Customers, Suppliers and Orders (live), and how to look them up',
    'THE BUSINESS RIGHT NOW (live counts):' || E'\n' ||
    '  Customers: ' || coalesce(v_biz->>'customers','0') || ' (with an inquiry: ' || coalesce(v_biz->>'customers_with_inquiry','0') || ')' || E'\n' ||
    '  Suppliers: ' || coalesce(v_biz->>'suppliers_total','0') || ' total — ' || coalesce(v_biz->>'suppliers_approved','0') || ' approved, '
      || coalesce(v_biz->>'suppliers_prospective','0') || ' prospective; sendable pool ' || coalesce(v_biz->>'sendable_supplier_pool','0') || E'\n' ||
    '  Inquiries/RFQs: ' || coalesce(v_biz->>'inquiries','0') || '  ·  Quotes: ' || coalesce(v_biz->>'quotes','0') || '  ·  Transactions/orders: ' || coalesce(v_biz->>'transactions','0') || E'\n' ||
    '  Categories: ' || coalesce(v_biz->>'categories_total','0') || ' (' || coalesce(v_biz->>'categories_at_target','0') || ' at the 10-supplier target)' || E'\n' ||
    'HOW TO KNOW A SPECIFIC ONE (do not memorise the records — look them up live):' || E'\n' ||
    '  - fn_business_entity_lookup(entity, key): one customer/supplier/inquiry/quote/transaction by id, email, company name or phone -> its full profile.' || E'\n' ||
    '  - fn_business_entity_list(entity, filter, limit): list or search them (e.g. all approved suppliers, recent inquiries).' || E'\n' ||
    '  - fn_business_entity_summary(): these live counts. Call these functions directly — you run with the database access to do so.',
    array['customers','suppliers','how many customers','how many suppliers','who are our customers','who are our suppliers','their profiles','their orders','look up a supplier','find a customer','list suppliers','our orders','the crm','business data','inquiries','quotes','transactions','entity lookup']);
  v_n := v_n + 1;

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now());
end $function$
;

-- 3. THE STANDING DECISIONS, RESTATED FROM THE RULINGS THAT SUPERSEDED THEM (decided_on stays the original date).
update public.company_policy_decision set decision_text =
  'OpenRouter credit is recharged by the founder; he sends the receipts to the expenses mailbox, which is the source of truth for '
  || 'expenses, so the books stay current from those receipts. Paid inference (OpenRouter) is ON and stays on: founder ruling 1175 '
  || '(7 Oct 2026), "from now on keep open router always on"; a route''s circuit breaker still opens on a real error (llm_route_health). '
  || 'No agent asks him to recharge. (Restated 16 Nov 2026: the hold of 6 Sep was lifted by ruling 1175.)'
 where decision_key = 'openrouter_credit';

update public.company_policy_decision set decision_text =
  'Standing rules: (1) nothing waits for the founder: the CEO seat decides every approval, refunds of any amount included '
  || '(8 Sep 2026, "all approvals are from CEO"; rulings 1696 and 1710), and he is told the result; (2) he is emailed exceptions only '
  || '(founder_mail_policy) — everything else becomes the owning seat''s task; (3) he is never asked technical questions — engineering '
  || 'decides, does, and records the reasoning; he sets boundaries, not methods; (4) a session reports one completion line only when '
  || 'everything is verified and deployed, otherwise an honest hand-over; (5) WhatsApp is his command channel; (6) money moves only '
  || 'within the company limits the CEO seat sets (public.company_limit_change, ruling 1696; a raise takes effect a day later), and only '
  || 'a fact or a credential that he alone holds is asked of him; his emergency stops stay his; (7) paid inference '
  || 'is on (ruling 1175) and he recharges the credit himself; (8) the OS stays signed in for him and the company solves its own '
  || 'problems. (Restated 16 Nov 2026: items 1, 6 and 7 from the rulings that superseded them.)'
 where decision_key = 'founder_standing_rules';

update public.company_policy_decision set decision_text =
  'Refund policy: five working days from the time the customer pays. After three working days with no response from the supplier, '
  || 'the sales engineer chases it through customer support, customer copied. On the fifth day the sales engineer makes the final '
  || 'call and the CEO seat decides ("refunds belong to the CEO from now on", 8 Sep 2026; rulings 1696 and 1710); the founder is '
  || 'told the result. If there is still no response, the refund is issued; banks usually take 7-14 working days to show it. The 3% '
  || 'the customer paid is refunded in full; the supplier owes what the Supplier Agreement version it accepted says (clause 33: from '
  || 'v14 the processor fee, AED 500 and 12% a year; v13 AED 500 and 9%; v10 to v12 AED 250 and 9%). Never ask again. (Restated 16 Nov '
  || '2026: the 6 Sep text had the founder make the final call.)'
 where decision_key = 'refund_ladder';

update public.company_policy_decision set decision_text =
  'The supplier invite campaign runs from the leads the company holds; the sales engineer seat tracks the inbound emails and contacts '
  || 'the leads to register; the target is at least 300 supplier registrations a month. New leads are sourced once a month by Claude '
  || 'on the subscription and ingested (ruling 1205), not by an automated job. Outreach runs while '
  || 'app_secrets.supplier_outreach_golive is true. The CEO seat has the sanctions lists checked weekly and decides when a registered '
  || 'supplier appears on one. These are existing seats'' tasks, not new agents. (Restated 16 Nov 2026.)'
 where decision_key = 'supplier_acquisition_and_screening';

update public.company_policy_decision set decision_text =
  'A trade opens to customers trade by trade once it has enough verified registered suppliers (ruling 1614): the level is '
  || 'trade_opening_rule.open_at_suppliers, tuned by the CEO seat, starting at 10. Matching an RFQ to suppliers is a separate rule '
  || 'and still needs at least one confirmed supplier. (Restated 16 Nov 2026: the 6 Sep text fixed it at 10.)'
 where decision_key = 'category_open_threshold';

update public.company_policy_decision set decision_text = replace(decision_text, 'the CFO opens a registration task', 'the accountant opens a registration task')
 where decision_key = 'corporate_tax' and decision_text like '%the CFO opens a registration task%';

-- every applies_to names seats (there are no departments): the old role keys map to the seat that holds the work today
update public.company_policy_decision d set applies_to = coalesce((
    select array_agg(distinct m order by m) from (
      select case
        when a in ('ceo','sales_engineer','customer_support','accountant','it_engineer','marketing','*','every_employee') then a
        when a in ('cfo','bookkeeper','financial_analyst','billing_specialist','payments_manager') then 'accountant'
        when a in ('legal','compliance_mgr','compliance_and_privacy_officer') then 'ceo'
        when a in ('bd','business_development','procurement','supplier_coverage','suppliers','onboarding','partnerships_mgr') then 'sales_engineer'
        when a in ('sales_director','marketing_analyst','design','reports') then 'marketing'
        when a in ('followup','cs_retention','customer_experience','refunds','messaging') then 'customer_support'
        when a in ('cto','it_operations_engineer') then 'it_engineer'
        else 'ceo' end as m
      from unnest(d.applies_to) a) x), '{}'::text[])
 where cardinality(d.applies_to) > 0;

-- 4. THE PUBLIC REFUND FAQ (EN 167, AR 616): no Customer Success Director, no "a person decides"
update public.company_faq set
  answer = replace(replace(answer,
    'every refund is decided by a person here — none is automatic', 'every refund is decided case by case — none is automatic'),
    'our Customer Success Director chases them with the customer copied', 'we chase them with the customer copied'),
  updated_at = now()
 where id = 167 and (answer like '%Customer Success Director%' or answer like '%decided by a person here%');
update public.company_faq set
  answer = replace(replace(answer,
    'ويقرر كل استرداد شخص لدينا ولا شيء منها آلي', 'ويُتخذ قرار كل استرداد حالةً بحالة ولا شيء منها آلي'),
    'يتابعه مدير نجاح العملاء لدينا مع نسخة إلى العميل', 'نتابعه مع نسخة إلى العميل'),
  updated_at = now()
 where id = 616 and (answer like '%مدير نجاح العملاء%' or answer like '%شخص لدينا%');

-- 5. the eleven department records no routine writes any more; then every qd-company record is rewritten once
update public.ops_knowledge set supersession_state = 'superseded', runtime_eligible = false
 where record_id like 'qd-company:org-%' and (supersession_state is distinct from 'superseded' or runtime_eligible);

select public.fn_company_self_knowledge_sync();
