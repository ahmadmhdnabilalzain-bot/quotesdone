// ceo (journey verification): A PHONE TAP IS NEVER HIDDEN UNDER THE ASSISTANT (10 Nov 2026).
// Measured on production (e2e run tag b9d7d1d5, journey f, 375 px, EN and AR): with the account assistant open, the
// tab bar changed views underneath it and the More sheet opened underneath it, so 7 of 10 destinations could not be
// reached and a customer saw nothing happen. The rule lives in src/lib/portalPanels.ts; this file proves the rule and
// that PortalShell uses it. On origin/main 17098f34b the wiring tests fail (the shell never closes the assistant).
//   node --test scripts/checks/a_phone_tap_is_never_hidden_under_the_assistant.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { afterNavigate, afterMoreToggle, afterEscape } from '../../src/lib/portalPanels.ts';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
// code only: a comment that names a call must not satisfy the check
const code = (src) => src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*|\{\/\*)/.test(l)).join('\n');
const shell = code(read('src/components/me/PortalShell.tsx'));
const open = { asst: true, more: false, bell: false };

test('a destination chosen on a phone closes the full-width assistant; on a wide screen it stays', () => {
  assert.deepEqual(afterNavigate(open, true), { asst: false, more: false, bell: false });
  assert.deepEqual(afterNavigate(open, false), { asst: true, more: false, bell: false });
  assert.deepEqual(afterNavigate({ asst: false, more: true, bell: false }, true), { asst: false, more: false, bell: false });
});

test('opening More closes the assistant; closing More leaves the assistant as it was', () => {
  assert.deepEqual(afterMoreToggle(open), { asst: false, more: true, bell: false });
  assert.deepEqual(afterMoreToggle({ asst: true, more: true, bell: false }), { asst: true, more: false, bell: false });
});

test('Escape closes every panel, the assistant included', () => {
  assert.deepEqual(afterEscape({ asst: true, more: true, bell: true }), { asst: false, more: false, bell: false });
});

test('PortalShell navigates, toggles More and handles Escape through the rule', () => {
  assert.ok(/const go = \(id\) => \{[^\n]*afterNavigate\(/.test(shell), 'go() does not apply afterNavigate: a tab chosen on a phone opens under the assistant');
  assert.ok(/ref=\{moreBtn\} onClick=\{[^\n]*afterMoreToggle\(/.test(shell), 'the More button does not apply afterMoreToggle: its sheet opens under the assistant');
  assert.ok(/e\.key === 'Escape'\)[^\n]*afterEscape\(/.test(shell), 'Escape does not apply afterEscape: it leaves the assistant open');
  assert.ok(!/ref=\{moreBtn\} onClick=\{\(\) => setMoreOpen\(\(v\) => !v\)\}/.test(shell), 'the More button toggles the sheet alone again');
});
