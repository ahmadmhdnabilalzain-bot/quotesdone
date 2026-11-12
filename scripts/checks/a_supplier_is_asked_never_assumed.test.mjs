// A SUPPLIER IS ASKED, NEVER ASSUMED (12 Nov 2026, sales_engineer; founder rulings 1647, 1628, 862 and 1645; report
// docs/reports/2026-11-12-supplier-service-profiling.md, slices 1 and 4). Offline: reads the Services tab's source, its copy and the
// server's writers.
//
// Measured that day: the one real supplier through this step confirmed 33 service keys, whole trades ticked, from a 22-word
// description, and is matched for dosing pumps and heat treatment his words never name. On the hard-profile set 4 of 12 companies
// whose readings agreed on nothing ('held') were told "We are still reading your documents" for ever, and nothing ever asked them.
// Slice 4 (the three screens and the question cards) keeps every rule below and adds 8-10:
//   1. no trade's checklist can be ticked in one tap: no "Select all" per trade, in either language;
//   2. the checklist is browsed under "Browse all services of my trades", open by itself only when nothing of his is listed;
//   3. a held profile asks what the company does, and the "Add a service we missed" box is where he answers (open when nothing is listed);
//   4. the services read off his documents start unticked; the one button ticks only his own statements, each beside his own sentence;
//   5. a vague or empty profile with nothing of his own gets the request, never "still reading";
//   6. every sentence the check screen opens with is true for its state, one sentence, plain words;
//   7. a profile on file is never asked for again, and a hold on our side is said to be ours;
//   8. NO PATH WRITES A KEY INTO `services` WITHOUT A TICK OR AN ANSWER: the confirm's services are only what he ticked or answered;
//      an answer, a stored question and a reading write nothing into supplier_capabilities.services; un-ticked implications are removed;
//   9. nothing unfinished-looking: the microphone is drawn only when it works;
//  10. every submit shows its loading state and cannot be sent twice.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const TAB = R('src/components/portal/supplier/ServicesTab.tsx');
const CARDS = R('src/components/portal/supplier/ServiceQuestions.tsx');
const COPY = R('src/components/portal/supplier/servicesCopy.ts');
const { profileStateOf, stateLine, FLOW_COPY, VERIFY_COPY, PROPOSED_COPY, asksWhatHeDoes } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
const { outcome } = await import(new URL('../../src/components/portal/supplier/serviceQuestions.ts', import.meta.url).href);
// The checklist block: from its comment to the trade proposals that follow it (since slice 4 it comes after the add box).
const CHECKLIST = TAB.slice(TAB.indexOf("THE SALES ENGINEER'S PREPARED CHECKLIST"), TAB.indexOf('d.trade_proposals.length > 0'));
const STATES = ['hits', 'reading', 'pending', 'unclear', 'scan', 'damaged', 'failed', 'none', 'missing'];

