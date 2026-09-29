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

// THE FILES THE STATIC CHECKS MUST READ (it_engineer, 29 Sep 2026). A pending file is appended to the
// END of MANIFEST.txt the moment it is applied, so a check that reads only MANIFEST passes a PR whose
// file waits in pending/ and turns red on main one bookkeeping commit later (#1036 and #1070 did exactly
// that). This returns MANIFEST's .sql lines followed by every pending file that is not a probe, in name
// order - the order they will be appended - so a PR fails its own CI instead of breaking main.
export function manifestWithPending(repo = REPO) {
  const listed = readFileSync(join(repo, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql') && !l.startsWith('#') && !l.startsWith('--'));
  const seen = new Set(listed);
  const pending = [...pendingNotes(repo)]
    .filter(([f, note]) => !seen.has(f) && !/^\s*A PROBE\b/.test(note) && existsSync(join(repo, f)))
    .map(([f]) => f);
  return [...listed, ...pending];
}

// IS THIS FILE A MANIFEST LINE? (29 Sep 2026). MANIFEST lines are 'scripts/sql/<name>.sql'; checks pass a
// bare name, a prefixed path, or a Windows path, and one of them compared a bare name with prefixed lines,
// found nothing once the file was applied, and turned main red (#994, #1100). Normalised here, once.
const manifestKey = (f) => `scripts/sql/${String(f).trim().split(String.fromCharCode(92)).join('/').replace(/^\.\//, '').replace(/^scripts\/sql\//, '')}`;
export function manifestLines(repo = REPO) {
  return readFileSync(join(repo, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql') && !l.startsWith('#') && !l.startsWith('--'));
}
export function manifestHas(file, lines = manifestLines()) {
  return lines.includes(manifestKey(file));
}
export function manifestIndex(file, lines = manifestLines()) {
  return lines.lastIndexOf(manifestKey(file));
}
