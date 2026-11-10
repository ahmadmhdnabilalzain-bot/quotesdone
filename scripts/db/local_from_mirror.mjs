// BUILD A LOCAL COPY OF THE PRODUCTION SCHEMA FROM THE REPOSITORY ALONE (it_engineer, 9 Nov 2026).
//
// Why this exists. Until today nothing in the repository could rebuild the database: supabase/migrations
// replays 414 tables, 8 functions and 0 policies against 784 tables, 2,045 functions, 88 views and 350
// policies in production, and every change is a scripts/sql file applied to production. So a defect could
// only be reproduced against production itself, which is why fixes looped. The schema mirror
// (supabase/schema/full_schema/, regenerated from public.fn_schema_export() after every apply) holds the
// whole live definition, but replaying it as committed fails, for two measured reasons:
//
//   1. fn_schema_export() prints every routine with pg_get_functiondef(), which ends a definition at its
//      closing $function$ WITHOUT a semicolon. psql therefore reads the whole FUNCTIONS section (2,045
//      routines, ~91,000 lines) as ONE statement and drops all of it with a single syntax error.
//   2. The export has no CREATE TYPE, so the two enums the tables use (answer_precedence, gate_state)
//      do not exist, and every table and routine that names them fails.
//
// What this does: take the mirror (scripts/lib/schema_mirror.mjs), terminate each routine, put the enum
// definitions in front (read from the SQL history, last definition wins), turn off function-body
// validation exactly as pg_dump does (production holds routines whose bodies name since-dropped routines;
// that is a production finding, see below, and the local copy must reproduce production, not repair it),
// and apply it to the local Supabase Postgres in passes until no new object appears (the export's order
// is best-effort: a generated column can name a routine defined later). Then it MEASURES: every table,
// view, routine, policy, trigger and cron job named in the mirror is looked up in the local catalog, and
// the run fails if any is missing.
//
// SAFETY. The mirror schedules ~92 pg_cron jobs. A local copy must never run them (they would call
// edge functions). Each cron.schedule() call is rewritten to schedule the job and switch it off in the
// same statement, so no job is ever active at commit. The local database holds no row data and no
// secret values (the mirror carries neither), so nothing in it can reach a real person.
//
//   supabase start                                    # once: the local stack (needs Docker)
//   node scripts/db/local_from_mirror.mjs             # build + measure; exit 1 on any missing object
//   node scripts/db/local_from_mirror.mjs --sql-only=/tmp/schema.sql   # just write the replayable SQL
//   --container=<name>   the local Postgres container (default: the one `supabase start` runs, found by name)
//   --passes=<n>         maximum replay passes (default 6)
//
// Runbook: docs/runbooks/local-database.md.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdtempSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const arg = (n, d) => { const a = process.argv.find((x) => x.startsWith(`--${n}=`)); return a ? a.split('=').slice(1).join('=') : d; };

// ── 1. The replayable SQL ────────────────────────────────────────────────────────────────────────────
/** Every SQL file in apply order: migrations_history, migrations, then scripts/sql in MANIFEST order. */
function sqlHistory() {
  const dir = (d) => (existsSync(join(REPO, d)) ? readdirSync(join(REPO, d)).filter((f) => f.endsWith('.sql')).sort().map((f) => `${d}/${f}`) : []);
  const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
  return [...dir('supabase/migrations_history'), ...dir('supabase/migrations'), ...manifest].filter((f) => existsSync(join(REPO, f)));
}

