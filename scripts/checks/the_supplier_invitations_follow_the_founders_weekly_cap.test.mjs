// FOUNDER RULING 1231 (13 Oct 2026): 20 invitations a day until 18 Oct, 30 from 19 Oct, 40 from 26 Oct,
// 50 from 2 Nov and never more. Before it, fn_invite_ramp grew the cap x1.5 per healthy day up to a
// configured 200, so the ruling held only while someone remembered a config value.
//
// This check reads production and fails if the schedule's numbers change, if the ramp stops taking its
// base and ceiling from the schedule, or if the sender stops clamping invite_daily_cap to it.
// Applied by scripts/sql/the_supplier_invitations_follow_the_founders_weekly_cap_of_20_30_40_then_50.sql.
//
//   node --test scripts/checks/the_supplier_invitations_follow_the_founders_weekly_cap.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
const q = (query) => sql(query, { ref: 'htdblwldjkcgjvmqkbeh', readOnly: true });

test('the daily invitation cap is the founder schedule, enforced by the ramp and the sender', async (t) => {
  if (!mgmtToken) { t.skip('no management token, so the live routines cannot be read'); return; }

  const [caps] = await q(`select public.fn_invite_founder_cap('2026-10-14') a, public.fn_invite_founder_cap('2026-10-18') b,
    public.fn_invite_founder_cap('2026-10-19') c, public.fn_invite_founder_cap('2026-10-26') d,
    public.fn_invite_founder_cap('2026-11-02') e, public.fn_invite_founder_cap('2030-01-01') f`);
  assert.deepEqual([caps.a, caps.b, caps.c, caps.d, caps.e, caps.f].map(Number), [20, 20, 30, 40, 50, 50],
    'fn_invite_founder_cap no longer returns ruling 1231 (20 / 30 from 19 Oct / 40 from 26 Oct / 50 from 2 Nov, ceiling 50)');

  const defs = await q(`select p.proname, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_invite_ramp', 'enqueue_supplier_invites')`);
  const def = (name) => String(defs.find((r) => r.proname === name)?.def || '');
  assert.match(def('fn_invite_ramp'), /v_base int\s+:= public\.fn_invite_founder_cap\(/,
    'fn_invite_ramp takes its base from config again, not from the founder schedule');
  assert.match(def('fn_invite_ramp'), /v_ceiling int\s+:= public\.fn_invite_founder_cap\(/,
    'fn_invite_ramp takes its ceiling from config again, so it can grow past the founder schedule');
  assert.match(def('enqueue_supplier_invites'), /v_cap := least\(v_cap, public\.fn_invite_founder_cap\(/,
    'enqueue_supplier_invites no longer clamps invite_daily_cap to the founder schedule');
});
