// A SUPPLIER SEES ONLY ITS OWN MATCH — the supplier-portal audit of 22 Sep 2026, findings SP-N-02,
// SP-N-03, SP-N-04, SP-N-05, SP-C-02, SP-C-04/SP-N-07, SP-F-02, SP-F-04 and SP-N-08 (seat: sales_engineer).
//
// Each of these was a door that did not ask a question it had the answer to, so each test names the
// question and asserts it is still asked. These are SOURCE assertions and they are not the proof:
// behaviour is proved beside them by supabase/functions/supplier_api/submit_review.test.ts (the real
// payload of each quoting door through the real review rules — written because the first version of
// this fix was grep-tested and shipped a refusal that would have closed both doors) and by
// scripts/sql/a_supplier_sees_only_the_jobs_it_was_matched_to_probe.sql (the three routines against ZZ
// DEMO fixtures inside a transaction it aborts).
//
// Comments are blanked before matching, so a comment describing the OLD shape can neither fail nor pass
// a test here (the lesson of 9 Sep 2026: a check that greps source will match your own prose).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pendingNotes, manifestHas } from '../lib/pending_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const read = (...p) => readFileSync(join(ROOT, ...p), 'utf8');
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));
const sqlCode = (s) => s.replace(/--[^\n]*/g, '');

const API = code(functionSource('supplier_api'));
const SQL = sqlCode(read('scripts', 'sql', 'a_supplier_sees_only_the_jobs_it_was_matched_to.sql'));
/** One action's body, from `if (action === 'x')` to the next top-level action test, or to the end of the handler that
 *  holds it (the column-0 `}` that closes its action group since the 9 Nov 2026 split; `};` of handle before it). */
function action(name) {
  const i = API.indexOf(`action === '${name}'`);
  assert.notEqual(i, -1, `supplier_api has no ${name} action`);
  const rest = API.slice(i);
  const j = rest.slice(1).search(/\n {4}if \(action ===|\n\}/);
  return j === -1 ? rest : rest.slice(0, j + 1);
}
const RECOMMEND = SQL.slice(SQL.indexOf('function public.fn_supplier_quote_recommend'), SQL.indexOf('function public.fn_supplier_opportunities'));
const OPPS = SQL.slice(SQL.indexOf('function public.fn_supplier_opportunities'), SQL.indexOf('function public.fn_supplier_workspaces'));
const WORKSPACES = SQL.slice(SQL.indexOf('function public.fn_supplier_workspaces'));

test('SP-N-03: the one matched-inquiry gate asks public.inquiry_matches and fails closed', () => {
  const g = API.slice(API.indexOf('async function matchedInquiry'), API.indexOf('const ownQuoteFile'));
  assert.match(g, /from\('inquiry_matches'\)[\s\S]{0,160}eq\('supplier_id', supplierId\)/, 'the gate must ask inquiry_matches for THIS supplier');
  assert.match(g, /if \(error \|\| !data \|\| !data\.length\) return null;/, 'an unreadable inquiry_matches must refuse, never assume a match');
});

