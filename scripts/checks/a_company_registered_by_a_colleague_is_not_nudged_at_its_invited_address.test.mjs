// A COMPANY REGISTERED BY A COLLEAGUE IS NOT NUDGED AT ITS INVITED ADDRESS (28 Oct 2026, sales_engineer; supplier-journey
// audit, founder ledger 1401, scenario S7, run b4e8a7fe).
//
// A colleague registered the invited company under his own address; the invited row stayed unclaimed, and the day-3/7/14
// nudge would have asked the company to register again, with a claim link leads_claimed_company_name_uidx refuses. This
// fails if the definition of fn_supplier_outreach_reachable that wins the apply order stops calling the twin rule, or if
// the rule stops comparing the unique index's key with ANOTHER, CLAIMED lead. It reads routine BODIES with -- comments
// removed, so a comment cannot satisfy it. Behaviour on production: the probe file of the same name (rolled back).
//   node --test scripts/checks/a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const FIX = 'a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defRe = (fn) => new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');

/** The file that defines the routine LAST: a pending file is applied after everything in MANIFEST, so it wins. */
function winning(fn) {
  const defines = (f) => existsSync(SQL + f) && defRe(fn).test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length, `no file defines ${fn}`);
  return listed[listed.length - 1];
}
function body(fn) {
  const src = readFileSync(SQL + winning(fn), 'utf8');
  const open = src.search(defRe(fn));
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${fn} has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  return src.slice(start, src.indexOf(m[1], start)).replace(/--[^\n]*/g, '');
}

test('the outreach gate (nudges, registration reminders) refuses a lead whose company another account has registered', () => {
  assert.match(body('fn_supplier_outreach_reachable'), /and\s+not\s+public\.fn_supplier_name_registered_by_another\(\s*p\s*\)/i);
});

test('the twin rule uses the unique index key, against another lead that is claimed', () => {
  const b = body('fn_supplier_name_registered_by_another');
  assert.match(b, /\bt\.claimed\b/i, 'only a CLAIMED lead makes a twin');
  assert.match(b, /t\.id\s*<>\s*p\.id/i, 'a lead is never its own twin');
  assert.match(b, /fn_company_registration_name_key\(\s*t\.company_name\s*\)\s*=\s*public\.fn_company_registration_name_key\(\s*p\.company_name\s*\)/i,
    'the key must be the one leads_claimed_company_name_uidx enforces');
});

test('the new routine is closed to the API roles and pins its search_path', () => {
  const src = readFileSync(SQL + winning('fn_supplier_name_registered_by_another'), 'utf8');
  assert.match(src, /revoke\s+execute\s+on\s+function\s+public\.fn_supplier_name_registered_by_another\(public\.leads\)\s+from\s+public,\s*anon,\s*authenticated/i);
  assert.match(src.slice(src.search(defRe('fn_supplier_name_registered_by_another'))), /set\s+search_path\s+to\s+'public',\s*'pg_temp'/i);
});
