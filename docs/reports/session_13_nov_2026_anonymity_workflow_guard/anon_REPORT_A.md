AUDITOR A: CUSTOMER TO SUPPLIER (worktree origin/main fc16e9c3a; read and run offline only; worktree removed)
Folder: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/A_customer_to_supplier/ (scripts s1_pipeline.ts, s1_model_stub.ts, s2_mask*.ts, s3_pdf.ts, reports *.json, sql/)

1. LEAKS AND GAPS (most harmful first)
L1 [R1 location; PROVED on production rows + offline]. The customer's area reaches every matched supplier. All 3 inquiries in production (all ZZ DEMO) serve summaries that name the area through inquiries_supplier_safe: "…in Al Nahda, Sharjah", "…in Khalifa City, Abu Dhabi", "…in Business Bay, Dubai". Suppliers see this in the portal card, the inquiry PDF hero and Scope, and the new_inquiry e-mail. No code removes areas. Run offline through inboxField, scrubIdentity and stripContact, all of these passed: "Al Barsha 2", "Al Barsha South", "near Mall of the Emirates", "Marina Gate 2 tower, Dubai Marina", Arabic "البرشاء 2 … فيلا رقم 15", the coordinates "25.1123, 55.2001" and a what3words address. "Villa 15 Al Barsha 2" (no comma, no emirate) became "█ Al Barsha 2" in the portal and stayed whole in the e-mail. The only full removal is the ADDRESS pattern (Villa N, …, Dubai), and it removes "Dubai" too.
- The intake prompt does not tell the model to keep the area out. It asks for `location: "<area + emirate>"` (inquiry_intake/handle.ts:393+, rule lines 66–71).
- 35 trades have a `location` checklist key (production category_specs), so the answer is stored in spec. Spec is sent in the inbox JSON (not drawn on screen or the PDF).
- PDF: pdfs/A3. The emirate-only "Site" field is correct.
- Smallest fix: (a) an intake prompt rule: summary and details carry the emirate only, never area, community, building or unit; (b) store the area server-side in a customer-only column; (c) add a community gazetteer (EN and AR) to _shared/identity_text.ts that turns the area into the emirate, plus a corpus row.
- FOR THE FOUNDER: today a supplier only ever sees the emirate. If he wants a rough location for site-visit or delivery pricing, he must choose a band (e.g. "Dubai, inland" or a distance band); nothing like that exists.

L2 [R1 + R3 + prices; deterministic parts PROVED, model part by reading]. The portal never treats an attached quotation as a quotation.
- NewRequest.tsx sends a PDF from either button to analyze_drawing with source 'drawing' or 'boq'. brief_source 'quotation' is never sent, so the quotation-aware code (drawing_boq/quotation_parties.ts, QUOTATION_NOTE) runs only for Word/Excel (analyze_document or analyze_boq), not for PDFs.
- For a PDF, the drawing QS model reads it. The only code backstop is setIdentityTerms (title-strip terms), then redactBoq with the customer's seeds and the file name.
- With a careless model reading stubbed in (s1_model_stub.ts), these reached the supplier's BOQ: "Falcon Trading" (no LLC), "Ahmed Saeed", "FT/Q/2026/0412", "FT-SD-04", and the prices "AED 95.00/m2, amount 8,170.00", "rate 1,180" and "AED 32,816.70". The portal BoqTable shows `basis` and `assumptions` (RfqParts.tsx:189, 202). "Falcon" was removed only when the file name happened to contain it.
- The page images of the quotation go through drawing_redact, which uses a drawing prompt that never mentions prices. If the vision verifier passes, the competitor's own page, with its prices and layout, is signed to suppliers (DrawingGallery, plus `Job_x_drawing_p01.jpg` in the inquiry PDF's document list). Proved: titleBlockBoxes returns low confidence, so the model decides. The vector-PDF file path HOLDS for all 3 quotation PDFs I made (pdf_title_block_not_confident).
- Fix: detect a priced document (isQuotation on the text layer) in analyze_drawing → no page previews, no file; route it to mode 'document' (quotation_parties + no price columns); add a price-shape and letterhead-term gate on basis, assumptions and summary.

L3 [R1; PROVED offline]. The new_inquiry e-mail (customer_api/lib/matching.ts:258-264) runs scrubIdentity with the buyer's name only: no seed list, no residual scan, no withhold. The portal uses inboxField. Leaked in the e-mail but caught in the portal: project name ("ZZ DEMO Barsha Garden Villa", "re:BarshaGardenVilla"), "Haddad Family Office", "Plot No. 373-4512", "Makani 12345 67890", "Apartment 1204". Fix: use inboxField with seedTerms in matchAndNotify (and the same in edit_inquiry, inquiry_lifecycle.ts:438).

L4 [R1; PROVED offline, every door]. All scrubbers miss:
- a phone written in words or split ("055 000 then 0499");
- the customer's name written in Arabic when it is stored in Latin;
- "omar.haddad @ zz-mail…" in the e-mail and answer paths (only half-masked);
- a competitor's name with no legal form ("Falcon Trading"), with his price.

