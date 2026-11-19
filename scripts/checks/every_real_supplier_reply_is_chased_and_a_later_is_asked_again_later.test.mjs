// Every real supplier reply is chased, and a "later" is asked again later (sales_engineer, agent chase-fix, 19 Nov 2026; ruling 1543).
// Measured: lead 455's touch 2 (supplier_reply_followup 18), due 19 Nov 06:50 UTC, was held all day by the COLD invitation switch;
// Triple Six's 1872 and 1873 were dropped because a sales_engineer answer was not "allowed"; a "later" waited 14 days and then got
// touches 2 and 3 as well (review of #2075). Each test below fails on the body that shipped the defect.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SQL = readFileSync(new URL('../sql/every_real_supplier_reply_is_chased_and_a_later_is_asked_again_later.sql', import.meta.url), 'utf8');
const fnOf = (name) => { const i = SQL.indexOf('create or replace function public.' + name + '('); assert.ok(i >= 0, name); return SQL.slice(i, SQL.indexOf('$fn$;', i)); };
// code lines only: a comment that names the forbidden key must not satisfy or fail a check (apply discipline section 7)
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('a follow-up of a supplier who wrote to us does not wait on the invitation switch; the other stops stay', () => {
  const f = code(fnOf('fn_sales_engineer_follows_up_supplier_replies'));
  assert.doesNotMatch(f, /key = 'invite_enabled'/);
  for (const s of ['fn_supplier_outreach_golive()', 'invite_brake b where b.resumed_at is null', "'company_brake'", "key = 'invite_daily_cap'",
    "pg_advisory_xact_lock(hashtext('qd_invite_daily_cap'))", "c.kind = 'public_holiday'", 'between 9 and 16', 'fn_mailbox_followup_allowed(f.inbound_message_id)',
    'fn_supplier_outreach_reachable(l, f.to_email)', 'fn_is_founder_own_inbox(f.to_email)', 'email_suppressions']) assert.ok(f.includes(s), s);
  assert.match(f, /if v_stop is not null or v_today >= v_cap then continue; end if;/);
});

test('a "later" is re-asked once at 30 days and never again; an interested prospect keeps touches 1 to 3', () => {
  const n = code(fnOf('fn_prospect_chase_next_touch'));
  assert.match(n, /coalesce\(p_intent, ''\) in \('subsidiary', 'later'\)/);
  assert.match(n, /p_touch >= 3 then null/);
  const f = code(fnOf('fn_sales_engineer_follows_up_supplier_replies'));
  assert.match(f, /if public\.fn_prospect_chase_next_touch\(f\.intent, f\.touch\) is not null then\s+insert into public\.supplier_reply_followup/);
  assert.doesNotMatch(f, /if f\.intent <> 'subsidiary' and f\.touch < 3 then/);
  for (const name of ['fn_sales_engineer_books_prospect_chase', 'fn_sales_engineer_acts_on_supplier_reply']) {
    const b = code(fnOf(name));
    assert.match(b, /when 'later' then interval '30 days'/, name);
    assert.doesNotMatch(b, /interval '14 days'/, name);
  }
});

test('a seat\'s answer to an evidenced supplier may be followed up; test, spam and opt-out never; a reading still decides alone', () => {
  const a = code(fnOf('fn_mailbox_followup_allowed'));
  assert.match(a, /select d\.may_reply from public\.mailbox_reply_decision d where d\.inbound_message_id = p_inbound_id/);
  assert.match(a, /not in \('test_reply', 'spam', 'opt_out'\)/);
  assert.match(a, /i\.replied_by = 'sales_engineer'\s+and \(coalesce\(i\.ai_category, ''\) = 'supplier_question'\s+or coalesce\(public\.fn_mail_sender_known\(/);
  assert.match(a, /fn_mailbox_reply_hard_rule\(p_inbound_id\) is null/);
  const b = code(fnOf('fn_sales_engineer_books_prospect_chase'));
  assert.match(b, /coalesce\(public\.fn_mail_sender_known\(v_from\), ''\) = 'supplier'/);
  // a fixture run books only fixtures, a real run never a fixture
  assert.match(b, /public\.fn_is_demo_email\(v_from\) <> v_fx/);
  assert.match(b, /if v_fx and not coalesce\(l\.is_demo, false\) then return/);
});

test('every routine is revoked with its exact signature and pins its search_path; the probe is a verdict row', () => {
  for (const sig of ['fn_mailbox_followup_allowed(bigint)', 'fn_prospect_chase_next_touch(text, integer)', 'fn_sales_engineer_books_prospect_chase(bigint)',
    'fn_sales_engineer_acts_on_supplier_reply(bigint)', 'fn_sales_engineer_follows_up_supplier_replies()'])
    assert.ok(SQL.includes('revoke execute on function public.' + sig + ' from public, anon, authenticated'), sig);
  for (const n of ['fn_mailbox_followup_allowed', 'fn_prospect_chase_next_touch', 'fn_sales_engineer_books_prospect_chase', 'fn_sales_engineer_acts_on_supplier_reply', 'fn_sales_engineer_follows_up_supplier_replies'])
    assert.match(fnOf(n), /set search_path to 'public', 'pg_temp'/i, n);
  assert.match(SQL, /^set local lock_timeout = '1500ms';/m);
  const probe = SQL.slice(SQL.indexOf('do $probe$'));
  assert.doesNotMatch(probe, /raise notice/);
  assert.doesNotMatch(probe, /fn_sales_engineer_follows_up_supplier_replies\(\)/, 'the probe never runs the sender');
  assert.doesNotMatch(probe.replace(/@example\.invalid/g, ''), /@[a-z0-9-]+\.[a-z]/i, 'the probe names no real address');
  assert.match(SQL, /select current_setting\('qd\.chase_probe'\) as verdict;\s*$/);
});
