// DRILLS D8 and D9 (docs/release/qualification_matrix.md §5.1): a seat duty that throws, and a duty
// whose own job stops ticking. Seat accountable: it_engineer (duties and infrastructure).
//
// The dispatcher is SQL: resilience_ping's `seatDuties` step calls public.fn_seat_duties_tick, which
// runs each due public.seat_duty through fn_seat_duty_run in its own sub-transaction and turns
// fn_seat_duty_health's problems into it_engineer_finding rows. So this drill runs the REAL routines on a
// THROWAWAY Postgres 16 (the recipe in .claude/memory/the-otp-race-step-runs-on-a-throwaway-postgres-in-
// the-cloud-container.md, on port 55433), never production. Each routine is loaded from the file
// scripts/sql/MANIFEST.txt makes canonical (the LAST file in apply order that defines it), and each table
// from supabase/schema/full_schema, so the drill cannot drift onto a copy. Fixtures are ZZ DEMO duties.
//
// Start the cluster (as the postgres user; it refuses root), then run with the suite's flags:
//   runuser -u postgres -- bash -c 'D=/var/lib/postgresql/qd-drill-d9; mkdir -p $D; echo drill > $D/pw;
//     /usr/lib/postgresql/16/bin/initdb -D $D/data -U postgres --auth=md5 --pwfile=$D/pw;
//     /usr/lib/postgresql/16/bin/pg_ctl -D $D/data -o "-p 55433 -k $D -c listen_addresses=127.0.0.1" -l $D/log -w start'
// With no cluster listening the tests are IGNORED and say so in their names; they never pass empty.
//
// Expected, in the matrix's terms (D9): the throwing duty is isolated, the others run, a finding opens.
// D8: a duty whose own job stopped is detected and a finding opens; it closes when the duty runs again.
// The known-bad control is the throwing duty itself (its error is recorded); the positive control is the
// two healthy duties writing their rows in the same tick.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import postgres from 'npm:postgres@3.4.5';

const PORT = 55433;
const REPO = new URL('../../../', import.meta.url);
const up = await Deno.connect({ hostname: '127.0.0.1', port: PORT }).then((c) => { c.close(); return true; }).catch(() => false);
const NOT_RUN = up ? '' : ` [NOT RUN: no throwaway Postgres on 127.0.0.1:${PORT}]`;

const TABLES = ['org_role', 'seat_duty', 'duty_pause', 'seat_duty_skip', 'it_engineer_finding'];
const ROUTINES = ['fn_it_engineer_severity', 'fn_it_engineer_finding_upsert', 'fn_seat_duty_routine_exists', 'fn_seat_duty_health',
  'fn_seat_duty_isolate', 'fn_seat_duty_run', 'fn_seat_duties_tick'];

function tableDdl(dump: string, t: string): string {
  const start = dump.indexOf(`CREATE TABLE IF NOT EXISTS public.${t} (`);
  if (start < 0) throw new Error('no CREATE TABLE for ' + t + ' in the schema dump');
  const ddl = dump.slice(start, dump.indexOf('\n);', start) + 3);
  // its primary key and checks; foreign keys are left out (their targets are not part of this drill)
  const cons = dump.split('\n').filter((l) => l.startsWith(`ALTER TABLE public.${t} ADD CONSTRAINT`) && !/FOREIGN KEY/.test(l));
  return [ddl, ...cons].join('\n');
}
/** The canonical definition: the last MANIFEST file that defines the routine, and the last definition in it. */
async function canonical(fn: string, manifest: string[]): Promise<{ file: string; sql: string }> {
  const head = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'gi');
  for (let i = manifest.length - 1; i >= 0; i--) {
    const text = await Deno.readTextFile(new URL(manifest[i], REPO)).catch(() => '');
    const hits = [...text.matchAll(head)];
    if (!hits.length) continue;
    const at = hits.at(-1)!.index!;
    const tag = text.slice(at).match(/\bas\s+(\$[a-z_]*\$)/i)![1];
    const open = text.indexOf(tag, at);
    const close = text.indexOf(tag, open + tag.length);
    return { file: manifest[i], sql: text.slice(at, close + tag.length) + ';' };
  }
  throw new Error('no definition of ' + fn + ' in any MANIFEST file');
}

// Every option postgres.js would otherwise read from PG* environment variables is given, because the suite
// grants env access to three names only (scripts/checks/run.mjs).
const OPTS = { host: '127.0.0.1', port: PORT, user: 'postgres', password: 'drill', max: 1, ssl: false, idle_timeout: 0,
  connect_timeout: 5, max_lifetime: 0, max_pipeline: 100, backoff: () => 0.1, keep_alive: 60, prepare: false, debug: false,
  fetch_types: false, publications: 'alltables', target_session_attrs: 'primary', onnotice: () => {} } as unknown as postgres.Options<Record<string, never>>;
