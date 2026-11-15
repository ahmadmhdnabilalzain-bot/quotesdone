// "Photos from the site" on the supplier's inquiry: checked copies only, which shots exist and which do not, and the visit line
// (15 Nov 2026, sales_engineer; founder ledger 1704, ruling 1683). Offline: the admin client is a stub.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { photosLine, releasedSitePhotos, sitePhotosSection, PHOTOS_TITLE, VISIT_LINE } from './site_photos_door.ts';
import { supplierSpec } from '../_shared/site_location.ts';
import type { SitePhotos } from '../_shared/site_photos.ts';

const JOB = (n: number) => `${String(n).padStart(8, '0')}-0000-4000-8000-000000000000`;
const rec: SitePhotos = {
  asked: [{ shot: 'Each indoor unit, from the front', shot_ar: 'x', from: 'replacements', trade: 'hvac', topic_id: 'hvac:spec-split-ac' },
    { shot: 'Where the water from the unit drains', shot_ar: 'x', from: 'drainage', trade: 'hvac', topic_id: 'hvac:spec-split-ac' }],
  photos: [{ shot: 'Each indoor unit, from the front', job_id: JOB(1), via: 'portal' }, { shot: null, job_id: JOB(2), via: 'whatsapp' }, { shot: 'Where the water from the unit drains', job_id: JOB(3), via: 'portal' }],
};

Deno.test('the section lists only released copies, says which shots exist and which do not, and keeps the visit line', () => {
  const s = sitePhotosSection(rec, new Map([[JOB(1), 'https://zz.invalid/a'], [JOB(2), 'https://zz.invalid/b']]))!;
  assertEquals(s.title, PHOTOS_TITLE);
  assertEquals(s.urls, ['https://zz.invalid/a', 'https://zz.invalid/b'], 'a withheld photo (job 3) was listed');
  assertEquals(s.provided, ['Each indoor unit, from the front']);
  assertEquals(s.not_provided, ['Where the water from the unit drains']);
  assertMatch(s.text, /^2 checked photos from the customer, showing: Each indoor unit, from the front\. Not provided: Where the water from the unit drains\. A final price may still need a site visit\.$/);
  const none = sitePhotosSection({ asked: rec.asked, photos: [] }, new Map())!;
  assertMatch(none.text, /^No photo from the customer\. Not provided: .*A final price may still need a site visit\.$/);
  assertEquals(sitePhotosSection(null, new Map()), null);
});

Deno.test('the record never reaches a supplier: it is a customer-only key of the brief', () => {
  const out = supplierSpec({ unit_type: 'wall split', site_photos: rec }, 'Dubai') as Record<string, unknown>;
  assert(!('site_photos' in out));
  assertEquals(out.unit_type, 'wall split');
});

Deno.test('the e-mail line points to the portal and keeps the visit line; nothing when no photo was asked or sent', () => {
  assertMatch(photosLine(rec), /the customer sent 3 photos; the checked copies are shown on the inquiry in the portal\. A final price may still need a site visit\.$/);
  assertEquals(photosLine({ asked: rec.asked, photos: [] }), ' ' + VISIT_LINE);
  assertEquals(photosLine(null), '');
});

Deno.test('only a done, released or masked, recorded photo job of the inquiry\'s own customer counts; anything unreadable is none', async () => {
  const jobs = [
    { id: JOB(1), customer_id: 'c1', why: 'site_photo_check', status: 'done', result: { redaction_complete: true, photo: { status: 'masked' }, drawing_redacted_paths: ['redacted/a/page_p0.jpg'] } },
    { id: JOB(2), customer_id: 'c1', why: 'site_photo_check', status: 'done', result: { redaction_complete: false, photo: { status: 'withheld' } } },
    { id: JOB(3), customer_id: 'c-other', why: 'site_photo_check', status: 'done', result: { redaction_complete: true, photo: { status: 'released' }, drawing_redacted_paths: ['redacted/c/page_p0.jpg'] } },
  ];
  // deno-lint-ignore no-explicit-any
  const admin: any = { from: (t: string) => ({ select: () => ({ in: async () => (t === 'inquiries' ? { data: [{ id: 'i1', customer_id: 'c1', site_photos: rec }], error: null } : { data: jobs, error: null }) }) }) };
  const r = await releasedSitePhotos(admin, ['i1']);
  assertEquals([...r.paths.entries()], [[JOB(1), 'redacted/a/page_p0.jpg']]);
  assertEquals(r.records.get('i1')?.photos.length, 3);
  // deno-lint-ignore no-explicit-any
  const broken: any = { from: () => ({ select: () => ({ in: async () => ({ data: null, error: { message: 'down' } }) }) }) };
  assertEquals((await releasedSitePhotos(broken, ['i1'])).paths.size, 0);
});
