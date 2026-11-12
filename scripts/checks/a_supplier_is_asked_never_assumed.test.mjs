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
const { profileStateOf, servicesSentences, VERIFY_COPY, PROPOSED_COPY } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
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

// Review of 12 Nov 2026 (rendered at 390 px): closed by default, the block hid the only boxes of every supplier whose documents proposed
// nothing (no documents, reading, reader down, "found no service", held), under a title with no arrow. It opens by itself for them.
test('2. the trades\' services are browsed under "Browse all services of my trades": open for a confirmed edit or when nothing was proposed, with a chevron and a 48 px title', () => {
  assert.equal(VERIFY_COPY.browse_trades, 'Browse all services of my trades');
  assert.match(CHECKLIST, /<details[^>]*open=\{browseOpen \?\? \(!!d\.confirmed \|\| proposedSvcs\.length === 0\)\}/);
  const summary = CHECKLIST.slice(CHECKLIST.indexOf('<summary'), CHECKLIST.indexOf('</summary>'));
  assert.match(summary, /\{VERIFY_COPY\.browse_trades\}/);
  assert.match(summary, /<ChevronDown aria-hidden="true"[^>]*group-open:rotate-180/, 'a visible arrow that turns when open');
  assert.match(summary, /min-h-12/, 'a tap target of at least 44 px (48)');
  assert.match(summary, /list-none/, 'the native marker is replaced, not doubled');
  assert.ok(CHECKLIST.indexOf('<details') < CHECKLIST.indexOf('trades.map('), 'every trade fieldset is inside the details');
  assert.ok(CHECKLIST.indexOf('</details>') > CHECKLIST.lastIndexOf('</fieldset>'));
});

test('3. known-bad: a profile whose readings agreed on nothing is asked what the company does, never "still reading" for ever', () => {
  const held = { status: 'read', source: 'document_text', choice: 'held', trades: [], held_readings: [[], [], []] };
  assert.equal(profileStateOf([held]), 'unclear');
  // review of 12 Nov 2026: "does not say what your company does" was untrue of most held profiles (the readings disagreed)
  assert.match(VERIFY_COPY.profile_unclear, /^We read your company profile but could not be sure which services you offer\. Please tell us in a line or two/);
  assert.doesNotMatch(VERIFY_COPY.profile_unclear, /still reading|does not say/i);
  assert.match(VERIFY_COPY.profile_unclear, /add the matching services for you to check/, 'the box below adds what it recognises, included with Remove');
  // the tab prints the state's sentence, and the free-text box is not conditional on any profile state
  assert.match(TAB, /servicesSentences\(profileState, \{ list: /);
  assert.match(TAB, /\{said\.profile\}/); assert.match(TAB, /\{said\.verify\}/);
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

test('6. every sentence above the services is true in every state: a list "below" is named only when one is on screen', () => {
  const LIST = /\btick\b|listed below|list below|keywords/i;
  for (const state of ['hits', 'reading', 'pending', 'unclear', 'scan', 'damaged', 'failed', 'none', 'missing']) {
    const without = servicesSentences(state, { list: false, signup: false });
    if (state !== 'hits') {
      assert.doesNotMatch(without.verify, LIST, `${state}, no list: ${without.verify}`);
      assert.doesNotMatch(without.profile ?? '', LIST, `${state}, no list: ${without.profile}`);
      assert.match(without.profile ?? '', /below|Documents|updates by itself/, `${state}: it says where to act`);
    }
    const withList = servicesSentences(state, { list: true, signup: false });
    assert.doesNotMatch(withList.profile ?? '', /chose at sign-up/, `${state}: the sign-up trade is named only when it is on the list`);
  }
  assert.match(servicesSentences('pending', { list: true, signup: true }).profile, /chose at sign-up is listed below/);
  assert.match(servicesSentences('none', { list: true, signup: false }).profile, /Tick what you do below/);
  assert.match(servicesSentences('none', { list: true, signup: false }).verify, /tick the services you do in the list below/);
  assert.equal(servicesSentences('hits', { list: true, signup: false }).verify, VERIFY_COPY.verify_needed, 'with what was read, the summary and keywords are below');
  // the first-visit sentence ("our sales engineer has listed the trades ...") only with a list; without one, its own sentence
  assert.equal(servicesSentences('missing', { list: true, signup: false }).intro, null);
  assert.doesNotMatch(servicesSentences('missing', { list: false, signup: false }).intro, /listed the trades|\btick each\b/i);
  assert.match(TAB, /said\.intro \?\? sc\(lang, 'first_run'\)/);
});

// Review round 2 (12 Nov 2026): a profile already on file was told to upload one (B), and a document still being read on OUR side was told
// to "upload it again later" (C). Each sentence is true for its state.
test('7. a profile on file is never asked for again, and a hold on our side is said to be ours', async () => {
  const { docStateLine } = await import(new URL('../../src/components/portal/supplier/servicesRead.ts', import.meta.url).href);
  const { VERIFY_COPY_NO_LIST } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
  assert.match(TAB, /profileDocs\.length \? VERIFY_COPY_NO_LIST\.no_prep_profile_on_file : sc\(lang, 'no_prep'\)/);
  assert.match(TAB, /goTo && !profileDocs\.length \?/);
  assert.doesNotMatch(VERIFY_COPY_NO_LIST.no_prep_profile_on_file, /upload/i);
  const line = docStateLine({ status: 'read', choice: 'unavailable' });
  assert.doesNotMatch(line, /upload/i);
  assert.match(line, /on our side, not yours: we read it again automatically, and you can carry on/);
});
