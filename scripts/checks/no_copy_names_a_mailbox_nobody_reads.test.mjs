// NO COPY NAMES A MAILBOX NOBODY READS (customer_support, 19 Nov 2026). A suspended customer (customer_api) and a paused one
// (trg_block_banned_inquiry) were told to write to a "support" mailbox at quotesdone.com. No reading, triage or routing code
// names it and, measured 19 Nov 2026 on production, 0 of the 100 inbound_messages rows were addressed to it: whoever wrote
// there to get their account back was never answered. Customer-facing copy names info@quotesdone.com, the public address
// customer_support answers (email_triage/supplier_mailbox_reading.ts TENANT_READ_MAILBOXES). Repository only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');
const UNREAD = new RegExp(['sup', 'port@'].join('') + '(quotesdone\\.com|\\.\\.\\.)', 'i');   // spelled in parts so this file is not a hit
const ROOTS = ['src', 'supabase/functions', 'knowledge', 'public'];
const TEXT = /\.(ts|tsx|js|mjs|json|md|html|txt)$/;

function* files(dir) {
  let names = [];
  try { names = readdirSync(dir); } catch { return; }
  for (const n of names) {
    if (n === 'node_modules' || n.startsWith('.')) continue;
    const p = join(dir, n);
    const s = statSync(p);
    if (s.isDirectory()) yield* files(p);
    else if (TEXT.test(n) && !/\.test\.(ts|mjs)$/.test(n) && s.size < 5_000_000) yield p;
  }
}

test('no customer-facing copy or knowledge names the unread mailbox', () => {
  const hits = [];
  for (const root of ROOTS) for (const f of files(join(REPO, root))) if (UNREAD.test(readFileSync(f, 'utf8'))) hits.push(f.slice(REPO.length + 1));
  assert.deepEqual(hits, [], 'copy names a mailbox nobody reads: ' + hits.join(', '));
});

test('the suspended and the paused customer are told the address customer_support reads', () => {
  const api = readFileSync(join(REPO, 'supabase/functions/customer_api/index.ts'), 'utf8');
  assert.match(api, /Your account is suspended\. Please contact info@quotesdone\.com/);
  const sql = readFileSync(join(REPO, 'scripts/sql/a_paused_customer_is_told_an_address_that_is_read.sql'), 'utf8');
  assert.match(sql, /Please contact info@quotesdone\.com to restore it\./);
  const box = readFileSync(join(REPO, 'supabase/functions/email_triage/supplier_mailbox_reading.ts'), 'utf8');
  assert.match(box, /TENANT_READ_MAILBOXES = \['info@quotesdone\.com'/, 'info@ is no longer a mailbox the agents read');
});
