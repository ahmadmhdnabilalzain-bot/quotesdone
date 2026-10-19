// DEPLOY PARITY DETECTS A STALE FILE (it_engineer, 13 Oct 2026).
//
// verify_deploy_parity.mjs once sampled 25 string literals of index.ts and missed an older
// supplier_portal deployed over #1393's fix. It now parses the deployed ESZIP and compares every
// first-party file with main. This builds an ESZIP2.3 fixture whose shared module is one statement
// behind main, and asserts the file is named STALE, while a transpiled-but-identical copy is MATCH.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseEszip, compareSources, norm, firstPartyPath } from '../verify_deploy_parity.mjs';

const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
const str = (s) => Buffer.concat([u32(Buffer.byteLength(s)), Buffer.from(s)]);

// ESZIP2.3, checksum none: magic, options, modules header, npm snapshot, sources, source maps.
// originals[spec], when given, goes in that module's source map as sourcesContent, as Deno's does.
function eszip(files, originals = {}) {
  const entries = []; const sources = []; const maps = []; let off = 0; let moff = 0;
  for (const [spec, src] of Object.entries(files)) {
    const len = Buffer.byteLength(src);
    const map = originals[spec] == null ? Buffer.alloc(0)
      : Buffer.from(JSON.stringify({ version: 3, sources: [spec], sourcesContent: [originals[spec]], names: [], mappings: '' }));
    entries.push(str(spec), Buffer.from([0]), u32(off), u32(len), u32(map.length ? moff : 0), u32(map.length), Buffer.from([0]));
    sources.push(Buffer.from(src)); off += len; maps.push(map); moff += map.length;
  }
  entries.push(str('npm:x@1'), Buffer.from([2]), u32(0)); // an npm entry must be skipped, not misread
  const header = Buffer.concat(entries); const src = Buffer.concat(sources); const mp = Buffer.concat(maps);
  return Buffer.concat([Buffer.from('ESZIP2.3'), u32(4), Buffer.from([0, 0, 1, 0]),
    u32(header.length), header, u32(0), u32(src.length), src, u32(mp.length), mp]);
}

const MAIN = {
  'functions/demo/index.ts': "import { gate } from '../_shared/gate.ts';\n// comment\nexport const run = (x: number): string => gate(x, ['a', 'b',]);\n",
  'functions/_shared/gate.ts': "export function gate(x: number, l: string[]) {\n  if (x > 1) for (const v of l) if (v) return (v);\n  return 'closed-v2';\n}\n",
};
const readMain = (spec) => MAIN[spec] ?? null;
// What Deno's emit produces from MAIN: types and comments gone, trailing comma and redundant parens dropped, braces added.
const DEPLOYED_SAME = {
  'functions/demo/index.ts': "import { gate } from '../_shared/gate.ts';\nexport const run = (x)=>gate(x, ['a','b']);\n",
  'functions/_shared/gate.ts': "export function gate(x, l) {\n  if (x > 1) { for (const v of l)if (v) return v; }\n  return 'closed-v2';\n}\n",
};

test('a deployment identical to main after transpilation is MATCH', () => {
  const r = compareSources(parseEszip(eszip(DEPLOYED_SAME)), readMain);
  assert.equal(r.state, 'MATCH', JSON.stringify(r));
  assert.equal(r.files, 2);
});

test('an older _shared file in the deployed bundle is STALE and named', () => {
  const stale = { ...DEPLOYED_SAME, 'functions/_shared/gate.ts': DEPLOYED_SAME['functions/_shared/gate.ts'].replace('closed-v2', 'closed') };
  const r = compareSources(parseEszip(eszip(stale)), readMain);
  assert.equal(r.state, 'STALE');
  assert.deepEqual(r.differ, ['functions/_shared/gate.ts']);
});

test('a deployed file main no longer has is STALE', () => {
  const r = compareSources(parseEszip(eszip({ ...DEPLOYED_SAME, 'functions/_shared/gone.ts': 'export const a = 1;' })), readMain);
  assert.equal(r.state, 'STALE');
  assert.deepEqual(r.differ, ['functions/_shared/gone.ts (not on main)']);
});

