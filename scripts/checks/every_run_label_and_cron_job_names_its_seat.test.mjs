// EVERY RUN LABEL AND CRON JOB NAMES ITS SEAT (30 Sep 2026, it_engineer; senior-hire audit, ownership).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the register loses RLS, its policy or its revoke; the resolver loses its revoke or pinned search_path;
//     a file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (pending files replayed first, nothing commits): an agent_runs label
//     written in the last 7 days, or a cron job, resolves to no active seat. That is how backup_kick, brief,
//     company_snapshot, supplier_invites, supplier_sanctions_screen and ceo-strategy-memo-monthly ran unowned.
//
//   node --test scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql';
const WA_FLUSH = 'scripts/sql/wa_flush_is_unscheduled_because_resilience_ping_drains_whatsapp.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: RLS + policy + revoke on the register, revoke + search_path on the resolver, pending XOR MANIFEST', () => {
  const src = code(read(FILE));
  assert.ok(src.includes('alter table public.writer_seat enable row level security'));
  assert.ok(src.includes('create policy writer_seat_service_role_only'));
  assert.ok(src.includes('revoke all on public.writer_seat from anon, authenticated'));
  assert.ok(src.includes('revoke execute on function public.fn_writers_without_a_seat(integer) from public, anon, authenticated'));
  assert.match(src, /fn_writers_without_a_seat\(p_days integer default 7\)[\s\S]{0,200}security definer\s+set search_path to 'public', 'pg_temp'/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  for (const f of [FILE, WA_FLUSH]) assert.ok(pending(f) !== manifest.includes(f), `${f}: exactly one of a pending note and a MANIFEST line`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: every run label of the last 7 days and every cron job names an active seat', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = [WA_FLUSH, FILE].filter(pending).map(read).join('\n');
  let o;
  try {
    await sql(replay + `
do $$ begin
  raise exception 'CHK<<%>>', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'name', name, 'runs', runs)) from public.fn_writers_without_a_seat(7)), '[]'::jsonb)::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, [], 'writers with no seat: ' + JSON.stringify(o));
});
