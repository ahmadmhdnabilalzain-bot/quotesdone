// THE ACCOUNTANT RE-SCREENS EVERY BENEFICIAL OWNER (24 Sep 2026; founder_instruction 898, ledger 983).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the routine is not security definer with a pinned search_path, is not revoked, the owner table has no
//     RLS or service-role-only policy, the duty is not on its own seat, or the file has both or neither of a pending
//     note and a MANIFEST line;
//   * production, in ONE aborted transaction (pending files replayed, ZZ DEMO only, nothing commits): a ZZ DEMO
//     supplier whose OWNER (not its signatory or contact) is on the latest list is not a hit, the hit does not reach
//     the CEO as a decision task, a second run files it again, or an unlisted owner is a hit.
//
//   node --test scripts/checks/the_accountant_rescreens_every_beneficial_owner.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const F = 'scripts/sql/the_accountant_rescreens_every_beneficial_owner.sql';
const DEPS = ['scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql',
  'scripts/sql/the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql', F];
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('static: definer + search_path + revoke, RLS + policy, duty on its own seat, pending XOR MANIFEST', () => {
  const src = code(read(F));
  const made = [...src.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
  assert.deepEqual(made, ['fn_supplier_beneficial_owner_record', 'fn_accountant_ubo_rescreen']);
  for (const name of made) {
    const head = src.slice(src.indexOf(`function public.${name}(`)).split('$fn$')[0];
    assert.match(head, /security definer\s+set search_path to 'public', 'pg_temp'/, `${name} has no pinned search_path`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated;`), `${name} is not revoked`);
  }
  assert.match(src, /alter table public\.supplier_beneficial_owner enable row level security/);
  assert.match(src, /create policy supplier_beneficial_owner_service_role_only[\s\S]{0,120}using \(false\) with check \(false\)/);
  assert.match(src, /revoke all on public\.supplier_beneficial_owner from anon, authenticated/);
  assert.match(src, /\('accountant\.ubo_rescreen', 'accountant', interval '1 day', 'fn_accountant_ubo_rescreen'/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(F) !== manifest.includes(F), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a listed owner is a hit that reaches the CEO once; an unlisted one is not', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = DEPS.filter(pending).map(read).join('\n');
  let o;
  try {
    await replaySql(replay + '\n' + String.raw`
do $$ declare o jsonb := '{}'; l1 bigint; l2 bigint; ent text; v jsonb; begin
  perform set_config('qd.duty_fixtures', 'on', true);
  select name into ent from screening_entry where run_id = (select max(id) from screening_run where status = 'ok' and source = 'un_consolidated')
     and name ~ '^[A-Za-z]+ [A-Za-z]+ [A-Za-z]+$' limit 1;
  insert into leads (company_name, email, lifecycle_stage, signatory_name, contact_name)
    values ('ZZ DEMO — UBO Supplier One', 'zz.ubo.s1@example.invalid', 'registered', 'ZZ Demo Signatory', 'ZZ Demo Contact') returning id into l1;
  insert into leads (company_name, email, lifecycle_stage)
    values ('ZZ DEMO — UBO Supplier Two', 'zz.ubo.s2@example.invalid', 'registered') returning id into l2;
  perform fn_supplier_beneficial_owner_record(l1, ent, 'supplier_declared', null, 60);
  perform fn_supplier_beneficial_owner_record(l1, '  ' || ent || ' ', 'trade_licence');           -- the same owner, once
  perform fn_supplier_beneficial_owner_record(l2, 'Zzdemo Qqxunlisted Owner', 'trade_licence');
  o := o || jsonb_build_object('owners', (select count(*) from supplier_beneficial_owner where lead_id in (l1, l2)));
  v := fn_accountant_ubo_rescreen();
  o := o || jsonb_build_object('r1', v - 'screen', 'screened_leads', v->'screen'->'suppliers');
  o := o || jsonb_build_object('hits', (select jsonb_agg(lead_id = l1 order by id) from supplier_screening_hit where lead_id in (l1, l2) and field = 'beneficial_owner'));
  o := o || jsonb_build_object('ceo_task', (select count(*) from org_tasks where assigned_agent = 'ceo' and title like 'Sanctions screening hit:%lead #' || l1));
  o := o || jsonb_build_object('hold', (select count(*) from org_tasks where assigned_agent = 'sales_engineer' and title like 'Hold outreach%lead #' || l1 || ' %'));
  o := o || jsonb_build_object('r2', fn_accountant_ubo_rescreen()->'owner_hits_new');
  o := o || jsonb_build_object('ceo_task2', (select count(*) from org_tasks where assigned_agent = 'ceo' and title like 'Sanctions screening hit:%lead #' || l1));
  raise exception 'CHK<<%>>', o::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.owners, 2, 'the same owner recorded twice became two rows');
  assert.equal(o.r1.owner_hits_new, 1, 'the listed owner was not a hit');
  assert.ok(o.r1.owners_screened >= 2, 'the owners in scope were not screened');
  assert.deepEqual(o.hits, [true], 'a hit landed on the wrong supplier, or the unlisted owner was a hit');
  assert.equal(o.ceo_task, 1, 'the owner hit did not reach the CEO as one decision task');
  assert.equal(o.hold, 1, 'the sales_engineer was not told to hold outreach');
  assert.equal(o.r2, 0, 'a second run filed the same owner hit again');
  assert.equal(o.ceo_task2, 1, 'a second run opened a second CEO task');
});
