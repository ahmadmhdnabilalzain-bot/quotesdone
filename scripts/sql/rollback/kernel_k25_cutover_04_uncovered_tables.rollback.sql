-- Rollback for K25, cutover increment 4 (the tables no trigger was watching).
--
-- After this, a customer can use the contact form, request their data under PDPL, or attach a
-- document to their inquiry, and no workflow will open for any of it — the pre-2026-08-17 state.
--
-- The three source-status corrections in phase_c_source_cutover are NOT reverted. They are
-- measurements of what each Edge Function writes: the eight marked
-- COVERED_BY_A_CUT_OVER_TABLE_TRIGGER write inquiries, quotes, quote_items or transactions and
-- reach the kernel through the increment 1-3 triggers whether or not this file is applied, and the
-- seven marked NOT_YET_CUT_OVER are still owed either way. Reverting them would replace a measured
-- fact with an older, wrong one.

begin;

drop trigger if exists z95_contact_message_to_kernel on public.contact_messages;
drop trigger if exists z95_pdpl_request_to_kernel on public.pdpl_requests;
drop trigger if exists z95_document_to_kernel on public.documents;

drop function if exists public.trg_contact_message_to_kernel();
drop function if exists public.trg_pdpl_request_to_kernel();
drop function if exists public.trg_document_to_kernel();

commit;
