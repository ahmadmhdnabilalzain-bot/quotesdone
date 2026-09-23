// AN UNREVEALED QUOTE'S FILE STAYS OUT OF THE CUSTOMER'S VAULT (customer-portal audit CP-02,
// supplier-portal audit, 22 Sep 2026 — the same leak found from both sides).
//
// WHAT LEAKED. trg_reg_quote_doc registers quotes.original_file_path in public.documents.
// fn_customer_document_refs() returned EVERY non-draft quote of the customer's own RFQ — it
// reported a `revealed` flag and never filtered on it. policy documents_customer_select grants any
// row that function returns, and customer_documents `get` then signed a one-hour storage URL for
// it and returned documents.extracted beside it. A customer who had paid nothing could download
// the supplier's own quotation PDF, letterhead and contact block included, and read its extracted
// text. customer_api has always signed that file only after the reveal; the documents path was the
// way around the 3% fee.
//
// WHY THIS CHECK READS PRODUCTION AND NOT THE REPOSITORY FILE. The repository file is what we
// intend; the deployed body is what a customer meets. A redeploy of an older canonical file, or an
// out-of-band `create or replace`, reopens the leak with the repository still reading correctly —
// so the assertion is made against the live definition, and the live data case is named beside it.
//
// LIVE CASE: document 62933 is a ZZ DEMO quotation file whose quote has no paid transaction. It is
// the row the rule must exclude, and it is safe to name (a demo fixture, no real person).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

test('the deployed refs function demands a PAID, revealed transaction before a quote file is in scope', { skip: SKIP }, async () => {
  const rows = await sql(`select pg_get_functiondef(p.oid) as def
                            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.proname = 'fn_customer_document_refs'`);
  assert.equal(rows.length, 1, 'exactly one fn_customer_document_refs is deployed');
  const def = String(rows[0].def);
  // The quotes branch must join transactions, and that join must test revealed_at — the same proof
  // of payment every other door reads. Described by shape rather than quoted whole, so a future
  // rewrite that keeps the rule keeps this green.
  const quotesBranch = def.slice(def.indexOf('public.quotes'), def.indexOf('public.leads l\n   where exists') + 1 || undefined);
  assert.match(quotesBranch, /join\s+public\.transactions\s+t/i, 'the quotes branch must join transactions');
  assert.match(quotesBranch, /t\.revealed_at\s+is\s+not\s+null/i, 'and must require revealed_at — a row alone is not payment');
  assert.doesNotMatch(quotesBranch, /left\s+join\s+public\.transactions/i, 'a LEFT join lets the unpaid row through, which is the defect');
});

test('no quote document without a paid reveal is in any customer\'s scope, and the case is real', { skip: SKIP }, async () => {
  // Left side: quote documents whose quote the owning customer has NOT paid to reveal. Right side:
  // how many of those the deployed function would return for that customer. The function is
  // security definer and reads auth.email(), so it cannot be called per customer from here; the
  // rule it now enforces is asserted instead — the pairing of the two is what makes this a
  // measurement rather than a tautology, and the first test above pins the function to that rule.
  const [r] = await sql(`
    with quote_docs as (
      select d.id as document_id, q.id as quote_id, i.customer_id,
             exists (select 1 from public.transactions t
                      where t.quote_id = q.id and t.customer_id = i.customer_id
                        and t.revealed_at is not null) as paid
        from public.documents d
        join public.quotes q on d.ref_table = 'quotes' and q.id::text = d.ref_id
        join public.inquiries i on i.id = q.inquiry_id
       where coalesce(q.status, '') <> 'draft'
    )
    select count(*) filter (where not paid) as unpaid_quote_documents,
           count(*) filter (where paid)     as paid_quote_documents,
           count(*) filter (where not paid and document_id = 62933) as fixture_62933_unpaid
      from quote_docs`);
  // A zero on the left would make this check unable to tell a working rule from an empty table.
  assert.ok(Number(r.unpaid_quote_documents) > 0,
    'there are no unpaid quote documents at all, so this check is currently proving nothing — say so rather than reading it as green');
  assert.equal(Number(r.fixture_62933_unpaid), 1,
    'document 62933 is the named live case: a quotation file whose quote has no paid reveal');
});

test('the action that signs the URL refuses a quotes document itself', () => {
  // Defence in depth, and the reason it is written here: customer_documents is the door that signs
  // the storage URL and returns documents.extracted. It states the rule rather than inheriting it
  // silently from a policy in another file.
  const f = readFileSync(join(ROOT, 'supabase/functions/customer_documents/index.ts'), 'utf8');
  assert.match(f, /ref_table[^\n]*===\s*'quotes'/, 'the get action must branch on a quotes document');
  assert.match(f, /reveal_required/, 'and refuse it with a machine code when the reveal is unpaid');
  assert.match(f, /\.not\('revealed_at',\s*'is',\s*null\)/, 'paid means revealed_at, the same as every other door');
});
