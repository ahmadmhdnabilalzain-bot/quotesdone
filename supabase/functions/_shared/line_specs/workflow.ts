// line_specs/workflow.ts — the sales engineer's hold desk: hold, notify, fill in, regenerate,
// approve, release. Every record it writes is owned by and attributed to `sales_engineer` (founder,
// 14 Sep 2026: "its always the sales agent. no other agent is involved in customer or supplier
// portal").
//
// HOW THE SUPPLIER IS REACHED (founder, 14 Sep 2026, founder_instruction #143): "if there is a
// notification on the portal only, then he might not notice it, so again the sales agent need to
// communicate with the customer support agent to communicate through whatsapp and email and notify."
// And #158: "we notify directly." So every notice this desk raises — the hold, the regenerated
// quotation to approve, the release — is a DELIVERY REQUEST from sales_engineer to customer_support
// (the #614 model: notifications.requested_by = sales_engineer, sender = customer_support), on email
// AND WhatsApp, queued in the same call that holds the quote and followed at once by a dispatch kick,
// so nothing waits for the next outbox tick. The portal shows the hold on the supplier's card
// (supplier_api inbox). No reminders and no expiry: a hold stays open until the customer reveals a
// quote on that request (the database then closes it as unresolved_at_decision — see
// scripts/sql/a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql).
//
// MEASURED: there is no supplier↔sales-engineer portal thread in the estate (public.messages is
// customer↔supplier only, sender in ('customer','supplier'); chat_threads is customer↔supplier;
// agent_chats is the internal console). So "answer in the supplier's open conversation" has nothing
// to attach to today, and the channel notice always goes.
//
// The state of one hold episode lives in public.quote_spec_hold, one row per episode: the ORIGINAL
// submission (original_snapshot), every set of values the supplier entered (supplier_values), the
// REGENERATED standardised quotation (regenerated + its PDF), who approved it and when.
//
//   open ──fill──▶ open (still missing) ──fill──▶ awaiting_approval ──approve──▶ released
//     └── resubmit (a revised quote) ──▶ superseded, and the new quote is gated again
//     └── the customer reveals a quote on the request first ──▶ unresolved_at_decision (database)
//
// Written against a small repository interface so the workflow test runs entirely in memory: no
// database, no network, and therefore no way to reach a real supplier.
import { approvalNotice, assessQuote, deliveryOf, holdNotice, lineText, releasedNotice, SEAT, termItem, validateLineValue, validateTerm, type Assessment, type FillError, type Line, type MissingItem, type Requirements, type Terms, type TermsSpec } from './assess.ts';
import { TRADES, type Attr } from './model.ts';
import { applyReading, type QuoteReading } from '../reasoned_matching.ts';
import { needsChecklist, withReasoned } from './reasoned_specs.ts';
import { optionLabel } from './options.ts';
import { maskIdentityNumbers } from '../identity_numbers.ts';
import { requestDelivery } from '../deliver.ts';
import { quoteDocument, type ArTexts, type InquiryRow, type Item, type QuoteRow as DocQuote } from '../quote_documents.ts';

