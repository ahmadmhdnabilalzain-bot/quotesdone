#!/usr/bin/env node
// THE LOCAL DATABASE A REHEARSAL RUNS ON (it_engineer, 13 Nov 2026). Runbook: docs/runbooks/local-database.md.
//
// Why. On 13 Nov 2026 rolled-back rehearsals on PRODUCTION held quotes and inquiries for 12-15 s at a time; 103 live requests
// waited behind 28 of them and the live role's 8 s statement_timeout cancelled a supplier's certificate write, a quotation's
// approval and a customer's acceptance of the terms (scripts/lib/replay_guard.mjs). Since then a replay (scripts/lib/safe_replay.mjs)
// runs here by default, and on production only with QD_REPLAY_ON_PRODUCTION=1, cut at 5 s. This builds the "here": a plain
// Postgres 16 cluster, no Docker, from the schema mirror (supabase/schema/full_schema/ via local_from_mirror.mjs --sql-only),
// with the platform's stand-ins (local_standins.sql) and the seed rows the probes read. It holds no row data and no secret.
// Every cron job is created switched off, and net.http_post only queues a row: nothing in it can reach a person.
//
//   node scripts/db/local_pg16.mjs start   # init + start the cluster, and load the schema if it is empty (about 2-4 minutes)
//   node scripts/db/local_pg16.mjs load    # (re)load the schema, stand-ins and seeds into the running cluster, then count
//   node scripts/db/local_pg16.mjs url     # print the URL for QD_LOCAL_DB_URL
//   node scripts/db/local_pg16.mjs stop    # stop the cluster and delete its directory
//   export QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)"
//
// QD_LOCAL_PG_DIR (default /tmp/pg-qd: never under the session's sandbox tmp, whose permissions are reset), QD_LOCAL_PG_PORT (default 55433), QD_PG_BIN (default /usr/lib/postgresql/16/bin).
// Run as root it runs the server as the `postgres` user (initdb refuses root). The cluster listens on a Unix socket in its own
// directory only, never on a network port. Postgres 16 has no transaction_timeout: the 5 s cut is production's guard, not this.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const REPO = join(import.meta.dirname, '..', '..');
const DIR = process.env.QD_LOCAL_PG_DIR || '/tmp/pg-qd';
const PORT = process.env.QD_LOCAL_PG_PORT || '55433';
const BIN = process.env.QD_PG_BIN || '/usr/lib/postgresql/16/bin';
const DATA = join(DIR, 'data');
const ROOT = process.getuid?.() === 0;
export const url = () => `postgresql://postgres@${encodeURIComponent(DIR)}:${PORT}/postgres`;

const say = (m) => process.stderr.write(`local_pg16: ${m}\n`);
function as(exe, args, opts = {}) {
  const r = ROOT ? spawnSync('runuser', ['-u', 'postgres', '--', join(BIN, exe), ...args], { encoding: 'utf8', ...opts })
    : spawnSync(join(BIN, exe), args, { encoding: 'utf8', ...opts });
  if (r.error) throw r.error;
  return r;
}
const psql = (args, input) => spawnSync('psql', ['-X', '-h', DIR, '-p', PORT, '-U', 'postgres', '-d', 'postgres', ...args],
  { encoding: 'utf8', input, maxBuffer: 256 << 20 });
const one = (q) => String(psql(['-qAt', '-c', q]).stdout).trim();
const running = () => existsSync(join(DATA, 'postmaster.pid')) && as('pg_ctl', ['-D', DATA, 'status']).status === 0;

