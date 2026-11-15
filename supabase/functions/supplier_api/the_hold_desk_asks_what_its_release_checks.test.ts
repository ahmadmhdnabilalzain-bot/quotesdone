// THE HOLD DESK ASKS WHAT ITS RELEASE CHECKS (sales_engineer; evidence run of 10 Nov 2026, ledger 1604, finding a).
//
// Real run 1, RFQ 164464: four suppliers filled every field spec_hold showed, spec_fill answered complete:true, and
// spec_approve answered 409 still_missing. Its precheck (the release review on the STORED quote) asked line 1
// ("Removal and disposal of existing PVC wall panels") and line 2 their exact `specification`, which the form never
// showed. Two causes, both fixed: workingFromStoredQuote dropped spec_source, so the review could not honour what
// reasoning read (a line's trade, a line that carries no material) and read every composite line as unread; and the
// desk built its form from deskAssess alone, so an item only the release asks was never offered and never accepted.
//
// The release check here is the production one minus the model read (readWorking, which under the model hold returns
// the working unchanged): reviewQuotation over workingFromStoredQuote + withDeskAnswers, mapped by issueAsMissing.
// Incapable of reaching a person: an in-memory repository, stubbed delivery, ZZ DEMO fixtures at @example.invalid.
// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/the_hold_desk_asks_what_its_release_checks.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessQuote, type Line } from '../_shared/line_specs/assess.ts';
import { answersOf, approve, deskAssess, fillIn, formSchema, gate, openHeld, type HoldRow, type NotificationRow, type Precheck, type QuoteRow, type SpecRepo } from '../_shared/line_specs/workflow.ts';
import type { QuoteReading } from '../_shared/reasoned_matching.ts';
import { reviewQuotation, type SafeInquiry } from './quote_review.ts';
import { issueAsMissing, withDeskAnswers, workingFromStoredQuote } from './submit_review.ts';

class Fake implements SpecRepo {
  quotes = new Map<string, QuoteRow>(); items = new Map<string, Line[]>(); holds: HoldRow[] = []; sent: NotificationRow[] = [];
  async quote(id: string) { return this.quotes.get(id) ?? null; }
  async lines(id: string) { return structuredClone(this.items.get(id) ?? []); }
  async saveLineSpecs(id: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]) { const ls = this.items.get(id)!; for (const r of rows) { const l = ls.find((x) => x.line_no === r.line_no)!; l.spec = r.spec; l.spec_source = r.spec_source as Line['spec_source']; } }
  async updateQuote(id: string, patch: Record<string, unknown>) { Object.assign(this.quotes.get(id)!, patch); }
  async liveHold(id: string) { return this.holds.find((h) => h.quote_id === id && (h.state === 'open' || h.state === 'awaiting_approval')) ?? null; }
  async insertHold(row: Omit<HoldRow, 'id'>) { const h = { ...structuredClone(row), id: this.holds.length + 1 } as HoldRow; this.holds.push(h); return h; }
  async updateHold(id: number, patch: Partial<HoldRow>) { Object.assign(this.holds.find((h) => h.id === id)!, structuredClone(patch)); }
  async notify(rows: NotificationRow[]) { this.sent.push(...rows); return rows.map((_, i) => this.sent.length - rows.length + i + 1); }
  async dispatch() {}
  async log() {}
}
const SUP = { id: 900101, email: 'zz-demo-wallpanels@example.invalid', phone: '+971500000093', locale: 'en' };
const NOW = () => new Date('2026-11-10T10:00:00Z');
const nobodyReal = (repo: Fake) => { for (const n of repo.sent) { assert(/@example\.invalid$/.test(String(n.to_email))); assert(!n.to_phone || /^\+9715000000\d\d$/.test(n.to_phone)); } };
const inquiry = (category: string, boq: SafeInquiry['boq_rows'] = []): SafeInquiry => ({ id: 'inq-zz-demo', job_no: 'RFQ-ZZ0001', category, emirate: 'Dubai', spec: null, boq_rows: boq, boq_withheld: false, concluded: false, revealed: false });
/** The production release check without the model read: the stored row, the engineer's explanations (none here), the desk answers. */
const releaseOf = (repo: Fake, inq: SafeInquiry): Precheck => async (row, answers = {}) => {
  const rvw = reviewQuotation(inq, withDeskAnswers(workingFromStoredQuote(row, await repo.lines(String(row.id))), answers), NOW());
  return rvw.approved ? null : { missing: rvw.issues.map(issueAsMissing), issues: rvw.issues };
};
const reads = (m: Record<string, QuoteReading>) => (qr: QuoteRow) => Promise.resolve(m[qr.id] ?? null);
const accept = (repo: Fake) => async (row: QuoteRow) => { repo.quotes.get(row.id)!.status = 'submitted'; return true; };
/** Fill EVERY field the form shows, and nothing else: what a supplier on the hold desk can do. */
function fillAllShown(schema: ReturnType<typeof formSchema>, value: (attr: string, type: string, options: string[] | null | undefined) => string) {
  const lines: Record<string, Record<string, string>> = {};
  for (const l of schema.lines) for (const f of l.fields) if (f.missing) (lines[String(l.line_no)] ??= {})[f.attr] = value(f.attr, f.type, f.options);
  const terms: Record<string, string> = {};
  for (const t of schema.terms) terms[t.attr] = value(t.attr, t.type, t.options);
  return { lines, terms };
}
const anAnswer = (attr: string, type: string, options: string[] | null | undefined) =>
  options?.length && type === 'choice' ? options[0] : type === 'number' ? '9000' : attr === 'brand' ? 'ZZ Demo Panels' : attr === 'total' ? 'Discount of AED 500 on the lines' : 'Excluded — by others';
