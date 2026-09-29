// DOES A SUPPLIER GET A TRUE MONTHLY SCORECARD AGAINST HIS TRADE, IN ENGLISH, WITH THE AVERAGE HIDDEN BELOW
// THREE SUPPLIERS, ONE TIP BY RULE, "NOT ENOUGH DATA YET" WITH NO DATA, AND ONE E-MAIL A MONTH?
// Seat: sales_engineer. 29 Sep 2026, founder_instruction 1013 item 2.
//
// Runs on PRODUCTION inside ONE transaction that always raises, so nothing commits. This PR's file is replayed
// first while its pending note exists. Every row is ZZ DEMO at example.invalid, in two trades that exist only in
// this transaction (zz_demo_1013_a, zz_demo_1013_b), so no real supplier is part of an average. qd.duty_fixtures =
// 'on' makes the tick select ONLY demo suppliers; inside the transaction only, mail to example.invalid is let
// through fn_email_sendable so the queued rows can be counted, and the rollback means nothing is ever sent.
//
// Last complete month in Dubai. Trade A: S1 (2 requests, first quotes after 5 h and 10 h, 1 of 2 won by reveal,
// rated 5), S2 (30 h, 0 of 1, rated 3), S3 (2 h, 1 of 1 won by hire, rated 4), S4 (sent 1, quoted none).
// Trade B: S5 (rated 3) alone with S7 (rated 5). S6: nothing at all.
//   1. S1: median 7.5 h against the trade's 13.2; win 50% against 50%; rating 5 against 4 -> keep_going
//   2. S2 -> respond_faster; S4 -> answer_invitations (no response time, no win rate); S6 -> "not enough data yet"
//   3. trade B has 2 rated suppliers: its average is NOT shown; S5 rated 3/5 -> lift_rating (under 4, no average)
//   4. the tick e-mails each approved demo supplier once, in English (no Arabic letter), through the door;
//      a suppressed address is recorded not_sendable; a second tick sends nothing
//
//   node scripts/eval/supplier_scorecard_proof.mjs     exit 0 = proved, 1 = an assertion failed
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const { sql } = await import('../lib/db.mjs');
const NAME = 'a_supplier_sees_its_monthly_scorecard_against_its_trade';
const replay = existsSync(join(REPO, 'scripts/sql/pending', NAME + '.txt')) ? readFileSync(join(REPO, 'scripts/sql', NAME + '.sql'), 'utf8') : '';

