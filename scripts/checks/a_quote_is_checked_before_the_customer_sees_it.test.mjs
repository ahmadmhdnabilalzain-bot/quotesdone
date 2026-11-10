// A QUOTE IS CHECKED BEFORE THE CUSTOMER SEES IT (sales_engineer, 29 Sep 2026, founder ledger 1018 item 2).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the gate no longer runs after every other BEFORE trigger on quotes, a flagged quote is no longer kept a draft,
//     one of the three checks is gone, the supplier's fixes can be written in any language but English, the hold is not
//     24 h from policy, supplier_api tells the customer of a quote the gate held, or the comparison no longer carries
//     (and the portal no longer shows) the reason;
//   * production, in ONE aborted transaction (the pending file replayed first; ZZ DEMO and example.invalid only):
//     scripts/sql/a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it_probe.sql answers PROBE OK.
//
//   node --test scripts/checks/a_quote_is_checked_before_the_customer_sees_it.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { readCustomerPortal } from '../lib/portal_sources.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it';
const FILE = `scripts/sql/${NAME}.sql`;
const src = read(FILE);
const pending = existsSync(join(REPO, 'scripts/sql/pending', `${NAME}.txt`));
const body = (fn) => { const i = src.indexOf(`function public.${fn}(`); assert.ok(i > 0, `${fn} is not defined`); const j = src.indexOf('create or replace function', i + 10); return src.slice(i, j < 0 ? undefined : j); };

test('the gate keeps a flagged quote a draft, after every other BEFORE trigger, and never pulls a shown quote back', () => {
  assert.match(src, /create trigger z40_quote_quality_gate before insert or update of status on public\.quotes/);
  const g = body('fn_quote_quality_gate');
  assert.match(g, /new\.status := 'draft';/, 'a flagged quote is no longer kept from the customer');
  assert.match(g, /if not v_live or h\.released_at is not null then/, 'a quote already out, or already waited, can be held again');
  assert.match(g, /public\.fn_seat_clock_policy\('quote_quality_hold_hours', 24\)/, 'the hold is not 24 h from policy');
});

test('the three checks: the pack checklist, the UAE price range (skipped without a benchmark), and the terms', () => {
  const f = body('fn_quote_quality_flags');
  assert.match(f, /from public\.trade_spec_checklist c/, 'the trade spec checklists are not read');
  assert.match(f, /public\.fn_price_benchmarks\(v_demo, p_quote\.inquiry_id\)/, 'the price is not judged against other requests\' ranges');
  assert.match(f, /from lines l join b on/, 'a line with no benchmark is no longer skipped (an inner join is the skip)');
  assert.match(f, /'well_above', 'well_below'/);
  for (const c of ['no_validity', 'no_delivery_time', 'no_vat_treatment', 'missing_spec']) assert.match(f, new RegExp(`'${c}'`), `${c} is gone`);
});

