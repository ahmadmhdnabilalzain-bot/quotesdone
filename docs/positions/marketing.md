# Position: Marketing (the `marketing` seat)

**Created 22 September 2026 on founder instruction 721.** It is the company's sixth seat, after ceo,
customer_support, sales_engineer, accountant and it_engineer. The seat is built by
`scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql`; its runtime is
`supabase/functions/marketing/`. Its probe, `..._probe.sql`, runs every conversation below end to end on
ZZ DEMO rows.

## 1. Mandate

The seat owns how buyers and the market find QuotesDone: **SEO, social media, digital marketing, business
development and LinkedIn** (instruction 625). It does **not** invite suppliers. Supplier invitations and the
outreach campaign belong to the sales engineer, and the campaign switches belong to the founder.

Meta, ads and social are this seat's alone. No other seat's code may read their credentials (rule 641;
`scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs`).

## 2. What it does

| Duty | How | Status |
|---|---|---|
| Publish and schedule posts | Only posts the founder created or approved with Claude and ingested to the seat. They go out through Postiz and Meta on the company's own channels. | The publishing build (PR #834) adds it to `duties.ts` |
| Monitor analytics | Reads each channel's analytics and the ad platforms' reports. A figure it could not read is recorded as *not measured*, never as zero. | PR #834 |
| Report ad spend to the accountant | Calls `fn_marketing_records_ad_spend` once for each platform day. The accountant records it and answers. | Door built here; the collection is PR #834 |
| Answer the social inbox | Sends standard replies grounded in company knowledge (`fn_marketing_assist`) and carries the conversation. | The social-inbox build |
| Hand a conversation to the founder | When someone asks to speak with a person, calls `fn_marketing_asks_the_founder_to_take_over`. The founder is emailed at once, the seat stops replying on that thread, and he carries on. | Door built here; the trigger is the social-inbox build |
| Report to the CEO | Files one daily report (`marketing_report`, handoff `marketing.report`). The CEO reads it and closes it. | Built here |

## 3. Reporting line: to the CEO, for the picture, not for approval

The founder, 22 Sep 2026: it "reports to the CEO for the overall picture", not for approval.
`org_reporting_edge` links marketing to the ceo. Each day from 07:00 Dubai time, `fn_marketing_report_tick`
writes that day's report and hands it to the CEO. The CEO's handler, `fn_ceo_reads_marketing_report`,
stamps a read receipt and closes the handoff. It approves nothing and decides nothing.

The CEO's daily judgement request carries the latest report as `input.marketing`. The CEO's board
(`fn_ceo_seat_board`) shows the seat's runs, its reports, whether the CEO read them, and the ad spend
reported. The CEO's plan does not send marketing a `ceo.directive`, because the plan's funnel stages
belong to other seats.

## 4. Ad money

The seat collects the spend each platform reports and shares it with the accountant, so the accountant
knows. The loop runs like this:

1. **`adspend.recorded`** (marketing to accountant). The accountant's `fn_accountant_keeps_reported_ad_spend`
   writes the row to `ad_spend_reported` and answers.
2. **`adspend.booked`** (accountant to marketing). The answer carries what was recorded and the month so
   far. For Meta it also carries the invoiced figure.
3. `fn_marketing_notes_ad_spend_booked` checks the answer against the accountant's row.
4. `fn_marketing_closes_ad_spend_loops` closes `adspend.recorded` as its originator. If an answer does not
   match, the conversation stays open and the handoff-window duty files it to the CEO.

**The ledger entry comes from the invoice.** Meta's invoice reaches the expenses mailbox and is booked by
the existing expense path (`fn_gl_sync_business`). Booking the reported figure as well would count the
same spend twice.

**Test money never reaches the accountant's record.** Spend marked as a test, or carrying a ZZ DEMO
reference, is never written there.

The seat has no authority to start, raise or move spend. Meta ad spend is still approved by the CEO
(`accountant.meta_ads_spend`), and the founder's go-live switch still applies.

## 5. Sending: who sends what

| Channel | Who sends it | Why |
|---|---|---|
| Email and WhatsApp | `customer_support` | Support is the only sender (founder, 14 Sep 2026). The seat asks through `delivery.request` and hears back through `delivery.result`. Today it may address only the founder. Customers and suppliers are addressed by the sales engineer. |
| Replies on the company's own social channels (Instagram and Facebook DMs, comments, LinkedIn) | The marketing seat | The founder ruled that marketing owns social and that Meta is wired to no other seat (rule 641). These replies never enter the `notifications` outbox. |

## 6. The founder is emailed only for a person

`founder_mail_policy` kind `social_human_request` is allowed and owned by marketing. It is sent at once,
not held for the IT digest. It goes as email only (level medium). It is sent at most once per conversation
per Dubai day. A ZZ DEMO conversation is refused before anything is queued.

## 7. Authority

| Standing grant (active) | What it allows |
|---|---|
| `marketing.publishing` | Publish approved posts |
| `marketing.analytics` | Read analytics |
| `marketing.social_conversation` | Answer the company's social inbox |
| `marketing.ad_spend_reporting` | Report ad spend; it grants no spending authority |

Every refusal in `org_role.forbidden_decisions` is tagged with its class and names its route. The classes
are `supplier_invitations`, `publish_unapproved`, `ad_spend`, `customer_email`, `books` and
`price_or_policy`.

## 8. Company knowledge

`fn_marketing_assist` pins the company block (`fn_company_context`) on every answer, including refusals. It
retrieves from `ops_knowledge`: the growth and marketplace playbooks, plus the seat's role card
`seat:marketing:role_card`. It uses the same admission rule as the IT engineer's retrieval. With no sourced
answer, it says so and never states a fee, date or policy.

## 9. Runtime

`resilience_ping` step `marketing` runs every 30 minutes. It calls `marketing` with action `duties`, using
the seat's credential `fn.marketing`. That action runs every entry in `duties.ts` (empty until the
publishing and inbox builds add theirs), then `fn_marketing_tick`. Every call writes an `agent_runs` row
with agent `marketing`. A failing duty becomes an IT finding owned by the marketing seat
(`fn_it_duty_settle 'marketing_duties'`), and the finding reaches the seat as `it.finding`.

No model is called. The founder chooses the model per seat later.

## 10. Credentials

These credentials are measured as set on 22 Sep 2026: `meta_access_token`, `meta_ad_account_id`,
`postiz_api_key`, `postiz_publish_key` and `postiz_integrations`.

These are measured as absent:

- A LinkedIn credential.
- Anything for receiving Instagram or Messenger DMs by webhook: the Meta app secret, a webhook verify
  token, and the page and Instagram business account ids.
