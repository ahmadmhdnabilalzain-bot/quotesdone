// inquiry_trades — AN INQUIRY IS PLACED IN THE WHOLE TAXONOMY, AND ITS TRADE'S PACKS DRIVE THE QUESTIONS (10 Nov 2026,
// sales_engineer; founder ledger 1586: "a general procurement system for EVERY trade in the UAE except food and beverage ...
// handled like an expert technical salesperson in that field, including location-specific rules").
//
// MEASURED (production, 10 Nov 2026): public.taxonomy_trade holds 223 active trades in 12 groups with 1,103 services, and
// public.trade_spec_checklist covers all 223 (305 checklists). But the request chat could only place an inquiry among the 56
// category_specs slugs, and public.intake_trade_taxonomy maps 32 of them to 25 of the 223 trades: a bus rental, a packaging
// order, an escalator or a scaffolding hire had no trade of its own, so no supplier of that trade could be reached and no
// question of that trade was asked. taxonomy_trade.authority_required names an authority for 3 trades (electrical: the
// electricity utility; fire_fighting: Civil Defence; security_systems: SIRA); every trade's verified pack carries a
// "UAE standards, authorities and approvals" entry (sales_knowledge, kind:standard, runtime_index_eligible).
//
// WHAT LIVES HERE:
//   * taxonomyOf (cached): every active trade, for the prompt that places an inquiry (taxonomyBlock, grouped codes);
//   * tradeContext: for the trades a conversation is placed in, their services (the keys a supplier ticks and matching
//     gates on), their spec checklists (what an exact quote must state, so what the buyer is asked), their authority and
//     their verified approvals entry (the location rules), each read with one bounded query, null when unreadable;
//   * tradeBlock: that context as text for the model; checklistFields: a checklist the request chat's slot machinery can
//     run for a trade no category_specs slug covers (the slugs stay as a compatibility input, never the boundary);
//   * validCodes / validServiceKeys: what the model named, kept only when it exists (a code is never guessed).
//   * THE BLOCKING SPECS (10 Nov 2026, founder ledger 1587: "the interview happens ONCE ... complete enough that every
//     supplier can quote without asking for a missing detail"): each checklist row carries the pack's spec_guide (why a spec
//     is needed to price, the UAE options, what to ask next), its blocking codes and its site-visit condition
//     (scripts/sql/a_trades_blocking_specs_and_their_guide_reach_the_interview.sql). activeChecklists picks, per placed
//     trade, the checklist(s) the job is (the model names them in "checklist_topics"; else the pack's first); packFields
//     makes every blocking spec of every placed trade REQUIRED and first, whatever the slug; readinessOf is THE RULE: a
//     request is not ready while a blocking spec of its trades has neither an answer nor an explicit "customer does not
//     know: supplier to advise", and it carries each site-visit condition into the brief as a known condition.
//     BEFORE: a trade with no slug had its first CHECKLIST_REQUIRED (6) specs required and every other trade none of its
//     pack's specs. A trade whose rows carry no blocking list yet (the loader has not run) keeps that earlier rule, so a
//     half-loaded table is never read as "nothing blocks".
// The trade is chosen by the model's reading of the whole conversation (ruling 890); nothing here reads the customer's words.
// prevented by: supabase/functions/_shared/inquiry_trades.test.ts (a spread across all twelve groups) and
//   supabase/functions/inquiry_intake/a_request_is_ready_only_when_every_blocking_spec_is_answered.test.ts
import { COMPOSITE, tradeOfCategory } from './line_specs/model.ts';
import { SAME_AS } from './line_specs/taxonomy_trades.ts';
import { plainOf } from './customer_questions.ts';
// deno-lint-ignore no-explicit-any
type Admin = any;

export interface TaxTrade { code: string; label: string; label_ar?: string | null; group_code: string | null; authority_required?: string[] | null }
export interface TradeService { trade_code: string; code: string; label_en: string; label_ar?: string | null }
export interface SpecItem { code: string; label_en: string }
/** One row of a checklist's spec_guide (the loader's shape: scripts/kb/load_trade_spec_checklists.mjs expertFieldsOf). */
export interface GuideRow { code: string; spec: string; why_needed_to_price: string; uae_options: string; follow_up_if: string; blocking: boolean;
  /** When this job does not need the spec (15 Nov 2026, journey A; inquiry_intake/interview.ts SpecField.not_needed_when): `answered`
   *  holds spec CODES of the same checklist (the loader writes them from the pack's labels), `text` the condition in plain words. */
  not_needed_when?: { answered?: string[]; text: string } | null }
/** One checklist of one trade, as public.trade_spec_checklist holds it. */
export interface TradeChecklist { trade_code: string; topic_id: string; topic: string; specs: SpecItem[]; guide: GuideRow[]; blocking: string[]; site_visit_required_when: string | null; pack_order: number }
export interface TradeContext { codes: string[]; trades: TaxTrade[]; services: TradeService[]; specs: Record<string, SpecItem[]>; approvals: Record<string, string>; checklists?: Record<string, TradeChecklist[]> }

