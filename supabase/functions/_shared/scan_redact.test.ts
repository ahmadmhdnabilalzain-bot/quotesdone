// scan_redact — the decisions around the OCR, with the engine replaced by what it would read. The real engine on a
// synthetic scanned sheet is scan_redact.check.ts, which runs in its own CI step.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/scan_redact.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MIN_TITLE_CONF, redactScan, rgbaToBmp, type OcrLine, type Rgba } from './scan_redact.ts';
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
/** An engine that reads `first` from the page and `second` from the painted page. */
const engine = (first: OcrLine[], second: OcrLine[]) => { let n = 0; return (_img: Uint8Array) => Promise.resolve(n++ === 0 ? first : second); };

Deno.test('a clean re-read publishes: the title strip is painted black, the plan is untouched', async () => {
  const r = await redactScan(blank(), engine([...TITLE(), ...PLAN], PLAN), seeds);
  assert(r.ok, JSON.stringify(!r.ok && r));
  if (!r.ok) return;
  const px = (x: number, y: number) => r.image.rgba[(y * W + x) * 4];
  assertEquals(px(1600, 170), 0, 'the phone line is not black');
  assertEquals(px(1990, 990), 0, 'the title strip does not run to the edge');
  assertEquals(px(250, 310), 255, 'a room name was painted over');
});

Deno.test('identity still read on the painted page HOLDS it (fail closed)', async () => {
  const r = await redactScan(blank(), engine([...TITLE(), ...PLAN], [...PLAN, line('TEL +971 4 000 0017', 1500, 160)]), seeds);
  assertEquals(r.ok ? 'published' : r.held, 'identity_survived_reocr');
  const r2 = await redactScan(blank(), engine([...TITLE(), ...PLAN], [...PLAN, line('RASHID', 900, 900)]), seeds);
  assertEquals(r2.ok ? 'published' : r2.held, 'identity_survived_reocr', 'a seed read back anywhere must hold the page');
});

Deno.test(`a title block read below ${MIN_TITLE_CONF}% confidence, no title block, or too few words: HELD`, async () => {
  const low = await redactScan(blank(), engine([...TITLE(55), ...PLAN], PLAN), seeds);
  assertEquals(low.ok ? 'published' : low.held, 'title_block_low_confidence');
  const none = await redactScan(blank(), engine([...PLAN, ...PLAN.map((l) => ({ ...l, bbox: { ...l.bbox, y0: l.bbox.y0 + 50, y1: l.bbox.y1 + 50 } }))], PLAN), seeds);
  assertEquals(none.ok ? 'published' : none.held, 'no_title_block_found');
  const few = await redactScan(blank(), engine([line('OFFICE', 10, 10)], []), seeds);
  assertEquals(few.ok ? 'published' : few.held, 'too_few_words');
});

Deno.test('the OCR input is a plain 24-bit BMP of the page', () => {
  const b = rgbaToBmp({ w: 3, h: 2, rgba: new Uint8ClampedArray(3 * 2 * 4).fill(200) });
  assertEquals([b[0], b[1]], [0x42, 0x4d]);
  assertEquals(new DataView(b.buffer).getUint16(28, true), 24);
  assertEquals(b.length, 54 + 12 * 2);
});
