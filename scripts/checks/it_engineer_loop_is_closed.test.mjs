// THE IT ENGINEER NEVER SENDS ANYTHING ONE WAY.
//
// Founder, 14 Sep 2026: "always make sure things are in loop. nothing literally should ever be a one
// way communication". The loop is scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql; the held
// classifier is scripts/sql/a_run_the_founders_hold_refused_is_held_not_failed.sql. This fails when:
//   1. a conversation the it_engineer starts has no reply window, or may be closed by the seat it asked;
//   2. trigger z61 is missing, or a receiving seat can in fact close an it_engineer handoff;
//   3. an it.finding handoff is past its reply window and was neither answered-and-closed nor escalated;
//   4. the alert tick writes to the notifications outbox itself instead of going round the loop;
//   5. a run the founder's hold refused raises a failure finding, or a real failure stops raising one;
//   6. fn_it_detect no longer fits PostgREST's 8 s statement timeout (it ran 10 s on 14 Sep 2026 and
//      persisted nothing for 80 minutes), or a detector that stops persisting goes unreported;
//   7. requests made inside a rehearsal window count as customers turned away.
//
// Against production. Every write is inside a transaction that ends in `raise exception 'CHK<<…>>'`,
// so nothing commits; the result is read out of the error text.
//
//   node --test scripts/checks/it_engineer_loop_is_closed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// Runs a block that must end in `raise exception 'CHK<<json>>'` and returns the parsed json.
async function probe(body) {
  try {
    await sql(`do $p$ ${body} $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (m) return JSON.parse(m[1].replace(/\\"/g, '"'));
    throw e;
  }
  throw new Error('probe committed instead of rolling back: it must end in raise exception CHK<<...>>');
}

// Closed by the originator means one of two shapes: the receiver may not close it at all (z61), or the
// receiver completes its step and a delivery.result conversation carries the outcome back to the
// it_engineer, which checks it (fn_originator_checks_delivery).
test('every conversation the it_engineer starts has a reply window and comes back to it', { skip: SKIP }, async () => {
  const types = await sql(`select k.type, k.to_seat, k.reply_within::text reply_within, k.originator_closes,
                                  exists (select 1 from public.seat_handoff_kind r
                                           where r.type = 'delivery.result' and r.from_seat = k.to_seat
                                             and r.to_seat = 'it_engineer') result_comes_back
                             from public.seat_handoff_kind k
                            where k.from_seat = 'it_engineer' order by 1, 2`);
  assert.ok(types.length > 0, 'fn_seat_handoff_types lists no it_engineer conversation at all');
  const bad = types.filter((t) => !t.reply_within || !(t.originator_closes === true
    || (t.type === 'delivery.request' && t.result_comes_back === true)));
  assert.deepEqual(bad, [], 'it_engineer conversations without a reply window, or that the receiver can close with nothing coming back');
});

test('a receiving seat cannot close an it_engineer handoff; the it_engineer can', { skip: SKIP }, async () => {
  const [trg] = await sql(`select count(*)::int n from pg_trigger
                            where tgrelid = 'public.agent_actions'::regclass and tgname = 'z61_handoff_only_originator_closes'
                              and tgenabled <> 'D'`);
  assert.equal(trg.n, 1, 'trigger z61_handoff_only_originator_closes is missing or disabled');
  const r = await probe(`
    declare t record; v_id bigint; n int := 0; refused int := 0; closed int := 0;
    begin
      for t in select k.type, k.to_seat from public.seat_handoff_kind k
                where k.from_seat = 'it_engineer' and k.originator_closes loop
        n := n + 1;
        insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
        values (t.to_seat, 'handoff', 'pending', 'low', 'ZZ DEMO close probe',
                jsonb_build_object('type', t.type, 'from', 'it_engineer', 'to', t.to_seat), 'probe', 'zz_probe:' || n)
        returning id into v_id;
        begin
          perform set_config('qd.handoff_closer', t.to_seat, true);
          perform set_config('qd.backup_closer', t.to_seat, true);
          update public.agent_actions set status = 'done' where id = v_id;
        exception when others then refused := refused + 1; end;
        -- qd.backup_closer too: the backup build's own trigger (z60) reads that name for its two types.
        perform set_config('qd.handoff_closer', 'it_engineer', true);
        perform set_config('qd.backup_closer', 'it_engineer', true);
        update public.agent_actions set status = 'done' where id = v_id and status <> 'done';
        if found then closed := closed + 1; end if;
      end loop;
      raise exception 'CHK<<%>>', json_build_object('conversations', n, 'refused', refused, 'originator_closed', closed);
    end`);
  assert.ok(r.conversations > 0);
  assert.equal(r.refused, r.conversations, 'a receiving seat closed an it_engineer handoff');
  assert.equal(r.originator_closed, r.conversations, 'the it_engineer could not close its own handoff');
});

test('no it.finding handoff sits past its reply window unanswered and unescalated', { skip: SKIP }, async () => {
  // Thirty minutes of slack: the tick that escalates runs every fifteen.
  const late = await sql(`select a.id, a.agent, a.created_at
                            from public.agent_actions a
                            join public.seat_handoff_kind w on w.type = 'it.finding' and w.from_seat = 'it_engineer' and w.to_seat = a.agent
                           where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
                             and not (a.detail ? 'escalated_report_id')
                             and a.created_at + w.reply_within < now() - interval '30 minutes'`);
  assert.deepEqual(late, [], 'it.finding handoffs past their window that nobody escalated');
});

test('the alert tick never writes to the outbox itself', { skip: SKIP }, async () => {
  const [f] = await sql(`select prosrc from pg_proc where oid = 'public.fn_it_engineer_alert_tick()'::regprocedure`);
  assert.doesNotMatch(f.prosrc, /insert\s+into\s+public\.notifications/i);
  assert.match(f.prosrc, /fn_it_loop_tick\(\)/);
});

test('a run the founder\'s hold refused is held; a real failure still raises a finding', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v jsonb; v_hold boolean;
    begin
      v_hold := exists (select 1 from public.llm_route_health
                         where opened_reason like 'HELD BY THE FOUNDER%' and open_until > now());
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      select a, 'error', now() - interval '1 minute', now() - interval '1 minute', c, 'ZZ DEMO hold probe'
        from (values ('inquiry_intake', '{"llm_call_ok":0}'::jsonb), ('inquiry_intake', '{"llm_call_ok":0}'::jsonb),
                     ('inquiry_intake', '{"llm_call_ok":0}'::jsonb),
                     ('zz_demo_probe_subject', '{"http":500}'::jsonb), ('zz_demo_probe_subject', '{"http":500}'::jsonb),
                     ('zz_demo_probe_subject', '{"http":500}'::jsonb)) x(a, c);
      v := public.fn_it_detect(null, false);
      raise exception 'CHK<<%>>', json_build_object(
        'hold', v_hold,
        'real', (select count(*) from jsonb_array_elements(v->'findings') f where f->>'detector_key' = 'run_failure:zz_demo_probe_subject'),
        'intake', (select f from jsonb_array_elements(v->'findings') f where f->>'detector_key' = 'run_failure:inquiry_intake'));
    end`);
  assert.equal(r.real, 1, 'three HTTP 500s on a subject with no hold signature must raise run_failure');
  if (r.hold && r.intake) {
    assert.ok(Number(r.intake.evidence.window_held) >= 3,
      `inquiry_intake fired while the hold is on and did not count the held runs: ${r.intake.title}`);
  }
});

