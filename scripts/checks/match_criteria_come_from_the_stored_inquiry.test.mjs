// A NAMED INQUIRY DECIDES ITS OWN MATCH CRITERIA — THE CALLER DOES NOT.
//
// 23 Sep 2026 (sales_engineer). The `match` action of supabase/functions/sales_engineer/index.ts
// took `body.inquiry_id` and then read `body.trades`, `body.products`, `body.brands`,
// `body.emirate`, `body.value`, `body.project_type`, `body.need` and `body.text` as `body.x || inq.x`
// — so the body won on every criterion of an inquiry the caller had not been checked against.
//
// PROVED OPEN ON PRODUCTION BEFORE THE FIX, on the ZZ DEMO gypsum inquiry with persist:false:
// the honest call returned asked_for.trades ['gypsum'] and 1 supplier; the same call with
// `trades:['painting'], emirate:'Sharjah'` in the body returned asked_for.trades ['painting'] and 0.
// A customer JWT could not reach the branch (the `caller.kind === 'customer'` cutoff refuses it
// first) and no caller in the repository passes criteria — customer_api.matchAndNotify sends
// inquiry_id and persist:false only. The lever was reachable with the sales_engineer credential, an
// internal credential or the founder's admin JWT, which is narrower than the hand-over claimed and
// is still not a guard.
//
// This fails if any of the properties the fix rests on is removed:
//   1. the branch reads customer_id, so an ownership comparison is one line away;
//   2. the customer cutoff still precedes the branch, with the type that makes the build enforce it;
//   3. no criterion is written as a body-OR-inquiry fallback again;
//   4. every criterion is read from the one `src` source, which is `inq ?? {…}`.
//
// Comments are stripped before every match, because a check that greps source will otherwise match
// its own prose — and this file's header names every pattern it forbids.
//
//   node --test scripts/checks/match_criteria_come_from_the_stored_inquiry.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FN = 'supabase/functions/sales_engineer/index.ts';

const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

function matchBranch() {
  const src = readFileSync(REPO + FN, 'utf8');
  const from = src.indexOf("if (action === 'match') {");
  const to = src.indexOf("if (action === 'health') {", from);
  assert.ok(from > 0 && to > from, 'the match branch was not found in ' + FN);
  return stripComments(src.slice(from, to));
}

test('the match branch reads the inquiry owner, so ownership can be decided', () => {
  assert.match(matchBranch(), /\.select\('id,customer_id[^']*'\)/,
    'the inquiries select no longer reads customer_id — ownership cannot be checked without it');
});

test('no caller without an owner check can reach match, and the build enforces it', () => {
  // A runtime `if (caller.kind === 'customer')` inside the branch DOES NOT COMPILE — `deno check`
  // narrows caller to never there, because the cutoff has already returned. So the invariant is a
  // type, and this asserts both halves of it: the cutoff still precedes the branch in source order,
  // and the assignment that goes red if it ever stops doing so is still present. Measured 23 Sep 2026:
  // deleting the cutoff makes `deno check` fail with TS2322 on that assignment.
  const src = readFileSync(REPO + FN, 'utf8');
  const cutoff = src.indexOf("if (caller.kind === 'customer') return J({ error: 'forbidden', action }, 403);");
  const branch = src.indexOf("if (action === 'match') {");
  assert.ok(cutoff > 0, 'the customer cutoff is gone from sales_engineer');
  assert.ok(cutoff < branch, 'match is now reachable by a customer caller: it sits above the cutoff');
  assert.match(matchBranch(), /const _onlyOperatorsReachMatch: Exclude<typeof caller, \{ kind: 'customer' \}> = caller;/,
    'the build-enforced ownership invariant was removed from the match branch');
});

test('no match criterion falls back from the body to the inquiry', () => {
  const b = matchBranch();
  const bad = [];
  // No \b before the operator: `|` and `?` are non-word characters and the character before them is
  // a space, so a word boundary there can never match and the check would pass on anything. It did,
  // on the pre-fix source, until that was run and measured.
  for (const m of b.matchAll(/[^;\n]*(?:\|\||\?\?)[^;\n]*/g)) {
    const line = m[0];
    if (/\bbody\.\w+/.test(line) && /\binq\b/.test(line)) bad.push(line.trim().slice(0, 140));
  }
  assert.deepEqual(bad, [],
    'a criterion is read as body-or-inquiry again; the stored inquiry must decide on its own');
});

test('every criterion is read from the one src source', () => {
  const b = matchBranch();
  assert.match(b, /const src: Record<string, unknown> = inq \?\?/,
    'the single criteria source `src = inq ?? {…}` is gone');
  // The only body reads allowed outside that initialiser are the request's own controls and the two
  // fields with no stored equivalent, each gated on there being no inquiry at all.
  const init = b.slice(b.indexOf('const src: Record<string, unknown> = inq ??'));
  const initEnd = init.indexOf('};') + 2;
  const outside = b.replace(init.slice(0, initEnd), ' ');
  const allowed = new Set(['body.inquiry_id', 'body.persist', 'body.products', 'body.brands', 'body.need']);
  const stray = [...new Set([...outside.matchAll(/body\.\w+/g)].map((m) => m[0]))].filter((x) => !allowed.has(x));
  assert.deepEqual(stray, [], 'a criterion is read straight off the body outside the src initialiser');
  for (const f of ['products', 'brands']) {
    assert.match(outside, new RegExp('inq \\? \\[\\] : arr\\(body\\.' + f + '\\)'),
      f + ' is no longer emptied on a named inquiry — it would narrow somebody else\'s match');
  }
  assert.match(outside, /const needAsked = inq \? '' : body\.need;/,
    'body.need is no longer ignored on a named inquiry');
});

test('the one runtime caller still passes only inquiry_id and persist', () => {
  // If this ever changes, the derivation above starts discarding something a caller relies on.
  const capi = functionSource('customer_api');
  const call = capi.slice(capi.indexOf('functions/v1/sales_engineer'));
  const body = call.slice(call.indexOf('JSON.stringify('), call.indexOf(') })'));
  assert.match(body, /action: 'match'/, 'customer_api no longer asks for a match here');
  const keys = [...new Set([...body.matchAll(/(\w+):/g)].map((m) => m[1]))]
    .filter((k) => !['__secret', 'action'].includes(k));
  assert.deepEqual(keys.sort(), ['inquiry_id', 'persist'],
    'customer_api now sends match criteria of its own: ' + keys.join(','));
});
