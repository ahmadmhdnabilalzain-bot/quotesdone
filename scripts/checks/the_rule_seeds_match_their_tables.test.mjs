// THE RULE SEEDS MATCH THEIR TABLES (21 Sep 2026, sales_engineer).
//
// Two consumers read the codified trade rules and they must never disagree:
//   * SQL — trade_scope_line, spec_equivalence, trade_comparability, trade_approval and the
//     red_flag_* columns of price_benchmark, seeded by
//     scripts/sql/the_comparison_engine_executes_codified_trade_rules.sql and served to
//     quote_compare by fn_trade_rules;
//   * the edge runtime and its tests — supabase/functions/_shared/rules/<trade>.json, read by
//     _shared/line_specs/rules.ts (rules.test.ts, the sandbox proof).
//
// The SQL seed is RENDERED from the JSON by scripts/lib/trade_rules_sql.mjs, so this check re-renders
// it and asserts the SQL file carries exactly that text. A FILE check (no database), so it runs in CI
// without a token. Same pattern as the_implication_map_has_one_seed.test.mjs.
//
//   node --test scripts/checks/the_rule_seeds_match_their_tables.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readRules, renderSeed, rulesPath } from '../lib/trade_rules_sql.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL_FILE = 'scripts/sql/the_comparison_engine_executes_codified_trade_rules.sql';
const sql = fs.readFileSync(path.join(ROOT, SQL_FILE), 'utf8');
const AR = /[ء-ي]/;
const DECISIONS = new Set(['hold_quote', 'flag_substitution', 'flag_omission', 'flag_price', 'not_comparable', 'approval_required', 'route_inquiry', 'recognise_service']);
const LABELS = new Set(['law', 'practice', 'manufacturer_data']);
const LICENCES = new Set(['government', 'licensed_standard', 'manufacturer_public', 'quotesdone']);

const TRADES = fs.readdirSync(path.dirname(rulesPath('x'))).filter((f) => f.endsWith('.json')).map((f) => f.replace(/\.json$/, ''));

test('every authored trade has its rendered seed in the SQL file, verbatim', () => {
  assert.ok(TRADES.length >= 1, 'no rules files under supabase/functions/_shared/rules');
  for (const trade of TRADES) {
    const seed = renderSeed(readRules(trade));
    assert.ok(sql.includes(seed), `the SQL seed for ${trade} is not the rendering of ${trade}.json — re-run: node scripts/lib/trade_rules_sql.mjs ${trade}`);
  }
});

test('every rule row passes the five admission tests of the doctrine', () => {
  for (const trade of TRADES) {
    const r = readRules(trade);
    assert.equal(r.trade_code, trade, `${trade}.json names another trade`);
    const rows = [...r.scope_lines, ...r.equivalence, ...r.price_flags, ...r.comparability, ...r.approvals];
    assert.ok(rows.length >= 20, `${trade}: only ${rows.length} rules — not technical-director depth`);
    for (const x of rows) {
      const where = `${trade}: ${JSON.stringify(x).slice(0, 90)}`;
      assert.ok(DECISIONS.has(x.decision), `${where} — decision not in the enum (test 1)`);
      assert.ok(/^(UAE|GCC|Dubai|Abu Dhabi|Sharjah|Ajman|Ras Al Khaimah|Fujairah|Umm Al Quwain)$/.test(x.jurisdiction), `${where} — jurisdiction not UAE/GCC/emirate (test 2)`);
      assert.ok(typeof x.citation === 'string' && x.citation.trim().length >= 15, `${where} — no citation (test 3)`);
      assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(String(x.effective_date)), `${where} — no effective_date (test 3)`);
      assert.ok(typeof x.rule_en === 'string' && x.rule_en.trim().length >= 20 && !AR.test(x.rule_en), `${where} — rule_en missing or not English (test 4)`);
      assert.ok(typeof x.rule_ar === 'string' && AR.test(x.rule_ar) && x.rule_ar !== x.rule_en, `${where} — rule_ar missing or not Arabic (test 4)`);
      assert.ok(LICENCES.has(x.licence), `${where} — licence not in the enum (test 5)`);
      assert.ok(LABELS.has(x.label), `${where} — label not law/practice/manufacturer_data`);
    }
    for (const s of r.scope_lines) { assert.ok(AR.test(s.line_ar) && s.line_en, `${trade}.${s.line_key}: line name not bilingual`); new RegExp(s.proof_regex_en, 'iu'); new RegExp(s.proof_regex_ar, 'iu'); if (s.applies_regex) new RegExp(s.applies_regex, 'iu'); }
    for (const a of r.approvals) assert.ok(AR.test(a.approval_ar) && a.approval_en, `${trade}: approval not bilingual`);
    for (const c of r.comparability) { assert.ok(c.required_attrs.length > 0); new RegExp(c.line_regex, 'iu'); }
    // A brand class member is admitted only on evidence; an unverified one is authored inactive, never live.
    for (const e of r.equivalence.filter((x) => x.attr_code === 'brand')) assert.ok(e.approval_ref, `${trade}: brand ${e.value} carries no evidence reference`);
  }
});

test('the SQL file states what it measured and carries the discipline items', () => {
  assert.ok(/MEASURED BEFORE THIS FILE/.test(sql) && /WHAT THIS CHANGES/.test(sql) && /NOT CHANGED/.test(sql));
  assert.ok(/set search_path to 'public', 'pg_temp'/.test(sql), 'fn_trade_rules has no pinned search_path');
  assert.ok(/revoke all on function public\.fn_trade_rules\(text\) from public, anon, authenticated/.test(sql), 'fn_trade_rules is not revoked');
  for (const t of ['trade_scope_line', 'spec_equivalence', 'trade_comparability', 'trade_approval']) {
    assert.ok(sql.includes(`alter table public.${t}`) && sql.includes(`enable row level security`), `${t}: RLS not enabled`);
    assert.ok(sql.includes(`create policy ${t}_service_role_only`), `${t}: no policy`);
  }
  assert.ok(/'PROBE OK'/.test(sql) && /'PROBE FAILED'/.test(sql) && !/raise notice/i.test(sql), 'the probe must return a verdict row');
  const manifest = fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).filter(Boolean);
  assert.equal(manifest[manifest.length - 1].trim(), SQL_FILE, 'the SQL file is not the last MANIFEST line');
});
