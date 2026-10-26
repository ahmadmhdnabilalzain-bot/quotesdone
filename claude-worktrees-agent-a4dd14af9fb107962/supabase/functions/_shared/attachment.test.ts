// AUDIT 9.1 - behavioural tests for the shared attachment sanitiser.
// Run: deno test --allow-none supabase/functions/_shared/attachment.test.ts
//
// These construct real file bytes and assert on what the sanitiser DOES, rather than checking
// that some string appears in the source. A substring check would have passed on a sanitiser
// that was never called.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload, sniff, safeFilename, stripJpegMetadata, stripPngMetadata, zipExpansionWithinLimits, looksMacroEnabled, SAFE_IMAGE, SAFE_SHEET } from './attachment.ts';

const enc = (s: string) => new TextEncoder().encode(s);
const cat = (...parts: Uint8Array[]) => {
  let n = 0; for (const p of parts) n += p.length;
  const out = new Uint8Array(n); let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
};
const u8 = (...b: number[]) => new Uint8Array(b);

// ---------------------------------------------------------------- realistic fixtures
function minimalPdf(extra = ''): Uint8Array {
  return enc(`%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n${extra}\ntrailer<</Root 1 0 R>>\n%%EOF\n`);
}

/** A JPEG with an APP1/EXIF block carrying GPS, then a minimal SOS payload. */
function jpegWithExif(): Uint8Array {
  const exifPayload = enc('Exif\0\0MM\0*GPSLatitude 25.2048 GPSLongitude 55.2708 Make Apple Owner AHMAD');
  const len = exifPayload.length + 2;
  return cat(
    u8(0xff, 0xd8),                                     // SOI
    u8(0xff, 0xe1, (len >> 8) & 0xff, len & 0xff),      // APP1
    exifPayload,
    u8(0xff, 0xfe, 0x00, 0x08), enc('secret'),          // COM comment
    u8(0xff, 0xdb, 0x00, 0x04, 0x00, 0x00),             // DQT (must survive)
    u8(0xff, 0xda, 0x00, 0x02),                         // SOS
    u8(0x01, 0x02, 0x03, 0x04),                         // image data
    u8(0xff, 0xd9),                                     // EOI
  );
}

function pngChunk(type: string, data: Uint8Array): Uint8Array {
  const len = data.length;
  return cat(u8((len >>> 24) & 255, (len >>> 16) & 255, (len >>> 8) & 255, len & 255), enc(type), data, u8(0, 0, 0, 0));
}
function pngWithText(): Uint8Array {
  return cat(
    u8(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a),
    pngChunk('IHDR', new Uint8Array(13)),
    pngChunk('eXIf', enc('GPS 25.2048,55.2708')),
    pngChunk('tEXt', enc('Author\0Ahmad Alzain')),
    pngChunk('IDAT', u8(1, 2, 3)),
    pngChunk('IEND', new Uint8Array(0)),
  );
}

// ---------------------------------------------------------------- sniffing
Deno.test('type comes from the bytes, not the declared header', () => {
  const r = sanitizeUpload({ input: minimalPdf(), declaredMime: 'image/png', filename: 'x.png' });
  assert(r.ok); assertEquals(r.mime, 'application/pdf'); assertEquals(r.ext, 'pdf');
  assert(r.declaredMismatch, 'a lying Content-Type must be recorded');
});

Deno.test('a ZIP declared as a PDF is refused', () => {
  const r = sanitizeUpload({ input: u8(0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4), declaredMime: 'application/pdf', filename: 'licence.pdf' });
  assert(!r.ok); assertEquals(r.error, 'file_type_not_allowed'); assertEquals(r.mime, 'application/zip');
});

