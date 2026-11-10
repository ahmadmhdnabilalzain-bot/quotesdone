// A COMPANY REGISTERED BY A COLLEAGUE IS NOT NUDGED AT ITS INVITED ADDRESS (28 Oct 2026, sales_engineer; supplier-journey
// audit, founder ledger 1401, scenario S7, run b4e8a7fe). Rewritten 10 Nov 2026 (customer_support, item 8 of #1901's report):
// the same company is found by its licence number, then its name in the same emirate, then its corporate mail domain, and
// no domain is nudged twice. A name match in another or an unknown emirate keeps its nudge (unsure).
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

const BODY = (fn) => body(fn).replace(/\s+/g, ' ');

test('the outreach gate (nudges, registration reminders) refuses a lead whose company another account has registered', () => {
  assert.match(body('fn_supplier_outreach_reachable'), /and\s+not\s+public\.fn_supplier_company_registered_by_another\(\s*p\s*,\s*p_to\s*\)/i);
});

test('the twin rule: the licence key, then the name key in the same known emirate, then the corporate domain; only another CLAIMED lead', () => {
  const b = BODY('fn_supplier_company_registered_by_another');
  const arms = b.split(/\)\)\s+or\s+\(/);
  assert.equal(arms.length, 3, 'exactly three ways to be the same company');
  for (const a of arms) {
    assert.match(a, /\bt\.claimed\b/i, 'only a CLAIMED lead makes a twin');
    assert.match(a, /t\.id <> p\.id/i, 'a lead is never its own twin');
  }
  assert.match(arms[0], /fn_trade_licence_key\(t\.trade_license_no\) = public\.fn_trade_licence_key\(p\.trade_license_no\)/, 'the licence key leads_claimed_trade_licence_uidx enforces');
  assert.match(arms[1], /fn_company_registration_name_key\(t\.company_name\) = public\.fn_company_registration_name_key\(p\.company_name\)/, 'the name key leads_claimed_company_name_uidx enforces');
  assert.match(arms[1], /nullif\(lower\(btrim\(coalesce\(p\.emirate, ''\)\)\), ''\) is not null/, 'a name match with no emirate must not count (unsure)');
  assert.match(arms[1], /lower\(btrim\(coalesce\(t\.emirate, ''\)\)\) = lower\(btrim\(p\.emirate\)\)/, 'the name must match in the same emirate');
  assert.match(arms[2], /fn_email_domain_class\(.*?\) = 'company'/, 'a free or disposable mail domain is many companies, never one');
});

test('the due list never nudges the same corporate domain twice', () => {
  const b = BODY('fn_supplier_invite_nudges_due');
  assert.match(b, /row_number\(\) over \(partition by coalesce\(d\.company_domain, d\.to_email\) order by d\.id\) as nth/);
  assert.match(b, /where x\.nth = 1/);
  assert.match(b, /n\.type = 'supplier_invite_nudge' and n\.lead_id is distinct from d\.id and n\.created_at >= p_now - interval '21 days'/);
  assert.match(b, /split_part\(c\.to_email, '@', 2\) <> 'example\.invalid'/, 'the shared fixture domain must not collapse every fixture into one');
});

test('the new routine is closed to the API roles and pins its search_path', () => {
  const src = readFileSync(SQL + winning('fn_supplier_company_registered_by_another'), 'utf8');
  assert.match(src, /revoke\s+execute\s+on\s+function\s+public\.fn_supplier_company_registered_by_another\(public\.leads, text\)\s+from\s+public,\s*anon,\s*authenticated/i);
  assert.match(src.slice(src.search(defRe('fn_supplier_company_registered_by_another'))), /set\s+search_path\s+to\s+'public',\s*'pg_temp'/i);
});
