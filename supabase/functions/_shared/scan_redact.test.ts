// scan_redact — the decisions around the OCR, with the engine replaced by what it would read. The real engine on a
// synthetic scanned sheet is scan_redact.check.ts, which runs in its own CI step.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/scan_redact.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MIN_TITLE_CONF, quarterTurn, redactScan, rgbaToBmp, type OcrLine, type Rgba } from './scan_redact.ts';
import { seedTerms } from './anonymise.ts';

const W = 2000, H = 1000;
const blank = (): Rgba => ({ w: W, h: H, rgba: new Uint8ClampedArray(W * H * 4).fill(255) });
const line = (text: string, x: number, y: number, conf = 92): OcrLine => {
  const bbox = { x0: x, y0: y, x1: x + text.length * 9, y1: y + 22 };
  let cx = x;
  const words = text.split(' ').map((t) => { const w = { text: t, conf, bbox: { x0: cx, y0: y, x1: cx + t.length * 9, y1: y + 22 } }; cx += (t.length + 1) * 9; return w; });
  return { text, conf, bbox, words };
};
const TITLE = (conf = 92) => [
  line('ZZ DEMO ORBIT CONSULTING ENGINEERS LLC', 1500, 100, conf), line('TEL +971 4 000 0017', 1500, 160, conf),
  line('CLIENT: ZZ DEMO RASHID KAREEM', 1500, 220, conf), line('DRAWN BY: ZZ DEMO DRAFTER', 1500, 280, conf),
];
const PLAN = [line('OFFICE 101', 200, 300), line('MEETING ROOM 102', 600, 300), line('LEGEND', 100, 700), line('SD - SMOKE DETECTOR', 100, 740)];
const seeds = seedTerms({ name: 'ZZ DEMO Rashid Kareem', email: 'rashid@zzdemo.example.invalid' });
/** An engine that reads `first` from the page and `second` from the painted page, upright; turned a quarter, half
 *  or three quarters (redactScan reads every page all four ways up) it reads nothing. */
const engine = (first: OcrLine[], second: OcrLine[]) => { let n = 0; return (_img: Uint8Array) => { const i = n++; return Promise.resolve(i % 4 ? [] : i === 0 ? first : second); }; };

Deno.test('a clean re-read publishes: the title strip is painted black, the plan is untouched', async () => {
  const r = await redactScan(blank(), engine([...TITLE(), ...PLAN], PLAN), seeds, { zoom: 1 });
  assert(r.ok, JSON.stringify(!r.ok && r));
  if (!r.ok) return;
  const px = (x: number, y: number) => r.image.rgba[(y * W + x) * 4];
  assertEquals(px(1600, 170), 0, 'the phone line is not black');
  assertEquals(px(1990, 990), 0, 'the title strip does not run to the edge');
  assertEquals(px(250, 310), 255, 'a room name was painted over');
});

Deno.test('identity still read on the painted page HOLDS it (fail closed)', async () => {
  const r = await redactScan(blank(), engine([...TITLE(), ...PLAN], [...PLAN, line('TEL +971 4 000 0017', 1500, 160)]), seeds, { zoom: 1 });
  assertEquals(r.ok ? 'published' : r.held, 'identity_survived_reocr');
  const r2 = await redactScan(blank(), engine([...TITLE(), ...PLAN], [...PLAN, line('RASHID', 900, 900)]), seeds, { zoom: 1 });
  assertEquals(r2.ok ? 'published' : r2.held, 'identity_survived_reocr', 'a seed read back anywhere must hold the page');
});

Deno.test(`a title block read below ${MIN_TITLE_CONF}% confidence, no title block, or too few words: HELD`, async () => {
  const low = await redactScan(blank(), engine([...TITLE(55), ...PLAN], PLAN), seeds, { zoom: 1 });
  assertEquals(low.ok ? 'published' : low.held, 'title_block_low_confidence');
  const none = await redactScan(blank(), engine([...PLAN, ...PLAN.map((l) => ({ ...l, bbox: { ...l.bbox, y0: l.bbox.y0 + 50, y1: l.bbox.y1 + 50 } }))], PLAN), seeds, { zoom: 1 });
  assertEquals(none.ok ? 'published' : none.held, 'no_title_block_found');
  const few = await redactScan(blank(), engine([line('OFFICE', 10, 10)], []), seeds, { zoom: 1 });
  assertEquals(few.ok ? 'published' : few.held, 'too_few_words');
});

Deno.test('the OCR input is a plain 24-bit BMP of the page', () => {
  const b = rgbaToBmp({ w: 3, h: 2, rgba: new Uint8ClampedArray(3 * 2 * 4).fill(200) });
  assertEquals([b[0], b[1]], [0x42, 0x4d]);
  assertEquals(new DataView(b.buffer).getUint16(28, true), 24);
  assertEquals(b.length, 54 + 12 * 2);
});