Deno.test('HTML is refused however it is dressed up', () => {
  for (const body of ['<!DOCTYPE html><html><script>fetch("//evil")</script>', '   \n<html><body>hi', '<script>alert(1)</script>']) {
    const r = sanitizeUpload({ input: enc(body), declaredMime: 'application/pdf', filename: 'quote.pdf' });
    assert(!r.ok, `accepted: ${body.slice(0, 24)}`);
    assertEquals(r.error, 'unsafe_file_type');
  }
});

Deno.test('SVG is refused - it is a script container, not an image', () => {
  const r = sanitizeUpload({ input: enc('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'), declaredMime: 'image/svg+xml', allow: SAFE_IMAGE });
  assert(!r.ok); assertEquals(r.error, 'unsafe_file_type'); assertEquals(r.mime, 'danger/svg');
});

Deno.test('executables are refused by name', () => {
  for (const sig of [u8(0x4d, 0x5a, 0x90, 0x00), u8(0x7f, 0x45, 0x4c, 0x46, 2, 1, 1), u8(0x23, 0x21, 0x2f, 0x62)]) {
    const r = sanitizeUpload({ input: sig, filename: 'invoice.pdf' });
    assert(!r.ok); assertEquals(r.error, 'unsafe_file_type');
  }
});

// ---------------------------------------------------------------- polyglots
Deno.test('a PDF that is also an HTML document is refused', () => {
  const r = sanitizeUpload({ input: cat(enc('%PDF-1.4\n%<html><script>alert(1)</script>\n'), minimalPdf()), declaredMime: 'application/pdf' });
  assert(!r.ok); assertEquals(r.error, 'unsafe_file_content');
});

Deno.test('a PDF carrying JavaScript, /Launch or an embedded file is refused', () => {
  for (const payload of ['/JavaScript 5 0 R', '/Launch /F (calc.exe)', '/EmbeddedFile 9 0 R']) {
    const r = sanitizeUpload({ input: minimalPdf(payload), declaredMime: 'application/pdf' });
    assert(!r.ok, `accepted PDF containing ${payload}`);
    assertEquals(r.error, 'unsafe_file_content');
  }
});

Deno.test('an ordinary PDF still passes', () => {
  const r = sanitizeUpload({ input: minimalPdf('2 0 obj<</Length 8>>stream\nhello!\nendstream endobj'), declaredMime: 'application/pdf' });
  assert(r.ok); assertEquals(r.mime, 'application/pdf');
});

// ---------------------------------------------------------------- metadata stripping
Deno.test('JPEG GPS and owner name are removed from the stored bytes', () => {
  const original = jpegWithExif();
  const before = new TextDecoder('latin1').decode(original);
  assert(before.includes('GPSLatitude') && before.includes('AHMAD'), 'fixture must contain the leak');

  const r = sanitizeUpload({ input: original, declaredMime: 'image/jpeg', allow: SAFE_IMAGE });
  assert(r.ok);
  assert(r.strippedMetadata, 'metadata must be reported as stripped');
  const after = new TextDecoder('latin1').decode(r.bytes);
  assert(!after.includes('GPSLatitude'), 'GPS coordinates survived');
  assert(!after.includes('55.2708'), 'longitude survived');
  assert(!after.includes('AHMAD'), 'owner name survived');
  assert(!after.includes('secret'), 'COM comment survived');
  assert(r.bytes.length < original.length, 'file should be smaller');
  assertEquals([r.bytes[0], r.bytes[1]], [0xff, 0xd8], 'still a JPEG');
  assert(after.includes('\x01\x02\x03\x04'), 'image data must be preserved byte for byte');
});

Deno.test('PNG eXIf and tEXt chunks are removed, critical chunks survive', () => {
  const original = pngWithText();
  const r = sanitizeUpload({ input: original, declaredMime: 'image/png', allow: SAFE_IMAGE });
  assert(r.ok); assert(r.strippedMetadata);
  const after = new TextDecoder('latin1').decode(r.bytes);
  assert(!after.includes('25.2048'), 'GPS survived');
  assert(!after.includes('Ahmad Alzain'), 'author survived');
  assert(after.includes('IHDR') && after.includes('IDAT') && after.includes('IEND'), 'critical chunks must survive');
});

