// THE FOUNDER'S DAILY SUPPLIER LIST IS THE SENDER'S OWN SELECTION (customer_support, 24 Sep 2026).
//
// The 18:00 Dubai email lists exactly who the campaign invites on the next sending day. That is only true while the
// list and the sender call the SAME selection with the SAME size. This fails if either side drifts:
//   1. the list calls fn_supplier_invite_candidates with least(invite_daily_cap, eligible pool), as the sender does;
//   2. the sender (canonical enqueue_supplier_invites) still selects through fn_supplier_invite_candidates;
//   3. the list skips the days the sender holds (weekend, company_calendar public holiday);
//   4. no model is called on the path (the tick and the attach are SQL; resilience_ping only renders the PDF);
//   5. emails in the PDF are masked.
// The behaviour is run on production, in an aborted transaction with a ZZ DEMO lead, by
// scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six_probe.sql.
//
//   node --test scripts/checks/the_daily_supplier_list_is_the_senders_selection.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');
const LIST = code(read('scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six.sql'));
const SENDER = code(read('scripts/sql/the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql'));
const body = (sql, name) => {
  const i = sql.indexOf('create or replace function public.' + name + '(');
  assert.ok(i >= 0, name + ' is defined');
  return sql.slice(i, sql.indexOf('$fn$;', i));
};

test('the list and the sender size the batch the same way and select through the same routine', () => {
  const list = body(LIST, 'fn_supplier_campaign_next_list');
  const send = body(SENDER, 'enqueue_supplier_invites');
  assert.match(list, /key = 'invite_daily_cap'\), 10\)/);
  assert.match(send, /key='invite_daily_cap'\), 10\)/);
  assert.match(list, /from public\.leads l where public\.fn_supplier_invite_eligible\(l\)/);
  assert.match(send, /from leads l where public\.fn_supplier_invite_eligible\(l\)/);
  assert.match(list, /v_n := greatest\(least\(v_cap, v_pool\), 0\)/);
  assert.match(list, /public\.fn_supplier_invite_candidates\(v_n\)/);
  assert.match(send, /public\.fn_supplier_invite_candidates\(v_remaining\)/);
});

test('the list skips exactly the days the sender holds', () => {
  const hold = body(LIST, 'fn_supplier_invites_hold_reason');
  assert.match(hold, /c\.kind = 'public_holiday'/);
  assert.match(hold, /extract\(isodow from p_day\) in \(6, 7\)/);
  const send = body(SENDER, 'enqueue_supplier_invites');
  assert.match(send, /c\.kind = 'public_holiday'/);
  assert.match(send, /extract\(isodow from \(now\(\) at time zone 'Asia\/Dubai'\)\) in \(6, 7\)/);
});

test('switched off, the email says so and still shows the list; emails are masked; one mailbox, one policy', () => {
  const tick = body(LIST, 'fn_customer_support_campaign_list_tick');
  assert.match(tick, /SWITCHED OFF/);
  assert.match(tick, /WOULD be sent/);
  assert.match(body(LIST, 'fn_supplier_campaign_next_list'), /public\.fn_mask_email\(c\.to_email\)/);
  const attach = body(LIST, 'fn_customer_support_campaign_list_attach');
  assert.match(attach, /where kind = 'supplier_campaign_daily_list'\), false\)/);
  assert.match(attach, /key = 'admin_emails'\), ',', 1\)/);
});

test('no model on the path: the heartbeat only renders and attaches', () => {
  const rp = read('supabase/functions/resilience_ping/index.ts');
  const i = rp.indexOf('async function supportCampaignListTick(');
  const fn = rp.slice(i, rp.indexOf('\n}\n', i));
  assert.match(fn, /admin\.rpc\('fn_customer_support_campaign_list_tick'\)/);
  assert.match(fn, /renderPdfAndAttach\(t, 'customer_support\/supplier_list', 'supplier_list', false, 'fn_customer_support_campaign_list_attach'\)/);
  assert.doesNotMatch(fn, /llm|gateway|openrouter|chat\/completions/i);
  assert.match(rp, /supportCampaignList: \{ run: supportCampaignListTick \}/);
});
