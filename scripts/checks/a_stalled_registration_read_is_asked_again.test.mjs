// A STALLED REGISTRATION READ IS ASKED AGAIN, NOT WAITED OUT (11 Nov 2026, it_engineer; founder ruling 1620: registration
// must not be laggy).
//
// Measured on production (function_edge_logs + edge_logs by trace_id + agent_runs fn:kyc, 24 h to 16:30Z on 11 Nov): kyc
// 'state' took 24,856 ms (10 Nov 19:58:39Z) and 43,808 ms (11 Nov 04:43:32Z) at the edge while kyc's own handler ran 200 ms
// and 256 ms; the first database call of each came 24.5 s and 43.5 s after the request was received. In both windows the kyc
// calls that arrived meanwhile were answered by a freshly booted isolate in 0.6-0.75 s. The portal waited 20 s and gave up.
// src/lib/fetchRetry.ts now hedges the cheap reads (kyc state, supplier_api/customer_api me, the dashboards) after HEDGE_MS.
// This pins the wiring: both portal clients, loaded for real, answer a 'state' read whose first request never returns, and
// the customer's boot read (me/prefetch.ts, BootPrefetch.tsx's raw fetch) is asked again the same way.
//   node --test scripts/checks/a_stalled_registration_read_is_asked_again.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const retryUrl = new URL('../../src/lib/fetchRetry.ts', import.meta.url).href;
const { HEDGE_MS } = await import(retryUrl);

function load(rel, extra = []) {
  const dir = mkdtempSync(join(tmpdir(), 'qd-hedge-'));
  let src = readFileSync(root + rel, 'utf8')
    .replace(/^import \{ SUPA_ANON as ANON, fnUrl \} from '@\/lib\/supaEnv';$/m, "const ANON = 'anon'; const fnUrl = (p) => 'https://fn.invalid/functions/v1/' + p;")
    .replace(/^import \{ retryRead, isReadAction \} from '@\/lib\/fetchRetry';$/m, `import { retryRead, isReadAction } from '${retryUrl}';`);
  for (const [re, by] of extra) src = src.replace(re, by);
  assert.equal((src.match(/^import /gm) || []).length, 1, rel + ' imports changed; update the stubs of this check');
  const f = join(dir, 'api.mts'); writeFileSync(f, src);
  return import(pathToFileURL(f).href);
}
const supplierApi = () => load('src/components/portal/supplier/api.ts');
const customerApi = () => load('src/components/me/api.ts', [
  [/^import \{ supaClient \} from '@\/lib\/supaClient';$/m, 'const supaClient = () => null;'],
  [/^import \{ warm \} from '\.\/prefetch';$/m, 'const warm = () => {};'],
  [/^import \{ readWidgetConv \} from '@\/lib\/widgetConv';$/m, "const readWidgetConv = () => '';"],
]);

// The first request sits like the 24.9 s one did (until the caller aborts); every later one answers at once.
function stalledOnce() {
  const seen = [];
  const fetch = (_url, init) => {
    seen.push(JSON.parse(init.body).action);
    if (seen.length === 1) return new Promise((_, no) => init.signal?.addEventListener('abort', () => no(new DOMException('aborted', 'AbortError'))));
    return Promise.resolve(new Response(JSON.stringify({ ok: true, kind: 'supplier', phone_verified: true }), { status: 200 }));
  };
  return { fetch, seen };
}

for (const [who, api] of [['supplier portal', supplierApi], ['customer portal', customerApi]]) {
  test(`${who}: a kyc state read that stalls is answered by its second request after HEDGE_MS`, async () => {
    const { call } = await api(); const real = globalThis.fetch; const s = stalledOnce(); globalThis.fetch = s.fetch;
    try {
      const t0 = Date.now();
      const j = await call('kyc', { action: 'state' }, 't');
      const ms = Date.now() - t0;
      assert.equal(j.ok, true, 'the stalled read was not answered: ' + JSON.stringify(j));
      assert.deepEqual(s.seen, ['state', 'state']);
      assert.ok(ms >= HEDGE_MS - 50 && ms < HEDGE_MS + 1500, `answered in ${ms} ms; expected just after HEDGE_MS ${HEDGE_MS}`);
    } finally { globalThis.fetch = real; }
  });
}

test('KNOWN-BAD control: a registration write that stalls is never sent twice', async () => {
  const { call } = await supplierApi(); const real = globalThis.fetch; const s = stalledOnce(); globalThis.fetch = s.fetch;
  try {
    const j = await call('kyc', { action: 'whatsapp_choose', opt: 'same' }, 't', { timeoutMs: HEDGE_MS + 600 });
    assert.equal(j.code, 'timeout');
    assert.deepEqual(s.seen, ['whatsapp_choose']);
  } finally { globalThis.fetch = real; }
});

// The customer's account gate takes its kyc 'state' from the boot script's raw fetch (BootPrefetch.tsx), which has no timeout.
async function loadPrefetch() {
  const dir = mkdtempSync(join(tmpdir(), 'qd-hedge-'));
  const src = readFileSync(root + 'src/components/me/prefetch.ts', 'utf8')
    .replace(/^import \{ HEDGE_MS \} from '@\/lib\/fetchRetry';$/m, `import { HEDGE_MS } from '${retryUrl}';`);
  assert.ok(src.includes(retryUrl), 'prefetch.ts no longer imports HEDGE_MS from @/lib/fetchRetry; update this check');
  const f = join(dir, 'prefetch.mts'); writeFileSync(f, src);
  return import(pathToFileURL(f).href);
}
test('customer portal: a boot kyc state that stalls is asked again after HEDGE_MS; an unhedged boot read is not', async () => {
  const pf = await loadPrefetch();
  const never = new Promise(() => {});
  globalThis.__qdBoot = { token: 'tk', m: { kyc: never, ov: never } };
  let kycRuns = 0, ovRuns = 0;
  pf.warm('tk', 'kyc', async () => { kycRuns++; return { ok: true, phone_verified: true }; });
  pf.warm('tk', 'ov', async () => { ovRuns++; return { ok: true }; });
  const t0 = Date.now();
  const j = await Promise.race([pf.take('tk', 'kyc', async () => ({ ok: false, code: 'not taken' })),
    new Promise((_, no) => setTimeout(() => no(new Error('the boot read was waited out: no answer after ' + (HEDGE_MS + 2000) + ' ms')), HEDGE_MS + 2000))]);
  const ms = Date.now() - t0;
  assert.equal(j.ok, true); assert.equal(kycRuns, 1);
  assert.ok(ms >= HEDGE_MS - 50 && ms < HEDGE_MS + 1500, `answered in ${ms} ms`);
  const ov = await Promise.race([pf.take('tk', 'ov', async () => 'fresh'), new Promise((ok) => setTimeout(() => ok('still waiting'), 200))]);
  assert.equal(ov, 'still waiting', 'KNOWN-BAD control: an unhedged boot read is not sent twice');
  assert.equal(ovRuns, 0);
});
