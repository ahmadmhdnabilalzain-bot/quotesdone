// EVERY PUBLIC TABLE IS IN THE DAILY EXPORT OR IS EXCLUDED WITH A REASON (owner: it_engineer, 29 Sep 2026).
//
// #1105 created public.supplier_availability and public.stalled_inquiry_rescue and did not add them to the daily
// table export (the backup to the bucket and Dropbox). This check looks at every table.
//
// SINCE THE REGISTRY (29 Sep 2026, the_daily_export_reads_a_registry_every_pull_request_adds_rows_to.sql): the list is
// public.table_export_registry, one row per table, exported (category = subject) or excluded (category = why), and
// fn_table_export_list() reads it. Seven PRs rewriting the old VALUES list on one day dropped each other's tables; a
// PR now INSERTS its row. The exclusion JSON that sat beside this file moved into the same rows.
//
// WHAT IT READS (static, no token, runs in CI):
//   tables    every CREATE TABLE in public in the schema mirror (readSchemaMirror), plus every `create table public.x`
//             in a pending, non-probe file - a check that ignores pending DDL passes the PR and turns main red at apply.
//   registry  every row inserted into public.table_export_registry, replayed in apply order (lib/table_export_registry).
//
// MEASURED when the registry was seeded: 693 public tables, 312 exported (174 before, 137 of the 178 backlog tables, the registry),
// 381 excluded: no_writer 244, log 60, measurement 36, cache 28, secret 10, fixture 3, backlog 0.
//
//   node --test scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { manifestWithPending, manifestHas } from '../lib/pending_sql.mjs';
import { readRegistry, registryRowsIn, EXCLUSION_CATEGORIES } from '../lib/table_export_registry.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const SCHEMA = readSchemaMirror();
const REGISTRY_FILE = 'scripts/sql/the_daily_export_reads_a_registry_every_pull_request_adds_rows_to.sql';

// A frozen category may only shrink. A new table is exported, or excluded for a true reason - never frozen.
// backlog was the admitted gap (178 tables); it is 0 and stays 0, so it is no category at all any more.
const FROZEN_CEILING = { no_writer: 244 };

const stripComments = (sql) => sql.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
export const createdIn = (sql) => [...stripComments(sql).matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\."?([a-z0-9_]+)"?\s*\(/gi)].map((m) => m[1].toLowerCase());

// A pending `drop table public.x` removes x the same way: the mirror still has it until the release train applies the
// file, and that same file deletes its registry row (30 Sep 2026, enterprise accounts).
export const droppedIn = (sql) => [...stripComments(sql).matchAll(/drop\s+table\s+(?:if\s+exists\s+)?public\."?([a-z0-9_]+)"?/gi)].map((m) => m[1].toLowerCase());

const PENDING = manifestWithPending(REPO).filter((f) => !manifestHas(f)).map((f) => read(f));
const DROPPED_PENDING = new Set(PENDING.flatMap(droppedIn));
const TABLES = new Set([
  ...[...SCHEMA.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?public\."?([a-z0-9_]+)"? \(/g)].map((m) => m[1]),
  ...PENDING.flatMap(createdIn),
].filter((t) => !DROPPED_PENDING.has(t)));
const REG = readRegistry(REPO);

// The one rule, pure so the self-test runs it on a fake table.
export function unaccounted(tables, registry) {
  return [...tables].filter((t) => !registry.has(t)).sort();
}

test('the parsers find the tables and the registry', () => {
  assert.ok(TABLES.size >= 600, `only ${TABLES.size} public tables parsed from the schema mirror - the parser is broken`);
  assert.ok(REG.size >= 600, `only ${REG.size} registry rows parsed - the parser is broken, or ${REGISTRY_FILE} is gone`);
  assert.ok([...REG.values()].filter((r) => r.exported).length >= 174, 'fewer tables exported than the 174 before the registry');
});

