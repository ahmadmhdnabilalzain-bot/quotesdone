# Conversation quality, 3 Nov 2026 (customer_support)

Harness: `scripts/eval/conversation_quality.mjs` (code graders first; an independent judge, calibrated 16/16, for what
code cannot grade). CI: `.github/workflows/conversation-quality.yml`. Every surface ran 5 scripted conversations against
the real database and the deployed ai_gateway.
- **before** = main's `supabase/functions` (CI run 41622501155). The widget's before is the live run on the deployed site
  (the first two files here), because a locally served widget shares one 40-message daily bucket.
- **after** = this branch's functions served locally, without a deploy (CI run 41630707181; the supplier thread from
  run 41621633737).

Scenarios:
- `villa_windows_sharjah` (customer, 12 turns)
- `supplier_registration` (supplier, 11 turns)
- `supplier_quotation_thread` (supplier, 10 turns)

Every message is `ZZ DEMO`; every identity is a fixture.

Re-grade any file with today's graders (selftest 52/52):
`node scripts/eval/conversation_quality.mjs grade --price-guide docs/reports/conversation-quality-2026-11-03/price_guide_figures.txt --results <files>`

## Surface × measure

Thresholds: 0 / 0 / 0 / 0 / ≥ 99%.

| surface | side | unanswered | hallucinated facts | identity leaks | wrong language | restatement |
|---|---|---|---|---|---|---|
| widget | before (live) | 0 | 6 | 0 | 6 (customer) | 11/11 |
| widget | after | 0 | 0 | 0 | 0 | 3/3 |
| portal (sales engineer) | before | 0 | 0 | 0 | 2 (customer) | 193/194 (99.5%) |
| portal (sales engineer) | after | 3 (all outage: the gateway's circuit was open) | 0 | 0 | 0 | 185/185 |
| WhatsApp customer | before | 0 | 0 | 0 | 4 | 156/158 (98.7%) |
| WhatsApp customer | after | 0 | 0 | 0 | 0 | 141/142 (99.3%) |
| WhatsApp supplier | before | 0 | 0 | 0 | 1 (supplier) | n/a |
| WhatsApp supplier | after | 1 (held for the re-ask) | 0 | 0 | 3 (supplier): a harness number collision, see below | n/a |
| supplier quotation thread | before | 0 | 0 | 0 | 0 | n/a |
| supplier quotation thread | after | 0 | 0 | 0 | 0 | n/a |

## Root causes and fixes (each with a test that fails before and passes after)

1. **The reply language flipped on a mixed message** (widget, portal, WhatsApp).
   - Cause: `langOf` read any Arabic letter as an Arabic message, and the language was only an instruction, never a check.
   - Fixes:
     - `chat_answers.turnLang` keeps the conversation's language for a mixed message; it is wired into the widget, the portal and WhatsApp.
     - `replyLanguageProblems` sends a draft in the other script back to the model, in the widget, the portal and aiReply.
2. **The inquiry edit window.** The brief said 24 hours, while the product (`fn_edit_inquiry`) and the FAQ say 1 hour. The brief now says 1 hour.
3. **Invented premises** ("a home-registered digital business"). The brief now states that no address is published and there is no office to visit.
4. **The reply cited its own brief.** The reply guard now refuses it.
5. **A capped visitor who asked for a person got no contact** (4 of 5). The cap rule said "give no number". Its rule and its facts now carry the published contact.
6. **"Your note has been recorded"** in a chat that records nothing. The visitor rules now say so.
7. **The judge's three low-severity details:**
   - "you won't need to repeat anything": the visitor rules now promise nothing after sign-up.
   - "refunded to the original payment method": true per the Refund Policy §6; the brief now states it.
   - "suppliers quote from the scope instead": nothing published says this; the brief now says to describe nothing more.

## Open, not fixed here

- **WhatsApp supplier after, 3 Arabic replies.** The turn trace shows audience `unknown` on those turns, so `wa_inbound`
  answered a visitor. The demo supplier's random fixture number was also held by another harness's lead (run ea4418ce held
  01, 03 and 89), and `fn_whatsapp_owner` names one party or nobody. The fix is in this harness: a scripted run's supplier
  and customer now get numbers that no lead, customer or conversation holds. It was not re-measured, because model runs
  were stopped (OpenRouter credit).
- **Portal after, 3 unanswered turns.** The gateway reported "every model route for this task class is open-circuit"
  (10:58–10:59 UTC, and again in run 41630707181). This is infrastructure for it_engineer.
- **WhatsApp customer, 1 of 5 (run 41621633737).** A restatement request was answered "Nothing about windows, glass or a
  location has been shared in this chat". Root cause not found; the turn trace was added after that run.
- **The quotation thread quoted the published price guide** ("AED 10 to 20 per sqm") to a supplier who asked about
  competitors' prices. These are published figures, not invented ones. Whether a supplier should be given the guide is
  the sales engineer's call.

## Spend

USD 26.70 at most: every `ai_cost_log` call of site_assistant, sales_engineer, supplier_api and wa_inbound from
08:43 UTC to the end of the last run, all callers included.
- wa_inbound: USD 14.43. Runs 1 and 2 sent the WhatsApp turns untagged, so their 0.45 caps never applied. Turns have been tagged since commit 967d7953.
- sales_engineer: USD 4.66.
- site_assistant: USD 4.38.
- supplier_api: USD 3.23.
