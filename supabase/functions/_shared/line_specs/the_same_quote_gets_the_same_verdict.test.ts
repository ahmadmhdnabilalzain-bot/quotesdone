// THE SAME QUOTATION GETS THE SAME VERDICT (sales_engineer, 2 Nov 2026).
//
// The defect, measured on the nightly journey: the identical demo quotations were held in run 41417049225 (the complete
// quote: preflight would_accept, submission spec_hold) and accepted in run 41422665440 (where the two-option quotation
// was held instead). The hold decision is made on what reasoning reads from the supplier's own words
// (reasoned_matching.ts readQuote); that reading was remembered only inside one edge worker, so the preflight and the
// submission — two requests — each asked the model again, and one field read once and not the next flipped the verdict.
//
// The model here is deliberately UNSTABLE: every second call it leaves out the thickness the line plainly states, as a
// real model at temperature 0.2 sometimes does. forgetReads() between runs is a new edge worker. With the settled
// reading (public.line_spec_reading, mocked as a Map) five runs give one verdict; without it (the control: the store
// answers nothing, as before) the same five runs flip. Mocked model and database: no network, no env, no paid call.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from '../think.ts';
import { applyReading, forgetReads, READER_VERSION, readQuote, settledRead } from '../reasoned_matching.ts';
import { assessQuote, type Line } from './assess.ts';
import { checkVerdict, gate, gateInputKey, readAndAssess, type HoldRow, type QuoteRow, type SpecRepo } from './workflow.ts';

const ev = (value: string, evidence: string) => ({ value, evidence });
const LINES: Line[] = [{ line_no: 1, description: 'Wardrobe 18mm MR MDF carcass, HPL finish', amount: 6000 }, { line_no: 2, description: 'Installation labour', amount: 800 }];
const TERMS = { lead_time: '3 weeks', warranty: '2 years on workmanship and hardware', scope: 'Supply and installation by our own team', price_ex_vat: 6800 };

/** A model that answers truthfully, except that every `flakeEvery`-th line reading drops the thickness. `store` false = the old code: nothing settled. */
function world(o: { store: boolean; flakeEvery?: number; held?: boolean }) {
  const settled = new Map<string, unknown>(); let lineReads = 0; const temps: (number | undefined)[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: true, rule: 'ok' }) as never),
    llm: (phase, sys, input, opt) => {
      temps.push(opt.temperature);
      const j = JSON.parse(input);
      if (phase !== 'synthesise') return Promise.resolve({ content: JSON.stringify({ verdict: 'agree', problems: [] }), model: 'v' });
      const q = String(j.question);
      let fields: Record<string, { value: string; evidence: string }> = {};
      if (sys.includes('installation_included (')) fields = { installation_included: ev('Supply and installation', 'Supply and installation by our own team'), installation_detail: ev('by our own team', 'installation by our own team'),
        warranty_period: ev('2 years', '2 years on workmanship'), warranty_coverage: ev('workmanship and hardware', 'workmanship and hardware'), delivery: ev('3 weeks', '3 weeks') };
      else {
        lineReads++;
        const flake = o.flakeEvery && lineReads % o.flakeEvery === 0;
        if (q.includes('LINE 1:') && q.includes('18mm')) Object.assign(fields, { L1__material: ev('MR MDF', '18mm MR MDF carcass'), L1__finish: ev('HPL', 'HPL finish') }, flake ? {} : { L1__thickness_mm: ev('18mm', '18mm MR MDF carcass') });
        else if (q.includes('LINE 1:')) Object.assign(fields, { L1__material: ev('MR MDF', 'MR MDF carcass'), L1__finish: ev('HPL', 'HPL finish') });
        if (q.includes('LINE 2:')) fields.L2__not_material = ev('Installation labour', 'Installation labour');
      }
      return Promise.resolve({ content: JSON.stringify({ answer: 'Read what is written.', reasoning: ['s1: read it'], cited: [], confidence: 0.9, decision: { fields } }), model: 'm' });
    },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn, args) => {
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (o.store && fn === 'fn_line_spec_reading_get') return Promise.resolve({ data: Object.fromEntries((args.p_keys as string[]).filter((k) => settled.has(k)).map((k) => [k, settled.get(k)])), error: null });
      if (o.store && fn === 'fn_line_spec_reading_put') { for (const r of args.p_rows as { key: string; found: unknown }[]) if (!settled.has(r.key)) settled.set(r.key, structuredClone(r.found)); return Promise.resolve({ data: 1, error: null }); }
      return Promise.resolve({ data: [], error: null });
    },
  };
  return { deps, temps, lineReads: () => lineReads, settled };
}
/** One run as a new edge worker: read the quotation, then the hold decision on it. */
async function verdict(deps: ThinkDeps, lines: Line[] = LINES) {
  forgetReads();
  const rd = await readQuote(deps, { quoteId: 'zz-demo-q', category: 'joinery', lines, terms: TERMS, requirements: null });
  const ap = applyReading(lines, null, rd);
  const a = assessQuote({ category: 'joinery', lines: ap.lines, terms: { ...TERMS, terms_spec: ap.terms_spec }, requirements: null });
  return JSON.stringify({ held: a.held, missing: a.missing.map((m) => `${m.line_no ?? 'q'}:${m.attr}`).sort() });
}

