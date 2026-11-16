// _shared/trade_context.ts -- the shapes of a trade's context and the choice of its active checklists, with nothing heavy
// behind them (16 Nov 2026, sales_engineer). Moved out of inquiry_trades.ts so a function that only reads a request's
// checklists (supplier_api's site photos) does not bundle the customer question tables inquiry_trades.ts imports: the
// supplier_api deploy of 16 Nov 02:30 UTC was refused at the 5 MB limit (4,994,611 bytes of local modules). inquiry_trades.ts
// re-exports everything here, so every other importer is unchanged.

export interface TaxTrade { code: string; label: string; label_ar?: string | null; group_code: string | null; authority_required?: string[] | null }
export interface TradeService { trade_code: string; code: string; label_en: string; label_ar?: string | null }
export interface SpecItem { code: string; label_en: string }
/** One row of a checklist's spec_guide (the loader's shape: scripts/kb/load_trade_spec_checklists.mjs expertFieldsOf). */
export interface GuideRow { code: string; spec: string; why_needed_to_price: string; uae_options: string; follow_up_if: string; blocking: boolean;
  /** When this job does not need the spec (15 Nov 2026, journey A; inquiry_intake/interview.ts SpecField.not_needed_when): `answered`
   *  holds spec CODES of the same checklist (the loader writes them from the pack's labels), `text` the condition in plain words. */
  not_needed_when?: { answered?: string[]; text: string } | null }
/** One photo a site-visit job asks for (15 Nov 2026, founder ledger 1704; scripts/kb/photos_to_ask.mjs): the shot in plain words,
 *  in English and Arabic, and `from`, the words of the checklist's own site-visit sentence it shows. */
export interface PhotoShot { shot: string; shot_ar: string; from: string }
/** One checklist of one trade, as public.trade_spec_checklist holds it. */
export interface TradeChecklist { trade_code: string; topic_id: string; topic: string; specs: SpecItem[]; guide: GuideRow[]; blocking: string[]; site_visit_required_when: string | null; pack_order: number;
  /** The photos a site-visit job asks for ([] when none, or before a_site_visit_checklist_carries_the_photos_to_ask_for.sql). */
  photos?: PhotoShot[] }
export interface TradeContext { codes: string[]; trades: TaxTrade[]; services: TradeService[]; specs: Record<string, SpecItem[]>; approvals: Record<string, string>; checklists?: Record<string, TradeChecklist[]> }

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
