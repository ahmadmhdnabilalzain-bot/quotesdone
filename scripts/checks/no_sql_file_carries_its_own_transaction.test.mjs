// NO SQL FILE CARRIES ITS OWN BEGIN OR COMMIT (it_engineer, 30 Sep 2026).
//
// A file in scripts/sql is run two ways: apply_sql.mjs applies it (one request, one transaction), and the checks
// replay it inside a request that must roll back. A top-level COMMIT in the file ends that transaction early, so
// on 30 Sep 2026 a check's "rolled-back" replay applied a pending file to production before its PR merged.
// scripts/lib/safe_replay.mjs now strips a file's wrapper, and this stops new files carrying one at all.
//
// Top level means code: a `commit` inside a string, a comment or a $tag$ body (a procedure that commits) is not
// one. The scan is scripts/lib/sql_text.mjs's, the same one the replay uses.
//
// APPLIED HISTORY IS NOT EDITED. The files that already carried a wrapper when this check was written are listed
// in scripts/sql/TRANSACTION_LINES_APPLIED.txt (beside MANIFEST.txt, with the history it records); that list may only shrink. A listed file that no longer
// carries one, or that is not on disk, is a finding too, so the list stays true. A pending file is never listed:
// it is fixed before it is applied.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskSql } from '../lib/sql_text.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const BASELINE = 'scripts/sql/TRANSACTION_LINES_APPLIED.txt';
const CONTROL = /^(begin|start\s+transaction|commit|end|rollback|abort)\b/;

/** The top-level transaction statements in a SQL text, lower-cased. */
export const transactionLines = (text) => maskSql(text).split(';')
  .map((c) => c.trim().toLowerCase().replace(/\s+/g, ' ')).filter((c) => CONTROL.test(c));

function* sqlFiles(dir) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) yield* sqlFiles(p);
    else if (n.endsWith('.sql')) yield relative(REPO, p).split('\\').join('/');
  }
}

test('the scan reads a wrapper as code and a commit in a body, string or comment as not', () => {
  assert.deepEqual(transactionLines('BEGIN;\nselect 1;\nCOMMIT;'), ['begin', 'commit']);
  assert.deepEqual(transactionLines("create procedure p() language plpgsql as $$ begin commit; end $$;\nselect 'commit;'; -- commit;"), []);
});

test('no file in scripts/sql carries its own top-level BEGIN or COMMIT, except the applied history listed', () => {
  const listed = readFileSync(join(REPO, BASELINE), 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const known = new Set(listed);
  const found = [];
  for (const f of sqlFiles(join(REPO, 'scripts', 'sql'))) {
    const hits = transactionLines(readFileSync(join(REPO, f), 'utf8'));
    if (hits.length && !known.has(f)) found.push(`${f}: ${hits.join(', ')} - remove the file's own transaction lines`);
    if (!hits.length && known.has(f)) found.push(`${f}: carries no transaction line any more - remove it from ${BASELINE}`);
  }
  for (const f of listed) {
    if (!existsSync(join(REPO, f))) found.push(`${f}: listed in ${BASELINE} and not on disk - remove the line`);
    const note = f.replace(/^scripts\/sql\/([^/]+)\.sql$/, 'scripts/sql/pending/$1.txt');
    if (note !== f && existsSync(join(REPO, note))) found.push(`${f}: is pending, so it is fixed, not listed`);
  }
  assert.deepEqual(found, [], found.join('\n'));
});
