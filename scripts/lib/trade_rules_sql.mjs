// trade_rules_sql.mjs — renders one trade's rule file (supabase/functions/_shared/rules/<trade>.json)
// into the SQL seed block that scripts/sql/the_comparison_engine_executes_codified_trade_rules.sql
// carries verbatim. ONE SEED: the JSON is the authoring surface the edge runtime reads; the SQL is
// what fn_trade_rules serves. scripts/checks/the_rule_seeds_match_their_tables.test.mjs re-renders
// the JSON and asserts the SQL file contains exactly this text, so the two cannot drift.
//
//   node scripts/lib/trade_rules_sql.mjs gypsum      # prints the seed block
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const rulesPath = (trade) => path.join(ROOT, 'supabase', 'functions', '_shared', 'rules', `${trade}.json`);
export const readRules = (trade) => JSON.parse(fs.readFileSync(rulesPath(trade), 'utf8'));

const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const b = (v) => (v === false ? 'false' : 'true');
const arr = (a) => `array[${a.map(q).join(',')}]::text[]`;
const shared = (r) => [q(r.decision), q(r.label), q(r.jurisdiction), q(r.citation), q(r.effective_date), q(r.expires_on), q(r.licence), q(r.rule_en), q(r.rule_ar), q(r.source_ref), b(r.active)].join(',');
export const SHARED_COLS = 'decision, label, jurisdiction, citation, effective_date, expires_on, licence, rule_en, rule_ar, source_ref, active';

export function renderSeed(rules) {
  const t = q(rules.trade_code);
  const out = [];
  out.push(`-- ==== SEED ${rules.trade_code} (rendered from supabase/functions/_shared/rules/${rules.trade_code}.json by scripts/lib/trade_rules_sql.mjs; do not hand-edit) ====`);
  out.push(`delete from public.trade_scope_line where trade_code = ${t};`);
  out.push(`insert into public.trade_scope_line (trade_code, job_type, line_key, line_en, line_ar, kind, proof_regex_en, proof_regex_ar, applies_regex, ${SHARED_COLS}) values`);
  out.push(rules.scope_lines.map((r) => `  (${t},${q(r.job_type ?? '')},${q(r.line_key)},${q(r.line_en)},${q(r.line_ar)},${q(r.kind)},${q(r.proof_regex_en)},${q(r.proof_regex_ar)},${q(r.applies_regex)},${shared(r)})`).join(',\n') + ';');
  out.push(`delete from public.spec_equivalence where trade_code = ${t};`);
  out.push(`insert into public.spec_equivalence (trade_code, attr_code, class_key, value, equivalent, evidence_kind, approval_ref, approval_expires, ${SHARED_COLS}) values`);
  out.push(rules.equivalence.map((r) => `  (${t},${q(r.attr_code)},${q(r.class_key)},${q(r.value)},${b(r.equivalent)},${q(r.evidence_kind)},${q(r.approval_ref)},${q(r.approval_expires)},${shared(r)})`).join(',\n') + ';');
  out.push(`delete from public.trade_comparability where trade_code = ${t};`);
  out.push(`insert into public.trade_comparability (trade_code, line_type, line_regex, required_attrs, ${SHARED_COLS}) values`);
  out.push(rules.comparability.map((r) => `  (${t},${q(r.line_type)},${q(r.line_regex)},${arr(r.required_attrs)},${shared(r)})`).join(',\n') + ';');
  out.push(`delete from public.trade_approval where trade_code = ${t};`);
  out.push(`insert into public.trade_approval (trade_code, emirate, authority, approval_en, approval_ar, stage, evidence_doc, cost_bearer, applies_regex, ${SHARED_COLS}) values`);
  out.push(rules.approvals.map((r) => `  (${t},${q(r.emirate)},${q(r.authority)},${q(r.approval_en)},${q(r.approval_ar)},${q(r.stage)},${q(r.evidence_doc)},${q(r.cost_bearer)},${q(r.applies_regex)},${shared(r)})`).join(',\n') + ';');
  // Price red flags live ON price_benchmark (doctrine section 7): trade_code + the reason per band row.
  for (const r of rules.price_flags) {
    out.push(`update public.price_benchmark set trade_code = ${t}, line_regex = ${q(r.line_regex)}, red_flag_reason_en = ${q(r.rule_en)}, red_flag_reason_ar = ${q(r.rule_ar)}, red_flag_citation = ${q(r.citation)}, red_flag_effective_date = ${q(r.effective_date)}, red_flag_expires_on = ${q(r.expires_on)}, red_flag_label = ${q(r.label)}, red_flag_licence = ${q(r.licence)} where id = ${Number(r.benchmark_id)} and item = ${q(r.item)} and unit = ${q(r.unit)} and low = ${Number(r.low)} and high = ${Number(r.high)};`);
  }
  out.push(`-- ==== END SEED ${rules.trade_code} ====`);
  return out.join('\n');
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  process.stdout.write(renderSeed(readRules(process.argv[2] || 'gypsum')) + '\n');
}
