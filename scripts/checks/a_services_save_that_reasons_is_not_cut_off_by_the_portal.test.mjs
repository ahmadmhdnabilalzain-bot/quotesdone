// A SERVICES SAVE THAT REASONS IS NOT CUT OFF BY THE PORTAL (27 Oct 2026, it_engineer; supplier registration walk).
//
// Measured on production with a ZZ DEMO supplier (walk 829ab868, function_edge_logs 15:47:11Z): the Services tab's
// confirm, supplier_api services_save_rewrite, resolved three of the supplier's own words by reasoning (three
// routine_employee_reasoning calls of 10-17 s, then three supplier_communication calls of 12-18 s) and answered HTTP 200
// after 36,959 ms with the capability confirmed. The portal's call() aborted every request at 20 s, so the supplier read
// "Could not save your services." for a save that had succeeded. This pins the portal side: call() takes a per-call
// timeout, the two reasoning actions use REASONING_TIMEOUT_MS (well over the measured 37 s), and every other call keeps 20 s.
//   node --test scripts/checks/a_services_save_that_reasons_is_not_cut_off_by_the_portal.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const API = readFileSync(root + 'src/components/portal/supplier/api.ts', 'utf8');
const TAB = readFileSync(root + 'src/components/portal/supplier/ServicesTab.tsx', 'utf8');
const MEASURED_MS = 36959;

// The real api.ts, with only its one import (the project's env module) replaced, loaded by Node's own type stripping.
async function loadApi() {
  const dir = mkdtempSync(join(tmpdir(), 'qd-api-'));
  // the real retry helper is loaded by file URL (the temp copy cannot resolve '@/lib'), so the timeout checks run through it
  const retryUrl = new URL('../../src/lib/fetchRetry.ts', import.meta.url).href;
  const src = API.replace(/^import \{ retryRead, isReadAction \} from '@\/lib\/fetchRetry';$/m, `import { retryRead, isReadAction } from '${retryUrl}';`).replace(/^import \{ SUPA_ANON as ANON, fnUrl \} from '@\/lib\/supaEnv';$/m,
    "const ANON = 'anon'; const fnUrl = (p) => 'https://fn.invalid/functions/v1/' + p;");
  assert.notEqual(src, API, 'api.ts no longer imports SUPA_ANON/fnUrl the way this check expects; update the stub');
  const f = join(dir, 'api.mts'); writeFileSync(f, src);
  return import(pathToFileURL(f).href);
}

// A server that answers after `ms`, and honours the abort signal like fetch does.
const slowServer = (ms) => (_url, init) => new Promise((resolve, reject) => {
  const t = setTimeout(() => resolve(new Response(JSON.stringify({ ok: true, confirmed: true }), { status: 200 })), ms);
  init.signal.addEventListener('abort', () => { clearTimeout(t); reject(new DOMException('aborted', 'AbortError')); });
});

test('call() honours a per-call timeout and keeps 20 s as the default', async () => {
  const api = await loadApi();
  const real = globalThis.fetch;
  try {
    globalThis.fetch = slowServer(150);
    assert.deepEqual(await api.call('supplier_api', { action: 'x' }, 't', { timeoutMs: 50 }), { ok: false, code: 'timeout' });
    assert.equal((await api.call('supplier_api', { action: 'x' }, 't', { timeoutMs: 1000 })).ok, true);
  } finally { globalThis.fetch = real; }
  assert.match(API, /const TIMEOUT_MS = 20000;/, 'the default for every other call stays 20 s');
  assert.ok(api.REASONING_TIMEOUT_MS >= 2 * MEASURED_MS, `REASONING_TIMEOUT_MS ${api.REASONING_TIMEOUT_MS} must stay well over the measured ${MEASURED_MS} ms`);
});

test('the Services tab gives services_rewrite and services_save_rewrite the reasoning timeout', () => {
  for (const action of ['services_rewrite', 'services_save_rewrite']) {
    const at = TAB.indexOf(`action: '${action}'`);
    assert.ok(at > 0, `${action} call not found in ServicesTab.tsx`);
    const callEnd = TAB.indexOf('.catch(', at);
    assert.match(TAB.slice(at, callEnd), /token, \{ timeoutMs: REASONING_TIMEOUT_MS \}\)$/, `${action} must pass { timeoutMs: REASONING_TIMEOUT_MS }`);
  }
});