let sql: ReturnType<typeof postgres> | null = null;
const loaded: Record<string, string> = {};
async function db() {
  if (sql) return sql;
  const admin = postgres({ ...OPTS, database: 'postgres' });
  await admin.unsafe('drop database if exists qd_drill_d9');
  await admin.unsafe('create database qd_drill_d9');
  await admin.end();
  sql = postgres({ ...OPTS, database: 'qd_drill_d9' });
  const dump = await Deno.readTextFile(new URL('supabase/schema/full_schema/01_extensions_sequences_tables_constraints_indexes.sql', REPO));
  for (const t of TABLES) await sql.unsafe(tableDdl(dump, t));
  const manifest = (await Deno.readTextFile(new URL('scripts/sql/MANIFEST.txt', REPO))).split('\n').map((l) => l.trim()).filter((l) => /^scripts\/sql\/[^ ]+\.sql$/.test(l));
  // A file committed but not yet applied (scripts/sql/pending/<name>.txt) is the next definition in apply order, so it
  // is loaded after the MANIFEST: the drill measures the fix that will be applied at merge, not only what is live.
  for (const e of Deno.readDirSync(new URL('scripts/sql/pending/', REPO))) if (e.name.endsWith('.txt')) {
    const f = 'scripts/sql/' + e.name.replace(/\.txt$/, '.sql');
    if (await Deno.stat(new URL(f, REPO)).then(() => true).catch(() => false)) manifest.push(f);
  }
  for (const fn of ROUTINES) { const c = await canonical(fn, manifest); loaded[fn] = c.file; await sql.unsafe(c.sql); }
  // ZZ DEMO fixtures: the seat, a duty forced to raise (the matrix names it zz_demo_control), two healthy duties.
  await sql.unsafe(`
    insert into public.org_role (role_id, display_name, runtime_mode, responsibilities, activation_conditions, authority_level)
      values ('it_engineer', 'IT engineer', 'scheduled_manager', 'ZZ DEMO', 'ZZ DEMO', 'execute_medium');
    create table public.zz_drill_ran (duty text, at timestamptz default clock_timestamp());
    create function public.fn_zz_demo_control() returns jsonb language plpgsql as $f$
      begin raise exception 'ZZ DEMO D9: the control duty was forced to raise'; end $f$;
    create function public.fn_zz_demo_alpha() returns jsonb language plpgsql as $f$
      begin insert into public.zz_drill_ran (duty) values ('alpha'); return '{"ok":true}'; end $f$;
    create function public.fn_zz_demo_beta() returns jsonb language plpgsql as $f$
      begin insert into public.zz_drill_ran (duty) values ('beta'); return '{"ok":true}'; end $f$;
    insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, avg_ms) values
      ('it_engineer.zz_demo_control', 'it_engineer', interval '1 day', 'fn_zz_demo_control', 'ZZ DEMO D9: forced to raise', 'scripts/sql/zz_demo_drill.sql', 5),
      ('it_engineer.zz_demo_alpha',   'it_engineer', interval '1 day', 'fn_zz_demo_alpha',   'ZZ DEMO D9: healthy',         'scripts/sql/zz_demo_drill.sql', 5),
      ('it_engineer.zz_demo_beta',    'it_engineer', interval '1 day', 'fn_zz_demo_beta',    'ZZ DEMO D9: healthy',         'scripts/sql/zz_demo_drill.sql', 5);`);
  return sql;
}
// The next tick, one interval later: every duty is due again (the clock is moved, not waited for).
async function aDayPasses(s: ReturnType<typeof postgres>) {
  await s.unsafe(`update public.seat_duty set last_started_at = last_started_at - interval '1 day 1 minute',
                    last_ok_at = last_ok_at - interval '1 day 1 minute', created_at = created_at - interval '1 day 1 minute'`);
}
const tick = async (s: ReturnType<typeof postgres>) => (await s.unsafe(`select public.fn_seat_duties_tick(8) as r`))[0].r as
  { ran: { duty: string; ok: boolean; error?: string }[]; problems: number };
const openFinding = async (s: ReturnType<typeof postgres>, key: string) =>
  (await s.unsafe(`select issue_key, title, blast from public.it_engineer_finding where issue_key = $1 and closed_at is null`, [key]))[0] ?? null;

