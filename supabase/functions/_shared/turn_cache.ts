// turn_cache.ts - one read of a key per request (it_engineer, 10 Nov 2026, channels audit R7). A function that reads the same
// app_secrets setting many times in one request (wa_inbound: wa_autoreply_enabled from the classification, the speculation, the
// menu and the send; twilio_wa_from for every row) wraps its request in withTurnCache, and its reader in perTurn: inside a
// request each key is read once and the answer shared; outside one (a module-level caller, a test) it reads as before. Per
// request and never across requests, so a changed setting is seen by the next one. A failed read is not kept.
// prevented by: wa_inbound/a_turn_reads_each_setting_once_and_a_forgery_claims_nothing.test.ts
import { AsyncLocalStorage } from 'node:async_hooks';

const store = new AsyncLocalStorage<Map<string, Promise<string>>>();

/** Run `work` with its own cache: every perTurn reader called inside it shares one answer per key. */
export function withTurnCache<T>(work: () => Promise<T>): Promise<T> { return store.run(new Map(), work); }

/** `read`, answered once per key inside a withTurnCache request. */
export function perTurn(read: (k: string) => Promise<string>): (k: string) => Promise<string> {
  return async (k: string) => {
    const seen = store.getStore();
    if (!seen) return await read(k);
    let p = seen.get(k);
    if (!p) { p = read(k); seen.set(k, p); p.catch(() => seen.delete(k)); }
    return await p;
  };
}