for (const name of ['submit_quote', 'extract_quote']) {
  test(`SP-N-03: ${name} resolves the enquiry through the gate and answers 404, not 403`, () => {
    const a = action(name);
    assert.match(a, /await matchedInquiry\(Number\(sup\.id\), body\.inquiry_id\)/, `${name} must resolve the enquiry through matchedInquiry`);
    assert.match(a, /matchedInquiry[\s\S]{0,200}return J\(\{ error: 'not_found', code: 'not_found' \}, 404\)/, `${name} must refuse an unmatched enquiry with 404`);
  });
  test(`SP-N-04: ${name} accepts a quotation file only under quotes/<this supplier>/`, () => {
    assert.match(action(name), /ownQuoteFile\(/, `${name} must gate the caller's original_file_path`);
  });
}

test('SP-N-03: nothing in submit_quote reads the caller\'s inquiry_id after the gate', () => {
  const after = action('submit_quote').split('matchedInquiry(Number(sup.id), body.inquiry_id)')[1];
  assert.doesNotMatch(after, /body\.inquiry_id/, 'every read must be keyed on the gate\'s answer, not on the request body');
});

test('SP-N-04: the prefix rule is the upload paths\' own prefix, and rejects traversal', () => {
  const f = API.slice(API.indexOf('const ownQuoteFile'), API.indexOf('const NOT_MY_FILE'));
  // Both prefixes the platform itself writes, and only those: extract_quote's and the review chat's.
  assert.match(f, /startsWith\(`quotes\/\$\{supplierId\}\/`\)/);
  assert.match(f, /startsWith\(`review\/\$\{supplierId\}\/`\)/);
  assert.match(f, /!s\.includes\('\.\.'\)/);
});

test('SP-F-02: the quotation review runs inside submit_quote, before the first write', () => {
  const a = action('submit_quote');
  const review = a.indexOf('reviewQuotation(');
  const insert = a.indexOf("from('quotes').insert(");
  const update = a.indexOf("from('quotes').update(det)");
  assert.notEqual(review, -1, 'submit_quote must run reviewQuotation — the chat rules are not the chat\'s alone');
  assert.ok(review < insert && review < update, 'the verdict must be known before the row is written');
});

test('SP-F-02: a failing review HOLDS the quote — it does not refuse it', () => {
  // Review of #854: a hard 400 here would have taken both quoting doors offline, because neither form
  // has a field for several of the details the review asks for (proved in submit_review.test.ts).
  const a = action('submit_quote');
  assert.match(a, /if \(reviewIssues\) \{[\s\S]{0,1200}accepted: false, held: true, code: 'quote_review_changes'/);
  assert.doesNotMatch(a, /'quote_review_changes'[^\n]*\}, 400\)/, 'a review failure must not be a refusal');
  assert.match(a, /if \(reviewIssues\) \{[\s\S]{0,300}update\(\{ status: 'draft' \}\)/, 'a held quote must not sit in a status the customer can read');
});

test('SP-F-02: spec_approve is gated too — it releases a held quote to the customer', () => {
  const a = action('spec_hold');   // the spec_hold / spec_fill / spec_approve branch
  // 10 Nov 2026 (evidence run, finding a; live re-run ea40c830): the review is ONE release check, defined once in this
  // branch; spec_hold builds the form from it, spec_fill asks it before it says complete, spec_approve before it releases.
  const check = a.indexOf('const releaseCheck: Precheck = async (row, answers) =>');
  assert.ok(check !== -1, 'the release must depend on a review of the STORED quote');
  assert.match(a.slice(check), /return releaseReview\(inqSafe, row, await repo\.lines\(String\(row\.id\)\), answers, \{ requirements: ctx\.requirements, checklist: ctx\.checklist \}, resolvedFrom\(rrow\?\.working\)\);/, 'the release check reviews the stored quote with the desk\'s own inputs');
  const m = code(read('supabase', 'functions', 'supplier_api', 'submit_review.ts'));
  assert.match(m, /export function releaseReview\([\s\S]{0,400}workingFromStoredQuote\(row, lines\)[\s\S]{0,200}reviewQuotation\(inq, w, now, desk\)/, 'the release review is not the review of the stored row');
  assert.match(a, /\(await deskView\(q, lines, hold, ctx, releaseCheck\)\)\.schema/, 'spec_hold builds its form without the release check');
  assert.match(a, /await approve\(repo,[\s\S]{0,300}releaseCheck\);/, 'spec_approve releases without the review');
  assert.match(a, /await fillIn\(repo,[\s\S]{0,300}, ctx, render, releaseCheck\);/, 'spec_fill says complete without the review');
});

test('SP-F-02: spec_approve\'s review is a PRECHECK — a refusal must not strand the quote', () => {
  // Re-review of #854: approve() marks the hold released BEFORE it calls accept, and liveHold() reads
  // only open and awaiting_approval, so refusing from inside accept left the quote unsent and the
  // hold desk shut — spec_fill and spec_approve both answering not_awaiting_approval, with nothing
  // named to fix. The precheck runs before the release and puts the hold back to 'open'.
  const wf = code(read('supabase', 'functions', '_shared', 'line_specs', 'workflow.ts'));
  const ap = wf.slice(wf.indexOf('export async function approve('));
  // The precheck is asked through deskView, the one evaluator of the desk (live re-run ea40c830).
  const pre = ap.indexOf('const view = await deskView(q, lines, hold, ctx, precheck);');
  const released = ap.indexOf("state: 'released'");
  assert.ok(pre !== -1 && pre < released, 'the precheck must be asked before the hold is released');
  assert.match(ap, /if \(view\.missing\.length\) \{[\s\S]{0,300}state: 'open', missing: view\.missing[\s\S]{0,200}'still_missing'/, 'a refusal reopens the desk carrying what to fix');
  assert.match(wf, /export async function deskView\([\s\S]{0,600}const pre = precheck \? await precheck\(q, answers\) : null;/, 'deskView no longer asks the release check');
  const a = action('spec_hold');
  const m = code(read('supabase', 'functions', 'supplier_api', 'submit_review.ts'));
  assert.match(m, /return rvw\.approved \? null : \{ missing: rvw\.issues\.map\(issueAsMissing\), issues: rvw\.issues \};/, 'the issues are handed back, not discarded');
  assert.match(a, /if \(!inqSafe\) return \{ missing: \[\{[\s\S]{0,400}review_unavailable/, 'a transient inbox failure must not strand the quote either');
});

test('SP-C-04: a review hold carries what to fix in the shape the card already renders', () => {
  // The portal renders a held quote from missing / spec_missing; a review hold used to carry
  // neither, so QuoteCheck printed "Nothing missing — this is a complete quote." over a held quote.
  const a = action('submit_quote');
  assert.match(a, /const reviewMissing = rv\.approved \? \[\] : rv\.issues\.map\(issueAsMissing\);/);
  assert.match(a, /code: 'quote_review_changes', missing: reviewMissing, review_issues: reviewIssues/);
  assert.match(a, /spec_missing: \[\.\.\.a\.missing, \.\.\.reviewMissing\], would_hold: a\.held \|\| !!reviewIssues/);
});

test('SP-F-02: the dry run reports the review instead of pretending it would be accepted', () => {
  const a = action('submit_quote');
  assert.match(a, /would_accept: acc\.accept && !a\.held && !reviewIssues, review_issues: reviewIssues/);
});

test('SP-F-02: what the supplier explained comes from the stored review, never from the request', () => {
  const a = action('submit_quote');
  assert.match(a, /withResolved\([\s\S]{0,400}resolvedFrom\(reviewRow\?\.working\)\)/, 'the explanations are the engineer\'s record');
  assert.doesNotMatch(a, /body\.boq_excluded|body\.qty_explained/, 'a caller must not be able to declare its own BOQ lines excluded');
  const m = code(read('supabase', 'functions', 'supplier_api', 'submit_review.ts'));
  assert.match(m, /boq_excluded: \{\}, qty_explained: \{\}, corrections: \[\]/, 'the builder never reads them off the body');
});

test('SP-C-02: the dry run snapshots the row and its lines, and puts them back', () => {
  const a = action('submit_quote');
  assert.match(a, /const dryRun = body\.dry_run === true;/);
  const snap = a.indexOf('snapCols');
  const write = a.indexOf("from('quotes').update(det)");
  assert.ok(snap !== -1 && snap < write, 'the snapshot must be taken before the write it undoes');
  assert.match(a, /if \(se \|\| sle \|\| !sr\) return J\(\{ error: 'preflight_unavailable'/, 'a snapshot we could not take refuses the check');
  assert.match(a, /if \(dryRun\) \{[\s\S]{0,1400}update\(snapRow\)[\s\S]{0,400}insert\(snapLines\)/, 'the prior row and its lines are restored');
  assert.match(a, /if \(dryRun\) \{[\s\S]{0,1600}from\('quotes'\)\.delete\(\)\.eq\('id', qid\)/, 'a row the check created is removed');
  assert.doesNotMatch(a, /update\(\{ status: prior\?\.status \|\| 'draft' \}\)/, 'restoring only the status is what let a dry run rewrite a sent quotation');
});

test('SP-C-02: a restore that failed pages, and does not answer 200', () => {
  // Review of #854: it answered ok:true with restored:false and a console line nobody reads, so a SENT
  // quotation could be left with its lines deleted and nothing would raise it.
  const a = action('submit_quote');
  assert.match(a, /if \(!restored\) \{[\s\S]{0,900}signal: 'dry_run_restore_failed'/, 'a failed restore writes an agent_runs error row');
  assert.match(a, /if \(!restored\) \{[\s\S]{0,1400}'preflight_restore_failed'[\s\S]{0,200}500\)/, 'and answers 500');
});

test('SP-C-04 / SP-N-07: every submit_quote answer carries an explicit accepted flag', () => {
  const a = action('submit_quote');
  for (const shape of [/dry_run: true, accepted: false/, /held: true, missing: r0\.missing/, /accepted: true, coaching/]) {
    assert.match(a, shape);
  }
  assert.match(a, /accepted: false, held: true, code: 'quote_review_changes'/);
});

test('SP-C-04: the one-click accept believes `accepted`, not `ok`', () => {
  const ui = code(read('src', 'components', 'portal', 'supplier', 'SupplierQuoteBuilder.tsx'));
  const accept = ui.slice(ui.indexOf('const accept = async'), ui.indexOf('const loaded ='));
  assert.match(accept, /j\.accepted === true/, 'a held or drafted quote reached nobody and must not read as sent');
  assert.doesNotMatch(accept, /if \(j && j\.ok\) setSent/);
});

test('SP-F-04: summary, spec and budget all pass the BOQ\'s own gate — redaction, residual scan, withhold', () => {
  // Review of #854: redactText alone matches seeds on WORD BOUNDARIES, so "MarsaHeights Villa 7" kept
  // the project name. redactBoq adds residualScan, which matches the same seeds as bare substrings and
  // HOLDS. The BOQ path always had it; spec and budget did not.
  const inbox = action('inbox');
  // summary was the LAST one left on redactText alone (re-review of #854) — and it is the field that is
  // always populated and always on the card, so it was the widest of the three leaks.
  assert.match(inbox, /const summaryGate = revealed \|\| !ownerResolved \? null : inboxField<string>\(i\.summary \?\? null, buyerName, seeds, hits\)/);
  assert.match(inbox, /summary_withheld: summaryWithheld/);
  assert.match(inbox, /const specGate = revealed \|\| !ownerResolved \? null : inboxField\(i\.spec, buyerName, seeds, hits\)/);
  assert.match(inbox, /const budgetGate = revealed \|\| !ownerResolved \? null : inboxField<string>\(i\.budget \?\? null, buyerName, seeds, hits\)/);
  assert.match(inbox, /spec_withheld: specWithheld/, 'a withheld brief must be said out loud, as the BOQ already is');
  assert.match(inbox, /budget_withheld: budgetWithheld/);
  assert.doesNotMatch(inbox, /scrubDeep\(|scrubIdentity\(i\.budget|scrubDeepSeeded|redactText\(/, 'the un-gated scrubbers are what left the project name in');
  assert.doesNotMatch(code(functionSource('supplier_api')), /import \{[^}]*redactText/, 'nothing in supplier_api reaches for the un-scanned redactor any more');
  const scrub = code(read('supabase', 'functions', 'supplier_api', 'identity_scrub.ts'));
  // 13 Nov 2026: the customer's seed PHRASES are painted first (a project named after its area must go whole before the
  // shared list reduces "Barsha" to "Dubai"); the gate is still redactBoq over scrubDeep, residual scan and all.
  assert.match(scrub, /export function inboxField[\s\S]{0,1200}redactBoq\(scrubDeep\((?:v|seeded), buyerName, hits\) as T, seeds\)/);
  assert.match(scrub, /export function inboxBoq[\s\S]{0,300}inboxField\(neutraliseCadLines\(boq\) as T/, 'one gate, not two');
});

test('SP-N-08: supplier_pay asks who is calling through _shared/signed_in_user', () => {
  const pay = code(read('supabase', 'functions', 'supplier_pay', 'index.ts'));
  assert.match(pay, /await signedInUser\(admin, req\.headers\.get\('Authorization'\)\)/);
  assert.doesNotMatch(pay, /admin\.auth\.getUser/, 'an auth outage must answer 503, not 401 "Not signed in"');
});

test('SP-N-02: the recommender requires a match and counts only submitted bids', () => {
  assert.match(RECOMMEND, /matched as \([\s\S]{0,300}from public\.inquiry_matches m[\s\S]{0,140}m\.supplier_id = p_lead_id/);
  assert.match(RECOMMEND, /bids as \([\s\S]{0,700}q\.status in \('submitted', 'revealed'\)/, 'a draft is not a bid');
  assert.match(RECOMMEND, /when not \(select ok from matched\)[\s\S]{0,300}'not_found'/);
});

test('SP-N-02: the floor counts COMPANIES, not rows', () => {
  // Review of #854: count(*) let one rival submitting three priced options clear a three-bid floor
  // alone, and the median of those three is that rival's middle option.
  assert.match(RECOMMEND, /select count\(distinct supplier_id\) n,/);
  assert.match(RECOMMEND, /when \(select n from stat\) < 3[\s\S]{0,200}'thin_market'/);
});

test('SP-N-02: no median and no percentile leave the routine — a bracket does', () => {
  // Review of #854, with the arithmetic: for three sorted bids a<b<c, p25=(a+b)/2 and p75=(b+c)/2, so
  // a = 2*p25 - median and c = 2*p75 - median. Rounding the median failed too: the fixture median
  // 61000 is already a multiple of 1000. A bracket has no centre to invert.
  const out = RECOMMEND.slice(RECOMMEND.indexOf("'recommended_price'"), RECOMMEND.indexOf("'market_position'"));
  for (const key of ['low', 'high', 'lowest', 'highest', 'observed', 'p25', 'p75', 'median']) {
    assert.ok(!new RegExp(`'${key}',\\s`).test(out), `the '${key}' key publishes, or reconstructs, a single competitor's figure`);
  }
  assert.match(out, /'range_low', \(select lo from band\)/);
  assert.match(out, /'range_high', \(select hi from band\)/);
  assert.match(RECOMMEND, /floor\(mid_raw \/ step\) \* step as lo/, 'the published figure is the bracket, not the midpoint');
  // The bracket's MIDDLE, not its bottom edge: the edge is up to a whole step low and it is what the
  // one-click accept sends, so the Quote Builder systematically under-bid (re-review of #854).
  assert.match(RECOMMEND, /lo \+ step \/ 2 as mid/);
  assert.match(out, /'value', \(select mid from band\)/);
  assert.doesNotMatch(RECOMMEND, /'verdict', 'at the market midpoint'/, 'the verdict must describe the bracket, not claim the midpoint');
  assert.match(RECOMMEND, /where r\.c >= 2/, 'a lead time or warranty is suggested only when two or more bids gave it');
});

test('SP-N-02: market_position.your_index has its own floor and its own status filter', () => {
  // Review of #854: idx to three decimal places over ONE measured enquiry recovered the others'
  // median to about a tenth of a percent, and the outer query counted the supplier's own drafts.
  const habit = RECOMMEND.slice(RECOMMEND.indexOf('habit as ('), RECOMMEND.indexOf('risk as ('));
  assert.match(habit, /round\(avg\(ratio\)::numeric, 2\)/, 'three decimal places was the leak');
  assert.match(habit, /count\(distinct o2\.supplier_id\)[\s\S]{0,300}>= 3/, 'only enquiries three other companies bid on');
  assert.match(habit, /and q\.status in \('submitted', 'revealed'\)/, 'a draft is not a bid, on this side either');
  assert.match(RECOMMEND, /case when n >= 3 then round\(idx, 1\) else null end idx/, 'one decimal place: two let a supplier difference one enquiry against the next');
  assert.match(RECOMMEND, /'your_quotes_measured', \(select n_band from habit_out\)/, 'the count is a band, not a number');
  assert.match(RECOMMEND, /case when n < 3 then null\s*\n\s*when n <= 5 then '3-5'/, 'a count below three must not fall through and read "6-10"');
  assert.doesNotMatch(RECOMMEND.slice(RECOMMEND.indexOf("'market_position'")), /from habit\)/, 'the unfloored index must not be published');
});

test('SP-N-02: the recommender reads the summary through the supplier-safe projection and the seed scrub', () => {
  assert.match(RECOMMEND, /inq as \(select \* from public\.inquiries_supplier_safe/);
  assert.match(RECOMMEND, /'summary', public\.fn_supplier_safe_text\(p_inquiry_id, \(select summary from inq\)\)/);
});

test('SP-N-03: the opportunities list is restricted to this supplier\'s matches', () => {
  assert.match(OPPS, /cand as \([\s\S]{0,900}exists \(select 1 from public\.inquiry_matches m[\s\S]{0,140}m\.supplier_id = p_lead_id\)/);
  assert.ok(!OPPS.includes('Outside your registered trade'), 'a list that says a job is not yours has already shown it to you');
  assert.ok(!/'open_inquiries', \(select count\(\*\) from public\.inquiries/.test(OPPS), 'the estate-wide open count is not this supplier\'s business');
});

test('SP-N-05: a workspace is titled with the masked summary until the reveal is paid for', () => {
  assert.match(WORKSPACES, /from public\.transactions t[\s\S]{0,200}t\.supplier_id = p_lead_id/, 'the reveal gate is a transactions row, the same definition the inbox uses');
  assert.match(WORKSPACES, /public\.fn_supplier_safe_text\(i\.id, i\.summary_masked\)/);
});

test('SP-N-03: no supplier-facing routine publishes an estate-wide count', () => {
  // Review of #854: the count removed from fn_supplier_opportunities was still in fn_supplier_workspaces.
  for (const [name, body] of [['opportunities', OPPS], ['workspaces', WORKSPACES]]) {
    assert.ok(!/count\(\*\) from public\.inquiries\b(?![\s\S]{0,80}inquiry_matches)/.test(body.replace(/\s+/g, ' ')),
      `fn_supplier_${name} must not tell a supplier how much work the estate holds`);
  }
});

test('the seed scrub is SECURITY DEFINER with a pinned search_path and no PUBLIC execute', () => {
  const fn = SQL.slice(SQL.indexOf('function public.fn_supplier_safe_text'), SQL.indexOf('function public.fn_supplier_quote_recommend'));
  assert.match(fn, /security definer/);
  assert.match(fn, /set search_path to 'public', 'pg_temp'/);
  for (const who of ['public', 'anon', 'authenticated']) {
    assert.ok(SQL.includes(`revoke execute on function public.fn_supplier_safe_text(uuid, text) from ${who};`), `EXECUTE must be revoked from ${who}`);
  }
});

test('the SQL files are accounted for — a pending note, not a MANIFEST line', () => {
  // The MANIFEST is what HAS been applied. The orchestrator applies these, so until then each carries a
  // note (scripts/lib/pending_sql.mjs); canonical_routine_manifest refuses one that claims both.
  const manifest = read('scripts', 'sql', 'MANIFEST.txt').split('\n').map((l) => l.trim());
  const notes = pendingNotes();
  for (const f of ['scripts/sql/a_supplier_sees_only_the_jobs_it_was_matched_to.sql',
                   'scripts/sql/a_supplier_sees_only_the_jobs_it_was_matched_to_probe.sql']) {
    assert.ok(notes.has(f) !== manifestHas(f), `${f}: exactly one of a pending note and a MANIFEST line`);
    assert.equal(manifest.filter((l) => l === f).length <= 1, true, `${f} is listed twice in the MANIFEST`);
  }
});