test('the supplier gets the exact fixes in English only; the customer is told in the request\'s language', () => {
  const t = body('fn_sales_engineer_quote_quality_tick');
  assert.match(t, /'to_role', 'supplier'[\s\S]*?'lang', 'en'/, 'the fixes are not addressed to the supplier in English');
  assert.match(t, /fn_quote_quality_compose\('supplier', 'en'/);
  assert.match(t, /fn_quote_quality_compose\('customer', h\.inq_lang/, 'the customer is not written in the request\'s language');
  assert.doesNotMatch(body('fn_quote_quality_fixes_en'), /[؀-ۿ]/, 'the fixes carry Arabic');
  const c = body('fn_quote_quality_compose');
  assert.match(c, /v_ar boolean := p_kind = 'customer' and/, 'a supplier could be written in Arabic');
  assert.match(c, /تحية طيبة وبعد[\s\S]*وتفضلوا بقبول فائق الاحترام والتقدير/, 'the Arabic customer notice is not in the formal register');
});

test('supplier_api does not tell the customer of a held quote, and the comparison shows the reason', () => {
  const api = functionSource('supplier_api');
  const al = api.slice(api.indexOf('async function acceptLive('), api.indexOf('async function acceptLive(') + 2500);
  assert.ok(al.indexOf('await qualityHold(qid)') > 0 && al.indexOf('await qualityHold(qid)') < al.indexOf('notifyNewQuote(inquiryId)'),
    'acceptLive notifies the customer before reading the quality hold back');
  const cmp = read('supabase/functions/quote_compare/index.ts');
  assert.match(cmp, /from\('quote_quality_hold'\)/, 'quote_compare does not read the holds');
  assert.match(cmp, /a\.quality_check = qualityCheck/, 'the comparison does not carry the reason');
  const portal = readCustomerPortal();
  assert.match(portal, /a\.quality_check/, 'the portal comparison does not show the quality check');
  const text = read('src/components/me/portalText.ts');
  for (const k of ['qq_title', 'qq_held', 'qq_missing_spec', 'qq_price_above', 'qq_price_below', 'qq_no_validity', 'qq_no_delivery_time', 'qq_no_vat_treatment', 'qq_uncorrected'])
    assert.equal(text.split(`${k}:`).length - 1, 2, `${k} is not written in English and Arabic`);
});

// REVIEW OF #1108 (29 Sep 2026): a wait must never publish content the door did not accept.
test('the wait releases only the version the door accepted; a refused submission supersedes the hold', () => {
  const t = body('fn_sales_engineer_quote_quality_tick');
  const guard = t.indexOf('if public.fn_quote_quality_content_md5(q) is distinct from h.accepted_md5 then');
  assert.ok(guard > 0 && guard < t.indexOf("update public.quotes set status = 'submitted'"), 'the duty can release content other than the accepted version');
  assert.match(t, /x\.superseded_at is null/, 'the duty reads superseded holds');
  assert.match(body('fn_quote_quality_gate'), /accepted_md5 = excluded\.accepted_md5/, 'the gate does not record the accepted version');
  const api = functionSource('supplier_api');
  assert.match(api, /if \(g\.held\) \{ await supersedeQualityHold\(qid\);/, 'a spec-held resubmission does not supersede the quality hold');
  assert.match(api, /update\(\{ status: 'draft' \}\)\.eq\('id', qid\); \} catch \(_e\) \{ \/\* the result below already says it was not accepted \*\/ \}\n\s*await supersedeQualityHold\(qid\);/,
    'a review-held resubmission does not supersede the quality hold');
  const al = api.slice(api.indexOf('async function acceptLive('));
  assert.match(al.slice(0, al.indexOf('\n}\n')), /update\(\{ status: 'draft' \}\)\.eq\('id', qid\); \} catch \(_e\) \{ \/\* \*\/ \}\n\s*await supersedeQualityHold\(qid\);/,
    'a resubmission the accept rule refuses does not supersede the quality hold');
});

test('the duty has a clock, the table is exported daily, and the file is pending XOR in MANIFEST', () => {
  assert.match(src, /\('sales_engineer\.quote_quality_hold',[\s\S]*?'15 minutes', true, 'fn_sales_engineer_quote_quality_tick'/);
  assert.match(body('fn_table_export_list'), /\('quote_quality_hold','quote'\)/, 'quote_quality_hold is not in the daily export');
  // Depends-on #1106: its export list is the base, so its stalled_inquiry_rescue row must survive this redefinition
  assert.match(body('fn_table_export_list'), /\('stalled_inquiry_rescue','inquiry'\)/, 'this redefinition drops #1106\'s stalled_inquiry_rescue from the daily export');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: ZZ DEMO quotes are flagged, held, sent their fixes and released', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const block = (pending ? src + '\n' : '') + read(`scripts/sql/${NAME}_probe.sql`);
  let msg = '';
  try { await replaySql(block, { retry: false }); msg = 'the probe committed instead of rolling back'; } catch (e) { msg = String(e.message); }
  const m = msg.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(out.verdict, 'PROBE OK', JSON.stringify(out).slice(0, 3000));
});