Deno.test('the same complete quotation, five runs on five workers with an unstable model: accepted all five times', async () => {
  const w = world({ store: true, flakeEvery: 2 });
  const runs = []; for (let i = 0; i < 5; i++) runs.push(await verdict(w.deps));
  assertEquals(new Set(runs).size, 1, 'one quotation, one verdict: ' + runs.join(' | '));
  assertEquals(JSON.parse(runs[0]), { held: false, missing: [] });
  assertEquals(w.lineReads(), 1, 'the model read the lines once; the four later runs used the settled reading');
  assert(w.temps.every((t) => t === 0), 'every call of the gate\'s reader asks for temperature 0: ' + JSON.stringify(w.temps));
});

Deno.test('KNOWN-BAD CONTROL: with nothing settled (the code before 2 Nov), the same five runs flip', async () => {
  const w = world({ store: false, flakeEvery: 2 });
  const runs = []; for (let i = 0; i < 5; i++) runs.push(await verdict(w.deps));
  assert(new Set(runs).size > 1, 'the control did not flip, so the test above proves nothing: ' + runs.join(' | '));
  assert(runs.some((r) => JSON.parse(r).held) && runs.some((r) => !JSON.parse(r).held));
});

Deno.test('a quotation missing a spec is held five times out of five, and the hold names the exact spec', async () => {
  const w = world({ store: true });
  const thin: Line[] = [{ ...LINES[0], description: 'Wardrobe MR MDF carcass, HPL finish' }, LINES[1]];
  const runs = []; for (let i = 0; i < 5; i++) runs.push(await verdict(w.deps, thin));
  assertEquals(new Set(runs).size, 1, runs.join(' | '));
  assertEquals(JSON.parse(runs[0]), { held: true, missing: ['1:thickness_mm'] }, 'held, and for exactly the thickness the line does not state');
});

// The preflight ("check before sending") and the submission run ONE assessment (workflow.ts readAndAssess), and the
// gate's input key does not change between them: the preflight's verdict is the submission's.
class Repo implements SpecRepo {
  quotes = new Map<string, QuoteRow>(); items = new Map<string, Line[]>(); holds: HoldRow[] = [];
  async quote(id: string) { return structuredClone(this.quotes.get(id) ?? null); }
  async lines(id: string) { return structuredClone(this.items.get(id) ?? []); }
  async saveLineSpecs(id: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]) { for (const r of rows) Object.assign(this.items.get(id)!.find((l) => l.line_no === r.line_no)!, { spec: r.spec, spec_source: r.spec_source }); }
  async updateQuote(id: string, patch: Record<string, unknown>) { Object.assign(this.quotes.get(id)!, patch); }
  async liveHold(id: string) { return this.holds.find((h) => h.quote_id === id && h.state === 'open') ?? null; }
  async insertHold(row: Omit<HoldRow, 'id'>) { const h = { ...row, id: this.holds.length + 1 } as HoldRow; this.holds.push(h); return h; }
  async updateHold(id: number, patch: Partial<HoldRow>) { Object.assign(this.holds.find((h) => h.id === id)!, patch); }
  async notify() { return []; }
  async dispatch() {}
  async log() {}
}
Deno.test('the preflight and the submission give one verdict, on new workers, with an unstable model', async () => {
  const w = world({ store: true, flakeEvery: 2 });
  const repo = new Repo();
  repo.quotes.set('zz-demo-q', { id: 'zz-demo-q', inquiry_id: 'inq-zz-demo', supplier_id: 900001, status: 'draft', option_no: 1, submission_id: 's1', quote_amount: 6800, ...TERMS });
  repo.items.set('zz-demo-q', structuredClone(LINES));
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZ-1', read: (qr: QuoteRow, ls: Line[]) => readQuote(w.deps, { quoteId: qr.id, category: 'joinery', lines: ls, terms: qr, requirements: null }) };
  const key0 = await gateInputKey((await repo.quote('zz-demo-q'))!, await repo.lines('zz-demo-q'), ctx);
  forgetReads();
  const pre = await readAndAssess(repo, 'zz-demo-q', ctx);
  assertEquals(repo.quotes.get('zz-demo-q')!.terms_spec, undefined, 'the preflight writes nothing');
  forgetReads();
  const sub = await gate(repo, 'zz-demo-q', { id: 900001, email: 'zz-demo@example.invalid', locale: 'en' }, ctx);
  assertEquals([pre.a.held, sub.held, sub.missing], [false, false, []]);
  // a resubmission of the same quotation (new submission id, new status) has the same gate input key
  const again = { ...(await repo.quote('zz-demo-q'))!, submission_id: 's2', status: 'submitted', terms_spec: null };
  assertEquals(await gateInputKey(again, LINES, ctx), key0);
  assertNotEquals(await gateInputKey({ ...again, lead_time: '4 weeks' }, LINES, ctx), key0, 'a changed quotation is a new key');
  assertNotEquals(await gateInputKey(again, LINES, { ...ctx, now: () => new Date(Date.now() + 864e5) }), key0, 'tomorrow is a new key (a stated date is judged against today)');
});

