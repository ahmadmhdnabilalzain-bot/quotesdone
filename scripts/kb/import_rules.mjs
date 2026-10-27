// import_rules.mjs — the native-shape decision rules the record importer cannot carry.
//
// Six of the 67 packages (002-007) ship 13_decision_rules.jsonl in a NATIVE rule shape —
// {rule_id, category_slug, subcategory_slug, priority, rule_type, when, then, source_ids,
// confidence, requires_human_review, version} — with no record_id, no title and no content.
// The knowledge-record importer validates against knowledge-record-v1.json, so it rejected
// every one of them. They are not malformed; they are a different, well-formed shape, and
// 63 of the 67 packages carry some.
//
// They land in kb_stage.decision_rules with record_id null, which is where production already
// holds 5,862 of them. Staging holds only 2,537 — this closes that gap from the corpus rather
// than by copying production, so the corpus stays the single source of truth.
//
//   node scripts/kb/import_rules.mjs --ref=<project> --root=<extracted _kbpkgs dir> [--dry]
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), ROOT = arg('root');
const DRY = process.argv.includes('--dry');
if (!/^[a-z]{20}$/.test(REF) || !ROOT) throw new Error('--ref and --root are required');
const token = supabaseAccessToken();

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
async function q(sql, attempt = 0) {
  let r, body;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180_000),
    });
    body = await r.text();
  } catch (e) {
    if (attempt < 6) { await sleep(1500 * 2 ** attempt); return q(sql, attempt + 1); }
    throw new Error(`transport failed: ${e.message}`);
  }
  if ([429, 500, 502, 503, 504].includes(r.status) && attempt < 6) {
    await sleep(1500 * 2 ** attempt); return q(sql, attempt + 1);
  }
  if (!r.ok) throw new Error(`management API ${r.status}: ${body.slice(0, 400)}`);
  return body ? JSON.parse(body) : null;
}
const lit = (s) => "'" + s.replace(/\u0000/g, '').replace(/'/g, "''") + "'";

const rows = [];
let seen = 0, rejected = 0;
const rejectSamples = [];
for (const d of readdirSync(ROOT, { withFileTypes: true })) {
  if (!d.isDirectory()) continue;
  const f = join(ROOT, d.name, '13_decision_rules.jsonl');
  let text; try { text = readFileSync(f, 'utf8'); } catch { continue; }
  for (const line of text.split('\n')) {
    const s = line.trim(); if (!s) continue;
    let o; try { o = JSON.parse(s); } catch { rejected++; continue; }
    if (o.record_id) continue;                       // knowledge-record shape: already imported
    seen++;
    if (!o.rule_id || !o.category_slug) {
      rejected++;
      if (rejectSamples.length < 10) rejectSamples.push(`${d.name} missing rule_id/category_slug`);
      continue;
    }
    rows.push({
      rule_id: o.rule_id,
      category_slug: o.category_slug,
      subcategory_slug: o.subcategory_slug ?? '',
      rule_type: o.rule_type ?? null,
      priority: o.priority ?? null,
      when_json: o.when ?? null,
      then_json: o.then ?? null,
      source_ids: o.source_ids ?? [],
      confidence: o.confidence ?? null,
      requires_human_review: o.requires_human_review ?? false,
      version: o.version ?? '1.0.0',
      payload: o,
    });
  }
}
const ids = new Set(rows.map(r => r.rule_id));
console.log(`target ref = ${REF}`);
console.log(`native-shape rules on disk: ${seen}   valid: ${rows.length}   distinct rule_id: ${ids.size}   rejected: ${rejected}`);
if (rejectSamples.length) console.log('rejects: ' + rejectSamples.join('; '));

const before = Number((await q(`select count(*)::bigint n from kb_stage.decision_rules where record_id is null;`))[0].n);
const total0 = Number((await q(`select count(*)::bigint n from kb_stage.decision_rules;`))[0].n);
console.log(`kb_stage.decision_rules before: ${total0} total, ${before} with record_id null`);
if (DRY) { console.log('--dry: nothing written'); process.exit(0); }

const COLS = ['rule_id', 'category_slug', 'subcategory_slug', 'rule_type', 'priority', 'when_json',
  'then_json', 'source_ids', 'confidence', 'requires_human_review', 'version', 'payload'];
const TYPES = 'rule_id text, category_slug text, subcategory_slug text, rule_type text, priority int, ' +
  'when_json jsonb, then_json jsonb, source_ids jsonb, confidence numeric, ' +
  'requires_human_review boolean, version text, payload jsonb';

let ins = 0, upd = 0;
for (let i = 0; i < rows.length; i += 400) {
  const batch = rows.slice(i, i + 400);
  const r = await q(
    `with src as (select * from jsonb_to_recordset(${lit(JSON.stringify(batch))}::jsonb) as x(${TYPES})),
     w as (insert into kb_stage.decision_rules (${COLS.join(',')})
           select ${COLS.join(',')} from src
           on conflict (rule_id) do update set
             ${COLS.filter(c => c !== 'rule_id').map(c => `${c}=excluded.${c}`).join(', ')}
           returning (xmax = 0) as fresh)
     select count(*) filter (where fresh) inserted, count(*) filter (where not fresh) updated from w;`);
  ins += Number(r[0].inserted); upd += Number(r[0].updated);
  process.stdout.write(`\r  ${i + batch.length}/${rows.length}  inserted=${ins} updated=${upd}   `);
}
const total1 = Number((await q(`select count(*)::bigint n from kb_stage.decision_rules;`))[0].n);
const after = Number((await q(`select count(*)::bigint n from kb_stage.decision_rules where record_id is null;`))[0].n);
console.log(`\nkb_stage.decision_rules after: ${total1} total, ${after} with record_id null`);
console.log(`inserted ${ins}  updated ${upd}  net +${total1 - total0}`);