export type QuoteRow = Terms & {
  id: string; inquiry_id: string; supplier_id: number; status: string; option_no: number; submission_id: string | null;
  quote_amount: number; validity?: string | null; payment_terms?: string | null; vat_treatment?: string | null;
};
// Customer-bound text never carries a TRN or a licence number (identity_numbers.ts).
const safe = (v: unknown) => (v == null ? null : maskIdentityNumbers(v).replace(/\s{2,}/g, ' ').trim() || null);
export type HoldState = 'open' | 'awaiting_approval' | 'released' | 'superseded' | 'unresolved_at_decision';
export type HoldRow = {
  id: number; quote_id: string; inquiry_id: string; supplier_id: number; submission_id: string | null; option_no: number; state: HoldState;
  missing: MissingItem[]; note_en: string; note_ar: string; original_snapshot: unknown; supplier_values: unknown[];
  regenerated: unknown | null; regenerated_at: string | null; pdf_bucket: string | null; pdf_path: string | null;
  approved_at: string | null; approved_by: string | null; released_at: string | null; superseded_at: string | null;
  owner_seat: typeof SEAT; opened_at: string; notified_at: string | null; notification_ids: number[] | null;
};
/** A delivery request: the sales engineer asks, customer_support sends (#614). */
export type NotificationRow = {
  type: string; kind: string; to_email: string | null; to_phone: string | null; to_role: 'supplier'; lead_id: number; inquiry_id: string; quote_id: string;
  channel: 'email' | 'whatsapp'; subject: string; body: string; status: 'queued'; requested_by: typeof SEAT; sender: 'customer_support';
};
export interface SpecRepo {
  quote(id: string): Promise<QuoteRow | null>;
  lines(quoteId: string): Promise<Line[]>;
  saveLineSpecs(quoteId: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]): Promise<void>;
  updateQuote(id: string, patch: Record<string, unknown>): Promise<void>;
  liveHold(quoteId: string): Promise<HoldRow | null>;
  insertHold(row: Omit<HoldRow, 'id'>): Promise<HoldRow>;
  updateHold(id: number, patch: Partial<HoldRow>): Promise<void>;
  /** Queue the delivery requests; returns their ids. */
  notify(rows: NotificationRow[]): Promise<number[]>;
  /** Ask customer_support's dispatchers to send what was just queued, now. */
  dispatch(): Promise<void>;
  log(counts: Record<string, unknown>, note: string): Promise<void>;
}
export type Supplier = { id: number; email: string | null; phone?: string | null; locale: string | null };
// read: what the supplier's quotation states, read by reasoning (_shared/reasoned_matching.ts readQuote) before
// the check; null under the model hold, and then only what he stated in keyed fields counts (the quote is held).
// checklist / reason: a trade with no catalogue entry asks its knowledge pack's required specs, judged by think()
// (reasoned_specs.ts); null under the hold, and then nothing is pre-filled.
export type Ctx = { category: string | null; requirements: Requirements; ref: string; multiOption?: boolean; now?: () => Date;
  read?: (q: QuoteRow, lines: Line[]) => Promise<QuoteReading | null>;
  checklist?: Attr[]; reason?: (lines: Line[], checklist: Attr[]) => Promise<Record<number, Record<string, string>> | null> };
const nowIso = (ctx: Ctx) => (ctx.now ? ctx.now() : new Date()).toISOString();
const langOf = (s: Supplier): 'en' | 'ar' => (String(s.locale || '').toLowerCase().startsWith('ar') ? 'ar' : 'en');

/** One notice as delivery requests on every channel the supplier has: email and WhatsApp. */
export function deliveryRows(s: Supplier, q: { id: string; inquiry_id: string }, type: string, n: { subject: string; body: string }): NotificationRow[] {
  const base = { type, kind: `${SEAT}_${type}`, to_role: 'supplier' as const, lead_id: s.id, inquiry_id: q.inquiry_id, quote_id: q.id, subject: n.subject, body: n.body, status: 'queued' as const, requested_by: SEAT, sender: 'customer_support' as const };
  const rows: NotificationRow[] = [];
  if (s.email) rows.push({ ...base, channel: 'email', to_email: s.email, to_phone: null });
  if (s.phone) rows.push({ ...base, channel: 'whatsapp', to_email: s.email, to_phone: s.phone });
  return rows;
}
async function deliver(repo: SpecRepo, rows: NotificationRow[]) {
  if (!rows.length) return [];
  const ids = await repo.notify(rows);
  await repo.dispatch();
  return ids;
}

async function persistSpecs(repo: SpecRepo, quoteId: string, a: Assessment, lines: Line[]) {
  const rows = a.lines.filter((r) => Object.keys(r.spec).length).filter((r) => {
    const l = lines.find((x) => x.line_no === r.line_no);
    return JSON.stringify(l?.spec ?? {}) !== JSON.stringify(r.spec);
  }).map((r) => ({ line_no: r.line_no, spec: r.spec, spec_source: r.source }));
  if (rows.length) await repo.saveLineSpecs(quoteId, rows);
}

/**
 * THE GATE. Run on every submission (form, upload, resubmission, each option on its own). A live
 * hold on the same quote is superseded first: a resubmission replaces the held quote and goes
 * through the same check. A held quote is left a draft, which every customer-facing read excludes,
 * and the supplier is told at once, on email and WhatsApp, through customer_support.
 */
