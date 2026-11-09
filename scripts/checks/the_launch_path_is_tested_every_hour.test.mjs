// THE LAUNCH PATH IS TESTED EVERY HOUR — owner: it_engineer (21 Sep 2026)
//
//   node --test scripts/checks/the_launch_path_is_tested_every_hour.test.mjs
//
// Holds the properties of supabase/functions/_shared/launch_path.ts that a refactor could quietly lose:
//   1. it covers the path it claims to: the invitation on BOTH hosts in EN and AR, the customer page in
//      EN and AR, the portal API, the sign-in code request, the portal functions' health;
//   2. it cannot reach a person: the sign-in probe uses a reserved +971 50 000 00xx number and never an
//      email, a 200 from login_otp is a FAILURE (a code was sent), and the claim probe's token is not a UUID;
//   3. every function call is pinned to the database region;
//   4. one dropped request does not raise, two do;
//   5. a broken path is ONE finding that does not flap (hold two clean hours before closing);
//   6. the heartbeat runs it and it has a schedule row, and the tick itself mails nobody.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';
import {
  launchPathProbes, probeLaunchPath, launchPathAction, launchPathItem, HOLD_MS, PROBE_MOBILE, HOSTS,
} from '../../supabase/functions/_shared/launch_path.ts';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/.*$/gm, '').replace(/\s\/\/.*$/gm, '');
const probes = launchPathProbes('anon');
const byId = Object.fromEntries(probes.map((p) => [p.id, p]));

test('covers both hosts in both languages, the customer page, the API, sign-in and health', () => {
  assert.deepEqual(HOSTS.map((h) => new URL(h).host).sort(), ['quotesdone.ae', 'www.quotesdone.com']);
  for (const h of ['www.quotesdone.com', 'quotesdone.ae']) for (const l of ['en', 'ar']) {
    assert.ok(byId[`invite:${h}:${l}`], `no invitation probe for ${h} ${l}`);
    assert.match(byId[`invite:${h}:${l}`].url, new RegExp(`/${l}/portal\\?t=`));
  }
  for (const l of ['en', 'ar']) assert.match(byId[`customer:${l}`].url, new RegExp(`/${l}/me$`));
  for (const id of ['api:supplier_portal', 'api:claim_lookup', 'signin:login_otp',
    'health:kyc', 'health:customer_api', 'health:customer_portal', 'health:project_api', 'health:messages_api']) {
    assert.ok(byId[id], `missing probe ${id}`);
  }
});

test('the sign-in probe is a reserved fixture mobile, never an email, and a sent code fails it', () => {
  assert.match(PROBE_MOBILE, /^\+9715000000\d\d$/);
  const p = byId['signin:login_otp'];
  const body = JSON.parse(p.init.body);
  assert.equal(body.action, 'send');
  assert.equal(body.identifier, PROBE_MOBILE);
  assert.ok(!probes.some((x) => String(x.init?.body || '').includes('@')), 'no probe may carry an email address');
  const H = new Headers({ 'x-sb-edge-region': 'ap-southeast-1' });
  assert.equal(p.judge(404, '{"no_account":true}', p.url, H), null);
  assert.equal(p.judge(200, '{"ok":false,"captured":true,"code":"fixture_number"}', p.url, H), null);
  assert.ok(p.judge(200, '{"ok":true,"identifier":"+971500000099","known":true}', p.url, H), 'a sent code must fail the probe');
  assert.ok(p.judge(404, '{"no_account":true}', p.url, new Headers({ 'x-sb-edge-region': 'us-east-1' })), 'wrong region must fail');
});

