// licence_extract — the licence half of license_extract (the vision read of a UAE trade licence), as a module.
// Seat: sales_engineer. 7 Oct 2026, accuracy suite (ledger 1162).
//
// WHY A MODULE. The founder's gate is "not a single mistake in any trade licence". The accuracy suite
// (scripts/e2e/document_intake_accuracy.mjs --model gateway) must measure the EXACT request and normalisation the
// function sends, before a prompt change is deployed; a copy in the harness would measure itself. license_extract
// builds its licence request and reads its answer only through these functions.
//
// WHAT CHANGED WITH THE MOVE: the prompt now also asks for the Arabic legal name, the trade name and the legal form,
// which a UAE licence prints and the suite measures; nothing else in the request changed.
import { DATE_RE, parseDate } from './document_expiry/dates.ts';
const DATES_G = new RegExp(DATE_RE.source, 'gi');

export const SYS_LICENSE = `You are a meticulous UAE corporate-registry document controller. You read an official UAE TRADE LICENCE (DED / DET / free-zone / e-trader) and extract its registration data EXACTLY as printed. Read every line; do not guess. Return STRICT JSON only:\n{"legal_name":string,"legal_name_ar":string,"trade_name":string,"legal_form":string,"license_number":string,"license_authority":string,"emirate":string,"city":string,"issue_date":"YYYY-MM-DD","expiry_date":"YYYY-MM-DD","activities":[string],"trn":string,"confidence":"low"|"medium"|"high","document_kind":"trade_licence"|"company_profile"|"catalogue"|"quotation_or_invoice"|"identity_document"|"certificate"|"other"|"unreadable","document_kind_why":string,"document_kind_confidence":"low"|"medium"|"high"}\nlegal_name = the exact licensed company / establishment name as printed in ENGLISH; when the licence prints its English name only as a Trade Name, with no separate company or legal name, that English Trade Name IS the licensed name: give it here too; if the licence prints no English name, an empty string (never a translation, a transliteration or the Arabic name). legal_name_ar = the name as printed in Arabic, else ''. trade_name = the trade name as printed, else ''. legal_form = the legal form / legal type / legal status as printed (e.g. 'Limited Liability Company', 'Free Zone Establishment'). license_number = the licence / register number exactly as printed. license_authority = issuing authority as printed (e.g. 'Dubai Department of Economy and Tourism', 'Sharjah Economic Development Department', 'Jebel Ali Free Zone Authority'). emirate = one of Dubai, Abu Dhabi, Sharjah, Ajman, Umm Al Quwain, Ras Al Khaimah, Fujairah. city = city/area if shown else the emirate. activities = the listed business activities, each exactly as printed. trn = VAT TRN if present else ''. Dates as printed, output YYYY-MM-DD (UAE dates are day-first). If a value is not visible use an empty string and lower the confidence. This is NOT a tax/AML check - it is commercial onboarding verification only.\nFIRST SAY WHAT THE DOCUMENT IS (a supplier may attach the wrong file by mistake). document_kind = trade_licence for ANY trade or commercial licence or any part of one: every emirate's economic department (DED / DET), every free zone, e-trader, a Commercial Register certificate page, an Arabic-only licence, a photo of a framed licence, a licence with a renewal receipt or payment voucher in front of it, a licence of another country, a free-zone Certificate of Incorporation, Formation or Registration (some free zones issue it with or instead of the licence); and also when a licence appears anywhere inside a larger file (for example a company profile with the licence scanned in it): then read the licence. company_profile = a company profile, brochure or presentation of the company's services, projects or clients, with no licence in it. catalogue = a product catalogue, datasheet or price list. quotation_or_invoice = a quotation, invoice, purchase order or receipt that is not a licence renewal receipt. identity_document = an Emirates ID, passport, visa or driving licence. certificate = a certificate that is not a trade licence (ISO, insurance, VAT / TRN registration, chamber of commerce membership, a product or test certificate). other = anything else. unreadable = you cannot see enough to tell. document_kind_why = one short plain sentence saying what it looks like and why (e.g. "a company profile: it describes services and projects and carries no licence number, issuing authority or expiry date"). document_kind_confidence = how sure you are of document_kind; say "high" only when you are certain. Always fill the licence fields with exactly what the file prints, whatever document_kind is: never leave a printed licence number, issuing authority or expiry date out because you think the file is not a licence.`;

