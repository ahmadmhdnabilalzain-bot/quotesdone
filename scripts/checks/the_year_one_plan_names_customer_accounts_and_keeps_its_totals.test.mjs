// THE YEAR-ONE PLAN NAMES CUSTOMER ACCOUNTS AND KEEPS ITS TOTALS (ceo, 30 Sep 2026, founder ledger 1091).
//
// The founder removed the enterprise account grouping (#1169) and ruled the year-one plan must not be lowered: its
// volume sits on customer accounts. This fails when:
//   * static: the plan rows no longer sum to the ledger's totals;
//   * production (read): a target, the mandate, a seat action, the plan table or the active contract names it; the
//     plan's totals differ from the LAST entry of LEDGER below; an entry names a ledger row that does not exist.
//     A plan change is legal only by adding an entry here that names the founder_instruction row that ordered it;
//   * production (one aborted transaction, the pending file replayed): any metric's monthly or yearly total differs
//     before and after the relabel, or the CEO target verdict or forecast stops running.
//
//   node --test scripts/checks/the_year_one_plan_names_customer_accounts_and_keeps_its_totals.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const PLAN = 'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql';
const MINE = 'scripts/sql/the_year_one_plan_carries_the_business_account_volume_on_customer_accounts.sql';
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

// Each founder_instruction row that set or moved the plan, with the year totals it leaves.
// requests, quotes, reveals, fee_aed, business-account months, cost ceilings, verified at September's end.
const LEDGER = [
  { id: 971, totals: { months: 12, requests: 915, quotes: 1647, reveals: 191, fee_aed: 157740, accounts: 25, cost_ceiling_aed: 235176, verified_sep: 525 } },
  { id: 1091, totals: { months: 12, requests: 915, quotes: 1647, reveals: 191, fee_aed: 157740, accounts: 25, cost_ceiling_aed: 235176, verified_sep: 525 } },
];
const current = LEDGER.at(-1).totals;