export const GROUP_LABEL: Record<string, string> = {
  construction_building: 'Construction & building', mep_building_systems: 'MEP & building systems', facilities_property: 'Facilities & property services',
  furniture_hospitality_consumer: 'Furniture, hospitality & consumer goods', health_lab_safety: 'Health, laboratory & safety',
  industrial_manufacturing: 'Industrial equipment & manufacturing', marketing_media_events: 'Marketing, media & events',
  materials_packaging: 'Materials, chemicals & packaging', professional_business: 'Professional & business services',
  technology_telecom: 'Technology & telecom', transport_mobility: 'Transport, vehicles, marine & aviation',
  energy_environment: 'Energy, environment & agriculture',
};
/** taxonomy_trade.authority_required, in words a customer understands (no figure, no fee). */
export const AUTHORITY: Record<string, string> = {
  electrical_utility: "the emirate's electricity authority (DEWA in Dubai, ADDC or AADC in Abu Dhabi, SEWA in Sharjah, Etihad WE in the northern emirates)",
  civil_defence: 'Civil Defence (an approved contractor, approved products and its inspection)',
  sira: "the Security Industry Regulatory Agency in Dubai (SIRA): an approved installer and approved equipment; other emirates' police set their own rules",
};

// ── the taxonomy, read once per instance for ten minutes ────────────────────────────────────────────────────────────
let cached: { at: number; rows: TaxTrade[] } | null = null;
const TTL_MS = 10 * 60_000;
/** Every ACTIVE taxonomy trade, or null when it cannot be read (the caller carries on without it). */
export async function taxonomyOf(admin: Admin, now = Date.now()): Promise<TaxTrade[] | null> {
  if (cached && now - cached.at < TTL_MS) return cached.rows;
  try {
    const { data, error } = await admin.from('taxonomy_trade').select('code,label,label_ar,group_code,authority_required').eq('active', true).order('code').limit(1000);
    if (error || !Array.isArray(data) || !data.length) return cached?.rows ?? null;
    cached = { at: now, rows: data as TaxTrade[] };
    return cached.rows;
  } catch { return cached?.rows ?? null; }
}
export const resetTaxonomyCache = () => { cached = null; };

/** The taxonomy as a prompt block: every code, grouped. The labels are the codes' own words, so codes alone are listed
 *  (223 codes is about 1,200 tokens; with labels it would be twice that for nothing the model needs). */
export function taxonomyBlock(trades: TaxTrade[]): string {
  const by = new Map<string, string[]>();
  for (const t of trades) { const g = t.group_code ?? 'other'; if (!by.has(g)) by.set(g, []); by.get(g)!.push(t.code); }
  return 'THE TRADE TAXONOMY (every trade we serve; put the one to four codes that do THIS job in "trade_codes", most central first; anything but food and beverage):\n'
    + [...by].map(([g, cs]) => `${GROUP_LABEL[g] ?? g}: ${cs.join(', ')}`).join('\n');
}

/** What the trades of a conversation need: services, spec checklists, authority and verified approvals, read together. */
export async function tradeContext(admin: Admin, codes: string[], lang: 'en' | 'ar' = 'en', all?: TaxTrade[] | null): Promise<TradeContext | null> {
  const cs = [...new Set(codes.filter((c) => /^[a-z0-9_]+$/.test(c)))].slice(0, 4);
  if (!cs.length) return null;
  try {
    const [svc, chk, appr, tax] = await Promise.all([
      admin.from('taxonomy_trade_service').select('trade_code,code,label_en,label_ar').eq('active', true).in('trade_code', cs).order('trade_code').order('sort').limit(200),
      checklistRows(admin, cs),
      admin.from('sales_knowledge').select('tags,content').eq('runtime_index_eligible', true).contains('tags', ['kind:standard', 'lang:' + lang])
        .overlaps('tags', cs.map((c) => 'trade:' + c)).limit(8),
      all ? Promise.resolve({ data: all }) : taxonomyOf(admin).then((rows) => ({ data: rows })),
    ]);
    const specs: Record<string, SpecItem[]> = {};
    for (const r of (chk.data ?? []) as { trade_code: string; specs: SpecItem[] }[]) {
      const have = specs[r.trade_code] ?? (specs[r.trade_code] = []);
      for (const s of Array.isArray(r.specs) ? r.specs : []) if (s?.code && !have.some((h) => h.code === s.code)) have.push({ code: String(s.code), label_en: String(s.label_en ?? s.code) });
    }
    const approvals: Record<string, string> = {};
    for (const r of (appr.data ?? []) as { tags: string[]; content: string }[]) {
      const c = (r.tags ?? []).find((t) => t.startsWith('trade:'))?.slice(6);
      if (c && cs.includes(c) && !approvals[c]) approvals[c] = String(r.content ?? '').replace(/\s+/g, ' ').trim().slice(0, 700);
    }
    const trades = ((tax.data ?? []) as TaxTrade[]).filter((t) => cs.includes(t.code));
    return { codes: cs, trades, services: (svc.data ?? []) as TradeService[], specs, approvals, checklists: checklistsOf(chk.data ?? []) };
  } catch { return null; }
}

