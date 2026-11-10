// THE HOLD FORM IS THE RELEASE CHECK (sales_engineer; live evidence re-run ea40c830 of 10 Nov 2026, after #1896).
//
// Quotes a6f89b7f, 080e2091, f5b1b5b6 and 12266a2e of inquiry 78aa5217 (PVC wall panels, placed in wallpaper): the form
// asked line 2 material/roll_size/brand, line 3 roll_size/brand, line 4 material/roll_size/brand; the supplier filled every
// one; spec_fill answered complete:false missing [material] on line 3 (080e2091 also line 4), and the holds closed
// unresolved when the customer chose. Two evaluators: the desk judged with the inquiry's own requirements (a named material
// component, so line 3 was asked component_material, which reasoning had filled), the release with the supplier inbox's
// view of them, which the inbox withholds; with no component, line 3 fell back to the trade's mandatory `material`.
//
// Proven here, on the four stored rows (the read-only SELECTs, in the_four_live_quotes_of_inquiry_78aa5217.fixture.json)
// and on a generated set: for every hold, every item the release check reports is on the form (onForm), and filling every
// field the form shows reaches the release. The release check is supplier_api's own (submit_review.ts releaseReview),
// minus only the inbox fetch. Incapable of reaching a person: an in-memory repository, no network, no model.
// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/the_hold_form_is_the_release_check.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import FIX from './the_four_live_quotes_of_inquiry_78aa5217.fixture.json' with { type: 'json' };
import { assessQuote, type Line, type MissingItem, type Requirements } from '../_shared/line_specs/assess.ts';
import { TRADES } from '../_shared/line_specs/model.ts';
import { approve, deskView, fillIn, onForm, type HoldRow, type NotificationRow, type Precheck, type QuoteRow, type SpecRepo } from '../_shared/line_specs/workflow.ts';
import type { SafeInquiry } from './quote_review.ts';
import { releaseReview } from './submit_review.ts';

const NOW = () => new Date('2026-11-10T19:30:00Z');
const SUP = { id: 900301, email: 'zz-demo-hold-form@example.invalid', phone: '+971500000094', locale: 'en' };
class Fake implements SpecRepo {
  quotes = new Map<string, QuoteRow>(); items = new Map<string, Line[]>(); holds: HoldRow[] = []; sent: NotificationRow[] = [];
  async quote(id: string) { return this.quotes.get(id) ?? null; }
  async lines(id: string) { return structuredClone(this.items.get(id) ?? []); }
  async saveLineSpecs(id: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]) { const ls = this.items.get(id)!; for (const r of rows) { const l = ls.find((x) => x.line_no === r.line_no)!; l.spec = r.spec; l.spec_source = r.spec_source as Line['spec_source']; } }
  async updateQuote(id: string, patch: Record<string, unknown>) { Object.assign(this.quotes.get(id)!, patch); }
  async liveHold(id: string) { return this.holds.find((h) => h.quote_id === id && (h.state === 'open' || h.state === 'awaiting_approval')) ?? null; }
  async insertHold(row: Omit<HoldRow, 'id'>) { const h = { ...structuredClone(row), id: this.holds.length + 1 } as HoldRow; this.holds.push(h); return h; }
  async updateHold(id: number, patch: Partial<HoldRow>) { Object.assign(this.holds.find((h) => h.id === id)!, structuredClone(patch)); }
  async notify(rows: NotificationRow[]) { this.sent.push(...rows); return rows.map((_, i) => i + 1); }
  async dispatch() {}
  async log() {}
}
type Ctx = { category: string; requirements: Requirements; ref: string; now: () => Date };
const inquiry = (category: string, spec: unknown, boq: SafeInquiry['boq_rows'] = []): SafeInquiry => ({ id: 'inq-zz', job_no: 'RFQ-ZZ', category, emirate: 'Dubai', spec, boq_rows: boq, boq_withheld: false, concluded: false, revealed: false });
/** supplier_api's releaseCheck with the inbox already read: the stored row, the desk answers, the desk's own inputs. */
const releaseOf = (repo: Fake, inq: SafeInquiry, ctx: Ctx): Precheck => async (row, answers) =>
  releaseReview(inq, row, await repo.lines(String(row.id)), answers, { requirements: ctx.requirements }, undefined, NOW());
