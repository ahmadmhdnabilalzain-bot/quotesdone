---
name: a-slow-reply-holds-a-burst-is-one-turn-a-loop-stops
description: "11 Nov 2026, ruling 1636 and the founder's burst / returning-person / loop asks: where the holding line, the burst gate, the router's 'confirm' and the auto-reply loop cap live, and what is pending."
metadata:
  type: project
  modified: 2026-11-11
---

Branch it_engineer-holding-and-bursts (it_engineer). Nothing deployed or applied by that pass.

- **Holding line (ruling 1636):** `_shared/holding_notice.ts` owns the words (EN/AR) and the clock (9 s after the last
  message; web chats 8 s). WhatsApp: `wa_inbound/holding.ts`, armed once in say.ts before the model, settled by every
  sendWa and by the turn's end. It goes through the outbox duplicate guard and is recorded in notifications
  (type `wa_holding_notice`), never queued. It is a status notice, not a reply: R7 of the 1339 replies check pins it.
- **Typing indicator:** Twilio `POST messaging.twilio.com/v3/Indicators/Typing.json` `{messageId: SM…, channel:
  whatsapp}`, Public Beta; marks the message read, clears on delivery or after 25 s. Whether this account has the beta
  was NOT measured (no live call): the result is in wa_messages meta.timings.typing_at_ask after deploy. Off switch:
  app_secrets `wa_typing_indicator` = off.
- **Web chats:** the stream sends `{"t":"working"}` every 8 s until the first sentence; `src/lib/stillWorking.ts` shows
  the page's own line. A reader that left no longer breaks the answer being stored.
- **Burst:** `wa_inbound/burst.ts` turnGate (index.ts, after the arrival). The first waiting message leads; claims are
  conditional updates on wa_messages arrival rows (`meta.stage`/`meta.burst`). Setting `wa_burst_quiet_ms` (default 4000,
  0 = off). The test harness defaults it to 0; a test about it sets it.
- **Loop cap:** `_shared/auto_reply_loop.ts`: 3 of our replies in an hour with no human-sounding message between them
  stops replying and raises a finding. WhatsApp in turnGate; email in email_triage (mailLoopHeld).
- **Router 'confirm':** `_shared/support_case_memory.ts`: unsure + case quiet 7+ days → the reply asks one question naming it.
- **Pending SQL:** `whatsapp_messages_are_read_by_sender_and_time_so_a_burst_is_one_turn.sql` (index only) + probe.
