// THE CODE CHECK AND THE COMPANY'S CREATION DO NOT WAIT ON A CORS PREFLIGHT THE BROWSER COULD HAVE PAID EARLIER.
// Assigned: customer_support.
//
// 15 Nov 2026: "the code verifies and the registration form opens" measured 3,026 ms (12:10) and 3,078 ms (15:13) from the
// US container against the bar's 3,000. login_otp verify was 875 ms of server time and 1,194 ms in the browser; create_company
// 797 ms and 1,430 ms. Each is a cross-origin POST with Authorization and Content-Type: application/json, so the browser sends an
// OPTIONS preflight first and waits a round trip to ap-southeast-1 for it. Neither function sent Access-Control-Max-Age, and the
// Fetch standard remembers a preflight for 5 seconds without it: `verify`, typed a minute after `send`, paid one again, and
// create_company, the first supplier_api call after sign-in, always paid one.
// Now: both functions' preflights carry a two-hour Max-Age, the portal pays supplier_api's preflight beside the code check
// (api.ts preflightNow -> supplier_api's warm door, 204 before any session or database read), and that door comes before the
// sign-in check. This reads the repository: what the deployed functions answer is the deploy's to prove.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (t) => t.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

test('both functions on the step tell the browser to remember their preflight', () => {
  for (const [file, name] of [['supabase/functions/supplier_api/context.ts', 'export const cors = {'], ['supabase/functions/login_otp/index.ts', 'const CORS = {']]) {
    const line = code(read(file)).split('\n').find((l) => l.includes(name)) || '';
    const age = /'Access-Control-Max-Age': '(\d+)'/.exec(line);
    assert.ok(age, `${file}: its CORS headers carry no Access-Control-Max-Age, so every POST more than 5 s after the last waits on an OPTIONS`);
    assert.ok(Number(age[1]) >= 600, `${file}: a preflight remembered for ${age[1]} s does not outlive the minute between send and verify`);
  }
});

test('the portal pays supplier_api\'s preflight beside the code check, with the request shape create_company sends', () => {
  const login = code(read('src/components/portal/supplier/core/Login.tsx'));
  const at = login.indexOf("preflightNow('supplier_api')"), verify = login.indexOf("call('login_otp', { action: 'verify'");
  assert.ok(at > 0 && verify > at, 'Login does not start supplier_api\'s preflight before it waits on the code check');
  const api = code(read('src/components/portal/supplier/api.ts'));
  const warm = api.slice(api.indexOf('export function preflightNow('), api.indexOf('export function preflightNow(') + 600);
  const call = api.slice(api.indexOf('export async function call('), api.indexOf('export async function call(') + 900);
  const heads = (s) => /headers:\s*\{([^}]*)\}/.exec(s)?.[1].split(',').map((h) => h.split(':')[0].trim().replace(/['"]/g, '').toLowerCase()).sort().join(',');
  assert.ok(warm.includes('fnUrl(path)') && call.includes('fnUrl(path)'), 'the warm and the call do not go to the same URL: a preflight is remembered per URL');
  assert.equal(heads(warm), heads(call), 'the warm sends other header names than call(): its preflight is not the one create_company needs');
  assert.match(warm, /method: 'POST'/);
  assert.match(warm, /body: '\{"action":"warm"\}'/);
});

test('supplier_api answers the warm 204 before the sign-in check or any database read', () => {
  const idx = code(read('supabase/functions/supplier_api/index.ts'));
  const warm = idx.indexOf('if (warmOnly(peek)) return new Response(null, { status: 204, headers: cors });');
  assert.ok(warm > 0, 'supplier_api has no warm door');
  for (const later of ['atTheDoor(jwt', "peek.action === 'spec_arabic_finish'", 'requireInternal(']) assert.ok(idx.indexOf(later) > warm, `the warm door comes after ${later}`);
  const door = code(read('supabase/functions/supplier_api/lib/door.ts'));
  assert.match(door, /return !!p && p\.action === 'warm' && p\.__secret == null;/, 'warmOnly takes more than the portal\'s warm (an internal door must never answer 204 here)');
});
