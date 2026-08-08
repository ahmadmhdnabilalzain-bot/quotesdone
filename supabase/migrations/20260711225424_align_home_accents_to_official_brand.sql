-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711225424   name: align_home_accents_to_official_brand
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Align live homepage accent colours (teal, gold) to the official brand kit.
-- Navy backgrounds intentionally left unchanged (bigger visual shift, pending review).
update public.pages
set html = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
      html,
      '#2DD4BF','#14B8A6'), '#2dd4bf','#14b8a6'),
      '45,212,191','20,184,166'),
      '#0D9488','#0B8276'), '#0d9488','#0b8276'),
      '13,148,136','11,130,118'),
      '#E7C579','#E3C065'), '#e7c579','#e3c065'),
      '231,197,121','227,192,101'),
      '#F2C75B','#F6DD8C'),
      '242,199,91','246,221,140')
where slug in ('home','home-ar');
