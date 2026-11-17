// _shared/llm.ts must not be the reason the shared secret can never be withdrawn.
//
// Audit 9.5 / WI-001. Every function that calls a model does it through this module, and this module
// authenticated to ai_gateway with sec('inbound_secret'). Neither the D3 nor the D5 hop inventory saw
// it: both were built by reading each function's OWN fetch() calls, and this hop lives in a shared
// import. Result - 32 callers on the shared secret, legacy.shared.use_count at 379 and still rising,
// and v_internal_secret_migration_progress.safe_to_withdraw_shared_secret pinned false for ever,
// because its 7-day silence clock is reset by every model call the platform makes.
//
// The second half is worse. A withdrawn or refused credential returns 403; makeLlm read the body,
// found no `content`, and returned null - this module's documented contract for "the model
// legitimately declined". All 32 callers handle null by moving on. The entire AI layer could have
// gone silent with no exception, no agent_runs row and no page from fn_watch_failed_runs.
//
// The last test asserts the CLASS rather than the instance: a 33rd importer added later without a
// credential would silently fall back to the shared secret and pin the withdrawal false again.
// QD_LLM_SRC points these assertions at an older copy of llm.ts so qd-check can prove they bite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readOneMigration } from './_migration_files.mjs';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FNDIR = join(root, 'supabase', 'functions');
const target = process.env.QD_LLM_SRC || join(FNDIR, '_shared', 'llm.ts');
const src = readFileSync(target, 'utf8');

// THE REQUEST PATH MOVED, THE BEHAVIOUR DID NOT (14 Aug 2026).
//
// This anchored on `return async function llm(` and sliced to the end of the file. makeLlm was
// then refactored into a thin wrapper - `const rich = makeLlmRich(...)`, and llm() just awaits it
// and checks res.truncated - so the slice stopped containing the fetch, the credential call and
// the status handling, and BOTH assertions below failed while every one of those things was still
// present and correct in makeLlmRich.
//
// That is a guard reporting on the wrong subject, not a regression: gatewayCredential(fnName) is
// called at the top of the request, and 401/403/503 are each read and logged before any content
// check. Anchoring on makeLlmRich tests the function that actually talks to ai_gateway.
//
// The llm() wrapper is asserted separately below to be exactly that - a wrapper - so this cannot
// silently start passing again if a second, unguarded request path is ever added to llm().
const bodyStart = src.indexOf('export function makeLlmRich(');
assert.ok(bodyStart > 0,
  'makeLlmRich is gone from _shared/llm.ts - the gateway request path has moved again and this '
  + 'guard is now testing nothing. Re-anchor it on whatever function calls fetch() against ai_gateway.');
const requestPath = src.slice(bodyStart);

