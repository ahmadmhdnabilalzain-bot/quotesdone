// THE CEO DECIDED SOMETHING IN THE LAST 48 HOURS, AND EVERY SEAT KPI BEHIND ITS TARGET HAS AN ORDER (ceo, 19 Nov 2026,
// ledger 1705: "the CEO plans and orders"). Agent: ceo kpi-to-order builder.
//
// The CEO's decisions are public.ceo_decision_log. public.ceo_decision is the RULE REGISTER (17 rules, the last added 2 Nov
// 2026), so a count of it by created_at reads 0 in any week the rules stand still and says nothing about whether the CEO
// decided. Measured 19 Nov 2026: ceo_decision_log 74 rows in 7 days, 16 in 48 h; ceo_seat_month_target held three
// November KPIs 'behind' (invitations_sent 82/750, suppliers_verified 2/768, trades_open 0/77) and none had a directive.
// a_seat_kpi_behind_its_target_becomes_a_ceo_decision_and_an_order.sql closes that; this fails if either returns:
//   1. no ceo_decision_log row in 48 h (the CEO stopped deciding);
//   2. once the duty ceo.kpi_orders is live and has run, a seat_kpi row reads behind with no live order
//      (ceo_directive target_miss seat_kpi:<kpi>:<month>, not met).
//
// READ-ONLY against production: SELECTs under an 8 s statement timeout. Skips with no management token, like its siblings.
//   node --test scripts/checks/the_ceo_decided_something_in_the_last_48_hours.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('ceo_decision_log has a row in the last 48 hours', { skip: SKIP }, async () => {
  const [r] = await rows(`select count(*)::int as n, max(decided_at) as last from public.ceo_decision_log
                           where decided_at > now() - interval '48 hours'`);
  assert.ok(r, 'the read returned nothing');
  assert.ok(r.n > 0, `the CEO logged no decision in 48 h (ceo_decision_log); the last is older than ${r.last ?? 'ever'}`);
});

test('every seat KPI behind its target has a live order once the duty has run', { skip: SKIP }, async () => {
  const [live] = await rows(`select to_regclass('public.seat_kpi') is not null as v,
      exists (select 1 from public.seat_duty where duty = 'ceo.kpi_orders' and enabled and last_ok_at is not null) as ran`);
  if (!live?.v || !live?.ran) return;   // not applied yet: scripts/sql/pending/ holds its note
  const missing = await rows(`
    select k.kpi, k.owner_seat, k.measured, k.target from public.seat_kpi k
     where k.behind and not exists (select 1 from public.ceo_directive d
            where d.seat = k.owner_seat and d.source_kind = 'target_miss' and d.status <> 'met'
              and d.source_ref = 'seat_kpi:' || k.kpi || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'))
       and exists (select 1 from public.org_role r where r.role_id = k.owner_seat and r.status = 'active')
       and (select last_ok_at from public.seat_duty where duty = 'ceo.kpi_orders') > now() - interval '2 hours'`);
  assert.deepEqual(missing, [], `seat KPIs behind with no order: ${JSON.stringify(missing)}`);
});
