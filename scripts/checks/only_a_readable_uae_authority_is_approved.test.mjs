// ONLY A READABLE UAE AUTHORITY IS APPROVED, AND A HELD REGISTRATION HAS A DECIDER (sales_engineer, 2 Nov 2026, ledger 1442).
// Offline, over the source. The behaviour is proved by scripts/e2e/supplier_document_read_walk.mjs on real files.
//   node --test scripts/checks/only_a_readable_uae_authority_is_approved.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = R('scripts/sql/only_a_readable_uae_authority_is_approved_and_a_held_registration_has_a_decider.sql');

test('both authority holds stand before automatic approval, and an approved supplier is asked too', () => {
  const auto = SQL.indexOf("elsif coalesce(v_auto, false) then v_decision := 'approved';");
  for (const reason of ['licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed']) {
    const at = SQL.indexOf(`v_decision := 'pending'; v_reason := '${reason}';`);
    assert.ok(at > 0 && at < auto, `${reason} is not held before approval`);
  }
  assert.match(SQL, /and not v_authority_unread and not v_authority_foreign and not v_authority_unknown then/);
});

test('a supplier cannot type the authority, and an old licence never judges a new one', () => {
  const api = R('supabase/functions/supplier_api/index.ts');
  assert.doesNotMatch(/const PROFILE_COLS = \[[^\]]*\]/.exec(api)[0], /license_authority/);
  assert.match(api, /upd\.trade_license_no = null; upd\.license_authority = null;/);
  assert.match(R('supabase/functions/supplier_portal/index.ts'), /upd\.license_authority = null; upd\.license_expiry = null;/);
  assert.match(R('supabase/functions/_shared/document_expiry.ts'), /licenceNeedsModel = [^\n]*!c\?\.authority/);
});

test('the decider asks, then closes through the ceo seat, on a clock that is actually run', () => {
  assert.match(SQL, /v_days >= 14[\s\S]*approval_decided_by = 'ceo'/);
  assert.match(SQL, /'registration incomplete after 14 days: '/, 'the gate reopens only on this wording');
  assert.match(SQL, /v_asks = 0 or \(v_asks = 1 and v_days >= 3\) or \(v_asks = 2 and v_days >= 7\)/);
  assert.match(R('supabase/functions/resilience_ping/index.ts'), /rpc\('fn_sales_engineer_decides_held_registrations'\)/);
  assert.match(SQL, /revoke execute on function public\.fn_sales_engineer_decides_held_registrations\(timestamptz\) from public, anon, authenticated;/);
});

test('every corpus authority is in the apply-time table logic, and unknown is never foreign', async () => {
  const { AUTHORITIES } = await import('../e2e/document_intake_corpus.mjs');
  const list = (name) => new RegExp(name + " text\\[\\] := array\\[([\\s\\S]*?)\\];").exec(SQL)[1].match(/'([^']+)'/g).map((x) => x.slice(1, -1));
  const known = [...list('v_strong'), ...list('v_weak')];
  const norm = (a) => ' ' + a.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim() + ' ';
  for (const [k, a] of Object.entries(AUTHORITIES)) assert.ok(known.some((x) => norm(a.authority).includes(' ' + x + ' ')), k + ': ' + a.authority);
  assert.match(SQL, /if v_f and v_s then return 'unknown'/);
  assert.match(SQL, /return 'unknown';\nend/);
  for (const c of ['RAK Economic Zone', 'Abu-Dhabi', 'راس الخيمة', 'Ministry of Economy, Kuwait', 'Northern Registry Office']) assert.ok(SQL.includes("'" + c + "'"), c + ' is not in the apply-time table');
});

test('nothing approved, unknown or answered is closed, and every licence door clears the old fields', () => {
  assert.match(SQL, /v_replied or \(v_days >= 14 and \(v_ever_approved or r\.reason = 'licence_authority_unconfirmed'\)\)/);
  assert.ok(SQL.indexOf('fn_ceo_task_open') < SQL.indexOf("approval_decided_by = 'ceo'"), 'the ceo branch must come before the close');
  for (const f of ['supabase/functions/resend_inbound/index.ts', 'supabase/functions/wa_inbound/index.ts']) assert.match(R(f), /trade_license_no: null, license_authority: null, license_expiry: null/, f);
});

test('the supplier is shown why', () => {
  const copy = R('src/components/portal/supplier/serverCopy.ts');
  assert.match(copy, /licence_authority_unread: s\(/);
  assert.match(copy, /licence_authority_not_uae: s\(/);
});
