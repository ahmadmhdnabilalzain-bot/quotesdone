// Prove, on production and with NO model call, that every metric_lifecycle step the deterministic
// applier has to work retrieves its OWN authored playbook — cosine at or above the 0.85 floor AND
// corroborated by the step's own words (MASTER_PLAN A1 / §4.2).
//
// This reproduces workflow_dispatch exactly: the need string it embeds is
//   "<workflow name> — <step> — <trigger context JSON>"
// and the corroboration text it passes is "<workflow name> <step>" (the step's own words, not the
// context). Postgres cannot embed a sentence — gte-small lives in the Edge runtime — so the query
// vector comes from kb_embed's query mode, the same free in-region model that embedded the rows.
// fn_apply_playbook is STABLE: nothing is written.
//
// Step 2 is absent on purpose: it has a real low-risk executor (ai_health) and is closed by
// fn_workflow_step_sweep, so the applier never sees it. See
// scripts/sql/metric_lifecycle_playbooks_close_the_loop_model_off.sql.
//
//   node scripts/kb/probe_metric_lifecycle_playbooks.mjs
import { sql } from '../phase_c/lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
// step_no -> the record that step must retrieve, and the agent the workflow names as its actor
const EXPECT = {
  1: ['ops-metric_lifecycle-define-the-metric-and-why-it-matters', 'intel_director'],
  3: ['ops-metric_lifecycle-measure-on-cadence-and-record-the-actual', 'intel_director'],
  4: ['ops-metric_lifecycle-detect-variance-against-target', 'cpo'],
  5: ['ops-metric_lifecycle-root-cause-the-work-or-the-target', 'cpo'],
  6: ['ops-metric_lifecycle-revise-the-metric-or-retire-it', 'intel_director'],
  7: ['ops-metric_lifecycle-report-the-measured-actual-and-its-evidence', 'bi_analyst'],
};
const FLOOR = 0.85;

const secret = (await sql(`select value from public.app_secrets where key = 'cred_cron_knowledge'`))[0]?.value;
if (!secret) { console.error('no cred_cron_knowledge in app_secrets'); process.exit(2); }

async function embed(query) {
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/kb_embed`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, query }) });
  const j = await r.json();
  if (!r.ok || !Array.isArray(j.embedding) || j.embedding.length !== 384) {
    throw new Error(`kb_embed query mode: HTTP ${r.status} ${JSON.stringify(j).slice(0, 200)}`);
  }
  return j.embedding;
}

const wfName = (await sql(`select name from public.workflow where workflow_key='metric_lifecycle'`))[0].name;
const steps = await sql(`select step_no, step from public.workflow_step where workflow_key='metric_lifecycle' order by step_no`);
// every live trigger context: a kpi.missed payload differs per metric and it is part of the embedded need
const ctxs = (await sql(`select distinct r.context::text as c from public.workflow_run r
                          where r.workflow_key='metric_lifecycle' and r.context is not null`)).map((r) => r.c);
if (!ctxs.length) ctxs.push('{}');

let bad = 0, cases = 0;
for (const s of steps) {
  const exp = EXPECT[s.step_no];
  if (!exp) { console.log(`step ${s.step_no}: no applier record by design (worked by the sweep) — skipped`); continue; }
  const [wantId, agent] = exp;
  let worst = null;
  for (const c of ctxs) {
    cases++;
    const vec = await embed(`${wfName} — ${s.step} — ${c}`.slice(0, 1200));
    const row = (await sql(`select public.fn_apply_playbook(
        '${agent}', '[${vec.join(',')}]'::vector(384),
        $q$${wfName} ${s.step}$q$, ${FLOOR}, 20) as d`))[0].d;
    const ok = row?.matched === true && row.record_id === wantId
      && Number(row.similarity) >= FLOOR && Number(row.terms_matched) >= 2
      && Number(row.terms_matched) / Number(row.terms_total) >= 0.30;
    if (!ok) bad++;
    if (!worst || Number(row?.similarity ?? 0) < Number(worst.similarity ?? 0)) worst = { ...row, ok };
  }
  const tag = worst?.matched === true && worst.record_id === wantId ? 'OK  ' : 'FAIL';
  if (tag === 'FAIL') bad++;
  console.log(`${tag} step ${s.step_no} (${agent}) "${s.step.slice(0, 44)}"`);
  console.log(`      worst of ${ctxs.length} live contexts: ${worst?.matched === true
    ? `${worst.record_id} @ ${worst.similarity}, corroborated ${worst.terms_matched}/${worst.terms_total}`
    : `NO MATCH — ${String(worst?.reason ?? '').slice(0, 180)}`}`);
}
console.log(`\n${cases - bad}/${cases} (step, live trigger context) pairs retrieved the step's own playbook at >= ${FLOOR} with keyword corroboration, no model call`);
process.exit(bad ? 1 : 0);
