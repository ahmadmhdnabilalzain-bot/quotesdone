import { call } from '../api';
// Same as the customer portal: an inline production fallback meant an unconfigured preview let
// suppliers upload trade licences into the LIVE database. See supaEnv.
import { SUPA_ANON as ANON, SUPA_URL } from '@/lib/supaEnv';
import { uploadToSignedUrl, retryTransient } from '@/lib/signedUpload';

// UPLOADS UP TO 100 MB GO STRAIGHT TO STORAGE (19 Oct 2026, sales_engineer). Vercel caps a request body at 4.5 MB, so a
// company profile or catalogue is not sent as base64: supplier_api upload_url signs a path in the supplier's own folder,
// the file goes to it, and process_docs / save_documents are given the path (the server gates the stored bytes).
// SB() is AUTH-ONLY (src/lib/supaClient.ts), so the file goes up by hand on the signed URL (src/lib/signedUpload.ts).
// SB().storage was undefined: every profile and catalogue threw before upload and "Uploading..." never ended (27 Oct).
// A platform 502/503/546 or a dropped leg is retried (up to 3 tries, a new signed path each time): walk 41379033121 (2 Nov 2026)
// lost a whole registration to ONE 502 on the catalogue's upload_url call.
const uploadDirect = (kind: string, file: File, token: string) => retryTransient(async () => {
  const u = await call('supplier_api', { action: 'upload_url', kind, filename: file.name, mime: file.type }, token);
  if (!(u && u.ok && u.path && u.token)) return { error: u };
  const { error } = await uploadToSignedUrl(SUPA_URL, ANON, 'supplier-docs', u.path, u.token, file, file.type);
  return error ? { error: { code: 'direct_upload_failed', status: error.status } } : { path: u.path, filename: file.name, mime: file.type };
});
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
export { uploadDirect, fileToB64, fileToImages };
