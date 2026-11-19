// The support-case rating card (SupportRatingPrompt.tsx) is fixed to a corner of both portals. Stage-2 run f0b2de8f (2 Nov 2026) found it
// 22rem wide and 15rem tall at the START corner: over the sidebar's Account and Documents items on a laptop ("nav item Account could not
// be pressed", S16/S26) and over the request box on a phone ("something lies on top of the box", S26). A customer or supplier with a
// closed case could not reach their own account page. It now sits in the END corner (opposite the sidebar in both directions of text),
// is one line until the person chooses to rate, and "Not now" is remembered for the browser session instead of returning on every page.
//   node --test scripts/checks/a_support_rating_prompt_never_covers_navigation.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../src/components/portal/SupportRatingPrompt.tsx', import.meta.url), 'utf8');

test('the card is fixed to the end corner, never the start corner where the sidebar is', () => {
  // Tailwind 4 (#1201) spells the logical insets inset-s-* / inset-e-*; start-*/end-* are the v3 names.
  // #2072 (19 Nov 2026, notched phones) keeps the 1rem gap but grows it to the safe-area inset:
  // `bottom-[max(1rem,env(...))] inset-e-[max(1rem,env(...))]`. Still the end corner; the plain 4 is also accepted.
  assert.match(src, /fixed bottom-(?:4|\[max\(1rem,env\(safe-area-inset-bottom\)\)\]) inset-e-(?:4|\[max\(1rem,env\(safe-area-inset-[a-z]+\)\)\])[\s"]/);
  assert.doesNotMatch(src, /fixed [^"]*\b(?:inset-s|start)-/);
});

test('it is one line until the person chooses to rate: the scales are only in the open branch', () => {
  const closed = src.slice(src.indexOf('!open ? ('), src.indexOf(') : (<>'));
  assert.ok(closed.length > 0 && !/<Scale/.test(closed), 'the collapsed branch renders no rating scale');
  assert.match(src, /onClick=\{\(\) => setOpen\(true\)\}/);
});

test('"Not now" is remembered for the session and a remembered case is not asked again', () => {
  assert.match(src, /const notNow = \(\) => \{ if \(cur\) skip\(cur\.case_ref\); next\(\); \}/);
  assert.match(src, /sessionStorage\.setItem\(SKIP_KEY/);
  assert.match(src, /filter\(\(d: Due\) => !skipped\(\)\.includes\(d\.case_ref\)\)/);
  assert.equal((src.match(/onClick=\{notNow\}/g) || []).length, 2, 'both "Not now" buttons use it');
});

test('storage that throws never breaks the card', () => {
  assert.match(src, /try \{ return JSON\.parse\(sessionStorage\.getItem\(SKIP_KEY\) \|\| '\[\]'\); \} catch \{ return \[\]; \}/);
});