/** The form a supplier sees on spec_hold, exactly as quotes.ts builds it. */
async function specHoldForm(repo: Fake, qid: string, category: string) {
  const q = (await repo.quote(qid))!; const lines = await repo.lines(qid); const hold = await repo.liveHold(qid);
  const a = deskAssess({ category, lines, terms: q, requirements: null }, q.validity, NOW());
  return formSchema(a, lines, hold && hold.state === 'open' ? openHeld(hold.missing, a, lines, answersOf(hold)) : []);
}

// The PVC wall-panel quotation of RFQ 164464, as the gate read it: a fit-out (composite) quote whose line 1 is a
// removal (no trade material), lines 2 and 3 wall panels (wallpaper), with its terms read from its own words.
function pvcQuote(repo: Fake, x: Partial<QuoteRow> = {}) {
  repo.quotes.set('qpvc', { id: 'qpvc', inquiry_id: 'inq-zz-demo', supplier_id: SUP.id, status: 'submitted', option_no: 1, submission_id: 's1', quote_amount: 9000, price_ex_vat: 9000,
    vat_treatment: 'exclusive', lead_time: '14 days', validity: '30 days', payment_terms: '50% advance', warranty: '2 years', scope: 'Remove and replace PVC wall panels', ...x });
  repo.items.set('qpvc', [
    { line_no: 1, description: 'Removal and disposal of existing PVC wall panels', qty: 40, unit: 'm2', unit_price: 25, amount: 1000 },
    { line_no: 2, description: 'Supply and install new PVC wall panels on the existing MDF partition', qty: 40, unit: 'm2', unit_price: 180, amount: 7200 },
    { line_no: 3, description: 'PVC trims, corner profiles and accessories', qty: 1, unit: 'lot', unit_price: 800, amount: 800 },
  ]);
}
const PVC_READ: QuoteReading = {
  lines: { 1: { _trade: 'none' }, 2: { _trade: 'wallpaper', material: 'PVC' }, 3: { _trade: 'wallpaper', material: 'PVC' } },
  terms: { installation: { included: 'yes', detail: 'by our own team, 5 working days', source: 'reasoned' }, warranty: { period: '2 years', coverage: 'materials and installation', source: 'reasoned' } },
};

