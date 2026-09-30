// THE INVITATIONS GO OUT EVERY DAY, AND A STARTED REGISTRATION IS FOLLOWED (21 Sep 2026, sales_engineer).
//
// The audit of 21 Sep found enqueue_supplier_invites with no caller (last plan 7 Sep, pg_cron gone),
// no follow-up for a supplier who starts registering and stops, and no clock on a submitted
// registration. This fails if any of the three causes comes back in the source:
//   * the heartbeat stops naming the daily step, or the step stops calling the routine;
//   * the routine stops calling enqueue_supplier_invites, or writes a reminder while the gates are shut;
//   * a reminder can reach a fixture, a screened, bounced or suppressed address;
//   * the 24-hour clock escalates to the founder instead of the CEO;
//   * claim_lookup stops recording the click.
// The behaviour itself is proved against production by the verdict probe at the end of the SQL file,
// and every_tick_step_is_scheduled.mjs proves the resilience_step row is applied.
//   node --test scripts/checks/the_invitations_go_out_every_day_and_a_started_registration_is_followed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ping = readFileSync('supabase/functions/resilience_ping/index.ts', 'utf8');
const claim = readFileSync('supabase/functions/claim_lookup/index.ts', 'utf8');
const sql = readFileSync('scripts/sql/the_invitations_go_out_every_day_and_a_started_registration_is_followed.sql', 'utf8');
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/);

// A routine's body, read from its create statement to the closing $fn$, so a comment elsewhere in the
// file cannot satisfy an assertion about the code.
function body(name) {
  const open = sql.indexOf(`create or replace function public.${name}(`);
  assert.ok(open >= 0, `${name} is no longer defined in the outreach file`);
  const start = sql.indexOf('$fn$', open);
  const end = sql.indexOf('$fn$;', start + 4);
  return sql.slice(start, end);
}

test('the heartbeat names the daily outreach step and it calls the routine', () => {
  const open = ping.indexOf("const STEP_RUN: Record<string, Omit<Step, 'name'>> = {");
  const close = ping.indexOf('\n};', open);
  assert.match(ping.slice(open, close), /^\s{2}supplierOutreach:\s*\{\s*run:\s*supplierOutreachTick\s*\}/m,
    'STEP_RUN no longer runs supplierOutreachTick: the daily invitation batch has no caller again');
  assert.match(ping, /admin\.rpc\('fn_sales_engineer_supplier_outreach_tick'\)/, 'supplierOutreachTick no longer calls the routine');
  assert.match(sql, /\('supplierOutreach', interval '30 min'/, 'the resilience_step row for supplierOutreach is not seeded');
});

test('the daily routine runs once per Dubai day and calls the existing composer', () => {
  const tick = body('fn_sales_engineer_supplier_outreach_tick');
  assert.match(tick, /public\.enqueue_supplier_invites\(null\)/, 'the tick no longer calls enqueue_supplier_invites');
  assert.match(tick, /at time zone 'Asia\/Dubai'\)::date = v_now_dxb::date/, 'the once-per-Dubai-day gate is gone');
  assert.match(tick, /'held', v_why is not null[\s\S]*insert into public\.agent_runs[^;]*v_out/, 'a held day is no longer recorded');
});

test('reminders are held while the campaign gates are shut', () => {
  const tick = body('fn_sales_engineer_supplier_outreach_tick');
  const hold = tick.indexOf('if v_why is not null then continue; end if;');
  const send = tick.indexOf('fn_sales_engineer_sends_registration_reminder(');
  assert.ok(hold > 0 && send > hold, 'the tick can write a reminder before checking the gates');
  const sender = body('fn_sales_engineer_sends_registration_reminder');
  assert.match(sender, /key = 'invite_enabled'/, 'the sender no longer reads invite_enabled');
  assert.match(sender, /fn_supplier_outreach_golive\(\)/, 'the sender no longer reads supplier_outreach_golive');
  assert.match(sender, /if not v_fixture and not v_go then/, 'the sender no longer refuses a real address while held');
  assert.match(sender, /fn_customer_support_takes_delivery\(/, 'the reminder no longer goes through the normal outbox');
});

test('a reminder never reaches a fixture, sanctioned, screened, bounced or suppressed address', () => {
  const reach = body('fn_supplier_outreach_reachable');
  for (const wall of ['is_demo', 'zz\\s*demo', 'fn_is_demo_email(p_to)', 'banned', 'sanctions_ban', 'supplier_screening_hit',
                      "invite_status, '') <> 'bounced'", 'fn_email_sendable(p_to)']) {
    assert.ok(reach.includes(wall), `fn_supplier_outreach_reachable lost the "${wall}" wall`);
  }
  assert.match(body('fn_supplier_registration_reminders_due'), /public\.fn_supplier_outreach_reachable\(d\.lead, d\.to_email\)/,
    'the due list no longer filters through fn_supplier_outreach_reachable');
});

// SUPPLIERS ALWAYS GET ENGLISH (founder, 28 Sep 2026; E2E stage 1 D3, 30 Sep). This asserted the reminder's
// Arabic register, read from this file's 21 Sep body. It now reads the LIVE composer from the schema mirror and
// asserts it is English with the link, and that its language switch is a constant false.
test('the reminder is written in English, with the link, and never chooses Arabic', () => {
  const mirror = readSchemaMirror();
  const at = mirror.indexOf('FUNCTION public.fn_supplier_registration_reminder_compose(');
  assert.ok(at > 0, 'the reminder composer is not in the schema mirror');
  const c = mirror.slice(at, mirror.indexOf('$function$', mirror.indexOf('$function$', at) + 10));
  for (const phrase of ['Dear ', 'v_link']) assert.ok(c.includes(phrase), `the reminder lost "${phrase}"`);
  assert.match(c, /v_ar boolean := false;/, 'the reminder decides a language again; a supplier is always written in English');
  assert.doesNotMatch(c, /v_ar\s*:=\s*(?!false)/, 'the reminder sets v_ar from something other than false');
});

test('the 24-hour clock raises to the CEO seat, never to the founder', () => {
  const clock = body('fn_sales_engineer_raises_undecided_submissions');
  assert.match(clock, /interval '24 hours'/);
  assert.match(clock, /fn_sales_engineer_verifies_supplier\(r\.id, 'submission_24h_clock'\)/, 'the sales engineer no longer acts before raising');
  assert.match(clock, /fn_support_report_to_ceo\([\s\S]*p_source_agent => 'sales_engineer'\)/, 'the undecided submission is no longer reported to the CEO');
  assert.doesNotMatch(clock, /fn_notify_founder|founder_alerts/, 'the 24-hour clock must not page the founder');
  assert.match(body('fn_sales_engineer_supplier_outreach_tick'), /fn_sales_engineer_raises_undecided_submissions\(false\)/,
    'the daily run escalates fixtures, or no longer runs the clock');
});

test('claim_lookup records the first click on an unclaimed invitation', () => {
  assert.match(claim, /update\(\{ invite_clicked_at: new Date\(\)\.toISOString\(\) \}\)\s*\.eq\('id', l\.id\)\.is\('invite_clicked_at', null\)/,
    'claim_lookup no longer records the invitation click, so a clicker is never followed up');
});

test('the file ends in a verdict row and is in the index', () => {
  assert.match(sql.trimEnd(), /select verdict from zz_outreach_probe;$/, 'the probe no longer reports a verdict row');
  assert.ok(manifest.includes('scripts/sql/the_invitations_go_out_every_day_and_a_started_registration_is_followed.sql'),
    'the outreach file has no MANIFEST line');
});
