// The registration's fixture mobile is recorded verified without racing the form (./fixture_mobile.mjs says what was
// measured: evidence run 8120d011, 10 Nov 2026). Offline: a simulated portal whose form reads kyc 'state' once, with the
// supplier portal's 20 s abort, and a harness whose send_sms takes as long as the live run's (33,345 ms), scaled 1:1000.
//   node --test scripts/e2e/fixture_mobile.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { recordFixtureMobile, settled } from './fixture_mobile.mjs';

const SCALE = 1000;                       // 1 ms here = 1 s live
const PORTAL_ABORT = 20000 / SCALE;       // src/components/portal/supplier/api.ts TIMEOUT_MS
const LIVE_SEND_SMS = 33345 / SCALE;      // kyc send_sms, function_edge_logs 20:11:20.284Z
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The server (leads row + kyc) and the form (one kyc read on mount, aborted at PORTAL_ABORT, gated by `gate`). */
function world({ sendSmsMs = LIVE_SEND_SMS } = {}) {
  const db = { phone_verified: false, opt: null };
  const kyc = () => ({ ok: true, phone_verified: db.phone_verified, whatsapp: db.opt ? { opt: db.opt } : { opt: null } });
  const form = { reads: 0, shown: null, routed: false };
  const mountForm = async (gate = Promise.resolve()) => {
    form.reads++;
    const read = gate.then(() => kyc());
    const aborted = sleep(PORTAL_ABORT).then(() => ({ ok: false, code: 'timeout' }));
    const k = await Promise.race([read, aborted]);
    form.shown = !!(k && k.phone_verified);
  };
  const deps = {
    sendSms: async () => { await sleep(sendSmsMs); return { ok: false, code: 'fixture_number' }; },
    markVerified: async () => { db.phone_verified = true; },
    chooseWhatsapp: async () => { db.opt = 'same'; return { ok: true }; },
    kycState: async () => kyc(),
    reloadForm: async () => { await mountForm(); },
    formShowsVerified: async () => form.shown === true,
    sleep,
  };
  return { db, form, deps, mountForm };
}

test('the old way: holding the form\'s one read across the live run\'s send_sms leaves it unverified', async () => {
  const w = world();
  let release; const held = new Promise((r) => { release = r; });
  const mounted = w.mountForm(held);                  // the form mounts after Create company; its read is held
  await w.deps.sendSms(); await w.deps.markVerified(); await w.deps.chooseWhatsapp();
  release(); await mounted;
  assert.equal(w.db.phone_verified, true, 'the database says verified');
  assert.equal(w.form.shown, false, 'and the form still says not verified: "Still needed: Verified mobile number"');
});

test('recordFixtureMobile: the form is read after kyc says verified, however long send_sms takes', async () => {
  for (const ms of [5, LIVE_SEND_SMS, 3 * LIVE_SEND_SMS]) {
    const w = world({ sendSmsMs: ms });
    const r = await recordFixtureMobile(w.deps, { timeoutMs: 200, everyMs: 5 });
    assert.equal(r.ok, true, `send_sms ${ms * SCALE} ms: ${r.detail}`);
    assert.equal(r.smsRefused, true, 'kyc refused the reserved number before any SMS');
    assert.equal(w.form.shown, true);
  }
});

test('it fails, and says why, when kyc never reads verified', async () => {
  const w = world({ sendSmsMs: 1 });
  w.deps.markVerified = async () => {};             // the write did not take
  const r = await recordFixtureMobile(w.deps, { timeoutMs: 30, everyMs: 5 });
  assert.equal(r.ok, false); assert.match(r.detail, /never read verified/);
  assert.equal(w.form.reads, 0, 'the form is not reloaded on a state that is not true');
  assert.equal(settled({ phone_verified: true, whatsapp: { opt: 'same' } }), true);
  assert.equal(settled({ phone_verified: true, whatsapp: { opt: null } }), false);
});

test('evidence_pack.mjs holds no kyc request and uses recordFixtureMobile', () => {
  const src = readFileSync(new URL('./evidence_pack.mjs', import.meta.url), 'utf8');
  assert.ok(!/p\.route\('\*\*\/functions\/v1\/kyc\*\*'/.test(src), 'the registration no longer routes (holds) the form\'s kyc read');
  assert.match(src, /const fm = await recordFixtureMobile\(\{/);
  assert.match(src, /step\('the fixture mobile is refused by kyc, recorded verified, and the form shows it', fm\.ok && fm\.smsRefused/);
});
