// line_specs/workflow.ts — the sales engineer's hold desk: hold, notify, fill in, regenerate,
// approve, release. Every record it writes is owned by and attributed to `sales_engineer` (founder,
// 14 Sep 2026: "its always the sales agent. no other agent is involved in customer or supplier
// portal").
//
// The state of one hold episode lives in public.quote_spec_hold, one row per episode, and is the
// audit trail the founder asked for: the ORIGINAL submission (original_snapshot), every set of values
// the supplier entered (supplier_values, appended with a timestamp), the REGENERATED standardised
// quotation (regenerated + its PDF), and who approved it and when (approved_by / approved_at).
//
//   open ──fill──▶ open (still missing) ──fill──▶ awaiting_approval ──approve──▶ released
//     └────────────── resubmit (a new revised quote) ──▶ superseded, and the new quote is gated again
//
// Written against a small repository interface so the workflow test runs entirely in memory: no
// database, no network, and therefore no way to reach a real supplier.
import { assessQuote, holdNotice, SEAT, SEAT_LABEL, validateLineValue, validateTerm, type Assessment, type FillError, type Line, type MissingItem, type Requirements, type Terms, type TermsSpec } from './assess.ts';
import { attrsForLine, TRADES } from './model.ts';
import { lineText } from './assess.ts';
import { optionLabel } from './options.ts';
import { maskIdentityNumbers } from '../identity_numbers.ts';

export type QuoteRow = Terms & {
  id: string; inquiry_id: string; supplier_id: number; status: string; option_no: number; submission_id: string | null;
  quote_amount: number; validity?: string | null; payment_terms?: string | null; vat_treatment?: string | null;
};
// Customer-bound text never carries a TRN or a licence number (identity_numbers.ts).
const safe = (v: unknown) => (v == null ? null : maskIdentityNumbers(v).replace(/\s{2,}/g, ' ').trim() || null);
export type HoldState = 'open' | 'awaiting_approval' | 'released' | 'superseded';
export type HoldRow = {
  id: number; quote_id: string; inquiry_id: string; supplier_id: number; submission_id: string | null; option_no: number; state: HoldState;
  missing: MissingItem[]; note_en: string; note_ar: string; original_snapshot: unknown; supplier_values: unknown[];
  regenerated: unknown | null; regenerated_at: string | null; pdf_bucket: string | null; pdf_path: string | null;
  approved_at: string | null; approved_by: string | null; released_at: string | null; superseded_at: string | null;
  owner_seat: typeof SEAT; opened_at: string; notified_at: string | null; notification_ids: number[] | null;
};
export type NotificationRow = { type: string; kind: string; to_email: string; to_role: 'supplier'; lead_id: number; inquiry_id: string; quote_id: string; channel: 'email'; subject: string; body: string; status: 'queued' };
export interface SpecRepo {
  quote(id: string): Promise<QuoteRow | null>;
  lines(quoteId: string): Promise<Line[]>;
  saveLineSpecs(quoteId: string, rows: { line_no: number; spec: Record<string, string>; spec_source: Record<string, string> }[]): Promise<void>;
  updateQuote(id: string, patch: Record<string, unknown>): Promise<void>;
  liveHold(quoteId: string): Promise<HoldRow | null>;
  insertHold(row: Omit<HoldRow, 'id'>): Promise<HoldRow>;
  updateHold(id: number, patch: Partial<HoldRow>): Promise<void>;
  notify(rows: NotificationRow[]): Promise<number[]>;
  log(counts: Record<string, unknown>, note: string): Promise<void>;
}
export type Supplier = { id: number; email: string | null; locale: string | null };
export type Ctx = { category: string | null; requirements: Requirements; ref: string; multiOption?: boolean; now?: () => Date };
const nowIso = (ctx: Ctx) => (ctx.now ? ctx.now() : new Date()).toISOString();
const langOf = (s: Supplier): 'en' | 'ar' => (String(s.locale || '').toLowerCase().startsWith('ar') ? 'ar' : 'en');

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
 * through the same check. Returns whether the quote is held; a held quote is left a draft, which
 * every customer-facing read already excludes.
 */
