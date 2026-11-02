---
name: supplier-document-uploads-measured-28-oct
description: "28 Oct 2026: what each supplier document upload does on production, its measured limits, and the traps that made the first measurements wrong. Walk: scripts/e2e/supplier_document_walk.mjs."
metadata:
  type: project
  modified: 2026-10-28
---

**Two upload doors, two ways of reading.**
- **The body path.** The trade licence, insurance, ISO, dealer letter, EGR and quotation travel as base64 in the request: `supplier_portal save_documents`, `supplier_api process_docs`, `extract_quote`. Each is read before the answer: first by code (`_shared/document_expiry.ts`), then by the vision model when code reads nothing (`license_extract`, `quote_extract`).
- **The direct path.** The company profile and catalogues go straight to storage (`supplier_api upload_url`, 100 MB) and are read after the answer (`_shared/supplier_docs_later.ts`).
- Supporting documents are base64 with no read (25 MB).
- Bucket `supplier-docs` is private, and `storage.objects` has RLS on with **no policy at all**. Only the service role reads it. A supplier sees only their own files, through 1-hour signed URLs that the functions issue for `claimed_by = JWT email`.

**Measured limits (scanner-style PDFs: one JPEG per page, text layer on page 1).**
- 9.66 MB was read on both body paths.
- 14.50 MB and 19.33 MB ended the function at the edge's **CPU** cap (HTTP 546, "CPU Time exceeded").
- The cause was `pdfText`: a whole-file `String.fromCharCode` decode, 810 ms for 19 MB, run three times per upload. #1721 decodes natively and reads once.
- #1720 caps the portal's body uploads at 10 MB (`supplier/api.ts MAX_READ_BYTES`) until the larger scans are proven.
- A 19.3 MB profile on the direct path and a 19.3 MB supporting document were both fine.
- Read times: a photo licence takes 10–18 s (model) and a quotation photo 25.9 s. The portal's old 20 s cut-off lost these (#1709, #1719 now wait 90 s).

**Traps in the measurement itself.**
- Padding a PDF with random base64 comment lines makes it spell `/JS` by chance. The old rule refused that as embedded JavaScript, and about 1% of real deflate data too (#1723). Pad with hex digits.
- Chromium's PDF printer de-duplicates a repeated image, so 6 identical pages came out at 1.3 MB. Real scans need distinct pages (the probe used PIL noise per page).
- Playwright cannot read the JSON of a response to a very large request, because the body is evicted. Assert on the screen instead.
- **Teardown runs 10–30 min while other runs share the management API.** A `timeout` wrapper shorter than that kills `closeRun` and leaks the run. Never wrap a probe in `timeout`, or purge with `run.mjs --purge-tag`, one tag at a time. See [[a-killed-check-leaks-its-fixtures]].
- `supplier_portal` and `supplier_api` call `license_extract`, `quote_extract` and `supplier_doc_trades` server-to-server without the run tag. A run's model spend therefore shows as untagged in `ai_cost_log`; attribute it by time window.

**Defects found and fixed that day:**
- #1707: `license_extract` read `{mime, data}` pages as `[object Object]` (38/38 failed).
- #1708: an insurance period's start date was read as its expiry.
- #1709 and #1719: the 20 s cut-off.
- #1720: raw platform text on screen, and the 10 MB cap.
- #1721: the one-pass read.
- #1723: the `/JS` false positive (security-reviewed).

Related: [[the-registration-walk-reads-the-real-code-through-a-resend-sink]].
