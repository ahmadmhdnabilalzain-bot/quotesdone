// DOES CUSTOMER SUPPORT ASK WHETHER THE CUSTOMER HIRED, RECORD THE ANSWER AS AN OUTCOME, AND NUDGE A QUIET
// CUSTOMER ABOUT THEIR OWN TRADES, IN THE INQUIRY'S LANGUAGE, NEVER TO A SUPPRESSED ADDRESS?
// Seat: customer_support. 29 Sep 2026, founder_instruction 1013 item 1.
//
// Runs on PRODUCTION inside ONE transaction that always raises, so nothing commits. Every pending file it needs is
// replayed first inside the same transaction: this PR's file, and the two it depends on while they are open
// (#1065 inquiries.lang / fn_inquiry_locale, #1064 fn_outcome_record and its z92 rating trigger), read from their
// branches when this checkout does not have them. Every row is ZZ DEMO at example.invalid; qd.duty_fixtures = 'on'
// selects ONLY demo rows. Inside the aborted transaction only, mail to example.invalid is let through
// fn_email_sendable so the queued rows can be counted; the transaction rolls back, so nothing is ever sent.
//
//   FOLLOW-UP  1. a reveal 4 days old is asked once (day_three) in the INQUIRY's language (Arabic inquiry, English
//                 registration -> Arabic); one 15 days old is asked on day_fourteen; a second tick asks nobody again;
//              2. a suppressed address is not asked (duty ledger says not_sendable: suppressed);
//              3. "yes, 4 stars" records outcome 'hired' (correct) on the inquiry and the quote through
//                 fn_outcome_record, sets inquiries.hired_supplier_id, writes the reveal's one review; a second tap
//                 changes nothing; "no" records 'not_hired' (wrong); a bad answer is refused (22023);
//              4. a definite answer closes the question: day 14 does not ask again; "not yet" leaves day 14 to ask.
//   WIN-BACK   5. a customer with no request and no reveal for 60+ days is nudged once, in the language of their
//                 last request, naming their most frequent trade; a suppressed quiet customer is not; a customer
//                 active 30 days ago is not; a second tick writes nothing again.
//
//   node scripts/eval/customer_followup_and_reengagement_proof.mjs     exit 0 = proved, 1 = an assertion failed
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const { sql } = await import('../lib/db.mjs');

// [file, the branch that carries it while its PR is open, the object that proves it is already live]
const DEPS = [
  ['the_supplier_invitation_ends_with_one_question_and_is_always_english', 'origin/sales_engineer/suppliers-always-english', null],
  ['suppliers_are_always_written_in_english_and_customers_in_their_inquirys_language', 'origin/sales_engineer/suppliers-always-english', 'fn_inquiry_locale(uuid)'],
  ['a_decision_names_the_recalled_case_it_followed', 'origin/it-engineer/outcomes-and-cross-seat-challenge', null],
  ['every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason', 'origin/it-engineer/outcomes-and-cross-seat-challenge', 'fn_outcome_record(text,text,text,boolean,text,text,text,text)'],
  ['customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades', null, null],
];
const live = async (sig) => sig && (await sql(`select to_regprocedure('public.${sig}') is not null as ok`))[0].ok;
const src = (name, branch) => {
  const p = join(REPO, 'scripts/sql', name + '.sql');
  if (existsSync(p)) return readFileSync(p, 'utf8');
  return execFileSync('git', ['-C', REPO, 'show', `${branch}:scripts/sql/${name}.sql`], { encoding: 'utf8', maxBuffer: 64 << 20 });
};
// a dependency PR's files are replayed together, unless its proving object is already live in production
const liveBranch = new Set();
for (const [, branch, sig] of DEPS) if (sig && await live(sig)) liveBranch.add(branch);
const replay = [];
for (const [name, branch] of DEPS) {
  if (branch && liveBranch.has(branch)) continue;
  if (!branch && !existsSync(join(REPO, 'scripts/sql/pending', name + '.txt'))) continue;   // this PR's file, applied
  replay.push(src(name, branch));
}
console.log(`replaying ${replay.length} file(s) inside the aborted transaction`);

