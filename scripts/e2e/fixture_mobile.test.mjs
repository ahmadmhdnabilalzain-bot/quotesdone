// The registration's fixture mobile is recorded verified without racing the form (./fixture_mobile.mjs says what was
// measured: evidence run 8120d011, 10 Nov 2026). Offline: a simulated portal whose form reads kyc 'state' once, with the
// supplier portal's 20 s abort, and a harness whose send_sms takes as long as the live run's (33,345 ms), scaled 1:1000.
//   node --test scripts/e2e/fixture_mobile.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { recordFixtureMobile, recordFixtureMobileBeforeTheForm, settled } from './fixture_mobile.mjs';

const SCALE = 1000;                       // 1 ms here = 1 s live
const PORTAL_ABORT = 20000 / SCALE;       // src/components/portal/supplier/api.ts TIMEOUT_MS
const LIVE_SEND_SMS = 33345 / SCALE;      // kyc send_sms, function_edge_logs 20:11:20.284Z
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The server (leads row + kyc) and the form (one kyc read on mount, aborted at PORTAL_ABORT, gated by `gate`). */
function world({ sendSmsMs = LIVE_SEND_SMS, chooseMs = 0 } = {}) {
  const db = { phone_verified: false, opt: null };
  const kyc = () => ({ ok: true, phone_verified: db.phone_verified, whatsapp: db.opt ? { opt: db.opt } : { opt: null } });
  const form = { reads: 0, shown: null, routed: false };
  const mountForm = async (gate = Promise.resolve()) => {
    form.reads++;
    const read = gate.then(() => kyc());
    const aborted = sleep(PORTAL_ABORT).then(() => ({ ok: false, code: 'timeout' }));
    const k = await Promise.race([read, aborted]);
    form.shown = !!(k && k.phone_verified);
    form.lost = !!(k && k.code === 'timeout');
  };
  const deps = {
    sendSms: async () => { await sleep(sendSmsMs); return { ok: false, code: 'fixture_number' }; },
    markVerified: async () => { db.phone_verified = true; },
    chooseWhatsapp: async () => { if (chooseMs) await sleep(chooseMs); db.opt = 'same'; return { ok: true }; },
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

// 11 Nov 2026 (registration certification 3b): evidence_pack.mjs walked the same registration with the reload path, which lands in
// the workspace on production. It now takes the one-mount path the certification takes; this fails if the reload comes back.
test('evidence_pack.mjs uses the one-mount path, never a reload', () => {
  const src = readFileSync(new URL('./evidence_pack.mjs', import.meta.url), 'utf8');
  assert.match(src, /const fm = await recordFixtureMobileBeforeTheForm\(\{/);
  assert.ok(!/reloadForm:/.test(src), 'a reload after Create company lands in the workspace');
  assert.ok(!/await recordFixtureMobile\(/.test(src), 'the reload path is back');
  // re-pinned 12 Nov 2026 (founder ruling 1672): there is no "Create company"; Verify mounts the form, so Verify is inside the held read
  assert.match(src, /openForm: async \(\) => \{\s*await box\.getByRole\('button', \{ name: \/\^Verify and continue\$\|\^Verify\/ \}\)\.first\(\)\.click\(\);/, 'Verify mounts the form inside the held read');
  assert.ok(!/getByRole\('textbox', \{ name: \/Company name\/ \}\)\.first\(\), company/.test(src), 'the walk types a company name again');
  assert.match(src, /step\('the fixture mobile is refused by kyc, recorded verified, and the form shows it', fm\.ok && fm\.smsRefused/);
});

// 11 Nov 2026: on production a reload after "Create company" lands in the workspace, never the form (Dashboard: Onboarding only
// for 'no_company'). The form is mounted ONCE, by the action that creates or claims the company; its read is held only across the
// fast writes, and the slow send_sms comes after.
test('recordFixtureMobileBeforeTheForm: one mount, the read held across the fast writes only, send_sms after', async () => {
  for (const ms of [5, LIVE_SEND_SMS, 3 * LIVE_SEND_SMS]) {
    const w = world({ sendSmsMs: ms });
    let gate = null, release = null, mounted = null;
    const deps = { ...w.deps,
      holdFormRead: async () => { gate = new Promise((r) => { release = r; }); return () => release(); },
      openForm: async () => { mounted = w.mountForm(gate); await sleep(2); },   // Create company: the form mounts and asks kyc once
      formShowsVerified: async () => { await mounted; return w.form.shown === true; },
      reloadForm: async () => { throw new Error('no reload: a reload lands in the workspace'); } };
    const r = await recordFixtureMobileBeforeTheForm(deps, { holdMaxMs: 15000 / SCALE, everyMs: 1 });
    assert.equal(r.ok, true, `send_sms ${ms * SCALE} ms: ${r.detail}`);
    assert.equal(r.smsRefused, true);
    assert.equal(w.form.reads, 1, 'the form was mounted once, never reloaded');
    assert.ok(r.heldMs < PORTAL_ABORT, `the read was held ${r.heldMs} (scaled) - under the portal's 20 s abort`);
  }
});

test('the certification uses the one-mount path; a reload only after a harness fault, and only into the registration form', () => {
  const src = readFileSync(new URL('./supplier_registration_certification.mjs', import.meta.url), 'utf8');
  assert.match(src, /recordFixtureMobileBeforeTheForm\(\{/);
  assert.ok(!/await recordFixtureMobile\(/.test(src), 'the reload-first path is back');
  // 16 Nov 2026: since 11 Nov a reload before Submit reopens the form (Dashboard `registering`); the reload waits for the form itself
  assert.match(src, /reloadForm: async \(\) => \{ await p\.reload\(\{ waitUntil: 'domcontentloaded' \}\); await formHeading\.waitFor\(\{ timeout: 45000 \}\); \}/);
});

// 11 Nov 2026, free certification run 1, J4 mobile: the harness's kyc whatsapp_choose ran 54,590 ms at the edge (16:01:07.720Z).
// The hold ended only when the writes settled, so the form's read was held 64 s and aborted by the portal at 20 s: the harness
// decided what the form showed. The hold now has its own clock under the abort, and the step names the harness as the cause.
const LIVE_WHATSAPP_CHOOSE = 54590 / SCALE;
test('a harness write slower than the portal\'s abort never holds the form\'s read past it, and the failure names the harness', async () => {
  const w = world({ sendSmsMs: 1, chooseMs: LIVE_WHATSAPP_CHOOSE });
  let gate = null, release = null, mounted = null;
  const deps = { ...w.deps,
    holdFormRead: async () => { gate = new Promise((r) => { release = r; }); return () => release(); },
    openForm: async () => { mounted = w.mountForm(gate); await sleep(2); },
    reloadForm: undefined,   // no reload given: the fault stands (the reload case is the next test)
    formShowsVerified: async () => { await mounted; return w.form.shown === true; } };
  const r = await recordFixtureMobileBeforeTheForm(deps, { holdMaxMs: 15000 / SCALE, everyMs: 1 });
  await mounted;
  assert.ok(r.heldMs < PORTAL_ABORT, `the read was held ${r.heldMs} (scaled), past the portal's 20 s abort`);
  assert.equal(w.form.lost, false, 'the portal aborted the held read: the harness, not the product, decided the form');
  assert.equal(r.ok, false, 'the form read before the fixture mobile was recorded, so it cannot show it');
  assert.equal(r.harnessFault, true);
  assert.match(r.detail, /the harness's own writes outlasted the hold/);
  assert.match(r.detail, /whatsapp_choose/);
  assert.equal(w.db.phone_verified, true, 'the writes still finish, so the server holds the truth for Submit');
  assert.equal(w.db.opt, 'same');
});

// 16 Nov 2026, paid certification 5c5ef298 J10 mobile: the harness's kyc whatsapp_choose took 53,110 ms (a Supabase edge isolate held
// seven kyc calls before our code). The writes did land, so the form is loaded again and its own read judged; it fails only when that
// read does not show the truth, and a fault with no reload given still fails as before.
test('when the harness\'s writes outlast the hold, the form is loaded again once kyc reads verified, and that read is judged', async () => {
  for (const reloadShows of [true, false]) {
    const w = world({ sendSmsMs: 1, chooseMs: 53110 / SCALE });
    let gate = null, release = null, mounted = null;
    const deps = { ...w.deps,
      holdFormRead: async () => { gate = new Promise((r) => { release = r; }); return () => release(); },
      openForm: async () => { mounted = w.mountForm(gate); await sleep(2); },
      reloadForm: async () => { await mounted; if (reloadShows) await w.mountForm(); else w.form.shown = null; },   // false: the reload never showed the form
      formShowsVerified: async () => { await mounted; return w.form.shown === true; } };
    const r = await recordFixtureMobileBeforeTheForm(deps, { holdMaxMs: 15000 / SCALE, everyMs: 1 });
    assert.equal(r.harnessFault, true); assert.equal(r.reloaded, true);
    assert.match(r.detail, /the harness's own writes outlasted the hold[\s\S]*loaded again once kyc read verified/);
    assert.equal(r.ok, reloadShows, r.detail);
    assert.equal(w.form.reads, reloadShows ? 2 : 1);
  }
});
