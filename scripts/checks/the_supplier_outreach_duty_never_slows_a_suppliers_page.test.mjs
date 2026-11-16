// THE SUPPLIER OUTREACH DUTY NEVER SLOWS A SUPPLIER'S PAGE (it_engineer, 16 Nov 2026).
// The 09:00-Dubai open beat of seat_duty:sales_engineer.supplier_outreach took 18.6-25.3 s on every open weekday of 10-16 Nov
// (cron.job_run_details), and on 16 Nov the supplier portal home took 9.2 s inside that window. Three causes, three changes
// (scripts/sql/the_supplier_outreach_duty_never_slows_a_suppliers_page.sql):
//   1. fn_supplier_invite_candidates joined 3,649 leads and 14,072 eligible ids by nested loop (the planner read them as 40 and
//      1,000): it now carries SET enable_nestloop TO 'off'.
//   2. fn_supplier_listing_has_registered_twin, LANGUAGE sql with SECURITY DEFINER and a SET clause, was re-planned on every call
//      (0.24 ms x every reachable listing): it is plpgsql now, so its plan is kept.
//   3. enqueue_supplier_invites counted its pool with the per-row rule over every lead: it counts the set rule now.
// A later redefinition copied from an older body would bring each of them back silently (CREATE OR REPLACE replaces the SET
// clauses with its own). This reads the LATEST definition of each routine in the repository (the last pending file defining
// it, else the last MANIFEST file) and fails when the change is gone. Offline: it reads files only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l.startsWith('scripts/sql/'));
const inManifest = new Set(manifest);
const pendingSql = readdirSync(new URL('scripts/sql/', ROOT)).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => 'scripts/sql/' + f).filter((f) => !inManifest.has(f));
const defines = (name) => new RegExp(`create or replace function public\\.${name}\\(`, 'i');
const fnText = (sql, name) => {
  const m = sql.match(defines(name));
  if (!m) return null;
  const ends = ['$function$;', '$fn$;'].map((t) => sql.indexOf(t, m.index)).filter((i) => i > 0);
  return sql.slice(m.index, Math.min(...ends));
};
const latest = (name) => {
  const f = [...manifest, ...pendingSql].filter((p) => defines(name).test(code(read(p)))).pop();
  assert.ok(f, `${name} is defined nowhere`);
  return { file: f, fn: fnText(code(read(f)), name) };
};

// the three predicates, each with a known-bad control below
const keepsHashJoins = (fn) => /\bSET\s+enable_nestloop\s+(TO|=)\s+'?off'?/i.test(fn);
const keepsItsPlan = (fn) => /\bLANGUAGE\s+plpgsql\b/i.test(fn);
const countsTheSet = (fn) => /select count\(\*\) into v_pool from public\.fn_supplier_invite_eligible_ids\(\)/i.test(fn)
  && !/fn_supplier_invite_eligible\(l\)/i.test(fn);

test('the candidates routine keeps its joins off nested loops', () => {
  const { file, fn } = latest('fn_supplier_invite_candidates');
  assert.ok(keepsHashJoins(fn), `${file}: fn_supplier_invite_candidates has no SET enable_nestloop TO 'off' (the 25 s open beat returns)`);
  assert.ok(!keepsHashJoins(fn.replace(/\bSET\s+enable_nestloop[^\n]*/i, '')), 'control: a body without the SET passed');
});

test('the registered-twin rule keeps its plan between calls', () => {
  const { file, fn } = latest('fn_supplier_listing_has_registered_twin');
  assert.ok(keepsItsPlan(fn), `${file}: fn_supplier_listing_has_registered_twin is not plpgsql (re-planned per listing again)`);
  assert.ok(!keepsItsPlan(fn.replace(/LANGUAGE\s+plpgsql/i, 'LANGUAGE sql')), 'control: a LANGUAGE sql body passed');
});

test('the batch counts its pool from the set rule, not the row rule over every lead', () => {
  const { file, fn } = latest('enqueue_supplier_invites');
  assert.ok(countsTheSet(fn), `${file}: enqueue_supplier_invites counts the pool per row again`);
  assert.ok(!countsTheSet(fn.replace(/from public\.fn_supplier_invite_eligible_ids\(\);/i, 'from leads l where public.fn_supplier_invite_eligible(l);')),
    'control: the per-row count passed');
});
