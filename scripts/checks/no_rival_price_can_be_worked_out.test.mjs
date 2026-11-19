// NO RIVAL'S PRICE CAN BE WORKED OUT, AND THE CUSTOMER SEES THE QUOTED PRICE (sales_engineer, 19 Nov 2026; founder rulings 1683, 1686,
// 1687). Reads the CANONICAL body of each routine (the last applied or pending file that defines it, scripts/lib/canonical_body.mjs),
// so a later file that brings a leak back fails here. FAILS if:
//   fn_supplier_stats counts a draft or a withdrawn quote, or a request still taking quotes (the supplier can move his own price
//     there and watch the answer: review of c1d1fd657), compares with fewer than 3 other companies, sends a figure before 5
//     comparisons, sends a percentage finer than a 5-point step (one rival: mine / (1 + pct/100) was his price), reads the band
//     from the unrounded average, or sends times_lowest;
//   fn_supplier_market sends a low, a high or a mean, counts the asker's own or a draft quote, or answers under 5 quotes / 3 companies;
//   fn_customer_decision_support, fn_pool_say or fn_inquiry_conversation_summary_build reads the generated margin column instead of quote_amount;
//   the company knowledge says the customer's price carries a platform margin.
//   node --test scripts/checks/no_rival_price_can_be_worked_out.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, read } from '../lib/canonical_body.mjs';

const FILE = 'scripts/sql/no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.sql';
// Comments out, whitespace folded: a comment that names the old shape must not satisfy or fail a check.
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n').replace(/\s+/g, ' ').toLowerCase();
const body = (fn) => code(canonicalBody(fn).body);

test('fn_supplier_stats: submitted quotes only, 3 other companies an inquiry, 5 inquiries, 5-point steps', () => {
  const b = body('fn_supplier_stats');
  const pos = b.slice(b.indexOf('with myq as'), b.indexOf('into v_pos from agg'));
  assert.ok(pos.length > 100, 'the price_positioning block was not found');
  assert.match(pos, /q\.status in \('submitted','revealed'\)/, 'my side must count only submitted or revealed quotes');
  assert.match(pos, /join inquiries i on i\.id = q\.inquiry_id/, 'my side must read the request\'s status');
  assert.match(pos, /i\.status in \('completed','closed','cancelled','expired','lost'\)/, 'a request still taking quotes is counted');
  assert.match(pos, /supplier_id is distinct from p_supplier_id and q\.status in \('submitted','revealed'\)/, 'the other side must be OTHER suppliers\' submitted quotes');
  assert.match(pos, /group by q\.inquiry_id, q\.supplier_id/, 'three options from one rival must be one rival');
  assert.match(pos, /where p\.n>=3/, 'an inquiry needs at least 3 other companies');
  assert.match(pos, /case when n < 5 then jsonb_build_object\('ready', false/, 'no figure before 5 comparisons');
  for (const k of ['lowest_rate', 'pct_low5', 'pct_avg5']) {
    assert.match(pos, new RegExp(`round\\([^;]*?/5\\)\\*5 ${k}\\b`), `${k} must be on a 5-point step`);
  }
  assert.match(pos, /'avg_pct_above_lowest', pct_low5, 'avg_pct_vs_average', pct_avg5/, 'a percentage is sent unrounded');
  assert.match(pos, /'band', case when pct_avg5 <= -5/, 'the band must be read from the rounded average');
  assert.doesNotMatch(pos, /avg\(pct_avg\) <=|'times_lowest', count/, 'the raw average or the exact times_lowest is sent');
  assert.doesNotMatch(pos, /::numeric,1\)/, 'a percentage to 0.1% is back');
});

test('fn_supplier_market: other suppliers\' submitted quotes, 5 from 3 companies, no low / high / mean, rounded', () => {
  const b = body('fn_supplier_market');
  const priced = b.slice(b.indexOf('priced as ('), b.indexOf('figures as ('));
  assert.match(priced, /q\.supplier_id is distinct from p_lead_id/, 'the asker\'s own quotes are counted');
  assert.match(priced, /q\.status in \('submitted', 'revealed'\)/, 'drafts or withdrawn quotes are counted');
  const money = b.slice(b.indexOf('from priced'), b.indexOf('as money_obj'));
  assert.match(money, /r\.n < 5 or r\.n_sup < 3/, 'the 5-quote / 3-company floor is missing');
  assert.doesNotMatch(money, /'low'|'high'|'mean'|min\(amt\)|max\(amt\)|avg\(amt\)/, 'a low, a high or a mean is sent');
  for (const k of ['median', 'p25', 'p75']) assert.match(money, new RegExp(`'${k}', round\\(`), `${k} is not rounded to its step`);
});

test('the customer and the seats read quote_amount, never the generated margin column', () => {
  for (const fn of ['fn_customer_decision_support', 'fn_pool_say', 'fn_inquiry_conversation_summary_build']) {
    assert.doesNotMatch(body(fn), /customer_price|margin_rate/, `${fn} reads the retired margin`);
  }
  assert.match(body('fn_customer_decision_support'), /q\.quote_amount price/);
  assert.doesNotMatch(body('fn_company_self_knowledge_sync'), /includes the '\s*'platform margin|includes the platform margin/,
    'the company knowledge says the customer\'s price carries a margin');
});

test('the file proves it with a probe that raises, and restates every revoke', () => {
  const src = read(FILE);
  assert.match(src, /raise exception 'PROBE FAILED: %'/);
  assert.match(src, /raise exception 'ZZPROBE rollback'/);
  assert.match(src, /'PROBE OK: two quotes give no figure/);
  for (const sig of ['fn_supplier_stats(bigint)', 'fn_supplier_market(bigint)', 'fn_customer_decision_support(uuid)',
    'fn_pool_say(text, text, text, jsonb, boolean)', 'fn_company_self_knowledge_sync()', 'fn_inquiry_conversation_summary_build(uuid)']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `no revoke for ${sig}`);
  }
});

test('the portals print no low or high, and the decision panel says the price excludes VAT', () => {
  const mi = read('src/components/portal/supplier/MarketIntelligence.tsx');
  assert.doesNotMatch(mi, /avg_market_price\.(low|high)\b/, 'the market panel prints a lowest or a highest quote');
  const ds = read('src/components/portal/twin/DecisionSupport.tsx');
  assert.doesNotMatch(ds, /aed\(r\.cheapest_price\)/, 'the cheapest price is printed without "excluding VAT"');
  assert.match(ds, /' excluding VAT'/);
  const ins = read('src/components/portal/supplier/SupplierInsightsSummary.tsx');
  assert.doesNotMatch(ins, /lowest: pp\.times_lowest/, 'the insights panel shows how often the supplier was lowest');
  assert.doesNotMatch(read('src/components/portal/supplier/workspaceCopy.ts'), /\{lowest\}/, 'the copy still says how often he was lowest');
});
