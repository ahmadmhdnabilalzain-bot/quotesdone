// WHAT package-lock.json SAYS node_modules HOLDS, AND WHETHER IT DOES (it_engineer, 11 Nov 2026; TD-24).
//
// The gate certified a tree that was not the one Vercel ships: the shared node_modules every worktree linked to was
// Deno's layout (node_modules/.deno/, top-level packages symlinked into it), written by the gate's own
// `deno ... --node-modules-dir=auto` steps. Measured 11 Nov 2026: 13 of 215 top-level packages differed from
// package-lock.json and sharp was 0.34.5 although `overrides` pins ^0.35.5 (GHSA-wq5f-xc86-pv6w). Vercel installs from
// the lockfile, so tsc, oxlint and next build passing on the Deno tree said nothing certain about the shipped one.
//
// lockEntries   the entries `npm ci` would install on this machine (linux-x64-glibc): npm's platform filter, the same
//               one scripts/ci/node_modules_from_lockfile.mjs builds from, so the builder and the check cannot disagree.
// treeFindings  every way a node_modules differs from those entries: a Deno layout, a missing package, a package at
//               another version, a top-level package the lockfile does not name. [] = lockfile-exact.
// fingerprint   a cheap signature of the tree (top-level names, link targets and versions), taken before and after
//               the gate's steps: a step that rewrites node_modules changes it.
import { existsSync, lstatSync, readFileSync, readdirSync, readlinkSync } from 'node:fs';
import { join } from 'node:path';

const okPlatform = (v) => (!v.os || v.os.includes('linux')) && (!v.cpu || v.cpu.includes('x64')) && (!v.libc || v.libc.includes('glibc'));

/** The lockfile entries npm would install here: [{ key, name, version, rel, entry }], shortest path first. */
export function lockEntries(lock) {
  const out = []; const skipped = new Set();
  const entries = Object.entries(lock.packages || {}).filter(([k]) => k.startsWith('node_modules/')).sort(([a], [b]) => a.length - b.length);
  for (const [k, v] of entries) {
    if (v.link) continue;
    const parentSkipped = [...skipped].some((s) => k.startsWith(s + '/'));
    if (!okPlatform(v) || v.inBundle || parentSkipped || (v.optional && !v.resolved)) { skipped.add(k); continue; }
    const name = v.name || k.slice(k.lastIndexOf('node_modules/') + 'node_modules/'.length);
    out.push({ key: k, name, version: v.version, rel: k.slice('node_modules/'.length), entry: v });
  }
  return out;
}

const versionAt = (dir) => { try { return JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).version ?? null; } catch { return null; } };

/** Top-level package directories of a node_modules (scoped ones as @scope/name), dot entries excluded. */
function topLevel(nm) {
  const names = [];
  for (const e of readdirSync(nm)) {
    if (e.startsWith('.')) continue;
    if (e.startsWith('@')) { for (const s of readdirSync(join(nm, e))) names.push(`${e}/${s}`); } else names.push(e);
  }
  return names.sort();
}

/** Every difference between node_modules and the lockfile; [] when the tree is lockfile-exact. */
export function treeFindings(repo, { lockFile = join(repo, 'package-lock.json'), nm = join(repo, 'node_modules') } = {}) {
  if (!existsSync(nm)) return [`${nm} does not exist`];
  const f = [];
  if (lstatSync(nm).isSymbolicLink()) f.push(`node_modules is a symbolic link (to ${readlinkSync(nm)}), not a tree built for this checkout`);
  if (existsSync(join(nm, '.deno'))) f.push('node_modules/.deno exists: this is Deno\'s layout (a deno --node-modules-dir=auto run wrote it), not npm\'s');
  const want = lockEntries(JSON.parse(readFileSync(lockFile, 'utf8')));
  for (const e of want) {
    const got = versionAt(join(nm, e.rel));
    if (got === null) f.push(`missing ${e.rel} (lockfile ${e.version})`);
    else if (got !== e.version) f.push(`${e.rel} is ${got}, the lockfile says ${e.version}`);
  }
  const named = new Set(want.filter((e) => !e.rel.includes('/node_modules/')).map((e) => e.rel));
  for (const t of topLevel(nm)) if (!named.has(t)) f.push(`${t} is installed at the top level and the lockfile does not name it`);
  return f;
}

/** A signature of the tree that changes when something rewrites it. */
export function fingerprint(repo, nm = join(repo, 'node_modules')) {
  if (!existsSync(nm)) return 'absent';
  const st = lstatSync(nm);
  if (st.isSymbolicLink()) return `link:${readlinkSync(nm)}`;
  const parts = [`deno:${existsSync(join(nm, '.deno'))}`];
  for (const t of topLevel(nm)) {
    const p = join(nm, t); const s = lstatSync(p);
    parts.push(`${t}=${s.isSymbolicLink() ? 'link:' + readlinkSync(p) : versionAt(p)}`);
  }
  return parts.join('\n');
}
