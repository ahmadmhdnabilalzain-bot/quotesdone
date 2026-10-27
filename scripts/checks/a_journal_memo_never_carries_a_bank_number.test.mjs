// A JOURNAL MEMO NEVER CARRIES A BANK OR IBAN NUMBER.
//
// 15 Sep 2026: the bank booking routines had copied Mashreq's line description, account and IBAN
// included, into gl_journal.memo, which the ledger view, the year-end Ledger.csv and the exports
// show. scripts/sql/a_journal_memo_never_carries_a_bank_or_iban_number.sql masks every memo write
// through public.fn_mask_bank_text and redacted the rows already written. This asserts, against
// production, that no memo matches the IBAN shape or a run of 8+ digits, and that the trigger doing
// the masking is still attached. On failure it names journal ids only, never the text.
//
//   node --test scripts/checks/a_journal_memo_never_carries_a_bank_number.test.mjs
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const q = async (query) => {
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await r.text();
  assert.ok(r.ok, `query failed: ${r.status} ${text}`);
  return JSON.parse(text);
};

test('no journal memo carries an IBAN or a run of 8+ digits', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select id from public.gl_journal
                         where memo ~ '[0-9]{8,}' or memo ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}' order by id`);
  assert.deepEqual(rows.map((r) => r.id), [], 'journals whose memo carries a bank number');
});

test('every memo write is routed through fn_mask_bank_text', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const [row] = await q(`select exists (select 1 from pg_trigger
                            where tgrelid = 'public.gl_journal'::regclass and tgname = 'trg_gl_journal_memo_masked'
                              and tgenabled <> 'D') as attached,
                          public.fn_mask_bank_text('ZZ DEMO IPP TRANSFER AE000000000000000000042 REF 000000000042') as masked`);
  assert.equal(row.attached, true, 'trg_gl_journal_memo_masked is missing or disabled');
  assert.equal(row.masked, 'ZZ DEMO IPP TRANSFER [IBAN] REF [ref]');
});
