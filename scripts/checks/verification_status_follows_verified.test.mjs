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

test('the mapping is total: true -> verified, else -> unverified', () => {
  assert.match(sql, /new\.verification_status := case when new\.verified is true then 'verified' else 'unverified' end/);
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
