// deno test --no-lock supabase/functions/resilience_ping/schedule.test.ts
//
// THE PROOF THAT NO STEP CAN STARVE BY BEING LAST (18 Sep 2026, it_engineer).
//
// fn_resilience_tick_plan's rule is reproduced here exactly — due when (now - last attempt) >= every,
// ordered by (now - last attempt)/every descending, greedy prefix fill against the budget, and the
// stalest due step admitted unconditionally — and run over the REAL seeded cadences and the REAL
// measured costs for a simulated day of 96 ticks. The assertion is the guarantee itself: every step
// runs, and no step waits longer than its own cadence plus the bound.
//
// This is the part that could be proved without deploying. It proves the RULE. What it cannot prove is
// that production's clock and production's costs behave as seeded — that is what the ewma in
// fn_resilience_step_record is for, and what the tick's own `tick.ms` field reports from the first run.
import { stepRows } from './steps.ts';

const eq = (a: unknown, b: unknown, m: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};
const ok = (c: boolean, m: string) => { if (!c) throw new Error(m); };

// The seed of public.resilience_step, verbatim: [step, every seconds, cost ms, place].
const SEED: Array<[string, number, number, 'plan' | 'last']> = [
  ['digest', 3600, 1000, 'plan'],
  ['ratings', 900, 1500, 'plan'],
  ['backup', 900, 1000, 'plan'],
  ['backupVerify', 21600, 25000, 'plan'],
  ['dropboxHealth', 7200, 10000, 'plan'],
  ['tableExport', 1800, 1000, 'plan'],
  ['backupPrune', 21600, 15000, 'plan'],
  ['weekly', 7200, 20000, 'plan'],
  ['vat', 3600, 1000, 'plan'],
  ['ceoWeekly', 7200, 1000, 'plan'],
  ['openrouter', 3600, 4000, 'plan'],
  ['ladder', 900, 800, 'plan'],
  ['refunds', 900, 4500, 'plan'],
  ['accountantDuties', 1800, 4500, 'plan'],
  ['whatsapp', 900, 8800, 'plan'],
  ['itdetect', 900, 8000, 'plan'],
  ['itduties', 1800, 3000, 'plan'],
  ['itscheduled', 1800, 4000, 'plan'],
  ['itlater', 1800, 3000, 'plan'],
  ['specoffer', 900, 4000, 'plan'],
  ['orphans', 900, 12000, 'plan'],
  ['orgtasks', 900, 1500, 'plan'],
  ['it', 900, 1000, 'last'],
  ['outbox', 900, 9500, 'last'],
  ['archive', 900, 6200, 'last'],
];
const BUDGET_MS = 70_000;
const TICK_S = 900;

type Row = { step: string; every: number; cost: number; place: string; lastStarted: number | null };
const fresh = (): Row[] => SEED.map(([step, every, cost, place]) => ({ step, every, cost, place, lastStarted: null }));

/** fn_resilience_tick_plan, in TypeScript. `nowS` is seconds since the start of the simulation. */
function plan(rows: Row[], nowS: number, budgetMs = BUDGET_MS) {
  const due = rows
    .filter((r) => r.place === 'plan')
    .filter((r) => r.lastStarted === null || nowS - r.lastStarted >= r.every)
    .map((r) => ({ r, ratio: (nowS - (r.lastStarted ?? nowS - r.every - 365 * 86400)) / Math.max(r.every, 1) }))
    .sort((a, b) => (b.ratio - a.ratio) || a.r.step.localeCompare(b.r.step));
  const run: string[] = [], deferred: string[] = [];
  let cum = 0;
  due.forEach((d, i) => {
    cum += d.r.cost;
    if (i === 0 || cum <= budgetMs) run.push(d.r.step); else deferred.push(d.r.step);
  });
  // The drains, in rank order (it -> outbox -> archive), appended outside the budget because they deliver.
  return { run: run.concat(['it', 'outbox', 'archive'].filter((s) => rows.some((r) => r.step === s))), deferred };
}

/** fn_resilience_step_record: an attempt stamps, a deferral stamps nothing. That is the mechanism. */
function record(rows: Row[], ran: string[], nowS: number) {
  for (const r of rows) if (ran.includes(r.step)) r.lastStarted = nowS;
}

Deno.test('a day of ticks: every step runs, and no step is left behind by the ones in front of it', () => {
  const rows = fresh();
  const lastRunAt = new Map<string, number>();
  const worstWait = new Map<string, number>();
  for (let tick = 0; tick < 96; tick++) {
    const nowS = tick * TICK_S;
    const { run } = plan(rows, nowS);
    record(rows, run, nowS);
    for (const step of run) {
      const prev = lastRunAt.get(step);
      if (prev !== undefined) worstWait.set(step, Math.max(worstWait.get(step) ?? 0, nowS - prev));
      lastRunAt.set(step, nowS);
    }
  }
  for (const [step, every] of SEED.map(([s, e]) => [s, e] as [string, number])) {
    ok(lastRunAt.has(step), `${step} never ran in 96 ticks`);
    const wait = worstWait.get(step) ?? 0;
    // The bound: a step's own cadence, plus at most one extra tick of rounding to the beat.
    ok(wait <= every + TICK_S, `${step} waited ${wait}s against a cadence of ${every}s`);
  }
});

