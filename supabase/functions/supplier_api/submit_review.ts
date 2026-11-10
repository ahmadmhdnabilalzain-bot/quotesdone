// submit_review — THE QUOTATION UNDER REVIEW, BUILT FROM WHAT A DOOR ACTUALLY SENT.
// Seat: sales_engineer. Audit of 22 Sep 2026, finding SP-F-02.
//
// reviewQuotation (quote_review.ts) is the founder's own rule set — "the most important part in the
// whole supplier portal" — and until this change it ran ONLY inside the quotation-review chat. Three
// other doors reach a customer without it: submit_quote from the portal's quote form, submit_quote from
// the Quote Builder's one-click accept, and spec_approve, which releases a held quote.
//
// This module is the pure half: it turns what a door sent (or what is already stored on a quote row)
// into the `Working` shape the review reads, so index.ts holds no second copy of that mapping and the
// two payload shapes can be tested without a database (submit_review.test.ts).
//
// WHAT IT DELIBERATELY DOES NOT TAKE FROM THE CALLER. `boq_excluded` and `qty_explained` are the
// supplier's recorded explanations — "BOQ line 3 excluded, by others" — and they SILENCE a rule. They
// are therefore passed in from public.quote_reviews.working, which only the sales engineer writes, and
// never read off the request body: otherwise a supplier posting straight to the endpoint could declare
// every BOQ line excluded and walk past the whole review.
import { readDelivery, readInstallation, readWarranty, type MissingItem, type TermsSpec } from '../_shared/line_specs/assess.ts';
import { foreignCurrency, parseQty, sanitizeSpec, sanitizeTermsSpec, type Issue, type WLine, type Working } from './quote_review.ts';

const num = (v: unknown): number | null => { const n = Number(v); return Number.isFinite(n) && String(v ?? '').trim() !== '' ? n : null; };
const str = (v: unknown): string => (v == null ? '' : String(v));

/** The supplier's explanations, as the engineer recorded them. Never the caller's. */
export type Resolved = { boq_excluded: Record<string, string>; qty_explained: Record<string, string> };
export const NOTHING_EXPLAINED: Resolved = { boq_excluded: {}, qty_explained: {} };
/** Whatever carries the explanations (a quote_reviews row's `working`), read defensively. */
// deno-lint-ignore no-explicit-any
export function resolvedFrom(working: any): Resolved {
  const o = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, string> : {});
  return { boq_excluded: o(working?.boq_excluded), qty_explained: o(working?.qty_explained) };
}

// deno-lint-ignore no-explicit-any
export type SubmitBody = Record<string, any>;

/**
 * The quotation as submit_quote received it. `scrubbed` is the free text AFTER scrubIdentity, because
 * that is what will be stored and what the customer would read — reviewing the raw text would review
 * something that never exists.
 */
export function workingFromSubmit(body: SubmitBody, scrubbed: { notes: string; scope: string; conditions: string; exclusions: string }, terms_spec: TermsSpec, masked_terms: string[], trn: string | null): Working {
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(body.items) ? body.items : [];
  const lines: WLine[] = items.map((it) => ({
    description: str(it?.description),
    qty: it?.qty == null ? '' : String(it.qty),
    unit: str(it?.unit),
    unit_price: num(it?.unit_price),
    amount: num(it?.amount) ?? (((num(it?.qty) || 0) * (num(it?.unit_price) || 0)) || null),
    ...(it?.specification ? { specification: String(it.specification) } : {}),
    // The same cleaning the stored rows get (sanitizeSpec), so the review and the hold gate judge one set of values.
    ...(it?.spec && typeof it.spec === 'object' ? { spec: sanitizeSpec(it.spec).spec } : {}),
  }));
  const lead_time = str(body.lead_time), validity = str(body.validity), payment_terms = str(body.payment_terms), warranty = str(body.warranty);
  return {
    lines, amount: num(body.amount), subtotal: num(body.subtotal), vat_amount: num(body.vat_amount),
    vat_treatment: body.vat_treatment ? String(body.vat_treatment) : null, price_ex_vat: num(body.price_ex_vat), trn,
    gross_amount: num(body.gross_amount), discount_amount: num(body.discount_amount), discount_label: body.discount_label ? str(body.discount_label).slice(0, 80) : null,
    lead_time, validity, payment_terms, warranty,
    scope: scrubbed.scope, conditions: scrubbed.conditions, exclusions: scrubbed.exclusions, notes: scrubbed.notes,
    terms_spec, masked_terms, option_totals: body.option_totals && typeof body.option_totals === 'object' ? body.option_totals : {},
    // A currency other than AED anywhere in the free text the supplier typed (rule 5). The chat reads
    // this off the uploaded file; a typed quotation has no file, so its own words are the text.
    foreign_currency: foreignCurrency([scrubbed.notes, scrubbed.scope, scrubbed.conditions, scrubbed.exclusions, payment_terms, ...lines.map((l) => l.description)].join('\n')),
    boq_excluded: {}, qty_explained: {}, corrections: [],
  };
}

