// THE CUSTOMER OVERVIEW'S SIX READS START AT HTML PARSE AND RUN IN THE DATABASE'S REGION.
//
// The nightly journey and the post-merge smoke failed "[a customer] overview data under 2.5 s" on all
// four locales from 18 to 21 Sep 2026 (~40 times each). Two causes, stacked:
//   1. the six reads waited for the client bundle (a React effect queue) — fixed by BootPrefetch.tsx
//      (#731), which starts them from an inline script at HTML parse;
//   2. each read then ran in the edge region nearest the CALLER while the database is in
//      ap-southeast-1, so every serial auth/DB hop inside the function crossed an ocean (US-runner p50
//      1.5-3.5 s per call) — fixed by supaEnv.ts fnUrl(), which pins the region.
// This check fails if either comes back: a read issued anywhere but the parse-time script and the
// region-pinned call(), or a URL without the pin. Comments are stripped before matching, so the
// explanation in these files cannot satisfy it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const code = (p) => readFileSync(root + p, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
const SIX = [['kyc', 'state'], ['customer_api', 'my_inquiries'], ['customer_portal', 'overview'], ['project_api', 'dashboard'], ['messages_api', 'threads'], ['customer_portal', 'decision_support']];

test('fnUrl pins every call to the database region (ap-southeast-1)', () => {
  const s = code('src/lib/supaEnv.ts');
  assert.match(s, /export const FN_REGION = 'ap-southeast-1';/);
  assert.match(s, /export const fnUrl = \(name: string\) => `\$\{SUPA_FN\}\/\$\{name\}\?forceFunctionRegion=\$\{FN_REGION\}`;/);
});

test('/me renders the parse-time prefetch BEFORE the portal', () => {
  assert.match(code('src/app/[locale]/me/page.tsx'), /<BootPrefetch \/>\s*<CustomerPortal \/>/);
});

test('the parse-time script issues all six reads, region-pinned', () => {
  const s = code('src/components/me/BootPrefetch.tsx');
  assert.match(s, /fetch\(F\+'\/'\+p\+'\?forceFunctionRegion='\+R,/, 'the boot fetch must carry the region pin');
  assert.match(s, /R=\$\{lit\(region\)\}/);
  assert.match(s, /BOOT\(SUPA_FN, FN_REGION\)/);
  for (const [fn, action] of SIX) assert.ok(s.includes(`g('${fn}',{action:'${action}'`), `boot script lost ${fn}:${action}`);
});

test("the portal's own reads go through the region-pinned call(), warmed beside kyc, not behind it", () => {
  const s = code('src/components/me/CustomerPortal.tsx');
  // The subject here is the REGION PIN, not the shape of the function. This pinned the whole
  // one-line body, so it went red on 22 Sep 2026 when call() grew an AbortController and a JSON
  // parse guard (CP-08) while still fetching fnUrl(path). It now asserts the property: the portal's
  // shared helper is declared, and the URL it fetches is the pinned one.
  assert.match(s, /async function call\(path, body, token\) \{/);
  assert.match(s, /await fetch\(fnUrl\(path\),/);
  assert.doesNotMatch(s, /\bSUPA_FN\b|FN \+ '\//, 'an unpinned functions URL is back in CustomerPortal');
  for (const [fn, action] of SIX) assert.match(s, new RegExp(`warm\\(tk, '\\w+', \\(\\) => call\\('${fn}', \\{ action: '${action}'`), `warmDashboard lost ${fn}:${action}`);
});

test('DecisionSupport falls back to the region-pinned URL', () => {
  const s = code('src/components/portal/twin/DecisionSupport.tsx');
  assert.match(s, /fetch\(fnUrl\('customer_portal'\)/);
  assert.doesNotMatch(s, /\$\{SUPA_FN\}\/customer_portal/);
});
