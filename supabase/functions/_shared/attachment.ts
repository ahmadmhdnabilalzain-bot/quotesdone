// AUDIT 9.1 - universal attachment sanitisation.
//
// The independent audit tabulated 15 inbound attachment paths and found ONE magic-byte check
// across the whole codebase (reg_fetch), no shared module, and no metadata stripping outside the
// two paths that happen to re-render. This file is the shared module. It is deliberately pure -
// no Supabase client, no fetch, no env - so it can be unit tested and so a caller cannot get a
// half-configured version of it.
//
// THREE THINGS IT ACTUALLY DOES
//
//  1. Decides the type from the BYTES, not from what the caller said. A declared Content-Type is
//     a courtesy, not evidence: "application/pdf" on a ZIP is one header edit. storage.buckets
//     .allowed_mime_types matches the declared type, so it narrows the blast radius but cannot
//     close this. sniff() closes it.
//
//  2. Refuses the shapes that are dangerous rather than merely unexpected - HTML and SVG (script
//     execution when served back), executables, and polyglots (a file that is a valid PDF and a
//     valid HTML document at once, which passes a type check and then runs in a browser).
//
//  3. Strips embedded metadata from images. This is not housekeeping on a marketplace whose whole
//     product is anonymity: a JPEG straight off a phone carries GPS coordinates, the device
//     serial, and often the owner's name in EXIF. A supplier who receives a "masked" site photo
//     with the customer's exact coordinates in it has been given the customer's address. We
//     rewrite JPEG APPn segments and PNG ancillary chunks out of the file entirely.
//
// WHAT IT DOES NOT DO, so nobody assumes otherwise:
//   * No malware scanning. Detecting a known-bad payload needs a signature database this codebase
//     does not have. The existing post-hoc scan stays the control for that.
//   * No re-encode. Re-encoding a PDF or an image needs a decoder that Deno does not ship. Metadata
//     is stripped by rewriting the container, which removes EXIF/XMP/ICC but not content embedded
//     in the image data itself. drawing_redact's render-to-JPEG path remains the stronger control
//     where it applies.

export type SanitizeResult =
  | { ok: true;  mime: string; ext: string; bytes: Uint8Array; size: number; strippedMetadata: boolean; declaredMismatch: boolean }
  | { ok: false; error: string; detail: string; mime?: string };

/** Types we are willing to accept anywhere. Anything not on this list is refused by name. */
export const SAFE_DOCUMENT = ['application/pdf'] as const;
export const SAFE_IMAGE    = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const SAFE_UPLOAD   = [...SAFE_DOCUMENT, ...SAFE_IMAGE] as const;

// AUDIT 9.1 part 2 (3 Aug 2026). Two ingestion paths could not use this module at all: cad_convert
// takes DWG/DXF and transcribe takes audio, and sniff() knew only PDF and images — so calling
// sanitizeUpload on either would have refused every legitimate upload. Adding the magic numbers is
// the change that makes those call sites possible; it widens nothing on its own, because a type is
// only ever accepted when the CALLER passes an allow-list containing it.
export const SAFE_AUDIO = ['audio/wav', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/webm', 'audio/flac'] as const;
export const SAFE_CAD   = ['image/vnd.dwg', 'image/vnd.dxf'] as const;

// 9 SEP 2026 — SPREADSHEETS. supplier_catalog_ingest was the one upload site of fourteen that
// called nothing in this file: it atob()'d the body straight into .upload(), decided the format from
// the FILENAME EXTENSION, applied no size limit of any kind, and handed a ZIP container to
// XLSX.read() with no entry-count, decompressed-size or ratio cap — a zip bomb, on a path a
// registered supplier can reach with one POST. Routing it here needed a sheet branch, because
// sniff() knew PDF, images, audio and CAD and nothing else, so sanitizeUpload would have refused
// every legitimate price list.
//
// This WIDENS NOTHING on its own. A type is only ever accepted when the CALLER passes an allow-list
// containing it, and no existing call site passes SAFE_SHEET. Every danger/* branch in sniff()
// still runs FIRST and still wins: an HTML file named catalogue.csv is refused as HTML, not read as
// a table. That precedence is the property, and attachment.test.ts asserts it.
export const SAFE_SHEET = [
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // xlsx
  'application/vnd.ms-excel',                                          // xls (OLE2)
  'text/csv',                                                          // csv / tsv / txt
] as const;

const EXT: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'audio/wav': 'wav',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/ogg': 'ogg',
  'audio/webm': 'weba',
  'audio/flac': 'flac',
  'image/vnd.dwg': 'dwg',
  'image/vnd.dxf': 'dxf',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.ms-excel': 'xls',
  'text/csv': 'csv',
};