/** Open a hold as the gate does: on what the desk finds missing. */
function hold(repo: Fake, qid: string, missing: MissingItem[]) {
  repo.holds.push({ id: repo.holds.length + 1, quote_id: qid, inquiry_id: 'inq-zz', supplier_id: SUP.id, submission_id: 's', option_no: 1, state: 'open', missing,
    note_en: '', note_ar: '', original_snapshot: null, supplier_values: [], regenerated: null, regenerated_at: null, pdf_bucket: null, pdf_path: null,
    approved_at: null, approved_by: null, released_at: null, superseded_at: null, owner_seat: 'sales_engineer', opened_at: NOW().toISOString(), notified_at: null, notification_ids: null } as HoldRow);
}
/** A valid answer to every field the form shows (what a supplier on the hold desk does). */
function fillAll(schema: Awaited<ReturnType<typeof deskView>>['schema'], total: number) {
  const lines: Record<string, Record<string, string>> = {};
  for (const l of schema.lines) for (const f of l.fields) if (f.missing) (lines[String(l.line_no)] ??= {})[f.attr] = f.type === 'number' ? '18' : f.options?.[0] ?? 'ZZ Demo exact value 8 mm';
  const terms: Record<string, string> = {};
  const T: Record<string, string> = { delivery: '14 days', validity: '30 days', warranty_period: '2 years', warranty_coverage: 'parts and workmanship', installation_included: 'yes', installation_detail: 'by our own team, 5 working days', price_ex_vat: String(total) };
  for (const t of schema.terms) terms[t.attr] = T[t.attr] ?? (t.options?.length ? t.options[0] : t.type === 'number' ? String(total) : 'Excluded — by others');
  return { lines, terms };
}
async function fillUntilDone(repo: Fake, qid: string, ctx: Ctx, release: Precheck, total: number) {
  for (let round = 0; round < 5; round++) {
    const v = await deskView((await repo.quote(qid))!, await repo.lines(qid), await repo.liveHold(qid), ctx, release);
    for (const m of v.pre?.missing ?? []) assert(onForm(v.schema, m), `round ${round}: the release asks ${m.scope === 'line' ? 'line ' + m.line_no + ' ' : ''}${m.attr}, the form does not offer it`);
    const r = await fillIn(repo, qid, SUP, fillAll(v.schema, total), ctx, undefined, release);
    if (!r.ok) throw new Error('fill refused: ' + JSON.stringify(r));
    if (r.complete) return round;
  }
  throw new Error('the form never reached the release: ' + JSON.stringify((await repo.liveHold(qid))?.missing));
}
const accept = (repo: Fake) => async (row: QuoteRow) => { repo.quotes.get(row.id)!.status = 'submitted'; return true; };

// ── the four live quotes ─────────────────────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
const F = FIX as any;
for (const view of ['withheld', 'served'] as const) {
  Deno.test(`inquiry 78aa5217, inbox spec ${view}: the form offers everything the release checks, and filling it releases all four quotes`, async () => {
    for (const [qid, f] of Object.entries(F.quotes) as [string, { q: Partial<QuoteRow>; lines: Line[] }][]) {
      const repo = new Fake();
      repo.quotes.set(qid, { id: qid, inquiry_id: 'inq-zz', supplier_id: SUP.id, status: 'draft', option_no: 1, submission_id: 's', ...f.q } as QuoteRow);
      repo.items.set(qid, structuredClone(f.lines));
      const ctx = { category: F.category, requirements: F.requirements, ref: 'ZZ78AA', now: NOW };
      const a = assessQuote({ category: F.category, lines: f.lines, terms: f.q, requirements: F.requirements });
      hold(repo, qid, a.missing);
      const release = releaseOf(repo, inquiry(F.category, view === 'served' ? { customer_requirements: F.requirements } : null), ctx);
      const v = await deskView(repo.quotes.get(qid)!, f.lines, repo.holds[0], ctx, release);
      for (const m of v.pre?.missing ?? []) assert(onForm(v.schema, m), `${qid.slice(0, 8)}: the release asks line ${m.line_no} ${m.attr}, the form does not`);
      // The release judges with the desk's requirements: line 3 names the customer's component, so `material` is not asked.
      assertEquals((v.pre?.missing ?? []).filter((m) => m.attr === 'material' && m.line_no === 3), [], `${qid.slice(0, 8)}: line 3 asked the trade's material`);
      const total = f.lines.reduce((s, l) => s + Number(l.amount || 0), 0);
      await fillUntilDone(repo, qid, ctx, release, total);
      const ok = await approve(repo, qid, SUP, SUP.email, true, ctx, accept(repo), release);
      assert(ok.ok && ok.released, `${qid.slice(0, 8)}: ${JSON.stringify(ok)}`);
    }
  });
}

