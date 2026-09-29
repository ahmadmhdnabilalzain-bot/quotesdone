// EVERY PUBLIC TABLE IS IN THE DAILY EXPORT OR IS EXCLUDED WITH A REASON (owner: it_engineer, 29 Sep 2026).
//
// #1105 created public.supplier_availability and public.stalled_inquiry_rescue and did not add them to
// fn_table_export_list(), the list the daily table export (the backup to the bucket and Dropbox) walks.
// Nothing caught it: the only guard was every_marketing_table_is_in_the_daily_export.test.mjs, which
// looks at marketing tables only. This check looks at every table.
//
// WHAT IT READS (static, no token, runs in CI):
//   tables    every CREATE TABLE in public in the schema mirror (readSchemaMirror), plus every
//             `create table public.x` in a pending, non-probe file (manifestWithPending) - the mirror
//             shows a table only once its file is applied, and a check that ignores pending DDL passes
//             the PR and turns main red at apply (#1063, #1036, #1070).
//   exported  the fn_table_export_list() body that WINS: the last file in MANIFEST order that defines
//             it, a pending redefinition after all of them (the rule the marketing check uses).
//   excluded  every_table_is_exported_or_explicitly_excluded.json beside this file: table -> category.
//             Each category's reason is in REASONS below.
//
// MEASURED when this was written, on origin/main 14df2a2: 683 public tables, 152 exported, 531 not.
// Of the 531: supplier_availability and stalled_inquiry_rescue are EXPECTED_BY_PR_1110 (below); the
// other 529 were seeded into the JSON - secret 8, cache 14, log 45, measurement 26, fixture 3,
// no_writer 254, backlog 179. The two frozen categories may only shrink (FROZEN_CEILING).
//
//   node --test scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { manifestWithPending, manifestLines, manifestHas } from '../lib/pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const SCHEMA = readSchemaMirror();
const EXCLUDED = JSON.parse(read('scripts/checks/every_table_is_exported_or_explicitly_excluded.json'));

const REASONS = {
  secret: 'Holds a credential, token, OTP or verification code. A secret never goes to the daily export or Dropbox; losing one means re-issuing it, not losing a record.',
  cache: 'A cache, dedupe marker or in-flight claim rebuilt from its source (which is exported, or whose work re-runs). Nothing is lost without it.',
  log: 'An operational log of runs, calls, probes, evals or errors. It records that machinery ran; it is not a customer, supplier, money or decision record.',
  measurement: 'A periodic snapshot, rollup or meter computed from other tables. Losing it loses a trend line, not a record: the rows it was computed from are what matters.',
  fixture: 'Import staging or a test fixture: its rows are promoted into an exported table, or are synthetic.',
  no_writer: 'FROZEN. No routine in the schema mirror or pending SQL, no edge function and no app code writes it (re-measured on every run below), so its content cannot drift - but it is NOT in Dropbox. Add it to the export if its rows matter.',
  backlog: 'FROZEN BACKLOG. Has a live writer, was never added to fn_table_export_list, and fits no category above. Not a reason - an admitted gap. Export it (subject by what it records) or move it to a category with its true reason.',
};
// A frozen category may only shrink. A new table gets exported, or a reasoned category - never these.
const FROZEN_CEILING = { no_writer: 254, backlog: 179 };

// #1105 created these two; #1110's file adds both to fn_table_export_list. Until that file is applied
// (it is in MANIFEST.txt) main is red on them for a reason already being fixed, so they are tolerated
// here - and only here, never in the JSON. Once the file is in MANIFEST the tolerance ends: if either is
// still not exported then, the last test fails. If #1110 is abandoned, the tolerance must be removed by
// hand and the two exported by whoever replaces it.
const EXPECTED_BY_PR_1110 = {
  file: 'scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql',
  tables: ['supplier_availability', 'stalled_inquiry_rescue'],
};

const stripComments = (sql) => sql.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
export const createdIn = (sql) => [...stripComments(sql).matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\."?([a-z0-9_]+)"?\s*\(/gi)].map((m) => m[1].toLowerCase());

const PENDING = manifestWithPending(REPO).filter((f) => !manifestHas(f)).map((f) => read(f));
const TABLES = new Set([
  ...[...SCHEMA.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?public\."?([a-z0-9_]+)"? \(/g)].map((m) => m[1]),
  ...PENDING.flatMap(createdIn),
]);

