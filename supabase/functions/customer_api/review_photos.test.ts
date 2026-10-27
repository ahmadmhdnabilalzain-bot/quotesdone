// Review photos: only real images, at most 5 MB each, at most 5 per review, metadata cut.
import { assertEquals } from 'jsr:@std/assert@1';
import { parseReviewPhotos, REVIEW_PHOTO_BYTES, REVIEW_PHOTO_MAX, stripImageMetadata } from './review_photos.ts';

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
// Minimal JPEG: SOI, APP1 "Exif" (carries the secret), SOS, data, EOI.
const exif = new TextEncoder().encode('Exif\0\0GPS 25.2N 55.3E');
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe1, 0, exif.length + 2, ...exif, 0xff, 0xda, 0, 2, 1, 2, 3, 0xff, 0xd9]);
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);

Deno.test('a JPEG and a PNG pass, typed from their bytes, and the JPEG loses its EXIF', () => {
  const r = parseReviewPhotos([{ b64: 'data:image/jpeg;base64,' + b64(jpeg) }, { b64: b64(png) }]);
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.photos.map((p) => p.mime), ['image/jpeg', 'image/png']);
    assertEquals(new TextDecoder().decode(r.photos[0].bytes).includes('GPS'), false);
    assertEquals(r.photos[0].bytes[0] === 0xff && r.photos[0].bytes[1] === 0xd8, true);
  }
});

Deno.test('a non-image is refused even when it claims to be a JPEG', () => {
  for (const bad of ['data:image/jpeg;base64,' + btoa('%PDF-1.7 not a photo'), btoa('<svg/>'), '!!not base64!!']) {
    const r = parseReviewPhotos([{ b64: bad }]);
    assertEquals(r.ok === false && r.code, 'photo_not_image');
  }
});

Deno.test('a photo over 5 MB is refused', () => {
  const big = new Uint8Array(REVIEW_PHOTO_BYTES + 1); big.set([0xff, 0xd8, 0xff]);
  let s = ''; for (let i = 0; i < big.length; i += 0x8000) s += String.fromCharCode(...big.subarray(i, i + 0x8000));
  const r = parseReviewPhotos([{ b64: btoa(s) }]);
  assertEquals(r.ok === false && r.code, 'photo_too_large');
});

Deno.test('more than 5 photos are refused, counting those already on the review', () => {
  const one = { b64: b64(jpeg) };
  assertEquals(parseReviewPhotos(Array(REVIEW_PHOTO_MAX).fill(one)).ok, true);
  const six = parseReviewPhotos(Array(REVIEW_PHOTO_MAX + 1).fill(one));
  assertEquals(six.ok === false && six.code, 'too_many_photos');
  const topUp = parseReviewPhotos([one, one], REVIEW_PHOTO_MAX - 1);
  assertEquals(topUp.ok === false && topUp.code, 'too_many_photos');
  const none = parseReviewPhotos([]);
  assertEquals(none.ok === false && none.code, 'photos_required');
});

Deno.test('PNG text chunks are cut', () => {
  const t = new TextEncoder().encode('Authorname');
  const chunk = new Uint8Array([0, 0, 0, t.length, 0x74, 0x45, 0x58, 0x74, ...t, 0, 0, 0, 0]);
  const withText = new Uint8Array([...png.subarray(0, 8), ...chunk, ...png.subarray(8)]);
  const out = stripImageMetadata(withText, 'image/png');
  assertEquals(new TextDecoder().decode(out).includes('Author'), false);
  assertEquals(out.length, png.length);
});