/** null = no usable object (a 502 with a named error, never a blank doc: 9 Sep 2026). */
export function parseJson(t: string): Record<string, unknown> | null {
  const take = (s: string) => { try { const v = JSON.parse(s); return (v && typeof v === 'object' && !Array.isArray(v)) ? v as Record<string, unknown> : null; } catch { return null; } };
  return take(t) ?? (t.match(/\{[\s\S]*\}/) ? take(t.match(/\{[\s\S]*\}/)![0]) : null);
}
const dataUrl = (b64: string, mime: string) => `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/, '')}`;
// A MODEL'S DATE IS A DATE ONLY AS A REAL CALENDAR DAY (12 Nov 2026, sales_engineer; independent review of #1978, F4). This took a
// timestamp through new Date(), so '2027-10-29T00:00:00+04:00' became 2027-10-28 (a licence expiring today refused a day early); a
// Hijri '1448/05/10' passed as the year 1448 and would read as long expired; '2027-02-30' and a month-first '10/29/2027' (as
// '2027-29-10') passed, and the date column then refused the model's whole row write. Now: the leading YYYY-MM-DD of an ISO date or
// timestamp as printed (never moved to another zone), a day-first D/M/YYYY, or a written date ("29 Oct 2027", document_expiry's
// parseDate); Arabic-Indic digits read as digits; a real calendar day with a year from 1990 to 2100, or null (unread). Shared with
// license_extract's certificate mode, where the same holds.
export function normDate(s: unknown): string | null {
  const v = String(s ?? '').trim().replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06f0));
  if (!v) return null;
  const day = (y: number, m: number, d: number) => {
    if (!(y >= 1990 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)) return null;
    const dt = new Date(Date.UTC(y, m - 1, d));
    if (dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
    return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  };
  let m = v.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:$|[T\s])/);
  if (m) return day(+m[1], +m[2], +m[3]);
  m = v.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/);
  if (m) return day(+m[3], +m[2], +m[1]);
  return /\p{L}/u.test(v) ? parseDate(v) : null;
}
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
export function normEmirate(s: unknown): string {
  const t = String(s || '').toLowerCase();
  for (const e of EMIRATES) if (t.includes(e.toLowerCase())) return e;
  if (/rak/.test(t)) return 'Ras Al Khaimah'; if (/uaq|umm al/.test(t)) return 'Umm Al Quwain'; if (/auh|abu/.test(t)) return 'Abu Dhabi';
  return '';
}

/** One page's base64, whichever shape the caller sent (28 Oct 2026, sales_engineer).
 * The supplier portal's fileToImages and pdfRaster send each page as { mime, data }; the server-side callers send
 * { b64, mime } or a bare string. Only b64 and a bare string were read, so every portal page became the text of an
 * object, the provider refused it ("Invalid image data URL ... payload is not base64-encoded data") and every licence
 * read from the registration form failed: 38 of 38 calls on 27-28 Oct. '' = no usable page. */
// deno-lint-ignore no-explicit-any
export function pageB64(im: any): string {
  const v = typeof im === 'string' ? im : (im?.b64 || im?.data || '');
  if (typeof v !== 'string') return '';
  // Review of #1707: a page that is not base64 (empty, '[object Object]', a URL, plain text) is no page at all,
  // rather than a request the provider refuses with a 400. Whitespace (MIME line breaks) is not part of the data.
  const raw = v.replace(/^data:[^;,]+;base64,/, '').replace(/\s+/g, '');
  return raw.length >= 16 && /^[A-Za-z0-9+/]+={0,2}$/.test(raw) ? raw : '';
}

/** The image type of one page: the mime the caller named when it is an image type, else the data URL's own prefix,
 * else the file's magic bytes. A PNG sent as image/jpeg (or the reverse) is what the provider is told it is. */
// deno-lint-ignore no-explicit-any
export function pageMime(im: any): string {
  const named = typeof im === 'object' && im ? String(im.mime || '') : '';
  if (/^image\/[a-z0-9.+-]+$/i.test(named)) return named.toLowerCase();
  const v = typeof im === 'string' ? im : String(im?.b64 || im?.data || '');
  const pre = v.match(/^data:(image\/[a-z0-9.+-]+);base64,/i);
  if (pre) return pre[1].toLowerCase();
  const b = pageB64(im);
  if (b.startsWith('iVBORw0KGgo')) return 'image/png';
  if (b.startsWith('/9j/')) return 'image/jpeg';
  if (b.startsWith('UklGR')) return 'image/webp';
  if (b.startsWith('R0lGOD')) return 'image/gif';
  return 'image/jpeg';
}

/** True when the request carries something a model can read: one usable page image, or a file. */
// deno-lint-ignore no-explicit-any
export function hasReadablePage(images: any[], body: { file_b64?: string }): boolean {
  return (Array.isArray(images) && images.slice(0, 10).some((im) => !!pageB64(im))) || !!pageB64(body?.file_b64 ?? '');
}