// ── second review of #967 (25 Sep 2026): fail closed ─────────────────────────────────────────────────────────────
/** An engine that reads `reads[i]` on its i-th call: calls 0-3 are the page at 0/90/180/270 degrees, 4-7 the painted one. */
const seq = (reads: OcrLine[][]) => { let n = 0; return (_img: Uint8Array) => Promise.resolve(reads[n++] ?? []); };

Deno.test('a stamp read only a quarter turn round is boxed where it stands on the upright page', async () => {
  // On the page turned 90 degrees clockwise (1000 wide, 2000 high), the stamp reads across at x' 299, y' 900: upright
  // it is a vertical strip at x 900-922, y 520-700.
  const r = await redactScan(blank(), seq([[...TITLE(), ...PLAN], [line('ZZ ORBIT ENGINEERING', 299, 900)], [], [], PLAN, [], [], []]), seeds, { zoom: 1 });
  assert(r.ok, JSON.stringify(!r.ok && r));
  if (!r.ok) return;
  const px = (x: number, y: number) => r.image.rgba[(y * W + x) * 4];
  assertEquals(px(910, 600), 0, 'the turned stamp was not boxed where it stands');
  assertEquals(px(250, 310), 255, 'a room name was painted over');
});

Deno.test('a body note with a word outside the vocabulary is boxed; one left readable on the painted page holds it', async () => {
  const note = line('BY ZZ OMEGA', 300, 850);
  const r = await redactScan(blank(), seq([[...TITLE(), ...PLAN, note], [], [], [], PLAN]), seeds, { zoom: 1 });
  assert(r.ok, JSON.stringify(!r.ok && r));
  if (r.ok) assertEquals(r.image.rgba[(860 * W + 320) * 4], 0, 'the note was not boxed');
  const held = await redactScan(blank(), seq([[...TITLE(), ...PLAN], [], [], [], [...PLAN, note]]), seeds, { zoom: 1 });
  assertEquals(held.ok ? 'published' : held.held, 'identity_survived_reocr');
});

Deno.test('text-like ink that no read word covers HOLDS the page (a stamp at 30 degrees, a smear OCR cannot read)', async () => {
  const img = blank();
  // Five glyph-sized blobs in a row in the drawing body, which no OCR reading covers.
  for (let g = 0; g < 5; g++) for (let y = 850; y < 872; y++) for (let x = 1000 + g * 20; x < 1014 + g * 20; x++) { const k = (y * W + x) * 4; img.rgba[k] = img.rgba[k + 1] = img.rgba[k + 2] = 20; }
  const r = await redactScan(img, seq([[...TITLE(), ...PLAN], [], [], [], PLAN]), seeds, { zoom: 1 });
  assertEquals(r.ok ? 'published' : r.held, 'unread_ink');
  // Read (at any orientation) and judged content, the same ink is covered and the page goes.
  const read: OcrLine = { text: 'SD SD', conf: 90, bbox: { x0: 1000, y0: 850, x1: 1094, y1: 872 }, words: [{ text: 'SD', conf: 90, bbox: { x0: 1000, y0: 850, x1: 1094, y1: 872 } }] };
  const ok = await redactScan(img, seq([[...TITLE(), ...PLAN, read], [], [], [], [...PLAN, read]]), seeds, { zoom: 1 });
  assert(ok.ok, JSON.stringify(!ok.ok && ok));
});

Deno.test('a reading at the wrong orientation does not black out content read clearly upright', async () => {
  // Upside down, "OFFICE 101" reads as junk at 66-76 (measured on the ZZ scan); upright it reads at 92. In the
  // half-turned page's pixels the room name stands at x' W-1-290 .. W-1-200, y' H-1-322 .. H-1-300.
  const bb = { x0: W - 1 - 290, y0: H - 1 - 322, x1: W - 1 - 200, y1: H - 1 - 300 };
  const junk: OcrLine = { text: 'XJQ', conf: 70, bbox: bb, words: [{ text: 'XJQ', conf: 70, bbox: bb }] };
  const r = await redactScan(blank(), seq([[...TITLE(), ...PLAN], [], [junk], [], PLAN]), seeds, { zoom: 1 });
  assert(r.ok, JSON.stringify(!r.ok && r));
  if (r.ok) assertEquals(r.image.rgba[(310 * W + 250) * 4], 255, 'the upright room name was boxed because of an upside-down misread');
});

Deno.test('quarter turns: four of them are the page again', () => {
  const img = blank();
  img.rgba[(10 * W + 20) * 4] = 7;
  let t = img;
  for (let i = 0; i < 4; i++) t = quarterTurn(t, 1);
  assertEquals([t.w, t.h, t.rgba[(10 * W + 20) * 4]], [W, H, 7]);
  const once = quarterTurn(img, 1);
  assertEquals([once.w, once.h, once.rgba[(20 * H + (H - 1 - 10)) * 4]], [H, W, 7]);
});