// Review of #1799: a held reading (the model hold, a gateway blip) gives a hold that asks everything. It is not THE
// verdict on the quotation: it is neither stored nor compared, so when the hold lifts the settled verdict is the first.
Deno.test('a held reading is not stored as the verdict, and the settled verdict after the hold lifts raises no mismatch', async () => {
  const held = world({ store: true, held: true });
  const repo = new Repo();
  repo.quotes.set('zz-demo-q', { id: 'zz-demo-q', inquiry_id: 'inq-zz-demo', supplier_id: 900001, status: 'draft', option_no: 1, submission_id: 's1', quote_amount: 6800, ...TERMS });
  repo.items.set('zz-demo-q', structuredClone(LINES));
  const ctxOf = (d: ThinkDeps) => ({ category: 'joinery', requirements: null, ref: 'ZZ-1', read: (qr: QuoteRow, ls: Line[]) => readQuote(d, { quoteId: qr.id, category: 'joinery', lines: ls, terms: qr, requirements: null }) });
  const key = await gateInputKey((await repo.quote('zz-demo-q'))!, await repo.lines('zz-demo-q'), ctxOf(held.deps));
  forgetReads();
  const during = await readAndAssess(repo, 'zz-demo-q', ctxOf(held.deps));
  assertEquals([during.reading, during.settled, during.a.held], [null, false, true]);
  const verdicts = new Map<string, unknown>();
  const rpc = (fn: string, args: Record<string, unknown>) => {
    if (fn === 'fn_line_spec_reading_put') { let n = 0; for (const r of args.p_rows as { key: string; found: unknown }[]) if (!verdicts.has(r.key)) { verdicts.set(r.key, r.found); n++; } return Promise.resolve({ data: n, error: null }); }
    return Promise.resolve({ data: Object.fromEntries((args.p_keys as string[]).filter((k) => verdicts.has(k)).map((k) => [k, verdicts.get(k)])), error: null });
  };
  assertEquals((await checkVerdict(rpc, key, during.a, during.settled)).outcome, 'unsettled');
  assertEquals([verdicts.size, held.settled.size], [0, 0], 'nothing stored for a held reading: no verdict, no reading');
  const live = world({ store: true });
  forgetReads();
  const after = await readAndAssess(repo, 'zz-demo-q', ctxOf(live.deps));
  assertEquals([after.settled, after.a.held], [true, false]);
  assertEquals((await checkVerdict(rpc, key, after.a, after.settled)).outcome, 'first', 'the settled verdict is the first, not a disagreement');
  assertEquals((await checkVerdict(rpc, key, after.a, after.settled)).outcome, 'same');
});

Deno.test('a READER_VERSION bump misses the cache: a changed reader reads again', async () => {
  const w = world({ store: true });
  const req = { seat: 'sales_engineer' as const, surface: 'line_specs.assess', question: 'LINE 1: Wardrobe 18mm MR MDF carcass, HPL finish', subject: { quote_id: 'zz' }, context: { audience: 'supplier' as const },
    plan: { steps: [{ id: 'read', goal: 'read', query: 'read', needs_knowledge: false }] }, reader: true,
    decision: { name: 'stated_specs', fields: [{ key: 'L1__thickness_mm', question: 'line 1 thickness' }] } };
  forgetReads(); await settledRead(w.deps, req);
  forgetReads(); await settledRead(w.deps, req);
  assertEquals(w.lineReads(), 1, 'same version: read once, then settled');
  forgetReads(); await settledRead(w.deps, req, READER_VERSION + 1);
  assertEquals([w.lineReads(), w.settled.size], [2, 2], 'a new version is a new key: the model reads again');
});
