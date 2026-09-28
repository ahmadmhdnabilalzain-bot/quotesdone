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

---

# Browser work held for Sunday 27 September 2026

*Written 24 September 2026. The founder, the same day: "all those stuff that require me doing work
on the browser, keep them till sunday as i can do them locally with claude working things on my
browser. keep that somewhere that the local session can read them".*

**For the local Claude session:** do these in the founder's own browser with him signed in. Every
value is pasted straight into `app_secrets` (the Supabase dashboard, project `htdblwldjkcgjvmqkbeh`,
table `app_secrets`, key = the name below). Never put a value into chat, a file or a commit.
Nothing here is switched on by doing it: each feature stays off until its PR is merged, its SQL is
applied and its flag is turned on. The PR named in each item carries the full detail.

## 6. A separate sending domain for supplier invitations — PR #963

1. **Resend dashboard** → Domains → Add domain `hello.quotesdone.com`, region **us-east-1** (the same
   region as the existing domains). Copy the DKIM value Resend shows.
2. **GoDaddy** → quotesdone.com → DNS → add:

   | Type | Host | Value | Priority |
   |---|---|---|---|
   | MX | `send.hello` | `feedback-smtp.us-east-1.amazonses.com` | 10 |
   | TXT | `send.hello` | `v=spf1 include:amazonses.com ~all` | – |
   | TXT | `resend._domainkey.hello` | the DKIM value from step 1 | – |
   | TXT | `_dmarc.hello` | `v=DMARC1; p=none; rua=mailto:management@quotesdone.com` | – |

   If Resend shows different record names or values, Resend's own screen wins — copy what it shows.
   No tracking CNAME (tracking is off on purpose).
3. **Resend** → Verify. It must read *Verified* before PR #963's flag `invite_lane_enabled` is ever
   set to `'true'`. After 2–4 clean weeks of DMARC reports, change `p=none` to `p=quarantine`.

## 7. Gmail read access for the daily inbox check — PR #966

1. **Google Cloud console**, the project that owns the OAuth client already stored as
   `google_oauth_client_id` (the YouTube one) → APIs & Services → enable **Gmail API**.
2. OAuth consent screen → add scope `https://www.googleapis.com/auth/gmail.readonly` → publishing
   status **In production** (unverified is fine for his own account; in *Testing* the token dies
   after 7 days). Add `https://developers.google.com/oauthplayground` as an authorised redirect URI
   on that client.
3. Signed in as **ahmadmhdnabilalzain@gmail.com**, consent once (OAuth Playground, "use your own
   OAuth credentials" with that client's id and secret, scope above, offline access) and exchange
   the code for a refresh token.
4. `app_secrets` → key **`gmail_seed_refresh_token`** = that refresh token.

## 8. Outlook read access for the daily inbox check — PR #966

1. **Microsoft Entra admin centre** of the **doratajewelries.com** tenant → App registrations → New
   registration (single tenant). Create a client secret.
2. API permissions → Microsoft Graph → **Mail.Read** (application) → Grant admin consent.
3. Restrict the app to the one seed mailbox (Exchange Online PowerShell, as an admin):
   `New-ApplicationAccessPolicy -AppId <client id> -PolicyScopeGroupId management@doratajewelries.com -AccessRight RestrictAccess -Description "QuotesDone inbox placement seed only"`
   (PR #966 also accepts delegated Mail.Read with a refresh token in `ms_graph_seed_refresh_token`
   instead; the application route is simpler.)
4. `app_secrets` → **`ms_graph_tenant_id`**, **`ms_graph_client_id`**, **`ms_graph_client_secret`**.

Until items 7 and 8 exist the daily check cannot read either inbox, so once PR #966 is live every
sending day is held (fail closed) — which is harmless while `invite_enabled` is `'false'`.

## 9. Google Postmaster Tools in the IT daily digest — PR #961

1. Same Google Cloud project as item 7 → enable **Gmail Postmaster Tools API** → add scope
   `https://www.googleapis.com/auth/postmaster.readonly` to the consent screen.
2. Signed in as the Google account that verified **quotesdone.com** in Postmaster Tools, consent once
   (same Playground route as item 7, this scope, offline access) and get a refresh token.
3. `app_secrets` → key **`google_postmaster_refresh_token`**. The client id and secret stay the
   existing `google_oauth_client_id` / `google_oauth_client_secret`.

Until then the digest line reads "not read" and one configuration finding stays open.

## 10. LinkedIn and YouTube for comment replies — PR #969 (optional, when he wants replies there)

Connect each channel with `node scripts/marketing/social_connect_link.mjs` (it prints the link to
open in his browser). Until connected, a held LinkedIn/YouTube comment is skipped by name and
waits; nothing fails.

## 11. The merge run for the local session (the cloud session of 24 Sep only opened PRs)

The founder, 24 Sep 2026: the cloud session follows his local-session instructions, so merging,
applying and deploying happen in the local session. **A merge to `main` deploys the changed edge
functions to production at once** (`.github/workflows/deploy-functions.yml`); the SQL does not go with
it — each PR's SQL waits in `scripts/sql/pending/<name>.txt` until applied. Every PR below was built to
be safe if its functions deploy before its SQL is applied, and none needs the Sunday items (6–10) to be
merged — those only switch features on.

Order:
1. **#968** (it_engineer, GLM 5.3 Flash price) first — every other branch carries its two commits
   byte-identically, so they merge cleanly after it.
2. **#961** (Postmaster) before **#966** (daily inbox check): both define `fn_invite_campaign_pause` and
   `fn_invite_same_day_brake` byte-identically (a check in #966 asserts it).
3. Then **#962, #963, #964, #965, #969, #898** in any order. Expected small conflicts, resolve by
   keeping both sides: #963 and #964 both edit `supabase/functions/send_outbox/index.ts`; #898 and
   #969 both edit `supabase/functions/_shared/reasoned_delivery.ts` (#898 adds TikTok, #969 LinkedIn
   and YouTube — keep all three branches in `replayHeldComment`).
4. **#967** (drawings) last, and only once its second independent review is clean.

For each PR, straight after its merge: `node scripts/apply_sql.mjs <file> --apply --ddl` for every
file in its pending notes (must print `PROBE OK`), then delete the pending note and append the file to
the END of `scripts/sql/MANIFEST.txt` in one commit. Finish with the end-of-session sweep in
`.claude/skills/quotesdone-session/SKILL.md` §9 (CI, schema mirror `--write`, deploy parity).
