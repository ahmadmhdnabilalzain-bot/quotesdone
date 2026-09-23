-- THE MARKETING SEAT KNOWS EVERY PLATFORM'S LIMITS, AND EACH ONE CITES ITS PAGE (23 Sep 2026; seat: marketing).
--
-- Founder, instruction 869: "Make sure our agent as well, the marketing agent, is having the right knowledge
-- about captioning limits for every platform, aspect ratio needed, and stuff like that. Otherwise, things will
-- get messy." Scope: the channels synced in Postiz — Instagram (feed + Reels), Facebook (feed + Reels), X,
-- YouTube (regular + Shorts), LinkedIn company page, and TikTok (video + photo; the founder connected it in Postiz
-- on 23 Sep 2026, after first leaving it out). Organic only.
--
-- WHAT WAS MEASURED BEFORE THIS FILE (23 Sep 2026, read-only):
--   * artifact_platform_spec (v3_artifact_review.sql + v3_video_platform_specs.sql) holds 14 media rows with NO
--     source and NO caption limits. Two of its numbers are now wrong against the official pages read today:
--     youtube/short max_duration_s 60 (YouTube: 180 since Oct 2024) and instagram/reel max 90 s with 100 MB
--     (Graph API: 900 s, 300 MB). It is the artifact reviewer's media gate; section 7b corrects those two rows.
--   * marketing_post_variant does not exist on main or in production; nothing hard-codes a caption limit yet.
--   * ops_knowledge has no record a marketing question about a platform limit can find.
--
-- WHAT THIS BUILDS:
--   marketing_platform_spec          ONE row per platform x surface x attribute, each with its source URL, the date
--                                    it was read, a confidence and a note. A number no official page states is NOT
--                                    typed: value_num stays null and the note says the page is silent. Postiz's own
--                                    limit is used only where the official page is silent or Postiz is stricter,
--                                    and the row says so (source_kind 'postiz').
--   marketing_platform_spec_source   every distinct source URL, the hash last seen and the hash last VERIFIED.
--   fn_marketing_caption_length      one counting rule per platform: X weighted (twitter-text v3: URL = 23,
--                                    emoji = 2, Arabic/Latin = 1), UTF-16 units (Postiz/JavaScript), UTF-8 bytes
--                                    (YouTube description), code points (YouTube title).
--   fn_marketing_variant_violations  reads the table and returns every limit a variant breaks, each citing its row.
--                                    marketing_post_variant's check calls THIS instead of typing numbers.
--   fn_marketing_platform_spec_knowledge_sync   one ops_knowledge record per platform (role marketing), so
--                                    fn_marketing_assist finds and cites the facts.
--   fn_marketing_platform_spec_source_seen / _verified / fn_marketing_platform_spec_freshness
--                                    the monthly re-read (duty platform_spec_freshness in
--                                    supabase/functions/marketing/duties.ts): a changed page is an IT finding
--                                    owned by the marketing seat, and it stays open until someone re-reads the page,
--                                    corrects the rows and marks the source verified. Nothing goes stale silently.
--   fn_table_export_list             + the two tables (copied from the_marketing_seat_writes_articles_and_drafts_
--                                    linkedin_outreach.sql, the current winner).
--
-- Prevented by: the_marketing_seat_knows_every_platforms_limits_probe.sql (read after apply; must print
-- PROBE OK) and scripts/checks/every_marketing_table_is_in_the_daily_export.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_knows_every_platforms_limits.sql --apply --ddl

begin;

-- ── 1. THE SPEC ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_platform_spec (
  platform     text not null check (platform in ('instagram', 'facebook', 'x', 'youtube', 'linkedin', 'tiktok')),
  surface      text not null check (surface in ('feed_image', 'carousel', 'reel', 'feed_post', 'post', 'video', 'short', 'page_post', 'photo')),
  attribute    text not null,
  value_num    numeric,
  value_text   text,
  unit         text,
  -- only for caption/title attributes: how the platform (or Postiz, when stricter) counts
  counted_as   text check (counted_as in ('codepoints', 'utf16_units', 'x_weighted', 'utf8_bytes')),
  source_kind  text not null check (source_kind in ('official', 'postiz')),
  source_url   text not null check (source_url ~ '^https://'),
  read_on      date not null,
  confidence   text not null check (confidence in ('high', 'medium', 'low')),
  note         text,
  primary key (platform, surface, attribute),
  -- a row either states a value or says why it cannot
  constraint marketing_platform_spec_value_or_silence check (value_num is not null or value_text is not null or btrim(coalesce(note, '')) <> '')
);
comment on table public.marketing_platform_spec is
  'The marketing seat''s ONE source of truth for each social platform''s posting limits (founder instruction 869). Every row cites the page it was read from and when. value_num null = the official page is silent; never fill it by guess. fn_marketing_variant_violations enforces the numeric rows; fn_marketing_platform_spec_knowledge_sync teaches them to the seat.';
alter table public.marketing_platform_spec enable row level security;
drop policy if exists marketing_platform_spec_service_role_only on public.marketing_platform_spec;
create policy marketing_platform_spec_service_role_only on public.marketing_platform_spec
  as permissive for all to public using (false) with check (false);
revoke all on public.marketing_platform_spec from anon, authenticated;

