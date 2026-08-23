// PHASE D DELIVERABLE — PHASE_D_MIGRATION_ROLLBACK_CLASSIFICATION.csv
//
// Section 7 of the founder's ruling: classify EVERY Phase D migration, G01-G19 included.
//
//   node scripts/phase_d/build_migration_rollback_classification.mjs
//
// WHY THIS IS GENERATED AND THE PROSE DOCUMENT IS NOT ENOUGH.
// docs/phase-d/PHASE_D_ROLLBACK_CLASSIFICATION_D9.md classifies by hand, and says so about itself
// three times over: it covered 66 files, then 73, then 87, and each count was true when written and
// wrong within the session. Measured 23 Aug 2026: `ls scripts/sql/phase_d_*.sql | wc -l` returns 197
// and the document names 87. A hand-written table of a growing corpus goes short in silence, which
// is the one failure mode a classification must not have.
//
// So the classes stay exactly as that document defines them -- it remains the authority on what a
// class MEANS and on the deployment defect at the end of it -- and the per-file assignment is
// derived here from the files themselves, every time.
//
// HOW A STATEMENT IS COUNTED. Dollar-quoted bodies are removed first, so DDL inside a routine body
// is not read as DDL of the file; the same measurement the prose document describes ("statements at
// column 0 only"), made by a program rather than by eye. A file whose class cannot be decided is
// UNCLASSIFIED and the check fails on it -- never a default that reads like an answer.
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';

const DIR = 'scripts/sql';
export const FILES = readdirSync(DIR).filter(f => /^phase_d_.*\.sql$/.test(f)).sort();

/** Remove dollar-quoted blocks so a routine body's DDL is not counted as the file's DDL. */
function stripBodies(sql) {
  return sql.replace(/\$([A-Za-z_][A-Za-z0-9_]*)?\$[\s\S]*?\$\1?\$/g, '\n$BODY$\n');
}

/** Statements that begin at column 0, lower-cased, first 200 characters each. */
function topLevelStatements(sql) {
  return stripBodies(sql)
    .split('\n')
    .filter(l => l.length && !/^\s/.test(l) && !l.startsWith('--'))
    .map(l => l.trim().toLowerCase());
}

// WHICH FILE INTRODUCED A ROUTINE. `create or replace function` reads the same whether it is the
// first definition or the ninth, and the two need opposite rollbacks: a REPLACEMENT is reversed by
// re-applying the predecessor, and an INTRODUCTION is reversed by dropping the routine, because
// there is no predecessor to restore. A routine that appears in exactly one phase_d file was
// introduced by that file. THE CORPUS IS EVERY scripts/sql/*.sql, not only the phase_d ones: the
// first run of this test called phase_d_j02 an introduction of fn_kernel_cancel, which is a Phase C
// kernel routine that no phase_d file had defined before and that j02 only replaces.
const DEFINES = /^create (?:or replace )?function\s+(public\.[a-z0-9_]+)\s*\(([^)]*)\)/gmi;
const definedIn = new Map();   // routine -> [file, ...]
const signature = new Map();   // routine -> the argument list as written
const ALL_SQL = readdirSync(DIR).filter(f => /.sql$/.test(f)).sort();
for (const f of ALL_SQL) {
  const text = readFileSync(`${DIR}/${f}`, 'utf8');
  for (const m of text.matchAll(DEFINES)) {
    const name = m[1].toLowerCase();
    if (!definedIn.has(name)) definedIn.set(name, []);
    if (!definedIn.get(name).includes(f)) definedIn.get(name).push(f);
    if (!signature.has(name)) signature.set(name, m[2].replace(/\s+/g, ' ').trim());
  }
}
/** Routines this file is the only definer of — the ones its rollback has to drop. */
export function introducedBy(file) {
  const text = readFileSync(`${DIR}/${file}`, 'utf8');
  const out = [];
  for (const m of text.matchAll(DEFINES)) {
    const name = m[1].toLowerCase();
    if (definedIn.get(name).length === 1 && !out.some(x => x.name === name)) {
      out.push({ name, args: m[2].replace(/\s+/g, ' ').trim() });
    }
  }
  return out;
}

