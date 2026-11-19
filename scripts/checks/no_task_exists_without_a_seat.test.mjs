// NO TASK EXISTS WITHOUT A SEAT (ceo, 19 Nov 2026; founder ruling 1743: "there shouldnt be a single task that is not
// owned by an agent. otherwise its not a real company.").
//
// MEASURED 19 Nov 2026: of 154 active cron jobs, accountant_payment_checks alone had no owner in the database, although
// the file that schedules it says "Assigned: accountant"; and the one Vercel cron (/api/resilience-ping, vercel.json)
// had no seat recorded anywhere. Nothing in the repository compared a scheduled job with an owner, so both passed every
// gate. scripts/sql/no_task_exists_without_a_seat.sql registers them and adds the hourly duty it_engineer.unowned_work.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * repo: a cron.schedule('<name>', ...) in scripts/sql (comments stripped) whose job is still scheduled at the end of
//     MANIFEST order (pending files after it) and has no owner. An owner is, for that job name:
//       - the newest writer_seat row ('cron_job', '<name>', '<seat>') in scripts/sql (MANIFEST order, then pending), or
//       - a header line "Assigned: <seat>" in the file that schedules it, or
//       - for a 'seat_duty:<seat>.<duty>' job, the seat in its name (seat_duty's own check ties the two);
//     and the seat is one of the live seats (scripts/lib/apply_seat.mjs SEATS). A name built at run time (concatenated,
//     a variable) is a seat_duty job made by fn_seat_duty_isolate and is resolved in the database, not here.
//   * repo: a vercel.json cron path with no writer_seat row ('vercel_cron', '<path>', '<seat>') on a live seat.
//   * known-bad controls: the parser is run on synthetic files that must fail (unowned, unknown seat, a writer_seat row
//     moved to an unknown seat, a Vercel cron with no row) and on ones that must pass (header, retired job, comment).
//   * static: the SQL file keeps its revokes, pinned search_path, seat_duty row and playbook class; pending XOR MANIFEST.
//   * production, in ONE aborted transaction (pending file replayed first): fn_unowned_work() returns a row.
//
//   node --test scripts/checks/no_task_exists_without_a_seat.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { SEATS } from '../lib/apply_seat.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/no_task_exists_without_a_seat.sql';
const pendingNote = (f) => join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt'));

// SQL with -- comments removed, keeping string contents ('--' inside a literal is rare here and never in a job name).
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const NAME = /^[A-Za-z0-9_.:\-]+$/;