// THE ORIGINAL PDF BESIDE ITS PAGE PICTURES, BEHIND A SWITCH (12 Nov 2026, sales_engineer; founder ruling 1666: the platform must read a
// licence as well as the model does when the same file is attached in the model's own app). The browser turns each PDF page into a
// JPEG (src/components/me/pdfRaster.ts, ~1071x1516 for A4) and only those pictures were sent when there were any; the model's own app
// is given the file itself. With `withFile`, a PDF the request also carries is sent after the pictures. Off unless
// app_secrets.licence_read_sends_the_pdf = 'on' (no row = off), so the main session can compare one paid read before turning it on.
// deno-lint-ignore no-explicit-any
export function documentContent(intro: string, images: any[], body: { file_b64?: string; mime?: string; filename?: string }, opts: { withFile?: boolean } = {}): any[] {
  // deno-lint-ignore no-explicit-any
  const content: any[] = [{ type: 'text', text: intro }];
  // Only pages that are real base64 are sent; when none is, the file is (the portal sends both), never an empty read.
  const pages = Array.isArray(images) ? images.slice(0, 10).filter((im) => !!pageB64(im)) : [];
  if (pages.length) {
    for (const im of pages) content.push({ type: 'image_url', image_url: { url: dataUrl(pageB64(im), pageMime(im)) } });
    const mime = String(body.mime || '');
    if (opts.withFile && body.file_b64 && pageB64(body.file_b64) && /pdf/i.test(mime)) {
      content.push({ type: 'file', file: { filename: String(body.filename || 'document.pdf'), file_data: dataUrl(String(body.file_b64), 'application/pdf') } });
    }
  } else if (body.file_b64 && pageB64(body.file_b64)) {
    const mime = String(body.mime || 'application/octet-stream');
    if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
    else content.push({ type: 'file', file: { filename: String(body.filename || 'document.pdf'), file_data: dataUrl(String(body.file_b64), mime || 'application/pdf') } });
  }
  return content;
}

/** The ai_gateway body for one licence (no caller-side `max`: model_policy.document_extraction decides it). */
// deno-lint-ignore no-explicit-any
// A company profile's reading (license_extract mode 'profile'). lines = the printed service lines, verbatim: the only text
// a picture's trades are chosen from, so every chosen trade's quote is a line the page prints (review of #1412, 18 Oct 2026).
export const SYS_PROFILE = `You read a UAE supplier's COMPANY PROFILE and/or PRODUCT CATALOG and summarise what the company actually does, so QuotesDone can match it to relevant customer requests. Be factual; use only what the documents show. Return STRICT JSON only:\n{\"summary\":string,\"services\":[string],\"products\":[string],\"sectors\":[string],\"emirates\":[string],\"confidence\":\"low\"|\"medium\"|\"high\",\"lines\":[string]}\nlines = every line on the pages that names a service, activity, product line or scope of work, copied EXACTLY as printed (same words and spelling, never reworded or summarised; max 30, each under 120 characters). Take them only from what the company prints about its OWN work; never from a certificate, a letter of recommendation, a client or project list, or a licence. summary = 2-4 plain sentences describing the business, its core offering and strengths. services = the services they provide. products = product lines they supply (generic, no need to keep brand names). sectors = the trade categories they fit (e.g. joinery, MEP, fit-out, flooring, signage, landscaping). emirates = areas/emirates they serve if stated. Keep arrays concise (max ~12 each).`;

export function profileExtractRequest(payload: { images?: any[]; file_b64?: string; mime?: string; filename?: string }, subject: unknown) {
  return { fn: 'license_extract', subject: subject ?? null, temperature: 0.1, sys: SYS_PROFILE,
    input: [{ role: 'user', content: documentContent('Read the attached company profile / catalog pages and return the summary JSON.', payload.images || [], payload) }] };
}

export function licenceExtractRequest(payload: { images?: any[]; file_b64?: string; mime?: string; filename?: string }, subject: unknown) {
  return { fn: 'license_extract', subject: subject ?? null, temperature: 0.1, sys: SYS_LICENSE,
    input: [{ role: 'user', content: documentContent('Read the attached UAE trade licence (all pages) and return the extraction JSON.', payload.images || [], payload) }] };
}

/** A licence number a model makes up when it sees none: one digit repeated, or a straight run (123456, 654321). */
export function placeholderLicenceNo(v: unknown): boolean {
  const t = String(v ?? '').trim();
  if (!/^\d{4,}$/.test(t)) return false;
  if (/^(\d)\1+$/.test(t)) return true;
  return '01234567890123456789'.includes(t) || '98765432109876543210'.includes(t);
}

