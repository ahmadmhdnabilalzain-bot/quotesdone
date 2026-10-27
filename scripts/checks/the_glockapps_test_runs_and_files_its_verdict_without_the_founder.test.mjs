// THE GLOCKAPPS TEST RUNS AND FILES ITS VERDICT WITHOUT THE FOUNDER (27 Oct 2026; it_engineer; ledger 1312).
//
// What fails if the cause returns:
//   static   a routine of the change file loses its pinned search_path or its revoke on the exact signature; a table
//            loses RLS, its service-role-only policy or its revoke; the file carries both or neither of a pending note
//            and a MANIFEST line; the edge function loses its config.toml block or its owner row;
//   prod     (token only) the change file and its probe, replayed in ONE rolled-back transaction through safe_replay:
//            every probe step must be true -- the tick collects the oldest open test, stays idle without intent,
//            creates on a request or a due weekly re-test; a verdict is filed once, raises / closes the it_engineer
//            finding, cannot pass under 80%; a lead's address is a known party; the invitation switches and the
//            adopted 27 Oct test are unchanged.
// The edge function's behaviour is proved offline by supabase/functions/deliverability_test/*.test.ts.
//
//   node --test scripts/checks/the_glockapps_test_runs_and_files_its_verdict_without_the_founder.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const SQL = read(FILE);
const manifestHas = (f) => read('scripts/sql/MANIFEST.txt').split(/\r?\n/).some((l) => l.trim() === f);
const noteFor = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.replace(/^scripts\/sql\//, '').replace(/\.sql$/, '.txt')));
const pending = () => !manifestHas(FILE);

const ROUTINES = {
  fn_deliverability_known_parties: 'text[]',
  fn_deliverability_test_request: 'text',
  fn_deliverability_test_tick: '',
  fn_deliverability_test_file: 'text',
};

test('static: every routine pins search_path and is revoked on its exact signature', () => {
  for (const [fn, sig] of Object.entries(ROUTINES)) {
    const body = SQL.match(new RegExp(`create or replace function public\\.${fn}\\([\\s\\S]*?\\$function\\$;`))?.[0];
    assert.ok(body, `${fn} is defined`);
    assert.match(body, /security definer/);
    assert.match(body, /set search_path to 'public', 'pg_temp'/, `${fn} pins search_path`);
    assert.ok(SQL.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn}(${sig}) is revoked`);
  }
});

test('static: both tables are RLS on, service-role-only, revoked from anon and authenticated, and exported', () => {
  for (const t of ['deliverability_test', 'deliverability_test_provider']) {
    assert.ok(SQL.includes(`alter table public.${t} enable row level security;`), `${t} RLS`);
    assert.ok(SQL.includes(`create policy ${t}_service_role_only on public.${t}\n  as permissive for all to public using (false) with check (false);`), `${t} policy`);
    assert.ok(SQL.includes(`revoke all on public.${t} from anon, authenticated;`), `${t} revoke`);
    assert.match(SQL, new RegExp(`\\('${t}', true, 'deliverability'`), `${t} in table_export_registry`);
  }
});

test('static: the file is pending XOR applied, the probe is a probe, and the function is configured and owned', () => {
  assert.notEqual(noteFor(FILE), manifestHas(FILE), 'exactly one of a pending note and a MANIFEST line');
  assert.ok(noteFor(PROBE) && !manifestHas(PROBE), 'the probe keeps its note and is never in MANIFEST');
  assert.match(read(PROBE), /raise exception 'CHK<<%>>'/);
  assert.doesNotMatch(SQL, /^\s*(commit|begin)\s*;/im, 'no transaction control in the change file');
  assert.match(read('supabase/config.toml'), /\[functions\.deliverability_test\]\nverify_jwt = false/);
  assert.match(SQL, /insert into public\.function_owner \(function_slug, owner, note\) values\s*\('deliverability_test', 'it_engineer'/);
  assert.match(SQL, /'it_engineer\.deliverability_test', 'it_engineer', interval '15 minutes', 'fn_deliverability_test_tick'/);
  assert.match(SQL, /\('deliverability_retest_weekly', 'false'\) on conflict \(key\) do nothing/, 'the weekly re-test is off unless someone turns it on');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, rolled back: the change file and its probe, every step true', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const text = (pending() ? SQL + '\n;\n' : '') + read(PROBE);
  let o = null;
  try {
    await replaySql(text, { label: NAME, retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1200));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  const failed = Object.entries(o).filter(([, v]) => v !== true).map(([k]) => k);
  assert.deepEqual(failed, [], 'probe steps false: ' + failed.join(', '));
  assert.ok(Object.keys(o).length >= 15, 'every step reported: ' + Object.keys(o).join(', '));
});
