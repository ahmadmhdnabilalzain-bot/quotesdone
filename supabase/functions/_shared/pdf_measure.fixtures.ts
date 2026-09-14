// pdf_measure.fixtures — one-page PDF drawings built in code, for pdf_measure's tests and for a later
// before/after audit that must measure byte-identical files (14 Sep 2026).
//
// The rectangle is 141.73 x 113.39 pt = 50 x 40 mm on paper = 5 x 4 m at 1:100: 20 sqm, 18 m perimeter.
// Pure functions: no I/O, no dates, no randomness.

/** A single-page PDF (1000 x 700 pt) with the given text lines and raw path operators. */
export function makeDrawingPdf(text: string[], paths: string): Uint8Array {
  const content = [...text.map((t, i) => `BT /F1 10 Tf 1 0 0 1 800 ${60 - i * 15} Tm (${t}) Tj ET`), paths].join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 1000 700] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  pdf += 'trailer << /Root 1 0 R >>\n%%EOF\n';
  return Uint8Array.from(pdf, (c) => c.charCodeAt(0) & 0xff);
}

// A sheet border (ignored by the measurer) plus the 5 x 4 m room outline.
const BORDER = '0.5 w 10 10 980 680 re S';
const ROOM = '0.7 w 100 100 141.73 113.39 re S';

/** "SCALE 1:100" and a 5 x 4 m rectangle: 20 sqm, 18 m perimeter. */
export const scaledRectPdf = () => makeDrawingPdf(['ZZ DEMO GROUND FLOOR PLAN', 'SCALE 1:100'], `${BORDER}\n${ROOM}`);
/** The same drawing with no scale printed: nothing may be measured. */
export const unscaledRectPdf = () => makeDrawingPdf(['ZZ DEMO GROUND FLOOR PLAN'], `${BORDER}\n${ROOM}`);
/** The rectangle drawn at half size under a 2x `cm`, and a second weight drawn with l/h: 20 sqm again. */
export const ctmScaledRectPdf = () => makeDrawingPdf(['ZZ DEMO PLAN', 'Scale: 1/100'],
  `${BORDER}\nq 2 0 0 2 0 0 cm 0.35 w 50 50 70.865 56.695 re S Q\nq 1.5 w 400 100 m 541.73 100 l 541.73 213.39 l 400 213.39 l h S Q`);
/** Two scales on one sheet: views cannot be told apart, nothing may be measured. */
export const twoScalesPdf = () => makeDrawingPdf(['PLAN SCALE 1:100', 'DETAIL SCALE 1:20'], ROOM);