test('1. no trade can be ticked whole in one tap: no "Select all" on a trade, in English or Arabic', () => {
  assert.ok(CHECKLIST.length > 500, 'the checklist block was found');
  assert.doesNotMatch(TAB, /select_all|clear_all|setAll\(/);
  assert.doesNotMatch(COPY, /select_all|clear_all|'Select all'|تحديد الكل/);
  // the only multi-tick in the checklist would be a loop over a trade's keys; each box toggles one key
  assert.match(CHECKLIST, /onChange=\{\(\) => toggleKey\(s\.key\)\}/);
  assert.doesNotMatch(CHECKLIST, /for \(const k of/);
});

// Review of 12 Nov 2026 (rendered at 390 px): closed by default, the block hid the only boxes of every supplier whose documents proposed
// nothing. CORRECTED 12 Nov 2026 (slice 4): it opens by itself whenever nothing of his is listed (that is when it holds his only boxes);
// a confirmed supplier's edit starts from the check screen's lists and their Edit, not from every service of every trade (walk: 470 words).
test('2. the trades\' services are browsed under "Browse all services of my trades": open when nothing is listed, with a chevron and a 48 px title', () => {
  assert.equal(VERIFY_COPY.browse_trades, 'Browse all services of my trades');
  assert.match(CHECKLIST, /<details[^>]*open=\{browseOpen \?\? nothingListed\}/);
  assert.match(TAB, /const nothingListed = statedKeys\.length === 0 && rwOwnWords\.length === 0;/);
  assert.match(TAB, /const editOwn = s1Count > 0 \? \(\) => setStep\('understood'\) : \(\) => setBrowseOpen\(true\);/, 'Edit opens it');
  assert.match(TAB, /const summaryCls = [^\n]*min-h-12[^\n]*list-none/, 'a tap target of at least 44 px (48), the native marker replaced');
  const summary = CHECKLIST.slice(CHECKLIST.indexOf('<summary'), CHECKLIST.indexOf('</summary>'));
  assert.match(summary, /\{VERIFY_COPY\.browse_trades\}/);
  assert.match(summary, /<ChevronDown aria-hidden="true"[^>]*group-open:rotate-180/, 'a visible arrow that turns when open');
  assert.ok(CHECKLIST.indexOf('<details') < CHECKLIST.indexOf('trades.map('), 'every trade fieldset is inside the details');
  assert.ok(CHECKLIST.indexOf('</details>') > CHECKLIST.lastIndexOf('</fieldset>'));
});

test('3. known-bad: a profile whose readings agreed on nothing is asked what the company does, never "still reading" for ever', () => {
  const held = { status: 'read', source: 'document_text', choice: 'held', trades: [], held_readings: [[], [], []] };
  assert.equal(profileStateOf([held]), 'unclear');
  assert.match(stateLine('unclear'), /Tell us below in a line or two/);
  assert.doesNotMatch(stateLine('unclear'), /still reading|does not say/i);
  // the check screen prints the state's one sentence, and the add box is open by itself while nothing of his is listed
  assert.match(TAB, /stateLine\(profileState\)/);
  assert.match(TAB, /open=\{addOpen \?\? nothingListed\}/);
  // control: an outage is still "pending" (the sweep asks the model again), and trades from another document win
  assert.equal(profileStateOf([{ status: 'read', choice: 'unavailable', trades: [] }]), 'pending');
  assert.equal(profileStateOf([held, { status: 'read', choice: 'on', trades: [{ code: 'labour_supply' }] }]), 'hits');
});

// Slice 4: "Yes, we do all of these" (report 3.9 Screen 1) replaces "Tick all proposed services"; it ticks his own statements (the keys and
// his words with no key), never a partner service, and every row stands under the sentence of his it was read from, in his language.
test('4. the services read off his documents start unticked; the one tap ticks only his own, each under his own sentence', () => {
  assert.match(TAB, /const proposedOwn = \(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => p\.delivery !== 'partner'\)/);
  assert.match(TAB, /setPropTicked\(\(cur\) => reloadSet\(cur, \(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => p\.stated\)/, 'on load only what he confirmed before');
  assert.match(TAB, /if \(!allProp\) for \(const p of proposedOwn\) n\.add\(p\.key\)/);
  assert.match(TAB, /const ownStated = readOwnWords\.filter\(\(w\) => w\.basis === 'stated'\)/);
  assert.doesNotMatch(TAB, /new Set\(proposedSvcs\.map\(\(p\) => p\.key\)\)/);
  assert.match(TAB, /<q dir="auto">\{g\.quote\}<\/q>/, 'his sentence, shown as his words');
  assert.match(TAB, /badge: p\.delivery === 'partner' \? PROPOSED_COPY\.through_partner : null/);
  assert.equal(FLOW_COPY.all_of_these, 'Yes, we do all of these');
  assert.equal(PROPOSED_COPY.through_partner, 'Through a partner');
});

test('5. reader @5: a vague or empty profile with nothing of his own to tick gets the request, never "still reading"', () => {
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'nothing', status: 'open' }] }, 0), true);
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'vague', status: 'open' }] }, 0), true);
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'vague', status: 'open' }] }, 3), false, 'his own services listed: he ticks them');
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'umbrella', status: 'open' }] }, 0), false);
  assert.equal(asksWhatHeDoes(null, 0), false);
  assert.match(TAB, /asksWhatHeDoes\(d\.reading, proposedOwn\.length\) \? 'unclear' : profileStateOf\(profileDocs\)/);
});

// Slice 4 (founder 1645, "far less text"): one sentence per state, replacing servicesSentences' two or three. Every sentence names a place
// to act that is on screen: "below" is the add box the check screen always shows; a list to tick only in the state that has one.
test('6. every sentence the check screen opens with is true for its state: one sentence, a place to act, no jargon', () => {
  for (const s of STATES) {
    const line = stateLine(s);
    assert.ok(line && line.split(/(?<=\.)\s+(?=[A-Z])/).length <= 2, `${s}: ${line}`);
    assert.match(line, /below|Documents|minute/, `${s}: it says where to act`);
    if (s !== 'hits') assert.doesNotMatch(line, /\btick\b|list below|keywords/i, `${s}: no list is named where none is shown`);
  }
  const all = JSON.stringify(Object.values(FLOW_COPY).filter((v) => typeof v === 'string'));
  assert.doesNotMatch(all, /cross-?match|keyword|rewrites? it into|standard service names/i, 'plain words');
  for (const k of ['understood_lead', 'check_lead', 'confirmed_lead']) assert.ok(FLOW_COPY[k].split('. ').length <= 2, `${k} is short`);
});

