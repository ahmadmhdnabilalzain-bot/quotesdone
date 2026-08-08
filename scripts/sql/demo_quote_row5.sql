-- ROW #5 — THE FENCED DEMO QUOTE AND ITS REVEAL, ON BOTH PROJECTS.
--
-- Founder, 2026-08-08: "create a demo quote with a reveal and lets say a duration of 1 hour so that
-- you can test it and then build it fully."
--
-- lead_time is '1 hour', which makes the rating clock testable in a session instead of a quarter.
--
-- ── revealed_at IS now(), NOT A BACK-DATED TIMESTAMP ────────────────────────────────────────────
-- The obvious way to see a "due" row today is to set revealed_at two hours ago. That is exactly the
-- back-dating the standing rule forbids, and it would leave a permanent lie in the transactions
-- table to make one check go green. fn_rating_due takes the evaluation moment as a PARAMETER, so
-- the schedule is proven by asking "what would be due two hours from now" against untouched rows.
-- A question is not a forgery.
--
-- ── THE FENCE ───────────────────────────────────────────────────────────────────────────────────
-- Both rows hang off the demo inquiry (brief_source = 'qd_demo_fixture'), whose customer_id is
-- NULL, and off the demo supplier, which is unverified and unmatchable. The three notification
-- triggers on these tables (trg_new_quote_sms, trg_reveal_receipt, trg_notify_refund) all address
-- a customer; with no customer there is nobody to address. That is asserted after the fact by
-- scripts/staging/audit_demo_fence.mjs rather than assumed here.
--
-- ── REMOVABLE ───────────────────────────────────────────────────────────────────────────────────
--     delete from public.transactions where quote_id in (select id from public.quotes where source='qd_demo_fixture');
--     delete from public.quotes where source = 'qd_demo_fixture';

insert into public.quotes (inquiry_id, supplier_id, quote_amount, source, status, lead_time, notes, warranty)
select i.id, s.id, 185000, 'qd_demo_fixture', 'submitted',
       '1 hour',                                   -- the duration the rating clock reads
       'ZZ DEMO — curtain walling package, supply and install. QuotesDone fixture, not a real quote.',
       '12 months on workmanship'
from public.inquiries i
join public.leads s on s.place_id = 'qd-demo-supplier-001'
where i.brief_source = 'qd_demo_fixture'
  and not exists (select 1 from public.quotes where source = 'qd_demo_fixture');

-- The reveal. revealed_at = now() on purpose: see the note above.
insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at)
select q.id, q.inquiry_id, q.supplier_id, null, q.quote_amount, now()
from public.quotes q
where q.source = 'qd_demo_fixture'
  and not exists (select 1 from public.transactions t where t.quote_id = q.id);
