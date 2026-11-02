---
name: whatsapp-reply-model-was-never-shown-the-conversation
description: "wa_inbound stored every turn but never passed them to the model; a voice note was treated as a licence upload (2 Nov 2026, customer_support)"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-02T00:00:00.000Z
---

# Stored is not shown (2 Nov 2026, customer_support)

Founder's check: a supplier gets a code on WhatsApp, texts the number, and the agents must carry the conversation.
Measured 14 days to 2 Nov: 40 wa_messages rows, all the 19 Oct fixture rehearsal (+971 50 000 00xx, captured, never sent),
0 real inbound; 0 WhatsApp codes (1 SMS code).

- `wa_inbound` wrote `wa_messages` and `wa_turn` for every turn but `sayFor` passed no `conversation` to `modelSays`, so
  turn 6 ("what about the second one?") reached the model alone. The 18 Oct ruling (no turn limit, whole history to the
  model) was built for the portal widget only. Now `_shared/wa_history.ts` reads this number's rows; the test is
  `wa_inbound/the_whole_exchange.test.ts` (red on the old handler, green now).
- A voice note (`audio/*` media) went down the document path and a supplier was told to send a PDF licence. It now says
  plainly it was not heard and asks for a typed message. NOTHING transcribes WhatsApp audio yet (the ogg/Gemini question in
  fn_wa_route.transcription_gap is still open): build that before saying voice notes work.
- A supplier is recognised on WhatsApp only through `fn_whatsapp_owner`: whatsapp_opt = 'same' with a verified mobile, or
  a number confirmed by `whatsapp_verify`. A mobile verified by an OTP that happened to arrive on WhatsApp (kyc `verify_sms`,
  purpose kyc_phone) does NOT set that choice, so such a supplier texting in is audience `unknown` until they choose. This is
  the consent design (rulings 1184/1341), not changed here; the founder decides whether a WhatsApp-delivered code should count.
- `mobile_otp` (customers) is SMS only; WhatsApp codes are login_otp and kyc (`_shared/wa_code.ts`).
- `wa_sender_quality_reading` has 0 rows: the sender's rating and limit are not recorded anywhere to read.
