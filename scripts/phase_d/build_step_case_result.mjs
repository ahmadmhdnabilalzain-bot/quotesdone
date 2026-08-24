// PHASE D DELIVERABLE — PHASE_D_STEP_CASE_RESULT.csv
//
// §11 of the brief: seven cases for each of the 257 frozen steps — positive, missing input, wrong
// actor, invalid state, duplicate, failed rule/gate, malformed output. 257 × 7 = 1,799.
//
// P05. THE INSTRUCTION THAT TOLD YOU TO WIPE THE TABLE AT THE MOMENT IT WAS SHORT.
// This header and the refusal message at the foot of this file both told a reader to run
// public.fn_phase_d_run_step_cases(). That routine is the pre-23-Aug contract-only matrix, its
// FIRST statement is `delete from public.phase_d_step_case_result`, and re-run at HEAD it replaces
// the authoritative 1,799 rows with 257 positive failures. The independent audit of 24 Aug 2026 did
// exactly that. It is retired by phase_d_p02 and now raises 23514. The authoritative runner is
// scripts/phase_d/run_step_cases_live.mjs, which drives a real step run per step in an aborted
// transaction and NEVER deletes -- it upserts on (step_id, case_kind).
//
// The matrix WAS executed by public.fn_phase_d_run_step_cases(), which wrote
// public.phase_d_step_case_result and asserts on the way out that it produced no effect and no step
// run. This script only READS that table, so it goes through the read door.
//
//   -- first, execute the matrix (it writes its own result table):
//   node scripts/phase_d/run_step_cases_live.mjs      <- the authoritative runner
//   -- then:
//   node scripts/phase_d/build_step_case_result.mjs
//
// `decided_at` is the column that keeps this honest: it records WHERE the guard that refused each
// case actually lives. Three of the seven kinds are decided by the step's own declared contract;
// four are decided at the executor, kernel or constraint boundary shared by all 257. A contract-level
// refusal must never be read as a driven one, so the level travels with every row.
//
// The script exits 1 rather than writing fewer rows than 7 × the frozen step count, so a partial
// export cannot be mistaken for a complete one.
import { writeFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { outPath, provenance } from './lib/deliverable.mjs';

const COLS = ['step_id', 'workflow_id', 'step_type', 'case_kind', 'decided_at',
              'expectation', 'passed', 'refused_with', 'detail'];

const rows = await mgmtRead(PROD_REF, `
  select r.step_id, s.workflow_id, s.step_type, r.case_kind, r.decided_at,
         r.expectation, r.passed::text, coalesce(r.refused_with,'') as refused_with, r.detail
    from public.phase_d_step_case_result r
    join public.phase_b_workflow_step s on s.step_id = r.step_id
   order by r.step_id,
            case r.case_kind
              when 'positive' then 1 when 'missing_input' then 2 when 'wrong_actor' then 3
              when 'invalid_state' then 4 when 'duplicate' then 5
              when 'failed_rule_or_gate' then 6 else 7 end`);

const expected = await mgmtRead(PROD_REF,
  'select (count(*) * 7)::int as n from public.phase_b_workflow_step');
const want = expected?.[0]?.n ?? 0;

if (!want || rows.length !== want) {
  console.error(`read ${rows.length} case row(s) and the frozen model implies ${want}. `
    + 'Refusing to write a partial export — run node scripts/phase_d/run_step_cases_live.mjs '
    + 'first. NOT fn_phase_d_run_step_cases(): that is the retired contract-only matrix and its '
    + 'first act is to DELETE this table, which is how it came to be short.');
  process.exit(1);
}

const cell = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};

writeFileSync(outPath('PHASE_D_STEP_CASE_RESULT.csv'),
  provenance({
    command: 'node scripts/phase_d/build_step_case_result.mjs',
    numerator: rows.length,
    denominator: want,
    of: 'declared cases (7 per frozen Phase B step)',
    attribution: 'one row per executed case in public.phase_d_step_case_result; decided_at records '
      + 'which boundary refused it, so a contract-level refusal is not read as a driven one',
  })
  + [COLS.join(',')].concat(rows.map((r) => COLS.map((c) => cell(r[c])).join(','))).join('\n') + '\n');

const failed = rows.filter((r) => r.passed !== 'true');
const byLevel = rows.reduce((a, r) => { a[r.decided_at] = (a[r.decided_at] || 0) + 1; return a; }, {});

console.log(`PHASE_D_STEP_CASE_RESULT.csv  ${rows.length} rows`);
console.log(`  cases passing                ${rows.length - failed.length} / ${rows.length}`);
for (const [k, v] of Object.entries(byLevel).sort()) console.log(`  decided at ${k.padEnd(22)} ${v}`);
if (failed.length) {
  console.log('  FAILING:');
  for (const f of failed.slice(0, 20)) console.log(`    ${f.step_id} ${f.case_kind} — ${f.detail}`);
  process.exit(1);
}
