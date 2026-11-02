// A SUPPLIER IS VERIFIED ONLY AFTER IT CONFIRMS ITS SERVICES (sales_engineer, 2 Nov 2026, founder ledger 1469).
// Prevented by this file: the gate approving a supplier who has confirmed nothing.
//   node --test scripts/checks/a_supplier_is_verified_only_after_it_confirms_its_services.test.mjs
// Two halves:
//   1. OFFLINE (always runs): the SQL carries the services hold in the right place in the chain (after the document holds, before the
//      automatic approval), the first branch that keeps an approved supplier approved does not mention services, only the three seeders
//      are exempt, and the supplier's confirm re-runs the gate.
//   2. PRODUCTION, one aborted transaction on ZZ DEMO rows (needs a Supabase management token): the definition and the probe are replayed
//      together through safe_replay and the six cases of the probe are asserted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const DEF = read('scripts/sql/a_supplier_is_verified_only_after_it_confirms_its_services.sql');
const PROBE = read('scripts/sql/a_supplier_is_verified_only_after_it_confirms_its_services_probe.sql');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('the services hold sits after the document holds and before the automatic approval', () => {
  const body = DEF.slice(DEF.indexOf('if coalesce(l.approval_status'));
  const at = (s) => body.indexOf(s);
  assert.ok(at("v_reason := 'documents_being_read'") > 0 && at("v_reason := 'services_unconfirmed'") > at("v_reason := 'documents_being_read'"));
  assert.ok(at("elsif coalesce(v_auto, false) then v_decision := 'approved'") > at("v_reason := 'services_unconfirmed'"));
  const first = body.slice(0, body.indexOf('elsif'));
  assert.ok(!/services/.test(first.replace(/--.*$/gm, '')), 'the branch that keeps an approved supplier approved must not ask for services');
});

test('only the three seeders are exempt, and the confirm re-runs the gate', () => {
  assert.match(DEF, /p_source not in \('demo_factory', 'hvac_dress_rehearsal', 'document_intake_accuracy'\)/);
  const ts = read('supabase/functions/_shared/supplier_capability.ts');
  assert.match(ts, /fn_sales_engineer_verifies_supplier[\s\S]{0,120}services_confirmed/, 'capabilityConfirm must run the gate as services_confirmed');
  const portal = read('src/components/portal/supplier/serverCopy.ts');
  assert.match(portal, /services_unconfirmed:/, 'the hold must have words on screen');
});

test('production, rolled back: unconfirmed is held, confirmed is approved, approved is not demoted',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let r = null;
  try { await replaySql(DEF + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    r = JSON.parse(m[1].replace(/^PROBE OK /, '').replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe committed instead of rolling back');
  for (const k of ['a', 'b', 'c', 'd', 'e', 'f']) assert.equal(r[k].demo, true, `case ${k} is not a ZZ DEMO fixture`);
  assert.deepEqual([r.a.status, r.a.reason, r.a.verified], ['pending', 'services_unconfirmed', false], JSON.stringify(r.a));
  assert.deepEqual([r.b.status, r.b.verified], ['approved', true], JSON.stringify(r.b));
  assert.deepEqual([r.c.status, r.c.reason, r.c.verified], ['pending', 'services_unconfirmed', false], 'a confirm older than the newest version is not the current version: ' + JSON.stringify(r.c));
  assert.deepEqual([r.d.status, r.d.verified], ['approved', true], 'an approved supplier is not demoted: ' + JSON.stringify(r.d));
  assert.deepEqual([r.e.status, r.e.verified], ['approved', true], 'a seeder is exempt: ' + JSON.stringify(r.e));
  assert.deepEqual([r.f_before.status, r.f_before.reason], ['pending', 'services_unconfirmed'], JSON.stringify(r.f_before));
  assert.deepEqual([r.f.status, r.f.verified], ['approved', true], 'the confirm releases the hold: ' + JSON.stringify(r.f));
  assert.equal(r.real_leads_before, r.real_leads_after, 'no real lead was touched');
});
