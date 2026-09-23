-- PROBE for the_marketing_seat_knows_every_platforms_limits.sql (23 Sep 2026; seat: marketing). Read-only: it
-- writes nothing, so it cannot reach a person. Returns ONE verdict row: 'PROBE OK' or 'PROBE FAILED: <why>'.
--   node scripts/qsql.mjs scripts/sql/the_marketing_seat_knows_every_platforms_limits_probe.sql
-- Fails on the pre-fix estate (the table and routines do not exist) and on any counting regression below.
with v(name, variant, expect_attr) as (values
  -- X, weighted: 257 Latin + space + a 60-character URL = 257 + 1 + 23 = 281 > 280
  ('x url counts 23',        jsonb_build_object('platform','x','surface','post','caption', repeat('a',257) || ' https://quotesdone.ae/' || repeat('p',38)), 'caption_max'),
  ('x url at the limit',     jsonb_build_object('platform','x','surface','post','caption', repeat('a',256) || ' https://quotesdone.ae/' || repeat('p',38)), null),
  ('x bare domain counts 23', jsonb_build_object('platform','x','surface','post','caption', repeat('a',257) || ' quotesdone.ae'), 'caption_max'),
  -- X, Arabic weighs 1: 280 letters pass, 281 fail
  ('x arabic 280',           jsonb_build_object('platform','x','surface','post','caption', repeat('ب',280)), null),
  ('x arabic 281',           jsonb_build_object('platform','x','surface','post','caption', repeat('ب',281)), 'caption_max'),
  -- X, emoji weigh 2 and a ZWJ family is ONE emoji: 140 pass, 141 fail; 140 families pass
  ('x emoji 140',            jsonb_build_object('platform','x','surface','post','caption', repeat('👍',140)), null),
  ('x emoji 141',            jsonb_build_object('platform','x','surface','post','caption', repeat('👍',141)), 'caption_max'),
  ('x zwj family 140',       jsonb_build_object('platform','x','surface','post','caption', repeat('👨‍👩‍👧',140)), null),
  ('x flags 141',            jsonb_build_object('platform','x','surface','post','caption', repeat('🇦🇪',141)), 'caption_max'),
  -- Instagram, UTF-16: 2200 Latin pass; 2199 Latin + one astral emoji = 2201 units fail (2200 code points would pass)
  ('ig 2200',                jsonb_build_object('platform','instagram','surface','reel','caption', repeat('a',2200)), null),
  ('ig emoji is 2 units',    jsonb_build_object('platform','instagram','surface','reel','caption', repeat('a',2199) || '😀'), 'caption_max'),
  ('ig arabic 2201',         jsonb_build_object('platform','instagram','surface','feed_image','caption', repeat('م',2201)), 'caption_max'),
  ('ig 31 hashtags',         jsonb_build_object('platform','instagram','surface','feed_image','caption', (select string_agg('#tag' || g, ' ') from generate_series(1,31) g)), 'hashtag_max'),
  ('ig 21 mentions',         jsonb_build_object('platform','instagram','surface','feed_image','caption', (select string_agg('@user' || g, ' ') from generate_series(1,21) g)), 'mention_max'),
  ('ig email is no mention', jsonb_build_object('platform','instagram','surface','feed_image','caption', 'write to info@quotesdone.ae'), null),
  ('ig reel 901 s',          jsonb_build_object('platform','instagram','surface','reel','caption','x','media', jsonb_build_object('duration_s',901)), 'max_duration_s'),
  ('ig reel 2 s',            jsonb_build_object('platform','instagram','surface','reel','caption','x','media', jsonb_build_object('duration_s',2)), 'min_duration_s'),
  ('ig image 2:1',           jsonb_build_object('platform','instagram','surface','feed_image','caption','x','media', jsonb_build_object('width',2000,'height',1000)), 'aspect_max'),
  ('ig image 1.91:1 passes', jsonb_build_object('platform','instagram','surface','feed_image','caption','x','media', jsonb_build_object('width',1910,'height',1000)), null),
  ('ig carousel 11',         jsonb_build_object('platform','instagram','surface','carousel','caption','x','media', jsonb_build_object('items',11)), 'items_max'),
  -- Facebook Reel: landscape refused, 9:16 accepted
  ('fb reel landscape',      jsonb_build_object('platform','facebook','surface','reel','caption','x','media', jsonb_build_object('width',1920,'height',1080,'duration_s',30,'fps',30)), 'aspect_max'),
  ('fb reel 9:16',           jsonb_build_object('platform','facebook','surface','reel','caption','x','media', jsonb_build_object('width',1080,'height',1920,'duration_s',30,'fps',30)), null),
  -- YouTube: description in BYTES (Arabic 2 each), title 100, Shorts 180 s, 61 hashtags
  ('yt arabic 2500 = 5000 B', jsonb_build_object('platform','youtube','surface','video','caption', repeat('ع',2500), 'title','ok'), null),
  ('yt arabic 2501',         jsonb_build_object('platform','youtube','surface','video','caption', repeat('ع',2501), 'title','ok'), 'caption_max'),
  ('yt title 101',           jsonb_build_object('platform','youtube','surface','video','caption','x','title', repeat('t',101)), 'title_max'),
  ('yt title <',             jsonb_build_object('platform','youtube','surface','video','caption','x','title','a <b>'), 'title_characters'),
  ('yt short 181 s',         jsonb_build_object('platform','youtube','surface','short','caption','x','media', jsonb_build_object('duration_s',181)), 'max_duration_s'),
  ('yt 61 hashtags',         jsonb_build_object('platform','youtube','surface','video','caption', (select string_agg('#t' || g, ' ') from generate_series(1,61) g)), 'hashtag_max'),
  -- LinkedIn: Postiz's 3000
  ('li 3001',                jsonb_build_object('platform','linkedin','surface','page_post','caption', repeat('a',3001)), 'caption_max'),
  ('li video 1801 s',        jsonb_build_object('platform','linkedin','surface','video','media', jsonb_build_object('duration_s',1801)), 'max_duration_s'),
  -- a surface with no rows is refused, not waved through
  ('tiktok is refused',      jsonb_build_object('platform','tiktok','surface','video','caption','x'), 'platform_surface')
), judged as (
  select name, expect_attr, public.fn_marketing_variant_violations(variant) got from v
), bad as (
  select name || case when expect_attr is null then ' expected no violation, got ' || got::text
                      else ' expected ' || expect_attr || ', got ' || got::text end why
    from judged
   where (expect_attr is null and jsonb_array_length(got) > 0)
      or (expect_attr is not null and not exists (select 1 from jsonb_array_elements(got) e where e->>'attribute' = expect_attr))
  union all
  select 'platform ' || p || ' has no caption_max row'
    from unnest(array['instagram','facebook','x','youtube','linkedin']) p
   where not exists (select 1 from public.marketing_platform_spec s where s.platform = p and s.attribute = 'caption_max')
  union all
  select 'row without a verifiable source: ' || platform || '/' || surface || '/' || attribute
    from public.marketing_platform_spec where source_url !~ '^https://' or read_on is null
  union all
  select 'cited source missing from marketing_platform_spec_source: ' || source_url
    from (select distinct source_url from public.marketing_platform_spec) s
   where not exists (select 1 from public.marketing_platform_spec_source x where x.source_url = s.source_url)
  union all
  select 'knowledge record missing for ' || p
    from unnest(array['instagram','facebook','x','youtube','linkedin']) p
   where not exists (select 1 from public.ops_knowledge o where o.record_id = 'qd-marketing:platform-spec:' || p
                        and o.role_key = 'marketing' and o.content like '%Source: https://%')
  union all
  select 'fn_marketing_assist does not cite the Instagram record for a caption-limit question'
   where not (public.fn_marketing_assist('Instagram caption limit hashtags', null)->'cited') ? 'ops_knowledge:qd-marketing:platform-spec:instagram'
)
select case when count(*) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || string_agg(why, ' | ') end as verdict from bad;