Deno.test({ name: 'D9 a duty that throws is isolated: the other duties in the same tick still run' + NOT_RUN, ignore: !up, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const s = await db();
  console.log('canonical routines loaded from:', JSON.stringify(loaded));
  const r = await tick(s);
  const by = Object.fromEntries(r.ran.map((x) => [x.duty, x]));
  assertEquals(by['it_engineer.zz_demo_control']?.ok, false, 'known-bad control: the forced failure is caught');
  assert(/forced to raise/.test(String(by['it_engineer.zz_demo_control']?.error)), 'its error is returned: ' + JSON.stringify(by['it_engineer.zz_demo_control']));
  assertEquals(by['it_engineer.zz_demo_alpha']?.ok, true);
  assertEquals(by['it_engineer.zz_demo_beta']?.ok, true);
  const ran = (await s.unsafe(`select duty from public.zz_drill_ran order by duty`)).map((x) => x.duty);
  assertEquals(ran, ['alpha', 'beta'], 'positive control: both healthy duties did their work in the tick the control threw');
  const [ctl] = await s.unsafe(`select failures, last_error, last_ok_at from public.seat_duty where duty = 'it_engineer.zz_demo_control'`);
  assertEquals(ctl.failures, 1);
  assert(/forced to raise/.test(ctl.last_error), 'visible on the duty row: ' + ctl.last_error);
  assertEquals(ctl.last_ok_at, null);
}});

// WAS OPEN, FIXED 3 Nov 2026 (it_engineer, drill D9). The matrix expects "a finding opens" and detection within 15
// minutes. fn_seat_duty_health raised a failing duty only at `d.failures >= 3`, and fn_seat_duty_run counts one failure
// per RUN of the duty, once per `every`: for a daily duty that is the third day. Measured with this test: it FAILED
// against the MANIFEST canonical file (no finding after the first failing tick). The fix,
// scripts/sql/a_failing_daily_duty_opens_its_finding_on_its_first_failure.sql (pending: applied at merge), raises an
// hourly-or-slower duty on its first failure; the loader above includes pending files, so this test measures it.
Deno.test({ name: 'D9 matrix expectation: the tick the duty first throws opens a finding' + NOT_RUN, ignore: !up, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const s = await db();
  assert(await openFinding(s, 'seat_duty:it_engineer.zz_demo_control'), 'a finding is open after the first failing tick');
}});

// And by the third failing run the finding is still open,
// the healthy duties ran every time, and the finding closes itself on the first run that passes.
Deno.test({ name: 'D9 a throwing duty has its finding open by its third failing run, and the finding closes itself when it passes' + NOT_RUN, ignore: !up, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const s = await db();
  await aDayPasses(s); await tick(s);
  await aDayPasses(s); await tick(s);
  const f = await openFinding(s, 'seat_duty:it_engineer.zz_demo_control');
  assert(f, 'after the third failure the finding is open');
  assert(/failed 3 times running/.test(f.title), f.title);
  assertEquals(f.blast, 'agent_facing');
  assertEquals((await s.unsafe(`select count(*)::int as n from public.zz_drill_ran`))[0].n, 6, 'the healthy duties ran on every one of the three ticks');
  // recovery with no hand: the routine is fixed, the duty runs on its clock, and its own finding closes
  await s.unsafe(`create or replace function public.fn_zz_demo_control() returns jsonb language sql as $f$ select '{"ok":true}'::jsonb $f$`);
  await aDayPasses(s); await tick(s);
  assertEquals(await openFinding(s, 'seat_duty:it_engineer.zz_demo_control'), null, 'the finding closed itself');
  const [ctl] = await s.unsafe(`select failures, last_error from public.seat_duty where duty = 'it_engineer.zz_demo_control'`);
  assertEquals([ctl.failures, ctl.last_error], [0, null]);
}});

Deno.test({ name: 'D8 a duty whose own job stopped ticking is found overdue, raised, and closed when it runs again' + NOT_RUN, ignore: !up, sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const s = await db();
  // An isolated duty (own_job: its own pg_cron job 'seat_duty:<duty>') whose job was disabled: the shared tick
  // never starts it (`not own_job`), so nothing runs it. Its last success is three days old.
  await s.unsafe(`insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, avg_ms, own_job, last_started_at, last_ok_at, created_at)
    values ('it_engineer.zz_demo_paused', 'it_engineer', interval '1 day', 'fn_zz_demo_alpha', 'ZZ DEMO D8: its own job stopped',
            'scripts/sql/zz_demo_drill.sql', 1500, true, now() - interval '3 days', now() - interval '3 days', now() - interval '10 days')`);
  const r = await tick(s);
  assert(!r.ran.some((x) => x.duty === 'it_engineer.zz_demo_paused'), 'the shared tick does not run an own-job duty');
  const f = await openFinding(s, 'seat_duty:it_engineer.zz_demo_paused');
  assert(f, 'detected on the first tick after it went overdue (2 x every + 15 min)');
  assert(/no successful run since/.test(f.title), f.title);
  // its job is re-enabled and runs (fn_seat_duty_run is what that job executes): the finding closes on the next tick
  const run = (await s.unsafe(`select public.fn_seat_duty_run('it_engineer.zz_demo_paused') as r`))[0].r;
  assertEquals(run.ok, true, JSON.stringify(run));
  await tick(s);
  assertEquals(await openFinding(s, 'seat_duty:it_engineer.zz_demo_paused'), null, 'closed with no hand');
  await s.end(); sql = null;
}});
