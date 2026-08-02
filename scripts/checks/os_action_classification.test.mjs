// Every os_api action must be explicitly classified. This is the build gate the founder asked for:
// it fails when an action is added without a classification, so "we forgot to register it" cannot
// reach production as "it was treated as read-only".
//
// Runs with the Node built-in test runner, no dependency to install:
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSource, extractDispatched, extractClassification } from './extract_os_actions.mjs';

const src = readSource();
const dispatched = extractDispatched(src);
const classified = extractClassification(src);

test('os_api declares an ACTION_CLASS table', () => {
  assert.ok(classified, 'ACTION_CLASS not found in os_api/index.ts - the classification gate is missing');
  assert.ok(classified.size > 0, 'ACTION_CLASS is empty');
});

test('every dispatched action is explicitly classified', () => {
  const missing = [...dispatched].filter((a) => !classified.has(a)).sort();
  assert.deepEqual(missing, [],
    `these os_api actions have no classification: ${missing.join(', ')}. ` +
    'Add each to ACTION_CLASS and to public.control_mode_action before shipping.');
});

test('no classification is left behind for an action that no longer exists', () => {
  const stale = [...classified.keys()].filter((a) => !dispatched.has(a)).sort();
  assert.deepEqual(stale, [],
    `ACTION_CLASS lists actions os_api no longer dispatches: ${stale.join(', ')}`);
});

test('every classification is one of the three legal values', () => {
  const legal = new Set(['read_only', 'mutating', 'mode_control']);
  const bad = [...classified].filter(([, c]) => !legal.has(c)).map(([a, c]) => `${a}=${c}`);
  assert.deepEqual(bad, [], `illegal classification values: ${bad.join(', ')}`);
});

test('mode_control is pinned to Control Mode plumbing only', () => {
  // The one class that is allowed past the gate. If it ever grows, it becomes the loophole the
  // whole exercise exists to close, so it is enumerated here and in a CHECK constraint.
  const allowed = new Set(['control_mode_status', 'control_mode_open', 'control_mode_close', 'control_mode_challenge']);
  const leaked = [...classified].filter(([a, c]) => c === 'mode_control' && !allowed.has(a)).map(([a]) => a);
  assert.deepEqual(leaked, [], `mode_control must not be used for ordinary actions: ${leaked.join(', ')}`);
});

test('a new mutating action cannot execute until it is classified', () => {
  // Simulates the exact mistake: an action added to the dispatch table and nowhere else.
  const withNewAction = src.replace(
    "if (action === 'ping') return J({ ok: true, user: email });",
    "if (action === 'danger_new_thing') return J({ ok: true });\n    if (action === 'ping') return J({ ok: true, user: email });",
  );
  const d2 = extractDispatched(withNewAction);
  const c2 = extractClassification(withNewAction);
  assert.ok(d2.has('danger_new_thing'), 'the simulated action was not picked up - the parser is wrong, not the code');
  assert.ok(!c2.has('danger_new_thing'), 'the simulated action should not be classified');
  const missing = [...d2].filter((a) => !c2.has(a));
  assert.deepEqual(missing, ['danger_new_thing'],
    'an unclassified action must be reported by this check - otherwise the gate is decorative');
});

test('os_api refuses an unclassified action rather than defaulting to read-only', () => {
  // The behaviour, asserted against the source: there is a refusal keyed on ACTION_CLASS lookup
  // failure, and it returns action_classification_required.
  assert.match(src, /if \(!ACTION_CLASS\[action\]\)/,
    'os_api does not refuse unclassified actions');
  assert.match(src, /action_classification_required/,
    'os_api does not return action_classification_required');
  // And it happens before any handler runs.
  const refusalAt = src.indexOf('action_classification_required');
  const firstHandlerAt = src.indexOf("if (action === 'control_mode_status')");
  assert.ok(refusalAt > 0 && refusalAt < firstHandlerAt,
    'the classification refusal must come before the first action handler');
});

test('the Control Mode gate fails closed when the database cannot answer', () => {
  // Regression guard. The first version swallowed every error from fn_control_mode_require and
  // carried on, so an unavailable database silently ungated every mutation.
  assert.match(src, /control_mode_unavailable/,
    'a failed gate lookup must refuse mutating actions, not fall through');
  assert.doesNotMatch(src, /catch \(_e\) \{ \/\* a lookup failure must not block reads/,
    'the old fall-through comment is still present, so the old behaviour probably is too');
});

test('Control Mode MFA is purpose-bound, not a generic phone verification', () => {
  // phone_verifications is written by login_otp and kyc. Control Mode must not read it.
  assert.doesNotMatch(src, /p_phone:\s*String\(body\?\.phone/,
    'os_api still passes a caller-supplied phone into Control Mode');
  assert.match(src, /fn_control_mode_challenge_start/,
    'os_api does not use the purpose-bound challenge');
  assert.match(src, /p_challenge_id/, 'control_mode_open no longer takes a challenge id');
  assert.match(src, /p_nonce/, 'control_mode_open no longer takes a nonce');
});

test('the Control Mode code is generated from a CSPRNG', () => {
  assert.match(src, /crypto\.getRandomValues/, 'the Control Mode code must not come from Math.random');
  assert.doesNotMatch(src, /Math\.random\(\)/, 'Math.random is not acceptable for a credential');
});

test('no phone number is hardcoded anywhere in os_api', () => {
  // The founder's number lives in app_secrets. A literal international number in source is both a
  // leak and a thing that goes stale.
  const numbers = src.match(/\+\d{7,}/g) || [];
  assert.deepEqual(numbers, [], `hardcoded phone numbers found: ${numbers.join(', ')}`);
});
