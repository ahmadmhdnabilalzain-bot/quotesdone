// AN "INSTALLATION INCLUDED" QUOTE LINE COUNTS AS THE LABOUR STATED (12 Oct 2026, it_engineer; final sandbox run 2,
// tag 1c94fa6a: every demo aluminium quote stayed a draft and the customer saw "0 quotes").
//
// supplier_api writes "installation included in the rate" as install = 0. The scorer counted only > 0, so the stated
// zero cost the quote 10 points and the 70 pass mark. WHAT FAILS IF THE CAUSE RETURNS (static, committed source):
//   * the canonical trg_quote_quality (the highest MANIFEST file that defines it) counts labour/install by value > 0;
//   * supplier_api stops recording "included" as a stated install of 0.
//
//   node --test scripts/checks/an_installation_included_line_counts_as_labour_stated.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const strip = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the canonical trg_quote_quality counts a stated labour or install, zero included', () => {
  const files = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const defs = files.filter((f) => { try { return /create or replace function public\.trg_quote_quality\(/.test(strip(read(f))); } catch { return false; } });
  const canon = defs.at(-1);
  assert.equal(canon, 'scripts/sql/an_installation_included_quote_line_counts_as_the_labour_stated.sql', `canonical trg_quote_quality is ${canon}`);
  const sql = strip(read(canon));
  assert.match(sql, /filter \(where labour is not null or install is not null\)/, 'a stated zero is read as "not stated" again');
  assert.doesNotMatch(sql, /coalesce\(install,0\)>0/);
});

test('supplier_api still records "installation included" as a stated install of 0', () => {
  const api = functionSource('supplier_api');
  assert.match(api, /i === 0 && !anyInstall && fromScope\.installation_included \? 0 : null/);
});