Deno.test('stripping never corrupts a file it does not understand', () => {
  const junk = u8(0xff, 0xd8, 0xff, 0x00, 0x11, 0x22);
  assertEquals(stripJpegMetadata(junk).stripped, false);
  assertEquals(stripJpegMetadata(junk).bytes, junk);
  const notPng = u8(1, 2, 3, 4);
  assertEquals(stripPngMetadata(notPng).bytes, notPng);
});

// ---------------------------------------------------------------- size and emptiness
Deno.test('the size ceiling is enforced and reported in MB', () => {
  const big = cat(enc('%PDF-1.4\n'), new Uint8Array(2 * 1024 * 1024));
  const r = sanitizeUpload({ input: big, maxBytes: 1024 * 1024 });
  assert(!r.ok); assertEquals(r.error, 'file_too_large'); assert(r.detail.includes('MB'));
});

Deno.test('empty and unreadable uploads are refused', () => {
  assertEquals((sanitizeUpload({ input: new Uint8Array(0) }) as { error: string }).error, 'empty_upload');
  assertEquals((sanitizeUpload({ input: '!!!not base64!!!' }) as { error: string }).error, 'unreadable_upload');
});

// ---------------------------------------------------------------- filenames
Deno.test('filenames cannot traverse, hide, or disagree with the content', () => {
  assertEquals(safeFilename('../../etc/passwd', 'application/pdf'), 'passwd.pdf');
  assertEquals(safeFilename('C:\\Windows\\system32\\cmd.exe', 'application/pdf'), 'cmd.pdf');
  assertEquals(safeFilename('licence.pdf\u0000.exe', 'application/pdf'), 'licence.pdf.pdf');
  assertEquals(safeFilename('photo\u202Egnp.exe', 'image/jpeg'), 'photognp.jpg');   // bidi override removed
  assertEquals(safeFilename('', 'image/png'), 'file.png');
  assertEquals(safeFilename('....', 'application/pdf'), 'file.pdf');
  // The extension always follows the sniffed type, never the caller's claim.
  assertEquals(safeFilename('anything.png', 'application/pdf'), 'anything.pdf');
});

// ---------------------------------------------------------------- allow-lists and fail-closed
Deno.test('a path that accepts only images refuses a PDF', () => {
  const r = sanitizeUpload({ input: minimalPdf(), allow: SAFE_IMAGE });
  assert(!r.ok); assertEquals(r.error, 'file_type_not_allowed');
});

Deno.test('an unidentifiable file is refused rather than waved through', () => {
  const r = sanitizeUpload({ input: u8(0x00, 0x01, 0x02, 0x03, 0x04, 0x05), declaredMime: 'application/pdf' });
  assert(!r.ok);
  assertEquals(sniff(u8(0x00, 0x01, 0x02, 0x03)), 'application/octet-stream');
});

// ---------------------------------------------------------- spreadsheets (added 9 Sep 2026)
//
// supplier_catalog_ingest was the one upload site of fourteen that called nothing in this module.
// Routing it here needed a sheet branch, and a sheet branch is only safe if it cannot be used to
// smuggle the shapes this module already refuses. That is what these assert.

