-- THE COMPANY KNOWS ITS OWN BRAND (6 Sep 2026).
--
-- The founder attached QuotesDone_Brand_Kit.zip (2.9 MB, 24 Jun 2026) and said: "attached brandkit for your
-- reference, feel free to upgrade it (except the logo) and make sure its in company knowledge so you never ask
-- me about it again." Until today the kit lived in Dropbox and, partially, in social-media/brand; the agents
-- carried one canon row ("Brand essentials") that the head budget cut from most employees (measured: the
-- marketing head did not contain #14B8A6, the marketing_design head did). Nothing structured held the colours,
-- the typefaces, the logo rules or where each file is.
--
-- What this file does, all table-driven so it can be corrected without another apply:
--   1. public.company_brand — one row per fact (key, group, value, note, sort): 15 colours + 3 gradients,
--      7 typography rules, 9 logo rules, 5 voice rules, 3 imagery rules, 4 size tables, 4 contrast/WCAG rules,
--      3 source rows. The hexes are the kit's own (WHERE_TO_USE.txt); the WCAG ratios were computed.
--   2. public.brand_assets — extended with bucket, path, folder, bytes, sha256, width, height, usage and a
--      unique filename; every one of the 58 kit files is a row pointing at the public brand bucket, kit/<zip path>
--      (uploaded 6 Sep 2026, 3,394,986 bytes; the 27 older social-media/brand copies are left in place).
--   3. The two transactional email wrappers in public.templates lose their off-brand hexes (Tailwind #0d9488 /
--      #2DD4BF, the old gold #E7B53C) and the white-on-teal CTA (2.5:1) becomes navy-on-teal (6.5:1); the mail
--      logo (app_secrets.email_logo_url, not a secret: a public URL) points at the kit's PWA_192 (same bytes as
--      the icon_192.png it pointed at). The two older canon rows that still carried the retired "alt" hexes
--      (#0d9488, #123047, #f0c869) and "Sora / Inter" as the web faces are corrected to the kit so no employee
--      reads two palettes.
--   4. fn_company_self_knowledge_sync renders qd-company:brand from company_brand, APPENDED LAST in the array
--      (sibling files of the same day add qd-company:decisions and qd-company:refunds ahead of it).
--   5. fn_agent_context (both overloads restated) opens LAYER 1 with a one-line BRAND fact right after the
--      LICENCE & TAX line, so every head carries the primary hex and the typeface.
--   6. kernel_routine_ownership rows for the three routines follow this manifest file.
--
-- Bucket note: the kit lives in the PUBLIC brand bucket on purpose — the same bucket already serves the site's
-- og:image and favicons, and mail clients and link previews need a public URL for the logo. Nothing in a logo
-- is secret. The bucket's MIME allow-list was widened to application/pdf and text/plain for the two vector
-- PDFs and WHERE_TO_USE.txt.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_knows_its_own_brand.sql --apply --ddl
begin;

-- 1. the brand facts ------------------------------------------------------------------------------------
create table if not exists public.company_brand (
  key        text primary key,
  "group"    text not null,
  value      text not null,
  note       text,
  sort       integer not null default 100,
  updated_at timestamptz not null default now()
);
comment on table public.company_brand is 'The brand kit as facts: colours (hex), gradients, typography, logo rules, voice, imagery, sizes, WCAG contrast pairs, sources. Rendered into every agent head by fn_company_self_knowledge_sync (qd-company:brand) and fn_agent_context (the BRAND line). Founder ruling 6 Sep 2026: never ask him about the brand again.';
alter table public.company_brand enable row level security;
revoke all on public.company_brand from public, anon, authenticated;

insert into public.company_brand (key, "group", value, note, sort) values
  ('colour.teal', 'colour', '#14B8A6', 'Teal — PRIMARY. The Q-ring, buttons, active states, links on navy. The kit gradient mid-stop is #16B8A6; #14B8A6 is the canonical token (site CSS --teal). On white it is 2.5:1 — an accent there, never body text.', 10),
  ('colour.teal_light', 'colour', '#6EE7D4', 'Teal light — gradient start; text and links on navy (10.8:1 AAA); the tagline colour.', 11),
  ('colour.teal_deep', 'colour', '#0B8276', 'Teal deep — gradient end; links and small teal text on white (4.7:1 AA).', 12),
  ('colour.gold', 'colour', '#E3C065', 'Gold — SECONDARY. The check mark; "Done" in the on-dark wordmark; highlights and totals on navy (9.2:1). Never text on white (1.8:1).', 13),
  ('colour.gold_light', 'colour', '#F6DD8C', 'Gold light — gradient start.', 14),
  ('colour.gold_deep', 'colour', '#BD8E36', 'Gold deep — gradient end; the only gold usable as large text on white (3.0:1).', 15),
  ('colour.gold_hairline', 'colour', '#CAA14E to #8A6A2F', 'The 3 px hairline frame on the brand square and app icons, 85% opacity.', 16),
  ('colour.navy', 'colour', '#0C2330', 'Navy — BACKGROUND. The ground of every dark surface; "Quotes" in the on-light wordmark; body text on white (16.2:1 AAA).', 17),
  ('colour.navy_hi', 'colour', '#173A4B', 'Navy high — background gradient start (top-left light).', 18),
  ('colour.navy_deep', 'colour', '#06121B', 'Navy deep — background gradient end (bottom-right).', 19),
  ('colour.ink', 'colour', '#0A0A0A', 'Ink — one-colour and print; the Black_Mono lockup; never a screen background.', 20),
  ('colour.paper', 'colour', '#EAF4F2', 'Paper — text on navy (14.4:1 AAA); site token --paper.', 21),
  ('colour.muted', 'colour', '#9DB2B2', 'Muted — secondary text on navy (7.3:1 AAA); site token --muted.', 22),
  ('colour.white', 'colour', '#FFFFFF', 'White — page grounds; the mark_white symbol on navy or photographs.', 23),
  ('colour.surface', 'colour', '#123041', 'Surface — raised cards on navy (site token --surf).', 24),
  ('gradient.teal', 'gradient', 'linear 0,0 to 1,1: #6EE7D4 0% · #16B8A6 55% · #0B8276 100%', 'The Q-ring.', 30),
  ('gradient.gold', 'gradient', 'linear 0,0 to 0.3,1: #F6DD8C 0% · #E3C065 50% · #BD8E36 100%', 'The check mark.', 31),
  ('gradient.navy', 'gradient', 'linear 0.12,0 to 0.88,1: #173A4B 0% · #0C2330 55% · #06121B 100%', 'Every dark ground: covers, avatars, post templates, the OS.', 32),
  ('type.display', 'typography', 'Poppins Bold (700)', 'The wordmark and every headline in brand artwork and social images (marketing_image renders it). "QuotesDone" is one word, camel-cased, never spaced or hyphenated in running text.', 40),
  ('type.caps', 'typography', 'Poppins Medium, UPPERCASE, +0.30 em tracking', 'The tagline "UAE SOURCING MARKETPLACE" and "QUOTES DONE" on the square master.', 41),
  ('type.ui', 'typography', 'Plus Jakarta Sans 400-800 (body), Space Grotesk 300-700 (headings), JetBrains Mono (figures, codes)', 'The website and the OS, self-hosted in public/fonts. Poppins is the brand display face; the product face is Plus Jakarta Sans — do not swap them.', 42),
  ('type.arabic', 'typography', 'Tajawal 400/500/700/800 (Arabic file + Latin file for digits)', 'Arabic locale; RTL mirrors the layout, never the logo.', 43),
  ('type.email', 'typography', 'Arial, Helvetica, sans-serif', 'Every transactional email — web-safe on purpose; no webfont loads in mail.', 44),
  ('type.pdf', 'typography', 'Helvetica / Helvetica-Bold (pdf-lib standard) for reports; Sora + Arabic TTF (brand bucket qd_sora_*.ttf, qd_ar_*.ttf) for quotation PDFs', 'Reports keep standard fonts so their text stays machine-verifiable (scripts/checks/reports_have_a_pdf.test.mjs).', 45),
  ('type.scale', 'typography', '12 / 14 / 16 / 18 / 22 / 28 / 36 / 48 / 64 px; line-height 1.6 body, 1.15 display; PDF 8.5 table / 9.5 body / 10.5 h3 / 14 section / 22 title', 'One ladder shared by web, mail and PDF.', 46),
  ('logo.mark', 'logo', 'A teal ring (the Q) with a gold check (the "done" tick) breaking out of its lower right. SVG viewBox 0 0 800 800: circle cx 400 cy 398 r 92 stroke 50 (teal gradient); path M434 470 L486 524 L582 408 stroke 44, round caps (gold gradient).', 'kit/08_Vector_Source/mark_color.svg (and mark_black / mark_white).', 50),
  ('logo.lockup', 'logo', 'The mark at the left of "QuotesDone" in Poppins Bold: on light grounds "Quotes" navy #0C2330 + "Done" teal #14B8A6; on dark grounds "Quotes" paper/white + "Done" gold #E3C065. Masters 1859x460 px.', 'kit/05_Logo_Lockups (OnLight, OnDark, Black_Mono, on_white, on_navy, mark_only, mark_white).', 51),
  ('logo.square', 'logo', 'The brand square: navy gradient, gold hairline frame, mark centred, "QUOTES DONE" beneath (Quotes paper, Done gold).', 'kit/07_Trademark_and_License/BRAND_SQUARE_color_2000.png; kit/08_Vector_Source/brand_square_bg.svg; every avatar and app icon derives from it.', 52),
  ('logo.master', 'logo', 'kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png', 'The founder-approved artwork. Nothing about the logo changes without him; everything else in the kit may be upgraded.', 53),
  ('logo.clear_space', 'logo', 'At least the height of the Q ring clear on every side.', null, 54),
  ('logo.min_size', 'logo', 'Mark never below 24 px (screen) / 8 mm (print); horizontal lockup never below 120 px wide / 30 mm.', null, 55),
  ('logo.variants', 'logo', 'colour on light (default) · OnDark (white wordmark) · Black_Mono #0A0A0A (print, fax, engraving) · mark_white (photographs, navy)', 'Trademark filings want colour AND black-and-white; trade-licence artwork = BRAND_SQUARE or LOCKUP_color_on_white.', 56),
  ('logo.dont', 'logo', 'Never recolour, stretch, rotate, outline, add drop shadows or glows, place on plain blue or busy photographs, set the wordmark in another face, or separate the check from the ring.', null, 57),
  ('logo.tagline', 'logo', 'UAE SOURCING MARKETPLACE', 'Poppins Medium caps, teal-light #6EE7D4, tracked, centred under the lockup on covers and post templates.', 58),
  ('voice.tone', 'voice', 'Plain, confident, specific. Short sentences, numbers over adjectives, no hype, no exclamation marks, no emoji in business mail. Write like a competent procurement colleague, not a marketer.', null, 60),
  ('voice.wording', 'voice', 'Say "smart engine", never "AI", in customer- and supplier-facing copy (canon rule). Use the platform nouns: RFQ, quote, reveal fee, top-3 comparison, verified supplier, buyer. Money as AED 1,250.00.', null, 61),
  ('voice.promise', 'voice', 'Real competing quotes without the enquiry becoming a lead list: the supplier stays anonymous until the buyer pays to reveal, and a supplier never sees a competitor quote.', null, 62),
  ('voice.bilingual', 'voice', 'English first; Arabic on the /ar locale and on request, in formal Modern Standard Arabic translated by meaning, never word-for-word. "QuotesDone", product names and AED figures stay in Latin script; layouts mirror for RTL, the logo never does.', null, 63),
  ('voice.signoff', 'voice', 'Emails sign with the employee name and title, then "QuotesDone", then the channel address and quotesdone.com; internal mail carries the INTERNAL badge; every external mail carries the unsubscribe line.', null, 64),
  ('imagery.style', 'imagery', 'Navy gradient grounds lit from the top-left, teal and gold as the only accents, generous space around the mark. Real UAE trade contexts and product screens; no stock handshakes, no blue corporate clip art, no gradients outside the three above.', null, 70),
  ('imagery.social', 'imagery', 'In-house cards from marketing_image: 1080x1080, navy gradient, teal-to-gold 14 px rule on the left, mark top-left, Poppins Bold headline, teal-light eyebrow, "QuotesDone" + quotesdone.com footer.', 'Backgrounds: kit/03_Social_Post_Templates.', 71),
  ('imagery.documents', 'imagery', 'Every PDF: navy header band with the OnDark lockup, teal section markers, gold for totals and the cover rule, Helvetica body, footer "Confidential — QuotesDone" + the trade-licence line + page x of y. Email: white card on #F6F7F9, navy "Quotes" + teal "Done" wordmark, teal-deep links.', null, 72),
  ('size.avatars', 'sizes', 'Same square for every platform — LinkedIn 400 · Instagram 320 · Facebook 500 · X 400 · YouTube 800 · WhatsApp 640 · TikTok 200 · Threads 400 · Pinterest 280 · Google Business 250; master 1000x1000', 'kit/01_Social_Avatars', 80),
  ('size.covers', 'sizes', 'LinkedIn personal 1584x396 · LinkedIn company 1128x191 · Facebook 820x312 · X 1500x500 · YouTube 2560x1440 (safe area 1546x423)', 'kit/02_Social_Covers', 81),
  ('size.posts', 'sizes', 'Instagram square 1080x1080 · portrait 1080x1350 · Story/Reel/TikTok 1080x1920 · landscape 1200x675 · link preview (OG) 1200x630', 'kit/03_Social_Post_Templates', 82),
  ('size.icons', 'sizes', 'favicon 16/32/48/64 + favicon.ico · Apple touch 180 · PWA 192 and maskable 512 · store listing 1024 · business card 1125x675 at 300 DPI with bleed', 'kit/04_Web_App_Icons, kit/06_Print_Business_Card', 83),
  ('contrast.on_white', 'contrast', 'navy #0C2330 16.2:1 AAA · ink #0A0A0A 19.8:1 AAA · teal-deep #0B8276 4.7:1 AA · gold-deep #BD8E36 3.0:1 large text only · teal #14B8A6 2.5:1 and gold #E3C065 1.8:1 decorative only', 'WCAG 2.1 ratios, measured 6 Sep 2026.', 90),
  ('contrast.on_navy', 'contrast', 'paper #EAF4F2 14.4:1 AAA · white 16.2:1 AAA · teal-light #6EE7D4 10.8:1 AAA · gold #E3C065 9.2:1 AAA · muted #9DB2B2 7.3:1 AAA · teal #14B8A6 6.5:1 AA · faint #7C97A3 5.2:1 AA', null, 91),
  ('contrast.buttons', 'contrast', 'Primary: teal #14B8A6 fill + navy #0C2330 label (6.5:1); hover teal-light fill; focus 2 px teal-light ring; disabled 40% opacity. Never white text on teal (2.5:1). Secondary: transparent, 1 px teal-light hairline, paper label. Destructive: gold-deep fill + navy label.', null, 92),
  ('contrast.links', 'contrast', 'On white: teal-deep #0B8276, underline on hover. On navy: teal-light #6EE7D4. Never brand teal #14B8A6 as link text on white.', null, 93),
  ('source.kit', 'source', 'Dropbox > projects > quotes done > QuotesDone_Brand_Kit.zip (2.9 MB, 24 Jun 2026)', 'Attached by the founder on 6 Sep 2026: "feel free to upgrade it (except the logo) and make sure it is in company knowledge so you never ask me about it again."', 100),
  ('source.files', 'source', 'Public bucket brand, folder kit/ — 58 files (50 PNG, 1 ICO, 4 SVG, 2 PDF, WHERE_TO_USE.txt)', 'public.brand_assets indexes every file with kind, platform, path, size, sha256 and usage. Older copies of 27 of them remain in social-media/brand.', 101),
  ('source.guide', 'source', 'docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel (board_reports report_type = brand)', null, 102)
on conflict (key) do update set "group" = excluded."group", value = excluded.value, note = excluded.note, sort = excluded.sort, updated_at = now();

-- 2. the kit files --------------------------------------------------------------------------------------
alter table public.brand_assets
  add column if not exists bucket text,
  add column if not exists path   text,
  add column if not exists folder text,
  add column if not exists bytes  integer,
  add column if not exists sha256 text,
  add column if not exists width  integer,
  add column if not exists height integer,
  add column if not exists usage  text;
create unique index if not exists brand_assets_filename_key on public.brand_assets (filename);
comment on table public.brand_assets is 'Every file of the founder''s brand kit (public bucket brand, kit/<zip path>): kind, platform, storage path, size, sha256, pixel size and where to use it. 27 older copies also sit in social-media/brand.';

insert into public.brand_assets (kind, platform, filename, url, bucket, path, folder, bytes, sha256, width, height, usage) values
  ('avatar', 'Facebook', 'avatar_Facebook_500x500.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_Facebook_500x500.png', 'brand', 'kit/01_Social_Avatars/avatar_Facebook_500x500.png', '01_Social_Avatars', 65630, '28b7f09663af4148f7681bf1b1342294c42e190ee3d7b4dc1b45b25ccde333f8', 500, 500, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'GoogleBusiness', 'avatar_GoogleBusiness_250x250.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_GoogleBusiness_250x250.png', 'brand', 'kit/01_Social_Avatars/avatar_GoogleBusiness_250x250.png', '01_Social_Avatars', 28228, '59928f8fc7024ace950ce7d8aad8e028b4dd700cac4effe8f48a3677c0261aca', 250, 250, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'Instagram', 'avatar_Instagram_320x320.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_Instagram_320x320.png', 'brand', 'kit/01_Social_Avatars/avatar_Instagram_320x320.png', '01_Social_Avatars', 37839, '2604be5b8a2a91f111cc7b5d9f51b984b42dc55923d616cd9b8386558fc73de1', 320, 320, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'LinkedIn', 'avatar_LinkedIn_400x400.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_LinkedIn_400x400.png', 'brand', 'kit/01_Social_Avatars/avatar_LinkedIn_400x400.png', '01_Social_Avatars', 49255, '6b2391cbfba929f567619f63eb3b4aa81db7b97fa8ed880fd725f9a873688650', 400, 400, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'Pinterest', 'avatar_Pinterest_280x280.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_Pinterest_280x280.png', 'brand', 'kit/01_Social_Avatars/avatar_Pinterest_280x280.png', '01_Social_Avatars', 32532, '7029024cc4217ad55bfaa0eef43eb0731d4dce45b17a1d107ab7eccf25749560', 280, 280, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'Threads', 'avatar_Threads_400x400.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_Threads_400x400.png', 'brand', 'kit/01_Social_Avatars/avatar_Threads_400x400.png', '01_Social_Avatars', 49255, '6b2391cbfba929f567619f63eb3b4aa81db7b97fa8ed880fd725f9a873688650', 400, 400, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'TikTok', 'avatar_TikTok_200x200.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_TikTok_200x200.png', 'brand', 'kit/01_Social_Avatars/avatar_TikTok_200x200.png', '01_Social_Avatars', 20962, '8db3accb0a4b5de0356afad9abef5937fe6ae2debb262306f05dd2a1e224ec62', 200, 200, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'Universal', 'avatar_Universal_Master_1000x1000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_Universal_Master_1000x1000.png', 'brand', 'kit/01_Social_Avatars/avatar_Universal_Master_1000x1000.png', '01_Social_Avatars', 164354, '11050f847feb1a58a0976fa7b781393b2af5c48a35bc25c99ffc3f6981ac0041', 1000, 1000, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'WhatsApp', 'avatar_WhatsApp_640x640.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_WhatsApp_640x640.png', 'brand', 'kit/01_Social_Avatars/avatar_WhatsApp_640x640.png', '01_Social_Avatars', 91081, '57ac07bc9d920802d7e33c1f623d54bc884c1d1334bca9d6825e082561222745', 640, 640, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'X_Twitter', 'avatar_X_Twitter_400x400.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_X_Twitter_400x400.png', 'brand', 'kit/01_Social_Avatars/avatar_X_Twitter_400x400.png', '01_Social_Avatars', 49255, '6b2391cbfba929f567619f63eb3b4aa81db7b97fa8ed880fd725f9a873688650', 400, 400, 'profile picture for the named platform; Universal_Master if unsure'),
  ('avatar', 'YouTube', 'avatar_YouTube_800x800.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/01_Social_Avatars/avatar_YouTube_800x800.png', 'brand', 'kit/01_Social_Avatars/avatar_YouTube_800x800.png', '01_Social_Avatars', 122380, '7d395b6f0b6f3eddce66587f43b81b4b9a85d58d3abee363add05d8cda28b574', 800, 800, 'profile picture for the named platform; Universal_Master if unsure'),
  ('cover', 'Facebook', 'Facebook_Cover_820x312.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/02_Social_Covers/Facebook_Cover_820x312.png', 'brand', 'kit/02_Social_Covers/Facebook_Cover_820x312.png', '02_Social_Covers', 36400, '6baf7dd679047d4f0f952a174b80192e91a6b49d94135547cc42ca208e8813a6', 820, 312, 'header / banner image, pre-sized for the named platform'),
  ('cover', 'LinkedIn_Company', 'LinkedIn_Company_Cover_1128x191.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/02_Social_Covers/LinkedIn_Company_Cover_1128x191.png', 'brand', 'kit/02_Social_Covers/LinkedIn_Company_Cover_1128x191.png', '02_Social_Covers', 26322, '0b5a430b51b0138820f86cd7cd688a0d3e383ca08fd65ca0818660910b32f56d', 1128, 191, 'header / banner image, pre-sized for the named platform'),
  ('cover', 'LinkedIn_Personal', 'LinkedIn_Personal_Cover_1584x396.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/02_Social_Covers/LinkedIn_Personal_Cover_1584x396.png', 'brand', 'kit/02_Social_Covers/LinkedIn_Personal_Cover_1584x396.png', '02_Social_Covers', 58969, '06e4cbff0c9ec2f50e7bc5ac1f1edc3a55829e865748b7cb4a0717f33dca9749', 1584, 396, 'header / banner image, pre-sized for the named platform'),
  ('cover', 'X', 'X_Twitter_Header_1500x500.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/02_Social_Covers/X_Twitter_Header_1500x500.png', 'brand', 'kit/02_Social_Covers/X_Twitter_Header_1500x500.png', '02_Social_Covers', 65265, 'eace99402a94316002752dc44b5305a89f9dc646fb6f0b29e46df9f8b494aabb', 1500, 500, 'header / banner image, pre-sized for the named platform'),
  ('cover', 'YouTube', 'YouTube_Channel_Art_2560x1440_safe1546x423.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/02_Social_Covers/YouTube_Channel_Art_2560x1440_safe1546x423.png', 'brand', 'kit/02_Social_Covers/YouTube_Channel_Art_2560x1440_safe1546x423.png', '02_Social_Covers', 181404, 'e9fab43f97915eb125b2ff1ca18352bbc6298ba1fde87bb95ae2e8ddf22fdfbd', 2560, 1440, 'header / banner image, pre-sized for the named platform'),
  ('template', 'Instagram', 'Instagram_Portrait_1080x1350.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/03_Social_Post_Templates/Instagram_Portrait_1080x1350.png', 'brand', 'kit/03_Social_Post_Templates/Instagram_Portrait_1080x1350.png', '03_Social_Post_Templates', 95966, 'a6892d57e42190b2158d338c4bea775922fa3bde997d5e0718dc4234180706af', 1080, 1350, 'ready branded background for a social post; add the headline on top'),
  ('template', 'Instagram', 'Instagram_Square_Post_1080x1080.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/03_Social_Post_Templates/Instagram_Square_Post_1080x1080.png', 'brand', 'kit/03_Social_Post_Templates/Instagram_Square_Post_1080x1080.png', '03_Social_Post_Templates', 100411, '930efa5f9a5af85cf6f122b6d48c241c496936cbf452abf8b93d6710ece413d7', 1080, 1080, 'ready branded background for a social post; add the headline on top'),
  ('template', '', 'Landscape_Post_1200x675.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/03_Social_Post_Templates/Landscape_Post_1200x675.png', 'brand', 'kit/03_Social_Post_Templates/Landscape_Post_1200x675.png', '03_Social_Post_Templates', 77491, '4e2e9659f537547af58cd081d13f62ce773658db297205a419cddf260f32d3a0', 1200, 675, 'ready branded background for a social post; add the headline on top'),
  ('template', 'TikTok', 'Story_Reel_TikTok_1080x1920.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/03_Social_Post_Templates/Story_Reel_TikTok_1080x1920.png', 'brand', 'kit/03_Social_Post_Templates/Story_Reel_TikTok_1080x1920.png', '03_Social_Post_Templates', 142545, '7c5172c654d18f3fbbb3c1d12027ac58f1b0fb9b1331c2cfc9d6e208be01a39c', 1080, 1920, 'ready branded background for a social post; add the headline on top'),
  ('icon', '', 'AppleTouch_180_180x180.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/AppleTouch_180_180x180.png', 'brand', 'kit/04_Web_App_Icons/AppleTouch_180_180x180.png', '04_Web_App_Icons', 12592, '37eb547fbeb1a74777dfb9fde38c8211e242e749b94b8ce053f32aa73c3c636c', 180, 180, 'iPhone home-screen icon'),
  ('icon', '', 'AppStore_1024_1024x1024.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/AppStore_1024_1024x1024.png', 'brand', 'kit/04_Web_App_Icons/AppStore_1024_1024x1024.png', '04_Web_App_Icons', 136860, '8dc82020f6db1f09a73b3944f8724e3556e619f6bcb29f83478a6022867dbfb9', 1024, 1024, 'App Store / Play Store listing icon'),
  ('icon', '', 'favicon.ico', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/favicon.ico', 'brand', 'kit/04_Web_App_Icons/favicon.ico', '04_Web_App_Icons', 7847, 'c3aedbb6296dd9ec678dc0aa3bd59e5ffc98ccd051a1b331f64625dff4f7ed68', null, null, 'browser tab favicon'),
  ('icon', '', 'favicon_16_16x16.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/favicon_16_16x16.png', 'brand', 'kit/04_Web_App_Icons/favicon_16_16x16.png', '04_Web_App_Icons', 544, '1e6205e98294ef79a9ef8efcf6afdccc120ab41b44efc4358a8343c7ccf5c25c', 16, 16, 'browser tab favicon'),
  ('icon', '', 'favicon_32_32x32.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/favicon_32_32x32.png', 'brand', 'kit/04_Web_App_Icons/favicon_32_32x32.png', '04_Web_App_Icons', 1252, '52f03e11b6b22cf53f90758c76c4d3dcf30bf608523d039b8b3f222248d3a72d', 32, 32, 'browser tab favicon'),
  ('icon', '', 'favicon_48_48x48.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/favicon_48_48x48.png', 'brand', 'kit/04_Web_App_Icons/favicon_48_48x48.png', '04_Web_App_Icons', 2033, '9c64ef85b698a55a882d7ae6018c7e0e1b83e49073119b5c4de4ddd26291d3cf', 48, 48, 'browser tab favicon'),
  ('icon', '', 'favicon_64_64x64.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/favicon_64_64x64.png', 'brand', 'kit/04_Web_App_Icons/favicon_64_64x64.png', '04_Web_App_Icons', 3164, '76330117935ba2a0da6214272c410d667df2ee80f25ac1aa4646fe765b685354', 64, 64, 'browser tab favicon'),
  ('icon', '', 'icon_256_256x256.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/icon_256_256x256.png', 'brand', 'kit/04_Web_App_Icons/icon_256_256x256.png', '04_Web_App_Icons', 20651, '1b974bb5fb378cdea1f30a8e64c29c86fe676339dc91c5fb83ccb3528be221f3', 256, 256, 'mark with no background, for app icons'),
  ('icon', '', 'mark_transparent_1024.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/mark_transparent_1024.png', 'brand', 'kit/04_Web_App_Icons/mark_transparent_1024.png', '04_Web_App_Icons', 64223, '2ff5f93a85c20c0bdb2c09ca9857b413adf3afa4b2eb165274e1a45de50581ac', 1024, 1024, 'mark with no background, for app icons'),
  ('icon', '', 'PWA_192_192x192.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/PWA_192_192x192.png', 'brand', 'kit/04_Web_App_Icons/PWA_192_192x192.png', '04_Web_App_Icons', 13729, 'ebead5766b3a3a8dd2d6c5fad2804858ba13276516545cd2f31cd882fa7a489e', 192, 192, 'installable web app icon'),
  ('icon', '', 'PWA_maskable_512_512x512.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/PWA_maskable_512_512x512.png', 'brand', 'kit/04_Web_App_Icons/PWA_maskable_512_512x512.png', '04_Web_App_Icons', 51233, '4a4cd3dfa226d2dc1bc9b526aba37d3e3ff2621abbe0b7127632297f4c9af6bd', 512, 512, 'installable web app icon'),
  ('logo', '', 'horizontal_Black_Mono_transparent.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_Black_Mono_transparent.png', 'brand', 'kit/05_Logo_Lockups/horizontal_Black_Mono_transparent.png', '05_Logo_Lockups', 33537, '5d83674b958f762f60f461408343a28e5d2455e12af6522b52be87fea928fe48', 1859, 460, 'one-colour lockup for print / fax / engraving'),
  ('logo', '', 'horizontal_OnDark_transparent.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnDark_transparent.png', 'brand', 'kit/05_Logo_Lockups/horizontal_OnDark_transparent.png', '05_Logo_Lockups', 47466, 'afc1d40d430dd39e97ca0e05c0b9064059cb9bd388fe06bfa5de084fd3f9127b', 1859, 460, 'horizontal lockup for dark backgrounds (white wordmark)'),
  ('logo', '', 'horizontal_OnLight_transparent.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnLight_transparent.png', 'brand', 'kit/05_Logo_Lockups/horizontal_OnLight_transparent.png', '05_Logo_Lockups', 47450, '0c2c28ebbcf3d9e3a730deaf35e11900f59365b6c5cd6e95b5ace2e47cfbf3ce', 1859, 460, 'horizontal lockup for light backgrounds (navy wordmark)'),
  ('logo', '', 'horizontal_on_navy.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_on_navy.png', 'brand', 'kit/05_Logo_Lockups/horizontal_on_navy.png', '05_Logo_Lockups', 50218, 'd6504986b9b1c896c33a85cfdca44f31b61ab38ca1dade8fab41ba1453fbe627', 1859, 460, 'lockup on a ready navy background'),
  ('logo', '', 'horizontal_on_white.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_on_white.png', 'brand', 'kit/05_Logo_Lockups/horizontal_on_white.png', '05_Logo_Lockups', 49769, '3f25cffc2725d890a089c51c4cb071f5981d2086f1a5c95ae84463d22e9f302f', 1859, 460, 'lockup on a ready white background'),
  ('logo', '', 'mark_only_transparent_1200.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/mark_only_transparent_1200.png', 'brand', 'kit/05_Logo_Lockups/mark_only_transparent_1200.png', '05_Logo_Lockups', 73944, '29851f6b26627371164dea275b7ea71572e0fec7cdf1488c5512c97e607cccf1', 1200, 1200, 'symbol on its own, colour — for light backgrounds'),
  ('logo', '', 'mark_white_transparent_1200.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/mark_white_transparent_1200.png', 'brand', 'kit/05_Logo_Lockups/mark_white_transparent_1200.png', '05_Logo_Lockups', 29300, '52596825b898b29f08e4897c9f5d848480fc93fddf1aff439f1c40f26638595a', 1200, 1200, 'symbol on its own, white — for navy or photo backgrounds'),
  ('print', '', 'business_card_BACK_1125x675_300dpi_bleed.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/06_Print_Business_Card/business_card_BACK_1125x675_300dpi_bleed.png', 'brand', 'kit/06_Print_Business_Card/business_card_BACK_1125x675_300dpi_bleed.png', '06_Print_Business_Card', 24653, '4bfd496d0ffb9b5e1c8b163726709613b0e06a340f5fe01de708c8889da52cd9', 1125, 675, '300 DPI business card with bleed; edit the [ ] fields'),
  ('print', '', 'business_card_FRONT_1125x675_300dpi_bleed.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/06_Print_Business_Card/business_card_FRONT_1125x675_300dpi_bleed.png', 'brand', 'kit/06_Print_Business_Card/business_card_FRONT_1125x675_300dpi_bleed.png', '06_Print_Business_Card', 79047, '10ca14ef283dc59f68340b76f47195281aeba3462fd371927e1e0a7ad16fcf10', 1125, 675, '300 DPI business card with bleed; edit the [ ] fields'),
  ('print', '', 'logo_horizontal_on_white_print.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/06_Print_Business_Card/logo_horizontal_on_white_print.png', 'brand', 'kit/06_Print_Business_Card/logo_horizontal_on_white_print.png', '06_Print_Business_Card', 49769, '3f25cffc2725d890a089c51c4cb071f5981d2086f1a5c95ae84463d22e9f302f', 1859, 460, 'lockup for letterhead, invoices and printed documents'),
  ('print', '', 'logo_horizontal_transparent_print.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/06_Print_Business_Card/logo_horizontal_transparent_print.png', 'brand', 'kit/06_Print_Business_Card/logo_horizontal_transparent_print.png', '06_Print_Business_Card', 47450, '0c2c28ebbcf3d9e3a730deaf35e11900f59365b6c5cd6e95b5ace2e47cfbf3ce', 1859, 460, 'lockup for letterhead, invoices and printed documents'),
  ('trademark', '', 'BRAND_SQUARE_color_2000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/BRAND_SQUARE_color_2000.png', 'brand', 'kit/07_Trademark_and_License/BRAND_SQUARE_color_2000.png', '07_Trademark_and_License', 407862, '1b9eba3aef363142fcd4e493679f5cf7884b573936635154c74bea73403559d2', 2000, 2000, 'trade-licence / IP-filing artwork (square)'),
  ('trademark', '', 'LOCKUP_black_on_white.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/LOCKUP_black_on_white.png', 'brand', 'kit/07_Trademark_and_License/LOCKUP_black_on_white.png', '07_Trademark_and_License', 37285, '121ff22324114e1b1f67ac5aa0a5963bf98172b1096487876a64b4caf841d4b0', 1859, 460, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'LOCKUP_color_on_white.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/LOCKUP_color_on_white.png', 'brand', 'kit/07_Trademark_and_License/LOCKUP_color_on_white.png', '07_Trademark_and_License', 49769, '3f25cffc2725d890a089c51c4cb071f5981d2086f1a5c95ae84463d22e9f302f', 1859, 460, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'LOCKUP_color_transparent.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/LOCKUP_color_transparent.png', 'brand', 'kit/07_Trademark_and_License/LOCKUP_color_transparent.png', '07_Trademark_and_License', 47450, '0c2c28ebbcf3d9e3a730deaf35e11900f59365b6c5cd6e95b5ace2e47cfbf3ce', 1859, 460, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'MARK_black_on_white_2000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/MARK_black_on_white_2000.png', 'brand', 'kit/07_Trademark_and_License/MARK_black_on_white_2000.png', '07_Trademark_and_License', 76121, '985f688b134278d53908a873933576ac2fbb775314e5ba61e3cace7e77e78a7c', 2000, 2000, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'MARK_black_transparent_2000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/MARK_black_transparent_2000.png', 'brand', 'kit/07_Trademark_and_License/MARK_black_transparent_2000.png', '07_Trademark_and_License', 70003, 'b22f116d9f3afb80e89c67c284868b37617959ca1c5269ed8a9b7dfd597f4d01', 2000, 2000, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'MARK_color_on_white_2000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/MARK_color_on_white_2000.png', 'brand', 'kit/07_Trademark_and_License/MARK_color_on_white_2000.png', '07_Trademark_and_License', 114721, '78c7b2240b371973b577b2efd94c664a03dcb76f953e385b7d08eab36dd7e1ab', 2000, 2000, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'MARK_color_transparent_2000.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/MARK_color_transparent_2000.png', 'brand', 'kit/07_Trademark_and_License/MARK_color_transparent_2000.png', '07_Trademark_and_License', 157792, 'a8c407906c494f609d667c17ef8817558b4df26125a9b65cfff9de52e739e20c', 2000, 2000, 'IP-filing artwork; filings usually want colour and black-and-white'),
  ('trademark', '', 'ORIGINAL_approved_master_800.png', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png', 'brand', 'kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png', '07_Trademark_and_License', 81044, '9ebef16ef41fb184e887a199d7f9b6db60757c37a1fd3a88cca389b6b093d032', 800, 800, 'the founder-approved master; the reference every other file derives from'),
  ('vector', '', 'brand_square_bg.svg', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/brand_square_bg.svg', 'brand', 'kit/08_Vector_Source/brand_square_bg.svg', '08_Vector_Source', 983, '8c300df0fe309e0b54768e5f6f779eea41764a62c6fe606aea3db819327fa73c', null, null, 'infinitely scalable source; send to printers and the IP agent first'),
  ('vector', '', 'mark_black.pdf', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/mark_black.pdf', 'brand', 'kit/08_Vector_Source/mark_black.pdf', '08_Vector_Source', 1062, 'cc787d362cd66cb77746a9d9886b598a395d662d16b1ba5a043c8ff555e9dff0', null, null, 'vector PDF for printers and IP filing'),
  ('vector', '', 'mark_black.svg', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/mark_black.svg', 'brand', 'kit/08_Vector_Source/mark_black.svg', '08_Vector_Source', 1024, 'e1557dad2cb3c2d23adccb920343d2dac921a0e1b8a67cb71cb6f4941251ed91', null, null, 'infinitely scalable source; send to printers and the IP agent first'),
  ('vector', '', 'mark_color.pdf', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/mark_color.pdf', 'brand', 'kit/08_Vector_Source/mark_color.pdf', '08_Vector_Source', 2669, 'a635b0a4f3b9de96ec45c8f35762d573f763721e976849a4db5f23515db1b9e1', null, null, 'vector PDF for printers and IP filing'),
  ('vector', '', 'mark_color.svg', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/mark_color.svg', 'brand', 'kit/08_Vector_Source/mark_color.svg', '08_Vector_Source', 1030, 'e90e8684d3092e483d44ea01ef240e2b57c12ee7a6f2092baf1018c0c136a80e', null, null, 'infinitely scalable source; send to printers and the IP agent first'),
  ('vector', '', 'mark_white.svg', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/08_Vector_Source/mark_white.svg', 'brand', 'kit/08_Vector_Source/mark_white.svg', '08_Vector_Source', 1024, 'a0c6a43e8f853ef31c3866bd935076f9bfcbbd2c4df1e4f44f6dcf731db22f73', null, null, 'infinitely scalable source; send to printers and the IP agent first'),
  ('doc', '', 'WHERE_TO_USE.txt', 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/WHERE_TO_USE.txt', 'brand', 'kit/WHERE_TO_USE.txt', '', 2872, '9fb3a1dd4346219430d507901ded78c7e3ae307a4ee1bfdaedf55386828ab324', null, null, 'the kit index: which file to use where')
on conflict (filename) do update set
  kind = excluded.kind, platform = excluded.platform, url = excluded.url, bucket = excluded.bucket, path = excluded.path,
  folder = excluded.folder, bytes = excluded.bytes, sha256 = excluded.sha256, width = excluded.width, height = excluded.height, usage = excluded.usage;

-- 3. the email wrappers ---------------------------------------------------------------------------------
update public.templates
   set content = replace(replace(replace(content,
       'color:#0d9488">Quotes<span style="color:#111827">Done', 'color:#0C2330">Quotes<span style="color:#14B8A6">Done'),
       '#0d9488', '#0B8276'), 'font-weight:700;color:#111827', 'font-weight:700;color:#0C2330')
 where name = 'email_customer';
update public.templates
   set content = replace(replace(replace(replace(replace(replace(replace(content,
       '#2DD4BF', '#6EE7D4'), 'rgba(45,212,191,.15)', 'rgba(110,231,212,.15)'), '#E7B53C', '#E3C065'), '#0d9488', '#0B8276'),
       'font-weight:700;color:#ffffff;text-decoration:none;border-radius:10px;">Go to the Supplier Portal', 'font-weight:700;color:#0C2330;text-decoration:none;border-radius:10px;">Go to the Supplier Portal'),
       'UAE Quotation Marketplace', 'UAE Sourcing Marketplace'), 'color:#9fb2bd;', 'color:#9DB2B2;')
 where name = 'email_supplier';

-- the mail logo is the kit file (a public URL, not a secret; byte-identical to the icon_192.png it replaces)
update public.app_secrets
   set value = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/PWA_192_192x192.png'
 where key = 'email_logo_url'
   and value <> 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/04_Web_App_Icons/PWA_192_192x192.png';

-- 3b. the older canon rows stop contradicting the kit ---------------------------------------------------
-- agent_knowledge 10445 (_global, priority 45) restated the Dropbox asset brand_colors_and_details.txt with "alt"
-- hexes and "Sora / Inter" web faces that the site never used; agent_knowledge 844 (priority 1000) named
-- make_pdf/pdf_native as the only branded renderer. Both are corrected in place (same id, same topic).
update public.agent_knowledge
   set content =
     'From company asset "brand_colors_and_details.txt" (Dropbox: /QuotesDone Backup/Assets/QuotesDone_Corporate_Kit/07_Reference/brand_colors_and_details.txt), '
     || 'corrected on 6 Sep 2026 to the founder''s brand kit. public.company_brand is the source of truth; qd-company:brand carries it into every head.' || E'\n\n'
     || 'QUOTESDONE — BRAND & COMPANY REFERENCE' || E'\n' || '========================================' || E'\n\n'
     || 'COLOURS (the kit; the former "alt" hexes #0d9488, #123047, #f0c869 and the Tailwind greys are retired)' || E'\n'
     || '  Teal (primary)     #14B8A6   light #6EE7D4 · deep #0B8276 (links and small teal text on white)' || E'\n'
     || '  Gold (secondary)   #E3C065   light #F6DD8C · deep #BD8E36' || E'\n'
     || '  Navy (background)  #0C2330   high #173A4B · deep #06121B · surface #123041' || E'\n'
     || '  Ink (print)        #0A0A0A   paper #EAF4F2 · muted #9DB2B2 (text on navy)' || E'\n\n'
     || 'TYPEFACES' || E'\n'
     || '  Wordmark and brand artwork: Poppins Bold. Website and OS: Plus Jakarta Sans (body), Space Grotesk (headings), JetBrains Mono (figures); Arabic: Tajawal. '
     || 'Email: Arial/Helvetica. Reports: Helvetica (report_pdf); quotation PDFs: Sora + Arabic TTF (pdf_native).' || E'\n\n'
     || 'COMPANY' || E'\n'
     || '  Legal name : QuotesDone Technologies' || E'\n'
     || '  Licence    : DET Trader Licence No. 1633275 (expires 24 Jun 2027; company_registration is the record)' || E'\n'
     || '  Activity   : B2B anonymous quotation marketplace' || E'\n'
     || '  Address    : Dubai, United Arab Emirates' || E'\n'
     || '  Signatory  : Ahmad Alzain — Founder & Managing Director' || E'\n'
     || '  Email      : management@quotesdone.com' || E'\n'
     || '  Mobile/WA  : +971 50 931 9355' || E'\n'
     || '  Website    : quotesdone.com',
       updated_at = now()
 where id = 10445 and agent_key = '_global' and topic = 'Asset text: brand_colors_and_details.txt';

update public.agent_knowledge
   set content = content || ' Reports (board_reports, exec_reports, finance_reports) render through the report_pdf edge function (6 Sep 2026): '
     || 'navy #0C2330 header band with the kit''s OnDark lockup, teal #14B8A6 section markers, gold #E3C065 cover rule, Helvetica body, '
     || 'and a footer carrying "Confidential — QuotesDone", the DET Trader Licence No. 1633275 line and "Page x of y". The full rules: docs/brand/QUOTESDONE_BRAND_GUIDE.md.',
       updated_at = now()
 where id = 844 and agent_key = '_global' and topic = 'Document branding standard' and position('report_pdf' in content) = 0;

-- 4. the company record ---------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_funnel text;
  v_founder text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
begin
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company)
  select string_agg(identity, ' / ' order by identity) into v_founder
    from public.phase_c_founder_identity where active and kind = 'email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  select string_agg('  ' || workflow_id || ' — ' || workflow_name, E'\n' order by workflow_id)
    into v_funnel from public.phase_b_workflow
   where workflow_id in ('W04','W05','W06','W07','W08','W09','W10','W12','W13','W14','W15','W16','W17','W18');

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT that day; both are closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L)',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.'),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then. The 30 workflows that run this: ' || coalesce(v_funnel,'(registry)') ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one.' || E'\n' ||
        'SUPPLIERS: registration is FREE until ' || coalesce(to_char(v_charge,'DD Mon YYYY'),'01 Aug 2027') ||
          ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. Suppliers are auto-approved on a verified file.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes that fee + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (fn_refund_amount_aed). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: 9% per annum (UAE Federal Decree-Law 50/2022).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the refunded fee (the 3%) + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the UAE statutory maximum), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)'))
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;

-- 5. the head (both overloads, restated) ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int;
        c_keep constant int := 19500;   -- what fn_agent_context_capped keeps of the head at 24,000
        v_room int; l2_cap int; l1_cap int; l3_cap int; l4_cap int; v_used int; v_first boolean;
        v_ops jsonb; v_ops_txt text;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_loop text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text;
        v_genome text;
        v_risks text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';

    -- ---- THE COMPANY GENOME (spec layer 9: every employee inherits all eleven attributes) -----
    -- A LIST OF HEADINGS WOULD SATISFY THE CHECK AND TEACH NOBODY ANYTHING, so each line carries the
    -- doctrine itself. 170 characters of it (was 220): the 550 characters bought back are what pay
    -- for the first profession row in the head.
    select string_agg('- '||c.title||': '||left(regexp_replace(c.body, '\s+', ' ', 'g'), 170),
                      E'\n' order by c.article_no)
      into v_genome
      from public.company_constitution c
     where c.title in ('Core values','Vision','Decision principles','Risk appetite',
                       'Hiring philosophy','Brand personality','Customer promises',
                       'Supplier promises','Ethics','Leadership style','Growth strategy');
    if v_genome is not null then
      out := out || '# THE COMPANY GENOME - you inherit every line of this'||E'\n'||v_genome||E'\n\n';
    end if;

    -- ---- WHAT THE COMPANY IS WORRIED ABOUT --------------------------------------------------
    -- RENDERED RAW: the check matches left(risk, 50) verbatim. Highest impact and likelihood first;
    -- capped at 12 entries so the register cannot crowd the profession out of the head.
    -- ALIAS rr, NOT r: `r record` is declared above and plpgsql resolves the identifier to it.
    select string_agg('- ['||coalesce(z.impact,'?')||' impact / '||coalesce(z.probability,'?')
                      ||' likelihood] '||z.risk
                      ||case when coalesce(z.mitigation,'') <> ''
                             then '  -> mitigating: '||left(z.mitigation, 120) else '' end,
                      E'\n' order by z.ord)
      into v_risks
      from (select rr.impact, rr.probability, rr.risk, rr.mitigation,
                   row_number() over (order by case coalesce(rr.impact,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               case coalesce(rr.probability,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               rr.id) ord
              from public.risk_register rr
             where coalesce(rr.status,'open') in ('open','mitigating') and length(rr.risk) > 20) z
     where z.ord <= 12;
    if v_risks is not null then
      out := out || '# WHAT THE COMPANY IS WORRIED ABOUT - its own live risk register'||E'\n'
                 || v_risks||E'\n\n';
    end if;

    -- ---- THE EMPLOYEE OBJECT (spec line 372) --------------------------------------------------
    select a.title, a.responsibilities, a.manager_key, a.seniority, a.improvement_plan, a.max_open_tasks
      into v_title, v_resp, v_mgr, v_sen, v_plan, v_cap_tasks
      from org_agents a where a.agent_key = p_agent_key;

    v_emp := '# YOUR EMPLOYEE RECORD'||E'\n'
      ||'Job title: '||coalesce(v_title,'(untitled)')
      ||'  |  Department: '||coalesce(v_dept,'(unassigned)')
      ||'  |  Seniority: '||coalesce(v_sen,'(unset)')||E'\n';

    if v_mgr is not null then
      select 'Reports to: '||m.agent_key||' — '||coalesce(m.title, m.role, 'manager') into v_line
        from org_agents m where m.agent_key = v_mgr;
      v_emp := v_emp || coalesce(v_line, 'Reports to: '||v_mgr) || E'\n';
    else
      v_emp := v_emp || 'Reports to: nobody — you are the top of the reporting line.'||E'\n';
    end if;

    select count(*), string_agg(x.agent_key||' ('||coalesce(x.title, x.role, 'specialist')||')', '; ' order by x.agent_key)
      into v_n, v_line
      from (select b.agent_key, b.title, b.role from org_agents b
             where b.manager_key = p_agent_key and b.active order by b.agent_key limit 12) x;
    if coalesce(v_n,0) > 0 then
      v_emp := v_emp || 'Your direct reports ('||v_n||'): '||v_line||E'\n'
        ||'You are accountable for their output: review it, return poor work for revision, and coach them.'||E'\n';
    end if;

    if v_resp is not null then v_emp := v_emp || 'Your responsibilities: '||left(v_resp, 600)||E'\n'; end if;
    if v_plan is not null then v_emp := v_emp || 'Your improvement plan: '||left(v_plan, 300)||E'\n'; end if;

    -- ---- AUTHORITY LIMITS ----------------------------------------------------------------------
    select string_agg(z.action_class||' -> '||z.max_tier
             ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
             order by z.action_class)
      into v_line
      from (select e.action_class, e.max_tier, e.threshold_aed from employee_authority e
             where e.agent_key = p_agent_key order by e.action_class limit 14) z;
    if v_line is null then
      select string_agg(z.action_class||' -> '||z.max_tier
               ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
               order by z.action_class)
        into v_line
        from (select o.action_class, o.max_tier, o.threshold_aed from org_authority o
               where o.dept_key = v_dept order by o.action_class limit 14) z;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (delegated to '||v_dept||', no personal grant on file)'||E'\n';
      end if;
    else
      v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (granted to you personally)'||E'\n';
    end if;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n'
        ||'Anything not on that list is GATED: propose it, do not do it.'||E'\n';
    end if;

    -- ---- ESCALATION RULES (blueprint component 5) ----------------------------------------------
    select string_agg(distinct '- when ' || replace(e.escalation_rule->>'when','_',' ')
                             || ' -> ' || replace(e.escalation_rule->>'action','_',' '), E'\n')
      into v_line
      from (select escalation_rule from ops_knowledge
             where dept_key = v_dept
               and escalation_rule is not null
               and escalation_rule ? 'when' and escalation_rule ? 'action'
             limit 40) e;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHEN TO ESCALATE (your department''s recorded rules)'||E'\n'||left(v_line, 700)||E'\n';
    end if;

    -- ---- KPIs: how this employee's work is judged ----------------------------------------------
    select string_agg(z.kpi||' — target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
             ||' ('||coalesce(z.cadence,'ongoing')
             ||case when z.serves_goal is not null then '; serves company goal '||z.serves_goal else '' end||')', E'\n- '
             order by z.kpi)
      into v_line
      from (select k.kpi, k.target_value, k.unit, k.cadence, k.serves_goal from employee_kpi k
             where k.agent_key = p_agent_key and k.active order by k.kpi limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR KPIs — this is how your work is measured'||E'\n- '||v_line||E'\n';
    end if;

    -- ---- CURRENT WORKLOAD, measured rather than assumed -----------------------------------------
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' proposed (held for review with '
           ||coalesce((select d.lead_agent from org_departments d where d.dept_key = v_dept), 'the department lead')
           ||', not the founder — a refund is the only decision that goes to him). Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
      into v_line
      from org_tasks t where t.dept_key = v_dept and t.status in ('assigned','in_progress');
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR CURRENT WORKLOAD (live)'||E'\n'||v_line||E'\n';
      select string_agg('- ['||z.status||'] '||left(z.title,90), E'\n' order by z.id)
        into v_line
        from (select t.id, t.status, t.title from org_tasks t
               where t.dept_key = v_dept and t.status in ('assigned','in_progress')
               order by t.id limit 6) z;
      if v_line is not null then v_emp := v_emp || v_line || E'\n'; end if;
    end if;

    -- ---- WHICH OPERATING SYSTEM YOU BELONG TO (spec file #2) ------------------------------------
    for r in
      select o.os_key, o.name, o.charter, o.mandate, o.mission, o.owner_agent,
             (select coalesce(w.title, w.role) from org_agents w
               where w.agent_key = o.owner_agent and w.active) owner_title,
             (select string_agg(x.responsibility, ', ' order by x.responsibility)
                from (select responsibility from os_responsibility where os_key = o.os_key
                       order by responsibility limit 12) x) resp,
             (select string_agg(y.horizon || ': ' || y.objective, E'\n- '
                       order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                               when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
                from (select horizon, objective from os_objective
                       where os_key = o.os_key and coalesce(active,true)) y) objectives
        from os_department d
        join operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
       where d.dept_key = v_dept
       limit 1
    loop
      v_os := r.os_key;
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
      v_emp := v_emp || E'\n'||'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)||E'\n'
        ||case when r.charter is not null then 'Purpose: '||left(r.charter,300)||E'\n' else '' end
        ||case when r.mission is not null then 'Mission: '||left(r.mission,240)||E'\n' else '' end
        ||case when r.mandate is not null then 'Mandate: '||left(r.mandate,240)||E'\n' else '' end
        ||v_line
        ||case when r.resp is not null
               then 'Your OS OWNS, and no other OS may own: '||r.resp||E'\n'
                 ||'If work belongs to another OS, hand it over — do not duplicate it.'||E'\n'
               else '' end
        ||case when r.objectives is not null
               then 'Your OS objectives by horizon:'||E'\n- '||r.objectives||E'\n' else '' end;
    end loop;

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
    select string_agg(z.goal||' ('||coalesce(z.metric,'no metric')
             ||case when z.target_value is not null then '; target '||z.target_value||' '||coalesce(z.unit,'') else '' end
             ||case when z.actual_value is not null
                    then '; CURRENTLY '||z.actual_value||coalesce(' ('||z.status||')','') else '; not yet measured' end||')', E'\n- '
             order by z.sort nulls last)
      into v_line
      from (select g.goal, g.metric, g.target_value, g.unit, g.sort, gp.actual_value, gp.status
              from company_goals g
              left join lateral (select p.actual_value, p.status from goal_period p
                                  where p.goal_key = g.key
                                  order by p.updated_at desc nulls last limit 1) gp on true
             where g.active and (g.owner_dept is null or g.owner_dept = v_dept or g.owner_dept = 'exec')
             order by g.sort nulls last limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# COMPANY GOALS YOUR WORK MUST MOVE'||E'\n- '||v_line||E'\n';
    end if;

    select string_agg('- '||z.objective, E'\n' order by z.sort nulls last)
      into v_line
      from (select o.objective, o.sort from department_objective o
             where o.dept_key = v_dept and coalesce(o.active,true) order by o.sort nulls last limit 6) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR DEPARTMENT''S OBJECTIVES'||E'\n'||v_line||E'\n';
    end if;

    -- ---- THE IMPROVEMENT LOOP, WHICH WROTE WHERE NOTHING READ -------------------------------
    -- Collected into v_loop and emitted AFTER LAYER 4 (see below): still read by every uncapped
    -- caller, no longer paid for out of the head that carries the profession and the live state.
    select string_agg(z.line, E'\n' order by z.ord, z.line)
      into v_line
      from (
        select 1 ord, '- OPEN FINDING ('||s.review_type||'): '||left(s.finding, 160)
               ||coalesce(' — proposed: '||left(s.proposal,120), '') line
          from self_review s
         where coalesce(s.status,'open') not in ('done','implemented','rejected')
         order by s.created_at desc limit 3
      ) z;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_loop := v_loop || v_line || E'\n';
    end if;

    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_loop := v_loop || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 5200) || E'\n\n';

    -- ---- YOUR THRESHOLDS: the decision_policy rows the gates enforce for this department ---------
    v_line := public.fn_dept_decision_thresholds(v_dept);
    if v_line is not null then out := out || v_line || E'\n\n'; end if;
  end if;

  -- ================= THE BUDGETED LAYERS. Everything below is measured against c_keep. ============
  -- v_room is what is left of the 19,500 the capped path keeps. LAYER 2 takes its share first (and the
  -- first row is admitted unconditionally); the remainder is re-split among LAYER 1, 3 and 4 after
  -- LAYER 2 has actually been emitted, so an employee with one 700-character profession row hands the
  -- slack on rather than leaving it empty.
  v_room := greatest(c_keep - length(out), 3200);
  l2_cap := greatest(1200, v_room * 27 / 100);

  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    v_used := 0; v_first := true;
    for r in select topic,content,review_due,validation_status from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and coalesce(validation_status,'') <> 'quarantined'
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if v_first then
        -- the first profession row ALWAYS lands: truncated to the budget if it is longer than the budget
        if length(piece) > l2_cap then
          piece := left(piece, l2_cap - 90)||E'\n'||'[… profession row truncated to the LAYER 2 budget; the full row is in agent_knowledge.]'||E'\n\n';
        end if;
        out := out || piece; v_used := v_used + length(piece); v_first := false;
      elsif v_used + length(piece) <= l2_cap then
        out := out || piece; v_used := v_used + length(piece);
      end if;
    end loop;
    if v_first then
      out := out || '(no profession row is on file for you or your department yet; ask people_ops to seed one)'||E'\n\n';
    end if;
  end if;

  -- re-split what is left among LAYER 1 / 3 / 4
  v_room := greatest(c_keep - length(out), 2400);
  l1_cap := greatest(800, v_room * 36 / 100);
  l3_cap := greatest(700, v_room * 28 / 100);
  l4_cap := greatest(700, v_room - l1_cap - l3_cap - 160);

  -- ---- LAYER 1: the four hard rules, the LIVE company rows, then the _global canon ----------------
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  piece := coalesce(public.fn_company_hard_rules(), '');
  out := out || piece || E'\n';
  -- 6 SEP 2026: the company's licence and tax status in one line, read from company_registration
  -- (the founder supplied the licence and ruled on VAT that day; the full record is qd-company:registration).
  select 'LICENCE & TAX: ' || cr.authority || ' ' || cr.license_type || ' no. ' || cr.license_no || ' "' || cr.trade_name || '", expires '
         || to_char(cr.expires_on, 'DD Mon YYYY') || '; activities ' || left(cr.activities, 90) || '. '
         || case when cr.vat_registered then 'VAT-registered, TRN ' || coalesce(cr.trn, '?') || '.'
                 else 'NOT VAT-registered: no VAT is charged or shown until AED ' || to_char(cr.vat_threshold_aed, 'FM999,999,999')
                      || ' taxable supplies in 12 months (founder ruling ' || to_char(cr.vat_ruling_on, 'DD Mon YYYY') || '; never ask the founder about VAT or the TRN).' end
    into piece from public.company_registration cr order by cr.recorded_at desc limit 1;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  -- 6 SEP 2026: the brand in one line, read from company_brand (the founder's kit is on file; the full record
  -- is qd-company:brand). Every head carries it so no employee ever asks him for a hex, a font or a logo.
  piece := null;
  select 'BRAND: teal ' || t.v || ' (primary), gold ' || g.v || ' (secondary), navy ' || n.v || ' (background), ink ' || i.v
         || ' (print); typeface ' || d.v || '; logo = teal Q-ring + gold check, clear space = the ring height, mark never below 24 px, '
         || 'lockup never below 120 px wide; files in the brand bucket kit/ (public.brand_assets), rules in public.company_brand '
         || '(qd-company:brand); the guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md. Never ask the founder for brand assets.'
    into piece
    from (select value as v from public.company_brand where key = 'colour.teal') t,
         (select value as v from public.company_brand where key = 'colour.gold') g,
         (select value as v from public.company_brand where key = 'colour.navy') n,
         (select value as v from public.company_brand where key = 'colour.ink') i,
         (select value as v from public.company_brand where key = 'type.display') d;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  v_used := 0;
  for r in select o.record_id, o.title, o.content, o.effective_date
             from ops_knowledge o
            where o.record_id in ('qd-company:stage','qd-company:live-state')
            order by case o.record_id when 'qd-company:stage' then 1 else 2 end loop
    piece := '## '||coalesce(r.title, r.record_id)||' (live, effective '||coalesce(to_char(r.effective_date,'DD Mon YYYY'),'?')||')'||E'\n'
             ||left(regexp_replace(coalesce(r.content,''), E'\n\nYou can answer questions about:.*$', ''), 700)||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out || piece; v_used := v_used + length(piece); end if;
  end loop;
  -- The _global canon, highest priority first, each cut at 500 inside the head. company:self_knowledge
  -- is skipped here (the live rows above replaced it); the untruncated remainder follows LAYER 4.
  for r in select id, topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 500
                  then left(r.content, 500)||E'\n'||'[… cut at 500 of '||length(r.content)||' characters; the full item is in agent_knowledge.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out||piece; v_used := v_used + length(piece); end if;
  end loop;

  -- ---- LAYER 3: live operational state, inside the head -----------------------------------------
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), l3_cap - 160)||E'\n\n';
      out := out || piece;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;

  -- ---- LAYER 4: what the organisation has learned, inside the head --------------------------------
  if p_agent_key is not null then
    for r in select topic, content, review_due, validation_status from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
               and coalesce(validation_status,'') <> 'quarantined'
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, l4_cap - 60) || E'\n';
    end if;
  end if;

  -- ================= AFTER THE HEAD. Reaches the uncapped callers; bounded by cap. ==============
  -- The improvement loop, then the rest of the _global canon in full.
  if v_loop <> '' then out := out || v_loop || E'\n'; end if;

  out := out || '# LAYER 1 (continued) - THE REST OF THE COMPANY CANON'||E'\n\n';
  for r in select topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;

  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  if v_os is not null then
    select string_agg(z.horizon||': '||z.objective||' — reads '
             ||coalesce(z.actual_value::text,'no value')
             ||coalesce(' (measured '||to_char(z.measured_at,'DD Mon')||')', ' (measure failed)'),
             E'\n- '
             order by case z.horizon when 'strategic' then 1 when 'annual' then 2
                                     when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
      into v_line
      from (select horizon, objective, actual_value, measured_at from os_objective
             where os_key = v_os and coalesce(active,true)) z;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS OBJECTIVES, MEASURED (the number, not the aspiration)'
             ||E'\n- '||left(v_line, 1600)||E'\n';
    end if;

    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
      from (select r2.id, r2.workflow_key, r2.current_step, r2.status, r2.started_at
              from workflow_run r2 join workflow w2 on w2.workflow_key = r2.workflow_key
             where r2.status in ('queued','running') and w2.os_key = v_os
             order by r2.started_at desc nulls last limit 8) x
      join workflow w on w.workflow_key = x.workflow_key
     where w.os_key = v_os;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS''S WORKFLOWS IN FLIGHT (workflow_run)'||E'\n'
             ||left(v_line, 900)||E'\n'
             ||'Close a step with fn_workflow_step_done(run, step_no, output).'||E'\n';
    end if;
  end if;

  -- ---- THE TARGET OPERATING MODEL — the Company Operations pack, finally addressed to a person ---
  if v_dept is not null then
    v_ops := public.fn_ops_department_context(v_dept, null, 2);
    if v_ops is not null and jsonb_array_length(coalesce(v_ops->'target_departments','[]'::jsonb)) > 0 then
      v_ops_txt := 'Your department maps to '
        || (select string_agg(t, ', ') from jsonb_array_elements_text(v_ops->'target_departments') t)
        || ' in the target operating model: '
        || jsonb_array_length(v_ops->'sops') || ' SOP(s), '
        || jsonb_array_length(v_ops->'decision_rules') || ' decision rule(s), '
        || jsonb_array_length(v_ops->'exception_playbooks') || ' exception playbook(s), '
        || jsonb_array_length(v_ops->'kpis') || ' KPI(s), '
        || jsonb_array_length(v_ops->'handoffs') || ' handoff(s), '
        || jsonb_array_length(v_ops->'templates') || ' template(s).' || E'\n';

      select coalesce(string_agg('- RULE ' || coalesce(d->>'rule_id','?') || ': when ' ||
               left(coalesce(d->>'when',''),110) || ' -> ' || left(coalesce(d->>'then',''),110) ||
               case when coalesce((d->>'requires_human_review')::boolean,false)
                    then ' [needs human review]' else '' end, E'\n'), '')
        into v_line from (select d from jsonb_array_elements(v_ops->'decision_rules') d limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg('- ' || (h->>'direction') || ' ' || coalesce(h->>'workflow','') ||
               ' (' || coalesce(h->>'from','?') || ' -> ' || coalesce(h->>'to','?') || '): ' ||
               left(coalesce(h->>'you_must',''),90), E'\n'), '')
        into v_line from (select h from jsonb_array_elements(v_ops->'handoffs') h limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg(e->>'event', ', '), '')
        into v_line from (select e from jsonb_array_elements(v_ops->'event_subscriptions') e limit 6) z;
      if coalesce(v_line,'') <> '' then
        v_ops_txt := v_ops_txt || 'Events your target model consumes (NOT yet activated on the live bus): '
                     || v_line || E'\n';
      end if;

      out := out || E'\n' || '# HOW YOUR DEPARTMENT IS DEFINED IN THE TARGET OPERATING MODEL'
             || E'\n' || left(v_ops_txt, 900) || E'\n'
             || 'Full text: select fn_ops_department_context(''' || v_dept || ''', <your topic>).' || E'\n';
    end if;
  end if;

  return out;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record; v_cat text; catx text := '';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  -- THE CATEGORY, derived from the task itself (inquiry / run reference, a key, or a catalogue name).
  v_cat := public.fn_category_key_from_text(p_query);

  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  -- THE MARKER IS ALWAYS EMITTED. fn_agent_context_capped splits the standing head from the retrieved
  -- tail on '# LAYER 2b'; when the library had no match there was no marker, and the whole retrieved
  -- tail fell past a positional cut instead of being kept inside the 4,500-character reserve.
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  else
    out := out || E'\n' || '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY: no dept_library row matched this task.' || E'\n\n';
  end if;

  -- LAYER 2d/2e/2f/2g: the V3 delivery, now WITH the category key when the task names one.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, v_cat, 9000);

    -- LAYER 2e first: the category pack has to sit inside the reserve the capped path keeps.
    if v_cat is not null and v3 ? 'category_knowledge' then
      for itm in select * from jsonb_array_elements(coalesce(v3->'category_knowledge','[]'::jsonb)) loop
        exit when length(catx) > 1800;
        catx := catx || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
              || left(regexp_replace(coalesce(itm->>'content',''), '\s+', ' ', 'g'), 600) || E'\n\n';
      end loop;
      if catx <> '' then
        out := out || E'\n' ||
          '# LAYER 2e - THE CATEGORY PACK FOR THIS TASK (' || v_cat || '): the route''s qualification playbook, ' ||
          'field and question bank, quality gate and comparison contract. This task is category-scoped; these records ' ||
          'decide what to ask, what may never be inferred and how quotes in this route are compared. Cite the [record_id].' ||
          E'\n\n' || catx;
      end if;
    end if;

    for r2 in
      select title, content, record_type, authority_tier, implementation_status, rank
        from public.fn_ops_knowledge_search(v_dept, p_query, 5)
       order by rank desc
    loop
      exit when length(ops) > 2400;
      ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
             coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
             coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
    end loop;
    if ops <> '' then
      out := out || E'\n' ||
        '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
        'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
        'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
        'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
        E'\n\n' || ops;
    end if;

    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
            || left(coalesce(itm->>'content',''), 700) || E'\n\n';
      end loop;
      if sec <> '' then
        out := out || E'\n' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'\n\n' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'\n\n' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'\n\n' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$;

-- 6. the ledger follows this file -----------------------------------------------------------------------

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_company_knows_its_own_brand.sql',
       evidence = 'defined by scripts/sql/the_company_knows_its_own_brand.sql (qd-company:brand appended to the record array, 6 Sep 2026)', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_company_self_knowledge_sync' and coalesce(identity_args,'') = '';
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, recorded_at)
select 'public', 'fn_company_self_knowledge_sync', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_company_knows_its_own_brand.sql (qd-company:brand appended to the record array, 6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_company_knows_its_own_brand.sql', now()
 where not exists (select 1 from public.kernel_routine_ownership where schema_name = 'public' and routine_name = 'fn_company_self_knowledge_sync' and coalesce(identity_args,'') = '');

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_company_knows_its_own_brand.sql',
       evidence = 'defined by scripts/sql/the_company_knows_its_own_brand.sql (the BRAND line after LICENCE & TAX, 6 Sep 2026)', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_agent_context' and coalesce(identity_args,'') = 'p_agent_key text, p_max_chars integer';
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, recorded_at)
select 'public', 'fn_agent_context', 'p_agent_key text, p_max_chars integer', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_company_knows_its_own_brand.sql (the BRAND line after LICENCE & TAX, 6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_company_knows_its_own_brand.sql', now()
 where not exists (select 1 from public.kernel_routine_ownership where schema_name = 'public' and routine_name = 'fn_agent_context' and coalesce(identity_args,'') = 'p_agent_key text, p_max_chars integer');

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_company_knows_its_own_brand.sql',
       evidence = 'restated verbatim by scripts/sql/the_company_knows_its_own_brand.sql (delegates to the 2-arg overload)', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_agent_context' and coalesce(identity_args,'') = 'p_agent_key text, p_max_chars integer, p_query text';
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, recorded_at)
select 'public', 'fn_agent_context', 'p_agent_key text, p_max_chars integer, p_query text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated verbatim by scripts/sql/the_company_knows_its_own_brand.sql (delegates to the 2-arg overload)', 'MANIFEST', 'scripts/sql/the_company_knows_its_own_brand.sql', now()
 where not exists (select 1 from public.kernel_routine_ownership where schema_name = 'public' and routine_name = 'fn_agent_context' and coalesce(identity_args,'') = 'p_agent_key text, p_max_chars integer, p_query text');

-- proof: the record exists and every head carries the primary hex and the typeface ----------------------
do $proof$
declare v_rows int; v_files int; v_content text; v_m text; v_d text;
begin
  select count(*) into v_rows from public.company_brand;
  select count(*) into v_files from public.brand_assets where bucket = 'brand';
  if v_rows < 50 then raise exception 'company_brand has % rows, expected >= 50', v_rows; end if;
  if v_files < 58 then raise exception 'brand_assets has % kit rows, expected 58', v_files; end if;
  perform public.fn_company_self_knowledge_sync();
  select content into v_content from public.ops_knowledge where record_id = 'qd-company:brand';
  if v_content is null or position('#14B8A6' in v_content) = 0 or position('Poppins' in v_content) = 0 then
    raise exception 'qd-company:brand is missing or lacks the primary hex / typeface';
  end if;
  v_m := public.fn_agent_context('marketing', 6000);
  v_d := public.fn_agent_context('marketing_design', 6000);
  if position('#14B8A6' in v_m) = 0 or position('Poppins' in v_m) = 0 then raise exception 'the marketing head lacks the brand line'; end if;
  if position('#14B8A6' in v_d) = 0 or position('Poppins' in v_d) = 0 then raise exception 'the marketing_design head lacks the brand line'; end if;
  if exists (select 1 from public.templates where name in ('email_customer','email_supplier') and (position('#0d9488' in content) > 0 or position('#E7B53C' in content) > 0 or position('#2DD4BF' in content) > 0)) then
    raise exception 'an email wrapper still carries a retired hex';
  end if;
  if exists (select 1 from public.agent_knowledge where id = 10445 and position('#0d9488' in content) > 0 and position('retired' in content) = 0) then
    raise exception 'agent_knowledge 10445 still teaches the retired alt hexes';
  end if;
  raise notice 'proof: company_brand rows=%, kit files=%, qd-company:brand chars=%, marketing head has #14B8A6 at %, marketing_design head at %',
    v_rows, v_files, length(v_content), position('#14B8A6' in v_m), position('#14B8A6' in v_d);
end $proof$;

commit;