/** Pixel size of a PNG or JPEG from its header, else null (unknown format: never judged). */
export function imageDims(b64: string): { w: number; h: number } | null {
  let u: Uint8Array;
  try { u = Uint8Array.from(atob(String(b64).replace(/^data:[^;]+;base64,/, '').slice(0, 200_000)), (c) => c.charCodeAt(0)); } catch { return null; }
  const be = (i: number, n: number) => { let v = 0; for (let k = 0; k < n; k++) v = v * 256 + u[i + k]; return v; };
  if (u.length >= 24 && u[0] === 0x89 && u[1] === 0x50 && u[2] === 0x4e && u[3] === 0x47) return { w: be(16, 4), h: be(20, 4) };
  if (u.length > 4 && u[0] === 0xff && u[1] === 0xd8) {
    for (let i = 2; i + 9 < u.length;) {
      if (u[i] !== 0xff) { i++; continue; }
      const m = u[i + 1];
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return { w: be(i + 7, 2), h: be(i + 5, 2) };
      i += 2 + be(i + 2, 2);
    }
  }
  return null;
}

/** THE BLANK-IMAGE GUARD RUNS BEFORE THE MODEL (13 Oct 2026, review of the run-4 fix). Nothing in the model's
 * answer can prove it read the image - a blank picture can come back 'low' with an invented Arabic name, a number
 * and a date, and normaliseLicence would keep them. So code decides first: when every page sent is an image too
 * small to carry legible print (under 200 px on either side - a 1x1 PNG, a thumbnail), the model is never asked
 * and the licence is unreadable. A PDF, or an image whose size code cannot read, still goes to the model. */
export const MIN_LICENCE_IMAGE_PX = 200;
// deno-lint-ignore no-explicit-any
export function imagesTooSmallToRead(images: any[], body: { file_b64?: string; mime?: string }): boolean {
  const pages = licencePages(images, body);
  if (!pages.length) return false;
  return pages.every((b) => { const d = imageDims(b); return !!d && (d.w < MIN_LICENCE_IMAGE_PX || d.h < MIN_LICENCE_IMAGE_PX); });
}

/** The image pages a licence request carries (base64), for code's own measurements. */
// deno-lint-ignore no-explicit-any
export function licencePages(images: any[], body: { file_b64?: string; mime?: string }): string[] {
  const pages = (Array.isArray(images) ? images : []).map((im) => pageB64(im)).filter(Boolean);
  if (pages.length) return pages;
  const file = /^image\//.test(String(body.mime || '')) ? pageB64(body.file_b64 ?? '') : '';
  return file ? [file] : [];
}

/** A 'low' read counts only when code proved a real page was read: ink measured on the image pages, or the read's
 * licence number standing in the document's own text layer (separators ignored). A read that is not 'low' = true. */
export function lowReadProven(doc: { confidence: string; unreadable: boolean; license_number: string }, inkProven: boolean, text: string | null): boolean {
  if (doc.unreadable || doc.confidence !== 'low' || inkProven) return true;
  return numberPrintedIn(doc.license_number, text);
}

const westernDigits = (t: string) => t.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x06f0));
const normNo = (v: string) => westernDigits(v).replace(/[\-\/.\s]/g, '').toUpperCase();
/** True when the licence number stands in the text, separators ignored: as a token of its own, or inside a run of text with no
 *  digit right before or after it ("No.ZZ-1234" holds ZZ1234; "991234" does not hold 1234). Shorter than 4 characters: never. */
export function numberPrintedIn(no: string | null | undefined, text: string | null): boolean {
  const n = normNo(String(no ?? '').trim());
  if (!text || n.length < 4) return false;
  const t = westernDigits(text);
  if ((t.match(/[0-9A-Za-z][0-9A-Za-z\-\/.]*/g) || []).some((x) => normNo(x) === n)) return true;
  const flat = normNo(t), esc = n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp((/^\d/.test(n) ? '(?<!\\d)' : '') + esc + (/\d$/.test(n) ? '(?!\\d)' : '')).test(flat);
}
/** Every date the text prints, as YYYY-MM-DD (day-first, as the code reader reads a UAE date; Arabic-Indic digits too). */
export function datesPrintedIn(text: string | null): Set<string> {
  return new Set((westernDigits(String(text ?? '')).match(DATES_G) ?? []).map(parseDate).filter((d): d is string => !!d));
}
const lettersKey = (v: string) => v.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');

