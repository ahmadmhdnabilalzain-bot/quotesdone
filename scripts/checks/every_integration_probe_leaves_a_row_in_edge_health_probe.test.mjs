// EVERY INTEGRATION PROBE LEAVES A ROW IN EDGE_HEALTH_PROBE.
//
// it_engineer, 28 Sep 2026. edge_health_probe held 0 rows while resilience_step itintegrations probed every
// registry entry every 15 minutes: fn_it_integration_settle recorded failures as findings and nothing at all for
// the probe itself. This fails if the record is dropped again.
//   offline: the canonical body (the LAST MANIFEST/pending file defining the routine) inserts into edge_health_probe
//            and skips carried items;
//   production: the file is executed inside ONE transaction that always rolls back, then one passing, one failing
//            and one carried ZZ probe item are settled; exactly two rows must appear, ALIVE and FAILING.
//
//   node --test scripts/checks/every_integration_probe_leaves_a_row_in_edge_health_probe.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/every_integration_probe_leaves_a_row_in_edge_health_probe.sql';
const SRC = readFileSync(join(REPO, FILE), 'utf8');
const BODY = SRC.slice(SRC.indexOf('create or replace function'), SRC.indexOf('end $fn$'));
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('offline: the settle writes one edge_health_probe row per measured item, never for a carried one', () => {
  const at = BODY.indexOf('insert into public.edge_health_probe');
  assert.ok(at > 0, 'fn_it_integration_settle no longer records its probes in edge_health_probe');
  const stmt = BODY.slice(at, BODY.indexOf(';', at));
  assert.match(stmt, /jsonb_array_elements\(p_items\)/);
  assert.match(stmt, /not coalesce\(\(e->>'carried'\)::boolean, false\)/);
  assert.match(stmt, /'ALIVE'/);
  assert.match(stmt, /'FAILING'/);
});

test('offline: this file is the canonical definition (no later MANIFEST file redefines the routine)', () => {
  const manifest = readFileSync(join(REPO, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const mine = manifest.indexOf(FILE);
  const later = manifest.slice(mine < 0 ? 0 : mine + 1)
    .filter((f) => existsSync(join(REPO, f)) && /function\s+public\.fn_it_integration_settle\s*\(/i.test(readFileSync(join(REPO, f), 'utf8')));
  // Until applied the file is pending (no MANIFEST line); then every MANIFEST definer is older, i.e. none may follow it.
  if (mine < 0) assert.ok(existsSync(join(REPO, 'scripts/sql/pending/every_integration_probe_leaves_a_row_in_edge_health_probe.txt')));
  else assert.deepEqual(later, [], 'a later file redefines fn_it_integration_settle: carry the edge_health_probe insert into it');
});

const PROBE = `
do $p$
declare n_alive int; n_failing int; n_carried int;
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  perform public.fn_it_integration_settle('integration', jsonb_build_array(
    jsonb_build_object('item','zz_probe_ok','title','answers again','recovered',true,'evidence',jsonb_build_object('recovered',true)),
    jsonb_build_object('item','zz_probe_bad','owner_seat','it_engineer','subject','zz_probe_bad','blast','internal','affected',1,
                       'title','ZZ PROBE http 503','evidence',jsonb_build_object('integration','zz_probe_bad','notify',false)),
    jsonb_build_object('item','zz_probe_carried','title','not measured this beat','carried',true,'evidence','{}'::jsonb)), '[]');
  select count(*) filter (where verdict = 'ALIVE' and fn_key = 'integration:zz_probe_ok'),
         count(*) filter (where verdict = 'FAILING' and fn_key = 'integration:zz_probe_bad' and note like 'ZZ PROBE http 503%'),
         count(*) filter (where fn_key = 'integration:zz_probe_carried')
    into n_alive, n_failing, n_carried from public.edge_health_probe where fn_key like 'integration:zz_probe_%';
  raise exception 'CHK<<%>>', jsonb_build_object('alive', n_alive, 'failing', n_failing, 'carried', n_carried,
    'finding', exists (select 1 from public.it_engineer_finding where issue_key = 'duty:integration:zz_probe_bad' and closed_at is null))::text;
end $p$;`;

test('production: one ALIVE and one FAILING row, none for the carried item, and the failure is still a finding', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  let message = '';
  try { await sql(SRC + '\n' + PROBE, { retry: false }); message = 'the probe returned without raising, so it did not roll back'; }
  catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 1500));
  const o = JSON.parse(chk[1].replace(/\\"/g, '"'));
  assert.equal(o.alive, 1, 'a passing probe left no ALIVE row');
  assert.equal(o.failing, 1, 'a failing probe left no FAILING row');
  assert.equal(o.carried, 0, 'an item not measured this beat was recorded as a probe');
  assert.equal(o.finding, true, 'a failing probe no longer raises its it_engineer finding (the alert)');
});
