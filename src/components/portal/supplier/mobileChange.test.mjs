// node --test src/components/portal/supplier/mobileChange.test.mjs
// WALK OF 12 NOV 2026, B2 (sales_engineer, built by it_engineer): on the Profile tab another number typed into the mobile box kept
// "Mobile verified" on screen with no way to verify it (w2_iphone_profile_mobile_changed.jpg), and Save then un-verified the number
// while the page said "Changes saved.". This fails if a changed number reads verified, if formatting alone reads as a change, if the
// Profile tab stops offering the code for the new number, or if its save sends a number that is not verified yet.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { MOBILE_CHANGE, numberChanged, verifiedWords } from './mobileChange.ts';

const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');

test('a different number is a change; the same number written another way is not; nothing verified is never "changed"', () => {
  assert.equal(numberChanged('+971500000011', '055 999 9999'), true);
  assert.equal(numberChanged('+971500000011', '050 000 0011'), false);
  assert.equal(numberChanged('+971500000011', '+971 50 000 0011'), false);
  assert.equal(numberChanged('+971500000011', ''), true, 'an emptied box is not the verified number');
  assert.equal(numberChanged('', '055 999 9999'), false);
});

test('the verified line names the WhatsApp code only when that code proved this same number (Settings\' words, PR #1984)', () => {
  assert.equal(verifiedWords('+971500000011', { verified: true, phone: '+971500000011' }), 'Mobile number verified by WhatsApp code');
  assert.equal(verifiedWords('+971500000011', { verified: true, phone: '+971559999999' }), 'Mobile number verified');
  assert.equal(verifiedWords('+971500000011', null), 'Mobile number verified');
  assert.match(MOBILE_CHANGE.not_verified('+971500000011'), /not verified yet\. Your verified number \+971 50 000 0011 stays/);
});

test('the Profile tab reads a changed number as not verified, offers the code, and does not send it at Save', () => {
  assert.match(form, /const changedNo = isEdit && phoneVerified && numberChanged\(provenPhone, f\.phone\)/);
  assert.match(form, /const shownVerified = phoneVerified && !changedNo/);
  assert.match(form, /\{shownVerified \? <div[^>]*>\{isEdit \? verifiedWords\(provenPhone, wa\)/, 'the verified line still keys on the flag alone');
  assert.match(form, /data-testid="mobile-not-verified"/);
  assert.match(form, /if \(keptPhone\) delete payload\.phone/, 'Save sends a number that is not verified');
  assert.match(form, /MOBILE_CHANGE\.saved_kept\(keptPhone\)/, 'Save says "Changes saved." without saying the number was kept');
});
