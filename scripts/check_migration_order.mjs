// Replay-order check: does any migration touch a table before an earlier migration creates it?
//
//   node scripts/check_migration_order.mjs             # check the tree as it stands
//   node scripts/check_migration_order.mjs --rename=old.sql=new.sql,...   # check a proposed rename
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────────────────────────
// The Supabase Preview check builds a fresh branch and replays supabase/migrations/ in filename
// order. It had never passed: `20260724_analytics_department.sql` ALTERs public.org_action_executor
// and `20260724_supplier_success_executors.sql` CREATEs it, and `analytics` sorts first — so a
// clean database died at 42P01 while both live projects were fine, because there the two ran in
// their real recorded order months earlier.
//
// Nothing in the repo could see that. Every existing gate — replay_parity, audit_session_parity,
// verify_prod_parity — compares the two live databases to each other, and both live databases have
// the table. A defect that only shows on an EMPTY database is invisible to every check that starts
// from a full one. This check starts from empty on purpose.
//
// ── WHAT IT CAN AND CANNOT SEE, STATED PLAINLY ──────────────────────────────────────────────────
// It reads DDL text; it does not run SQL. It follows `create table`, `alter table`, `insert into`
// and `create index ... on`, resolves them to a bare table name, and reports any reference that
// precedes every creation of that table. It does NOT understand tables created inside a plpgsql
// body, `execute` strings, or `create table as select` from a view chain — so a clean run is
// evidence, not proof. A DIRTY run, though, is proof: those really are out of order.
//
// Tables that no migration in the tree ever creates are reported separately and are NOT failures —
// auth.users, storage.objects and the supabase_migrations ledger are all legitimately pre-existing.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const MIG = join(process.cwd(), 'supabase', 'migrations');

// A proposed rename can be checked before it is performed, which is the point: the fix is verified
// against the order it would produce rather than after the files have already moved.
const renameArg = process.argv.find((a) => a.startsWith('--rename='));
const renames = new Map();
if (renameArg) {
  for (const pair of renameArg.slice('--rename='.length).split(',')) {
    const [from, to] = pair.split('=');
    if (from && to) renames.set(from, to);
  }
}

// --exclude lets the baseline generator ask "what would be missing WITHOUT my output file?".
// Without it the generator is self-defeating: it reads the missing list from a tree that already
// contains the baseline, sees nothing missing, and regenerates an empty file over a good one.
const excludeArg = process.argv.find((a) => a.startsWith('--exclude='));
const excluded = new Set(excludeArg ? excludeArg.slice('--exclude='.length).split(',') : []);

const files = readdirSync(MIG)
  .filter((f) => f.endsWith('.sql') && !excluded.has(f))
  .map((f) => ({ real: f, sorted: renames.get(f) || f }))
  .sort((a, b) => a.sorted.localeCompare(b.sorted));

// Comments and dollar-quoted bodies are stripped. A function body mentioning a table is not a
// schema dependency — the body is not executed at migration time — and leaving them in produced
// dozens of false positives on the first run.
const strip = (sql) => sql
  .replace(/\$([a-z_]*)\$[\s\S]*?\$\1\$/gi, ' $BODY$ ')
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/--.*$/gm, ' ');

