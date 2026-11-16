// THE CEO WRITES ITS WEEKLY PLAN WITH A MODEL AND CARRIES IT OUT (ceo, agent L1_CEO, 16 Nov 2026).
// Founder, ledger 1436: "300-400 registrations by end of year without risking the email being blocked"; 1448: "The plan goes to
// the CEO and the CEO acts"; 1696: the CEO has full authority; 1450: the daily one-number report.
// Measured 16 Nov (SELECT): no weekly plan was ever written by the loop. The heartbeat called fn_ceo_plan_due, which builds the
// planning pack inside the API's 8 s statement timeout; resilience_step ceoPlan averaged 7.9 s and every Monday tick was
// cancelled, silently (the loop's error was nested under 'loop').
// This fails when:
//   1. the heartbeat calls anything that builds a pack, or a failed loop stops failing the ceoPlan step;
//   2. the hand-over writes or measures, the duty stops opening plans, a cap is lost, or an unpriced call costs AED 0;
//   3. the plan stops being asked and measured against the registration target, or the CEO's cap ask moves the cap itself
//      or reaches the ramp outside its healthy growth branch;
//   4. the daily number is not switched on with its reason;
//   5. LOCAL (QD_LOCAL_DB_URL, a Postgres 16 copy; never production): the chain asked -> answered (ceo_agent's own runPlan with a
//      stub model) -> orders filed -> measured, end to end; and the file's probe (the ramp still decides) reads PROBE OK.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<local url> node --test scripts/checks/the_ceo_writes_its_weekly_plan_with_a_model_and_carries_it_out.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'the_ceo_writes_its_weekly_plan_with_a_model_and_carries_it_out';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const SQL = read(FILE);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const C = code(SQL);
const fnBody = (name) => {
  const at = C.indexOf(`create or replace function public.${name}(`);
  return at < 0 ? '' : C.slice(at, C.indexOf('$fn$;', at));
};
const LOCAL = process.env.QD_LOCAL_DB_URL || '';

test('1. the heartbeat only hands a plan over, and a failed loop fails the ceoPlan step', async () => {
  const tick = read('supabase/functions/resilience_ping/ticks/ceo.ts');
  const loop = tick.slice(tick.indexOf('export async function ceoPlanningLoopTick'), tick.indexOf('async function planCTick'));
  assert.match(loop, /admin\.rpc\('fn_ceo_plan_handover', \{\}\)/, 'the heartbeat asks the hand-over');
  assert.doesNotMatch(code(loop.replace(/\/\/.*$/gm, '')), /fn_ceo_plan_due|fn_ceo_planning_pack/, 'the heartbeat builds no pack');
  assert.match(tick, /return withLoop\(await planCTick\(\), await ceoPlanningLoopTick\(\)\);/);
  const { withLoop, failureOf } = await import(join(REPO, 'supabase/functions/resilience_ping/steps.ts'));
  assert.equal(failureOf(withLoop({ ok: true }, { ok: false, error: 'canceling statement due to statement timeout' })),
    'planning loop: canceling statement due to statement timeout');
  assert.equal(failureOf(withLoop({ ok: true }, { call_model: false, busy: 'x' })), null);
});