// The expert columns arrive with a_trades_blocking_specs_and_their_guide_reach_the_interview.sql. Before it is applied the
// wider select is refused (42703), so the rows are read as before and carry no guide and no blocking list.
const CHECKLIST_COLS = 'trade_code,topic_id,topic,specs,spec_guide,blocking,site_visit_required_when,pack_order';
// deno-lint-ignore no-explicit-any
async function checklistRows(admin: Admin, cs: string[]): Promise<{ data: any[] | null }> {
  const q = (cols: string) => admin.from('trade_spec_checklist').select(cols).in('trade_code', cs).order('topic_id').limit(50);
  const wide = await q(CHECKLIST_COLS);
  if (!wide.error) return wide;
  return await q('trade_code,topic_id,specs');
}
const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));
/** A guide row's not_needed_when, kept only with a condition in words and only naming specs of its own checklist. */
// deno-lint-ignore no-explicit-any
function notNeededOfGuide(g: any, codes: Set<string>): { answered?: string[]; text: string } | null {
  const n = g?.not_needed_when;
  const text = str(n?.text).trim();
  if (!n || typeof n !== 'object' || !text) return null;
  const answered = (Array.isArray(n.answered) ? n.answered : []).map(String).filter((c: string) => codes.has(c));
  return answered.length ? { answered, text } : { text };
}
/** The rows as checklists per trade, the pack's first checklist first (pack_order, then topic_id). */
// deno-lint-ignore no-explicit-any
export function checklistsOf(rows: any[]): Record<string, TradeChecklist[]> {
  const out: Record<string, TradeChecklist[]> = {};
  for (const r of rows) {
    if (!r?.trade_code || !r?.topic_id) continue;
    const specs: SpecItem[] = (Array.isArray(r.specs) ? r.specs : []).filter((x: SpecItem) => x?.code).map((x: SpecItem) => ({ code: String(x.code), label_en: str(x.label_en ?? x.code) }));
    const codes = new Set(specs.map((x) => x.code));
    const blocking = (Array.isArray(r.blocking) ? r.blocking : []).map(String).filter((c: string) => codes.has(c));
    const guide: GuideRow[] = (Array.isArray(r.spec_guide) ? r.spec_guide : []).filter((g: GuideRow) => g?.code && codes.has(String(g.code))).map((g: GuideRow) => ({
      code: String(g.code), spec: str(g.spec), why_needed_to_price: str(g.why_needed_to_price), uae_options: str(g.uae_options), follow_up_if: str(g.follow_up_if), blocking: blocking.includes(String(g.code)),
      ...(notNeededOfGuide(g, codes) ? { not_needed_when: notNeededOfGuide(g, codes) } : {}) }));
    const svw = str(r.site_visit_required_when).trim();
    (out[r.trade_code] ??= []).push({ trade_code: String(r.trade_code), topic_id: String(r.topic_id), topic: str(r.topic ?? r.topic_id), specs, guide, blocking,
      site_visit_required_when: svw || null, pack_order: Number.isFinite(Number(r.pack_order)) ? Number(r.pack_order) : 0 });
  }
  for (const k of Object.keys(out)) out[k].sort((a, b) => a.pack_order - b.pack_order || a.topic_id.localeCompare(b.topic_id));
  return out;
}

/** The context as a prompt block. '' when there is nothing to say. Only the placed trades are in it (at most four), and of
 *  each only the checklist(s) this job is get the full guide; the trade's other checklists are one line each, to choose. */
