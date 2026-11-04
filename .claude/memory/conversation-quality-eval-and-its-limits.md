---
name: conversation-quality-eval-and-its-limits
description: 3 Nov 2026. scripts/eval/conversation_quality.mjs grades every chat surface by code against the canon; the widget allows 5 live conversations per IP per day.
metadata:
  type: reference
---
`node scripts/eval/conversation_quality.mjs run --surface widget|portal|whatsapp_customer|whatsapp_supplier --scenario <id> --runs 5` drives a scripted customer or supplier (quantities change, Arabic mixed in, fee/refund/identity/injection/angry/person turns) and grades each reply by code: canon figures and timelines, identity, language, restatement, deferral. `judge-packet` feeds an independent judge; `replay` re-runs code decisions on a stored run. Evidence: docs/reports/conversation-quality-2026-11-03/.

**Limits measured:** the widget gives a visitor 8 messages per conversation and 40 per IP per day (visitor_scope VISITOR_CAP), so one IP gets 5 widget conversations a day. Never forge X-Forwarded-For to get more. The portal and WhatsApp drivers need the management token; without it they print NOT RUN.

**Lesson:** the canon is the product, not the brief. company.md said a 24-hour edit window while fn_edit_inquiry enforces 1 hour; the grader first flagged the models' correct "1 hour". Check a canon figure against the code that enforces it.
