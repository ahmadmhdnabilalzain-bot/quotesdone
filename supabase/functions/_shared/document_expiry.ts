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
  const re = /\(((?:\\.|[^\\)])*)\)\s*Tj|\[((?:[^\]\\]|\\.)*)\]\s*TJ|<([0-9A-Fa-f\s]+)>\s*Tj|\b(T\*|Td\b|TD\b|ET\b)/g;
  // 24 Sep 2026: `T*` then a trailing \b never matched (no word boundary after '*'), so a licence laid out
  // with T* read as ONE line and "Legal Name : X" swallowed the rest of the page. Measured by the
  // readLicenceName test below the fix.
  let m: RegExpExecArray | null;
  while ((m = re.exec(content))) {
    if (m[1] !== undefined) out.push(unescapePdf(m[1]));
    else if (m[2] !== undefined) {
      const parts: string[] = [];
      const inner = /\(((?:\\.|[^\\)])*)\)|<([0-9A-Fa-f\s]+)>|(-?\d+(?:\.\d+)?)/g;
      let p: RegExpExecArray | null;
      while ((p = inner.exec(m[2]))) {
        if (p[1] !== undefined) parts.push(unescapePdf(p[1]));
        else if (p[2] !== undefined) parts.push(hexString(p[2]));
        else if (Number(p[3]) < -200) parts.push(' ');   // a large negative kern is a word gap
      }
      out.push(parts.join(''));
    }
    else if (m[3] !== undefined) out.push(hexString(m[3]));
    else out.push('\n');
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
const NAME_LABELS = ['legal name', 'company name', 'name of company', 'name of the company', 'trade name',
  'الاسم القانوني', 'اسم الشركة', 'الاسم التجاري'];
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

/** The one call the upload paths make: bytes in, a read expiry or null out. Images return null (no OCR here). */
export async function readExpiry(bytes: Uint8Array, mime: string): Promise<ExpiryRead | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? expiryFromText(text) : null;
}
