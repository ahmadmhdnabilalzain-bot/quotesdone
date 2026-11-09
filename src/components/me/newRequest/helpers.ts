// @ts-nocheck
'use client';

const DICT_NAME = { en: { en: 'English', ar: 'Arabic' }, ar: { en: 'الإنجليزية', ar: 'العربية' } };

export const fileB64 = (f) => new Promise((res) => { const rd = new FileReader(); rd.onloadend = () => res(String(rd.result).split(',')[1] || ''); rd.readAsDataURL(f); });
export async function fileToImages(file) {
  const b64 = await fileB64(file);
  // Photos (incl. HEIC and multi-page TIFF) become JPEG pages in this browser; ocrClient throws
  // HEIC_UNSUPPORTED where the browser cannot decode HEIC, which onFile tells the customer.
  if ((file.type && file.type.startsWith('image/')) || /\.(heic|heif|tiff?)$/i.test(file.name || '')) {
    const { toJpegPages } = await import('../ocrClient');
    const images = await toJpegPages(file);
    return { images, b64: (images[0] && images[0].data) || b64, mime: (images[0] && images[0].mime) || 'image/jpeg' };
  }
  if (file.type === 'application/pdf') {
    try {
      const { rasterisePdf } = await import('../pdfRaster');
      const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      return { images: await rasterisePdf(arr), b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}
// ATTACH A BOQ (founder, 14 Sep 2026). A spreadsheet goes to analyze_boq (cells read with no model);
// a PDF BOQ is read like a drawing, from its text layer. BOQ_ERR maps the server's refusal to words.
// 14 Sep 2026 ("the sales agent need to be extremely capable of reading all types of document"): every
// document drawing_boq's 'document' mode reads goes to analyze_document; PDFs, photos and DWG keep the
// drawing path (redacted pages for suppliers).
export const DOC_RE = /\.(xlsx|xlsm|xls|csv|ods|docx?|pptx|odt|odp|rtf|txt|eml|msg|xml|x8[1-6]|zip|dxf)$/i;
// Founder ruling 28 Sep 2026: a drawing is PDF or CAD (DWG/DXF) only. The server refuses the rest the same way
// (supabase/functions/_shared/drawing_format.ts); refused here first so nothing is uploaded.
export const REFUSED_DRAWING_RE = /\.(rvt|rfa|rte|rft|ifc|ifczip|ifcxml|dgn|dgnlib|dwf|dwfx|skp|3dm|nwd|nwc|nwf|step|stp|pln)$/i;
export const BOQ_ERR = { file_too_large: 'nr_boq_err_too_large', unsafe_file_content: 'nr_boq_err_macro', encrypted: 'nr_boq_err_encrypted', file_type_not_allowed: 'nr_boq_err_type', unsafe_file_type: 'nr_boq_err_type', drawing_format_not_accepted: 'nr_drawing_format' };

// A question may arrive as a sentence or as {key, text|question|label}; the chip needs text.
export const qText = (q) => (q == null ? '' : typeof q === 'string' ? q : String(q.text || q.question || q.label || q.key || ''));
// readiness is {filled, required} from the rebuilt intake or a 0-100 number from the old one.
// After this long the indicator says the turn is still being worked on (the server's own budget is 24 s).
export const SLOW_TURN_MS = 12000;
// One id per customer message, sent again on a retry (inquiry_intake/turn_clock.ts turnIdOf: 6-64 of [A-Za-z0-9_-]).
export const newTurnId = () => 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
// The turn never reached us: the wait ran out, the connection dropped, or the edge answered with a page that is not
// JSON (a 504). An answer the function itself gave (rate limit, a refusal) is not this, and is shown as before.
export const turnNotReached = (r) => !r || r.error === 'qd_timeout' || r.error === 'qd_network' || (r.error === 'qd_bad_response' && !(Number(r.status) >= 400 && Number(r.status) < 500));
export const readinessPct = (r) => {
  if (r && typeof r === 'object') { const req = Number(r.required); return req > 0 ? Math.round((Math.min(Number(r.filled) || 0, req) / req) * 100) : null; }
  const n = Number(r); return Number.isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : null;
};
export { DICT_NAME };
