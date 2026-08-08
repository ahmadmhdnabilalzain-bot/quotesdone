-- Applied version: 20260803175609
-- A booked expense with no archived receipt is a tax-evidence gap, and nothing surfaced it.
--
-- On 3 Aug 2026 00:55 UTC resend_inbound received the Apify invoice, fetched the PDF attachment
-- (expense_entries.doc_name is the real filename, so the bytes were in hand), and then failed to
-- upload it: trg_containment_block_sensitive_upload() refused writes to receipt-files with SQLSTATE
-- QDM01 while containment maintenance was on. The handler catches that failure and books the
-- expense anyway - deliberately, so the charge is not lost. The consequence is asymmetric: the
-- financial row was written while its evidence was refused, because expense_entries was never in
-- the containment blocklist and receipt-files was.
--
-- The only trace was one agent_runs error row and a null doc_path. v_dead_letter_open does not
-- cover it, fn_resilience_watch does not cover it, and expense_entries has no constraint requiring
-- a document. Three of twenty-five booked expenses currently have none.
--
-- This view is the instrument, not a fix. It names the rows and separates the two causes, because
-- they need different remedies: re-forward the receipt email (recoverable) versus reconstruct the
-- evidence from the vendor's billing portal (pre-archive rows).
create or replace view public.v_expense_receipt_gap as
select e.id,
       e.vendor,
       e.amount,
       e.currency,
       e.charged_on,
       e.source,
       e.doc_name,
       e.created_at,
       (current_date - e.charged_on)                       as age_days,
       (e.doc_name is not null and e.doc_name <> '')        as document_was_received,
       case
         when e.doc_name is not null and e.doc_name <> ''
           then 'the receipt was received and read but the archive write was refused - re-forward the vendor email to the inbound address to retry'
         else 'no receipt document was ever attached to this entry - retrieve the invoice from the vendor billing portal and attach it manually'
       end                                                  as remedy
  from public.expense_entries e
 where e.doc_path is null
 order by e.charged_on desc;

comment on view public.v_expense_receipt_gap is
  'Booked expenses with no archived receipt document. Must stay empty. Every row is a booked cost with no evidence behind it; document_was_received distinguishes an archive failure that can be retried by re-forwarding the email from an entry that never had a document at all.';

revoke all on public.v_expense_receipt_gap from anon, authenticated;
grant select on public.v_expense_receipt_gap to service_role;
