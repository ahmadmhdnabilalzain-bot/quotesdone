// How resilience_ping runs its ticks: in order, each on its own, inside a deadline, and with every
// failure named. Pure, so the rules are tested without a network (steps.test.ts).
//
// WHY. Measured 15 Sep 2026: every tick swallowed its error and the endpoint answered ok:true, so the
// accountant's duties answered HTTP 401 on every pass (151 refusals at the gateway in 24 hours) and
// nothing anywhere said so. A step that fails is now returned in `failing` and raised as an IT engineer
// finding by the handler; one step failing never stops the next.
export type Step = { name: string; run: () => Promise<unknown>; always?: boolean; nested?: boolean };
export type Failure = { name: string; error: string };

// What counts as a failed step: it threw, it answered {ok:false, error}, or its HTTP call answered 4xx/5xx.
// A seat answering {ok:false} WITHOUT an error string has already reported its own partial failure
// (fn_accountant_duties stages each failed duty as its own finding), so it is not counted twice.
export function failureOf(r: unknown): string | null {
  if (!r || typeof r !== 'object') return null;
  const o = r as Record<string, unknown>;
  if (o.ok === false && typeof o.error === 'string') return o.error.slice(0, 300);
  if (typeof o.status === 'number' && o.status >= 400) return 'HTTP ' + o.status;
  return null;
}

// Runs every step in order. A step not started by `deadlineMs` after `t0` is skipped and counted as
// failing, unless it is `always` (the mail drains: skipping them would hold a message a whole beat).
export async function runSteps(steps: Step[], t0: number, deadlineMs: number, now: () => number = Date.now) {
  const results: Record<string, unknown> = {};
  const failing: Failure[] = [];
  for (const s of steps) {
    if (!s.always && now() - t0 > deadlineMs) {
      results[s.name] = { skipped: 'deadline' };
      failing.push({ name: s.name, error: 'not run: the tick passed its ' + Math.round(deadlineMs / 1000) + 's deadline' });
      continue;
    }
    let r: unknown;
    try { r = await s.run(); } catch (e) { r = { ok: false, error: String((e as Error)?.message || e) }; }
    results[s.name] = r;
    if (s.nested && r && typeof r === 'object') {
      for (const [k, v] of Object.entries(r as Record<string, unknown>)) {
        const f = failureOf(v);
        if (f) failing.push({ name: s.name + '.' + k, error: f });
      }
    } else {
      const f = failureOf(r);
      if (f) failing.push({ name: s.name, error: f });
    }
  }
  return { results, failing };
}
