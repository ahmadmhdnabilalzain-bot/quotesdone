AUDITOR C: supplier to customer (R2, R3, R5, and the document inventory). Phase 1 only: I read the code and ran it offline. Nothing was written to production; I only ran SELECTs (counts, shapes and policies). Worktree /tmp/claude-0/anon-C has been removed. Skills: quotesdone memory notes as briefed. No plugins needed.
Folder: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/C_supplier_to_customer/ (harnesses c1_harness.ts, c2_compare.ts, c3_probes.ts, c4_chat_door.ts, c5_short.ts; outputs c1_report_*.json, c3_probes_out.txt, c2_text.txt, c2_compare.csv, png/, sql/). The harnesses import from /tmp/claude-0/anon-C, so recreate that worktree to re-run them.

1. LEAKS AND GAPS, most harmful first
L1 (R2, PROVED BY RUNNING). Code does not remove a short form of the supplier's own name once it drops the trade word.
- Examples: "Desert Brush team" for Desert Brush Painting LLC, "Gulf Shield warranty" for Gulf Shield Waterproofing LLC, "Emirates Steel workshop" for Emirates Steel Fabrication LLC (c5_short.ts).
- Every layer misses it: save scrubIdentity (supplier_api/identity_scrub.ts:40), knownNameRe (_shared/identity_text.ts:367), maskContacts (_shared/quote_documents/base.ts:32) and the generaliser.
- The customer sees it in the portal terms, the comparison PDF and the CSV: C2 PDF and CSV show "balance on completion - Desert Brush team".
- On the typed-form door and in clarify questions there is no model at all, so nothing catches it.
- Smallest fix: in knownNameRe, also match the name with its trade words removed (2+ words) for the supplier's own text. Check it against the two over-redaction lists, as the identity-shapes note requires.
L2 (R2, PROVED). These shapes pass every code layer (c3_probes_out.txt, 11 of 46 cases fail at the customer door):
- a person without a label ("Contact Rashid Khan for details", "Regards, Rashid");
- an area or showroom in prose ("visit our showroom in Al Quoz", "from our Al Quoz warehouse");
- an Arabic firm name with no legal form ("فالكون للدهانات");
- a phone written in words, or split ("050 123 / then 4567");
- the bank name ("Emirates NBD");
- the supplier's document-number prefix ("FT-Q-[hidden]");
- an unknown house brand ("Falcolux");
- "Sales Manager. Signed and stamped".
The upload door relies on the model alone for all of these. A careless reading puts them on the customer's quotation PDF: "C1 output - the same with a careless model reading.pdf", pages 2-3 show "Contact Rashid Khan", "from our Al Quoz warehouse" and "FT-Q-".
L3 (R2 brand rule, PROVED). With a ZZ DEMO lead name, "Falcon premium paint" (his own name inside an item description) reaches the PDF and the comparison. knownNameRe needs the whole "ZZ DEMO Falcon". With a real-shaped name, "Falcon Trading LLC", it is removed.
- Consequence: demo-based leak tests understate this case and overstate others. Phase 2 demo suppliers should get names that test this.
L4 (accuracy, PROVED). Over-redaction changes a field the customer is allowed to see.
- "5 years warranty by Falcon Trading LLC" is saved as "5 █ on workmanship".
- The checker then takes "manufacturer warranty 10 years", so the cover, terms and comparison say "Warranty 10 years" when the supplier gave 5 years (careless PDF, page 1).
- The firm-name pattern eats "years warranty by …". The fix belongs in FIRM_EN's left context.
L5 (R2 brand rule vs messages, PROVED). A supplier's clarify question to the customer before reveal (messages_api/strip_contact.ts:30) is not run through the brand generaliser. "Do you accept Jotun Fenomastic / Daikin FTKF50?" reaches the customer's e-mail and portal as written. The brand note says no brand reaches the customer before reveal. Founder to decide whether questions are covered.
L6 (R3 after reveal, READ plus production policy). After a paid reveal the vault hands the customer originals:
- the supplier's ORIGINAL quotation file: customer_documents/index.ts:143-149, signed URL; fn_customer_document_refs has the reveal filter live;
- his licence, profile and catalogue files: supplier-docs, live rows 11, 7 and 2.
This contradicts the code's own comment in customer_api/actions/reveal.ts:25 ("never the supplier's own file") and ruling 1683 ("no single document … unless under our template"). FOUNDER DECISION: is an original allowed after reveal?
L7 (ruling 1671, READ). Two downloads are not PDFs:
- compare_csv (customer_api/actions/reports.ts:54-76): the same masked rows, minus the maskNames layer. The C2 CSV had the same leaks as the PDF.
- the JSON copy beside "Download my data" (src/components/portal/PrivacyControls.tsx:129).
L8 (coverage gap, READ). Since PR #1981 the upload door is model-first. The permanent planted-identity corpus (scripts/e2e/identity_leak_pipeline.ts) still drives only the code reader quoteFromExtracted, which only the chat door uses now. The model path's code backstop has no identity fixture: quote_extract tests are all about money. My c1_harness is the only measurement.
- Small detail: unit, qty and country_of_origin bypass gen() in quote_extract/model_reading.ts:113-118. country_of_origin is cut to the country at the customer door (countryOnly); unit is printed raw.
L9 (state, PROVED). The portal quotation chat is still code-first for lines and prices (supplier_api/quote_review_flow/reading.ts:45-74). Only terms and scan transcription use a model. On C1's input it kept 1-2 of 4 lines plus a footer phone as a line, so masking there is code-only.
L10 (low, READ). The customer activity trace keeps "supplier #<id>" (customer_api/actions/discovery.ts:20-50). There is no public supplier directory, so it cannot be searched. It also counts any transaction row as revealed, not only revealed_at.

