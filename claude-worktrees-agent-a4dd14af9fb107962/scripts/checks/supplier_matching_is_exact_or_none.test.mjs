// SUPPLIER MATCHING IS EXACT OR NONE — NO FUZZY OR KEYWORD MATCHER COMES BACK ONTO A MATCHING PATH.
//
// 15 Sep 2026 (sales_engineer). Founder rule: exact trade match or none; no nearest or fuzzy mapping.
// Measured before: PR #697 removed customer_api's keyword fallback on a matcher error, but the turnkey
// path still shortlisted by keyword (the last caller of the keyword routine). That path now asks the
// sales engineer, and the routine is dropped by
// scripts/sql/the_turnkey_path_asks_the_sales_engineer_and_the_keyword_matcher_is_dropped.sql.
//
// This fails if: an edge function or portal file calls a routine whose name marks it as a fuzzy,
// keyword or similarity matcher; customer_api's matcher skips the sales engineer; a SQL change file
// applied after the drop re-creates the keyword routine or defines a routine that reads public.leads
// with trigram similarity; or (with a token) production has such a routine.
//
//   node --test scripts/checks/supplier_matching_is_exact_or_none.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const walk = (d) => readdirSync(d).flatMap((f) => { const p = join(d, f); return statSync(p).isDirectory() ? walk(p) : /\.(tsx?|mjs|js)$/.test(f) && !/\.test\./.test(f) ? [p] : []; });
const DROP = 'scripts/sql/the_turnkey_path_asks_the_sales_engineer_and_the_keyword_matcher_is_dropped.sql';
// A supplier matcher whose name says fuzzy, keyword or nearest. The fuzzy words must sit beside a
// matching word so an unrelated routine (a nearest-branch lookup) does not trip it.
// fn_match_capability is the exact matcher and passes.
const FUZZY_NAME = /^match_suppliers|_kw$|(supplier|lead|match).*(similar|fuzzy|trgm|trigram|nearest)|(similar|fuzzy|trgm|trigram|nearest).*(supplier|lead|match)/;
// Trigram similarity in SQL: the function forms and the operators pg_trgm adds.
const TRIGRAM = /\b(word_|strict_word_)?similarity\s*\(|\s(<<?%|%>>?|<->>?|<<<->)\s|gin_trgm_ops|gist_trgm_ops/i;
const stripSqlComments = (s) => s.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

test('no edge function or portal file calls a fuzzy or keyword supplier matcher', () => {
  const files = [join(REPO, 'supabase', 'functions'), join(REPO, 'src')].filter(existsSync).flatMap(walk);
  const hits = [];
  for (const f of files) {
    for (const m of readFileSync(f, 'utf8').matchAll(/\.rpc\(\s*['"`]([a-z0-9_]+)['"`]/g)) {
      if (FUZZY_NAME.test(m[1])) hits.push(`${f.slice(REPO.length)} -> ${m[1]}`);
    }
  }
  assert.deepEqual(hits, []);
});

test('customer_api matches through the sales engineer on every path', () => {
  const src = read('supabase/functions/customer_api/index.ts');
  const body = src.slice(src.indexOf('async function matchAndNotify('), src.indexOf('\ntype Cfg'));
  assert.ok(body.length > 100, 'matchAndNotify was not found');
  assert.match(body, /functions\/v1\/sales_engineer`[\s\S]*action: 'match'/, 'matchAndNotify does not ask the sales engineer');
  assert.doesNotMatch(body, /useRouter|admin\.rpc\('match_/, 'matchAndNotify has a path that skips the sales engineer');
  // Every caller goes through the one function; none passes an option that would switch the router off.
  const calls = src.match(/await matchAndNotify\(/g) || [];
  assert.ok(calls.length >= 3, `expected the split, turnkey and single paths to call matchAndNotify (${calls.length})`);
});

test('no SQL change applied after the drop brings a fuzzy supplier matcher back', () => {
  const order = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
  const at = order.indexOf(DROP);
  assert.ok(at >= 0, 'MANIFEST has no line for the drop');
  const bad = [];
  for (const f of order.slice(at)) {
    const sql = stripSqlComments(read(f));
    if (/create\s+(or\s+replace\s+)?function\s+(public\.)?match_suppliers_kw\b/i.test(sql)) bad.push(`${f}: re-creates match_suppliers_kw`);
    for (const m of sql.matchAll(/create\s+(or\s+replace\s+)?function\s+(?:public\.)?([a-z0-9_]+)[\s\S]*?\$([a-z_]*)\$([\s\S]*?)\$\3\$/gi)) {
      if (/\bleads\b/i.test(m[4]) && TRIGRAM.test(m[4])) bad.push(`${f}: ${m[2]} reads leads with trigram similarity`);
    }
  }
  assert.deepEqual(bad, []);
  assert.match(stripSqlComments(read(DROP)), /drop function if exists public\.match_suppliers_kw\(text\[\], text, text, text, numeric, integer, boolean\);/);
  assert.match(read('scripts/sql/DROPPED.txt'), /^match_suppliers_kw :: dropped 15 Sep 2026/m, 'DROPPED.txt does not record the drop');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: no routine selects suppliers by trigram similarity, and nothing calls the keyword matcher', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select p.oid::regprocedure::text as sig,
      (p.prosrc ~* '\\m(word_|strict_word_)?similarity\\s*\\(' or p.prosrc ~ '\\s(<<?%|%>>?)\\s') and p.prosrc ~* '\\mleads\\M' as trigram_on_leads,
      p.proname <> 'match_suppliers_kw' and p.prosrc ilike '%match_suppliers_kw%' as calls_kw
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind in ('f', 'p')`);
  assert.deepEqual(rows.filter((r) => r.trigram_on_leads).map((r) => r.sig), []);
  assert.deepEqual(rows.filter((r) => r.calls_kw).map((r) => r.sig), []);
});