export async function gate(repo: SpecRepo, quoteId: string, supplier: Supplier, ctx: Ctx) {
  const q = await repo.quote(quoteId); if (!q) throw new Error('quote not found: ' + quoteId);
  const stored = await repo.lines(quoteId);
  // READ BEFORE THE CHECK (23 Sep 2026): what reasoning finds in his own words is written in; under the hold
  // nothing is, and every required detail is asked of him.
  const reading = ctx.read ? await ctx.read(q, stored) : null;
  const applied = applyReading(stored, q.terms_spec, reading);
  if (reading) { q.terms_spec = applied.terms_spec; await repo.updateQuote(quoteId, { terms_spec: applied.terms_spec }); }
  const read = applied.lines;
  const lines = ctx.checklist?.length && ctx.reason && needsChecklist(ctx.category)
    ? withReasoned(read, await ctx.reason(read, ctx.checklist)) : read;
  const a = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements, checklist: ctx.checklist });
  await persistSpecs(repo, quoteId, a, stored);
  const at = nowIso(ctx);
  const live = await repo.liveHold(quoteId);
  let superseded: number | null = null;
  if (live) { await repo.updateHold(live.id, { state: 'superseded', superseded_at: at }); superseded = live.id; }
  if (!a.held) {
    if (superseded) await repo.log({ signal: 'spec_hold_superseded_clean', quote_id: quoteId, hold_id: superseded }, `Resubmitted quote ${quoteId} states every required detail; hold ${superseded} superseded, no new hold.`);
    return { held: false as const, hold_id: null, missing: [] as MissingItem[], superseded, assessment: a, notification_ids: [] as number[] };
  }
  const en = holdNotice(a, 'en', ctx.ref, ctx.multiOption ? optionLabel(q.option_no, 'en') : null);
  const ar = holdNotice(a, 'ar', ctx.ref, ctx.multiOption ? optionLabel(q.option_no, 'ar') : null);
  const hold = await repo.insertHold({
    quote_id: quoteId, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, submission_id: q.submission_id, option_no: q.option_no, state: 'open',
    // The checklist this hold was judged on travels with it: fill-in and approval read it back rather than
    // choosing again, so the rule a supplier answers is the rule he is released on.
    missing: a.missing, note_en: en.body, note_ar: ar.body,
    original_snapshot: { quote: q, lines, checklist: ctx.checklist?.map((x) => ({ code: x.code, label_en: x.en, label_ar: x.ar })) ?? null }, supplier_values: [],
    regenerated: null, regenerated_at: null, pdf_bucket: null, pdf_path: null, approved_at: null, approved_by: null, released_at: null, superseded_at: null,
    owner_seat: SEAT, opened_at: at, notified_at: null, notification_ids: null,
  });
  if (q.status !== 'draft') await repo.updateQuote(quoteId, { status: 'draft' });
  // Immediately (founder: "why 2 days? directly on spot"): same call, same instant, both channels.
  const ids = await deliver(repo, deliveryRows(supplier, q, 'quote_spec_hold', langOf(supplier) === 'ar' ? ar : en));
  await repo.updateHold(hold.id, { notified_at: at, notification_ids: ids });
  await repo.log({ signal: 'spec_hold_opened', quote_id: quoteId, hold_id: hold.id, missing: a.missing.length, delivery_requests: ids.length, option_no: q.option_no },
    `Held quote ${quoteId}: ${a.missing.length} required detail(s) missing — ${a.missing.map((m) => m.scope === 'line' ? `line ${m.line_no} ${m.attr}` : m.attr).join(', ')}. ${ids.length} delivery request(s) to customer_support (email and WhatsApp) queued and dispatched at once.`);
  return { held: true as const, hold_id: hold.id, missing: a.missing, superseded, assessment: a, notification_ids: ids };
}

/**
 * THE HOLD DESK ASKS EVERYTHING ITS RELEASE ASKS (stage-2 run 4, 13 Oct 2026). spec_approve's precheck runs the
 * quotation review (quote_review.ts), whose rule 7 wants a concrete validity; assessQuote never asks it, so the
 * form never showed it, validateTerm refused it as unknown_attribute, and a supplier who filled in every field
 * was answered still_missing [validity] with no way to supply it. The desk (spec_hold, spec_fill, spec_approve)
 * now asks it as one more quote-level term. The submission gate is unchanged: the review already asks it there.
 */
export function deskAssess(input: Parameters<typeof assessQuote>[0], validity: string | null | undefined): Assessment {
  const a = assessQuote(input);
  if (deliveryOf(String(validity ?? ''))) return a;
  return { ...a, held: true, missing: [...a.missing, termItem('validity')] };
}

/**
 * The quote-level details the form asks. "Is installation included?" is asked WITH its scope or timeline
 * (23 Sep 2026): since #893 nothing reads the scope out of the supplier's prose, so a "yes" alone came back
 * as a second hold asking for the detail (post-deploy smoke, "filling in the details regenerates the
 * quotation": still missing installation_detail). A supplier who answers "no" leaves it blank and fillIn
 * ignores a blank value, so it is never required of supply-only.
 */
