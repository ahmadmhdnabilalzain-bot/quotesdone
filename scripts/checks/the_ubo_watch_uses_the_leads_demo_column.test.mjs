// The accountant's UBO watch never counts a demo supplier as real (28 Sep 2026, accountant; handoff 98486).
//
// MEASURED. acct:ubo:owner_unknown was raised by lead 133960 "ZZ DEMO holds probe 0b04d2d2": the watch
// matched demo names by a private literal (prefix + em dash) that the probe name did not carry. The fix
// reads leads.is_demo, the estate's one demo rule. This check fails if the newest file defining the
// watch (MANIFEST order, then pending files) filters by its own name pattern instead of that column.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const dir = new URL('../sql/', import.meta.url);
const manifest = readFileSync(new URL('MANIFEST.txt', dir), 'utf8').split(/\r?\n/)
  .map((l) => l.trim()).filter((l) => l && !l.startsWith('#')).map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = readdirSync(new URL('pending/', dir)).filter((f) => f.endsWith('.txt')).map((f) => f.replace(/\.txt$/, '.sql'));
const HEAD = /create or replace function public\.fn_accountant_ubo_watch_tick\(/i;
const defines = (f) => { try { return HEAD.test(readFileSync(new URL(f, dir), 'utf8')); } catch { return false; } };
const file = [...manifest, ...pending].filter(defines).pop();

test('the UBO watch excludes demo leads by leads.is_demo', () => {
  assert.ok(file, 'no file defines fn_accountant_ubo_watch_tick');
  const body = readFileSync(new URL(file, dir), 'utf8').split(HEAD)[1];
  const filter = body.slice(0, body.indexOf('select coalesce(jsonb_agg'));
  assert.match(filter, /l\.is_demo/, `${file}: the owner_unknown population must be filtered by leads.is_demo`);
  assert.doesNotMatch(filter, /like\s+'ZZ DEMO/i, `${file}: a private ZZ DEMO name pattern misses probe names such as "ZZ DEMO holds probe"`);
});
