// Closes a run of run.mjs whose driver was stopped before its own finally block: models off, spend read, teardown, window closed
// (sales_engineer, 12 Nov 2026). Used twice in the analysis of docs/reports/2026-11-12-supplier-service-profiling.md (2.6).
//   NODE_USE_ENV_PROXY=1 node scripts/e2e/services_hard_profiles/cleanup.mjs <tag>
const lib = (f) => import('../../lib/' + f);
const [tag] = process.argv.slice(2);
if (!/^[a-z0-9]{4,16}$/.test(tag || '')) { console.error('usage: cleanup.mjs <run tag>'); process.exit(2); }
const { newRun, teardown, REF, q, closeRehearsalWindow } = await lib('demo_factory.mjs');
const { mgmtRead, mgmtFixture } = await lib('qd_guard.mjs');
process.env.QD_FIXTURES = '1';
const run = newRun({ tag, quiet: true });
await mgmtFixture(REF, `update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + tag)}`, 'hard-profile window: models off');
const spend = (await mgmtRead(REF, `select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed from public.ai_cost_log where e2e_run_tag = ${q(tag)}`))[0];
console.log(`SPEND ${tag}: ${JSON.stringify(spend)} (USD ${(Number(spend.aed) / 3.6725).toFixed(4)})`);
const t = await teardown(run);
console.log(`run ${tag} torn down: ${t.summary}`);
await closeRehearsalWindow(tag);
console.log('window closed');