export function termsAsked(missing: MissingItem[]): MissingItem[] {
  const terms = missing.filter((m) => m.scope === 'quote' && m.attr !== 'line_items');
  const i = terms.findIndex((m) => m.attr === 'installation_included');
  if (i >= 0 && !terms.some((m) => m.attr === 'installation_detail')) terms.splice(i + 1, 0, termItem('installation_detail'));
  return terms;
}

/** What the supplier's fill-in form shows: every missing detail, with the values already read beside it. */
export function formSchema(a: Assessment, _lines: Line[]) {
  return {
    lines: a.lines.filter((l) => l.material && l.defs.length).map((l) => ({
      line_no: l.line_no, description: l.description, trade: l.trade, trade_en: l.trade ? TRADES[l.trade].en : null, trade_ar: l.trade ? TRADES[l.trade].ar : null,
      fields: l.defs.map((x) => ({ attr: x.code, label_en: x.en, label_ar: x.ar, type: x.type, unit: x.unit ?? null, unit_ar: x.unit_ar ?? null, options: x.options ?? null, mandatory: x.mandatory, value: l.spec[x.code] ?? null, missing: l.missing.includes(x.code) })),
    })),
    terms: termsAsked(a.missing),
    needs_itemised_lines: a.missing.some((m) => m.attr === 'line_items'),
    values: a.terms,
  };
}

export type FillValues = { lines?: Record<string, Record<string, unknown>>; terms?: Record<string, unknown> };
export type Standardised = {
  contract: 'standardised_quotation'; version: 1; quote_id: string; option_no: number; category: string | null; trade: string; currency: 'AED';
  /** The price EXCLUDING VAT. No VAT amount, VAT treatment or TRN is ever on this record. */
  total: number; price_basis: 'ex_vat';
  lines: { line_no: number; description: string; qty: unknown; unit: unknown; unit_price: unknown; amount: unknown; trade: string | null; spec: { code: string; label_en: string; label_ar: string; value: string; unit: string | null; unit_ar: string | null; source: string }[] }[];
  terms: {
    delivery: string | null;
    /** The sentence the record shows. The document reads the two structured fields below, never this sentence. */
    installation: string | null;
    installation_included: boolean | null; installation_detail: string | null;
    warranty: string | null; validity: string | null; payment_terms: string | null; exclusions: string | null };
  prepared_by: typeof SEAT; prepared_at: string;
};

export function standardise(q: QuoteRow, lines: Line[], a: Assessment, ctx: Ctx): Standardised {
  return {
    contract: 'standardised_quotation', version: 1, quote_id: q.id, option_no: q.option_no, category: ctx.category, trade: a.trade, currency: 'AED',
    total: Number(q.price_ex_vat ?? q.quote_amount), price_basis: 'ex_vat',
    lines: a.lines.filter((l) => l.material).map((l) => {
      const src = lines.find((x) => x.line_no === l.line_no)!;
      return { line_no: l.line_no, description: safe(l.description) ?? '', qty: src.qty ?? null, unit: src.unit ?? null, unit_price: src.unit_price ?? null, amount: src.amount ?? null, trade: l.trade,
        spec: l.defs.filter((x) => l.spec[x.code]).map((x) => ({ code: x.code, label_en: x.en, label_ar: x.ar, value: safe(l.spec[x.code]) ?? '', unit: x.unit ?? null, unit_ar: x.unit_ar ?? null, source: l.source[x.code] })) };
    }),
    terms: {
      delivery: safe(a.terms.delivery.value),
      installation: a.terms.installation.applies ? (a.terms.installation.included === 'yes' ? `Included${a.terms.installation.detail ? ' — ' + safe(a.terms.installation.detail) : ''}` : 'Not included (supply only)') : null,
      installation_included: a.terms.installation.applies ? a.terms.installation.included === 'yes' : null,
      installation_detail: a.terms.installation.applies && a.terms.installation.included === 'yes' ? safe(a.terms.installation.detail) : null,
      warranty: a.terms.warranty.applies ? safe(`${a.terms.warranty.period} — ${a.terms.warranty.coverage}`) : safe(q.warranty),
      validity: safe(q.validity), payment_terms: safe(q.payment_terms), exclusions: safe(q.exclusions),
    },
    prepared_by: SEAT, prepared_at: nowIso(ctx),
  };
}