/**
 * The quotation as it is already STORED — the shape spec_approve needs, because by then the supplier
 * filled the missing details in through the hold desk and the row, not the request, is the quotation.
 */
// deno-lint-ignore no-explicit-any
export function workingFromStoredQuote(q: any, rows: any[]): Working {
  const lines: WLine[] = (rows || []).map((r) => ({
    description: str(r?.description),
    qty: r?.qty == null ? '' : String(r.qty),
    unit: str(r?.unit),
    unit_price: num(r?.unit_price),
    amount: num(r?.amount) ?? (((num(r?.qty) || 0) * (num(r?.unit_price) || 0)) || null),
    ...(r?.specification ? { specification: String(r.specification) } : {}),
    ...(r?.spec && typeof r.spec === 'object' ? { spec: r.spec as Record<string, string> } : {}),
  }));
  return {
    lines, amount: num(q?.quote_amount) ?? num(q?.amount_as_stated), subtotal: null, vat_amount: num(q?.vat_amount),
    vat_treatment: q?.vat_treatment ? String(q.vat_treatment) : null, price_ex_vat: num(q?.price_ex_vat), trn: q?.supplier_trn ?? null,
    gross_amount: num(q?.gross_amount), discount_amount: num(q?.discount_amount), discount_label: q?.discount_label ? str(q.discount_label) : null,
    lead_time: str(q?.lead_time), validity: str(q?.validity), payment_terms: str(q?.payment_terms), warranty: str(q?.warranty),
    scope: str(q?.scope), conditions: str(q?.conditions), exclusions: str(q?.exclusions), notes: str(q?.notes),
    terms_spec: (q?.terms_spec ?? {}) as TermsSpec, masked_terms: Array.isArray(q?.masked_terms) ? q.masked_terms : [],
    option_totals: {},
    // Stored text has already been through the review or the hold desk; a currency it still names is read.
    foreign_currency: foreignCurrency([q?.notes, q?.scope, q?.conditions, q?.exclusions, q?.payment_terms].filter(Boolean).map(String).join('\n')),
    boq_excluded: {}, qty_explained: {}, corrections: [],
  };
}

/** Apply the engineer's recorded explanations to a working quote. */
export function withResolved(w: Working, r: Resolved): Working {
  return { ...w, boq_excluded: r.boq_excluded, qty_explained: r.qty_explained };
}

/**
 * One review issue in the shape the HOLD DESK stores and renders (assess.ts MissingItem), so a quote
 * held by the review shows the same card as a quote held for a missing spec. The engineer's sentence
 * is the label, in both languages; there is nothing to convert because both carry the same thing —
 * one detail, named, with what to do about it.
 */
export function issueAsMissing(i: Issue): MissingItem {
  return { scope: i.line_no ? 'line' : 'quote', line_no: i.line_no, description: null, attr: i.attr || i.code, type: 'text', label_en: i.en, label_ar: i.ar };
}

/** One quantity reader, so a caller need not import quote_review.ts for it. */
export { parseQty };

// ── AN ANSWERED HOLD ITEM IS NEVER ASKED AGAIN (defect F5, production walk of 10 Nov 2026) ──────────────────
// The supplier answers a hold in the hold panel (spec_fill -> workflow.ts fillIn), and the answers land on the
// QUOTE ROW: quotes.terms_spec (delivery / installation / warranty / components, source 'supplier_portal'),
// quote_items.spec with spec_source 'supplier_portal', and quotes.validity (recorded in the hold's supplier_values).
// A price refresh posts the quote form again — which has no installation field — and submit_quote reviewed the
// request body alone, so the review held the quote for `installation_included` a second time, with no spec-hold
// panel to answer it on (report docs/reports/2026-11-10-walks-on-production.md, F5).
//
// The rule is carryOver's (quote_review/corrections.ts), the chat's own: every detail the new submission states
// wins; every detail it does not state keeps the supplier's answer; a line's answered specification follows the
// line that says the same thing. Only answers given on THIS quote row — this job, this supplier, this option —
// are carried: another job's quote, another supplier's, or this supplier's other option is a different quotation.
// The ex-VAT price is deliberately NOT carried: a price refresh restates the price, and an answer about the old
// figure is not an answer about the new one.

