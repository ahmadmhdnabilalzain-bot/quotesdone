// THE GATE CERTIFIES THE TREE THAT SHIPS (it_engineer, 11 Nov 2026; TD-24, TD-25, the due-diligence review's item 2).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the lockfile detector (scripts/lib/lockfile_tree.mjs) stops seeing a Deno layout, a package at another version,
//     a missing or an extra package, or a linked tree; or starts flagging a package npm would not install here;
//   * the fingerprint stops changing when a step rewrites node_modules;
//   * the gate (scripts/ci/local_gate.mjs) loses its node-tree, next-build or tree-unchanged step;
//   * any Deno call the gate makes, directly or through npm test (scripts/ci, scripts/checks, scripts/lib), passes
//     --node-modules-dir=auto again. Measured 11 Nov 2026: one offline run of scripts/checks/*.test.mjs relinked a
//     lockfile-exact tree's pdfjs-dist from 6.5.438 to 4.10.38 and wrote node_modules/.deno.
// Scripts outside the gate (scripts/e2e, scripts/eval, scripts/staging) are run by hand and are not scanned.
//
//   node --test scripts/checks/the_gate_certifies_the_tree_that_ships.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, symlinkSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { lockEntries, treeFindings, fingerprint } from '../lib/lockfile_tree.mjs';
import { DENO_NPM_FLAGS } from '../lib/deno_npm.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');

const LOCK = { lockfileVersion: 3, packages: {
  '': { name: 'x' },
  'node_modules/a': { version: '1.0.0', resolved: 'https://r/a', integrity: 'sha512-x' },
  'node_modules/@s/b': { version: '2.0.0', resolved: 'https://r/b', integrity: 'sha512-x' },
  'node_modules/a/node_modules/c': { version: '3.0.0', resolved: 'https://r/c', integrity: 'sha512-x' },
  'node_modules/mac-only': { version: '1.0.0', os: ['darwin'], optional: true, resolved: 'https://r/m', integrity: 'sha512-x' },
  'node_modules/mac-only/node_modules/d': { version: '1.0.0', resolved: 'https://r/d', integrity: 'sha512-x' },
  'node_modules/linked': { link: true, resolved: '../linked' },
} };

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'qd-lock-tree-'));
  writeFileSync(join(dir, 'package-lock.json'), JSON.stringify(LOCK));
  const put = (rel, version) => { mkdirSync(join(dir, 'node_modules', rel), { recursive: true });
    writeFileSync(join(dir, 'node_modules', rel, 'package.json'), JSON.stringify({ version })); };
  put('a', '1.0.0'); put('@s/b', '2.0.0'); put('a/node_modules/c', '3.0.0');
  mkdirSync(join(dir, 'node_modules', '.bin'));
  return { dir, put };
}

test('the entries npm installs here: platform-filtered with their children, links left out', () => {
  assert.deepEqual(lockEntries(LOCK).map((e) => e.rel), ['a', '@s/b', 'a/node_modules/c']);
});

test('a lockfile-exact tree has no findings, and every way of differing is one', () => {
  const { dir, put } = fixture();
  try {
    assert.deepEqual(treeFindings(dir), []);
    const fp = fingerprint(dir);
    put('@s/b', '2.0.1');
    assert.match(treeFindings(dir).join('\n'), /@s\/b is 2\.0\.1, the lockfile says 2\.0\.0/);
    assert.notEqual(fingerprint(dir), fp, 'a version change must change the fingerprint');
    put('@s/b', '2.0.0');
    assert.equal(fingerprint(dir), fp);
    mkdirSync(join(dir, 'node_modules', '.deno'));
    assert.match(treeFindings(dir).join('\n'), /node_modules\/\.deno exists/);
    assert.notEqual(fingerprint(dir), fp, 'a Deno layout must change the fingerprint');
    rmSync(join(dir, 'node_modules', '.deno'), { recursive: true });
    put('stray', '0.0.1');
    assert.match(treeFindings(dir).join('\n'), /stray is installed at the top level and the lockfile does not name it/);
    rmSync(join(dir, 'node_modules', 'stray'), { recursive: true });
    rmSync(join(dir, 'node_modules', 'a', 'node_modules'), { recursive: true });
    assert.match(treeFindings(dir).join('\n'), /missing a\/node_modules\/c \(lockfile 3\.0\.0\)/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('a node_modules linked from elsewhere is not a tree built for this checkout', () => {
  const { dir } = fixture();
  const other = mkdtempSync(join(tmpdir(), 'qd-lock-link-'));
  try {
    mkdirSync(join(other, 'co'));
    writeFileSync(join(other, 'co', 'package-lock.json'), JSON.stringify(LOCK));
    symlinkSync(join(dir, 'node_modules'), join(other, 'co', 'node_modules'));
    assert.match(treeFindings(join(other, 'co')).join('\n'), /node_modules is a symbolic link/);
  } finally { rmSync(dir, { recursive: true, force: true }); rmSync(other, { recursive: true, force: true }); }
});

test('the gate has the three steps, and next-build is the site\'s own build', () => {
  const gate = read('scripts/ci/local_gate.mjs');
  for (const id of ['node-tree', 'next-build', 'tree-unchanged']) assert.match(gate, new RegExp(`\\['${id}', `), `the gate has no ${id} step`);
  assert.match(gate, /\['next-build',[^\n]*'npm run build'/);
  assert.equal(JSON.parse(read('package.json')).scripts.build, 'next build');
  assert.match(gate, /treeFindings\(REPO\)/, 'node-tree must read the tree with the shared detector');
  assert.match(gate, /const TREE_BEFORE = fingerprint\(REPO\)/);
});

test('no Deno call the gate makes passes --node-modules-dir=auto', () => {
  assert.deepEqual(DENO_NPM_FLAGS, ['--no-lock', '--node-modules-dir=none']);
  const files = ['scripts/ci', 'scripts/checks', 'scripts/lib'].flatMap((d) => readdirSync(join(REPO, d))
    .filter((f) => /\.m?js$/.test(f) && !f.includes('.RETIRED.') && f !== 'the_gate_certifies_the_tree_that_ships.test.mjs').map((f) => `${d}/${f}`));
  const bad = [];
  for (const f of files) {
    read(f).split('\n').forEach((line, i) => {
      const t = line.trim();
      if (t.startsWith('//') || t.startsWith('*')) return;   // a comment may describe the old flag
      // an argv token, or a deno command line inside a string
      if (/['"`]--node-modules-dir=auto['"`]/.test(line) || /deno (test|check|run)\b[^\n]*--node-modules-dir=auto/.test(line)) bad.push(`${f}:${i + 1}`);
    });
  }
  assert.deepEqual(bad, [], 'use DENO_NPM_FLAGS from scripts/lib/deno_npm.mjs');
  assert.ok(existsSync(join(REPO, 'scripts/ci/node_modules_from_lockfile.mjs')), 'the builder the node-tree note names is gone');
});
