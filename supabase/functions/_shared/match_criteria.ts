// WHAT THE STORED INQUIRY ASKS THE MATCHER FOR (sales_engineer, 12 Oct 2026).
//
// Measured on production, stage-2 sandbox run f4294be8: 9 ZZ DEMO requests, all status 'sent', 0 rows in
// inquiry_matches, routing.gap = 'no_trade_identified' on every one. Two causes, both in the one path
// every request takes (sales_engineer {action:'match'}):
//  1. customer_api.create_inquiry stores `trades` only when the caller names them, so a single-trade
//     request carries its trade in `category` alone. The matcher read `trades`, then fell back to
//     fn_norm_trades over the WHOLE brief — which since #893 (23 Sep 2026) resolves an exact slug only
//     and answers NULL for free text. The category slug was inside that brief and never tried on its own.
//  2. `emirate` is stored as written; 'دبي' never equalled a supplier's stated 'Dubai', so an Arabic
//     request was matched against nobody in its own emirate.
// Both are exact, never nearest: the category is a slug from the intake's fixed list (resolved by
// fn_taxonomy_trades_for, exact only), and an emirate is one of eight names in two scripts.
import { parseEmirate } from './answer_parse.ts';

const list = (v: unknown): string[] =>
  (Array.isArray(v) ? v : []).map((x) => String(x).trim().toLowerCase()).filter(Boolean);

/** The slugs to resolve: the stored trades, else the stored category on its own. */
export function tradeSlugsOf(inq: { trades?: unknown; category?: unknown }): string[] {
  const t = list(inq.trades);
  if (t.length) return t;
  const c = String(inq.category ?? '').trim().toLowerCase();
  return c ? [c] : [];
}

/** The emirate in the one spelling suppliers state it in; unrecognised text is passed through. */
export function matchEmirate(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (!s) return null;
  return parseEmirate(s) ?? s;
}
