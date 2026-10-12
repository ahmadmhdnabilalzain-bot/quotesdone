// licence_page_ink - does a licence page carry print, measured in code before any model is asked.
// Seat: sales_engineer. 13 Oct 2026, release operator's review of the run-4 fix.
//
// WHY. Nothing in a vision model's answer proves it read the image: a white scan or a photo of a wall can come
// back 'low' with an invented Arabic name, number and expiry. So code decodes each page and measures it first.
// A printed licence has dark strokes on a light ground: the luminance spread is wide and a measurable share of
// the page is "ink" (clearly darker than the page's own background). A blank or near-blank page has neither.
//
// THRESHOLDS, measured 13 Oct 2026. Test pages (licence_page_ink.test.ts): white A4 PNG spread 0 / ink 0;
// near-blank JPEG (grey noise +-6) spread 2.3 / ink 0; printed bars spread 77 / ink 0.138. The sandbox corpus
// (run-after-rulings-1176-1177, 22 licence images + 1 profile): lic_blank_photo.jpg spread 0 / ink 0; every real
// licence spread 21.5..48.2 / ink 0.0118..0.232, the lowest being the two Arabic-only licences
// (lic_ajman_ded_ar_png 21.5 / 0.0118, lic_fujairah_ded_ar_jpg 21.8 / 0.0123). Blank = spread under 8 OR ink
// under 0.3%: a 2.7x margin under the faintest real licence's spread and 3.9x under its ink.
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';

export const MIN_SPREAD = 8;
export const MIN_INK = 0.003;

const bytesOf = (b64: string) => Uint8Array.from(atob(String(b64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));

/** { spread, ink } of one page, or null when code cannot decode it (never judged blank on a guess). */
export async function pageInk(b64: string): Promise<{ spread: number; ink: number } | null> {
  let img: Image;
  try { const d = await Image.decode(bytesOf(b64)); if (!(d instanceof Image)) return null; img = d; } catch { return null; }
  // A sampled grid of at most ~250 x 250 points keeps a 3000 px photo inside the edge CPU budget.
  const step = Math.max(1, Math.floor(Math.max(img.width, img.height) / 250));
  const lum: number[] = [];
  for (let y = 1; y <= img.height; y += step) {
    for (let x = 1; x <= img.width; x += step) {
      const [r, g, b] = Image.colorToRGB(img.getPixelAt(x, y));
      lum.push(0.299 * r + 0.587 * g + 0.114 * b);
    }
  }
  if (!lum.length) return null;
  const sorted = [...lum].sort((a, b) => a - b);
  const bg = sorted[Math.floor(sorted.length * 0.9)]; // the page's own light ground
  const mean = lum.reduce((a, b) => a + b, 0) / lum.length;
  const spread = Math.sqrt(lum.reduce((a, v) => a + (v - mean) ** 2, 0) / lum.length);
  const ink = lum.filter((v) => v < bg - 60).length / lum.length;
  return { spread, ink };
}

/** true = every page decoded and none carries print; false = at least one page is printed; null = not measurable. */
export async function pagesBlank(pages: string[]): Promise<boolean | null> {
  if (!pages.length) return null;
  let anyUnknown = false;
  for (const p of pages) {
    const m = await pageInk(p);
    if (!m) { anyUnknown = true; continue; }
    if (m.spread >= MIN_SPREAD && m.ink >= MIN_INK) return false;
  }
  return anyUnknown ? null : true;
}
