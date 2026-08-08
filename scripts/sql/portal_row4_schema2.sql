-- ROW #4, §7 rfq-certificates — WHERE THE REQUIRED CERTIFICATES LIVE ONCE THEY ARE ATTACHED.
--
-- MEASURED (production, 7 Aug 2026): "the RFQ-creation path names the checklist or the answer
-- store: false; categories carrying a compliance checklist: 21 of 56; routines reading
-- compliance_checklist ... : none; inquiry_answer_document rows: 0."
--
-- WHY NOT inquiry_answer_document, WHICH ALREADY EXISTS. That table is
-- (answer_id, document_id, page_or_sheet, extraction_confidence, original_text, assigned_scope) —
-- the OCR PROVENANCE store, recording which page of which uploaded file an answer was extracted
-- from. A certificate the category REQUIRES is not an extraction from a document the customer
-- supplied; it is a requirement that exists before any document does. Writing requirements into a
-- provenance table would make every future reader of that table wrong about what its rows mean.
--
-- WHY NOT inquiries.spec. spec is what the CUSTOMER stated, and the RFQ card renders it as flat
-- key/value pairs. A system-derived nested list dropped in there renders as noise and, worse,
-- becomes indistinguishable from something the customer typed.
alter table public.inquiries add column if not exists compliance_checklist jsonb;
comment on column public.inquiries.compliance_checklist is
  'Spec §7: the certificate/approval checklist category_specs holds for this RFQ''s category, '
  'copied onto the RFQ at creation. A COPY on purpose — the category''s checklist can change '
  'afterwards, and an RFQ already quoted against must keep the requirements it was quoted against.';
