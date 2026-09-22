-- FIVE DEAD SECRETS LEAVE THE STORE (customer_support, 22 Sep 2026, finding INT-07)
--
-- public.app_secrets is one service-role compromise away from being fully readable (the 14 Sep
-- backend audit says so in those words), so a key nothing reads is not neutral clutter — it is
-- blast radius somebody has to keep explaining. One of these five is a plaintext account password.
--
-- EACH DELETION WAS PROVED UNREFERENCED TWICE, 22 Sep 2026, before this file was written:
--   (a) in the repository — grep for the literal key name over every .ts/.tsx/.mjs/.sql/.md/.yml
--       outside node_modules;
--   (b) in the database — `select count(*) from pg_proc p join pg_namespace n ... where
--       n.nspname='public' and p.prosrc like '%<key>%'` (the LOOSE pattern, not the quoted one: a
--       routine that names a key inside a prose sentence would slip past '%''key''%') and the same
--       LIKE over pg_views.definition. Every one of the five returned 0 routines and 0 views.
--
--   meta_sync_enabled        the on/off switch for an edge function called meta_sync, which no
--                            longer exists (supabase/functions holds no such directory and the
--                            Management API lists no such slug). A switch for a deleted thing.
--   meta_campaign_filter     'QuotesDone', read only by that same deleted meta_sync.
--   cred_cron_ads_autopilot  the plaintext half of an internal credential for a cron named
--                            ads_autopilot. pg_cron has been empty since 7 Sep and nothing presents
--                            this credential. The internal_credential row is left alone: this file
--                            removes the readable copy, not the scope model.
--   inbound_secret_rotated_from_20260719
--                            a breadcrumb written during the 19 Jul rotation to record what the
--                            previous inbound secret had been. The rotation completed two months
--                            ago; the breadcrumb is the old secret, still readable.
--   qa_customer_password     a PLAINTEXT PASSWORD for a QA account, sitting in production since
--                            24 Jul. The 14 Sep backend audit named "dropping the QA password from
--                            production secrets" as part of the remedy and it was never done.
--
-- WHAT IS DELIBERATELY KEPT, so the next sweep does not re-litigate it:
--   apify_token         Apify is PAUSED until ~Feb 2027, not retired. Deleting the token would
--                       turn a pause into an outage nobody scheduled.
--   postiz_publish_key  STILL REFERENCED. It is in HELD_KEYS in supabase/functions/marketing/index.ts
--   postiz_integrations and guarded by scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs;
--                       docs/positions/marketing.md and the IT daily note (fn_it_daily_note, via
--                       scripts/sql/the_founder_hears_from_it_once_a_day.sql) both name them as
--                       held for the marketing seat. Held is not dead. postiz_publish_key answering
--                       401 at api.postiz.com is a separate finding about the key's validity, and
--                       deleting a key because it is expired is how you lose the integration rather
--                       than renew it.
--
-- DELETE BY EXACT KEY, NEVER BY PATTERN. 15 Sep: an ilike sweep closed an unfixed Stripe finding by
-- matching its title. `in (...)` on the primary key cannot reach a sixth row.

delete from public.app_secrets
 where key in (
   'meta_sync_enabled',
   'meta_campaign_filter',
   'cred_cron_ads_autopilot',
   'inbound_secret_rotated_from_20260719',
   'qa_customer_password'
 );
