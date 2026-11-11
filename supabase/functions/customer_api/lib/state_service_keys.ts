// THE REQUEST'S SERVICES, FROM ITS CONVERSATION STATE (10 Nov 2026, sales_engineer; founder ledger 1573/1579).
//
// The expert-advice catalogue (branch sales_engineer-expert-advice) maps the option a customer chose to exact taxonomy
// service keys and writes them into inquiry_state.specs.service_keys of the request chat ('intake:<inquiry_intake.id>').
// When they are there, the inquiry carries them in inquiries.service_keys from the moment it is created, so dispatch
// (sales_engineer action match) matches on the codes the customer chose instead of reading his prose again. When they are
// not (no state, the table not yet applied, nothing chosen), the column stays NULL and dispatch matches at trade level: since
// 11 Nov 2026 (founder rulings 1627 and 1628) the brief is never read for keys by code (service_vocabulary.serviceKeysOf is
// deleted). The keys in the state are the ones the intake model named from our catalogue, or the option the customer chose.
// prevented by: supabase/functions/customer_api/state_service_keys.test.ts
import { intakeKey, readState } from '../../_shared/inquiry_state.ts';
import { stateServiceKeys } from '../../_shared/profile_services.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** The live service keys the request chat's state names, [] when none (or unreadable). */
export async function stateKeysForIntake(admin: Admin, intakeId: string): Promise<string[]> {
  try {
    const raw = stateServiceKeys(await readState(admin, intakeKey(intakeId)));
    if (!raw.length) return [];
    const { data, error } = await admin.from('taxonomy_trade_service').select('trade_code,code').eq('active', true)
      .in('trade_code', [...new Set(raw.map((k) => k.split('.')[0]))]).in('code', [...new Set(raw.map((k) => k.split('.')[1]))]);
    if (error || !Array.isArray(data)) return [];
    const live = new Set(data.map((r: { trade_code: string; code: string }) => r.trade_code + '.' + r.code));
    return raw.filter((k) => live.has(k));
  } catch (_e) { return []; }
}

/** A split child carries only the keys of its own trade: a key of another trade would widen the child's reach to that trade
 *  (fn_match_capability adds a named service's trade). The child's trade is resolved as dispatch resolves it. */
export async function keysOfTrade(admin: Admin, keys: string[], trade: string): Promise<string[]> {
  if (!keys.length) return [];
  const { data, error } = await admin.rpc('fn_taxonomy_trades_for', { p_slugs: [trade] });
  const codes = new Set(!error && Array.isArray(data) ? data.map(String) : [trade]);
  return keys.filter((k) => codes.has(k.split('.')[0]));
}

/** The insert columns: service_keys only when the state named some (so NULL keeps meaning "never derived"). */
export const serviceKeyCols = (keys: string[]): { service_keys?: string[] } => (keys.length ? { service_keys: keys } : {});