// THE MODEL'S ANSWER IS THE READING; CODE ONLY CHECKS IT, NEVER BY LAYOUT (12 Nov 2026, sales_engineer; founder rulings 1663,
// 1664, 1666: "why should there be rules to how the layout of the trade license is? The AI should read it no matter what";
// "Trade license reading ... there's no code first, 100%"). The model reads every licence and its reading is THE reading.
//   1. ONE HARD CHECK. A licence expires after it is issued: an expiry on or before the issue date is impossible whoever read
//      it, and since the pair cannot say which of the two is wrong, both are unread here. license_extract then asks the model
//      once more; a second answer that is sound stands, otherwise the expiry stays unread: the supplier is asked in plain words
//      to attach the licence again, or held for a person. Never refused as "expired".
//   2. A NOTE, NEVER A STOP. When the file has a text layer that is this licence's own text (it holds the model's number or
//      name), each date and the number the model returned is looked for in it, in any printed form (29/10/2027, 29-10-2027,
//      2027-10-29, 29 Oct 2027, Arabic-Indic digits; the number with separators ignored). A miss is only recorded for our own
//      reviewer (`notes`): a PDF text layer is itself unreliable (the founder's licence lost Arabic letters in extraction), so a
//      miss is weak evidence and must never hold, refuse or be shown to a supplier. The value stands.
// Measured on the founder's own DET licence (12 Nov 2026): the code reader read the register page's Reg. Date as the expiry and
// overrode the model; the portal refused a licence valid to 2027-10-29 as "expired on 30 Oct 2026".
// Prevented by: _shared/a_licence_is_refused_as_expired_only_on_the_models_checked_reading.test.ts.
export type LicenceCheck = { failed: string[]; notes: string[]; grounded: boolean };

// A WRONG DOCUMENT IN THE LICENCE SLOT IS SAID ONLY WHEN THE MODEL IS SURE (12 Nov 2026, sales_engineer; founder ruling 1668: "if
// someone attaches that by mistake ... the sales agent ... should be able to judge, oh, listen, this is the wrong document ... But of
// course, it has to be accurate when it says that. I don't want it to be misjudging actual documents"). Measured that evening: the
// founder attached his company profile as his licence on purpose; license_extract read it (24,093 prompt tokens, 16.3 s) and the form
// said only "being read". The model now says what the file is in the SAME call that reads it (SYS_LICENSE document_kind); code does
// not classify a document by keywords or layout (memory: the-llm-understands-code-only-checks). THE RULE, here and nowhere else:
// "wrong document" when, and only when,
//   1. the model named a kind that is not a licence (company_profile, catalogue, quotation_or_invoice, identity_document, certificate,
//      other), AND
//   2. it said so with document_kind_confidence 'high', AND
//   3. it read NO issuing authority and NO expiry date from the file. (A company profile's footer often prints the licence number; a real
//      licence always prints its issuing authority and its expiry. The prompt asks the model to fill every printed field whatever it
//      thinks the file is, so this condition is evidence of its own and never a copy of the model's doubt: review of #1985, D1.)
// Anything else is outcome (i) or (iii) of licenceJudgementOf below. A wrong document carries no fields (normaliseLicence) and never
// becomes his licence file: the row is put back to the licence before it, or to none (review of #1985, D3; on the re-read sweep there
// is nothing earlier, so a supplier without an accepted reading has none: third review, F1), he is told which file it is, and the
// re-read sweep never asks the model about it again.
// Prevented by: _shared/a_wrong_document_in_the_licence_slot_is_named_only_when_the_model_is_sure.test.ts.
export const NOT_A_LICENCE_KINDS = ['company_profile', 'catalogue', 'quotation_or_invoice', 'identity_document', 'certificate', 'other'] as const;
export type WrongDocument = { kind: typeof NOT_A_LICENCE_KINDS[number]; why: string; message: string };
const WRONG_DOCUMENT_SENTENCE: Record<typeof NOT_A_LICENCE_KINDS[number], string> = {
  company_profile: 'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below.',
  catalogue: 'This looks like a product catalogue or price list, not a trade licence. Please attach your trade licence here. Catalogues go in the Product catalogues box below.',
  quotation_or_invoice: 'This looks like a quotation or an invoice, not a trade licence. Please attach your trade licence here.',
  identity_document: 'This looks like an identity document, not a trade licence. Please attach your company\'s trade licence here.',
  certificate: 'This looks like a certificate (such as ISO, insurance or VAT registration) rather than your trade licence. Please attach your trade licence here.',
  other: 'This does not look like a trade licence. Please attach your company\'s trade licence here.',
};
/** The plain sentence a supplier reads when the file in the licence slot is not a licence (suppliers read English, ruling 1008). */
export const wrongDocumentSentence = (kind: unknown): string =>
  WRONG_DOCUMENT_SENTENCE[(NOT_A_LICENCE_KINDS as readonly string[]).includes(String(kind)) ? String(kind) as typeof NOT_A_LICENCE_KINDS[number] : 'other'];
