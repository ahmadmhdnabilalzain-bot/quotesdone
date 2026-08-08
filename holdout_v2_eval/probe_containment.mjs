// Live containment probe. Prints HTTP status and response body ONLY.
// The shared secret is held in memory and never printed.
// The transaction_id used is a non-existent UUID, so no real refund can be issued by this probe:
// the containment gate runs before the transaction lookup, and without the gate the call would
// return transaction_not_found (404) rather than moving money.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${REF}.supabase.co/functions/v1`;

function mgmtToken() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('no management token');
}

async function q(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${mgmtToken()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  return r.json();
}

async function call(fn, body, label) {
  const r = await fetch(`${BASE}/${fn}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  console.log(`\n[${label}] ${fn} -> HTTP ${r.status}`);
  console.log('  ' + txt.slice(0, 400));
}

const rows = await q("select value from app_secrets where key='inbound_secret'");
const secret = rows?.[0]?.value;
if (!secret) throw new Error('inbound_secret not readable');
console.log('shared secret loaded into memory (not printed), length=' + String(secret).length);

// 1. money action with the shared secret — must be refused by containment
await call('refunds_api',
  { __secret: secret, action: 'resolve', transaction_id: '00000000-0000-0000-0000-000000000000', decision: 'approve' },
  'A refunds_api.resolve WITH shared secret, no Control Mode session');

// 2. read-only action with the shared secret — must still work (proves we did not over-block)
await call('refunds_api', { __secret: secret, action: 'list_pending' },
  'B refunds_api.list_pending WITH shared secret');

// 3. money action with no credential at all — must be refused before containment even runs
await call('refunds_api',
  { action: 'resolve', transaction_id: '00000000-0000-0000-0000-000000000000', decision: 'approve' },
  'C refunds_api.resolve with NO credential');

// 4. os_ops without a credential — platform-level JWT verification
await call('os_ops', { action: 'supplier_decide', id: 1, op: 'approve' },
  'D os_ops.supplier_decide with NO credential');
