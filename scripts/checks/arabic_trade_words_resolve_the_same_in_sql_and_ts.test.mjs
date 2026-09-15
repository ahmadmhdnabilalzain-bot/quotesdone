// AN ARABIC TRADE WORD RESOLVES TO THE SAME CODE IN SQL AND IN TYPESCRIPT. Seat: sales_engineer.
//
// public.fn_norm_trades resolves a customer's brief; supabase/functions/_shared/trade_words.ts resolves
// a supplier's document. They are two implementations of one rule, and the day they disagree a supplier
// is proposed a trade a customer's brief for the same words would never reach. Until 15 Sep 2026 both
// were English only (0 Arabic aliases on 40 active codes); scripts/sql/an_arabic_document_names_its_
// trades_in_arabic.sql and trade_words.ts made both Arabic-aware together.
//
// WHAT THIS ASSERTS
//   1. The SQL file applies exactly the alias list the TypeScript tests read (trade_aliases_ar.json).
//      Runs everywhere — it reads the repository.
//   2. Against production: every Arabic alias is in taxonomy_trade, and for every case in the shared
//      fixture (trade_words.fixtures.json) production fn_norm_trades, the TS twin fed the LIVE
//      vocabulary, and the expected codes are all the same. Skipped without a management token.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SHARED = join(ROOT, 'supabase', 'functions', '_shared');
const SQL_FILE = join(ROOT, 'scripts', 'sql', 'an_arabic_document_names_its_trades_in_arabic.sql');
const ALIASES = JSON.parse(readFileSync(join(SHARED, 'trade_aliases_ar.json'), 'utf8'));
const FIXTURES = JSON.parse(readFileSync(join(SHARED, 'trade_words.fixtures.json'), 'utf8'));

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

test('the SQL file applies exactly the alias list the TypeScript tests read', () => {
  const m = /\$aliases\$([\s\S]*?)\$aliases\$/.exec(readFileSync(SQL_FILE, 'utf8'));
  assert.ok(m, 'no $aliases$ block in the SQL file');
  assert.deepEqual(JSON.parse(m[1]), ALIASES);
});

test('production fn_norm_trades and the TS twin agree on every shared fixture', { skip: SKIP }, async () => {
  // Node strips the types of a .ts file natively (Node >= 22.18; CI runs 24). trade_words.ts has no imports.
  const { tradesFromText } = await import(pathToFileURL(join(SHARED, 'trade_words.ts')).href);
  const vocab = await sql('select code, aliases from public.taxonomy_trade where active');
  const live = new Set(vocab.flatMap((v) => v.aliases || []));
  const missing = Object.values(ALIASES).flat().filter((a) => !live.has(a));
  assert.deepEqual(missing, [], 'Arabic aliases not in production taxonomy_trade: the SQL file is not applied');

  const rows = await sql(`select u.o::int as i, public.fn_norm_trades(u.t) as codes
    from unnest(array[${FIXTURES.map((f) => q(f.text)).join(',')}]::text[]) with ordinality u(t, o) order by u.o`);
  for (const [k, f] of FIXTURES.entries()) {
    const fromSql = [...(rows[k].codes || [])].sort();
    const fromTs = tradesFromText(f.text, vocab).map((h) => h.code).sort();
    assert.deepEqual(fromTs, fromSql, `SQL and TS disagree on: ${f.text}`);
    assert.deepEqual(fromSql, [...f.codes].sort(), `wrong codes for: ${f.text}`);
  }
});
