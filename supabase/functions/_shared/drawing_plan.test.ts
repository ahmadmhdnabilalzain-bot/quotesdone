// drawing_plan — a PDF read page by page in workers of their own reaches the SAME verdict as the whole-set read it
// replaced on analyze_drawing's request path (17 Nov 2026, sales_engineer; the measurement is in drawing_plan.ts).
// Fixtures are ZZ DEMO only: the 8-sheet mechanical set is the one scripts/e2e/drawing_reaches_suppliers.mjs builds
// (stressSetPdf(8), written with --pdf); the review sheets are the anonymity reviews' own.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { linesFromRuns, pdfPages } from './pdf_text_positions.ts';
import { seedTerms, titleBlockBoxes } from './anonymise.ts';
import { mergePlan, planBoxes, planStrips, readPdfPlan, type PlanCall } from './drawing_plan.ts';

const SEEDS = seedTerms({ name: 'ZZ Demo Drawing Customer', email: 'qd-zz-demo@example.invalid', phone: '+971500000123', extra: ['ZZ DEMO mechanical set.pdf'] });
const SET8 = new URL('./testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url);
const FIXTURES = [SET8, new URL('./testdata/review_f3/v11_two_pages_p2_no_strip.pdf', import.meta.url),
  new URL('./testdata/review_f3/v02_outlined_title_block.pdf', import.meta.url), new URL('./testdata/review_f3/v17_keyplan_label_over_pool.pdf', import.meta.url)];

/** drawing_redact's 'plan' mode, in process: what customer_api's pdfPlanCall gets back over the wire. */
const local = (bytes: Uint8Array): PlanCall => async (b) => {
  const from = Number(b.from), to = Number(b.to);
  const part = b.step === 'boxes' ? await planBoxes(bytes, from, to, b.seed_terms as string[], b.set_seeds as string[]) : await planStrips(bytes, from, to);
  return JSON.parse(JSON.stringify({ ok: true, ...part }));
};

/** What analyze_drawing computed on its request path until 17 Nov (documents.ts, the whole-set read). */
async function wholeSet(bytes: Uint8Array) {
  const pp = await pdfPages(bytes, undefined, { layers: false });
  const tb = titleBlockBoxes(pp, SEEDS);
  return { pdfWords: pp.reduce((n, pg) => n + pg.runs.length, 0), pdfLines: linesFromRuns(pp).split('\n').map((l) => l.trim()).filter(Boolean), tb };
}

Deno.test('page by page reaches the whole-set verdict: words, lines, every box, the confidence and the set seeds', async () => {
  for (const u of FIXTURES) {
    const bytes = await Deno.readFile(u), name = u.pathname.split('/').pop();
    const want = await wholeSet(bytes), got = await readPdfPlan(local(bytes), SEEDS);
    assert(got, `${name}: the plan answered`);
    assertEquals(got.pdfWords, want.pdfWords, `${name}: words`);
    assertEquals(got.pdfLines, want.pdfLines, `${name}: printed lines`);
    assertEquals(got.tb.boxes, JSON.parse(JSON.stringify(want.tb.boxes)), `${name}: boxes, page by page`);
    assertEquals(got.tb.confidence, want.tb.confidence, `${name}: confidence`);
    assertEquals(got.tb.residual, want.tb.residual, `${name}: residual, with the set's page numbers`);
    assertEquals(got.tb.setSeeds, want.tb.setSeeds, `${name}: set seeds, in order`);
  }
});

Deno.test('the 8-sheet set is read as 8 sheets, its strips name the consultant, and the verdict is not trivially empty', async () => {
  const bytes = await Deno.readFile(SET8);
  const got = (await readPdfPlan(local(bytes), SEEDS))!;
  assertEquals(got.tb.boxes.length, 8);
  assert(got.pdfWords > 1000 && got.tb.boxes.every((b) => b.length > 0), 'every sheet has words and boxes');
  assert(got.tb.setSeeds.some((s) => /zz demo consulting/i.test(s)), 'the consultant in the strip is a set seed');
});

Deno.test('one page read in its own worker costs a small part of the whole-set read (the request path\'s old cost)', async () => {
  const bytes = await Deno.readFile(SET8);
  await wholeSet(bytes); await readPdfPlan(local(bytes), SEEDS); // warm both paths: the comparison is of the work, not of compiling
  let whole = Infinity, worst = 0;
  for (let k = 0; k < 3; k++) {
    const t0 = performance.now(); await wholeSet(bytes); whole = Math.min(whole, performance.now() - t0);
    const pp = await planStrips(bytes, 0, 1), setOf = [...new Set(pp.strips.flat())];
    for (let i = 0; i < 8; i++) {
      const t1 = performance.now(); await planStrips(bytes, i, i + 1); await planBoxes(bytes, i, i + 1, SEEDS, setOf);
      worst = Math.max(worst, performance.now() - t1);
    }
  }
  assert(worst < whole * 0.5, `the heaviest one-sheet call ${worst.toFixed(0)} ms vs the whole set ${whole.toFixed(0)} ms`);
});

Deno.test('any part that does not answer, or answers out of shape, gives the whole read up (the old parse failure)', async () => {
  const bytes = await Deno.readFile(SET8);
  const good = local(bytes);
  const failing = (bad: (b: Record<string, unknown>) => unknown): PlanCall => async (b) => { const x = bad(b); return x === undefined ? await good(b) : x; };
  const cases: [string, PlanCall][] = [
    ['first call refused', failing((b) => (b.from === 0 && b.step === 'strips' ? null : undefined))],
    ['a later page 546s', failing((b) => (b.from === 5 && b.step === 'strips' ? null : undefined))],
    ['a boxes call throws', failing((b) => { if (b.step === 'boxes' && b.from === 3) throw new Error('timeout'); return undefined; })],
    ['a boxes answer short of a page', failing((b) => (b.step === 'boxes' && b.from === 2 ? { ok: true, from: 2, boxes: [], low: false, residual: [], setSeeds: [] } : undefined))],
    ['a strips answer with another page count', failing((b) => (b.step === 'strips' && b.from === 4 ? { ok: true, pages: 9, from: 4, words: [1], lines: [''], strips: [[]] } : undefined))],
    ['ok:false', failing((b) => (b.step === 'boxes' && b.from === 7 ? { ok: false, error: 'WORKER_RESOURCE_LIMIT' } : undefined))],
  ];
  for (const [what, call] of cases) assertEquals(await readPdfPlan(call, SEEDS), null, what);
});

Deno.test('a file with no pages reads as no words and no server boxes, as before', async () => {
  const call: PlanCall = async (b) => ({ ok: true, pages: 0, from: b.from, words: [], lines: [], strips: [] });
  const got = (await readPdfPlan(call, SEEDS))!;
  assertEquals(got.pdfWords, 0);
  assertEquals(got.tb.confidence, 'low');
  assertEquals(mergePlan([], [], SEEDS).tb.boxes, []);
});

Deno.test('a part that fails once (a cold worker, a timeout) is asked once more and the verdict is the whole-set one (review, 17 Nov)', async () => {
  const bytes = await Deno.readFile(SET8);
  const good = local(bytes), seen = new Set<string>(); let calls = 0;
  const flaky: PlanCall = async (b) => { calls++; const k = `${b.step}:${b.from}`; if (!seen.has(k) && (b.from === 3 || b.from === 6)) { seen.add(k); if (b.step === 'boxes') throw new Error('timeout'); return null; } return await good(b); };
  const got = await readPdfPlan(flaky, SEEDS), want = await wholeSet(bytes);
  assert(got, 'recovered');
  assertEquals(got.tb.boxes, JSON.parse(JSON.stringify(want.tb.boxes)));
  assertEquals(calls, 16 + 4, 'two parts of each step failed once and were asked once more');
});

Deno.test('setOf never boxes a page with fewer seeds than the page alone (an empty set_seeds is not a weaker read)', async () => {
  const pp = await pdfPages(await Deno.readFile(SET8), [0, 1], { layers: false });
  const alone = titleBlockBoxes([pp[0]], SEEDS), empty = titleBlockBoxes([pp[0]], SEEDS, []);
  assertEquals(empty.boxes, alone.boxes); assertEquals(empty.setSeeds, alone.setSeeds);
});
