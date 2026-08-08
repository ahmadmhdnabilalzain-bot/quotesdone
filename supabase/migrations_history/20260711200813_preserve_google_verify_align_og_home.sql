-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711200813   name: preserve_google_verify_align_og_home
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Before the redesign publishes, preserve the Google Search Console verification
-- tag it was missing, and align og/twitter images to the site-standard qd_mark.png.
update public.pages
set html = replace(
      html,
      '<link rel="canonical" href="https://quotesdone.com/">',
      '<link rel="canonical" href="https://quotesdone.com/"><meta name="google-site-verification" content="8Z_NGjZw1CSvxZ1rn_ItJ7bYTjIBWMqcc_R4Q2u-_w4">'
    )
where slug='home'
  and position('google-site-verification' in html) = 0;

-- align og:image + twitter:image (content= only; logo <img src=> are untouched)
update public.pages
set html = replace(
      html,
      'content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2"',
      'content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_mark.png"'
    )
where slug in ('home','home-ar')
  and position('content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2"' in html) > 0;
