// EVERY SCHEDULED JOB NAMES A LIVE SEAT.
//
// Founder, 7 Sep 2026: no job or task without an agent. On 22 Sep 2026 the scheduler ran 34
// resilience_step rows and 12 it_duty_schedule rows and NEITHER table had an owner column
// (SEATS-11), so the only way to answer "whose job is this" was to read each note by hand.
// scripts/sql/every_scheduled_step_and_duty_names_the_seat_that_owns_it.sql adds owner_seat to
// both, NOT NULL and FK to org_agents(agent_key). This check is what stops the next row being
// added with an owner that is not a live seat — the FK allows a seat that exists but has been
// deactivated, and a deactivated seat owning a live job is the same silence one step later.
//
// It also asserts that every ACTIVE seat says what it is responsible for: an owner nobody can
// look up is a name, not an owner.
//
// Runs against production only; without a management token there is nothing to read, and the
// check says so rather than passing quietly.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: every resilience_step and it_duty_schedule row names a live seat', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`
    select 'resilience_step' as t, s.step as k, s.owner_seat,
           (a.agent_key is not null and a.active) as live
      from public.resilience_step s left join public.org_agents a on a.agent_key = s.owner_seat
    union all
    select 'it_duty_schedule', d.duty, d.owner_seat, (a.agent_key is not null and a.active)
      from public.it_duty_schedule d left join public.org_agents a on a.agent_key = d.owner_seat`);
  assert.ok(rows.length > 0, 'neither schedule table returned a row');
  const bad = rows.filter((r) => !r.live).map((r) => `${r.t}.${r.k}: owner_seat=${r.owner_seat ?? '(none)'}`);
  assert.deepEqual(bad, [], 'a scheduled job names a seat that is not a live org_agents row');
});

test('production: every active seat says what it is responsible for', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select agent_key, coalesce(btrim(responsibilities),'') as resp, coalesce(btrim(role),'') as role
                            from public.org_agents where active order by agent_key`);
  const bad = rows.filter((r) => !r.resp || !r.role).map((r) => `${r.agent_key}: ${!r.role ? 'no role' : ''}${!r.resp ? ' no responsibilities' : ''}`);
  assert.deepEqual(bad, [], 'an active seat carries no role or no responsibilities');
});
