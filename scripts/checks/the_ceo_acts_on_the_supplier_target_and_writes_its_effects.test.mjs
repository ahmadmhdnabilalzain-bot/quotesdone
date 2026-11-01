// THE CEO ACTS ON THE SUPPLIER TARGET AND WRITES WHAT IT DID.       seat: ceo · 2 Nov 2026 · ledger 1436, 1438, 1448
//
// The audit of 2 Nov found no fn_ceo_* routine that wrote a cap, a lead or a channel switch. This fails if that returns:
//   A. static: the routine stops writing its levers, its log or its effect; loses the ledger 1231 clamp; or can open ads;
//   B. pure replay: brakes win, the schedule wins, WhatsApp needs every measured condition;
//   C. the file + probe in one rolled-back transaction: the routine acts and writes its effect, or the switch off moves nothing;
//   D. live, once applied: the duty ran within 48 hours, and no applied action sits past its review with no effect.
//
//   node --test scripts/checks/the_ceo_acts_on_the_supplier_target_and_writes_its_effects.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';
import { sql } from '../lib/db.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql';
const PROBE = FILE.replace('.sql', '_probe.sql');
const src = readFileSync(path.join(REPO, FILE), 'utf8');
const code = src.replace(/--[^\n]*/g, '');
const body = (name) => {
  const m = src.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$;'));
  assert.ok(m, `${name} is not in the file`);
  return m[0];
};
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();
const isPending = () => pendingNotes().has(FILE);