-- The rows. Read 23 Sep 2026. Enforced attribute keys (fn_marketing_variant_violations): caption_max, title_max,
-- hashtag_max, mention_max, items_max, min_duration_s, max_duration_s, max_file_bytes, aspect_min, aspect_max
-- (width / height), min_width, min_height, fps_min, fps_max. Every other attribute is text for the seat to read.
with src(k, url) as (values
  ('IG',  'https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media'),
  ('FBR', 'https://developers.facebook.com/docs/video-api/guides/reels-publishing'),
  ('XC',  'https://docs.x.com/fundamentals/counting-characters'),
  ('XU',  'https://docs.x.com/x-api/media/quickstart/media-upload-chunked'),
  ('TTX', 'https://raw.githubusercontent.com/twitter/twitter-text/master/config/v3.json'),
  ('YTV', 'https://developers.google.com/youtube/v3/docs/videos'),
  ('YTS', 'https://support.google.com/youtube/answer/15424877'),
  ('YTH', 'https://support.google.com/youtube/answer/6390658'),
  ('YTT', 'https://support.google.com/youtube/answer/72431'),
  ('YTE', 'https://support.google.com/youtube/answer/1722171'),
  ('LIP', 'https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api'),
  ('LIS', 'https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/post-api-schema'),
  ('LIV', 'https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api'),
  ('PZX', 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/x.provider.ts'),
  ('PZI', 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts'),
  ('PZF', 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts'),
  ('PZL', 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/linkedin.provider.ts'),
  ('TTM', 'https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide'),
  ('TTD', 'https://developers.tiktok.com/doc/content-posting-api-reference-direct-post'),
  ('TTP', 'https://developers.tiktok.com/doc/content-posting-api-reference-photo-post'),
  ('PZT', 'https://raw.githubusercontent.com/gitroomhq/postiz-app/main/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts')
), r(platform, surface, attribute, value_num, value_text, unit, counted_as, source_kind, k, confidence, note) as (values
  -- INSTAGRAM (Graph API content publishing, ig-user/media) — feed image, carousel, Reels
  ('instagram','feed_image','caption_max', 2200, null, 'characters', 'utf16_units', 'official', 'IG', 'high', 'Counted as UTF-16 units, the stricter reading and the one Postiz (JavaScript) applies; an emoji outside the BMP counts 2.'),
  ('instagram','feed_image','hashtag_max', 30, null, 'hashtags', null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','mention_max', 20, null, '@ tags', null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','aspect_min', 0.8, '4:5', 'width/height', null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','aspect_max', 1.91, '1.91:1', 'width/height', null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','max_file_bytes', 8388608, '8 MB', 'bytes', null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','image_format', null, 'JPEG only, sRGB; width 320-1440 px (scaled outside that range)', null, null, 'official', 'IG', 'high', null),
  ('instagram','feed_image','link_in_caption', null, null, null, null, 'official', 'IG', 'low', 'The API page is silent on whether caption links are clickable. Do not promise a clickable link; say "link in bio".'),
  ('instagram','feed_image','first_comment', null, null, null, null, 'official', 'IG', 'low', 'Not read: the comments endpoint page was not checked on 23 Sep 2026. Unknown until read.'),
  ('instagram','carousel','items_max', 10, null, 'items', null, 'official', 'IG', 'high', 'Postiz enforces the same 10.'),
  ('instagram','carousel','caption_max', 2200, null, 'characters', 'utf16_units', 'official', 'IG', 'high', null),
  ('instagram','carousel','hashtag_max', 30, null, 'hashtags', null, 'official', 'IG', 'high', null),
  ('instagram','carousel','mention_max', 20, null, '@ tags', null, 'official', 'IG', 'high', null),
  ('instagram','reel','caption_max', 2200, null, 'characters', 'utf16_units', 'official', 'IG', 'high', null),
  ('instagram','reel','hashtag_max', 30, null, 'hashtags', null, 'official', 'IG', 'high', null),
  ('instagram','reel','mention_max', 20, null, '@ tags', null, 'official', 'IG', 'high', null),
  ('instagram','reel','min_duration_s', 3, null, 'seconds', null, 'official', 'IG', 'high', null),
  ('instagram','reel','max_duration_s', 900, null, 'seconds', null, 'official', 'IG', 'high', '15 minutes through the API. artifact_platform_spec still says 90 s.'),
  ('instagram','reel','max_file_bytes', 314572800, '300 MB', 'bytes', null, 'official', 'IG', 'high', null),
  ('instagram','reel','aspect_min', 0.01, '0.01:1', 'width/height', null, 'official', 'IG', 'high', 'Accepted range 0.01:1 to 10:1; 9:16 is the recommendation.'),
  ('instagram','reel','aspect_max', 10, '10:1', 'width/height', null, 'official', 'IG', 'high', null),
  ('instagram','reel','aspect_recommended', null, '9:16', null, null, 'official', 'IG', 'high', null),
  ('instagram','reel','fps_min', 23, null, 'fps', null, 'official', 'IG', 'high', null),
  ('instagram','reel','fps_max', 60, null, 'fps', null, 'official', 'IG', 'high', null),
  ('instagram','reel','resolution', null, 'at most 1920 px horizontally', null, null, 'official', 'IG', 'high', null),
  ('instagram','reel','codec_container', null, 'MOV or MP4, moov atom at the front, no edit lists; H.264 or HEVC, progressive, closed GOP, 4:2:0; up to 25 Mbps VBR', null, null, 'official', 'IG', 'high', null),
  ('instagram','reel','audio', null, 'AAC, at most 48 kHz, mono or stereo, 128 kbps', null, null, 'official', 'IG', 'high', null),
  ('instagram','reel','cover', null, 'JPEG, at most 8 MB, 9:16 recommended, sRGB', null, null, 'official', 'IG', 'high', null),
  ('instagram','reel','safe_zone', null, null, null, null, 'official', 'IG', 'low', 'Meta publishes no pixel safe zone. Keep text away from the bottom (caption, audio) and right edge (action rail). artifact_platform_spec uses 14% per edge, unsourced.'),
  -- FACEBOOK (Page feed post and Reels)
  ('facebook','feed_post','caption_max', 63206, null, 'characters', 'utf16_units', 'postiz', 'PZF', 'medium', 'Meta''s documentation states no Page post limit; 63,206 is Postiz''s own maxLength and is the limit this company posts through.'),
  ('facebook','feed_post','first_comment', null, null, null, null, 'official', 'FBR', 'low', 'Not read: the Graph comments page was not checked on 23 Sep 2026.'),
  ('facebook','feed_post','link_in_caption', null, 'A URL in the message is clickable and generates a link preview', null, null, 'official', 'FBR', 'low', 'Behaviour known from the product, not stated on the page read; re-verify before relying on it.'),
  ('facebook','reel','caption_max', 63206, null, 'characters', 'utf16_units', 'postiz', 'PZF', 'medium', 'The Reels guide states no description limit; Postiz''s maxLength applies.'),
  ('facebook','reel','min_duration_s', 3, null, 'seconds', null, 'official', 'FBR', 'high', null),
  ('facebook','reel','max_duration_s', 90, null, 'seconds', null, 'official', 'FBR', 'medium', 'The API guide says 90 s; the app may allow longer. The API is how Postiz posts, so 90 binds.'),
  ('facebook','reel','aspect_min', 0.5525, '9:16', 'width/height', null, 'official', 'FBR', 'high', '9:16 only (0.5625); the bounds carry a 0.01 tolerance for encoder rounding.'),
  ('facebook','reel','aspect_max', 0.5725, '9:16', 'width/height', null, 'official', 'FBR', 'high', null),
  ('facebook','reel','min_width', 540, null, 'px', null, 'official', 'FBR', 'high', '1080x1920 recommended, 540x960 minimum.'),
  ('facebook','reel','min_height', 960, null, 'px', null, 'official', 'FBR', 'high', null),
  ('facebook','reel','fps_min', 24, null, 'fps', null, 'official', 'FBR', 'high', null),
  ('facebook','reel','fps_max', 60, null, 'fps', null, 'official', 'FBR', 'high', null),
  ('facebook','reel','codec_container', null, '.mp4 recommended; H.264 or H.265 (VP9 and AV1 also accepted)', null, null, 'official', 'FBR', 'high', null),
  ('facebook','reel','audio', null, 'AAC-LC, 48 kHz, stereo, 128 kbps or more', null, null, 'official', 'FBR', 'high', null),
  ('facebook','reel','max_file_bytes', null, null, null, null, 'official', 'FBR', 'high', 'The Reels guide is silent on file size.'),
  ('facebook','reel','cover', null, 'A custom cover may be set', null, null, 'official', 'FBR', 'high', 'No cover dimensions or size are given.'),
  -- X
  ('x','post','caption_max', 280, null, 'weighted characters', 'x_weighted', 'official', 'XC', 'high', 'Weighted: ANY URL 23 whatever its length; emoji 2; text NFC-normalised first. docs.x.com says only Latin-1 and some punctuation weigh 1 and other Unicode 2; the exact ranges (which include Arabic at 1) are twitter-text config/v3.json, the next row. Premium accounts may post longer but only 280 show before "Show more".'),
  ('x','post','weight_ranges', null, 'Weight 1: U+0000-10FF (Latin, Greek, Cyrillic, Hebrew, ARABIC and more), U+2000-200D, U+2010-201F, U+2032-2037; everything else 2; emoji 2; URLs 23; scale 100, max weighted length 280', null, null, 'official', 'TTX', 'high', 'twitter-text is X''s own open-source counting library; fn_marketing_caption_length implements this table.'),
  ('x','post','caption_max_premium', 4000, null, 'weighted characters', null, 'postiz', 'PZX', 'high', 'Postiz allows 4,000 for a verified (Premium) account. X''s own Premium figure is on help.x.com, which refuses automated reads, so it is not cited here. Not enforced: the company account is not known to be Premium.'),
  ('x','post','link_in_caption', null, 'Every URL is shortened to t.co and counts 23', null, null, 'official', 'XC', 'high', null),
  ('x','video','max_file_bytes', 8589934592, '8 GB (Premium 16 GB)', 'bytes', null, 'official', 'XU', 'high', 'Uploaded in chunks of 5 MB or less.'),
  ('x','video','max_duration_s', 1200, '20 min (Premium 7500 s)', 'seconds', null, 'official', 'XU', 'high', null),
  ('x','video','resolution_fps_aspect', null, null, null, null, 'official', 'XU', 'medium', 'The media-upload page states no resolution, frame rate or aspect ratio.'),
  ('x','post','image_max_bytes', 5242880, '5 MB (GIF 15 MB)', 'bytes', null, 'official', 'XU', 'high', null),
  -- YOUTUBE (regular video and Shorts)
  ('youtube','video','title_max', 100, null, 'characters', 'codepoints', 'official', 'YTV', 'high', 'The characters < and > are invalid in a title.'),
  ('youtube','video','caption_max', 5000, null, 'bytes', 'utf8_bytes', 'official', 'YTV', 'high', 'The description. The API counts BYTES (the help page says characters): an Arabic letter is 2 bytes, an emoji 4, so an all-Arabic description holds about 2,500 letters.'),
  ('youtube','video','tags_max', 500, null, 'characters total', null, 'official', 'YTV', 'high', 'A tag containing a space counts its quotation marks.'),
  ('youtube','video','hashtag_max', 60, null, 'hashtags', null, 'official', 'YTH', 'high', 'More than 60 and YouTube ignores ALL of them. The first 3 show above the title.'),
  ('youtube','video','link_in_caption', null, 'Clickable in the description once the channel is verified or has advanced features', null, null, 'official', 'YTV', 'high', null),
  ('youtube','video','thumbnail', null, '16:9 JPG/PNG, up to 3840x2160, at least 640 wide; 2 MB from a phone, 50 MB from a desktop', null, null, 'official', 'YTT', 'high', 'The old 1280x720 / 2 MB guidance is no longer on the page.'),
  ('youtube','video','codec_container', null, 'MP4, fast start, no edit lists; H.264 High profile, progressive, closed GOP, 2 B-frames, CABAC, 4:2:0, BT.709', null, null, 'official', 'YTE', 'high', null),
  ('youtube','video','audio', null, 'AAC-LC or Opus, 48 kHz, stereo 384 kbps', null, null, 'official', 'YTE', 'high', null),
  ('youtube','video','fps', null, 'Upload at the original frame rate: 24, 25, 30, 48, 50 or 60', null, null, 'official', 'YTE', 'high', null),
  ('youtube','video','bitrate', null, '1080p 8 Mbps, 720p 5 Mbps, 4K 35-45 Mbps (SDR, standard frame rate)', null, null, 'official', 'YTE', 'high', null),
  ('youtube','video','aspect_recommended', null, '16:9', null, null, 'official', 'YTS', 'high', 'A square or vertical video of 3 minutes or less is classed as a Short.'),
  ('youtube','short','title_max', 100, null, 'characters', 'codepoints', 'official', 'YTV', 'high', null),
  ('youtube','short','caption_max', 5000, null, 'bytes', 'utf8_bytes', 'official', 'YTV', 'high', 'Same byte rule as a regular video.'),
  ('youtube','short','hashtag_max', 60, null, 'hashtags', null, 'official', 'YTH', 'high', null),
  ('youtube','short','max_duration_s', 180, null, 'seconds', null, 'official', 'YTS', 'high', '3 minutes. artifact_platform_spec still says 60 s.'),
  ('youtube','short','aspect_max', 1.0, 'square or vertical', 'width/height', null, 'official', 'YTS', 'high', null),
  ('youtube','short','aspect_recommended', null, '9:16', null, null, 'official', 'YTT', 'high', null),
  ('youtube','short','thumbnail', null, '9:16, up to 2160x3840, at least 640 high', null, null, 'official', 'YTT', 'high', null),
  ('youtube','short','safe_zone', null, null, null, null, 'official', 'YTS', 'low', 'YouTube publishes no pixel safe zone for Shorts; keep text off the bottom fifth (title, channel) and the right edge (buttons).'),
  -- LINKEDIN (company page through Postiz's linkedin-page channel)
  ('linkedin','page_post','caption_max', 3000, null, 'characters', 'utf16_units', 'postiz', 'PZL', 'medium', 'LinkedIn''s Posts API states no number, only the error FIELD_LENGTH_TOO_LONG; 3,000 is Postiz''s maxLength.'),
  ('linkedin','page_post','mention_format', null, '@[Exact Name](urn:li:organization:N) — the name must match exactly, case-sensitive; hashtags are plain #tag', null, null, 'official', 'LIP', 'high', 'No count limit for mentions or hashtags is stated.'),
  ('linkedin','page_post','organic_formats', null, 'text, image, video, document, article, multi-image, poll; carousel is sponsored only', null, null, 'official', 'LIP', 'high', null),
  ('linkedin','page_post','first_comment', null, null, null, null, 'official', 'LIS', 'low', 'Not read: the comments API page was not checked on 23 Sep 2026.'),
  ('linkedin','video','min_duration_s', 3, null, 'seconds', null, 'official', 'LIV', 'high', null),
  ('linkedin','video','max_duration_s', 1800, null, 'seconds', null, 'official', 'LIV', 'high', '30 minutes.'),
  ('linkedin','video','max_file_bytes', 524288000, '500 MB', 'bytes', null, 'official', 'LIV', 'medium', 'The page gives 75 KB-500 MB in the spec and a field that allows 5 GB; the stricter 500 MB is enforced.'),
  ('linkedin','video','codec_container', null, 'MP4, uploaded in 4 MB parts; one optional thumbnail; one SRT caption file', null, null, 'official', 'LIV', 'high', null),
  ('linkedin','video','resolution_fps_aspect', null, null, null, null, 'official', 'LIV', 'high', 'The Videos API page states none; it points to the video ADS spec page, which is paid media and out of scope.'),
  -- TIKTOK (Content Posting API; added 23 Sep 2026 when the founder connected TikTok in Postiz)
  ('tiktok','video','caption_max', 2000, null, 'characters', 'utf16_units', 'postiz', 'PZT', 'high', 'TikTok allows 2,200 UTF-16 units in a video title/caption (direct-post reference); Postiz caps at 2,000, which is stricter and binds.'),
  ('tiktok','video','caption_max_tiktok', 2200, null, 'UTF-16 units', null, 'official', 'TTD', 'high', 'TikTok''s own limit; not enforced because Postiz''s 2,000 is stricter.'),
  ('tiktok','video','hashtag_max', null, null, null, null, 'official', 'TTD', 'medium', 'Neither TikTok''s API reference nor Postiz states a hashtag count; hashtags count inside the caption length.'),
  ('tiktok','video','max_duration_s', 600, '10 minutes', 'seconds', null, 'official', 'TTM', 'high', 'API ceiling. Each creator has a lower personal ceiling (creator_info max_video_post_duration_sec, typically 3-10 min by account); query it before posting.'),
  ('tiktok','video','min_duration_s', null, null, null, null, 'official', 'TTM', 'medium', 'The media-transfer page states no minimum duration.'),
  ('tiktok','video','max_file_bytes', 4294967296, '4 GB', 'bytes', null, 'official', 'TTM', 'high', null),
  ('tiktok','video','min_width', 360, null, 'px', null, 'official', 'TTM', 'high', 'Both sides at least 360 px and at most 4096 px.'),
  ('tiktok','video','min_height', 360, null, 'px', null, 'official', 'TTM', 'high', null),
  ('tiktok','video','fps_min', 23, null, 'fps', null, 'official', 'TTM', 'high', null),
  ('tiktok','video','fps_max', 60, null, 'fps', null, 'official', 'TTM', 'high', null),
  ('tiktok','video','codec_container', null, 'MP4 (recommended), WebM or MOV; H.264 (recommended), H.265, VP8 or VP9', null, null, 'official', 'TTM', 'high', null),
  ('tiktok','video','aspect_recommended', null, null, null, null, 'official', 'TTM', 'medium', 'The API pages state no aspect ratio rule; 9:16 is TikTok''s native frame but no official page read on 23 Sep 2026 says so.'),
  ('tiktok','video','privacy_level', null, 'PUBLIC_TO_EVERYONE, MUTUAL_FOLLOW_FRIENDS, FOLLOWER_OF_CREATOR, SELF_ONLY (offer only those creator_info returns); disable_comment / disable_duet / disable_stitch are per-post switches', null, null, 'official', 'TTD', 'high', null),
  ('tiktok','video','cover', null, 'A frame chosen by video_cover_timestamp_ms; no separate cover upload', null, null, 'official', 'TTD', 'high', null),
  ('tiktok','video','safe_zone', null, null, null, null, 'official', 'TTD', 'low', 'TikTok publishes no pixel safe zone in the API docs.'),
  ('tiktok','photo','caption_max', 2000, null, 'characters', 'utf16_units', 'postiz', 'PZT', 'high', 'Photo description: TikTok allows 4,000 UTF-16 units; Postiz caps post text at 2,000, which binds.'),
  ('tiktok','photo','title_max', 90, null, 'UTF-16 units', 'utf16_units', 'official', 'TTP', 'high', null),
  ('tiktok','photo','items_max', 35, null, 'photos', null, 'official', 'TTP', 'high', null),
  ('tiktok','photo','max_file_bytes', 20971520, '20 MB per image', 'bytes', null, 'official', 'TTM', 'high', null),
  ('tiktok','photo','image_format', null, 'WebP or JPEG, at most 1080p (Postiz: at most 1080 px on the shorter side)', null, null, 'official', 'TTM', 'high', null)
)
insert into public.marketing_platform_spec
  (platform, surface, attribute, value_num, value_text, unit, counted_as, source_kind, source_url, read_on, confidence, note)
select r.platform, r.surface, r.attribute, r.value_num, r.value_text, r.unit, r.counted_as, r.source_kind, s.url,
       date '2026-09-23', r.confidence, r.note
  from r join src s on s.k = r.k
on conflict (platform, surface, attribute) do update set
  value_num = excluded.value_num, value_text = excluded.value_text, unit = excluded.unit, counted_as = excluded.counted_as,
  source_kind = excluded.source_kind, source_url = excluded.source_url, read_on = excluded.read_on,
  confidence = excluded.confidence, note = excluded.note;

-- ── 2. THE SOURCES AND THEIR FRESHNESS ───────────────────────────────────────────────────────────
create table if not exists public.marketing_platform_spec_source (
  source_url    text primary key check (source_url ~ '^https://'),
  seen_hash     text,          -- sha-256 of the page's visible text at the last read
  verified_hash text,          -- the hash the rows were last checked against; null until the first read
  checked_at    timestamptz,
  verified_at   timestamptz,
  last_status   int,
  last_error    text
);
comment on table public.marketing_platform_spec_source is
  'Every page marketing_platform_spec cites. The marketing duty platform_spec_freshness re-reads each one monthly; seen_hash <> verified_hash is an open finding for the marketing seat until the rows are re-checked and fn_marketing_platform_spec_source_verified is called.';
alter table public.marketing_platform_spec_source enable row level security;
drop policy if exists marketing_platform_spec_source_service_role_only on public.marketing_platform_spec_source;
create policy marketing_platform_spec_source_service_role_only on public.marketing_platform_spec_source
  as permissive for all to public using (false) with check (false);
revoke all on public.marketing_platform_spec_source from anon, authenticated;

insert into public.marketing_platform_spec_source (source_url)
select distinct source_url from public.marketing_platform_spec
on conflict (source_url) do nothing;

-- ── 3. COUNTING ──────────────────────────────────────────────────────────────────────────────────
-- X: twitter-text v3 (github.com/twitter/twitter-text config/v3.json): code points in 0-4351, 8192-8205,
-- 8208-8223 and 8242-8247 weigh 1 (Latin AND Arabic 0x0600-0x06FF fall inside), everything else 2; any URL
-- weighs 23; an emoji — including a ZWJ family, a skin-tone or flag sequence — weighs 2 as one unit.
-- ponytail: URL detection is scheme/www/common-TLD only; twitter-text's full TLD list is the upgrade if a bare
-- domain on an unusual TLD ever slips through (it would be UNDER-counted by at most 23 - its own length).
create or replace function public.fn_marketing_caption_length(p_text text, p_counted_as text)
returns int language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare v text := coalesce(p_text, ''); n int := 0; cp int; ch text; v_urls int;
begin
  if p_counted_as = 'utf8_bytes' then return octet_length(v); end if;
  if p_counted_as = 'codepoints' then return char_length(v); end if;
  if p_counted_as = 'utf16_units' then
    return char_length(v) + (select count(*) from regexp_split_to_table(v, '') c where ascii(c) > 65535)::int;
  end if;
  if p_counted_as is distinct from 'x_weighted' then
    raise exception 'fn_marketing_caption_length: unknown counting rule %', p_counted_as;
  end if;
  v := normalize(v, NFC);
  -- A URL is ASCII only ([!-~]) and never ends in trailing punctuation, so "(https://quotesdone.ae)" keeps its
  -- brackets outside, an Arabic comma after a link is not swallowed, and Arabic glued to a domain stays text.
  select count(*) into v_urls from regexp_matches(v,
    '(https?://[!-~]*[A-Za-z0-9/#=_&%+~-]|www\.[!-~]*[A-Za-z0-9/#=_&%+~-]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|ae|net|org|io|co|app|me|ly|gl)(/[!-~]*[A-Za-z0-9/#=_&%+~-])?)', 'gi');
  v := regexp_replace(v,
    '(https?://[!-~]*[A-Za-z0-9/#=_&%+~-]|www\.[!-~]*[A-Za-z0-9/#=_&%+~-]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|ae|net|org|io|co|app|me|ly|gl)(/[!-~]*[A-Za-z0-9/#=_&%+~-])?)', '', 'gi');
  -- A keycap (digit, optional VS16, U+20E3) and any character shown as emoji (followed by VS16, e.g. ©️) are
  -- emoji and weigh 2: replace each with one astral stand-in before the folding below.
  v := regexp_replace(v, '.' || chr(65039) || '?' || chr(8419), chr(128512), 'g');
  v := regexp_replace(v, '.' || chr(65039), chr(128512), 'g');
  -- fold each emoji sequence to its first code point: drop text selectors, skin tones, and every ZWJ with the
  -- code point it joins; a flag (two regional indicators) keeps one.
  v := regexp_replace(v, '[' || chr(65038) || chr(127995) || '-' || chr(127999) || ']', '', 'g');
  v := regexp_replace(v, chr(8205) || '.', '', 'g');
  v := regexp_replace(v, '([' || chr(127462) || '-' || chr(127487) || '])[' || chr(127462) || '-' || chr(127487) || ']', '\1', 'g');
  -- regexp_split_to_table('', '') yields one empty row, which the loop would weigh as 1.
  if v = '' then return 23 * v_urls; end if;
  for ch in select c from regexp_split_to_table(v, '') c loop
    cp := ascii(ch);
    n := n + case when cp <= 4351 or cp between 8192 and 8205 or cp between 8208 and 8223 or cp between 8242 and 8247
                  then 1 else 2 end;
  end loop;
  return n + 23 * v_urls;
end $fn$;
revoke execute on function public.fn_marketing_caption_length(text, text) from public, anon, authenticated;

-- ── 4. ENFORCEMENT ───────────────────────────────────────────────────────────────────────────────
-- p_variant: {platform, surface, caption, title, media:{duration_s, bytes, width, height, fps, items}}.
-- Returns [] when the variant is within every stated limit; otherwise one object per broken limit, each naming
-- the row (and its source URL) that refused it. A platform/surface with no row at all is itself a violation, so a
-- typo cannot pass as "no limits". A null measurement is not judged (a text-only post has no duration).
create or replace function public.fn_marketing_variant_violations(p_variant jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_pf text := lower(btrim(coalesce(p_variant->>'platform', '')));
  v_sf text := lower(btrim(coalesce(p_variant->>'surface', '')));
  v_cap text := coalesce(p_variant->>'caption', p_variant->>'text', '');
  v_media jsonb := coalesce(p_variant->'media', '{}'::jsonb);
  v_out jsonb := '[]'::jsonb; s record; v_actual numeric; v_bad boolean;
begin
  if not exists (select 1 from public.marketing_platform_spec where platform = v_pf and surface = v_sf) then
    return jsonb_build_array(jsonb_build_object('attribute', 'platform_surface', 'actual', v_pf || '/' || v_sf,
      'message', 'No spec rows for ' || v_pf || '/' || v_sf || '; nothing may be posted to a surface the seat has no limits for.'));
  end if;
  for s in select * from public.marketing_platform_spec
            where platform = v_pf and surface = v_sf and value_num is not null
              and attribute in ('caption_max', 'title_max', 'hashtag_max', 'mention_max', 'items_max', 'min_duration_s',
                                'max_duration_s', 'max_file_bytes', 'aspect_min', 'aspect_max', 'min_width', 'min_height',
                                'fps_min', 'fps_max') loop
    v_actual := case s.attribute
      when 'caption_max' then public.fn_marketing_caption_length(v_cap, s.counted_as)
      when 'title_max'   then case when p_variant ? 'title' then public.fn_marketing_caption_length(p_variant->>'title', coalesce(s.counted_as, 'codepoints')) end
      when 'hashtag_max' then (select count(*) from regexp_matches(v_cap, '#[^[:space:]#]+', 'g'))
      when 'mention_max' then (select count(*) from regexp_matches(v_cap, '(^|[^[:alnum:]_.])@[[:alnum:]_.]+', 'g'))
      when 'items_max'   then (v_media->>'items')::numeric
      when 'min_duration_s' then (v_media->>'duration_s')::numeric
      when 'max_duration_s' then (v_media->>'duration_s')::numeric
      when 'max_file_bytes' then (v_media->>'bytes')::numeric
      when 'aspect_min' then (v_media->>'width')::numeric / nullif((v_media->>'height')::numeric, 0)
      when 'aspect_max' then (v_media->>'width')::numeric / nullif((v_media->>'height')::numeric, 0)
      when 'min_width'  then (v_media->>'width')::numeric
      when 'min_height' then (v_media->>'height')::numeric
      when 'fps_min' then (v_media->>'fps')::numeric
      when 'fps_max' then (v_media->>'fps')::numeric
    end;
    continue when v_actual is null;
    v_bad := case when s.attribute in ('min_duration_s', 'aspect_min', 'min_width', 'min_height', 'fps_min')
                  then v_actual < s.value_num else v_actual > s.value_num end;
    if v_bad then
      v_out := v_out || jsonb_build_object('attribute', s.attribute, 'limit', s.value_num, 'actual', round(v_actual, 4),
        'counted_as', s.counted_as, 'unit', s.unit, 'source_url', s.source_url, 'read_on', s.read_on,
        'message', format('%s/%s %s: %s against a limit of %s %s (%s)', v_pf, v_sf, s.attribute, round(v_actual, 4),
                          s.value_num, coalesce(s.unit, ''), s.source_url));
    end if;
  end loop;
  -- YouTube: < and > are refused by the API in the title and the description regardless of length.
  if v_pf = 'youtube' and coalesce(p_variant->>'title', '') ~ '[<>]' then
    v_out := v_out || jsonb_build_object('attribute', 'title_characters', 'actual', p_variant->>'title',
      'source_url', 'https://developers.google.com/youtube/v3/docs/videos', 'message', 'A YouTube title may not contain < or >.');
  end if;
  if v_pf = 'youtube' and v_cap ~ '[<>]' then
    v_out := v_out || jsonb_build_object('attribute', 'caption_characters', 'actual', left(v_cap, 200),
      'source_url', 'https://developers.google.com/youtube/v3/docs/videos', 'message', 'A YouTube description may not contain < or >.');
  end if;
  return v_out;
end $fn$;
revoke execute on function public.fn_marketing_variant_violations(jsonb) from public, anon, authenticated;

-- The interface marketing_post_variant (PR #874) calls: text only, one message per broken limit. post_type is
-- #874's vocabulary (reel|short|post|video); it maps to the surface whose CAPTION rows govern the text. The
-- hashtags are appended to the body as the platform will publish them, so they count in the length and the
-- hashtag limit. alt_text and first_comment have no spec rows (first-comment support is unread; see the rows).
create or replace function public.fn_marketing_platform_spec_problems(p_platform text, p_post_type text, p_body text,
  p_hashtags text[], p_title text, p_alt_text text, p_first_comment text)
returns text[] language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_pf text := lower(btrim(coalesce(p_platform, '')));
  v_pt text := lower(btrim(coalesce(p_post_type, '')));
  v_sf text; v_tags text;
begin
  v_sf := case
    when v_pf = 'instagram' then case v_pt when 'reel' then 'reel' else 'feed_image' end
    when v_pf = 'facebook'  then case v_pt when 'reel' then 'reel' else 'feed_post' end
    when v_pf = 'youtube'   then case v_pt when 'short' then 'short' else 'video' end
    when v_pf = 'x'         then 'post'
    when v_pf = 'linkedin'  then 'page_post'
    when v_pf = 'tiktok'    then 'video'
    else v_pt end;
  select string_agg('#' || ltrim(btrim(t), '#'), ' ') into v_tags
    from unnest(coalesce(p_hashtags, '{}'::text[])) t where btrim(t) <> '';
  return coalesce((
    select array_agg(e->>'message')
      from jsonb_array_elements(public.fn_marketing_variant_violations(
             jsonb_build_object('platform', v_pf, 'surface', v_sf,
                                'caption', concat_ws(' ', nullif(btrim(coalesce(p_body, '')), ''), v_tags))
             || case when p_title is not null then jsonb_build_object('title', p_title) else '{}'::jsonb end)) e), '{}'::text[]);
end $fn$;
revoke execute on function public.fn_marketing_platform_spec_problems(text, text, text, text[], text, text, text) from public, anon, authenticated;

-- ── 5. THE SEAT'S KNOWLEDGE ──────────────────────────────────────────────────────────────────────
-- One ops_knowledge record per platform, composed from the rows (so a corrected row is a corrected answer on
-- the next sync), found by fn_marketing_assist's lexical and gte-small routes and cited by record_id.
create or replace function public.fn_marketing_platform_spec_knowledge_sync()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p text; v_body text; v_n int := 0;
begin
  for p in select distinct platform from public.marketing_platform_spec order by 1 loop
    select format(E'Posting limits for %s (organic), read from the official pages on the dates shown. '
                  'A limit marked "silent" is one the platform does not publish: do not state a number for it.\n\n', initcap(p))
        || string_agg(format('- %s / %s: %s%s%s. Source: %s (read %s, confidence %s)%s',
                        surface, replace(attribute, '_', ' '),
                        coalesce(value_text, value_num::text, 'silent'),
                        case when value_num is not null and value_text is not null then ' = ' || value_num::text else '' end,
                        case when counted_as is not null then ' ' || coalesce(unit, '') || ', counted as ' || counted_as
                             when unit is not null and value_num is not null then ' ' || unit else '' end,
                        source_url, read_on, confidence, coalesce('. ' || note, '')),
                      E'\n' order by surface, attribute)
      into v_body
      from public.marketing_platform_spec where platform = p;
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, role_key, layer, module, record_type, title, content, structured_data,
      source_ids, implementation_status, validation_status, authority_tier, risk_level, version, keywords,
      jurisdiction, source_freshness, confidentiality, runtime_eligible, deterministic, supersession_state,
      embedding_status, effective_date)
    values (
      'qd-marketing:platform-spec:' || p, 'role', 'marketing', 'marketing', 'source_reference', 'marketing_platform_spec',
      'md', initcap(p) || ' posting limits: caption length, hashtags, aspect ratio, duration, file size', v_body,
      jsonb_build_object('table', 'marketing_platform_spec', 'platform', p),
      array['marketing_platform_spec'], 'active', 'validated', 'autonomous', 'low', '1',
      array[p, 'caption limit', 'character limit', 'hashtags', 'aspect ratio', 'video length', 'duration', 'file size',
            'resolution', 'thumbnail', 'safe zone', 'reels', 'shorts'],
      'international', 'monthly', 'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      title = excluded.title, content = excluded.content, structured_data = excluded.structured_data,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'records', v_n);
end $fn$;
revoke execute on function public.fn_marketing_platform_spec_knowledge_sync() from public, anon, authenticated;

-- ── 6. FRESHNESS ─────────────────────────────────────────────────────────────────────────────────
-- Due: never read, or read more than 30 days ago. The duty reads at most p_limit per beat (edge CPU cap).
create or replace function public.fn_marketing_platform_spec_sources_due(p_limit int default 3)
returns setof text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select source_url from public.marketing_platform_spec_source
   where checked_at is null or checked_at < now() - interval '30 days'
   order by checked_at nulls first, source_url
   limit greatest(1, least(coalesce(p_limit, 3), 20))
$fn$;
revoke execute on function public.fn_marketing_platform_spec_sources_due(int) from public, anon, authenticated;

-- A read. The FIRST successful read of a source becomes its verified baseline (the rows were written from the
-- page on 23 Sep 2026); every later read only updates seen_hash, so a change stays visible until verified.
create or replace function public.fn_marketing_platform_spec_source_seen(p_url text, p_hash text, p_status int, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.marketing_platform_spec_source;
begin
  update public.marketing_platform_spec_source
     set checked_at = now(), last_status = p_status, last_error = left(p_error, 300),
         seen_hash = coalesce(p_hash, seen_hash),
         verified_hash = coalesce(verified_hash, p_hash),
         verified_at = case when verified_hash is null and p_hash is not null then now() else verified_at end
   where source_url = p_url
  returning * into r;
  if not found then raise exception 'fn_marketing_platform_spec_source_seen: % is not a cited source', p_url; end if;
  return jsonb_build_object('url', r.source_url, 'changed', r.seen_hash is distinct from r.verified_hash, 'status', r.last_status);
end $fn$;
revoke execute on function public.fn_marketing_platform_spec_source_seen(text, text, int, text) from public, anon, authenticated;

-- Someone re-read the page and corrected (or confirmed) the rows: accept what was seen.
create or replace function public.fn_marketing_platform_spec_source_verified(p_url text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_by), '') = '' then raise exception 'fn_marketing_platform_spec_source_verified: say who re-read the page'; end if;
  update public.marketing_platform_spec_source set verified_hash = seen_hash, verified_at = now() where source_url = p_url;
  if not found then raise exception 'fn_marketing_platform_spec_source_verified: % is not a cited source', p_url; end if;
  update public.marketing_platform_spec set read_on = current_date where source_url = p_url;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('marketing', 'ok', now(), now(), jsonb_build_object('action', 'platform_spec_verified', 'url', p_url), 'verified by ' || p_by);
  perform public.fn_marketing_platform_spec_knowledge_sync();
  return jsonb_build_object('ok', true, 'url', p_url);
end $fn$;
revoke execute on function public.fn_marketing_platform_spec_source_verified(text, text) from public, anon, authenticated;

-- The findings: every changed page, and every page unreadable at its last read, is an item owned by marketing.
-- Settled on every run so a verified page closes its own finding.
create or replace function public.fn_marketing_platform_spec_freshness()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', md5(source_url),
           'title', case when seen_hash is distinct from verified_hash
                         then 'platform spec source changed since it was verified: ' || source_url
                         else 'platform spec source could not be read (' || coalesce(last_status::text, 'no status') || '): ' || source_url end,
           'owner_seat', 'marketing', 'subject', 'marketing', 'blast', 'agent_facing',
           'affected', (select count(*) from public.marketing_platform_spec p where p.source_url = s.source_url),
           'evidence', jsonb_build_object('url', source_url, 'checked_at', checked_at, 'verified_at', verified_at,
                                          'status', last_status, 'error', last_error,
                                          'remedy', 'Re-read the page, correct marketing_platform_spec, then call fn_marketing_platform_spec_source_verified(url, who).'))), '[]'::jsonb)
    into v_items
    from public.marketing_platform_spec_source s
   where (seen_hash is distinct from verified_hash)
      -- a timeout or network error leaves status 0; an HTTP error leaves its code. Both are reported.
      or (checked_at is not null and (coalesce(last_status, 0) = 0 or last_status >= 400));
  return public.fn_it_duty_settle('marketing_platform_spec_freshness', v_items);
end $fn$;
revoke execute on function public.fn_marketing_platform_spec_freshness() from public, anon, authenticated;

-- ── 7. THE DAILY TABLE EXPORT: + the two spec tables ─────────────────────────────────────────────
-- Copied from the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql with
-- marketing_platform_spec and marketing_platform_spec_source added under subject 'marketing'.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

-- ── 7b. THE ARTIFACT REVIEWER'S TWO STALE NUMBERS ─────────────────────────────────────────────────
-- artifact_platform_spec (v3_video_platform_specs.sql) is the media gate of the artifact reviewer. Two of its rows
-- contradict the official pages cited above; corrected here so the two stores agree (coordinator, 23 Sep 2026).
update public.artifact_platform_spec set max_duration_s = 180
 where platform = 'youtube' and kind = 'short';
update public.artifact_platform_spec set max_duration_s = 900, max_bytes = 314572800
 where platform = 'instagram' and kind = 'reel';

-- ── 8. TEACH THE SEAT NOW ────────────────────────────────────────────────────────────────────────
select public.fn_marketing_platform_spec_knowledge_sync();

commit;
