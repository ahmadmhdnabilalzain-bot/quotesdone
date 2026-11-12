// WHAT A FILE CAN BE, SAID THE MOMENT HE PICKS IT (12 Nov 2026, customer_support; browser perfection walk B1, M1, M2;
// founder ruling 1645: "if you notice ... some buttons are not clickable ... I'm looking for perfection").
//
// Measured on production at 390x844 with the certification's phone network: a .docx picked as the licence waited for the server
// and was answered "Could not load this section. Please try again."; a HEIC photo waited 25.5-27.9 s for the same sentence; an
// empty PDF was announced "Licence uploaded"; a 4.32 MB phone photo (4032x3024) went as a 17.29 MB request and was cut off after
// 102 s. The browser now refuses what the server would refuse, at once and in a true sentence, and makes a phone photo small
// before it leaves: the long edge at most PHOTO_MAX_EDGE, JPEG. A PDF is never touched.
//
// The types are the server's: the licence gate is SAFE_UPLOAD (PDF, JPEG, PNG, WebP), a profile or catalogue is
// SAFE_SUPPLIER_PAPERS (those plus Word and PowerPoint), supabase/functions/_shared/attachment.ts. The ceilings are
// api.ts MAX_READ_BYTES for the licence (it is read before the answer) and the bucket's 100 MB for a profile or catalogue.
// English only: suppliers are written to in English (ruling 1008).
// Prevented by: src/components/portal/supplier/fileCheck.test.mjs.

export const PHOTO_MAX_EDGE = 2000;
export const PHOTO_QUALITY = 0.85;
export const LICENCE_MAX_BYTES = 10 * 1024 * 1024;
export const PAPER_MAX_BYTES = 100 * 1024 * 1024;
export const LICENCE_ACCEPT = 'image/*,application/pdf';
export const PAPER_ACCEPT = '.pdf,.docx,.pptx,.jpg,.jpeg,.png,.webp,image/*';

type Picked = { name?: string; type?: string; size?: number };
export type FileKind = 'pdf' | 'photo' | 'heic' | 'word' | 'powerpoint' | 'other';
const ext = (f: Picked) => (/\.([a-z0-9]{1,8})$/i.exec(String(f.name || ''))?.[1] || '').toLowerCase();

/** What the picked file is, by its type and, when the browser gives none, its name. */
export function fileKind(f: Picked): FileKind {
  const t = String(f.type || '').toLowerCase(); const e = ext(f);
  if (t === 'application/pdf' || (!t && e === 'pdf')) return 'pdf';
  if (t === 'image/heic' || t === 'image/heif' || e === 'heic' || e === 'heif') return 'heic';
  if (['image/jpeg', 'image/jpg', 'image/png', 'image/webp'].includes(t) || (!t && ['jpg', 'jpeg', 'png', 'webp'].includes(e))) return 'photo';
  if (t === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || (!t && e === 'docx')) return 'word';
  if (t === 'application/vnd.openxmlformats-officedocument.presentationml.presentation' || (!t && e === 'pptx')) return 'powerpoint';
  return 'other';
}

/** "4.3 MB", as a phone's Files app and Finder count them (decimal). */
export const mbText = (bytes: number) => `${Math.round((Number(bytes || 0) / 1e6) * 10) / 10} MB`;
const named = (f: Picked) => { const e = ext(f); return e ? `a .${e} file` : 'that file'; };

// Safari turns a HEIC into a JPEG in the page (upload.ts preparePhoto); this is said only where the browser cannot.
export const HEIC_SENTENCE = 'This photo is in the HEIC format, which we cannot read. Please choose a JPEG or PNG photo, or a PDF, instead.';

/**
 * Why this file cannot be the trade licence, or null when it can go (a photo is shrunk first, so its size is checked after).
 */
export function licenceFileProblem(f: Picked, { afterShrink = false } = {}): string | null {
  if (!Number(f.size || 0)) return 'That file is empty (0 bytes), so there is nothing to read. Please choose the file again: a PDF or a photo of your trade licence.';
  const k = fileKind(f);
  if (k === 'heic') return HEIC_SENTENCE;
  if (k !== 'pdf' && k !== 'photo') return `We cannot read ${named(f)} as a trade licence. Please choose a PDF or a photo (JPEG or PNG) of your licence.`;
  if ((k === 'pdf' || afterShrink) && Number(f.size) > LICENCE_MAX_BYTES) return `That file is ${mbText(Number(f.size))}. We can read a licence of up to 10 MB. Please upload a smaller copy (most PDF tools have a "reduce file size" option) or a photo of each page.`;
  return null;
}

/** Why this file cannot be a company profile or catalogue, or null. */
export function paperFileProblem(f: Picked, what = 'company profile'): string | null {
  if (!Number(f.size || 0)) return `That file is empty (0 bytes). Please choose your ${what} again.`;
  const k = fileKind(f);
  if (k === 'heic') return HEIC_SENTENCE;
  if (k === 'other') return `We cannot accept ${named(f)} as your ${what}. Please choose a PDF, a Word or PowerPoint file, or a photo (JPEG or PNG).`;
  if (Number(f.size) > PAPER_MAX_BYTES) return `That file is ${mbText(Number(f.size))}. We can take a file of up to 100 MB here. Please upload a smaller copy.`;
  return null;
}

/** The size a photo is drawn at: the long edge at most `max`, the shape kept. null when it is already small enough. */
export function shrinkSize(w: number, h: number, max = PHOTO_MAX_EDGE): { w: number; h: number } | null {
  const long = Math.max(w, h);
  if (!(long > max)) return null;
  const k = max / long;
  return { w: Math.max(1, Math.round(w * k)), h: Math.max(1, Math.round(h * k)) };
}

/** The name the shrunk photo goes by: the same name, ending .jpg. */
export const jpegName = (name: string) => (String(name || 'licence').replace(/\.[a-z0-9]{1,8}$/i, '') || 'licence') + '.jpg';
