// Recover the migration files this repository never had, from production's own ledger.
//
//   node scripts/recover_missing_migrations.mjs           # report
//   node scripts/recover_missing_migrations.mjs --write   # write the files
//
// ── WHAT WAS ACTUALLY WRONG, AFTER FOUR SMALLER DIAGNOSES ───────────────────────────────────────
// The Supabase Preview check builds a branch from production and replays supabase/migrations/. It
// had never passed. Fixing the 20260724 ordering got it further; a generated baseline for 41
// uncreated tables got it further again; giving those files real timestamps got it further still.
// Then it said something different:
//
//     Remote migration versions not found in local migrations directory.
//
// Measured: production's schema_migrations holds 715 migrations. The repo holds 291 files, 278 of
// them with a parseable version. FOUR HUNDRED AND FORTY-FIVE recorded migrations have no file —
// including create_leads_table, marketplace_core_schema and app_secrets_table.
//
// So the repo was never a partial description of the database that had drifted. It is the last
// third of the history, and the first two thirds — the part that CREATES everything — was never
// committed. Every symptom above is that one fact: the 41 tables with no create are exactly the
// tables whose create migrations are among the missing 445.
//
// ── AND THE SQL IS NOT LOST ─────────────────────────────────────────────────────────────────────
// schema_migrations.statements holds the applied SQL for all 715, verbatim. This script writes each
// missing one back out as <version>_<name>.sql. That is recovery, not reconstruction: the bytes
// come from the database that ran them, the same discipline as apply_sql.mjs promoting a routine by
// reading the verified definition back rather than retyping it.
//
// Statements are rejoined with ';\n\n'. The CLI splits a migration on statement boundaries when it
// records it, so this restores a file that re-splits identically.
import { readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';

const MIG = join(process.cwd(), 'supabase', 'migrations');
const WRITE = process.argv.includes('--write');

const localVersions = new Set(readdirSync(MIG)
  .filter((f) => f.endsWith('.sql'))
  .map((f) => (f.match(/^(\d{14})_/) || [])[1])
  .filter(Boolean));

const index = await mgmtRead(PROD_REF,
  `select version, name from supabase_migrations.schema_migrations order by version`);
const missing = index.filter((r) => !localVersions.has(r.version));

console.log(`production ledger: ${index.length} migration(s)`);
console.log(`local files with a version: ${localVersions.size}`);
console.log(`recorded with no local file: ${missing.length}`);
if (!missing.length) { console.log('nothing to recover'); process.exit(0); }
console.log(`  earliest ${missing[0].version} ${missing[0].name}`);
console.log(`  latest   ${missing[missing.length - 1].version} ${missing[missing.length - 1].name}`);

if (!WRITE) { console.log('\nreport only; pass --write to recover them'); process.exit(0); }

// Paged, because 715 migrations of SQL in one response is a payload the management API will not
// return and a timeout is indistinguishable from an empty answer.
const PAGE = 25;
let written = 0, bytes = 0;
for (let i = 0; i < missing.length; i += PAGE) {
  const batch = missing.slice(i, i + PAGE);
  const lit = batch.map((b) => `'${b.version}'`).join(',');
  const rows = await mgmtRead(PROD_REF, `
    select version, name, array_to_string(statements, ';\n\n') sql
    from supabase_migrations.schema_migrations
    where version in (${lit}) order by version`);
  for (const r of rows) {
    // A name is part of a filename, so anything that is not a safe identifier is dropped rather
    // than escaped — a slash or a quote in a filename is a different kind of problem.
    const safe = String(r.name || 'recovered').replace(/[^a-z0-9_]/gi, '_').slice(0, 80);
    let body = String(r.sql || '');
    if (body && !/;\s*$/.test(body)) body += ';';
    const header = `-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.\n`
      + `-- Applied version: ${r.version}   name: ${r.name}\n`
      + `-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.\n\n`;
    const file = `${r.version}_${safe}.sql`;
    writeFileSync(join(MIG, file), header + body + '\n');
    written++; bytes += body.length;
  }
  console.log(`  recovered ${Math.min(i + PAGE, missing.length)}/${missing.length}`);
}
console.log(`\nwrote ${written} file(s), ${(bytes / 1024).toFixed(0)} KB of SQL`);
