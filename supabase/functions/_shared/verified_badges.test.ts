import { assert, assertEquals } from 'jsr:@std/assert@1';
import { verifiedBadges } from './verified_badges.ts';

const today = new Date('2026-10-04T08:00:00Z');
const full = { verified: true, licence_gate_reason: null, license_doc_path: 'l.pdf', license_expiry: '2027-06-24', company_profile_doc_path: 'p.pdf' };
const both = (l: Parameters<typeof verifiedBadges>[0]) => { const b = verifiedBadges(l, today); return [b.licence_verified, b.documents_complete]; };

Deno.test('both badges when verified, not held, both documents on file, licence valid', () => {
  assertEquals(both(full), [true, true]);
  assertEquals(verifiedBadges(full, today).to_earn, { licence_verified: [], documents_complete: [] });
});

Deno.test('an expiry of today still counts as valid', () => {
  assertEquals(both({ ...full, license_expiry: '2026-10-04' }), [true, true]);
});

Deno.test('licence_verified: no badge when unverified', () => {
  assertEquals(verifiedBadges({ ...full, verified: false }, today).licence_verified, false);
});
Deno.test('licence_verified: no badge when held (licence_gate_reason set)', () => {
  assertEquals(verifiedBadges({ ...full, licence_gate_reason: 'name mismatch' }, today).licence_verified, false);
});
Deno.test('licence_verified: no badge when the licence document is missing', () => {
  assertEquals(verifiedBadges({ ...full, license_doc_path: null }, today).licence_verified, false);
});
Deno.test('licence_verified: no badge when the expiry is null', () => {
  const b = verifiedBadges({ ...full, license_expiry: null }, today);
  assertEquals(b.licence_verified, false);
  assertEquals(b.to_earn.licence_verified, ['Your trade licence expiry date has not been read yet']);
});
Deno.test('licence_verified: no badge when the licence expired yesterday', () => {
  assertEquals(verifiedBadges({ ...full, license_expiry: '2026-10-03' }, today).licence_verified, false);
});

Deno.test('documents_complete is never shown to a held supplier', () => {
  const b = verifiedBadges({ ...full, licence_gate_reason: 'licence unreadable' }, today);
  assertEquals([b.licence_verified, b.documents_complete], [false, false]);
  // 12 Nov 2026 (walk finding M12): a hold says its own reason, not "on hold - see the notice on your overview" (there is no
  // overview). 'licence unreadable' is not a reason code the gate writes, so it reads as the general check, never a guess.
  assertEquals(b.to_earn.documents_complete, ['Your registration is being checked by QuotesDone']);
});

Deno.test('M12: each hold says its own reason; services_unconfirmed never mentions the licence', () => {
  const svc = verifiedBadges({ ...full, verified: false, licence_gate_reason: 'services_unconfirmed' }, today);
  assertEquals([svc.to_earn.licence_verified, svc.to_earn.documents_complete], [['Confirm your services on the Services tab'], ['Confirm your services on the Services tab']]);
  assertEquals(verifiedBadges({ ...full, licence_gate_reason: 'licence_expiry_unread' }, today).to_earn.licence_verified[0], 'Upload a clearer copy of your trade licence (a PDF, or a sharp photo of the whole page)');
  for (const r of ['services_unconfirmed', 'reg_terms', 'documents_being_read', 'licence_being_read', 'licence_unreadable', 'licence_name_mismatch', 'anything_else']) {
    const all = JSON.stringify(verifiedBadges({ ...full, licence_gate_reason: r }, today).to_earn);
    assert(!/on hold|overview/i.test(all), `${r}: ${all}`);
  }
});

Deno.test('documents_complete is never shown to an unverified supplier', () => {
  const b = verifiedBadges({ ...full, verified: false }, today);
  assertEquals([b.licence_verified, b.documents_complete], [false, false]);
  assertEquals(b.to_earn.documents_complete, ['Your trade licence is awaiting verification by QuotesDone']);
});

Deno.test('missing company profile loses documents_complete only, and says what to upload', () => {
  const b = verifiedBadges({ ...full, company_profile_doc_path: null }, today);
  assertEquals([b.licence_verified, b.documents_complete], [true, false]);
  assertEquals(b.to_earn.documents_complete, ['Upload your company profile']);
});

Deno.test('an expired licence removes BOTH badges; an empty row earns nothing', () => {
  assertEquals(both({ ...full, license_expiry: '2026-10-03' }), [false, false]);
  const e = verifiedBadges(null, today);
  assertEquals([e.licence_verified, e.documents_complete, e.to_earn.documents_complete.length], [false, false, 2]);
});
