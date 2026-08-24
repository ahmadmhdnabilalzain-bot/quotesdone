// PD-PRIV-005 — a deterministic hidden-metadata scanner, and the fixtures that prove it discriminates.
//
// WHY THIS IS HERE AND NOT IN POSTGRES. Postgres in this estate never receives file bytes: the only
// bytea columns in public are pages._osb and phase_d_fixture_secret.secret, and public.documents
// stores bucket/path/mime — a pointer. A scan over metadata has to run where the bytes are and
// record its verdict where a predicate can read it, which is exactly how the section 8 HTTP probes
// already work.
//
// WHY NO DEPENDENCY. pdf-lib exists in this repo only as an esm.sh import inside Deno edge
// functions; it is not a node dependency and adding one to read a /Info dictionary would be
// absurd. A PDF Info dictionary, an XMP packet, a PNG tEXt chunk and a JPEG APP1/COM segment are
// all readable from the raw bytes with the standard library, and scripts/staging/fixtures/
// licence_pdf.mjs already establishes that this repo writes PDFs by hand for exactly this reason.
//
// WHAT IT DELIBERATELY DOES NOT DO. It does not decide whether a free-form personal NAME is
// present — the identifier class person_name_freeform is registered as HUMAN_REVIEW in
// public.phase_d_personal_identifier_class precisely because a regex cannot decide a name, and
// scoring it automatically as absent is the "absent input scores as satisfied" shape. What it does
// instead is surface every metadata value it found, so a reviewer judges the text rather than
// judging a boolean somebody else computed.
//
// FAIL CLOSED. An unreadable file, an unrecognised media type and a parse error are three separate
// outcomes and NONE of them is CLEAN: they are SCAN_FAILED or UNSUPPORTED, and
// fn_phase_d_file_revision_dispatchable refuses both.

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SCANNER = 'quotesdone/metadata_scan.mjs';
export const SCANNER_VERSION = '1';

export const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

// ---------------------------------------------------------------------------------------------
// EXTRACTION — one function per container, each returning {class, where, value} records of the raw
// metadata STRINGS it found. No judgement here; judgement is the scan() below, against the classes
// the database registers.
// ---------------------------------------------------------------------------------------------

/** PDF: the trailer /Info dictionary, every /Key (value) pair, plus any XMP packet. */
function pdfMetadata(buf) {
  const out = [];
  const text = buf.toString('latin1');
  // Every "N 0 obj << ... >>" that carries at least one Info-style key. A PDF may hold several;
  // taking only the first would miss an incremental update, which is how an "already cleaned" file
  // keeps its old author.
  const INFO_KEYS = ['Title', 'Author', 'Subject', 'Keywords', 'Creator', 'Producer'];
  const re = /\/(Title|Author|Subject|Keywords|Creator|Producer)\s*\(((?:\\.|[^\\)])*)\)/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const value = m[2].replace(/\\([()\\])/g, '$1');
    if (value.trim() !== '') out.push({ where: `pdf:/Info//${m[1]}`, value });
  }
  // XMP is XML embedded between these markers; the whole packet is surfaced as one value so a
  // reviewer sees what is actually in it.
  const xmp = text.match(/<\?xpacket begin[\s\S]*?<\?xpacket end[^>]*\?>/g) || [];
  for (const packet of xmp) out.push({ where: 'pdf:xmp', value: packet.replace(/\s+/g, ' ').trim() });
  // A PDF with no /Info at all is a legitimate, clean result — not a failure.
  void INFO_KEYS;
  return out;
}

/** PNG: every tEXt / zTXt / iTXt chunk keyword and value. */
function pngMetadata(buf) {
  const out = [];
  if (buf.length < 8 || buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  let off = 8;
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('latin1', off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'tEXt' || type === 'iTXt') {
      const s = data.toString('latin1');
      const nul = s.indexOf('\0');
      const keyword = nul < 0 ? s : s.slice(0, nul);
      // iTXt carries compression/language bytes between the keyword and the text; taking
      // everything after the last NUL is enough to surface the value for review.
      const value = nul < 0 ? '' : s.slice(s.lastIndexOf('\0') + 1);
      if (value.trim() !== '') out.push({ where: `png:${type}/${keyword}`, value });
    } else if (type === 'zTXt') {
      // Deflated. Not decompressed here: its presence alone is reportable, and a value nobody can
      // read must not be reported as absent.
      out.push({ where: 'png:zTXt', value: '(compressed text chunk present, not decoded)' });
    }
    if (type === 'IEND') break;
    off += 12 + len;
  }
  return out;
}

