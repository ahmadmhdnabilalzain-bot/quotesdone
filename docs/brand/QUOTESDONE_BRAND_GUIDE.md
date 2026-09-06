# QuotesDone Brand Guide

Version 1.0 — 6 September 2026. Owner: Growth (brand_mgr, marketing_design). Source of truth: `public.company_brand` (every rule below is a row there) and `public.brand_assets` (every file). Every AI employee reads this through `qd-company:brand` and the BRAND line of its head. The founder's ruling of 6 September 2026: the kit is company knowledge; nobody asks him for a logo, a colour or a font again. Everything in the kit may be upgraded except the logo artwork.

## Provenance and where things live

| Item | Value |
|---|---|
| The kit | QuotesDone_Brand_Kit.zip, 2.9 MB, produced 24 June 2026, attached by the founder on 6 September 2026 |
| Files | 58 files (50 PNG, 1 ICO, 4 SVG, 2 vector PDF, WHERE_TO_USE.txt) in the public `brand` storage bucket under `kit/` — indexed in `public.brand_assets` with kind, platform, path, bytes, sha256, pixel size and usage |
| Rules | `public.company_brand` — colours, gradients, typography, logo rules, voice, imagery, sizes, contrast pairs, sources |
| Agents | `qd-company:brand` in `ops_knowledge`, rendered every 15 minutes by `fn_company_self_knowledge_sync`; the one-line BRAND fact in every head from `fn_agent_context` |
| Edge code | `supabase/functions/_shared/brand.ts` (the same hexes for report_pdf and mail); `src/app/globals.css` tokens for the site and the OS |
| This guide | `docs/brand/QUOTESDONE_BRAND_GUIDE.md`, and the "QuotesDone Brand Guide" PDF in the OS Reports panel (report_type `brand`, published by `scripts/brand/publish_brand_guide.mjs`) |
| Company | quotesdone technologies — DET Trader Licence no. 1633275, Dubai, UAE (expires 24 June 2027); quotesdone.com |

The bucket is public on purpose: it already serves the site's favicons and og:image, and mail clients need a plain URL for the logo. Nothing in a logo is secret.

## The mark

The mark is a teal ring — the Q — with a gold check breaking out of its lower right: the "done" tick. Geometry (SVG viewBox 0 0 800 800, `kit/08_Vector_Source/mark_color.svg`):

