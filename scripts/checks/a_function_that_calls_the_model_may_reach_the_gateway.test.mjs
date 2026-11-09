// A function that calls the model through _shared/llm.ts presents cred_fn_<slug> to ai_gateway, and ai_gateway
// refuses it (403, out_of_scope) unless that credential's scope names ai_gateway. llm.ts logs the refusal, but its
// callers see a null answer - the same as "the model declined".
// Assigned: sales_engineer.
//
// MEASURED 13 Oct 2026: supplier_api began writing every quotation-chat reply through _shared/ai_reply.ts in #1335,
// and fn.supplier_api's scope did not name ai_gateway. Every supplier got the held notice instead of the engineer's
// answer. llm_gateway_credential.test.mjs did not see it: it looks only at functions importing llm.ts directly,
// and only asks whether a credential was MINTED, not whether its scope reaches the gateway.
//
// WHAT THIS ASSERTS (reads production): every function whose own source imports _shared/llm.ts, _shared/ai_reply.ts
// or think.ts's defaultDeps, AND has an active fn.<slug> credential, has ai_gateway in that credential's scope.
// A function with no fn.<slug> credential falls back to the shared secret; llm_gateway_credential.test.mjs owns that.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const FNDIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'supabase', 'functions');
const MODEL_PATH = /_shared\/(llm|ai_reply)\.ts['"]|\bdefaultDeps\b[^;]*_shared\/think\.ts['"]/;

export function modelCallers() {
  const out = [];
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name.startsWith('_')) continue;
    // recursive: a function's source is its folder (customer_api and supplier_api keep their actions in actions/ and lib/ since 9 Nov 2026)
    const files = readdirSync(join(FNDIR, d.name), { recursive: true }).map(String).filter((f) => f.endsWith('.ts') && !f.includes('.test.'));
    if (files.some((f) => MODEL_PATH.test(readFileSync(join(FNDIR, d.name, f), 'utf8')))) out.push(d.name);
  }
  return out.sort();
}

test('static: the model callers are found (the scan is not empty)', () => {
  const m = modelCallers();
  assert.ok(m.includes('supplier_api') && m.length >= 10, 'expected supplier_api among at least ten model callers, found: ' + m.join(', '));
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: every model caller with its own credential may reach ai_gateway', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select context, scope from public.internal_credential where active and retired_at is null and context like 'fn.%'`);
  const scope = new Map();
  for (const r of rows) scope.set(r.context, [...(scope.get(r.context) || []), ...(r.scope || [])]);
  const refused = modelCallers().filter((s) => scope.has('fn.' + s) && !scope.get('fn.' + s).includes('ai_gateway'));
  assert.deepEqual(refused, [], 'these functions call the model but their credential is not scoped to ai_gateway, so every call answers 403:\n' + refused.join('\n'));
});
