// PROMOTIONAL MESSAGES ARE OPT-IN (19 Oct 2026, founder decision on legal finding 2; seat: ceo).
//
// Fails if: the separate promotional box on customer sign-up or supplier registration starts ticked, is made
// required, or stops being sent; the sign-up writes stop recording it only when exactly true; or the outbox
// gate (the notifications trigger that suppresses a promotional row without consent) is removed from
// scripts/sql/promotional_messages_are_opt_in_and_the_outbox_checks_the_consent.sql.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

for (const f of ['src/components/me/CustomerPortal.tsx', 'src/components/portal/SupplierPortal.tsx']) {
  test(`${f}: the promotional box starts unticked and is not required`, () => {
    const s = read(f);
    assert.match(s, /const \[marketingOptIn, setMarketingOptIn\] = useState\(false\)/, 'the box must start unticked');
    const box = s.split('\n').find((l) => /t\((lang|'en'), 'marketing_opt_in'\)/.test(l));
    assert.ok(box, 'the separate promotional checkbox is missing');
    assert.match(box, /checked=\{marketingOptIn\}/);
    assert.doesNotMatch(box, /required|defaultChecked|Need /, 'the promotional box must never be required or pre-ticked');
    assert.match(s, /marketing_consent: marketingOptIn === true/, 'the choice must be sent with the sign-up');
    // Nothing that blocks proceeding may read the box.
    assert.doesNotMatch(s, /!marketingOptIn/, 'proceeding must not depend on the promotional box');
  });
}

const EN = "marketing_opt_in:'Send me offers and news from QuotesDone by email, SMS or WhatsApp (optional). You can withdraw this at any time.'";
test('customer strings exist in English and Arabic; the supplier box is English only (suppliers always English)', () => {
  const c = read('src/components/me/portalText.ts');
  assert.ok(c.includes(EN), 'customer EN');
  assert.ok(c.includes("marketing_opt_in:'أرغب في تلقّي العروض والأخبار من QuotesDone"), 'customer AR');
  const s = read('src/components/portal/SupplierPortal.tsx');
  assert.ok(s.includes(EN), 'supplier EN');
  assert.ok(!s.includes("marketing_opt_in:'أرغب"), 'no Arabic supplier string');
  assert.ok(s.includes("t('en', 'marketing_opt_in')"), 'supplier box reads English, no lang switch');
});

test('the sign-up writes record consent only when it is exactly true', () => {
  assert.match(read('supabase/functions/kyc/index.ts'), /if \(b\.marketing_consent === true\) await admin\.from\('customers'\)\.update\(\{ marketing_consent: true/);
  assert.match(read('supabase/functions/supplier_api/index.ts'), /if \(body\.marketing_consent === true\) await admin\.from\('leads'\)\.update\(\{ marketing_consent: true/);
});

test('the outbox gate exists and defaults everyone to not consented', () => {
  const sql = read('scripts/sql/promotional_messages_are_opt_in_and_the_outbox_checks_the_consent.sql');
  for (const t of ['customers', 'leads']) assert.match(sql, new RegExp(`alter table public\\.${t} add column if not exists marketing_consent boolean not null default false`));
  assert.match(sql, /create trigger a20_notifications_promotional_consent_gate\s+before insert or update of status on public\.notifications/);
  assert.match(sql, /new\.status := 'suppressed';/);
  assert.match(sql, /not public\.fn_promotional_consent\(new\.to_email, new\.to_phone\)/);
  assert.match(sql, /like 'promo\\_%'/, 'promotional = type starting promo_');
  assert.doesNotMatch(sql, /set marketing_consent = true/i, 'no backfill to true');
  assert.match(sql, /'PROBE OK'/);
});