test('the detector fits the 8 s statement timeout, and a detector that stops persisting is itself a finding', { skip: SKIP }, async () => {
  const r = await probe(`
    declare t0 timestamptz; v_ms numeric;
    begin
      set local statement_timeout = '8s';
      t0 := clock_timestamp();
      perform public.fn_it_detect(null, false);
      v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
      set local statement_timeout = 0;
      update public.it_watch_tick set ran_at = ran_at - interval '2 hours' where ran_at > now() - interval '2 hours';
      perform public.fn_it_engineer_alert_tick();
      raise exception 'CHK<<%>>', json_build_object('detect_ms', round(v_ms),
        'blind_finding', (select closed_at is null from public.it_engineer_finding where issue_key = 'monitor:detect_tick_blind'));
    end`);
  assert.ok(r.detect_ms < 6000, `fn_it_detect took ${r.detect_ms} ms; PostgREST cancels it at 8000`);
  assert.equal(r.blind_finding, true, 'a detector with no persisted tick for two hours raised no monitor finding');
});

test('refusals inside a rehearsal window are the harness, not customers turned away', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v jsonb;
    begin
      insert into public.rehearsal_window (run_tag, opened_by, note) values ('qd_run:zz_probe', 'probe', 'ZZ DEMO');
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      select 'fn:login_otp', 'warn', now() - interval '1 minute', now() - interval '1 minute', '{"http":404}'::jsonb, 'ZZ DEMO'
        from generate_series(1, 60);
      v := public.fn_it_detect(null, false);
      raise exception 'CHK<<%>>', json_build_object('login_refusal_finding',
        (select count(*) from jsonb_array_elements(v->'findings') f where f->>'detector_key' = 'refusal_rate:login_otp'));
    end`);
  assert.equal(r.login_refusal_finding, 0);
});
