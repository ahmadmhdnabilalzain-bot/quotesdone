// THE CEO RUNS THE COMPANY ON THE FOUNDER'S YEAR-ONE TARGETS (24 Sep 2026).
//
// WHAT FAILS IF THE CAUSE RETURNS.
//   * static: a number in the plan table is not the founder's rule (recomputed here from the rules), a milestone moves
//     (200 by Nov, 300 by Dec, 500 by Aug), the year's cost ceilings reach AED 250,000, a routine is unpinned or
//     unrevoked, a table has no policy, the file carries both a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the pending files replayed first, the founder path stubbed, fixtures
//     ZZ DEMO / example.invalid): the replaced targets are still active; a November day with nothing measured opens
//     no task; a cost over its ceiling is not a miss; the month closes no directive, sends no report, or issues a
//     seat no directive; a second run issues twice; a stuck handoff is not re-run; the founder's note goes out on a
//     day when nothing matters or twice on a day when something does; a recurring miss makes no improvement; five
//     missed targets do not get exactly one improvement each; a second sweep proposes anything (it must settle in one run).
//
//   node --test scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const MINE = 'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql';
const FILES = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql',
  'scripts/sql/the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql',
  'scripts/sql/the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql', MINE,
  'scripts/sql/the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run.sql',
  // the sweep's 30 s budget on its own job (27 Oct 2026): with the 2 s one it never settles in one run on production
  'scripts/sql/the_ceo_improvement_sweep_settles_in_one_run_on_its_own_job.sql',
  // ledger 1609 (10 Nov 2026): fn_ceo_daily_run keeps its note on the day and no longer mails it to the founder
  'scripts/sql/the_ceo_note_is_not_mailed_to_the_founder_the_brief_is_his_one_daily_message.sql'];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (p) => read(p).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

// The founder's targets and the stated rules (the file header says the same in words).
function plan() {
  const verified = [125, 200, 300, 325, 350, 375, 400, 425, 450, 475, 500, 525];
  const accts = [0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5];   // repeat business customer accounts (ledger 1091); // customers launch in January 2027 (index 3)
  const base = 10000 + 5000 + 799 + 799 + 1200 + 800, oneOff = [7000, 5000];
  let cum = 0;
  return verified.map((v, i) => {
    const sme = i >= 3 ? Math.round(0.2 * v) : 0, requests = sme + 6 * accts[i], reveals = Math.round(0.15 * sme) + 3 * accts[i];
    const fee = Math.round(0.15 * sme) * 390 + 3 * accts[i] * 1500; cum += fee;
    return [new Date(Date.UTC(2026, 9 + i, 1)).toISOString().slice(0, 10), v, v - (i ? verified[i - 1] : 0), requests,
      Math.round(requests * 1.8), reveals, fee, cum, accts[i], base + (oneOff[i] ?? 0)];
  });
}

