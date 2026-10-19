// EVERY DEPLOYED FUNCTION HAS AN OWNER
//
// The founder's rule, 8 September 2026: "if they dont belong to the CEO nor the customer support
// agent then delete", and "if they belong to the website then leave them".
//
// 69 functions were deleted across three waves for belonging to nobody. This is what stops that
// state coming back. A sweep is a moment; a check is a property.
//
// It compares what is DEPLOYED against public.function_owner and fails on either mismatch:
//
//   deployed, no owner   the orphan state the sweep existed to end. A function nobody owns is
//                        one nobody maintains, nobody switches off, and -- if it calls a model --
//                        one that can spend the founder's balance with no seat accountable.
//   owned, not deployed  a stale row. Ownership records that outlive their subject are how a
//                        registry becomes fiction, and this estate has already retired thirteen
//                        checks for measuring things that no longer existed.
//
// It reads the LIVE deployment list rather than the repository folders on purpose. The founder's
// standing rule is that GitHub and Supabase stay in sync, and a check that reads only the repo
// would pass while something served quietly on the internet with no source and no owner.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

import { pathToFileURL } from 'node:url';

import { sql, THROTTLED } from '../lib/db.mjs';
import { withRetry } from '../lib/retry.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';

// A READ THAT IS NOT A LIST IS NEVER A RESULT (19 Oct 2026, PR #1210's parity run). The management API
// answered 429 and the error body reached `owned.map`, which crashed with "owned.map is not a
// function": red for the wrong reason, and one refactor away from green for the wrong reason (an
// error body defaulted to [] reads as "nothing owned"). Both reads now retry a throttle (db.mjs sql
// backs off on 429/5xx; the functions list goes through withRetry), and anything still not an array
// stops the check with exit 2 and a message naming what was not measured. Never a pass.
export function mustBeList(what, value) {
  // An EMPTY list is not measured either: a wrong ref, a token that lists nothing or a blank page would pass vacuously.
  if (Array.isArray(value) && value.length > 0) return value;
  throw new Error(`${what} did not return a non-empty list, so nothing was measured: ${JSON.stringify(value).slice(0, 300)}`);
}

async function listFunctions() {
  const mgmt = (process.env.SUPABASE_ACCESS_TOKEN
    || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
  return withRetry(async () => {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions`, { headers: { Authorization: 'Bearer ' + mgmt } });
    const t = await r.text();
    if (!r.ok) throw new Error(`${r.status === 429 ? THROTTLED + ' ' : ''}functions list HTTP ${r.status}: ${t.slice(0, 300)}`);
    return mustBeList('the deployed functions list', JSON.parse(t));
  }, 6, 3000);
}

async function main() {
let deployed; let owned;
try {
  deployed = (await listFunctions()).map((f) => f.slug);
  owned = mustBeList('public.function_owner', await sql('select function_slug, owner from public.function_owner'));
} catch (e) {
  console.error(`\nNOT MEASURED: ${e.message}`);
  process.exit(2);
}
const ownerOf = new Map(owned.map((r) => [r.function_slug, r.owner]));

const unowned = deployed.filter((s) => !ownerOf.has(s)).sort();
const stale = owned.map((r) => r.function_slug).filter((s) => !deployed.includes(s)).sort();

const byOwner = {};
for (const s of deployed) { const o = ownerOf.get(s); if (o) byOwner[o] = (byOwner[o] || 0) + 1; }

console.log(`\ndeployed functions: ${deployed.length}`);
for (const [o, n] of Object.entries(byOwner).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(n).padStart(3)}  ${o}`);
}

if (unowned.length) {
  console.log(`\nDEPLOYED WITH NO OWNER (${unowned.length}) — the state the sweep ended, returning:`);
  for (const s of unowned) console.log('    ' + s);
}
if (stale.length) {
  console.log(`\nOWNED BUT NOT DEPLOYED (${stale.length}) — a record outliving its subject:`);
  for (const s of stale) console.log('    ' + s);
}
if (!unowned.length && !stale.length) {
  console.log('\nEvery deployed function names an owner, and every owner has a subject.');
}
process.exit(unowned.length || stale.length ? 1 : 0);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