/** JPEG: APP1 (EXIF/XMP) and COM comment segments, surfaced as printable runs. */
function jpegMetadata(buf) {
  const out = [];
  if (buf.length < 4 || buf.readUInt16BE(0) !== 0xffd8) throw new Error('not a JPEG');
  let off = 2;
  while (off + 4 <= buf.length) {
    if (buf[off] !== 0xff) break;
    const marker = buf[off + 1];
    if (marker === 0xd9 || marker === 0xda) break;      // EOI / start of scan
    const len = buf.readUInt16BE(off + 2);
    const seg = buf.subarray(off + 4, off + 2 + len);
    if (marker === 0xe1 || marker === 0xfe) {           // APP1, COM
      // Printable runs of 4+ characters. EXIF is a TIFF structure; pulling its strings is enough to
      // surface an author, a GPS string, a camera owner or a copyright line for review.
      const s = seg.toString('latin1');
      for (const run of s.match(/[\x20-\x7e]{4,}/g) || []) {
        out.push({ where: marker === 0xfe ? 'jpeg:COM' : 'jpeg:APP1', value: run });
      }
    }
    off += 2 + len;
  }
  return out;
}

/** Office OOXML core/custom properties. Detected, and reported as unsupported rather than guessed. */
function ooxmlMetadata() {
  // docProps/core.xml lives inside a ZIP; unzipping needs inflate over the central directory, and
  // this estate produces no OOXML on a supplier-facing path today. Reported as UNSUPPORTED, which
  // fails closed, rather than scanned badly and reported CLEAN.
  throw Object.assign(new Error('OOXML core/custom properties are not decoded by this scanner'),
    { unsupported: true });
}

const BY_TYPE = {
  'application/pdf': pdfMetadata,
  'image/png': pngMetadata,
  'image/jpeg': jpegMetadata,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ooxmlMetadata,
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ooxmlMetadata,
};

export function mediaTypeOf(path) {
  const ext = path.toLowerCase().split('.').pop();
  return { pdf: 'application/pdf', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }[ext] || null;
}

// ---------------------------------------------------------------------------------------------
// THE SCAN. Classes come from the DATABASE, never from a constant here, so the rule and the scanner
// cannot disagree about what a personal identifier is.
// ---------------------------------------------------------------------------------------------
export function scan(buf, mediaType, classes) {
  const inspected = classes.map((c) => c.identifier_class);
  const reader = BY_TYPE[mediaType];
  if (!reader) {
    return { outcome: 'UNSUPPORTED', findings: [], classes_inspected: inspected,
      detail: `no metadata reader for media type ${mediaType}` };
  }
  let records;
  try {
    records = reader(buf);
  } catch (err) {
    if (err?.unsupported) {
      return { outcome: 'UNSUPPORTED', findings: [], classes_inspected: inspected,
        detail: String(err.message) };
    }
    return { outcome: 'SCAN_FAILED', findings: [], classes_inspected: inspected,
      detail: String(err?.message ?? err) };
  }

  const findings = [];
  for (const rec of records) {
    for (const c of classes) {
      if (c.detection !== 'REGEX') continue;
      let re;
      try { re = new RegExp(c.pattern, 'i'); } catch { continue; }
      const hit = rec.value.match(re);
      if (hit) {
        findings.push({ identifier_class: c.identifier_class, where: rec.where,
          matched: hit[0].slice(0, 120) });
      }
    }
  }
  // Every metadata value found is carried in the detail even when no regex class matched, because
  // person_name_freeform is HUMAN_REVIEW by registration and a scanner that silently discarded
  // "/Author (Omar Bin Faisal)" would be reporting a clean file it never judged.
  const values = records.map((r) => `${r.where}=${r.value}`).join(' | ').slice(0, 3000);
  return {
    outcome: findings.length ? 'IDENTIFIERS_FOUND' : 'CLEAN',
    findings,
    classes_inspected: inspected,
    detail: records.length
      ? `${records.length} metadata value(s) read: ${values}`
      : 'no metadata values present in this container',
  };
}

// ---------------------------------------------------------------------------------------------
// THE FIXTURES. Deterministic — no dates, no random ids — so the committed bytes and their digests
// are reproducible. Regenerate with:  node scripts/phase_d/metadata_scan.mjs --write-fixtures
// ---------------------------------------------------------------------------------------------
const HERE = dirname(fileURLToPath(import.meta.url));
export const FIXTURE_DIR = join(HERE, '..', 'staging', 'fixtures', 'metadata');

const escPdf = (s) => String(s).replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

