// The ZZ DEMO fixtures of evidence run ea40c830 (10 Nov 2026), shared by drawing_identity_ocr_misread.test.ts and
// customer_api/drawing_send_gate.test.ts: journey 2's HVAC sheet M-101 rebuilt with demoPdf (a real text layer, the same
// title strip as the harness drew it, so no binary is committed), and the 13 lines the live run's take-off held after the
// portal OCR'd the rendered sheet (inquiry_intake brief.boq_check.lines[].description, verbatim; "Mir. 22 Demo Owner" is
// tesseract's reading of "Mr. ZZ Demo Owner"). Every name, number and address in them is a ZZ DEMO fixture.
// deno-lint-ignore no-explicit-any
const demo: any = await import('../../../scripts/lib/demo_pdf.mjs');

/** journey 2's sheet: A3 landscape, plan and schedule on the left, the title strip right of a border at x = 985 pt. */
export function hvacSheetPdf(): Uint8Array {
  const W = 1191, H = 842;
  const t = (x: number, y: number, s: string, size = 9) => `/F1 ${size} Tf\n1 0 0 1 ${x} ${H - y} Tm\n(${s.replace(/[()\\]/g, (c) => '\\' + c)}) Tj\n`;
  let c = '0 G\n1 w\n20 20 m 1171 20 l S\n1171 20 m 1171 822 l S\n1171 822 m 20 822 l S\n20 822 m 20 20 l S\n985 20 m 985 822 l S\nBT\n0 g\n';
  c += t(30, 40, 'GROUND FLOOR AND FIRST FLOOR - HVAC LAYOUT (DUCTED SPLIT SYSTEM)', 12);
  const rooms: [number, number, string, string, string][] = [
    [40, 120, 'MAJLIS', '48 m2', 'DSU-01 3.0TR'], [270, 120, 'LIVING / DINING', '62 m2', 'DSU-02 3.0TR'],
    [520, 120, 'MASTER BEDROOM', '44 m2', 'DSU-04 2.5TR'], [760, 120, 'BEDROOM 2', '22 m2', 'DSU-05 2.0TR'],
    [40, 300, 'KITCHEN', '24 m2', ''], [270, 300, 'GUEST BEDROOM', '26 m2', 'DSU-03 2.5TR'],
    [520, 300, 'FAMILY LOUNGE', '38 m2', 'DSU-06 2.0TR'], [760, 300, 'BEDROOM 3', '21 m2', 'DSU-05 2.0TR'],
  ];
  for (const [x, y, name, area, unit] of rooms) { c += t(x, y, name, 10) + t(x, y + 14, area) + t(x + 10, y + 30, 'GI DUCT 500x300', 8); if (unit) c += t(x + 120, y, unit); }
  c += t(30, 460, 'SCALE 1:100 ALL DUCT SIZES IN MM UNITS CONCEALED ABOVE FALSE CEILING');
  c += t(30, 520, 'EQUIPMENT SCHEDULE', 10) + t(30, 536, 'TAG') + t(110, 536, 'DESCRIPTION') + t(300, 536, 'CAPACITY') + t(380, 536, 'AREA SERVED') + t(520, 536, 'QTY');
  const sched: [string, string, string, string, string][] = [
    ['DSU-01', 'Ducted split unit, inverter', '3.0 TR', 'Majlis', '1'], ['DSU-02', 'Ducted split unit, inverter', '3.0 TR', 'Living / Dining', '1'],
    ['DSU-03', 'Ducted split unit, inverter', '2.5 TR', 'Guest bedroom + kitchen', '1'], ['DSU-04', 'Ducted split unit, inverter', '2.5 TR', 'Master bedroom', '1'],
    ['DSU-05', 'Ducted split unit, inverter', '2.0 TR', 'Bedrooms 2 + 3', '1'], ['DSU-06', 'Ducted split unit, inverter', '2.0 TR', 'Family lounge', '1'],
    ['EF-01..05', 'Bathroom exhaust fan', '150 m3/h', 'Bathrooms', '5'], ['TH-01..06', 'Wall thermostat', 'Digital', 'Each unit', '6'],
  ];
  sched.forEach((r, i) => { const y = 552 + i * 16; c += t(30, y, r[0]) + t(110, y, r[1]) + t(300, y, r[2]) + t(380, y, r[3]) + t(520, y, r[4]); });
  c += t(600, 600, 'LEGEND', 10) + t(600, 616, 'SD - Supply diffuser 600x600 (38 nos total incl. return grilles RG)') + t(600, 632, 'RG - Return grille 600x300')
    + t(600, 648, 'Refrigerant piping copper, insulated (approx. 120 m)') + t(600, 664, 'Condensate drain uPVC 32 mm (approx. 60 m)');
  const strip = ['CONSULTANT', 'ZZ DEMO MEP CONSULTANTS', 'Office 000, ZZ Tower, Dubai', 'Tel +971 4 000 0000', 'MOB +971 50 000 0094', 'zz.mep@example.invalid', '',
    'CLIENT', 'ZZ DEMO PRIVATE VILLA', 'Mr. ZZ Demo Owner', 'Plot 000-0000, Al Barsha South', '', 'PROJECT', 'G+1 PRIVATE VILLA - MEP WORKS', '',
    'DRAWING', 'HVAC LAYOUT - GF AND FF', '', 'DRG NO.', 'M-101 REV 0', '', 'DATE', '01/11/2026', '', 'NOTE', 'ZZ DEMO FIXTURE - NOT A REAL PROJECT'];
  strip.forEach((s, i) => { if (s) c += t(995, 60 + i * 16, s, 8); });
  c += 'ET\n';
  return new Uint8Array(demo.demoPdf([], { mediaBox: [W, H], content: c }));
}

/** The live run's take-off of the OCR'd sheet, as inquiry_intake recorded it (brief.boq_check.lines[].description). */
export const LIVE_OCR_LINES = [
  'MAJLIS DsU-013.07R | | LIVING ١ DINING DSU- MASTER BEDROOM DSU-0425TR | | BEDROOM 2 DSU-05 2.0TR Mir. 22 Demo Owner',
  'M-101 REV',
  'KITCHEN GUEST BEDROOM FAMILY LOUNGE 050-06 | | BEDROOM 3 DSU-05 2.0TR NOTE',
  '26m 3m 21m 22 DEMO FIXTURE - NOT A REAL PROJECT',
  'DSU-01 | Ducted split unit, inverter | [mais [1',
  'DSU-02 | Ducted split unit, inverter | Living / Dining',
  'DSU-03 | Ducted split unit, inverter | Guest bedroom + kitchen',
  'DSU-04 | Ducted split unit, inverter | LEGEND',
  'DSU-05 | Ducted split unit, inverter [ Bedrooms 2 + 3 SD - Supply diffuser 600x600 (38 nos total incl. return grilles RG',
  'DSU-06 | Ducted split unit, inverter | Family lounge Re ‏ار‎ gre 00300',
  'EF-01.05 | Bathroom exhaust fan | 150 mh Refrigerant piping copper, insulated (approx. )',
  'Condensate drain uPVC 32 mm (approx. )',
  'TH-01..06 | Wall thermostat [Oigtal [Eachumt Je | GI ductwork with 25 mm insulation (approx. ?)',
];
/** Indices of LIVE_OCR_LINES that carry the title block. */
export const IDENTITY_LINES = [0, 3];
export const boqOf = (lines: string[]) => ({ boq: lines.map((description, i) => ({ item: String(i + 1), description, qty: 1, unit: 'nos' })), summary: 'Draft take-off', assumptions: [] as string[] });