/** The enum/composite types the mirror omits, last definition in apply order wins; plus every ADD VALUE. */
export function typeDefinitions(files = sqlHistory()) {
  const types = new Map(); const adds = [];
  for (const f of files) {
    const t = readFileSync(join(REPO, f), 'utf8');
    for (const m of t.matchAll(/create\s+type\s+(?:if\s+not\s+exists\s+)?((?:public\.)?"?[a-z_0-9]+"?)\s+as\s+(enum\s*\([^;]*\)|\([^;]*\))\s*;/gi)) {
      const name = m[1].replace(/"/g, '').replace(/^public\./, '');
      types.set(name, `DO $qd_type$ BEGIN CREATE TYPE public.${name} AS ${m[2]}; EXCEPTION WHEN duplicate_object THEN NULL; END $qd_type$;`);
    }
    for (const m of t.matchAll(/alter\s+type\s+((?:public\.)?[a-z_0-9]+)\s+add\s+value\s+(?:if\s+not\s+exists\s+)?('[^']*')/gi))
      adds.push(`ALTER TYPE public.${m[1].replace(/^public\./, '')} ADD VALUE IF NOT EXISTS ${m[2]};`);
  }
  return { names: [...types.keys()], sql: [...types.values(), ...adds].join('\n') };
}

/** The mirror made replayable: routines terminated, cron jobs created switched off. */
export function replayableMirror(mirror = readSchemaMirror()) {
  const lines = mirror.split('\n');
  let terminated = 0;
  for (let i = 0; i < lines.length; i++) {
    // pg_get_functiondef ends a body with $function$ (on its own line or after the last body text) and
    // no semicolon. The OPENING line is exactly "AS $function$" and is left alone.
    if (/\$function\$\s*$/.test(lines[i]) && lines[i].trim() !== 'AS $function$') { lines[i] = lines[i].replace(/\$function\$\s*$/, '$function$;'); terminated++; }
  }
  let sql = lines.join('\n');
  let cron = 0;
  // Only the export's own top-level schedule statements; routine bodies that mention cron.schedule are code.
  sql = sql.replace(/^select\s+cron\.schedule\(/gim, () => { cron++; return 'select qd_local.schedule_off('; });
  return { sql, terminated, cron };
}

const PRELUDE = `
-- local_from_mirror.mjs prelude: reproduce production as it is (pg_dump does the same), never run its jobs.
SET check_function_bodies = off;
CREATE SCHEMA IF NOT EXISTS qd_local;
CREATE OR REPLACE FUNCTION qd_local.schedule_off(p_name text, p_schedule text, p_command text) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
  v := cron.schedule(p_name, p_schedule, p_command);
  PERFORM cron.alter_job(v, active := false);   -- same transaction: the job is never active at commit
  RETURN v;
END $$;
`;

export function buildSql() {
  const types = typeDefinitions();
  const m = replayableMirror();
  return { sql: `${PRELUDE}\n${types.sql}\n${m.sql}\n`, types: types.names, terminated: m.terminated, cron: m.cron };
}

// ── 2. What the mirror says production holds, to measure the local copy against ──────────────────────
export function expectedObjects(mirror = readSchemaMirror()) {
  const set = (re) => new Set([...mirror.matchAll(re)].map((x) => x.slice(1).filter(Boolean).join('.').toLowerCase()));
  return {
    tables: set(/^CREATE TABLE (?:IF NOT EXISTS )?public\.("?[A-Za-z0-9_]+"?) /gm),
    views: set(/^CREATE (?:OR REPLACE )?(?:MATERIALIZED )?VIEW public\.("?[A-Za-z0-9_]+"?) /gm),
    routines: set(/^CREATE OR REPLACE (?:FUNCTION|PROCEDURE) public\.("?[A-Za-z0-9_]+"?)\(/gm),
    policies: set(/^CREATE POLICY ("?[^"\n]+?"?) ON public\.("?[A-Za-z0-9_]+"?)\b/gm),
    triggers: set(/^CREATE (?:CONSTRAINT )?TRIGGER ("?[A-Za-z0-9_]+"?) .*? ON public\.("?[A-Za-z0-9_]+"?)\b/gm),
    cron_jobs: set(/^select cron\.schedule\('([^']+)'/gim),
  };
}

const CATALOG_SQL = `
select 'tables'::text, c.relname::text from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')
union all select 'views', c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('v','m')
union all select distinct 'routines', p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
union all select 'policies', policyname::text || '.' || tablename::text from pg_policies where schemaname='public'
union all select 'triggers', t.tgname::text || '.' || c.relname::text from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal
union all select 'cron_jobs', jobname from cron.job
union all select 'cron_active', jobname from cron.job where active;`;

// ── 3. Apply and measure ─────────────────────────────────────────────────────────────────────────────
function docker(args, input) {
  const r = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.error) throw r.error;
  return r;
}
function findContainer() {
  const r = docker(['ps', '--format', '{{.Names}}']);
  const names = r.stdout.split('\n').filter((n) => /^supabase_db_/.test(n));
  if (names.length !== 1) throw new Error(`expected exactly one running supabase_db_* container (run \`supabase start\`), found: ${names.join(', ') || 'none'}; or pass --container=`);
  return names[0];
}
const psql = (container, file, extra = []) => docker(['exec', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=0', '-q', ...extra, '-f', file]);

function main() {
  const built = buildSql();
  const only = arg('sql-only', null);
  if (only) { writeFileSync(only, built.sql); console.log(`wrote ${only}: ${built.terminated} routines terminated, ${built.types.length} types (${built.types.join(', ')}), ${built.cron} cron jobs created switched off`); return 0; }

  const container = arg('container', null) || findContainer();
  const work = mkdtempSync(join(tmpdir(), 'qd-localdb-'));
  writeFileSync(join(work, 'schema.sql'), built.sql);
  writeFileSync(join(work, 'catalog.sql'), CATALOG_SQL);
  docker(['cp', join(work, 'schema.sql'), `${container}:/tmp/qd_schema.sql`]);
  docker(['cp', join(work, 'catalog.sql'), `${container}:/tmp/qd_catalog.sql`]);

  // A re-run reports "already exists" / "multiple primary keys" for what the previous pass made: noise.
  const NOISE = /already exists|multiple primary keys/;
  const maxPasses = Number(arg('passes', '6'));
  let previous = null; let last = [];
  for (let pass = 1; pass <= maxPasses; pass++) {
    const r = psql(container, '/tmp/qd_schema.sql');
    last = (r.stderr + r.stdout).split('\n').filter((l) => /ERROR:/.test(l) && !NOISE.test(l));
    console.log(`pass ${pass}: ${last.length} errors that are not re-run noise`);
    const key = last.map((l) => l.replace(/^psql:[^:]+:\d+: /, '')).sort().join('\n');
    if (key === previous) break;
    previous = key;
  }

  const cat = docker(['exec', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-tA', '-F', '\t', '-f', '/tmp/qd_catalog.sql']).stdout;
  const have = {};
  for (const line of cat.split('\n')) { const [k, v] = line.split('\t'); if (k && v) (have[k] ||= new Set()).add(v.toLowerCase()); }
  const strip = (s) => s.replace(/"/g, '');
  const expected = expectedObjects();
  let missingTotal = 0;
  console.log('\nkind        mirror  local  missing');
  for (const [kind, names] of Object.entries(expected)) {
    const got = have[kind] || new Set();
    const missing = [...names].map(strip).filter((n) => !got.has(n));
    missingTotal += missing.length;
    console.log(`${kind.padEnd(11)} ${String(names.size).padStart(6)} ${String(got.size).padStart(6)} ${String(missing.length).padStart(8)}${missing.length ? '  ' + missing.slice(0, 8).join(', ') + (missing.length > 8 ? ', …' : '') : ''}`);
  }
  const active = have.cron_active ? have.cron_active.size : 0;
  console.log(`cron jobs active locally: ${active} (must be 0)`);
  if (last.length) console.log(`\nresidual errors (production holds these objects in this state; see docs/runbooks/local-database.md):\n${last.map((l) => '  ' + l.replace(/^psql:[^:]+:\d+: /, '')).join('\n')}`);
  const ok = missingTotal === 0 && active === 0;
  console.log(ok ? '\nLOCAL DATABASE MATCHES THE MIRROR' : '\nLOCAL DATABASE IS INCOMPLETE');
  return ok ? 0 : 1;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
