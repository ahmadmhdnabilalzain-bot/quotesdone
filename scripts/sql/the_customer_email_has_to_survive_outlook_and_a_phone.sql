-- THE CUSTOMER EMAIL HAS TO SURVIVE OUTLOOK AND A PHONE
--
-- The founder, 8 September 2026: "any email that the company sends need to be extremely
-- professional in a proper template."
--
-- The support agent's mail to customers is wrapped in templates.email_customer. Read side by side
-- with templates.email_supplier, which is built correctly, it has two defects that only show up on
-- the recipient's screen -- which is the only place they matter and the last place we look.
--
--   1. NO <head>. The supplier template opens with charset and a viewport meta; this one goes
--      straight to <body>. Without `width=device-width` a phone renders the mail at desktop width
--      and zooms out, so a 560px card arrives as unreadable grey text. Every customer-facing
--      message the agent sends lands on a phone first.
--
--   2. display:flex FOR THE LOGO ROW. Outlook on Windows renders with Word's engine, which has no
--      flexbox support whatsoever -- the property is not degraded, it is ignored. The logo and the
--      wordmark stack or collide. The supplier template uses tables, which is why it survives.
--      UAE B2B buyers read mail in Outlook.
--
-- Everything worth keeping is kept: the wordmark, the card, the signature block, the footer, and
-- the RTL handling (dir="auto" with unicode-bidi:plaintext) that makes an Arabic message lay out
-- correctly instead of mirroring the Latin text inside it.
--
-- {{BODY}} STAYS ESCAPED AND PRE-WRAPPED. send_outbox HTML-escapes the body before substitution, so
-- message content cannot inject markup, and white-space:pre-wrap is what preserves the line breaks
-- the agent wrote. Rendering the body as HTML would look richer and would hand anyone who can get
-- text into a notification the ability to put markup in our mail.

update public.templates
   set content = $tpl$<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>QuotesDone</title></head>
<body style="margin:0;padding:0;background:#f6f7f9;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f6f7f9;padding:24px 12px;">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;">
<tr><td style="padding:28px 28px 0 28px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle;padding-right:10px;">{{LOGO}}</td>
<td style="vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-weight:800;font-size:18px;color:#0C2330;">Quotes<span style="color:#14B8A6;">Done</span></td>
</tr></table>
</td></tr>
<tr><td style="padding:18px 28px 0 28px;">
<div dir="auto" style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.6;color:#1f2937;white-space:pre-wrap;text-align:start;unicode-bidi:plaintext;">{{BODY}}</div>
</td></tr>
<tr><td style="padding:24px 28px 28px 28px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-top:1px solid #eef0f2;padding-top:16px;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.55;color:#374151;">
<div style="font-weight:700;color:#0C2330;">{{NAME}}</div>
<div>{{TITLE}}, QuotesDone</div>
<div style="color:#6b7280;padding-top:2px;">{{REPLY}} &middot; <a href="https://quotesdone.com" style="color:#0B8276;text-decoration:none;">quotesdone.com</a></div>
</td></tr></table>
</td></tr>
</table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;"><tr><td align="center" style="padding-top:14px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#9ca3af;line-height:1.5;">
QuotesDone &middot; Dubai, UAE{{UNSUB}}
</td></tr></table>
</td></tr>
</table>
</body></html>$tpl$
 where name = 'email_customer';
