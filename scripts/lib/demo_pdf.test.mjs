// demo_pdf — the office plan fixture is a drawing, not four rectangles (audit 21 Sep 2026, finding 3).
// node --test scripts/lib/demo_pdf.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inflateSync } from 'node:zlib';
import { demoOfficePlan, demoOfficePlanPdf, demoOfficePlanPng, demoOfficePlanTitleBlockPx } from './demo_pdf.mjs';

/** Decode our own PNG (8-bit RGB, filter 0 on every row) back to raw pixels. */
function decodePng(buf) {
  assert.equal(buf.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'PNG signature');
  let off = 8; const idat = []; let w = 0, h = 0;
  while (off < buf.length) {
    const len = buf.readUInt32BE(off); const type = buf.subarray(off + 4, off + 8).toString();
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); assert.equal(data[8], 8); assert.equal(data[9], 2); }
    if (type === 'IDAT') idat.push(data);
    off += 12 + len;
    if (type === 'IEND') break;
  }
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * 3 + 1;
  assert.equal(raw.length, stride * h, 'raw pixel length');
  const white = (x, y) => { const o = y * stride + 1 + x * 3; return raw[o] === 255 && raw[o + 1] === 255 && raw[o + 2] === 255; };
  const black = (x, y) => { const o = y * stride + 1 + x * 3; return raw[o] === 0 && raw[o + 1] === 0 && raw[o + 2] === 0; };
  return { w, h, white, black };
}

const inkSpread = (img, x0, y0, x1, y1) => {
  const rows = new Set(), cols = new Set();
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (!img.white(x, y)) { rows.add(y); cols.add(x); }
  return { rows: rows.size, cols: cols.size };
};

test('the PNG decodes at the requested size and the plan area is dense with ink', () => {
  const img = decodePng(demoOfficePlanPng({ w: 1240, h: 880 }));
  assert.equal(img.w, 1240); assert.equal(img.h, 880);
  const tb = demoOfficePlanTitleBlockPx(1240, 880);
  // Plan area: everything above the title block strip.
  const s = inkSpread(img, 0, 0, img.w, tb.y0);
  assert.ok(s.rows > 40 && s.cols > 40, `ink in ${s.rows} rows x ${s.cols} cols — four rectangles would be far fewer`);
  const small = decodePng(demoOfficePlanPng({ w: 620, h: 440 }));
  assert.equal(small.w, 620); assert.equal(small.h, 440);
});

test('redactTitleBlock paints the title block solid black; without it the block carries text', () => {
  const tb = demoOfficePlanTitleBlockPx(1240, 880);
  const red = decodePng(demoOfficePlanPng({ redactTitleBlock: true }));
  for (let y = tb.y0; y < tb.y1; y++) for (let x = tb.x0; x < tb.x1; x++) assert.ok(red.black(x, y), `pixel ${x},${y} not black`);
  const full = decodePng(demoOfficePlanPng());
  const s = inkSpread(full, tb.x0, tb.y0, tb.x1, tb.y1);
  assert.ok(s.rows > 40 && s.cols > 40, `title block ink ${s.rows} rows x ${s.cols} cols`);
  let allBlack = true;
  for (let y = tb.y0; y < tb.y1 && allBlack; y++) for (let x = tb.x0; x < tb.x1; x++) if (!full.black(x, y)) { allBlack = false; break; }
  assert.ok(!allBlack, 'unredacted title block must not be solid black');
});

test('the PDF carries the room names and the title-block identity as text', () => {
  const pdf = demoOfficePlanPdf().toString('latin1');
  assert.ok(pdf.startsWith('%PDF-1.4') && pdf.trimEnd().endsWith('%%EOF'));
  const plan = demoOfficePlan();
  for (const room of plan.rooms) assert.ok(pdf.includes(`(${room}) Tj`), `room missing: ${room}`);
  for (const s of plan.identity) assert.ok(pdf.includes(`(${s}) Tj`), `identity missing: ${s}`);
  assert.ok(pdf.includes('(SCALE 1:100) Tj') && pdf.includes(' m ') && pdf.includes(' l S'));
});
