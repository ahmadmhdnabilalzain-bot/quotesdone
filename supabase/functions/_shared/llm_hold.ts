// llm_hold — "is the founder's OpenRouter hold on right now?", asked BEFORE the gateway is called.
//
// THE HOLD IS A ROW, NOT A FLAG (measured 22 Sep 2026, htdblwldjkcgjvmqkbeh): all 8 rows of
// public.llm_route_health carry open_until = 2126-08-15 and opened_reason 'HELD BY THE FOUNDER
// 15 Aug 2026: no OpenRouter calls until he releases it. Release with: update llm_route_health
// set open_until = null;'. ai_gateway reads the same rows and refuses every call with
// err='circuit_open'.
//
// WHY A CALLER NEEDS TO ASK FIRST. inquiry_intake called ai_gateway on EVERY intake request under
// the hold and logged the deterministic interview — the designed path, running exactly as built —
// as agent_runs status 'error': 592 rows in 72 h (SEATS-08/CP-14, 22 Sep 2026 audit). A run that is
// working as designed must not be logged as a fault, and a call that cannot be answered must not be
// made. Both need the same one-line answer, and nothing in _shared gave it.
//
// COST: one select of a tiny table, cached per isolate for 60 s. The gateway still enforces the
// hold; this only stops the pointless round trip and the false error.
// ponytail: 60 s cache — a release takes at most a minute to be seen by a warm isolate.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type RouteRow = { open_until: string | null };

/** True when EVERY model route is open (circuit open) — i.e. no route can answer. */
export function heldFromRows(rows: RouteRow[] | null, now: Date = new Date()): boolean {
  if (!rows || rows.length === 0) return false;   // no routes configured is not a hold; let the gateway decide
  return rows.every((r) => r.open_until != null && new Date(r.open_until).getTime() > now.getTime());
}

let _cached: { at: number; held: boolean } | null = null;

/** Is the OpenRouter hold on? Never throws: an unreadable table answers false and the gateway decides. */
export async function modelHeld(admin: Admin, ttlMs = 60_000): Promise<boolean> {
  if (_cached && Date.now() - _cached.at < ttlMs) return _cached.held;
  try {
    const { data, error } = await admin.from('llm_route_health').select('open_until');
    if (error) return false;
    const held = heldFromRows(data as RouteRow[]);
    _cached = { at: Date.now(), held };
    return held;
  } catch (_e) { return false; }
}