export function tradeBlock(ctx: TradeContext | null, lang: 'en' | 'ar' = 'en', topics: string[] = []): string {
  if (!ctx || !ctx.codes.length) return '';
  const out = ['THE TRADES THIS CONVERSATION IS PLACED IN (from our taxonomy and each trade\'s verified pack; follow it):'];
  const cut = (x: string, n = GUIDE_FIELD_MAX) => (x.length > n ? x.slice(0, n - 1).trimEnd() + '…' : x);
  for (const code of ctx.codes) {
    const t = ctx.trades.find((x) => x.code === code);
    out.push(`[${code}] ${t?.label ?? code.replace(/_/g, ' ')}${lang === 'ar' && t?.label_ar ? ' (' + t.label_ar + ')' : ''}`);
    const auth = (t?.authority_required ?? []).map((a) => AUTHORITY[a]).filter(Boolean);
    if (auth.length) out.push('  APPROVAL ALWAYS NEEDED: ' + auth.join('; ') + '. Say so when it matters to their job, and ask the emirate.');
    if (ctx.approvals[code]) out.push('  LOCATION RULES (verified; the emirate decides which authority applies): ' + ctx.approvals[code]);
    const all = ctx.checklists?.[code] ?? [];
    const active = activeChecklists(ctx, topics)[code] ?? [];
    if (active.some((c) => c.blocking.length)) {
      for (const c of active) {
        out.push(`  THE CHECKLIST FOR THIS JOB: ${c.topic_id} (${cut(c.topic, 120)})`);
        const g = new Map(c.guide.map((r) => [r.code, r]));
        const line = (s: SpecItem, why: boolean) => {
          const r = g.get(s.code);
          return `   - [${s.code}] ${s.label_en}` + (r ? (why && r.why_needed_to_price ? ` | why: ${cut(r.why_needed_to_price)}` : '') + (r.uae_options ? ` | UAE options: ${cut(r.uae_options)}` : '')
            + (r.follow_up_if ? ` | then ask: ${cut(r.follow_up_if)}` : '') + (r.not_needed_when ? ` | NOT NEEDED (never ask it) when: ${cut(r.not_needed_when.text)}` : '') : '');
        };
        // a universal spec (UNIVERSAL_SPECS) is not this trade's question: it is asked once, in the block after the trades
        const own = c.specs.filter((s) => !universalOf(s.label_en));
        const blk = own.filter((s) => c.blocking.includes(s.code));
        out.push('  BLOCKING: a supplier cannot give a firm price without these. Ask them FIRST, in plain words, one or two at a time, never one they already answered. The request is not ready until each is answered, or the customer says they do not know (put its key in "unknown_keys": it goes to the suppliers as "supplier to advise").');
        out.push(...blk.map((s) => line(s, true)));
        const rest = own.filter((s) => !c.blocking.includes(s.code));
        if (rest.length) { out.push('  ALSO FOR AN EXACT QUOTE (after the blocking ones; never what they already said):'); out.push(...rest.map((s) => line(s, false))); }
        if (c.site_visit_required_when) out.push(`  SITE VISIT: ${cut(c.site_visit_required_when, 300)} If this applies to their job, put "${code}" in "site_visit" and tell them plainly that a final price needs a visit first.`);
      }
      const others = all.filter((c) => !active.includes(c));
      if (others.length) out.push('  THIS TRADE\'S OTHER CHECKLISTS (if the job is one of these instead, put its id in "checklist_topics"): ' + others.map((c) => `${c.topic_id} (${cut(c.topic, 80)})`).join('; '));
    } else {
      const sp = ctx.specs[code] ?? [];
      if (sp.length) out.push('  WHAT A SUPPLIER OF THIS TRADE NEEDS STATED TO QUOTE EXACTLY (ask what is still missing, in plain words, one or two at a time; never what they already said): ' + sp.map((s) => s.label_en).join('; '));
    }
    const sv = ctx.services.filter((s) => s.trade_code === code);
    if (sv.length) out.push('  SERVICES (put the keys of the ones this job needs in "service_keys"): ' + sv.map((s) => `${s.trade_code}.${s.code} = ${s.label_en}`).join('; '));
  }
  const once = packFields(ctx, topics).filter((f) => f.trade === 'universal');
  if (once.length) {
    out.push('ASKED ONCE FOR THE WHOLE REQUEST, NEVER ONCE PER TRADE (one answer serves every trade above; put it in brief.details under this key, and never ask it again once it is held or the emirate is known):');
    for (const f of once) {
      const by = ctx.codes.filter((c) => (activeChecklists(ctx, topics)[c] ?? []).some((k) => k.specs.some((x) => universalOf(x.label_en) === f.key && k.blocking.includes(x.code))));
      out.push(`   - [${f.key}] ${f.question}${by.length ? ' BLOCKING for: ' + by.join(', ') + '.' : ' (not blocking)'}`);
    }
  }
  return out.join('\n');
}
/** A guide field is cut here in the prompt (the table keeps it whole). Measured 10 Nov 2026 over the 4,045 guide rows. */
export const GUIDE_FIELD_MAX = 220;

/** The codes the model named that exist (at most four, in its order). */
export function validCodes(x: unknown, trades: TaxTrade[] | null): string[] {
  if (!Array.isArray(x) || !trades) return [];
  const known = new Set(trades.map((t) => t.code));
  return [...new Set(x.map((c) => String(c ?? '').trim().toLowerCase()).filter((c) => known.has(c)))].slice(0, 4);
}
/** The service keys the model named that exist among the services it was shown. */
export function validServiceKeys(x: unknown, services: TradeService[] | null | undefined): string[] {
  if (!Array.isArray(x) || !services?.length) return [];
  const known = new Set(services.map((s) => s.trade_code + '.' + s.code));
  return [...new Set(x.map((c) => String(c ?? '').trim().toLowerCase()).filter((c) => known.has(c)))].slice(0, 8);
}

