// public_site POSTs ended 546 / 502 / 503 about 1.4% of the time (function_edge_logs, 2 Nov 2026); those
// responses carry no CORS header, so the browser reports ERR_FAILED. src/lib/publicSite.ts retries a
// read ONCE. This runs the real publicSite() against a stubbed fetch: a transient failure is absorbed,
// a persistent one still throws (the callers' fallback), and the known-bad control (retry removed) fails.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const src = readFileSync(new URL('../../src/lib/publicSite.ts', import.meta.url), 'utf8');
const ts = src.slice(src.indexOf('const RETRY_STATUS'), src.indexOf('export type Counters')).replace('export async function', 'async function');
const body = stripTypeScriptTypes(ts);
const build = (code, fetch) => new Function('fetch', 'FN', 'SUPA_ANON', `${code}; return publicSite;`)(fetch, 'u', 'k');
const res = (status, json = { ok: true }) => ({ status, json: async () => json });

test('a transient failure is retried once and absorbed', async () => {
  for (const first of [() => { throw new TypeError('Failed to fetch'); }, () => res(546), () => res(502)]) {
    let n = 0;
    const f = async () => (n++ === 0 ? first() : res(200, { ok: true, v: 1 }));
    assert.deepEqual(await build(body, f)('counters'), { ok: true, v: 1 });
    assert.equal(n, 2);
  }
});
test('a persistent failure still throws after one retry, and a 429 is not retried', async () => {
  let n = 0;
  await assert.rejects(build(body, async () => { n++; throw new TypeError('x'); })('counters'));
  assert.equal(n, 2);
  n = 0;
  assert.deepEqual(await build(body, async () => { n++; return res(429); })('counters'), { ok: false, rate_limited: true });
  assert.equal(n, 1);
});
test('known-bad control: without the retry the transient failure surfaces', async () => {
  const bad = body.replace(/catch \(_e\) \{[^}]*\}/, 'catch (e) { throw e; }');
  assert.notEqual(bad, body);
  let n = 0;
  await assert.rejects(build(bad, async () => { if (n++ === 0) throw new TypeError('x'); return res(200); })('counters'));
});
