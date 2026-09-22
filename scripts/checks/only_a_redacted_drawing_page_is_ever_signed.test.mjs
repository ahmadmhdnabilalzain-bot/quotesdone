// ONLY A REDACTED DRAWING PAGE IS EVER SIGNED (22 Sep 2026, sales_engineer, finding SP-F-05).
//
// WHAT IS AT STAKE. QuotesDone sells the supplier's identity at reveal, and the customer's ORIGINAL
// drawing carries the title block, the client name, the address, the contacts and the project
// number. The original and the redacted pages live in the SAME storage bucket (drawing-files), and
// _shared/drawing_pages.ts signed whatever string stood in inquiries.drawing_redacted_paths. One bad
// write upstream would have handed every matched supplier the un-anonymised drawing before a fee was
// ever paid — destroying both the promise and the reveal revenue behind it.
//
// TWO HALVES. The guard has to exist in the one helper that signs (source), and no row stored today
// may fall outside it (production). A row that does would be a live leak, not a style point.
//
//   node --test scripts/checks/only_a_redacted_drawing_page_is_ever_signed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const PAGES = join(REPO, 'supabase', 'functions', '_shared', 'drawing_pages.ts');
// The two shapes a redaction output really takes: drawing_redact writes 'redacted/<uuid>/page_pN.jpg'
// and the demo / E2E pages are uploaded to 'drawings/redacted/<tag>/...'. An original is
// 'drawings/<customer_id>/<ts>_<name>' and matches neither.
const REDACTED = /^(?:drawings\/)?redacted\/[^/]+\/.+/;

test('the signer refuses a path that is not a redacted page', () => {
  const src = readFileSync(PAGES, 'utf8');
  assert.match(src, /export const isRedactedPath/, 'drawing_pages.ts no longer has the prefix guard');
  assert.match(src, /if \(!isRedactedPath\(path\)\) return \{ url: null/, 'signOne signs before it checks the prefix');
  // THE GUARD ITSELF, NOT A STRING THAT LOOKS LIKE IT (review of #859, 23 Sep 2026). The first
  // version of this line matched /\.\.'/, which any comment containing ..' would have satisfied.
  // These pin the three clauses of isRedactedPath — the prefix, the traversal refusal and the
  // absolute-path refusal — and the unit test beside the module proves each one behaves.
  const guard = /export const isRedactedPath[\s\S]{0,320}?;/.exec(src);
  assert.ok(guard, 'isRedactedPath is no longer one declaration this check can read');
  assert.match(guard[0], /REDACTED_PREFIX\.test\(p\)/, 'the prefix test is gone from the guard');
  assert.match(guard[0], /!p\.includes\('\.\.'\)/, 'the traversal refusal is gone from the guard');
  assert.match(guard[0], /!p\.startsWith\('\/'\)/, 'the absolute-path refusal is gone from the guard');
  assert.match(src, /const REDACTED_PREFIX = \/\^\(\?:drawings\\\/\)\?redacted\\\//, 'the prefix itself changed');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: no inquiry stores a drawing path outside the redacted prefixes', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select i.id::text as id, p as path
                            from public.inquiries i, unnest(coalesce(i.drawing_redacted_paths, '{}'::text[])) p`);
  const bad = rows.filter((r) => !REDACTED.test(String(r.path))).map((r) => `${r.id} -> ${r.path}`);
  assert.deepEqual(bad, [], 'a supplier-facing drawing path is not a redaction output');
  console.log(`${rows.length} stored drawing page path(s), all under redacted/ or drawings/redacted/`);
});
