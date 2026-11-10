-- Seat: marketing. 10 Nov 2026.
-- marketing platform_spec_freshness: the four Postiz provider sources are now hashed on maxLength() alone
-- (supabase/functions/marketing/duties.ts specHashText), not on the whole raw.githubusercontent.com file that changes with
-- nearly every upstream commit (9 Nov 2026: 13 findings open, ~640 re-raises). Their stored hashes were taken over the whole
-- file, so they are cleared here and the next monthly read sets the baseline again (fn_marketing_platform_spec_source_seen
-- takes the first successful read as the verified baseline). The cited values were re-read on 10 Nov 2026 against the live
-- files and still hold: facebook 63206, linkedin 3000, tiktok 2000, x 280 / 4000 premium.
--
--   node scripts/apply_sql.mjs scripts/sql/postiz_spec_sources_are_hashed_on_maxlength_alone.sql --apply
update public.marketing_platform_spec_source
   set seen_hash = null, verified_hash = null, verified_at = null
 where source_url like 'https://raw.githubusercontent.com/gitroomhq/postiz-app/%';
