-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711195530   name: dedupe_twitter_card_home
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Remove the single duplicate twitter:card on home (first occurrence only;
-- regexp_replace without the 'g' flag replaces just one). Leaves exactly one.
update public.pages
set html = regexp_replace(html, '<meta name="twitter:card" content="summary_large_image">', '', '')
where slug='home'
  and (select count(*) from regexp_matches(html,'name="twitter:card"','g')) = 2;
