// A DELIVERY REPORT LEAVES THE REVIEW QUEUE IN EVERY LATER BODY OF THE SUPPLIER-MAILBOX OWNER (sales_engineer, 2 Nov 2026).
// Prevented by this file: a later file re-defining public.fn_supplier_mailbox_mail_gets_its_owner from an older body and silently
// dropping #1779's rule (#1792 was written from the body before it; found in review, not by a check).
//   node --test scripts/checks/a_delivery_report_leaves_the_review_queue_in_every_later_owner_body.test.mjs
// Rule: every file in scripts/sql that defines the routine and is #1779's file or sits after it in MANIFEST.txt (or is not in MANIFEST
// yet, which makes it newer than every listed file) clears needs_review in the bounce branch, and only there.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = join(ROOT, 'scripts', 'sql');
const RULE_FILE = 'a_delivery_report_in_the_supplier_mailbox_leaves_the_review_queue.sql';
const DEFINES = /create\s+or\s+replace\s+function\s+public\.fn_supplier_mailbox_mail_gets_its_owner\s*\(/i;
const strip = (s) => s.replace(/--[^\n]*/g, '');

export function ruleProblems(sql) {
  const body = strip(sql);
  const start = body.search(DEFINES);
  const fn = body.slice(start, body.indexOf('end $fn$', start));
  const bounce = fn.slice(fn.search(/if\s+public\.fn_inbound_is_bounce\(/), fn.search(/if\s+public\.fn_is_founder_own_inbox\(v_from\)/));
  const out = [];
  if (!/update\s+public\.inbound_messages\s+set\s+owner_role\s*=\s*v_owner\s*,\s*needs_review\s*=\s*false\s+where\s+id\s*=\s*m\.id/.test(bounce)) {
    out.push('the bounce branch no longer clears needs_review');
  }
  const rest = fn.slice(fn.search(/if\s+public\.fn_is_founder_own_inbox\(v_from\)/));
  if (/needs_review\s*=\s*false/.test(rest)) out.push('a person\'s reply or the founder\'s seed reply leaves the review queue');
  return out;
}

export function laterBodies() {
  const manifest = readFileSync(join(DIR, 'MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim().replace('scripts/sql/', '')).filter((l) => l && !l.startsWith('#'));
  const pos = new Map(manifest.map((f, i) => [f, i]));
  assert.ok(pos.has(RULE_FILE), `${RULE_FILE} is not in MANIFEST.txt`);
  return readdirSync(DIR).filter((f) => f.endsWith('.sql') && !f.endsWith('_probe.sql'))
    .filter((f) => DEFINES.test(readFileSync(join(DIR, f), 'utf8')))
    .filter((f) => !pos.has(f) || pos.get(f) >= pos.get(RULE_FILE));
}

test('every body of the owner at or after #1779 keeps the delivery-report rule', () => {
  const files = laterBodies();
  assert.ok(files.includes(RULE_FILE), 'the rule file itself was not found');
  for (const f of files) assert.deepEqual(ruleProblems(readFileSync(join(DIR, f), 'utf8')), [], f);
});

test('known-bad control: a body rebuilt from before #1779 is caught', () => {
  const good = readFileSync(join(DIR, RULE_FILE), 'utf8');
  const old = good.replace('set owner_role = v_owner, needs_review = false where id = m.id', 'set owner_role = v_owner where id = m.id');
  assert.notEqual(old, good, 'the control did not remove anything');
  assert.match(ruleProblems(old).join(), /no longer clears needs_review/);
});
