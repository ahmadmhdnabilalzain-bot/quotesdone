// A SEAT IS ALIVE WHEN IT ACTS, NOT WHEN IT LOGS A RUN (22 Sep 2026, it_engineer).
//
// WHY THIS EXISTS. On 22 Sep customer_support showed 4 agent_runs in 24 hours (last 21 Sep 15:32Z) and the
// ceo 2, and read as seats that had stopped. They had decided 826 and 74 handoffs in the same 24 hours:
// agent_runs holds only the org_task closures fn_org_task_consume_tick writes for them. public.fn_seat_liveness
// (scripts/sql/a_seat_is_alive_when_it_acts_not_when_it_logs_a_run.sql) reads the handoffs a seat decided and
// the handoffs waiting on it past their window. This fails if liveness is read from agent_runs alone again,
// if a seat is missing, or if a seat with overdue work and no act stops reading 'stopped'.
//
//   node --test scripts/checks/a_seat_is_alive_when_it_acts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = readFileSync(join(REPO, 'scripts/sql/a_seat_is_alive_when_it_acts_not_when_it_logs_a_run.sql'), 'utf8');
const BODY = SRC.slice(SRC.indexOf('as $function$'), SRC.indexOf('$function$;'));

test('liveness is read from the handoffs a seat decides and the handoff_sla rule, not from agent_runs alone', () => {
  assert.match(BODY, /h\.kind = 'handoff' and h\.decided_by = s\.seat/, 'acts must come from agent_actions.decided_by');
  assert.match(BODY, /public\.fn_it_handoff_sla_items\(p_include_demo\)/, 'overdue work must be the handoff_sla duty\'s own reading');
  assert.match(BODY, /when x\.acts_24h \+ x\.runs_24h > 0 then 'acting'/);
  assert.match(BODY, /from public\.org_agents o where o\.active/, 'every active seat must have a row');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
let SKIP = hasToken ? false : 'no Supabase management token';
let sql;
if (!SKIP) {
  ({ sql } = await import('../lib/db.mjs'));
  const [r] = await sql(`select to_regprocedure('public.fn_seat_liveness(boolean)') is not null ok`);
  if (!r.ok) SKIP = 'NOT_APPLIED: a_seat_is_alive_when_it_acts_not_when_it_logs_a_run.sql is not on production yet';
}

test('production: every active seat has a verdict; a ZZ DEMO seat with overdue work and no act is stopped, then behind', { skip: SKIP }, async () => {
  let out;
  try {
    await replaySql(`do $p$
      declare v1 text; v2 text; v3 text; n_seats int; n_rows int; v_act bigint;
        -- Since #1578 (every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql,
        -- founder ledger 1013) a handoff row states context, decision, open asks and deadline, or the a01 trigger and
        -- the CHECK refuse it; zz_demo.kind is no registered type the trigger can build a note from, so the probe's
        -- hand-made rows carry their own note (deadline past for the overdue one).
        v_note jsonb := jsonb_build_object('context', 'ZZ DEMO probe: work waiting on the demo seat',
          'decision', 'the probe handed it to zz_demo_seat', 'open_asks', jsonb_build_array('ZZ DEMO act on it'),
          'deadline', now() - interval '1 day', 'known', '{}'::jsonb, 'tried', '{}'::jsonb, 'needed', '{}'::jsonb, 'evidence', '[]'::jsonb);
      begin
        select count(*) into n_seats from public.org_agents where active;
        select count(*) into n_rows from public.fn_seat_liveness();
        insert into public.org_agents (agent_key, kind, active) values ('zz_demo_seat', 'brain', true);
        select verdict into v1 from public.fn_seat_liveness(true) where seat = 'zz_demo_seat';
        insert into public.agent_actions (agent, kind, status, title, detail, target_id, created_at)
        values ('zz_demo_seat', 'handoff', 'pending', 'ZZ DEMO probe', jsonb_build_object('type', 'zz_demo.kind', 'summary', v_note), 'zz_demo:1', now() - interval '2 days');
        select verdict into v2 from public.fn_seat_liveness(true) where seat = 'zz_demo_seat';
        -- The seat ACTS: it closes a handoff the way every seat does, through fn_seat_handoff_complete, which cites the
        -- handover note. Since 27 Oct (a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql,
        -- ledger 1013) trigger a02 refuses a handoff that reaches 'done' citing nothing, so the old insert-as-done
        -- fixture was refused with 23514; the guard is right, and the probe now acts through the real door.
        insert into public.agent_actions (agent, kind, status, title, detail, target_id, created_at)
        values ('zz_demo_seat', 'handoff', 'pending', 'ZZ DEMO probe', jsonb_build_object('type', 'zz_demo.kind', 'summary', v_note), 'zz_demo:2', now())
        returning id into v_act;
        perform set_config('qd.handoff_closer', 'zz_demo_seat', true);
        if not coalesce((public.fn_seat_handoff_complete(v_act, '{}'::jsonb)->>'ok')::boolean, false) then
          raise exception 'ZZ DEMO probe: fn_seat_handoff_complete did not close handoff %', v_act;
        end if;
        select verdict into v3 from public.fn_seat_liveness(true) where seat = 'zz_demo_seat';
        raise exception 'CHK<<%>>', json_build_object('seats', n_seats, 'rows', n_rows, 'idle', v1, 'stopped', v2, 'behind', v3);
      end $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.equal(out.rows, out.seats, 'a seat has no liveness row');
  assert.deepEqual([out.idle, out.stopped, out.behind], ['idle', 'stopped', 'behind']);
});
