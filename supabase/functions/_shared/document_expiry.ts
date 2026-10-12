// document_expiry — read an expiry date OFF a document by code, before any model is asked.
//
// Founder instruction 524 (21 Sep 2026): expiry dates were typed by hand in the supplier portal
// Documents tab while license_extract existed to read them — and license_extract runs through
// ai_gateway, which the OpenRouter hold keeps closed. This is the deterministic first attempt:
//   1. pdfText(bytes): the strings a PDF's content streams draw (Tj / TJ operators), inflating
//      FlateDecode streams with the runtime's DecompressionStream. No dependency.
//   2. expiryFromText(text): a date within 90 characters AFTER an expiry keyword, English or
//      Arabic. A date with no keyword beside it is NOT an expiry — an issue date, a policy start,
//      a print date all look the same — so nothing is returned and the caller says it could not
//      read the document. NEVER a guess: a wrong expiry either suspends a valid supplier or lets a
//      lapsed one keep trading.
//
// CEILING, measured against scripts/staging/fixtures/licence_pdf.mjs (Helvetica, WinAnsi, plain
// content stream): every field reads. A scanned licence (image-only PDF or a photo) has no text
// stream and returns null — there is no OCR here; the browser-side tesseract (src/components/me/
// ocrClient.ts) is a customer-portal tool and was not moved. A PDF whose fonts use a CID/Identity
// encoding draws two-byte glyph ids, not characters; those come out as noise and, because no
// keyword matches noise, the answer is null rather than wrong. That is the honest direction.
// ponytail: text-stream PDFs only; add pdf.js-in-Deno or server OCR when a measured share of real
// uploads is scanned.

export type ExpiryRead = { expiry: string; source: 'text'; keyword: string; raw: string };

const MONTHS: Record<string, number> = {
  jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3, apr: 4, april: 4, may: 5, jun: 6, june: 6,
  jul: 7, july: 7, aug: 8, august: 8, sep: 9, sept: 9, september: 9, oct: 10, october: 10, nov: 11, november: 11, dec: 12, december: 12,
};

// Keywords first, then the date. Order inside the alternation does not matter: the FIRST keyword
// occurrence in the text wins, and only a date after it counts.
const KEYWORDS = [
  'expiry date', 'expiry', 'expires on', 'expires', 'expiration date', 'expiration', 'date of expiry',
  'valid until', 'valid till', 'valid to', 'valid upto', 'valid up to', 'validity', 'period of insurance',
  'تاريخ الانتهاء', 'تاريخ انتهاء', 'الانتهاء', 'ينتهي في', 'ينتهي', 'صالحة حتى', 'صالح حتى', 'سارية حتى', 'ساري حتى', 'صلاحية',
];
const KEYWORD_RE = new RegExp('(' + KEYWORDS.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')', 'i');

// The date shapes a UAE licence or certificate prints: 13/03/2027, 13-03-2027, 2027-03-13,
// 13 Mar 2027, 13-MAR-2027, 13 March 2027, March 13, 2027. Two-digit years are not accepted.
const DATE_RE = /(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})|(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})|(\d{1,2})[ \-]([A-Za-z]{3,9})[ \-,]+(\d{4})|([A-Za-z]{3,9})[ \-]+(\d{1,2}),?[ \-]+(\d{4})/;