test('static: the plan table is the founder\'s targets, recomputed', () => {
  const src = read(MINE);
  const rows = [...src.matchAll(/\('(20\d\d-\d\d-01)', (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+)\)/g)]
    .map((m) => [m[1], ...m.slice(2).map(Number)]);
  assert.deepEqual(rows, plan(), 'a number in ceo_year_plan is not the rule\'s');
  const at = (m) => rows.find((r) => r[0] === m)[1];
  assert.equal(at('2026-11-01'), 200); assert.equal(at('2026-12-01'), 300); assert.equal(at('2027-08-01'), 500);
  assert.ok(rows.reduce((a, r) => a + r[9], 0) < 250000, 'the year\'s cost ceilings reach AED 250,000');
  assert.ok(rows.slice(0, 3).every((r) => r[3] === 0 && r[5] === 0 && r[6] === 0), 'customer activity before the January 2027 launch');
  assert.ok(!/three quotes on every request(?! \(any)/i.test(src), 'three quotes read as a cap; any number of suppliers may quote');
  assert.ok(!/investor|valuation|cap table|\bAI\b/i.test(src), 'the CEO\'s plan names the investor pack or the word AI');
});

test('static: every routine pinned and revoked, every table RLS + policy, duties owned, pending XOR MANIFEST', () => {
  const src = code(MINE);
  const made = [...new Set([...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]))];
  assert.ok(made.length >= 15, `expected the routines of this file, found ${made.length}`);
  for (const name of made) {
    const head = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[0];
    assert.match(head, /set search_path to 'public', 'pg_temp'/, `${name} has no pinned search_path`);
    assert.match(head, /security definer/, `${name} is not security definer`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  for (const t of [...src.matchAll(/create table if not exists public\.(\w+)/g)].map((m) => m[1])) {
    assert.match(src, new RegExp(`alter table public\\.${t} enable row level security`), `${t} has no RLS`);
    assert.match(src, new RegExp(`create policy ${t}_service_role_only on public\\.${t}[^;]*using \\(false\\) with check \\(false\\)`), `${t} has no policy`);
    assert.match(src, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t} is not revoked`);
  }
  for (const [, prefix, owner] of src.matchAll(/\('(\w+)\.\w+', '(\w+)', interval/g)) assert.equal(prefix, owner, `duty ${prefix} registered to ${owner}`);
  // the judgements stay where #906 and #913 put them (the review, the forecast, root causes); every new routine is code
  const judged = new Set(['fn_ceo_target_forecast', 'fn_ceo_management_review', 'fn_ceo_target_daily_verdict']);
  for (const name of made.filter((n) => !judged.has(n))) {
    const body = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[1];
    assert.ok(!/fn_seat_duty_reason|fn_ceo_root_cause_ask|fn_seat_duty_cross_review/.test(body), `${name} calls a model; routine work is code`);
  }
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(MINE) !== manifest.includes(MINE), 'exactly one of a pending note and a MANIFEST line');
});

test('static: the probe empties the hold\'s target_keys only, never its flag', () => {
  const src = read('scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs');
  const writes = [...src.matchAll(/update public\.founder_hold set ([^;]*);/g)].map((m) => m[1]);
  assert.deepEqual(writes, ["target_keys = '{}' where hold_key = 'supplier_campaign'"], 'the probe writes the hold beyond its target_keys');
  assert.ok(!/(update|insert into|delete from) public\.app_secrets/i.test(src), 'the probe writes app_secrets: the hold\'s flag is the founder\'s');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

// The hold pauses, it does not hide: with the founder's hold on, every held target reads 'paused' and every other
// target reads exactly what it reads without the hold. And while the hold is on, at least one held target must be one
// that would otherwise have missed, or the held pass proves nothing about the hold.
function assertHoldPauses(held, free) {
  assert.ok(held && held.day && free, 'the probe did not read the day with and without the hold');
  for (const [m, s] of Object.entries(free)) {
    const want = held.keys.includes(m) ? 'paused' : s;
    assert.equal(held.day[m], want, `with the founder's hold on, ${m} read ${held.day[m]}, expected ${want}`);
  }
  assert.deepEqual(Object.keys(held.day).sort(), Object.keys(free).sort(), 'the hold dropped a target from the day');
  if (held.keys.length) assert.ok(held.keys.some((k) => free[k] === 'miss'), `the hold is on (${held.keys}) but no held target would have missed: the held pass is vacuous`);
}

async function liveHold() {
  const { sql } = await import('../lib/db.mjs');
  return (await sql(`select h.target_keys, (select value from public.app_secrets where key = h.flag_key) is not distinct from h.flag_released_value released
                       from public.founder_hold h where hold_key = 'supplier_campaign'`, { readOnly: true }))[0];
}

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  try { await replaySql(FILES.filter(pending).map(read).join('\n') + '\n' + block, { retry: false }); }
  catch (e) {
    // e.message is capped at 2,000 characters by db.mjs; the full answer is on e.body
    const m = String(e.body ?? e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1500));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: the path, the day, the month and the improvements act', { skip: SKIP }, async () => {
  const hold = await liveHold();
  const o = await probe(String.raw`
do $$ declare o jsonb := '{}'; v jsonb; n bigint; hid bigint; c bigint; hk text[]; begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  select id into c from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30';
  o := o || jsonb_build_object('contracts', (select jsonb_object_agg(contract_key, status) from public.target_contract
            where contract_key in ('FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30', 'REVEAL_FEES_BASE_PATH_BY_2027_08_31', 'REVENUE_AED_1M_BY_2027_10_01', 'SUPPLIERS_1000_BY_2027_10_01')),
    'paths', (select count(*) from public.target_path where contract_id = c),
    'seats', (select count(distinct owner_seat) from public.target_path where contract_id = c),
    'plan_month_oct', (select jsonb_build_object('verified', verified, 'inquiries', inquiries, 'fee', fee_aed) from public.ceo_plan_month where month = date '2026-10-01'),
    'mandate', (select count(*) from public.ceo_mandate));

  -- a November day with nothing measured, and a cost over its ceiling
  insert into public.expense_entries (vendor, category, amount, currency, charged_on, note, source)
  values ('ZZ DEMO vendor', 'probe', 30000, 'AED', date '2026-11-05', 'ZZ DEMO probe', 'probe');
  -- The founder's supplier_campaign hold (ledger 1312) pauses the supplier targets, so with it on a November day has
  -- fewer misses than the path. First the day as production would read it, in a sub-block that rolls itself back:
  -- every held target must read 'paused' (never dropped). Then the hold's target_keys are emptied INSIDE THIS ABORTED
  -- TRANSACTION ONLY (the flag, invite_enabled, is never touched) so the rest of the probe measures the path itself.
  hk := array(select target_key from public.fn_held_targets() where hold_key = 'supplier_campaign');
  begin
    v := public.fn_ceo_target_daily_verdict(timestamptz '2026-11-20 10:00+04');
    o := o || jsonb_build_object('held', jsonb_build_object('keys', to_jsonb(hk), 'misses', v->'misses',
      'day', (select jsonb_object_agg(metric_key, status) from public.target_daily_verdict where contract_id = c and day = date '2026-11-20')));
    raise exception 'ZZ_HELD_PASS_ROLLED_BACK';
  exception when raise_exception then if sqlerrm <> 'ZZ_HELD_PASS_ROLLED_BACK' then raise; end if;
  end;
  -- ISOLATION (10 Nov 2026, it_engineer). This probe reads a November day; it was written before production had one.
  -- Since 8 Nov the year-one contract holds REAL open November miss tasks (5 on 10 Nov: invitations_delivered,
  -- registrations_submitted, registrations_verified_cumulative, verified_suppliers_milestone, it_findings_open), and the
  -- verdict rightly opens one task per metric per month, so the probe saw 7 misses and only 2 new tasks. The real
  -- links are set aside for the 20 Nov runs only and restored right after them; the closing raise rolls back both.
  create temp table _zz_nov_links on commit drop as
    select day, contract_id, metric_key, task_id from public.target_daily_verdict where contract_id = c and day between date '2026-11-01' and date '2026-11-30' and task_id is not null;
  update public.target_daily_verdict d set task_id = null from _zz_nov_links l
   where (d.day, d.contract_id, d.metric_key) = (l.day, l.contract_id, l.metric_key);
  update public.founder_hold set target_keys = '{}' where hold_key = 'supplier_campaign';
  select coalesce(max(id), 0) into n from public.agent_actions;
  v := public.fn_ceo_target_daily_verdict(timestamptz '2026-11-20 10:00+04');
  o := o || jsonb_build_object('nov_misses', v->'misses', 'nov_opened', v->'tasks_opened',
    'nov_day', (select jsonb_object_agg(metric_key, status) from public.target_daily_verdict where contract_id = c and day = date '2026-11-20'),
    'cost_status', (select status from public.target_daily_verdict where contract_id = c and day = date '2026-11-20' and metric_key = 'costs_aed'),
    'root_cause_to', (select jsonb_agg(distinct agent order by agent) from public.agent_actions where id > n and kind = 'handoff' and detail->>'type' = 'ceo.root_cause'));
  update public.target_daily_verdict d set task_id = l.task_id from _zz_nov_links l   -- the real November links, back
   where (d.day, d.contract_id, d.metric_key) = (l.day, l.contract_id, l.metric_key);

  -- the day: a stuck ZZ DEMO handoff is re-run; the note is kept on the day, never mailed (ledger 1609)
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  values ('marketing', 'handoff', 'pending', 'low', 'ZZ DEMO stuck', jsonb_build_object('type', 'ceo.improvement', 'from', 'ceo', 'to', 'marketing', 'proposal', 'ZZ DEMO'),
          'ceo_improvement', 'ceo.improvement:zz-demo', timestamptz '2026-11-15 10:00+04') returning id into hid;
  v := public.fn_ceo_daily_run(timestamptz '2026-11-20 10:05+04');
  o := o || jsonb_build_object('day', jsonb_build_object('stuck_new', v->'stuck_new', 'note', coalesce(v->>'note_handoff_id', '') <> '',
            'matters', jsonb_array_length(v->'matters'), 'seats', (select count(*) from jsonb_object_keys(v->'priorities'))),
    'stuck_after', (select detail ? 'replied_at' from public.agent_actions where id = hid),
    'day_again_note_same', public.fn_ceo_daily_run(timestamptz '2026-11-20 12:00+04')->'note_handoff_id' = v->'note_handoff_id');

  -- the month: October closes, the report goes, November's directives are issued once
  v := public.fn_ceo_month_plan(timestamptz '2026-10-02 09:00+04');
  -- October is issued once, by the routine: by its own 1 Oct run in production or by this call. Count the month, not
  -- this call's return, or the check goes red every day after the real run (issued live 1 Oct 2026 08:45 Dubai).
  o := o || jsonb_build_object('oct_issued', (select count(*) from public.ceo_seat_directive
            where month = date '2026-10-01' and handoff_id is not null));
  -- November the same way (10 Nov 2026): the real 1 Nov run (report written 31 Oct 22:01 UTC) closed October's five
  -- directives, wrote its report and issued November's five, so this call returns closed 0 / issued 0 every day after
  -- it. The month is counted: October's directives judged, November's issued with a handoff, October's report written.
  v := public.fn_ceo_month_plan(timestamptz '2026-11-01 09:00+04');
  o := o || jsonb_build_object('nov', jsonb_build_object(
      'closed', (select count(*) from public.ceo_seat_directive where month = date '2026-10-01' and status in ('met', 'missed', 'not_measurable')),
      'issued', (select count(*) from public.ceo_seat_directive where month = date '2026-11-01' and handoff_id is not null),
      'reported', exists (select 1 from public.ceo_month_report where month = date '2026-10-01')),
    'nov_again', public.fn_ceo_month_plan(timestamptz '2026-11-02 09:00+04')->'issued',
    'oct_status', (select jsonb_object_agg(seat, status) from public.ceo_seat_directive where month = date '2026-10-01'),
    'se_nov_targets', (select jsonb_agg(t->>'metric' order by t->>'metric') from public.ceo_seat_directive d, jsonb_array_elements(d.targets) t where d.month = date '2026-11-01' and d.seat = 'sales_engineer'),
    'se_nov_actions', (select cardinality(actions) from public.ceo_seat_directive where month = date '2026-11-01' and seat = 'sales_engineer'),
    'month_miss_improvements', (select count(*) from public.ceo_improvement where source_kind = 'month_miss'),
    'report_has_targets', (select body like '%registrations_verified_cumulative%' from public.ceo_month_report where month = date '2026-10-01'));

  -- recurring misses become an improvement, once
  insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status)
  select current_date - g, c, 'inquiries_posted', 'marketing', 10, 0, -100, 'miss' from generate_series(1, 8) g
  on conflict (day, contract_id, metric_key) do update set status = 'miss', owner_seat = excluded.owner_seat;   -- live days carry the real owner
  -- five ZZ DEMO targets behind their path: exactly one improvement each, in ONE run
  insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status)
  select current_date - g, c, 'zz_demo_target_' || k, 'marketing', 10, 0, -100, 'miss' from generate_series(1, 5) k, generate_series(0, 7) g;
  v := public.fn_ceo_improvement_sweep();
  o := o || jsonb_build_object('improvement', (select jsonb_build_object('seat', seat, 'status', status, 'handoff', (select status from public.agent_actions where id = i.handoff_id))
            from public.ceo_improvement i where source_kind = 'recurring_miss' and source_ref like 'inquiries_posted:%'),
    'zz_improvements', (select jsonb_build_object('rows', count(*), 'targets', count(distinct evidence->>'metric')) from public.ceo_improvement
            where source_kind = 'recurring_miss' and evidence->>'metric' like 'zz_demo_target_%'),
    'sweep_again', (public.fn_ceo_improvement_sweep()->>'proposed')::int);
  -- the weekly summary email: plan against actual for every metric
  v := public.fn_ceo_weekly_report(date '2026-11-16');
  update public.ceo_weekly_report set body = body where id = (v->>'id')::bigint;   -- a rewrite must not add it twice
  o := o || jsonb_build_object('weekly', (select jsonb_build_object('has_section', position('PLAN AGAINST ACTUAL' in body) > 0,
            'rows', jsonb_array_length(figures->'plan_vs_actual'),
            'line', substring(body from '(registrations_verified_cumulative \(sales_engineer\)[^\n]*\n[^\n]*)'),
            'once', (length(body) - length(replace(body, 'PLAN AGAINST ACTUAL', ''))) = length('PLAN AGAINST ACTUAL'))
            from public.ceo_weekly_report where id = (v->>'id')::bigint));
  o := o || jsonb_build_object('status_metrics', jsonb_array_length(public.fn_ceo_year_plan_status(timestamptz '2026-11-20 10:00+04')->'metrics'),
    'forecast_reads_it', public.fn_ceo_target_forecast()->'verdicts' @> '[{"contract":"FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30"}]');
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.deepEqual(await liveHold(), hold, 'the founder\'s hold changed in production: the probe must touch it only inside its aborted transaction');

  assert.deepEqual(o.contracts, { FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30: 'active', REVEAL_FEES_BASE_PATH_BY_2027_08_31: 'superseded',
    REVENUE_AED_1M_BY_2027_10_01: 'superseded', SUPPLIERS_1000_BY_2027_10_01: 'superseded' }, 'a replaced target is still in force');
  assert.equal(o.paths, 192); assert.equal(o.seats, 6);
  assert.deepEqual(o.plan_month_oct, { verified: 125, inquiries: 0, fee: 0 }, 'the CEO month plan does not follow the path');
  assert.ok(o.mandate >= 20, 'the mandate is missing');
  assert.ok(o.nov_misses >= 4 && o.nov_opened === o.nov_misses, `a November day with nothing measured: ${o.nov_misses} misses, ${o.nov_opened} tasks`);
  assertHoldPauses(o.held, o.nov_day);
  assert.equal(o.cost_status, 'miss', 'a cost over its month ceiling is not a miss');
  assert.ok(o.root_cause_to.includes('accountant') && o.root_cause_to.includes('sales_engineer'), `root cause went to ${o.root_cause_to}`);
  assert.equal(o.day.stuck_new >= 1, true, 'the stuck handoff was not found');
  assert.equal(o.stuck_after, true, 'the stuck handoff was not re-run');
  assert.equal(o.day.note, false, 'ledger 1609: the CEO note is mailed to the founder again; the brief is his one daily message');
  assert.ok(o.day.matters >= 1, 'a day with misses kept nothing on ceo_day.matters');
  assert.equal(o.day.seats, 5, 'not every seat has the day\'s priority');
  assert.equal(o.day_again_note_same, true, 'a second run the same day sent a second note');
  assert.equal(o.oct_issued, 5, 'October\'s directives were not issued');
  assert.deepEqual(o.nov, { closed: 5, issued: 5, reported: true }, 'the month did not close, report and issue');
  assert.equal(o.nov_again, 0, 'a second run the same month issued twice');
  assert.ok(Object.values(o.oct_status).every((s) => ['met', 'missed', 'not_measurable'].includes(s)), JSON.stringify(o.oct_status));
  assert.deepEqual(o.se_nov_targets, ['b2b_active_accounts', 'inquiries_posted', 'quote_coverage_pct', 'quotes_received', 'registrations_verified_cumulative', 'reveals_paid']);
  assert.equal(o.se_nov_actions, 1, 'the sales engineer\'s directive carries no actions from the plan table');
  assert.ok(o.month_miss_improvements >= 1, 'a missed month opened no improvement');
  assert.equal(o.report_has_targets, true, 'the monthly report does not carry the targets');
  assert.deepEqual(o.improvement, { seat: 'marketing', status: 'assigned', handoff: 'pending' }, 'a recurring miss did not become an assigned improvement');
  assert.deepEqual(o.zz_improvements, { rows: 5, targets: 5 }, 'five missed targets did not get exactly one improvement each');
  assert.equal(o.sweep_again, 0, 'a second sweep proposed more: the sweep does not settle in one run (it must close before it proposes, until a pass changes nothing)');
  assert.equal(o.status_metrics, 16);
  assert.equal(o.weekly.has_section, true, 'the weekly summary email carries no plan against actual');
  assert.equal(o.weekly.rows, 16, 'the weekly summary misses a metric');
  assert.match(o.weekly.line ?? '', /^registrations_verified_cumulative \(sales_engineer\): target [\d.]+, actual \d+, gap -?[\d.]+, (on plan|BEHIND)(\n|\\n)\s*Action: .+/, 'a weekly line lacks target, actual, gap, seat or action: ' + o.weekly.line);
  assert.equal(o.weekly.once, true, 'the section was written twice');
  assert.equal(o.forecast_reads_it, true, 'the weekly forecast does not read the founder\'s contract');
});

test('production, aborted: five missed ZZ targets settle in one sweep; a recovered one and a month rollover open nothing', { skip: SKIP }, async () => {
  const o = await probe(read('scripts/sql/the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run_probe.sql'));
  assert.equal(o.verdict, 'PROBE OK', JSON.stringify(o));
});
