// THE DASHBOARD'S FIRST READS START WITH THE KYC GATE, NOT AFTER IT.
//
// Measured on quotesdone.ae/me in the founder's session, 14 Sep 2026, with the Resource Timing API:
// kyc started at 397 ms and took 1,674 ms, and only when it returned (t = 2,087 ms) did the five
// dashboard calls start — customer_portal overview and decision_support, customer_api my_inquiries,
// project_api dashboard, messages_api threads — each 747–1,534 ms. The data appeared at about 3.6 s,
// 1.7 s of it the serial gate. None of those reads depends on the answer kyc gives: kyc decides only
// WHETHER the dashboard renders, never what it asks for.
//
// So Authed starts them beside kyc (warm) and the dashboard's first load takes the in-flight promise
// (take) instead of issuing the request again. A promise is handed out ONCE and only to the same
// token that started it: every later refresh, and a customer whose profile turned out incomplete,
// asks the server fresh, so nothing stale can be shown twice.
import { HEDGE_MS } from '@/lib/fetchRetry';

type Entry = { token: string; p: Promise<unknown> };
const inflight = new Map<string, Entry>();

// ONE STEP FURTHER UP: BootPrefetch.tsx issues the same six reads from an inline script when the
// HTML is parsed, so they overlap the 1.35 MB bundle download instead of waiting behind it (18 Sep
// 2026 — see that file for the measurement). Same rules as `inflight`: a promise belongs to the
// token that started it, and is handed out exactly once, so a refresh or a second customer asks the
// server fresh. A boot promise that REJECTED (the network, not a 401) falls back to `run()`; a 401
// BODY is passed through untouched, because Authed.load()'s refresh-once path is what must see it.
function boot(token: string, key: string): Promise<unknown> | null {
  try {
    const b = (globalThis as unknown as { __qdBoot?: { token: string; m: Record<string, Promise<unknown>> } }).__qdBoot;
    const p = b && b.token === token ? b.m[key] : null;
    if (!p) return null;
    delete b!.m[key];
    return p;
  } catch (_e) { return null; }
}

// A BOOT READ THAT STALLS IS ASKED AGAIN (11 Nov 2026, it_engineer). The boot script's fetch has no timeout and no retry, so
// a kyc 'state' that sits on the edge the way one did for 43.8 s before kyc's handler ran (handler 256 ms;
// docs/reports/2026-11-11-kyc-slow-requests.md) would hold the account gate for as long. For the cheap reads the portal hedges anyway (fetchRetry HEDGE_MS: kyc state, the
// project dashboard), no answer from the boot read after HEDGE_MS starts `run()`, and whichever answers first is taken.
// Prevented by: scripts/checks/a_stalled_registration_read_is_asked_again.test.mjs
const HEDGED_KEYS = new Set(['kyc', 'pd']);
export function bootOrAgain(b: Promise<unknown>, run: () => Promise<unknown>, hedgeMs: number): Promise<unknown> {
  if (!(hedgeMs > 0)) return b.catch(() => run());
  return new Promise((resolve, reject) => {
    let done = false; let again: Promise<unknown> | null = null;
    const askAgain = () => {
      if (again) return;
      again = run();
      again.then((v) => { if (!done) { done = true; resolve(v); } }, (e) => { if (!done) { done = true; reject(e); } });
    };
    const timer = setTimeout(askAgain, hedgeMs);
    b.then((v) => { clearTimeout(timer); if (!done) { done = true; resolve(v); } }, () => { clearTimeout(timer); askAgain(); });
  });
}

export function warm(token: string, key: string, run: () => Promise<unknown>): void {
  if (!token || inflight.get(key)?.token === token) return;
  const b = boot(token, key);
  const p = b ? bootOrAgain(b, run, HEDGED_KEYS.has(key) ? HEDGE_MS : 0) : run();
  p.catch(() => {}); // an unhandled rejection before anyone takes it is noise, not a signal
  inflight.set(key, { token, p });
}

// A customer sent to the profile gate instead: what was warmed was asked before the profile existed.
export function drop(): void { inflight.clear(); }

export function take<T = unknown>(token: string, key: string, run: () => Promise<T>): Promise<T> {
  const e = inflight.get(key);
  inflight.delete(key);
  return e && e.token === token ? (e.p as Promise<T>) : run();
}
