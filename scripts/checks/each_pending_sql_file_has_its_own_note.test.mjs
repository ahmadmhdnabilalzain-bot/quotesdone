// EACH PENDING SQL FILE HAS ITS OWN NOTE — the recurrence check for the merge conflicts of 21 Sep 2026
// (it_engineer, 22 Sep 2026). The shared list scripts/sql/PENDING.txt made every open pull request
// conflict on the same end-of-file lines; it is replaced by scripts/sql/pending/<name>.txt (see
// scripts/lib/pending_sql.mjs). This FAILS if the shared list comes back, if a note is empty, if a file
// is both pending and in MANIFEST.txt, or if a note names a file that is not on disk. Repository only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes, PENDING_DIR } from '../lib/pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const manifest = new Set(readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8')
  .split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#')));
const notes = pendingNotes();

test('the shared list is retired', () => {
  assert.ok(!existsSync(join(REPO, 'scripts/sql/PENDING.txt')),
    'scripts/sql/PENDING.txt is back — convert each entry to scripts/sql/pending/<name>.txt');
});

test('every pending note states a reason', () => {
  for (const [f, why] of notes) assert.ok(why, `${f}: its note in ${PENDING_DIR}/ is empty`);
});

test('no file is both pending and applied', () => {
  for (const f of notes.keys()) assert.ok(!manifest.has(f), `${f} has a pending note AND a MANIFEST line — delete the note`);
});

test('every pending note names a file on disk', () => {
  for (const f of notes.keys()) assert.ok(existsSync(join(REPO, f)), `${PENDING_DIR}: a note for ${f}, which does not exist`);
});

test('an empty or whitespace note reads as an empty reason, not as absent', () => {
  const root = mkdtempSync(join(tmpdir(), 'pending-notes-'));
  try {
    mkdirSync(join(root, PENDING_DIR), { recursive: true });
    writeFileSync(join(root, PENDING_DIR, 'a.txt'), '  \n');
    writeFileSync(join(root, PENDING_DIR, 'b.txt'), 'because\n');
    writeFileSync(join(root, PENDING_DIR, 'README.md'), 'not a note');
    const m = pendingNotes(root);
    assert.deepEqual([...m], [['scripts/sql/a.sql', ''], ['scripts/sql/b.sql', 'because']]);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
