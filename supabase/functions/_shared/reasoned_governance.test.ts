// reasoned_governance.test.ts — batch B7 (trade_glossary_ar): Arabic is written by reasoning, with a MOCKED model.
// No network, no env, no paid call. Every branch: answered, cached, held (no guess), partial (held, not half),
// English (untouched), and the queue row the replay acts on (surface, subject.sources, dedupeKey).
import { assert, assertEquals } from 'jsr:@std/assert';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { ARABIC_SURFACE, arabicOf, arabicPairs, arabicQuestion, arabicTextsFor, batches, nativeArabic, needsArabic } from './reasoned_governance.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'translate each line natively', needs_knowledge: false }], facts: [], high_stakes: false });
const synth = (pairs: Record<string, string>) => J({ answer: J(pairs), reasoning: ['s1: each line translated for meaning'], cited: [], confidence: 0.9 });

function mock(o: { gate?: unknown; replies?: Partial<Record<Phase, string[]>>; cached?: Record<string, string>; throwOnLlm?: boolean }) {
  const rpcs: [string, Record<string, unknown>][] = []; const llm: Phase[] = [];
  const q: Record<string, string[]> = JSON.parse(J(o.replies ?? {}));
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.gate ?? { allowed: true, rule: 'ok' }) as GateAnswer),
    llm: (phase) => { llm.push(phase); if (o.throwOnLlm) throw new Error('boom'); const c = q[phase]?.shift(); return Promise.resolve((c ? { content: c, model: 'mock' } : { content: null, error: 'no mock reply' }) as LlmReply); },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_arabic_translations') return Promise.resolve({ data: o.cached ?? {}, error: null });
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 77, error: null });
      return Promise.resolve({ data: 1, error: null });
    },
  };
  return { deps, rpcs, llm };
}
const HOLD = { allowed: false, rule: 'founder_hold', held: 1, routes: 8 };
// A stand-in document builder with the contract quote_documents' builders have: lines it cannot print are `untranslated`.
const LINES = ['Supply and install 18mm MR MDF wardrobes', 'Painting of walls excluded', 'مطابق'];
const build = (ar: Record<string, string>) => ({ body: LINES.map((l) => ar[l] ?? l), untranslated: LINES.filter((l) => needsArabic(l) && !ar[l]) });

Deno.test('answered: the lines are reasoned, stored in the cache, and the document is built wholly in Arabic', async () => {
  const m = mock({ replies: { decompose: [PLAN], synthesise: [synth({ 1: 'توريد وتركيب خزائن من MDF مقاوم للرطوبة بسماكة 18 مم', 2: 'دهان الجدران غير مشمول' })] } });
  const r = await nativeArabic(m.deps, build, { subject: { quote_id: 'zz-demo' } });
  assertEquals(r.held, false);
  assertEquals(r.doc!.body, ['توريد وتركيب خزائن من MDF مقاوم للرطوبة بسماكة 18 مم', 'دهان الجدران غير مشمول', 'مطابق']);
  const store = m.rpcs.find(([f]) => f === 'fn_arabic_translation_store')!;
  assertEquals(Object.keys(store[1].p_pairs as object), LINES.slice(0, 2));
  assert(m.llm.includes('synthesise'));
});

Deno.test('cached: a line reasoned before is served from public.arabic_translation with no model call', async () => {
  const m = mock({ cached: { [LINES[0]]: 'خزائن', [LINES[1]]: 'دهان' } });
  const r = await nativeArabic(m.deps, build);
  assertEquals(r.doc!.body, ['خزائن', 'دهان', 'مطابق']);
  assertEquals(m.llm, []);
});

Deno.test('held (the founder\'s model hold): no guess, no half-translated document, the lines are filed for the replay', async () => {
  const m = mock({ gate: HOLD });
  const r = await nativeArabic(m.deps, build, { subject: { quote_id: 'zz-demo' } });
  assertEquals(r.doc, null);
  assertEquals(r.held, true);
  assertEquals(r.missing, LINES.slice(0, 2));
  assertEquals(m.llm, [], 'no model is called under the hold');
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals(hold[1].p_surface, ARABIC_SURFACE);
  assertEquals(hold[1].p_seat, 'sales_engineer');
  assertEquals((hold[1].p_subject as { sources: string[] }).sources, LINES.slice(0, 2), 'the replay stores the Arabic against exactly these sources');
  assertEquals((hold[1].p_subject as { quote_id: string }).quote_id, 'zz-demo');
  assert(String(hold[1].p_dedupe_key).startsWith('arabic:'), 'one held row per batch of lines');
  assert(!m.rpcs.some(([f]) => f === 'fn_arabic_translation_store'), 'nothing is stored that was not reasoned');
});