const bare = (t) => t.replace(/^public\./i, '').replace(/["`]/g, '').toLowerCase();
// Schemas the platform owns. A migration never creates these and must never be blamed for them.
const EXTERNAL = /^(auth|storage|extensions|graphql|graphql_public|realtime|vault|supabase_migrations|cron|net|pg_catalog|information_schema)\./i;

const created = new Map();   // table -> first file that creates it
const problems = [];
const unknown = new Map();   // table -> first file that referenced it, never created in-tree

for (const { real, sorted } of files) {
  const sql = strip(readFileSync(join(MIG, real), 'utf8'));

  // TEMP and UNLOGGED tables count as creations. Missing them reported public._cand as an
  // uncreated table for the whole of this exercise — it is `create temporary table _cand … on
  // commit drop`, three lines above the insert that "referenced" it. A scanner that only knows one
  // spelling of create invents a missing table, which is the same false-MISSING class as a scan
  // whose population excludes where the fact lives.
  for (const m of sql.matchAll(/\bcreate\s+(?:temp\s+|temporary\s+|unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([a-z0-9_."]+)/gi)) {
    const t = bare(m[1]);
    if (EXTERNAL.test(m[1])) continue;
    if (!created.has(t)) created.set(t, sorted);
  }

  const refs = [
    ...[...sql.matchAll(/\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?([a-z0-9_."]+)/gi)].map((m) => ['alter', m[1]]),
    ...[...sql.matchAll(/\binsert\s+into\s+([a-z0-9_."]+)/gi)].map((m) => ['insert into', m[1]]),
    ...[...sql.matchAll(/\bcreate\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?[a-z0-9_"]+\s+on\s+([a-z0-9_."]+)/gi)].map((m) => ['index on', m[1]]),
  ];

  for (const [how, rawT] of refs) {
    if (EXTERNAL.test(rawT)) continue;
    const t = bare(rawT);
    if (created.has(t)) continue;                       // created here or earlier — fine
    if (!unknown.has(t)) unknown.set(t, { file: sorted, how });
  }
}

// A table is only OUT OF ORDER if some LATER migration does create it. Never created anywhere means
// it predates the tree, which is a different (and usually benign) thing.
for (const [t, first] of unknown) {
  const creator = created.get(t);
  if (creator && creator > first.file) {
    problems.push({ table: t, referenced: first.file, how: first.how, createdIn: creator });
  }
}
// ── NEVER CREATED IS TWO DIFFERENT THINGS, AND THE FIRST VERSION CONFLATED THEM ────────────────
// It reported all never-created tables as "pre-existing or externally owned, not failures". For
// auth.users that is right. For public.decision_policy it is exactly wrong: on a FRESH database
// nothing pre-exists, so a public table no migration creates is a hard replay blocker — which is
// what the Supabase Preview check hit immediately after the ordering fix landed.
//
// The distinction is the schema. Anything the platform owns is genuinely not ours to create;
// anything in public that only exists because it was made out-of-band is a hole in the history.
const neverCreated = [...unknown].filter(([t]) => !created.has(t));
const missingPublic = neverCreated.filter(([t]) => !t.includes('.'));
const externalOnly = neverCreated.filter(([t]) => t.includes('.'));

// --json so the baseline generator consumes the SAME analysis the human report prints, rather than
// keeping a second list of missing tables that could drift from this one.
if (process.argv.includes('--json')) {
  console.log(JSON.stringify({
    migrations: files.length,
    orderingBreaks: problems,
    missingPublic: [...unknown].filter(([t]) => !created.has(t) && !t.includes('.'))
      .map(([t, v]) => ({ table: t, firstUse: v.how, file: v.file })),
  }, null, 2));
  process.exit(0);
}

console.log(`${files.length} migration(s) in replay order${renames.size ? `, with ${renames.size} proposed rename(s)` : ''}`);

if (problems.length) {
  console.log(`\nOUT OF ORDER — ${problems.length} table(s) touched before they are created:`);
  for (const p of problems) {
    console.log(`  public.${p.table}`);
    console.log(`      ${p.how} in  ${p.referenced}`);
    console.log(`      created in   ${p.createdIn}`);
  }
} else {
  console.log('\nORDER OK: every table is created before any migration alters, inserts into or indexes it.');
}

if (missingPublic.length) {
  console.log(`\nNEVER CREATED — ${missingPublic.length} public table(s) that no migration in this tree creates.`);
  console.log('These exist on production and staging only because they were made out-of-band, so the');
  console.log('history CANNOT replay onto an empty database until each one has a create migration:');
  for (const [t, v] of missingPublic) console.log(`  public.${t}   (first ${v.how} in ${v.file})`);
}

if (externalOnly.length) {
  console.log(`\nplatform-owned, correctly not created here (${externalOnly.length}): `
    + externalOnly.map(([t]) => t).join(', '));
}

// Ordering and completeness are reported separately because they are fixed differently: ordering by
// renaming, completeness by recovering a definition. Either one blocks a fresh replay.
const failed = problems.length + missingPublic.length;
console.log(`\n${problems.length} ordering break(s), ${missingPublic.length} missing create(s)`);
process.exit(failed ? 1 : 0);