/** A checklist the request chat can run for a trade's spec checklist: the first `required` specs are required, the rest
 *  optional (a pack lists the core first: passengers before exclusions, dimensions before printing). THE EARLIER RULE,
 *  kept only for a trade whose rows carry no blocking list yet (packFields). */
export const CHECKLIST_REQUIRED = 6;
export type PackField = { key: string; question: string; required: boolean; type: string; options: string[]; blocking?: boolean; trade?: string;
  not_needed_when?: { answered?: string[]; text: string } | null;
  /** WHAT THE CUSTOMER READS (15 Nov 2026; _shared/customer_questions.ts): `question` stays the supplier-facing label; the card
   *  shows these plain questions, with card_options to tap (each list ending with "Not sure"). `options` stays [] so the
   *  interview's own readers treat a pack spec as free text, exactly as before. plain=false: no vetted wording for this spec. */
  question_plain_en?: string; question_plain_ar?: string; card_options?: string[]; card_options_ar?: string[]; plain?: boolean };
/** A pack spec's customer-facing wording beside its label (customer_questions.ts plainOf). */
function withPlain(code: string, label: string): Pick<PackField, 'question_plain_en' | 'question_plain_ar' | 'card_options' | 'card_options_ar' | 'plain'> {
  const p = plainOf(code, label);
  return { question_plain_en: p.question_plain_en, ...(p.question_plain_ar ? { question_plain_ar: p.question_plain_ar } : {}), card_options: p.options, card_options_ar: p.options_ar, plain: p.plain };
}
const questionOf = (label: string) => label.charAt(0).toUpperCase() + label.slice(1);
export function checklistFields(specs: SpecItem[], required = CHECKLIST_REQUIRED): PackField[] {
  return specs.map((s, i) => ({ key: s.code, question: questionOf(s.label_en), required: i < required, type: 'text', options: [], ...withPlain(s.code, s.label_en) }));
}

// ── THE BLOCKING RULE (founder ledger 1587) ──────────────────────────────────────────────────────────────────────────
/** What goes to the suppliers for a blocking spec the customer said they do not know: an explicit answer, not a gap. */
export const SUPPLIER_TO_ADVISE = 'Customer does not know: supplier to advise';

// ── THE UNIVERSAL SPECS: ASKED ONCE PER REQUEST, NEVER ONCE PER TRADE (10 Nov 2026, ledger 1587) ────────────────────
// The supplier ask-back reviews added "Payment terms" to most checklists (231 of 305 measured after the merge) and "site
// location and emirate" / "delivery location and emirate" to many (blocking in 66). A request held in two trades asked
// both twice. A spec whose label is EXACTLY one of these (lower-cased, trimmed) is the request's single field for that
// concept: one question, one answer, and every trade that lists it reads the same answer. The pack rows stay as they are:
// they say why each trade needs the field. An explicit table, never a word match (decision points are code): a label not
// listed here is a trade spec, however close its wording.
//   NOT listed, on purpose: "lead time" (the supplier states it, the customer does not), "delivery terms and location"
//   (the terms, ex-works or delivered, are the trade's own), "inter-emirate travel", "plot location and emirate" and
//   "property locations and emirates" (a plot or many properties is more than the request's one site), "start date"
//   (when a service starts, not when the job is needed by), "budget breakdown".
export type UniversalKey = 'location' | 'payment_terms' | 'required_by' | 'budget';
export const UNIVERSAL_SPECS: Readonly<Record<string, UniversalKey>> = {
  'site location and emirate': 'location', 'site_location_and_emirate': 'location', 'site locations and emirates': 'location',
  'delivery location and emirate': 'location', 'delivery emirate and site': 'location', 'delivery site and emirate': 'location',
  'delivery site location': 'location', 'delivery addresses and emirate': 'location', 'delivery and installation site and emirate': 'location',
  'service location and emirate': 'location', 'emirate and site location': 'location', 'facility location and emirate': 'location',
  'premises location and emirate': 'location', 'building location and emirate': 'location', 'site location for on-site work': 'location',
  'emirate': 'location',
  'payment terms': 'payment_terms', 'payment_terms': 'payment_terms', 'payment milestones': 'payment_terms',
  'required delivery or completion date': 'required_by', 'required delivery date': 'required_by', 'delivery date': 'required_by',
  'budget': 'budget',
};
export const universalOf = (label: string): UniversalKey | null => UNIVERSAL_SPECS[String(label ?? '').trim().toLowerCase()] ?? null;
/** The one question for each universal field, asked once for the whole request. */
export const UNIVERSAL_QUESTION: Readonly<Record<UniversalKey, string>> = {
  location: 'Where is the site or the delivery address, and in which emirate?',
  payment_terms: 'What payment terms do you expect (for example an advance, on delivery, or 30 days after invoice)?',
  required_by: 'By when do you need it done or delivered?',
  budget: 'Do you have a budget in mind?',
};
/** Payment terms is asked once of every request a pack trade is placed in (nothing else in the interview asks it); it
 *  never blocks. location is a field when a placed trade lists it. required_by and budget are already the interview's
 *  own (the four questions' "needed by", the solution state's budget): a trade's spec for them is answered from there
 *  and never asked as a pack question. */