/** A real ZIP with stored (uncompressed) entries, so the central-directory reader has something true to read. */
function zip(entries: { name: string; body: Uint8Array; declaredUncompressed?: number }[]): Uint8Array {
  const te = new TextEncoder();
  const w16 = (n: number) => u8(n & 0xff, (n >> 8) & 0xff);
  const w32 = (n: number) => u8(n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff);
  const locals: Uint8Array[] = [];
  const centrals: Uint8Array[] = [];
  let offset = 0;
  for (const e of entries) {
    const name = te.encode(e.name);
    const usize = e.declaredUncompressed ?? e.body.length;
    const local = cat(u8(0x50, 0x4b, 0x03, 0x04), w16(20), w16(0), w16(0), w16(0), w16(0),
                      w32(0), w32(e.body.length), w32(usize), w16(name.length), w16(0), name, e.body);
    centrals.push(cat(u8(0x50, 0x4b, 0x01, 0x02), w16(20), w16(20), w16(0), w16(0), w16(0), w16(0),
                      w32(0), w32(e.body.length), w32(usize), w16(name.length), w16(0), w16(0),
                      w16(0), w16(0), w32(0), w32(offset), name));
    locals.push(local);
    offset += local.length;
  }
  const cd = cat(...centrals);
  const eocd = cat(u8(0x50, 0x4b, 0x05, 0x06), w16(0), w16(0), w16(entries.length), w16(entries.length),
                   w32(cd.length), w32(offset), w16(0));
  return cat(...locals, cd, eocd);
}
const xlsx = (extra: { name: string; body: Uint8Array; declaredUncompressed?: number }[] = []) =>
  zip([{ name: 'xl/workbook.xml', body: enc('<workbook/>') }, ...extra]);

