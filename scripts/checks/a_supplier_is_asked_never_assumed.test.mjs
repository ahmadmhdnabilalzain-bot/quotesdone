// A SUPPLIER IS ASKED, NEVER ASSUMED (12 Nov 2026, sales_engineer; founder rulings 1647, 1628 and 862; report
// docs/reports/2026-11-12-supplier-service-profiling.md, slice 1). Offline: reads the Services tab's source and its copy.
//
// Measured that day: the one real supplier through this step confirmed 33 service keys, whole trades ticked, from a 22-word
// description, and is matched for dosing pumps and heat treatment his words never name. On the hard-profile set 4 of 12 companies
// whose readings agreed on nothing ('held') were told "We are still reading your documents" for ever, and nothing ever asked them.
//   1. no trade's checklist can be ticked in one tap: no "Select all" per trade, in either language;
//   2. the checklist is browsed, under "Browse all services of my trades", open by itself only for a confirmed supplier's edit;
//   3. a held profile asks what the company does (and the free-text box, which is always shown, is where he answers);
//   4. the services read off his documents start unticked; the one button that ticks them ticks only those, each shown with his sentence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const TAB = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/ServicesTab.tsx'), 'utf8');
const COPY = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/servicesCopy.ts'), 'utf8');
const { profileStateOf, VERIFY_COPY, PROPOSED_COPY } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
// The checklist block: from its comment to the free-text box that follows it.
const CHECKLIST = TAB.slice(TAB.indexOf("THE SALES ENGINEER'S PREPARED CHECKLIST"), TAB.indexOf('ADDING: ONE TEXT BOX AND THE MIC'));

test('1. no trade can be ticked whole in one tap: no "Select all" on a trade, in English or Arabic', () => {
  assert.ok(CHECKLIST.length > 500, 'the checklist block was found');
  assert.doesNotMatch(TAB, /select_all|clear_all|setAll\(/);
  assert.doesNotMatch(COPY, /select_all|clear_all|'Select all'|تحديد الكل/);
  // the only multi-tick in the checklist would be a loop over a trade's keys; each box toggles one key
  assert.match(CHECKLIST, /onChange=\{\(\) => toggleKey\(s\.key\)\}/);
  assert.doesNotMatch(CHECKLIST, /for \(const k of/);
});

test('2. the trades\' services are browsed under "Browse all services of my trades", closed unless he is editing a confirmed list', () => {
  assert.equal(VERIFY_COPY.browse_trades, 'Browse all services of my trades');
  assert.match(CHECKLIST, /<details[^>]*open=\{browseOpen \?\? !!d\.confirmed\}/);
  assert.match(CHECKLIST, /<summary[^>]*>\{VERIFY_COPY\.browse_trades\}<\/summary>/);
  assert.ok(CHECKLIST.indexOf('<details') < CHECKLIST.indexOf('trades.map('), 'every trade fieldset is inside the details');
  assert.ok(CHECKLIST.indexOf('</details>') > CHECKLIST.lastIndexOf('</fieldset>'));
});

test('3. known-bad: a profile whose readings agreed on nothing is asked what the company does, never "still reading" for ever', () => {
  const held = { status: 'read', source: 'document_text', choice: 'held', trades: [], held_readings: [[], [], []] };
  assert.equal(profileStateOf([held]), 'unclear');
  assert.match(VERIFY_COPY.profile_unclear, /^Your profile does not say what your company does\. Tell us in a line or two/);
  assert.doesNotMatch(VERIFY_COPY.profile_unclear, /still reading/i);
  // the tab prints the state's sentence, and the free-text box is not conditional on any profile state
  assert.match(TAB, /VERIFY_COPY\[\('profile_' \+ profileState\) as 'profile_none'\]/);
  const box = TAB.slice(TAB.indexOf('ADDING: ONE TEXT BOX AND THE MIC') - 200, TAB.indexOf('ADDING: ONE TEXT BOX AND THE MIC'));
  assert.doesNotMatch(box, /profileState\s*[!=]==?\s*'[a-z]+'\s*&&\s*\(\s*$/);
  // control: an outage is still "still reading" (the sweep asks the model again), and trades from another document win
  assert.equal(profileStateOf([{ status: 'read', choice: 'unavailable', trades: [] }]), 'pending');
  assert.equal(profileStateOf([held, { status: 'read', choice: 'on', trades: [{ code: 'labour_supply' }] }]), 'hits');
});

test('4. the services read off his documents start unticked, and the one tick-all ticks only them, each beside his own sentence', () => {
  assert.match(TAB, /setPropTicked\(allProp \? new Set\(\) : new Set\(proposedSvcs\.map\(\(p\) => p\.key\)\)\)/);
  assert.match(TAB, /PROPOSED_COPY\.from_line\} <q dir="auto">\{p\.snippet\}<\/q>/);
  assert.equal(PROPOSED_COPY.tick_all, 'Tick all proposed services');
});
