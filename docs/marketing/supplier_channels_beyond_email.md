# Supplier channels beyond email: what is built, what is safe, and what the founder holds

Seat: **marketing** (recruitment targeting with **sales_engineer**). 27 Oct 2026. Founder ledger 1184 (12 Oct): use every
safe channel beyond email so every trade has enough suppliers, and do nothing that risks a ban. Ledger 1301: no links.
Ledger 1312: the supplier campaign is **paused** until a GlockApps test shows Outlook at 80% inbox or better. Nothing in
this document was sent to anyone, and no switch was changed.

## What was measured (27 Oct 2026, production, read-only)

| Fact | Value |
|---|---|
| #1511 (WhatsApp invitation, 19 Oct) | **merged** through integration PR #1496; its SQL is MANIFEST line 2082. `wa_supplier_invite_golive = 'false'` is the founder's switch, not a missing merge |
| Callers of `fn_wa_supplier_invite_queue` | **none**: no cron job, no seat duty. Turning the switch on would have queued nothing |
| `supplier_invite` WhatsApp template | never submitted (no `messaging_template` row). Its text carried a claim link, which ruling 1301 now forbids |
| Leads with a UAE mobile | 2,863 (not demo) |
| ...that opted in to WhatsApp messages from us | **0** (`marketing_consent` 0, `wa_optin` 0, ever wrote to our number 0) |
| Leads with a LinkedIn company page on file | 1,177; 1,132 never invited |
| Leads with Instagram / Facebook on file | 2,417 / 2,247 |

## WhatsApp: built, switched off, and opt-in only

**Why opt-in is the rule.** Meta's WhatsApp Business Messaging Policy: a business may contact a person only if (a) that
person gave the business their number and (b) the business received opt-in permission confirming the person wants to
receive messages from that particular business. The permission may be general (not WhatsApp-specific), but it must name
the business. A number copied from a map listing is neither (a) nor (b). Messaging the 2,857 published numbers would
collect blocks and reports, drop the quality rating, cut the messaging limit and could disconnect the one number customer
support and the founder's alerts run on. That is the ban risk ruling 1184 excludes, so the invitation goes **only** to a
lead with an opt-in on record. Today that pool is 0, and it fills from the opt-in routes below.

**What runs** (`scripts/sql/the_supplier_whatsapp_invitation_waits_for_opt_in_both_switches_and_a_high_quality_sender.sql`):

| Gate | Where it is enforced |
|---|---|
| `wa_supplier_invite_golive = 'true'` **and** `invite_enabled = 'true'` (WhatsApp never runs ahead of the paused email campaign) | `fn_wa_supplier_invite_gate` when a row is queued; `supplierInviteGate` in `send_whatsapp` when it leaves |
| An opt-in on record (`supplier_whatsapp_optin`) | `fn_wa_supplier_invite_queue` |
| Sender quality **HIGH** and status **ONLINE** (Twilio `GET /v2/Channels/Senders`, read at most hourly) | `send_whatsapp` and the queue gate. A reading below HIGH applies the **brake** |
| STOP brake: 2 or more opt-outs **and** at least 5% of the WhatsApp invitations sent in 7 days | `fn_wa_supplier_invite_gate` |
| The brake: `it_watch_finding 'deliverability:supplier_invite_wa'` opens (it_engineer), everything queued is cancelled, and nothing more queues until a person resolves the finding. It never touches a switch | `fn_wa_supplier_invite_brake` |
| One invitation per lead **and** per number, for life. No second message is ever sent; a reply goes to a person | the queue |
| At most 20 a Dubai day, Mon to Fri 10:00 to 17:00, never on a UAE public holiday | the queue gate |
| STOP or the "Stop" button opts the lead out for good and cancels anything queued | `wa_inbound` and `fn_wa_supplier_invite_opt_out` |
| Never fails over to SMS (ruling 1185) | `send_whatsapp` |
| A demo lead's message is captured and never reaches Twilio | `zzzz_notifications_demo_capture` and `isDemoPhone` |

The hourly seat duty `marketing.whatsapp_supplier_invites` calls the queue. While either switch is off it writes nothing.

**What counts as an opt-in (founder ledger 1341, 27 Oct 2026).** Recommended to him: "count an opt-in only when the
supplier taps 'Set up my page' or answers yes to a question that asks for consent, not from any message a supplier
sends". His reply: "approved. dont ask me". So a supplier writing to us, a "who is this?", or a "yes" to anything other
than the consent question is **not** an opt-in. One routine, `fn_wa_optin_rule`, decides for every writer, and a
trigger on `supplier_whatsapp_optin` refuses any row it does not count, including a direct insert.

1. **The "Set up my page" button.** Twilio sends `ButtonPayload = 'supplier_invite_yes'`; `wa_inbound` passes it to
   `fn_marketing_files_wa_invite_reply`, which records a `wa_button` opt-in. The same words typed are not a tap.
