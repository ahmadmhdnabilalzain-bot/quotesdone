// AN UNVERIFIED LEAD CANNOT BE QUEUED, AND A BRAKE READS REAL SENDS (2 Nov 2026, sales_engineer, ledger 1449).
// Reads the definition that wins the apply order, comments removed, so a comment cannot satisfy it. Known-bad controls: the
// clause taken out of the same text must fail. Behaviour against production: the probe, replayed and rolled back, last test.
//   node --test scripts/checks/an_unverified_lead_cannot_be_queued.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { replaySql } from '../lib/safe_replay.mjs';

const SQL = 'scripts/sql/';
const NAME = 'an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself';
const FIX = NAME + '.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = existsSync(SQL + 'pending/' + NAME + '.txt');

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const defRe = (head) => new RegExp('create\\s+or\\s+replace\\s+function\\s+public\\.' + esc(head), 'i');

/** The body of the routine as the last file to define it leaves it, comments removed. */
function body(head) {
  const order = pending ? [...manifest, FIX] : manifest;
  const file = [...order].reverse().find((f) => existsSync(SQL + f) && defRe(head).test(readFileSync(SQL + f, 'utf8')));
  assert.ok(file, 'no file defines ' + head);
  const src = readFileSync(SQL + file, 'utf8').replace(/\r\n/g, '\n');
  const at = src.search(defRe(head));
  const open = src.slice(at).match(/\bas\s+(\$[a-z_]*\$)/i);
  const from = at + open.index + open[0].length;
  return src.slice(from, src.indexOf(open[1], from)).replace(/--[^\n]*/g, '');
}

const VERDICT = /verdict\s*=\s*'verified'[\s\S]{0,40}email_md5\s*=\s*md5\(lower\(btrim\(p\.email\)\)\)/;
export const gateHolds = (b) => VERDICT.test(b);
const READS_QUEUE_TIME = /invited_at\s*>/;

test('both eligibility definitions require the verdict for this address', () => {
  for (const f of ['fn_supplier_invite_eligible(p leads)', 'fn_supplier_invite_eligible_ids()']) {
    const b = body(f);
    assert.ok(gateHolds(b), f + ' does not require a verified verdict');
    assert.ok(!gateHolds(b.replace(VERDICT, "verdict = 'rejected'")), 'control: the check passed with the clause removed');
  }
});

test('the outbox guard and the sender both go through the gate', () => {
  assert.match(body('fn_notifications_supplier_invite_is_whole('), /fn_supplier_invite_eligible\(l\)/);
  assert.match(body('fn_supplier_invite_candidates(p_limit integer, p_providers text[])'), /fn_supplier_invite_eligible_ids\(\)/);
});

test('no routine inserts a real supplier_invite past the guard', () => {
  const trig = readFileSync('supabase/schema/full_schema/11_triggers_rls_policies_cron_secret_names.sql', 'utf8');
  assert.match(trig, /a07_notifications_supplier_invite_is_whole BEFORE INSERT ON public\.notifications/, 'the guard trigger is gone');
});

