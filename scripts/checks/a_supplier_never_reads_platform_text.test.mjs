// A SUPPLIER NEVER READS PLATFORM TEXT, AND A FILE TOO LARGE TO READ IS REFUSED BEFORE IT IS SENT (28 Oct 2026,
// sales_engineer; production document walk 4e9d675a and the size measurement that followed it).
//
// Measured on production: a 24 MB trade licence on the Documents tab ended supplier_portal at the edge's CPU cap, and the
// platform's own HTTP 546 body, {"code":"WORKER_RESOURCE_LIMIT","message":"Function failed due to not having enough
// compute resources (please check logs)"}, was printed on the supplier's screen at 1366 and 390 px. Scanner-style licences
// (one JPEG per page, text layer on page 1): 9.66 MB stored and read on both body paths; 14.50 MB and 19.33 MB ended both
// at the cap. This check pins the two halves of the fix in src/components/portal/supplier/api.ts and the three body uploads
// in SupplierPortal.tsx:
//   1. call() replaces any 5xx/413 that does not carry one of OUR codes with our own code; the text never reaches a panel;
//   2. our own 5xx answers (lower-case codes) keep their code and message;
//   3. every new code renders in English AND Arabic from serverCopy.ts, with no platform wording;
//   4. the licence, the Documents-tab body upload and the quotation upload refuse a file over MAX_READ_BYTES first.
//   node --test scripts/checks/a_supplier_never_reads_platform_text.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const API = readFileSync(root + 'src/components/portal/supplier/api.ts', 'utf8');
const COPY = readFileSync(root + 'src/components/portal/supplier/serverCopy.ts', 'utf8');
const PORTAL = readFileSync(root + 'src/components/portal/SupplierPortal.tsx', 'utf8');
const PLATFORM_546 = JSON.stringify({ code: 'WORKER_RESOURCE_LIMIT', message: 'Function failed due to not having enough compute resources (please check logs)' });

// The real api.ts, with its env import stubbed and its retry import (fetchRetry, #1769) pointed at the real file, loaded by Node's own type stripping.
async function loadApi() {
  const dir = mkdtempSync(join(tmpdir(), 'qd-api-'));
  const retryUrl = new URL('../../src/lib/fetchRetry.ts', import.meta.url).href;
  const src = API.replace(/^import \{ SUPA_ANON as ANON, fnUrl \} from '@\/lib\/supaEnv';$/m,
    "const ANON = 'anon'; const fnUrl = (p) => 'https://fn.invalid/functions/v1/' + p;")
    .replace(/^import \{ retryRead, isReadAction \} from '@\/lib\/fetchRetry';$/m, `import { retryRead, isReadAction } from '${retryUrl}';`);
  assert.notEqual(src, API, 'api.ts no longer imports SUPA_ANON/fnUrl the way this check expects; update the stub');
  assert.ok(src.includes(retryUrl), 'api.ts no longer imports retryRead/isReadAction from @/lib/fetchRetry; update the stub');
  const f = join(dir, 'api.mts'); writeFileSync(f, src);
  return import(pathToFileURL(f).href);
}
const answering = (status, body, type = 'application/json') => async () => new Response(body, { status, headers: { 'Content-Type': type } });

test('a platform failure reaches the portal as our own code, never as its text', async () => {
  const api = await loadApi();
  const real = globalThis.fetch;
  try {
    const cases = [
      [546, PLATFORM_546, 'application/json', 'worker_limit'],
      [503, JSON.stringify({ code: 'BOOT_ERROR', message: 'Worker failed to boot (please check logs)' }), 'application/json', 'server_error'],
      [502, '<html><body>Bad Gateway</body></html>', 'text/html', 'server_error'],
      [504, 'upstream request timeout', 'text/plain', 'server_error'],
      [500, JSON.stringify({ error: 'TypeError: Cannot read properties of undefined (reading \'id\')' }), 'application/json', 'server_error'],
      [413, JSON.stringify({ statusCode: '413', error: 'Payload too large', message: 'The object exceeded the maximum allowed size' }), 'application/json', 'file_too_large'],
    ];
    for (const [status, body, type, code] of cases) {
      globalThis.fetch = answering(status, body, type);
      const j = await api.call('supplier_portal', { action: 'save_documents' }, 't');
      assert.deepEqual(j, { ok: false, code, _http: status }, `HTTP ${status} ${body.slice(0, 40)}`);
      assert.doesNotMatch(JSON.stringify(j), /compute resources|check logs|Bad Gateway|upstream|TypeError|Payload too large/);
    }
    // our own failures keep their code and their sentence
    globalThis.fetch = answering(502, JSON.stringify({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store your trade licence. Please try again.' }));
    const own = await api.call('supplier_api', { action: 'process_docs' }, 't');
    assert.equal(own.code, 'upload_failed'); assert.equal(own._http, 502); assert.match(own.message, /could not store your trade licence/);
    globalThis.fetch = answering(500, JSON.stringify({ error: 'Could not load this section. Please try again.', code: 'load_failed' }));
    assert.equal((await api.call('supplier_portal', { action: 'documents' }, 't')).code, 'load_failed');
    // a 4xx that is ours is untouched; a 401 still marks the session expired
    globalThis.fetch = answering(401, JSON.stringify({ error: 'unauthorized' }));
    assert.equal((await api.call('supplier_portal', { action: 'documents' }, 't'))._expired, true);
  } finally { globalThis.fetch = real; }
});

test('every new code has plain English and Arabic copy, and none repeats platform wording', () => {
  for (const code of ['worker_limit', 'file_too_large', 'server_error', 'file_too_large_read']) {
    const at = COPY.indexOf(`  ${code}: s(`);
    assert.ok(at > 0, `serverCopy.ts has no entry for ${code}`);
    const rest = COPY.slice(at + code.length + 6); const next = rest.search(/\n  (?:\/\/|[a-z_]+: )/);   // the text after `<code>: s(`
    const entry = rest.slice(0, next > 0 ? next : 800);
    assert.match(entry, /[؀-ۿ]/, `${code} has no Arabic`);
    assert.doesNotMatch(entry, /compute resources|check logs|WORKER_|BOOT_ERROR/i, `${code} repeats platform wording`);
  }
});

test('the measured read cap is 10 MB, and every body upload that is read refuses a larger file before sending it', async () => {
  const api = await loadApi();
  assert.equal(api.MAX_READ_BYTES, 10 * 1024 * 1024);
  assert.equal(api.tooBigToRead({ size: 9.66 * 1048576 }), false);   // measured: stored and read
  assert.equal(api.tooBigToRead({ size: 14.5 * 1048576 }), true);    // measured: HTTP 546
  // the licence box, the Documents tab's body upload and the quotation upload each check before they call
  const before = (fnStart, callNeedle) => {
    const at = PORTAL.indexOf(fnStart); assert.ok(at > 0, `${fnStart} not found`);
    const c = PORTAL.indexOf(callNeedle, at); assert.ok(c > at, `${callNeedle} not found after ${fnStart}`);
    return PORTAL.slice(at, c);
  };
  assert.match(before('const upLicense = async (file) => {', "action: 'process_docs'"), /tooBigToRead\(file\)[^\n]*file_too_large_read/);
  assert.match(before('const upload = async (kind, file, expiry) => {', "action: 'save_documents'"), /kind !== 'profile' && kind !== 'catalogs' && tooBigToRead\(file\)[^\n]*file_too_large_read/);
  assert.match(before('const onFile = async (file) => {', "action: 'extract_quote'"), /tooBigToRead\(file\)[^\n]*file_too_large_read/);
});