const UNIVERSAL_FIELD: Readonly<Record<UniversalKey, boolean>> = { location: true, payment_terms: true, required_by: false, budget: false };
/** The request's single answer for each universal field: its own key in the specs/details, the slots' emirate (detected
 *  or stated), the four questions' "needed by", the state's budget. A field with no answer is absent. */
export function universalAnswers(src: { specs?: Record<string, unknown>; emirate?: string | null; required_by?: string | null; budget?: string | null }): Partial<Record<UniversalKey, string>> {
  const sp = src.specs ?? {};
  const first = (...xs: unknown[]) => { for (const x of xs) { const v = valueOf(x); if (v) return v; } return ''; };
  const out: Partial<Record<UniversalKey, string>> = {};
  const loc = first(sp.location, sp.emirate, src.emirate);
  if (loc) out.location = loc;
  const pay = first(sp.payment_terms);
  if (pay) out.payment_terms = pay;
  const by = first(sp.required_by, sp.timeline, src.required_by);
  if (by) out.required_by = by;
  const bud = first(sp.budget, src.budget);
  if (bud) out.budget = bud;
  return out;
}
/** The topic ids the model named that are checklists of the placed trades. */
export function validTopics(x: unknown, ctx: TradeContext | null): string[] {
  if (!Array.isArray(x) || !ctx?.checklists) return [];
  const known = new Set(Object.values(ctx.checklists).flat().map((c) => c.topic_id));
  return [...new Set(x.map((t) => String(t ?? '').trim()).filter((t) => known.has(t)))].slice(0, 8);
}
/** Per placed trade, the checklist(s) this job is: the ones named in `topics`, else the pack's first (the core job). */
export function activeChecklists(ctx: TradeContext | null, topics: string[] = []): Record<string, TradeChecklist[]> {
  const out: Record<string, TradeChecklist[]> = {};
  for (const code of ctx?.codes ?? []) {
    const all = ctx?.checklists?.[code] ?? [];
    if (!all.length) continue;
    const named = all.filter((c) => topics.includes(c.topic_id));
    out[code] = named.length ? named : [all[0]];
  }
  return out;
}
/** Whether a trade's rows carry the blocking rule (the loader has written them since the SQL was applied). */
export const hasBlocking = (ctx: TradeContext | null, code: string) => (ctx?.checklists?.[code] ?? []).some((c) => c.blocking.length > 0);

/** The pack fields the request chat runs, for EVERY placed trade: each blocking spec of the job's checklist(s) REQUIRED, and
 *  first; the rest optional. A trade without a blocking list yet keeps the earlier rule (its first CHECKLIST_REQUIRED
 *  specs, required only when the request has no real slug), and only for the most central trade, as before. */
export function packFields(ctx: TradeContext | null, topics: string[] = [], generic = true): PackField[] {
  if (!ctx?.codes.length) return [];
  const active = activeChecklists(ctx, topics);
  const blocking: PackField[] = [];
  const rest: PackField[] = [];
  const seen = new Set<string>();
  const universal = new Map<UniversalKey, boolean>();   // universal key -> blocking for some placed trade
  for (const code of ctx.codes) {
    if (!hasBlocking(ctx, code)) {
      if (code !== ctx.codes[0]) continue;
      for (const f of checklistFields(ctx.specs[code] ?? [], generic ? CHECKLIST_REQUIRED : 0)) if (!seen.has(f.key)) { seen.add(f.key); (f.required ? blocking : rest).push({ ...f, trade: code }); }
      continue;
    }
    for (const c of active[code] ?? []) for (const s of c.specs) {
      const u = universalOf(s.label_en);
      if (u) { const b = c.blocking.includes(s.code); universal.set(u, (universal.get(u) ?? false) || b); continue; }
      if (seen.has(s.code)) continue;
      seen.add(s.code);
      const b = c.blocking.includes(s.code);
      const nn = c.guide.find((g) => g.code === s.code)?.not_needed_when;
      (b ? blocking : rest).push({ key: s.code, question: questionOf(s.label_en), required: b, type: 'text', options: [], blocking: b, trade: code, ...(nn ? { not_needed_when: nn } : {}), ...withPlain(s.code, s.label_en) });
    }
  }
  // the universal fields, ONCE for the whole request: required when any placed trade blocks on it; payment terms always
  if (ctx.codes.some((c) => hasBlocking(ctx, c)) && !universal.has('payment_terms')) universal.set('payment_terms', false);
  for (const [u, b] of universal) {
    if (!UNIVERSAL_FIELD[u] || seen.has(u)) continue;
    seen.add(u);
    (b ? blocking : rest).push({ key: u, question: UNIVERSAL_QUESTION[u], required: b, type: 'text', options: [], blocking: b, trade: 'universal', ...withPlain(u, UNIVERSAL_QUESTION[u]) });
  }
  return [...blocking, ...rest];
}

