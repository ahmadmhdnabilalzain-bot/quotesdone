-- Assigned: sales_engineer
--
-- AN APPROVED SUPPLIER WHO SWAPS IN AN UNREADABLE LICENCE IS HELD AGAIN (7 Oct 2026).
--
-- #1268 made fn_sales_engineer_verifies_supplier hold an approved supplier whose licence name was not
-- read ('pending', reason licence_unreadable). Measured on production the same day, in a rolled-back
-- probe on ZZ DEMO supplier 126512: name read -> approved; then the exact write supplier_api
-- process_docs makes for a new licence code cannot name (license_doc_path set, licence_legal_name
-- null) -> STILL approved, reason null, verified true; calling the verification by hand afterwards ->
-- pending/licence_unreadable. The routine was right; nothing called it. z20 re-runs the verification
-- only WHEN the supplier is waiting (action_required / pending), so for an approved supplier a new
-- licence document never reached the review at all. #1268's own probe called the routine directly,
-- so it measured the case the fix handled, not the path a real upload takes.
--
-- The fix is in the one place every writer routes through: z20 also fires for an APPROVED supplier
-- when the licence document or the licence name changes. That covers supplier_api process_docs,
-- supplier_portal save_documents, resend_inbound and wa_inbound alike. Nothing else changes for an
-- approved supplier: a phone, profile or terms change still does not re-review him (the six gate,
-- trg_leads_e0_mandatory_six_gate, already demotes a supplier who loses a mandatory item), and an
-- approved supplier whose licence merely expired stays approved, as before.
--
-- No routine is created or replaced here, so no grant changes. pg_trigger_depth() < 1 stays: the
-- verification's own update never re-enters.
--
-- Prevented by: an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again_probe.sql (writes
-- the column change only, never calls the routine) and the trigger assertion in
-- scripts/checks/an_unread_licence_name_is_never_approved_automatically.test.mjs.

drop trigger if exists z20_leads_mandatory_item_landed_reverifies on public.leads;
create trigger z20_leads_mandatory_item_landed_reverifies
  after update of company_name, phone, phone_e164, owner_phone_verified, owner_email_verified, license_doc_path,
                  license_expiry, company_profile_doc_path, signed_terms_path, licence_legal_name
  on public.leads for each row
  when (pg_trigger_depth() < 1
        and (new.approval_status = any (array['action_required', 'pending'])
             or (new.approval_status = 'approved'
                 and (old.license_doc_path is distinct from new.license_doc_path
                      or old.licence_legal_name is distinct from new.licence_legal_name))))
  execute function public.fn_leads_mandatory_item_landed_reverifies();
