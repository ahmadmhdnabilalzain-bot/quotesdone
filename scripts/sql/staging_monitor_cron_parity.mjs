// 164 active cron jobs on production, 37 on staging. Copying all 127 would be wrong: most of them
// are the company DOING ITS WORK -- department AI dailies, weekly reports, outreach, knowledge
// generation -- and staging has no business to run, so each would be a model call spent to produce
// something nobody reads.
//
// What a rehearsal surface MUST run is the detectors. If staging does not watch what production
// watches, a monitoring failure cannot be rehearsed there, which is the whole point of the surface.
// Part 9 already made this argument for control_mode_sweep_5min and smoke_test_30min. This is the
// rest of that class: jobs whose purpose is to notice that something is broken, with no external
// side effect.
//
// DELIBERATELY NOT COPIED, and this is a decision rather than drift:
//   * every *_ai_daily, cos_execute, exec-agents, report and digest job -- the company's work, and
//     a model call each
//   * backup_daily / dropbox_* -- they write to a SHARED external account, so staging backups would
//     land in the same Dropbox as production's
//   * supplier_invites, invite_ramp, no_quote_nudges, reveal-nudges, wa_flush, sms_flush, email_cron
//     -- outbound. Staging's channels are all gated off, but scheduling them would make the gate the
//     only thing standing between a rehearsal and a real supplier's phone
//
//   node scripts/sql/staging_monitor_cron_parity.mjs [--apply]
import { readFileSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh', STG = 'pglpqrhvozwepymcuunn';
const APPLY = process.argv.includes('--apply');
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const q = async (ref, sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  const b = await r.text();
  if (!r.ok) throw new Error(ref + ' ' + r.status + ': ' + b.slice(0, 300));
  return JSON.parse(b);
};

const DETECTORS = [
  'uptime_check_15min', 'edge_health_scan_15min', 'ai_health_15min', 'resilience_watch_10min',
  'health_check', 'exception_alerts_hourly', 'sla_watch_hourly', 'ai_spend_guard_hourly',
  'security_selfaudit_daily', 'money_tests_daily', 'qa_suite_daily', 'policy_consistency_weekly',
  'dead_letter_drain_held', 'autonomy_audit_weekly',
];

const lit = (s) => "'" + s.replace(/'/g, "''") + "'";

const want = await q(PROD, `select jobname, schedule, command from cron.job
   where active and jobname in (${DETECTORS.map(lit).join(',')})`);
const have = new Set((await q(STG, `select jobname from cron.job`)).map(r => r.jobname));
const todo = want.filter(j => !have.has(j.jobname));

console.log(`detectors named ${DETECTORS.length}, found on production ${want.length}, missing on staging ${todo.length}`);
for (const j of todo) console.log(`  ${j.jobname.padEnd(28)} ${j.schedule}`);
const notOnProd = DETECTORS.filter(d => !want.some(w => w.jobname === d));
if (notOnProd.length) console.log(`  NOT ON PRODUCTION EITHER (nothing copied): ${notOnProd.join(', ')}`);

if (APPLY && todo.length) {
  for (const j of todo) {
    await q(STG, `select cron.schedule(${lit(j.jobname)}, ${lit(j.schedule)}, ${lit(j.command)});`);
  }
  const after = (await q(STG, `select count(*)::int as n from cron.job where active`))[0].n;
  const prod = (await q(PROD, `select count(*)::int as n from cron.job where active`))[0].n;
  console.log(`staging active crons now ${after} (production ${prod}); the gap is the company's own` +
              ` work and the outbound jobs, left off on purpose`);
}
