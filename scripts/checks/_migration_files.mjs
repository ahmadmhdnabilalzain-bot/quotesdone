// Where the repository keeps migrations, for checks that ask "is this migration in the repo?".
//
// ── WHY THERE ARE TWO DIRECTORIES ───────────────────────────────────────────────────────────────
// supabase/migrations/ is the REPLAY PATH: a generated baseline describing the schema as it is,
// which a fresh database can actually be built from. supabase/migrations_history/ is the real
// history, 736 files, kept for the record and applied by nothing.
//
// The split happened because replaying the history had never once worked — eight separate defects,
// ending in SQL the Supabase CLI cannot even record. See supabase/migrations_history/README.md.
//
// ── WHAT THIS DOES NOT CHANGE ───────────────────────────────────────────────────────────────────
// Every guard that asserts a particular migration exists is asking whether the repository still
// contains it, and the answer is unchanged: it does, one directory over. Reading both is what keeps
// those guards measuring the thing they were written to measure instead of an artefact of a move.
// A check that started failing because a file was relocated is not detecting a regression — but a
// check silently narrowed to a directory that no longer holds the answer is a false green, which is
// the more expensive mistake and the one this file exists to prevent.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const MIG_DIRS = [
  join(root, 'supabase', 'migrations'),
  join(root, 'supabase', 'migrations_history'),
];

/** Every migration filename in the repo, with the directory it lives in. */
export function allMigrations() {
  const out = [];
  for (const dir of MIG_DIRS) {
    let names = [];
    try { names = readdirSync(dir); } catch { continue; }   // the history folder is optional
    for (const f of names.filter((n) => n.endsWith('.sql'))) out.push({ file: f, dir });
  }
  return out.sort((a, b) => a.file.localeCompare(b.file));
}

/** Migrations whose filename ends with `suffix`, anywhere in the repo. */
export function migrationsEndingWith(suffix) {
  return allMigrations().filter((m) => m.file.endsWith(suffix));
}

/** The single migration ending with `suffix`, read as text. Throws the caller's message if absent. */
export function readOneMigration(suffix, assert, message) {
  const hit = migrationsEndingWith(suffix);
  assert.equal(hit.length, 1, message || ('expected exactly one migration ending ' + suffix + ', found ' + hit.length));
  return readFileSync(join(hit[0].dir, hit[0].file), 'utf8');
}
