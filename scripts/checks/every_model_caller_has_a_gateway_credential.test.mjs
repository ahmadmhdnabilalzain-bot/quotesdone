// Every caller name handed to the model client has a credential issued for it.
//
// _shared/llm.ts presents app_secrets.cred_fn_<fn> to ai_gateway and falls back to the shared
// inbound_secret, whose context is inactive — so a caller without its own credential gets 403 on every
// call and reads the null as "the model declined". llm_gateway_credential.test.mjs guards functions
// whose index.ts imports llm.ts; this guards the caller NAME wherever it is passed — think.ts
// defaultDeps(admin, '<fn>') and makeLlm/makeLlmRich({ fn: '<fn>' }) — which is how public_site,
// inquiry_intake and marketing_social_inbox went uncredentialed (71 + 8 + 2 refusals, 14 days to 19 Oct 2026).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MIG_DIRS } from './_migration_files.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Callers that legitimately have no cred_fn_<name> of their own. Each entry names why.
const ALLOW = new Map([
]);

function walk(dir, ext, out = []) {
  if (!existsSync(dir)) return out;
  for (const d of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, d.name);
    if (d.isDirectory()) walk(p, ext, out);
    else if (d.name.endsWith(ext) && !/\.test\.ts$/.test(d.name)) out.push(p);
  }
  return out;
}

const PATTERNS = [
  /defaultDeps\(\s*admin\s*,\s*'([a-z0-9_]+)'\s*\)/g,
  /makeLlm(?:Rich)?\([^()]*?\bfn:\s*'([a-z0-9_]+)'/g,
];

test('every model caller name has a credential issued in scripts/sql or the migrations', () => {
  const callers = new Map();
  for (const f of walk(join(root, 'supabase', 'functions'), '.ts')) {
    const src = readFileSync(f, 'utf8');
    for (const re of PATTERNS) for (const m of src.matchAll(re)) callers.set(m[1], f);
  }
  assert.ok(callers.size > 0, 'no model caller names found — the patterns no longer match and this guard tests nothing');

  // The migration folders are _migration_files.mjs's MIG_DIRS, not a copy: this list named supabase/migrations_archive after
  // it became migrations_history, and so lost the 3 Aug 2026 issue of fn.knowledge_exam and fn.messages_api (live, active).
  const sql = [join(root, 'scripts', 'sql'), ...MIG_DIRS]
    .flatMap((d) => walk(d, '.sql')).map((f) => readFileSync(f, 'utf8')).join('\n');
  const issued = (n) => sql.includes('cred_fn_' + n) || sql.includes("'fn." + n + "'")
    // "[\\s\\S]": written "[\s\S]" in a string literal this was the class [sS], so a mint loop's caller array never matched
    || new RegExp("internal_credential[\\s\\S]{0,4000}'" + n + "'").test(sql);

  const missing = [...callers.keys()].filter((n) => !ALLOW.has(n) && !issued(n)).sort();
  assert.deepEqual(missing, [],
    'these callers reach ai_gateway with no credential of their own, so every model call is refused (403) and '
    + 'returns null: ' + missing.map((n) => n + ' (' + callers.get(n).slice(root.length + 1) + ')').join(', ')
    + '. Issue one in a scripts/sql file (pattern: the_think_callers_get_their_own_gateway_credential.sql) or '
    + 'add it to ALLOW with the reason.');
});