The pre-reveal answer channel (messages_api clarify_answer → e-mailed to every matched supplier) also misses plot and Makani. S4 has text only, no files; chat opens only after a reveal (messages_api:350).

L5 [reader gap; PROVED]. A normal reportlab PDF (ASCII85+Flate streams) reads as "no text layer" (0 runs). Every deterministic layer goes blind (title boxes, setIdentityTerms, quotation parties) and the model alone decides.

L6 [minor; read]. The supplier inbox treats any transactions row as revealed (inbox.ts:217, no revealed_at filter; other doors filter). Today every insert sets revealed_at, so it is harmless.
- The inquiry PDF offers a BOQ as .csv, against ruling 1672.
- The supplier PDF drops the brand/spec column (RAK, Duravit, Hansgrohe…), so a supplier cannot price the specified make.
- Suppliers are told "A drawing with a draft bill of quantities is attached" for a quotation.

2. WHAT HOLDS (evidence)
- File name, PDF properties and the original path never reach a supplier: inbox nulls drawing_file_name and URL; names are Job_x_…; the view has no file name; grants for anon/authenticated on inquiries, the view and rfq_clarification are false (production has_table_privilege).
- The inbox, inquiry_pdf and review chat are scoped to the caller's own matches.
- WhatsApp new_inquiry carries the subject and portal link only.
- The quotation template path (Word/Excel, code reading) removed every party and every price on my quotation except "FT-SD-04" (pdfs/A1 output).
- The WhatsApp door (wa_inbound/customer_files.ts) holds PDFs; e-mail and the widget post no inquiry.
- S6: projects or contact only on revealed_at; a non-revealed supplier's revealed flag is per supplier_id; notifyLosers is scrubbed.
- Tests I ran: 12 deno sets passed, 59/59: identity_text, anonymise, anonymise_formats, inquiry_document_no_contact, competitor_quote, drawing_chain, quote_generalise_the_corpus_holds (brand set), the money corpus test, pre_reveal_quote_text, identity_contacts, pre_reveal_identities, mailbox. Checks: a_supplier_sees_only_its_own_match 30/30, nothing_a_supplier_sets_shares… 4/4, a_scanned_drawing… 4/4, drawing_confirm… 2/2, withdraws… 2/2, site_copy… 1/1. Skipped as they read production: an_unrevealed_quotes_file…, only_a_redacted_drawing_page…, reveal_work….
- Coverage gap: no set plants areas or communities, a customer's competitor quotation, words-phones, or prices in basis/assumptions. identity_never_leaks_before_reveal.mjs was not run (1 h with OCR, disk tight); it does not plant these either.

3. DOCUMENTS A SUPPLIER RECEIVES
- Inquiry PDF (supplier_api inquiry_pdf, portal download): our template (pdf_native).
- BOQ .csv download: not a template.
- Drawing or quotation page JPEGs and the anonymised vector PDF: pass-through of the customer's file with marks painted over. For a quotation, prices survive (L2).
- E-mails new_inquiry and clarification answer: plain text. WhatsApp: template.

4. PHASE 2 (live, ZZ DEMO, clean browser context for every capture: harness intercepts /functions/v1)
- P1 (S1): upload pdfs/"A1 input…" (also A_customer_to_supplier/"Falcon Trading LLC - Quotation….pdf", to test the file name) via the portal paperclip. Capture:
  - the analyze_drawing answer (redaction_complete, drawing_redacted_paths);
  - the supplier inbox JSON (boq.basis, assumptions, summary);
  - the DrawingGallery pages and the inquiry_pdf.
  - Harness: scripts/e2e/drawing_reaches_suppliers.mjs walks it but has no input-file flag (needs an `--input <pdf>` addition).
  - Model calls: intake 3–4 turns (USD 0.016/turn, p90 0.024), drawing_boq 0.004–0.011, drawing_redact 1 page detect plus verify ~0.003, sales_engineer match ~0.02, supplier arabicOf ~0.004.
  - Total about USD 0.12–0.17.
- P2 (S2, S3, S4 in one request): type "I'm Omar Haddad, villa 15 Al Barsha 2 near Mall of the Emirates, call zero five five…", answer one supplier question with the plot and Makani in the answer. Capture the stored summary, spec.location, the queued notifications.body (SELECT) and the supplier card. Cost: intake ~0.06–0.10 plus match ~0.02, about USD 0.10. Harness: scripts/e2e/held_intake_asks_the_open_specs.mjs plus demo_factory.
- Both together: about USD 0.25–0.30, inside the 0.60 left.
- PDFs in /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/pdfs/:
  - "A1 input - customer's existing quotation.pdf"
  - "A1 output - inquiry as suppliers receive it (model step stubbed).pdf" — stubbed: the PDF model read was replaced by the product's own code reader (drawing_boq mode 'document'); intake answers set to null.
  - "A3 output - area and site details on the supplier inquiry PDF (intake answers stubbed).pdf"

5. NOT DETERMINED
- What the live model and verifier do with a quotation page (L2): needs P1.
- Whether the intake model writes "Villa 15" into the summary (it writes the area on all 3 rows).
- E-mail headers, reply-to and tracking links in send_outbox were not read.
- Matching explanations were not read.