export async function gate(repo: SpecRepo, quoteId: string, supplier: Supplier, ctx: Ctx) {
  const q = await repo.quote(quoteId); if (!q) throw new Error('quote not found: ' + quoteId);
  const lines = await repo.lines(quoteId);
  const a = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements });
  await persistSpecs(repo, quoteId, a, lines);
  const live = await repo.liveHold(quoteId);
  let superseded: number | null = null;
  if (live) { await repo.updateHold(live.id, { state: 'superseded', superseded_at: nowIso(ctx) }); superseded = live.id; }
  if (!a.held) {
    if (superseded) await repo.log({ signal: 'spec_hold_superseded_clean', quote_id: quoteId, hold_id: superseded }, `Resubmitted quote ${quoteId} states every required detail; hold ${superseded} superseded, no new hold.`);
    return { held: false as const, hold_id: null, missing: [] as MissingItem[], superseded, assessment: a };
  }
  const label = ctx.multiOption ? optionLabel(q.option_no, langOf(supplier)) : null;
  const en = holdNotice(a, 'en', ctx.ref, ctx.multiOption ? optionLabel(q.option_no, 'en') : null);
  const ar = holdNotice(a, 'ar', ctx.ref, ctx.multiOption ? optionLabel(q.option_no, 'ar') : null);
  const hold = await repo.insertHold({
    quote_id: quoteId, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, submission_id: q.submission_id, option_no: q.option_no, state: 'open',
    missing: a.missing, note_en: en.body, note_ar: ar.body, original_snapshot: { quote: q, lines }, supplier_values: [],
    regenerated: null, regenerated_at: null, pdf_bucket: null, pdf_path: null, approved_at: null, approved_by: null, released_at: null, superseded_at: null,
    owner_seat: SEAT, opened_at: nowIso(ctx), notified_at: null, notification_ids: null,
  });
  if (q.status !== 'draft') await repo.updateQuote(quoteId, { status: 'draft' });
  let ids: number[] = [];
  if (supplier.email) {
    const n = langOf(supplier) === 'ar' ? ar : en;
    ids = await repo.notify([{ type: 'quote_spec_hold', kind: 'sales_engineer_spec_hold', to_email: supplier.email, to_role: 'supplier', lead_id: supplier.id, inquiry_id: q.inquiry_id, quote_id: quoteId, channel: 'email', subject: n.subject, body: n.body, status: 'queued' }]);
    await repo.updateHold(hold.id, { notified_at: nowIso(ctx), notification_ids: ids });
  }
  await repo.log({ signal: 'spec_hold_opened', quote_id: quoteId, hold_id: hold.id, missing: a.missing.length, notified: ids.length, option_no: q.option_no },
    `Held quote ${quoteId}${label ? ' (' + label + ')' : ''}: ${a.missing.length} required detail(s) missing — ${a.missing.map((m) => m.scope === 'line' ? `line ${m.line_no} ${m.attr}` : m.attr).join(', ')}. Supplier notified: ${ids.length ? 'yes' : 'no e-mail on file'}.`);
  return { held: true as const, hold_id: hold.id, missing: a.missing, superseded, assessment: a };
}

