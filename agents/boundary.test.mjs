// THE BOUNDARY BETWEEN THE COMPANY AND THE ESTATE IT GREW OUT OF, ASSERTED RATHER THAN DECLARED.
//
//   node --test agents/boundary.test.mjs
//
// agents/MANIFEST.json says which edge functions, tables and routines belong to the CEO seat and to
// the customer-support agent. A manifest nobody checks is a comment. This checks it, and checks it in
// BOTH directions, which is the part that matters.
//
// WHY BOTH DIRECTIONS. On 8 September 2026 public.function_owner was built by reading the LIVE
// DEPLOYMENT LIST and then checked against that same list. Eight edge functions — the entire customer
// and supplier portal backend — had already been deleted, so they had no row, so nothing measured as
// unowned, so the check reported 68 of 68 owned and went green. Meanwhile every button on /me and
// /portal returned 404 for ninety minutes.
//
// A registry derived from the thing it checks can only ever see what is PRESENT AND UNCLAIMED. It is
// structurally incapable of seeing what is MISSING. So this file compares three independent sources —
// the manifest on disk, function_owner in the database, and the live deployment list — and fails on a
// disagreement between any two of them.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const REF = 'htdblwldjkcgjvmqkbeh';

const TOKEN = process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(join(homedir(), '.supabase', 'access-token'))
      ? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim() : '');
if (!TOKEN) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
const skip = TOKEN ? false : 'no Supabase management token';

const manifest = JSON.parse(readFileSync(join(HERE, 'MANIFEST.json'), 'utf8'));
const AGENTS = manifest.agents;

const api = async (path, body) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return r.json();
};
const sql = (q) => api('/database/query', { query: q });

// ── 1. THE MANIFEST AND THE REPOSITORY ─────────────────────────────────────────────────────────
test('every edge function the manifest claims exists in the repository', () => {
  const missing = [];
  for (const [agent, spec] of Object.entries(AGENTS)) {
    for (const fn of spec.edge_functions) {
      if (!existsSync(join(ROOT, 'supabase', 'functions', fn, 'index.ts'))) missing.push(`${agent}: ${fn}`);
    }
  }
  assert.deepEqual(missing, [],
    'the manifest claims edge functions whose source is not in supabase/functions:\n  ' + missing.join('\n  ')
    + '\nEither the source was deleted and the manifest was not updated, or the name is wrong. The first '
    + 'is the shape of the 8 September portal outage.');
});

// ── 2. THE MANIFEST AND THE DATABASE, BOTH WAYS ────────────────────────────────────────────────
test('the manifest and function_owner agree, in both directions', { skip }, async () => {
  const rows = await sql(
    `select function_slug, owner from public.function_owner where owner in ('ceo','customer_support')`);
  const dbOwner = new Map(rows.map((r) => [r.function_slug, r.owner]));

  const wrongOwner = [];
  const notInDb = [];
  for (const [agent, spec] of Object.entries(AGENTS)) {
    for (const fn of spec.edge_functions) {
      if (!dbOwner.has(fn)) notInDb.push(`${fn} (manifest says ${agent})`);
      else if (dbOwner.get(fn) !== agent) wrongOwner.push(`${fn}: manifest ${agent}, database ${dbOwner.get(fn)}`);
    }
  }

  // THE DIRECTION THAT CAUGHT NOTHING ON 8 SEPTEMBER: something the database says these agents own,
  // that the manifest has never heard of.
  const claimedByDb = [];
  const inManifest = new Set(Object.values(AGENTS).flatMap((s) => s.edge_functions));
  for (const [fn, owner] of dbOwner) {
    if (!inManifest.has(fn)) claimedByDb.push(`${fn} (database says ${owner})`);
  }

  assert.deepEqual(notInDb, [], 'manifest claims a function function_owner does not record:\n  ' + notInDb.join('\n  '));
  assert.deepEqual(wrongOwner, [], 'manifest and database disagree on the owner:\n  ' + wrongOwner.join('\n  '));
  assert.deepEqual(claimedByDb, [],
    'the database says these belong to an agent and the manifest does not list them:\n  ' + claimedByDb.join('\n  ')
    + '\nAdd them to agents/MANIFEST.json, or correct the owner. An agent whose surface is bigger than '
    + 'its manifest has no boundary.');
});

