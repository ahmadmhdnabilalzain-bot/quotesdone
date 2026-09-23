// documents.boq_arabic with a MOCKED model (think.test.ts pattern). No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { boqReadings, FILED, READS_PER_CALL, sectionReading, type ReadingStore } from './reasoned_documents.ts';
import { boqWithArabic, type BoqLine } from './boq_arabic.ts';

function mock(o: { live: boolean; choice?: string | ((input: string) => string) }) {
  const rpcs: [string, Record<string, unknown>][] = []; const llmCalls: Phase[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve(o.live ? { allowed: true } : { allowed: false, rule: 'founder_hold', held: 1, routes: 8 }) as never,
    llm: (phase, _s, input) => {
      llmCalls.push(phase);
      const choice = typeof o.choice === 'function' ? o.choice(input) : o.choice;
      const r: Record<Phase, string> = {
        decompose: JSON.stringify({ steps: [], facts: [] }),
        synthesise: JSON.stringify({ answer: 'The heading names the ceiling works of the bill.', decision: { choice }, confidence: 0.9 }),
        verify: JSON.stringify({ verdict: 'agree', problems: [] }),
        research: JSON.stringify({ queries: [] }),
      };
      return Promise.resolve({ content: r[phase], model: 'mock' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 7, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { deps, rpcs, llmCalls };
}
function store(initial: Record<string, string> = {}) {
  const saved: [string, string, string][] = []; const asked: string[][] = [];
  const s: ReadingStore = {
    remembered: (keys) => { asked.push(keys); return Promise.resolve(Object.fromEntries(keys.filter((k) => k in initial).map((k) => [k, initial[k]]))); },
    remember: (k, sec, r) => { saved.push([k, sec, r]); return Promise.resolve(); },
  };
  return { s, saved, asked };
}

Deno.test('answered: the reasoned heading is returned', async () => {
  const m = mock({ live: true, choice: 'ceilings' });
  const r = await sectionReading(m.deps, { section: 'Suspended ceiling package' });
  assertEquals(r.value, 'ceilings');
  assertEquals(r.result.status, 'answered');
});

Deno.test('answered none: a heading reasoned to be no glossary heading is none, not a guess', async () => {
  const m = mock({ live: true, choice: 'none' });
  assertEquals((await sectionReading(m.deps, { section: 'Block A — level 2' })).value, 'none');
});

Deno.test('held: no value, no model called, filed once per heading on the documents.boq_arabic surface', async () => {
  const m = mock({ live: false });
  const r = await sectionReading(m.deps, { section: '  Ceilings ' });
  assertEquals(r.value, null);
  assertEquals(r.result.status, 'held');
  assertEquals(m.llmCalls.length, 0);
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals(hold[1].p_surface, 'documents.boq_arabic');
  assertEquals(hold[1].p_seat, 'sales_engineer');
  assertEquals(hold[1].p_dedupe_key, 'boq_section:ceilings');
  assertEquals((hold[1].p_subject as Record<string, unknown>).section_key, 'ceilings');
});

Deno.test('boqReadings: remembered readings are used, new ones reasoned once and remembered', async () => {
  const m = mock({ live: true, choice: 'partitions' });
  const st = store({ ceilings: 'ceilings' });
  const r = await boqReadings(m.deps, st.s, [{ boq: [{ section: 'Ceilings' }, { section: 'Drywall' }] }, { boq: [{ section: 'drywall' }, { section: 'الأسقف' }] }]);
  assertEquals(r, { ceilings: 'ceilings', drywall: 'partitions' });
  assertEquals(st.asked, [['ceilings', 'drywall']]);
  assertEquals(st.saved, [['drywall', 'Drywall', 'partitions']]);
});

Deno.test('boqReadings under the hold: each heading is filed once, nothing guessed, the originals show', async () => {
  const m = mock({ live: false });
  const st = store();
  const r = await boqReadings(m.deps, st.s, [{ boq: [{ section: 'Ceilings' }, { section: 'Partitions' }] }]);
  assertEquals(r, { ceilings: FILED, partitions: FILED });
  assertEquals(st.saved, [['ceilings', 'Ceilings', FILED], ['partitions', 'Partitions', FILED]]);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_hold').length, 2);
  // FILED prints nothing: the heading shows its original words.
  assertEquals(boqWithArabic({ boq: [{ section: 'Ceilings' }] as BoqLine[] }, r).boq[0].section_ar, null);
});

Deno.test('a read whose headings are all remembered (read or filed) calls neither the gate nor think', async () => {
  const m = mock({ live: false });
  const st = store({ ceilings: 'ceilings', partitions: FILED });
  await boqReadings(m.deps, st.s, [{ boq: [{ section: 'Ceilings' }, { section: 'Partitions' }] }]);
  assertEquals(m.rpcs.length, 0);
  assertEquals(m.llmCalls.length, 0);
  assertEquals(st.saved, []);
});

Deno.test('a revealed (unscrubbed) BOQ is only looked up: its headings are never reasoned over or stored', async () => {
  const m = mock({ live: true, choice: 'ceilings' });
  const st = store({ ceilings: 'ceilings' });
  const r = await boqReadings(m.deps, st.s, [], [{ boq: [{ section: 'Ceilings' }, { section: 'ZZ DEMO Marsa Villa 7 fit-out' }] }]);
  assertEquals(r, { ceilings: 'ceilings' });
  assertEquals(st.asked, [['ceilings', 'zz demo marsa villa 7 fit-out']]);
  assertEquals(m.rpcs.length, 0);
  assertEquals(m.llmCalls.length, 0);
  assertEquals(st.saved, []);
});

Deno.test('boqReadings reasons at most READS_PER_CALL new headings per read', async () => {
  const m = mock({ live: false });
  const st = store();
  const rows = Array.from({ length: READS_PER_CALL + 5 }, (_, i) => ({ section: `Bill ${i + 1}` }));
  await boqReadings(m.deps, st.s, [{ boq: rows }]);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_hold').length, READS_PER_CALL);
  assert(READS_PER_CALL > 0);
});
