// THE SOCIAL CALENDAR OBEYS THE FOUNDER'S COPY RULES (marketing, 23 Sep 2026).
// Founder, 23 Sep 2026: social copy is English only, never the word "AI" (say "smart"), never the trade licence
// number. Every month's calendar file in docs/marketing/ in the loader's shape (YYYY-MM_social_calendar.json)
// is read; what fn_marketing_calendar_load would store and publish (caption, hashtags, title, alt text, first
// comment) must carry none of them. Also: the five platforms of the plan, and every link on quotesdone.ae.
//   node --test scripts/checks/the_social_calendar_obeys_the_copy_rules.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';

const DIR = new URL('../../docs/marketing/', import.meta.url);
const files = readdirSync(DIR).filter((f) => /^\d{4}-\d{2}_social_calendar\.json$/.test(f));

test('at least one month calendar is in the loader shape', () => assert.ok(files.length > 0));

for (const f of files) {
  test(f + ' obeys the copy rules', () => {
    const cal = JSON.parse(readFileSync(new URL(f, DIR), 'utf8'));
    const bad = [];
    for (const p of cal.posts) {
      const text = [p.caption_en, p.caption_ar, p.title, p.alt_text, p.first_comment, ...(p.hashtags || [])].filter(Boolean).join('\n');
      if (/[؀-ۿ]/.test(text) || p.caption_ar) bad.push(p.key + ': Arabic');
      if (/\bA\.?I\b/.test(text)) bad.push(p.key + ': the word AI');
      if (/1633275|licen[cs]e (no|number)/i.test(text)) bad.push(p.key + ': licence number');
      if (!['linkedin', 'facebook', 'youtube', 'instagram', 'tiktok'].includes(p.platform)) bad.push(p.key + ': platform ' + p.platform);
      // the alt text describes the video, whose end card prints quotesdone.com; what we WRITE links to quotesdone.ae
      if (/quotesdone\.com/i.test([p.caption_en, p.first_comment, p.cta_url].join(' '))) bad.push(p.key + ': quotesdone.com (the site is quotesdone.ae)');
    }
    assert.deepEqual(bad, []);
  });
}
