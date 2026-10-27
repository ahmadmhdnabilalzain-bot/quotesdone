---
name: checkpoint-22-sep-marketing-seat-live
description: "READ FIRST on resume after 22 Sep 2026 — the marketing seat is live (#834-#837). Open items: meta_app_secret (founder password), Twilio ticket 29665983, marketing_golive off, prospects go-ahead, LLM-per-seat reminder"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-22T11:23:27.933Z
---

**Merged and live on 22 Sep 2026:**
- #827–#833: drawing formats, CAD redaction leak fixed, AI-spend loops, login alarm, stuck handoffs, overview warm-up, DWG note.
- #836: seat `marketing`, the sixth seat. It reports to the CEO for information only, reports ad spend to the accountant, and emails the founder with founder-mail kind `social_human_request`.
- #834: posts, Postiz publishing, insights and ad spend.
- #835: the Instagram/Facebook social inbox, function `marketing_social_inbox`.
- #837: blogs and LinkedIn outreach. The seat drafts 2–3 messages a day and the founder sends them by hand; LinkedIn's User Agreement §8.2 rules out automating this.

**Switches:** `marketing_golive` and `social_send_enabled` are OFF. Nothing posts or sends until the founder says go.

**Open items:**
- **Meta app secret:** needed for the webhook. The app is "QuotesDone automation", id 1778791833261376, business 2335064440232533. "Show" on the app secret asks for the founder's password. Once it is stored as `app_secrets.meta_app_secret`, run `node scripts/marketing/connect_social_inbox.mjs`.
- **WhatsApp templates:** the WABA does exist: id 994300166829007, approved and business-verified. The number is +1 218-316-6814 (connected, green), Twilio is subscribed, and 13 templates are approved. The templates stuck at "received" were created on or after 18 Sep, plus a test template made 22 Sep (HX8e33d4601bbe7b7210a53cb1061f5b89). Twilio support wrongly said "no WABA". I replied on ticket 29665983 on 22 Sep at 10:45Z with the evidence, and we are waiting for Twilio. Do NOT do the self sign-up. Once Twilio approves, run `every_whatsapp_notice_is_a_utility_template.mjs --switch`.
- **Real prospects:** the LinkedIn outreach prospect list needs the founder's go-ahead before real people's data is collected.
- **LLM per seat:** remind the founder about plans A/B/C (see [[next-phases-marketing-then-llm-per-seat]]).
- **Test phone number on real rows:** +971500000097 is on 2 real customer rows, found by the `a_phone_cannot_select_an_account` check. Investigate.
- **Disk:** 317 GB free. Worktrees are deleted on merge; see [[agent-worktrees-fill-the-founders-disk]].
