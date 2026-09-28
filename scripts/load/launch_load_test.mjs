#!/usr/bin/env node
// it_engineer — January 2027 launch load test. Plan: docs/it/CAPACITY_PLAN_JANUARY_2027.md
//
// SANDBOX ONLY. This script is built to be INCAPABLE of reaching a real person
// (auditor skill section 8): every identity it generates is "ZZ DEMO — ..." with an
// @example.invalid address, and assertFixture() throws before any request is sent.
//
//   node scripts/load/launch_load_test.mjs                      # --dry-run (default): print the plan
//   QD_LOADTEST=1 QD_LOADTEST_BASE_URL=https://<sandbox-ref>.supabase.co \
//   QD_LOADTEST_KEY=<sandbox anon key> node scripts/load/launch_load_test.mjs --run [--scale=10] [--seconds=60]
//
// Refuses: without QD_LOADTEST=1, without a base URL, or when the base URL is production.
// Reports p50 / p95 / error rate per scenario. Plain Node, no dependencies.

import { pathToFileURL } from 'node:url';

const PRODUCTION_MARKERS = ['htdblwldjkcgjvmqkbeh', 'quotesdone.ae', 'quotesdone.com'];

// Launch baseline (req/min at peak) — derivation in the capacity plan, section 2.
export const SCENARIOS = [
  { name: 'inquiry_intake', method: 'POST', path: '/functions/v1/inquiry_intake', baselinePerMin: 2, sloP95Ms: 3000 },
  { name: 'quote_submit', method: 'POST', path: '/functions/v1/supplier_portal', baselinePerMin: 6, sloP95Ms: 2000 },
  { name: 'portal_read', method: 'POST', path: '/functions/v1/customer_portal', baselinePerMin: 60, sloP95Ms: 800 },
];
export const SLO_MAX_ERROR_RATE = 0.01;

export class Refused extends Error {
  constructor(reason) { super(`load test refused — prevented by: ${reason}`); }
}

export function assertFixture(identity) {
  if (!identity || !String(identity.name).startsWith('ZZ DEMO — ')) {
    throw new Refused(`name "${identity?.name}" is not a "ZZ DEMO — " fixture`);
  }
  if (!/^[^@\s]+@example\.invalid$/i.test(String(identity.email))) {
    throw new Refused(`address "${identity?.email}" is not @example.invalid`);
  }
  return identity;
}

export function assertTarget(env) {
  if (env.QD_LOADTEST !== '1') throw new Refused('QD_LOADTEST is not 1');
  const base = env.QD_LOADTEST_BASE_URL;
  if (!base) throw new Refused('QD_LOADTEST_BASE_URL is not set');
  const hit = PRODUCTION_MARKERS.find((m) => base.toLowerCase().includes(m));
  if (hit) throw new Refused(`base URL is production (${hit})`);
  return base.replace(/\/$/, '');
}

export function makeIdentity(scenario, i) {
  return assertFixture({
    name: `ZZ DEMO — load ${scenario} ${i}`,
    email: `zz-demo-load-${scenario}-${i}@example.invalid`,
  });
}

function body(scenario, id) {
  // Every body carries only the asserted fixture identity; nothing is read from real tables.
  if (scenario === 'inquiry_intake') return { name: id.name, email: id.email, phone: null, message: 'ZZ DEMO — load test inquiry', load_test: true };
  if (scenario === 'quote_submit') return { action: 'quotations.list', email: id.email, load_test: true };
  return { action: 'inquiries.list', email: id.email, load_test: true };
}

const pct = (sorted, p) => (sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))] : 0);

export function summarise(name, samples, sloP95Ms) {
  const ms = samples.map((s) => s.ms).sort((a, b) => a - b);
  const errors = samples.filter((s) => !s.ok).length;
  const errorRate = samples.length ? errors / samples.length : 0;
  const p95 = pct(ms, 0.95);
  return { name, n: samples.length, p50: pct(ms, 0.5), p95, errorRate, pass: p95 <= sloP95Ms && errorRate <= SLO_MAX_ERROR_RATE };
}

export function plan(scale, seconds) {
  return SCENARIOS.map((s) => ({ ...s, perMin: s.baselinePerMin * scale, total: Math.ceil((s.baselinePerMin * scale * seconds) / 60) }));
}

async function runScenario(base, key, s) {
  const samples = [];
  const gapMs = 60000 / s.perMin;
  const inflight = [];
  for (let i = 0; i < s.total; i++) {
    const id = makeIdentity(s.name, i); // throws before send if the fixture rule is ever broken
    const t0 = performance.now();
    inflight.push(
      fetch(base + s.path, {
        method: s.method,
        headers: { 'content-type': 'application/json', apikey: key, authorization: `Bearer ${key}`, 'x-qd-load-test': '1' },
        body: JSON.stringify(body(s.name, id)),
        signal: AbortSignal.timeout(15000),
      })
        .then((r) => samples.push({ ms: performance.now() - t0, ok: r.status < 500 && r.status !== 429 }))
        .catch(() => samples.push({ ms: performance.now() - t0, ok: false })),
    );
    await new Promise((r) => setTimeout(r, gapMs));
  }
  await Promise.all(inflight);
  return summarise(s.name, samples, s.sloP95Ms);
}

async function main(argv, env) {
  const arg = (k, d) => Number((argv.find((a) => a.startsWith(`--${k}=`)) || '').split('=')[1]) || d;
  const scale = arg('scale', 10);
  const seconds = arg('seconds', 60);
  const rows = plan(scale, seconds);
  console.log(`launch load test — ${scale}x baseline for ${seconds}s`);
  for (const r of rows) console.log(`  ${r.name.padEnd(15)} ${String(r.perMin).padStart(5)}/min  ${String(r.total).padStart(5)} requests  SLO p95<=${r.sloP95Ms}ms err<=${SLO_MAX_ERROR_RATE * 100}%`);
  console.log(`  sample identity: ${JSON.stringify(makeIdentity('inquiry_intake', 0))}`);
  if (!argv.includes('--run')) { console.log('dry run — nothing sent. Add --run with QD_LOADTEST=1 to execute against the sandbox.'); return 0; }

  const base = assertTarget(env);
  const key = env.QD_LOADTEST_KEY || '';
  const results = await Promise.all(rows.map((r) => runScenario(base, key, r)));
  for (const r of results) console.log(`  ${r.name.padEnd(15)} n=${r.n} p50=${r.p50.toFixed(0)}ms p95=${r.p95.toFixed(0)}ms err=${(r.errorRate * 100).toFixed(2)}% ${r.pass ? 'PASS' : 'FAIL'}`);
  return results.every((r) => r.pass) ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then((c) => process.exit(c), (e) => { console.error(e.message); process.exit(2); });
}
