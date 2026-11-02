// THE JUDGE OF THE PROFILE-READ WALK FAILS ON EVERY KNOWN-BAD SCREEN. Seat: sales_engineer. 2 Nov 2026, ledger 1469.
// scripts/e2e/profile_read_judge.mjs decides whether the Services tab told the supplier the truth about its company
// profile. A judge that never fails proves nothing, so each check is shown a screen that is wrong in exactly one way
// and must flag exactly that check, and one true screen that must pass. The live walk runs the same controls on its own data.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { judgeView, stateOfNotice, norm } from '../e2e/profile_read_judge.mjs';

const LABELS = { aluminium: 'Aluminium Works', glazing: 'Glazing Works', electrical: 'Electrical', hvac: 'HVAC' };
const labelOf = (c) => LABELS[c] || c;
const FILE = ['ZZ DEMO Al Reem Facades LLC is a UAE contractor.', 'Our services', '- Aluminium windows and doors', '- Glazing works'];
const truth = (read, stated = ['aluminium', 'glazing']) => ({ read, stated, fileText: FILE });
const view = (o = {}) => ({ state: 'hits', keywords: ['Aluminium Works', 'Glazing Works'], lines: ['Aluminium windows and doors', 'Glazing works'], arabicOutside: '', arabicQuotes: [], ...o });
const failed = (r) => r.filter((x) => !x.ok).map((x) => x.name);
const judge = (t, v) => judgeView({ truth: t, view: v, labelOf });

test('control: a true screen passes every check', () => assert.deepEqual(failed(judge(truth('text'), view())), []));
test('known-bad: an invented keyword is flagged', () => assert.match(failed(judge(truth('text'), view({ keywords: ['Aluminium Works', 'Glazing Works', 'Electrical'] }))).join('|'), /no keyword is invented/));
test('known-bad: a nearest trade instead of the stated one is flagged twice (invented and missing)', () => {
  const f = failed(judge(truth('text'), view({ keywords: ['Aluminium Works', 'HVAC'] })));
  assert.ok(f.some((n) => /invented/.test(n)) && f.some((n) => /every trade the file states/.test(n)), f.join('|'));
});
test('known-bad: a stated trade left out is flagged', () => assert.match(failed(judge(truth('text'), view({ keywords: ['Aluminium Works'] }))).join('|'), /every trade the file states/));
test('known-bad: a summary line the file does not print is flagged', () => assert.match(failed(judge(truth('text'), view({ lines: ['We install lifts and escalators'] }))).join('|'), /every summary line/));
test('known-bad: a truncated copy of a real line is still a line of the file', () => assert.deepEqual(failed(judge(truth('text'), view({ lines: ['Aluminium windows and…'] }))), []));
test('known-bad: keywords with no summary line are flagged', () => assert.match(failed(judge(truth('text'), view({ lines: [] }))).join('|'), /a summary line is shown/));
test('known-bad: "found no service" for a profile that states services is flagged', () => assert.match(failed(judge(truth('text'), view({ state: 'none', keywords: [], lines: [] }))).join('|'), /true of this file/));
test('known-bad: keywords for a profile that states no service are flagged', () => {
  const f = failed(judge(truth('none', []), view()));
  assert.ok(f.some((n) => /true of this file/.test(n)) && f.some((n) => /no keyword is invented/.test(n)) && f.some((n) => /no keyword and no summary/.test(n)), f.join('|'));
});
test('control: a profile that states no service passes when the tab says so and shows nothing', () => assert.deepEqual(failed(judge(truth('none', []), view({ state: 'none', keywords: [], lines: [] }))), []));
test('known-bad: "found no service" for a blank or corrupt file is flagged (it was never read)', () => assert.match(failed(judge(truth('unreadable', []), view({ state: 'none', keywords: [], lines: [] }))).join('|'), /true of this file/));
test('control: a blank file passes when the tab says it could not be read', () => {
  for (const state of ['scan', 'failed']) assert.deepEqual(failed(judge(truth('unreadable', []), view({ state, keywords: [], lines: [] }))), [], state);
});
// Ledger 1442: a scan or photo that states services is READ (the licence's model), so "could not read" is no longer an acceptable answer for it.
test('known-bad: a picture shown as "found no service" or "could not read" is flagged', () => {
  for (const state of ['none', 'scan']) assert.match(failed(judge(truth('picture'), view({ state, keywords: [], lines: [] }))).join('|'), /true of this file/, state);
});
test('known-bad: a picture that shows only one of its two trades is flagged', () => assert.match(failed(judge(truth('picture'), view({ keywords: ['Glazing Works'], lines: ['Glazing works'] }))).join('|'), /every trade the file states/));
test('control: a picture shows its trades; a line the reading wobbled on (1 word in 6) is still the file\'s line, 1 in 4 is not', () => {
  assert.deepEqual(failed(judge(truth('picture'), view())), []);
  assert.deepEqual(failed(judge(truth('picture'), view({ lines: ['Aluminium windows and doors glazing xyzzy'] }))), []);
  assert.match(failed(judge(truth('picture'), view({ lines: ['Aluminium windows and doers'] }))).join('|'), /every summary line/);
});
test('known-bad: the same wobble in a TEXT file is flagged (a text layer is exact)', () => assert.match(failed(judge(truth('text'), view({ lines: ['Aluminium windows and doors glazing xyzzy'] }))).join('|'), /every summary line/));
test('known-bad: a picture line that is mostly not in the file is flagged', () => assert.match(failed(judge(truth('picture'), view({ lines: ['Lift installation and maintenance services'] }))).join('|'), /every summary line/));
test('control: an Arabic-only profile may show its keywords with no line', () => assert.deepEqual(failed(judge({ ...truth('picture'), arabic: true }, view({ lines: [] }))), []));
test('control: a corrupt file must say it is damaged', () => {
  assert.deepEqual(failed(judge({ ...truth('unreadable', []), mustBe: ['damaged'] }, view({ state: 'damaged', keywords: [], lines: [] }))), []);
  assert.match(failed(judge({ ...truth('unreadable', []), mustBe: ['damaged'] }, view({ state: 'scan', keywords: [], lines: [] }))).join('|'), /true of this file/);
});
test('known-bad: a file still "being read" is flagged (a hang)', () => assert.match(failed(judge(truth('text'), view({ state: 'reading', keywords: [], lines: [] }))).join('|'), /true of this file/));
test('known-bad: Arabic outside a quoted line is flagged', () => assert.match(failed(judge(truth('text'), view({ arabicOutside: 'خدمات' }))).join('|'), /no Arabic outside/));
test('known-bad: an Arabic summary line is flagged', () => assert.match(failed(judge(truth('text'), view({ arabicQuotes: ['أعمال الألمنيوم'] }))).join('|'), /no Arabic in the summary/));
test('the notice the tab prints decides the state', () => {
  assert.equal(stateOfNotice('We read your company profile and found no service we could match. Tick what you do below'), 'none');
  assert.equal(stateOfNotice('We are still reading your company profile. This page updates by itself'), 'reading');
  assert.equal(stateOfNotice('Your company profile is a scan or photo that we could not read as text yet.'), 'scan');
  assert.equal(stateOfNotice('No company profile has been read yet. Upload it in Documents'), 'missing');
  assert.equal(stateOfNotice('We could not read your company profile. Upload a clear PDF or Word file in Documents'), 'failed');
  assert.equal(stateOfNotice('Summary of your company profile Keywords of your services Aluminium Works'), 'hits');
});
test('norm ignores case, punctuation and a trailing ellipsis', () => assert.equal(norm('  - Aluminium Works…'), 'aluminium works'));
