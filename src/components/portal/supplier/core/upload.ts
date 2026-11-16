import { call } from '../api';
// Same as the customer portal: an inline production fallback meant an unconfigured preview let
// suppliers upload trade licences into the LIVE database. See supaEnv.
import { SUPA_ANON as ANON, SUPA_URL } from '@/lib/supaEnv';
import { uploadToSignedUrl, retryTransient } from '@/lib/signedUpload';
import { fileKind, shrinkSize, jpegName, keptAsSent, PHOTO_QUALITY } from '../fileCheck';
import { fileToB64, fileToImages as toPages } from '@/components/me/fileImages';

// UPLOADS UP TO 100 MB GO STRAIGHT TO STORAGE (19 Oct 2026, sales_engineer). Vercel caps a request body at 4.5 MB, so a
// company profile or catalogue is not sent as base64: supplier_api upload_url signs a path in the supplier's own folder,
// the file goes to it, and process_docs / save_documents are given the path (the server gates the stored bytes).
// SB() is AUTH-ONLY (src/lib/supaClient.ts), so the file goes up by hand on the signed URL (src/lib/signedUpload.ts).
// SB().storage was undefined: every profile and catalogue threw before upload and "Uploading..." never ended (27 Oct).
// A platform 502/503/546 or a dropped leg is retried (up to 3 tries, a new signed path each time): walk 41379033121 (2 Nov 2026)
// lost a whole registration to ONE 502 on the catalogue's upload_url call.
// THE LICENCE GOES THIS WAY TOO (12 Nov 2026, customer_support; browser walk B1): kind 'licence' signs a path in the licence
// folder (supplier_api/actions/documents.ts upload_url). `onProgress` (0..1) is told as the bytes go (H2); a dropped connection
// comes back as the code 'network', so the form can say that it was the connection (M6). A dropped or stalled upload is tried THREE
// times in all (retryTransient: a new signed path each time, 1.5 s then 3 s apart), so on a line that has gone quiet the form offers
// "Try again" about 65 s after the press (3 x 20 s of stall, signedUpload.ts STALL_MS, plus 4.5 s), not after the first stall.
const uploadDirect = (kind: string, file: File, token: string, onProgress?: (done: number) => void, signal?: AbortSignal) => retryTransient(async () => {
  const u = await call('supplier_api', { action: 'upload_url', kind, filename: file.name, mime: file.type }, token);
  if (!(u && u.ok && u.path && u.token)) return { error: u };
  onProgress?.(0);
  if (signal?.aborted) return { error: { code: 'cancelled', status: -1 } };
  const { error } = await uploadToSignedUrl(SUPA_URL, ANON, 'supplier-docs', u.path, u.token, file, file.type, fetch, onProgress, signal);
  // cancelled by him, or over the 15-minute safeguard: said as such, and never tried again (status -1 is not transient)
  if (error && error.status === -1) return { error: { code: error.message === 'too_slow' ? 'upload_too_slow' : 'cancelled', status: -1 } };
  return error ? { error: { code: error.status === 0 ? 'network' : 'direct_upload_failed', status: error.status } } : { path: u.path, filename: file.name, mime: file.type, ...(u.issued ? { issued: u.issued } : {}) };
});

// A LARGE PHONE PHOTO IS MADE SMALLER BEFORE IT LEAVES; A SMALL FILE IS SENT AS IT IS (12 Nov 2026, customer_support; browser walk
// B1, then the review of this change, finding 6). Measured: a 4032x3024 JPEG of 4.32 MB went whole, as base64, three times. The
// first cut drew every photo at 2,000 px, which re-encoded a 235 KB screenshot and left 8 pt print on a whole A4 licence about
// 7 px high. Now: a file of KEEP_AS_SENT_BYTES (3 MB) or less, and every PDF, goes as his own bytes (fileCheck.ts keptAsSent); a
// larger photo is drawn upright (its EXIF orientation applied) with its long edge at PHOTO_MAX_EDGE (3,000 px), JPEG at
// PHOTO_QUALITY (0.85); a HEIC is drawn the same way where the browser can decode it (Safari), and is otherwise left as HEIC for
// fileCheck.ts to refuse plainly. A photo the browser cannot draw goes as it was picked, judged by its size.
// MEASURED 12 Nov 2026 in Chromium, through this function in the portal (walk at 390x844 and 360x740):
//   a 17.0 MB 48 MP photo of a whole A4 licence (6048x8064, the page 92% of the frame; ZZ DEMO fixture) went up as 935,734 bytes,
//   2250x3000; 8 pt capitals there are 19 px high (53 px in the original), 10 pt 24 px, so 8 pt lower case is about 14 px;
//   the walk's 4.32 MB 4032x3024 photo went up as 1,434,978 bytes, 3000x2250, upright; a 234,913-byte PNG screenshot went up as
//   the same 234,913 bytes; a text PDF byte-identical. Code reads nothing off any photo (no OCR), before or after.
async function drawable(file: File): Promise<{ img: CanvasImageSource; w: number; h: number; done: () => void } | null> {
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
    return { img: bmp, w: bmp.width, h: bmp.height, done: () => bmp.close?.() };
  } catch (_e) { /* Safari decodes some types only through an <img> */ }
  const url = URL.createObjectURL(file);
  try {
    const im = new Image(); im.src = url; await im.decode();
    return { img: im, w: im.naturalWidth, h: im.naturalHeight, done: () => URL.revokeObjectURL(url) };
  } catch (_e) { URL.revokeObjectURL(url); return null; }
}
async function preparePhoto(file: File): Promise<File> {
  const k = fileKind(file);
  if ((k !== 'photo' && k !== 'heic') || keptAsSent(file)) return file;
  if (typeof document === 'undefined') return file;
  const d = typeof createImageBitmap === 'function' || typeof Image === 'function' ? await drawable(file) : null;
  if (!d) return file;
  try {
    const size = shrinkSize(d.w, d.h);
    if (!size && k === 'photo') { d.done(); return file; }
    const { w, h } = size || { w: d.w, h: d.h };
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const g = c.getContext('2d');
    if (!g) { d.done(); return file; }
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, w, h); g.imageSmoothingQuality = 'high';
    g.drawImage(d.img, 0, 0, w, h); d.done();
    const blob = await new Promise<Blob | null>((res) => c.toBlob(res, 'image/jpeg', PHOTO_QUALITY));
    if (!blob || (k === 'photo' && blob.size >= file.size)) return file;
    return new File([blob], jpegName(file.name), { type: 'image/jpeg', lastModified: Date.now() });
  } catch (_e) { d.done(); return file; }
}
// A quotation photo or PDF becomes page images through the ONE converter both portals use (me/fileImages.ts, 16 Nov
// 2026): until then this file had its own copy, which sent a HEIC or multi-page TIFF up raw. Only the PAGES the reader
// takes are converted: the supplier's ORIGINAL quotation is kept exactly as sent, as before (every page of a multi-page
// TIFF, a phone photo at full size; supplier_api stores a TIFF or HEIC as it is, attachment.ts SAFE_PHOTO_EXTRA).
const quotePages = async (file: File) =>
  ({ images: (await toPages(file)).images, b64: await fileToB64(file), mime: file.type || 'application/octet-stream' });
export { uploadDirect, preparePhoto, fileToB64, quotePages as fileToImages };
