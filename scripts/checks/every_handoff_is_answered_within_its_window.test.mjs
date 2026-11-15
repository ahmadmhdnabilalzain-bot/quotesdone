// EVERY HANDOFF IS ANSWERED WITHIN ITS WINDOW, OR THE IT ENGINEER SAYS SO (ceo, 22 Sep 2026).
//
// scripts/sql/every_handoff_is_answered_within_its_window.sql. Measured 22 Sep 2026: 29 it.finding
// handoffs sat pending 1 to 8 days -- answered by their seat, finding cleared, parked by
// fn_it_loop_reverify at awaiting_learning with no clock and no addressee. And two founder-bound
// delivery requests held for the 19:00 Dubai IT digest were raised as undelivered after 2 hours.
//
// This fails when the same causes come back:
//   * a cleared it.finding handoff parked past its reply window is NOT reported by the handoff_sla duty
//     (rolled-back ZZ DEMO fixture against production), or one whose finding is still open IS;
//   * the delivery duty stops honouring the digest hold, or the hold's arithmetic drifts from 19:00 Dubai;
//   * fn_it_duties stops settling the handoff_sla duty;
//   * fn_it_loop_reverify stops completing the CEO report of a handoff closed by another door.
//
// The live half runs against production inside a transaction that ends in `raise exception
// 'CHK<<...>>'`, so nothing commits and no fixture can reach anyone.
//
//   node --test scripts/checks/every_handoff_is_answered_within_its_window.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/every_handoff_is_answered_within_its_window.sql';
const src = readFileSync(join(REPO, FILE), 'utf8');
const body = (name) => {
  const a = src.indexOf(`create or replace function public.${name}(`);
  assert.ok(a >= 0, `${name} is not defined in ${FILE}`);
  return src.slice(a, src.indexOf('$fn$;', a));
};

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('the delivery duty waits out the IT digest hold, and fn_it_duties settles the handoff_sla duty', () => {
  const d = body('fn_it_duties');
  assert.match(d, /a\.evidence->>'digest' = 'pending'\s+and now\(\) < public\.fn_it_digest_hold_ends\(a\.created_at\)/,
    'the delivery duty raises a founder-bound request the 19:00 digest is still allowed to hold (22 Sep: 48729, 50861)');
  assert.match(d, /fn_it_duty_settle\('handoff_sla', public\.fn_it_handoff_sla_items\(\)\)/,
    'nothing reports a handoff parked past its window: the 29 of 22 Sep waited up to 8 days unseen');
});

test('a handoff closed by another door still completes its CEO report', () => {
  const r = body('fn_it_loop_reverify');
  assert.match(r, /r\.idempotency_key ~ '\^it_loop:\[0-9\]\+\$'[\s\S]*?a\.status = 'done'/,
    'fn_it_attach_learning closes a handoff but its it_loop report stays accepted for good');
});

test('the digest hold ends at the first 19:00 Dubai a day after the request, plus the duty\'s 2 hours', { skip: SKIP }, async () => {
  const [r] = await sql(`select
      public.fn_it_digest_hold_ends(timestamptz '2026-09-22 02:30:53+00')::text same_day,
      public.fn_it_digest_hold_ends(timestamptz '2026-09-22 16:00:00+00')::text after_the_hour`);
  assert.equal(r.same_day, '2026-09-23 17:00:00+00');
  assert.equal(r.after_the_hour, '2026-09-24 17:00:00+00');
});

// Runs a block that must end in `raise exception 'CHK<<json>>'` and returns the parsed json.
async function probe(block) {
  try {
    await replaySql(`select set_config('qd.probe_files_demo_handoff', 'on', true); do $p$ ${block} $p$;`, { label: 'the handoff window probe' });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (m) return JSON.parse(m[1].replace(/\\"/g, '"'));
    throw e;
  }
  throw new Error('probe committed instead of rolling back: it must end in raise exception CHK<<...>>');
}

test('a cleared it.finding parked past its window is reported; one whose finding is still open is not', { skip: SKIP }, async () => {
  const r = await probe(`
    declare k_parked text := 'duty:zz_demo_handoff_sla_probe:parked'; k_open text := 'duty:zz_demo_handoff_sla_probe:open';
            h_parked bigint; h_open bigint; v jsonb;
    begin
      set local statement_timeout = '60s';
      perform public.fn_it_engineer_finding_upsert(k_parked, 'ZZ DEMO handoff_sla probe (parked)', 'probe', 'agent_facing', 1,
        '{"demo": true, "owner_seat": "ceo"}'::jsonb, '{}'::text[], '{}'::text[], 'zz_demo_probe');
      perform public.fn_it_engineer_finding_upsert(k_open, 'ZZ DEMO handoff_sla probe (open)', 'probe', 'agent_facing', 1,
        '{"demo": true, "owner_seat": "ceo"}'::jsonb, '{}'::text[], '{}'::text[], 'zz_demo_probe');
      perform public.fn_it_loop_open(k_parked);
      perform public.fn_it_loop_open(k_open);
      select id into h_parked from public.agent_actions where kind = 'handoff' and detail->>'issue_key' = k_parked;
      select id into h_open   from public.agent_actions where kind = 'handoff' and detail->>'issue_key' = k_open;
      -- The finding cleared five hours ago and nobody closed the handoff: the 22 Sep shape.
      update public.agent_actions set created_at = now() - interval '6 hours' where id in (h_parked, h_open);
      perform public.fn_it_engineer_finding_close(k_parked, 'ZZ DEMO probe');
      update public.it_engineer_finding set closed_at = now() - interval '5 hours' where issue_key = k_parked;
      v := public.fn_it_handoff_sla_items(true);
      raise exception 'CHK<<%>>', json_build_object(
        'h_parked', h_parked, 'h_open', h_open,
        'replied', (select detail ? 'replied_at' from public.agent_actions where id = h_parked),
        'parked_reported', exists (select 1 from jsonb_array_elements(v) i
                                    where i->'evidence'->>'state' = 'unclosed' and i->'evidence'->'handoff_ids' @> to_jsonb(h_parked)),
        'open_reported', exists (select 1 from jsonb_array_elements(v) i where i->'evidence'->'handoff_ids' @> to_jsonb(h_open)),
        'demo_hidden_from_the_duty', not exists (select 1 from jsonb_array_elements(public.fn_it_handoff_sla_items()) i
                                                 where i->'evidence'->'handoff_ids' @> to_jsonb(h_parked)),
        'playbook', (public.fn_it_playbook_for('duty:handoff_sla:it.finding:ceo:unclosed')).failure_class);
    end`);
  assert.ok(r.h_parked && r.h_open, 'the fixture handoffs were not opened');
  assert.equal(r.replied, true, 'the seat did not answer the fixture, so it would read as unanswered, not unclosed');
  assert.equal(r.parked_reported, true, 'a cleared handoff parked past its window went unreported: the 22 Sep backlog can build again');
  assert.equal(r.open_reported, false, 'a handoff whose finding is still open was reported late: the finding itself is the tracked wait');
  assert.equal(r.demo_hidden_from_the_duty, true, 'a ZZ DEMO handoff reached the real duty');
  assert.equal(r.playbook, 'handoff_sla', 'a cleared handoff_sla finding would park at the very gate it reports on');
});
