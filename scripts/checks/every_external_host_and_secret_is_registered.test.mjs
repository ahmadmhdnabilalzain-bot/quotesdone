// EVERY EXTERNAL HOST AND EVERY SECRET THE CODE USES HAS A ROW IN THE INTEGRATION REGISTRY.
//
// it_engineer, 24 Sep 2026, founder instruction 979: the IT engineer watches every external service the company
// depends on, from ONE data-driven registry (supabase/functions/_shared/integration_registry.json), so a new
// integration is one entry, not new code. The registry is only as good as its coverage, so this FAILS when:
//   * code under supabase/functions or src calls a host no entry names (as an integration, or in not_integrations
//     with its reason);
//   * code reads an app_secrets key (sec('x'), secrets([...]), app_secrets .eq('key','x')) or an env name
//     (Deno.env.get / process.env) that no entry names;
//   * an entry's probe is malformed: an unknown kind, an http probe without url, a custom probe naming a coded
//     probe _shared/integration_watch.ts does not have, or an auth/url placeholder naming a secret no entry holds;
//   * with a Supabase management token: production app_secrets holds a key no entry names.
// Comments are stripped before the scan, so a URL in prose is not an integration. Test files and fixtures in
// *.test.* and offline *.check.* are skipped; fixtures that are not tests are covered by not_integrations with their reason.
//
//   node --test scripts/checks/every_external_host_and_secret_is_registered.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const REG = JSON.parse(readFileSync(join(REPO, 'supabase/functions/_shared/integration_registry.json'), 'utf8'));
const WATCH = readFileSync(join(REPO, 'supabase/functions/_shared/integration_watch.ts'), 'utf8');

const entries = Object.entries(REG.integrations);
const knownHosts = new Set([...entries.flatMap(([, e]) => e.hosts || []), ...Object.keys(REG.not_integrations.hosts)]);
const knownSecrets = new Set([...entries.flatMap(([, e]) => e.secrets || []), ...Object.keys(REG.internal_and_settings.secrets)]);
const knownEnv = new Set(entries.flatMap(([, e]) => e.env || []));
const prefixes = Object.keys(REG.internal_and_settings.prefixes);
const secretKnown = (k) => knownSecrets.has(k) || prefixes.some((p) => k.startsWith(p));

function* walk(d) {
  if (!existsSync(d)) return;
  for (const e of readdirSync(d)) {
    if (e === 'node_modules' || e.startsWith('.') || e === 'vendor') continue;
    const p = join(d, e);
    if (statSync(p).isDirectory()) yield* walk(p);
    // *.check.ts is an offline `deno test` file, never imported by a function and so never deployed
    // (scripts/lib/function_sources.mjs NOT_RUNTIME). 19 Nov 2026: drawing_redact/a_queued_sheet_is_checked_in_the_worker_as_on_the_edge.check.ts
    // names https://api.supabase.com/ only to intercept it in its fetch stub, and read as an unregistered host.
    else if (/\.(ts|tsx|js|mjs)$/.test(e) && !/\.(test|check)\.[a-z]+$/.test(e)) yield p;
  }
}
// THE AGENT BRIEF CITES ~80 GOVERNMENT AND PRESS URLs IT NEVER FETCHES (#1333). _shared/brief.generated.ts is
// compiled from knowledge/brief/*.md and is DATA ONLY: comments and `export const NAME = <JSON literal>;` lines.
// Only while that holds are its literals skipped as host citations; one line of code in it and it is scanned like
// every other file. No other file gets this.
export const BRIEF_GEN = 'supabase/functions/_shared/brief.generated.ts';
// A line is data when its value parses as JSON on its own: a string, number or array literal, nothing evaluated.
const DATA_HEAD = /^export const [A-Z0-9_]+(?:: [A-Za-z[\]]+)? = /;
const isDataLine = (l) => {
  const m = l.match(DATA_HEAD); if (!m || !l.endsWith(';')) return false;
  try { const v = JSON.parse(l.slice(m[0].length, -1)); return typeof v !== 'object' || Array.isArray(v); } catch { return false; }
};
export const isDataOnly = (src) => src.split(/\r?\n/).every((l) => !l.trim() || l.startsWith('//') || isDataLine(l));
// Block comments, then line comments not inside a URL (a '//' right after ':' is a scheme).
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');

