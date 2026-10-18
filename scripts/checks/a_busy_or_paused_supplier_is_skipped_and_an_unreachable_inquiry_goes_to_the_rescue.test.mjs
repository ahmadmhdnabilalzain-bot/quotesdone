// A BUSY OR PAUSED SUPPLIER IS SKIPPED, AND AN INQUIRY NOBODY CAN REACH GOES TO THE RESCUE
// (29 Sep 2026, sales_engineer, founder ledger 1033 under 1018).
//
// A supplier marks itself available, busy until a date, or paused (portal Settings, English). Matching skips busy
// and paused suppliers; a busy date expires on its day; and an open inquiry with no live quote and zero reachable
// suppliers is flagged to the stalled-inquiry rescue (public.stalled_inquiry_rescue) - at dispatch by customer_api,
// and by the sales_engineer.supplier_availability duty every 15 minutes.
//
// What fails if that breaks:
//   * the canonical matcher loses the availability gate, or reads it outside its candidate set  -> static
//   * "busy until D" stops meaning available ON D, or the duty stops expiring and sweeping      -> static + probe
//   * the dispatch path lands on nobody without flagging the rescue                              -> static
//   * the portal or supplier_api stops offering the three states, or writes around the writer    -> static
//   * any of it, on production, on ZZ DEMO data in one rolled-back transaction                   -> the live probe
//     (scripts/sql/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue_probe.sql)
//
//   node --test scripts/checks/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '').replace(/^\s*\/\/.*$/, '')).join('\n');
const NAME = 'a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;

// The canonical body: the last file, in the order files are (or will be) applied, that defines it.
function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  const src = R(owner);
  const from = src.search(re);
  const tag = src.slice(from).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  const body = src.slice(from).split(tag)[1] || '';
  return { owner, body: code(body) };
}

test('the canonical matcher skips a busy or paused supplier inside its candidate set', () => {
  const { owner, body } = canonical('fn_match_capability');
  const cand = body.slice(body.indexOf('cand as ('), body.indexOf('eff as ('));
  assert.match(cand, /left join public\.supplier_availability av on av\.supplier_id = sc\.supplier_id/, `${owner}: no availability join in cand`);
  assert.match(cand, /and public\.fn_supplier_available\(av\.state, av\.busy_until\)/, `${owner}: no availability gate in cand`);
  // the gates it already had are still there
  assert.match(cand, /sc\.confirmed_at is not null/, `${owner}: the confirmed-scope gate is gone`);
  assert.match(cand, /public\.fn_is_matchable\(/, `${owner}: the matchability gate is gone`);
  assert.match(cand, /left join public\.supplier_performance pf on pf\.lead_id = sc\.supplier_id/, `${owner}: the measured score is gone`);
});

test('busy until a date means available again ON that date (Dubai), and paused means not available', () => {
  const { body } = canonical('fn_supplier_available');
  assert.match(body, /coalesce\(p_state, 'available'\) = 'available'/, 'no row must read as available');
  assert.match(body, /p_state = 'busy' and p_busy_until <= \(now\(\) at time zone 'Asia\/Dubai'\)::date/, 'a busy date must expire on its own Dubai day');
  assert.doesNotMatch(body, /paused/, 'paused must never read as available');
});

test('the duty expires busy dates and sweeps every open inquiry into the rescue, every 15 minutes', () => {
  const s = code(R(FILE));
  assert.match(s, /\('sales_engineer\.supplier_availability', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_availability_tick'/, 'the duty is not registered on the sales_engineer clock');
  const { body } = canonical('fn_sales_engineer_availability_tick');
  assert.match(body, /set state = 'available', busy_until = null[\s\S]*where state = 'busy' and busy_until <= \(now\(\) at time zone 'Asia\/Dubai'\)::date/, 'busy rows are not expired on their day');
  assert.match(body, /i\.status in \('sent', 'quoted'\)[\s\S]*public\.fn_stalled_inquiry_flag\(r\.id/, 'open inquiries are not swept through fn_stalled_inquiry_flag');
  const flag = canonical('fn_stalled_inquiry_flag').body;
  assert.match(flag, /insert into public\.stalled_inquiry_rescue/, 'nothing is written to the rescue');
  assert.match(flag, /public\.fn_supplier_available\(av\.state, av\.busy_until\)/, 'reachable does not read availability');
});

test('a dispatch that lands on nobody flags the rescue before it returns', () => {
  const api = code(R('supabase/functions/customer_api/index.ts'));
  const at = api.indexOf('if (!landedIds.length) {');
  assert.ok(at > 0, 'the zero-landed branch of matchAndNotify is gone');
  const branch = api.slice(at, api.indexOf('return { matches: 0, routing };', at));
  assert.match(branch, /admin\.rpc\('fn_stalled_inquiry_flag', \{ p_inquiry_id: inqId/, 'customer_api does not flag an inquiry that reached nobody');
});

test('the portal offers the three states in English and writes only through the one writer', () => {
  const api = code(R('supabase/functions/supplier_api/index.ts'));
  assert.match(api, /action === 'set_availability'[\s\S]{0,900}admin\.rpc\('fn_supplier_set_availability'/, 'supplier_api does not write through fn_supplier_set_availability');
  assert.doesNotMatch(api, /from\('supplier_availability'\)/, 'supplier_api writes or reads the table around the writer');
  assert.match(api, /admin\.rpc\('fn_supplier_availability_of'/, 'the settings answer does not carry availability as matching reads it');
  const ui = R('src/components/portal/supplier/SupplierAvailability.tsx');
  for (const v of ["'available'", "'busy'", "'paused'"]) assert.ok(ui.includes(v), `the panel does not offer ${v}`);
  assert.match(ui, /action: 'set_availability'/, 'the panel does not save');
  assert.match(ui, /type="date"/, 'busy has no date');
  assert.doesNotMatch(ui, /[؀-ۿ]/, 'the supplier panel must be English only');
  assert.match(R('src/components/portal/supplier/SupplierSettings.tsx'), /<SupplierAvailability token=\{token\} initial=\{avail\} \/>/, 'Settings does not show the panel');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production, rolled back, ZZ DEMO only: skipped when busy or paused, back on the date, unreachable inquiries flagged and cleared', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  // While the change is pending, its file runs first in the same transaction; the probe's raise rolls both back.
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let out = null;
  try { await replaySql(pre + R(PROBE), { retry: false }); } catch (e) {
    const m = String(e.message || e).match(/CHK<<([\s\S]*)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  if (out.skipped) { console.log('NOT_VERIFIED_' + out.skipped.replace(/\W+/g, '_').toUpperCase()); t.skip(out.skipped); return; }
  console.log('  ' + JSON.stringify(out));
  assert.equal(out.failures, '', out.failures);
  const left = await sql(`select count(*)::int as n from public.inquiries where summary like 'ZZ DEMO availability probe%'`);
  assert.equal(left[0].n, 0, 'the probe left an inquiry behind');
});
