// FOUNDER RULING 1231 (13 Oct 2026; dates corrected 19 Oct): 20 a day until 25 Oct, 30 from 26 Oct, 40 from 2 Nov,
// 50 from 9 Nov and never more. Before it, fn_invite_ramp grew the cap x1.5 per healthy day up to a
// configured 200, so the ruling held only while someone remembered a config value.
//
// This check reads production and fails if the schedule's numbers change, if the ramp stops taking its
// base and ceiling from the schedule, or if the sender stops clamping invite_daily_cap to it.
// Applied by scripts/sql/the_founders_weekly_invite_cap_starts_its_week_of_20_on_19_october.sql.
//
//   node --test scripts/checks/the_supplier_invitations_follow_the_founders_weekly_cap.test.mjs
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
const q = (query) => sql(query, { ref: 'htdblwldjkcgjvmqkbeh', readOnly: true });

test('the daily invitation cap is the founder schedule, enforced by the ramp and the sender', async (t) => {
  if (!mgmtToken) { t.skip('no management token, so the live routines cannot be read'); return; }

  const [caps] = await q(`select public.fn_invite_founder_cap('2026-10-19') a, public.fn_invite_founder_cap('2026-10-25') b,
    public.fn_invite_founder_cap('2026-10-26') c, public.fn_invite_founder_cap('2026-11-02') d,
    public.fn_invite_founder_cap('2026-11-09') e, public.fn_invite_founder_cap('2030-01-01') f`);
  assert.deepEqual([caps.a, caps.b, caps.c, caps.d, caps.e, caps.f].map(Number), [20, 20, 30, 40, 50, 50],
    'fn_invite_founder_cap no longer returns ruling 1231 (20 until 25 Oct / 30 from 26 Oct / 40 from 2 Nov / 50 from 9 Nov, ceiling 50)');

  const defs = await q(`select p.proname, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_invite_ramp', 'enqueue_supplier_invites')`);
  const def = (name) => String(defs.find((r) => r.proname === name)?.def || '');
  const ramp = def('fn_invite_ramp');
  assert.match(ramp, /v_ceiling int\s+:= least\([^;]*public\.fn_invite_founder_cap\(/,
    'fn_invite_ramp\'s ceiling is no longer bounded by the founder schedule, so it can grow past the ruling');
  assert.match(ramp, /v_base int\s+:= least\([^;]*public\.fn_invite_founder_cap\(/,
    'fn_invite_ramp\'s restart base is no longer bounded by the founder schedule');
  // THE SCHEDULE ONLY LOWERS (review of #1389): flooring the cap at a schedule-derived base would RAISE a cap set
  // lower (10 -> 20 -> 30) and turn the bounce back-off into a no-op. Measured by rolled-back probe on 13 Oct 2026:
  // cap 10 stays 10, 10% bounces halve 20 -> 10, a hand-set 500 comes back 20.
  assert.doesNotMatch(ramp, /greatest\(\s*v_base\s*,/,
    'fn_invite_ramp floors a cap at v_base again: that raises a lower cap and stops the bounce back-off from reducing');
  assert.match(ramp, /v_base := least\(v_base, v_cur\);/,
    'a cold restart may raise the cap again; the restart base must be bounded by the cap already set');
  assert.match(def('enqueue_supplier_invites'), /v_cap := least\(v_cap, public\.fn_invite_founder_cap\(/,
    'enqueue_supplier_invites no longer clamps invite_daily_cap to the founder schedule');
});