function ymd(y: number, m: number, d: number): string | null {
  if (!(y >= 2000 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31)) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;   // 31/02 is not a date
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** Normalise one printed date to YYYY-MM-DD, or null when it is not one. Day-first for numeric forms (UAE). */
export function parseDate(raw: string): string | null {
  const m = DATE_RE.exec(raw);
  if (!m) return null;
  if (m[1]) return ymd(+m[1], +m[2], +m[3]);
  if (m[4]) return ymd(+m[6], +m[5], +m[4]);
  if (m[7]) { const mo = MONTHS[m[8].toLowerCase()]; return mo ? ymd(+m[9], mo, +m[7]) : null; }
  if (m[10]) { const mo = MONTHS[m[10].toLowerCase()]; return mo ? ymd(+m[12], mo, +m[11]) : null; }
  return null;
}

/** The expiry a document states, or null. Only a date that follows an expiry keyword within 90 characters counts. */
export function expiryFromText(text: string): ExpiryRead | null {
  const t = String(text || '').replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x0660)); // Arabic-Indic digits
  let from = 0;
  for (let i = 0; i < 20; i++) {
    const km = KEYWORD_RE.exec(t.slice(from));
    if (!km) return null;
    const at = from + (km.index ?? 0) + km[0].length;
    const window = t.slice(at, at + 90);
    const dm = DATE_RE.exec(window);
    if (dm) {
      const expiry = parseDate(dm[0]);
      if (expiry) return { expiry, source: 'text', keyword: km[0], raw: dm[0] };
    }
    from = at;   // this keyword had no date beside it ("valid until the expiry date shown above") — try the next
  }
  return null;
}

// ── PDF text ─────────────────────────────────────────────────────────────────────────────────────
const latin1 = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000)); return s; };

async function inflate(bytes: Uint8Array): Promise<Uint8Array | null> {
  for (const fmt of ['deflate', 'deflate-raw'] as const) {
    try {
      const ds = new DecompressionStream(fmt);
      const out = new Response(new Blob([bytes as BlobPart]).stream().pipeThrough(ds));
      return new Uint8Array(await out.arrayBuffer());
    } catch { /* try the other framing */ }
  }
  return null;
}

function unescapePdf(s: string): string {
  return s.replace(/\\([nrtbf()\\]|[0-7]{1,3})/g, (_, c: string) => {
    if (/^[0-7]+$/.test(c)) return String.fromCharCode(parseInt(c, 8));
    return ({ n: '\n', r: '\r', t: '\t', b: '\b', f: '\f' } as Record<string, string>)[c] ?? c;
  });
}

/** Strings drawn by one content stream, in drawing order; a text-position operator becomes a newline. */
export function textFromContent(content: string): string {
  const out: string[] = [];
  // (...) Tj  |  [ (...) -250 (...) ] TJ  |  <hex> Tj  |  T* / Td / TD / ET → newline
  const re = /\(((?:\\.|[^\\)])*)\)\s*Tj|\[((?:[^\]\\]|\\.)*)\]\s*TJ|<([0-9A-Fa-f\s]+)>\s*Tj|(?:-?[\d.]+\s+){5}(-?[\d.]+)\s+Tm\b|-?[\d.]+\s+(-?[\d.]+)\s+T[dD]\b|(T\*|ET\b)/g;
  // 28 Sep 2026 (sales_engineer): a PDF that places every line with its own `Tm` (the registration walk's
  // licence fixture, and many generators) also read as ONE line, so the line-anchored name label never
  // matched and every such licence was held as licence_name_unread. `Tm` now breaks the line too.
  // 7 Oct 2026 (sales_engineer, accuracy suite, ledger 1162): ...but only when it moves to ANOTHER line. A licence
  // laid out as a two-column table places each label and its value with their own Tm (or their own BT..ET) on
  // the SAME baseline; breaking there put "Legal Name" and its value on different lines, and every table-layout
  // licence of scripts/e2e/document_intake_corpus.mjs (DET, ADGM, SEDD, RAKEZ, JAFZA, DAFZA, IFZA, SHAMS) was
  // held as licence_unreadable with its name printed in plain text. A placement that keeps the baseline
  // (|dy| < 2pt) is now a space, and ET ends the line only if the next placement leaves it.
  // 24 Sep 2026: `T*` then a trailing \b never matched (no word boundary after '*'), so a licence laid out
  // with T* read as ONE line and "Legal Name : X" swallowed the rest of the page. Measured by the
  // readLicenceName test below the fix.
  let m: RegExpExecArray | null;
  let y: number | null = null;   // the baseline being written, from Tm (absolute) and Td (relative)
  let ended = false;             // an ET: the line ends unless the next placement keeps the baseline
  const brk = () => { out.push('\n'); ended = false; };
  const push = (s: string) => { if (ended) brk(); out.push(s); };
  while ((m = re.exec(content))) {
    if (m[4] !== undefined) {                                   // Tm
      const ny = Number(m[4]);
      if (y !== null && Math.abs(ny - y) < 2) { ended = false; out.push(' '); } else brk();
      y = ny; continue;
    }
    if (m[5] !== undefined) {                                   // Td / TD
      const dy = Number(m[5]);
      if (Math.abs(dy) < 2) { ended = false; out.push(' '); } else brk();
      if (y !== null) y += dy; continue;
    }
    if (m[6] === 'ET') { ended = true; continue; }
    if (m[6] !== undefined) { brk(); continue; }                // T*
    if (m[1] !== undefined) push(unescapePdf(m[1]));
    else if (m[2] !== undefined) {
      const parts: string[] = [];
      const inner = /\(((?:\\.|[^\\)])*)\)|<([0-9A-Fa-f\s]+)>|(-?\d+(?:\.\d+)?)/g;
      let p: RegExpExecArray | null;
      while ((p = inner.exec(m[2]))) {
        if (p[1] !== undefined) parts.push(unescapePdf(p[1]));
        else if (p[2] !== undefined) parts.push(hexString(p[2]));
        else if (Number(p[3]) < -200) parts.push(' ');   // a large negative kern is a word gap
      }
      push(parts.join(''));
    }
    else if (m[3] !== undefined) push(hexString(m[3]));
  }
  return out.join(' ').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n');
}
const hexString = (h: string) => { const clean = h.replace(/\s+/g, ''); let s = ''; for (let i = 0; i + 1 < clean.length; i += 2) s += String.fromCharCode(parseInt(clean.slice(i, i + 2), 16)); return s; };

