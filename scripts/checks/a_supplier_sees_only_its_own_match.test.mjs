// A SUPPLIER SEES ONLY ITS OWN MATCH — the supplier-portal audit of 22 Sep 2026, findings SP-N-02,
// SP-N-03, SP-N-04, SP-N-05, SP-C-02, SP-C-04/SP-N-07, SP-F-02, SP-F-04 and SP-N-08 (seat: sales_engineer).
//
// Each of these was a door that did not ask a question it had the answer to, so each test names the
// question and asserts it is still asked. Behaviour against the live database is proved beside this by
// scripts/sql/a_supplier_sees_only_the_jobs_it_was_matched_to_probe.sql, which runs the three routines
// against ZZ DEMO fixtures inside a transaction it aborts.
//
// Comments are blanked before matching, so a comment describing the OLD shape can neither fail nor pass
// a test here (the lesson of 9 Sep 2026: a check that greps source will match your own prose).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const read = (...p) => readFileSync(join(ROOT, ...p), 'utf8');
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));
const sqlCode = (s) => s.replace(/--[^\n]*/g, '');

const API = code(read('supabase', 'functions', 'supplier_api', 'index.ts'));
const SQL = sqlCode(read('scripts', 'sql', 'a_supplier_sees_only_the_jobs_it_was_matched_to.sql'));
/** One action's body, from `if (action === 'x')` to the next top-level action test. */
function action(name) {
  const i = API.indexOf(`action === '${name}'`);
  assert.notEqual(i, -1, `supplier_api has no ${name} action`);
  const rest = API.slice(i);
  const j = rest.slice(1).search(/\n {4}if \(action ===/);
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
  assert.ok(review < insert && review < update, 'a refused quotation must leave no row behind');
  assert.match(a, /if \(!rv\.approved\)[\s\S]{0,400}'quote_review_changes'[\s\S]{0,400}400\)/, 'a failing review must refuse the submission');
});

test('SP-F-02: what the supplier explained comes from the stored review, never from the request', () => {
  const a = action('submit_quote');
  assert.match(a, /boq_excluded: reviewRow\?\.working\?\.boq_excluded \|\| \{\}/, 'exclusions are the engineer\'s record');
  assert.match(a, /qty_explained: reviewRow\?\.working\?\.qty_explained \|\| \{\}/, 'quantity explanations are the engineer\'s record');
  assert.doesNotMatch(a, /body\.boq_excluded|body\.qty_explained/, 'a caller must not be able to declare its own BOQ lines excluded');
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

test('SP-C-04 / SP-N-07: every submit_quote answer carries an explicit accepted flag', () => {
  const a = action('submit_quote');
  for (const shape of [/dry_run: true, accepted: false/, /held: true, missing: r0\.missing/, /accepted: true, coaching/]) {
    assert.match(a, shape);
  }
  assert.match(a, /code: 'quote_review_changes', accepted: false/);
});

test('SP-C-04: the one-click accept believes `accepted`, not `ok`', () => {
  const ui = code(read('src', 'components', 'portal', 'supplier', 'SupplierQuoteBuilder.tsx'));
  const accept = ui.slice(ui.indexOf('const accept = async'), ui.indexOf('const loaded ='));
  assert.match(accept, /j\.accepted === true/, 'a held or drafted quote reached nobody and must not read as sent');
  assert.doesNotMatch(accept, /if \(j && j\.ok\) setSent/);
});

test('SP-F-04: the inbox runs the seed list over spec and budget, not only over summary', () => {
  const inbox = action('inbox');
  assert.match(inbox, /const sSpec = revealed \? i\.spec : \(ownerResolved \? scrubDeepSeeded\(i\.spec, buyerName, seeds, hits\)/);
  assert.match(inbox, /const sBudget = revealed \? i\.budget : \(ownerResolved \? \(scrubDeepSeeded\(i\.budget \?\? null, buyerName, seeds, hits\)/);
  assert.doesNotMatch(inbox, /scrubDeep\(|scrubIdentity\(i\.budget/, 'the un-seeded scrubbers are what left the project name in');
  const scrub = code(read('supabase', 'functions', 'supplier_api', 'identity_scrub.ts'));
  assert.match(scrub, /export function scrubDeepSeeded[\s\S]{0,400}redactText\(s, seeds\)\.text/);
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

test('SP-N-02: the recommender never returns one competitor\'s price or promise', () => {
  assert.match(RECOMMEND, /when \(select n from stat\) < 3[\s\S]{0,200}'thin_market'/, 'below three bids the median IS a rival\'s quotation');
  const out = RECOMMEND.slice(RECOMMEND.indexOf("'recommended_price'"));
  // The jsonb KEY form ('low', …), not the bare word: 'low' is also the value of risk_level.
  for (const key of ['low', 'high', 'lowest', 'highest', 'observed']) {
    assert.ok(!new RegExp(`'${key}',\\s`).test(out), `the '${key}' key publishes a single competitor's figure verbatim`);
  }
  assert.match(RECOMMEND, /where r\.c >= 2/, 'a lead time or warranty is suggested only when two or more bids gave it');
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

test('the seed scrub is SECURITY DEFINER with a pinned search_path and no PUBLIC execute', () => {
  const fn = SQL.slice(SQL.indexOf('function public.fn_supplier_safe_text'), SQL.indexOf('function public.fn_supplier_quote_recommend'));
  assert.match(fn, /security definer/);
  assert.match(fn, /set search_path to 'public', 'pg_temp'/);
  for (const who of ['public', 'anon', 'authenticated']) {
    assert.ok(SQL.includes(`revoke execute on function public.fn_supplier_safe_text(uuid, text) from ${who};`), `EXECUTE must be revoked from ${who}`);
  }
});

test('the SQL file is in the MANIFEST', () => {
  assert.ok(read('scripts', 'sql', 'MANIFEST.txt').split('\n').map((l) => l.trim())
    .includes('scripts/sql/a_supplier_sees_only_the_jobs_it_was_matched_to.sql'));
});
