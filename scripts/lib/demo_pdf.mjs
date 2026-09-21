// A one-page PDF built by hand for ZZ DEMO fixtures — a trade licence, a company profile — with no
// dependency and no embedded font (Standard-14 Helvetica), so a file is ~1.5 kB.
//
// Lifted out of scripts/staging/make_fixture_licence_pdf.mjs (12 Aug 2026) on 14 Sep 2026, when the
// e2e harness (scripts/e2e/fixtures.mjs) needed the same document with per-run text: every demo
// supplier it creates carries a licence file the product can open, named for that supplier. One
// generator, two callers, rather than a second copy of the byte layout.
//
// Latin-1 only (Helvetica has no Arabic glyphs); callers keep the text ASCII. Everything printed is
// invented and says so.
//
// 21 Sep 2026 — the office fit-out PLAN (demoOfficePlan / demoOfficePlanPdf / demoOfficePlanPng).
// Audit finding 3 of 21 Sep: the founder-demo supplier downloaded a "redacted drawing" that was four
// empty rectangles. Measured cause: the fixture, not redaction — drawingPng() in founder_demo_tour.mjs
// and supplier_quote_review.mjs drew a white sheet with a plan outline and no text, and the tour
// uploaded it straight to drawing-files as the redacted page (drawing_redact never ran on it). One
// layout below feeds both a PDF with a real text layer (so _shared/pdf_text_positions.ts can read it
// and _shared/drawing_identity_text.ts can prove it boxes only the title block) and a PNG that a
// supplier can actually read: rooms, areas, dimensions, a legend, a north arrow, a scale — and a
// title block full of fixture identity that redactTitleBlock paints black.
import { deflateSync, crc32 } from 'node:zlib';

const pdfStr = (s) => String(s).replace(/([()\\])/g, '\\$1');

/**
 * lines: [text, fontSize][] top to bottom. Returns a Buffer holding a valid PDF 1.4 file.
 * opts.mediaBox — [w, h] in points (default A4 portrait); opts.content — an extra content-stream
 * string (path and text operators) written before the lines, for callers that draw.
 */