/** What the supplier's fill-in form shows: every missing detail, with the values already read beside it. */
export function formSchema(a: Assessment, lines: Line[]) {
  return {
    lines: a.lines.filter((l) => l.material && l.trade).map((l) => {
      const src = lines.find((x) => x.line_no === l.line_no)!;
      const attrs = attrsForLine(l.trade!, lineText(src));
      return { line_no: l.line_no, description: l.description, trade: l.trade, trade_en: TRADES[l.trade!].en, trade_ar: TRADES[l.trade!].ar,
        fields: attrs.map((x) => ({ attr: x.code, label_en: x.en, label_ar: x.ar, type: x.type, unit: x.unit ?? null, unit_ar: x.unit_ar ?? null, options: x.options ?? null, mandatory: x.mandatory, value: l.spec[x.code] ?? null, missing: l.missing.includes(x.code) })) };
    }).filter((l) => l.fields.length),
    terms: a.missing.filter((m) => m.scope === 'quote' && m.attr !== 'line_items'),
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
  terms: { delivery: string | null; installation: string | null; warranty: string | null; validity: string | null; payment_terms: string | null; exclusions: string | null };
  prepared_by: typeof SEAT; prepared_at: string;
};

export function standardise(q: QuoteRow, lines: Line[], a: Assessment, ctx: Ctx): Standardised {
  return {
    contract: 'standardised_quotation', version: 1, quote_id: q.id, option_no: q.option_no, category: ctx.category, trade: a.trade, currency: 'AED',
    total: Number(q.price_ex_vat ?? q.quote_amount), price_basis: 'ex_vat',
    lines: a.lines.filter((l) => l.material).map((l) => {
      const src = lines.find((x) => x.line_no === l.line_no)!;
      const attrs = l.trade ? TRADES[l.trade].attrs : [];
      return { line_no: l.line_no, description: safe(l.description) ?? '', qty: src.qty ?? null, unit: src.unit ?? null, unit_price: src.unit_price ?? null, amount: src.amount ?? null, trade: l.trade,
        spec: attrs.filter((x) => l.spec[x.code]).map((x) => ({ code: x.code, label_en: x.en, label_ar: x.ar, value: safe(l.spec[x.code]) ?? '', unit: x.unit ?? null, unit_ar: x.unit_ar ?? null, source: l.source[x.code] })) };
    }),
    terms: {
      delivery: safe(a.terms.delivery.value),
      installation: a.terms.installation.applies ? (a.terms.installation.included === 'yes' ? `Included${a.terms.installation.detail ? ' — ' + safe(a.terms.installation.detail) : ''}` : 'Not included (supply only)') : null,
      warranty: a.terms.warranty.applies ? safe(`${a.terms.warranty.period} — ${a.terms.warranty.coverage}`) : safe(q.warranty),
      validity: safe(q.validity), payment_terms: safe(q.payment_terms), exclusions: safe(q.exclusions),
    },
    prepared_by: SEAT, prepared_at: nowIso(ctx),
  };
}

/** The body pdf_native renders for a regenerated quotation, both languages. The design is pdf_native's. */
export function pdfBody(s: Standardised, supplierLabel: string) {
  const specLine = (l: Standardised['lines'][number], ar: boolean) => l.spec.map((x) => `${ar ? x.label_ar : x.label_en}: ${x.value}${x.unit ? ' ' + (ar ? x.unit_ar ?? x.unit : x.unit) : ''}`).join(' · ');
  const q = (ar: boolean) => ({
    supplier_label: supplierLabel, job_category: s.category, total: s.total,
    items: s.lines.map((l) => ({ desc: `${l.description}${l.spec.length ? ' — ' + specLine(l, ar) : ''}`, qty: l.qty ?? '', unit: l.unit ?? '' })),
    lead_time: s.terms.delivery, validity: s.terms.validity, warranty: s.terms.warranty, payment_terms: s.terms.payment_terms, exclusions: s.terms.exclusions,
    notes: s.terms.installation ? (ar ? 'التركيب: ' : 'Installation: ') + s.terms.installation : null,
    source_note: ar ? `أعدّه ${SEAT_LABEL.ar} من عرض المورّد والتفاصيل التي أكّدها المورّد.` : `Regenerated by the ${SEAT_LABEL.en} from the supplier's quote and the details the supplier confirmed.`,
  });
  return { quote: q(false), quote_ar: q(true), lang: 'bi' as const, options: { letterhead: true } };
}

export type Render = (s: Standardised) => Promise<{ bucket: string; path: string } | null>;

/** WAY OUT (a): the supplier fills in what was missing on the portal. */
export async function fillIn(repo: SpecRepo, quoteId: string, supplierId: number, values: FillValues, ctx: Ctx, render?: Render) {
  const q = await repo.quote(quoteId);
  if (!q || Number(q.supplier_id) !== Number(supplierId)) return { ok: false as const, code: 'not_found' as const };
  const hold = await repo.liveHold(quoteId);
  if (!hold) return { ok: false as const, code: 'no_hold' as const };
  const lines = await repo.lines(quoteId);
  const a0 = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements });
  const errors: FillError[] = [];
  const next = lines.map((l) => ({ ...l, spec: { ...(l.spec ?? {}) }, spec_source: { ...(l.spec_source ?? {}) } }));
  for (const [ln, vals] of Object.entries(values.lines ?? {})) {
    const lr = a0.lines.find((x) => x.line_no === Number(ln)); const l = next.find((x) => x.line_no === Number(ln));
    for (const [attr, raw] of Object.entries(vals ?? {})) {
      if (raw == null || String(raw).trim() === '') continue;
      const def = lr?.trade && l ? attrsForLine(lr.trade, lineText(l)).find((x) => x.code === attr) : undefined;
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
  if (tv.price_ex_vat) { const n = Number(tv.price_ex_vat); patch.price_ex_vat = n; patch.quote_amount = n; patch.vat_treatment = 'confirmed_on_portal'; }
  patch.terms_spec = ts;
  const changed = next.filter((l, i) => JSON.stringify(l.spec) !== JSON.stringify(lines[i].spec ?? {})).map((l) => ({ line_no: l.line_no, spec: l.spec, spec_source: l.spec_source as Record<string, string> }));
  if (changed.length) await repo.saveLineSpecs(quoteId, changed);
  await repo.updateQuote(quoteId, patch);
  const history = [...(hold.supplier_values ?? []), { at: nowIso(ctx), by: 'supplier', values }];

  const q1 = { ...q, ...patch } as QuoteRow;
  const a1 = assessQuote({ category: ctx.category, lines: next, terms: q1, requirements: ctx.requirements });
  if (a1.held) {
    await repo.updateHold(hold.id, { missing: a1.missing, state: 'open', supplier_values: history });
    return { ok: true as const, complete: false as const, missing: a1.missing, schema: formSchema(a1, next) };
  }
  // Complete: the sales engineer regenerates the standardised quotation and asks the supplier to approve it.
  const record = standardise(q1, next, a1, ctx);
  let pdf: { bucket: string; path: string } | null = null;
  try { pdf = render ? await render(record) : null; } catch (_e) { pdf = null; }
  await repo.updateHold(hold.id, { state: 'awaiting_approval', missing: [], supplier_values: history, regenerated: record, regenerated_at: record.prepared_at, pdf_bucket: pdf?.bucket ?? null, pdf_path: pdf?.path ?? null });
  await repo.log({ signal: 'spec_hold_regenerated', quote_id: quoteId, hold_id: hold.id, pdf: pdf ? 1 : 0 }, `Supplier completed every required detail on quote ${quoteId}; the standardised quotation was regenerated${pdf ? ' with its PDF' : ' (PDF not produced)'} and is awaiting the supplier's approval.`);
  return { ok: true as const, complete: true as const, regenerated: record, pdf };
}

/**
 * The supplier confirms the regenerated quotation is correct. Only then is the hold released and
 * the quote offered to the commercial accept rule (`accept`, supplied by the caller), which decides
 * whether it goes to the customer and is counted in the comparison.
 */
export async function approve(repo: SpecRepo, quoteId: string, supplierId: number, actorEmail: string, confirm: unknown, ctx: Ctx, accept: (q: QuoteRow) => Promise<boolean>) {
  const q = await repo.quote(quoteId);
  if (!q || Number(q.supplier_id) !== Number(supplierId)) return { ok: false as const, code: 'not_found' as const };
  const hold = await repo.liveHold(quoteId);
  if (!hold || hold.state !== 'awaiting_approval') return { ok: false as const, code: 'not_awaiting_approval' as const };
  if (confirm !== true) return { ok: false as const, code: 'confirm_required' as const };
  const lines = await repo.lines(quoteId);
  const a = assessQuote({ category: ctx.category, lines, terms: q, requirements: ctx.requirements });
  if (a.held) { await repo.updateHold(hold.id, { state: 'open', missing: a.missing }); return { ok: false as const, code: 'still_missing' as const, missing: a.missing }; }
  const at = nowIso(ctx);
  await repo.updateHold(hold.id, { state: 'released', approved_at: at, approved_by: actorEmail, released_at: at });
  const live = await accept(q);
  await repo.log({ signal: 'spec_hold_released', quote_id: quoteId, hold_id: hold.id, sent_to_customer: live ? 1 : 0 }, `Supplier ${actorEmail} approved the regenerated quotation ${quoteId}; the hold is released${live ? ' and the quote is with the customer' : ', and the quote still waits on its commercial terms'}.`);
  return { ok: true as const, released: true as const, live };
}

// ---------------------------------------------------------------------------------------------
// The production repository: the service-role client. Every row it writes names the seat.
// ---------------------------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
export function supabaseRepo(admin: any): SpecRepo {
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
    async notify(rows) { const { data } = must(await admin.from('notifications').insert(rows).select('id')); return (data ?? []).map((r: { id: number }) => r.id); },
    async log(counts, note) { try { await admin.from('agent_runs').insert({ agent: SEAT, status: 'ok', started_at: new Date().toISOString(), finished_at: new Date().toISOString(), counts, note: note.slice(0, 500) }); } catch (_e) { /* the trail never blocks the desk */ } },
  };
}
