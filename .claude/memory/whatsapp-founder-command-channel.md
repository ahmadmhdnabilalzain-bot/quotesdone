---
name: whatsapp-founder-command-channel
description: The founder wants to run QuotesDone by texting his registered mobile number on WhatsApp — any request he sends should be executed and answered.
metadata: 
  node_type: memory
  type: project
  originSessionId: 89075d82-5230-476c-8c2c-979664458fc5
  modified: 2026-08-10T09:32:36.559Z
---

Stated by the founder on 10 Aug 2026. He wants two founder-facing control surfaces, and WhatsApp
is the one he actually expects to use:

- **WhatsApp from his registered mobile number.** Anything he texts should be carried out and
  answered — his examples: *"print me last month's revenue"*, *"share with me what social media
  post you have for next week"*. Not a fixed command list: **any** request.
- **The Command Center**, where he can also address employees or an executive directly.

**Why:** he is a phone-first founder. A dashboard he has to open is a dashboard he will not open —
which is exactly what happened to the OS shell (see [[os-dashboard-still-basic]]). The company is
supposed to work for him, not wait for him at a screen.

**How to apply:**
- Treat this as a build target, not a preference. It was explicitly deferred — *"these things, I
  don't want you to worry about now"* — so it belongs in the automation gap analysis, not in the
  middle of another row's work.
- The inbound side must authenticate on the registered mobile number itself; see
  [[no-observe-mode-plain-login]] for the auth shape he wants.
- Requests are open-ended, so the design is a router into existing routines and knowledge, not a
  command parser with a fixed vocabulary.
