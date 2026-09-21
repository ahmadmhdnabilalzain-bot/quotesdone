// drawing_set.fixtures — a SYNTHETIC ZZ DEMO CAD sheet in the exact shape of the two real US bid sets that
// scored 0 of 49 on 21 Sep 2026 (rotated 270, /Contents as an array object, text inside a Form XObject with a
// nested title-block form and a logo image, tags written the CAD way, a US-style title block). Used by
// drawing_set.test.ts (reader, take-off, redaction) and drawing_chain.test.ts (the reader's BOQ to the PDF).
// ── the synthetic sheet, written in DISPLAY coordinates (a, b = fraction across, fraction down) ─────
const W = 1728, H = 2592;            // user space (portrait); shown rotated 270 as 2592 x 1728
const DW = H, DH = W;
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (a: number, b: number, size: number, s: string) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * DW).toFixed(1)} ${((1 - b) * DH).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
const line = (a1: number, b1: number, a2: number, b2: number) => `${(a1 * DW).toFixed(1)} ${((1 - b1) * DH).toFixed(1)} m ${(a2 * DW).toFixed(1)} ${((1 - b2) * DH).toFixed(1)} l S\n`;

// A diffuser tag: the letter, then its neck size over its airflow, offsets as measured on the real plan.
const device = (a: number, b: number, letter: string, neck: string, cfm: string) => t(a, b, 11, letter) + t(a + 0.005, b - 0.003, 11, neck) + t(a + 0.005, b + 0.003, 11, cfm);
export const IDENTITY = ['(555) 010-7400', 'ZZDEMODESIGN.COM', '1039 ZZ MAIN STREET', 'ZZTOWN, CO  80550', 'ZZ DEMO CRIME LAB REMODEL', 'PROJECT NO:', 'ZZ-2018-040'];
const plan =
  line(0.915, 0.05, 0.915, 0.95) +                                            // the title-block border
  t(0.35, 0.80, 20, 'MAIN FLOOR PLAN - MECHANICAL') + t(0.35, 0.82, 11, 'SCALE:') + t(0.372, 0.82, 11, '1/8" = 1\'-0"') +
  t(0.300, 0.300, 9, 'EF') + t(0.3012, 0.3065, 9, '1') +                    // tag bubble: type over number
  t(0.600, 0.200, 9, 'EF') + t(0.6012, 0.2065, 9, '1') +                    // the same fan drawn again: still one fan
  t(0.40, 0.30, 11, 'IRH-1') + t(0.50, 0.30, 11, 'RTU1-2') + t(0.50, 0.33, 11, 'RTU1-2-H') +
  device(0.20, 0.50, 'A', '8x8', '180') + device(0.25, 0.50, 'A', '6x6', '100') + device(0.30, 0.55, 'A', '8x8', '180') +
  device(0.20, 0.60, 'B', '10x10', '--') + device(0.25, 0.60, 'B', '8x8', '--') +
  t(0.40, 0.62, 11, 'C') +                                                    // a bare letter continuing the series
  t(0.45, 0.45, 11, 'WC/L-1') + t(0.45, 0.50, 11, 'WC/L-1') + t(0.55, 0.50, 11, '(E)FCO') +
  t(0.60, 0.60, 11, '16x14 (1" LNR)') + t(0.60, 0.65, 11, '3" SS') +
  t(0.75, 0.10, 20, 'WORK NOTES:') +
  t(0.755, 0.15, 11, '1.') + t(0.762, 0.15, 11, 'PROVIDE MAN BARS AT EXTERIOR WALL PENETRATION.') +
  t(0.755, 0.17, 11, '2.') + t(0.762, 0.17, 11, 'EXISTING DUCT TO REMAIN.') +
  t(0.35, 0.45, 11, '1') + t(0.45, 0.70, 11, '1') +                           // two bubbles for note 1
  t(0.10, 0.90, 9, 'COORDINATE SHUTDOWNS WITH ZZ DEMO CRIME LAB REMODEL STAFF.') +
  t(0.10, 0.93, 9, 'LOCATION:') + t(0.15, 0.93, 9, 'ZZTOWN, CO') +
  'q /Fm2 Do Q\n';
const titleBlock = IDENTITY.map((s, i) => t(0.925, 0.10 + i * 0.04, 10, s)).join('') + t(0.93, 0.90, 30, 'M1.0') +
  t(0.925, 0.80, 10, 'MAIN FLOOR PLAN - MECHANICAL') +
  `q ${(0.05 * DW).toFixed(1)} 0 0 ${(0.03 * DH).toFixed(1)} ${(0.93 * DW).toFixed(1)} ${((1 - 0.60) * DH).toFixed(1)} cm /Im1 Do Q\n`;

export function sheetPdf(): Uint8Array {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  const stream = (dict: string, body: string) => `<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
  add('<< /Type /Catalog /Pages 2 0 R >>');                                                                  // 1
  add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');                                                          // 2
  add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Rotate 270 /Resources << /XObject << /Fm1 6 0 R >> >> /Contents 4 0 R >>`); // 3
  add('[5 0 R]');                                                                                             // 4: an ARRAY object
  add(stream('', 'q /Fm1 Do Q'));                                                                            // 5
  // Form 1: the drawing, turned to the display frame by its /Matrix (display y-up -> user space for /Rotate 270).
  add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Matrix [0 -1 1 0 0 ${H}] /Resources << /Font << /F1 8 0 R >> /XObject << /Fm2 7 0 R /Im1 9 0 R >> >>`, plan)); // 6
  add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Resources << /Font << /F1 8 0 R >> /XObject << /Im1 9 0 R >> >>`, titleBlock)); // 7: nested
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');                                             // 8
  add(stream('/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8', '\x00\xff')); // 9: the "logo"
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  out += 'trailer\n<< /Root 1 0 R >>\n%%EOF\n';
  return new TextEncoder().encode(out);
}