export function classify(file) {
  const raw = readFileSync(`${DIR}/${file}`, 'utf8');
  const st = topLevelStatements(raw);
  const has = (re) => st.filter(l => re.test(l));

  const routines = has(/^create (or replace )?function /).length;
  const createTable = has(/^create table /).length;
  const createIndex = has(/^create (unique )?index /).length;
  const createTrigger = has(/^create (or replace )?(constraint )?trigger /).length;
  const createView = has(/^create (or replace )?view /).length;
  const createType = has(/^create type /).length;
  const alterTable = has(/^alter table /).length;

  // A `drop trigger if exists T on X;` sitting immediately above `create trigger T on X` is an
  // idempotent RE-CREATE, not destruction, and reading it as destruction put 13 files into
  // IRREVERSIBLE_WITH_FOUNDER_APPROVAL on the first run of this classifier -- a class the prose
  // document states no file carries. A drop is destructive only when the same object is not created
  // again in the same file.
  const named = (l) => (l.match(/^drop (?:table|type|index|trigger|view|policy)\s+(?:if exists\s+)?([a-z0-9_."]+)/) || [])[1];
  const recreated = new Set(st.flatMap(l =>
    (l.match(/^create (?:or replace )?(?:unique )?(?:constraint )?(?:table|type|index|trigger|view|policy)\s+(?:if not exists\s+)?([a-z0-9_."]+)/) || []).slice(1)));
  const dropsRecreated = has(/^drop (table|type|index|trigger|view|policy) /)
    .filter(l => recreated.has(named(l))).length;
  const dropDestructive = has(/^drop (table|type|index|trigger|view|policy) /)
      .filter(l => !recreated.has(named(l))).length
    + has(/^alter table .*\bdrop column\b/).length;
  const dropFunction = has(/^drop function /).length;
  const grants = has(/^(grant|revoke) /).length;
  const policies = has(/^(create|alter|drop) policy /).length;
  const deletes = has(/^delete from /).length;
  const writes = has(/^(insert into|update) /).length;

  const introduced = introducedBy(file);
  const ddl = [];
  if (createTable) ddl.push(`${createTable} table`);
  if (createIndex) ddl.push(`${createIndex} index`);
  if (createTrigger) ddl.push(`${createTrigger} trigger`);
  if (createView) ddl.push(`${createView} view`);
  if (createType) ddl.push(`${createType} type`);
  if (alterTable) ddl.push(`${alterTable} alter table`);
  if (policies) ddl.push(`${policies} policy`);
  if (dropFunction) ddl.push(`${dropFunction} drop function`);
  if (dropsRecreated) ddl.push(`${dropsRecreated} drop-and-recreate`);
  if (dropDestructive) ddl.push(`${dropDestructive} destructive drop`);

  const additiveDdl = createTable + createIndex + createTrigger + createView + createType
    + alterTable + policies;

  // The order is the order the prose document states, and it is a precedence, not a menu: a file
  // that both creates a table and replaces a routine needs the table's down script, and a file that
  // drops data needs the founder before either.
  let cls;
  if (dropDestructive) cls = 'IRREVERSIBLE_WITH_FOUNDER_APPROVAL';
  else if (additiveDdl) cls = 'EXPLICIT_DOWN_REQUIRED';
  else if (deletes) cls = 'DATA_PURGE_NOT_REVERSIBLE';
  // A file whose only DDL is `drop function` -- a signature change, where CREATE OR REPLACE cannot
  // bring the old signature back -- is reversed the same way a routine is: by re-applying the file
  // that defined it and every later file in that routine's chain. A down script under
  // scripts/sql/down/ would hold no statement it could run, and the prose document's own entry for
  // d4 shows why the two were conflated: that file drops two routines AND creates a table, and the
  // table is what needs the down.
  else if (dropFunction) cls = 'ROUTINE_SIGNATURE_CHANGE';
  // A file that is the only definer of a routine INTRODUCED it. Re-applying a predecessor cannot
  // reverse that — there is no predecessor — so the reversal is a named drop, and the file needs a
  // down script exactly as one that created a table does.
  else if (introduced.length) cls = 'ROUTINE_INTRODUCED';
  else if (routines) cls = 'ROUTINE_RESTORE';
  else if (grants) cls = 'GRANT_RESTORE';
  else if (writes) cls = 'ADDITIVE_SURVIVAL_SAFE';
  else cls = 'UNCLASSIFIED';

  const stem = file.replace(/\.sql$/, '');
  const downFile = `${DIR}/down/${stem}_down.sql`;
  const downNeeded = cls === 'EXPLICIT_DOWN_REQUIRED' || cls === 'IRREVERSIBLE_WITH_FOUNDER_APPROVAL'
    || cls === 'ROUTINE_INTRODUCED' || introduced.length > 0;
  const headerDown = /^--.*\bROLLBACK\b/mi.test(raw) || /^--.*\bDOWN\b/m.test(raw);

  return {
    file, class: cls,
    routines, routines_introduced: introduced.map(x => x.name).join(' ') || 'none',
    additive_ddl: ddl.join(', ') || 'none',
    grants, registry_writes: writes, deletes,
    down_script_required: downNeeded ? 'YES' : 'NO',
    down_script: existsSync(downFile) ? `${DIR}/down/${stem}_down.sql` : (downNeeded ? 'MISSING' : '-'),
    rollback_stated_in_header: headerDown ? 'YES' : 'NO',
  };
}

if (String(process.argv[1] || '').endsWith('build_migration_rollback_classification.mjs')) {
  const rows = FILES.map(classify);
  const cols = Object.keys(rows[0]);
  const csv = provenance({
    command: 'node scripts/phase_d/build_migration_rollback_classification.mjs',
    numerator: rows.length, denominator: FILES.length,
    of: 'files matching scripts/sql/phase_d_*.sql, each classified from its own text',
    attribution: 'dollar-quoted routine bodies are removed first, then statements beginning at column 0 are counted; the classes are the ones docs/phase-d/PHASE_D_ROLLBACK_CLASSIFICATION_D9.md defines and that document remains the authority on what each one means',
  }) + cols.join(',') + '\n'
    + rows.map(r => cols.map(c => `"${String(r[c] ?? '').replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
  writeFileSync(outPath('PHASE_D_MIGRATION_ROLLBACK_CLASSIFICATION.csv'), csv);

  const by = rows.reduce((a, r) => (a[r.class] = (a[r.class] || 0) + 1, a), {});
  console.log(`Phase D migrations classified ${rows.length} of ${FILES.length}`);
  for (const [k, v] of Object.entries(by).sort()) console.log(`  ${k.padEnd(38)} ${v}`);
  const missing = rows.filter(r => r.down_script === 'MISSING');
  console.log(`down script required and missing  ${missing.length}`);
  for (const m of missing) console.log(`  ${m.file}  (${m.additive_ddl})`);
}
