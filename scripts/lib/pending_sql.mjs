// FILES COMMITTED AND DELIBERATELY NOT APPLIED — one note per file (it_engineer, 22 Sep 2026).
//
// scripts/sql/MANIFEST.txt is the ordered list of what HAS been applied to htdblwldjkcgjvmqkbeh. A file
// that is committed but must not run yet has a note instead: scripts/sql/pending/<name>.txt for
// scripts/sql/<name>.sql, whose text is the reason and the condition that would move it. When the
// coordinator applies the file, the note is deleted and the file is appended to the END of MANIFEST.txt.
//
// Why one file per note: this used to be ONE shared list, scripts/sql/PENDING.txt. Every pull request
// appended its entry at the same end-of-file lines, and each apply that moved a line out conflicted
// every other open pull request — measured 21 Sep 2026, six to eight parallel PRs conflicted on every
// merge, the main side of each conflict an orphaned comment header. Separate files share no lines.
//
// scripts/checks/canonical_routine_manifest.mjs refuses a note with an empty reason, a note whose file
// is also in MANIFEST.txt, and a note whose file is not on disk.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PENDING_DIR = 'scripts/sql/pending';
const REPO = fileURLToPath(new URL('../..', import.meta.url));

// Map 'scripts/sql/<name>.sql' -> reason (trimmed; '' when the note is empty), in name order.
export function pendingNotes(repo = REPO) {
  const dir = join(repo, PENDING_DIR);
  const out = new Map();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.txt')).sort()) {
    out.set(`scripts/sql/${f.slice(0, -4)}.sql`, readFileSync(join(dir, f), 'utf8').trim());
  }
  return out;
}