const PROBE = String.raw`
do $p$ declare o jsonb := '{}'; c uuid; s bigint[] := '{}'; x bigint; i uuid; q uuid; n int; t0 timestamptz; k jsonb := '{}';
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  delete from email_domain_mx where domain = 'example.invalid';
  update email_block_pattern set active = false where 'zz.1013.s1@example.invalid' ~ pattern;
  -- the 10th of the last complete month, noon in Dubai
  t0 := ((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month' + interval '9 days 12 hours')::timestamp at time zone 'Asia/Dubai');
  insert into customers (full_name, email) values ('ZZ DEMO 1013 buyer', 'zz.1013.buyer@example.invalid') returning id into c;
  for n in 1..7 loop
    -- THE FOUNDER'S MANDATORY SIX, supplied as evidence (the gate is never softened): a verified +9715 mobile, a
    -- verified owner e-mail, a licence and a company profile that storage.objects HOLDS, signed terms. The storage
    -- rows are written inside this aborted transaction and roll back with it; no file is uploaded.
    insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz_demo_1013/s' || n || '/licence.pdf'),
                                                         ('supplier-docs', 'zz_demo_1013/s' || n || '/profile.pdf');
    insert into leads (company_name, email, claimed, claimed_by, phone, phone_e164, owner_phone_verified, owner_email_verified,
                       license_doc_path, company_profile_doc_path, signed_terms_path, verified, approval_status)
      values ('ZZ DEMO 1013 S' || n, 'zz.1013.s' || n || '@example.invalid', true, 'zz.1013.s' || n || '@example.invalid',
              '+97150000013' || n, '+97150000013' || n, true, true,
              'zz_demo_1013/s' || n || '/licence.pdf', 'zz_demo_1013/s' || n || '/profile.pdf', 'zz_demo_1013/s' || n || '/terms.pdf',
              true, 'approved') returning id into x;
    s := s || x; k := k || jsonb_build_object(x::text, 's' || n);
    if n <= 4 then insert into lead_trade_class (lead_id, trade_code, evidence) values (x, 'zz_demo_1013_a', 'ZZ DEMO');
    elsif n in (5, 7) then insert into lead_trade_class (lead_id, trade_code, evidence) values (x, 'zz_demo_1013_b', 'ZZ DEMO'); end if;
  end loop;
  insert into email_suppressions (email, reason, source) values ('zz.1013.s7@example.invalid', 'unsubscribe', 'zz_demo_1013');

  -- S1: two requests, first quotes after 5 h and 10 h, the first revealed, rated 5
  insert into inquiries (customer_id, category, status, created_at, raw_input) values (c, 'painting', 'revealed', t0, 'ZZ DEMO 1') returning id into i;
  insert into inquiry_matches (inquiry_id, supplier_id, sent_at) values (i, s[1], t0);
  insert into quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (i, s[1], 1000, 'revealed', t0 + interval '5 hours') returning id into q;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at) values (q, i, s[1], c, 1000, 'paid', t0 + interval '1 day');
  insert into reviews (supplier_id, customer_id, inquiry_id, rating, created_at) values (s[1], c, i, 5, t0 + interval '3 days');
  insert into inquiries (customer_id, category, status, created_at, raw_input) values (c, 'painting', 'quoted', t0, 'ZZ DEMO 2') returning id into i;
  insert into inquiry_matches (inquiry_id, supplier_id, sent_at) values (i, s[1], t0);
  insert into quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (i, s[1], 1000, 'submitted', t0 + interval '10 hours');
  -- S2: 30 h, not chosen, rated 3
  insert into inquiry_matches (inquiry_id, supplier_id, sent_at) values (i, s[2], t0);
  insert into quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (i, s[2], 1200, 'submitted', t0 + interval '30 hours');
  insert into reviews (supplier_id, customer_id, rating, created_at) values (s[2], c, 3, t0 + interval '3 days');
  -- S3: 2 h, hired, rated 4
  insert into inquiries (customer_id, category, status, created_at, raw_input, hired_supplier_id) values (c, 'painting', 'completed', t0, 'ZZ DEMO 3', s[3]) returning id into i;
  insert into inquiry_matches (inquiry_id, supplier_id, sent_at) values (i, s[3], t0);
  insert into quotes (inquiry_id, supplier_id, quote_amount, status, created_at) values (i, s[3], 900, 'submitted', t0 + interval '2 hours');
  insert into reviews (supplier_id, customer_id, rating, created_at) values (s[3], c, 4, t0 + interval '3 days');
  -- S4: sent one, quoted none. S5 and S7: rated, alone in trade B. S6: nothing.
  insert into inquiry_matches (inquiry_id, supplier_id, sent_at) values (i, s[4], t0);
  insert into reviews (supplier_id, customer_id, rating, created_at) values (s[5], c, 3, t0 + interval '3 days'), (s[7], c, 5, t0 + interval '3 days');

  -- only what is asserted: the management API cuts a long error message, and the report travels in one
  o := o || jsonb_build_object('s1', (select jsonb_build_object('m', sc->'metrics', 'tip', sc->'tip'->>'code', 'enough', sc->'enough_data', 'act', sc->'activity') from fn_supplier_scorecard(s[1]) sc),
    's2', fn_supplier_scorecard(s[2])->'tip'->>'code',
    's4', (select jsonb_build_object('tip', sc->'tip'->>'code', 'resp', sc->'metrics'->'response_hours'->'you', 'win', sc->'metrics'->'win_rate'->'you') from fn_supplier_scorecard(s[4]) sc),
    's5', (select jsonb_build_object('r', sc->'metrics'->'rating', 'tip', sc->'tip'->>'code') from fn_supplier_scorecard(s[5]) sc),
    's6', (select jsonb_build_object('enough', sc->'enough_data', 'message', sc->'message') from fn_supplier_scorecard(s[6]) sc));
  o := o || jsonb_build_object('t1', fn_sales_engineer_supplier_scorecard_tick());
  o := o || jsonb_build_object('t2', fn_sales_engineer_supplier_scorecard_tick());
  o := o || jsonb_build_object('sent', (select jsonb_object_agg(k->>lead_id::text, outcome) from supplier_scorecard where lead_id = any (s)));
  o := o || jsonb_build_object('mail', (select jsonb_agg(jsonb_build_object('lang', lang, 'arabic', (subject || body) ~ '[؀-ۿ]', 'role', to_role) order by id)
                                          from notifications where to_email = 'zz.1013.s1@example.invalid' and type = 'supplier_scorecard'));
  o := o || jsonb_build_object('body_s1', (select jsonb_build_object('mine', body like '%7.5%', 'trade', body like '%your trade: 13.2%', 'tip', body like '%One thing to improve: %', 'subject', subject)
                                              from notifications where to_email = 'zz.1013.s1@example.invalid' and type = 'supplier_scorecard' limit 1));
  raise exception 'CHK<<%>>', o::text;
end $p$;
`;

