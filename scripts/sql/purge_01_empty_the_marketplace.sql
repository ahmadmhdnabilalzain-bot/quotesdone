-- EMPTY THE MARKETPLACE — founder instruction, 15 Aug 2026: "remove all the demo data we have.
-- not a single inquiry/customer/supplier should exist" … "just leads remains".
--
-- WHAT SURVIVES, by his decision:
--   * leads                  — the 20,470 real scraped rows. Apify is paused until ~Feb 2027, so
--                              these cannot be rebuilt by scraping and are the asset the company
--                              is meant to run off.
--   * supplier_score         — 20,471 rows of computed enrichment ON those leads.
--   * supplier_capabilities  — 15,306 rows of the same. He chose to keep both: they are attributes
--                              of a lead, not a supplier account.
--
-- WHAT GOES: every entity that makes the marketplace look occupied — inquiries, customers, quotes,
-- matches, transactions — plus every supplier ACCOUNT artefact sitting on top of a lead (claims,
-- registrations, portal state, catalogues), plus the ZZ DEMO fixture rows.
--
-- THE ONE REAL RECORD IN HERE. customers holds two rows on production:
--   ahmadmhdnabilalzain+qdcust1@gmail.com   his own probe address
--   djzaino@outlook.com  +971509319355      a member of the public who registered himself on
--                                           13 Aug 2026 and has posted nothing since
-- He was asked about the second one specifically and chose: delete permanently, no backup. It is
-- recorded here because a deletion of a real person's account should be legible afterwards, not
-- because the decision is in doubt.
--
-- A supplier ACCOUNT is cleared by UPDATE, never by deleting the lead: the claim, the registration
-- and the portal state come off, and the company row stays on the list. Deleting the lead would
-- throw away a real UAE company because someone once clicked claim on it.
--
-- Counts are raised at the end so the transaction reports what it did.

begin;

-- ── 1. everything hanging off an inquiry ─────────────────────────────────────────────────────
delete from comparison_candidate_v2;
delete from comparison_run_v2;
delete from quote_committed_items;
delete from quote_comparisons;
delete from quote_items;
delete from quote_pdf_cache;
delete from quote_requirements;
delete from quote_review_messages;
delete from quote_reviews;
-- The FK graph, walked four levels deep rather than guessed at. A first pass without these seven
-- was refused by procurement_approval_policy_organization_id_fkey and rolled itself back, which is
-- the constraint doing its job: it would have left an approval policy pointing at an organisation
-- that no longer existed.
delete from refunds;
delete from reveal_invoices;
delete from ap_bills;
delete from transactions;
delete from po_lines;
delete from po_orders;
delete from chat_threads;
delete from quotes;
delete from inquiry_matches;
delete from inquiry_supplier_brief;
delete from inquiry_requirement;
delete from inquiry_answer_conflict_value;
delete from inquiry_answer_conflict;
delete from inquiry_answer_corroboration;
delete from inquiry_answer_document;
delete from inquiry_answer_scope;
delete from inquiry_answer;
delete from inquiry_scope_disposition;
delete from inquiry_trade_candidate_evidence;
delete from inquiry_trade_candidate;
delete from inquiry_trade_clarification;
delete from inquiry_workstream_requirement;
delete from inquiry_workstream_group;
delete from inquiry_workstream;
delete from inquiry_gate_required;
delete from inquiry_gate;
delete from inquiry_state_audit;
delete from inquiry_cancellations;
delete from inquiry_intake;
delete from supplier_opportunity_score;
delete from project_component;
delete from shipment_leg;
delete from questions;
delete from reviews;
delete from messages;
delete from customer_calls;
delete from inquiries;

-- ── 2. customers and everything that belongs to one ──────────────────────────────────────────
delete from drawing_redaction_runs;
delete from procurement_approval_request;
delete from procurement_approval_policy;
delete from customer_organization_member;
delete from customer_organization;
delete from customer_phone_otps;
delete from customer_preference;
delete from customer_layout;
delete from customer_score;
delete from customer_kpi_snapshots;
delete from projects;
delete from customers;

