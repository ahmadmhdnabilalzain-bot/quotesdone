# Supplier document uploads on production, 28 Oct – 1 Nov 2026

**Assigned:** `sales_engineer` (supplier onboarding).

**Asked:** the coordinator relayed the founder's question about invited suppliers uploading their company profile, trade licence and other documents. The task was to verify the whole document path on production, as a supplier experiences it.

Every test used a ZZ DEMO lead. Every sign-up used the real e-mail code, delivered to a Resend sink (`delivered+qd-<tag>@resend.dev`). Each run was torn down afterwards; the leftover scan is at the end.

## The path, per document

| document | upload UI | types, size | storage | read by | written | supplier sees | review sees |
|---|---|---|---|---|---|---|---|
| Trade licence | Documents card (Upload / Replace); for a fresh supplier, also the registration form | PDF, JPEG, PNG, WebP; 25 MB on the server, 10 MB in the portal (#1720) | `supplier-docs/licence/<id>/` (Documents tab) or `licenses/<id>/` (registration form) | code first (`document_expiry.ts`: number, authority, emirate, name, expiry); `license_extract` (vision) when code reads nothing | `license_doc_path`, `trade_license_no`, `license_authority`, `licence_legal_name`, `license_expiry`, `doc_versions` | "Valid · expires …", "Read from the document: expires … (machine-read)", or "could not read … upload a clear PDF" | `fn_sales_engineer_verifies_supplier`: approves, or holds with a reason (`licence_name_unread`, `licence_expiry_unread`, `licence_name_mismatch`, `licence_expired` …) shown as "Why: …"; decision in `agent_actions` |
| Company profile | Documents card; registration form | PDF, DOCX, PPTX, JPEG, PNG; 100 MB | `profiles/<id>/` via a signed upload, never in the request body | after the answer (`supplier_docs_later.ts`): type and malware gate, then trades read by code or model | `company_profile_doc_path`, `supplier_capabilities.source_docs` | "On file"; "still being read" until the read finishes | mandatory-six `reg_profile` |
| Insurance, ISO, dealer letter | Documents cards, with an optional date box | PDF, JPEG, PNG, WebP; 10 MB in the portal | `certs/<id>/` | code reads the expiry; `license_extract` cert mode for a scan | path, plus `*_expiry` once confirmed | "We read … expires X — is that right? [Confirm]" | expiry alerts (`fn_supplier_expiries`) |
| EGR card | Documents card | as above | `certs/<id>/` | none | `egr_doc_path` | "On file" | none |
| Catalogues | Documents card; registration form | as the profile | `catalogs/<id>/` | after the answer | `catalog_doc_paths` (append) | list with View / Download / Replace / Remove | none |
| Supporting documents | Supporting company documents panel | PDF, image or office file; 25 MB; 30 files | `supporting/<id>/` | `doc_extract` drains them later | `documents` (`ref_table supplier_supporting`) | list with name and type | none |

**Who can read the files.** RLS is on for `storage.objects` and it has **no policy at all**, so `anon` and `authenticated` read nothing. Only the service role can. The functions select the supplier by `claimed_by = JWT email` and hand out 1-hour signed URLs. Upload paths are checked against `<folder>/<own id>/`.

`drawing_redact` is not on this path. Its CPU kills (8 in 14 days) come from customer drawings.

## Health of each function, 14 days (`ai_cost_log`, `agent_runs`, function logs)

- **`license_extract`.** 75 OK on 18–19 Oct, then **38 of 38 failed** between 27 Oct 15:25Z and 28 Oct 00:40Z.
  - The stored error: `Invalid image data URL ... payload is not base64-encoded data`.
  - **Root cause:** the portal sends each page as `{ mime, data }`, but `_shared/licence_extract.ts` read only `b64`. The model was therefore given `[object Object]` and OpenRouter refused the request before any model ran.
  - Fixed in **#1707** (live). After the fix, a phone-photo licence sent through the registration form was read exactly in 14.4 s (1366) and 14.1 s (390).
- **`doc_extract`.** 3 errors: a caller with the wrong inbound secret, on 18, 19 and 27 Oct.
- **`supplier_doc_trades`.** 2,217 OK and 8 failed.
- **CPU and wall-clock shutdowns.** None on `supplier_api`, `supplier_portal`, `license_extract`, `claim_lookup` or `doc_extract`. There were 92 on `ai_gateway` (76 of them on 27 Oct) and 8 on `drawing_redact`.

## Browser walk: run 4e9d675a, 1366 px and 390 px

The walk is `scripts/e2e/supplier_document_walk.mjs`. The summary is `walk_4e9d675a_summary.json` and the screenshots are in `screenshots/`. It ran before #1708, #1709, #1720 and #1721 shipped.

| upload | 1366 | 390 | note |
|---|---|---|---|
| sign-up with the real code, claim | PASS | PASS | |
| phone-photo licence, registration form (#1707 live) | PASS 14.4 s | PASS 14.1 s | all fields read |
| phone-photo licence, Documents tab | PASS 11.1 s | PASS 10.4 s | read by the model; a shakedown took 18.0 s, inside the old 20 s wait by 2 s (#1709) |
| bilingual Arabic/English licence PDF | PASS 14.5 s | PASS 11.9 s | |
| 24 MB licence | **FAIL** | **FAIL** | 546; raw platform text on screen (#1720, #1721) |
| 26 MB licence | PASS on screen | PASS on screen | "Upload failed: 26.0 MB exceeds the 25 MB limit" |
| company profile PDF | PASS | PASS | |
| insurance | **FAIL** | **FAIL** | the start date was offered as the expiry (#1708) |
| ISO | PASS | PASS | |
| dealer letter | PASS | PASS | |
| DED licence PDF (number, expiry, name by code) | PASS | PASS | |
| every control on screen | PASS | PASS | |
| finish registration, approved | PASS | PASS | |

## Sizes (realistic scans: one JPEG per page, text layer on page 1)

| file | `supplier_portal` (Documents tab) | `supplier_api` process_docs (registration form) |
|---|---|---|
| 9.66 MB, before #1721 | 200 | 200 |
| 14.50 MB, before #1721 | 546 | 546 |
| 14.50 MB, after #1721 (1 Nov) | **200** in 7.0 s | **200** in 34.1 s |
| 19.33 MB, after #1721 (1 Nov) | **200** in 6.0 s | **546** in 4.1 s |

`process_docs` still stops at 19.3 MB. The portal sends the licence twice (`original_b64` and `file_b64`), plus page images.

Also measured, both fine: a 19.3 MB profile on the direct-upload path, and a 19.3 MB supporting document.

A real quotation photo took **25.9 s** to read (#1719).

## Defects and PRs, by severity

1. **High.** `license_extract` failed on every portal licence: photos and scans were never read, and the review held them. **#1707**, live.
2. **High.** The insurance start date was offered as the expiry. A licence printing "Validity: A - B" would have had its issue date written as its expiry. **#1708**, live.
3. **High.** Reads were cut off at the portal's 20 s limit:
   - document uploads, **#1709**, live;
   - quotation uploads, **#1719**, live.
4. **Medium-high.**
   - A licence over about 10 MB failed with the raw platform text on screen. The fix maps platform errors to plain copy and caps the portal at 10 MB: **#1720**.
   - The reader that causes it, one pass with a native decode: **#1721**, live.
5. **Medium (security-sensitive).** About 0.7–1.4% of compressed PDFs were refused as "embedded JavaScript", and `/J#53` was accepted. **#1723**.

## Spend

The upper bound across all runs, 28 Oct – 1 Nov, is about **$0.07** of model calls. Server-to-server calls drop the run tag, so this counts every untagged licence and trade read in my windows, including any made by others.

## Leftovers

Seven runs were torn down: `e8d1e4b5`, `4e9d675a`, `ab1fe44e`, `0076d1a5`, `85bd0f54`, `02ecc0e4`, plus the 1 Nov probe. Four of them were killed mid-teardown by a `timeout` wrapper, then purged with `run.mjs --purge-tag`. One quote-files object was removed by hand. The final scan is in the hand-over report.
