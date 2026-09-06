// Appends the drop of every routine a Phase D migration INTRODUCED to that migration's existing
// down script. Twenty-eight hand-written down scripts reversed their file's tables, columns and
// triggers and left behind the routines the same file was the only definer of — a rollback that
// leaves a routine nothing else defines is not a rollback of that file.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { FILES, introducedBy } from '../phase_d/build_migration_rollback_classification.mjs';

const WRITE = process.argv.includes('--write');
let touched = 0;
for (const f of FILES) {
  const intro = introducedBy(f);
  if (!intro.length) continue;
  const d = 'scripts/sql/down/' + f.replace(/\.sql$/, '') + '_down.sql';
  if (!existsSync(d)) continue;
  let t = readFileSync(d, 'utf8');
  const missing = intro.filter(r => !t.includes(r.name));
  if (!missing.length) continue;

  const block = '\n-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------\n'
    + '-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so\n'
    + '-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.\n'
    + '-- Anything still calling one of them will raise on a missing function after this rollback.\n'
    + missing.map(r => `drop function if exists ${r.name}(${r.args});`).join('\n') + '\n';

  // Before the final commit, so the drops are inside the same transaction as the rest of the down.
  const at = t.lastIndexOf('\ncommit;');
  const next = at >= 0 ? t.slice(0, at + 1) + block + t.slice(at + 1) : t + block;
  console.log(`${WRITE ? 'WRITE' : 'WOULD'} ${d}  +${missing.length} drop(s)`);
  if (WRITE) { writeFileSync(d, next); touched++; }
}
console.log(WRITE ? `${touched} down script(s) extended` : 'nothing written (pass --write)');