function startsWith(b: Uint8Array, sig: number[], at = 0): boolean {
  if (b.length < at + sig.length) return false;
  for (let i = 0; i < sig.length; i++) if (b[at + i] !== sig[i]) return false;
  return true;
}

function asciiAt(b: Uint8Array, at: number, len: number): string {
  return new TextDecoder('latin1').decode(b.subarray(at, at + len));
}

/**
 * Is this plausibly a text file? A NUL byte or a run of control characters means binary; a decoder
 * that rejects the bytes as UTF-8 means binary. Samples the first 8 KB — enough to catch a binary
 * that opens with a text-looking preamble, cheap on a 20 MB upload.
 */
function isProbablyText(b: Uint8Array): boolean {
  const n = Math.min(b.length, 8192);
  if (n === 0) return false;
  let control = 0;
  for (let i = 0; i < n; i++) {
    const c = b[i];
    if (c === 0) return false;                                   // NUL — never a text file
    if (c < 0x20 && c !== 0x09 && c !== 0x0a && c !== 0x0d) control++;
  }
  return control <= n / 100;
}

/**
 * Identify a file from its leading bytes. Returns a mime string, or one of the
 * 'danger/*' pseudo-types for shapes we recognise specifically in order to refuse them.
 * Never throws.
 */
export function sniff(b: Uint8Array): string {
  if (!b || b.length < 4) return 'application/octet-stream';

  // Executables - refuse by name so the log says why.
  if (startsWith(b, [0x4d, 0x5a])) return 'danger/executable';                       // MZ  - PE
  if (startsWith(b, [0x7f, 0x45, 0x4c, 0x46])) return 'danger/executable';           // ELF
  if (startsWith(b, [0xca, 0xfe, 0xba, 0xbe]) || startsWith(b, [0xcf, 0xfa, 0xed, 0xfe])) return 'danger/executable';
  if (startsWith(b, [0x23, 0x21])) return 'danger/script';                           // #!

  if (startsWith(b, [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';             // %PDF
  if (startsWith(b, [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (startsWith(b, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(b, [0x52, 0x49, 0x46, 0x46]) && asciiAt(b, 8, 4) === 'WEBP') return 'image/webp';

  // ---- audio (transcribe) ----------------------------------------------------------------
  // RIFF is shared with WebP, so the WAVE branch must sit beside it and after it.
  if (startsWith(b, [0x52, 0x49, 0x46, 0x46]) && asciiAt(b, 8, 4) === 'WAVE') return 'audio/wav';
  if (startsWith(b, [0x49, 0x44, 0x33])) return 'audio/mpeg';                        // ID3-tagged MP3
  // Bare MP3 frame sync: 11 set bits. Catches files with no ID3 header at all.
  if (b[0] === 0xff && (b[1] & 0xe0) === 0xe0) return 'audio/mpeg';
  if (startsWith(b, [0x4f, 0x67, 0x67, 0x53])) return 'audio/ogg';                   // OggS
  if (startsWith(b, [0x66, 0x4c, 0x61, 0x43])) return 'audio/flac';                  // fLaC
  if (startsWith(b, [0x1a, 0x45, 0xdf, 0xa3])) return 'audio/webm';                  // EBML (WebM/Matroska)
  if (asciiAt(b, 4, 4) === 'ftyp') {
    const brand = asciiAt(b, 8, 4);
    if (brand === 'M4A ' || brand === 'M4B ' || brand === 'mp42' || brand === 'isom' || brand === 'mp41') return 'audio/mp4';
  }

  // ---- CAD (cad_convert) -----------------------------------------------------------------
  // DWG carries its format version in the first six ASCII bytes: AC1015, AC1018, AC1021,
  // AC1024, AC1027, AC1032 and so on. Matching the AC10.. shape rather than an enumerated list
  // means a newer AutoCAD release does not silently become an unrecognised upload.
  if (/^AC10\d\d$/.test(asciiAt(b, 0, 6))) return 'image/vnd.dwg';
  if (asciiAt(b, 0, 18) === 'AutoCAD Binary DXF') return 'image/vnd.dxf';
  // ASCII DXF, added 9 Sep 2026 while restoring cad_convert. Only the BINARY variant was
  // recognised, and binary DXF is rare: every DXF an architect or a supplier actually exports is
  // ASCII, so sniff() answered application/octet-stream and sanitizeOrMessage refused the file as
  // unsupported_type before CloudConvert was ever asked. cad_convert's own extension check
  // (`ext === 'dxf' ? 'dxf' : 'dwg'`) proves ASCII DXF was always meant to be accepted.
  //
  // The signature is the DXF file structure itself, not a guess: a DXF begins with group code 0
  // then the string SECTION, one per line, and the code may be right-aligned in a 3-character
  // field ('  0'), which is why the leading run of spaces is allowed and nothing else is.
  if (/^[ \t]*0\r?\n[ \t]*SECTION\r?\n/.test(asciiAt(b, 0, 24))) return 'image/vnd.dxf';

  // OLE2 compound document. Legacy .xls (and .doc, .ppt) share this header; the caller's allow-list
  // decides whether that is acceptable, and supplier_catalog_ingest hands whatever comes back to
  // SheetJS, which reads the workbook stream or fails honestly.
  if (startsWith(b, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) return 'application/vnd.ms-excel';

  // XLSX is a ZIP. Distinguishing it from a plain archive means looking at what is INSIDE: an OOXML
  // workbook always carries the part `xl/workbook.xml`, and a zip stores every entry's name
  // uncompressed in its local header and again in the central directory, so the name is findable in
  // the raw bytes without inflating anything. A zip that does not carry it stays application/zip and
  // is refused by every allow-list in this file.
  if (startsWith(b, [0x50, 0x4b, 0x03, 0x04]) || startsWith(b, [0x50, 0x4b, 0x05, 0x06])) {
    const scan = asciiAt(b, 0, Math.min(b.length, 4 * 1024 * 1024));
    if (scan.includes('xl/workbook.xml')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    return 'application/zip';
  }
  if (startsWith(b, [0x1f, 0x8b])) return 'application/gzip';
  if (startsWith(b, [0x52, 0x61, 0x72, 0x21])) return 'application/x-rar-compressed';
  if (startsWith(b, [0x7b, 0x5c, 0x72, 0x74, 0x66])) return 'application/rtf';       // {\rtf

  // Text-ish. Look at a generous prefix, skipping a UTF-8 BOM and leading whitespace, because
  // "     <html>" and "<!-- x --><svg>" are both still HTML and SVG.
  const head = asciiAt(b, 0, Math.min(b.length, 2048)).replace(/^﻿/, '').replace(/^\s+/, '');
  const lower = head.toLowerCase();
  if (/^<!doctype\s+html/.test(lower) || /^<html[\s>]/.test(lower) || /^<head[\s>]/.test(lower) ||
      /^<script[\s>]/.test(lower) || /^<body[\s>]/.test(lower)) return 'danger/html';
  if (/^<\?xml/.test(lower) && lower.includes('<svg')) return 'danger/svg';
  if (/^<svg[\s>]/.test(lower)) return 'danger/svg';
  if (/^<\?php/.test(lower)) return 'danger/script';

  // ASCII DXF is plain text — a group code 0 followed by SECTION — so it can only be identified
  // HERE, after every danger/* branch above has had its say. A file that is both valid HTML and
  // valid DXF is refused as HTML, which is the correct precedence: the dangerous reading wins.
  if (/^0\s+SECTION/.test(head) && /\$ACADVER|\bHEADER\b|\bENTITIES\b/.test(head.toUpperCase())) {
    return 'image/vnd.dxf';
  }

  // Delimited text. CSV has no magic number — it is text, and the only honest identification is
  // "these bytes are text and they have a delimiter". It sits LAST on purpose: every danger/*
  // branch, and every binary and DXF branch, has already had its say, so an HTML document, an SVG
  // or a PHP file named .csv is refused as what it is rather than read as a table here.
  if (isProbablyText(b) && /[,;\t]/.test(head.slice(0, 512))) return 'text/csv';

  return 'application/octet-stream';
}

/**
 * A polyglot is a file that satisfies two format parsers at once. The classic is a PDF whose
 * header comment also opens an HTML document: a type check sees a PDF, a browser runs the script.
 * PDF is permissive about leading bytes, which is exactly what makes it the usual carrier.
 */
export function looksPolyglot(b: Uint8Array, mime: string): string | null {
  if (mime !== 'application/pdf') return null;
  const head = asciiAt(b, 0, Math.min(b.length, 4096)).toLowerCase();
  if (head.includes('<html') || head.includes('<!doctype html') || head.includes('<script')) {
    return 'the file is a valid PDF whose first bytes also open an HTML document';
  }
  // Active content inside a PDF. /JavaScript and /Launch are how a PDF runs something on open.
  const whole = asciiAt(b, 0, Math.min(b.length, 262144));
  if (/\/JavaScript\b/.test(whole) || /\/JS\b/.test(whole)) return 'the PDF contains embedded JavaScript';
  if (/\/Launch\b/.test(whole)) return 'the PDF contains a /Launch action';
  if (/\/EmbeddedFile\b/.test(whole)) return 'the PDF carries an embedded file attachment';
  return null;
}

/**
 * Remove EXIF, XMP, ICC and comment segments from a JPEG by rebuilding the segment chain and
 * dropping every APPn and COM marker. Image data (SOS onward) is copied byte for byte, so the
 * picture is unchanged and only the metadata is gone. Returns the original on anything unexpected -
 * failing to strip must never mean failing to accept a legitimate document.
 */
export function stripJpegMetadata(b: Uint8Array): { bytes: Uint8Array; stripped: boolean } {
  if (!startsWith(b, [0xff, 0xd8, 0xff])) return { bytes: b, stripped: false };
  const out: Uint8Array[] = [new Uint8Array([0xff, 0xd8])];
  let i = 2, dropped = false;
  while (i < b.length - 1) {
    if (b[i] !== 0xff) return { bytes: b, stripped: false };       // desynchronised - do not touch it
    let marker = b[i + 1];
    while (marker === 0xff && i + 2 < b.length) { i++; marker = b[i + 1]; }  // fill bytes
    if (marker === 0xd9) { out.push(b.subarray(i)); break; }        // EOI
    if (marker === 0xda) { out.push(b.subarray(i)); break; }        // SOS - image data to the end
    if (i + 4 > b.length) return { bytes: b, stripped: false };
    const len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return { bytes: b, stripped: false };
    const isAppN = marker >= 0xe0 && marker <= 0xef;                // APP0..APP15: EXIF, XMP, ICC, Adobe
    const isCom  = marker === 0xfe;                                 // COM: free-text comment
    if (isAppN || isCom) dropped = true; else out.push(b.subarray(i, i + 2 + len));
    i += 2 + len;
  }
  if (!dropped) return { bytes: b, stripped: false };
  let total = 0; for (const c of out) total += c.length;
  const merged = new Uint8Array(total);
  let o = 0; for (const c of out) { merged.set(c, o); o += c.length; }
  return { bytes: merged, stripped: true };
}

/**
 * Remove ancillary chunks from a PNG - eXIf, tEXt, iTXt, zTXt, tIME - keeping the critical ones
 * (IHDR, PLTE, IDAT, IEND) and the ones that change how the image renders (tRNS, gAMA, sRGB).
 * CRCs are copied with their chunks, so the result stays valid without recomputation.
 */
export function stripPngMetadata(b: Uint8Array): { bytes: Uint8Array; stripped: boolean } {
  if (!startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return { bytes: b, stripped: false };
  const KEEP = new Set(['IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'sRGB', 'cHRM', 'sBIT', 'bKGD', 'pHYs', 'acTL', 'fcTL', 'fdAT']);
  const out: Uint8Array[] = [b.subarray(0, 8)];
  let i = 8, dropped = false;
  while (i + 8 <= b.length) {
    const len = (b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) >>> 0;
    const type = asciiAt(b, i + 4, 4);
    const end = i + 12 + len;
    if (end > b.length) return { bytes: b, stripped: false };
    if (KEEP.has(type)) out.push(b.subarray(i, end)); else dropped = true;
    i = end;
    if (type === 'IEND') break;
  }
  if (!dropped) return { bytes: b, stripped: false };
  let total = 0; for (const c of out) total += c.length;
  const merged = new Uint8Array(total);
  let o = 0; for (const c of out) { merged.set(c, o); o += c.length; }
  return { bytes: merged, stripped: true };
}

/**
 * A filename from a caller is attacker-controlled text that ends up in a storage key, a Content-
 * Disposition header and an email. Strip directory components, control characters and anything
 * that could re-open a path, and force the extension to match what the bytes actually are.
 */
export function safeFilename(raw: unknown, mime: string): string {
  let name = String(raw ?? '').split(/[\\/]/).pop() || 'file';
  name = name.replace(/[ -]/g, '')     // control chars, including the NUL that truncates
             .replace(/[‪-‮⁦-⁩]/g, '')  // bidi overrides - "photo‮gnp.exe"
             .replace(/[^A-Za-z0-9._ -]/g, '_')
             .replace(/^\.+/, '')
             .replace(/\.{2,}/g, '.')
             .trim();
  if (!name) name = 'file';
  const base = name.replace(/\.[A-Za-z0-9]{1,8}$/, '').slice(0, 80) || 'file';
  const ext = EXT[mime] || 'bin';
  return `${base}.${ext}`;
}

export function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(String(b64).replace(/^data:[^;]+;base64,/, '').replace(/\s+/g, ''));
  const a = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i);
  return a;
}

export interface SanitizeOptions {
  /** Raw bytes, or a base64 / data-URL string. */
  input: Uint8Array | string;
  /** What the caller claimed. Recorded and compared; never trusted. */
  declaredMime?: string | null;
  filename?: unknown;
  /** Types the calling path accepts. Defaults to PDF + JPEG/PNG/WebP. */
  allow?: readonly string[];
  /** Hard byte ceiling for this path. Defaults to 25 MB, matching the storage buckets. */
  maxBytes?: number;
  /** Set false only where metadata must survive for a downstream tool. */
  stripMetadata?: boolean;
}

/**
 * The single entry point. Every inbound attachment path should call this before the bytes reach
 * storage, an LLM or another supplier. It fails CLOSED: anything it cannot positively identify as
 * an allowed type is refused.
 */
export function sanitizeUpload(opts: SanitizeOptions): SanitizeResult {
  const allow = opts.allow ?? SAFE_UPLOAD;
  const maxBytes = opts.maxBytes ?? 25 * 1024 * 1024;

  let bytes: Uint8Array;
  try {
    bytes = typeof opts.input === 'string' ? b64ToBytes(opts.input) : opts.input;
  } catch (_e) {
    return { ok: false, error: 'unreadable_upload', detail: 'the upload is not valid base64' };
  }
  if (!bytes || bytes.length === 0) return { ok: false, error: 'empty_upload', detail: 'the file is empty' };
  if (bytes.length > maxBytes) {
    return { ok: false, error: 'file_too_large',
             detail: `${(bytes.length / 1048576).toFixed(1)} MB exceeds the ${(maxBytes / 1048576).toFixed(0)} MB limit for this upload` };
  }

  const mime = sniff(bytes);

  if (mime.startsWith('danger/')) {
    const what = mime === 'danger/html' ? 'an HTML document'
               : mime === 'danger/svg' ? 'an SVG, which can carry script'
               : mime === 'danger/executable' ? 'an executable'
               : 'a script';
    return { ok: false, error: 'unsafe_file_type', mime,
             detail: `the file content is ${what}, whatever it was named or declared as` };
  }

  if (!allow.includes(mime)) {
    return { ok: false, error: 'file_type_not_allowed', mime,
             detail: `the file content is ${mime}; this upload accepts ${allow.join(', ')}` };
  }

  const poly = looksPolyglot(bytes, mime);
  if (poly) return { ok: false, error: 'unsafe_file_content', mime, detail: poly };

  // Recorded rather than refused. A wrong declared type is usually a careless browser, not an
  // attack - and the decision has already been made on the bytes, so it changes nothing.
  const declared = String(opts.declaredMime || '').split(';')[0].trim().toLowerCase();
  const declaredMismatch = declared.length > 0 && declared !== mime &&
    !(declared === 'image/jpg' && mime === 'image/jpeg');

  let out = bytes, stripped = false;
  if (opts.stripMetadata !== false) {
    if (mime === 'image/jpeg') { const r = stripJpegMetadata(bytes); out = r.bytes; stripped = r.stripped; }
    else if (mime === 'image/png') { const r = stripPngMetadata(bytes); out = r.bytes; stripped = r.stripped; }
  }

  return { ok: true, mime, ext: EXT[mime] || 'bin', bytes: out, size: out.length,
           strippedMetadata: stripped, declaredMismatch };
}

// ── ZIP EXPANSION LIMITS ────────────────────────────────────────────────────────────────────────
//
// An XLSX is a ZIP, and handing a ZIP to a parser is handing it a DECOMPRESSION RATIO. A 40 KB file
// can declare 4 GB of contents; SheetJS will try to produce them, and the isolate dies before any
// size check written AFTER the parse ever runs. So the check has to happen BEFORE, and it can:
// a zip's central directory states every entry's uncompressed size in plain bytes, uncompressed. No
// inflation is needed to read the bill.
//
// WHAT THIS IS NOT: it is not a timeout. XLSX.read() is synchronous and CPU-bound, and nothing in
// JavaScript can abort a synchronous call from the same isolate — an AbortController cannot reach
// it. The entry count, the total and the ratio ARE the control, chosen so the work is bounded before
// it starts rather than interrupted after. Said plainly rather than implied by a signal that would
// do nothing.

export interface ZipLimits {
  /** Refuse an archive with more entries than this. */
  maxEntries?: number;
  /** Refuse an archive whose entries sum to more than this uncompressed. */
  maxTotalBytes?: number;
  /** Refuse an archive that claims to expand by more than this multiple of its own size. */
  maxRatio?: number;
}

export type ZipVerdict =
  | { ok: true; entries: number; totalUncompressed: number; ratio: number }
  | { ok: false; error: string; detail: string };

/**
 * Read a zip's central directory and decide whether it is worth expanding. Reads sizes only; never
 * inflates anything. An archive whose directory cannot be read is REFUSED, not waved through: a
 * container this cannot account for is exactly the one not to hand to a parser.
 */
export function zipExpansionWithinLimits(b: Uint8Array, limits: ZipLimits = {}): ZipVerdict {
  const maxEntries = limits.maxEntries ?? 512;
  const maxTotalBytes = limits.maxTotalBytes ?? 64 * 1024 * 1024;
  const maxRatio = limits.maxRatio ?? 120;

  const u32 = (at: number) => (b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)) >>> 0;
  const u16 = (at: number) => b[at] | (b[at + 1] << 8);

  // End of Central Directory: 'PK\x05\x06', within the last 64 KB + 22 header bytes.
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 0x05 && b[i + 3] === 0x06) { eocd = i; break; }
  }
  if (eocd < 0) return { ok: false, error: 'zip_unreadable', detail: 'no end-of-central-directory record; this is not a readable archive' };

  const entries = u16(eocd + 10);
  const cdOffset = u32(eocd + 16);
  if (entries === 0xffff || cdOffset === 0xffffffff) {
    return { ok: false, error: 'zip_unreadable', detail: 'ZIP64 archive; this path does not accept one' };
  }
  if (entries > maxEntries) {
    return { ok: false, error: 'zip_too_many_entries', detail: `${entries} entries exceeds the ${maxEntries} allowed` };
  }

  let total = 0, seen = 0, at = cdOffset;
  while (seen < entries && at + 46 <= b.length) {
    if (!(b[at] === 0x50 && b[at + 1] === 0x4b && b[at + 2] === 0x01 && b[at + 3] === 0x02)) {
      return { ok: false, error: 'zip_unreadable', detail: `central directory entry ${seen + 1} has no PK\\x01\\x02 signature` };
    }
    total += u32(at + 24);                                    // uncompressed size, as the archive states it
    if (total > maxTotalBytes) {
      return { ok: false, error: 'zip_expands_too_far',
               detail: `the archive declares more than ${maxTotalBytes} bytes uncompressed` };
    }
    at += 46 + u16(at + 28) + u16(at + 30) + u16(at + 32);    // + name + extra + comment
    seen++;
  }
  if (seen !== entries) return { ok: false, error: 'zip_unreadable', detail: `directory ended after ${seen} of ${entries} entries` };

  const ratio = b.length ? total / b.length : 0;
  if (ratio > maxRatio) {
    return { ok: false, error: 'zip_expands_too_far',
             detail: `${total} bytes from a ${b.length} byte archive is a ${ratio.toFixed(0)}:1 ratio; the cap is ${maxRatio}:1` };
  }
  return { ok: true, entries, totalUncompressed: total, ratio };
}

/** Convenience for the many call sites that just need a yes/no plus a message for the user. */
export function sanitizeOrMessage(opts: SanitizeOptions): { ok: true; result: Extract<SanitizeResult, { ok: true }> } | { ok: false; status: number; body: Record<string, unknown> } {
  const r = sanitizeUpload(opts);
  if (r.ok) return { ok: true, result: r };
  const status = r.error === 'file_too_large' ? 413 : 415;
  return { ok: false, status, body: { error: r.error, detail: r.detail, message: userMessage(r) } };
}

function userMessage(r: Extract<SanitizeResult, { ok: false }>): string {
  switch (r.error) {
    case 'file_too_large':       return 'That file is too large. Please upload a smaller version.';
    case 'empty_upload':         return 'That file appears to be empty. Please try again.';
    case 'unreadable_upload':    return 'We could not read that upload. Please try again.';
    case 'unsafe_file_type':
    case 'unsafe_file_content':  return 'That file cannot be accepted for security reasons. Please upload a PDF or an image.';
    default:                     return 'Please upload a PDF or an image (JPEG, PNG or WebP).';
  }
}
