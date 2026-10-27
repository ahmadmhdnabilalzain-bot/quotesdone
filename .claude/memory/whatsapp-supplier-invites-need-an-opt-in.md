---
name: whatsapp-supplier-invites-need-an-opt-in
description: "A WhatsApp invitation goes only to a lead with an opt-in on record. A scraped mobile is not one (Meta policy), and messaging those numbers is the ban risk ruling 1184 forbids. #1511 WAS merged."
metadata:
  type: project
  modified: 2026-10-27
---

Measured 27 Oct 2026 (marketing, PR #1634):
- #1511 (WhatsApp supplier invitation, 19 Oct) **was merged** through integration #1496. It shows on GitHub as closed,
  not merged. Read the closing comment before calling a PR unmerged.
- Of the 2,863 real leads with a UAE mobile, 0 had any opt-in. Meta's WhatsApp Business Messaging Policy allows a
  business to message a person only after the person gave the number **and** opted in to messages from that business.
  The permission can be general, but it must name us.

**Why:** cold template marketing to numbers scraped from listings collects blocks and reports. That lowers the sender's
quality rating, cuts its messaging limit and can cost the one number customer support and the founder's alerts use.
Ruling 1184 says "nothing that risks bans".

**How to apply:** `fn_wa_supplier_invite_queue` selects only leads with a row in `supplier_whatsapp_optin`. Those rows
come from a lead writing to us first (wa_inbound), from an email reply or a call (the sales engineer, through
`fn_supplier_whatsapp_optin_record`), or from the web form. Never relax this filter to make the pool bigger. To grow the
pool, collect opt-ins: click-to-WhatsApp, lead forms with a consent line, or the email reply. The invitation also needs
`wa_supplier_invite_golive` **and** `invite_enabled`, a sender reading HIGH and ONLINE, and no open
`deliverability:supplier_invite_wa` brake. Details are in docs/marketing/supplier_channels_beyond_email.md.

Related: [[a-status-column-is-not-a-delivery-record]], [[apify-paused-until-2027]], [[whatsapp-templates-are-claudes]].
