// node --test src/components/portal/supplier/licenceExpiry.test.mjs
// Supplier registration certification, free round of 11 Nov 2026, finding 6 (customer_support): an expired licence (fixture L8,
// expired 31 Aug 2026) was read at upload and the step said only "expires 2026-08-31"; the supplier learned it at Submit. This
// fails if the licence step stops saying, at upload, that the licence has expired and what to do, in either licence door.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dubaiToday, expiredLicenceNote, licenceHasExpired } from './licenceExpiry.ts';

const at = (iso) => Date.parse(iso);

test('a licence that expired before today in Dubai has expired; today and later have not; an unread date never has', () => {
  const now = at('2026-11-11T08:00:00Z');
  assert.equal(licenceHasExpired('2026-08-31', now), true);
  assert.equal(licenceHasExpired('2026-11-11', now), false, 'it expires at the end of its own day');
  assert.equal(licenceHasExpired('2027-02-15', now), false);
  assert.equal(licenceHasExpired(null, now), false);
  assert.equal(licenceHasExpired('31/08/2026', now), false, 'a date the reader did not normalise is not called expired');
});

test('the day turns at midnight in Dubai, not at midnight UTC', () => {
  // 21:00 UTC on 10 Nov is 01:00 on 11 Nov in Dubai: a licence that expired on 10 Nov has expired there
  assert.equal(dubaiToday(at('2026-11-10T21:00:00Z')), '2026-11-11');
  assert.equal(licenceHasExpired('2026-11-10', at('2026-11-10T21:00:00Z')), true);
  assert.equal(licenceHasExpired('2026-11-10', at('2026-11-10T19:00:00Z')), false);
});

test('the note says plainly that it has expired, when, and what to do, in English, with no code or status', () => {
  const s = expiredLicenceNote('2026-08-31', 'ZZ-261150');
  assert.match(s, /expired on 31 Aug 2026/);
  assert.match(s, /upload your renewed trade licence/i);
  assert.match(s, /ZZ-261150/);
  assert.doesNotMatch(s, /[\u0600-\u06FF]/, 'suppliers are written to in English (ruling 1008)');
  assert.doesNotMatch(s, /licence_expired|invalid|denied|not allowed|you must/i, 'plain and polite (criterion 7)');
});

test('both licence doors say it at upload: the registration form and the Documents tab', () => {
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.match(form, /const gone = licenceHasExpired\(ex\.expiry\);[^\n]*gone \? expiredLicenceNote\(ex\.expiry, ex\.license_number\)/, 'the registration form');
  const docs = readFileSync(new URL('./core/Documents.tsx', import.meta.url), 'utf8');
  assert.match(docs, /read\.kind === 'license' && licenceHasExpired\(read\.expiry\)/, 'the Documents tab');
});

// Second free round on production (11 Nov 2026), J4 (phone photo) and J5 (scan) with the models off: the form said "we will e-mail
// you for a clearer copy" and the Documents tab "please upload a clear PDF", of a licence OUR reader had not read (#1909 holds it
// as licence_being_read and reads it again). This fails if either door goes back to asking the supplier.
test('a licence our reader has not finished is said as ours, in both doors, in the servers\' own words', async () => {
  const { LICENCE_BEING_READ_NOTE, licenceBeingRead } = await import('./licenceExpiry.ts');
  const server = readFileSync(new URL('../../../../supabase/functions/_shared/licence_read_state.ts', import.meta.url), 'utf8');
  assert.ok(server.includes(JSON.stringify(LICENCE_BEING_READ_NOTE).replace(/"/g, "'")), 'the portal\'s sentence must be the servers\' LICENCE_BEING_READ_NOTE');
  assert.equal(licenceBeingRead({ license_read_state: 'ours_failed' }), true);
  assert.equal(licenceBeingRead({ being_read: true }), true);
  assert.equal(licenceBeingRead({ license_read_state: 'read' }), false);
  assert.doesNotMatch(LICENCE_BEING_READ_NOTE, /clearer copy|upload/i, 'nothing is asked of the supplier');
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  assert.match(form, /if \(licenceBeingRead\(j\)\) \{ setLicExpired\(false\); setLicNote\(LICENCE_BEING_READ_NOTE\); \}/);
  const docs = readFileSync(new URL('./core/Documents.tsx', import.meta.url), 'utf8');
  const beingRead = docs.indexOf('if (licenceBeingRead(read)) return');
  assert.ok(beingRead > 0 && beingRead < docs.indexOf('if (read.unread) return'), 'the Documents tab must say it before its "upload a clear PDF" line');
});
