// EVERY STORED DOCUMENT SOURCE IS REGISTERED FOR BACKUP (owner: it_engineer, 14 Sep 2026).
//
// The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes". A column or bucket
// that holds documents and that nobody registered is a document nobody backs up. public.
// fn_backup_source_registry() is the one list (scripts/sql/every_stored_document_source_is_
// registered_for_backup.sql). This check reads the committed schema mirror, so it runs in CI with
// no token, and fails when:
//   1. a public base-table column named *_path / *_paths is not in the registry;
//   2. a bucket the code names (storage.from('x') in an edge function, or a storage.buckets insert
//      in scripts/sql) is not in the registry - and, with a management token, a live bucket;
//   3. a backed-up source has no enqueue rule, or its column never appears in fn_enqueue_doc_backups;
//      a not-backed-up source has no reason.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const SCHEMA = readFileSync(join(ROOT, 'supabase', 'schema', 'full_schema.sql'), 'utf8');

function fnBody(name) {
  const i = SCHEMA.indexOf(`FUNCTION public.${name}(`);
  assert.ok(i >= 0, `public.${name} is not in supabase/schema/full_schema.sql`);
  const m = /\n\s*AS (\$[A-Za-z_]*\$)/.exec(SCHEMA.slice(i));
  assert.ok(m, `public.${name}: no body found in the schema mirror`);
  const start = i + m.index + m[0].length;
  return SCHEMA.slice(start, SCHEMA.indexOf(m[1], start));
}

const REG = [...fnBody('fn_backup_source_registry').matchAll(
  /\('([^']+)',\s*'(column|bucket)',\s*(?:NULL|null|'([^']*)'),\s*(true|false),\s*(?:NULL|null|'((?:[^']|'')*)'),\s*(?:NULL|null|'((?:[^']|'')*)')\)/g)]
  .map((m) => ({ source: m[1], kind: m[2], bucket: m[3] ?? null, backed_up: m[4] === 'true', rule: m[5] ?? null, reason: m[6] ?? null }));
const has = (kind, source) => REG.some((r) => r.kind === kind && r.source === source);

function pathColumns() {
  const out = [];
  for (const m of SCHEMA.matchAll(/CREATE TABLE (?:IF NOT EXISTS )?public\.("?)([a-z0-9_]+)\1 \(([\s\S]*?)\n\);/g)) {
    for (const line of m[3].split('\n')) {
      const c = line.trim().match(/^"?([a-z0-9_]+)"?\s/);
      if (c && /(_path|_paths)$/.test(c[1])) out.push(`${m[2]}.${c[1]}`);
    }
  }
  return out;
}

function codeBuckets() {
  const found = new Set();
  const walk = (d) => {
    for (const e of readdirSync(d)) {
      const p = join(d, e);
      if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p); continue; }
      if (!/\.ts$/.test(e) || /\.test\.ts$/.test(e)) continue;
      for (const m of readFileSync(p, 'utf8').matchAll(/storage\.from\(\s*'([a-z0-9-]+)'\s*\)/g)) found.add(m[1]);
    }
  };
  walk(join(ROOT, 'supabase', 'functions'));
  const sqlDir = join(ROOT, 'scripts', 'sql');
  for (const f of readdirSync(sqlDir).filter((x) => x.endsWith('.sql'))) {
    for (const m of readFileSync(join(sqlDir, f), 'utf8').matchAll(/insert into storage\.buckets\s*\([^)]*\)\s*values\s*\(\s*'([a-z0-9-]+)'/gi)) found.add(m[1]);
  }
  return [...found];
}

test('the registry parses from the schema mirror', () => {
  assert.ok(REG.length >= 40, `only ${REG.length} registry rows parsed from fn_backup_source_registry`);
});

test('every *_path / *_paths column is registered', () => {
  const cols = pathColumns();
  assert.ok(cols.length >= 40, `only ${cols.length} path columns found in the schema mirror - the parser is broken`);
  const missing = cols.filter((c) => !has('column', c));
  assert.deepEqual(missing, [], 'register these in public.fn_backup_source_registry() - backed up with its enqueue rule, or not backed up with a reason: ' + missing.join(', '));
});

test('every bucket the code names is registered', () => {
  const missing = codeBuckets().filter((b) => !has('bucket', b));
  assert.deepEqual(missing, [], 'register these buckets in public.fn_backup_source_registry(): ' + missing.join(', '));
});

// 15 Sep 2026: a source backed up by the STORAGE SWEEP is filed because its file sits in a swept bucket,
// not because the enqueue names its column. So: the enqueue must call the sweep, and a swept column that
// names its bucket must name a bucket the registry sweeps. A source that is not backed up is either an
// OPEN GAP (the backup_gap duty raises it) or a reasoned EXEMPT (the duty leaves it); nothing else.
test('every backed-up source has an enqueue rule the enqueue actually implements; every other source has a reason', () => {
  const enqueue = fnBody('fn_enqueue_doc_backups');
  const swept = new Set(REG.filter((r) => r.kind === 'bucket' && r.backed_up && /STORAGE SWEEP/.test(r.rule || '')).map((r) => r.source));
  for (const r of REG) {
    if (r.backed_up) {
      assert.ok(r.rule, `${r.source} is backed up but names no enqueue rule`);
      if (/STORAGE SWEEP/.test(r.rule)) {
        assert.ok(enqueue.includes('fn_backup_sweep_objects'), `${r.source} is backed up by the STORAGE SWEEP but fn_enqueue_doc_backups never calls fn_backup_sweep_objects`);
        if (r.kind === 'column' && r.bucket) assert.ok(swept.has(r.bucket), `${r.source} is backed up by the STORAGE SWEEP of ${r.bucket}, which the registry does not sweep`);
      } else if (r.kind === 'column') {
        assert.ok(enqueue.includes(r.source.split('.')[1]), `${r.source} is registered as backed up but fn_enqueue_doc_backups never reads ${r.source.split('.')[1]}`);
      }
    } else {
      assert.ok(r.reason, `${r.source} is not backed up and gives no reason`);
      assert.match(r.reason, /^(OPEN GAP|EXEMPT \((not a file or not ours|derived)\)): /, `${r.source}: a source that is not backed up is an 'OPEN GAP: ' or an 'EXEMPT (not a file or not ours): ' / 'EXEMPT (derived): ' with its reason`);
    }
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('every live bucket is registered', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql('select id from storage.buckets order by id');
  const missing = rows.map((r) => r.id).filter((b) => !has('bucket', b));
  assert.deepEqual(missing, [], 'live buckets missing from the registry: ' + missing.join(', '));
});
