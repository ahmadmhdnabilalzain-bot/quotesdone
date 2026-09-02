// Ingest senior-expert deep operating knowledge (authored as JSONL, one file per department) into
// ops_knowledge, department-scoped, so fn_ops_knowledge_match retrieves it by MEANING for every agent
// in that department. Idempotent: record_id is deterministic on (dept,title); a changed content
// checksum resets embedding so the backfill re-embeds it. No schema change — each record's layer maps
// onto the existing ops_knowledge_layer_ck allow-list; the domain identity lives in dept_key.
//
//   node scripts/kb/ingest_deep_knowledge.mjs            # ingest every <dept>.jsonl present
//   node scripts/kb/ingest_deep_knowledge.mjs finance    # just one
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { sql } from '../phase_c/lib/db.mjs';

// Version-controlled source of truth for the deep expert knowledge, re-ingestable on any machine.
const KNOWLEDGE_DIR = join(dirname(fileURLToPath(import.meta.url)), 'deep_knowledge');
// filename (without .jsonl) MUST be a real org_departments.dept_key
const only = process.argv[2] || null;

function loadFile(dept) {
  const path = `${KNOWLEDGE_DIR}/${dept}.jsonl`;
  if (!existsSync(path)) return null;
  const rows = [];
  const errs = [];
  readFileSync(path, 'utf8').split('\n').forEach((ln, i) => {
    const t = ln.trim(); if (!t) return;
    let o; try { o = JSON.parse(t); } catch (e) { errs.push(`line ${i + 1}: ${e.message}`); return; }
    // shape guard — skip anything that is not a usable expert record
    if (!o.title || !o.content || String(o.content).length < 120) { errs.push(`line ${i + 1}: missing/short title|content`); return; }
    rows.push({
      dept,
      title: String(o.title).slice(0, 300),
      content: String(o.content).slice(0, 6000),
      record_type: String(o.record_type || 'decision_playbook'),
      authority_tier: String(o.authority_tier || 'operational'),
      jurisdiction: String(o.jurisdiction || 'UAE'),
      keywords: Array.isArray(o.keywords) ? o.keywords.map(k => String(k).slice(0, 40)).slice(0, 12) : [],
    });
  });
  return { rows, errs };
}

async function ingest(dept, rows) {
  const json = JSON.stringify(rows);
  // dollar-quote the payload so no single-quote escaping is needed; guard against tag collision.
  const tag = '$ingest_' + Date.now() + '$';
  if (json.includes(tag)) throw new Error('payload contains the dollar tag — retry');
  const q = `
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content,
  structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
  version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness, confidentiality,
  runtime_eligible, deterministic, supersession_state, embedding_status, layer, effective_date,
  checksum, source_type, source_authority)
select
  'ops-'||(e->>'dept')||'-deep-'||substr(md5((e->>'dept')||(e->>'title')),1,20),
  'department', e->>'dept', e->>'dept', (e->>'dept')||'_expert', e->>'record_type',
  e->>'title', e->>'content',
  '{}'::jsonb, '{}'::text[], 'active', 'author_verified',
  case e->>'authority_tier' when 'governing' then 'gated' when 'operational' then 'supervised' else 'advisory' end,
  case e->>'authority_tier' when 'governing' then 'high' when 'operational' then 'medium' else 'low' end,
  '1.0',
  array(select jsonb_array_elements_text(e->'keywords')), '{}'::text[], '{}'::jsonb,
  case e->>'jurisdiction' when 'UAE' then 'AE' when 'GCC' then 'GCC' else 'INTL' end,
  'current', 'internal', true, false, 'current', 'pending',
  case e->>'record_type'
    when 'reference' then 'source_reference' when 'decision_playbook' then 'decision_playbook'
    when 'failure_mode' then 'failure_mode' when 'authority' then 'authority'
    when 'policy' then 'policy' when 'remediation' then 'remediation' when 'kpi' then 'kpi'
    else 'decision_playbook' end,
  current_date, md5(e->>'content'), 'authored_expert', 'senior_expert_uae'
from jsonb_array_elements(${tag}${json}${tag}::jsonb) e
on conflict (record_id) do update set
  content = excluded.content, title = excluded.title, keywords = excluded.keywords,
  record_type = excluded.record_type, layer = excluded.layer, authority_tier = excluded.authority_tier,
  risk_level = excluded.risk_level,
  embedding_gte = case when public.ops_knowledge.checksum is distinct from excluded.checksum then null else public.ops_knowledge.embedding_gte end,
  embedding_status = case when public.ops_knowledge.checksum is distinct from excluded.checksum then 'pending' else public.ops_knowledge.embedding_status end,
  checksum = excluded.checksum
returning 1`;
  const r = await sql(q);
  return r.length;
}

const depts = only ? [only]
  : readdirSync(KNOWLEDGE_DIR).filter(f => f.endsWith('.jsonl')).map(f => f.replace(/\.jsonl$/, ''));

// dept_key must exist and be active
const valid = new Set((await sql(`select dept_key from public.org_departments`)).map(r => r.dept_key));
let total = 0;
for (const dept of depts) {
  if (!valid.has(dept)) { console.log(`SKIP ${dept}: not a real dept_key`); continue; }
  const f = loadFile(dept);
  if (!f) { console.log(`SKIP ${dept}: no file`); continue; }
  if (f.errs.length) console.log(`  ${dept}: ${f.errs.length} bad line(s): ${f.errs.slice(0, 3).join(' | ')}`);
  if (!f.rows.length) { console.log(`SKIP ${dept}: 0 usable rows`); continue; }
  const n = await ingest(dept, f.rows);
  total += n;
  console.log(`INGESTED ${dept}: ${n} rows`);
}
console.log(`\nTOTAL upserted: ${total}`);
process.exit(0);
