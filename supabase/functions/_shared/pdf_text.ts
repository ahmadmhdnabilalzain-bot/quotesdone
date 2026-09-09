// pdf_text — DETERMINISTIC extraction of a PDF's text layer (9 Sep 2026).
//
// WHY THIS EXISTS. A receipt forwarded to expenses@mail.quotesdone.com is usually a PDF with an
// empty covering note, so _shared/receipt_parse.ts — which reads the EMAIL BODY — has nothing to
// read and returns null, and the receipt goes to review unbooked. The estate's only other way to
// read a PDF is supabase/functions/extract_text, which posts the file to a model through
// ai_gateway. Every paid route is held, so that path returns nothing today. This module needs no
// model: a PDF written by Stripe, Orb, Apify, GoDaddy or a UAE vendor's accounting package carries
// a real text layer, and the text layer is plain data in the file.
//
// WHAT IT DOES. Walks `stream ... endstream` objects, inflates the FlateDecode ones with the
// platform's own DecompressionStream (no dependency), and reads the text-showing operators —
// `(str) Tj`, `[(a) -250 (b)] TJ`, `(str) '`, `(str) "` and hex `<...> Tj`. Nothing else: no
// layout reconstruction, no font metrics, no glyph mapping.
//
// WHAT IT DOES NOT DO, so nobody assumes otherwise:
//   * No OCR. A scanned or photographed receipt has no text layer and returns ''.
//   * No CID/Identity-H decoding. A subset-embedded font maps bytes through a CMap this module
//     does not read, so its output is glyph indices, not letters. That is the DANGEROUS case —
//     garbage that still contains digits would let parseReceipt read an amount that is not on the
//     receipt — so looksLikeText() refuses any result that is not mostly ordinary prose, and the
//     caller then holds the receipt for review instead of guessing. Never relax that guard.
//   * No encryption. An encrypted PDF returns ''.
// ponytail: single-pass regex over the whole buffer, fine for a one-page receipt; if a 200-page
// statement ever arrives, parse the xref table instead of scanning.

const DEC = new TextDecoder('latin1');   // a content stream is bytes; latin1 is byte-transparent

async function inflate(bytes: Uint8Array, format: 'deflate' | 'deflate-raw'): Promise<Uint8Array | null> {
  try {
    const ds = new DecompressionStream(format);
    const buf = await new Response(new Blob([bytes as BlobPart]).stream().pipeThrough(ds)).arrayBuffer();
    return new Uint8Array(buf);
  } catch { return null; }
}

/** PDF literal-string escapes: \n \r \t \b \f \( \) \\ \ddd, and a backslash-newline continuation. */
function unescapePdfString(s: string): string {
  return s.replace(/\\(?:(\d{1,3})|(\r\n|\n|\r)|(.))/g, (_m, oct, nl, ch) => {
    if (oct) return String.fromCharCode(parseInt(oct, 8) & 0xff);
    if (nl) return '';
    return ({ n: '\n', r: '\n', t: '\t', b: '', f: '\n' } as Record<string, string>)[ch] ?? ch;
  });
}

function hexToString(h: string): string {
  const clean = h.replace(/[^0-9A-Fa-f]/g, '');
  let out = '';
  for (let i = 0; i + 1 < clean.length; i += 2) out += String.fromCharCode(parseInt(clean.slice(i, i + 2), 16));
  if (clean.length % 2) out += String.fromCharCode(parseInt(clean.slice(-1) + '0', 16));
  return out;
}

/**
 * Is this plausibly the document's prose, or is it glyph indices from a font we cannot map?
 * A real receipt is mostly letters, digits, spaces and punctuation. Identity-H output is mostly
 * control bytes and high-plane noise. Refusing the second is what stops a fabricated amount.
 */
