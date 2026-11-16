---
name: whatsapp-opt-in-is-the-button-or-a-yes-to-consent
description: "A supplier's WhatsApp opt-in counts only for the 'Set up my page' button or a yes to the consent question or the WhatsApp offer, read by a MODEL (16 Nov: no keyword); never for a message they send (27 Oct 2026, instruction 1341)"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-16T18:00:00.000Z
---

# A WhatsApp opt-in is the button or a yes to the consent question (27 Oct 2026, instruction 1341)

**Recommended to him, 27 Oct 2026 about 14:35 UTC:** "count an opt-in only when the supplier taps 'Set up my page' or
answers yes to a question that asks for consent, not from any message a supplier sends".
**His reply, verbatim:** "approved. dont ask me".

**Why:** the first build of PR #1634 recorded any non-STOP message from a lead's number as an opt-in. A "who is this?"
would then have opened that number to a marketing template. Meta allows a template only to a person who opted in, and
messages to people who did not are what lowers the sender's quality rating (ruling 1184: nothing that risks bans).

**How to apply:**
- One routine decides: `fn_wa_optin_rule(source, button_payload, question, answer)`. Every writer calls it
  (`fn_marketing_files_wa_invite_reply` from wa_inbound, `fn_supplier_whatsapp_optin_record` for email and calls), and
  the trigger `a00_supplier_whatsapp_optin_obeys_the_rule` refuses any other row, a direct insert included. Never add
  a writer that bypasses it, and never widen the source list.
- (a) Button: Twilio `ButtonPayload = 'supplier_invite_yes'` (`WA_INVITE_BUTTONS` in `_shared/marketing_send_gate.ts`).
  Typed words are not a tap.
- (b) Consent: the question is `fn_wa_consent_question()` word for word, or (16 Nov 2026) the offer `fn_wa_job_request_offer()`
  that every invitation and every e-mail reply to a supplier now carries. On WhatsApp, record each ask with
  `fn_supplier_whatsapp_consent_ask_record`; the first reply after it closes it, so a later "yes" to something else
  never counts.
- **16 Nov 2026 (L2_OPTIN, rulings 1663/1664 supersede the 27 Oct "yes is code"):** the YES is read by a MODEL, never a
  keyword. The rule is `fn_wa_optin_counts(source, payload, question, answer, read_by)`: a consent reply counts only when
  the message answered carried the question or the offer (a fact) AND a model read the answer as a yes (`read_by` names it).
  E-mail: the supplier-mailbox reading returns `whatsapp_yes` in the same call. WhatsApp: `wa_inbound` reads the reply to an
  open ask (`readConsentReply`) and puts its model on the ask (`fn_supplier_whatsapp_consent_read`). `fn_wa_optin_rule` is
  kept with the same signature (no overload: a replay of the 27 Oct file must never make a call "not unique") and answers
  with no reader. `fn_wa_is_affirmative` has no caller. The model only classifies; the reply is still the reply model's.
- An e-mailed yes is PENDING until the supplier sends the 8-digit code from his WhatsApp (`fn_supplier_whatsapp_optin_confirm`);
  only a confirmed number opens job requests on WhatsApp (`fn_supplier_job_request_whatsapp`, read by a03 and trg_wa_fanout).
  docs/marketing/supplier_channels_beyond_email.md.
- It is a policy call that was his. Do not re-ask it, and do not loosen it to grow the opt-in pool.

Related: [[whatsapp-supplier-invites-need-an-opt-in]], [[founder-rulings-are-the-holy-book]].
