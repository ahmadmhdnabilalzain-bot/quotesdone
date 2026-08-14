-- Video platform constraints, for the social and marketing team.
--
-- Duration is a video's own failure mode: Reels and TikTok reject or truncate past their limit,
-- and a 2-second clip is not a post. Both bounds are data, so a channel changing its rules is a
-- row and not a deploy.
alter table artifact_platform_spec
  add column if not exists min_duration_s numeric,
  add column if not exists max_duration_s numeric;

-- Allow the video containers explicitly; a spec with an image-only allowed_mime would fail every
-- video on format before anyone looked at it.
insert into artifact_platform_spec
  (platform, kind, min_width, min_height, aspect_min, aspect_max, max_bytes, allowed_mime,
   safe_zone_pct, min_duration_s, max_duration_s)
values
  ('instagram', 'reel',   1080, 1920, 0.55, 0.58, 100000000, '{video/mp4,video/quicktime}', 0.14, 3, 90),
  ('instagram', 'video',  1080, 1080, 0.79, 1.92, 100000000, '{video/mp4,video/quicktime}', 0.05, 3, 60),
  ('tiktok',    'video',  1080, 1920, 0.55, 0.58, 287000000, '{video/mp4,video/quicktime}', 0.14, 3, 600),
  ('linkedin',  'video',   640,  360, 0.41, 2.40,  200000000, '{video/mp4,video/quicktime}', 0.05, 3, 600),
  ('facebook',  'video',   600,  315, 0.55, 1.92,  100000000, '{video/mp4,video/quicktime}', 0.05, 1, 240),
  ('x',         'video',   320,  180, 0.33, 3.00,  536870912, '{video/mp4,video/quicktime}', 0.05, 1, 140),
  ('youtube',   'short',  1080, 1920, 0.55, 0.58, 256000000, '{video/mp4,video/quicktime}', 0.14, 3, 60),
  ('generic',   'video',   480,  270, 0.20, 5.00, 536870912, '{video/mp4,video/quicktime,video/webm}', 0.05, 1, 1800)
on conflict (platform, kind) do update set
  min_width = excluded.min_width, min_height = excluded.min_height,
  aspect_min = excluded.aspect_min, aspect_max = excluded.aspect_max,
  max_bytes = excluded.max_bytes, allowed_mime = excluded.allowed_mime,
  safe_zone_pct = excluded.safe_zone_pct,
  min_duration_s = excluded.min_duration_s, max_duration_s = excluded.max_duration_s;

-- The safe zone for a vertical format is 14% of each edge, not 5%: the platform's own UI —
-- caption, avatar, action rail — covers the top and bottom of a Reel, a Short and a TikTok.
-- A caption inside the 5% margin is legally "inside the frame" and invisible in the app.