/**
 * The pdf_native body for a regenerated quotation: THE SAME builder as every other quotation
 * (_shared/quote_documents.ts quoteDocument), in the language asked for.
 *
 * 22 Sep 2026 (audit of every document we issue, finding 1 — CRITICAL). This used to return
 * { quote, quote_ar, lang: 'bi' }: a shape from an older renderer that pdf_native/render.ts never
 * reads (it draws `cover`, `blocks` or `body_html`). The regenerated quotation was therefore a blank
 * one-page "Document" with a letterhead, stored in quote-files and returned to the supplier as
 * pdf_url for approval. Prevented by pdf_native/every_document_we_issue.test.ts and
 * scripts/checks/every_pdf_we_issue_is_on_our_template.mjs (renders this body and asserts content).
 */
export function pdfBody(s: Standardised, args: { inquiry: InquiryRow; letter: string; lang: 'en' | 'ar'; arTexts?: ArTexts }) {
  return pdfDoc(s, args).body;
}
/** The whole quoteDocument result (body + the lines an Arabic page still needs translated by reasoning). */
export function pdfDoc(s: Standardised, args: { inquiry: InquiryRow; letter: string; lang: 'en' | 'ar'; arTexts?: ArTexts }) {
  // Installation arrives as the structured fields standardise() wrote (decision point
  // line_specs.workflow_installation: it used to be read back off our own sentence by its first word).
  // Warranty is still one sentence, split on the separator standardise() itself put there.
  const [wPeriod, ...wCov] = String(s.terms.warranty ?? '').split(' — ');
  const quote: DocQuote = {
    id: s.quote_id, quote_amount: s.total, price_ex_vat: s.total,
    lead_time: s.terms.delivery, validity: s.terms.validity, payment_terms: s.terms.payment_terms, exclusions: s.terms.exclusions,
    installation_applicable: s.terms.installation_included != null, installation_included: s.terms.installation_included,
    installation_scope: s.terms.installation_included ? s.terms.installation_detail : null,
    warranty: wPeriod || null, warranty_coverage: wCov.join(' — ') || null,
  };
  const items: Item[] = s.lines.map((l) => ({
    desc: l.description, qty: l.qty == null ? '' : String(l.qty), unit: l.unit == null ? '' : String(l.unit),
    unit_price: l.unit_price == null ? null : Number(l.unit_price), amount: l.amount == null ? null : Number(l.amount),
    specs: Object.fromEntries(l.spec.map((x) => [x.code, `${x.value}${x.unit ? ' ' + (args.lang === 'ar' ? x.unit_ar ?? x.unit : x.unit) : ''}`])),
  }));
  return quoteDocument({ quote, inquiry: { ...args.inquiry, summary: null }, items, letter: args.letter, lang: args.lang, arTexts: args.arTexts });
}

/** 'arabic_pending': an Arabic quotation whose lines are not all translated by reasoning yet (decision point
 * trade_glossary_ar). The quotation is NOT sent for approval without its PDF: the hold keeps state
 * 'awaiting_approval' (every live-hold reader stays correct) with regenerated.arabic_pending = true, no approval
 * notice goes out, approve() refuses it, and finishArabic() renders it and sends the notice when the Arabic exists. */
export type Render = (s: Standardised) => Promise<{ bucket: string; path: string } | 'arabic_pending' | null>;
/** True while a regenerated quotation waits for its reasoned Arabic. */
export const arabicPending = (h: HoldRow | null | undefined) => !!(h?.regenerated && (h.regenerated as { arabic_pending?: boolean }).arabic_pending === true);

