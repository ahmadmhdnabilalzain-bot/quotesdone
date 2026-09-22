// NO FUNCTION CALLS AN EDGE FUNCTION THAT IS NOT DEPLOYED (customer_support, 22 Sep 2026).
//
// Measured 22 Sep 2026, wa_messages 271: the founder asked "What sectors you cover" on WhatsApp and
// wa_inbound POSTed to agent_brain, which the 137-function sweep of 7 Sep 2026 deleted. The URL answered
// 404 and the reply he received quoted it: "(agent_brain returned no reply (HTTP 404))". The same sweep
// left supplier_api calling profile_ai and supplier_review on every registration, answered by 404 each
// time. Nothing failed loudly: a call to a function that is gone deploys, type-checks and runs.
//
// THE REGISTRY is supabase/config.toml: every deployed function has a [functions.<slug>] block
// (scripts/gen_supabase_config.mjs writes it from the deployed list, and every_deployed_function_has_an_
// owner.mjs holds it to production). A callee is any slug named after /functions/v1/ in
//   - edge-function source (supabase/functions/**/*.ts, tests excluded), as a literal URL, as
//     `<BASE> + '/<slug>'` or as `${BASE}/<slug>` where BASE is a constant ending in /functions/v1;
//   - the live schema mirror supabase/schema/full_schema.sql (routines and cron commands).
// Comment lines are skipped: they may name the defect, code may not repeat it.
//
//   node --test scripts/checks/no_function_calls_an_undeployed_function.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FN_DIR = path.join(REPO, 'supabase/functions');

export function deployedSlugs(configToml) {
  return new Set([...configToml.matchAll(/^\[functions\.([a-z0-9_-]+)\]/gm)].map((m) => m[1]));
}

/** Every edge-function slug a TypeScript source calls. */
export function calleesInTs(src) {
  const code = src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
  const out = new Set();
  for (const m of code.matchAll(/\/functions\/v1\/([a-z][a-z0-9_-]*)/g)) out.add(m[1]);
  // Constants holding the functions base: const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
  const bases = [...code.matchAll(/\b(?:const|let)\s+([A-Za-z_$][\w$]*)\s*=[^;\n]*\/functions\/v1['"`]\s*\)?\s*;?/g)].map((m) => m[1]);
  for (const b of bases) {
    const e = b.replace(/\$/g, '\\$');
    for (const m of code.matchAll(new RegExp('\\b' + e + "\\s*\\+\\s*['\"`]/([a-z][a-z0-9_-]*)", 'g'))) out.add(m[1]);
    for (const m of code.matchAll(new RegExp('\\$\\{' + e + '\\}/([a-z][a-z0-9_-]*)', 'g'))) out.add(m[1]);
  }
  return out;
}

/** Every slug the schema mirror calls (net.http_post to /functions/v1/<slug>, cron commands). */
export function calleesInSql(sql) {
  const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  return new Set([...code.matchAll(/\/functions\/v1\/([a-z][a-z0-9_-]*)/g)].map((m) => m[1]));
}

function tsFiles(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...tsFiles(p));
    else if (/\.ts$/.test(e.name) && !/\.test\.ts$/.test(e.name)) out.push(p);
  }
  return out;
}

test('the detector sees the shapes the estate actually uses', () => {
  const wa = "const FNBASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';\nawait fetch(FNBASE + '/agent_brain', {});";
  assert.deepEqual([...calleesInTs(wa)], ['agent_brain']);
  assert.deepEqual([...calleesInTs('await fetch(`${SUPA_URL}/functions/v1/profile_ai`)')], ['profile_ai']);
  assert.deepEqual([...calleesInTs("const FN = x + '/functions/v1';\nfetch(`${FN}/kyc`)")], ['kyc']);
  assert.deepEqual([...calleesInTs("// fetch(FN + '/gone') named in a comment\nconst y = 1;")], []);
  assert.deepEqual([...calleesInSql("select net.http_post(url := base || '/functions/v1/send_outbox');")], ['send_outbox']);
  assert.ok(deployedSlugs('[functions.wa_inbound]\nverify_jwt = false\n[functions.send_outbox]\n').has('send_outbox'));
});

test('every edge function called from edge-function source is deployed', () => {
  const deployed = deployedSlugs(fs.readFileSync(path.join(REPO, 'supabase/config.toml'), 'utf8'));
  assert.ok(deployed.size > 20, 'config.toml lists ' + deployed.size + ' functions; the registry did not parse');
  const missing = [];
  for (const f of tsFiles(FN_DIR)) {
    for (const slug of calleesInTs(fs.readFileSync(f, 'utf8'))) {
      if (!deployed.has(slug)) missing.push(path.relative(REPO, f).replace(/\\/g, '/') + ' -> ' + slug);
    }
  }
  assert.deepEqual(missing, [], 'calls to functions that are not deployed (no [functions.<slug>] in supabase/config.toml)');
});

test('every edge function called from the database is deployed', () => {
  const deployed = deployedSlugs(fs.readFileSync(path.join(REPO, 'supabase/config.toml'), 'utf8'));
  const mirror = path.join(REPO, 'supabase/schema/full_schema.sql');
  const missing = [...calleesInSql(fs.readFileSync(mirror, 'utf8'))].filter((s) => !deployed.has(s));
  assert.deepEqual(missing, [], 'routines or cron commands in the schema mirror call functions that are not deployed');
});

test('every deployed function in the registry has its source in the repository', () => {
  const deployed = deployedSlugs(fs.readFileSync(path.join(REPO, 'supabase/config.toml'), 'utf8'));
  const absent = [...deployed].filter((s) => !fs.existsSync(path.join(FN_DIR, s, 'index.ts')));
  assert.deepEqual(absent, []);
});