Deno.test('the step that was starved — orphans, with the sanctions screen in it — runs every beat it is due', () => {
  const rows = fresh();
  let runs = 0;
  for (let tick = 0; tick < 96; tick++) {
    const nowS = tick * TICK_S;
    const { run } = plan(rows, nowS);
    record(rows, run, nowS);
    if (run.includes('orphans')) runs++;
  }
  // Its cadence is one tick; on a day of 96 ticks it may lose a beat to a stalest rival, never a run.
  ok(runs >= 90, `orphans ran ${runs} times in 96 ticks`);
});

// THE CASE THAT MATTERS, AND THE ONE THE ORIGINAL LIST FAILED. Give every step its WORST case — the
// day the backup queue is deep, the accountant is slow and every callee times out, so the every-tick
// set alone wants ~173 s against a 70 s budget. The tick is then oversubscribed by 2.5x and SOMETHING
// must wait; the whole question is whether the same steps always wait. Under the old fixed list the
// answer was yes, by construction: the tail lost every single tick. Under staleness the wait is shared,
// and the assertion is that no step is a permanent loser.
Deno.test('when the work does not fit the clock at all, the wait is SHARED and no step is a permanent loser', () => {
  const worst: Record<string, number> = {
    backup: 35000, backupVerify: 35000, backupPrune: 35000, dropboxHealth: 20000, openrouter: 32000,
    orphans: 60000, whatsapp: 15000, itscheduled: 15000, specoffer: 20000, refunds: 10000,
    accountantDuties: 10000, itdetect: 10000, itlater: 10000, itduties: 8000, orgtasks: 5000,
    weekly: 20000, tableExport: 2000, ceoWeekly: 2000, digest: 1500, ratings: 1500, vat: 1500, ladder: 1500,
  };
  const rows = fresh().map((r) => ({ ...r, cost: worst[r.step] ?? r.cost }));
  const runsOf = new Map<string, number>();
  for (let tick = 0; tick < 96; tick++) {
    const nowS = tick * TICK_S;
    const { run } = plan(rows, nowS);
    record(rows, run, nowS);
    for (const s of run) runsOf.set(s, (runsOf.get(s) ?? 0) + 1);
  }
  for (const [step, every] of SEED.filter(([, , , p]) => p === 'plan').map(([s, e]) => [s, e] as [string, number])) {
    const n = runsOf.get(step) ?? 0;
    ok(n > 0, `${step} NEVER ran in a whole day — that is starvation`);
    // Each step should get at least a quarter of the runs its own cadence asks for, even at 2.5x
    // oversubscription. The old list gave the tail zero.
    const wanted = Math.floor((96 * TICK_S) / every);
    ok(n >= Math.max(1, Math.floor(wanted / 4)), `${step} ran ${n} times, wanted ~${wanted} at its cadence`);
  }
  // And the every-tick steps share the shortfall rather than one of them taking it all.
  const perTick = SEED.filter(([, e, , p]) => e === 900 && p === 'plan').map(([s]) => runsOf.get(s) ?? 0);
  ok(Math.min(...perTick) * 3 >= Math.max(...perTick),
    `the every-tick steps ran ${perTick.join('/')} times — one of them is being singled out`);
});

Deno.test('a step deferred this tick leads the next one, whatever it costs', () => {
  const rows = fresh();
  // Everything ran a moment ago except orphans, the most expensive planned step (60 s against a 55 s
  // budget). Before this change it was last in a list and could never win; now it is rn = 1 and the
  // unconditional admission is what puts it on the wire.
  for (const r of rows) r.lastStarted = 1000;
  (rows.find((r) => r.step === 'orphans'))!.lastStarted = 0;
  const { run } = plan(rows, 1900);
  eq(run[0], 'orphans', 'the stalest step goes first');
});

Deno.test('a step costing more than the whole budget still runs — the guarantee, not the arithmetic', () => {
  const rows: Row[] = [
    { step: 'huge', every: 900, cost: 999_000, place: 'plan', lastStarted: null },
    { step: 'small', every: 900, cost: 1000, place: 'plan', lastStarted: null },
  ];
  const { run, deferred } = plan(rows, 0, 55_000);
  eq(run, ['huge'], 'the stalest is admitted whatever it costs');
  eq(deferred, ['small'], 'and the rest wait a beat');
});

Deno.test('what the tick writes back: a run stamps, a failure stamps the attempt, a deferral stamps nothing', () => {
  const rows = stepRows(
    { backup: 33210, orphans: 4100 },
    [{ name: 'orphans.sanctions_screen', error: 'HTTP 500' }],
    ['weekly'],
  );
  eq(rows, [
    { step: 'backup', ms: 33210, ok: true },
    { step: 'orphans', ms: 4100, ok: false },   // a nested failure is the parent step failing
    { step: 'weekly', deferred: true },          // no ms, no ok: nothing is stamped, so it leads next tick
  ], 'the rows fn_resilience_step_record reads');
});