/** WAY OUT (a): the supplier fills in what was missing on the portal. */
export async function fillIn(repo: SpecRepo, quoteId: string, supplier: Supplier, values: FillValues, ctx: Ctx, render?: Render) {
  const q = await repo.quote(quoteId);
  if (!q || Number(q.supplier_id) !== Number(supplier.id)) return { ok: false as const, code: 'not_found' as const };
  const hold = await repo.liveHold(quoteId);
  if (!hold) return { ok: false as const, code: 'no_hold' as const };
  const lines = await repo.lines(quoteId);
  const a0 = deskAssess({ category: ctx.category, lines, terms: q, requirements: ctx.requirements, checklist: ctx.checklist }, q.validity);
  const errors: FillError[] = [];
  const next = lines.map((l) => ({ ...l, spec: { ...(l.spec ?? {}) }, spec_source: { ...(l.spec_source ?? {}) } }));
  for (const [ln, vals] of Object.entries(values.lines ?? {})) {
    const lr = a0.lines.find((x) => x.line_no === Number(ln)); const l = next.find((x) => x.line_no === Number(ln));
    for (const [attr, raw] of Object.entries(vals ?? {})) {
      if (raw == null || String(raw).trim() === '') continue;
      const def = lr?.defs.find((x) => x.code === attr);
      if (!def || !l) { errors.push({ scope: 'line', line_no: Number(ln), attr, code: 'unknown_attribute' }); continue; }
      const v = validateLineValue(def, raw);
      if (!v.ok) { errors.push({ scope: 'line', line_no: Number(ln), attr, code: v.code }); continue; }
      l.spec[attr] = v.value; l.spec_source[attr] = 'supplier_portal';
    }
  }
  const t = values.terms ?? {}; const tv: Record<string, string> = {};
  for (const [attr, raw] of Object.entries(t)) {
    if (raw == null || String(raw).trim() === '') continue;
    const v = validateTerm(attr, raw);
    if (!v.ok) errors.push({ scope: 'quote', line_no: null, attr, code: v.code }); else tv[attr] = v.value;
  }
  if (errors.length) return { ok: false as const, code: 'invalid_values' as const, errors };

  const ts: TermsSpec = { ...(q.terms_spec ?? {}) };
  const patch: Record<string, unknown> = {};
  if (tv.validity) patch.validity = tv.validity;
  if (tv.delivery) { ts.delivery = { value: tv.delivery, source: 'supplier_portal' }; patch.lead_time = tv.delivery; }
  if (tv.installation_included || tv.installation_detail) {
    const included = (tv.installation_included ?? ts.installation?.included ?? a0.terms.installation.included ?? 'yes') as 'yes' | 'no';
    ts.installation = { included, detail: included === 'yes' ? (tv.installation_detail ?? ts.installation?.detail ?? a0.terms.installation.detail ?? null) : null, source: 'supplier_portal' };
  }
  if (tv.warranty_period || tv.warranty_coverage) {
    const period = tv.warranty_period ?? ts.warranty?.period ?? a0.terms.warranty.period ?? '';
    const coverage = tv.warranty_coverage ?? ts.warranty?.coverage ?? a0.terms.warranty.coverage ?? '';
    ts.warranty = { period, coverage, source: 'supplier_portal' };
    if (period && coverage) patch.warranty = `${period} — ${coverage}`;
  }
  for (const [attr, v] of Object.entries(tv)) if (attr.startsWith('component:')) ts.components = { ...(ts.components ?? {}), [attr.slice('component:'.length)]: { value: v, source: 'supplier_portal' } };
  if (tv.price_ex_vat) { const n = Number(tv.price_ex_vat); patch.price_ex_vat = n; patch.quote_amount = n; patch.vat_treatment = 'confirmed_on_portal'; }
  patch.terms_spec = ts;
  const changed = next.filter((l, i) => JSON.stringify(l.spec) !== JSON.stringify(lines[i].spec ?? {})).map((l) => ({ line_no: l.line_no, spec: l.spec, spec_source: l.spec_source as Record<string, string> }));
  if (changed.length) await repo.saveLineSpecs(quoteId, changed);
  await repo.updateQuote(quoteId, patch);
  const history = [...(hold.supplier_values ?? []), { at: nowIso(ctx), by: 'supplier', values }];

  const q1 = { ...q, ...patch } as QuoteRow;
  const a1 = deskAssess({ category: ctx.category, lines: next, terms: q1, requirements: ctx.requirements, checklist: ctx.checklist }, q1.validity);
  if (a1.held) {
    await repo.updateHold(hold.id, { missing: a1.missing, state: 'open', supplier_values: history });
    return { ok: true as const, complete: false as const, missing: a1.missing, schema: formSchema(a1, next) };
  }
  // Complete: the sales engineer regenerates the standardised quotation and asks the supplier to approve it.
  const record = standardise(q1, next, a1, ctx);
  let rendered: Awaited<ReturnType<Render>> = null;
  try { rendered = render ? await render(record) : null; } catch (_e) { rendered = null; }
  if (rendered === 'arabic_pending') {
    await repo.updateHold(hold.id, { state: 'awaiting_approval', missing: [], supplier_values: history, regenerated: { ...record, arabic_pending: true }, regenerated_at: record.prepared_at, pdf_bucket: null, pdf_path: null });
    await repo.log({ signal: 'spec_hold_arabic_pending', quote_id: quoteId, hold_id: hold.id }, `Supplier completed every required detail on quote ${quoteId}; the Arabic quotation waits for its reasoned translation, so no approval request was sent without its PDF.`);
    return { ok: true as const, complete: true as const, regenerated: record, pdf: null, arabic_pending: true as const };
  }
  const pdf = rendered;
  await repo.updateHold(hold.id, { state: 'awaiting_approval', missing: [], supplier_values: history, regenerated: record, regenerated_at: record.prepared_at, pdf_bucket: pdf?.bucket ?? null, pdf_path: pdf?.path ?? null });
  const ids = await deliver(repo, deliveryRows(supplier, q, 'quote_spec_regenerated', approvalNotice(langOf(supplier), ctx.ref)));
  await repo.log({ signal: 'spec_hold_regenerated', quote_id: quoteId, hold_id: hold.id, pdf: pdf ? 1 : 0, delivery_requests: ids.length }, `Supplier completed every required detail on quote ${quoteId}; the standardised quotation was regenerated${pdf ? ' with its PDF' : ' (PDF not produced)'} and the approval request went to customer_support for email and WhatsApp.`);
  return { ok: true as const, complete: true as const, regenerated: record, pdf };
}

