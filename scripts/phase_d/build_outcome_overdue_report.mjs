// PHASE D DELIVERABLE — PHASE_D_OUTCOME_OVERDUE_REPORT.csv
//
// The founder's ruling of 21 Aug 2026, section G: a READ-ONLY report on the overdue outcome
// records, and nothing else. No record is updated, no corrective task is created, nothing is sent,
// no automation is reactivated and Row #3 is not touched.
//
//   node scripts/phase_d/build_outcome_overdue_report.mjs
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../lib/db.mjs';

const rows = await sql('select * from public.fn_phase_d_outcome_overdue_report()');
const total = (await sql('select count(*) n from public.outcome_record'))[0].n;
const job = (await sql("select jobid, jobname, schedule, active from cron.job where jobname = 'outcome_evaluate_daily'"))[0];

const cols = ['outcome_id','actor','dept_key','subject','original_due_at','days_overdue',
  'owning_workflow','accountable_role','expected_metric','verdict_now','why_evaluation_is_paused',
  'automation_hold','what_activation_would_do'];

const csv = provenance({
  command: 'node scripts/phase_d/build_outcome_overdue_report.mjs',
  numerator: rows.length, denominator: total,
  of: `rows of public.outcome_record; the numerator is those with due_at < now() and closed_at is null. cron job ${job.jobid} ${job.jobname} (${job.schedule}) active=${job.active}`,
  attribution: 'public.fn_phase_d_outcome_overdue_report(), which is STABLE and LANGUAGE sql so Postgres itself refuses any write from inside it; what_activation_would_do is derived from fn_outcome_evaluate\'s own selection predicate',
}) + cols.join(',') + '\n'
  + rows.map(r => cols.map(c => `"${String(r[c] ?? '').replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_OUTCOME_OVERDUE_REPORT.csv'), csv);
console.log(`${rows.length} overdue of ${total} outcome records; cron ${job.jobname} active=${job.active}`);
for (const r of rows) console.log(`  ${r.outcome_id}  due ${String(r.original_due_at).slice(0,10)}  ${r.days_overdue}d  ${r.verdict_now}  ${r.what_activation_would_do.slice(0,58)}`);