- Ring: circle cx 400, cy 398, r 92, stroke 50, teal gradient.
- Check: path M434 470 L486 524 L582 408, stroke 44, round caps and joins, gold gradient.
- One-colour versions: `mark_black.svg` (#0A0A0A) and `mark_white.svg` (#FFFFFF), same geometry.

The wordmark is "QuotesDone" set in Poppins Bold, one word, camel-cased. On light grounds "Quotes" is navy #0C2330 and "Done" is teal #14B8A6. On dark grounds "Quotes" is paper/white and "Done" is gold #E3C065. The lockup masters are 1859 x 460 px, transparent.

The founder-approved master is `kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png`: the brand square (navy gradient, gold hairline frame, the mark, "QUOTES DONE" beneath). Every avatar and app icon derives from it. The logo artwork is the one thing in this guide that changes only with the founder.

### Logo variants and when to use each

| Use | File |
|---|---|
| Colour lockup on white or light grounds (default) | `kit/05_Logo_Lockups/horizontal_OnLight_transparent.png` |
| Lockup on navy, photographs or any dark ground | `kit/05_Logo_Lockups/horizontal_OnDark_transparent.png` |
| One-colour (print, fax, engraving, embossing) | `kit/05_Logo_Lockups/horizontal_Black_Mono_transparent.png` |
| Ready-made backgrounds | `horizontal_on_white.png`, `horizontal_on_navy.png` |
| Symbol alone, colour (light grounds) | `kit/05_Logo_Lockups/mark_only_transparent_1200.png` |
| Symbol alone, white (navy or photo grounds) | `kit/05_Logo_Lockups/mark_white_transparent_1200.png` |
| Printers and IP agents (never blurs) | `kit/08_Vector_Source/*.svg`, `mark_color.pdf`, `mark_black.pdf` |
| Trademark filings (colour and black-and-white are both usually required) | `kit/07_Trademark_and_License/MARK_*`, `LOCKUP_*`, `BRAND_SQUARE_color_2000.png` |
| Trade-licence artwork | `BRAND_SQUARE_color_2000.png` or `LOCKUP_color_on_white.png` |

### Clear space, minimum size, and the don'ts

- Clear space: at least the height of the Q ring on every side of the mark or lockup.
- Minimum size: the mark never below 24 px on screen or 8 mm in print; the horizontal lockup never below 120 px wide or 30 mm.
- Never recolour, stretch, rotate, outline, add drop shadows or glows, place on plain blue or on busy photographs, set the wordmark in another typeface, or separate the check from the ring.
- The logo never mirrors for Arabic layouts. The page mirrors; the logo does not.

## Colour

Primary is teal, secondary is gold, the ground is navy, print is ink. The hexes below are the kit's own (WHERE_TO_USE.txt) and the same values sit in `src/app/globals.css`, `_shared/brand.ts` and `public.company_brand`.

| Token | Hex | Role |
|---|---|---|
| Teal | #14B8A6 | Primary. The Q ring, primary buttons, active states, links on navy. On white it is an accent only (2.5:1) — never body text there |
| Teal light | #6EE7D4 | Gradient start; text and links on navy (10.8:1); the tagline colour on covers; the eyebrow on social cards |
| Teal deep | #0B8276 | Gradient end; links and small teal text on white (4.7:1, AA) |
| Gold | #E3C065 | Secondary. The check mark; "Done" in the on-dark wordmark; highlights and totals on navy (9.2:1). Never text on white (1.8:1) |
| Gold light | #F6DD8C | Gradient start |
| Gold deep | #BD8E36 | Gradient end; the only gold that works as large text on white (3.0:1) |
| Gold hairline | #CAA14E to #8A6A2F | The 3 px frame on the brand square and app icons, 85% opacity |
| Navy | #0C2330 | Background of every dark surface; "Quotes" in the on-light wordmark; body text on white (16.2:1) |
| Navy high | #173A4B | Background gradient start (top-left) |
| Navy deep | #06121B | Background gradient end (bottom-right) |
| Surface | #123041 | Raised cards on navy (site token `--surf`) |
| Ink | #0A0A0A | One-colour and print; the Black_Mono lockup; never a screen background |
| Paper | #EAF4F2 | Text on navy (14.4:1); site token `--paper` |
| Muted | #9DB2B2 | Secondary text on navy (7.3:1); site token `--muted` |
| Faint | #7C97A3 | Tertiary text on navy (5.2:1); site token `--faint` |
| White | #FFFFFF | Page grounds; the white mark on navy or photographs |

### The three gradients

| Use | Definition |
|---|---|
| Teal (the Q ring) | linear, (0,0) to (1,1): #6EE7D4 at 0%, #16B8A6 at 55%, #0B8276 at 100% |
| Gold (the check) | linear, (0,0) to (0.3,1): #F6DD8C at 0%, #E3C065 at 50%, #BD8E36 at 100% |
| Navy (every dark ground) | linear, (0.12,0) to (0.88,1): #173A4B at 0%, #0C2330 at 55%, #06121B at 100% |

The gradient's teal mid-stop is #16B8A6; the canonical flat token is #14B8A6. Use the token for flat fills and the gradient for the artwork. Retired hexes that must not reappear: #0d9488 and #2DD4BF (Tailwind teals), #5EEAD4, #E7B53C and #f0c869 (old golds), #123047, #8FB0C0 and #9fb2bd (old greys), #15181d, #64748b.

## Contrast (measured 6 September 2026)

WCAG 2.1 ratios computed from the hexes above with the relative-luminance formula. AA is 4.5:1 for normal text and 3:1 for large text (18 pt, or 14 pt bold) and UI components; AAA is 7:1.

### Text on white #FFFFFF

| Pair | Ratio | Grade |
|---|---|---|
| Ink #0A0A0A on white | 19.8:1 | AAA |
| Navy #0C2330 on white | 16.2:1 | AAA — the body text colour |
| Surface #123041 on white | 13.8:1 | AAA |
| Teal deep #0B8276 on white | 4.7:1 | AA — links and small teal text |
| Gold deep #BD8E36 on white | 3.0:1 | large text and UI components only |
| Faint #7C97A3 on white | 3.1:1 | large text only |
| Teal #14B8A6 on white | 2.5:1 | decorative only |
| Muted #9DB2B2 on white | 2.2:1 | decorative only |
| Gold #E3C065 on white | 1.8:1 | decorative only |

### Text on navy #0C2330

| Pair | Ratio | Grade |
|---|---|---|
| White on navy | 16.2:1 | AAA |
| Paper #EAF4F2 on navy | 14.4:1 | AAA — the body text colour on dark grounds |
| Gold light #F6DD8C on navy | 12.0:1 | AAA |
| Teal light #6EE7D4 on navy | 10.8:1 | AAA — links and the tagline |
| Gold #E3C065 on navy | 9.2:1 | AAA — totals and highlights |
| Muted #9DB2B2 on navy | 7.3:1 | AAA — secondary text |
| Teal #14B8A6 on navy | 6.5:1 | AA |
| Gold deep #BD8E36 on navy | 5.5:1 | AA |
| Faint #7C97A3 on navy | 5.2:1 | AA — tertiary text, the floor |
| Teal deep #0B8276 on navy | 3.4:1 | large text only |

### Text on paper #EAF4F2 and on surface #123041

| Pair | Ratio | Grade |
|---|---|---|
| Navy on paper | 14.4:1 | AAA |
| Ink on paper | 17.6:1 | AAA |
| Teal deep #0B8276 on paper | 4.2:1 | large text only — on paper, links are navy and underlined, not teal |
| Paper on surface | 12.3:1 | AAA |
| Teal light on surface | 9.2:1 | AAA |
| Gold on surface | 7.9:1 | AAA |
| Muted on surface | 6.2:1 | AA |
| Teal on surface | 5.5:1 | AA |

### Labels on the two accent fills

| Pair | Ratio | Grade |
|---|---|---|
| Navy #0C2330 on teal #14B8A6 | 6.5:1 | AA — the primary button label |
| Ink #0A0A0A on teal | 8.0:1 | AAA |
| White on teal | 2.5:1 | fails — never white text on a teal button |
| Navy on gold #E3C065 | 9.2:1 | AAA — the destructive and highlight button label |
| White on gold | 1.8:1 | fails |

## Typography

| Face | Where | Rule |
|---|---|---|
| Poppins Bold 700 | The wordmark, every headline inside brand artwork, social cards (marketing_image renders it) | The brand display face. "QuotesDone" is always one word, camel-cased, never spaced or hyphenated in running text |
| Poppins Medium, uppercase, +0.30 em tracking | The tagline UAE SOURCING MARKETPLACE; "QUOTES DONE" on the square master | Teal light #6EE7D4 on navy, centred under the lockup |
| Plus Jakarta Sans 400–800 | Website and OS body text (`--font-body`) | Self-hosted in `public/fonts`; the product face, not a substitute for Poppins in artwork |
| Space Grotesk 300–700 | Website and OS headings (`--font-head`) | Weight 600 for h2/h3 |
| JetBrains Mono | Figures, codes, tables in the OS (`--font-mono`) | Latin only: never for Arabic |
| Tajawal 400/500/700/800 | The /ar locale (Arabic file for letters, Latin file for digits) | Arabic headings, body and mono all resolve to Tajawal |
| Arial, Helvetica, sans-serif | Every transactional email | Web-safe on purpose; no webfont loads in mail |
| Helvetica / Helvetica-Bold | Reports (report_pdf, pdf-lib standard fonts) | Kept standard so the CI check can read the text back with a plain parser |
| Sora + Arabic TTF | Quotation and document PDFs (pdf_native; `brand` bucket qd_sora_*.ttf, qd_ar_*.ttf) | Bilingual documents |

### Type scale

One ladder shared by web, mail and PDF, in px: 12, 14, 16, 18, 22, 28, 36, 48, 64. Line height 1.6 for body, 1.15 for display. Web body is 16 px; mail body is 15 px at 1.6; headline tracking is +0.04 em for uppercase eyebrows and section labels.

PDF sizes (points): 8.5 tables, 9.5 body, 10.5 h3, 14 section title, 22 document title on the cover, 8 footer, 7 licence line.

## Buttons, links and states

| State | Primary | Secondary | Destructive |
|---|---|---|---|
| Rest | Teal #14B8A6 fill, navy #0C2330 label, 10 px radius | Transparent, 1 px teal-light #6EE7D4 hairline, paper label | Gold deep #BD8E36 fill, navy label |
| Hover | Teal light #6EE7D4 fill | Hairline brightens to teal #14B8A6; label white | Gold #E3C065 fill |
| Focus (keyboard) | 2 px teal #14B8A6 outline, 3 px offset (globals.css `:focus-visible`) | same | same |
| Active / pressed | Teal deep #0B8276 fill, paper label | Surface #123041 fill | Gold deep, 90% |
| Disabled | 40% opacity, no hover change | same | same |

Links: on white, teal deep #0B8276, underline on hover; on navy, teal light #6EE7D4; on paper, navy and underlined. Never brand teal #14B8A6 as link text on white — it is 2.5:1. Never white text on teal. The site's `a:focus-visible` outline is the shared focus rule for every control.

## Email layout

Two wrappers live in `public.templates` (`email_customer`, `email_supplier`); `send_outbox` renders every message through them and through its own internal-report template. Rules:

- Page ground #F6F7F9 (customer) or #EEF1F4 (supplier); one white card, 1 px #E5E7EB border, 12–14 px radius, 560–600 px wide.
- Header: the mark at 34–44 px (`email_logo_url`, the kit's PWA_192) and the wordmark as text — navy "Quotes" + teal "Done" on white; white "Quotes" + teal-light "Done" on the supplier wrapper's navy header band.
- Font stack Arial, Helvetica, sans-serif; body 15 px / 1.6; `dir="auto"` and `unicode-bidi: plaintext` on the body so Arabic replies render right-to-left without a second template.
- Links and section headings teal deep #0B8276. Section headings (internal reports) are UPPERCASE, 13 px, bold, +0.04 em.
- The supplier CTA is a teal #14B8A6 block with a navy #0C2330 label (6.5:1), never white text. Gold #E3C065 is the 4 px accent rule under the header and the 52 px rule above the signature.
- Signature: name (navy, bold), title + ", QuotesDone", channel address, quotesdone.com. Internal mail carries the INTERNAL badge; every external mail carries the unsubscribe line and "QuotesDone · Dubai, UAE".
- No images beyond the logo; no webfonts; nothing that needs JavaScript. Say "smart engine", never "AI", in anything a customer or supplier reads.

## PDF layout (reports)

`report_pdf` renders every board, executive and finance report deterministically (pdf-lib, standard fonts, no model call) into the private `reports` bucket; the OS Reports panel signs the URL on demand.

- A4 portrait, 595 x 842 pt, 48 pt margins.
- Cover: 260 pt navy band, the OnDark lockup 46 pt high at top-left, a 70 x 2 pt gold rule, "Corporate report", the title in Helvetica-Bold 22 white; below the band the meta block (period, kind, generated at, prepared by, classification) and the summary with a teal marker.
- Running header on every other page: 40 pt navy band, the OnDark lockup 22 pt high, the document title right-aligned in 9 pt paper-tint.
- Sections: a 3 x 16 pt teal marker, numbered title 14 pt navy bold; h3 10.5 bold navy; body 9.5 ink; bullets with a teal bullet glyph.
- Tables: 8.5 pt, navy header row with white text, zebra rows #F6F7F9, totals row under a navy rule; money as AED 1,250.00; a cell that starts with a hex colour draws its swatch.
- Charts: rectangles only — positive bars teal, negative bars gold, muted axis labels.
- Footer on every page: a hairline, "Confidential — QuotesDone" left, kind · period · generated centre, "Page x of y" right, and the licence line "quotesdone technologies · DET Trader License no. 1633275 · Dubai, UAE" in 7 pt.
- A table of contents is inserted when the report has three or more sections.
- Text is WinAnsi: Arabic strings are replaced by "[Arabic]" in report PDFs; bilingual documents use pdf_native with the Sora + Arabic faces.

## Social

### Avatars (one square for every platform)

| Platform | Size | File |
|---|---|---|
| Master | 1000 x 1000 | `kit/01_Social_Avatars/avatar_Universal_Master_1000x1000.png` |
| LinkedIn | 400 x 400 | `avatar_LinkedIn_400x400.png` |
| Instagram | 320 x 320 | `avatar_Instagram_320x320.png` |
| Facebook | 500 x 500 | `avatar_Facebook_500x500.png` |
| X | 400 x 400 | `avatar_X_Twitter_400x400.png` |
| YouTube | 800 x 800 | `avatar_YouTube_800x800.png` |
| WhatsApp | 640 x 640 | `avatar_WhatsApp_640x640.png` |
| TikTok | 200 x 200 | `avatar_TikTok_200x200.png` |
| Threads | 400 x 400 | `avatar_Threads_400x400.png` |
| Pinterest | 280 x 280 | `avatar_Pinterest_280x280.png` |
| Google Business | 250 x 250 | `avatar_GoogleBusiness_250x250.png` |

### Covers and headers

| Platform | Size | File |
|---|---|---|
| LinkedIn personal | 1584 x 396 | `kit/02_Social_Covers/LinkedIn_Personal_Cover_1584x396.png` |
| LinkedIn company | 1128 x 191 | `LinkedIn_Company_Cover_1128x191.png` |
| Facebook | 820 x 312 | `Facebook_Cover_820x312.png` |
| X | 1500 x 500 | `X_Twitter_Header_1500x500.png` |
| YouTube | 2560 x 1440, safe area 1546 x 423 centred | `YouTube_Channel_Art_2560x1440_safe1546x423.png` |

### Posts

| Platform | Size | File |
|---|---|---|
| Instagram / LinkedIn square | 1080 x 1080 | `kit/03_Social_Post_Templates/Instagram_Square_Post_1080x1080.png` |
| Instagram portrait | 1080 x 1350 | `Instagram_Portrait_1080x1350.png` |
| Story / Reel / TikTok | 1080 x 1920 | `Story_Reel_TikTok_1080x1920.png` |
| Landscape (X, LinkedIn, Facebook) | 1200 x 675 | `Landscape_Post_1200x675.png` |
| Link preview (og:image) | 1200 x 630 | the site's own og image, same navy gradient and lockup |

The in-house card renderer (`marketing_image`) makes every post image without an external model: 1080 x 1080, navy gradient, a 14 px teal-to-gold rule on the left, the mark top-left, a Poppins Bold headline (up to 48 characters, centred), a teal-light #6EE7D4 eyebrow, and the footer "QuotesDone" + quotesdone.com in muted #9DB2B2. Captions follow the voice rules below; hashtags at most three; no emoji in LinkedIn copy.

## Web and app icons

| Item | File |
|---|---|
| Browser tab | `kit/04_Web_App_Icons/favicon.ico`, `favicon_16/32/48/64` |
| iPhone home screen | `AppleTouch_180_180x180.png` |
| Installable web app | `PWA_192_192x192.png`, `PWA_maskable_512_512x512.png` (safe zone: the centre 80%) |
| Store listing | `AppStore_1024_1024x1024.png` |
| Mark without background | `mark_transparent_1024.png`, `icon_256_256x256.png` |

## Print

- Business card: 1125 x 675 px at 300 DPI with bleed (`kit/06_Print_Business_Card`). Front: white, mark + "QuotesDone" in navy, name in navy bold, title muted, email/phone/quotesdone.com in navy. Back: navy gradient, the lockup, the tagline in teal light. Edit the [ ] fields.
- Letterhead, invoices and quotations: `logo_horizontal_on_white_print.png` or the transparent print lockup, 30 mm wide minimum, top-left; the licence line in the footer.
- Send `kit/08_Vector_Source` files to any printer or IP agent first — they never blur.

## Voice and tone

- Plain, confident, specific. Short sentences. Numbers over adjectives. No hype, no exclamation marks, no emoji in business mail. Write like a competent procurement colleague, not a marketer.
- Say "smart engine", never "AI", in customer- and supplier-facing copy. Use the platform's nouns: RFQ, quote, reveal fee, top-3 comparison, verified supplier, buyer.
- The promise: real competing quotes without the enquiry becoming a lead list. The supplier stays anonymous until the buyer pays to reveal, and a supplier never sees a competitor's quote.
- Money is written AED 1,250.00. Dates are 06 Sep 2026. Percentages carry the number, not "significant".
- Never promise savings percentages or delivery times we cannot guarantee; never imply suppliers pay commission on won jobs (they do not).
- Sign-off: employee name and title, then "QuotesDone", then the channel address and quotesdone.com.

## Arabic and English (UAE B2B)

- English first. Arabic on the /ar locale, in Arabic replies, and on request — formal Modern Standard Arabic, translated by meaning, never word for word. No dialect in business copy.
- "QuotesDone", product names, URLs, email addresses and AED figures stay in Latin script inside Arabic text. Digits are Western Arabic (0–9); the site's Tajawal setup takes digits from the Latin file for that reason.
- Layouts mirror for RTL (navigation, tables, alignment, the accent rule on cards); the logo, the mark and the check never mirror. The lockup stays left-to-right on an Arabic page.
- Mail: `dir="auto"` on the body, so a reply in Arabic renders right-to-left inside the English wrapper; the signature and footer stay in English.
- Typography: Tajawal 500 for Arabic body, 700–800 for headings; never JetBrains Mono for Arabic (no glyphs); minimum 14 px on screen. Arabic headlines in artwork use Tajawal Bold in place of Poppins.
- Bilingual documents put English and Arabic side by side or English above Arabic, never interleaved sentence by sentence; the reference number, amounts and dates appear once, in Latin script.
- Register: address the reader with the formal plural; avoid transliterated English where an Arabic term exists (e.g. عرض سعر for quote, طلب عرض أسعار for RFQ, المورّد for supplier).

## Do and don't

| Do | Don't |
|---|---|
| Use the kit files by path from `public.brand_assets` | Re-export, recolour or redraw the logo |
| Navy #0C2330 text on white; paper #EAF4F2 text on navy | Teal or gold body text on white |
| Teal deep #0B8276 for links on white | Brand teal #14B8A6 as link text on white |
| Navy label on a teal button | White label on a teal button |
| Poppins Bold for headlines inside artwork | Poppins as the product or email body face |
| The navy gradient lit from the top-left | Plain blue, purple, or a flat #000000 ground |
| Real UAE trade contexts and product screens | Stock handshakes and blue corporate clip art |
| "Get three verified quotes in 48 hours" | "Revolutionary AI-powered sourcing!!!" |
| "Reveal fee: 3% of the quotation value, charged once" | "Small fee, no strings" |
| "The smart engine ranked 12 quotes; here are the top 3" | "Our AI picked the winner" |
| Arabic in formal MSA, brand name in Latin script | Machine-translated slang, a transliterated brand name, a mirrored logo |
| AED 1,250.00 · 06 Sep 2026 | 1250 AED · 9/6/26 |

## Governance

- The founder owns only the logo artwork. Every other rule is company knowledge: change it by updating the row in `public.company_brand` (colours, typography, logo rules, voice, imagery, sizes, contrast), run `select public.fn_company_self_knowledge_sync()`, and refresh this guide plus its PDF with `node scripts/brand/publish_brand_guide.mjs --publish`.
- New kit files go into the `brand` bucket under `kit/` with a `brand_assets` row (kind, platform, path, bytes, sha256, pixel size, usage).
- Brand review follows SOP 03 — Brand Review in the marketing operating knowledge; the Brand Manager (brand_mgr) signs off assets, the Graphic Designer (marketing_design) produces them.
- Any hex not in the colour table is a defect. Any email or PDF without the licence line is a defect.

## Asset index

| Use | Files |
|---|---|
| 01_Social_Avatars | 11 PNG: Universal_Master 1000, LinkedIn 400, Instagram 320, Facebook 500, X 400, YouTube 800, WhatsApp 640, TikTok 200, Threads 400, Pinterest 280, GoogleBusiness 250 |
| 02_Social_Covers | 5 PNG: LinkedIn personal 1584x396, LinkedIn company 1128x191, Facebook 820x312, X 1500x500, YouTube 2560x1440 |
| 03_Social_Post_Templates | 4 PNG: square 1080x1080, portrait 1080x1350, story 1080x1920, landscape 1200x675 |
| 04_Web_App_Icons | favicon.ico, favicon 16/32/48/64, AppleTouch 180, PWA 192, PWA maskable 512, AppStore 1024, icon 256, mark_transparent 1024 |
| 05_Logo_Lockups | horizontal OnLight / OnDark / Black_Mono transparent, on_white, on_navy (1859x460); mark_only and mark_white 1200 |
| 06_Print_Business_Card | business card front and back 1125x675 at 300 DPI with bleed; logo_horizontal on_white and transparent print |
| 07_Trademark_and_License | BRAND_SQUARE_color 2000, LOCKUP black_on_white / color_on_white / color_transparent, MARK black and colour on white and transparent 2000, ORIGINAL_approved_master 800 |
| 08_Vector_Source | mark_color.svg, mark_black.svg, mark_white.svg, brand_square_bg.svg, mark_color.pdf, mark_black.pdf |
| Root | WHERE_TO_USE.txt — the kit's own index |
