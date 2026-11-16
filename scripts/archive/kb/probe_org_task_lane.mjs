// Prove the ORG_TASK LANE retrieves by meaning, on production, with no model (MASTER_PLAN A1 / §4.3).
//
// This is the dispatcher's own retrieval, run read-only: for a sample of open org_tasks per cluster it
// embeds exactly what workflow_dispatch embeds (title + detail, 1200 chars) through kb_embed's query
// mode — the same free in-region gte-small that embedded the records — and calls fn_apply_playbook with
// exactly the corroboration text fn_org_task_subject computes. Nothing is written.
//
//   node scripts/archive/kb/probe_org_task_lane.mjs            # 5 open tasks per (event, department) cluster
//   node scripts/archive/kb/probe_org_task_lane.mjs 3          # n per cluster
//   node scripts/archive/kb/probe_org_task_lane.mjs 5 kpi      # only clusters whose event matches
import { sql } from '../../lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const PER = Math.max(1, Math.min(Number(process.argv[2]) || 5, 20));
const FILTER = (process.argv[3] || '').toLowerCase();

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

// n open tasks per cluster, exactly as the lane sees them: the agent the run would address, the
// embedding text, and the corroboration subject the claim computes.
const q = `
  with c as (
    select t.*,
           case when t.title like '% on %' then split_part(t.title,' on ',1)
                when t.title like 'KPI missed%' then 'KPI missed'
                when t.title like 'OS review%' then 'OS review'
                when t.title like 'Exec meeting%' then 'Exec meeting'
                else left(t.title, 24) end as cluster,
           row_number() over (partition by
             case when t.title like '% on %' then split_part(t.title,' on ',1)
                  when t.title like 'KPI missed%' then 'KPI missed'
                  when t.title like 'OS review%' then 'OS review'
                  when t.title like 'Exec meeting%' then 'Exec meeting'
                  else left(t.title, 24) end, t.dept_key order by t.id) rn
      from public.org_tasks t
     where t.status in ('assigned','in_progress')
  )
  select c.id, c.cluster, c.dept_key, c.action_class, c.title, coalesce(c.detail,'') detail,
         coalesce(c.assigned_agent, d.brain_agent, d.lead_agent, c.dept_key) as agent,
         public.fn_org_task_subject(c.title, c.action_class, c.dept_key) as subject
    from c left join public.org_departments d on d.dept_key = c.dept_key
   where c.rn <= ${PER}
   order by c.cluster, c.dept_key, c.id`;

const tasks = await sql(q);
const rows = FILTER ? tasks.filter((t) => String(t.cluster).toLowerCase().includes(FILTER)) : tasks;
console.log(`${rows.length} open org_task(s) sampled, up to ${PER} per (cluster, department)\n`);

// The management API rate-limits per statement, not per row, so the appliers run in batches: one
// statement carrying N (vector, subject, agent) triples. The vectors still come one at a time from
// kb_embed, which is the free in-region model and is not the limited surface.
const lit = (s) => `'${String(s ?? '').replace(/'/g, "''")}'`;
const BATCH = 8;
const per = new Map();
let matched = 0;
for (let i = 0; i < rows.length; i += BATCH) {
  const slice = rows.slice(i, i + BATCH);
  const parts = [];
  for (const t of slice) {
    const need = (String(t.title) + ' — ' + String(t.detail)).slice(0, 1200);
    const vec = await embed(need);
    parts.push(`select ${t.id}::bigint as id, public.fn_apply_playbook(${lit(t.agent)},
        '[${vec.join(',')}]'::vector(384), ${lit(t.subject)}, 0.85, 20) as r`);
  }
  const out = await sql(parts.join('\nunion all\n'));
  const byId = new Map(out.map((o) => [String(o.id), o.r]));
  for (const t of slice) {
    const r = byId.get(String(t.id)) || { matched: false, reason: 'no row returned' };
    const key = `${t.cluster} / ${t.dept_key}`;
    const acc = per.get(key) || { n: 0, ok: 0, sims: [] };
    acc.n++;
    if (r.matched) {
      acc.ok++; matched++;
      acc.sims.push(Number(r.similarity));
      console.log(`  OK   #${t.id} ${key}  sim ${r.similarity}  terms ${r.terms_matched}/${r.terms_total}  -> ${String(r.title).slice(0, 70)}`);
    } else {
      console.log(`  MISS #${t.id} ${key}  ${String(r.reason).slice(0, 170)}`);
    }
    per.set(key, acc);
  }
}

console.log('\n--- per cluster/department ---');
for (const [k, v] of [...per.entries()].sort()) {
  const lo = v.sims.length ? Math.min(...v.sims).toFixed(3) : '-';
  const hi = v.sims.length ? Math.max(...v.sims).toFixed(3) : '-';
  console.log(`  ${v.ok}/${v.n}  ${k.padEnd(46)} cosine ${lo}..${hi}`);
}
console.log(`\n${matched}/${rows.length} sampled tasks retrieve a CORROBORATED actionable playbook at cosine >= 0.85`);
process.exit(matched === rows.length ? 0 : 1);
