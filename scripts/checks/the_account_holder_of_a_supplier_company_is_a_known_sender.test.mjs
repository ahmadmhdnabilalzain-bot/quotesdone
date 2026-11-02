// THE ACCOUNT HOLDER OF A SUPPLIER COMPANY IS A KNOWN SENDER (2 Nov 2026, customer_support).
// send_outbox gives a claimed_by address the Reply-To supplier@, and email_triage answers there only when
// fn_mail_sender_known says 'supplier'. It read leads.email alone, so the account holder's next reply was declined.
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the file no longer carries the claimed_by clause, or loses a clause production has, or the file is both or
//     neither pending and in MANIFEST;
//   * production, in ONE aborted transaction (the pending file replayed first; ZZ DEMO and example.invalid only): the
//     _probe file must answer PROBE OK. On the definition before this fix it answers PROBE FAILED.
//
//   node --test scripts/checks/the_account_holder_of_a_supplier_company_is_a_known_sender.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'the_account_holder_of_a_supplier_company_is_a_known_sender';
const src = readFileSync(join(REPO, `scripts/sql/${NAME}.sql`), 'utf8');
const pending = existsSync(join(REPO, 'scripts/sql/pending', `${NAME}.txt`));
const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim().replace(/^scripts\/sql\//, ''));

export function problems(text) {
  const t = text.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
  const out = [];
  if (!/lower\(btrim\(claimed_by\)\) = e\) then return 'supplier'/.test(t)) out.push('claimed_by is not read');
  if (!/lower\(email\) = e\) then return 'supplier'/.test(t)) out.push('leads.email is no longer read');
  if (!/lower\(email\) = e\) then return 'customer'/.test(t)) out.push('customers are no longer read');
  if (!/then return 'staff'/.test(t)) out.push('staff are no longer read');
  return out;
}

test('the routine reads claimed_by and keeps what production has', () => assert.deepEqual(problems(src), []));

test('known-bad control: the definition before this fix is caught', () => {
  const before = src.replace(/ *if exists \(select 1 from public\.leads where lower\(btrim\(claimed_by\)\) = e\)[^\n]*\n/, '');
  assert.notEqual(before, src, 'the control could not remove the clause');
  assert.ok(problems(before).includes('claimed_by is not read'));
});

test('the file is pending XOR in MANIFEST, and its probe is never applied', () => {
  assert.ok(pending !== manifest.includes(`${NAME}.sql`));
  assert.ok(existsSync(join(REPO, 'scripts/sql/pending', `${NAME}_probe.txt`)));
  assert.ok(!manifest.includes(`${NAME}_probe.sql`));
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: an account holder reads supplier, a stranger null', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const block = (pending ? src + '\n' : '') + readFileSync(join(REPO, `scripts/sql/${NAME}_probe.sql`), 'utf8');
  let msg = '';
  try { await replaySql(block, { retry: false }); msg = 'the probe committed instead of rolling back'; } catch (e) { msg = String(e.message); }
  const m = msg.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(m, 'the probe failed before it could report: ' + msg.slice(0, 1500));
  const out = JSON.parse(m[1].replace(/\\"/g, '"'));
  assert.equal(out.verdict, 'PROBE OK', JSON.stringify(out));
});