test('every brake reads real sends, not the queue time', () => {
  for (const f of ['enqueue_supplier_invites(', 'fn_invite_same_day_brake(', 'fn_sales_engineer_nudges_invited_suppliers(']) {
    const b = body(f);
    assert.match(b, /fn_invite_send_health\(/, f + ' does not read fn_invite_send_health');
    assert.ok(!/brake_since|resumed_at/.test(b), f + ' lets a restart reset the bounce window');
    assert.ok(!/from\s+(public\.)?leads\s+where\s+invited_at\s*>/.test(b), f + ' still counts by queue time');
  }
  assert.match(body('fn_invite_ramp('), /fn_invite_send_health\(now\(\) - interval '48 hours'\)/);
  const health = body('fn_invite_send_health(');
  assert.match(health, /n\.sent_at is not null/);
  assert.ok(!READS_QUEUE_TIME.test(health));
  assert.ok(READS_QUEUE_TIME.test("from leads where invited_at > now()"), 'control: the shape the check refuses');
});

test('invite_schedule.sent is not written at queue time, and the view counts the outbox', () => {
  assert.ok(!/sent\s*=\s*sent\s*\+/.test(body('enqueue_supplier_invites(')), 'the sender counts a queued row as sent');
  const fix = readFileSync(SQL + FIX, 'utf8');
  const view = fix.slice(fix.indexOf('create or replace view public.v_invite_deliverability_daily'));
  assert.match(view.slice(0, 700), /n\.sent_at is not null/);
});

test('the restart never lifts the founder\'s go, a complaint or another seat\'s pause, and touches no cap', () => {
  const b = body('fn_sales_engineer_restarts_invites_after_a_brake(');
  assert.match(b, /fn_supplier_outreach_golive\(\)/);
  assert.match(b, /v_complaints > 0/);
  assert.match(b, /b\.fired_at \+ interval '3 days'/, 'no cooldown');
  assert.match(b, /restarted_by_seat and x\.resumed_at > b\.fired_at - interval '30 days'/, 'no limit on restarts');
  assert.match(b, /fn_ceo_task_open\(/, 'a second breach does not reach the CEO seat');
  assert.ok(b.indexOf('fn_ceo_task_open(') < b.indexOf("set value = 'true'"), 'the second breach is decided after the resume');
  assert.match(body('enqueue_supplier_invites('), /fn_invite_restart_cap\(/, 'no small first batch');
  assert.match(b, /paused_by/);
  assert.match(b, /insert into public\.email_suppressions/);
  assert.ok(b.indexOf('email_suppressions') < b.indexOf("set value = 'true'"), 'it resumes before suppressing');
  const writes = [...b.matchAll(/update\s+public\.app_secrets\s+set\s+value\s*=[^;]*;/gi)].map((m) => m[0]);
  assert.ok(writes.length > 0 && writes.every((w) => /key = 'invite_enabled'/.test(w)), 'it writes another switch');
  assert.match(b, /fn_invite_send_health\(v_since\)/, 'the second breach does not read the sends since the restart');
  const cap = body('fn_invite_restart_cap(');
  const clockOnly = (s) => !/first_sent/.test(s);
  assert.ok(!clockOnly(cap), 'the first-batch limit runs on a clock, so a restart on a closed day lapses before anything is sent');
  assert.ok(clockOnly("resumed_at > now() - interval '24 hours'"), 'control: the clock shape is refused');
});

test('a proven mailbox goes first, free mail last', () => {
  const b = body('fn_supplier_invite_candidates(p_limit integer, p_providers text[])');
  assert.match(b, /when c\.email_verified in \('verified','true'\) then 0 when c\.mailbox = 'free' then 3 when c\.mailbox = 'role' then 1 else 2/);
  assert.match(b, /order by r\.target_rank, r\.plan_rank, r\.mailbox_rank,/);
});

// A JS replace whose replacement held a regex ending in $' pasted the file's tail inside 7 copies (review of #1744).
export const spliced = (src) => {
  const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.([a-z0-9_]+)\(([^)]*)\)/gi)].map((m) => m[1] + '(' + m[2] + ')');
  return heads.length !== new Set(heads).size || !src.includes("donotreply)$'");
};
test('the file was not spliced: each routine once, its regex literals whole', () => {
  const src = readFileSync(SQL + FIX, 'utf8');
  assert.ok(!spliced(src), 'a routine is defined twice or a regex literal was cut');
  const bad = 'x'.replace('x', () => src).replace('create table', () => src + 'create table');
  assert.ok(spliced(bad), 'control: a pasted tail passes');
});

test('the file is pending XOR in MANIFEST, and its probe is never applied', () => {
  assert.ok(pending !== manifest.includes(FIX), 'exactly one of a pending note and a MANIFEST line');
  assert.ok(existsSync(SQL + 'pending/' + NAME + '_probe.txt'), 'the probe has no pending note');
  assert.ok(!manifest.includes(NAME + '_probe.sql'), 'the probe is in MANIFEST');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, aborted: the gate, the counts and the restart', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const block = (pending ? readFileSync(SQL + FIX, 'utf8') + '\n' : '') + readFileSync(SQL + NAME + '_probe.sql', 'utf8');
  let msg = '';
  try { await replaySql(block, { retry: false }); msg = 'the probe committed instead of rolling back'; } catch (e) { msg = String(e.message); }
  const m = msg.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(out.verdict, 'PROBE OK', JSON.stringify(out).slice(0, 3000));
});