const PROBE = String.raw`
do $p$ declare o jsonb := '{}'; ca uuid; cb uuid; cc uuid; cd uuid; ce uuid; cf uuid; cg uuid; l bigint;
  ia uuid; ib uuid; ic uuid; id_ uuid; ie uuid; qa uuid; qb uuid; qc uuid; qd uuid; ta uuid; tb uuid; tc uuid; td uuid; e text; k jsonb;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  delete from email_domain_mx where domain = 'example.invalid';
  update email_block_pattern set active = false where 'zz.1013.a@example.invalid' ~ pattern;
  insert into leads (company_name, email) values ('ZZ DEMO 1013 Painters', 'zz.1013.s@example.invalid') returning id into l;
  insert into customers (full_name, email, locale) values ('ZZ DEMO 1013 A', 'zz.1013.a@example.invalid', 'en') returning id into ca;
  insert into customers (full_name, email) values ('ZZ DEMO 1013 B', 'zz.1013.b@example.invalid') returning id into cb;
  insert into customers (full_name, email) values ('ZZ DEMO 1013 C', 'zz.1013.c@example.invalid') returning id into cc;
  insert into customers (full_name, email) values ('ZZ DEMO 1013 D', 'zz.1013.d@example.invalid') returning id into cd;
  insert into customers (full_name, email, locale) values ('ZZ DEMO 1013 E', 'zz.1013.e@example.invalid', 'en') returning id into ce;
  insert into customers (full_name, email) values ('ZZ DEMO 1013 F', 'zz.1013.f@example.invalid') returning id into cf;
  insert into customers (full_name, email) values ('ZZ DEMO 1013 G', 'zz.1013.g@example.invalid') returning id into cg;
  insert into email_suppressions (email, reason, source) values ('zz.1013.b@example.invalid', 'unsubscribe', 'zz_demo_1013'),
                                                               ('zz.1013.g@example.invalid', 'unsubscribe', 'zz_demo_1013');
  insert into inquiries (customer_id, category, status, created_at, raw_input, lang) values (ca, 'painting', 'revealed', now() - interval '6 days', 'ZZ DEMO paint the villa', 'ar') returning id into ia;
  insert into inquiries (customer_id, category, status, created_at, raw_input, lang) values (cb, 'painting', 'revealed', now() - interval '6 days', 'ZZ DEMO paint b', 'en') returning id into ib;
  insert into inquiries (customer_id, category, status, created_at, raw_input, lang) values (cc, 'gypsum', 'revealed', now() - interval '20 days', 'ZZ DEMO ceiling c', 'en') returning id into ic;
  insert into inquiries (customer_id, category, status, created_at, raw_input, lang) values (cd, 'painting', 'revealed', now() - interval '6 days', 'ZZ DEMO paint d', 'en') returning id into id_;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (ia, l, 1000, 'revealed') returning id into qa;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (ib, l, 1000, 'revealed') returning id into qb;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (ic, l, 1000, 'revealed') returning id into qc;
  insert into quotes (inquiry_id, supplier_id, quote_amount, status) values (id_, l, 1000, 'revealed') returning id into qd;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at) values (qa, ia, l, ca, 1000, 'paid', now() - interval '4 days') returning id into ta;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at) values (qb, ib, l, cb, 1000, 'paid', now() - interval '4 days') returning id into tb;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at) values (qc, ic, l, cc, 1000, 'paid', now() - interval '15 days') returning id into tc;
  insert into transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, fee_status, revealed_at) values (qd, id_, l, cd, 1000, 'paid', now() - interval '4 days') returning id into td;
  -- quiet customers: E posted painting twice and gypsum once, 70-80 days ago, the last request in Arabic;
  -- F posted 30 days ago; G is quiet but unsubscribed
  insert into inquiries (customer_id, category, status, created_at, raw_input, lang) values
    (ce, 'gypsum', 'open', now() - interval '80 days', 'ZZ DEMO e1', 'en'), (ce, 'painting', 'open', now() - interval '75 days', 'ZZ DEMO e2', 'en'),
    (ce, 'painting', 'open', now() - interval '70 days', 'ZZ DEMO e3', 'ar'),
    (cf, 'painting', 'open', now() - interval '30 days', 'ZZ DEMO f', 'en'), (cg, 'painting', 'open', now() - interval '70 days', 'ZZ DEMO g', 'en');

  k := jsonb_build_object(ca::text, 'a', cb::text, 'b', cc::text, 'c', cd::text, 'd', ce::text, 'e', cf::text, 'f', cg::text, 'g');
  -- the deciding seat's judgement on A's and C's requests, as the matcher records one (fn_judgement_record)
  perform fn_judgement_record('sales_engineer', 'zz_demo_1013', jsonb_build_object('table', 'inquiries', 'id', ia::text), 'ZZ DEMO which suppliers for this request?', '{"available":true,"cases":[],"finalised_precedent":false,"reason":null}'::jsonb);
  perform fn_judgement_record('sales_engineer', 'zz_demo_1013', jsonb_build_object('table', 'inquiries', 'id', ic::text), 'ZZ DEMO which suppliers for this request?', '{"available":true,"cases":[],"finalised_precedent":false,"reason":null}'::jsonb);
  -- 1-2. the follow-up clock
  o := o || jsonb_build_object('fu1', fn_customer_support_followup_tick(), 'fu2', fn_customer_support_followup_tick());
  o := o || jsonb_build_object('asked', (select jsonb_object_agg(k->>t.customer_id::text, f.stage || '/' || f.lang) from customer_followup f join transactions t on t.id = f.transaction_id where t.id in (ta, tb, tc, td)));
  o := o || jsonb_build_object('ledger', (select jsonb_object_agg(k->>customer_id::text, stage || '/' || outcome) from customer_support_duty_message where customer_id in (ca, cb, cc, cd) and stage like 'followup.%'));
  o := o || jsonb_build_object('note_a', (select jsonb_build_object('lang', lang, 'subject', subject, 'link', body ~ 'https://quotesdone.com/u/followup\?t=[0-9a-f-]{36}') from notifications where to_email = 'zz.1013.a@example.invalid' and type = 'duty_followup_day_three' limit 1));

  -- 3. the answers
  o := o || jsonb_build_object('view_a', fn_customer_followup_view((select f.token from customer_followup f where f.transaction_id = ta)) - 'company');
  o := o || jsonb_build_object('ans_a', fn_customer_followup_answer((select f.token from customer_followup f where f.transaction_id = ta), 'yes', 4, 'ZZ DEMO tidy work, on time'));
  o := o || jsonb_build_object('ans_a2', fn_customer_followup_answer((select f.token from customer_followup f where f.transaction_id = ta), 'no', 1, null));
  o := o || jsonb_build_object('hired_a', (select hired_supplier_id = l from inquiries where id = ia),
                               'review_a', (select jsonb_agg(rating) from reviews where transaction_id = ta));
  o := o || jsonb_build_object('ans_c', fn_customer_followup_answer((select f.token from customer_followup f where f.transaction_id = tc), 'no', null, 'ZZ DEMO went with a cheaper firm'));
  o := o || jsonb_build_object('ans_d', fn_customer_followup_answer((select f.token from customer_followup f where f.transaction_id = td), 'not_yet', null, null));
  o := o || jsonb_build_object('judged', (select jsonb_agg(distinct subject_table || '/' || outcome_correct::text) from seat_judgement where subject_id in (ia::text, qa::text, ic::text, qc::text) and outcome_kind is not null));
  begin perform fn_customer_followup_answer((select f.token from customer_followup f where f.transaction_id = td), 'maybe'); e := 'accepted';
  exception when sqlstate '22023' then e := 'refused'; end;
  o := o || jsonb_build_object('bad', e, 'unknown', fn_customer_followup_view(gen_random_uuid()));

  -- 4. day 14: A answered yes (not asked again), D said not yet (asked again)
  update transactions set revealed_at = now() - interval '15 days' where id in (ta, td);
  o := o || jsonb_build_object('fu3', fn_customer_support_followup_tick());
  -- a separate statement: a sibling subquery of the tick's own statement would read the snapshot from before it ran
  o := o || jsonb_build_object('day14', (select jsonb_agg(k->>t.customer_id::text) from customer_followup f join transactions t on t.id = f.transaction_id where f.stage = 'day_fourteen' and t.id in (ta, td)));

  -- 5. the win-back clock
  o := o || jsonb_build_object('wb1', fn_customer_support_winback_tick(), 'wb2', fn_customer_support_winback_tick());
  o := o || jsonb_build_object('wb_ledger', (select jsonb_object_agg(k->>customer_id::text, outcome) from customer_support_duty_message where customer_id in (ce, cf, cg) and stage = 'winback.dormant'));
  o := o || jsonb_build_object('wb_note', (select jsonb_build_object('lang', lang, 'label', body like '%الدهانات والتشطيبات%', 'n', count(*) over ()) from notifications where to_email = 'zz.1013.e@example.invalid' and type = 'duty_winback_dormant' limit 1));
  raise exception 'CHK<<%>>', o::text;
end $p$;
`;