Deno.test('partial: a model answer that leaves a line without Arabic holds the document rather than printing it half-translated', async () => {
  const m = mock({ replies: { decompose: [PLAN], synthesise: [synth({ 1: 'توريد وتركيب خزائن', 2: 'Painting of walls excluded' })] } });
  const r = await nativeArabic(m.deps, build);
  assertEquals(r.doc, null);
  assertEquals(r.missing, [LINES[1]]);
  assertEquals(Object.keys(m.rpcs.find(([f]) => f === 'fn_arabic_translation_store')![1].p_pairs as object), [LINES[0]], 'only the Arabic line is cached');
});

Deno.test('English: nothing needs translating, nothing is called', async () => {
  const m = mock({});
  const r = await nativeArabic(m.deps, () => ({ body: 'x', untranslated: [] }));
  assertEquals(r.held, false);
  assertEquals(m.rpcs, []);
  assertEquals(await arabicTextsFor(m.deps, 'en', ['Wardrobe']), undefined);
});

Deno.test('a message never waits on reasoning: a failure leaves the words to be quoted as written', async () => {
  const m = mock({ throwOnLlm: true });
  const deps = { ...m.deps, rpc: () => { throw new Error('db down'); } } as ThinkDeps;
  assertEquals(await arabicTextsFor(deps, 'ar', ['Wardrobe']), {});
});

Deno.test('format helpers: the question asks for one JSON object; pairs keep only Arabic; batches respect the reply cap', () => {
  assert(arabicQuestion(['a', 'b']).includes('1. a\n2. b'));
  assertEquals(arabicPairs(['a', 'b', 'c'], '```json\n{"1":"أ","2":"x","4":"د"}\n```'), { a: 'أ' });
  // a line that is only a code/model/brand, kept exactly as written by the model, IS its answer (else held for ever)
  assertEquals(arabicPairs(['IP65', 'Daikin FTKF50TV', 'MDF board', 'Painting of walls excluded'], '{"1":"IP65","2":"Daikin FTKF50TV","3":"MDF board","4":"Painting of walls excluded"}'),
    { IP65: 'IP65', 'Daikin FTKF50TV': 'Daikin FTKF50TV' }, 'prose echoed back is not an answer; a code kept as written is');
  assertEquals(arabicPairs(['a'], 'not json'), {});
  assertEquals(batches(['x'.repeat(400), 'y'.repeat(300), 'z'], 600).map((b) => b.length), [1, 2]);
  assertEquals(needsArabic('مطابق'), false);
  assertEquals(needsArabic('12.5'), false);
  assertEquals(needsArabic('MDF'), true);
});

Deno.test('arabicOf de-duplicates and trims before it reasons', async () => {
  const m = mock({ gate: HOLD });
  const r = await arabicOf(m.deps, { texts: [' Wardrobe ', 'Wardrobe', ''] });
  assertEquals(r.missing, ['Wardrobe']);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_hold').length, 1);
});

Deno.test('a request path never waits on a model: the cache answers, the rest is FILED for the replay', async () => {
  const m = mock({ cached: { Wardrobe: 'خزانة' }, replies: { decompose: [PLAN] } });
  const r = await arabicOf(m.deps, { texts: ['Wardrobe', 'Kitchen base unit'], fileOnly: true });
  assertEquals(r.map, { Wardrobe: 'خزانة' });
  assertEquals(r.missing, ['Kitchen base unit']);
  assertEquals(m.llm, [], 'no model call on a request path, even with the gate open');
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals([hold[1].p_surface, (hold[1].p_subject as { sources: string[] }).sources], [ARABIC_SURFACE, ['Kitchen base unit']]);
  assertEquals((hold[1].p_request as { surface: string; research: boolean }).research, false, 'the replay re-runs exactly the request think() would have run');
});