Deno.test('a6f89b7f and 080e2091: the supplier\'s exact recorded answers, filled once, are complete and release (on main: complete:false missing [material])', async () => {
  for (const [qid, values] of Object.entries(F.supplier_answers) as [string, { lines: Record<string, Record<string, string>> }][]) {
    const f = F.quotes[qid];
    const repo = new Fake();
    repo.quotes.set(qid, { id: qid, inquiry_id: 'inq-zz', supplier_id: SUP.id, status: 'draft', option_no: 1, submission_id: 's', ...f.q } as QuoteRow);
    repo.items.set(qid, structuredClone(f.lines));
    const ctx = { category: F.category, requirements: F.requirements, ref: 'ZZ78AA', now: NOW };
    hold(repo, qid, assessQuote({ category: F.category, lines: f.lines, terms: f.q, requirements: F.requirements }).missing);
    const release = releaseOf(repo, inquiry(F.category, null), ctx);   // the inbox withheld the spec, as on production
    const r = await fillIn(repo, qid, SUP, values, ctx, undefined, release);
    assert(r.ok && r.complete, `${qid.slice(0, 8)}: ${JSON.stringify(r).slice(0, 300)}`);
    const ok = await approve(repo, qid, SUP, SUP.email, true, ctx, accept(repo), release);
    assert(ok.ok && ok.released, `${qid.slice(0, 8)}: ${JSON.stringify(ok).slice(0, 300)}`);
  }
});

Deno.test('the trade\'s material on a wall-panel line is asked in neutral words, never "wallpaper type"', () => {
  const m = TRADES.wallpaper.attrs.find((x) => x.code === 'material')!;
  assert(!/wallpaper/i.test(m.en) && !/ورق الجدران/.test(m.ar), `${m.en} / ${m.ar}`);
});