// A FILE THE MODEL DOUBTS IS A LICENCE GOES TO A PERSON (12 Nov 2026, second review of #1985, W1). Since the model fills every printed
// field whatever it thinks the file is, a chamber of commerce membership certificate came back kind 'certificate' (high) WITH a number,
// an authority ("Dubai Chamber of Commerce and Industry"), the name and an expiry: rule (ii) let it through, it was stored as the
// licence, and production's fn_licence_authority_class answers 'uae' for the chambers, so the gate could approve him on it. THE THREE
// OUTCOMES OF ONE ANSWER, here and nowhere else (licenceJudgementOf):
//   (i)   'licence'          the kind is trade_licence or unreadable, the field is absent (an older or fallback model), or the model's
//                            doubt is 'low': today's flow, the reading is the reading;
//   (ii)  'wrong_document'   a non-licence kind, 'high', and no authority and no expiry read (wrongDocumentOf): he is told which file
//                            it is and asked for his licence;
//   (iii) 'held_for_person'  a non-licence kind at 'high' with an authority or an expiry read, or at 'medium' whatever was read: the
//                            model itself doubts this is a licence, so NOTHING of it is a licence reading and it can never be approved
//                            by code; because it may be a real but unusual licence, he is not told "wrong document" either. He is told
//                            the truth (HELD_FOR_PERSON_SENTENCE) and a person is asked to look at once (licence_read_state.ts
//                            holdLicenceForPerson). What the model read is kept for that person, never on the row.
export const HELD_FOR_PERSON_SENTENCE = 'We could not confirm that this is a trade licence. If it is another document (such as a chamber of commerce or VAT certificate), please attach your trade licence here. If it is your trade licence, you do not need to do anything: one of our team will check it and confirm.';
export type HeldForPerson = { kind: typeof NOT_A_LICENCE_KINDS[number]; why: string; message: string;
  read: { license_number: string; license_authority: string; expiry_date: string; issue_date: string; legal_name: string } };
export type LicenceJudgement = { outcome: 'licence' } | { outcome: 'wrong_document'; wrong: WrongDocument } | { outcome: 'held_for_person'; held: HeldForPerson };
// THE KIND AND THE DOUBT ARE READ IN THEIR NORMAL FORM (third review of #1985, F3): no response schema holds the model to the exact
// spelling, so 'High', ' Certificate ', 'Company Profile', 'Trade Licence' or 'trade_license' are read as 'high', 'certificate',
// 'company_profile' and 'trade_licence'. Anything still unknown (a missing field, null, a new word) keeps the safe default:
// the existing flow, so a real licence is never refused on a malformed answer.
const LICENCE_KIND_SPELLINGS = new Set(['trade_licence', 'trade_license', 'licence', 'license', 'commercial_licence', 'commercial_license']);
export const normalKind = (v: unknown): string => {
  if (v == null) return '';
  const k = String(v).trim().toLowerCase().replace(/[\s-]+/g, '_');   // String(): an array kind reads as before (['certificate'] held)
  return LICENCE_KIND_SPELLINGS.has(k) ? 'trade_licence' : k;
};
export const normalDoubt = (v: unknown): string => (v == null ? '' : String(v).trim().toLowerCase());
export function licenceJudgementOf(ai: Record<string, unknown> | null | undefined): LicenceJudgement {
  const wrong = wrongDocumentOf(ai);
  if (wrong) return { outcome: 'wrong_document', wrong };
  if (!ai) return { outcome: 'licence' };
  const kind = normalKind(ai.document_kind), conf = normalDoubt(ai.document_kind_confidence);
  if (!(NOT_A_LICENCE_KINDS as readonly string[]).includes(kind) || !['high', 'medium'].includes(conf)) return { outcome: 'licence' };
  const v = (x: unknown) => String(x ?? '').trim().slice(0, 200);
  return { outcome: 'held_for_person', held: { kind: kind as HeldForPerson['kind'], why: v(ai.document_kind_why).slice(0, 300), message: HELD_FOR_PERSON_SENTENCE,
    read: { license_number: v(ai.license_number), license_authority: v(ai.license_authority), expiry_date: v(ai.expiry_date), issue_date: v(ai.issue_date), legal_name: v(ai.legal_name) } } };
}
/** The model's raw answer -> a wrong document, or null (the existing flow). Outcome (ii) of licenceJudgementOf; see the header above. */
export function wrongDocumentOf(ai: Record<string, unknown> | null | undefined): WrongDocument | null {
  if (!ai) return null;
  const kind = normalKind(ai.document_kind);
  if (!(NOT_A_LICENCE_KINDS as readonly string[]).includes(kind)) return null;
  if (normalDoubt(ai.document_kind_confidence) !== 'high') return null;
  const read = (v: unknown) => String(v ?? '').trim() !== '';
  if (read(ai.license_authority) || read(ai.expiry_date)) return null;
  return { kind: kind as WrongDocument['kind'], why: String(ai.document_kind_why ?? '').trim().slice(0, 300), message: wrongDocumentSentence(kind) };
}
export function checkLicenceRead<T extends { license_number: string; issue_date: string | null; expiry_date: string | null; legal_name?: string; legal_name_ar?: string }>(doc: T, text: string | null): { doc: T; check: LicenceCheck } {
  const out = { ...doc }; const failed: string[] = []; const notes: string[] = [];
  const t = String(text ?? '');
  const tk = lettersKey(t);
  const named = [doc.legal_name, doc.legal_name_ar].some((n) => lettersKey(String(n ?? '')).length >= 6 && tk.includes(lettersKey(String(n))));
  const grounded = !!t.trim() && (numberPrintedIn(doc.license_number, t) || named);
  if (grounded) {
    if (doc.license_number && !numberPrintedIn(doc.license_number, t)) notes.push('license_number_not_in_text_layer');
    const printed = datesPrintedIn(t);
    if (doc.issue_date && !printed.has(doc.issue_date)) notes.push('issue_date_not_in_text_layer');
    if (doc.expiry_date && !printed.has(doc.expiry_date)) notes.push('expiry_date_not_in_text_layer');
  }
  if (out.issue_date && out.expiry_date && out.expiry_date <= out.issue_date) { out.issue_date = null; out.expiry_date = null; failed.push('expiry_not_after_issue'); }
  return { doc: out, check: { failed, notes, grounded } };
}

