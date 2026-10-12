// THE CRON ROUTE FAILS CLOSED (it_engineer, 6 Oct 2026, review of #1246). /api/resilience-ping forwards the
// service key to resilience_ping, so it must answer 401 and forward nothing unless CRON_SECRET is set and the
// request carries exactly `Bearer <CRON_SECRET>`. Node 24 strips the types from the .ts helper on import.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cronAuthorized } from '../../src/lib/cronAuth.ts';

const req = (auth) => new Request('https://quotesdone.com/api/resilience-ping', auth == null ? {} : { headers: { authorization: auth } });

test('unset secret refuses everything, including an empty bearer', () => {
  assert.equal(cronAuthorized(req('Bearer '), undefined), false);
  assert.equal(cronAuthorized(req('Bearer anything'), ''), false);
  assert.equal(cronAuthorized(req(null), undefined), false);
});

test('only the exact Vercel header passes', () => {
  const s = 'zz-test-cron-secret';
  assert.equal(cronAuthorized(req('Bearer ' + s), s), true);
  for (const bad of [null, s, 'bearer ' + s, 'Bearer ' + s.slice(0, -1), 'Bearer x' + s.slice(1)])
    assert.equal(cronAuthorized(req(bad), s), false, String(bad));
});

test('the route checks the door before it pings, records uptime or touches the service key', () => {
  const src = readFileSync(new URL('../../src/app/api/resilience-ping/route.ts', import.meta.url), 'utf8');
  const get = src.slice(src.indexOf('export async function GET'));
  const door = get.indexOf('if (!cronAuthorized(req, process.env.CRON_SECRET))');
  assert.ok(door > 0, 'GET must open with the cron door');
  for (const after of ['checkOrigins()', 'fetch(PING', 'SUPABASE_SERVICE_ROLE_KEY'])
    assert.ok(get.indexOf(after) > door, after + ' runs before the door');
  assert.ok(!/if \(secret && /.test(src), 'the open-when-unset form is back');
});