test('A. the routine writes every lever, its log and its effect, inside the bounds', () => {
  const act = body('fn_ceo_growth_act');
  for (const k of ['invite_daily_cap', 'invite_reachable_only', 'wa_supplier_invite_golive', 'invite_enabled'])
    assert.match(act, new RegExp(`update public\\.app_secrets set value = [^;]*where key = '${k}'`), `the CEO no longer writes ${k}`);
  assert.match(act, /insert into public\.ceo_invite_trade_priority/, 'the CEO no longer reorders trades');
  assert.match(act, /public\.fn_ceo_directive_issue\(/, 'the CEO no longer directs a seat');
  assert.match(act, /insert into public\.ceo_growth_action/, 'the CEO no longer logs what it did');
  assert.match(act, /fn_ceo_growth_review\(/, 'the CEO no longer reviews what it did');
  assert.match(act, /least\(\(d->>'to'\)::int, v_founder\)/, 'a cap is written without the ledger 1231 clamp');
  assert.match(act, /fn_invite_campaign_pause\(/, 'a close must go through the one pause routine');
  assert.match(body('fn_ceo_growth_review'), /update public\.ceo_growth_action set effect = v_effect, verdict = v_verdict/, 'the review writes no effect');
  assert.match(act, /'ceo_growth_act_golive'/, 'the act has no switch');
  assert.doesNotMatch(code, /meta_autospend_golive'[^;]*set value|set value[^;]*meta_autospend_golive/i, 'this file can start ad spend');
  assert.match(code, /\('ceo_growth_act_golive', 'false'\), \('ceo_daily_number_golive', 'false'\)/, 'a switch is not seeded off');
  assert.match(body('fn_ceo_daily_number_report'), /fn_notify_founder\([^;]*'info', 'ceo_daily_number'/, 'the report leaves founder_mail_policy or can reach WhatsApp');
  const queue = code.slice(code.indexOf('fn_supplier_invite_candidates(p_limit integer, p_providers'));
  assert.match(queue, /not v_reach or l\.email_verified in/, 'the queue does not read the reachability lever');
  assert.match(queue, /ceo_invite_trade_priority/, 'the queue does not read the trade priority');
});

const reading = (o = {}) => JSON.stringify({ day: '2026-11-09', sent_7d: 100, bounced_7d: 1, bounce_rate_7d: 0.01, complained_48h: 0, complained_7d: 0,
  max_bounce: 0.03, invite_enabled: true, cur_cap: 30, founder_cap: 50, open_classes: 1, reachable_only: false, unchecked_sent: 0, unchecked_bounced: 0,
  checked_pool_open: 700, brake_pause_days_ago: null, resume_failed_recently: false, wa_golive: false, wa_opt_ins: 0, wa_template_approved: false,
  wa_reading_ok: false, wa_brake: false, started_stuck: 0, replied_unanswered: 0, trade_live: 5, trade_candidates: [], ...o }).replace(/'/g, "''");

test('B. the decision: brakes and the schedule win; WhatsApp needs every condition', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const fn = body('fn_ceo_growth_decide').replace('public.fn_ceo_growth_decide', 'pg_temp.fn_ceo_growth_decide').replace(/revoke[^\n]*/g, '');
  const cases = {
    healthy: {}, atCeiling: { cur_cap: 50 }, overCeiling: { cur_cap: 90 },
    brake: { bounced_7d: 10, bounce_rate_7d: 0.1 }, complaint: { complained_48h: 1, complained_7d: 1 },
    noRate: { sent_7d: 3, bounced_7d: 0, bounce_rate_7d: null },
    unchecked: { unchecked_sent: 18, unchecked_bounced: 5 },
    wild: { sent_7d: 52, bounced_7d: 7, bounce_rate_7d: 0.135 },
    pausedSoon: { invite_enabled: false, brake_pause_days_ago: 2, reachable_only: true },
    pausedOk: { invite_enabled: false, brake_pause_days_ago: 8, reachable_only: true, sent_7d: 0, bounce_rate_7d: null },
    pausedByNobody: { invite_enabled: false, brake_pause_days_ago: null, reachable_only: true },
    pausedUnchecked: { invite_enabled: false, brake_pause_days_ago: 8, reachable_only: false },
    pausedRetried: { invite_enabled: false, brake_pause_days_ago: 8, reachable_only: true, resume_failed_recently: true },
    waMissingOne: { wa_opt_ins: 3, wa_template_approved: true, wa_reading_ok: false },
    waAll: { wa_opt_ins: 3, wa_template_approved: true, wa_reading_ok: true },
    waBrake: { wa_golive: true, wa_opt_ins: 3, wa_template_approved: true, wa_reading_ok: true, wa_brake: true },
  };
  const q = fn + '\nselect ' + Object.entries(cases).map(([k, v]) => `pg_temp.fn_ceo_growth_decide('${reading(v)}'::jsonb) as "${k}"`).join(', ') + ';';
  const [d] = await replaySql(q, { rows: true, label: 'fn_ceo_growth_decide in pg_temp' });
  const pick = (a, power, subject) => a.find((x) => x.power === power && (!subject || x.subject === subject));
  assert.equal(pick(d.healthy, 'cap').to, 40, 'a clean week raises one step');
  assert.equal(pick(d.atCeiling, 'cap'), undefined, 'the cap rose past the schedule');
  assert.equal(pick(d.overCeiling, 'cap').to, 50, 'a cap above the schedule did not come down');
  assert.equal(pick(d.brake, 'cap').to, 15, 'a bounce brake did not halve');
  assert.equal(pick(d.complaint, 'cap').to, 15, 'a complaint did not halve');
  assert.equal(pick(d.noRate, 'cap'), undefined, 'under 15 sends is not a rate and must not raise');
  assert.equal(pick(d.unchecked, 'reachable').to, true, 'measured unchecked bounces did not stop unchecked mail');
  assert.equal(pick(d.wild, 'channel', 'email_supplier_mailbox').to, 'close', 'over twice the limit did not close the mailbox');
  for (const k of ['pausedSoon', 'pausedByNobody', 'pausedUnchecked', 'pausedRetried'])
    assert.equal(pick(d[k], 'channel', 'email_supplier_mailbox'), undefined, `${k}: a resume outside its bounds`);
  assert.equal(pick(d.pausedOk, 'channel', 'email_supplier_mailbox').to, 'open');
  assert.equal(pick(d.pausedOk, 'cap').to, 10, 'a resume must restart low');
  assert.equal(pick(d.waMissingOne, 'channel', 'whatsapp_opt_in'), undefined, 'WhatsApp opened without a reading');
  assert.equal(pick(d.healthy, 'channel', 'whatsapp_opt_in'), undefined, 'WhatsApp opened without an opt-in');
  assert.equal(pick(d.waAll, 'channel', 'whatsapp_opt_in').to, 'open');
  assert.equal(pick(d.waBrake, 'channel', 'whatsapp_opt_in').to, 'close', 'a WhatsApp brake did not close the channel');
});

test('C. the routine acts and writes its effect (rolled back)', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const probe = readFileSync(path.join(REPO, PROBE), 'utf8');
  const text = (isPending() ? src + '\n' : '') + probe;
  await assert.rejects(replaySql(text, { label: 'the CEO growth probe' }), /CHK<<PROBE OK/, 'the probe did not end PROBE OK');
});

test('D. live: the duty ran, and nothing applied waits without an effect', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  if (isPending()) { t.skip('pending: not applied yet'); return; }
  const [r] = await sql(`select
      (select max(created_at) > now() - interval '48 hours' from public.ceo_growth_action where power = 'run') as ran,
      (select count(*) from public.ceo_growth_action where applied and verdict = 'pending' and review_on < current_date - 2) as overdue`,
  { ref: 'htdblwldjkcgjvmqkbeh', readOnly: true });
  assert.equal(r.ran, true, 'the CEO action routine has written no run row in 48 hours');
  assert.equal(Number(r.overdue), 0, 'an applied CEO action is past its review with no measured effect');
});
