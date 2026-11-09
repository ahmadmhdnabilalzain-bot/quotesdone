// EVERY ORPHAN JOB resilience_ping CALLS PRESENTS A CREDENTIAL SCOPED TO THAT CALLEE (28 Sep 2026, it_engineer).
//
// The cause: wa_templates_watch answered HTTP 403 on every hourly run (137 out_of_scope rows in
// internal_credential_audit in 48 h) because resilience_ping presented its own credential,
// fn.resilience_ping, and that context is not scoped to the callee. send_sms, email_cron, email_triage
// and doc_extract had the same defect behind a shut gate.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: a job in orphanTick's list stops passing an explicit credential variable, or passes one
//     that is not read from app_secrets in the same function;
//   * production (read-only): the context that credential names is not active, or its scope does not
//     include the callee slug.
//
//   node --test scripts/checks/resilience_orphan_jobs_present_a_scoped_credential.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = functionSource('resilience_ping');

// Every `call('<slug>', <ms>, <body>, <credVar>)` inside the orphan step's job list.
function jobs() {
  const start = SRC.indexOf('const jobs: Array<[string, string, number');
  assert.ok(start > 0, 'the orphan job list was not found in resilience_ping');
  const block = SRC.slice(start, SRC.indexOf('for (const [gate, key, need, run] of jobs)', start));
  const out = [];
  for (const m of block.matchAll(/call\('([a-z_]+)'([^)]*)\)/g)) {
    const args = m[2].split(',').map((s) => s.trim()).filter(Boolean);
    out.push({ slug: m[1], cred: args.length >= 3 ? args[args.length - 1] : null });
  }
  return out;
}
// credVar -> app_secrets key, from `const <var> = await sec('<key>')`.
const credKeys = Object.fromEntries([...SRC.matchAll(/const (\w+) = await sec\('(cred_[a-z_]+)'\)/g)].map((m) => [m[1], m[2]]));
// app_secrets key -> internal_credential context: cred_cron_x -> cron.x, cred_fn_x -> fn.x.
const context = (key) => key.replace(/^cred_(cron|fn)_/, '$1.');

test('static: every orphan job passes a credential read from app_secrets', () => {
  const js = jobs();
  assert.ok(js.length >= 6, 'expected at least six orphan jobs, found ' + js.length);
  for (const j of js) {
    assert.ok(j.cred, `${j.slug} is called with resilience_ping's default credential, which is not scoped to it`);
    assert.ok(credKeys[j.cred], `${j.slug} passes ${j.cred}, which is not read from app_secrets in resilience_ping`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production: each presented credential is scoped to its callee', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select context, scope from public.internal_credential where retired_at is null`);
  const scopes = new Map();
  for (const r of rows) scopes.set(r.context, [...(scopes.get(r.context) || []), ...(r.scope || [])]);
  for (const j of jobs()) {
    const ctx = context(credKeys[j.cred]);
    assert.ok(scopes.has(ctx), `${j.slug}: no active credential in context ${ctx}`);
    assert.ok(scopes.get(ctx).includes(j.slug), `${j.slug}: context ${ctx} is not scoped to it, so the call answers 403`);
  }
});