/** What the supplier already answered on one stored quote row. */
export type HeldAnswers = {
  quote_id: string; option_no: number;
  terms_spec: TermsSpec;
  /** The stored validity, only when the supplier gave it in the hold panel (a hold's supplier_values). */
  validity: string | null;
  lines: { description: string; spec: Record<string, string> }[];
};

const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const portal = (v: unknown) => isObj(v) && v.source === 'supplier_portal';

/**
 * The answers stored on quote row `q`, or null when the row is not this supplier's quote on this job. `rows` and
 * `holds` are filtered to q's own id, so a caller that read several quotes at once cannot cross them.
 */
// deno-lint-ignore no-explicit-any
export function heldAnswersOf(owner: { inquiry_id: string; supplier_id: number }, q: any, rows: any[], holds: any[]): HeldAnswers | null {
  if (!q || String(q.inquiry_id) !== String(owner.inquiry_id) || Number(q.supplier_id) !== Number(owner.supplier_id)) return null;
  const id = String(q.id);
  const mineOnly = (r: { quote_id?: unknown }) => r?.quote_id == null || String(r.quote_id) === id;
  const st = isObj(q.terms_spec) ? q.terms_spec as TermsSpec : {};
  const ts: TermsSpec = {};
  if (portal(st.delivery) && str(st.delivery?.value).trim()) ts.delivery = st.delivery;
  if (portal(st.installation) && (st.installation?.included === 'yes' || st.installation?.included === 'no')) ts.installation = st.installation;
  if (portal(st.warranty) && str(st.warranty?.period).trim()) ts.warranty = st.warranty;
  const comps = Object.entries(isObj(st.components) ? st.components : {}).filter(([, v]) => portal(v) && str((v as { value?: unknown }).value).trim());
  if (comps.length) ts.components = Object.fromEntries(comps) as TermsSpec['components'];
  const answeredValidity = (holds || []).filter(mineOnly).some((h) => (Array.isArray(h?.supplier_values) ? h.supplier_values : [])
    .some((e: { values?: { terms?: Record<string, unknown> } }) => str(e?.values?.terms?.validity).trim() !== ''));
  const lines = (rows || []).filter(mineOnly).map((r) => {
    const spec = isObj(r?.spec) ? r.spec : {}, src = isObj(r?.spec_source) ? r.spec_source : {};
    return { description: str(r?.description), spec: Object.fromEntries(Object.entries(spec).filter(([k, v]) => src[k] === 'supplier_portal' && str(v).trim()).map(([k, v]) => [k, str(v)])) };
  }).filter((l) => l.description.trim() && Object.keys(l.spec).length);
  return { quote_id: id, option_no: Number(q.option_no) || 1, terms_spec: ts, validity: answeredValidity && str(q.validity).trim() ? str(q.validity) : null, lines };
}

/** The option each submitted item belongs to (index-aligned with `items`); null for a heading or a line shared by several options. */
export function optionOfEach<T>(items: T[], plan: { option_no: number; lines: T[] }[]): (number | null)[] {
  return items.map((it) => { const hit = plan.filter((p) => p.lines.includes(it)); return hit.length === 1 ? hit[0].option_no : null; });
}

const tokens = (s: unknown) => str(s).toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((t) => t.length > 1);
type TermKey = 'delivery' | 'installation' | 'warranty';

/**
 * submit_quote's body with the supplier's held answers carried in (for the review), and what each option's row is
 * written with (so the hold gate, which reads the row, agrees with the review). `held` must already be this
 * supplier's quotes on this job (heldAnswersOf); `optionOf` is optionOfEach(body.items, plan); `planned` the option
 * numbers this submission writes. The shared review carries a term only when EVERY planned option answered it.
 */
