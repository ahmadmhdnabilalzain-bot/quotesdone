---
name: the-registration-walk-reads-the-real-code-through-a-resend-sink
description: "28 Oct 2026: the supplier registration walk can use the REAL e-mail code (--real-otp): delivered+qd-<tag>@resend.dev, read back through pg_net. Also: replies to supplier@ were never answered (internal rule) until #1699."
metadata:
  type: project
  modified: 2026-10-28
---

**Real OTP without a real inbox.** `scripts/e2e/supplier_registration_walk.mjs --real-otp` types
`delivered+qd-<tag>-sup<n>@resend.dev` (Resend's own sink: accepted, recorded delivered, dropped) into the real form and
reads the code back from Resend's API **through pg_net** (`scripts/e2e/resend_sink.mjs`). The cloud container cannot reach
api.resend.com (proxy 403), and no disposable-inbox API is reachable either (mail.tm, 1secmail and mail.gw were all
refused, 28 Oct). Keep the lead `ZZ DEMO` + `@example.invalid`; only the ACCOUNT is the sink. The seat clock then refuses
the approval mail to the sink, and that refusal is correct.

**Replies to the invitation were never answered (fixed in #1699, deployed 28 Oct).** `customer_mail.ts` listed supplier@
as internal, so `noAutoReply` returned `internal` for every reply to an invitation. Since 6 Oct, the M365 lane has sent
with no Reply-To, so every reply lands in supplier@. `invitationReplyAnswerable` now answers a lead's reply, and the
answer carries the lead's own `/portal?t=` link. To re-check, run `node scripts/e2e/invitation_reply_probe.mjs`. It goes
through the real M365 hand-off: Svix-signed, `m365:` id, EOP Authentication-Results. On 28 Oct it passed 6/6 and the
answer took 141–172 s.
**A reply probe touches the support tables too.** email_triage's support wiring creates `support_customer_profile` +
`support_case` for the sender. The first probe's clean-up missed them. Clean them, then scan every e-mail column.

**Harness traps at 390 px:** `navigation.first()` is the site header, and `input[type=file]` nth(n) differs by width.
Find the strip by "Inquiries received" and each upload by its card heading. Playwright actions have no default timeout:
`setDefaultTimeout`, or a hung leg is killed before teardown and leaks fixtures. Purge with `run.mjs --purge-tag`.
A clipped overflow keeps `documentElement.scrollWidth` equal to the viewport, so test the buttons' rects instead.

**Preview builds cannot run the portal flows:** edge functions send no CORS headers to `*.vercel.app` preview
origins. On a preview, stub only the call you need (route regex, because the URL carries `?forceFunctionRegion`).

Related: [[supplier-campaign-sends-from-supplier-at-quotesdone-com]], [[a-killed-check-leaks-its-fixtures]].
