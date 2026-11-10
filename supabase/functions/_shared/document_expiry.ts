// document_expiry — read an expiry date OFF a document by code, before any model is asked.
//
// Founder instruction 524 (21 Sep 2026): expiry dates were typed by hand in the supplier portal
// Documents tab while license_extract existed to read them — and license_extract runs through
// ai_gateway, which the OpenRouter hold keeps closed. This is the deterministic first attempt:
//   1. pdfText(bytes): the strings a PDF's content streams draw (Tj / TJ operators), inflating
//      FlateDecode streams with the runtime's DecompressionStream. No dependency.
//   2. expiryFromText(text): a date within 90 characters AFTER an expiry keyword, English or
//      Arabic, or the date in an expiry label's own column of a table. A date with no keyword
//      beside it is NOT an expiry — an issue date, a policy start, a print date all look the same —
//      so nothing is returned and the caller says it could not read the document. NEVER a guess: a
//      wrong expiry either suspends a valid supplier or lets a lapsed one keep trading.
//
// CEILING, measured against scripts/staging/fixtures/licence_pdf.mjs (Helvetica, WinAnsi, plain
// content stream): every field reads. A scanned licence (image-only PDF or a photo) has no text
// stream and returns null — there is no OCR here; the browser-side tesseract (src/components/me/
// ocrClient.ts) is a customer-portal tool and was not moved. A PDF whose fonts use a CID/Identity
// encoding draws two-byte glyph ids, not characters; those come out as noise and, because no
// keyword matches noise, the answer is null rather than wrong. That is the honest direction.
// ponytail: text-stream PDFs only; add pdf.js-in-Deno or server OCR when a measured share of real
// uploads is scanned.


// Split into ./document_expiry/*.ts on 9 Nov 2026 (a pure move); this file re-exports the same names.
export { parseDate } from './document_expiry/dates.ts';
export type { ExpiryRead } from './document_expiry/dates.ts';
export { expiryFromText } from './document_expiry/expiry_text.ts';
export { pdfText, readExpiry, textFromContent } from './document_expiry/pdf_text.ts';
export { emirateOf, emirateOfAuthority, licenceFieldsFromText, licenceNameFromText, NAME_LABELS, readLicenceFields, readLicenceName } from './document_expiry/licence_fields.ts';
export type { LicenceFields } from './document_expiry/licence_fields.ts';
export { b64Size, licenceModelPayload, licenceNameFromModel, licenceNeedsModel, mergeLicenceReads, READ_MAX_BYTES, toB64, tooLargeToRead } from './document_expiry/licence_model.ts';
