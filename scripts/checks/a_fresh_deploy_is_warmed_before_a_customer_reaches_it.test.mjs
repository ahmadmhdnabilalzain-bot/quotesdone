// A FRESH DEPLOY IS WARMED BEFORE A CUSTOMER REACHES IT (22 Sep 2026).
//
// After merge 4fb90cd redeployed all six customer-overview functions, the post-deploy smoke measured the
// overview at 4,947 ms (en-desktop) and 3,412 ms (ar-desktop) against a 2.5 s budget: the first calls to
// a just-deployed bundle wait ~3 s for it to reach a worker (measurements in scripts/lib/warm_functions.mjs).
// Proved on production at 06:46Z the same day: keep-warm calls to the five functions, redeployed a minute
// earlier, took 3,126-3,787 ms in their first round and 242-478 ms by the second; a ZZ DEMO customer's
// overview then answered in 753 ms on its first load.
// This fails if the deploy stops warming, or if an overview function stops answering the keep-warm
// header (it would then be skipped, and the first customer after a deploy would pay the cold start again).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { warmable, warmFunctions, WARM_REGION } from '../lib/warm_functions.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const source = (s) => read(`supabase/functions/${s}/index.ts`);

test('every function the customer overview reads at sign-in answers the keep-warm header', () => {
  const boot = read('src/components/me/BootPrefetch.tsx');
  const fns = [...new Set([...boot.matchAll(/g\('([a-z_]+)',\{action:/g)].map((m) => m[1]))];
  assert.ok(fns.length >= 5, `BootPrefetch lists ${fns.length} overview functions; expected the five`);
  assert.deepEqual(warmable(fns, source).sort(), fns.sort(), 'an overview function no longer answers x-qd-warm, so a deploy would leave it cold');
});

test('a mention in a comment does not make a function warmable', () => {
  const src = "// if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });\nDeno.serve(() => new Response('real work'));";
  assert.deepEqual(warmable(['x'], () => src), []);
  assert.deepEqual(warmable(['gone'], () => { throw new Error('no such file'); }), []);
});

test('the deploy warms what it deployed, after the read-back verified it', () => {
  const d = read('scripts/deploy_functions.mjs');
  const good = d.indexOf("console.log('ALL GOOD')");
  const warm = d.indexOf('await warmFunctions(');
  assert.ok(good > 0 && warm > good, 'deploy_functions.mjs must call warmFunctions after ALL GOOD');
  assert.match(d.slice(good), /warmable\(slugs,/);
});

test('warmFunctions calls each slug in the database region with the keep-warm header, in parallel rounds', async () => {
  const seen = [];
  const fake = async (url, init) => { seen.push({ url, h: init.headers }); return { status: 204, body: null }; };
  const out = await warmFunctions({ url: 'https://x.supabase.co', anon: 'a', slugs: ['kyc', 'customer_api'], rounds: 2, fanout: 3, gapMs: 0, fetchImpl: fake });
  assert.equal(seen.length, 12);
  assert.ok(seen.every((c) => c.url.endsWith(`?forceFunctionRegion=${WARM_REGION}`) && c.h['x-qd-warm'] === '1'));
  assert.equal(WARM_REGION, 'ap-southeast-1');
  assert.deepEqual(Object.fromEntries(Object.entries(out).map(([k, v]) => [k, [v.ok, v.calls, v.slowest_ms.length]])), { kyc: [6, 6, 2], customer_api: [6, 6, 2] });
});