test('fn_table_export_list() reads the registry and no later file rewrites it as a list', () => {
  const DEF = /create\s+or\s+replace\s+function\s+public\.fn_table_export_list\s*\(\s*\)[\s\S]*?\$fn\$;/i;
  const defs = manifestWithPending(REPO).filter((f) => existsSync(join(REPO, f)) && DEF.test(stripComments(read(f))));
  const winner = defs.pop();
  assert.equal(winner, REGISTRY_FILE, `${winner} redefines fn_table_export_list() after the registry: insert a row into `
    + 'public.table_export_registry instead (see the header of ' + REGISTRY_FILE + ')');
  assert.match(stripComments(read(winner)).match(DEF)[0], /from public\.table_export_registry r/);
});

test('every public table is exported every day or excluded with a reason', () => {
  const missing = unaccounted(TABLES, REG);
  assert.deepEqual(missing, [], 'insert a row into public.table_export_registry in the file that creates each of these '
    + `(exported with its subject, or excluded as ${EXCLUSION_CATEGORIES.join('/')} if that is truly what it is): ${missing.join(', ')}`);
});

test('every registry row names a real table, an exclusion names a known category with a reason, frozen ones only shrink', () => {
  const gone = [...REG.keys()].filter((t) => !TABLES.has(t));
  assert.deepEqual(gone, [], 'registry rows for tables that no longer exist - the daily export fails on them; set exported = false or drop the row');
  const bad = [...REG.values()].filter((r) => !r.exported && !EXCLUSION_CATEGORIES.includes(r.category)).map((r) => `${r.table}: ${r.category} (${r.file})`);
  assert.deepEqual(bad, [], `an exclusion is one of ${EXCLUSION_CATEGORIES.join(', ')}; "backlog" is gone for good`);
  const reasonless = [...REG.values()].filter((r) => r.reason.trim().length < 10 || !r.added_by.trim()).map((r) => r.table);
  assert.deepEqual(reasonless, [], 'every row says why and who added it');
  for (const [cat, ceiling] of Object.entries(FROZEN_CEILING)) {
    const n = [...REG.values()].filter((r) => !r.exported && r.category === cat).length;
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
  const written = [...REG.values()].filter((r) => !r.exported && r.category === 'no_writer').map((r) => r.table).filter((t) =>
    sqlTargets.has(t) || codeTargets.has(t)
    || ([`'${t}'`, `"${t}"`, `\`${t}\``].some((q) => code.includes(q)) && new RegExp(`${t}[\\s\\S]{0,200}\\.(insert|upsert|update)\\(`).test(code)));
  assert.deepEqual(written, [], 'these now have a writer, so "no_writer" is no longer true: export them, or give their true category');
});

test('#1105\'s supplier_availability and stalled_inquiry_rescue are exported', () => {
  for (const t of ['supplier_availability', 'stalled_inquiry_rescue']) assert.equal(REG.get(t)?.exported, true, `${t} is not exported`);
});

test('self-test: a pending create table that nobody registered is caught, and a registered one is not', () => {
  const fake = '-- a comment mentioning create table public.zz_commented_out (\ncreate table if not exists public.zz_probe_t (\n  id bigint primary key\n);';
  assert.deepEqual(createdIn(fake), ['zz_probe_t']);
  const tables = new Set([...TABLES, ...createdIn(fake)]);
  assert.deepEqual(unaccounted(tables, REG), ['zz_probe_t']);
  const rows = registryRowsIn("-- insert into public.table_export_registry values ('zz_commented', true, 'x', 'a commented row', 'me') on conflict\n"
    + "insert into public.table_export_registry (table_name, exported, category, reason, added_by) values\n"
    + "  ('zz_probe_t', true, 'supplier', 'the CEO''s probe -- a test', 'it_engineer') -- a real comment\non conflict (table_name) do nothing;");
  assert.deepEqual(rows.map((r) => [r.table, r.reason]), [['zz_probe_t', "the CEO's probe -- a test"]]);
  assert.deepEqual(unaccounted(tables, new Map([...REG, ['zz_probe_t', rows[0]]])), []);
});
