-- COMPANY CANON — the authoritative company knowledge so any agent can answer any company question.
-- Two layers: (1) 8 always-on _global canon core facts (below), read by every agent via agent_brain/fn_agent_context;
-- (2) the full canon (36 grounded Q&A) loaded as DATA into dept_library department='company', retrievable via
-- fn_dept_library_search('company', <question>). Grounded in the live product + pricing_config as of 2026-07-24.
insert into public.agent_knowledge(agent_key,topic,priority,content)
select '_global', v.topic, v.priority, v.content from (values
('canon:what_is_quotesdone',91,'QuotesDone is a UAE B2B anonymous quotation marketplace: a buyer posts an RFQ; verified UAE suppliers submit quotes that reach the buyer ANONYMISED; the buyer pays a reveal fee to unlock and contact a chosen supplier. Anonymity stops suppliers spamming buyers and incumbents retaliating. Vision: become the smartest marketplace engine in the world.'),
('canon:fees',91,'Fees (live): buyer REVEAL FEE = 3% of quote value, currently effectively uncapped. NO commission on won work. Supplier registration FREE for first 1,000 suppliers, then AED 1,000/year (dormant - all free-tier). Money via Stripe both ways; QuotesDone never holds supplier bank details.'),
('canon:refunds',90,'Refunds (unresponsive supplier): 3-working-day window - after 1 wd Notify supplier, after 3 wd Request refund -> founder approval; payout 7-14 wd after approval; 3% processing deduction. From an unreachable supplier: recover reveal fee + 9%/annum late fee (Fed. Decree-Law 50/2022) + AED 250 admin fee/claim.'),
('canon:supplier_verification',89,'Supplier onboarding: required = contact name, SMS-verified mobile, trade licence number (ONLY required doc, OCR-verified), company profile doc, accept terms. Approval targeted within 3 working days (manual today). Optional docs only widen reach. Expired licence/insurance auto-pauses matching, auto-restores free on renewal.'),
('canon:how_it_works_flow',89,'Buyer: OTP sign-in -> profile -> post RFQ -> anonymised quotes (cards show licence-verified badge, years, emirate, response stats, 6-dim ratings) -> pay reveal fee -> contact & hire. Supplier: register+verify -> matched RFQs -> submit quote (OCR upload or line items, quality-scored 70 pass) -> anonymised delivery -> paid on reveal.'),
('canon:matching_quality',86,'Matching routes RFQs to capable suppliers via keyword shortlist + capability engine (flagged), excluding matching-blocked/banned/closed. Quote quality scored (70 pass) with coaching.'),
('canon:status_tech',85,'Status: pre-launch, 0 real transactions. ~20,465 scraped/indexed UAE supplier records = directory asset. Launch focus 3 Dubai trades. Built on Supabase (Postgres + Deno edge) + Next.js OS; DB region ap-southeast-1.'),
('canon:reference_pointer',84,'Full Company Canon (deep Q&A) is in dept_library department=company, retrievable via fn_dept_library_search(''company'', <question>). Answer specific company questions from the canon rather than guessing.')
) as v(topic,priority,content)
where not exists (select 1 from public.agent_knowledge k where k.agent_key='_global' and k.topic=v.topic);
