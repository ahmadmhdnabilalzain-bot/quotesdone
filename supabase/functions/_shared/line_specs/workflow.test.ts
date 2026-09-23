// The hold desk end to end, in memory: held → fill in → regenerate → approve → released; held →
// resubmit → released; two options from one submission, one held while the other passes; and every
// notice delivered at once through customer_support on email AND WhatsApp (founder_instruction #143,
// #158: "we notify directly").
//
// Incapable of reaching a person: the repository is an in-memory fake, delivery is stubbed (the
// dispatch kick only counts), there is no client, no fetch and no database, and every party is a
// ZZ DEMO fixture at an @example.invalid address and a +971 50 000 00xx number — asserted at the end
// of every scenario, not assumed.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/workflow.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { SEAT, SEAT_LABEL, type Line } from './assess.ts';
import { optionAmount, splitOptions } from './options.ts';
import { approve, fillIn, formSchema, gate, supabaseRepo, type HoldRow, type NotificationRow, type QuoteRow, type SpecRepo } from './workflow.ts';

class Fake implements SpecRepo {
  quotes = new Map<string, QuoteRow>(); items = new Map<string, Line[]>(); holds: HoldRow[] = []; sent: NotificationRow[] = []; runs: string[] = []; dispatched = 0;
  // Every step in call order, so "sent immediately" is a fact about the sequence, not a timestamp.
  steps: string[] = [];
  async quote(id: string) { return this.quotes.get(id) ?? null; }
  async lines(id: string) { return structuredClone(this.items.get(id) ?? []); }
  async saveLineSpecs(id: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]) { const ls = this.items.get(id)!; for (const r of rows) { const l = ls.find((x) => x.line_no === r.line_no)!; l.spec = r.spec; l.spec_source = r.spec_source as Line['spec_source']; } }
  async updateQuote(id: string, patch: Record<string, unknown>) { Object.assign(this.quotes.get(id)!, patch); }
  async liveHold(id: string) { return this.holds.find((h) => h.quote_id === id && (h.state === 'open' || h.state === 'awaiting_approval')) ?? null; }
  async insertHold(row: Omit<HoldRow, 'id'>) { const h = { ...structuredClone(row), id: this.holds.length + 1 } as HoldRow; this.holds.push(h); this.steps.push('hold'); return h; }
  async updateHold(id: number, patch: Partial<HoldRow>) { Object.assign(this.holds.find((h) => h.id === id)!, patch); }
  async notify(rows: NotificationRow[]) { this.sent.push(...rows); this.steps.push(...rows.map((r) => 'queue:' + r.channel)); return rows.map((_, i) => this.sent.length - rows.length + i + 1); }
  async dispatch() { this.dispatched++; this.steps.push('dispatch'); }
  async log(_c: Record<string, unknown>, note: string) { this.runs.push(note); }
}
const SUP_AR = { id: 900001, email: 'zz-demo-joinery@example.invalid', phone: '+971500000091', locale: 'ar' };
const SUP_EN = { id: 900002, email: 'zz-demo-hvac@example.invalid', phone: '+971500000092', locale: 'en' };
const NOW = () => new Date('2026-09-14T10:00:00Z');
const q = (id: string, supplier_id: number, x: Partial<QuoteRow> = {}): QuoteRow => ({ id, inquiry_id: 'inq-zz-demo', supplier_id, status: 'submitted', option_no: 1, submission_id: 'sub-1', quote_amount: 12000, price_ex_vat: 12000, lead_time: '21 days', validity: '30 days', payment_terms: '50% advance', warranty: '2 years on workmanship and hardware', scope: 'Supply and installation of wardrobes and kitchen cabinets by our own team', ...x });
const accept = (repo: Fake) => async (row: QuoteRow) => { repo.quotes.get(row.id)!.status = 'submitted'; return true; };
const nobodyReal = (repo: Fake) => {
  for (const n of repo.sent) {
    assert(!n.to_email || /@example\.invalid$/.test(n.to_email), `a notification left the fixture domain: ${n.to_email}`);
    assert(!n.to_phone || /^\+9715000000\d\d$/.test(n.to_phone), `a notification left the fixture numbers: ${n.to_phone}`);
    assertEquals([n.requested_by, n.sender], ['sales_engineer', 'customer_support'], 'every notice is a delivery request from the sales engineer, sent by customer_support');
  }
};
const byType = (repo: Fake, type: string) => repo.sent.filter((n) => n.type === type).map((n) => n.channel).sort();

