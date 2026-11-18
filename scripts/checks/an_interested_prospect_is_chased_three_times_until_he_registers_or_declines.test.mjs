// An interested prospect is chased three times until he registers or declines, and a failed hand-over cannot lose him
// (sales_engineer, 18 Nov 2026). Measured: one follow-up at +7 days ("This is the only reminder"), then nothing; Hindco's hand-over
// failed inside a trigger that swallowed the error and no follow-up row ever existed; a prospect asking for the plans was sent a
// rating survey. Rehearsed on the local Postgres 16 mirror (scripts/db/local_pg16.mjs) in a rolled-back transaction: touch 1 booked
// from the answered mail, sent with his own /portal?t= link and a next step, touches 2 and 3 booked and sent, no 4th; a decline books
// nothing; a paused campaign holds it; the daily cap of 1 sends 1; a prospect's closed case asks no rating, a registered one's does.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SQL = readFileSync(new URL('../sql/an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql', import.meta.url), 'utf8');
const BACKUP = readFileSync(new URL('../sql/a_backup_folder_with_no_file_or_no_party_is_a_finding.sql', import.meta.url), 'utf8');
const fnOf = (name) => { const i = SQL.indexOf('create or replace function public.' + name + '('); assert.ok(i >= 0, name); return SQL.slice(i, SQL.indexOf('$fn$;', i)); };

test('up to three touches, seven days apart, and never "the only reminder" on an interested prospect', () => {
  const f = fnOf('fn_sales_engineer_follows_up_supplier_replies');
  assert.match(f, /if f\.intent <> 'subsidiary' and f\.touch < 3 then\s+insert into public\.supplier_reply_followup[^;]+now\(\) \+ interval '7 days', f\.touch \+ 1\)/);
  assert.match(SQL, /check \(touch between 1 and 3\)/);
  assert.match(SQL, /unique \(inbound_message_id, touch\)/);
  assert.match(f, /when f\.touch >= 3 then 'This is the last reminder/);
  assert.equal((f.match(/only reminder/g) || []).length, 1, 'only the subsidiary note keeps "the only reminder"');
});

test('every touch carries his company\'s own registration link and one next step, and the campaign\'s stops and cap hold it', () => {
  const f = fnOf('fn_sales_engineer_follows_up_supplier_replies');
  assert.match(f, /l\.claim_token is not null and lower\(btrim\(coalesce\(l\.email, ''\)\)\) = lower\(btrim\(f\.to_email\)\)\s+then v_site \|\| '\/portal\?t=' \|\| l\.claim_token else v_site \|\| '\/portal' end/);
  assert.match(f, /Next step: open your company''s own registration link/);
  for (const s of ["key = 'invite_enabled'", 'fn_supplier_outreach_golive()', 'invite_brake b where b.resumed_at is null', "'company_brake'", "key = 'invite_daily_cap'",
    "pg_advisory_xact_lock(hashtext('qd_invite_daily_cap'))", "c.kind = 'public_holiday'", 'fn_supplier_outreach_reachable(l, f.to_email)', 'fn_is_founder_own_inbox(f.to_email)',
    "n.type in ('supplier_invite', 'supplier_invite_nudge')"]) assert.ok(f.includes(s), s);
  // the ONE cap: no second budget of its own (review of #2051) — the day is the UTC day the invitation routines count
  assert.doesNotMatch(f, /at time zone 'Asia\/Dubai'\)::date = \(now\(\) at time zone 'Asia\/Dubai'\)::date\);/);
  assert.ok(f.indexOf("pg_advisory_xact_lock") < f.indexOf('v_today :='), 'the lock is taken before the cap is read');
  assert.match(f, /if v_stop is not null or v_today >= v_cap then continue; end if;/);
  // the stops that existed stay, before any send
  for (const s of ['fn_mailbox_followup_allowed', 'registration_submitted_at is not null', 'email_suppressions', 'n.id > f.inbound_message_id']) assert.ok(f.indexOf(s) < f.indexOf('fn_customer_support_takes_delivery'), s);
  assert.match(f, /invite_followups = coalesce\(invite_followups, 0\) \+ 1, invite_last_followup_at = now\(\)/);
});