/** The replay's effect for a regenerated quotation that waited for its Arabic: render it now (the reasoned Arabic
 * is in the cache), then send the approval request exactly as fillIn would have. Still missing → stays pending. */
export async function finishArabic(repo: SpecRepo, quoteId: string, supplier: Supplier, ctx: Ctx, render: Render) {
  const q = await repo.quote(quoteId);
  if (!q || Number(q.supplier_id) !== Number(supplier.id)) return { ok: false as const, code: 'not_found' as const };
  const hold = await repo.liveHold(quoteId);
  if (!hold || hold.state !== 'awaiting_approval' || !arabicPending(hold)) return { ok: false as const, code: 'not_pending' as const };
  const { arabic_pending: _p, ...record } = hold.regenerated as Standardised & { arabic_pending?: boolean };
  let pdf: Awaited<ReturnType<Render>> = null;
  try { pdf = await render(record as Standardised); } catch (_e) { pdf = null; }
  if (!pdf || pdf === 'arabic_pending') return { ok: false as const, code: 'still_pending' as const };
  await repo.updateHold(hold.id, { regenerated: record, pdf_bucket: pdf.bucket, pdf_path: pdf.path });
  const ids = await deliver(repo, deliveryRows(supplier, q, 'quote_spec_regenerated', approvalNotice(langOf(supplier), ctx.ref)));
  await repo.log({ signal: 'spec_hold_regenerated', quote_id: quoteId, hold_id: hold.id, pdf: 1, delivery_requests: ids.length }, `The Arabic quotation for quote ${quoteId} was rendered once its reasoned translation existed, and the approval request went to customer_support.`);
  return { ok: true as const, pdf };
}

/**
 * The supplier confirms the regenerated quotation is correct. Only then is the hold released and
 * the quote offered to the commercial accept rule (`accept`, supplied by the caller), which decides
 * whether it goes to the customer and is counted in the comparison.
 */
// `precheck` (22 Sep 2026, sales_engineer — re-review of #854). A caller may have a further reason not
// to release, and it MUST be asked before the hold is marked released, not inside `accept`. The hold is
// the supplier's only way back: once it is released, liveHold() — which reads only 'open' and
// 'awaiting_approval' — stops finding it, so spec_fill and spec_approve both answer
// not_awaiting_approval and the desk is shut with the quote unsent and nothing named to fix. A
// precheck that returns items puts the hold back to 'open' carrying them, exactly as `a.held` does
// above, so the supplier sees what to do and can fill it in. Returning null means release.
export async function approve(repo: SpecRepo, quoteId: string, supplier: Supplier, actorEmail: string, confirm: unknown, ctx: Ctx, accept: (q: QuoteRow) => Promise<boolean>, precheck?: (q: QuoteRow) => Promise<{ missing: MissingItem[]; issues?: unknown[] } | null>) {
  const q = await repo.quote(quoteId);
  if (!q || Number(q.supplier_id) !== Number(supplier.id)) return { ok: false as const, code: 'not_found' as const };
  const hold = await repo.liveHold(quoteId);
  if (!hold || hold.state !== 'awaiting_approval') return { ok: false as const, code: 'not_awaiting_approval' as const };
  // Nothing is approved that the supplier has not been shown: the Arabic quotation is still being translated.
  if (arabicPending(hold)) return { ok: false as const, code: 'arabic_pending' as const };
  if (confirm !== true) return { ok: false as const, code: 'confirm_required' as const };
  const lines = await repo.lines(quoteId);
  const a = deskAssess({ category: ctx.category, lines, terms: q, requirements: ctx.requirements, checklist: ctx.checklist }, q.validity);
  if (a.held) { await repo.updateHold(hold.id, { state: 'open', missing: a.missing }); return { ok: false as const, code: 'still_missing' as const, missing: a.missing }; }
  if (precheck) {
    const pre = await precheck(q);
    if (pre) {
      await repo.updateHold(hold.id, { state: 'open', missing: pre.missing });
      return { ok: false as const, code: 'still_missing' as const, missing: pre.missing, review_issues: pre.issues ?? null };
    }
  }
  const at = nowIso(ctx);
  await repo.updateHold(hold.id, { state: 'released', approved_at: at, approved_by: actorEmail, released_at: at });
  const live = await accept(q);
  const ids = await deliver(repo, deliveryRows(supplier, q, 'quote_spec_released', releasedNotice(langOf(supplier), ctx.ref, live)));
  await repo.log({ signal: 'spec_hold_released', quote_id: quoteId, hold_id: hold.id, sent_to_customer: live ? 1 : 0, delivery_requests: ids.length }, `Supplier ${actorEmail} approved the regenerated quotation ${quoteId}; the hold is released${live ? ' and the quote is with the customer' : ', and the quote still waits on its commercial terms'}.`);
  return { ok: true as const, released: true as const, live };
}