test('static: the year-plan files name customer accounts, and the rows sum to the ledger', () => {
  // The plan file is applied history (24 Sep, #924) and keeps its wording: an applied file is never edited. Whether
  // anything LIVE still names the removed grouping is the production test below, which reads the database.
  const rows = [...read(PLAN).matchAll(/\('(20\d\d-\d\d-01)', (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+), (\d+)\)/g)].map((m) => m.slice(2).map(Number));
  const sum = (i) => rows.reduce((a, r) => a + r[i], 0);
  assert.deepEqual({ months: rows.length, requests: sum(2), quotes: sum(3), reveals: sum(4), fee_aed: sum(5), accounts: sum(7), cost_ceiling_aed: sum(8), verified_sep: rows.at(-1)[0] },
    current, 'the plan file no longer carries the totals of the last founder ledger entry');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';
const TOTALS = `(select jsonb_build_object('months', count(*), 'requests', sum(requests), 'quotes', sum(quotes), 'reveals', sum(reveals),
   'fee_aed', sum(fee_aed), 'accounts', sum(coalesce((to_jsonb(y)->>'business_accounts')::int, (to_jsonb(y)->>'enterprise')::int)),
   'cost_ceiling_aed', sum(cost_ceiling_aed), 'verified_sep', max(verified) filter (where month = date '2027-09-01')) from public.ceo_year_plan y)`;

test('production: no target names the grouping; totals match the last ledger entry; every entry is a real ledger row', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  if (pending(MINE)) return;   // before the apply the live plan still carries the old wording; the aborted probe covers it
  const [r] = await sql(`select ${TOTALS} as totals,
    (select coalesce(jsonb_agg(id order by id), '[]') from public.founder_instruction where id = any (array[${LEDGER.map((l) => l.id).join(',')}])) as ledger,
    (select count(*) from public.ceo_mandate where clause_key ~* 'enterpr' or statement ~* 'enterpr')
    + (select count(*) from public.ceo_plan_action where action ~* 'enterpr')
    + (select count(*) from public.ceo_year_plan where basis ~* 'enterpr')
    + (select count(*) from public.target_contract where status = 'active' and (objective ~* 'enterpr' or contract_key ~* 'enterpr' or success_definition ~* 'enterpr' or assumptions::text ~* 'enterpr'))
    + (select count(*) from public.target_path p join public.target_contract c on c.id = p.contract_id where c.status = 'active' and (p.metric_key ~* 'enterpr' or p.source ~* 'enterpr'))
    + (select count(*) from information_schema.columns where table_schema = 'public' and table_name in ('ceo_year_plan', 'target_path', 'target_contract', 'ceo_mandate') and column_name ~* 'enterpr') as names`);
  assert.equal(Number(r.names), 0, 'a target, the mandate, a seat action or the plan names the removed account grouping');
  assert.deepEqual(r.ledger, LEDGER.map((l) => l.id), 'a LEDGER entry names a founder_instruction row that does not exist');
  const got = Object.fromEntries(Object.entries(r.totals).map(([k, v]) => [k, Number(v)]));
  assert.deepEqual(got, current, 'the year-one plan totals changed without a founder ledger entry in this check');
});

test('production, aborted: every monthly and yearly total is identical before and after; verdict and forecast run', { skip: SKIP }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');   // the one door: the pending body cannot commit
  const body = pending(MINE) ? read(MINE).replace(/\n-- Verdict:[\s\S]*$/, '\n') : '';
  const snap = `(select jsonb_object_agg(y.month, (to_jsonb(y) - 'basis' - 'enterprise' - 'business_accounts')
      || jsonb_build_object('accounts', coalesce(to_jsonb(y)->'business_accounts', to_jsonb(y)->'enterprise'))) from public.ceo_year_plan y)`;
  const paths = `(select jsonb_object_agg(p.metric_key || '@' || p.month, p.value) from public.target_path p join public.target_contract c on c.id = p.contract_id
      where c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30')`;
  let o;
  try {
    await replaySql(`create temp table zz_before on commit drop as select ${snap} as months, ${TOTALS} as year, ${paths} as paths;\n${body}\n` + String.raw`
do $$ declare o jsonb; v jsonb; f jsonb; begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  v := public.fn_ceo_target_daily_verdict(now());
  f := public.fn_ceo_target_forecast();
  o := jsonb_build_object(
    'before_year', (select year from zz_before), 'after_year', ${TOTALS},
    'months_same', (select months from zz_before) = ${snap}, 'paths_same', (select paths from zz_before) = ${paths},
    'path_rows', (select count(*) from jsonb_object_keys((select paths from zz_before))),
    'names', (select count(*) from public.ceo_mandate where clause_key ~* 'enterpr' or statement ~* 'enterpr')
           + (select count(*) from public.ceo_plan_action where action ~* 'enterpr')
           + (select count(*) from public.target_contract where status = 'active' and objective ~* 'enterpr')
           + (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ceo_year_plan' and column_name ~* 'enterpr'),
    'verdict_ran', v is not null and v ? 'misses', 'forecast_ran', f is not null,
    'forecast_reads_plan', f->'verdicts' @> '[{"contract":"FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30"}]');
  raise exception 'CHK<<%>>', o::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1500));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  const num = (x) => Object.fromEntries(Object.entries(x).map(([k, v]) => [k, Number(v)]));
  assert.deepEqual(num(o.after_year), num(o.before_year), 'a yearly total moved');
  assert.deepEqual(num(o.after_year), current, 'the yearly totals are not the founder\'s');
  assert.equal(o.months_same, true, 'a monthly figure moved');
  assert.equal(o.paths_same, true, 'a target path value moved');
  assert.equal(o.path_rows, 192, 'the path lost a metric-month');
  assert.equal(Number(o.names), 0, 'the plan still names the removed account grouping');
  assert.equal(o.verdict_ran, true, 'the CEO target verdict does not run');
  assert.equal(o.forecast_ran && o.forecast_reads_plan, true, 'the CEO forecast does not run or does not read the plan');
});
