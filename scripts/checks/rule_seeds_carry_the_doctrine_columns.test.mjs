// EVERY RULE SEED CARRIES THE DOCTRINE COLUMNS (21 Sep 2026, sales_engineer).
//
// docs/KNOWLEDGE_DOCTRINE.md section 1 lists five admission tests and section 7 makes them
// constraints on every rule table. The seeds in supabase/functions/_shared/rules/<trade>.json are
// the authoring surface for those tables, so a seed row that would fail a CHECK must fail here,
// in CI, before anyone tries to apply it. Measured on the first four seeds (electrical, steel,
// fire_fighting, hvac): the mistakes a writer actually makes are an Arabic column pasted from the
// English, an enum value spelt from memory, and a date left as a year. All three are caught below.
//
// FILE check only (no database, no token) — it runs in the CI `checks` job.
//
//   node --test scripts/checks/rule_seeds_carry_the_doctrine_columns.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = path.join(ROOT, 'supabase', 'functions', '_shared', 'rules');

// The doctrine's enums, section 7 verbatim.
const DECISION = new Set(['hold_quote', 'flag_substitution', 'flag_omission', 'flag_price', 'not_comparable', 'approval_required', 'route_inquiry', 'recognise_service']);
const LABEL = new Set(['law', 'practice', 'manufacturer_data']);
const LICENCE = new Set(['government', 'licensed_standard', 'manufacturer_public', 'quotesdone']);
const SCOPE_KIND = new Set(['mandatory', 'commonly_omitted']);
const EVIDENCE = new Set(['authority_approval', 'conformity_cert', 'consultant_list', 'datasheet']);
const STAGE = new Set(['before_works', 'on_completion', 'supplier_licence']);
const COST = new Set(['supplier', 'customer', 'either']);
const DIRECTION = new Set(['below_band', 'above_band']);

// Per family: the family's own required columns, its EN/AR pairs beyond rule_en/rule_ar, and the
// primary key from section 7 (price_red_flag keys on unit+direction+reason, the columns that
// price_benchmark gains).
const FAMILIES = {
  trade_scope_line: { required: ['line_key', 'line_en', 'line_ar', 'kind', 'proof_regex_en', 'proof_regex_ar'], pairs: [['line_en', 'line_ar']], enums: { kind: SCOPE_KIND }, key: (r) => [r.job_type ?? '', r.line_key] },
  spec_equivalence: { required: ['attr_code', 'class_key', 'value', 'equivalent', 'evidence_kind'], pairs: [], enums: { evidence_kind: EVIDENCE }, key: (r) => [r.attr_code, r.class_key, r.value] },
  price_red_flag: { required: ['unit', 'direction', 'reason_en', 'reason_ar'], pairs: [['reason_en', 'reason_ar']], enums: { direction: DIRECTION }, key: (r) => [r.unit, r.direction, r.reason_en] },
  trade_comparability: { required: ['line_type', 'required_attrs'], pairs: [], enums: {}, key: (r) => [r.line_type] },
  trade_approval: { required: ['emirate', 'authority', 'approval_en', 'approval_ar', 'stage', 'evidence_doc', 'cost_bearer'], pairs: [['approval_en', 'approval_ar']], enums: { stage: STAGE, cost_bearer: COST }, key: (r) => [r.emirate, r.authority, r.approval_en] },
};
const SHARED = ['decision', 'label', 'jurisdiction', 'citation', 'effective_date', 'licence', 'rule_en', 'rule_ar'];

const AR = /[؀-ۿ]/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const isDate = (s) => typeof s === 'string' && ISO_DATE.test(s) && !Number.isNaN(Date.parse(s));
const nonEmpty = (s) => typeof s === 'string' && s.trim().length > 0;

const files = fs.existsSync(DIR) ? fs.readdirSync(DIR).filter((f) => f.endsWith('.json')).sort() : [];

