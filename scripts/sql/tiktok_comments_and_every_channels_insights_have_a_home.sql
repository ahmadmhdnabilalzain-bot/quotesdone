-- TIKTOK COMMENTS AND EVERY CHANNEL'S INSIGHTS HAVE A HOME (23 Sep 2026; seat: marketing).
--
-- Founder, 23 Sep 2026: on every social channel the marketing seat reads the insights, reads and answers the comments,
-- and reads and answers the messages, "as if it's me".
-- MEASURED before this file (repository, read-only): social_conversation / social_message admit
-- 'instagram','facebook','youtube','linkedin' (youtube_and_linkedin_connect_with_one_link.sql); marketing_insight_day
-- admits 'facebook','instagram','linkedin','x' (the_marketing_seat_publishes_measures_and_reports_spend.sql).
--
-- BUILDS
--   social_* platform checks        + 'tiktok' (the business account's comments, answered as that account).
--   marketing_insight_day platform  + 'youtube', 'tiktok' ('x' stays: rows may exist; nothing writes it any more).
-- No table, routine or grant is created, so there is nothing to revoke and no new policy.
--
--   node scripts/apply_sql.mjs scripts/sql/tiktok_comments_and_every_channels_insights_have_a_home.sql --apply --ddl
begin;

alter table public.social_conversation drop constraint if exists social_conversation_platform_check;
alter table public.social_conversation add constraint social_conversation_platform_check
  check (platform in ('instagram', 'facebook', 'youtube', 'linkedin', 'tiktok'));
alter table public.social_message drop constraint if exists social_message_platform_check;
alter table public.social_message add constraint social_message_platform_check
  check (platform in ('instagram', 'facebook', 'youtube', 'linkedin', 'tiktok'));

alter table public.marketing_insight_day drop constraint if exists marketing_insight_day_platform_check;
alter table public.marketing_insight_day add constraint marketing_insight_day_platform_check
  check (platform in ('facebook', 'instagram', 'linkedin', 'youtube', 'tiktok', 'x'));

commit;
