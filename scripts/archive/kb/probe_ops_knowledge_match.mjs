// Prove that fn_ops_knowledge_match returns a decision_playbook / decision_rule / exception_playbook
// BY MEANING for a department's real need, on production, with no model (MASTER_PLAN §4.2 / A4).
//
// Postgres cannot embed a sentence (gte-small lives in the Edge runtime), so the query vector comes
// from kb_embed's query mode — the same free in-region model that embedded the rows — and the cosine
// search runs in fn_ops_knowledge_match scoped to the agent. Nothing is written.
//
//   node scripts/archive/kb/probe_ops_knowledge_match.mjs                 # the five standing needs
//   node scripts/archive/kb/probe_ops_knowledge_match.mjs cs_support "customer asks for refund of the reveal fee"
import { sql } from '../../lib/db.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const STANDING = [
  ['supplier_verification', 'supplier trade licence expired what do we do'],
  ['cs_support',            'customer asks for refund of the reveal fee'],
  ['inquiry_router',        'RFQ found no matching suppliers'],
  ['marketing_analyst',     'ad spend exceeded the daily cap'],
  ['qa_manager',            'a test failed in CI'],
];
const cases = process.argv[2] ? [[process.argv[2], process.argv.slice(3).join(' ')]] : STANDING;

// The cron's own credential, read from the database and passed straight through — never printed.
const secret = (await sql(`select value from public.app_secrets where key = 'cred_cron_knowledge'`))[0]?.value;
if (!secret) { console.error('no cred_cron_knowledge in app_secrets'); process.exit(2); }

async function embed(query) {
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/kb_embed`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, query }) });
  const j = await r.json();
  if (!r.ok || !Array.isArray(j.embedding) || j.embedding.length !== 384) throw new Error(`kb_embed query mode: HTTP ${r.status} ${JSON.stringify(j).slice(0, 200)}`);
  return j.embedding;
}

let failures = 0;
for (const [agent, need] of cases) {
  const vec = await embed(need);
  const rows = await sql(`select record_type, title, round(similarity::numeric, 3) as similarity, dept_key
                            from public.fn_ops_knowledge_match('[${vec.join(',')}]'::vector(384), '${agent.replace(/'/g, "''")}', 8)`);
  // The applier's view: the same vector, restricted to the three playbook kinds it can apply.
  const kinds = await sql(`select record_type, title, round(similarity::numeric, 3) as similarity, dept_key
                             from public.fn_ops_knowledge_match('[${vec.join(',')}]'::vector(384), '${agent.replace(/'/g, "''")}', 3,
                                                                 array['decision_playbook','decision_rule','exception_playbook'])`);
  const hit = kinds[0];
  console.log(`\n${agent} :: "${need}" -> ${rows.length} rows unfiltered (k=8); nearest applicable: ${hit ? `${hit.record_type} @ ${hit.similarity}` : 'NONE'}`);
  for (const r of rows) console.log(`  ${String(r.similarity).padEnd(6)} ${r.record_type.padEnd(28)} ${r.dept_key ?? '-'}  ${r.title}`);
  console.log('  -- playbook/rule/exception kinds only (k=3):');
  for (const r of kinds) console.log(`  ${String(r.similarity).padEnd(6)} ${r.record_type.padEnd(28)} ${r.dept_key ?? '-'}  ${r.title}`);
  if (!hit || rows.length < 8) failures++;
}
console.log(`\n${cases.length - failures}/${cases.length} needs returned 8 unfiltered rows AND a decision_playbook/decision_rule/exception_playbook by meaning`);
process.exit(failures ? 1 : 0);