Deno.test('RFQ 164464: fill everything the form shows → spec_approve releases it (no 409 asking an unshown `specification`)', async () => {
  const repo = new Fake(); pvcQuote(repo);
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  const g = await gate(repo, 'qpvc', SUP, ctx);
  assert(g.held);
  assertEquals(g.missing.map((m) => `${m.line_no}:${m.attr}`), ['2:brand', '3:brand']);
  const release = releaseOf(repo, inquiry('fitout'));
  const form = await specHoldForm(repo, 'qpvc', 'fitout');
  const done = await fillIn(repo, 'qpvc', SUP, fillAllShown(form, anAnswer), ctx, undefined, release);
  assert(done.ok && done.complete, 'every field the form showed was filled, so the desk is complete — and so is the release');
  const ok = await approve(repo, 'qpvc', SUP, SUP.email, true, ctx, accept(repo), release);
  assertEquals(ok.ok ? 'released' : `${ok.code} ${JSON.stringify((ok as { missing?: unknown }).missing)}`, 'released');
  assertEquals(repo.quotes.get('qpvc')!.status, 'submitted');
  nobodyReal(repo);
});

Deno.test('the release review reads the stored lines WITH their sources: a line read as no trade is not asked its specification', async () => {
  const repo = new Fake(); pvcQuote(repo);
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  await gate(repo, 'qpvc', SUP, ctx);
  const w = workingFromStoredQuote(repo.quotes.get('qpvc'), await repo.lines('qpvc'));
  assertEquals(w.lines[0].spec_source?._trade, 'reasoned');
  const rvw = reviewQuotation(inquiry('fitout'), w, NOW());
  assertEquals(rvw.issues.filter((i) => i.attr === 'specification'), [], 'no line is asked the exact specification the desk does not ask');
});

Deno.test('a quotation whose PDF states each line\'s specification is not asked it again (no reading, a composite trade)', () => {
  const lines: Line[] = [
    { line_no: 1, description: 'PVC wall panels', specification: 'PVC panel 8 mm, 2440 x 1220 mm, ZZ Demo Panels model WP-8, white matt', qty: 40, unit: 'm2', unit_price: 180, amount: 7200 },
    { line_no: 2, description: 'Trims and accessories', specification: '', qty: 1, unit: 'lot', unit_price: 800, amount: 800 },
  ];
  const a = assessQuote({ category: 'fitout', lines, terms: { lead_time: '14 days', warranty: '2 years', price_ex_vat: 8000 } });
  const specAsked = a.missing.filter((m) => m.attr === 'specification').map((m) => m.line_no);
  assertEquals(specAsked, [2], 'line 1 states its specification in its own column; only line 2, which states none, is asked');
});

