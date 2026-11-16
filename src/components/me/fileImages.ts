// A FILE A PERSON ATTACHES -> the page images the readers take, and its own base64. One copy for both portals
// (16 Nov 2026, it_engineer; simplification wave B, SITE-09).
//
// The customer's new-request chat (me/newRequest/helpers.ts) and the supplier's quotation upload
// (portal/supplier/core/upload.ts) each had their own copy, and they had drifted: the customer's turned a HEIC, HEIF or
// multi-page TIFF photo into JPEG pages, the supplier's sent any image/* up raw, so a supplier's iPhone or scanner
// quotation reached the reader as bytes it cannot open. Guarded by src/components/portal/oneFileConverterAndOneEdgeCall.test.mjs.
//
//   photo (any image/*, or a .heic/.heif/.tif/.tiff the browser gave no type) -> JPEG pages (ocrClient.toJpegPages); it
//     throws HEIC_UNSUPPORTED where this browser cannot decode HEIC, and each caller says so in its own words;
//   PDF -> page images through the bundled pdf.js (pdfRaster), or none if it cannot be read;
//   anything else -> no pages, sent as it is.
import type { PageImage } from './ocrClient.ts';

export const fileToB64 = (f: Blob) => new Promise<string>((res) => {
  const rd = new FileReader();
  rd.onloadend = () => res(String(rd.result).split(',')[1] || '');
  rd.readAsDataURL(f);
});

export async function fileToImages(file: File): Promise<{ images: PageImage[]; b64: string; mime: string }> {
  const b64 = await fileToB64(file);
  if ((file.type && file.type.startsWith('image/')) || /\.(heic|heif|tiff?)$/i.test(file.name || '')) {
    const { toJpegPages } = await import('./ocrClient.ts');
    const images = await toJpegPages(file);
    return { images, b64: (images[0] && images[0].data) || b64, mime: (images[0] && images[0].mime) || 'image/jpeg' };
  }
  if (file.type === 'application/pdf') {
    try {
      const { rasterisePdf } = await import('./pdfRaster.ts');
      const raw = atob(b64); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
      return { images: await rasterisePdf(arr), b64, mime: 'application/pdf' };
    } catch (_e) { return { images: [], b64, mime: 'application/pdf' }; }
  }
  return { images: [], b64, mime: file.type || 'application/octet-stream' };
}
