-- WHY: Founder spec says "An agent periodically upgrades SEO ... and automatically updates the
-- website". The seo_gen edge function existed and was working, but NO cron job referenced it, so it
-- only ever ran when someone invoked it by hand. This schedules it.
--
-- CADENCE: weekly. SEO landing-page copy is slow-moving; regenerating it more often burns AI spend
-- without changing rankings. Sunday 22:40 UTC = Monday 02:40 Asia/Dubai: the lowest-traffic local
-- hours, it is outside the crowded 02:00-08:00 UTC batch window every other job uses, and it lands
-- fresh pages just before the working week starts.
--
-- SCOPE (verified by reading seo_gen's source before scheduling): called with only the secret it
-- selects seo_categories WHERE generated = false, limit 20, and fills intro/includes/faqs. It never
-- overwrites copy that already exists and it deploys nothing itself; it is a no-op once every
-- category is generated. Secret is read from app_secrets at run time, never inlined.
select cron.schedule('seo_gen_weekly', '40 22 * * 0', $$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/seo_gen',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=120000)
$$);
