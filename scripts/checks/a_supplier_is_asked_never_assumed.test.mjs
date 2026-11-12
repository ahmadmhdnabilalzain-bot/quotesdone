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
//  10. every submit shows its loading state and cannot be sent twice;
//  11. (slice 3's review) no trade is confirmed without a tick, and the one tap ticks only his own certain statements;
//  12-13. (slice 3's review round 2) "found no service" only when nothing is listed; the wait is said, with a moving mark.
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
const STATES = ['hits', 'listed', 'reading', 'pending', 'unclear', 'scan', 'damaged', 'failed', 'none', 'missing'];

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
  // (round-2 review of slice 4: Edit reopens his cards first, then screen 1, then this list)
  // (round-3 review: once he has confirmed, his cards are answered, so Edit opens this list, scrolled to where he can see it)
  assert.match(TAB, /const openBrowse = \(\) => \{ setBrowseOpen\(true\); requestAnimationFrame\(\(\) => browseRef\.current\?\.scrollIntoView/);
  assert.match(TAB, /const editOwn = !d\.confirmed && cardList\.length \? \(\) => setStep\('questions'\) : !d\.confirmed && s1Count > 0 \? \(\) => setStep\('understood'\) : openBrowse;/, 'Edit opens it');
  // Browse and the list agree: a box shows whether the key is on his list, and unticking takes it out (round-2 review, finding A)
  assert.match(TAB, /checked=\{statedSet\.has\(s\.key\)\} onChange=\{\(\) => toggleKey\(s\.key\)\}/);
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
  // (since the review of branch 2 "his own" also leaves out projects, brands and "please check": test 11)
  assert.match(TAB, /const proposedOwn = \(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => !otherRow\(p\)\)/);
  // on load only what he confirmed before, and what HE ticked before a reload of the same reading (review of slice 4, finding 2)
  assert.match(TAB, /setPropTicked\(\(cur\) => reloadSet\(cur, \[\.\.\.\(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => p\.stated\)\.map\(\(p\) => p\.key\), \.\.\.\(flow\?\.ticked \?\? \[\]\)\], keep\)\)/, 'on load only what he confirmed or ticked');
  assert.match(TAB, /if \(!allProp\) for \(const p of proposedOwn\) n\.add\(p\.key\)/);
  assert.match(TAB, /const ownStated = readOwnWords\.filter\(\(w\) => w\.basis === 'stated'\)/);
  // shown ONCE (slice 3 review round 2 warning: project, partner and "please check" keys are now both listed rows and card options): a row
  // a card asks about is not listed on screen 1; the cards never ask a key of his tick list (toStore: `has`, supplier_service_questions.test.ts)
  assert.match(TAB, /const s1Partner = fresh \? proposedSvcs\.filter\(\(p\) => otherRow\(p\) && !askedKeys\.has\(p\.key\) && !held\.has\(p\.key\)\) : \[\];/);
  assert.doesNotMatch(TAB, /new Set\(proposedSvcs\.map\(\(p\) => p\.key\)\)/);
  assert.match(TAB, /<q dir="auto">\{g\.quote\}<\/q>/, 'his sentence, shown as his words');
  assert.match(TAB, /const badgeOf = \(p: ProposedSvc\) => p\.delivery === 'partner' \? PROPOSED_COPY\.through_partner/);
  assert.equal(FLOW_COPY.all_of_these, 'Yes, we do all of these');
  assert.equal(PROPOSED_COPY.through_partner, 'Through a partner');
});

test('5. reader @5: a vague or empty profile with nothing of his own to tick gets the request, never "still reading"', () => {
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'nothing', status: 'open' }] }, 0), true);
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'vague', status: 'open' }] }, 0), true);
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'vague', status: 'open' }] }, 3), false, 'his own services listed: he ticks them');
  assert.equal(asksWhatHeDoes({ questions: [{ kind: 'umbrella', status: 'open' }] }, 0), false);
  assert.equal(asksWhatHeDoes(null, 0), false);
  assert.match(TAB, /asksWhatHeDoes\(d\.reading, proposedOwn\.length\) \? 'unclear' : listedProfileState\(profileStateOf\(profileDocs\)/);
});

