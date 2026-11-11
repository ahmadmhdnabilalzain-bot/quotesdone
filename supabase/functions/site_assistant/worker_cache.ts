// WHAT EVERY TURN READ AGAIN, READ ONCE A MINUTE PER WORKER (it_engineer, 11 Nov 2026, load test, founder ruling 1622).
//
// Measured on production, 11 Nov 2026 01:26-01:30 UTC (50 concurrent website chats, the model stubbed): two site_assistant
// workers were killed with "CPU Time exceeded" (function_logs Shutdown reason CPUTime, cpu_time_used 2,002 and 2,007 ms)
// and every request they held came back HTTP 546 WORKER_RESOURCE_LIMIT (11 of 139 turns). The runtime's CPU budget is per
// WORKER, not per request: the other 17 workers of the run were retired (EarlyDrop) at 1,097-1,938 ms after 5-12 turns
// each, i.e. 145-215 ms of CPU per turn. Every turn read, before any answer:
//   - the whole published FAQ, 302 rows (~170 KB of JSON) — used only when the per-worker brief (company_brief.ts,
//     BRIEF_TTL_MS = 5 min) has expired, so on almost every turn it was read, decoded, parsed and thrown away;
//   - the seven widget limits from app_secrets, and the gateway credential, two more reads.
// A local CPU profile (the real site_assistant on a fake Supabase, 30 turns) put the FAQ read alone (PostgREST
// processResponse + decode) at 7% of all JS time. These three now come from this cache: one read per worker per TTL, shared
// by every turn in flight (the promise is shared, so twelve turns arriving together cause one read, not twelve).
// A failed or empty read is NOT kept, so the next turn reads again; nothing here changes what a turn decides.
// Freshness: an FAQ edit reaches the brief within FAQ_TTL_MS + BRIEF_TTL_MS (was BRIEF_TTL_MS); a limit within LIMITS_TTL_MS.
// prevented by: site_assistant/worker_cache.test.ts

export const FAQ_TTL_MS = 60_000;
export const LIMITS_TTL_MS = 60_000;

/** One shared read per `ms`. `keep(v)` says whether a result may be kept (a failed or empty read is not). */
export function ttlMemo<T>(ms: number, load: () => Promise<T>, keep: (v: T) => boolean = (v) => v != null, clock: () => number = Date.now): () => Promise<T> {
  let held: { at: number; p: Promise<T> } | null = null;
  return () => {
    const now = clock();
    if (held && now - held.at < ms && now >= held.at) return held.p;
    const mine = { at: now, p: load() };
    held = mine;
    // forget a read that failed or came back empty, unless a newer read already replaced it
    mine.p.then((v) => { if (!keep(v) && held === mine) held = null; }, () => { if (held === mine) held = null; });
    return mine.p;
  };
}