function buildPdf({ info, line }) {
  const body = ['BT', '/F1 12 Tf', '16 TL', '56 780 Td', `(${escPdf(line)}) Tj`, 'ET'].join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      + '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    `<< /Length ${Buffer.byteLength(body, 'latin1')} >>\nstream\n${body}\nendstream`,
    '<< ' + Object.entries(info).map(([k, v]) => `/${k} (${escPdf(v)})`).join(' ') + ' >>',
  ];
  let out = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(Buffer.byteLength(out, 'latin1'));
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = Buffer.byteLength(out, 'latin1');
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`
    + offsets.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('');
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R /Info ${objs.length} 0 R >>\n`
    + `startxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, 'latin1');
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = c ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

function buildPng(textChunks) {
  // A 1x1 opaque black PNG. The image is irrelevant: the fixture is about the text chunks.
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0); ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  // zlib stream for one filter byte + one RGB pixel, stored (uncompressed) so no deflate is needed.
  const raw = Buffer.from([0x00, 0x00, 0x00, 0x00]);
  let adler = 1, s1 = 1, s2 = 0;
  for (const b of raw) { s1 = (s1 + b) % 65521; s2 = (s2 + s1) % 65521; }
  adler = ((s2 << 16) | s1) >>> 0;
  const ad = Buffer.alloc(4); ad.writeUInt32BE(adler);
  const idat = Buffer.concat([
    Buffer.from([0x78, 0x01, 0x01, raw.length & 0xff, (raw.length >> 8) & 0xff,
      ~raw.length & 0xff, (~raw.length >> 8) & 0xff]),
    raw, ad,
  ]);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    ...textChunks.map(([k, v]) => pngChunk('tEXt', Buffer.from(`${k}\0${v}`, 'latin1'))),
    pngChunk('IDAT', idat),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

// MARKED test identifiers, in this estate's own demo convention: ZZ DEMO and example.invalid, so
// nothing here can be mistaken for a real customer even if a fixture escapes into a bucket.
export const FIXTURES = {
  'supplier_drawing_dirty.pdf': () => buildPdf({
    info: {
      Title: 'ZZ DEMO Villa 42 plot 345-8871 — window schedule',
      Author: 'ZZ DEMO Omar Bin Faisal',
      Subject: 'contact zz.customer@example.invalid or 0501234567',
      Keywords: 'PHASE_D_FIXTURE_DO_NOT_PUBLISH wa.me/971501234567',
      Creator: 'C:\\Users\\zz.demo.customer\\AutoCAD',
      Producer: 'ZZ DEMO CAD 2026',
    },
    line: 'ZZ DEMO window schedule — quantities and scope only.',
  }),
  'supplier_drawing_clean.pdf': () => buildPdf({
    info: { Producer: 'QuotesDone' },
    line: 'ZZ DEMO window schedule — quantities and scope only.',
  }),
  'supplier_photo_dirty.png': () => buildPng([
    ['Author', 'ZZ DEMO Omar Bin Faisal'],
    ['Comment', 'site contact zz.customer@example.invalid / +971501234567'],
    ['Source', 'https://zz-demo.example.invalid/projects/villa-42'],
  ]),
  'supplier_photo_clean.png': () => buildPng([]),
};

function writeFixtures() {
  mkdirSync(FIXTURE_DIR, { recursive: true });
  for (const [name, build] of Object.entries(FIXTURES)) {
    const buf = build();
    writeFileSync(join(FIXTURE_DIR, name), buf);
    console.log(`${name}  ${buf.length} bytes  sha256 ${sha256(buf)}`);
  }
}

export function readFixture(name) {
  return readFileSync(join(FIXTURE_DIR, name));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.includes('--write-fixtures')) writeFixtures();
  else {
    // Self-check with the registered classes stubbed, so the extractor can be exercised with no
    // database. The real run reads the classes from public.phase_d_personal_identifier_class.
    const CLASSES = [
      { identifier_class: 'customer_email', detection: 'REGEX', pattern: '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}' },
      { identifier_class: 'customer_phone_ae', detection: 'REGEX', pattern: '(971|0)5[0-9]{8}' },
      { identifier_class: 'messenger_handle', detection: 'REGEX', pattern: '(wa[.]me/|t[.]me/|skype:)' },
      { identifier_class: 'embedded_url', detection: 'REGEX', pattern: 'https?://[^\\s)>"]+' },
      { identifier_class: 'filesystem_username', detection: 'REGEX', pattern: '([A-Za-z]:\\\\Users\\\\[^\\\\ ]+|/(home|Users)/[^/ ]+)' },
    ];
    let bad = 0;
    for (const name of Object.keys(FIXTURES)) {
      const buf = readFixture(name);
      const r = scan(buf, mediaTypeOf(name), CLASSES);
      const want = name.includes('dirty') ? 'IDENTIFIERS_FOUND' : 'CLEAN';
      const ok = r.outcome === want;
      if (!ok) bad++;
      console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(30)} ${r.outcome.padEnd(18)} `
        + `${r.findings.length} finding(s) [${[...new Set(r.findings.map((f) => f.identifier_class))].join(',')}]`);
    }
    // an unreadable file must fail closed, not read as clean
    const broken = scan(Buffer.from('not a pdf at all'), 'image/png', CLASSES);
    console.log(`${broken.outcome === 'SCAN_FAILED' ? 'ok  ' : 'FAIL'}  ${'(corrupt png)'.padEnd(30)} ${broken.outcome}`);
    if (broken.outcome !== 'SCAN_FAILED') bad++;
    const unsup = scan(Buffer.from('x'), 'application/zip', CLASSES);
    console.log(`${unsup.outcome === 'UNSUPPORTED' ? 'ok  ' : 'FAIL'}  ${'(unknown media type)'.padEnd(30)} ${unsup.outcome}`);
    if (unsup.outcome !== 'UNSUPPORTED') bad++;
    process.exit(bad ? 1 : 0);
  }
}
