-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711195414   name: seo_add_og_image_and_arabic_social_tags
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- English home: had OG text tags but no og:image -> social shares showed no
-- thumbnail. Add og:image + Twitter Card. Guarded so it can't double-insert.
update public.pages
set html = replace(
  html,
  '<meta property="og:site_name" content="QuotesDone">',
  '<meta property="og:site_name" content="QuotesDone">'
  || '<meta property="og:image" content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2">'
  || '<meta property="og:image:alt" content="QuotesDone">'
  || '<meta name="twitter:card" content="summary_large_image">'
  || '<meta name="twitter:title" content="QuotesDone — Anonymous quotes from vetted UAE suppliers">'
  || '<meta name="twitter:description" content="Describe the job once. Compare anonymised quotes from vetted UAE suppliers. Free to post, reveal when ready.">'
  || '<meta name="twitter:image" content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2">'
)
where slug='home'
  and position('<meta property="og:site_name" content="QuotesDone">' in html) > 0
  and position('og:image' in html) = 0;

-- Arabic home (/ar/): had NO canonical and NO Open Graph at all. Add a
-- self-canonical + full OG + Twitter block after its description meta.
update public.pages
set html = replace(
  html,
  '<meta name="description" content="انشر طلبك مرة واحدة واحصل على عروض من موردين إماراتيين موثوقين يتنافسون بعروض مجهولة.">',
  '<meta name="description" content="انشر طلبك مرة واحدة واحصل على عروض من موردين إماراتيين موثوقين يتنافسون بعروض مجهولة.">'
  || '<link rel="canonical" href="https://quotesdone.com/ar/">'
  || '<meta property="og:type" content="website">'
  || '<meta property="og:title" content="QuotesDone — عروض مجهولة من موردين إماراتيين موثوقين">'
  || '<meta property="og:description" content="انشر طلبك مرة واحدة واحصل على عروض من موردين إماراتيين موثوقين يتنافسون بعروض مجهولة.">'
  || '<meta property="og:url" content="https://quotesdone.com/ar/">'
  || '<meta property="og:site_name" content="QuotesDone">'
  || '<meta property="og:locale" content="ar_AE">'
  || '<meta property="og:image" content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2">'
  || '<meta name="twitter:card" content="summary_large_image">'
  || '<meta name="twitter:title" content="QuotesDone — عروض مجهولة من موردين إماراتيين موثوقين">'
  || '<meta name="twitter:description" content="انشر طلبك مرة واحدة واحصل على عروض من موردين إماراتيين موثوقين يتنافسون بعروض مجهولة.">'
  || '<meta name="twitter:image" content="https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/qd_lockup_light.png?v=2">'
)
where slug='home-ar'
  and position('og:title' in html) = 0;
