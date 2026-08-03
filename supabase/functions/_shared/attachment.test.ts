// AUDIT 9.1 - behavioural tests for the shared attachment sanitiser.
// Run: deno test --allow-none supabase/functions/_shared/attachment.test.ts
//
// These construct real file bytes and assert on what the sanitiser DOES, rather than checking
// that some string appears in the source. A substring check would have passed on a sanitiser
// that was never called.

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload, sniff, safeFilename, stripJpegMetadata, stripPngMetadata, SAFE_IMAGE } from './attachment.ts';

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
