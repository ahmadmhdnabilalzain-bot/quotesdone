// "Photos from the site" on the supplier's inquiry: checked copies only, which shots exist and which do not, and the visit line
// (15 Nov 2026, sales_engineer; founder ledger 1704, ruling 1683). Offline: the admin client is a stub.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { photoStates, photosAtSend, photosLine, releasedSitePhotos, sitePhotosSection, PHOTOS_TITLE, VISIT_LINE } from './site_photos_door.ts';
import { supplierSpec } from '../_shared/site_location.ts';
import type { SitePhotos } from '../_shared/site_photos.ts';
import { inquiryDocument } from '../_shared/quote_documents.ts';
import { REQUEST } from '../_shared/quote_documents.fixture.ts';

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

// Review of bf8b9ea45, item 3: the line said "the customer sent 3 photos; the checked copies are shown" when none was checked yet,
// and counted withheld photos. It now counts only released copies and says the rest are still being checked.
Deno.test('the e-mail line counts only released copies, says what is still being checked, and keeps the visit line', () => {
  assertMatch(photosLine(rec, { released: 1, checking: 1 }), /^ Photos from the site: 1 checked photo from the customer is shown on the inquiry in the portal\. One more is being checked and will be added there if cleared\. A final price may still need a site visit\.$/);
  assertMatch(photosLine(rec, { released: 0, checking: 3 }), /^ Photos from the site: the customer's photos are being checked; any that clear are shown on the inquiry in the portal\. A final/);
  // three photos sent, all withheld: no count, no promise
  assertEquals(photosLine(rec, { released: 0, checking: 0 }), ' ' + VISIT_LINE);
  assert(!/3/.test(photosLine(rec, { released: 2, checking: 0 })), 'a withheld photo was counted');
  assertEquals(photosLine({ asked: rec.asked, photos: [] }), ' ' + VISIT_LINE);
  assertEquals(photosLine(null), '');
});

Deno.test('photoStates and photosAtSend: only this customer\'s photo jobs; released, checking and withheld told apart', async () => {
  const jobs = [
    { id: JOB(1), customer_id: 'c1', why: 'site_photo_check', status: 'done', result: { redaction_complete: true, photo: { status: 'released' }, drawing_redacted_paths: ['redacted/a/page_p0.jpg'] } },
    { id: JOB(2), customer_id: 'c1', why: 'site_photo_check', status: 'queued', result: null },
    { id: JOB(3), customer_id: 'c1', why: 'site_photo_check', status: 'done', result: { redaction_complete: false, photo: { status: 'withheld' } } },
  ];
  // deno-lint-ignore no-explicit-any
  const admin: any = { from: () => ({ select: () => ({ in: (_c: string, ids: string[]) => ({ eq: (_k: string, v: string) => {
    // deno-lint-ignore no-explicit-any
    const q: any = { data: jobs.filter((j) => ids.includes(j.id) && j.customer_id === v), error: null }; q.eq = () => q; return q; } }) }) }) };
  assertEquals(await photoStates(admin, 'c1', rec), { released: 1, checking: 1 });
  // a photo uploaded after the last chat turn: the intake record has none, Send carries two jobs, one is another customer's
  const kept = await photosAtSend(admin, 'c1', { asked: rec.asked, photos: [] }, [{ job_id: JOB(2), shot: rec.asked[1].shot }, { job_id: JOB(9) }]);
  assertEquals(kept?.photos, [{ shot: rec.asked[1].shot, job_id: JOB(2), via: 'portal' }]);
  assertEquals(await photosAtSend(admin, 'c1', null, []), null);
});

Deno.test('the section carries the shots in Arabic too, for the Arabic inquiry PDF', () => {
  const s = sitePhotosSection({ ...rec, asked: rec.asked.map((a, i) => ({ ...a, shot_ar: 'zz-ar-' + i })) }, new Map([[JOB(1), 'https://zz.invalid/a']]))!;
  assertEquals([s.provided_ar, s.not_provided_ar], [['zz-ar-0'], ['zz-ar-1']]);
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

// Review of bf8b9ea45, item 3: the inquiry PDF a supplier downloads said nothing of the photos.
Deno.test('the inquiry PDF prints "Photos from the site": the checked copies in the portal, shots provided and not, the visit line', () => {
  const sec = sitePhotosSection(rec, new Map([[JOB(1), 'https://zz.invalid/a']]))!;
  const doc = JSON.stringify(inquiryDocument({ inquiry: { ...REQUEST, site_photos: { shown: sec.urls.length, provided: sec.provided, not_provided: sec.not_provided } }, lang: 'en' }));
  assertMatch(doc, /Photos from the site/);
  assertMatch(doc, /1 checked photo from the customer, with anything that could identify them covered, is on this inquiry in the portal/);
  assertMatch(doc, /Shots provided.*Each indoor unit, from the front/);
  assertMatch(doc, /Not provided.*Where the water from the unit drains/);
  assertMatch(doc, /A final price may still need a site visit/);
  assert(!/zz\.invalid/.test(doc), 'a signed link was printed');
  assert(!/Photos from the site/.test(JSON.stringify(inquiryDocument({ inquiry: { ...REQUEST, site_photos: null }, lang: 'en' }))));
});