// Slice 4 (founder 1645, "far less text"): one sentence per state, replacing servicesSentences' two or three. Every sentence names a place
// to act that is on screen: "below" is the add box the check screen always shows; a list to tick only in the state that has one.
test('6. every sentence the check screen opens with is true for its state: one sentence, a place to act, no jargon', () => {
  for (const s of STATES) {
    const line = stateLine(s);
    assert.ok(line && line.split(/(?<=\.)\s+(?=[A-Z])/).length <= 2, `${s}: ${line}`);
    assert.match(line, /below|Documents|minute/, `${s}: it says where to act`);
    if (s !== 'hits' && s !== 'listed') assert.doesNotMatch(line, /\btick\b|list below|keywords/i, `${s}: no list is named where none is shown`);
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

test('8. no path writes a key into services without a tick or an answer', async () => {
  // the confirm's services: browse ticks, the rewrite he kept, meaning proposals he added, screen-1 ticks, and his answers; nothing else
  // since the review of slice 4 (finding 13) the derivation is serviceQuestions.selection, unit-tested in serviceQuestions.test.mjs
  // (a "Please check" row he ticks is his own, finding 1); the tab feeds it exactly these sources and sends what it returns
  // (round-2 review: after a confirm only cards answered since count, serviceQuestions.liveQuestions, unit-tested)
  assert.match(TAB, /const sel = selection\(\{ rows: proposedSvcs, ticked: propTicked, readWords: readOwnWords, wordsTicked: readWordsTicked, questions: liveQuestions\(questions, cards\.answers, d\.capability\?\.confirmed_at\), answers: cards\.answers,\s*more: \[\.\.\.liveTicks, \.\.\.rwStated, \.\.\.rwMeaning\]/);
  // and every listed service can be taken out on the check screen, then is sent as removed
  assert.match(TAB, /onClick=\{\(\) => toggleDrop\(isKey\(k\) \? k : wordKey\(k\)\)\}>\s*<X aria-hidden/);
  assert.match(TAB, /\.\.\.ans\.declined, \.\.\.sel\.removed\]/);
  assert.match(TAB, /const statedKeys = sel\.stated, partnerKeys = sel\.partner, ownKeys = sel\.own;/);
  const { selection } = await import(new URL('../../src/components/portal/supplier/serviceQuestions.ts', import.meta.url).href);
  const s0 = selection({ rows: [{ key: 'a.b', delivery: 'own', check: true }], ticked: new Set(), readWords: [], wordsTicked: new Set(), questions: [], answers: {} });
  assert.deepEqual(s0.stated, [], 'a listed row nobody ticked is not his');
  assert.match(TAB, /const rwMeaning = \(rw\?\.meaning\?\.proposals \|\| \[\]\)\.map\(\(p\) => p\.key\)\.filter\(\(k\) => kept\.has\(k\)/);
  assert.match(TAB, /services: statedKeys, partner: \[\.\.\.partnerKeys, \.\.\.sel\.partnerWords\]/);
  // an answer is his only for what he tapped: an unanswered card, an untapped chip and "None of these" add nothing
  const q = [{ id: 1, kind: 'umbrella', options: [{ key: 'a.b', label_en: 'B', own_words: false }], multi: true, status: 'open', answer: null }];
  assert.deepEqual(outcome(q, {}).own, []);
  assert.deepEqual(outcome(q, { 1: { none: true } }).own, []);
  assert.deepEqual(outcome(q, { 1: { picked: [0] } }).own, ['a.b']);
  // for a profiled supplier, the rewrite's "also covers" starts off, and the server removes every implication he did not tick
  assert.match(TAB, /next\.implied\.filter\(\(i\) => i\.removed \|\| !!d\.reading\)/);
  assert.match(TAB, /asked: !!d\.reading && !d\.confirmed/, 'never for a supplier confirmed before (review of slice 4, finding 10)');
  const svc = R('supabase/functions/_shared/supplier_services.ts');
  assert.match(svc, /if \(body\.asked === true && !prevCap\?\.confirmed_at\) \{[\s\S]{0,400}removed\.push\(i\.to\)/);
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

// Review of branch 2 (12 Nov 2026): wrong trades became his at Confirm without a tick (115 trades on 16 suppliers, 12 wrong), and every
// row "Tick all" ticked counted as his own. A trade is never confirmed for him unless he ticked or answered for it; only his own certain
// statements are ticked by "Yes, we do all of these"; projects, brands, partner and "please check" rows are his to tick one by one.
test('11. no trade is confirmed for him without a tick or an answer, and the one tap ticks only his own certain statements', () => {
  const SAVE = R('supabase/functions/_shared/supplier_services.ts');
  const READER = R('supabase/functions/_shared/supplier_profile_reading.ts');
  // the tab sends a trade only when he ticked in it, confirmed it before, or chose it at sign-up
  // (review round 2: a trade ON FILE is already his and is sent too, so a listed supplier can confirm what we hold)
  assert.match(TAB, /trades: activeTrades\.filter\(\(c\) => \['confirmed', 'on_file', 'signup'\]\.includes\(sourceOf\(c\) \?\? ''\) \|\| statedKeys\.some\(\(k\) => k\.startsWith\(c \+ '\.'\)\)\)/);
  // the server holds it whatever a client sends
  assert.match(SAVE, /const keep = new Set\(keepTickedProposed\(\[\.\.\.trades\], proposedByDocs, held, signupTradeOf\(lead\?\.sector, vocabTrades\), stated\)\);/);
  assert.match(SAVE, /for \(const t of \[\.\.\.trades\]\) if \(!keep\.has\(t\)\) trades\.delete\(t\);/);
  // the reader lists a trade only through a stated claim mapped to a key ("please check" listings list none)
  assert.match(READER, /for \(const x of tick\) if \(!x\.check && tradeOf\.has\(x\.trade\)/);
  // the one tap leaves partner, projects, brands and "please check" rows alone
  assert.match(TAB, /const otherRow = \(p: ProposedSvc\) => p\.delivery === 'partner' \|\| p\.basis === 'shown' \|\| p\.basis === 'brand' \|\| !!p\.check;/);
  assert.match(TAB, /const proposedOwn = \(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => !otherRow\(p\)\);/);
  assert.equal(PROPOSED_COPY.from_projects, 'From your projects'); assert.equal(PROPOSED_COPY.please_check, 'Please check');
});

// Review round 2 (12 Nov 2026): hard profile H09 (its work all in project captions, so no trade of his own) read "We read your company profile
// and found no service we could match" above 35 listed services. That sentence appears only when the list is truly empty.
test('12. "found no service" is said only when nothing is listed', async () => {
  const { listedProfileState, profileStateOf } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
  const h09 = profileStateOf([{ status: 'read', source: 'document_text', choice: 'on', trades: [] }]);
  assert.equal(h09, 'none');
  assert.equal(listedProfileState(h09, 35), 'listed');
  assert.equal(listedProfileState(h09, 0), 'none');
  assert.equal(listedProfileState('hits', 5), 'hits');
  // slice 4: the check screen's one sentence for the state (stateLine; servicesSentences went with the old screen)
  assert.doesNotMatch(stateLine('listed'), /found no service/);
  assert.match(stateLine('listed'), /listed to tick/);
  assert.doesNotMatch(VERIFY_COPY.profile_listed, /found no service/);
  assert.match(TAB, /listedProfileState\(profileStateOf\(profileDocs\), \(d\.proposed_services \|\| \[\]\)\.length\)/);
});

// Review round 2 (12 Nov 2026), the wait: a whole reading takes 22-161 s (p50 101 s). The step-A progress is shown the moment the 5 s poll
// sees it (it reloaded only at the end before), and the reading state is a moving mark beside honest words, never a bare spinner.
test('13. while his profile is read he is told how long and that he can carry on, and what step A read appears without a reload', () => {
  assert.match(VERIFY_COPY.profile_reading, /^Reading your profile\. This takes one to two minutes; you can carry on and come back\./);
  assert.match(stateLine('reading'), /^Reading your profile\. This takes one to two minutes; you can carry on and come back\./, 'the check screen says the same');
  assert.match(TAB, /reading_progress: j\.reading_progress \?\? s\.data\.reading_progress/);
  // slice 4: the check screen's sentence carries the moving mark (and the step-A progress view its own)
  assert.match(TAB, /data-testid=\{profileState === 'reading' \? 'profile-reading' : 'check-lead'\}>\s*\{profileState === 'reading' && !d\.reading \? <Loader2 aria-hidden="true" className="[^"]*animate-spin motion-reduce:animate-none" \/> : null\}<span>\{lead\}<\/span>/);
  assert.match(TAB, /<Loader2 aria-hidden="true" className="[^"]*animate-spin motion-reduce:animate-none" \/>\s*<span>\{PROPOSED_COPY\.progress_help\}<\/span>/);
  assert.match(PROPOSED_COPY.progress_help, /about another minute/);
});

// Round-3 review of slice 4 (12 Nov 2026), findings 4, 6 and 7: on a phone each sticky bar keeps clear of the docked assistant
// bubble, the "Something else" keyboard says Done, and the Done line is short enough for two lines at 360 px.
test('14. the cards\' and screen 1\'s bars keep clear of the assistant bubble; Something else ends with Done; the Done line is short', () => {
  assert.match(CARDS, /'-mx-5 -mb-5 mt-4 flex items-center justify-between gap-3 bg-card px-5 pb-5 pe-16 pt-3 sm:pe-5'[^\n]*data-testid="cards-bar"/);
  assert.match(TAB, /className="[^"]*pe-16 sm:flex-row sm:pe-5" data-testid="understood-bar"/);
  assert.match(CARDS, /<input id=\{uid \+ '-other'\}[^>]*enterKeyHint="done"/);
  const done = COPY.match(/confirmed_done: '([^']+)'/)[1] + ' ' + COPY.match(/verify_finishing: '([^']+)'/)[1];
  assert.ok(done.length <= 62, `the Done line is ${done.length} characters (62, measured: two lines at 360 and 390 px in the confirm bar; 71 took three)`);
});
