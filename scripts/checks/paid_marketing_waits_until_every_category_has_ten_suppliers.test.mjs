// PAID MARKETING WAITS UNTIL EVERY CATEGORY HAS TEN SUPPLIERS (founder ledger 1004, 28 Sep 2026).
//
// Every paid route (the ad_decision guard trigger, fn_ads_manage, fn_ad_spend_daily_ceiling) reads
// fn_ads_autospend_state().live_allowed. Before the_ceo_tracks_the_supplier_target_by_trade_and_emirate.sql it knew
// nothing of supplier coverage: the founder's go, token and cap alone would have opened spend with 0 of 213 trades
// at ten. This fails if the canonical definition (a pending file first, else the last MANIFEST file defining it)
// stops requiring fn_every_category_has_ten_suppliers in live_allowed, or if the gate's threshold drifts from 10.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { manifestHas, manifestIndex } from '../lib/pending_sql.mjs';

const SQL = 'scripts/sql';
const manifest = readFileSync(`${SQL}/MANIFEST.txt`, 'utf8').split(/\r?\n/).map(s => s.trim()).filter(s => s.endsWith('.sql'));
const defining = name => readdirSync(SQL).filter(f => f.endsWith('.sql') && !f.endsWith('_probe.sql'))
  .filter(f => new RegExp(`function\\s+public\\.${name}\\s*\\(`, 'i').test(readFileSync(`${SQL}/${f}`, 'utf8')));

function canonical(name) {
  const files = defining(name);
  const pending = files.filter(f => existsSync(`${SQL}/pending/${f.replace(/\.sql$/, '.txt')}`));
  if (pending.length) return pending.at(-1);
  return files.filter((f) => manifestHas(f)).sort((a, b) => manifestIndex(a) - manifestIndex(b)).at(-1);
}

function body(file, name) {
  const t = readFileSync(`${SQL}/${file}`, 'utf8');
  const i = t.search(new RegExp(`function\\s+public\\.${name}\\s*\\(`, 'i'));
  const end = t.slice(i).search(/\$(function|fn)\$;/);
  return t.slice(i, i + end);
}

test('the paid path refuses while any category has fewer than ten suppliers', () => {
  const f = canonical('fn_ads_autospend_state');
  assert.ok(f, 'no file defines fn_ads_autospend_state');
  const b = body(f, 'fn_ads_autospend_state');
  assert.match(b, /fn_every_category_has_ten_suppliers\(\)/, `${f}: fn_ads_autospend_state does not read the ten-per-category gate`);
  assert.match(b, /'live_allowed',\s*\(ten->>'gate'\)::boolean and/, `${f}: live_allowed is not conditioned on the gate`);
});

test('the gate counts ten per category', () => {
  const f = canonical('fn_every_category_has_ten_suppliers');
  assert.ok(f, 'no file defines fn_every_category_has_ten_suppliers');
  const b = body(f, 'fn_every_category_has_ten_suppliers');
  assert.match(b, /verified < 10\)\s*=\s*0/, `${f}: the gate threshold is not 10`);
});
