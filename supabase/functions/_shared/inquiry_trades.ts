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
// The trade is chosen by the model's reading of the whole conversation (ruling 890); nothing here reads the customer's words.
// prevented by: supabase/functions/_shared/inquiry_trades.test.ts (a spread across all twelve groups)
// deno-lint-ignore no-explicit-any
type Admin = any;

export interface TaxTrade { code: string; label: string; label_ar?: string | null; group_code: string | null; authority_required?: string[] | null }
export interface TradeService { trade_code: string; code: string; label_en: string; label_ar?: string | null }
export interface SpecItem { code: string; label_en: string }
export interface TradeContext { codes: string[]; trades: TaxTrade[]; services: TradeService[]; specs: Record<string, SpecItem[]>; approvals: Record<string, string> }

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
      admin.from('trade_spec_checklist').select('trade_code,topic_id,specs').in('trade_code', cs).order('topic_id').limit(50),
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
    return { codes: cs, trades, services: (svc.data ?? []) as TradeService[], specs, approvals };
  } catch { return null; }
}

/** The context as a prompt block. '' when there is nothing to say. */
export function tradeBlock(ctx: TradeContext | null, lang: 'en' | 'ar' = 'en'): string {
  if (!ctx || !ctx.codes.length) return '';
  const out = ['THE TRADES THIS CONVERSATION IS PLACED IN (from our taxonomy and each trade\'s verified pack; follow it):'];
  for (const code of ctx.codes) {
    const t = ctx.trades.find((x) => x.code === code);
    out.push(`[${code}] ${t?.label ?? code.replace(/_/g, ' ')}${lang === 'ar' && t?.label_ar ? ' (' + t.label_ar + ')' : ''}`);
    const auth = (t?.authority_required ?? []).map((a) => AUTHORITY[a]).filter(Boolean);
    if (auth.length) out.push('  APPROVAL ALWAYS NEEDED: ' + auth.join('; ') + '. Say so when it matters to their job, and ask the emirate.');
    if (ctx.approvals[code]) out.push('  LOCATION RULES (verified; the emirate decides which authority applies): ' + ctx.approvals[code]);
    const sp = ctx.specs[code] ?? [];
    if (sp.length) out.push('  WHAT A SUPPLIER OF THIS TRADE NEEDS STATED TO QUOTE EXACTLY (ask what is still missing, in plain words, one or two at a time; never what they already said): ' + sp.map((s) => s.label_en).join('; '));
    const sv = ctx.services.filter((s) => s.trade_code === code);
    if (sv.length) out.push('  SERVICES (put the keys of the ones this job needs in "service_keys"): ' + sv.map((s) => `${s.trade_code}.${s.code} = ${s.label_en}`).join('; '));
  }
  return out.join('\n');
}

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
 *  optional (a pack lists the core first: passengers before exclusions, dimensions before printing). */
export const CHECKLIST_REQUIRED = 6;
export function checklistFields(specs: SpecItem[], required = CHECKLIST_REQUIRED): { key: string; question: string; required: boolean; type: string; options: string[] }[] {
  return specs.map((s, i) => ({ key: s.code, question: s.label_en.charAt(0).toUpperCase() + s.label_en.slice(1), required: i < required, type: 'text', options: [] }));
}