const DEF = /create\s+or\s+replace\s+function\s+public\.fn_table_export_list\s*\(\s*\)[\s\S]*?\$fn\$;/i;
const WINNER = manifestWithPending(REPO).filter((f) => existsSync(join(REPO, f)) && DEF.test(read(f))).pop();
const EXPORTED = new Set(WINNER ? [...read(WINNER).match(DEF)[0].matchAll(/\('([a-z0-9_]+)',\s*'[^']*'\)/g)].map((m) => m[1]) : []);

// The one rule, pure so the self-test runs it on a fake table.
export function unaccounted(tables, exported, excluded, tolerated = []) {
  return [...tables].filter((t) => !exported.has(t) && !(t in excluded) && !tolerated.includes(t)).sort();
}
const tolerated = () => (manifestHas(EXPECTED_BY_PR_1110.file) ? [] : EXPECTED_BY_PR_1110.tables);

test('the parsers find the tables and the export list', () => {
  assert.ok(WINNER, 'no MANIFEST or pending file defines fn_table_export_list()');
  assert.ok(TABLES.size >= 600, `only ${TABLES.size} public tables parsed from the schema mirror - the parser is broken`);
  assert.ok(EXPORTED.size >= 100, `only ${EXPORTED.size} tables parsed from ${WINNER} - the parser is broken`);
});

test('every public table is exported every day or excluded with a reason', () => {
  const missing = unaccounted(TABLES, EXPORTED, EXCLUDED, tolerated());
  assert.deepEqual(missing, [], `add to fn_table_export_list() (winner: ${WINNER}), or to `
    + `every_table_is_exported_or_explicitly_excluded.json under secret/cache/log/measurement/fixture if that is `
    + `truly what it is: ${missing.join(', ')}`);
  for (const t of tolerated()) if (!EXPORTED.has(t)) console.log(`# known pending gap: ${t} - exported by ${EXPECTED_BY_PR_1110.file} once applied`);
});

test('every exclusion names a real, unexported table, a known category, and the frozen ones only shrink', () => {
  const bad = Object.entries(EXCLUDED).filter(([, c]) => !(c in REASONS)).map(([t, c]) => `${t}: ${c}`);
  assert.deepEqual(bad, [], `unknown categories (known: ${Object.keys(REASONS).join(', ')})`);
  const gone = Object.keys(EXCLUDED).filter((t) => !TABLES.has(t));
  assert.deepEqual(gone, [], 'excluded tables that no longer exist - remove them from the JSON');
  const both = Object.keys(EXCLUDED).filter((t) => EXPORTED.has(t));
  assert.deepEqual(both, [], 'exported now - remove them from the exclusion JSON');
  const doubled = EXPECTED_BY_PR_1110.tables.filter((t) => t in EXCLUDED);
  assert.deepEqual(doubled, [], 'these must be exported, never excluded');
  for (const [cat, ceiling] of Object.entries(FROZEN_CEILING)) {
    const n = Object.values(EXCLUDED).filter((c) => c === cat).length;
    assert.ok(n <= ceiling, `${cat} has ${n} tables, ceiling ${ceiling}: it is frozen and may only shrink - export the new table instead`);
  }
});

test('a no_writer table still has no writer', () => {
  const routines = SCHEMA.slice(SCHEMA.indexOf('-- ===== FUNCTIONS')) + PENDING.map(stripComments).join('\n');
  let code = '';
  const walk = (d) => {
    if (!existsSync(d)) return;
    for (const e of readdirSync(d)) {
      const p = join(d, e);
      if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p); } else if (/\.(ts|tsx|js|mjs)$/.test(e) && !/\.test\./.test(e)) code += readFileSync(p, 'utf8') + '\n';
    }
  };
  walk(join(REPO, 'supabase', 'functions'));
  walk(join(REPO, 'src'));
  // One pass over each text, not one regex per table (254 regexes over the mirror took 8.5 s).
  const sqlTargets = new Set([...routines.matchAll(/(?:insert\s+into|update|delete\s+from|merge\s+into)\s+(?:only\s+)?(?:public\.)?"?([a-z0-9_]+)/gi)].map((m) => m[1].toLowerCase()));
  const codeTargets = new Set([...code.matchAll(/['"`]([a-z0-9_]+)['"`]\s*\)\s*\.\s*(?:insert|upsert|update|delete)\b/g)].map((m) => m[1]));
  const written = Object.entries(EXCLUDED).filter(([, c]) => c === 'no_writer').map(([t]) => t).filter((t) =>
    sqlTargets.has(t) || codeTargets.has(t)
    || ([`'${t}'`, `"${t}"`, `\`${t}\``].some((q) => code.includes(q)) && new RegExp(`${t}[\\s\\S]{0,200}\\.(insert|upsert|update)\\(`).test(code)));
  assert.deepEqual(written, [], 'these now have a writer, so "no_writer" is no longer true: export them, or give their true category');
});

test('#1110 exports supplier_availability and stalled_inquiry_rescue once its file is applied', () => {
  if (!manifestHas(EXPECTED_BY_PR_1110.file, manifestLines(REPO))) return;
  const missing = EXPECTED_BY_PR_1110.tables.filter((t) => !EXPORTED.has(t));
  assert.deepEqual(missing, [], `${EXPECTED_BY_PR_1110.file} is applied but fn_table_export_list() (winner: ${WINNER}) still lacks these`);
});

test('self-test: a pending create table that nobody exported is caught', () => {
  const fake = '-- a comment mentioning create table public.zz_commented_out (\ncreate table if not exists public.zz_probe_t (\n  id bigint primary key\n);';
  assert.deepEqual(createdIn(fake), ['zz_probe_t']);
  const tables = new Set([...TABLES, ...createdIn(fake)]);
  assert.deepEqual(unaccounted(tables, EXPORTED, EXCLUDED, EXPECTED_BY_PR_1110.tables), ['zz_probe_t']);
  assert.deepEqual(unaccounted(tables, new Set([...EXPORTED, 'zz_probe_t']), EXCLUDED, EXPECTED_BY_PR_1110.tables), []);
});
