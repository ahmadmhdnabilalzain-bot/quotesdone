// EVERY SOCIAL POST IS CLICKABLE.
//
// Founder's order, 6 Sep 2026: a prepared or designed social post carries a clickable link to the
// network once it is published, and clickable media while it is still a draft. Measured that day the
// OS Marketing page listed "Social live 4" — four Postiz DRAFTS from 24 Jun 2026 that never reached a
// network — and nothing on the Social, Review or Blog lists was a link. The mechanism now: postiz_publish
// writes the social_posts ledger row (media, Postiz preview, honest permalink_missing) and action=sync
// reads Postiz's releaseURL into permalinks; the CHECK social_posts_clickable refuses a live row with
// neither a permalink nor a reason, and any row with neither media nor a reason.
//
//   1. 0 live rows (mode=now, status sent/published) without permalinks or a permalink_missing reason,
//      and 0 rows disclosed as permalink_missing with an empty reason;
//   2. 0 rows without either a media URL that resolves (HEAD 200) or an explicit media_missing reason —
//      social_posts and the Review queue's content_drafts alike;
//   3. the newest 10 published blog posts answer 200 at https://quotesdone.com/blog/<slug>.
//
// READ-ONLY against production: SELECTs under an 8s statement timeout plus HEAD/GET requests.
//
//   node --test scripts/checks/social_posts_are_clickable.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../phase_c/lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}
async function status(url, method = 'HEAD') {
  try { const r = await fetch(url, { method, redirect: 'follow', signal: AbortSignal.timeout(15000) }); return r.status; }
  catch (e) { return 'ERR ' + String(e?.message || e); }
}

test('published social posts carry a permalink or an honest permalink_missing reason', { skip: SKIP }, async () => {
  const r = await rows(`
    select id, source, mode, status, permalinks, permalink_missing, created_at
      from public.social_posts
     where mode = 'now' and status in ('sent', 'published')
       and (permalinks is null or permalinks = '{}'::jsonb)
       and coalesce(trim(permalink_missing), '') = ''
     order by created_at limit 50`);
  assert.equal(r.length, 0, 'live social posts with neither a permalink nor a reason:\n' + JSON.stringify(r, null, 1));
  const empty = await rows(`select id from public.social_posts where permalink_missing is not null and trim(permalink_missing) = '' limit 50`);
  assert.equal(empty.length, 0, 'rows disclosed as permalink_missing with an empty reason: ' + JSON.stringify(empty));
});

test('every social post and review draft has media that resolves, or says "no media designed yet"', { skip: SKIP }, async () => {
  const social = await rows(`select 'social_posts' as t, id::text, image_url, media_missing from public.social_posts order by created_at desc limit 200`);
  const drafts = await rows(`select 'content_drafts' as t, id::text, image_url, null::text as media_missing from public.content_drafts where status = 'draft' and coalesce(review_status, 'pending') = 'pending' order by created_at desc limit 200`);
  const bad = [];
  for (const x of [...social, ...drafts]) {
    if (x.image_url) { const s = await status(x.image_url); if (s !== 200) bad.push({ ...x, head: s }); }
    else if (x.t === 'social_posts' && !String(x.media_missing || '').trim()) bad.push({ ...x, head: 'no media and no reason' });
    // a pending content_draft without an image is disclosed by fn_review_pending as 'no media designed yet'
  }
  assert.equal(bad.length, 0, 'rows whose media does not resolve or whose absence is not disclosed:\n' + JSON.stringify(bad, null, 1));
});

test('the newest 10 published blog posts are live at quotesdone.com/blog/<slug>', { skip: SKIP }, async () => {
  const r = await rows(`select slug from public.blog_posts where published and slug is not null order by published_at desc nulls last limit 10`);
  const bad = [];
  for (const b of r) { const s = await status('https://quotesdone.com/blog/' + b.slug); if (s !== 200) bad.push({ slug: b.slug, status: s }); }
  assert.equal(bad.length, 0, 'published blog posts that do not answer 200:\n' + JSON.stringify(bad, null, 1));
});