/** The doc a licence nobody could read yields: no fields at all. */
export const UNREADABLE_LICENCE = () => normaliseLicence({});

/** The model's object -> the licence doc every caller reads.
 *
 * NOTHING UNGROUNDED IS A READING (12 Oct 2026, stage-2 run 3 S02, sales_engineer). A 1x1 PNG went to the
 * vision model and came back with expiry 2023-03-14 and licence number 123456 (ai_cost_log 19449, lead 143063);
 * supplier_api wrote both and the review held the supplier as licence_expired off a date no document printed.
 * Every UAE licence prints the licensee's name, so a read with no name in either language saw no licence: it
 * yields NO fields at all (unreadable: true) and callers write nothing. A 'low' read is unreadable too UNLESS it
 * carries the Arabic name: SYS_LICENSE tells the model to leave legal_name empty and lower the confidence when a
 * licence prints no English name, so an Arabic-only licence is always 'low' (13 Oct 2026, stage-2 run 4 S21,
 * lic_ajman_ded_ar_png lost 20840 / 2027-04-12 to the first version of this guard).
 * A placeholder number (123456, 000000) is dropped even from an otherwise named read. */
export function normaliseLicence(ai: Record<string, unknown>) {
  const s = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
  // A LICENCE THAT PRINTS ITS NAME ONLY AS A TRADE NAME IS NAMED (28 Oct 2026, sales_engineer, the supplier-journey audit,
  // ledger 1401). Measured on production: a licence whose one name line reads "Trade Name" came back from the model with
  // every field read (number, authority, issue and expiry dates, activities), confidence 'medium', the name in trade_name
  // and legal_name '' (correctly: the page prints no other name). The check below then threw the whole read away as
  // unreadable, so the supplier was held as licence_unreadable and told to upload "a clearer copy" of a clear licence.
  // The same licence with its name line labelled "Company Name" read in full, confidence 'high'. When no legal name is
  // printed, the trade name IS the licensed name; the code reader already takes it so (document_expiry.ts, NAME_LABELS).
  // REVIEW OF #1711 (28 Oct 2026): ONLY AN ENGLISH TRADE NAME, AND ONLY ON A 'medium' OR 'high' READ. The first version
  // took any trade name, in any script, at any confidence. Replayed through it, the model's own recorded answers for the
  // corpus's two Arabic-only licences (docs/reports/.../run-arabic-name-gateway: lic_ajman_ded_ar_png and
  // lic_fujairah_ded_ar_jpg, trade_name = legal_name_ar = the Arabic name) put the Arabic name in legal_name, which every
  // upload path writes to leads.licence_legal_name through licenceNameFromModel; the review (ruling 1176) then renamed the
  // supplier's company in Arabic and could approve it, where it held the name for a person (corpus: 'hold_name'). And an
  // Arabic-only read 'low' (stage-2 run 4 S21, the arabicOnly rule below) became unreadable and lost its number and
  // expiry, because its Arabic trade name made it no longer "Arabic-only". legal_name is the ENGLISH name (SYS_LICENSE),
  // so the trade name stands in only when it is written in Latin letters with no Arabic letter in it (an English name,
  // as mergeLicenceReads and licenceFieldsFromText read one: "النور للمقاولات LLC" is not), and a read that is not
  // 'medium' or 'high' normalises exactly as it did before the fallback existed.
  // A file the model says is not a licence carries no licence fields, whatever it printed (licenceJudgementOf, the one rule): a sure
  // wrong document is named; one the model doubts is held for a person, with what it read kept apart for that person.
  const judged = licenceJudgementOf(ai);
  if (judged.outcome !== 'licence') {
    return { legal_name: '', legal_name_ar: '', trade_name: '', legal_form: '', license_number: '', license_authority: '', emirate: '',
             city: '', issue_date: null as string | null, expiry_date: null as string | null, activities: [] as string[], trn: '',
             confidence: 'low', unreadable: true, wrong_document: (judged.outcome === 'wrong_document' ? judged.wrong : null) as WrongDocument | null,
             held_for_person: (judged.outcome === 'held_for_person' ? judged.held : null) as HeldForPerson | null };
  }
  const en = s(ai.legal_name, 200), trade = s(ai.trade_name, 200);
  const sure = ['medium', 'high'].includes(String(ai.confidence));
  const englishTrade = /\p{Script=Latin}{2}/u.test(trade) && !/\p{Script=Arabic}/u.test(trade);
  const legal = !/\p{L}{2}/u.test(en) && sure && englishTrade ? trade : en;
  const named = /\p{L}{2}/u.test(legal) || /\p{L}{2}/u.test(s(ai.legal_name_ar, 200));
  const arabicOnly = !/\p{L}{2}/u.test(en) && /\p{Script=Arabic}{2}/u.test(s(ai.legal_name_ar, 200));
  if (!named || (String(ai.confidence) === 'low' && !arabicOnly)) {
    return { legal_name: '', legal_name_ar: '', trade_name: '', legal_form: '', license_number: '', license_authority: '', emirate: '',
             city: '', issue_date: null as string | null, expiry_date: null as string | null, activities: [] as string[], trn: '',
             confidence: 'low', unreadable: true, wrong_document: null as WrongDocument | null, held_for_person: null as HeldForPerson | null };
  }
  const emirate = normEmirate(ai.emirate || ai.city);
  return {
    legal_name: legal, legal_name_ar: s(ai.legal_name_ar, 200), trade_name: s(ai.trade_name, 200), legal_form: s(ai.legal_form, 120),
    license_number: placeholderLicenceNo(ai.license_number) ? '' : s(ai.license_number, 60), license_authority: s(ai.license_authority, 160), emirate,
    city: s(ai.city || ai.emirate, 80) || emirate, issue_date: normDate(ai.issue_date), expiry_date: normDate(ai.expiry_date),
    activities: Array.isArray(ai.activities) ? ai.activities.map((x) => String(x).slice(0, 120)).slice(0, 20) : [],
    trn: String(ai.trn || '').replace(/\D/g, '').slice(0, 15),
    confidence: ['low', 'medium', 'high'].includes(String(ai.confidence)) ? String(ai.confidence) : 'low', unreadable: false,
    wrong_document: null as WrongDocument | null, held_for_person: null as HeldForPerson | null,
  };
}

/** A gateway answer -> { ok, doc } or { ok:false, error } exactly as license_extract answers its callers. */
// deno-lint-ignore no-explicit-any
export function licenceFromGateway(httpOk: boolean, jd: any): { ok: true; doc: ReturnType<typeof normaliseLicence> } | { ok: false; error: string; detail?: string } {
  if (!httpOk || jd?.ok === false) return { ok: false, error: 'ai_error', detail: String(jd?.detail || jd?.error || JSON.stringify(jd)).slice(0, 300) };
  if (jd?.truncated === true || jd?.finish_reason === 'length') return { ok: false, error: 'extract_truncated' };
  const parsed = parseJson(String(jd?.content ?? ''));
  if (!parsed) return { ok: false, error: 'extract_unreadable' };
  return { ok: true, doc: normaliseLicence(parsed) };
}