// ---------------------------------------------------------------------------------------------
// The production repository: the service-role client. Every row it writes names the seat.
// ---------------------------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
export function supabaseRepo(admin: any, opts: { dispatch?: () => Promise<void> } = {}): SpecRepo {
  // deno-lint-ignore no-explicit-any
  const must = (r: { data?: any; error?: { message: string } | null }) => { if (r.error) throw new Error(r.error.message); return r; };
  return {
    async quote(id) { const { data } = must(await admin.from('quotes').select('id,inquiry_id,supplier_id,status,option_no,submission_id,quote_amount,price_ex_vat,vat_treatment,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,notes,terms_spec').eq('id', id).maybeSingle()); return data ?? null; },
    async lines(quoteId) { const { data } = must(await admin.from('quote_items').select('line_no,description,brand,model,specification,qty,unit,unit_price,labour,install,amount,notes,spec,spec_source').eq('quote_id', quoteId).order('line_no', { ascending: true })); return (data ?? []).map((r: Line) => ({ ...r, description: String(r.description ?? '') })); },
    async saveLineSpecs(quoteId, rows) { for (const r of rows) must(await admin.from('quote_items').update({ spec: r.spec, spec_source: r.spec_source }).eq('quote_id', quoteId).eq('line_no', r.line_no)); },
    async updateQuote(id, patch) { must(await admin.from('quotes').update(patch).eq('id', id)); },
    async liveHold(quoteId) { const { data } = must(await admin.from('quote_spec_hold').select('*').eq('quote_id', quoteId).in('state', ['open', 'awaiting_approval']).maybeSingle()); return data ?? null; },
    async insertHold(row) { const { data } = must(await admin.from('quote_spec_hold').insert(row).select('*').single()); return data; },
    async updateHold(id, patch) { must(await admin.from('quote_spec_hold').update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id)); },
    async notify(rows) {
      const ids: number[] = [];
      // Email first. trg_wa_fanout adds a WhatsApp twin for a supplier who opted in, in the same
      // statement; the explicit WhatsApp row is queued only when no twin was made, so a supplier is
      // never messaged twice.
      // Through customer_support's door (_shared/deliver.ts): every notice here comes back to the sales
      // engineer with what became of it. A row the door did not queue is an error, as the insert was.
      const queued = async (r: Record<string, unknown>) => { const { data, error } = await requestDelivery(admin, r); if (error || data[0]?.notification_id == null) throw new Error(error?.message || 'not queued'); return Number(data[0].notification_id); };
      for (const r of rows.filter((x) => x.channel === 'email')) ids.push(await queued(r));
      for (const r of rows.filter((x) => x.channel === 'whatsapp')) {
        const { data: twin } = must(await admin.from('notifications').select('id').eq('channel', 'whatsapp').eq('lead_id', r.lead_id).eq('type', r.type).eq('quote_id', r.quote_id).gte('created_at', new Date(Date.now() - 60e3).toISOString()).limit(1));
        if (twin?.length) { ids.push(twin[0].id); continue; }
        ids.push(await queued(r));
      }
      return ids;
    },
    async dispatch() { try { if (opts.dispatch) await opts.dispatch(); } catch (_e) { /* the scheduled outbox still sends; the kick only removes the wait */ } },
    async log(counts, note) { try { await admin.from('agent_runs').insert({ agent: SEAT, status: 'ok', started_at: new Date().toISOString(), finished_at: new Date().toISOString(), counts, note: note.slice(0, 500) }); } catch (_e) { /* the trail never blocks the desk */ } },
  };
}

export { lineText };
