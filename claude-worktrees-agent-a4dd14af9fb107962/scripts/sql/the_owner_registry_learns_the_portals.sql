-- THE EIGHT PORTAL FUNCTIONS GET THEIR OWNER ROWS, and the registry learns why it missed them.
--
-- public.function_owner was written on 8 September to record which seat owns each deployed edge
-- function, with a check that fails on any unowned deployment. It reported 68 deployed, 68 owned,
-- 0 unowned — and it was wrong, in the one way a registry of this shape can be:
--
--     it was BUILT by reading the live deployment list.
--
-- The eight portal functions had already been deleted when it was built, so they were not in the
-- list, so they got no row, so nothing was unowned. A registry derived from the thing it is meant to
-- check cannot notice that something is missing from that thing. It can only notice what is present
-- and unclaimed. That is the defect, and it is worth stating plainly because the same shape appears
-- everywhere in this estate: a mirror emitted from production can never disagree with production.
--
-- What would have caught it is the direction this file adds: an expectation written from the CODE
-- THAT CALLS a function — CustomerPortal.tsx posts to customer_api, therefore customer_api must
-- exist — rather than from the list of functions that happen to be deployed.
--
--   node scripts/apply_sql.mjs scripts/sql/the_owner_registry_learns_the_portals.sql --apply --ddl

begin;

insert into public.function_owner (function_slug, owner, note) values
  ('customer_api',            'website', 'The customer portal''s backend. 19 call sites in src/components/me/CustomerPortal.tsx: create_inquiry, my_inquiries, reveal, request_refund, rate_supplier, complete_inquiry, quote_pdf, compare_pdf, analyze_drawing, cancel_inquiry, edit_inquiry, me, set_locale.'),
  ('supplier_api',            'website', 'The supplier portal''s backend. 19 call sites in src/components/portal/SupplierPortal.tsx.'),
  ('supplier_portal',         'website', 'The supplier portal''s data surface. 23 call sites across src/components/portal/supplier/*.'),
  ('messages_api',            'website', 'Messaging between customer and supplier. 18 call sites across both portals and src/components/comms/api.ts.'),
  ('inquiry_intake',          'website', 'The RFQ brief the customer fills in. CustomerPortal.tsx:1123 and :1365.'),
  ('quote_compare',           'website', 'The quote comparison screen. CustomerPortal.tsx:1203.'),
  ('supplier_onboard',        'website', 'Supplier registration. SupplierOnboarding.tsx:113.'),
  ('supplier_catalog_ingest', 'website', 'Supplier catalogue upload. SupplierCatalogUpload.tsx:92.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note;

commit;
