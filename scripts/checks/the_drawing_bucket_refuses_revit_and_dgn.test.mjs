// THE DRAWING BUCKET REFUSES REVIT AND DGN (it_engineer, 28 Sep 2026; founder ruling 1000).
//
// The code refuses a Revit or DGN upload (_shared/drawing_format.ts); the storage bucket must agree.
// The mirror does not carry storage.buckets rows, so this reads the SQL that sets them: the LAST file in
// MANIFEST order (or a pending fix file) that changes drawing-files' mime list must be the one that
// removes the two types, and nothing may add them back after it.
//
//   node --test scripts/checks/the_drawing_bucket_refuses_revit_and_dgn.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'the_drawing_bucket_refuses_revit_and_dgn.sql';
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the last change to the drawing-files mime list removes Revit and DGN', () => {
  const order = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
    .map((l) => l.replace(/^scripts\/sql\//, ''));
  if (!order.includes(FIX) && existsSync(join(REPO, 'scripts/sql/pending', FIX.replace(/\.sql$/, '.txt')))) order.push(FIX);
  const touching = order.filter((f) => existsSync(join(REPO, 'scripts/sql', f)))
    .filter((f) => /update\s+storage\.buckets\s+set\s+allowed_mime_types[^;]*where\s+id\s*=\s*'drawing-files'/i.test(code(read('scripts/sql/' + f))));
  assert.equal(touching.at(-1), FIX, 'a later file changes drawing-files after the Revit/DGN removal: ' + touching.at(-1));
  assert.match(code(read('scripts/sql/' + FIX)), /not in \('application\/vnd\.autodesk\.revit', 'image\/vnd\.dgn'\)/);
});

test('the code still refuses both types', () => {
  const src = read('supabase/functions/_shared/drawing_format.ts');
  assert.match(src, /REFUSED_DRAWING_MIMES[^\n]*application\/vnd\.autodesk\.revit/);
  assert.match(src, /REFUSED_DRAWING_MIMES[^\n]*image\/vnd\.dgn/);
});
