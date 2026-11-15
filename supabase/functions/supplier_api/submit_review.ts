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
import { readDelivery, readInstallation, readWarranty, RELEASE_CHOICES, termItem, type MissingItem, type TermsSpec } from '../_shared/line_specs/assess.ts';
import { foreignCurrency, parseQty, reviewQuotation, sanitizeSpec, sanitizeTermsSpec, type DeskInputs, type Issue, type SafeInquiry, type WLine, type Working } from './quote_review.ts';

const num = (v: unknown): number | null => { const n = Number(v); return Number.isFinite(n) && String(v ?? '').trim() !== '' ? n : null; };
const str = (v: unknown): string => (v == null ? '' : String(v));

/** The supplier's explanations, as the engineer recorded them. Never the caller's. */
export type Resolved = {
  boq_excluded: Record<string, string>; qty_explained: Record<string, string>;
  /** His answer to the VAT-basis question, as the chat recorded it (quote_review/corrections.ts) or as the hold desk took it on
   *  an earlier submission of the same option (carryHeldAnswers). Never the caller's: a body field is never read for it. */
  vat_answered?: string | null;
};
export const NOTHING_EXPLAINED: Resolved = { boq_excluded: {}, qty_explained: {} };
const vatChoice = (v: unknown): string | null => (RELEASE_CHOICES.vat.some((c) => c.value === v) ? String(v) : null);
/** Whatever carries the explanations (a quote_reviews row's `working`), read defensively. */
// deno-lint-ignore no-explicit-any
export function resolvedFrom(working: any): Resolved {
  const o = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, string> : {});
  return { boq_excluded: o(working?.boq_excluded), qty_explained: o(working?.qty_explained), vat_answered: vatChoice(working?.vat_answered) };
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
    // WHERE EACH VALUE CAME FROM travels with it (evidence run of 10 Nov 2026, finding a). What reasoning read about a
    // line — which trade it is (_trade), that it carries no material (_not_material) — is honoured only with its source
    // 'reasoned' (assess.ts READ). Without spec_source the release review read every line of a composite quote as
    // unread, and asked line 1 ("Removal and disposal of existing PVC wall panels") its exact `specification`, which
    // the desk, reading the same row WITH its sources, never asked.
    ...(r?.spec_source && typeof r.spec_source === 'object' ? { spec_source: r.spec_source as WLine['spec_source'] } : {}),
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
  return { ...w, boq_excluded: r.boq_excluded, qty_explained: r.qty_explained, ...(r.vat_answered ? { vat_answered: r.vat_answered } : {}) };
}

/**
 * One review issue in the shape the HOLD DESK stores and renders (assess.ts MissingItem), so a quote
 * held by the review shows the same card as a quote held for a missing spec. The engineer's sentence
 * is the label, in both languages; there is nothing to convert because both carry the same thing —
 * one detail, named, with what to do about it.
 */
export function issueAsMissing(i: Issue): MissingItem {
  const base = { description: null, label_en: i.en, label_ar: i.ar };
  // AN ITEM THE DESK CAN ANSWER (evidence run of 10 Nov 2026, finding a). A release-review item reopens the hold and
  // is shown on the hold desk's form, so each one is keyed by what answers it. A detail of a line (its specification)
  // is a field of that line; a BOQ line, a quantity, a unit or a total difference is the supplier's explanation
  // (the chat records the same as quote_reviews.working boq_excluded / qty_explained); the VAT basis and prices in
  // AED are choices; a price is a number. Every other issue keeps its own attribute.
  const quote = (attr: string, x: Partial<MissingItem> = {}): MissingItem => ({ ...base, scope: 'quote', line_no: null, attr, type: 'text', ...x });
  switch (i.code) {
    case 'boq_line_not_priced': return i.boq_line ? quote(`boq:${i.boq_line}`) : quote(i.code);
    case 'qty_mismatch': return i.boq_line ? quote(`boq:${i.boq_line}:qty`) : quote(i.code);
    case 'unit_mismatch': return i.boq_line ? quote(`boq:${i.boq_line}:unit`) : quote(i.code);
    case 'line_unpriced': return i.line_no ? quote(`line:${i.line_no}`) : quote(i.code);
    case 'total_mismatch': return quote('total');
    case 'currency_not_aed': return quote('currency', { type: 'choice', options: RELEASE_CHOICES.currency.map((c) => c.value), option_labels: RELEASE_CHOICES.currency });
    case 'vat_basis': return quote('vat', { type: 'choice', options: RELEASE_CHOICES.vat.map((c) => c.value), option_labels: RELEASE_CHOICES.vat });
    case 'vat_ex_price': { const p = termItem('price_ex_vat'); return quote('price_ex_vat', { type: 'number', unit: p.unit, unit_ar: p.unit_ar }); }
    default: return { ...base, scope: i.line_no ? 'line' : 'quote', line_no: i.line_no, attr: i.attr || i.code, type: 'text' };
  }
}

