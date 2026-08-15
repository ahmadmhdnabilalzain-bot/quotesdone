// Every os_api action must be explicitly classified. This is the build gate the founder asked for:
// it fails when an action is added without a classification, so "we forgot to register it" cannot
// reach production as "it was treated as read-only".
//
// Runs with the Node built-in test runner, no dependency to install:
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { readSource, extractDispatched, extractClassification, ACTION_CLASSES } from './extract_os_actions.mjs';

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

// ── THE SECOND LIST, WHICH THIS FILE KNEW ABOUT AND NEVER CHECKED ──────────────────────────────
//
// The test above already tells you to "add each to ACTION_CLASS and to public.control_mode_action".
// It then only ever compared the code against ITSELF. Both gates refuse independently — that is
// the design — but nothing kept the two lists in step, and by 13 Aug 2026 they had drifted by
// eleven: ACTION_CLASS 73, control_mode_action 90, and 11 actions in the code that the database
// had never heard of.
//
// The symptom was not a quiet one, it was just aimed at the wrong person. The database gate refuses
// an unregistered action with `action_classification_required`, and the console renders that as the
// Control Mode panel — so opening System Health asked the founder for a code sent to his phone in
// order to look at a dashboard. Eight of the eleven were read_only.
//
// ONLY ONE DIRECTION IS ASSERTED, and the reason is measured rather than assumed. The first draft
// also asserted the reverse — registered in the database, absent from the code — and it failed on
// 28 actions: action_decide, po_approve, cancel_inquiry, gl_post, task_create and the rest. They
// are all dispatched by os_ops. control_mode_action is SHARED across os_api and os_ops, so this
// file cannot see the whole of the other side and an assertion that it can would fail for a
// non-reason on every run. The direction that matters is checked: an action the code will dispatch
// and the database will refuse is the one that reaches a human as a challenge.
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

test('every classified action is registered in public.control_mode_action, with the same classification', async (t) => {
  if (!mgmtToken) {
    t.skip('no SUPABASE_ACCESS_TOKEN and no local access token, so the database gate cannot be read. '
      + 'The two lists are compared from a session that has the management token; the code-only '
      + 'assertions above still ran.');
    return;
  }
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'select action, classification from public.control_mode_action' }),
  });
  assert.ok(r.ok, `could not read control_mode_action: ${r.status}`);
  const rows = await r.json();
  const db = new Map(rows.map((x) => [x.action, x.classification]));

  const missing = [...classified.keys()].filter((a) => !db.has(a)).sort();
  assert.deepEqual(missing, [], `classified in os_api but NOT registered in public.control_mode_action: `
    + `${missing.join(', ')}. The database gate refuses these as unclassified, and the console shows `
    + `that refusal to the founder as a Control Mode challenge — including for read_only screens.`);

  const disagree = [...classified].filter(([a, c]) => db.has(a) && db.get(a) !== c)
    .map(([a, c]) => `${a}: code=${c} db=${db.get(a)}`).sort();
  assert.deepEqual(disagree, [], `the two gates classify these differently: ${disagree.join('; ')}`);

  // Reported, never asserted — see the note above: the table is shared with os_ops, so a row this
  // file cannot account for is usually os_ops's and not a fault.
  const dbOnly = [...db.keys()].filter((a) => !classified.has(a));
  console.log(`os_api actions: ${classified.size} classified, all registered. `
    + `control_mode_action holds ${db.size}, of which ${dbOnly.length} belong to another function (os_ops).`);
});

test('no classification is left behind for an action that no longer exists', () => {
  const stale = [...classified.keys()].filter((a) => !dispatched.has(a)).sort();
  assert.deepEqual(stale, [],
    `ACTION_CLASS lists actions os_api no longer dispatches: ${stale.join(', ')}`);
});

test('every classification is one of the legal values', () => {
  // One list, shared with the parser in extract_os_actions.mjs. Two copies would drift, and the
  // drift is silent in the worst direction: a class the parser knows but this test rejects, or a
  // class this test allows but the parser cannot see — which reads as "dispatched but
  // unclassified" and fires the loudest alarm in the file for the most boring reason.
  const legal = new Set(ACTION_CLASSES);
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

test('founder_gated is pinned to the founder command channel only', () => {
  // The second class allowed past Control Mode, added 15 Aug 2026 so the founder's own channel
  // stops demanding a phone code for every order. It is a real control - the caller must be in
  // phase_c_founder_identity - but it is still an EXEMPTION, and an exemption that can spread is a
  // loophole. Enumerated here and pinned by control_mode_action_founder_gated_pinned in the
  // database, so both layers have to be defeated at once.
  const allowed = new Set(['founder_command', 'founder_command_control']);
  const leaked = [...classified].filter(([a, c]) => c === 'founder_gated' && !allowed.has(a)).map(([a]) => a);
  assert.deepEqual(leaked, [], `founder_gated must not be used for ordinary actions: ${leaked.join(', ')}`);
});

test('founder_gated actions are still audited and still outside the preview bypass', () => {
  // The two halves that make the exemption survivable. Losing either is silent: the action keeps
  // working, and only the record of it disappears.
  assert.match(src, /ACTION_CLASS\[a\] === 'mutating' \|\| ACTION_CLASS\[a\] === 'founder_gated'/,
    'founder_gated actions must be in OSAPI_MUTATIONS so os_api writes an audit row for them');
  assert.match(src, /ACTION_CLASS\[a\] === 'read_only' && !BYPASS_DENY\.has\(a\)/,
    'the x-os-key preview bypass must still allow only read_only actions');
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

test('the authenticated user id is read from a hoisted variable, not an out-of-scope one', () => {
  // Regression guard for the bug that made Control Mode unopenable: control_mode_open read
  // `u?.user?.id`, but `u` is declared with const inside the else branch of the auth block, so at
  // runtime it threw a ReferenceError that the outer catch returned as an opaque 500. Every
  // database-level test of Control Mode passed while the API path could never work.
  //
  // `deno check` in CI catches this class properly. This assertion is the cheap, specific version
  // that also runs on a laptop with no Deno installed.
  assert.match(src, /let userId: string \| null = null;/,
    'os_api no longer hoists userId out of the auth block');
  const declAt = src.indexOf('const { data: u, error: uerr }');
  assert.ok(declAt > 0, 'the auth block no longer looks the way this check expects');
  const closeBrace = src.indexOf('\n    }', declAt);
  const afterAuth = src.slice(closeBrace);
  assert.ok(!/\bu\?\./.test(afterAuth),
    'os_api references `u` after the block where it is declared has closed - that is the ReferenceError');
});

test('no phone number is hardcoded anywhere in os_api', () => {
  // The founder's number lives in app_secrets. A literal international number in source is both a
  // leak and a thing that goes stale.
  const numbers = src.match(/\+\d{7,}/g) || [];
  assert.deepEqual(numbers, [], `hardcoded phone numbers found: ${numbers.join(', ')}`);
});