test('there is at least one rule seed to check', () => {
  assert.ok(files.length > 0, `no *.json under ${DIR}`);
});

for (const file of files) {
  const trade = file.replace(/\.json$/, '');
  const seed = JSON.parse(fs.readFileSync(path.join(DIR, file), 'utf8'));

  test(`${file}: is keyed by its trade code and carries the five families`, () => {
    assert.equal(seed.trade_code, trade, 'trade_code must equal the file name (reads are by taxonomy_trade.code)');
    for (const fam of Object.keys(FAMILIES)) assert.ok(Array.isArray(seed[fam]), `${fam} must be an array`);
  });

  for (const [fam, spec] of Object.entries(FAMILIES)) {
    test(`${file}: every ${fam} row carries the doctrine columns`, () => {
      const rows = seed[fam] ?? [];
      const seen = new Set();
      rows.forEach((r, i) => {
        const at = `${fam}[${i}]`;
        for (const c of [...SHARED, ...spec.required]) assert.ok(c in r, `${at}: missing column ${c}`);
        // Test 1 — a decision from the enum.
        assert.ok(DECISION.has(r.decision), `${at}: decision '${r.decision}' not in the enum`);
        // Label and licence (test 5).
        assert.ok(LABEL.has(r.label), `${at}: label '${r.label}' not in the enum`);
        assert.ok(LICENCE.has(r.licence), `${at}: licence '${r.licence}' not in the enum`);
        // Test 2 — a jurisdiction.
        assert.ok(nonEmpty(r.jurisdiction), `${at}: jurisdiction empty`);
        // Test 3 — citation and effective date; expires_on is a date or null.
        assert.ok(nonEmpty(r.citation), `${at}: citation empty`);
        assert.ok(isDate(r.effective_date), `${at}: effective_date '${r.effective_date}' is not YYYY-MM-DD`);
        assert.ok(r.expires_on == null || isDate(r.expires_on), `${at}: expires_on '${r.expires_on}' is not YYYY-MM-DD or null`);
        // Test 4 — both languages, present, different, and each in its own script.
        for (const [en, ar] of [['rule_en', 'rule_ar'], ...spec.pairs]) {
          assert.ok(nonEmpty(r[en]), `${at}: ${en} empty`);
          assert.ok(nonEmpty(r[ar]), `${at}: ${ar} empty`);
          assert.notEqual(r[en].trim(), r[ar].trim(), `${at}: ${ar} equals ${en}`);
          assert.ok(AR.test(r[ar]), `${at}: ${ar} carries no Arabic`);
          assert.ok(!AR.test(r[en]), `${at}: ${en} carries Arabic`);
        }
        // The family's own enums and the boolean.
        for (const [col, allowed] of Object.entries(spec.enums)) assert.ok(allowed.has(r[col]), `${at}: ${col} '${r[col]}' not in the enum`);
        if ('equivalent' in r) assert.equal(typeof r.equivalent, 'boolean', `${at}: equivalent must be boolean`);
        if ('required_attrs' in r) assert.ok(Array.isArray(r.required_attrs) && r.required_attrs.length > 0 && r.required_attrs.every(nonEmpty), `${at}: required_attrs must be a non-empty string array`);
        if ('approval_expires' in r) assert.ok(r.approval_expires == null || isDate(r.approval_expires), `${at}: approval_expires is not a date or null`);
        if ('active' in r) assert.equal(typeof r.active, 'boolean', `${at}: active must be boolean`);
        // A regex that does not compile would throw at runtime inside quote_compare.
        for (const c of ['proof_regex_en', 'proof_regex_ar']) if (nonEmpty(r[c])) assert.doesNotThrow(() => new RegExp(r[c], 'iu'), `${at}: ${c} does not compile`);
        // Section 7 primary key.
        const k = JSON.stringify(spec.key(r));
        assert.ok(!seen.has(k), `${at}: duplicate primary key ${k}`);
        seen.add(k);
      });
    });
  }
}