Deno.test('an XLSX is told apart from a plain archive by what is inside it', () => {
  assertEquals(sniff(xlsx()), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  // A zip that does NOT carry the workbook part stays a zip, and every allow-list still refuses it.
  assertEquals(sniff(zip([{ name: 'notes.txt', body: enc('hello') }])), 'application/zip');
  const r = sanitizeUpload({ input: zip([{ name: 'a.txt', body: enc('x') }]), allow: SAFE_SHEET, filename: 'prices.xlsx' });
  assert(!r.ok); assertEquals(r.error, 'file_type_not_allowed');
});

Deno.test('legacy .xls and delimited text are identified, and text is not mistaken for a sheet', () => {
  assertEquals(sniff(u8(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0)), 'application/vnd.ms-excel');
  assertEquals(sniff(enc('sku,name,price\r\nA1,Tile,12.50\r\n')), 'text/csv');
  assertEquals(sniff(enc('sku\tname\tprice\nA1\tTile\t12.5\n')), 'text/csv');
  // Prose with no delimiter is not a table, and is not claimed to be one. Since 14 Sep 2026 it is
  // identified as text/plain (doc_read reads .txt), and the sheet route still refuses it.
  assertEquals(sniff(enc('just some plain prose with no delimiters at all')), 'text/plain');
  assert(!sanitizeUpload({ input: enc('just some plain prose with no delimiters at all'), allow: SAFE_SHEET }).ok);
});

Deno.test('THE DISGUISED UPLOAD: the sheet route refuses what it is really given', () => {
  // Every one of these is named as a catalogue the ingester would have parsed by extension.
  const disguised: [string, Uint8Array, string][] = [
    ['catalogue.csv  (really HTML)',      enc('<!doctype html><script>fetch("/steal")</script>'), 'unsafe_file_type'],
    ['prices.csv     (really SVG)',       enc('<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>'), 'unsafe_file_type'],
    ['pricelist.xlsx (really a PE exe)',  cat(u8(0x4d, 0x5a, 0x90, 0x00), enc('this program cannot be run')), 'unsafe_file_type'],
    ['products.csv   (really a shell script)', enc('#!/bin/sh\nrm -rf /\n'), 'unsafe_file_type'],
    ['catalogue.xlsx (really a plain zip)', zip([{ name: 'payload.bin', body: enc('x') }]), 'file_type_not_allowed'],
    ['sheet.xlsx     (really a PDF+JS)',  minimalPdf('/JavaScript (app.alert(1))'), 'file_type_not_allowed'],
  ];
  for (const [label, bytes, want] of disguised) {
    const r = sanitizeUpload({ input: bytes, declaredMime: 'text/csv', filename: label.split(' ')[0], allow: SAFE_SHEET });
    assert(!r.ok, `${label} was ACCEPTED`);
    assertEquals(r.error, want, label);
  }
  // ...and the genuine article still gets through, or the guard proves nothing.
  const good = sanitizeUpload({ input: enc('sku,name,price\nA1,Tile,12.50\n'), allow: SAFE_SHEET, filename: 'prices.csv' });
  assert(good.ok);
  assertEquals(good.mime, 'text/csv');
  assert(sanitizeUpload({ input: xlsx(), allow: SAFE_SHEET, filename: 'prices.xlsx' }).ok);
});

Deno.test('adding the sheet branch did not widen any existing call site', () => {
  // The default allow-list, and the image-only one, still refuse every sheet type by name.
  for (const bytes of [enc('a,b,c\n1,2,3\n'), xlsx(), u8(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0)]) {
    const d = sanitizeUpload({ input: bytes });
    assert(!d.ok, 'a sheet reached a default-allow-list call site');
    const i = sanitizeUpload({ input: bytes, allow: SAFE_IMAGE });
    assert(!i.ok, 'a sheet reached an image-only call site');
  }
  // And the danger branches still win over the new text branch, whatever the caller allows.
  assertEquals(sniff(enc('<!doctype html><p>,,,</p>')), 'danger/html');
  assertEquals(sniff(enc('<?php echo 1,2,3; ?>')), 'danger/script');
});

// ------------------------------------------------------------------------- zip expansion limits
Deno.test('a zip bomb is refused before it is expanded', () => {
  // 4 GB declared from a handful of stored bytes: the shape that kills the isolate inside XLSX.read.
  const bomb = xlsx([{ name: 'xl/worksheets/sheet1.xml', body: enc('x'), declaredUncompressed: 4_000_000_000 }]);
  const v = zipExpansionWithinLimits(bomb, { maxEntries: 512, maxTotalBytes: 64 * 1024 * 1024, maxRatio: 120 });
  assert(!v.ok);
  assertEquals(v.error, 'zip_expands_too_far');
});

Deno.test('an archive with too many entries is refused, and counted not guessed', () => {
  const many = xlsx(Array.from({ length: 40 }, (_, i) => ({ name: `xl/media/i${i}.bin`, body: enc('x') })));
  const v = zipExpansionWithinLimits(many, { maxEntries: 8 });
  assert(!v.ok);
  assertEquals(v.error, 'zip_too_many_entries');
  assert(v.detail.includes('41'), `expected the real entry count in: ${v.detail}`);
});

Deno.test('an unreadable or truncated archive is refused, never waved through', () => {
  assert(!zipExpansionWithinLimits(enc('not a zip at all')).ok);
  const good = xlsx();
  assert(!zipExpansionWithinLimits(good.subarray(0, good.length - 10)).ok);   // EOCD chopped off
});

Deno.test('an ordinary workbook passes the caps - a limit that refuses everything is not a limit', () => {
  const ordinary = xlsx([
    { name: 'xl/worksheets/sheet1.xml', body: enc('<sheetData>' + 'row,'.repeat(500) + '</sheetData>') },
    { name: '[Content_Types].xml', body: enc('<Types/>') },
  ]);
  const v = zipExpansionWithinLimits(ordinary, { maxEntries: 512, maxTotalBytes: 64 * 1024 * 1024, maxRatio: 120 });
  assert(v.ok, `an ordinary workbook was refused: ${JSON.stringify(v)}`);
  assertEquals(v.entries, 3);
});

// ---------------------------------------------------------------- CAD (cad_convert)
// The ASCII variant is the one people actually export. Only the binary sentinel was recognised, so
// every real .dxf was refused as unsupported_type before CloudConvert was ever asked.
Deno.test('an ASCII DXF is recognised, in both the bare and the right-aligned group-code form', () => {
  assertEquals(sniff(enc('0\r\nSECTION\r\n2\r\nHEADER\r\n9\r\n$ACADVER\r\n1\r\nAC1015\r\n')), 'image/vnd.dxf');
  assertEquals(sniff(enc('  0\n  SECTION\n  2\nENTITIES\n')), 'image/vnd.dxf');
  assertEquals(sniff(enc('AutoCAD Binary DXF\r\n\x1a\x00rest')), 'image/vnd.dxf');
  assertEquals(sniff(enc('AC1032nnnnnnnnnnnn')), 'image/vnd.dwg');
});

Deno.test('the DXF signature does not swallow ordinary text', () => {
  // Anything whose first line is not exactly the group code 0 followed by SECTION.
  assert(sniff(enc('0\r\nSECTIONAL SOFA QUOTE\r\n')) !== 'image/vnd.dxf');
  assert(sniff(enc('10\r\nSECTION\r\n')) !== 'image/vnd.dxf');
  assert(sniff(enc('SECTION\r\n0\r\n')) !== 'image/vnd.dxf');
});

// ---------------------------------------------------------------- macro-bearing office files
// 9 SEP 2026, with the malware watch. An .xlsm renamed .xlsx is a genuine OOXML workbook — the ZIP
// still carries xl/workbook.xml — so every check that existed before passed it, SheetJS read it,
// and we stored and forwarded a file whose payload runs on the laptop of whoever opens it next.
// The macro container itself is the test, not a heuristic, and these assert the guard fires ONLY on
// a file that actually has one: a guard that refuses every workbook would be caught here too.
Deno.test('POSITIVE CONTROL: a macro-bearing workbook is refused, whatever it was named', () => {
  const macro = xlsx([{ name: 'xl/vbaProject.bin', body: enc('\0\x01macro payload') }]);
  assertEquals(sniff(macro), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  assertEquals(looksMacroEnabled(macro, sniff(macro)),
               'the workbook contains a VBA macro project (xl/vbaProject.bin)');
  const r = sanitizeUpload({ input: macro, allow: SAFE_SHEET, filename: 'price-list-2026.xlsx',
                             declaredMime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  assert(!r.ok, 'a workbook carrying a VBA project was ACCEPTED');
  assertEquals(r.error, 'unsafe_file_content');
});

Deno.test('NEGATIVE CONTROL: an ordinary workbook is still accepted', () => {
  const plain = xlsx([{ name: 'xl/worksheets/sheet1.xml', body: enc('<sheetData/>') }]);
  assertEquals(looksMacroEnabled(plain, sniff(plain)), null);
  const r = sanitizeUpload({ input: plain, allow: SAFE_SHEET, filename: 'price-list-2026.xlsx' });
  assert(r.ok, `an ordinary workbook was refused: ${JSON.stringify(r)}`);
});

Deno.test('a legacy .xls carrying _VBA_PROJECT is refused, and one without it is not', () => {
  const ole = (tail: Uint8Array) => cat(u8(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1), tail);
  // OLE2 stores a directory entry name as UTF-16LE, which is how Excel actually writes it.
  const utf16 = (s: string) => u8(...Array.from(s).flatMap((c) => [c.charCodeAt(0), 0]));
  const withMacro = ole(utf16('_VBA_PROJECT'));
  assertEquals(looksMacroEnabled(withMacro, 'application/vnd.ms-excel'),
               'the workbook contains a VBA macro project (_VBA_PROJECT stream)');
  assertEquals(looksMacroEnabled(ole(enc('Workbook')), 'application/vnd.ms-excel'), null);
});

Deno.test('the macro check does not fire on file types that cannot carry one', () => {
  // A PDF containing the literal string is still a PDF; /JavaScript is what looksPolyglot covers.
  assertEquals(looksMacroEnabled(minimalPdf('vbaProject.bin'), 'application/pdf'), null);
  assertEquals(looksMacroEnabled(enc('sku,name\nA1,Tile\n'), 'text/csv'), null);
});