2. **A yes to the consent question on WhatsApp.** The consent question is `fn_wa_consent_question()`, word for word:
   > May QuotesDone send you WhatsApp messages about requests for quotation in your trade? Reply YES to agree, or STOP
   > if you do not want them.

   The seat that sends it (inside the 24-hour window the supplier's own message opens) records the ask with
   `fn_supplier_whatsapp_consent_ask_record(phone, text_sent, seat)`. The **first** reply after the ask closes it. If
   that reply is a yes (`fn_wa_is_affirmative`: English or Arabic yes words plus courtesy words, no question mark,
   nothing else; code only, no model), a `wa_consent_reply` opt-in is recorded with the question and the answer.
3. **A yes to the consent question by email or on a call.** The sales engineer records it with
   `fn_supplier_whatsapp_optin_record(lead_id, 'email_consent_reply' | 'call_consent_reply', question_asked, answer)`.
   It is refused unless the question carries the consent question and the answer is a yes.

Any WhatsApp message from an invited lead with no company page still becomes an `invite.reply` handoff to the sales
engineer (`opted_in` says whether it counted), the same conversation an email reply starts. No cold messages are sent
to collect opt-ins.

**The template (draft, not submitted to Meta).** It is MARKETING category, English only, with no link, one variable,
and two quick-reply buttons: **Set up my page** and **Stop**. Its source is
`supabase/functions/_shared/marketing_send_gate.ts` `WA_INVITE_TEMPLATE_EN`:

> Hello from QuotesDone. We connect companies in the UAE with qualified suppliers: each request for quotation reaches
> only the suppliers registered for that exact trade. We are now onboarding {{1}} suppliers ahead of our buyer launch.
> Requests that match your trade come directly to you, you choose which ones to quote on, and there is no commission on
> work you win. Registration is free for our first 1,000 suppliers. To join, reply with the trades you cover and our
> team will set up your company page for you, or register at quotesdone.com. If this isn't relevant, reply STOP and we
> won't message you again.

To submit it when the go comes: `wa_template_setup` with `{"action":"create","key":"supplier_invite","language":"en"}`.
Templates are Claude's to submit, never the founder's.

## LinkedIn

| Action | Safe? | How |
|---|---|---|
| Scraping profiles or search results, or browser automation (auto-connect, auto-DM, auto-visit) | **No.** The LinkedIn User Agreement forbids scraping, bots and automated messaging, and accounts are restricted for it | not built and never will be |
| Posting on the QuotesDone company page | Yes. LinkedIn's Community Management API covers it | already runs through Postiz on the monthly calendar (one-shot approval, no weekends or holidays) |
| Messaging a company from our own account, by a person | Yes, within LinkedIn's weekly invitation limits | the daily target list below; a person sends, with no link in a first message |
| Sponsored content or lead-gen forms aimed at UAE trade owners | Yes. A lead-gen form with a consent line is also a WhatsApp and email opt-in | needs an ad budget and the founder's ad account |

**Built:** `fn_marketing_supplier_outreach_targets(3)` is the seat duty `marketing.manual_outreach_targets`, run daily.
For each of the 15 thinnest trades in marketing's gap ranking, it lists 3 suppliers that have never been invited, are
not suppressed and have not opted out, each with the LinkedIn, Instagram or Facebook page we already hold. It contacts
nobody. Read it in `seat_duty.last_result`.

**Company page post plan.** These are English recruitment posts with no "AI" and no licence number. They go through the
existing monthly calendar approval, one a week on a working day.
1. "Every request on QuotesDone reaches only the suppliers registered for that exact trade. If you supply or install in
   the UAE, your company page is free for our first 1,000 suppliers."
2. "No commission on work you win. You choose which requests to quote on. That is the whole deal for suppliers."
3. A trade spotlight on the thinnest trade of the week (from the target list): "We are onboarding <trade> suppliers
   across the UAE. Message us here and our team sets up your page."
4. "How a request reaches you: a buyer posts, we match the exact trade, you quote. Message the page to join."

## Other channels

| Channel | Safe use | Status |
|---|---|---|
| Instagram / Facebook DMs | Only replies to people who wrote first (Meta's messaging window). Cold DMs from the API are not allowed | inbound is handled by marketing (rule 641); manual follow-up uses the target list |
| Google Business Profile posts | Yes: "Suppliers: register free" posts | needs the GBP owner login |
| UAE business directories and trade associations (Dubai Chamber events, trade groups) | Yes, as a listing or by a person attending | manual; no automation |
| Bulk SMS | Not now (ruling 1185: too expensive) | not built |
| Apify or other scraping for new leads | Paused until about Feb 2027 (founder, 10 Aug); never logged-in LinkedIn scraping | not built |

## What needs the founder (exact list)

1. **The go**, unchanged: `invite_enabled` (after GlockApps shows Outlook at 80% or better) and then
   `wa_supplier_invite_golive`. Nobody else changes either switch.
2. **Nothing for the WhatsApp template.** It is Claude's to submit (`wa_template_setup`) when the go comes.
3. **LinkedIn:** admin access to the QuotesDone company page for whoever sends the manual messages, and his decision on
   any **LinkedIn Ads** budget. Lead-gen forms need the founder's ad account and a payment method.
4. **Meta ads** (optional): a click-to-WhatsApp or lead ad budget on the existing Meta ad account. It is the fastest
   compliant way to collect WhatsApp opt-ins at volume.
5. **Google Business Profile:** the owner login, if posts there are wanted.

No other permit is needed. Every channel here is the company's own account, used by hand or through an API the platform
offers for that purpose.

Sources: [Meta, Get opt-in for WhatsApp](https://developers.facebook.com/documentation/business-messaging/whatsapp/getting-opt-in);
[360dialog, opt-in](https://docs.360dialog.com/docs/messaging/overview/opt-in);
[Twilio, WhatsApp Senders API (quality_rating)](https://www.twilio.com/docs/whatsapp/api/senders).