/** All text the PDF's content streams draw, or null when the bytes are not a PDF / draw no text. */
export async function pdfText(bytes: Uint8Array): Promise<string | null> {
  const raw = latin1(bytes);
  if (!raw.startsWith('%PDF')) return null;
  const chunks: string[] = [];
  const re = /(<<[\s\S]*?>>)\s*stream\r?\n/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw))) {
    const start = m.index + m[0].length;
    const end = raw.indexOf('endstream', start);
    if (end < 0) break;
    const dict = m[1];
    // The EOL before `endstream` is not stream data; DecompressionStream refuses bytes after the
    // deflate trailer ("junk after end"), so it is trimmed before inflating.
    let bodyEnd = end;
    while (bodyEnd > start && (bytes[bodyEnd - 1] === 0x0a || bytes[bodyEnd - 1] === 0x0d)) bodyEnd--;
    let body = bytes.subarray(start, bodyEnd);
    if (/\/FlateDecode/.test(dict)) { const inf = await inflate(body); if (!inf) { re.lastIndex = end; continue; } body = inf; }
    else if (/\/Filter/.test(dict)) { re.lastIndex = end; continue; }   // LZW / DCT (an image) — not text
    const content = latin1(body);
    if (/\bTj\b|\bTJ\b/.test(content)) chunks.push(textFromContent(content));
    re.lastIndex = end;
  }
  const text = chunks.join('\n').trim();
  return text ? text : null;
}

// THE NAME A LICENCE PRINTS (24 Sep 2026, sales_engineer). The review compares it with the registered
// company name (fn_supplier_licence_name_mismatch). Read the same way as the expiry: a value on the SAME
// line as a name label, nothing inferred. Legal name is preferred over trade name, which a UAE licence
// may print without the legal form. No label = null ("not read"), never a guess.
// 7 Oct 2026 (accuracy suite): an Ajman sole establishment prints "Establishment Name"; with no label for it the
// reader fell through to "Trade Name" and recorded the trade name as the licence's name.
const LEGAL_NAME_LABELS = ['legal name', 'company name', 'name of company', 'name of the company', 'establishment name', 'name of establishment',
  'الاسم القانوني', 'اسم الشركة', 'اسم المؤسسة'];
