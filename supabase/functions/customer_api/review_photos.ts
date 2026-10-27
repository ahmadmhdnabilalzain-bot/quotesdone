// PHOTOS ON A POST-JOB REVIEW (T2) — what a customer may attach, decided in one testable place.
//
// A review may carry up to REVIEW_PHOTO_MAX images. Each must BE an image — the type is read from the
// file's own first bytes, never from the name or the browser's claim — and at most REVIEW_PHOTO_BYTES.
// Camera metadata (EXIF/XMP/text chunks: GPS position, device, owner name) is cut before storage, so
// a photo cannot tell the supplier where the customer lives. The stored name is a random id, never
// the customer's file name. The bucket (review-photos) is private and served only by signed URL.
//
// Tested in review_photos.test.ts — it fails if a non-image, an oversize file or a sixth photo passes.

export const REVIEW_PHOTO_MAX = 5;
export const REVIEW_PHOTO_BYTES = 5 * 1024 * 1024;

export type PhotoMime = 'image/jpeg' | 'image/png' | 'image/webp';
export type ReviewPhoto = { bytes: Uint8Array; mime: PhotoMime; ext: 'jpg' | 'png' | 'webp' };
export type PhotoCode = 'photos_required' | 'too_many_photos' | 'photo_not_image' | 'photo_too_large';
export type PhotoResult = { ok: true; photos: ReviewPhoto[] } | { ok: false; code: PhotoCode; error: string };

const fail = (code: PhotoCode, error: string): PhotoResult => ({ ok: false, code, error });

/** The image type from the bytes themselves, or null. */
export function sniffImage(b: Uint8Array): ReviewPhoto['mime'] | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return 'image/png';
  if (b.length > 12 && String.fromCharCode(...b.subarray(0, 4)) === 'RIFF' && String.fromCharCode(...b.subarray(8, 12)) === 'WEBP') return 'image/webp';
  return null;
}

function b64ToBytes(b64: string): Uint8Array {
  const raw = atob(b64.replace(/^data:[^;]+;base64,/, ''));
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/** JPEG: drop APP1..APP15 and COM segments (EXIF, XMP, comments); keep APP0 (JFIF) and image data. */
function stripJpeg(b: Uint8Array): Uint8Array {
  const parts: Uint8Array[] = [b.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= b.length && b[i] === 0xff) {
    const m = b[i + 1];
    if (m === 0xda) break; // start of scan: the rest is image data
    const len = (b[i + 2] << 8) | b[i + 3];
    const end = i + 2 + len;
    if (end > b.length) break;
    const drop = (m >= 0xe1 && m <= 0xef) || m === 0xfe;
    if (!drop) parts.push(b.subarray(i, end));
    i = end;
  }
  parts.push(b.subarray(i));
  return concat(parts);
}

/** PNG: drop tEXt/iTXt/zTXt/eXIf/tIME chunks. */
function stripPng(b: Uint8Array): Uint8Array {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const parts: Uint8Array[] = [b.subarray(0, 8)];
  let i = 8;
  while (i + 12 <= b.length) {
    const len = dv.getUint32(i);
    const type = String.fromCharCode(...b.subarray(i + 4, i + 8));
    const end = i + 12 + len;
    if (end > b.length) { parts.push(b.subarray(i)); i = b.length; break; }
    if (!['tEXt', 'iTXt', 'zTXt', 'eXIf', 'tIME'].includes(type)) parts.push(b.subarray(i, end));
    i = end;
  }
  if (i < b.length) parts.push(b.subarray(i));
  return concat(parts);
}

/** WebP: drop EXIF and XMP chunks, clear their VP8X flags, fix the RIFF size. */
function stripWebp(b: Uint8Array): Uint8Array {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const parts: Uint8Array[] = [];
  let i = 12;
  while (i + 8 <= b.length) {
    const type = String.fromCharCode(...b.subarray(i, i + 4));
    const len = dv.getUint32(i + 4, true);
    const end = Math.min(b.length, i + 8 + len + (len & 1));
    if (type !== 'EXIF' && type !== 'XMP ') {
      const chunk = b.slice(i, end);
      if (type === 'VP8X' && chunk.length > 8) chunk[8] &= ~(0x08 | 0x04);
      parts.push(chunk);
    }
    i = end;
  }
  const body = concat(parts);
  const out = new Uint8Array(12 + body.length);
  out.set(b.subarray(0, 12));
  new DataView(out.buffer).setUint32(4, 4 + body.length, true);
  out.set(body, 12);
  return out;
}

function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

export function stripImageMetadata(bytes: Uint8Array, mime: PhotoMime): Uint8Array {
  try {
    return mime === 'image/jpeg' ? stripJpeg(bytes) : mime === 'image/png' ? stripPng(bytes) : stripWebp(bytes);
  } catch {
    return bytes; // a malformed container is still the bytes the customer sent; the type was already proven
  }
}

/**
 * photos: [{ b64 }] (data-URL or bare base64). `existing` = photos already on this review, so the
 * cap holds across several uploads. Nothing here touches storage or the database.
 */
export function parseReviewPhotos(photos: unknown, existing = 0): PhotoResult {
  if (!Array.isArray(photos) || photos.length === 0) return fail('photos_required', 'Choose at least one photo.');
  if (existing + photos.length > REVIEW_PHOTO_MAX) {
    return fail('too_many_photos', `A review can carry at most ${REVIEW_PHOTO_MAX} photos.`);
  }
  const out: ReviewPhoto[] = [];
  for (const p of photos) {
    const b64 = String((p as { b64?: unknown })?.b64 ?? '');
    // Base64 is 4/3 the bytes: refuse an oversize file before decoding it.
    if (b64.length > Math.ceil(REVIEW_PHOTO_BYTES * 4 / 3) + 128) return fail('photo_too_large', 'Each photo must be 5 MB or smaller.');
    let bytes: Uint8Array;
    try { bytes = b64ToBytes(b64); } catch { return fail('photo_not_image', 'Only JPEG, PNG or WebP photos can be attached.'); }
    if (bytes.length > REVIEW_PHOTO_BYTES) return fail('photo_too_large', 'Each photo must be 5 MB or smaller.');
    const mime = sniffImage(bytes);
    if (!mime) return fail('photo_not_image', 'Only JPEG, PNG or WebP photos can be attached.');
    out.push({ bytes: stripImageMetadata(bytes, mime), mime, ext: mime === 'image/jpeg' ? 'jpg' : mime === 'image/png' ? 'png' : 'webp' });
  }
  return { ok: true, photos: out };
}