export interface BlockingItem { trade: string; key: string; spec: string; question: string }
export interface SiteVisit { trade: string; topic_id: string; when: string; applies: boolean; text: string }
export interface Readiness { ready: boolean; open: BlockingItem[]; answered: BlockingItem[]; advised: BlockingItem[]; site_visits: SiteVisit[] }
const filled = (v: unknown) => v !== undefined && v !== null && String(typeof v === 'object' ? (v as { value?: unknown }).value ?? JSON.stringify(v) : v).trim() !== '';
const valueOf = (v: unknown) => String(typeof v === 'object' && v !== null ? (v as { value?: unknown }).value ?? '' : v ?? '').trim();
/** THE RULE: a request is ready only when every blocking spec of every placed trade's job checklist has an answer in
 *  `specs` (the state's specs and this turn's details, by spec code), or is one the customer said they do not know
 *  (`unknown`), which counts as answered and is sent as SUPPLIER_TO_ADVISE. Each site-visit condition of those checklists
 *  is carried: `applies` when the model judged it applies to this job (`siteVisit` names the trade), else stated as the
 *  condition it is. A trade without a blocking list yet adds nothing here (the earlier rule holds it through the slots). */
export function readinessOf(ctx: TradeContext | null, topics: string[], specs: Record<string, unknown>, unknown: Iterable<string> = [], siteVisit: string[] = [],
  universal: Partial<Record<UniversalKey, string>> = universalAnswers({ specs })): Readiness {
  const unk = new Set([...unknown].map(String));
  const r: Readiness = { ready: true, open: [], answered: [], advised: [], site_visits: [] };
  const seen = new Set<string>();
  for (const [code, lists] of Object.entries(activeChecklists(ctx, topics))) {
    for (const c of lists) {
      for (const code0 of c.blocking) {
        const label = c.specs.find((s) => s.code === code0)?.label_en ?? code0;
        // a universal spec is the request's one field: reported once under its universal key, answered by its one answer
        const u = universalOf(label);
        const key = u ?? code0;
        if (seen.has(key)) continue;
        seen.add(key);
        const item = { trade: u ? 'universal' : code, key, spec: u ? UNIVERSAL_QUESTION[u] : label, question: u ? UNIVERSAL_QUESTION[u] : questionOf(label) };
        const v = u ? (universal[u] ?? specs[code0]) : specs[key];
        if (filled(v) && valueOf(v) !== SUPPLIER_TO_ADVISE) r.answered.push(item);
        else if (filled(v) || unk.has(key)) r.advised.push(item);
        else r.open.push(item);
      }
      if (c.site_visit_required_when) {
        const applies = siteVisit.includes(code);
        r.site_visits.push({ trade: code, topic_id: c.topic_id, when: c.site_visit_required_when, applies,
          text: (applies ? 'Site visit needed before a final price. ' : 'Known condition: ') + c.site_visit_required_when });
      }
    }
  }
  r.ready = r.open.length === 0;
  return r;
}
/** details with the request's one answer under each universal field the checklist runs and the details do not hold yet
 *  (the emirate the conversation states answers "location" for every trade), so the slots never ask it again. */
export function withUniversal(details: Record<string, unknown>, fields: PackField[], universal: Partial<Record<UniversalKey, string>>): Record<string, unknown> {
  const out = { ...details };
  for (const f of fields) if (f.trade === 'universal' && !filled(out[f.key]) && universal[f.key as UniversalKey]) out[f.key] = universal[f.key as UniversalKey];
  return out;
}
/** details with SUPPLIER_TO_ADVISE under every pack spec of the job the customer said they do not know and that holds no
 *  answer, so the slots count it answered (never held for it) and the suppliers read it as theirs to advise. */
export function adviseUnknown(details: Record<string, unknown>, fields: PackField[], unknown: Iterable<string>): Record<string, unknown> {
  const keys = new Set(fields.map((f) => f.key));
  const out = { ...details };
  for (const k of unknown) if (keys.has(k) && !filled(out[k])) out[k] = SUPPLIER_TO_ADVISE;
  return out;
}