/**
 * The supplier's answers on the hold desk, applied to the quotation the release review reads. Only an answer to an
 * item the hold ASKED is ever here (workflow.ts fillIn accepts a release-review answer only for an item on the hold,
 * and the hold is written by the sales engineer's desk, never by the caller), so this is the chat's own channel —
 * "BOQ line 3 excluded — by others" — through the desk's form, not a way past the review.
 */
export function withDeskAnswers(w: Working, answers: Record<string, string> | null | undefined): Working {
  const a = answers ?? {};
  const out: Working = { ...w, boq_excluded: { ...w.boq_excluded }, qty_explained: { ...w.qty_explained } };
  for (const [k, v] of Object.entries(a)) {
    if (!str(v).trim()) continue;
    let m: RegExpMatchArray | null;
    if ((m = k.match(/^boq:(\d+)$/))) out.boq_excluded[m[1]] = v;
    else if ((m = k.match(/^boq:(\d+):qty$/))) out.qty_explained[m[1]] = v;
    else if ((m = k.match(/^boq:(\d+):unit$/))) out.qty_explained[`${m[1]}:unit`] = v;
    else if ((m = k.match(/^line:(\d+)$/))) out.qty_explained[`line:${m[1]}`] = v;
    else if (k === 'total') out.qty_explained.total = v;
    else if (k === 'currency' && v === 'aed') out.foreign_currency = null;
    else if (k === 'vat' && RELEASE_CHOICES.vat.some((c) => c.value === v)) out.vat_answered = v;
  }
  return out;
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
  /** His answer to the VAT-basis question on this row's hold desk (the hold's supplier_values `answers.vat`, the latest). */
  vat: string | null;
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
  // The VAT answer, the latest given (workflow.ts answersOf reads supplier_values the same way).
  let vat: string | null = null;
  for (const h of (holds || []).filter(mineOnly)) for (const e of (Array.isArray(h?.supplier_values) ? h.supplier_values : [])) { const v = vatChoice(e?.answers?.vat); if (v) vat = v; }
  return { quote_id: id, option_no: Number(q.option_no) || 1, terms_spec: ts, validity: answeredValidity && str(q.validity).trim() ? str(q.validity) : null, lines, vat };
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
  { body: SubmitBody; options: Record<string, { held: boolean; terms_spec: TermsSpec | null; validity: string }>; carried: string[]; vat_answered: string | null } {
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
  // HIS VAT ANSWER IS CARRIED TOO (independent review of 15 Nov 2026, item 6): a re-submission after he answered the VAT
  // question on the desk was asked it again, because nothing carried the answer. It is carried when every option written
  // answered it the same way; it then stands only while the basis this submission states is that answer (vat.ts answerStands).
  const vats = all.map((h) => h?.vat ?? null);
  const vat_answered = vats.length && vats.every((v) => v && v === vats[0]) ? vats[0] : null;
  if (vat_answered) carried.push('vat');
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
  if (!carried.length) return { body, options, carried, vat_answered };
  const reviewTs = withSent(review);
  const out: SubmitBody = { ...body, items: Array.isArray(body.items) ? outItems : body.items, validity };
  if (reviewTs) out.terms_spec = reviewTs;
  return { body: out, options, carried, vat_answered };
}

// ── THE RELEASE CHECK IS ONE FUNCTION, AND IT JUDGES WHAT THE DESK JUDGES (live re-run ea40c830, 10 Nov 2026) ────────────
// After #1896 the form still asked what deskAssess asked, while spec_fill / spec_approve asked this review: two evaluators.
// Measured on quotes a6f89b7f and 080e2091 (RFQ of inquiry 78aa5217, wallpaper): the desk read the customer's requirements
// from the inquiry row (a named material component, so line 3 was asked component_material, which reasoning had already
// filled), while the review read them from the supplier-inbox view (inqSafe.spec), which the inbox withholds or scrubs;
// with no named component, line 3 fell back to the trade's mandatory `material` ("wallpaper type"), which the form never
// showed. The supplier filled every field, spec_fill answered complete:false missing [material], and the hold closed
// unresolved when the customer chose. Now the review is judged on the STORED row with the desk's own requirements and
// checklist (rule 8 = deskAssess), and no second model reading: the gate's settled reading is already on the row. The
// BOQ, the VAT basis, the currency and the totals (rules 1-7) are still the review's own, read from the inbox's job.
/** The release review of a stored quote, as spec_hold, spec_fill and spec_approve all run it (supplier_api actions/quotes.ts). */
// deno-lint-ignore no-explicit-any
export function releaseReview(inq: SafeInquiry, row: any, lines: any[], answers: Record<string, string>, desk: DeskInputs, resolved: Resolved = NOTHING_EXPLAINED, now: Date = new Date()) {
  const w = withDeskAnswers(withResolved(workingFromStoredQuote(row, lines), resolved), answers);
  const rvw = reviewQuotation(inq, w, now, desk);
  return rvw.approved ? null : { missing: rvw.issues.map(issueAsMissing), issues: rvw.issues };
}
