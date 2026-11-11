// THE SUPPLIER PORTAL'S FIRST READS START WHEN THE HTML IS PARSED (11 Nov 2026, customer_support). Supplier registration
// certification (ruling 1620), free round, finding 9: the portal home took 2.6 s median and 3.4 s max on desktop against 3 s,
// while the function edge logs put each call's server time at 0.3-0.6 s. The two first reads (supplier_portal dashboard and
// supplier_api me) waited for the bundle. src/components/me/BootPrefetch.tsx SupplierBootPrefetch starts them at parse time.
//
// The script is RUN here, in a sandbox with a fake localStorage, location and fetch, so this fails if it stops issuing the two
// reads, stops pinning the region, starts reading on an invitation link (?t=, the claim must land first), reads on a dead token,
// or hands the portal an answer shaped differently from supplier/api.ts call(). It also fails if /portal stops rendering it, or
// its keys drift from the ones the portal takes (supplier/core/session.ts DASH_KEY, ME_KEY).
//   node --test scripts/checks/the_supplier_portal_first_reads_start_when_the_html_is_parsed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const SRC = R('src/components/me/BootPrefetch.tsx');
const tpl = /const SUPPLIER_BOOT = \(fn: string, region: string\) => `([\s\S]*?)`;/.exec(SRC);
const FN = 'https://example.invalid/functions/v1';
const script = () => tpl[1].replace('${lit(fn)}', JSON.stringify(FN)).replace('${lit(region)}', JSON.stringify('ap-southeast-1'));
const jwt = (expSec) => 'h.' + Buffer.from(JSON.stringify({ exp: expSec })).toString('base64') + '.s';

function run({ token, search = '', answer = () => ({ status: 200, body: { ok: true } }) }) {
  const calls = [];
  const window = {};
  const ctx = {
    window, location: { search, pathname: '/portal' }, atob: (s) => Buffer.from(s, 'base64').toString('binary'), Date, JSON,
    localStorage: { getItem: (k) => (k === 'qd-sup-token' ? token ?? null : null) },
    fetch: (url, init) => { calls.push({ url, body: JSON.parse(init.body), auth: init.headers.Authorization });
      const a = answer(url); return Promise.resolve({ ok: a.status < 300, status: a.status, json: async () => a.body }); },
  };
  vm.runInNewContext(script(), ctx);
  return { calls, boot: window.__qdBoot };
}

test('the script exists and /portal renders it before the supplier portal', () => {
  assert.ok(tpl, 'SupplierBootPrefetch is gone from BootPrefetch.tsx');
  assert.match(R('src/app/[locale]/portal/page.tsx'), /<SupplierBootPrefetch \/><SupplierPortal \/>/);
});

test('a live supplier token: the dashboard and me start at once, region-pinned, under the keys the portal takes', async () => {
  const t = jwt(Math.floor(Date.now() / 1000) + 3600);
  const { calls, boot } = run({ token: t });
  assert.deepEqual(calls.map((c) => [c.url, c.body.action]), [
    [FN + '/supplier_portal?forceFunctionRegion=ap-southeast-1', 'dashboard'],
    [FN + '/supplier_api?forceFunctionRegion=ap-southeast-1', 'me'],
  ]);
  assert.ok(calls.every((c) => c.auth === 'Bearer ' + t), 'the supplier\'s own token, and nothing else');
  assert.equal(boot.token, t);
  const session = R('src/components/portal/supplier/core/session.ts');
  for (const k of Object.keys(boot.m)) assert.match(session, new RegExp(`const \\w+_KEY = '${k}';`), `the portal takes no key '${k}'`);
  assert.deepEqual(await boot.m.sup_me, { ok: true });
});

test('a refusal is shaped as call() shapes it: the portal reads no_company and a 401 exactly as its own', async () => {
  const t = jwt(Math.floor(Date.now() / 1000) + 3600);
  const { boot } = run({ token: t, answer: (u) => (u.includes('supplier_portal') ? { status: 400, body: { error: 'no_company', code: 'no_company' } } : { status: 401, body: { error: 'unauthorised' } }) });
  const d = await boot.m.sup_dash, m = await boot.m.sup_me;
  assert.equal(d.code, 'no_company'); assert.equal(d._http, 400);
  assert.equal(m._http, 401); assert.equal(m._expired, true); assert.equal(m.code, 'load_failed');
});

test('nothing is read on an invitation link, with no token, or with a dead one', () => {
  const live = jwt(Math.floor(Date.now() / 1000) + 3600);
  assert.equal(run({ token: live, search: '?t=00000000-0000-4000-8000-000000000000' }).calls.length, 0, 'the claim lands first');
  assert.equal(run({ token: null }).calls.length, 0);
  assert.equal(run({ token: jwt(Math.floor(Date.now() / 1000) + 30) }).calls.length, 0, 'a token within a minute of expiry');
  assert.equal(run({ token: 'not-a-jwt' }).calls.length, 0);
});