-- ── 3. supplier ACCOUNTS come off the leads; the leads themselves stay ───────────────────────
delete from supplier_capability_confirmation;
delete from supplier_product_variant;
delete from supplier_product;
delete from supplier_catalog;
delete from supplier_negotiation_policy;
delete from supplier_dues;
delete from supplier_kpi_snapshots;
-- Supplier document reviews and inbound supplier mail are account artefacts, and doc_reviews is
-- the last FK that refuses a demo-lead delete. supplier_capabilities and lead_category are
-- ON DELETE CASCADE, so a demo lead takes its own enrichment with it; the 15,306 capability rows
-- on REAL leads are untouched, which is what he chose.
delete from doc_reviews;
delete from inbound_messages;

-- ── 3a. the demo fixtures themselves, BEFORE the account clear ───────────────────────────────
-- The convention is in the DATA, not the schema: 'ZZ DEMO — …' in the name and @example.invalid in
-- the email. These are the only lead rows deleted, because they are not real companies. Deleting
-- them first means the account clear below never touches a row that is about to disappear.
-- TWO demo conventions exist, not one. The first pass only knew 'ZZ DEMO — …' / @example.invalid
-- and left a whole family standing: 'QD Demo …' with @example.com, source='demo_factory' and a
-- qd_demo tag. Measured before widening, so this cannot take a real company with it:
--   production 20,471 leads -> 6 match (all ZZ DEMO, 0 demo_factory)  -> 20,465 real leads survive
--   staging       58 leads -> 56 match (6 ZZ DEMO + 50 demo_factory) ->      2 survive
delete from leads
 where company_name ilike 'ZZ DEMO%'
    or company_name ilike 'QD Demo%'
    or email ilike '%@example.invalid'
    or email ilike '%@example.com'
    or source = 'demo_factory'
    or tags && array['qd_demo'];

-- ── 3b. supplier ACCOUNTS come off the surviving leads ───────────────────────────────────────
update leads set
  claimed                   = false,
  claimed_by                = null,
  -- claim_token is NOT NULL, default gen_random_uuid(). Rotated rather than cleared: it also
  -- invalidates any claim link already sent, which nulling could not do.
  claim_token               = gen_random_uuid(),
  registration_status       = null,
  registration_submitted_at = null,
  registration_paid_at      = null,
  registration_expires_at   = null,
  registration_fee_due      = null,
  subscription_paid_until   = null,
  subscription_exempt       = false,
  owner_email_verified      = false,
  owner_phone_verified      = false,
  -- verified and email_verified are deliberately NOT cleared. They describe the LEAD — whether the
  -- company's own details stood up — not the account someone opened on it, and the CHECK
  -- constraint leads_approved_implies_verified proves the schema treats them that way: clearing
  -- verified on an approved row is refused. owner_email_verified / owner_phone_verified ARE
  -- account fields and are cleared.
  portal_updated_at         = null
where claimed
   or claimed_by is not null
   or claim_token is not null
   or registration_status is not null
   or registration_submitted_at is not null
   or subscription_paid_until is not null
   or portal_updated_at is not null;

do $$
declare v text;
begin
  select format(
    'inquiries=%s customers=%s quotes=%s matches=%s transactions=%s | leads=%s claimed=%s registered=%s | supplier_score=%s supplier_capabilities=%s',
    (select count(*) from inquiries), (select count(*) from customers), (select count(*) from quotes),
    (select count(*) from inquiry_matches), (select count(*) from transactions),
    (select count(*) from leads), (select count(*) from leads where claimed_by is not null),
    (select count(*) from leads where registration_status is not null),
    (select count(*) from supplier_score), (select count(*) from supplier_capabilities))
  into v;
  raise notice 'AFTER PURGE: %', v;
end $$;

commit;