export function looksLikeText(s: string): boolean {
  if (s.length < 20) return false;
  let ok = 0, letters = 0;
  for (const c of s) {
    const n = c.codePointAt(0)!;
    if (n === 9 || n === 10 || n === 13 || (n >= 32 && n <= 126)) { ok++; if ((n >= 65 && n <= 90) || (n >= 97 && n <= 122)) letters++; }
  }
  return ok / s.length >= 0.9 && letters / s.length >= 0.2;
}

/** Pull the text-showing operators out of one decoded content stream. */
function textFromContentStream(src: string): string {
  let out = '';
  // (literal) or <hex> followed by a showing operator, or an array for TJ
  // The line-break operators MUST be matched, and `T*` is why this is not written with \b on both
  // sides: `*` is not a word character, so `\bT\*\b` never matches and every line of the document
  // ran together. Glued lines are not cosmetic here — "…AED 100.00VAT (5%)…" defeats \bVAT and
  // \bTRN, so the tax line and the TRN silently disappear from a UAE invoice.
  const re = /\[((?:[^\[\]\\]|\\.)*)\]\s*TJ|\(((?:[^()\\]|\\.|\((?:[^()\\]|\\.)*\))*)\)\s*(?:Tj|'|")|<([0-9A-Fa-f\s]+)>\s*(?:Tj|TJ)|(T\*|\bTd\b|\bTD\b|\bET\b)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    if (m[1] !== undefined) {
      // [(Amount paid) -250 (AED 77.50)] TJ — a kern below -100/1000 em reads as a space
      const inner = /\(((?:[^()\\]|\\.)*)\)|<([0-9A-Fa-f\s]+)>|(-?\d+(?:\.\d+)?)/g;
      let p: RegExpExecArray | null;
      while ((p = inner.exec(m[1])) !== null) {
        if (p[1] !== undefined) out += unescapePdfString(p[1]);
        else if (p[2] !== undefined) out += hexToString(p[2]);
        else if (Number(p[3]) <= -100) out += ' ';
      }
    } else if (m[2] !== undefined) out += unescapePdfString(m[2]);
    else if (m[3] !== undefined) out += hexToString(m[3]);
    else out += '\n';
  }
  return out;
}

/**
 * Returns the PDF's text layer, or '' when there is none we can trust.
 * '' is a real answer — "this receipt cannot be read deterministically" — and the caller must hold
 * the receipt for review rather than fall back to a number from anywhere else.
 */
export async function pdfText(bytes: Uint8Array): Promise<string> {
  if (!bytes || bytes.length < 5) return '';
  const raw = DEC.decode(bytes);
  if (!raw.startsWith('%PDF')) return '';
  if (/\/Encrypt\b/.test(raw)) return '';           // encrypted: no text without the key
  let out = '';
  const re = /stream\r?\n?/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw)) !== null) {
    const start = m.index + m[0].length;
    const end = raw.indexOf('endstream', start);
    if (end < 0) break;
    re.lastIndex = end;
    const dict = raw.slice(Math.max(0, m.index - 400), m.index);
    if (/\/Image\b|\/DCTDecode\b|\/JPXDecode\b/.test(dict)) continue;   // pixels, not prose
    // the EOL that separates the stream data from the `endstream` keyword is NOT stream data, and
    // DecompressionStream rejects a zlib stream with trailing bytes — so trim it before inflating
    let dataEnd = end;
    while (dataEnd > start && (bytes[dataEnd - 1] === 10 || bytes[dataEnd - 1] === 13)) dataEnd--;
    const body = bytes.subarray(start, dataEnd);
    let decoded: Uint8Array | null = null;
    if (/\/FlateDecode\b/.test(dict)) {
      decoded = (await inflate(body, 'deflate'))
             ?? (await inflate(body, 'deflate-raw'))
             ?? (await inflate(bytes.subarray(start, end), 'deflate'));
    }
    else if (!/\/Filter\b/.test(dict)) decoded = body;                  // uncompressed content stream
    if (!decoded) continue;
    const text = textFromContentStream(DEC.decode(decoded));
    if (text) out += text + '\n';
  }
  out = out.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
  return looksLikeText(out) ? out : '';
}