let o;
try { await sql(replay.join('\n') + '\n' + PROBE, { retry: false }); }
catch (e) {
  const m = String(e.message).match(/CHK<<(.*?)>>/s);
  if (!m) { console.error('the probe failed before it could report:', String(e.message).slice(0, 1500)); process.exit(1); }
  o = JSON.parse(m[1].replace(/\\"/g, '"'));
}
if (!o) { console.error('the probe committed instead of rolling back'); process.exit(1); }
const I = { a: 'a', b: 'b', c: 'c', d: 'd', e: 'e', g: 'g' };
const checks = [
  ['day 3 asked A, day 14 asked C, suppressed B and nobody else', () => assert.deepEqual(o.asked, { [I.a]: 'day_three/ar', [I.c]: 'day_fourteen/en', [I.d]: 'day_three/en' })],
  ['a second tick asks nobody again', () => assert.equal(o.fu2.asked, 0)],
  ['the suppressed address is recorded, not asked', () => assert.equal(o.ledger[I.b], 'followup.day_three/not_sendable: suppressed')],
  ['A is written in the INQUIRY language (Arabic), with the one-tap link', () => assert.deepEqual([o.note_a.lang, o.note_a.link, /[؀-ۿ]/.test(o.note_a.subject)], ['ar', true, true])],
  ['the page reads the question in its language', () => assert.deepEqual([o.view_a.ok, o.view_a.lang, o.view_a.answered], [true, 'ar', false])],
  ['yes: outcome hired, correct, on the inquiry and the quote, by the deciding seat', () => {
    assert.equal(o.ans_a.recorded.inquiry.kind, 'hired'); assert.equal(o.ans_a.recorded.inquiry.correct, true);
    assert.equal(o.ans_a.recorded.quote.kind, 'hired'); assert.equal(o.ans_a.recorded.review, true); }],
  ['yes sets hired_supplier_id and writes the reveal one 4-star review', () => assert.deepEqual([o.hired_a, o.review_a], [true, [4]])],
  ['a second tap changes nothing', () => assert.deepEqual([o.ans_a2.already, o.ans_a2.hired], [true, 'yes'])],
  ['no: outcome not_hired, wrong', () => assert.deepEqual([o.ans_c.recorded.inquiry.kind, o.ans_c.recorded.inquiry.correct], ['not_hired', false])],
  ['not yet records no outcome', () => assert.deepEqual(o.ans_d.recorded, {})],
  ['the outcomes reached seat_judgement', () => assert.ok(o.judged.includes('inquiries/true') && o.judged.includes('inquiries/false'), JSON.stringify(o.judged))],
  ['a bad answer is refused; an unknown token is not found', () => assert.deepEqual([o.bad, o.unknown.ok], ['refused', false])],
  ['day 14: "yes" is not asked again, "not yet" is', () => assert.deepEqual(o.day14, [I.d])],
  ['win-back: the quiet customer once, the suppressed one recorded, the active one not', () => assert.deepEqual(o.wb_ledger, { [I.e]: 'queued', [I.g]: 'not_sendable: suppressed' })],
  ['win-back writes once', () => assert.equal(o.wb_note.n, 1)],
  ['win-back is in the last request language and names their trade', () => assert.deepEqual([o.wb_note.lang, o.wb_note.label], ['ar', true])],
];
let failed = 0;
for (const [name, fn] of checks) {
  try { fn(); console.log('PASS', name); } catch (e) { failed++; console.log('FAIL', name, '-', e.message.split('\n')[0]); }
}
console.log(`${checks.length - failed}/${checks.length} PASS; the transaction rolled back, 0 rows left`);
if (failed) { console.log(JSON.stringify(o, null, 1)); process.exit(1); }