Deno.test('held → notified at once on email and WhatsApp → fill in → regenerated → approved → released, with the trail kept', async () => {
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
  // SENT IMMEDIATELY: queued on both channels and dispatched inside the same call that held it.
  assertEquals(repo.steps, ['hold', 'queue:email', 'queue:whatsapp', 'dispatch']);
  assertEquals(byType(repo, 'quote_spec_hold'), ['email', 'whatsapp']);
  assertEquals([repo.holds[0].notified_at, repo.holds[0].opened_at, repo.holds[0].notification_ids], [NOW().toISOString(), NOW().toISOString(), [1, 2]]);
  assert(repo.sent[0].body.includes('البند 1') && repo.sent[0].body.includes(SEAT_LABEL.ar), 'Arabic supplier gets the Arabic notice');
  const schema = formSchema(g.assessment, await repo.lines('q1'));
  assertEquals(schema.lines[0].fields.find((f) => f.attr === 'thickness_mm')!.missing, true);
  assertEquals(schema.terms.map((t) => t.attr), ['warranty_coverage']);

  assertEquals((await fillIn(repo, 'q1', SUP_AR, { lines: { '1': { thickness_mm: 'TBD' } } }, ctx)).ok, false);
  assertEquals((await fillIn(repo, 'q1', { ...SUP_AR, id: 999 }, { lines: { '1': { thickness_mm: '18' } } }, ctx)).ok, false, 'another supplier cannot fill this quote');
  const partial = await fillIn(repo, 'q1', SUP_AR, { lines: { '1': { thickness_mm: '18' } } }, ctx);
  assert(partial.ok && !partial.complete);

  const done = await fillIn(repo, 'q1', SUP_AR, { terms: { warranty_coverage: 'Hinges, hardware and workmanship' } }, ctx, async () => ({ bucket: 'quote-files', path: 'quotes/zz/regenerated.pdf' }));
  assert(done.ok && done.complete);
  assertEquals(done.regenerated.lines[0].spec.find((s) => s.code === 'thickness_mm')?.source, 'supplier_portal');
  assertEquals(repo.holds[0].state, 'awaiting_approval');
  assertEquals(byType(repo, 'quote_spec_regenerated'), ['email', 'whatsapp'], 'the approval request goes through support too');
  assertEquals(repo.quotes.get('q1')!.status, 'draft', 'not released before the supplier approves');

  assertEquals((await approve(repo, 'q1', SUP_AR, 'zz-demo-joinery@example.invalid', false, ctx, accept(repo))).ok, false);
  const ok = await approve(repo, 'q1', SUP_AR, 'zz-demo-joinery@example.invalid', true, ctx, accept(repo));
  assert(ok.ok && ok.released && ok.live);
  assertEquals(byType(repo, 'quote_spec_released'), ['email', 'whatsapp']);
  const h = repo.holds[0];
  assertEquals([h.state, h.approved_by, h.pdf_path], ['released', 'zz-demo-joinery@example.invalid', 'quotes/zz/regenerated.pdf']);
  assertEquals(repo.quotes.get('q1')!.status, 'submitted');
  assertEquals((h.original_snapshot as { lines: Line[] }).lines[0].description, 'Wardrobe MDF carcass, HPL finish');
  assertEquals(h.supplier_values.length, 2);
  assertEquals(repo.dispatched, 3);
  nobodyReal(repo);
});

Deno.test('held → a revised quote is resubmitted → the old hold is superseded and the quote goes out', async () => {
  const repo = new Fake();
  repo.quotes.set('q2', q('q2', SUP_EN.id, { lead_time: 'ASAP' }));
  repo.items.set('q2', [{ line_no: 1, description: 'Wardrobe 18mm MDF carcass, HPL finish', amount: 6000 }]);
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZDEMO02', now: NOW };
  assert((await gate(repo, 'q2', SUP_EN, ctx)).held);
  Object.assign(repo.quotes.get('q2')!, { lead_time: '3 weeks from drawing approval' });
  const again = await gate(repo, 'q2', SUP_EN, ctx);
  assertEquals([again.held, again.superseded], [false, 1]);
  assertEquals(repo.holds.map((x) => x.state), ['superseded']);
  nobodyReal(repo);
});

Deno.test('the customer\'s inquiry decides what is required: "supply only" and "no warranty" are not asked; a named component is', async () => {
  const repo = new Fake();
  repo.quotes.set('q3', q('q3', SUP_EN.id, { scope: '', warranty: '' }));
  repo.items.set('q3', [{ line_no: 1, description: 'Dining table legs, 40mm, lacquer finish', amount: 900 }]);
  const requirements = { version: 1, installation: { required: 'no' }, warranty: { required: 'no' }, materials: [{ component: 'legs_base', label_en: 'Legs or base', label_ar: 'الأرجل أو القاعدة', choice: 'steel', choice_en: 'Steel' }] };
  const g = await gate(repo, 'q3', SUP_EN, { category: 'custom-furniture', requirements, ref: 'ZZDEMO05', now: NOW });
  assertEquals(g.missing.map((m) => `${m.line_no}:${m.attr}`), ['1:component_legs_base']);
  const done = await fillIn(repo, 'q3', SUP_EN, { lines: { '1': { component_legs_base: 'Powder-coated steel' } } }, { category: 'custom-furniture', requirements, ref: 'ZZDEMO05', now: NOW });
  assert(done.ok && done.complete);
  nobodyReal(repo);
});