2. WHAT HOLDS
- The original file never reaches the customer before reveal. Live: quote-files is private with no storage policy; the RLS refs function filters on revealed_at; the only routine touching supplier identity that authenticated users can run is fn_customer_document_refs; leads, quotes, quote_items, messages and rfq_clarification have no authenticated SELECT.
- The original file name and PDF properties never reach the customer. Our PDFs are named "QD-990457-A-v2.3-quotation-en.pdf" with Title "QD-990457-A — Quotation" and Author "QuotesDone Technologies" (render.ts:637). The input's Title and Author ("Falcon Trading…", "Rashid Khan") are gone. I ran this.
- With a faithful model reading, the customer's PDF and portal screen carry no identity. Contacts, TRN, licence, IBAN, P.O. Box, labelled person, full address and Arabic legal firm names are removed at save and at the door.
- Before reveal the customer sees only bands for rating, reviews and years, plus a verified flag and the job count. Emirate, win rate and match reason are hidden (inquiry_lifecycle.ts:289-296).
- The comparison masks every quoting supplier, revealed or not (lib/pdfs.ts:191). The quotation PDF names only a revealed party (pdfs.ts:39). E-mailed and WhatsApp quotes are never submitted by themselves. A WhatsApp file goes to the licence reader, never to a request.
- Guards I ran: 174 tests passed, 0 failed (identity_text, quote_generalise plus its corpus, quote_documents ×4, pre_reveal_quote_text, quote_extract ×4, pre_reveal_identities, quote_review_corpus, inquiry_document_no_contact). The brand corpus: leaks 125 → 0 of 177. The template check: 45/45.
- Not run: identity_never_leaks_before_reveal.mjs (about 1 h of OCR).
- S2 cases with no fixture anywhere: an unlabelled person, an area in prose, a phone in words or split, the document-number prefix, a short or house-brand name, an Arabic firm with no legal form, a bank name.

3. DOCUMENT INVENTORY
| Document | Who receives it | Door | Status |
|---|---|---|---|
| Quotation PDF | customer | quote_pdf | TEMPLATE |
| Comparison PDF | customer | compare_pdf | TEMPLATE |
| Comparison CSV | customer | compare_csv | NOT A PDF |
| Brief PDF | customer | brief_pdf | TEMPLATE |
| Reveal invoice and receipt | customer | e-mail attachment and WhatsApp link | TEMPLATE; customer's details only, no supplier |
| Data copy | customer | my_data_pdf | TEMPLATE, plus a JSON copy (NOT A PDF) |
| Terms certificates | customer | compliance_archive | TEMPLATE |
| Supplier's original quotation | customer, after reveal | vault | PASS-THROUGH after reveal (L6) |
| Supplier's licence, profile, catalogue | customer, after reveal | vault | PASS-THROUGH after reveal (L6) |
| Chat attachments | either side, after reveal | messages | PASS-THROUGH after reveal |
| Inquiry PDF | supplier | inquiry_pdf | TEMPLATE |
| Regenerated quotation, receipts, registration and dues invoices | supplier | supplier portal | TEMPLATE |
| Drawings | supplier | inquiry | redacted originals (auditor B) |
| Social calendar .xlsx, customers-register .xlsx | founder / internal | e-mail, compliance archive | NOT A PDF |
The template check (every_pdf_we_issue_is_on_our_template.mjs) only proves that PDFs we generate come from pdf_native and are not Stripe's. It does not see CSV, JSON or XLSX, originals passed through by signed URL, or file names.

4. PHASE-2 PLAN (deploy first, one scenario at a time)
P1, S1/S2 upload door:
- Steps: supplier_full_walk.mjs step b (setInputFiles), with "C1 input - supplier's own quotation with full identity.pdf" in place of quotationPdf(). Use a demo supplier named "Falcon Trading LLC (ZZ DEMO)", and also a "<Name> Painting LLC" to test L1.
- Capture: the extract_quote JSON, the my_inquiries JSON, and customer_api quote_pdf in en and ar via demo_factory `call`.
- Cost: quote_extract USD 0.001-0.004 (2 tries max, so ≤0.01); submit reasoning about 0.005; Arabic lines about 0.01.
P2, comparison:
- Add two typed form quotes carrying the L1/L2 strings, then call compare_pdf and compare_csv.
- Ask for the deterministic path. A model comparison averages USD 0.106 (max 0.25), so that is the budget risk: run it at most once.
P3, S3:
- One clarify_ask holding the c3 strings (no model). Capture the customer e-mail row and clarify_list.
P4, R5:
- One Stripe TEST reveal of the typed quote. Re-fetch quote_pdf for both quotes, compare_pdf, and the vault list; check the original file is now signed (L6).
- Cost: USD 0, apart from hand-off notices.
Budget: total about USD 0.05 without a model comparison, about 0.30 with one.
Clean browser context: server-produced bytes can be captured by API. Any claim that "the customer can download it in a browser" needs a context with no interception, signing in with storageState.
PDFs for the founder, in /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/pdfs/:
- "C1 input - supplier's own quotation with full identity.pdf"
- "C1 output - the quotation as the customer sees it (model reading stubbed, faithful).pdf" (clean)
- "C1 output - the same with a careless model reading.pdf" (L2-L4 visible)
- "C2 output - comparison of three quotations as the customer sees it.pdf" (L1/L2 visible)

5. COULD NOT DETERMINE
- What the live model actually returns for the identity fields (not called).
- Whether logos, stamps or QR codes in a photo affect the model's reading.
- The live quotation chat's vision transcription.
- The full OCR corpus run.
- The real browser download of the CSV and PDF.
FOUNDER DECISIONS: L5 (brands in supplier questions), L6 (originals after reveal), L7 (whether CSV and JSON may exist beside the PDF).