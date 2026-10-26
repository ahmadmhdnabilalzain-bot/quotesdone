// import_pack3_csvs.mjs — the AI autonomy pack's four CSVs.
//
// The scorecard put AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS at 28.6% because only its 32 task
// classes had a table. The tool matrix (22), the recommended model catalogue (14) and the
// per-identity policies (96 target employees + 24 current agents) had nowhere to land.
//
//   node scripts/kb/import_pack3_csvs.mjs --ref=<project> --dir=<pack dir>
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), DIR = arg('dir');
if (!/^[a-z]{20}$/.test(REF) || !DIR) throw new Error('--ref and --dir are required');
const token = readFileSync(SUPABASE_TOKEN_FILE, 'utf8').trim();

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000) });
  const b = await r.text();
  if (!r.ok) { if (attempt < 4) { await new Promise(s => setTimeout(s, 1500 * 2 ** attempt)); return q(sql, attempt + 1); } throw new Error(r.status + ': ' + b.slice(0, 300)); }
  return JSON.parse(b);
}
const lit = (s) => "'" + String(s).replace(/\u0000/g, '').replace(/'/g, "''") + "'";

// RFC4180-ish: quoted fields, doubled quotes inside them, newlines inside quotes.
function parseCsv(text) {
  const rows = []; let row = [], field = '', inQ = false;
  const s = text.replace(/^\uFEFF/, '');
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inQ) {
      if (c === '"') { if (s[i + 1] === '"') { field += '"'; i++; } else inQ = false; }
      else field += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); field = ''; if (row.some(x => x !== '')) rows.push(row); row = []; }
    else if (c !== '\r') field += c;
  }
  row.push(field); if (row.some(x => x !== '')) rows.push(row);
  const head = rows.shift().map(h => h.trim());
  return rows.map(r => Object.fromEntries(head.map((h, i) => [h, (r[i] ?? '').trim()])));
}
const read = (f) => parseCsv(readFileSync(join(DIR, f), 'utf8'));
const num = (v) => (v === '' || v == null || isNaN(Number(v))) ? 'null' : Number(v);

const out = [];

// ---- tool / connector matrix
{
  const rs = read('02_TOOL_AND_CONNECTOR_MATRIX.csv');
  const vals = rs.map(r => `(${[r.tool, r.current_status, r.priority, r.required_before_launch,
    r.purpose, r.recommendation, r.code_dependency].map(lit).join(',')})`).join(',');
  await q(`insert into ai_tool_matrix (tool,current_status,priority,required_before_launch,purpose,recommendation,code_dependency)
           values ${vals}
           on conflict (tool) do update set current_status=excluded.current_status, priority=excluded.priority,
             required_before_launch=excluded.required_before_launch, purpose=excluded.purpose,
             recommendation=excluded.recommendation, code_dependency=excluded.code_dependency, imported_at=now();`);
  out.push(['ai_tool_matrix', rs.length, Number((await q('select count(*) n from ai_tool_matrix'))[0].n)]);
}

// ---- recommended model catalogue
{
  const rs = read('03_MODEL_CATALOG_RECOMMENDED.csv');
  const vals = rs.map(r => `(${lit(r.model_id)},${lit(r.role)},${num(r.price_input_usd_per_m)},${num(r.price_output_usd_per_m)},${lit(r.context)},${lit(r.best_for)},${lit(r.deployment_note)})`).join(',');
  await q(`insert into model_catalog (model_id,tier_role,price_input_usd_per_m,price_output_usd_per_m,context,best_for,deployment_note)
           values ${vals}
           on conflict (model_id) do update set tier_role=excluded.tier_role,
             price_input_usd_per_m=excluded.price_input_usd_per_m, price_output_usd_per_m=excluded.price_output_usd_per_m,
             context=excluded.context, best_for=excluded.best_for, deployment_note=excluded.deployment_note, imported_at=now();`);
  out.push(['model_catalog', rs.length, Number((await q('select count(*) n from model_catalog'))[0].n)]);
}

// ---- per-identity policies: 96 target employees + 24 current production agents
{
  const emp = read('05_MODEL_POLICY_BY_96_TARGET_EMPLOYEES.csv').map(r => ({ ...r, scope: 'target_employee' }));
  const cur = read('06_MODEL_POLICY_BY_CURRENT_PRODUCTION_AGENTS.csv').map(r => ({ ...r, scope: 'current_agent' }));
  for (const rs of [emp, cur]) {
    const vals = rs.map(r => `(${lit(r.agent_key)},${lit(r.scope)},${lit(r.department ?? '')},${lit(r.title ?? '')},
      ${lit(r.deterministic_first ?? '')},${lit(r.primary_model ?? '')},${lit(r.fallback_model ?? '')},
      ${lit(r.escalation_model ?? '')},${num(r.max_output_tokens)},${lit(r.reasoning_effort ?? '')},
      ${lit(r.manager ?? '')},${lit(r.authority_tier ?? '')},${lit(r.note ?? '')})`).join(',');
    await q(`insert into model_policy_by_identity (identity_key,scope,department,title,deterministic_first,
               primary_model,fallback_model,escalation_model,max_output_tokens,reasoning_effort,manager,authority_tier,note)
             values ${vals}
             on conflict (identity_key,scope) do update set department=excluded.department, title=excluded.title,
               deterministic_first=excluded.deterministic_first, primary_model=excluded.primary_model,
               fallback_model=excluded.fallback_model, escalation_model=excluded.escalation_model,
               max_output_tokens=excluded.max_output_tokens, reasoning_effort=excluded.reasoning_effort,
               manager=excluded.manager, authority_tier=excluded.authority_tier, note=excluded.note, imported_at=now();`);
  }
  out.push(['model_policy_by_identity target_employee', emp.length,
    Number((await q(`select count(*) n from model_policy_by_identity where scope='target_employee'`))[0].n)]);
  out.push(['model_policy_by_identity current_agent', cur.length,
    Number((await q(`select count(*) n from model_policy_by_identity where scope='current_agent'`))[0].n)]);
}

console.log(`\n${REF}`);
for (const [t, disk, db] of out) console.log(`  ${t.padEnd(42)} disk ${String(disk).padStart(4)}  db ${String(db).padStart(4)}  ${disk === db ? 'OK' : 'MISMATCH'}`);
