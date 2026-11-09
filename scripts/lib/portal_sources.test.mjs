// portal_sources.test.mjs — the portal file lists the text checks read are complete and real.
// node --test scripts/lib/portal_sources.test.mjs
//
// A file added to a split folder and missing from the list would sit outside every check that reads
// the portal through portal_sources.mjs, and those checks would pass without having read it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import * as P from './portal_sources.mjs';

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const portals = Object.keys(P).filter((k) => /_FILES$/.test(k)).map((k) => [k, P[k], P[k.replace(/_FILES$/, '_DIRS')]]);

test('each portal names its files and its split folders', () => {
  assert.ok(portals.length >= 1);
  for (const [k, files, dirs] of portals) {
    assert.ok(Array.isArray(dirs) && dirs.length, `${k} has no _DIRS list`);
    assert.equal(new Set(files).size, files.length, `${k} names a file twice`);
  }
});

test('every listed file exists', () => {
  for (const [, files] of portals) for (const f of files) assert.ok(existsSync(join(P.REPO, f)), f);
});

test('every .ts/.tsx in a split folder is listed', () => {
  for (const [k, files, dirs] of portals) {
    const missing = dirs.flatMap((d) => walk(join(P.REPO, d))).map((f) => relative(P.REPO, f))
      .filter((f) => /\.tsx?$/.test(f) && !files.includes(f));
    assert.deepEqual(missing, [], `${k} does not name these files`);
  }
});
