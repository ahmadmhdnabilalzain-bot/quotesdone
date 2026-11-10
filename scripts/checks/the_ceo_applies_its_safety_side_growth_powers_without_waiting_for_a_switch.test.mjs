// THE CEO APPLIES ITS SAFETY-SIDE GROWTH POWERS WITHOUT WAITING FOR A SWITCH.   seat: ceo · 10 Nov 2026 · ledger 1438, 1455, 1609
//
// Measured 10 Nov 2026: 81 growth decisions since 2 Nov, 0 applied, because ceo_growth_act_golive was off. The decisions it
// held back were brakes: halve the cap on 4 bounces of 35, send only to checked addresses, close the mailbox. A switch that
// can only stop a brake is a safety limit pointing the wrong way. This fails if that returns:
//   A. static: a lever is written under the switch alone again; the ceiling stops being behind the switch; the review can no
//      longer roll back a raise; the brake floor drops back under the 15-send rate window;
//   B. pure, with a token: the classifier answers each decision kind as the file says, and the brake halves to 5, never 1;
//   C. with a token: the file and its probe in one rolled-back transaction answer PROBE OK.
//
//   node --test scripts/checks/the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql';
const PROBE = FILE.replace('.sql', '_probe.sql');
const src = readFileSync(path.join(REPO, FILE), 'utf8');
const body = (name) => {
  const m = src.match(new RegExp('create or replace function public\\.' + name + '\\([\\s\\S]*?\\$fn\\$;', 'i'));
  assert.ok(m, `${name} is not in the file`);
  return m[0].replace(/--[^\n]*/g, '');
};
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8') : '')).trim();
const isPending = () => pendingNotes().has(FILE);

test('A. every lever is written under the per-decision test, and the ceiling stays behind the switch', () => {
  const act = body('fn_ceo_growth_act');
  assert.match(act, /v_safe := public\.fn_ceo_growth_power_is_safe\(d, v_read, v_restore\);\s*v_ok := v_apply or v_safe;/,
    'a decision is no longer applied on "switch on OR safety-side"');
  for (const k of ['invite_daily_cap', 'invite_reachable_only', 'wa_supplier_invite_golive'])
    assert.match(act, new RegExp(`if v_ok then update public\\.app_secrets set value = [^;]*where key = '${k}'`), `${k} is written under the switch alone again`);
  assert.match(act, /if v_ok then insert into public\.ceo_invite_trade_priority/, 'the trade order waits for the switch again');
  assert.match(act, /if v_ok and d->>'to' = 'open' then[\s\S]*?elsif v_ok then\s*perform public\.fn_invite_campaign_pause\(/, 'the mailbox close waits for the switch again');
  assert.match(act, /if v_ok and not exists \(select 1 from public\.ceo_directive/, 'a directive waits for the switch again');
  assert.match(act, /when 'ceiling' then[\s\S]*?if v_apply then\s*update public\.app_secrets set value = v_after where key = 'invite_ceo_ceiling'/,
    'ledger 1455: the ceiling step must stay behind ceo_growth_act_golive');
  assert.match(act, /least\(\(d->>'to'\)::int, v_founder\)/, 'a cap is written without the founder schedule clamp');
  assert.match(act, /fn_ceo_growth_review\(p_at, v_read, true\)/, 'a review can no longer roll back a raise with the switch off');
  assert.match(act, /safety-side with the switch off/, 'the run row no longer says what was applied on the safety side');
  const safe = body('fn_ceo_growth_power_is_safe');
  assert.match(safe, /else false\s+end/, 'an unknown power is treated as safe');
  assert.doesNotMatch(safe, /when 'ceiling' then true/, 'the ceiling became safety-side');
  const dec = body('fn_ceo_growth_decide');
  assert.match(dec, /elsif v_brake and v_cur > 5 then[\s\S]*?greatest\(5, v_cur \/ 2\)/, 'the brake can halve below 5 again: the 7-day rate window goes blind');
  assert.match(src, /revoke execute on function public\.fn_ceo_growth_power_is_safe\(jsonb, jsonb, integer\) from public, anon, authenticated;/,
    'the new routine is CREATEd without its revoke');
});

test('B. the classifier and the brake floor, replayed', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const fn = (name) => body(name).replace('public.' + name, 'pg_temp.' + name);
  const q = fn('fn_ceo_growth_power_is_safe') + '\n' + fn('fn_ceo_growth_decide') + `
    select pg_temp.fn_ceo_growth_power_is_safe('{"power":"cap","to":10}', '{"cur_cap":20}', null) cut,
           pg_temp.fn_ceo_growth_power_is_safe('{"power":"cap","to":30}', '{"cur_cap":20}', null) raise,
           pg_temp.fn_ceo_growth_power_is_safe('{"power":"cap","to":20}', '{"cur_cap":10}', 20) giveback,
           pg_temp.fn_ceo_growth_power_is_safe('{"power":"reachable","to":false}', '{}', null) unchecked_again,
           pg_temp.fn_ceo_growth_power_is_safe('{"power":"channel","subject":"whatsapp_opt_in","to":"open"}', '{}', null) wa_open,
           pg_temp.fn_ceo_growth_power_is_safe('{"power":"ceiling","to":60}', '{}', null) ceiling,
           (select e->>'to' from jsonb_array_elements(pg_temp.fn_ceo_growth_decide('{"max_bounce":0.05,"bounce_rate_7d":0.2,"sent_7d":40,"bounced_7d":8,"cur_cap":8,"founder_cap":50,"invite_enabled":true,"reachable_only":true,"trade_live":5,"wa_golive":false,"wa_opt_ins":1}')) e where e->>'power' = 'cap') floor8;`;
  const [r] = await replaySql(q, { rows: true, label: 'the safety-side classifier in pg_temp' });
  assert.equal(r.cut, true); assert.equal(r.raise, false); assert.equal(r.giveback, true);
  assert.equal(r.unchecked_again, false, 'sending to unchecked addresses again became safety-side');
  assert.equal(r.wa_open, false, 'opening WhatsApp became safety-side');
  assert.equal(r.ceiling, false, 'the ceiling became safety-side');
  assert.equal(r.floor8, '5', 'the brake halved below 5');
});

test('C. the file and its probe, rolled back', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const probe = readFileSync(path.join(REPO, PROBE), 'utf8');
  const text = (isPending() ? src + '\n' : '') + probe;
  await assert.rejects(replaySql(text, { label: 'the CEO safety-side growth probe' }), /PROBE OK CHK<</, 'the probe did not end PROBE OK');
});