let o;
try { await sql(replay + '\n' + PROBE, { retry: false }); }
catch (e) {
  const m = String(e.message).match(/CHK<<(.*?)>>/s);
  if (!m) { console.error('the probe failed before it could report:', String(e.message).slice(0, 1500)); process.exit(1); }
  o = JSON.parse(m[1].replace(/\\"/g, '"').replace(/\\\\n/g, '\\n'));
}
if (!o) { console.error('the probe committed instead of rolling back'); process.exit(1); }
const M = o.s1.m;
const checks = [
  ['S1 median response 7.5 h against the trade 13.2 over 3 suppliers', () => assert.deepEqual([M.response_hours.you, M.response_hours.trade_average, M.response_hours.trade_suppliers], [7.5, 13.2, 3])],
  ['S1 win rate 50% against the trade 50% (reveal and hire both count)', () => assert.deepEqual([M.win_rate.you, M.win_rate.trade_average], [0.5, 0.5])],
  ['S1 rating 5 against the trade 4', () => assert.deepEqual([M.rating.you, M.rating.trade_average], [5, 4])],
  ['S1 tip keep_going; data enough; activity counted', () => assert.deepEqual([o.s1.tip, o.s1.enough, o.s1.act], ['keep_going', true, { requests_sent: 2, quoted: 2, won: 1, ratings: 1 }])],
  ['S2, slower than the trade, is told to respond faster', () => assert.equal(o.s2, 'respond_faster')],
  ['S4, sent a request and quoted none, is told to answer invitations; no response time or win rate', () => {
    assert.deepEqual([o.s4.tip, o.s4.resp, o.s4.win], ['answer_invitations', null, null]); }],
  ['trade B has 2 rated suppliers: no average shown', () => assert.deepEqual([o.s5.r.you, o.s5.r.trade_average, o.s5.r.trade_suppliers], [3, null, 2])],
  ['S5 rated 3/5 with no average is told to lift the rating', () => assert.equal(o.s5.tip, 'lift_rating')],
  ['S6 with no data: "not enough data yet"', () => assert.deepEqual([o.s6.enough, o.s6.message], [false, 'not enough data yet'])],
  ['the tick e-mails every approved demo supplier once; the suppressed one is recorded', () => assert.deepEqual(o.sent,
    { s1: 'queued', s2: 'queued', s3: 'queued', s4: 'queued', s5: 'queued', s6: 'queued', s7: 'not_sendable: suppressed' })],
  ['a second tick sends nothing', () => assert.deepEqual([o.t2.sent, o.t2.not_sendable], [0, 0])],
  ['the e-mail is English, to the supplier, once', () => assert.deepEqual(o.mail.map((m) => [m.lang, m.arabic, m.role]), [['en', false, 'supplier']])],
  ['the e-mail carries the numbers, the trade average and the tip', () => {
    assert.deepEqual([o.body_s1.mine, o.body_s1.trade, o.body_s1.tip], [true, true, true]); assert.match(o.body_s1.subject, /^Your QuotesDone scorecard for \w+ \d{4}$/); }],
];
let failed = 0;
for (const [name, fn] of checks) {
  try { fn(); console.log('PASS', name); } catch (e) { failed++; console.log('FAIL', name, '-', e.message.split('\n')[0]); }
}
console.log(`${checks.length - failed}/${checks.length} PASS; the transaction rolled back, 0 rows left`);
if (failed) { console.log(JSON.stringify(o, null, 1)); process.exit(1); }
