-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711233637   name: align_home_navy_to_official_brand
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Align live homepage navy backgrounds to the official brand kit
-- (#0C2330 base, #06121B deep). Accents were aligned earlier.
update public.pages
set html = replace(replace(replace(replace(
      html,
      '#05121A','#0C2330'), '#05121a','#0c2330'),
      '#030A0F','#06121B'), '#030a0f','#06121b')
where slug in ('home','home-ar');
