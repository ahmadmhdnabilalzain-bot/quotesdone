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
import { t } from './portalText.ts';

const SRC = fs.readFileSync(new URL('./CustomerPortal.tsx', import.meta.url), 'utf8');
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
  assert.match(fn, /setTimeout\(\(\) => ac\.abort\(\), CALL_TIMEOUT_MS\)/);
  assert.match(fn, /'qd_timeout'/);
  assert.match(fn, /'qd_network'/);
  assert.match(fn, /JSON\.parse\(text\)/);
  assert.match(fn, /catch \(_e\) \{ return \{ ok: false, error: 'qd_bad_response'/);
  for (const lang of ['en', 'ar']) for (const k of ['err_timeout', 'err_network']) assert.notEqual(t(lang, k), k, `${lang}.${k}`);
});

test('CP-12: both upload paths go through the same 20 MB guard', () => {
  const nr = fs.readFileSync(new URL('./NewRequest.tsx', import.meta.url), 'utf8');
  assert.match(nr, /const tooBig = \(file\) =>/);
  assert.equal((nr.match(/tooBig\(file\)/g) || []).length, 2, 'both entry points call the one guard');
  assert.match(nr, /MAX_UPLOAD_BYTES = 20 \* 1024 \* 1024/);
});