Deno.test('two options from one submission: each its own quote with the shared terms; one held, one passes', async () => {
  const repo = new Fake();
  // Keyed by option, as the document reader and the portal send them (options split by structure, never by words).
  const submitted = [
    { description: 'Option 1 - Daikin', option: 1 }, { description: 'Ducted split 2.5 TR Daikin model FDMRN30, R410A', amount: 10000, option: 1 },
    { description: 'Option 2 - Other brand', option: 2 }, { description: 'Ducted split 2.5 TR, R410A', amount: 8000, option: 2 },
  ];
  const shared = { lead_time: '3 weeks', warranty: '5 years on compressor, 1 year parts and labour', scope: 'Supply and installation of ducted split units, testing and commissioning', validity: '30 days', payment_terms: '30 days credit' };
  for (const o of splitOptions(submitted)) {
    const id = 'opt' + o.option_no;
    repo.quotes.set(id, q(id, SUP_EN.id, { ...shared, option_no: o.option_no, submission_id: 'sub-zz-2', quote_amount: optionAmount(o)!, price_ex_vat: optionAmount(o)! }));
    repo.items.set(id, o.lines.map((l, i) => ({ line_no: i + 1, description: l.description, amount: l.amount ?? null })));
  }
  const ctx = { category: 'hvac', requirements: null, ref: 'ZZDEMO03', multiOption: true, now: NOW };
  const g1 = await gate(repo, 'opt1', SUP_EN, ctx), g2 = await gate(repo, 'opt2', SUP_EN, ctx);
  assertEquals([g1.held, g2.held], [false, true]);
  assertEquals(g2.missing.map((m) => `${m.line_no}:${m.attr}`), ['1:brand', '1:model']);
  assert(repo.sent[0].subject.includes('Option 2'), repo.sent[0].subject);
  nobodyReal(repo);
});

Deno.test('every record the desk writes is the sales engineer\'s; customer_support is the only sender', async () => {
  assertEquals(SEAT, 'sales_engineer');
  const repo = new Fake();
  repo.quotes.set('q4', q('q4', SUP_EN.id, { lead_time: '', price_ex_vat: null, quote_amount: 12600, payment_terms: '50% advance, TRN 100 2345 6789 0003' }));
  repo.items.set('q4', [{ line_no: 1, description: 'Wardrobe 18mm MDF carcass, HPL finish', amount: 6000 }]);
  const ctx = { category: 'joinery', requirements: null, ref: 'ZZDEMO04', now: NOW };
  const g = await gate(repo, 'q4', SUP_EN, ctx);
  assertEquals(g.missing.map((m) => m.attr), ['delivery', 'price_ex_vat']);
  assertEquals(repo.holds[0].owner_seat, 'sales_engineer');
  assert(repo.sent.every((n) => n.kind.startsWith('sales_engineer_') && n.body.includes(SEAT_LABEL.en)));
  const done = await fillIn(repo, 'q4', SUP_EN, { terms: { delivery: '21 days', price_ex_vat: '12,000' } }, ctx);
  assert(done.ok && done.complete);
  assertEquals([done.regenerated.prepared_by, done.regenerated.total, repo.quotes.get('q4')!.quote_amount], ['sales_engineer', 12000, 12000]);
  assert(!/2345|vat_amount|vat_treatment|supplier_trn|\bTRN\b/i.test(JSON.stringify(done.regenerated)));
  for (const text of [...repo.runs, ...repo.sent.map((n) => n.body), JSON.stringify(repo.holds)]) assert(!/\b(ceo|accountant)\b/.test(text), text);
  const rows: { table: string; row: Record<string, unknown> }[] = [];
  const admin = { from: (table: string) => ({ insert: (row: Record<string, unknown>) => { rows.push({ table, row }); return Promise.resolve({ error: null }); } }) };
  await supabaseRepo(admin).log({ signal: 'x' }, 'note');
  assertEquals(rows, [{ table: 'agent_runs', row: { ...rows[0].row, agent: 'sales_engineer', status: 'ok' } }]);
  nobodyReal(repo);
});