// Files in the order production received them: MANIFEST.txt, then every other .sql (pending) sorted.
export function orderedFiles(repo = REPO) {
  const manifest = readFileSync(join(repo, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
  const listed = new Set(manifest);
  const rest = readdirSync(join(repo, 'scripts/sql')).filter((f) => f.endsWith('.sql')).map((f) => 'scripts/sql/' + f)
    .filter((f) => !listed.has(f)).sort();
  const seen = new Set();
  return [...manifest, ...rest].filter((f) => !seen.has(f) && seen.add(f) && existsSync(join(repo, f)));
}

// files: [{ path, text }] in apply order. vercel: parsed vercel.json or null. Returns the list of findings (strings).
export function unownedScheduledWork(files, vercel, seats = SEATS) {
  const live = new Set(seats);
  const jobs = new Map();          // name -> { file, scheduled }
  const owner = new Map();         // `${kind}\u0000${name}` -> { seat, file }
  for (const { path, text } of files) {
    const src = code(text);
    const header = (text.match(/^--.*\bAssigned:\s*`?([a-z_]+)`?/m) || [])[1] || null;
    const events = [];
    for (const m of src.matchAll(/cron\.schedule\(\s*'([^']*)'\s*,/g)) if (NAME.test(m[1])) events.push([m.index, m[1], true]);
    for (const m of src.matchAll(/cron\.unschedule\(\s*'([^']*)'\s*\)/g)) if (NAME.test(m[1])) events.push([m.index, m[1], false]);
    for (const [, name, on] of events.sort((a, b) => a[0] - b[0])) {
      jobs.set(name, on ? { file: path, scheduled: true, header } : { file: path, scheduled: false, header: null });
    }
    for (const ins of src.matchAll(/insert\s+into\s+public\.writer_seat\b([\s\S]*?)(?:on\s+conflict|;\s*$)/gim)) {
      for (const t of ins[1].matchAll(/\(\s*'(cron_job|vercel_cron|agent_runs_label)'\s*,\s*'([^']+)'\s*,\s*'([a-z_]+)'/g)) {
        owner.set(`${t[1]}\u0000${t[2]}`, { seat: t[3], file: path });
      }
    }
  }
  const bad = [];
  for (const [name, j] of jobs) {
    if (!j.scheduled) continue;                                  // retired: its last word is an unschedule
    const reg = owner.get(`cron_job\u0000${name}`);
    const duty = (name.match(/^seat_duty:([a-z_]+)\./) || [])[1] || null;
    const seat = reg?.seat ?? j.header ?? duty;
    if (!seat) bad.push(`cron job ${name} (${j.file}): no writer_seat row, no "Assigned: <seat>" header`);
    else if (!live.has(seat)) bad.push(`cron job ${name} (${reg?.file ?? j.file}): owner ${seat} is not a live seat`);
  }
  for (const c of vercel?.crons ?? []) {
    const reg = owner.get(`vercel_cron\u0000${c.path}`);
    if (!reg) bad.push(`vercel cron ${c.path} (${c.schedule}): no writer_seat row ('vercel_cron', '${c.path}', <seat>)`);
    else if (!live.has(reg.seat)) bad.push(`vercel cron ${c.path} (${reg.file}): owner ${reg.seat} is not a live seat`);
  }
  return bad;
}

const repoFiles = () => orderedFiles().map((p) => ({ path: p, text: read(p) }));
const vercelJson = () => JSON.parse(read('vercel.json'));

test('repo: every scheduled cron job and every vercel.json cron has a live seat', () => {
  const files = repoFiles();
  assert.ok(files.length > 1000, `only ${files.length} SQL files read`);
  assert.ok(files.some((f) => /cron\.schedule\(\s*'accountant_payment_checks'/.test(f.text)), 'the parser no longer sees accountant_payment_checks');
  assert.ok((vercelJson().crons ?? []).length >= 1, 'vercel.json has no cron: the Vercel arm proves nothing');
  assert.deepEqual(unownedScheduledWork(files, vercelJson()), [], 'scheduled work with no seat');
});

test('repo: the move and the new kind are the newest word', () => {
  const files = repoFiles();
  const last = (kind, name) => {
    let seat = null;
    for (const { text } of files) for (const m of code(text).matchAll(new RegExp(`\\(\\s*'${kind}'\\s*,\\s*'${name.replace(/[/.-]/g, '\\$&')}'\\s*,\\s*'([a-z_]+)'`, 'g'))) seat = m[1];
    return seat;
  };
  assert.equal(last('cron_job', 'dropbox_backup_second_scheduler'), 'it_engineer');
  assert.equal(last('cron_job', 'accountant_payment_checks'), 'accountant');
  assert.equal(last('vercel_cron', '/api/resilience-ping'), 'it_engineer');
});

test('known-bad controls: the parser fails what it must and passes what it must', () => {
  const f = (path, text) => ({ path, text });
  const S = (n) => `select cron.schedule('${n}', '0 * * * *', 'select 1');`;
  const W = (k, n, s) => `insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values ('${k}', '${n}', '${s}', 'x', 'y') on conflict (kind, name) do nothing;`;
  // must FAIL
  assert.equal(unownedScheduledWork([f('a.sql', S('zz_demo_unowned'))], null).length, 1, 'an unowned job passed');
  assert.equal(unownedScheduledWork([f('a.sql', `-- Assigned: sales\n${S('zz_demo_x')}`)], null).length, 1, 'a header naming no live seat passed');
  assert.equal(unownedScheduledWork([f('a.sql', S('zz_demo_y') + W('cron_job', 'zz_demo_y', 'ceo')), f('b.sql', W('cron_job', 'zz_demo_y', 'finance'))], null).length, 1,
    'a later move to an unknown seat passed');
  assert.equal(unownedScheduledWork([], { crons: [{ path: '/api/zz-demo', schedule: '*/5 * * * *' }] }).length, 1, 'a Vercel cron with no row passed');
  assert.equal(unownedScheduledWork([f('a.sql', 'select cron.unschedule(\'zz_demo_z\');'), f('b.sql', S('zz_demo_z'))], null).length, 1,
    'a job unscheduled and then scheduled again was treated as retired');
  assert.equal(unownedScheduledWork([f('a.sql', 'select cron.schedule(\n  \'zz_demo_multi\' ,\n \'0 * * * *\', $$select 1$$);')], null).length, 1, 'a multi-line schedule was missed');
  // must PASS
  assert.deepEqual(unownedScheduledWork([f('a.sql', `-- X.\n--\n-- Assigned: accountant (the books)\n${S('zz_demo_h')}`)], null), [], 'a header owner was not read');
  assert.deepEqual(unownedScheduledWork([f('a.sql', S('zz_demo_r')), f('b.sql', `select cron.unschedule('zz_demo_r');`)], null), [], 'a retired job was flagged');
  assert.deepEqual(unownedScheduledWork([f('a.sql', `-- once: ${S('zz_demo_c')}`)], null), [], 'a commented schedule was counted');
  assert.deepEqual(unownedScheduledWork([f('a.sql', `select cron.schedule('seat_duty:' || d.duty, '* * * * *', 'x');`)], null), [], 'a run-time name was judged here');
  assert.deepEqual(unownedScheduledWork([f('a.sql', S('seat_duty:marketing.zz_demo'))], null), [], 'a seat_duty job did not name its seat');
  assert.deepEqual(unownedScheduledWork([f('a.sql', W('vercel_cron', '/api/zz-demo', 'it_engineer'))], { crons: [{ path: '/api/zz-demo' }] }), [], 'a registered Vercel cron was flagged');
});

test('static: revokes, pinned search_path, the duty, the playbook class, the new kind; pending XOR MANIFEST', () => {
  const src = code(read(FILE));
  for (const sig of ['fn_unowned_work()', 'fn_it_engineer_unowned_work()']) {
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated`), `${sig}: no revoke`);
    assert.match(src, new RegExp(`function public\\.${sig.replace(/[()]/g, '\\$&')}[\\s\\S]{0,120}security definer\\s+set search_path to 'public', 'pg_temp'`), `${sig}: search_path not pinned`);
  }
  assert.match(src, /check \(kind in \('agent_runs_label', 'cron_job', 'vercel_cron'\)\)/);
  assert.match(src, /\('it_engineer\.unowned_work', 'it_engineer', interval '1 hour', 'fn_it_engineer_unowned_work'/);
  assert.match(src, /\('work_without_a_seat', 'unowned_work:'/);
  assert.match(src, /public\.fn_it_engineer_finding_upsert\(/, 'the duty must raise through the one finding path');
  assert.ok(!/create\s+(constraint\s+)?trigger[\s\S]{0,200}on\s+cron\.job/i.test(src), 'no trigger on cron.job');
  assert.match(src, /set local lock_timeout/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  const note = existsSync(pendingNote(FILE));
  assert.ok(note !== manifest.includes(FILE), `${FILE}: exactly one of a pending note and a MANIFEST line`);
  if (note) assert.ok(readFileSync(pendingNote(FILE), 'utf8').trim(), 'the pending note is empty');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: fn_unowned_work() returns no row', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const replay = existsSync(pendingNote(FILE)) ? read(FILE).replace(/^-- ── PROBE[\s\S]*$/m, '') : '';
  let o;
  try {
    await replaySql(replay + `
do $$ begin
  raise exception 'CHK<<%>>', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'name', name)) from public.fn_unowned_work()), '[]'::jsonb)::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, [], 'unowned work: ' + JSON.stringify(o));
});
