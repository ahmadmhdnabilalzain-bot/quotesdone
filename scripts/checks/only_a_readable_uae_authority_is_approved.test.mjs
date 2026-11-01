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
  for (const reason of ['licence_authority_unread', 'licence_authority_not_uae']) {
    const at = SQL.indexOf(`v_decision := 'pending'; v_reason := '${reason}';`);
    assert.ok(at > 0 && at < auto, `${reason} is not held before approval`);
  }
  assert.match(SQL, /and not v_authority_unread and not v_authority_foreign then/);
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

test('every UAE authority of the corpus passes the allowlist and a foreign one does not', async () => {
  const { AUTHORITIES } = await import('../e2e/document_intake_corpus.mjs');
  const src = /lower\(p_authority\) ~ '\\y\(([^)]+)\)\\y'/.exec(SQL)[1];
  const uae = new RegExp(`\\b(${src})\\b`);
  for (const [k, a] of Object.entries(AUTHORITIES)) assert.ok(uae.test(a.authority.toLowerCase()), `${k}: ${a.authority} would be held as foreign`);
  for (const f of ['Ministry of Commerce, Kingdom of Saudi Arabia', 'Companies House, United Kingdom', 'Qatar Financial Centre', 'Oman Ministry of Commerce']) assert.ok(!uae.test(f.toLowerCase()), `${f} passes`);
});

test('the supplier is shown why', () => {
  const copy = R('src/components/portal/supplier/serverCopy.ts');
  assert.match(copy, /licence_authority_unread: s\(/);
  assert.match(copy, /licence_authority_not_uae: s\(/);
});
