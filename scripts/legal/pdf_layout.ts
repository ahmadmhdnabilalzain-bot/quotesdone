// pdf_layout.ts — where text actually lies in a rendered PDF, read back out of the file itself.
//
// 14 Sep 2026, agent: accountant. Two layout faults the founder saw in the legal PDFs: text running under
// other text (the totals row, "Interest (c) at 9% p.a. …" under its amount) and a second page that was
// 80% empty (Reminder 2's totals alone). Both are measured here from the PDF, not from the renderer's
// own idea of where it drew.
//
// pdf.js is the library the repository already depends on (package.json pdfjs-dist ^4.10.38, lockfile
// 4.10.38); it is imported pinned through Deno's npm: specifier so the check needs no `npm ci` — the
// checks job has none. The worker runs on the main thread (globalThis.pdfjsWorker), so no worker file.
// deno-lint-ignore-file no-explicit-any
import * as pdfjs from 'npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs';
import * as pdfjsWorker from 'npm:pdfjs-dist@4.10.38/legacy/build/pdf.worker.mjs';
(globalThis as any).pdfjsWorker = pdfjsWorker;

const EPS = 0.75; // points; runs laid end to end on one line touch but do not overlap
const PH = 841.89, BODY_TOP = PH - 38 - 24, BODY_BOTTOM = 78; // the renderer's slim header and footer rule

type Box = { s: string; x0: number; x1: number; y0: number; y1: number; y: number };
async function pagesOf(bytes: Uint8Array): Promise<Box[][]> {
  const doc = await (pdfjs as any).getDocument({ data: bytes.slice(), disableFontFace: true, verbosity: 0, isEvalSupported: false }).promise;
  const out: Box[][] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const { items } = await (await doc.getPage(p)).getTextContent();
    out.push(items.filter((it: any) => it.str && it.str.trim() && it.width > 0).map((it: any) => {
      const size = Math.hypot(it.transform[2], it.transform[3]) || it.height || 8;
      const x = it.transform[4], y = it.transform[5];
      return { s: it.str, x0: x, x1: x + it.width, y0: y - 0.22 * size, y1: y + 0.78 * size, y };
    }));
  }
  await doc.destroy();
  return out;
}

/** Every pair of text runs on one page whose ink boxes share more than 0.75pt in both directions. */
export async function overlapsIn(bytes: Uint8Array) {
  const found: { page: number; a: string; b: string; w: number; h: number }[] = [];
  (await pagesOf(bytes)).forEach((boxes, pi) => {
    for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j];
      const w = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0), h = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      if (w > EPS && h > EPS) found.push({ page: pi + 1, a: a.s.slice(0, 50), b: b.s.slice(0, 50), w: +w.toFixed(1), h: +h.toFixed(1) });
    }
  });
  return found;
}

/** Per page, the share of the body area above the lowest line of body text (page 1 carries the cover). */
export async function pageFill(bytes: Uint8Array) {
  return (await pagesOf(bytes)).map((boxes) => {
    const ys = boxes.map((b) => b.y).filter((y) => y > BODY_BOTTOM && y < BODY_TOP);
    const low = ys.length ? Math.min(...ys) : BODY_TOP;
    return +((BODY_TOP - low) / (BODY_TOP - BODY_BOTTOM)).toFixed(3);
  });
}

/** A page after the first that is more than 70% empty, unless it is the last page of a 3+ page document. */
export function sparsePages(fill: number[]) {
  return fill.map((v, i) => ({ page: i + 1, empty: 1 - v })).filter((p, i) => i > 0 && p.empty > 0.7 && !(i === fill.length - 1 && fill.length >= 3));
}