Deno.test('an item only the release asks is on the form, accepted by spec_fill, and the release then passes (prices in AED, an unpriced BOQ line)', async () => {
  const repo = new Fake(); pvcQuote(repo, { notes: 'Panel rates converted from USD 2,450 at the day rate' });
  const inq = inquiry('fitout', [
    { description: 'Removal and disposal of existing PVC wall panels', qty: 40, unit: 'm2' },
    { description: 'Supply and install new PVC wall panels on the existing MDF partition', qty: 40, unit: 'm2' },
    { description: 'PVC trims, corner profiles and accessories', qty: 1, unit: 'lot' },
    { description: 'Repaint the ceiling bulkhead above the partition', qty: 1, unit: 'lot' },
  ]);
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  await gate(repo, 'qpvc', SUP, ctx);
  const release = releaseOf(repo, inq);
  // Round 1: the supplier fills every field shown. The desk is satisfied; the release is not, and says what it wants.
  const r1 = await fillIn(repo, 'qpvc', SUP, fillAllShown(await specHoldForm(repo, 'qpvc', 'fitout'), anAnswer), ctx, undefined, release);
  assert(r1.ok && !r1.complete, 'complete is the release\'s verdict, not the desk\'s alone');
  const asked = r1.missing.map((m) => m.attr).sort();
  assertEquals(asked, ['boq:4', 'currency']);
  // Every item still missing is on the form the supplier now sees.
  const form = await specHoldForm(repo, 'qpvc', 'fitout');
  for (const m of r1.missing) assert(form.terms.some((t) => t.attr === m.attr), `${m.attr} is on the form`);
  const aed = form.terms.find((t) => t.attr === 'currency')!;
  assertEquals([aed.type, aed.options], ['choice', ['aed']]);
  // A choice that is not one of the listed ones is refused, by shape.
  const bad = await fillIn(repo, 'qpvc', SUP, { terms: { currency: 'usd' } }, ctx, undefined, release);
  assert(!bad.ok && bad.code === 'invalid_values');
  // Round 2: fill what the form shows. Complete, and the release passes.
  const r2 = await fillIn(repo, 'qpvc', SUP, fillAllShown(form, anAnswer), ctx, undefined, release);
  assert(r2.ok && r2.complete, JSON.stringify(r2));
  assertEquals(answersOf(repo.holds[0]), { 'boq:4': 'Excluded — by others', currency: 'aed' }, 'the answers are stored on the hold');
  const ok = await approve(repo, 'qpvc', SUP, SUP.email, true, ctx, accept(repo), release);
  assert(ok.ok && ok.released);
  nobodyReal(repo);
});

Deno.test('a hold reopened by spec_approve\'s precheck shows every item it carries, and spec_fill accepts each (an older desk that did not precheck)', async () => {
  const repo = new Fake(); pvcQuote(repo, { notes: 'Panel rates converted from USD 2,450 at the day rate' });
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  await gate(repo, 'qpvc', SUP, ctx);
  const release = releaseOf(repo, inquiry('fitout'));
  // fillIn without the release check: complete by the desk alone, as before this change.
  const r1 = await fillIn(repo, 'qpvc', SUP, fillAllShown(await specHoldForm(repo, 'qpvc', 'fitout'), anAnswer), ctx);
  assert(r1.ok && r1.complete);
  const no = await approve(repo, 'qpvc', SUP, SUP.email, true, ctx, accept(repo), release);
  assert(!no.ok && no.code === 'still_missing');
  const form = await specHoldForm(repo, 'qpvc', 'fitout');
  for (const m of (no as { missing: { attr: string }[] }).missing) assert(form.terms.some((t) => t.attr === m.attr) || form.lines.some((l) => l.fields.some((f) => f.attr === m.attr)), `${m.attr} is on the form`);
  const r2 = await fillIn(repo, 'qpvc', SUP, fillAllShown(form, anAnswer), ctx, undefined, release);
  assert(r2.ok && r2.complete);
  const ok = await approve(repo, 'qpvc', SUP, SUP.email, true, ctx, accept(repo), release);
  assert(ok.ok && ok.released);
});

Deno.test('a release item on a LINE (the exact specification of a line the desk did not read) is a field of that line and is stored on it', async () => {
  const repo = new Fake(); pvcQuote(repo);
  // No reading: under the model hold the gate asks every composite line its specification.
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW };
  const g = await gate(repo, 'qpvc', SUP, ctx);
  assertEquals(g.missing.filter((m) => m.attr === 'specification').map((m) => m.line_no), [1, 2, 3]);
  // The release asks one line again after it was cleared on the row (as the evidence run's reopened hold did).
  const hold = repo.holds[0];
  hold.missing = [...hold.missing, { scope: 'line', line_no: 9, description: 'gone', attr: 'specification', type: 'text', label_en: 'x', label_ar: 'x' }];
  const form = await specHoldForm(repo, 'qpvc', 'fitout');
  assertEquals(form.lines.map((l) => l.line_no), [1, 2, 3], 'a line the quotation no longer has is not asked');
  const filled = fillAllShown(form, (attr, type, opts) => attr === 'specification' ? 'PVC panel 8 mm, ZZ Demo WP-8' : attr === 'installation_detail' ? 'By our own team, 5 working days' : anAnswer(attr, type, opts));
  assertEquals(Object.keys(filled.lines), ['1', '2', '3']);
  const out = await fillIn(repo, 'qpvc', SUP, filled, ctx, undefined, releaseOf(repo, inquiry('fitout')));
  assert(out.ok && out.complete, JSON.stringify(out));
  assertEquals((await repo.lines('qpvc')).map((l) => l.spec_source?.specification), ['supplier_portal', 'supplier_portal', 'supplier_portal']);
});

