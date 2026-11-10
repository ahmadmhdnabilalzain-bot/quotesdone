// EVERY BROWSER CALL TO AN EDGE FUNCTION, AND EVERY SERVER HOP TO A PORTAL FUNCTION, RUNS IN THE DATABASE REGION.
//
// 28 Sep 2026, it_engineer (#1038). kyc p95 was 9,767 ms against 2,500. agent_runs fn:kyc, 7 days, p95 by the region
// that served the call: ap-southeast-1 359 | ap-south-1 8,797 | us-east-1 14,667 | us-west-1 15,711. Supabase runs a
// function in the region nearest the CALLER, the database is in ap-southeast-1, and each call makes several serial
// hops. supaEnv.ts fnUrl() pins the region, but 15 src files still built `${SUPA_FN}/name`, `FN + '/name'` or
// `${SUPA_URL}/functions/v1/name` by hand (projects, documents, approvals, predict, spatial, twin, the contact and
// complaint forms, the chat widget, public_site), and resilience_ping warmed the portal functions unpinned, so it
// kept isolates warm in whatever region it landed in rather than the one the portal uses.
// This fails if any src file outside supaEnv.ts / BootPrefetch.tsx builds a functions URL without fnUrl(), or a
// named server-side caller loses its pin. Comments are stripped before matching.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
const code = (p) => strip(readFileSync(root + p, 'utf8'));
const walk = (d) => readdirSync(root + d).flatMap((f) => {
  const p = `${d}/${f}`;
  return statSync(root + p).isDirectory() ? walk(p) : (/\.(ts|tsx)$/.test(f) && !/\.test\./.test(f) ? [p] : []);
});
const ALLOWED = new Set(['src/lib/supaEnv.ts', 'src/components/me/BootPrefetch.tsx']);
// Not a function call from a portal page: server routes that proxy to non-portal functions.
const SERVER_ROUTES = /^src\/(app\/api\/|app\/u\/|instrumentation\.ts)/;

test('no src file builds an unpinned functions URL', () => {
  const bad = walk('src').filter((f) => !ALLOWED.has(f) && !SERVER_ROUTES.test(f)).filter((f) => {
    const s = code(f);
    return /\$\{SUPA_FN\}\/|\bFN \+ '\/|\/functions\/v1\/[a-z_]+`/.test(s);
  });
  assert.deepEqual(bad, [], 'build these URLs with fnUrl() from src/lib/supaEnv.ts');
});

test('the server-side callers of portal functions carry the pin', () => {
  for (const [f, needle] of [
    ['supabase/functions/resilience_ping/index.ts', "FN + '/' + fn + '?forceFunctionRegion=ap-southeast-1'"],
    ['supabase/functions/rfq_flag/index.ts', '/functions/v1/messages_api?forceFunctionRegion=ap-southeast-1'],
    ['supabase/functions/_shared/reasoned_delivery.ts', '/functions/v1/supplier_api?forceFunctionRegion=ap-southeast-1'],
    ['scripts/lib/demo_factory.mjs', '/functions/v1/${slug}?forceFunctionRegion=ap-southeast-1'],
  ]) assert.ok((f === 'supabase/functions/resilience_ping/index.ts' ? strip(functionSource('resilience_ping')) : code(f)).includes(needle), `${f} must call with ${needle}`);
});