// ── the generated set ────────────────────────────────────────────────────────────────────────────────────────────────
// A seeded generator (the same 400 cases every run): trade, 1-5 lines, each trade attribute present or absent, a line's
// own specification text present or absent, a reasoned trade / no-material / named-component read or none, the customer's
// requirements (a named component or none, installation and warranty asked or not), every term present or absent, the VAT
// basis stated or not, a foreign currency in the notes or not, a BOQ that matches or does not, and the inbox's view of the
// requirements served or withheld.
function rng(seed: number) { return () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }; }
Deno.test('generated: for every hold, every item the release check reports is on the form, and filling the form reaches the release', async () => {
  const R = rng(20261110);
  const pick = <T,>(xs: T[]) => xs[Math.floor(R() * xs.length)];
  const yes = (p = 0.5) => R() < p;
  const CATS = ['wallpaper', 'joinery', 'fitout', 'hvac', 'gypsum', 'tiling', 'mep', 'glazing'];
  const DESCS = ['Supply and install wall panels', 'Kitchen base cabinets', 'Split AC unit 2 TR', 'Gypsum partition', 'Porcelain floor tiles 60x60', 'Removal and disposal of existing finishes', 'Aluminium trims', 'Glass partition 10 mm'];
  let cases = 0, released = 0;
  for (let n = 0; n < 400; n++) {
    const category = pick(CATS);
    const comp = ['fitout', 'mep'].includes(category);
    const trade = comp ? pick(category === 'mep' ? ['hvac', 'electrical', 'plumbing'] : ['joinery', 'gypsum', 'tiling', 'wallpaper']) : category;
    const attrs = TRADES[trade]?.attrs ?? [];
    const named = yes(0.4);
    const requirements: Requirements = { version: 1, category, installation: { required: pick(['yes', 'supply_only', 'not_sure']) }, warranty: { required: pick(['yes', 'not_needed']) },
      materials: named ? [{ component: 'material', label_en: 'Material', choice: 'other', note: 'ZZ demo material' }] : [] };
    const lines: Line[] = Array.from({ length: 1 + Math.floor(R() * 5) }, (_, i) => {
      const spec: Record<string, string> = {}; const src: Record<string, 'reasoned' | 'supplier_portal' | 'extracted'> = {};
      for (const a of attrs) if (yes(0.4)) { spec[a.code] = a.type === 'number' ? '18' : 'ZZ value'; src[a.code] = pick(['reasoned', 'supplier_portal', 'extracted']); }
      if (comp && yes(0.7)) { spec._trade = yes(0.15) ? 'none' : trade; src._trade = 'reasoned'; }
      if (named && yes(0.5)) { spec['_names:material'] = 'ZZ'; src['_names:material'] = 'reasoned'; if (yes(0.5)) { spec.component_material = 'ZZ PVC'; src.component_material = 'reasoned'; } }
      const amount = 100 * (1 + Math.floor(R() * 50));
      return { line_no: i + 1, description: pick(DESCS), specification: yes(0.5) ? 'ZZ panel 8 mm, 250 x 2800 mm, made in Germany' : null, qty: yes(0.5) ? 2 : null, unit: 'nos', unit_price: null, amount, spec, spec_source: src };
    });
    const total = lines.reduce((s, l) => s + Number(l.amount), 0);
    const q = { id: 'q' + n, inquiry_id: 'inq-zz', supplier_id: SUP.id, status: 'draft', option_no: 1, submission_id: 's', quote_amount: total,
      price_ex_vat: yes(0.8) ? total : null, vat_treatment: yes(0.8) ? 'exclusive' : null, lead_time: yes(0.7) ? '14 days' : '', validity: yes(0.7) ? '30 days' : '',
      warranty: yes(0.6) ? '2 years' : '', notes: yes(0.15) ? 'rates converted from USD' : '',
      terms_spec: yes(0.5) ? { installation: { included: 'yes' as const, detail: 'own team', source: 'reasoned' as const }, warranty: { period: '2 years', coverage: 'parts', source: 'reasoned' as const } } : {} } as QuoteRow;
    const boq = yes(0.3) ? [...lines.slice(0, 1).map((l) => ({ description: l.description, qty: l.qty ?? null, unit: 'nos' })), ...(yes(0.5) ? [{ description: 'ZZ unrelated works item', qty: 1, unit: 'lot' }] : [])] : [];
    const ctx = { category, requirements, ref: 'ZZGEN', now: NOW };
    const desk = assessQuote({ category, lines, terms: q, requirements });
    if (desk.missing.some((m) => m.attr === 'line_items')) continue;   // a revised quotation, never the form
    const repo = new Fake(); repo.quotes.set(q.id, q); repo.items.set(q.id, structuredClone(lines));
    hold(repo, q.id, desk.missing);
    const release = releaseOf(repo, inquiry(category, yes() ? { customer_requirements: requirements } : null, boq), ctx);
    const v = await deskView(q, lines, repo.holds[0], ctx, release);
    for (const m of v.pre?.missing ?? []) assert(onForm(v.schema, m), `case ${n} (${category}): the release asks ${m.scope === 'line' ? 'line ' + m.line_no + ' ' : ''}${m.attr}, the form does not offer it`);
    cases++;
    await fillUntilDone(repo, q.id, ctx, release, total);
    const ok = await approve(repo, q.id, SUP, SUP.email, true, ctx, accept(repo), release);
    assert(ok.ok && ok.released, `case ${n} (${category}): approve after filling everything shown answered ${JSON.stringify(ok).slice(0, 400)}`);
    released++;
  }
  assert(cases >= 300, `only ${cases} cases ran`);
  assertEquals(released, cases);
});