// ── 3. THE MANIFEST AND WHAT IS ACTUALLY DEPLOYED ──────────────────────────────────────────────
test('every edge function the manifest claims is actually deployed', { skip }, async () => {
  const live = new Set((await api('/functions')).map((f) => f.slug));
  const notDeployed = [];
  for (const [agent, spec] of Object.entries(AGENTS)) {
    for (const fn of spec.edge_functions) if (!live.has(fn)) notDeployed.push(`${agent}: ${fn}`);
  }
  assert.deepEqual(notDeployed, [],
    'the manifest claims functions that are not deployed:\n  ' + notDeployed.join('\n  ')
    + '\nA function that exists in the repository and not in production is exactly what took the '
    + 'portals down: the app calls it and gets a 404.');
});

// ── 4. THE DATABASE OBJECTS THE MANIFEST NAMES ─────────────────────────────────────────────────
test('every table and routine the manifest names exists', { skip }, async () => {
  const tables = new Set((await sql(
    `select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind in ('r','v')`)).map((r) => r.relname));
  const routines = new Set((await sql(
    `select proname from pg_proc where pronamespace='public'::regnamespace`)).map((r) => r.proname));

  const missing = [];
  for (const [agent, spec] of Object.entries(AGENTS)) {
    for (const t of spec.tables) if (!tables.has(t)) missing.push(`${agent} table ${t}`);
    for (const r of spec.routines) if (!routines.has(r)) missing.push(`${agent} routine ${r}`);
  }
  assert.deepEqual(missing, [],
    'the manifest names database objects that do not exist:\n  ' + missing.join('\n  '));
});

// ── 5. THE NEW COMPANY DOES NOT RE-COUPLE TO THE OLD ESTATE ────────────────────────────────────
// This is the point of the whole directory. The two agents were entangled with ten departments, four
// governance phases, an event kernel and an admin console, and unpicking that has been the slowest
// work of the rebuild. Nothing written here gets to start it again.
const FORBIDDEN = [
  [/\bphase_[abcd]_[a-z_]+/g, 'the Phase A-D programme'],
  [/\bfn_phase_[abcd]_[a-z_]+/g, 'the Phase A-D programme'],
  [/\bkernel_[a-z_]+/g, 'the event kernel'],
  [/\bfn_kernel_[a-z_]+/g, 'the event kernel'],
  [/\bfounder_command[a-z_]*/g, 'the retired founder-command layer'],
  [/\bworkflow_step_run\b|\bphase_b_workflow\b/g, 'the retired workflow engine'],
  [/\borg_departments\b|\borg_tasks\b|\bdept_[a-z_]+/g, 'the removed organisation chart'],
];

const walk = (dir, out = []) => {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(sql|ts|mjs)$/.test(e)) out.push(p);
  }
  return out;
};

test('nothing under agents/ references the estate being removed', () => {
  const offences = [];
  for (const f of walk(HERE)) {
    if (f === fileURLToPath(import.meta.url)) continue;   // this file names them in order to forbid them
    const src = readFileSync(f, 'utf8');
    // Comments are where the reasoning lives, and the reasoning often has to NAME what it is avoiding.
    // Only executable text is judged.
    const code = src.replace(/--[^\n]*/g, ' ').replace(/\/\/[^\n]*/g, ' ').replace(/\/\*[\s\S]*?\*\//g, ' ');
    for (const [re, what] of FORBIDDEN) {
      const hit = code.match(re);
      if (hit) offences.push(`${f.replace(ROOT, '').replace(/\\/g, '/')}: ${hit[0]} — ${what}`);
    }
  }
  assert.deepEqual(offences, [],
    'agents/ references the estate being removed:\n  ' + offences.join('\n  ')
    + '\nThe whole reason this directory exists is that the two agents were entangled with a company '
    + 'that no longer exists, and unpicking it has been the slowest work of the rebuild. Do not start '
    + 'again. If an agent genuinely needs something from the old estate, that thing needs re-homing '
    + 'under the agent first.');
});