test('2. the hand-over reads only, the duty opens, and the cost is bounded twice', () => {
  const ho = fnBody('fn_ceo_plan_handover');
  assert.ok(ho, 'fn_ceo_plan_handover exists');
  assert.doesNotMatch(ho, /fn_ceo_planning_pack|fn_ceo_plan_measure|fn_ceo_priors_update|insert into|update public/, 'the hand-over builds, measures or writes');
  assert.match(ho, /attempts = 0 or \(attempts < 2 and coalesce\(asked_at, created_at\) < p_at - interval '2 hours'\)/, 'a plan never handed goes at once; a retry after two hours');
  assert.match(fnBody('fn_ceo_planning_loop_tick'), /fn_ceo_plan_due\(now\(\), true\)/, 'the duty opens plans');
  const due = fnBody('fn_ceo_plan_due');
  assert.doesNotMatch(due, /'retry', true|perform public\.fn_ceo_plan_request/, 'fn_ceo_plan_due no longer hands plans over');
  assert.match(due, /fn_ceo_plan_score_registrations\(p_at\)/, 'the daily measure scores the plan against the target');
  assert.match(fnBody('fn_ceo_plan_spend_7d'), /greatest\(coalesce\(l\.cost_aed, 0\),\s*\(coalesce\(l\.prompt_tokens, 0\) \* coalesce\(r\.in_aed_per_mtok, 0\)/, 'an unpriced call counts its tokens x price');
  const req = fnBody('fn_ceo_plan_request');
  assert.match(req, /v_spent >= v_cap or v_calls >= v_calls_cap/, 'the one door refuses at either cap');
  assert.match(SQL, /'\{"week_calls_cap": 14\}'::jsonb/);
});

test('3. the plan is asked and measured against 300-400 registrations; the cap ask is an ask the ramp decides', () => {
  assert.match(SQL, /'ceo_registration_target', '\{"low": 300, "high": 400, "by": "2026-12-31"/);
  const req = fnBody('fn_ceo_plan_request');
  assert.match(req, /'registration_target', v_target, 'last_week_registrations', v_last/);
  assert.match(fnBody('fn_ceo_plan_contract'), /THE TARGET is 300 to 400 registered suppliers by 31 Dec 2026/);
  assert.match(fnBody('fn_ceo_plan_contract'), /raise_invite_cap \{to: the daily invitation cap you want/);
  const act = fnBody('fn_ceo_plan_self_action');
  const raise = act.slice(act.indexOf("elsif v_kind = 'raise_invite_cap' then"), act.indexOf('end if;\n  return jsonb_build_object(\'ok\', false, \'reason\', \'no such CEO action'));
  assert.match(raise, /insert into public\.ceo_own_decision/, 'the ask is recorded');
  assert.doesNotMatch(raise, /update public\.app_secrets|invite_daily_cap'\)?\s*;?\s*$/m, 'the plan never writes the cap itself');
  const ramp = fnBody('fn_invite_ramp');
  const grow = ramp.indexOf('select count(*) into v_last_day_sent');   // the healthy growth branch's first statement
  const applied = ramp.indexOf('v_new := least(v_ceiling, v_ask,');
  assert.ok(grow > 0 && applied > grow, 'the ask is applied only inside the healthy growth branch');
  assert.equal(ramp.split('v_new := least(v_ceiling, v_ask,').length, 2, 'the ask is applied in one place only');
  assert.match(ramp, /greatest\(v_new, ceil\(v_cur \* v_ask_growth\)::int\)/, 'at most doubling a send day');
  assert.match(ramp, /v_new := greatest\(1, least\(v_new, v_ceiling\)\);/, 'never above the ceiling');
});

test('4. the daily number goes on, with the CEO\'s reason', () => {
  assert.match(C, /insert into public\.app_secrets \(key, value\) values \('ceo_daily_number_golive', 'true'\)/);
  assert.match(SQL, /'switch:ceo_daily_number_golive:on:2026-11-16'/);
  assert.match(SQL, /Ledger 1450 asked for one number a day/);
});

test('5. a file not yet applied has its pending notes and no MANIFEST line', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n');
  const listed = manifest.includes(FILE);
  const pending = existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(listed !== pending, 'exactly one of: a MANIFEST line (applied) or a pending note (not yet)');
  assert.ok(existsSync(join(REPO, PROBE)));
});

// ── LOCAL: one psql session, one transaction, rolled back at the end ─────────────────────────────────────────────────────
class Session {
  constructor(url) {
    this.p = spawn('psql', [url, '-qAtX'], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.out = ''; this.err = ''; this.n = 0;
    this.p.stdout.on('data', (d) => { this.out += d; this.poke(); });
    this.p.stderr.on('data', (d) => { this.err += d; this.poke(); });
    this.wait = null;
  }
  poke() { if (this.wait) this.wait(); }
  q(sql) {
    const m = `__QD_END_${++this.n}__`;
    this.p.stdin.write(`${sql};\n\\echo ${m}\n\\warn ${m}\n`);
    return new Promise((resolve) => {
      this.wait = () => {
        if (!this.out.includes(m + '\n') || !this.err.includes(m + '\n')) return;
        const out = this.out.slice(0, this.out.indexOf(m + '\n')); this.out = this.out.slice(this.out.indexOf(m + '\n') + m.length + 1);
        const err = this.err.slice(0, this.err.indexOf(m + '\n')); this.err = this.err.slice(this.err.indexOf(m + '\n') + m.length + 1);
        this.wait = null;
        resolve({ rows: out.split('\n').filter((l) => l !== ''), error: /ERROR:/.test(err) ? err.trim() : null });
      };
      this.wait();
    });
  }
  async one(sql) { const r = await this.q(sql); if (r.error) throw new Error(r.error + '\n' + sql.slice(0, 300)); return r.rows[0]; }
  async json(sql) { return JSON.parse(await this.one(sql)); }
  close() { this.p.stdin.end(); }
}
const lit = (v) => v === null || v === undefined ? 'null' : typeof v === 'number' ? String(v) : typeof v === 'boolean' ? String(v)
  : typeof v === 'object' ? `$qdj$${JSON.stringify(v)}$qdj$::jsonb` : `$qdj$${String(v)}$qdj$`;

test('5a. LOCAL: asked -> answered by ceo_agent\'s own runPlan on a stub model -> orders filed -> measured against the target',
  { skip: LOCAL ? false : 'NOT RUN: no QD_LOCAL_DB_URL (never production)' }, async () => {
  const { runPlan } = await import(join(REPO, 'supabase/functions/ceo_agent/plan.ts'));
  const s = new Session(LOCAL);
  try {
    await s.one(`begin; set local qd.duty_fixtures = 'on'; set local qd.probe_files_demo_handoff = 'on'; select 1`);
    const monday = await s.one(`select ((date_trunc('week', now() at time zone 'Asia/Dubai')::date + 7 + time '08:00') at time zone 'Asia/Dubai')::text`);
    // the duty opens the weekly plan (no model); the heartbeat's door hands it over
    const opened = await s.json(`select public.fn_ceo_plan_due('${monday}'::timestamptz, true)::text`);
    assert.ok(opened.plan_id, 'the duty opened no weekly plan: ' + JSON.stringify(opened));
    const handed = await s.json(`select public.fn_ceo_plan_handover(now())::text`);
    assert.equal(handed.call_model, true, JSON.stringify(handed));
    assert.equal(handed.plan_id, opened.plan_id);
    // the stub model: the seed's two safe bets and one bet on the founder (refused), then a revision that drops it
    const bets = await s.json(`select jsonb_agg(b || jsonb_build_object('due_at', to_char(now() + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SSOF')))::text
      from public.ceo_plan_week w, jsonb_array_elements(w.output->'decision'->'bets') b where w.world = 'real' and w.kind = 'seed' and b->>'channel' in ('reply_within_1h', 'registration_unblock')`);
    assert.equal(bets.length, 2, 'the seed\'s two safe bets');
    await s.one(`insert into public.app_secrets (key, value) values ('invite_daily_cap', '3') on conflict (key) do update set value = excluded.value returning 1`);
    const calls = [];
    const deps = {
      rpc: async (fn, args) => {
        await s.q('savepoint qd_rpc');
        const r = await s.q(`select public.${fn}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')})::text`);
        await s.q(r.error ? 'rollback to savepoint qd_rpc' : 'release savepoint qd_rpc');
        return r.error ? { data: null, error: { message: r.error } } : { data: JSON.parse(r.rows[0]), error: null };
      },
      model: async (system, user, taskClass) => {
        const u = JSON.parse(user);
        calls.push({ taskClass, target: u.input.registration_target, revision: 'refused_by_code' in u.input, pack: !!u.input.pack, system });
        const answer = calls.length === 1
          ? { situation: 'stub: behind pace', decision: { bets: [...bets, { ...bets[0], seat: 'founder' }],
              ceo_actions: [{ kind: 'raise_invite_cap', to: 20, reason: 'stub: the bounce judgement is healthy and the pool is large' }] } }
          : { decision: { bets: [], dropped: [{ option: 'the founder bet', why: 'ledger 1710' }] } };
        return { content: JSON.stringify(answer), model: 'zz-demo/stub', truncated: false };
      },
    };
    const r = await runPlan(deps, opened.plan_id);
    assert.equal(r.ok, true, JSON.stringify(r));
    assert.equal(calls.length, 2, 'one answer and one revision');
    assert.equal(calls[0].taskClass, 'ceo_strategic_planning');
    assert.ok(calls[0].pack && calls[0].target && calls[0].target.target_low === 300 && calls[0].target.needed_per_week != null, 'the model reads the pack and the target');
    assert.match(calls[0].system, /THE TARGET is 300 to 400/);
    assert.equal(calls[1].revision, true);
    const filed = await s.json(`select jsonb_build_object('status', w.status, 'target', w.registration_target is not null,
        'orders', (select count(*) from public.ceo_plan_bet b join public.agent_actions a on a.id = b.handoff_id where b.plan_id = w.id and b.status = 'filed' and a.status = 'pending' and a.detail->>'path' = 'plan'),
        'refused', (select count(*) from public.ceo_plan_bet b where b.plan_id = w.id and b.status = 'refused'),
        'ask', public.fn_ceo_invite_cap_ask(), 'cap', (select value from public.app_secrets where key = 'invite_daily_cap'))::text
      from public.ceo_plan_week w where w.id = ${opened.plan_id}`);
    assert.deepEqual(filed, { status: 'filed', target: true, orders: 2, refused: 1, ask: 20, cap: '3' });
    // a week later: measured against the target from the daily number's own count
    await s.one(`insert into public.ceo_supplier_funnel_daily (day, channel, submitted) values (('${monday}'::timestamptz at time zone 'Asia/Dubai')::date + 2, 'zz_demo_e2e', 3) returning 1`);
    await s.one(`select public.fn_ceo_plan_due('${monday}'::timestamptz + interval '7 days', true)::text`);
    const res = await s.json(`select registration_result::text from public.ceo_plan_week where id = ${opened.plan_id}`);
    assert.equal(res.registered, 3, JSON.stringify(res));
    assert.equal(res.on_pace, 3 >= res.needed_per_week);
    assert.match(res.verdict, /^3 registered in the week of/);
  } finally {
    await s.q('rollback');
    s.close();
  }
});

test('5b. LOCAL: the file\'s probe reads PROBE OK (the ramp keeps the last word, the caps hold)',
  { skip: LOCAL ? false : 'NOT RUN: no QD_LOCAL_DB_URL (never production)' }, () => {
  const r = spawnSync('psql', [LOCAL, '-qAtX', '-f', join(REPO, PROBE)], { encoding: 'utf8' });
  const out = String(r.stdout || '') + String(r.stderr || '');
  assert.match(out, /CHK<<PROBE OK/, out.slice(0, 1500));
});