export function scan(repo = REPO) {
  const hosts = new Map(), secrets = new Map(), env = new Map();
  const add = (m, k, f) => { if (!m.has(k)) m.set(k, f); };
  for (const root of ['supabase/functions', 'src']) for (const p of walk(join(repo, root))) {
    const rel = relative(repo, p).replace(/\\/g, '/');
    const s = strip(readFileSync(p, 'utf8'));
    const citationsOnly = rel === BRIEF_GEN && isDataOnly(readFileSync(p, 'utf8'));
    if (!citationsOnly) for (const m of s.matchAll(/https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/gi)) add(hosts, m[1].toLowerCase(), rel);
    // setting('x') is send_outbox's per-request reader over the canonical sec(); it reads app_secrets too.
    for (const m of s.matchAll(/\b(?:sec|setting)\(\s*'([a-z0-9_]+)'/gi)) add(secrets, m[1], rel);
    for (const m of s.matchAll(/secrets\(\s*\[([^\]]+)\]/g)) for (const k of m[1].matchAll(/'([a-z0-9_]+)'/g)) add(secrets, k[1], rel);
    for (const m of s.matchAll(/app_secrets'\)[^;]*?\.eq\('key',\s*'([a-z0-9_]+)'/g)) add(secrets, m[1], rel);
    for (const m of s.matchAll(/Deno\.env\.get\(\s*'([A-Z0-9_]+)'/g)) add(env, m[1], rel);
    for (const m of s.matchAll(/process\.env\.([A-Z0-9_]+)/g)) add(env, m[1], rel);
  }
  return { hosts, secrets, env };
}

const { hosts, secrets, env } = scan();
const missing = (m, ok) => [...m].filter(([k]) => !ok(k)).map(([k, f]) => `${k} (${f})`);

test('the scan itself sees the estate (a scan that reads nothing would pass everything)', () => {
  assert.ok(hosts.has('api.stripe.com') && secrets.has('stripe_secret_key') && env.has('SUPABASE_URL'),
    'the scan no longer finds Stripe: the patterns or the paths broke');
});

test('the agent brief is data only, so its URLs are citations, not calls', () => {
  assert.ok(isDataOnly(readFileSync(join(REPO, BRIEF_GEN), 'utf8')), BRIEF_GEN + ' holds code: regenerate it with scripts/kb/compile_brief.mjs');
  assert.ok(!isDataOnly('export const BRIEF_TEXT = "x";\nfetch("https://evil.example/")'), 'a line of code must break data-only');
  assert.ok(!isDataOnly('export const BRIEF_TEXT = "x" + await fetch("https://evil.example/");'), 'an expression is not a literal');
});

// THE SKIP ABOVE HOLDS ONLY WHILE NOTHING SHIPPED IMPORTS A TEST FILE (review of #2088, 23 Nov 2026). A runtime file that imported
// a *.check.* or *.test.* file would carry its hosts into production unscanned, so no non-test file may import one.
test('no shipped file imports a *.check.* or *.test.* file (so the scan may skip them)', () => {
  const IMPORT_TEST = /(?:\bfrom\s*|\bimport\s*\(?\s*)['"][^'"]*\.(?:check|test)\.[a-z]+['"]/;
  const offenders = [];
  for (const root of ['supabase/functions', 'src']) for (const p of walk(join(REPO, root))) {
    if (IMPORT_TEST.test(strip(readFileSync(p, 'utf8')))) offenders.push(p.slice(REPO.length));
  }
  assert.deepEqual(offenders, [], 'a shipped file imports a test file; its hosts would reach production unscanned');
});

test('every external host called by code is in the registry', () => {
  assert.deepEqual(missing(hosts, (k) => knownHosts.has(k)), [], 'add each host to an integration (or to not_integrations with why)');
});

test('every secret the code reads is in the registry', () => {
  assert.deepEqual(missing(secrets, secretKnown), [], 'add each key to its integration (or to internal_and_settings)');
});

test('every env name the code reads is in the registry', () => {
  assert.deepEqual(missing(env, (k) => knownEnv.has(k)), [], 'add each env name to its integration');
});

test('every MCP server the repository declares is in the registry', () => {
  const p = join(REPO, '.mcp.json');
  const declared = existsSync(p) ? Object.keys(JSON.parse(readFileSync(p, 'utf8')).mcpServers || {}) : [];
  assert.deepEqual(declared.filter((k) => !(k in REG.mcp_servers)), []);
});

test('every probe is runnable as written', () => {
  const bad = [];
  const customs = new Set([...WATCH.matchAll(/^\s{2}async (\w+)\(f, /gm)].map((m) => m[1]));
  for (const [k, e] of entries) {
    const p = e.probe || {};
    if (!['http', 'custom', 'covered', 'marketing'].includes(p.kind)) bad.push(`${k}: probe.kind ${p.kind}`);
    if (p.kind === 'http' && !p.url) bad.push(`${k}: http probe without url`);
    if (p.kind === 'custom' && !customs.has(p.name)) bad.push(`${k}: custom probe ${p.name} is not in integration_watch.ts`);
    if ((p.kind === 'covered' || p.kind === 'marketing') && !p.by) bad.push(`${k}: ${p.kind} without 'by'`);
    if (!e.owner_seat || !e.blast) bad.push(`${k}: owner_seat and blast are required`);
    const named = [...String(p.url || '').matchAll(/\{secret:([a-z0-9_]+)\}/g)].map((m) => m[1])
      .concat(/^(bearer|header|basic)/.test(p.auth || '') ? String(p.auth).split(':').slice(p.auth.startsWith('header') ? 2 : 1) : []);
    for (const s of named) if (!knownSecrets.has(s)) bad.push(`${k}: probe reads ${s}, which no entry holds`);
  }
  assert.deepEqual(bad, []);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: every app_secrets key is in the registry', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select key from public.app_secrets order by key`);
  assert.deepEqual(rows.map((r) => r.key).filter((k) => !secretKnown(k)), [], 'a stored key no registry entry names');
});
