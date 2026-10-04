import { assertEquals } from 'jsr:@std/assert@1';
import { verifiedBadges } from './verified_badges.ts';

const today = new Date('2026-10-04T08:00:00Z');
const full = { verified: true, license_doc_path: 'l.pdf', license_expiry: '2027-06-24', company_profile_doc_path: 'p.pdf' };

Deno.test('both badges when verified, both required documents on file, licence valid', () => {
  const b = verifiedBadges(full, today);
  assertEquals([b.licence_verified, b.documents_complete], [true, true]);
  assertEquals(b.to_earn.documents_complete, []);
});

Deno.test('missing company profile loses documents_complete only, and says what to upload', () => {
  const b = verifiedBadges({ ...full, company_profile_doc_path: null }, today);
  assertEquals([b.licence_verified, b.documents_complete], [true, false]);
  assertEquals(b.to_earn.documents_complete, ['Upload your company profile']);
});

Deno.test('an expired licence removes BOTH badges', () => {
  const b = verifiedBadges({ ...full, license_expiry: '2026-10-03' }, today);
  assertEquals([b.licence_verified, b.documents_complete], [false, false]);
});

Deno.test('an unverified licence on file waits for verification; empty row earns nothing', () => {
  assertEquals(verifiedBadges({ ...full, verified: false }, today).to_earn.licence_verified, ['Your trade licence is awaiting verification by QuotesDone']);
  const e = verifiedBadges(null, today);
  assertEquals([e.licence_verified, e.documents_complete, e.to_earn.documents_complete.length], [false, false, 2]);
});
