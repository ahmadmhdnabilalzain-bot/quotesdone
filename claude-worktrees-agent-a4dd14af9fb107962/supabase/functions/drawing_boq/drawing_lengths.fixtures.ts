// drawing_lengths.fixtures — SYNTHETIC ZZ DEMO CAD sheets that carry their layers as PDF optional content,
// in the shape measured on two real US bid sets on 22 Sep 2026 (copyrighted, never in the repo):
//  * every system on its own layer (P-SANR, P-VENT, P-EXIST-SANR, M-HVAC-DUCT, M-ANNO), written
//    `/OC /Ln BDC ... EMC` with the layer named in the page's /Properties;
//  * a below-slab sanitary run drawn DASHED with every dash exported as its own segment (13.5 pt dashes,
//    4.5 pt gaps), which summed as segments loses a quarter of the pipe;
//  * a double-line duct whose 1" liner is drawn as dashed lines 4" inside each wall (pairing a wall with
//    its liner booked a phantom "4" round");
//  * a single-line round branch, a closed duct-up box, keyed-note bubbles in boxes drawn two ways (one
//    closed path, four separate lines) and a stray note-number that is NOT in a box.
// Known answers, at the printed scale: 3" SS 19.75 ft, 2" SS 5 ft, 2" V 5 ft (1/4" = 1'-0"); 26x18 duct 50 ft,
// 8" round 20 ft (1/8" = 1'-0"); keyed note 1: 2 bubbles; note 2: 1; note 3: 1.
const W = 2592, H = 1728;                                  // 36 x 24 in, unrotated, user space y-up
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (x: number, y: number, size: number, s: string) => `BT /F1 ${size} Tf ${x} ${y} Td (${esc(s)}) Tj ET\n`;
const seg = (x1: number, y1: number, x2: number, y2: number) => `${x1} ${y1} m ${x2} ${y2} l S\n`;
const layer = (name: string, body: string, w = 1.44) => `/OC /${name} BDC q ${w} w\n${body}Q EMC\n`;
const dashes = (x1: number, x2: number, y: number, dash: number, gap: number) => {
  let s = ''; for (let x = x1; x < x2 - 1e-6; x += dash + gap) s += seg(x, y, Math.min(x + dash, x2), y); return s;
};
const box = (x: number, y: number, s: number) => `${x} ${y} ${s} ${s} re S\n`;                  // a closed path
const boxOfLines = (x: number, y: number, s: number) => seg(x, y, x + s, y) + seg(x + s, y, x + s, y + s) + seg(x + s, y + s, x, y + s) + seg(x, y + s, x, y);

const LAYERS = ['P-SANR', 'P-VENT', 'P-EXIST-SANR', 'M-HVAC-DUCT', 'M-ANNO'];

/** A waste-and-vent plan at 1/4" = 1'-0" (0.6667 real in per paper pt) with keyed notes. */
function plumbing(): string {
  return t(900, 200, 22, 'WASTE AND VENT PLAN') + t(900, 175, 9, 'SCALE: 1/4" = 1\'-0"') + t(2300, 120, 30, 'P-1.01') +
    // 3" SS: 20 dashes of 13.5 pt every 18 pt = 355.5 pt = 237 in = 19.75 ft (15 ft if the gaps were dropped).
    layer('L1', dashes(500, 860, 1000, 13.5, 4.5) + seg(1000, 1000, 1000, 1090), 1.68) + t(660, 1010, 9, '3" SS') + t(1010, 1040, 9, '2" SS') +
    layer('L2', seg(1200, 1000, 1290, 1000)) + t(1230, 1008, 9, '2" V') +                     // 90 pt = 60 in = 5 ft
    layer('L3', seg(400, 900, 1400, 900), 0.42) + t(700, 905, 9, '(E)4" SS') +              // existing: not scope
    t(2000, 1500, 18, 'WORK NOTES:') +
    t(2000, 1460, 9, '1.') + t(2020, 1460, 9, 'PROVIDE GOOSENECK TERMINATION. AT THE ROOF.') +
    t(2000, 1440, 9, '2.') + t(2020, 1440, 9, 'PROVIDE GOOSENECK TERMINATION. AT THE WALL.') +
    t(2000, 1420, 9, '3.') + t(2020, 1420, 9, 'INSTALL SOLENOID VALVE.') +
    // bubbles: note 1 twice in closed boxes, note 2 in a box of four lines, note 3 in a closed box
    layer('L5', box(596, 1196, 14) + box(996, 1296, 14) + boxOfLines(1196, 1296, 14) + box(1396, 1296, 14)) +
    t(600, 1200, 9, '1') + t(1000, 1300, 9, '1') + t(1200, 1300, 9, '2') + t(1400, 1300, 9, '3') +
    t(1600, 1300, 9, '1');                                                                     // a stray "1": not a bubble
}

/** A mechanical plan at 1/8" = 1'-0" (1.3333 real in per paper pt). */
function mechanical(): string {
  const lo = 600, hi = 600 + 19.5;                                                              // 26" apart
  return t(900, 200, 22, 'MAIN FLOOR PLAN - MECHANICAL') + t(900, 175, 9, 'SCALE: 1/8" = 1\'-0"') + t(2300, 120, 30, 'M1.0') +
    layer('L4',
      seg(200, lo, 650, lo) + seg(200, hi, 650, hi) +                                           // walls: 450 pt = 600 in = 50 ft
      seg(200, lo, 200, hi) + seg(650, lo, 650, hi) +                                           // end caps
      dashes(200, 650, lo + 3, 9, 4.5) + dashes(200, 650, hi - 3, 9, 4.5) +                       // the liner, 4" inside
      seg(900, 700, 900, 790) + seg(900, 790, 990, 790) +                                       // single-line branch: 180 pt = 20 ft
      box(1200, 1200, 12)) +                                                                    // a duct-up box: a symbol
    t(400, 606, 8, '26x18') + 'BT /F1 8 Tf 910 745 Td (8"\\330) Tj ET\n';     // Ø as the WinAnsi byte a CAD export writes
}

export function layeredSetPdf(): Uint8Array {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  const stream = (dict: string, body: string) => `<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
  add('<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R 8 0 R 9 0 R] >> >>');     // 1
  add('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');                                                   // 2
  const res = `/Resources << /Font << /F1 10 0 R >> /Properties << ${LAYERS.map((_, i) => `/L${i + 1} ${i + 5} 0 R`).join(' ')} >> >>`;
  add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] ${res} /Contents 11 0 R >>`);                // 3
  add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] ${res} /Contents 12 0 R >>`);                // 4
  for (const l of LAYERS) add(`<< /Type /OCG /Name (${l}) >>`);                                             // 5..9
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');                                            // 10
  add(stream('', plumbing()));                                                                              // 11
  add(stream('', mechanical()));                                                                            // 12
  let out = '%PDF-1.5\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  out += 'trailer\n<< /Root 1 0 R >>\n%%EOF\n';
  return new TextEncoder().encode(out);
}