const TRADE_NAME_LABELS = ['trade name', 'trading name', 'الاسم التجاري'];
const NAME_LABELS = [...LEGAL_NAME_LABELS, ...TRADE_NAME_LABELS];
export function licenceNameFromText(text: string): string | null {
  for (const label of NAME_LABELS) {
    const re = new RegExp('^[ \\t]*' + label + '[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'im');
    const v = re.exec(String(text || ''))?.[1]?.trim().slice(0, 200);
    if (v && /\p{L}{2}/u.test(v)) return v;
  }
  return null;
}
/** The licence's printed company name from a text-layer PDF, or null. Images return null (no OCR). */
export async function readLicenceName(bytes: Uint8Array, mime: string): Promise<string | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? licenceNameFromText(text) : null;
}

// EVERY FIELD A LICENCE PRINTS, READ BY CODE (7 Oct 2026, sales_engineer; founder gate ledger 1162: "not a single
// mistake in any trade licence"). Measured before this on the 50-licence synthetic corpus of
// scripts/e2e/document_intake_accuracy.mjs: code read the name and the expiry only, so the licence number, the
// issuing authority, the legal form, the issue date, the emirate and the activities of a text licence were read by
// nothing at all (process_docs's model switch is off), and trades were proposed from the company's NAME line
// ("Horizon Floor LLC" -> floor cleaners) instead of its licensed activities. Same rule as the name: a value is
// taken only from the same line as its label; no label, no value. Labels are each authority's own vocabulary.
export type LicenceFields = {
  licence_no: string | null; legal_name_en: string | null; trade_name: string | null; legal_form: string | null;
  authority: string | null; emirate: string | null; issue_date: string | null; expiry_date: string | null; activities: string[] | null;
  legal_name_ar: string | null;
};
const LABELS: Record<'licence_no' | 'legal_form' | 'authority' | 'emirate' | 'issue_date' | 'activities', string[]> = {
  licence_no: ['trade licence number', 'trade license number', 'trade licence no', 'trade license no', 'commercial licence no', 'commercial license no',
    'licence number', 'license number', 'licence no', 'license no', 'registered number', 'registration number', 'registration no', 'رقم الرخصة'],
  legal_form: ['legal form', 'legal type', 'legal status', 'company type', 'الشكل القانوني'],
  authority: ['issuing authority', 'licensing authority', 'issued by', 'جهة الإصدار'],
  emirate: ['emirate', 'الإمارة'],
  issue_date: ['issue date', 'date of issue', 'issued on', 'تاريخ الإصدار'],
  activities: ['business activities', 'licensed activities', 'activities', 'activity', 'الأنشطة', 'النشاط'],
};
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** The value on the same line as the first label that has one. A label is a whole word: "Licence No" never reads "Licence Number". */
function labelled(text: string, labels: string[]): string | null {
  for (const label of labels) {
    const re = new RegExp('^[ \\t]*' + esc(label) + '(?![\\p{L}])\\.?[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'imu');
    const v = re.exec(text)?.[1]?.trim().slice(0, 300);
    if (v && /[\p{L}\p{N}]/u.test(v)) return v;
  }
  return null;
}
const EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
const EMIRATE_AR: Record<string, string> = { 'دبي': 'Dubai', 'أبوظبي': 'Abu Dhabi', 'ابوظبي': 'Abu Dhabi', 'الشارقة': 'Sharjah', 'عجمان': 'Ajman', 'أم القيوين': 'Umm Al Quwain', 'رأس الخيمة': 'Ras Al Khaimah', 'الفجيرة': 'Fujairah' };
export function emirateOf(s: string | null | undefined): string | null {
  const t = String(s ?? '');
  for (const e of EMIRATES) if (new RegExp('\\b' + e + '\\b', 'i').test(t)) return e;
  for (const [ar, e] of Object.entries(EMIRATE_AR)) if (t.includes(ar)) return e;
  return null;
}
// Where a licence prints no emirate (most free zones), the issuing authority decides it: each of these is in one emirate.
const AUTHORITY_EMIRATE: [RegExp, string][] = [
  [/abu dhabi global market|\badgm\b/i, 'Abu Dhabi'], [/ras al khaimah|\brakez\b/i, 'Ras Al Khaimah'], [/sharjah|\bshams\b|\bsaif\b|hamriyah/i, 'Sharjah'],
  [/jebel ali|\bjafza\b|multi commodities|\bdmcc\b|airport free ?zone|\bdafza\b|silicon oasis|\bdso\b|international free zone|\bifza\b|meydan|international financial centre|\bdifc\b|economy and tourism|dubai/i, 'Dubai'],
  [/abu dhabi/i, 'Abu Dhabi'], [/ajman/i, 'Ajman'], [/umm al quwain/i, 'Umm Al Quwain'], [/fujairah/i, 'Fujairah'],
];
export function emirateOfAuthority(a: string | null | undefined): string | null {
  for (const [re, e] of AUTHORITY_EMIRATE) if (re.test(String(a ?? ''))) return e;
  return null;
}
export function licenceFieldsFromText(text: string): LicenceFields {
  const t = String(text || '');
  const noRaw = labelled(t, LABELS.licence_no);
  const licence_no = noRaw ? (/[A-Z0-9][A-Z0-9\-/.]*\d[A-Z0-9\-/.]*/i.exec(noRaw)?.[0].replace(/[.\-/]+$/, '') ?? null) : null;
  const legal = labelled(t, LEGAL_NAME_LABELS);
  const authority = labelled(t, LABELS.authority);
  const emirateRaw = labelled(t, LABELS.emirate);
  const issueRaw = labelled(t, LABELS.issue_date);
  const acts = labelled(t, LABELS.activities);
  const name = legal && /\p{L}{2}/u.test(legal) ? legal : null;
  return {
    licence_no, legal_name_en: name && !/[؀-ۿ]/.test(name) ? name : null,
    legal_name_ar: name && /[؀-ۿ]/.test(name) ? name : null,
    trade_name: labelled(t, TRADE_NAME_LABELS), legal_form: labelled(t, LABELS.legal_form), authority,
    emirate: emirateOf(emirateRaw) ?? emirateOfAuthority(authority),
    issue_date: issueRaw ? parseDate(issueRaw) : null, expiry_date: expiryFromText(t)?.expiry ?? null,
    activities: acts ? acts.split(/[,،;؛]/).map((a) => a.trim()).filter((a) => a.length >= 3) : null,
  };
}
const NO_FIELDS: LicenceFields = { licence_no: null, legal_name_en: null, legal_name_ar: null, trade_name: null, legal_form: null, authority: null, emirate: null, issue_date: null, expiry_date: null, activities: null };
/** A licence file's fields by code; an image or a PDF with no text layer reads as all null ("not read"). */
export async function readLicenceFields(bytes: Uint8Array, mime: string): Promise<LicenceFields> {
  if (!/pdf/i.test(mime)) return { ...NO_FIELDS };
  const text = await pdfText(bytes);
  return text ? licenceFieldsFromText(text) : { ...NO_FIELDS };
}
/** The model is asked whenever code left one of the three fields the gate stands on unread. */
export const licenceNeedsModel = (c: Partial<LicenceFields> | null | undefined) => !c?.legal_name_en || !c?.licence_no || !c?.expiry_date;

/**
 * CODE FIRST, THE MODEL ONLY WHERE CODE COULD NOT READ (founder: "code first, LLM only where code can't"). One rule,
 * used by supplier_api.process_docs and by the accuracy suite, so what is measured is what runs. A field code read
 * is never overwritten by the model. The model's name counts only when it is confident (licenceNameFromModel).
 * `source` says, per field, who read it.
 */
// deno-lint-ignore no-explicit-any
export function mergeLicenceReads(code: Partial<LicenceFields> | null | undefined, model: any): { merged: LicenceFields; source: Record<string, 'code' | 'model'> } {
  const c = { ...NO_FIELDS, ...(code || {}) };
  const m = model || {};
  const conf = m.confidence !== 'low';
  const fromModel: Partial<LicenceFields> = {
    licence_no: String(m.license_number ?? '').trim() || null,
    legal_name_en: conf ? (licenceNameFromModel(m) && !/[؀-ۿ]/.test(String(m.legal_name)) ? licenceNameFromModel(m) : null) : null,
    legal_name_ar: conf ? (String(m.legal_name_ar ?? '').trim() || null) : null,
    trade_name: String(m.trade_name ?? '').trim() || null, legal_form: String(m.legal_form ?? '').trim() || null,
    authority: String(m.license_authority ?? '').trim() || null, emirate: emirateOf(m.emirate) ?? emirateOfAuthority(m.license_authority),
    issue_date: m.issue_date || null, expiry_date: m.expiry_date || null,
    activities: Array.isArray(m.activities) && m.activities.length ? m.activities.map((a: unknown) => String(a).trim()).filter(Boolean) : null,
  };
  const merged = { ...NO_FIELDS }; const source: Record<string, 'code' | 'model'> = {};
  for (const k of Object.keys(NO_FIELDS) as (keyof LicenceFields)[]) {
    const cv = c[k], mv = fromModel[k];
    const has = (v: unknown) => v != null && v !== '' && !(Array.isArray(v) && !v.length);
    // deno-lint-ignore no-explicit-any
    if (has(cv)) { (merged as any)[k] = cv; source[k] = 'code'; } else if (has(mv)) { (merged as any)[k] = mv; source[k] = 'model'; }
  }
  return { merged, source };
}

// A SCANNED LICENCE STILL YIELDS ITS NAME (24 Sep 2026, sales_engineer). Code reads only a text layer, so a
// scan or a photo reaches the name through license_extract (vision, model_policy.document_extraction). These
// two are the whole rule, shared by every upload path (supplier_api, resend_inbound, wa_inbound):
/** The name the model read, or null. A 'low' confidence read (an unreadable scan, or a truncated reply) is not a name. */
export function licenceNameFromModel(doc: { legal_name?: unknown; confidence?: unknown } | null | undefined): string | null {
  if (!doc || doc.confidence === 'low') return null;
  const v = String(doc.legal_name ?? '').trim().slice(0, 200);
  return /\p{L}{2}/u.test(v) ? v : null;
}
function toB64(u8: Uint8Array): string {
  let bin = ''; for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(bin);
}
/** What license_extract is sent: the images or file the request carried; otherwise, when code could not read a
 *  name, the STORED licence (a scan uploaded earlier, or by path). null = nothing to send. */
export function licenceModelPayload(lic: { images?: unknown[]; file_b64?: string; mime?: string; filename?: string },
    stored: { bytes: Uint8Array; mime: string } | null, codeName: string | null) {
  const images = Array.isArray(lic.images) ? lic.images : [];
  if (images.length || lic.file_b64) return { images, file_b64: lic.file_b64, mime: lic.mime, filename: lic.filename };
  if (codeName || !stored?.bytes?.length) return null;
  return /^image\//i.test(stored.mime)
    ? { images: [{ b64: toB64(stored.bytes), mime: stored.mime }], file_b64: undefined, mime: stored.mime, filename: lic.filename }
    : { images: [], file_b64: toB64(stored.bytes), mime: stored.mime || 'application/pdf', filename: lic.filename || 'licence.pdf' };
}

/** The one call the upload paths make: bytes in, a read expiry or null out. Images return null (no OCR here). */
export async function readExpiry(bytes: Uint8Array, mime: string): Promise<ExpiryRead | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? expiryFromText(text) : null;
}
