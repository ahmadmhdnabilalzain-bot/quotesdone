// PDF text, and readExpiry over it (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { type ExpiryRead } from './dates.ts';
import { expiryFromText } from './expiry_text.ts';

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
// ONE READ OF A PDF PER UPLOAD, AND A NATIVE DECODE (28 Oct 2026, sales_engineer; production size measurement).
// A scanner-style licence of 14.50 MB and one of 19.33 MB ended supplier_portal save_documents and supplier_api
// process_docs at the edge's CPU cap (HTTP 546); 9.66 MB passed. Measured locally on the 19.33 MB file: the whole-file
// latin1() above (String.fromCharCode over 32 KB slices) took 810 ms of the 1,044 ms pdfText spent, and each upload ran
// pdfText three times (readExpiry, readLicenceName, readLicenceFields on the same bytes). The whole-file view is now
// decoded natively (TextDecoder 'latin1', which the WHATWG Encoding standard maps to windows-1252: one character per
// byte, so every offset still indexes `bytes`, and only ASCII - the dictionaries and `stream`/`endstream` - is read
// from it); a content stream's own text still goes through latin1(), unchanged. And the text is kept per bytes object,
// so the three readers share one pass.
const TEXT_OF = new WeakMap<Uint8Array, Promise<string | null>>();
export function pdfText(bytes: Uint8Array): Promise<string | null> {
  let p = TEXT_OF.get(bytes);
  if (!p) { p = readPdfText(bytes).then((t) => readable(t) ? t : pdfjsFallback(bytes, t)); TEXT_OF.set(bytes, p); }
  return p;
}
// A TEXT LICENCE WRITTEN WITH AN EMBEDDED FONT (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). The reader
// below decodes a string one byte per character, which is right for the Standard-14 fonts and wrong for a Type0 / Identity-H font
// (two-byte glyph ids, mapped to letters only by the font's ToUnicode CMap) - the way most generators write a PDF today. Such a
// licence, English or Arabic, read as control characters: 1 of 8 fields, and a supplier with a perfectly readable licence was sent
// to the model or held. When this reader's text is not readable words, pdf.js (doc_read/pdf.ts, which applies ToUnicode) reads the
// file instead; its text is taken when it holds more letters. Never a guess: both are the file's own text layer.
const lettersOf = (t: string | null) => (t ?? '').replace(/[^\p{L}]/gu, '').length;
const readable = (t: string | null) => !!t && lettersOf(t) >= 0.5 * t.replace(/\s/g, '').length;
async function pdfjsFallback(bytes: Uint8Array, own: string | null): Promise<string | null> {
  try {
    const { pdfjsText } = await import('../doc_read/pdf.ts');
    const r = await pdfjsText(bytes, 20);
    return r.status === 'text' && lettersOf(r.text) > lettersOf(own) ? r.text : own;
  } catch { return own; }
}
async function readPdfText(bytes: Uint8Array): Promise<string | null> {
  const raw = new TextDecoder('latin1').decode(bytes);
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
    // AN IMAGE IS NEVER INFLATED TO LOOK FOR TEXT (28 Oct 2026, sales_engineer; supplier-journey audit, run fceb5876).
    // A 686 kB scan saved from a browser (one 2483x3265 RGB image and its soft mask, both FlateDecode) ended
    // supplier_portal save_documents at the edge's CPU cap (HTTP 546, "CPU Time exceeded", 08:40:31Z), and the platform's
    // own error sentence reached the supplier. Each read inflated 32 MB of pixels and copied them into a string to look
    // for text operators an image cannot hold: 4.3 s for the three readers of one upload, measured locally. An image
    // XObject (and its /SMask, also an image) is skipped before it is inflated; the page's content streams are read as before.
    // Only the stream's OWN dictionary is asked, here and by the two filter tests below (review of #1726, 28 Oct 2026). The match above starts at the first `<<`
    // after the previous stream, so `dict` can begin in an earlier object; a text stream that followed any object naming
    // `/Subtype /Image` (or an image whose `stream` keyword ends in a lone CR, so its match ran on into the next stream)
    // was skipped and its licence text lost. What follows the span's last `N G obj` header is this stream's dictionary.
    const heads = [...dict.matchAll(/\d+\s+\d+\s+obj\b/g)];
    const own = heads.length ? dict.slice(heads[heads.length - 1].index) : dict;
    if (/\/Subtype\s*\/Image\b/.test(own)) { re.lastIndex = end; continue; }
    if (/\/FlateDecode/.test(own)) { const inf = await inflate(body); if (!inf) { re.lastIndex = end; continue; } body = inf; }
    else if (/\/Filter/.test(own)) { re.lastIndex = end; continue; }   // LZW / DCT (an image) — not text
    const content = latin1(body);
    if (/\bTj\b|\bTJ\b/.test(content)) chunks.push(textFromContent(content));
    re.lastIndex = end;
  }
  const text = chunks.join('\n').trim();
  return text ? text : null;
}

/** The one call the upload paths make: bytes in, a read expiry or null out. Images return null (no OCR here). */
export async function readExpiry(bytes: Uint8Array, mime: string): Promise<ExpiryRead | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? expiryFromText(text) : null;
}
