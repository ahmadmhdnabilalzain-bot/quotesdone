// The last 2,537 records of the 86-category corpus.
//
// Packages 002-007 ship 13_decision_rules.jsonl in a NATIVE rule shape — {rule_id, category_slug,
// subcategory_slug, priority, rule_type, when, then, source_ids, confidence,
// requires_human_review, version} — with no record_id, no title and no content. The
// knowledge-record importer validates against knowledge-record-v1.json and correctly rejected all
// 2,537, so kb_stage.records held 112,611 of the corpus's 115,148.
//
// They were never lost (all 2,537 are in kb_stage.decision_rules), but they were not RETRIEVABLE:
// fn_kb_retrieve reads kb_stage.records, so six categories' decision rules could not be found by
// the routine that answers questions about them.
//
// NOTHING IS INVENTED. record_id is derived deterministically from the pack's own stable rule_id;
// title and content are a faithful rendering of the rule's own when/then; the untouched original
// is kept in structured_data. Re-running produces byte-identical rows.
//
//   node scripts/kb/import_native_rules_as_records.mjs --ref=<project> --root=<_kbpkgs dir>
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), ROOT = arg('root');
if (!/^[a-z]{20}$/.test(REF) || !ROOT) throw new Error('--ref and --root are required');
const token = readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8').trim();

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180000) });
  const b = await r.text();
  if (!r.ok) { if (attempt < 5) { await new Promise(s => setTimeout(s, 1500 * 2 ** attempt)); return q(sql, attempt + 1); } throw new Error(r.status + ': ' + b.slice(0, 300)); }
  return JSON.parse(b);
}
const lit = (s) => "'" + s.replace(/\u0000/g, '').replace(/'/g, "''") + "'";
const sha = (s) => createHash('sha256').update(s).digest('hex');
const words = (s) => String(s).replace(/[_-]+/g, ' ').trim();

const rows = [];
for (const d of readdirSync(ROOT, { withFileTypes: true })) {
  if (!d.isDirectory()) continue;
  const pkg = d.name.match(/^(QD-KB-\d+)/)?.[1]; if (!pkg) continue;
  let text; try { text = readFileSync(join(ROOT, d.name, '13_decision_rules.jsonl'), 'utf8'); } catch { continue; }
  for (const line of text.split('\n')) {
    const s = line.trim(); if (!s) continue;
    const o = JSON.parse(s);
    if (o.record_id || !o.rule_id) continue;              // record-shaped rows are already imported
    const when = JSON.stringify(o.when ?? {});
    const then = JSON.stringify(o.then ?? {});
    const content =
      `Decision rule ${o.rule_id} for ${words(o.category_slug)}` +
      (o.subcategory_slug ? ` / ${words(o.subcategory_slug)}` : '') +
      `. Rule type: ${o.rule_type ?? 'unspecified'}. Priority: ${o.priority ?? 'unset'}. ` +
      `WHEN ${when} THEN ${then}. ` +
      `Human review required: ${o.requires_human_review ? 'yes' : 'no'}.`;
    rows.push({
      record_id: `kb-rule-${o.rule_id}`,
      category_slug: o.category_slug,
      subcategory_slug: o.subcategory_slug ?? 'general',
      module: 'inquiry_qualification',
      record_type: 'decision_rule',
      title: `Decision rule: ${words(o.rule_id)}`.slice(0, 300),
      content,
      structured_data: o,                                  // the original, untouched
      jurisdiction: null, authority: null,
      source_ids: o.source_ids ?? [],
      effective_date: null, superseded_date: null,
      version: o.version ?? '1.0.0',
      confidence: (typeof o.confidence === 'number' && o.confidence >= 0 && o.confidence <= 1) ? o.confidence : null,
      validation_status: 'draft',
      review_after: null,
      keywords_en: [], keywords_ar: [], applies_when: o.when ?? null, exceptions: [],
      escalation_rule: o.requires_human_review ? { requires_human_review: true } : null,
      package_id: pkg,
      content_sha256: sha(content),
    });
  }
}
const COLS = ['record_id','category_slug','subcategory_slug','module','record_type','title','content',
  'structured_data','jurisdiction','authority','source_ids','effective_date','superseded_date','version',
  'confidence','validation_status','review_after','keywords_en','keywords_ar','applies_when','exceptions',
  'escalation_rule','package_id','content_sha256'];
const TYPES = 'record_id text, category_slug text, subcategory_slug text, module text, record_type text, ' +
  'title text, content text, structured_data jsonb, jurisdiction text, authority text, source_ids jsonb, ' +
  'effective_date text, superseded_date text, version text, confidence numeric, validation_status text, ' +
  'review_after text, keywords_en jsonb, keywords_ar jsonb, applies_when jsonb, exceptions jsonb, ' +
  'escalation_rule jsonb, package_id text, content_sha256 text';

const before = Number((await q('select count(*) n from kb_stage.records'))[0].n);
let ins = 0, upd = 0;
for (let i = 0; i < rows.length; i += 300) {
  const r = await q(
    `with src as (select * from jsonb_to_recordset(${lit(JSON.stringify(rows.slice(i, i + 300)))}::jsonb) as x(${TYPES})),
     w as (insert into kb_stage.records (${COLS.join(',')}) select ${COLS.join(',')} from src
           on conflict (record_id) do update set ${COLS.filter(c => c !== 'record_id').map(c => `${c}=excluded.${c}`).join(',')}, updated_at=now()
           returning (xmax = 0) fresh)
     select count(*) filter (where fresh) inserted, count(*) filter (where not fresh) updated from w;`);
  ins += Number(r[0].inserted); upd += Number(r[0].updated);
}
const after = Number((await q('select count(*) n from kb_stage.records'))[0].n);
console.log(`${REF}: native rules ${rows.length} | inserted ${ins} updated ${upd} | kb_stage.records ${before} -> ${after}`);
