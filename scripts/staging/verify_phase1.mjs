// verify_phase1.mjs — is staging actually deployed, isolated, and in sync with the repo?
//
// Phase 1's completion standard is not "the work was done", it is that the claims survive being
// checked against the live systems. Every line below is a measurement, not an assertion. It is
// read-only and refuses to target production.
//
//   node scripts/staging/verify_phase1.mjs
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF, assertNotProduction } from './qd_guard.mjs';

// REHOMED 15 AUG 2026: this defaulted to 'pglpqrhvozwepymcuunn', a project deleted that morning.
// The target now comes from demo_factory, which is the single place that decides it.
import { REF } from './demo_factory.mjs';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const rows = [];
const check = (area, name, ok, detail) => {
  rows.push({ ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${area.padEnd(10)} ${name.padEnd(36)} ${detail}`);
};
const sh = (c) => { try { return execSync(c, { encoding: 'utf8' }).trim(); } catch { return ''; } };

// ---- 1. repo in sync -------------------------------------------------------------------------
const dirty = sh('git status --porcelain').split('\n').filter(l => l.trim() && !l.startsWith('??'));
check('repo', 'no uncommitted tracked changes', dirty.length === 0, `${dirty.length} modified`);

const local = sh('git rev-parse HEAD');
const remote = sh('git rev-parse @{u}');
check('repo', 'pushed to origin', !!local && local === remote, `${local.slice(0, 7)} vs ${remote.slice(0, 7)}`);

// ---- 2. functions deployed --------------------------------------------------------------------
const repoFns = readdirSync('supabase/functions', { withFileTypes: true })
  .filter(d => d.isDirectory() && !d.name.startsWith('_')).map(d => d.name);
const live = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/functions`,
  { headers: { Authorization: 'Bearer ' + token } })).json();
const liveSlugs = new Set(live.map(f => f.slug));
const notDeployed = repoFns.filter(s => !liveSlugs.has(s));
check('deploy', 'every repo function is deployed', notDeployed.length === 0,
  `${liveSlugs.size} live / ${repoFns.length} in repo${notDeployed.length ? ' - missing ' + notDeployed.join(' ') : ''}`);

// config.toml pins verify_jwt; live must agree or the auth posture is not what git says it is.
const cfg = readFileSync('supabase/config.toml', 'utf8');
const pinned = new Map();
for (const m of cfg.matchAll(/^\[functions\.([A-Za-z0-9_-]+)\]\s*\r?\nverify_jwt\s*=\s*(true|false)/gm)) {
  pinned.set(m[1], m[2] === 'true');
}
const jwtDrift = live.filter(f => pinned.has(f.slug) && pinned.get(f.slug) !== f.verify_jwt);
check('deploy', 'verify_jwt matches config.toml', jwtDrift.length === 0,
  `${jwtDrift.length} drifted, ${live.filter(f => f.verify_jwt).length} require a JWT`);

// ---- 3. schema parity with production ----------------------------------------------------------
const shape = `select
  (select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE') as tables,
  (select count(*) from information_schema.views where table_schema='public') as views,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') as routines,
  (select count(*) from information_schema.columns where table_schema='public') as cols`;
const [p] = await mgmtRead(PROD_REF, shape);
const [s] = await mgmtRead(REF, shape);
for (const k of ['tables', 'views', 'routines', 'cols']) {
  check('schema', `${k} match production`, Number(p[k]) === Number(s[k]), `production ${p[k]}, staging ${s[k]}`);
}

// ---- 4. isolation -------------------------------------------------------------------------------
// The 3-4 Aug incident was branch crons calling production for eighteen hours. Zero is the only
// acceptable answer here until a cron is deliberately armed.
const [{ n: crons }] = await mgmtRead(REF, 'select count(*)::int as n from cron.job');
check('isolate', 'no cron jobs armed on staging', Number(crons) === 0, `${crons} job(s)`);

// A staging routine carrying the production ref calls production from staging.
const [{ n: leaks }] = await mgmtRead(REF,
  `select count(*)::int as n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prokind = 'f'
     and pg_get_functiondef(p.oid) like '%${PROD_REF}%'`);
check('isolate', 'no routine references production', Number(leaks) === 0, `${leaks} routine(s)`);

const [{ n: liveKeys }] = await mgmtRead(REF,
  `select count(*)::int as n from public.app_secrets
   where key in ('stripe_secret_key','stripe_publishable_key','vercel_token','github_token')`);
check('isolate', 'no live payment or deploy tokens', Number(liveKeys) === 0, `${liveKeys} present`);

// ---- 5. forward migrations ------------------------------------------------------------------------
// Phase 1 asks that "migrations can move forward from a known baseline". That requires the
// migration ledger to exist and to record where staging actually is.
// The ledger has to agree with production, not merely exist. Staging's schema was rebuilt from
// production's baseline, but its ledger still claimed 31 migrations with the newest dated June -
// the remnant of the original failed branch replay. A `supabase db push` against that state would
// have tried to replay 254 migrations the schema already contained. A ledger that understates how
// far a database has come is worse than an empty one, because tooling believes it.
const LEDGER = 'select count(*)::int as n, max(version) as newest from supabase_migrations.schema_migrations';
let applied = -1, newest = null;
try { const [r] = await mgmtRead(REF, LEDGER); applied = Number(r.n); newest = r.newest; } catch { /* absent */ }
const [pl] = await mgmtRead(PROD_REF, LEDGER);
const repoMigrations = readdirSync('supabase/migrations').filter(f => f.endsWith('.sql')).length;
check('migrate', 'ledger matches production', applied === Number(pl.n) && newest === pl.newest,
  `staging ${applied}@${newest}, production ${pl.n}@${pl.newest}, ${repoMigrations} files in repo`);

const pass = rows.filter(r => r.ok).length;
console.log(`\nPHASE 1 VERIFY ${pass}/${rows.length} on ${REF}`);
process.exitCode = pass === rows.length ? 0 : 1;
