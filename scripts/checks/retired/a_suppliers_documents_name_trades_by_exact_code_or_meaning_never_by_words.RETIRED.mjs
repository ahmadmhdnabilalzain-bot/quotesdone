// RETIRED 11 Nov 2026 (customer_support) WITH ITS SUBJECT, not softened to green. Founder ruling 1627: "It's not word matching
// only ... So it has to be read." trade_resolve.tradesOfText (a supplier document's trades by exact code or by gte-small meaning)
// is deleted; the reader model reads all the supplier's documents together and code only checks its keys and quotes
// (supabase/functions/_shared/supplier_doc_trades.ts readTogether, proved by the_model_reads_the_suppliers_documents_together.test.ts).
// fn_norm_trades_many (its SQL file) stays applied and unused by this path.
// A SUPPLIER'S DOCUMENTS NAME TRADES BY EXACT CODE OR BY MEANING, NEVER BY THEIR WORDS
// (29 Sep 2026, sales_engineer, founder ledger 1054, round 3 of 1018; ruling 890).
//
// supabase/functions/_shared/trade_words.ts proposed a supplier's trades from the aliases its documents
// contained. It is deleted; supabase/functions/_shared/trade_resolve.ts resolves a trade by an exact code or slug
// (decided by public.fn_norm_trades, through fn_norm_trades_many) or by meaning over the stored service vectors
// (service_meaning.proposeByMeaning). What fails if the cause returns:
//   * static: trade_words.ts or a caller of tradesFromText comes back; the document reader or the Services
//     rewrite reads a trade-alias vocabulary again; fn_norm_trades_many loses its revoke or its search_path;
//   * live (token): on ZZ DEMO documents, with production's own fn_norm_trades (this change's file run first in a
//     rolled-back transaction while it is pending), the service vectors as production reads them after the release
//     backfill and embed_ml (free, in-region, not OpenRouter), a heading that IS a code resolves, the
//     catalogue is read as what it sells, and none of the false hits the alias words produced on 21 Sep comes back.
//     Nothing is written; nobody is contacted.
//
//   node --test scripts/checks/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { pendingNotes } from '../../lib/pending_sql.mjs';
import { replaySql } from '../../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const SHARED = join(ROOT, 'supabase', 'functions', '_shared');
const FILE = 'scripts/sql/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.sql';
/** Code only: TS line comments and SQL comments removed (a check that greps source must not match its own prose). */
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|--|\*|\/\*\*)/.test(l)).map((l) => l.replace(/\s(\/\/|--) .*$/, '')).join('\n');
const walk = (d, out = []) => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p, out); else if (/\.tsx?$/.test(n)) out.push(p); } return out; };