test('7. a profile on file is never asked for again, and a hold on our side is said to be ours', async () => {
  const { docStateLine } = await import(new URL('../../src/components/portal/supplier/servicesRead.ts', import.meta.url).href);
  assert.match(TAB, /goTo && !profileDocs\.length && !d\.confirmed \?/, 'the Documents button only when no profile is on file');
  assert.match(stateLine('missing'), /Upload your company profile/);
  for (const s of STATES.filter((x) => x !== 'missing' && x !== 'scan' && x !== 'damaged' && x !== 'failed')) assert.doesNotMatch(stateLine(s), /upload/i, s);
  assert.match(stateLine('pending'), /try again by ourselves/);
  const line = docStateLine({ status: 'read', choice: 'unavailable' });
  assert.doesNotMatch(line, /upload/i);
  assert.match(line, /on our side, not yours: we read it again automatically, and you can carry on/);
});

test('8. no path writes a key into services without a tick or an answer', () => {
  // the confirm's services: browse ticks, the rewrite he kept, meaning proposals he added, screen-1 ticks, and his answers; nothing else
  assert.match(TAB, /const statedKeys = \[\.\.\.new Set\(\[\.\.\.liveTicks, \.\.\.rwStated, \.\.\.rwMeaning, \.\.\.propKeys, \.\.\.ans\.own, \.\.\.ans\.partner\]\)\]/);
  assert.match(TAB, /const rwMeaning = \(rw\?\.meaning\?\.proposals \|\| \[\]\)\.map\(\(p\) => p\.key\)\.filter\(\(k\) => kept\.has\(k\)/);
  assert.match(TAB, /services: statedKeys, partner: partnerKeys/);
  // an answer is his only for what he tapped: an unanswered card, an untapped chip and "None of these" add nothing
  const q = [{ id: 1, kind: 'umbrella', options: [{ key: 'a.b', label_en: 'B', own_words: false }], multi: true, status: 'open', answer: null }];
  assert.deepEqual(outcome(q, {}).own, []);
  assert.deepEqual(outcome(q, { 1: { none: true } }).own, []);
  assert.deepEqual(outcome(q, { 1: { picked: [0] } }).own, ['a.b']);
  // for a profiled supplier, the rewrite's "also covers" starts off, and the server removes every implication he did not tick
  assert.match(TAB, /next\.implied\.filter\(\(i\) => i\.removed \|\| !!d\.reading\)/);
  assert.match(TAB, /asked: !!d\.reading/);
  const svc = R('supabase/functions/_shared/supplier_services.ts');
  assert.match(svc, /if \(body\.asked === true\) \{[\s\S]{0,400}removed\.push\(i\.to\)/);
  // the question store, the answer and the reading never write supplier_capabilities.services
  const qs = R('supabase/functions/_shared/supplier_service_questions.ts');
  assert.doesNotMatch(qs, /from\('supplier_capabilities'\)\.(update|upsert|insert)/);
  assert.match(qs, /from\('supplier_capabilities'\)\.select\('services'\)/);
  const docs = R('supabase/functions/_shared/supplier_doc_trades.ts');
  assert.doesNotMatch(docs, /services:\s*\[/);
  // services_partner is a subset of services, enforced in the one writer
  assert.match(R('supabase/functions/_shared/supplier_capability.ts'), /const servicesPartner = \[\.\.\.new Set\(sentPartner\)\]\.filter\(\(k\) => services\.includes\(k\)\)/);
});

test('9. nothing unfinished-looking: the microphone is drawn only when it works, never a disabled button with "coming soon"', () => {
  assert.match(TAB, /const micOn = voice\.enabled && canRecord;/);
  assert.match(TAB, /\{micOn && \(\s*<Button/);
  assert.doesNotMatch(TAB, /disabled=\{!voice\.enabled/);
});

test('10. every submit shows its loading state for its whole duration and cannot be sent twice; every tap target is 44 px', () => {
  assert.match(TAB, /const save = async \(\) => \{\s*if \(busy\) return;/);
  assert.match(TAB, /disabled=\{busy \|\| !canSave\} aria-busy=\{busy\}/);
  assert.match(TAB, /\{busy \? <><Spinner \/>\{F\.confirming\}<\/> :/);
  assert.match(TAB, /\{rwBusy \? <><Spinner \/>\{sc\(lang, 'rewriting'\)\}<\/> :/);
  assert.match(CARDS, /export const chipCls = [\s\S]{0,120}min-h-11[\s\S]{0,300}active:scale/, 'chips: 44 px with a pressed state');
  assert.match(CARDS, /min-h-11 min-w-0 flex-1/, 'the partner choices: 44 px');
  for (const f of [TAB, CARDS]) assert.doesNotMatch(f.slice(f.indexOf('return (')), /<(input|textarea)[^>]*text-(sm|xs|\[1[0-5](\.\d)?px\])/, 'a text field under 16 px makes iOS zoom');
});
