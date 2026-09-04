# What only you can give the machine

*Written 4 September 2026, from what was measured on the live project that day. Everything below
is something the company cannot do for itself. Each item says where it goes, why the connectors
you attached to the Claude session do not stand in for it, and what stays switched off until you
supply it. Nothing here asks you a technical question — the engineering choices are made; these
are the keys, numbers and go decisions that are yours.*

Where a value "goes in `app_secrets`" it means one row in the `app_secrets` table of the one
Supabase project (`htdblwldjkcgjvmqkbeh`): the **key** column is the name given below, the
**value** column is what you paste. Never put a value into chat, a file, or a message.

---

## 1. The Meta key the platform itself can use

| | |
|---|---|
| **What** | A Meta system-user access token with the `ads_management` permission, made in your Business Manager for the ad account already on file (`meta_ad_account_id`, the AED account). |
| **Goes in** | `app_secrets` → key `meta_access_token` |
| **Why the session connector is not enough** | The Meta Ads connector you attached on 3 September reaches *this chat session* only. The company's own ad manager runs on the platform's clock every morning (a scheduled job inside the database, calling the platform's own Meta function) and has no way to borrow a key from a chat window. Without its own token it runs in sandbox mode: it decides, it records, it moves nothing on Meta. |
| **Until then** | The daily ad-spend manager and the daily Meta sync both run and both log an honest "disabled — no token". No campaign is switched on, no budget is raised, no spend figures are pulled in. The company's marketing reads as blind, which is correct. |

## 2. Your daily ad-spend ceiling, in AED

| | |
|---|---|
| **What** | The most the machine may put on Meta per day across all QuotesDone campaigns. A plain number, e.g. `150`. |
| **Goes in** | `app_secrets` → key `meta_daily_budget_cap_aed` (today it holds the word `UNSET`). |
| **Why nobody else can set it** | It is your money. The number that was in the code before today (200) was an engineering default, not a decision of yours, so it was moved out of the real path: while this key is not a positive number the real ceiling is **zero**. The database itself refuses any decision that would put more than this on Meta — the manager cannot exceed it, a model cannot exceed it, an operator cannot exceed it. Below your number the manager approves its own moves; above it, nothing gets through except you raising the number. |
| **Until then** | Real ceiling = 0 AED/day. Nothing is activated. The sandbox rehearsal keeps proving the manager against its own demo ceiling (26 of 26 checks on 4 September), so the day you set the number the behaviour is already proven. |

## 3. Your go switches

Three rows, each `'true'` or `'false'`, all `'false'` today. They are the company's ignition keys; the
machine reads them every time it is about to act and never flips them itself.

| Key in `app_secrets` | What it releases | What is held while `false` |
|---|---|---|
| `meta_autospend_golive` | Autonomous ad spend on real campaigns (activating, raising budgets). Needs items 1 and 2 as well — all three, or the real ceiling stays 0. | Real campaigns are left exactly as you have them in Ads Manager: not switched on, not raised, and **not paused** by the manager either. |
| `marketing_golive` | Publishing content live (social posts and the like). | Content is drafted and staged; nothing is posted. |
| `invite_enabled` | The supplier invitation emails leaving to real suppliers. | Invitations are prepared; none are sent. The supply funnel stays at its invited pool. |

## 4. Meta's approval of the WhatsApp template

| | |
|---|---|
| **What** | The template `supplier_quote_accepted` (Arabic and English) was submitted to Meta on 3 September. Meta approves templates in the Business Manager; approval arrives there, not here. |
| **Goes in** | Nothing to paste. The template ids are already on file (`wa_template_sids`); the message goes out under that id once Meta has approved it on its side. |
| **Why the session cannot do it** | Only the WhatsApp Business account owner sees and receives the approval. |
| **Until then** | Suppliers whose quote is accepted are told by **email** (proven end to end in the sandbox). The WhatsApp copy of that message waits for the template. |

## 5. A Stripe test-mode secret key (only if you want the platform to rehearse checkout by itself)

| | |
|---|---|
| **What** | The secret API key of the **QuotesDone sandbox** Stripe account (test mode). |
| **Goes in** | `app_secrets` → key `stripe_secret_key_test` |
| **What already works without it** | The live keys and the live webhook are in place and were checked on 4 September: the live endpoint is enabled, points at the platform, and is subscribed to exactly the five events the platform handles. The sandbox webhook endpoint and its signing secret are in place too, and a real test-card payment through a sandbox Payment Link was recorded by the platform on 3 September (5 of 5 checks). |
| **What it would add** | Today the platform can create a checkout page only in **live** mode — every rehearsal that needs the platform's own checkout step either creates a live session that is expired immediately, or uses a Payment Link made by hand in the sandbox. With a test key the platform could run its own reveal-and-pay step against the sandbox, card 4242…, end to end, with no hand-made link. It also lets the platform look up a **test-mode refund** whose amount is missing from Stripe's event; with the live key that lookup returns "not found" and the refund is quarantined for you to look at. |
| **One small gap you can close in the Stripe dashboard** | The sandbox endpoint is subscribed to four of the five events; `refund.failed` is missing on the sandbox only (the live endpoint has all five). Test mode → Developers → Webhooks → the sandbox endpoint → add `refund.failed`. This changes nothing live. |
| **Until then** | Nothing is blocked for real customers. Only the platform-driven test rehearsal stays manual. |

## 6. Real suppliers

| | |
|---|---|
| **What** | Suppliers who register and confirm. The invitation campaign is built and proven; it is switched off by your `invite_enabled` key (item 3). |
| **Why the machine cannot supply them** | It can invite, chase, onboard and verify; it cannot decide *that* real emails leave, and a marketplace with no confirmed suppliers matches no request. |
| **Until then** | The whole funnel — request, match, quotes, comparison, reveal fee — is proven on demo suppliers and demo customers in the sandbox (20 of 20 on 3 September). It is waiting for the first real supply. |

---

## What does *not* need you

Everything else. Model routing, org structure, authority, cron schedules, defects — those are
engineering decisions and are taken and reported, not asked. The only approval the machine will
ever hold for you is a **refund** (any amount), which is a rule of the business, not a missing key.

## The order things come alive in

1. Item 6 first: `invite_enabled` → real suppliers arrive, the marketplace can match.
2. Item 1 + 2 + `meta_autospend_golive` together: the machine starts buying demand within your ceiling.
3. Item 4 arrives on Meta's own timetable; nothing waits on it except the WhatsApp copy.
4. Item 5 is optional and only about rehearsals.