test('trade_words.ts is gone, and nothing reads a trade from alias words', () => {
  assert.ok(!existsSync(join(SHARED, 'trade_words.ts')), 'trade_words.ts is back');
  const bad = walk(join(ROOT, 'supabase', 'functions')).filter((f) => /tradesFromText\(|from '\.\/trade_words\.ts'|from '\.\.\/_shared\/trade_words\.ts'/.test(code(readFileSync(f, 'utf8'))));
  assert.deepEqual(bad.map((f) => relative(ROOT, f)), [], 'a trade is read from words again');
  const doc = code(R('supabase/functions/_shared/supplier_doc_trades.ts'));
  assert.match(doc, /await tradesOfText\(/, 'the document reader does not resolve through trade_resolve.ts');
  assert.doesNotMatch(doc, /select\('code,aliases'\)|termPattern\(/, 'the document reader reads the trade aliases again');
  const svc = code(R('supabase/functions/_shared/supplier_services.ts'));
  assert.doesNotMatch(svc, /from\('taxonomy_trade'\)\.select\('code,aliases'\)/, 'the Services rewrite reads the trade aliases again');
  assert.match(svc, /withExactTrades\(rw0, await exactTradesOf\(admin, ownWordsOf\(rw0\)\)\)/, 'an own-words phrase is not resolved exactly');
  const res = code(R('supabase/functions/_shared/trade_resolve.ts'));
  assert.match(res, /admin\.rpc\('fn_norm_trades_many'/, 'the exact path is not decided by the database routine');
  assert.match(res, /proposeByMeaning\(/, 'the meaning path is not the shared meaning rule');
  assert.doesNotMatch(res, /termPattern\(|\.aliases\b/, 'trade_resolve.ts reads aliases');
});

test('fn_norm_trades_many is closed and pinned, and pending until the release applies it', () => {
  const s = R(FILE);
  assert.match(s, /create or replace function public\.fn_norm_trades_many\(p_texts text\[\]\)[\s\S]*set search_path to 'public', 'pg_temp'/);
  assert.match(s, /revoke execute on function public\.fn_norm_trades_many\(text\[\]\) from public, anon, authenticated;/);
  assert.match(s, /grant execute on function public\.fn_norm_trades_many\(text\[\]\) to service_role;/);
  assert.match(code(s), /public\.fn_norm_trades\(u\.t\)/, 'it must ask fn_norm_trades itself, not a copy of its rule');
  const applied = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(applied || pendingNotes().has(FILE), 'the file is neither applied nor pending');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const PROFILE = [
  'ZZ DEMO Coolfix Contracting - company profile (QuotesDone fixture, not a real company)',
  'Our divisions',
  'HVAC',
  'Carpentry',
  'Chiller maintenance and AMC contracts for towers and villas',
  'Activities: Plumbing works and drainage maintenance',
].join('\n');

test('production, ZZ DEMO documents: an exact code resolves, the catalogue is read as what it sells, no false hit', { skip: SKIP, timeout: 900_000 }, async () => {
  const { sql, PROJECT_REF } = await import('../../lib/db.mjs');
  const T = (f) => pathToFileURL(join(SHARED, f)).href;
  const { tradesOfText, exactCandidates, textLines } = await import(T('trade_resolve.ts'));
  const { catalogueLines, supplyOnlyOf } = await import(T('catalogue_read.ts'));
  const { PAGES } = await import(T('catalogue_fixtures/make_zz_demo_catalogue.mjs'));

  // The ZZ DEMO catalogue as supplier_doc_trades reads it: spec rows and contacts set aside, supply-only decided.
  const L = catalogueLines(PAGES.map((p) => p.map(([l]) => l).join('\n')).join('\n'));
  const catalogue = { text: [...L.headings, ...L.types, ...L.statements].join('\n'), supplyOnly: supplyOnlyOf([...L.headings, ...L.statements].join('\n')).supply_only };

  // fn_norm_trades_many over every phrase either text would ask about - this change's file first while it is
  // pending, in one transaction that always raises, so nothing is left behind.
  const phrases = [...new Set([PROFILE, catalogue.text].flatMap((t) => exactCandidates(textLines(t))))];
  const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
  const ask = `do $x$ begin raise exception 'CHK<<%>>', public.fn_norm_trades_many(array[${phrases.map(q).join(',')}]::text[])::text; end $x$;`;
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let exact = null;
  try { await replaySql(pre + ask, { retry: false }); } catch (e) {
    const m = String(e.message || e).match(/CHK<<([\s\S]*)>>/); assert.ok(m, 'fn_norm_trades_many did not answer: ' + String(e.message).slice(0, 500));
    exact = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(exact, 'the probe committed instead of rolling back');

  // The service vectors as production reads them once the release backfill has run (scripts/lib/service_vectors.mjs:
  // stored when current, otherwise computed in memory through embed_ml), and the same embed_ml path per clause.
  const { liveServices } = await import('../../lib/service_vectors.mjs');
  const { MEANING_MAX_LINES } = await import(T('service_meaning.ts'));
  const { services, embed, stats } = await liveServices({ sql, PROJECT_REF, caller: 'supplier_doc_trades' });
  console.log('  service vectors:', JSON.stringify(stats));
  assert.equal(stats.failed, 0, 'a service vector could not be computed');
  const deps = () => ({ normTrades: async (ph) => Object.fromEntries(ph.filter((p) => exact[p]).map((p) => [p, exact[p]])), services, embed, budget: { left: MEANING_MAX_LINES } });

  const profile = await tradesOfText(PROFILE, deps());
  const cat = await tradesOfText(catalogue.text, deps(), { supplyOnly: catalogue.supplyOnly });
  const show = (r) => r.trades.map((t) => `${t.code}<-${t.via}:${t.phrases.join('|')}${t.similarity ? '@' + t.similarity : ''}`);
  console.log('  exact map:', JSON.stringify(exact));
  console.log('  profile:', JSON.stringify(show(profile)), profile.exact, profile.meaning);
  console.log('  catalogue:', JSON.stringify(show(cat)), cat.exact, cat.meaning, 'supply_only', catalogue.supplyOnly);

  // The exact path, decided by production's fn_norm_trades: a heading that IS a code or a slug.
  assert.deepEqual(exact.HVAC, ['hvac']);
  assert.deepEqual(exact.Carpentry, ['joinery']);
  assert.ok(!Object.keys(exact).some((p) => p.split(' ').length > 2), 'a sentence resolved exactly: ' + JSON.stringify(exact));
  const byCode = (r, c) => r.trades.find((t) => t.code === c);
  assert.equal(byCode(profile, 'hvac')?.via, 'exact_code');
  assert.equal(byCode(profile, 'joinery')?.via, 'exact_code');
  assert.equal(profile.meaning, 'on');
  // The catalogue: what it sells, by meaning, and none of the 21 Sep false hits the alias words produced.
  assert.equal(cat.meaning, 'on');
  assert.equal(catalogue.supplyOnly, true);
  for (const c of ['office_equipment', 'pos_retail', 'power_generators', 'security_systems']) assert.ok(byCode(cat, c), `${c} not read from the catalogue: ${JSON.stringify(show(cat))}`);
  for (const c of ['electrical', 'logistics_moving']) assert.ok(!byCode(cat, c), `${c} proposed from a spec row or a sentence: ${JSON.stringify(show(cat))}`);
  for (const t of [...profile.trades, ...cat.trades]) assert.ok(['exact_code', 'meaning'].includes(t.via), JSON.stringify(t));
});
