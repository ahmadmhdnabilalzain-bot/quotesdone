-- The two open receipt gaps were never a vendor-portal problem. Both documents existed in the
-- founder's mailbox the whole time; only one had ever been forwarded to expenses@, and its
-- attachment did not survive into the archive.
--
-- Apify USD 29.00, charged 2026-06-04
--   invoice #202606032609, billing@apify.com, 2026-06-03T22:10:19Z, PDF attached to that message.
--   Gmail message id 19e8f8998fce1e60. It WAS forwarded to expenses@mail.quotesdone.com on
--   2026-06-29 (message 19f14963d1cdc6cf) and still produced no doc_path, which is the more
--   interesting failure: the forward path did not carry the attachment through.
--
-- OpenRouter USD 10.80, charged 2026-06-08
--   receipt #1512-7448, receipts@openrouter.ai, 2026-06-08T17:14:54Z, Visa -5057, "OpenRouter
--   Credits". Gmail message id 19ea83c25bb55707. NEVER forwarded to expenses@ — that is the whole
--   reason it is missing. Stripe hosts an immutable receipt for it.
--
-- PROVENANCE, stated plainly: doc_path here is a vendor-hosted reference or a mailbox locator, NOT
-- an archived binary in our own storage. That is weaker than a stored PDF and stronger than the
-- nothing that was there before. If the audit standard requires our own copy, re-forward both
-- messages to the inbound address once the attachment-forwarding defect is fixed.

update public.expense_entries set
  doc_name = 'OpenRouter receipt #1512-7448 (USD 10.80, 2026-06-08)',
  doc_path = 'https://dashboard.stripe.com/receipts/payment/CAcQARoXChVhY2N0XzFNeHV1MkRoaFBqOGk0UEEo3fGb0QYyBpbojKHF1TovFpxZES83ImCFVYM7avS06_rVRD0kuN__6DAG7CU1cGnb29V5QOmNA4BcFQNr47g'
where vendor = 'OpenRouter' and charged_on = date '2026-06-08' and doc_path is null;

update public.expense_entries set
  doc_name = 'Apify invoice #202606032609 (USD 29.00, 2026-06-04)',
  doc_path = 'gmail:19e8f8998fce1e60#attachment (billing@apify.com, 2026-06-03T22:10:19Z)'
where vendor = 'Apify' and charged_on = date '2026-06-04' and doc_path is null;;