test('llm() reaches the gateway only through the guarded request path', () => {
  const wrapper = src.slice(src.indexOf('export function makeLlm('));
  assert.ok(wrapper.length > 0, 'makeLlm is gone from _shared/llm.ts');
  assert.doesNotMatch(wrapper, /await fetch\(/,
    'makeLlm now calls fetch() itself instead of delegating to makeLlmRich, so it has a second '
    + 'request path that the credential and status assertions in this file do not cover.');
});

test('the request path presents a scoped credential, not the shared secret', () => {
  assert.match(src, /async function gatewayCredential\(/,
    'gatewayCredential is missing, so llm.ts has no way to present a per-caller credential.');
  assert.match(requestPath, /await gatewayCredential\(fnName\)/,
    'the llm() request path does not call gatewayCredential, so whatever it presents to ai_gateway is not ' +
    'the caller-scoped credential.');
  assert.doesNotMatch(requestPath, /sec\('inbound_secret'\)/,
    "the llm() request path still reads sec('inbound_secret') directly. That is the shape that put 32 " +
    'functions on the shared secret and made safe_to_withdraw_shared_secret permanently false.');
});

test('the scoped credential is tried before the legacy fallback, not after', () => {
  const fn = src.slice(src.indexOf('async function gatewayCredential('));
  const scopedAt = fn.indexOf("sec('cred_fn_'");
  const legacyAt = fn.indexOf("sec('inbound_secret')");
  assert.ok(scopedAt > 0, 'gatewayCredential never looks up cred_fn_<caller>');
  assert.ok(legacyAt > scopedAt,
    'gatewayCredential reads inbound_secret before cred_fn_<caller>, so the scoped credential would never be ' +
    'presented and nothing would change.');
});

test('falling back to the shared secret leaves a row naming the caller', () => {
  const fn = src.slice(src.indexOf('async function gatewayCredential('), src.indexOf('export function makeLlm'));
  assert.match(fn, /logAuth\('legacy_fallback'/,
    'the legacy fallback is silent. v_legacy_secret_users records the CALLEE - always ai_gateway - so without ' +
    'this row nothing can name which importer is still on the shared secret, and the watch that gates the ' +
    'withdrawal is blind.');
});

test('an authentication refusal is logged instead of being returned as a null answer', () => {
  assert.match(requestPath, /r\.status === 403 \|\| r\.status === 401/,
    'llm.ts does not inspect the HTTP status. A 403 falls through to `typeof j.content === "string"` -> null, ' +
    'which every caller reads as "the model declined". That is the failure this whole item is about.');
  assert.match(requestPath, /logAuth\('gateway_forbidden'/,
    'a refused credential produces no agent_runs row, so withdrawing the shared secret would silence the AI ' +
    'layer with every monitor still reporting normal.');
  assert.match(requestPath, /logAuth\('verifier_unavailable'/,
    'a 503 from the credential verifier is not logged. Failing closed is correct; failing closed silently is not.');
});

test('the pre-9.5 shape cannot come back', () => {
  assert.doesNotMatch(src, /const secret = await sec\('inbound_secret'\);\s*\n\s*if \(!secret\) return null;/,
    'llm.ts has returned to reading the shared secret directly and returning a bare null.');
});

test('every function that imports _shared/llm.ts has a credential minted for it', () => {
  const importers = readdirSync(FNDIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name !== '_shared')
    .filter((d) => {
      try { return /_shared\/llm\.ts/.test(readFileSync(join(FNDIR, d.name, 'index.ts'), 'utf8')); }
      catch { return false; }
    })
    .map((d) => d.name).sort();
  assert.ok(importers.length > 0, 'no function imports _shared/llm.ts - this guard is now testing nothing');

  // Both migration directories — the replay path and the archived history. See
  // scripts/checks/_migration_files.mjs; the migration is still in the repo, one folder over.
  const sql = readOneMigration('_audit_95_llm_path_scoped_credentials.sql', assert,
    'the migration that issues the llm.ts credentials is not in the repo, so a rebuilt database would put every ' +
    'model call back on the shared secret.');

  // 17 Nov 2026: a function whose every model call names its caller (makeLlm/makeLlmRich({ fn: '<x>' })) presents
  // cred_fn_<x>, never one named after its directory (llm.ts gatewayCredential(def.fn)); the test below requires each
  // such <x> to be minted. it_engineer's seat exam calls only as fn 'knowledge_exam' (fn.knowledge_exam, live and active).
  const namesEveryCaller = (n) => {
    const s = readFileSync(join(FNDIR, n, 'index.ts'), 'utf8');
    const calls = [...s.matchAll(/makeLlm(?:Rich)?\(([^;]*?)\)/g)];
    return calls.length > 0 && calls.every((c) => /\bfn:\s*'[a-z0-9_]+'/.test(c[1]));
  };
  const missing = importers.filter((n) => !new RegExp("'" + n + "'").test(sql) && !namesEveryCaller(n));
  assert.deepEqual(missing, [],
    'these functions import _shared/llm.ts but are not in the credential migration, so each one falls back to ' +
    'the shared inbound_secret on every model call: ' + missing.join(', '));
});

// THE CLASS, SECOND DOOR (19 Oct 2026, finding llm_gateway_auth). public_site, inquiry_intake and
// marketing_social_inbox never import llm.ts; they reach it through _shared/think.ts
// defaultDeps(admin, '<fn>'), which passes its own fn name to makeLlmRich. The test above only sees
// textual importers, so these ran on the inactive shared secret and got 403 on every model call.
// Every fn name handed to defaultDeps must be issued a credential by some SQL file.
test('every fn name passed to defaultDeps has a credential issued for it', () => {
  const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(d, e.name)) : /\.ts$/.test(e.name) && !/\.test\.ts$/.test(e.name) ? [join(d, e.name)] : []);
  const names = new Set();
  // Three doors, each derived from the code: think.ts defaultDeps(admin, '<fn>'); makeLlm/makeLlmRich
  // with { fn: '<fn>' } (llm.ts presents cred_fn_<fn>); and a direct gateway post, which presents
  // whatever sec('cred_fn_<x>') it reads. A direct post's own `fn:` label is attribution only - the
  // gateway authenticates __secret - so for that door the credential it READS is what must exist.
  for (const f of walk(FNDIR)) {
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(/defaultDeps\(\s*\w+\s*,\s*'([a-z0-9_]+)'\s*\)/g)) names.add(m[1]);
    for (const m of src.matchAll(/makeLlm(?:Rich)?\([^;]*?\bfn:\s*'([a-z0-9_]+)'/g)) names.add(m[1]);
    if (/ai_gateway/.test(src)) for (const m of src.matchAll(/sec\('cred_fn_([a-z0-9_]+)'\)/g)) names.add(m[1]);
  }
  assert.ok(names.size > 0, "no defaultDeps(admin, 'fn') call found - this guard is now testing nothing");
  const sqlDirs = ['scripts/sql', 'supabase/migrations', 'supabase/migrations_history'].map((d) => join(root, d));
  const issuing = sqlDirs.flatMap((d) => {
    try { return readdirSync(d).filter((n) => n.endsWith('.sql')).map((n) => readFileSync(join(d, n), 'utf8')); }
    catch { return []; }
  }).filter((s) => /fn_internal_credential_(issue|rotate)|insert\s+into\s+public\.internal_credential/.test(s));
  // Only text that mints counts: the callers array a mint loop iterates, or a direct issue('fn.<name>'.
  // A bare 'fn.<name>' elsewhere (a verdict query, a comment) must not satisfy this guard.
  const minted = issuing.flatMap((s) => [
    ...[...s.matchAll(/callers\s+text\[\]\s*:=\s*array\[([\s\S]*?)\]/g)].map((m) => m[1]),
    ...[...s.matchAll(/foreach\s+\w+\s+in\s+array\s+array\[([\s\S]*?)\]/g)].map((m) => m[1]),
    ...[...s.matchAll(/fn_internal_credential_issue\(\s*'fn\.([a-z0-9_]+)'/g)].map((m) => "'" + m[1] + "'"),
    ...[...s.matchAll(/'cred_fn_([a-z0-9_]+)'/g)].map((m) => "'" + m[1] + "'"),
  ]).join('\n');
  const missing = [...names].filter((n) => !minted.includes("'" + n + "'")).sort();
  assert.deepEqual(missing, [],
    'these fn names reach ai_gateway (defaultDeps, makeLlm fn:, or a direct post) but no SQL file issues them a credential, so each '
    + 'falls back to the shared inbound_secret (403 while it is inactive): ' + missing.join(', '));
});
