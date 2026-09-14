// The hold desk end to end, in memory: held → fill in → regenerate → approve → released; held →
// resubmit → released; and two options from one submission, one held while the other passes.
//
// Incapable of reaching a person: the repository is an in-memory fake, there is no client, no
// fetch and no database, and every party is a ZZ DEMO fixture at an @example.invalid address —
// asserted at the end of every scenario, not assumed.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/workflow.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { SEAT, SEAT_LABEL, type Line } from './assess.ts';
import { optionAmount, splitOptions } from './options.ts';
import { approve, fillIn, formSchema, gate, supabaseRepo, type HoldRow, type NotificationRow, type QuoteRow, type SpecRepo } from './workflow.ts';

class Fake implements SpecRepo {
  quotes = new Map<string, QuoteRow>(); items = new Map<string, Line[]>(); holds: HoldRow[] = []; sent: NotificationRow[] = []; runs: string[] = [];
  async quote(id: string) { return this.quotes.get(id) ?? null; }
  async lines(id: string) { return structuredClone(this.items.get(id) ?? []); }
  async saveLineSpecs(id: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]) { const ls = this.items.get(id)!; for (const r of rows) { const l = ls.find((x) => x.line_no === r.line_no)!; l.spec = r.spec; l.spec_source = r.spec_source as Line['spec_source']; } }
  async updateQuote(id: string, patch: Record<string, unknown>) { Object.assign(this.quotes.get(id)!, patch); }
  async liveHold(id: string) { return this.holds.find((h) => h.quote_id === id && (h.state === 'open' || h.state === 'awaiting_approval')) ?? null; }
  async insertHold(row: Omit<HoldRow, 'id'>) { const h = { ...structuredClone(row), id: this.holds.length + 1 } as HoldRow; this.holds.push(h); return h; }
  async updateHold(id: number, patch: Partial<HoldRow>) { Object.assign(this.holds.find((h) => h.id === id)!, patch); }
  async notify(rows: NotificationRow[]) { this.sent.push(...rows); return rows.map((_, i) => this.sent.length - rows.length + i + 1); }
  async log(_c: Record<string, unknown>, note: string) { this.runs.push(note); }
}
const SUP_AR = { id: 900001, email: 'zz-demo-joinery@example.invalid', locale: 'ar' };
const SUP_EN = { id: 900002, email: 'zz-demo-hvac@example.invalid', locale: 'en' };
const NOW = () => new Date('2026-09-14T10:00:00Z');
const q = (id: string, supplier_id: number, x: Partial<QuoteRow> = {}): QuoteRow => ({ id, inquiry_id: 'inq-zz-demo', supplier_id, status: 'submitted', option_no: 1, submission_id: 'sub-1', quote_amount: 12000, price_ex_vat: 12000, lead_time: '21 days', validity: '30 days', payment_terms: '50% advance', warranty: '2 years on workmanship and hardware', scope: 'Supply and installation of wardrobes and kitchen cabinets by our own team', ...x });
const accept = (repo: Fake) => async (row: QuoteRow) => { repo.quotes.get(row.id)!.status = 'submitted'; return true; };
const nobodyReal = (repo: Fake) => { for (const n of repo.sent) assert(/@example\.invalid$/.test(n.to_email), `a notification left the fixture domain: ${n.to_email}`); };

