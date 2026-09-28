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
//   2. Against production: every Arabic alias is in taxonomy_trade; since #893 (ruling 890) fn_norm_trades
//      resolves no fixture sentence from its words and every expected code to itself (see the note on the
//      test). Skipped without a management token.
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

// 29 SEP 2026. The SQL half of the shared rule is gone on purpose: #893
// (trades_categories_and_product_matches_are_reasoned_not_word_matched.sql, founder ledger 890, "no word matching
// anywhere") made fn_norm_trades accept an exact taxonomy code or intake slug only; free text is reasoned upstream,
// never resolved from its words. The parity assertion below compared TS with a SQL word-matcher that no longer exists
// and failed on the first fixture. It now asserts the rule production holds: every fixture sentence resolves to
// NOTHING in SQL (a word matcher creeping back fails here), and every code a fixture expects resolves to itself.
// supabase/functions/_shared/trade_words.ts still reads words for suppliers' documents; whether that survives ruling
// 890 is the sales_engineer's open question, not something this check may settle by going green.
test('production fn_norm_trades reads no words: a fixture sentence resolves to nothing, an exact code to itself', { skip: SKIP }, async () => {
  const vocab = await sql('select code, aliases from public.taxonomy_trade where active');
  const live = new Set(vocab.flatMap((v) => v.aliases || []));
  const missing = Object.values(ALIASES).flat().filter((a) => !live.has(a));
  assert.deepEqual(missing, [], 'Arabic aliases not in production taxonomy_trade: the SQL file is not applied');

  const rows = await sql(`select u.o::int as i, public.fn_norm_trades(u.t) as codes
    from unnest(array[${FIXTURES.map((f) => q(f.text)).join(',')}]::text[]) with ordinality u(t, o) order by u.o`);
  const worded = FIXTURES.map((f, k) => [f.text, rows[k].codes]).filter(([, c]) => c && c.length);
  assert.deepEqual(worded, [], 'fn_norm_trades resolved free text from its words (ruling 890)');

  const codes = [...new Set(FIXTURES.flatMap((f) => f.codes))].sort();
  const exact = await sql(`select c, public.fn_norm_trades(c) as codes from unnest(array[${codes.map(q).join(',')}]::text[]) c`);
  assert.deepEqual(exact.filter((r) => JSON.stringify(r.codes) !== JSON.stringify([r.c])).map((r) => r.c), [],
    'an exact taxonomy code no longer resolves to itself');
});