test('a body that is not an eszip is refused, never read as a pass', () => {
  assert.throws(() => parseEszip(Buffer.from('<html>error</html>')), /not an eszip/);
  assert.equal(compareSources(new Map([['jsr:@x/y', 'z']]), readMain).state, 'UNVERIFIED');
});

// ── dropbox_backup/dropbox.ts, the false STALE of 13 Oct ─────────────────────────────────────────
// Frozen copies: main's dropbox.ts and the transpiled text the deployed ESZIP carried for it.
// Deno moves `refreshes = 0;` class field initialisers into the constructor; TS's default
// [[Define]] emit kept them as fields, so norm() read the identical file as different.
const here = (f) => readFileSync(new URL(f, import.meta.url), 'utf8');
const DBX_MAIN = here('./deploy_parity_dropbox.main.ts.txt');
const DBX_DEPLOYED = here('./deploy_parity_dropbox.deployed.js.txt');
const DBX = 'functions/dropbox_backup/dropbox.ts';
const dbxMain = (spec) => (spec === DBX ? DBX_MAIN : null);

test('dropbox.ts: main vs its deployed transpiled form is MATCH through norm()', () => {
  assert.ok(DBX_DEPLOYED.includes('this.refreshes = 0'), 'fixture is the constructor-initialised emit');
  assert.equal(norm(DBX_MAIN), norm(DBX_DEPLOYED));
  assert.equal(compareSources(parseEszip(eszip({ [DBX]: DBX_DEPLOYED })), dbxMain).state, 'MATCH');
});

test('dropbox.ts: a changed string literal in the deployed form is STALE', () => {
  const changed = DBX_DEPLOYED.replace("'refresh_token'", "'refresh_tokens'");
  assert.notEqual(changed, DBX_DEPLOYED);
  const r = compareSources(parseEszip(eszip({ [DBX]: changed })), dbxMain);
  assert.equal(r.state, 'STALE');
  assert.deepEqual(r.differ, [DBX]);
});

test('dropbox.ts: a changed class field initialiser is STALE', () => {
  const changed = DBX_DEPLOYED.replace('this.refreshes = 0', 'this.refreshes = 1');
  assert.notEqual(changed, DBX_DEPLOYED);
  assert.equal(compareSources(parseEszip(eszip({ [DBX]: changed })), dbxMain).state, 'STALE');
});

test('the original source in the source map is compared exactly when present', () => {
  // Transpiled text deliberately differs; the map's original equals main (CRLF aside), so MATCH.
  const same = parseEszip(eszip({ [DBX]: 'garbage' }, { [DBX]: DBX_MAIN.replace(/\n/g, '\r\n') }));
  assert.equal(same.get(DBX).original, true);
  assert.equal(compareSources(same, dbxMain).state, 'MATCH');
  // A comment-only change is invisible to norm() but is a real difference in the original.
  const edited = parseEszip(eszip({ [DBX]: DBX_DEPLOYED }, { [DBX]: DBX_MAIN + '// edited\n' }));
  assert.equal(compareSources(edited, dbxMain).state, 'STALE');
});

test('a bundle rooted at supabase/functions/ maps its specifiers to functions/', () => {
  assert.equal(firstPartyPath('site_error_ingest/index.ts'), 'functions/site_error_ingest/index.ts');
  assert.equal(firstPartyPath('functions/x/index.ts'), 'functions/x/index.ts');
  for (const s of ['vfs://0', 'jsr:@std/x', 'npm:a@1', 'https://esm.sh/a', '---SUPABASE-ESZIP-VERSION-ESZIP---']) assert.equal(firstPartyPath(s), null, s);
  const r = compareSources(parseEszip(eszip({ 'demo/index.ts': DEPLOYED_SAME['functions/demo/index.ts'] })), readMain);
  assert.equal(r.state, 'MATCH', JSON.stringify(r));
  const s = compareSources(parseEszip(eszip({ 'demo/index.ts': "export const run = (x)=>gate(x, ['a','c']);" })), readMain);
  assert.deepEqual(s.differ, ['functions/demo/index.ts']);
});