Deno.test('held → fill in on the portal → regenerated → approved → released, with the audit trail kept', async () => {
  const repo = new Fake();
  repo.quotes.set('q1', q('q1', SUP_AR.id, { warranty: '2 years' }));
  repo.items.set('q1', [
    { line_no: 1, description: 'Wardrobe MDF carcass, HPL finish', qty: 2, unit: 'nos', unit_price: 3000, amount: 6000 },
    { line_no: 2, description: 'Kitchen base cabinets 18mm plywood, lacquer finish', qty: 1, unit: 'lot', unit_price: 6000, amount: 6000 },
  ]);
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZDEMO01', now: NOW };
  const g = await gate(repo, 'q1', SUP_AR, ctx);
  assert(g.held);
  assertEquals(g.missing.map((m) => (m.scope === 'line' ? `${m.line_no}:${m.attr}` : m.attr)), ['1:thickness_mm', 'warranty_coverage']);
  assertEquals(repo.quotes.get('q1')!.status, 'draft');
  assertEquals(repo.sent.length, 1);
  assert(repo.sent[0].body.includes('البند 1') && repo.sent[0].body.includes(SEAT_LABEL.ar), 'Arabic supplier gets the Arabic notice');
  const schema = formSchema(g.assessment, await repo.lines('q1'));
  assertEquals(schema.lines[0].fields.find((f) => f.attr === 'thickness_mm')!.missing, true);
  assertEquals(schema.terms.map((t) => t.attr), ['warranty_coverage']);

  assertEquals((await fillIn(repo, 'q1', SUP_AR.id, { lines: { '1': { thickness_mm: 'TBD' } } }, ctx)).ok, false);
  assertEquals((await fillIn(repo, 'q1', 999, { lines: { '1': { thickness_mm: '18' } } }, ctx)).ok, false, 'another supplier cannot fill this quote');
  const partial = await fillIn(repo, 'q1', SUP_AR.id, { lines: { '1': { thickness_mm: '18' } } }, ctx);
  assert(partial.ok && !partial.complete);
  assertEquals(partial.missing.map((m) => m.attr), ['warranty_coverage']);

  const done = await fillIn(repo, 'q1', SUP_AR.id, { terms: { warranty_coverage: 'Hinges, hardware and workmanship' } }, ctx, async () => ({ bucket: 'quote-files', path: 'quotes/zz/regenerated.pdf' }));
  assert(done.ok && done.complete);
  const reg = done.regenerated;
  assertEquals(reg.lines[0].spec.find((s) => s.code === 'thickness_mm'), { code: 'thickness_mm', label_en: 'Thickness', label_ar: 'السماكة', value: '18', unit: 'mm', unit_ar: 'ملم', source: 'supplier_portal' });
  assertEquals(reg.terms.warranty, '2 years — Hinges, hardware and workmanship');
  assertEquals(repo.holds[0].state, 'awaiting_approval');
  assertEquals(repo.quotes.get('q1')!.status, 'draft', 'not released before the supplier approves');

  assertEquals((await approve(repo, 'q1', SUP_AR.id, 'zz-demo-joinery@example.invalid', false, ctx, accept(repo))).ok, false);
  const ok = await approve(repo, 'q1', SUP_AR.id, 'zz-demo-joinery@example.invalid', true, ctx, accept(repo));
  assert(ok.ok && ok.released && ok.live);
  const h = repo.holds[0];
  assertEquals([h.state, h.approved_by, h.approved_at, h.pdf_path], ['released', 'zz-demo-joinery@example.invalid', NOW().toISOString(), 'quotes/zz/regenerated.pdf']);
  assertEquals(repo.quotes.get('q1')!.status, 'submitted');
  // The trail: the original as submitted, every set of values the supplier entered, the regenerated version.
  assertEquals((h.original_snapshot as { lines: Line[] }).lines[0].description, 'Wardrobe MDF carcass, HPL finish');
  assertEquals(h.supplier_values.length, 2);
  assert(h.regenerated);
  nobodyReal(repo);
});

Deno.test('held → a revised quote is resubmitted → the old hold is superseded and the quote goes out', async () => {
  const repo = new Fake();
  repo.quotes.set('q2', q('q2', SUP_EN.id, { lead_time: 'ASAP' }));
  repo.items.set('q2', [{ line_no: 1, description: 'Wardrobe 18mm MDF carcass, HPL finish', amount: 6000 }]);
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZDEMO02', now: NOW };
  assert((await gate(repo, 'q2', SUP_EN, ctx)).held);
  // The supplier uploads a revised quotation: the same quote row is replaced and gated again.
  Object.assign(repo.quotes.get('q2')!, { lead_time: '3 weeks from drawing approval' });
  const again = await gate(repo, 'q2', SUP_EN, ctx);
  assertEquals([again.held, again.superseded], [false, 1]);
  assertEquals(repo.holds.map((x) => x.state), ['superseded']);
  assertEquals(await repo.liveHold('q2'), null);
  await accept(repo)(repo.quotes.get('q2')!);
  assertEquals(repo.quotes.get('q2')!.status, 'submitted');
  nobodyReal(repo);
});

