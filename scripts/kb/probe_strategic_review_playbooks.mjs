// Prove, on production and with no model, that every step of the `strategic_review` workflow now has
// a company playbook the DETERMINISTIC applier will apply: cosine >= 0.85 AND keyword corroboration
// from the step's own words (MASTER_PLAN A1 / §4.2, scripts/sql/apply_playbook_needs_corroboration.sql).
//
// The need is built EXACTLY as supabase/functions/workflow_dispatch builds it —
//   embedding text: workflow name + ' — ' + step + ' — ' + JSON.stringify(run context), 1200 chars
//   corroboration text: workflow name + ' ' + step   (the step's own words, not the context blob)
// — and fn_apply_playbook is called with the same p_min_similarity 0.85 and p_k 20. The query vector
// comes from kb_embed's query mode: the same free in-region gte-small that embedded the rows, so this
// costs nothing and calls no paid provider. Nothing is written.
//
//   node scripts/kb/probe_strategic_review_playbooks.mjs
//   node scripts/kb/probe_strategic_review_playbooks.mjs --all-runs   # every running run, not one per context
import { sql } from '../lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const ALL = process.argv.includes('--all-runs');
const WORKFLOW = 'strategic_review';
// what each step must resolve to — the applier picking a different record is a FAILURE, not a pass
const EXPECT = {
  1: 'ops-exec-strategic-review-step-1-evidence',
  2: 'ops-exec-strategic-review-step-2-options',
  3: 'ops-exec-strategic-review-step-3-priority-hierarchy',
  4: 'ops-exec-strategic-review-step-4-decide-and-record',
  5: 'ops-exec-strategic-review-step-5-cascade',
  6: 'ops-exec-strategic-review-step-6-outcome-baseline',
};

const secret = (await sql(`select value from public.app_secrets where key = 'cred_cron_knowledge'`))[0]?.value;
if (!secret) { console.error('no cred_cron_knowledge in app_secrets'); process.exit(2); }

async function embed(query) {
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/kb_embed`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, query }),
  });
  const j = await r.json();
  if (!r.ok || !Array.isArray(j.embedding) || j.embedding.length !== 384) {
    throw new Error(`kb_embed query mode: HTTP ${r.status} ${JSON.stringify(j).slice(0, 200)}`);
  }
  return j.embedding;
}

const lit = s => `'${String(s).replace(/'/g, "''")}'`;

const [wf] = await sql(`select name from public.workflow where workflow_key = ${lit(WORKFLOW)}`);
const steps = await sql(`select step_no, step, actor_role from public.workflow_step
                          where workflow_key = ${lit(WORKFLOW)} order by step_no`);
const runs = await sql(`select r.id, r.context::text as context from public.workflow_run r
                         where r.workflow_key = ${lit(WORKFLOW)} and r.status = 'running'
                         order by r.created_at desc`);
if (!wf || !steps.length || !runs.length) { console.error('no running strategic_review run to probe'); process.exit(2); }

// One run per DISTINCT context by default: the context is what varies the need vector, and two runs
// created by the same goal.at_risk emission carry the same one.
const seen = new Set();
const picked = runs.filter(r => ALL || !seen.has(r.context) && seen.add(r.context) !== undefined);

let failures = 0, checks = 0;
for (const run of picked) {
  const ctx = String(run.context);
  console.log(`\nrun ${run.id}  context ${ctx.slice(0, 110)}${ctx.length > 110 ? '…' : ''}`);
  for (const s of steps) {
    const need = `${wf.name} — ${s.step} — ${ctx}`.slice(0, 1200);
    const qtext = `${wf.name} ${s.step}`;
    const vec = await embed(need);
    const [agentRow] = await sql(`select public.fn_workflow_actor_resolve(${lit(run.id)}::uuid, ${lit(s.actor_role)}) as employee`);
    const employee = agentRow?.employee;
    if (!employee) { console.log(`  step ${s.step_no}  FAIL actor ${s.actor_role} resolves to nobody`); failures++; checks++; continue; }
    const [res] = await sql(`select public.fn_apply_playbook(${lit(employee)}, '[${vec.join(',')}]'::vector(384),
                                                             ${lit(qtext)}, 0.85, 20) as r`);
    const d = res.r;
    checks++;
    const ok = d?.matched === true && d.record_id === EXPECT[s.step_no]
      && Number(d.similarity) >= 0.85 && Number(d.terms_matched) >= 2
      && Number(d.terms_matched) / Number(d.terms_total) >= 0.30
      && String(d.determination || '').length >= 300;
    if (!ok) failures++;
    console.log(`  step ${s.step_no} (${employee}) ${ok ? 'PASS' : 'FAIL'}  `
      + (d?.matched
        ? `${d.record_id} cos ${d.similarity} terms ${d.terms_matched}/${d.terms_total} `
          + `(${Math.round(100 * d.terms_matched / d.terms_total)}%) chars ${String(d.determination || '').length}`
        : `no match — ${String(d?.reason || '').slice(0, 200)}`));
  }
}

console.log(`\n${checks - failures}/${checks} step needs return the step's own company playbook `
  + `at cosine >= 0.85 with keyword corroboration, no model called`);
process.exit(failures ? 1 : 0);