// ── PLACEMENT FOLLOWS THE CHOSEN SERVICES (evidence run of 10 Nov 2026, ledger 1604, finding b1) ─────────────────────
// "Old PVC wall panels on an MDF partition: remove and install new PVC wall panels" (Business Bay) was placed in
// trade_codes [interior_fitout, joinery] while its chosen services were [wallpaper.wall_cladding, wallpaper.wall_panels,
// interior_fitout.refurbishment, joinery.wood_panelling]: the wall-panel trade itself was not placed, a fit-out's
// blocking specs (MEP scope, authority approvals) were asked of a panel job, and the composer offered a turnkey
// contractor for what one wall-panel installer does. The model's trade list is an INPUT here, not the final word. The
// placement is decided in code from the service keys (each key names its trade: <trade>.<service>) and the taxonomy:
//   * a WHOLE-SCOPE trade (a fit-out, combined MEP, general contracting: a trade whose own job is to carry several others
//     — line_specs' composite trades, by EXACT mapping only) is primary only when the chosen services span at least
//     WHOLE_SCOPE_SPREAD specialist trades (or name no specialist at all): then it is a genuine multi-trade job, and
//     every trade that owns a chosen service stays placed beside it. Two specialist scopes are not a fit-out: they are
//     one specialist, or two quotes (the PVC job named wall panels and wood panelling, and was one installer's job);
//   * otherwise the PRIMARY trade is the specialist that owns the most chosen services (a tie goes to the model's
//     order, then to the first key named). It is one supplier type: another specialist stays only when it owns as many
//     chosen services as the primary (a genuinely co-equal second scope), and a whole-scope trade never joins it;
//   * the service keys kept are the placed trades' own, so the request never invites a trade it was not placed in.
// With no chosen service the model's codes stand, as before. Pure: nothing here reads the customer's words.

/** A trade whose own job carries several others (a fit-out, combined MEP, general contracting). Exact mappings only: a code
 *  tradeOfCategory resolves to 'general' merely because it knows no better (a bus rental) is NOT whole-scope. */
export function isWholeScopeTrade(code: string): boolean {
  const c = String(code ?? '').trim().toLowerCase();
  const t = tradeOfCategory(c);
  if (!COMPOSITE.has(t)) return false;
  return t !== 'general' || c === 'general' || SAME_AS[c] === 'general';
}
export interface Placement { codes: string[]; primary: string | null; keys: string[]; multi: boolean; by: 'services' | 'model' }
/** The trades a request is placed in, from its chosen service keys and the model's codes (both already validated). */
export function placeTrades(modelCodes: string[], serviceKeys: string[]): Placement {
  const codes = [...new Set((modelCodes ?? []).map(String).filter(Boolean))];
  const keys = [...new Set((serviceKeys ?? []).map(String).filter((k) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(k)))];
  if (!keys.length) return { codes: codes.slice(0, 4), primary: codes[0] ?? null, keys: [], multi: codes.length > 1, by: 'model' };
  const tradeOf = (k: string) => k.slice(0, k.indexOf('.'));
  const count = new Map<string, number>(); const first = new Map<string, number>();
  keys.forEach((k, i) => { const t = tradeOf(k); count.set(t, (count.get(t) ?? 0) + 1); if (!first.has(t)) first.set(t, i); });
  const rank = (t: string) => { const i = codes.indexOf(t); return i < 0 ? codes.length + (first.get(t) ?? 0) : i; };
  const owners = [...count.keys()].sort((a, b) => (count.get(b)! - count.get(a)!) || (rank(a) - rank(b)));
  const specialists = owners.filter((t) => !isWholeScopeTrade(t));
  const whole = [...new Set([...codes, ...owners])].filter(isWholeScopeTrade).sort((a, b) => rank(a) - rank(b));
  let primary: string; let placed: string[];
  if (whole.length && (specialists.length >= WHOLE_SCOPE_SPREAD || !specialists.length)) {
    primary = whole[0];
    placed = [...new Set([primary, ...owners.filter((t) => t !== primary), ...codes])];
  } else {
    primary = specialists[0];
    placed = [primary, ...specialists.slice(1).filter((t) => count.get(t) === count.get(primary))];
  }
  placed = placed.slice(0, 4);
  return { codes: placed, primary, keys: keys.filter((k) => placed.includes(tradeOf(k))), multi: placed.length > 1, by: 'services' };
}
/** How many specialist trades the chosen services must span before a whole-scope trade (a fit-out) is the placement. A
 *  judgement, written down: partitions plus paint is one gypsum contractor's job; partitions, ceilings, power and AC is a
 *  fit-out. Below it the specialist placement stands and the customer still chooses one contractor or separate quotes. */
export const WHOLE_SCOPE_SPREAD = 3;
/** The category slug of a placed trade: the code itself, or its hyphenated spelling, when it is a listed slug. */
export function slugOfTrade(code: string | null | undefined, slugs: string[]): string | null {
  const c = String(code ?? '').trim().toLowerCase();
  if (!c) return null;
  if (slugs.includes(c)) return c;
  const h = c.replace(/_/g, '-');
  return slugs.includes(h) ? h : null;
}