Deno.test('two options from one submission: each its own quote with the shared terms; one held, one passes', async () => {
  const repo = new Fake();
  const submitted = [
    { description: 'Option 1 - Daikin' }, { description: 'Ducted split 2.5 TR Daikin model FDMRN30, R410A', amount: 10000 },
    { description: 'Option 2 - Other brand' }, { description: 'Ducted split 2.5 TR, R410A', amount: 8000 },
  ];
  const shared = { lead_time: '3 weeks', warranty: '5 years on compressor, 1 year parts and labour', scope: 'Supply and installation of ducted split units, testing and commissioning', validity: '30 days', payment_terms: '30 days credit' };
  const opts = splitOptions(submitted);
  for (const o of opts) {
    const id = 'opt' + o.option_no;
    repo.quotes.set(id, q(id, SUP_EN.id, { ...shared, option_no: o.option_no, submission_id: 'sub-zz-2', quote_amount: optionAmount(o)!, price_ex_vat: optionAmount(o)! }));
    repo.items.set(id, o.lines.map((l, i) => ({ line_no: i + 1, description: l.description, amount: l.amount ?? null })));
  }
  assertEquals([...repo.quotes.keys()], ['opt1', 'opt2']);
  for (const id of ['opt1', 'opt2']) { const r = repo.quotes.get(id)!; assertEquals([r.lead_time, r.warranty, r.payment_terms, r.submission_id], [shared.lead_time, shared.warranty, shared.payment_terms, 'sub-zz-2']); }
  const ctx = { category: 'hvac', requirements: null, ref: 'ZZDEMO03', multiOption: true, now: NOW };
  const g1 = await gate(repo, 'opt1', SUP_EN, ctx), g2 = await gate(repo, 'opt2', SUP_EN, ctx);
  assertEquals([g1.held, g2.held], [false, true]);
  assertEquals(g2.missing.map((m) => `${m.line_no}:${m.attr}`), ['1:brand', '1:model']);
  assertEquals(repo.holds.map((h) => [h.quote_id, h.option_no]), [['opt2', 2]]);
  assert(repo.sent[0].subject.includes('Option 2'), repo.sent[0].subject);
  assertEquals([repo.quotes.get('opt1')!.quote_amount, repo.quotes.get('opt2')!.quote_amount], [10000, 8000]);
  nobodyReal(repo);
});

Deno.test('every record the desk writes is the sales engineer\'s, and nobody else\'s', async () => {
  assertEquals(SEAT, 'sales_engineer');
  const repo = new Fake();
  repo.quotes.set('q4', q('q4', SUP_EN.id, { lead_time: '', price_ex_vat: null, quote_amount: 12600, payment_terms: '50% advance, TRN 100 2345 6789 0003' }));
  repo.items.set('q4', [{ line_no: 1, description: 'Wardrobe 18mm MDF carcass, HPL finish', amount: 6000 }]);
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZDEMO04', now: NOW };
  const g = await gate(repo, 'q4', SUP_EN, ctx);
  assertEquals(g.missing.map((m) => m.attr), ['delivery', 'price_ex_vat']);
  assertEquals(repo.holds[0].owner_seat, 'sales_engineer');
  assert(repo.sent.every((n) => n.kind.startsWith('sales_engineer_') && n.body.includes(SEAT_LABEL.en)));
  const done = await fillIn(repo, 'q4', SUP_EN.id, { terms: { delivery: '21 days', price_ex_vat: '12,000' } }, ctx);
  assert(done.ok && done.complete);
  assertEquals(done.regenerated.prepared_by, 'sales_engineer');
  // The regenerated quotation carries the ex-VAT price and no VAT or TRN detail at all.
  assertEquals([done.regenerated.total, done.regenerated.price_basis, repo.quotes.get('q4')!.quote_amount], [12000, 'ex_vat', 12000]);
  assert(!/2345|vat_amount|vat_treatment|supplier_trn|\bTRN\b/i.test(JSON.stringify(done.regenerated)), JSON.stringify(done.regenerated.terms));
  for (const text of [...repo.runs, ...repo.sent.map((n) => n.body), JSON.stringify(repo.holds)]) assert(!/\b(ceo|customer_support)\b/.test(text), text);
  // The production repository attributes its run log to the seat.
  const rows: { table: string; row: Record<string, unknown> }[] = [];
  const admin = { from: (table: string) => ({ insert: (row: Record<string, unknown>) => { rows.push({ table, row }); return Promise.resolve({ error: null }); } }) };
  await supabaseRepo(admin).log({ signal: 'x' }, 'note');
  assertEquals(rows, [{ table: 'agent_runs', row: { ...rows[0].row, agent: 'sales_engineer', status: 'ok' } }]);
  nobodyReal(repo);
});
