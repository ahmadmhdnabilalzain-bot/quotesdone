-- THE MAIL GOES DARK, ON THE BRAND IT ALREADY HAD
--
-- The founder, 8 September 2026: "where is our logo? also the theme need to be dark".
--
-- THE LOGO WAS NEVER MISSING FROM THE TEMPLATE -- it was missing from my preview, where I
-- substituted {{LOGO}} with nothing. app_secrets.email_logo_url was set all along. What it pointed
-- at, though, was 04_Web_App_Icons/PWA_192_192x192.png: a 192px progressive-web-app tile. That is
-- an app icon, not an email lockup, and the brand kit's own rule says the horizontal lockup is
-- never below 120px wide. A square app tile beside a wordmark is not the lockup; it is two logos.
--
-- AND THE KIT ALREADY HAD THE DARK VARIANT. company_brand lists "OnDark (white wordmark)" among the
-- approved variants, and 05_Logo_Lockups/horizontal_OnDark_transparent.png is live in storage --
-- verified reachable, HTTP 200, 47466 bytes. Nothing needed designing. It needed pointing at.
--
-- THE PALETTE IS THE KIT'S, INCLUDING ITS CONTRAST MEASUREMENTS, which is the part that matters and
-- the part usually thrown away. company_brand records the ratios: paper #EAF4F2 on navy is 14.4:1
-- AAA, muted #9DB2B2 is 7.3:1 AAA, teal-light #6EE7D4 is 10.8:1 AAA. It also records the rule that
-- was already broken once here -- "On navy: teal-light #6EE7D4. Never brand teal #14B8A6 as link
-- text on white" -- so links go teal-light on the dark ground rather than the brand teal, which is
-- an accent and fails as text.
--
-- WHY THE LOCKUP KEEPS AN ALT AND THE WORDMARK GOES. The OnDark lockup already contains the
-- wordmark, so the HTML wordmark beside it would print the name twice. But most clients block
-- images by default, and a header that is only an image is an empty header on first open. The alt
-- text carries the name when the image does not load, which is the whole reason alt exists and the
-- reason it is not decorative here.
--
-- TABLES AND bgcolor, NOT DIVS. Outlook renders with Word, which ignores flexbox entirely and is
-- unreliable about background-color on a div. Every coloured surface below is a table cell carrying
-- BOTH the bgcolor attribute and the inline style, because the two are read by different clients.
--
-- {{BODY}} STAYS ESCAPED AND PRE-WRAPPED. send_outbox escapes it before substitution, so message
-- content cannot inject markup; pre-wrap is what preserves the agent's line breaks.

update public.app_secrets
   set value = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/kit/05_Logo_Lockups/horizontal_OnDark_transparent.png'
 where key = 'email_logo_url';

-- ---------------------------------------------------------------------------------------------
-- CUSTOMER
-- ---------------------------------------------------------------------------------------------
update public.templates
   set content = $tpl$<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>QuotesDone</title></head>
<body style="margin:0;padding:0;background:#06121B;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#06121B" style="background:#06121B;padding:28px 12px;">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="#123041" style="max-width:600px;width:100%;background:#123041;border:1px solid #173A4B;border-radius:14px;">
<tr><td style="padding:30px 30px 0 30px;">{{LOGO}}</td></tr>
<tr><td style="padding:22px 30px 0 30px;">
<div dir="auto" style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.65;color:#EAF4F2;white-space:pre-wrap;text-align:start;unicode-bidi:plaintext;">{{BODY}}</div>
</td></tr>
<tr><td style="padding:26px 30px 30px 30px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-top:1px solid #173A4B;padding-top:18px;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.6;color:#9DB2B2;">
<div style="font-weight:700;color:#FFFFFF;">{{NAME}}</div>
<div style="color:#EAF4F2;">{{TITLE}}, QuotesDone</div>
<div style="padding-top:3px;">{{REPLY}} &middot; <a href="https://quotesdone.com" style="color:#6EE7D4;text-decoration:none;">quotesdone.com</a></div>
</td></tr></table>
</td></tr>
</table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;"><tr><td align="center" style="padding-top:16px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#9DB2B2;line-height:1.55;">
QuotesDone &middot; Dubai, UAE{{UNSUB}}
</td></tr></table>
</td></tr>
</table>
</body></html>$tpl$
 where name = 'email_customer';

-- ---------------------------------------------------------------------------------------------
-- SUPPLIER. Same ground, same rules; the difference is the unsubscribe line, which suppliers get
-- because their mail can be bulk and customers' transactional mail is not.
-- ---------------------------------------------------------------------------------------------
update public.templates
   set content = $tpl$<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>QuotesDone</title></head>
<body style="margin:0;padding:0;background:#06121B;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#06121B" style="background:#06121B;padding:28px 12px;">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="#123041" style="max-width:600px;width:100%;background:#123041;border:1px solid #173A4B;border-radius:14px;">
<tr><td style="padding:30px 30px 0 30px;">{{LOGO}}</td></tr>
<tr><td style="padding:22px 30px 0 30px;">
<div dir="auto" style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.65;color:#EAF4F2;white-space:pre-wrap;text-align:start;unicode-bidi:plaintext;">{{BODY}}</div>
</td></tr>
<tr><td style="padding:26px 30px 30px 30px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-top:1px solid #173A4B;padding-top:18px;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.6;color:#9DB2B2;">
<div style="font-weight:700;color:#FFFFFF;">{{NAME}}</div>
<div style="color:#EAF4F2;">{{TITLE}}, QuotesDone</div>
<div style="padding-top:3px;">{{REPLY}} &middot; <a href="https://quotesdone.com" style="color:#6EE7D4;text-decoration:none;">quotesdone.com</a></div>
</td></tr></table>
</td></tr>
</table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;"><tr><td align="center" style="padding-top:16px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#9DB2B2;line-height:1.55;">
QuotesDone &middot; Dubai, UAE &middot; Dubai DET E-Trader Licence 1633275{{UNSUB}}
</td></tr></table>
</td></tr>
</table>
</body></html>$tpl$
 where name = 'email_supplier';