test('the claim probe never sends a well-formed token (that would forge the broken-template signal)', () => {
  const t = JSON.parse(byId['api:claim_lookup'].init.body).t;
  assert.doesNotMatch(t, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
});

test('every function probe is pinned to the database region', () => {
  for (const p of probes.filter((x) => x.url.includes('/functions/v1/'))) {
    assert.match(p.url, /\?forceFunctionRegion=ap-southeast-1$/, p.id);
  }
});

test('a page is judged on language, direction and where it landed', () => {
  const ar = byId['invite:quotesdone.ae:ar'];
  assert.equal(ar.judge(200, '<html lang="ar" dir="rtl"><body>', 'https://quotesdone.ae/ar/portal?t=x'), null);
  assert.ok(ar.judge(200, '<html lang="en" dir="ltr">', 'https://quotesdone.ae/portal'), 'English served for /ar');
  assert.ok(ar.judge(200, '<html lang="ar">', 'https://quotesdone.ae/ar/portal'), 'Arabic without rtl');
  assert.ok(ar.judge(500, '', ar.url));
  const en = byId['invite:www.quotesdone.com:en'];
  // Vercel drops the default /en and may move a UAE caller to quotesdone.ae: both are fine.
  assert.equal(en.judge(200, '<html lang="en" dir="ltr">', 'https://quotesdone.ae/portal?t=x'), null);
  assert.ok(en.judge(200, '<html lang="en" dir="ltr">', 'https://quotesdone.ae/'), 'landing on the home page is a failure');
});

// A fake fetch answering every probe as production did on 21 Sep 2026, with an override per probe.
function fakeFetch(override = {}) {
  const calls = {};
  const f = async (url, init) => {
    const p = probes.find((x) => x.url === url);
    calls[p.id] = (calls[p.id] || 0) + 1;
    const o = override[p.id]?.(calls[p.id]);
    if (o instanceof Error) throw o;
    const [status, body] = o || (p.id.startsWith('invite') || p.id.startsWith('customer')
      ? [200, `<html lang="${p.id.endsWith(':ar') ? 'ar' : 'en'}" dir="${p.id.endsWith(':ar') ? 'rtl' : 'ltr'}">`]
      : p.id === 'api:supplier_portal' ? [401, '{"error":"unauthorized"}']
      : p.id === 'api:claim_lookup' ? [400, '{"ok":false,"error":"invalid_link"}']
      : p.id === 'signin:login_otp' ? [404, '{"no_account":true}'] : [204, '']);
    return { status, url, headers: new Headers({ 'x-sb-edge-region': 'ap-southeast-1' }), text: async () => body, init };
  };
  return { f, calls };
}

test('one dropped request is retried and passes; two failures fail; a redirect loop fails', async () => {
  const { f: flaky, calls } = fakeFetch({ 'health:kyc': (n) => (n === 1 ? new Error('fetch failed') : null) });
  const a = await probeLaunchPath('anon', flaky, 0);
  assert.equal(a.ok, true);
  assert.equal(calls['health:kyc'], 2);
  assert.equal(a.results.find((r) => r.id === 'health:kyc').retried, true);

  const { f: down } = fakeFetch({ 'signin:login_otp': () => [503, '{"error":"x"}'],
    'invite:quotesdone.ae:ar': () => new TypeError('fetch failed: redirect count exceeded') });
  const b = await probeLaunchPath('anon', down, 0);
  assert.equal(b.ok, false);
  assert.deepEqual(b.failed.map((r) => r.id).sort(), ['invite:quotesdone.ae:ar', 'signin:login_otp']);
  const item = launchPathItem(b);
  assert.equal(item.item, 'down');
  assert.equal(item.blast, 'customer_facing');
  assert.equal(item.evidence.failed.length, 2, 'two broken doors are ONE finding with two lines of evidence');
});

test('the finding does not flap: held open two clean hours, then closed', () => {
  const now = Date.parse('2026-09-23T10:00:00Z');
  const ago = (ms) => new Date(now - ms).toISOString();
  assert.equal(launchPathAction(false, null, now), 'raise');
  assert.equal(launchPathAction(false, ago(10), now), 'raise');
  assert.equal(launchPathAction(true, ago(3600e3), now), 'hold');
  assert.equal(launchPathAction(true, ago(HOLD_MS + 1), now), 'settle');
  assert.equal(launchPathAction(true, null, now), 'settle');
  assert.ok(HOLD_MS >= 2 * 3600e3, 'a shorter hold lets an hourly blip reopen and re-email');
});

test('the heartbeat runs it hourly through fn_it_duty_settle and mails nobody itself', () => {
  const src = functionSource('resilience_ping');
  assert.match(src, /^\s{2}launchpath:\s*\{\s*run:\s*launchPathTick\s*\}/m, 'launchpath is not in STEP_RUN');
  const at = src.indexOf('async function launchPathTick');
  const body = strip(src.slice(at, src.indexOf('\n}\n', at) + 3));
  assert.match(body, /fn_it_duty_settle/);
  assert.match(body, /duty:launch_path:down/);
  assert.doesNotMatch(body, /fn_notify_founder|founder_alerts|send_outbox|sendEmail/, 'the tick must not mail the founder directly');
  const seed = R('scripts/sql/the_launch_path_is_tested_every_hour.sql');
  assert.match(seed, /\('launchpath', interval '1 hour'/);
  const test = R('supabase/functions/resilience_ping/schedule.test.ts');
  assert.match(test, /\['launchpath', 3600, 8000, 'plan'\]/, 'schedule.test.ts SEED must carry the row verbatim');
});
