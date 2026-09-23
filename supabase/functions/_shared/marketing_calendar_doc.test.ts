// The monthly calendar is drawn from the loaded rows, on the company PDF template (marketing, 23 Sep 2026).
//   deno test --allow-net=esm.sh supabase/functions/_shared/marketing_calendar_doc.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { calendarBlocks, calendarRows, calendarSheet, dubai, type CalPost } from './marketing_calendar_doc.ts';
import { renderPdf } from '../pdf_native/render.ts';

const V = 'campaigns/2026-month1-supplier-recruitment/videos/01.mp4';
const URL1 = 'https://stub.invalid/storage/v1/object/sign/marketing-media/' + V + '?token=zz';
const POSTS: CalPost[] = [
  { ingest_key: 'm1-02-x', scheduled_at: '2026-10-02T08:00:00Z', scheduled_local: '2026-10-02T12:00:00', title: 'Three quotes', cta_url: 'https://www.quotesdone.ae/suppliers',
    video_path: V, video_sha256: 'a'.repeat(64),
    variants: [
      { platform: 'x', seq: 2, language: 'ar', post_type: 'video', body: 'الموردون', hashtags: [], title: null, alt_text: null, first_comment: null },
      { platform: 'x', seq: 1, language: 'en', post_type: 'video', body: 'Suppliers\n\n#UAE', hashtags: ['UAE'], title: null, alt_text: null, first_comment: null }] },
  { ingest_key: 'm1-01-instagram', scheduled_at: '2026-10-01T15:00:00Z', scheduled_local: '2026-10-01T19:00:00', title: 'Three quotes', cta_url: null,
    video_path: V, video_sha256: 'a'.repeat(64),
    variants: [{ platform: 'instagram', seq: 1, language: 'bi', post_type: 'reel', body: 'Get requests\n\nاستقبل الطلبات\n\n#UAE #Suppliers',
                 hashtags: ['UAE', 'Suppliers'], title: null, alt_text: 'A supplier on a phone', first_comment: 'Link in bio' }] },
];

Deno.test('one row per platform post, in time order, with hashtags in their own column', () => {
  const rows = calendarRows(POSTS, { [V]: URL1 });
  assertEquals(rows.map((r) => [r.n, r.date, r.time, r.platform]), [[1, 'Thu 01 Oct 2026', '19:00', 'Instagram · Reel'], [2, 'Fri 02 Oct 2026', '12:00', 'X · Video']]);
  assertEquals(rows[0].caption, 'Get requests\n\nاستقبل الطلبات\n\n#UAE #Suppliers', 'the caption cell is the exact text sent, hashtags included');
  assertEquals(rows[0].hashtags, '#UAE #Suppliers');
  assertEquals(rows[0].video_url, URL1);
  assertEquals(rows[1].caption, '(1/2) Suppliers\n\n#UAE\n\n(2/2) الموردون', 'a thread shows its parts in order');
  assertEquals(rows[0].extra, 'First comment: Link in bio');
  assertEquals(dubai('2026-10-31T21:30:00Z'), { date: 'Sun 01 Nov 2026', time: '01:30' });
});

Deno.test('the spreadsheet carries the same rows and live links', () => {
  const { aoa, links } = calendarSheet(calendarRows(POSTS, { [V]: URL1 }));
  assertEquals(aoa[0].slice(0, 9), ['#', 'Date', 'Dubai time', 'Platform', 'Video', 'Video link', 'Caption used', 'Hashtags used', 'Link']);
  assertEquals(aoa.length, 3);
  assert(links.some((l) => l.r === 1 && l.c === 5 && l.url === URL1));
  assert(links.some((l) => l.r === 2 && l.c === 8 && l.url === 'https://www.quotesdone.ae/suppliers'));
});

Deno.test('the PDF renders on the company template with a pressable link per video', async () => {
  const rows = calendarRows(POSTS, { [V]: URL1 });
  const blocks = calendarBlocks({ campaign_key: '2026-month1-supplier-recruitment', theme: 'Supplier recruitment', month: 'October 2026', hash: 'f'.repeat(64), expires: '14 Nov 2026' }, rows, []);
  const out = await renderPdf({ title: 'Social calendar October 2026', blocks }, { fetchBytes: () => Promise.resolve(null) });
  assert(out.ok, JSON.stringify((out as any).body));
  if (out.ok) {
    assertEquals(new TextDecoder().decode(out.bytes.slice(0, 5)), '%PDF-');
    assert(out.meta.links >= 3, 'two video links and the post link were written as link annotations, got ' + out.meta.links);
  }
});