// GENERALISED (rulings 1579/1586: every example applies to every trade).
Deno.test('every trade: an MEP quote (HVAC line + an unread line) and a joinery quote whose total differs — fill the form, release passes', async () => {
  // MEP: composite. Line 1 read as hvac; line 2 unread — the desk asks its specification, the release asks the same.
  {
    const repo = new Fake();
    repo.quotes.set('qmep', { id: 'qmep', inquiry_id: 'inq-zz-demo', supplier_id: SUP.id, status: 'submitted', option_no: 1, submission_id: 's1', quote_amount: 15000, price_ex_vat: 15000, vat_treatment: 'exclusive', lead_time: '3 weeks', validity: '30 days', warranty: '1 year' });
    repo.items.set('qmep', [
      { line_no: 1, description: 'Ducted split AC unit 5 TR', qty: 1, unit: 'nos', unit_price: 12000, amount: 12000 },
      { line_no: 2, description: 'Sockets relocation near the wall', qty: 4, unit: 'nos', unit_price: 750, amount: 3000 },
    ]);
    const ctx = { category: 'mep', requirements: null, ref: 'ZZ0002', now: NOW, read: reads({ qmep: { lines: { 1: { _trade: 'hvac' } }, terms: PVC_READ.terms } }) };
    await gate(repo, 'qmep', SUP, ctx);
    const release = releaseOf(repo, inquiry('mep'));
    let form = await specHoldForm(repo, 'qmep', 'mep');
    for (let round = 0; round < 3; round++) {
      const r = await fillIn(repo, 'qmep', SUP, fillAllShown(form, (attr, type, opts) => type === 'number' ? '5' : anAnswer(attr, type, opts)), ctx, undefined, release);
      assert(r.ok, JSON.stringify(r));
      if (r.complete) break;
      form = await specHoldForm(repo, 'qmep', 'mep');
    }
    assertEquals(repo.holds[0].state, 'awaiting_approval');
    const ok = await approve(repo, 'qmep', SUP, SUP.email, true, ctx, accept(repo), release);
    assert(ok.ok && ok.released, JSON.stringify(ok));
  }
  // Joinery: the lines add up to more than the total. The release asks what the difference is; the form shows it.
  {
    const repo = new Fake();
    repo.quotes.set('qjoin', { id: 'qjoin', inquiry_id: 'inq-zz-demo', supplier_id: SUP.id, status: 'submitted', option_no: 1, submission_id: 's1', quote_amount: 9500, price_ex_vat: 9500, vat_treatment: 'exclusive', lead_time: '21 days', validity: '30 days', warranty: '2 years' });
    repo.items.set('qjoin', [{ line_no: 1, description: 'Wardrobe 2.4 m', qty: 2, unit: 'nos', unit_price: 5000, amount: 10000 }]);
    const ctx = { category: 'joinery', requirements: null, ref: 'ZZ0003', now: NOW, read: reads({ qjoin: { lines: { 1: { material: 'MDF', finish: 'HPL' } }, terms: PVC_READ.terms } }) };
    await gate(repo, 'qjoin', SUP, ctx);
    const release = releaseOf(repo, inquiry('joinery'));
    const r1 = await fillIn(repo, 'qjoin', SUP, fillAllShown(await specHoldForm(repo, 'qjoin', 'joinery'), (a, t, o) => a === 'thickness_mm' ? '18' : anAnswer(a, t, o)), ctx, undefined, release);
    assert(r1.ok && !r1.complete);
    assertEquals(r1.missing.map((m) => m.attr), ['total']);
    const r2 = await fillIn(repo, 'qjoin', SUP, fillAllShown(await specHoldForm(repo, 'qjoin', 'joinery'), anAnswer), ctx, undefined, release);
    assert(r2.ok && r2.complete);
    const ok = await approve(repo, 'qjoin', SUP, SUP.email, true, ctx, accept(repo), release);
    assert(ok.ok && ok.released);
  }
});

