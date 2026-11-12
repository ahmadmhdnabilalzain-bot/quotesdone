// THE ROLE LIST IS NEVER SHOWN AS A SUGGESTION (12 Nov 2026, sales_engineer, built by it_engineer; founder ruling, ledger 1670:
// "how can a real estate company be a designer? Where was it mentioned anywhere in the company profile ... we have to be realistic
// with the suggestions, not just random").
//
// Measured on production: the reading of his real-estate profile read one role, `consultant`, and nothing else. "Designer" came from
// the screen: ServicesTab's "Your role" drew EVERY role of the vocabulary (the same fixed list for every company) as unlabelled chips
// whenever no role was set yet (before the reading landed, or when it read none) and whenever he tapped Change. Now the screen shows
// what is his or what the reading read (said so in words), asks in words when there is none, and draws the complete list only when he
// asks for it, under "All roles. Choose only what your company does.". This fails if any of that comes back.
//   node --test scripts/checks/the_role_list_is_never_shown_as_a_suggestion.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (f) => readFileSync(new URL('../../' + f, import.meta.url), 'utf8');
const { roleView } = await import(new URL('../../src/components/portal/supplier/servicesRead.ts', import.meta.url).href);
const tab = read('src/components/portal/supplier/ServicesTab.tsx');
const copy = read('src/components/portal/supplier/servicesCopy.ts');

test('the reading read "consultant": that is what is shown, said to come from his profile, and no other role', () => {
  assert.deepEqual(roleView({ roles: ['consultant'], confirmed: [], read: ['consultant'], editing: false }), { mode: 'chosen', fromReading: true });
});

test('no role yet (the reading not landed, or it read none): he is asked in words, no list is drawn', () => {
  assert.deepEqual(roleView({ roles: [], confirmed: [], read: [], editing: false }), { mode: 'ask', fromReading: false });
});

test('the complete list appears only when he asks for it', () => {
  assert.equal(roleView({ roles: ['consultant'], confirmed: [], read: ['consultant'], editing: true }).mode, 'all');
  assert.equal(roleView({ roles: [], confirmed: [], read: [], editing: true }).mode, 'all');
});

test('a role he confirmed is his, not "read from your profile"', () => {
  assert.deepEqual(roleView({ roles: ['contractor'], confirmed: ['contractor'], read: ['consultant'], editing: false }), { mode: 'chosen', fromReading: false });
  assert.equal(roleView({ roles: ['contractor'], confirmed: [], read: ['consultant'], editing: false }).fromReading, false);
});

test('the Services tab draws the vocabulary of roles only under its "All roles" label, in the mode he asked for', () => {
  const at = tab.indexOf("aria-labelledby={uid + '-role'}");
  assert.ok(at > 0, 'the role section was not found');
  const section = tab.slice(at, tab.indexOf('ADDING: ONE TEXT BOX', at));
  const list = section.indexOf('d.vocabulary.roles.map');
  assert.ok(list > 0, 'the complete list is still offered on request');
  const before = section.slice(0, list);
  assert.match(before, /rv\.mode === 'chosen'[\s\S]*rv\.mode === 'ask'[\s\S]*F\.role_all/, 'the list must sit in the third branch, after its label');
  // a drawing maps each role to markup (`=> (`); the one data use, the set of known codes, maps to `r.code`
  assert.equal((tab.match(/d\.vocabulary\.roles\.map\(\(\w+\) => \(/g) || []).length, 1, 'no second unlabelled drawing of every role');
  assert.match(copy, /role_all: 'All roles\. Choose only what your company does\.'/);
  assert.match(copy, /role_ask: '[^']*Choose[^']*'/);
});
