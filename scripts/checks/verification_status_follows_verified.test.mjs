// verification_status_follows_verified.test.mjs — sales_engineer, 19 Oct 2026 (ruling 1230 walk).
// Approval set leads.verified but nothing set leads.verification_status, so approved suppliers read "unverified".
// The fix is one BEFORE trigger that derives the column from the FINAL verified value. This pins the shape that
// makes it work for every writer: fires on every UPDATE (no column list), sorts after trg_leads_e0_* so the
// mandatory-six demotion is seen, and maps true -> 'verified', anything else -> 'unverified'. Once applied, the
// schema mirror must carry the same trigger.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const FILE = 'scripts/sql/a_verified_supplier_reads_verified_in_verification_status.sql';
const TRG = 'trg_leads_z90_verification_status_follows_verified';
const sql = readFileSync(FILE, 'utf8').replace(/--[^\n]*/g, '');

test('the trigger fires before insert or update with no column list', () => {
  assert.match(sql, new RegExp(`create trigger ${TRG}\\s+before insert or update on public\\.leads\\s+for each row`, 'i'));
});

test('it sorts after the mandatory-six gate, so a demotion is seen', () => {
  assert.ok(TRG > 'trg_leads_e0_mandatory_six_gate');
});

// Runs the trigger's CASE by translating it out of the file, so the downgrade rule is executed, not just
// matched: verified=false never overwrites 'held', 'pending' or 'rejected' (release review of #1486).
const derive = (verified, status) => {
  const body = sql.match(/new\.verification_status := case([\s\S]*?)end;/i)[1];
  const js = body
    .replace(/when new\.verified is true then 'verified'/i, "verified === true ? 'verified' :")
    .replace(/when new\.verification_status is null or new\.verification_status = 'verified' then 'unverified'/i, "(status == null || status === 'verified') ? 'unverified' :")
    .replace(/else new\.verification_status/i, 'status');
  return Function('verified', 'status', 'return (' + js + ')')(verified, status);
};

test('true -> verified, whatever the status was', () => {
  for (const s of [null, 'unverified', 'held', 'pending']) assert.equal(derive(true, s), 'verified');
});

test('a downgrade clears verified or null to unverified', () => {
  assert.equal(derive(false, 'verified'), 'unverified');
  assert.equal(derive(false, null), 'unverified');
  assert.equal(derive(null, null), 'unverified');
});

test('a downgrade never wipes held, pending or rejected', () => {
  assert.equal(derive(false, 'held'), 'held');
  assert.equal(derive(false, 'pending'), 'pending');
  assert.equal(derive(false, 'rejected'), 'rejected');
});

test('the correction names exact ids and never lead 143027', () => {
  assert.match(sql, /where id in \(126512, 144967\)/);
  assert.doesNotMatch(sql, /143027/);
});

test('once applied, the mirror carries the trigger (or the file is still pending)', () => {
  const pending = existsSync('scripts/sql/pending/a_verified_supplier_reads_verified_in_verification_status.txt');
  if (pending) return;
  assert.ok(readSchemaMirror().includes(TRG), `${TRG} is not in the schema mirror after apply`);
});