export function demoPdf(lines, { mediaBox = [595, 842], content = '' } = {}) {
  let y = 760;
  let text = content;
  if (lines.length) {
    text += 'BT\n';
    for (const [line, size] of lines) {
      text += `/F1 ${size} Tf\n1 0 0 1 60 ${y} Tm\n(${pdfStr(line)}) Tj\n`;
      y -= size + 10;
    }
    text += 'ET\n';
  }
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${mediaBox[0]} ${mediaBox[1]}] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>`,
    `<< /Length ${text.length} >>\nstream\n${text}endstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => { offsets.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`
       + offsets.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')
       + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}

/** The trade licence a ZZ DEMO supplier carries. */
export function demoTradeLicence({ company, licenceNo, issue = '15/03/2025', expiry = '14/03/2028', activity = 'General Trading' }) {
  return demoPdf([
    ['GOVERNMENT OF DUBAI', 18],
    ['DEPARTMENT OF ECONOMY AND TOURISM', 13],
    ['TRADE LICENCE', 16],
    ['', 11],
    [`Licence No.: ${licenceNo}`, 12],
    [`Company Name: ${company}`, 12],
    ['(QuotesDone fixture, not a real company)', 10],
    ['Legal Type: Limited Liability Company', 12],
    ['Issuing Authority: Dubai Department of Economy and Tourism', 12],
    ['Emirate: Dubai', 12],
    ['City: Dubai', 12],
    [`Issue Date: ${issue}`, 12],
    [`Expiry Date: ${expiry}`, 12],
    [`Activities: ${activity}`, 11],
  ]);
}

// ── the office fit-out plan ───────────────────────────────────────────────────────────────────
// Sheet coordinates: 1240 x 880 units, top-left origin (the PNG's own pixels at its default size;
// the PDF page is the same size in points with y flipped). 1 unit = 20 mm at "1:100", so the
// 800 x 560 plan is 16 000 x 11 200 mm and the room areas are the real products of their sides.
export const PLAN_W = 1240, PLAN_H = 880;

/** The layout: wall segments, thin lines (dimensions, doors, arrow), texts, and the title block. */
export function demoOfficePlan() {
  const walls = [], thin = [], texts = [];
  const rect = (x, y, w, h) => walls.push([x, y, x + w, y], [x + w, y, x + w, y + h], [x + w, y + h, x, y + h], [x, y + h, x, y]);
  const t = (x, y, text, size, kind) => texts.push({ x, y, text, size, kind });
  const MM = 20;
  const area = (w, h) => ((w * MM / 1000) * (h * MM / 1000)).toFixed(1);
  // (x, y, w, h) in sheet units, name, [label x, label y] baseline of the first line.
  const rooms = [
    [100, 100, 240, 200, 'RECEPTION'], [340, 100, 240, 200, 'MEETING ROOM 1'], [580, 100, 320, 200, 'MEETING ROOM 2'],
    [100, 300, 520, 360, 'OPEN OFFICE'], [620, 300, 280, 160, 'MANAGER'], [620, 460, 140, 200, 'PANTRY'],
    [760, 460, 140, 100, 'STORE'], [760, 560, 140, 100, 'WC'],
  ];
  for (const [x, y, w, h, name] of rooms) {
    rect(x, y, w, h);
    t(x + 14, y + h / 2 - 4, name, 11, 'room');
    t(x + 14, y + h / 2 + 14, `${area(w, h)} m2`, 10, 'room');
  }
  // Door swings: a quarter arc from the hinge plus the leaf. (hinge x, hinge y, radius, quadrant)
  const door = (hx, hy, r, sx, sy) => {
    let px = hx + r * sx, py = hy;
    for (let i = 1; i <= 8; i++) {
      const a = (Math.PI / 2) * (i / 8);
      const nx = hx + r * Math.cos(a) * sx, ny = hy + r * Math.sin(a) * sy;
      thin.push([px, py, nx, ny]); px = nx; py = ny;
    }
    thin.push([hx, hy, hx, hy + r * sy]);
  };
  door(120, 300, 50, 1, -1);   // reception -> open office
  door(360, 300, 50, 1, -1);   // meeting room 1
  door(600, 300, 50, 1, -1);   // meeting room 2
  door(620, 320, 50, 1, 1);    // manager
  door(620, 480, 50, 1, 1);    // pantry
  door(780, 460, 40, 1, 1);    // store
  door(780, 660, 40, 1, -1);   // wc
  door(200, 660, 60, 1, -1);   // entrance
  // Dimension lines with ticks and values (mm).
  const dimH = (x1, x2, y, label) => {
    thin.push([x1, y, x2, y], [x1, y - 6, x1, y + 6], [x2, y - 6, x2, y + 6]);
    t((x1 + x2) / 2 - label.length * 3, y - 5, label, 9, 'dim');
  };
  const dimV = (y1, y2, x, label) => {
    thin.push([x, y1, x, y2], [x - 6, y1, x + 6, y1], [x - 6, y2, x + 6, y2]);
    t(x - 52, (y1 + y2) / 2 + 3, label, 9, 'dim');
  };
  dimH(100, 900, 62, '16 000');
  dimH(100, 340, 84, '4 800'); dimH(340, 580, 84, '4 800'); dimH(580, 900, 84, '6 400');
  dimV(100, 660, 64, '11 200');
  dimV(100, 300, 84, '4 000'); dimV(300, 660, 84, '7 200');
  dimH(620, 760, 690, '2 800'); dimH(760, 900, 690, '2 800');
  // North arrow and scale, right of the plan.
  thin.push([1080, 200, 1080, 120], [1080, 120, 1068, 144], [1080, 120, 1092, 144], [1060, 200, 1100, 200]);
  t(1074, 112, 'N', 12, 'north');
  t(1040, 226, 'NORTH', 10, 'north');
  t(1020, 270, 'SCALE 1:100', 11, 'scale');
  t(1000, 300, 'LEVEL 12 PLAN', 11, 'scale');
  // Legend, bottom-left, with a line sample beside each entry.
  t(60, 740, 'LEGEND', 11, 'legend');
  const legend = ['P1 100mm gypsum partition', 'C1 600x600 mineral fibre ceiling', 'B1 gypsum bulkhead 300 drop'];
  legend.forEach((l, i) => { const y = 768 + i * 26; thin.push([60, y - 4, 110, y - 4]); t(124, y, l, 10, 'legend'); });
  // Title block, bottom-right: the identity a supplier must never see.
  const titleBlock = { x: 760, y: 720, w: 440, h: 140 };
  walls.push([760, 720, 1200, 720], [1200, 720, 1200, 860], [1200, 860, 760, 860], [760, 860, 760, 720]);
  const identity = ['ZZ DEMO Design Studio LLC', 'Client: ZZ DEMO Customer', 'Project: Office fit-out, Level 12',
    'Tel: +971 50 000 0001', 'Email: studio@example.invalid', 'Drawn by: A. Fixture', 'Dwg No: ZZD-A-101 Rev B'];
  identity.forEach((l, i) => t(772, 740 + i * 18, l, i === 0 ? 11 : 10, 'identity'));
  return { W: PLAN_W, H: PLAN_H, walls, thin, texts, titleBlock, identity, legend, rooms: rooms.map((r) => r[4]) };
}

/** The plan as a one-page PDF: real path operators and a real text layer (BT/Tm/Tj). */
export function demoOfficePlanPdf() {
  const p = demoOfficePlan();
  const H = p.H;
  let c = '0.12 0.24 0.35 RG\n2 w\n';
  for (const [x1, y1, x2, y2] of p.walls) c += `${x1} ${H - y1} m ${x2} ${H - y2} l S\n`;
  c += '0.6 w\n';
  for (const [x1, y1, x2, y2] of p.thin) c += `${x1.toFixed(1)} ${(H - y1).toFixed(1)} m ${x2.toFixed(1)} ${(H - y2).toFixed(1)} l S\n`;
  c += 'BT\n0 g\n';
  for (const { x, y, text, size } of p.texts) c += `/F1 ${size} Tf\n1 0 0 1 ${x} ${H - y} Tm\n(${pdfStr(text)}) Tj\n`;
  c += 'ET\n';
  return demoPdf([], { mediaBox: [p.W, p.H], content: c });
}

// 5x7 bitmap font, one hex byte per row, bit 4 = leftmost column. Enough for a drawing's Latin text;
// lowercase is drawn as uppercase and m² is written "m2" (Latin-1 keeps the PDF text layer honest).
const FONT = {
  A: '0e11111f111111', B: '1e11111e11111e', C: '0e11101010110e', D: '1e11111111111e', E: '1f10101e10101f',
  F: '1f10101e101010', G: '0e11101711110f', H: '1111111f111111', I: '0e04040404040e', J: '0702020202120c',
  K: '11121418141211', L: '1010101010101f', M: '111b1515111111', N: '11111915131111', O: '0e11111111110e',
  P: '1e11111e101010', Q: '0e11111115120d', R: '1e11111e141211', S: '0f10100e01011e', T: '1f040404040404',
  U: '1111111111110e', V: '11111111110a04', W: '1111111515150a', X: '11110a040a1111', Y: '11110a04040404',
  Z: '1f01020408101f',
  0: '0e11131519110e', 1: '040c040404040e', 2: '0e11010204081f', 3: '1f02040201110e', 4: '02060a121f0202',
  5: '1f101e0101110e', 6: '0608101e11110e', 7: '1f010204080808', 8: '0e11110e11110e', 9: '0e11110f01020c',
  ' ': '00000000000000', '.': '00000000000c0c', ',': '000000000c0408', ':': '000c0c000c0c00', '/': '01010204081010',
  '-': '0000001f000000', '+': '0004041f040400', '(': '02040808080402', ')': '08040202020408', '@': '0e11010d15150e',
};

/**
 * The plan rasterised as a PNG (RGB, no dependency). Same layout as the PDF, scaled to w x h.
 * redactTitleBlock paints the title block solid black — the page a supplier is meant to see.
 */
export function demoOfficePlanPng({ w = PLAN_W, h = PLAN_H, redactTitleBlock = false } = {}) {
  const p = demoOfficePlan();
  const sx = w / p.W, sy = h / p.H;
  const stride = w * 3 + 1;
  const px = Buffer.alloc(stride * h, 255);
  for (let y = 0; y < h; y++) px[y * stride] = 0; // filter byte: none
  const dot = (x, y, r, g, b) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const o = y * stride + 1 + x * 3; px[o] = r; px[o + 1] = g; px[o + 2] = b;
  };
  const line = (x1, y1, x2, y2, thick, [r, g, b]) => {
    x1 = Math.round(x1 * sx); y1 = Math.round(y1 * sy); x2 = Math.round(x2 * sx); y2 = Math.round(y2 * sy);
    const dx = Math.abs(x2 - x1), dy = -Math.abs(y2 - y1), stepX = x1 < x2 ? 1 : -1, stepY = y1 < y2 ? 1 : -1;
    let err = dx + dy, x = x1, y = y1;
    for (;;) {
      for (let i = 0; i < thick; i++) for (let j = 0; j < thick; j++) dot(x + i, y + j, r, g, b);
      if (x === x2 && y === y2) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += stepX; }
      if (e2 <= dx) { err += dx; y += stepY; }
    }
  };
  const INK = [30, 60, 90], BLACK = [0, 0, 0];
  for (const l of p.walls) line(...l, Math.max(1, Math.round(2 * sx)), INK);
  for (const l of p.thin) line(...l, 1, INK);
  // Text: 5x7 glyphs scaled 2x (then by the sheet scale), baseline-anchored like the PDF's Tm.
  const glyph = 2 * sx;
  for (const { x, y, text } of p.texts) {
    let cx = x * sx;
    for (const ch of String(text).toUpperCase()) {
      const rows = FONT[ch] || FONT[' '];
      for (let r = 0; r < 7; r++) {
        const bits = parseInt(rows.slice(r * 2, r * 2 + 2), 16);
        for (let c = 0; c < 5; c++) {
          if (!(bits & (0x10 >> c))) continue;
          const gx = Math.round(cx + c * glyph), gy = Math.round(y * sy - (7 - r) * glyph);
          for (let i = 0; i < Math.ceil(glyph); i++) for (let j = 0; j < Math.ceil(glyph); j++) dot(gx + i, gy + j, ...BLACK);
        }
      }
      cx += 6 * glyph;
    }
  }
  if (redactTitleBlock) {
    const { x, y, w: tw, h: th } = p.titleBlock;
    for (let yy = Math.floor(y * sy); yy < Math.ceil((y + th) * sy); yy++) {
      for (let xx = Math.floor(x * sx); xx < Math.ceil((x + tw) * sx); xx++) dot(xx, yy, ...BLACK);
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(px)), chunk('IEND', Buffer.alloc(0))]);
}

/** The title block's pixel rectangle at a given PNG size — for tests and for anyone checking the mask. */
export function demoOfficePlanTitleBlockPx(w = PLAN_W, h = PLAN_H) {
  const { x, y, w: tw, h: th } = demoOfficePlan().titleBlock;
  return { x0: Math.floor(x * w / PLAN_W), y0: Math.floor(y * h / PLAN_H), x1: Math.ceil((x + tw) * w / PLAN_W), y1: Math.ceil((y + th) * h / PLAN_H) };
}
