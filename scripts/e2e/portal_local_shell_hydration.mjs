// scripts/e2e/portal_local_shell_hydration.mjs — isolates the JS-payload/hydration component of the
// /me cold-first-load fix from Vercel's CDN cache state, which this local `next start` server has
// none of (no PoP, no eviction). Every browser context is fresh (browser.mjs's signedInPage, no
// disk/HTTP cache reuse), so every run here already measures the worst case for hydration cost —
// what changes between BEFORE and AFTER is only the size/count of what has to parse before the nav
// renders. It reads real customer data from the ONE production Supabase project (the fallback
// src/lib/supaEnv.ts uses when NEXT_PUBLIC_SUPABASE_URL is unset and VERCEL_ENV isn't 'preview' —
// exactly this process's env), through a ZZ DEMO / @example.invalid fixture, read-only after setup.
//
// This does NOT reproduce the CDN-cache-eviction root cause (see the PR description for that,
// verified separately with curl against quotesdone.com's X-Vercel-Cache headers) — it reproduces the
// other half of the causal chain this PR's fix actually changed: how much JS has to run before the
// nav is visible.
import { openRun, closeRun, makeDemoCustomer } from './fixtures.mjs';
import { signedInPage, openPortal, launch } from './browser.mjs';
import { MATRIX } from './journeys.mjs';

const PORT = process.env.QD_LOCAL_PORT || 3100;
const SITE = `http://localhost:${PORT}`;
const RUNS = Number(process.argv[2] || 5);
const portalUrl = (lang) => `${SITE}${lang === 'ar' ? '/ar' : ''}/me`;

const q50 = (a) => a.slice().sort((x, y) => x - y)[Math.floor((a.length - 1) * 0.5)];
const q95 = (a) => a.slice().sort((x, y) => x - y)[Math.floor((a.length - 1) * 0.95)];

async function main() {
  const run = await openRun();
  const results = {};
  for (const m of MATRIX) results[`${m.lang}-${m.viewport}`] = { shellMs: [], dataMs: [] };
  try {
    const cust = await makeDemoCustomer(run, { locale: 'en', label: 'LocalHydration' });
    const browser = await launch();
    try {
      for (let i = 0; i < RUNS; i++) {
        for (const m of MATRIX) {
          const s = await signedInPage(browser, cust, m);
          try {
            const t = await openPortal(s.page, portalUrl(m.lang), s.calls);
            const key = `${m.lang}-${m.viewport}`;
            results[key].shellMs.push(t.shellMs); results[key].dataMs.push(t.dataMs);
            console.log(`run ${i + 1} ${key}: shellMs=${t.shellMs} dataMs=${t.dataMs} calls=${t.calls} errs=${JSON.stringify(s.consoleErrors.slice(0, 2))}`);
          } finally { await s.ctx.close(); }
        }
      }
    } finally { await browser.close(); }
  } finally {
    await closeRun(run);
  }
  const summary = {};
  for (const [key, r] of Object.entries(results)) summary[key] = { shell_p50: q50(r.shellMs), shell_p95: q95(r.shellMs), data_p50: q50(r.dataMs), data_p95: q95(r.dataMs), n: r.shellMs.length };
  console.log('JSON:', JSON.stringify(summary));
}

main().catch((e) => { console.error(e); process.exit(1); });
