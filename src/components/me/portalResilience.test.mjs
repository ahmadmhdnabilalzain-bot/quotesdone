// portalResilience.test.mjs — the three customer-portal defects found on 22 Sep 2026 stay fixed.
// node --test src/components/me/portalResilience.test.mjs
//
// These are read off the source rather than rendered, because the subject of each one is a line of
// control flow, not a pixel: CP-05 unlocks on the server's word, CP-07 puts a failed load on the
// screen, CP-08 makes the one shared request helper incapable of hanging or throwing. The strings
// themselves are covered by portalText's own bilingual checks.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { errText, t, transportFailed } from './portalText.ts';
import { readCustomerPortal } from '../../../scripts/lib/portal_sources.mjs';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const SRC = readCustomerPortal();
const body = SRC.split(/\r?\n/).filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');

test('CP-05: a reveal is unlocked only when the server says it already is, and names the supplier', () => {
  assert.match(body, /revealedFacts = \(r\) => !!\(r && r\.already_revealed && r\.supplier\)/);
  assert.match(body, /if \(!revealedFacts\(r\)\) \{ setState\('settling'\); return false; \}/);
  // The settling state has words and a way forward, in both languages.
  for (const lang of ['en', 'ar']) for (const k of ['pay_settling', 'pay_check_again', 'pay_checking']) {
    assert.notEqual(t(lang, k), k, `${lang}.${k}`);
  }
});

test('CP-07: a failed overview is rendered, and does not leave skeletons pulsing', () => {
  assert.match(body, /loadOv = \(first\)[\s\S]{0,400}?\.catch\(\(\) => setErr\(/);
  assert.match(body, /\{err && <div[\s\S]{0,400}?role="alert"[\s\S]{0,400}?t\(lang, 'retry'\)/);
  assert.match(body, /const booting = !ov && !data && !err;/);
});

test('CP-08: call() times out, never throws, and never returns a half-parsed answer', () => {
  const fn = body.slice(body.indexOf('async function call('), body.indexOf('const warmDashboard'));
  assert.match(fn, /new AbortController\(\)/);
  // every call has a deadline: 30 s unless the caller names a longer one (the comparison report, PR #1574)
  assert.match(fn, /async function call\(path, body, token, timeoutMs = CALL_TIMEOUT_MS\)/);
  assert.match(fn, /setTimeout\(\(\) => ac\.abort\(\), timeoutMs\)/);
  assert.match(fn, /'qd_timeout'/);
  assert.match(fn, /'qd_network'/);
  assert.match(fn, /JSON\.parse\(text\)/);
  assert.match(fn, /catch \(_e\) \{ return \{ ok: false, error: 'qd_bad_response'/);
  for (const lang of ['en', 'ar']) for (const k of ['err_timeout', 'err_network']) assert.notEqual(t(lang, k), k, `${lang}.${k}`);
});

test('CP-08: a transport sentinel is never filed as the server\'s answer', () => {
  // The three shapes call() can invent, and the ones it must not claim.
  for (const e of ['qd_timeout', 'qd_network', 'qd_bad_response']) assert.equal(transportFailed({ ok: false, error: e }), true, e);
  for (const j of [null, undefined, {}, { ok: true }, { inquiries: [] }, { error: 'unauthorized' }, { ok: false, error: 'stripe_error' }]) {
    assert.equal(transportFailed(j), false, JSON.stringify(j));
  }
  // Every reader that does not test a field of its own asks it before it stores the answer.
  assert.match(body, /if \(transportFailed\(j\)\) \{ setErr\('net'\); return; \}\s*\n\s*setK\(j \|\| \{\}\);/);
  assert.match(body, /if \(transportFailed\(j\)\) \{ setMsg\(t\(lang, 'load_failed'\)\); return; \} setSt\(j\);/);
  // my_inquiries has no `ok`; its contract is the list, and nothing else is stored as one.
  assert.match(body, /if \(!j \|\| !Array\.isArray\(j\.inquiries\)\) \{ setErr\(errText\(j, lang, 'load_failed'\)\); return; \}/);
});

test('CP-05: the card follows the server after the poll confirms the reveal', () => {
  assert.match(body, /useEffect\(\(\) => \{ if \(q\.revealed && state !== 'revealed'\) setState\('revealed'\); \}, \[q\.revealed\]\);/);
  // A revealed quote the server will not hand a contact for falls back to the card that has a retry.
  assert.match(body, /if \(r && r\.supplier\) setContact\([\s\S]{0,200}?else setState\('settling'\);/);
});

test('CP-12: both upload paths go through the same 20 MB guard', () => {
  const nr = fs.readFileSync(new URL('./NewRequest.tsx', import.meta.url), 'utf8');
  assert.match(nr, /const tooBig = \(file\) =>/);
  assert.equal((nr.match(/tooBig\(file\)/g) || []).length, 2, 'both entry points call the one guard');
  assert.match(nr, /MAX_UPLOAD_BYTES = 20 \* 1024 \* 1024/);
});

test('PR #1574: a held Arabic comparison report reaches the customer as a clear Arabic status, not a timeout', () => {
  // The report call waits as long as the edge function may run, so the 202 arrives instead of qd_timeout at 30 s.
  assert.match(body, /const COMPARE_PDF_TIMEOUT_MS = 150000;/);
  assert.match(body, /action: 'compare_pdf'[^\n]*\}, token, COMPARE_PDF_TIMEOUT_MS\)/);
  // The 202 the server sends (customer_api heldReply) is rendered as its own Arabic sentence by errText.
  const api = functionSource('customer_api');
  const held = api.match(/const heldReply = \(\) => J\(\{ ok: false, held: true, code: 'arabic_held',\s*message: '([^']+)',\s*message_ar: '([^']+)' \}, 202\);/);
  assert.ok(held, 'customer_api heldReply keeps its bilingual 202 shape');
  const reply = { ok: false, held: true, code: 'arabic_held', message: held[1], message_ar: held[2] };
  const ar = errText(reply, 'ar', 'cmp_save_fail');
  assert.equal(ar, held[2]);
  assert.match(ar, /[\u0600-\u06FF]/, 'Arabic text');
  assert.match(ar, /سنرسلها/, 'it tells the customer the report will be sent to them');
  assert.notEqual(ar, t('ar', 'cmp_save_fail'), 'not the generic failure line');
  assert.equal(errText(reply, 'en', 'cmp_save_fail'), held[1]);
});
