// THE SERVICES HOLD SURVIVES EVERY LATER BODY OF THE SUPPLIER GATE (sales_engineer, 2 Nov 2026, founder ledger 1469).
// Prevented by this file: a later file re-defining public.fn_sales_engineer_verifies_supplier from an older body and silently deleting the
// services_unconfirmed hold (PR #1746 did, written before #1760 landed; found in review, not by a check).
//   node --test scripts/checks/the_supplier_gate_keeps_the_services_hold_in_every_later_body.test.mjs
// Rule: every file in scripts/sql that defines the routine, and is the services file or sits after it in MANIFEST.txt (or is not in
// MANIFEST yet, which makes it newer than every listed file), keeps the hold in its chain: the same reason and the same seeder exemption.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = join(ROOT, 'scripts', 'sql');
const SERVICES_FILE = 'a_supplier_is_verified_only_after_it_confirms_its_services.sql';
const DEFINES = /create\s+or\s+replace\s+function\s+public\.fn_sales_engineer_verifies_supplier\s*\(/i;
const strip = (s) => s.replace(/--[^\n]*/g, '');

export function holdProblems(sql) {
  const body = strip(sql);
  const out = [];
  if (!/elsif\s+v_services_open\s+then\s+v_decision\s*:=\s*'pending'\s*;\s*v_reason\s*:=\s*'services_unconfirmed'/.test(body)) out.push('the services_unconfirmed branch is missing');
  if (!/p_source\s+not\s+in\s*\(\s*'demo_factory'\s*,\s*'hvac_dress_rehearsal'\s*,\s*'document_intake_accuracy'\s*\)/.test(body)) out.push('the seeder exemption is missing');
  const hold = body.search(/elsif\s+v_services_open/);
  const auto = body.search(/elsif\s+coalesce\(v_auto/);
  if (hold < 0 || auto < 0 || hold > auto) out.push('the hold does not stand before automatic approval');
  const from = body.search(/if\s+coalesce\(l\.approval_status/);
  const branch = body.slice(from, body.indexOf('elsif', from));
  if (/v_services_open/.test(branch)) out.push('the approved-supplier branch asks for services (nobody is demoted)');
  return out;
}

export function laterBodies() {
  const manifest = readFileSync(join(DIR, 'MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim().replace('scripts/sql/', '')).filter((l) => l && !l.startsWith('#'));
  const pos = new Map(manifest.map((f, i) => [f, i]));
  assert.ok(pos.has(SERVICES_FILE), 'the services file is not in MANIFEST.txt');
  return readdirSync(DIR).filter((f) => f.endsWith('.sql') && !f.endsWith('_probe.sql'))
    .filter((f) => DEFINES.test(readFileSync(join(DIR, f), 'utf8')))
    .filter((f) => !pos.has(f) || pos.get(f) >= pos.get(SERVICES_FILE));
}

test('every body of the gate at or after the services file keeps the hold', () => {
  const files = laterBodies();
  assert.ok(files.includes(SERVICES_FILE), 'the services file itself was not found');
  for (const f of files) assert.deepEqual(holdProblems(readFileSync(join(DIR, f), 'utf8')), [], f);
});

test('known-bad control: a body rebuilt from before the services gate is caught', () => {
  const good = readFileSync(join(DIR, SERVICES_FILE), 'utf8');
  const noBranch = good.replace(/elsif v_services_open then v_decision := 'pending'; v_reason := 'services_unconfirmed';\r?\n/, '');
  assert.notEqual(noBranch, good, 'the control did not remove anything');
  assert.match(holdProblems(noBranch).join(), /branch is missing/);
  const noExempt = good.replace(/p_source not in \('demo_factory', 'hvac_dress_rehearsal', 'document_intake_accuracy'\)/, 'true');
  assert.match(holdProblems(noExempt).join(), /exemption is missing/);
  const demoting = good.replace('and not v_number_unread', 'and not v_number_unread and not v_services_open');
  assert.match(holdProblems(demoting).join(), /nobody is demoted/);
});
