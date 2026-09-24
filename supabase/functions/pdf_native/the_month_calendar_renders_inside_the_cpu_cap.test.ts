// deno test --no-lock -A supabase/functions/pdf_native/the_month_calendar_renders_inside_the_cpu_cap.test.ts
// 24 Sep 2026 (marketing): the marketing_channels beat renders the month's calendar PDF in-process. With 60 posts,
// fontkit's OpenType layout ran on every growing line prefix (~3.1 s of CPU measured locally), the edge CPU cap
// killed the beat from 20:21 UTC on 23 Sep, and the calendar was never sent. render.ts now caches word widths.
// This renders the real first calendar (docs/marketing/2026-09_social_calendar.json, 60 posts) and fails if the
// render is back above 2.5 s here (it measured 3.1 s before the fix and 0.7 s after, on the same machine).
import { assert } from 'jsr:@std/assert@1';
import { calendarBlocks, calendarRows, type CalPost } from '../_shared/marketing_calendar_doc.ts';
import { renderPdf } from './render.ts';

const FONTS = new URL('./fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => (/\.ttf$/.test(p) ? await Deno.readFile(new URL(p, FONTS)) : null);

Deno.test('the 60-post calendar renders well inside the edge CPU budget', async () => {
  const cal = JSON.parse(await Deno.readTextFile(new URL('../../../docs/marketing/2026-09_social_calendar.json', import.meta.url)));
  // deno-lint-ignore no-explicit-any
  const posts: CalPost[] = cal.posts.map((p: any, i: number) => ({ id: i, ingest_key: p.key, scheduled_at: p.at_utc, scheduled_local: p.at_dubai,
    title: p.video.title, cta_url: p.cta_url, video_path: p.video.path, video_sha256: p.video.sha256, cover_path: null,
    variants: [{ post_id: i, platform: p.platform, seq: 1, language: 'en', post_type: 'video', title: p.video.title, alt_text: p.alt_text,
      first_comment: null, hashtags: p.hashtags, body: p.caption_en + '\n\n#' + (p.hashtags || []).join(' #') }] }));
  const urls = Object.fromEntries(posts.map((p) => [p.video_path, 'https://example.invalid/zz-demo/' + 'x'.repeat(300)]));
  const t0 = performance.now();
  const blocks = calendarBlocks({ campaign_key: 'zz-demo', theme: 't', month: 'September 2026', hash: '0'.repeat(64), expires: '2026-11-01' },
    calendarRows(posts, urls), []);
  const r = await renderPdf({ title: 'Social calendar', blocks }, { fetchBytes });
  const ms = performance.now() - t0;
  assert(r.ok, 'the calendar did not render');
  assert(ms < 2500, `the 60-post calendar took ${Math.round(ms)} ms to render: the edge CPU cap will kill the marketing beat again`);
});
