// stripe_setup/webhook_plan.ts — the decisions stripe_setup makes about Stripe webhook endpoints and its
// own token, kept pure so each rule is tested alone (webhook_plan.test.ts). 14 Sep 2026, agent: accountant.
//
// Independent security review of #631 (14 Sep 2026) asked for three things, all here:
//   * ONE matcher for "our endpoint", used by webhook_status, webhook_sync and webhook_ensure alike;
//   * for LIVE, never create a second endpoint and never write stripe_webhook_secret: an existing live
//     endpoint is only synced additively, and a live endpoint whose secret is not stored is refused
//     rather than created or rotated;
//   * a constant-time token comparison.

export const WEBHOOK_URL_SUFFIX = '/functions/v1/stripe_webhook';

// Only our own endpoint is ever touched. A Stripe account can carry endpoints belonging to other
// integrations and silently rewriting one of those would be a genuinely bad day.
// deno-lint-ignore no-explicit-any
export function ours(list: any[]): any[] {
  return (list || []).filter((e) => String(e?.url || '').endsWith(WEBHOOK_URL_SUFFIX));
}

// deno-lint-ignore no-explicit-any
export function drift(ep: any, required: readonly string[]): { missing: string[]; wildcard: boolean } {
  const have = new Set<string>((ep?.enabled_events || []) as string[]);
  const wildcard = have.has('*');
  return { missing: wildcard ? [] : required.filter((e) => !have.has(e)), wildcard };
}

export type EnsurePlan =
  | { kind: 'create'; writesSecret: true }
  // deno-lint-ignore no-explicit-any
  | { kind: 'sync'; endpoint: any; missing: string[]; writesSecret: false }
  // deno-lint-ignore no-explicit-any
  | { kind: 'in_sync'; endpoint: any; writesSecret: false }
  | { kind: 'refuse'; reason: string; writesSecret: false };

/**
 * What webhook_ensure may do. Only a TEST account with no endpoint of ours gets one created, and only
 * then is a signing secret written. Everything else is an additive sync, or a refusal that says why.
 */
export function planWebhookEnsure(a: {
  mode: 'test' | 'live';
  // deno-lint-ignore no-explicit-any
  endpoints: any[];
  required: readonly string[];
  secretStored: boolean;
}): EnsurePlan {
  const mine = ours(a.endpoints);
  if (a.mode === 'live') {
    if (!mine.length) {
      return { kind: 'refuse', writesSecret: false, reason: 'No live endpoint points at stripe_webhook. This action never creates a live endpoint: create it deliberately in the live Stripe account and store its signing secret with the save action.' };
    }
    if (!a.secretStored) {
      return { kind: 'refuse', writesSecret: false, reason: 'The live endpoint exists but stripe_webhook_secret is not stored. This action never rotates or replaces a live signing secret: store the existing one with the save action.' };
    }
  } else if (!mine.length) {
    return { kind: 'create', writesSecret: true };
  }
  if (mine.length > 1) {
    return { kind: 'refuse', writesSecret: false, reason: `${mine.length} endpoints on this account point at stripe_webhook; resolve that in Stripe first rather than let this action guess which is ours.` };
  }
  const ep = mine[0];
  const d = drift(ep, a.required);
  return !d.wildcard && d.missing.length
    ? { kind: 'sync', endpoint: ep, missing: d.missing, writesSecret: false }
    : { kind: 'in_sync', endpoint: ep, writesSecret: false };
}

/**
 * Constant-time equality for the setup token. Both sides are hashed first, so the comparison always
 * walks 32 bytes whatever their lengths, and the loop never exits early.
 */
export async function sameSecret(given: string, expected: string): Promise<boolean> {
  if (!expected) return false;
  const enc = new TextEncoder();
  const [x, y] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(String(given ?? ''))),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ]);
  const a = new Uint8Array(x), b = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Failed token attempts allowed in the window before stripe_setup stops answering. */
export const BAD_TOKEN_LIMIT = 10;
export const BAD_TOKEN_WINDOW_MS = 10 * 60 * 1000;
