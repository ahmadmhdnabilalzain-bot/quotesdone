// Prove that every step of the change_deployment workflow now has a company playbook the
// DETERMINISTIC applier will apply — on production, with no model call (MASTER_PLAN A1 / §4.2).
//
// This is the applier's own call, not an approximation of it: the query vector comes from kb_embed's
// query mode (the same free in-region gte-small that embedded the rows), the query text is what
// workflow_dispatch passes (workflow name + step text — the trigger JSON is in the embedding, never in
// the corroboration), and fn_apply_playbook runs at its real floor of 0.85 with k=20. It writes
// nothing and it calls no paid provider.
//
// PASS = every step returns matched=true, cites the record written for that step, and is corroborated
// by at least 2 of the step's own lexemes and at least 30% of them.
//
//   node scripts/archive/kb/probe_change_deployment_playbooks.mjs
import { sql } from '../../lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const WORKFLOW = 'change_deployment';

// The seat that actually works each step, read off the parked runs on 4 Sep 2026. Step 3 is worked by
// eng_manager on 14 of the 26 runs and by cto on the other 12; eng_manager is the stricter of the two
// (it holds no packaged role, so only the department arm of the scope predicate can reach it).
const SEAT = { 1: 'optimisation_eng', 2: 'cto', 3: 'eng_manager', 4: 'qa_manager',
               5: 'qa_manager', 6: 'cto', 7: 'qa_manager', 8: 'cto', 9: 'cpo' };

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

const wf = (await sql(`select name from public.workflow where workflow_key = '${WORKFLOW}'`))[0]?.name;
const steps = await sql(`select step_no, step from public.workflow_step
                          where workflow_key = '${WORKFLOW}' order by step_no`);
// One real trigger context off a parked run, so the embedded need is the one the dispatcher builds.
const ctx = (await sql(`select context::text c from public.workflow_run
                         where workflow_key = '${WORKFLOW}' order by created_at desc limit 1`))[0]?.c ?? '{}';

let failures = 0;
for (const s of steps) {
  const agent = SEAT[Number(s.step_no)];
  const need = `${wf} — ${s.step} — ${ctx}`.slice(0, 1200);       // workflow_dispatch's embedding text
  const qtext = `${wf} ${s.step}`;                                 // workflow_dispatch's corroboration text
  const vec = await embed(need);
  const [row] = await sql(
    `select public.fn_apply_playbook('${agent}', '[${vec.join(',')}]'::vector(384),
              '${qtext.replace(/'/g, "''")}', 0.85, 20) as r`);
  const d = row.r;
  const ok = d?.matched === true
    && String(d.record_id || '').startsWith(`ops-change-deployment-step-${String(s.step_no).padStart(2, '0')}-`)
    && Number(d.similarity) >= 0.85
    && Number(d.terms_matched) >= 2
    && Number(d.terms_matched) / Number(d.terms_total) >= 0.30;
  if (!ok) failures++;
  console.log(`step ${s.step_no} (${agent}) ${ok ? 'OK ' : 'FAIL'} `
    + (d?.matched
        ? `${d.similarity} ${d.terms_matched}/${d.terms_total} terms  ${d.record_type}  ${d.title}`
        : `no match: ${String(d?.reason || '').slice(0, 180)}`));
}

console.log(`\n${steps.length - failures}/${steps.length} change_deployment steps have a corroborated `
  + `actionable playbook at or above the 0.85 floor, for the seat that works them`);
process.exit(failures ? 1 : 0);