Deno.test('the VAT basis, asked by the release, is a choice of three; the answer is stored where the release reads it', async () => {
  const vat = issueAsMissing({ code: 'vat_basis', kind: 'adjustment', line_no: null, boq_line: null, attr: 'vat', en: 'State the VAT basis.', ar: 'يُرجى بيان أساس الضريبة.' });
  assertEquals([vat.scope, vat.attr, vat.type, vat.options], ['quote', 'vat', 'choice', ['exclusive', 'inclusive', 'not_registered']]);
  const repo = new Fake(); pvcQuote(repo);
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  await gate(repo, 'qpvc', SUP, ctx);
  repo.holds[0].missing = [...repo.holds[0].missing, vat];
  assert((await specHoldForm(repo, 'qpvc', 'fitout')).terms.some((t) => t.attr === 'vat'));
  const bad = await fillIn(repo, 'qpvc', SUP, { terms: { vat: 'none' } }, ctx);
  assert(!bad.ok && bad.code === 'invalid_values');
  const out = await fillIn(repo, 'qpvc', SUP, { lines: { '2': { brand: 'ZZ Demo Panels' }, '3': { brand: 'ZZ Demo Panels' } }, terms: { vat: 'not_registered' } }, ctx);
  assert(out.ok && out.complete);
  assertEquals(repo.quotes.get('qpvc')!.vat_treatment, 'not_registered');
});

// 13 Nov 2026 (sales_engineer, workflow audit build item 10): a quotation held for its VAT basis stores no fee base
// (quote_amount NULL, the supplier's total in amount_as_stated); his one answer "including 5% VAT" settles the ex-VAT price
// and writes the fee base, so the quote is released without a person and without a second question.
Deno.test('the answer "including 5% VAT" settles the ex-VAT price from the stated total and writes the fee base', async () => {
  const vat = issueAsMissing({ code: 'vat_basis', kind: 'adjustment', line_no: null, boq_line: null, attr: 'vat', en: 'Is AED 54,476.10 including 5% VAT, or before VAT, or are you not VAT-registered?', ar: '-' });
  const repo = new Fake(); pvcQuote(repo);
  const q = repo.quotes.get('qpvc')! as Record<string, unknown>;
  Object.assign(q, { amount_as_stated: 54476.1, quote_amount: null, price_ex_vat: null, vat_treatment: 'not_stated' });
  const ctx = { category: 'fitout', requirements: null, ref: 'ZZ0001', now: NOW, read: reads({ qpvc: PVC_READ }) };
  await gate(repo, 'qpvc', SUP, ctx);
  repo.holds[0].missing = [...repo.holds[0].missing, vat];
  const out = await fillIn(repo, 'qpvc', SUP, { lines: { '2': { brand: 'ZZ Demo Panels' }, '3': { brand: 'ZZ Demo Panels' } }, terms: { vat: 'inclusive' } }, ctx);
  assert(out.ok);
  const after = repo.quotes.get('qpvc')! as Record<string, unknown>;
  assertEquals([after.vat_treatment, after.price_ex_vat, after.quote_amount], ['inclusive', 51882, 51882]);
});
