// reasoned_trades — which trade a person's words name, REASONED among the real taxonomy, never read off a word list.
// Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
//
// Replaces, in decision_points.json order:
//   19 shared.trade_classify      _shared/trade_classify.ts (KW map, tradeHits, detectCat, detectTrades, COMPONENT_OF) — deleted
//   20 customer_api.keywords      customer_api/keywords.ts detect(): create_inquiry's category fallback — deleted
//   21 customer_api.resolve_trade customer_api discover: resolveTrade's alias / label-substring match
//   22 inbound_email.infer_sector inbound_email inferSector: a second KW map scoring substrings
//
// EXACT TRADE OR NONE (founder): the choice is one of the real options the caller passes (category_specs or
// taxonomy_trade rows, read live) or 'none' — a new trade, or no job at all. There is no nearest mapping: the
// 'none' option says so, and think() refuses any id that is not an option. Under the model hold the value is
// null (the question is filed in the sales engineer's queue unless the caller says the answer has no later use)
// and every caller does the non-committal thing; none of them falls back to a word.
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';

export type TradeOption = { slug: string; label: string };
export const NONE = 'none';

/** Which ONE of `options` is the job these words describe, or 'none'. */
export async function tradeOfText(deps: ThinkDeps, o: {
  surface: 'customer_api.keywords' | 'customer_api.resolve_trade' | 'inbound_email.infer_sector';
  text: string; options: TradeOption[]; audience: 'customer' | 'supplier';
  dedupeKey?: string; subject?: Record<string, unknown>; queueWhenHeld?: boolean;
}): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: o.surface, question: o.text.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    queueWhenHeld: o.queueWhenHeld,
    context: { audience: o.audience },
    decision: {
      name: 'trade',
      options: [
        ...o.options.map((t) => ({ id: t.slug, meaning: `the work or product is exactly ${t.label}` })),
        { id: NONE, meaning: 'none of the listed trades is exactly this work (a trade we do not list yet, or not a job at all) — never the nearest one' },
      ],
    },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}