test('touch 1 is booked from the answered mail itself, a decline books nothing, and a failure is a finding', () => {
  const b = fnOf('fn_sales_engineer_books_prospect_chase');
  assert.match(b, /if v_intent = 'decline' then return/);
  assert.match(b, /coalesce\(l\.claimed, false\) or l\.registration_submitted_at is not null/);
  assert.match(SQL, /create trigger z54_answered_prospect_gets_its_chase after update of replied_at on public\.inbound_messages\s+for each row when \(new\.replied_at is not null and old\.replied_at is null\)/);
  const t = fnOf('trg_answered_prospect_gets_its_chase');
  assert.match(t, /fn_it_engineer_finding_upsert\('sales_engineer:prospect_chase_not_booked:'/);
  const h = fnOf('trg_invite_reply_reaches_sales_engineer');
  assert.match(h, /fn_it_engineer_finding_upsert\('sales_engineer:invite_reply_not_filed:'/);
  assert.doesNotMatch(h.replace(/exception when others then\s+raise warning[^;]+;\s+end;\s+end;/, ''), /exception when others then\s+raise warning/, 'the warning is only the last resort, after the finding');
});

test('a prospect who has not registered is asked no rating; every new routine is revoked', () => {
  const r = fnOf('fn_support_case_closed_asks_for_the_rating');
  assert.match(r, /not coalesce\(l\.claimed, false\) and l\.registration_submitted_at is null\) then\s+update public\.support_case set csat_requested_at = now\(\), csat_request_error = 'not asked: an invited supplier who has not registered/);
  for (const sig of ['fn_sales_engineer_books_prospect_chase(bigint)', 'trg_answered_prospect_gets_its_chase()', 'trg_invite_reply_reaches_sales_engineer()',
    'fn_sales_engineer_follows_up_supplier_replies()', 'fn_support_case_closed_asks_for_the_rating()', 'fn_sales_engineer_acts_on_supplier_reply(bigint)'])
    assert.ok(SQL.includes('revoke execute on function public.' + sig + ' from public, anon, authenticated'), sig);
  for (const n of ['fn_sales_engineer_books_prospect_chase', 'trg_answered_prospect_gets_its_chase', 'fn_sales_engineer_follows_up_supplier_replies'])
    assert.match(fnOf(n), /set search_path to 'public', 'pg_temp'/i, n);
});

test('review of #2051: send_outbox counts the follow-ups into the one cap; the probe is a verdict row; the one-off obeys the same rules', () => {
  const so = readFileSync(new URL('../../supabase/functions/send_outbox/index.ts', import.meta.url), 'utf8');
  assert.match(so, /from\('supplier_reply_followup'\)\.select\('id', \{ count: 'exact', head: true \}\)\.eq\('state', 'sent'\)\.gte\('done_at'/);
  assert.match(so, /cappedSentToday = a\.error \? Number\.MAX_SAFE_INTEGER : \(a\.count \|\| 0\) \+ await replyFollowupsSince\(since\)/);
  assert.match(so, /laneSentToday = \(count \|\| 0\) \+ await replyFollowupsSince\(since\)/);
  const probe = SQL.slice(SQL.indexOf('-- ── PROBE'));
  assert.doesNotMatch(probe, /raise (exception|notice)/);
  assert.match(probe, /else 'PROBE OK' end as verdict;/);
  assert.match(SQL, /^set local lock_timeout = '1500ms';/m);
  const once = SQL.slice(SQL.indexOf('-- ── 7. ONE-OFF'), SQL.indexOf('-- ── PROBE'));
  assert.ok(once.includes('fn_is_founder_own_inbox(f.to_email)') && once.includes('fn_supplier_outreach_reachable(l, f.to_email)'));
  // the booking reads the company of the exact address that wrote, never a domain match
  assert.match(fnOf('fn_sales_engineer_books_prospect_chase'), /where lower\(btrim\(x\.email\)\) = v_from/);
});

test('the handler and the booking use the same (message, touch) key', () => {
  assert.equal((SQL.match(/on conflict \(inbound_message_id, touch\) do nothing/g) || []).length, 4);
  assert.doesNotMatch(SQL, /on conflict \(inbound_message_id\) do nothing/);
});

test('an empty or ownerless backup folder is raised, never deleted, and closed when a listing finds none', () => {
  assert.match(BACKUP, /fn_it_engineer_finding_upsert\('dropbox:party_folder_empty_or_of_no_party'/);
  assert.match(BACKUP, /fn_it_engineer_finding_close\('dropbox:party_folder_empty_or_of_no_party'/);
  assert.match(BACKUP, /if p_summary \? 'shells' then/);
  assert.doesNotMatch(BACKUP.slice(BACKUP.indexOf('create or replace')), /delete_v2|delete from/i);
});