function start() {
  if (!existsSync(join(BIN, 'initdb'))) { say(`no Postgres 16 at ${BIN} (set QD_PG_BIN)`); process.exit(2); }
  mkdirSync(DIR, { recursive: true });
  if (ROOT) spawnSync('chown', ['postgres', DIR]);
  if (!existsSync(join(DATA, 'PG_VERSION'))) {
    const r = as('initdb', ['-D', DATA, '-A', 'trust', '-U', 'postgres', '-E', 'UTF8', '--no-locale']);
    if (r.status !== 0) { say(`initdb failed: ${r.stderr}`); process.exit(1); }
  }
  if (!running()) {
    const r = as('pg_ctl', ['-D', DATA, '-l', join(DIR, 'server.log'), '-w', '-o', `-p ${PORT} -k ${DIR} -c listen_addresses=''`, 'start']);
    if (r.status !== 0) { say(`the server did not start: ${r.stderr}${r.stdout}`); process.exit(1); }
  }
  if (one("select to_regclass('public.app_secrets') is not null") !== 't') load();
  else say(`running, schema already loaded: ${url()}`);
}

function load() {
  if (!running()) { say('the cluster is not running: node scripts/db/local_pg16.mjs start'); process.exit(1); }
  const t0 = Date.now();
  const raw = join(DIR, 'schema.sql');
  const b = spawnSync(process.execPath, [join(REPO, 'scripts/db/local_from_mirror.mjs'), `--sql-only=${raw}`], { encoding: 'utf8', cwd: REPO });
  if (b.status !== 0) { say(`the mirror did not build: ${b.stderr}`); process.exit(1); }
  const [standins, seeds] = readFileSync(join(REPO, 'scripts/db/local_standins.sql'), 'utf8').split('-- @@ SEEDS');
  const s = psql(['-q', '-f', '-'], standins);
  if (s.status !== 0) { say(`the stand-ins failed: ${s.stderr}`); process.exit(1); }
  // what a plain Postgres 16 does not have: the platform's extensions (stood in above) and pgvector (a real[] keeps the column)
  const local = readFileSync(raw, 'utf8')
    .replace(/^CREATE EXTENSION IF NOT EXISTS (pg_cron|pg_net|supabase_vault|vector|pg_stat_statements|pgcrypto|"uuid-ossp"|pg_trgm|plpgsql)\b.*$/gim, '')
    .replace(/\bvector\(\d+\)/g, 'real[]').replace(/\bpublic\.vector\b/g, 'real[]');
  writeFileSync(join(DIR, 'local.sql'), local);
  // the export's order is best-effort (a generated column names a routine defined later): passes until nothing new appears
  let last = -1;
  for (let pass = 1; pass <= 6; pass++) {
    psql(['-q', '-f', join(DIR, 'local.sql')]);
    const n = Number(one("select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'"))
      + Number(one("select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'"));
    say(`pass ${pass}: ${n} public relations and routines`);
    if (n === last) break;
    last = n;
  }
  const sd = psql(['-q', '-v', 'ON_ERROR_STOP=1', '-f', '-'], '-- @@ SEEDS' + seeds);
  if (sd.status !== 0) { say(`the seeds failed: ${sd.stderr}`); process.exit(1); }
  const count = (q) => one(q);
  say(`loaded in ${Math.round((Date.now() - t0) / 1000)} s: ${count("select count(*) from pg_tables where schemaname='public'")} tables, `
    + `${count("select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'")} routines, `
    + `${count("select count(*) from pg_policies where schemaname='public'")} policies, `
    + `${count('select count(*) from pg_trigger where not tgisinternal')} triggers, `
    + `${count('select count(*) from cron.job')} cron jobs (${count('select count(*) from cron.job where active')} active)`);
  say(`export QD_LOCAL_DB_URL="${url()}"`);
}

function stop() {
  if (existsSync(DATA) && running()) as('pg_ctl', ['-D', DATA, '-m', 'fast', '-w', 'stop']);
  rmSync(DIR, { recursive: true, force: true });
  say(`stopped and removed ${DIR}`);
}

const cmd = process.argv[2];
if (import.meta.url === `file://${process.argv[1]}`) {
  if (cmd === 'start') start();
  else if (cmd === 'load') load();
  else if (cmd === 'stop') stop();
  else if (cmd === 'url') process.stdout.write(url() + '\n');
  else { console.error('usage: node scripts/db/local_pg16.mjs start | load | stop | url'); process.exit(2); }
}