export function carryHeldAnswers(body: SubmitBody, held: HeldAnswers[], optionOf: (number | null)[], planned: number[]):
  { body: SubmitBody; options: Record<string, { held: boolean; terms_spec: TermsSpec | null; validity: string }>; carried: string[] } {
  const byOpt = new Map(held.map((h) => [h.option_no, h]));
  const sentTs = sanitizeTermsSpec(body.terms_spec) ?? {};
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(body.items) ? body.items : [];
  // What the submission itself states wins (the readers carryOver uses).
  const stated: Record<TermKey, boolean> = {
    delivery: !!sentTs.delivery || !!readDelivery(str(body.lead_time)),
    warranty: !!sentTs.warranty || !!readWarranty(str(body.warranty)).period,
    installation: !!sentTs.installation || !!readInstallation(
      items.map((it, i) => ({ line_no: i + 1, description: str(it?.description), specification: it?.specification ?? null, notes: it?.notes ?? null, install: num(it?.install), labour: num(it?.labour) })) as never,
      { scope: str(body.scope), conditions: str(body.conditions), notes: str(body.notes), exclusions: str(body.exclusions) }).included,
  };
  const keep = (h: HeldAnswers | undefined): TermsSpec => {
    const t: TermsSpec = {};
    if (!h) return t;
    for (const k of ['delivery', 'installation', 'warranty'] as const) if (h.terms_spec[k] && !stated[k]) (t as Record<string, unknown>)[k] = h.terms_spec[k];
    const comps = Object.entries(h.terms_spec.components ?? {}).filter(([c]) => !sentTs.components?.[c]);
    if (comps.length) t.components = Object.fromEntries(comps);
    return t;
  };
  const withSent = (t: TermsSpec): TermsSpec | null => {
    const out: TermsSpec = { ...t, ...sentTs };
    if (t.components || sentTs.components) out.components = { ...(t.components ?? {}), ...(sentTs.components ?? {}) };
    return Object.keys(out).length ? out : null;
  };
  const sentValidity = str(body.validity).trim();
  // `held` false: that option's row was not read (a new option, or a read that failed), so its row keeps what it has.
  const options: Record<string, { held: boolean; terms_spec: TermsSpec | null; validity: string }> = {};
  for (const o of planned) {
    const h = byOpt.get(o);
    options[String(o)] = { held: !!h, terms_spec: withSent(keep(h)), validity: sentValidity ? str(body.validity) : (h?.validity ?? str(body.validity)) };
  }
  // The one review of the submission: a term every planned option answered (the first option's words).
  const all = planned.map((o) => byOpt.get(o));
  const carried: string[] = [];
  const review: TermsSpec = {};
  if (all.length && all.every(Boolean)) {
    const per = all.map((h) => keep(h));
    for (const k of ['delivery', 'installation', 'warranty'] as const) if (per.every((t) => t[k])) { (review as Record<string, unknown>)[k] = per[0][k]; carried.push(k); }
    const comps = Object.keys(per[0].components ?? {}).filter((c) => per.every((t) => t.components?.[c]));
    if (comps.length) { review.components = Object.fromEntries(comps.map((c) => [c, per[0].components![c]])); carried.push(...comps.map((c) => `component:${c}`)); }
  }
  let validity = str(body.validity);
  if (!sentValidity && all.length && all.every((h) => h?.validity)) { validity = all[0]!.validity!; carried.push('validity'); }
  // A line's answered specification follows the line that says the same thing, within its own option.
  const used = new Set<string>();
  const outItems = items.map((it, i) => {
    const h = optionOf[i] == null ? undefined : byOpt.get(optionOf[i]!);
    if (!h || !isObj(it)) return it;
    const nt = tokens(it.description); if (!nt.length) return it;
    let best = -1, score = 0;
    h.lines.forEach((l, j) => {
      if (used.has(`${h.option_no}:${j}`)) return;
      const pt = new Set(tokens(l.description));
      const s = l.description.trim().toLowerCase() === str(it.description).trim().toLowerCase() ? 2 : nt.filter((t) => pt.has(t)).length / nt.length;
      if (s >= 0.5 && s > score) { best = j; score = s; }
    });
    if (best < 0) return it;
    used.add(`${h.option_no}:${best}`);
    const have = isObj(it.spec) ? it.spec as Record<string, unknown> : {};
    const add = Object.entries(h.lines[best].spec).filter(([k]) => have[k] == null || str(have[k]).trim() === '');
    if (!add.length) return it;
    carried.push(...add.map(([k]) => `line_spec:${i + 1}:${k}`));
    return { ...it, spec: { ...have, ...Object.fromEntries(add) } };
  });
  if (!carried.length) return { body, options, carried };
  const reviewTs = withSent(review);
  const out: SubmitBody = { ...body, items: Array.isArray(body.items) ? outItems : body.items, validity };
  if (reviewTs) out.terms_spec = reviewTs;
  return { body: out, options, carried };
}
