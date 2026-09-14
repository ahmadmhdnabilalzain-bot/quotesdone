// scripts/e2e/portal_cold_first_load.mjs — repeats the /me cold-first-load measurement PR #638 used
// (14 Sep 2026: en-desktop p50 10.8s/p95 13.2s against a 2.5s bar, root-caused to 1.45 MB of client
// JS across 16 chunks that Vercel's edge cache evicts from a rarely-hit route after an idle gap).
//
// Method, unchanged from the 14 Sep reading: N idle-gapped RUNS. Each run waits IDLE_MS since the
// last request this process made to QD_SITE, then opens the four MATRIX combos (en/ar x
// desktop/mobile) back to back — only the first combo of a run is genuinely cold, exactly as the
// original reading found ("en-desktop always ran first, fully cold"). shellMs/dataMs come from
// browser.mjs openPortal, the same functions journeys.mjs uses, so a number here is comparable to
// one from the funnel harness.
//
// ONE demo customer (ZZ DEMO / @example.invalid) is created once and reused for every run — creating
// a fresh customer per run would itself warm customer_api/kyc, which is not what this measures.
//
// Usage: QD_SITE=https://<preview>.vercel.app node scripts/e2e/portal_cold_first_load.mjs [runs] [idleMinutes]
import { openRun, closeRun, makeDemoCustomer } from './fixtures.mjs';
import { signedInPage, openPortal, portalUrl, launch } from './browser.mjs';
import { MATRIX } from './journeys.mjs';

const RUNS = Number(process.argv[2] || 5);
const IDLE_MS = Number(process.argv[3] || 16) * 60_000;

const q50 = (a) => a.slice().sort((x, y) => x - y)[Math.floor((a.length - 1) * 0.5)];
const q95 = (a) => a.slice().sort((x, y) => x - y)[Math.floor((a.length - 1) * 0.95)];

async function main() {
  const run = await openRun({ tag: 'coldload' });
  const results = {}; // "en-desktop" -> { shellMs: [], dataMs: [] }
  for (const m of MATRIX) results[`${m.lang}-${m.viewport}`] = { shellMs: [], dataMs: [] };
  try {
    const cust = await makeDemoCustomer(run, { locale: 'en', label: 'ColdLoad' });
    const browser = await launch();
    try {
      for (let i = 0; i < RUNS; i++) {
        if (i > 0) { console.log(`idling ${IDLE_MS / 60000} min before run ${i + 1}/${RUNS}...`); await new Promise((r) => setTimeout(r, IDLE_MS)); }
        for (const m of MATRIX) {
          const s = await signedInPage(browser, cust, m);
          try {
            const t = await openPortal(s.page, portalUrl('customer', m.lang), s.calls);
            const key = `${m.lang}-${m.viewport}`;
            results[key].shellMs.push(t.shellMs); results[key].dataMs.push(t.dataMs);
            console.log(`run ${i + 1} ${key}: shellMs=${t.shellMs} dataMs=${t.dataMs} calls=${t.calls}`);
          } finally { await s.ctx.close(); }
        }
      }
    } finally { await browser.close(); }
  } finally {
    await closeRun(run);
  }
  console.log('\n=== SUMMARY (p50/p95, ms) ===');
  const summary = {};
  for (const [key, r] of Object.entries(results)) {
    summary[key] = { shell_p50: q50(r.shellMs), shell_p95: q95(r.shellMs), data_p50: q50(r.dataMs), data_p95: q95(r.dataMs), n: r.shellMs.length };
    console.log(key, JSON.stringify(summary[key]));
  }
  console.log('\nJSON:', JSON.stringify(summary));
}

main().catch((e) => { console.error(e); process.exit(1); });
