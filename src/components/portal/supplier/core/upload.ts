import { call } from '../api';
// Same as the customer portal: an inline production fallback meant an unconfigured preview let
// suppliers upload trade licences into the LIVE database. See supaEnv.
import { SUPA_ANON as ANON, SUPA_URL } from '@/lib/supaEnv';
import { uploadToSignedUrl, retryTransient } from '@/lib/signedUpload';
import { fileKind, shrinkSize, jpegName, PHOTO_QUALITY } from '../fileCheck';

// UPLOADS UP TO 100 MB GO STRAIGHT TO STORAGE (19 Oct 2026, sales_engineer). Vercel caps a request body at 4.5 MB, so a
// company profile or catalogue is not sent as base64: supplier_api upload_url signs a path in the supplier's own folder,
// the file goes to it, and process_docs / save_documents are given the path (the server gates the stored bytes).
// SB() is AUTH-ONLY (src/lib/supaClient.ts), so the file goes up by hand on the signed URL (src/lib/signedUpload.ts).
// SB().storage was undefined: every profile and catalogue threw before upload and "Uploading..." never ended (27 Oct).
// A platform 502/503/546 or a dropped leg is retried (up to 3 tries, a new signed path each time): walk 41379033121 (2 Nov 2026)
// lost a whole registration to ONE 502 on the catalogue's upload_url call.
// THE LICENCE GOES THIS WAY TOO (12 Nov 2026, customer_support; browser walk B1): kind 'licence' signs a path in the licence
// folder (supplier_api/actions/documents.ts upload_url). `onProgress` (0..1) is told as the bytes go (H2); a dropped connection
// comes back as the code 'network', so the form can say that it was the connection (M6).
const uploadDirect = (kind: string, file: File, token: string, onProgress?: (done: number) => void) => retryTransient(async () => {
  const u = await call('supplier_api', { action: 'upload_url', kind, filename: file.name, mime: file.type }, token);
  if (!(u && u.ok && u.path && u.token)) return { error: u };
  onProgress?.(0);
  const { error } = await uploadToSignedUrl(SUPA_URL, ANON, 'supplier-docs', u.path, u.token, file, file.type, fetch, onProgress);
  return error ? { error: { code: error.status === 0 ? 'network' : 'direct_upload_failed', status: error.status } } : { path: u.path, filename: file.name, mime: file.type };
});

// A PHONE PHOTO IS MADE SMALL BEFORE IT LEAVES (12 Nov 2026, customer_support; browser walk B1). Measured: a 4032x3024 JPEG of
// 4.32 MB went whole (and as base64, three times). It is drawn again with its long edge at PHOTO_MAX_EDGE (2,000 px) as a JPEG
// at PHOTO_QUALITY; a HEIC the browser can decode (Safari) is turned into a JPEG the same way. A photo already small is left as
// it is, and so is one the browser cannot draw (its type is then judged as it is: fileCheck.ts). A PDF is never touched.
// Measured 12 Nov 2026 in Chromium on the walk's own photo: 4,321,364 bytes (4032x3024) went up as 459,343 bytes (1500x2000, turned
// upright from its EXIF), once, stored and answered 3.2-3.5 s after the pick on the phone network (1.5 Mbit/s up, 60 ms, CPU x2).
async function preparePhoto(file: File): Promise<File> {
  const k = fileKind(file);
  if (k !== 'photo' && k !== 'heic') return file;
  if (typeof createImageBitmap !== 'function' || typeof document === 'undefined') return file;
  try {
    const bmp = await createImageBitmap(file);
    const size = shrinkSize(bmp.width, bmp.height);
    if (!size && k === 'photo') { bmp.close?.(); return file; }
    const { w, h } = size || { w: bmp.width, h: bmp.height };
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const g = c.getContext('2d');
    if (!g) { bmp.close?.(); return file; }
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, w, h); g.imageSmoothingQuality = 'high';
    g.drawImage(bmp, 0, 0, w, h); bmp.close?.();
    const blob = await new Promise<Blob | null>((res) => c.toBlob(res, 'image/jpeg', PHOTO_QUALITY));
    if (!blob || (k === 'photo' && blob.size >= file.size)) return file;
    return new File([blob], jpegName(file.name), { type: 'image/jpeg', lastModified: Date.now() });
  } catch (_e) { return file; }
}
const fileToB64 = (f: Blob) => new Promise<string>((res) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result).split(',')[1]); rd.readAsDataURL(f); });

// pdf.js is the bundled pdfjs-dist the customer portal uses (me/pdfRaster.ts), not a runtime script
// from cdnjs: a network that blocks cdnjs made every PDF "unreadable", and the CSP can now drop it.
async function fileToImages(file: File) {
  const b64 = await fileToB64(file);
  if (file.type && file.type.startsWith('image/')) return { images: [{ mime: file.type, data: b64 }], b64, mime: file.type };
  if (file.type === 'application/pdf') {
    try { const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      const { rasterisePdf } = await import('@/components/me/pdfRaster');
      return { images: await rasterisePdf(arr), b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}
export { uploadDirect, preparePhoto, fileToB64, fileToImages };
