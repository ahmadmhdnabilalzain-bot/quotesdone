---
name: the-estate-could-not-email-a-file
description: Until 9 Sep 2026 no agent could attach a document to an email; notifications.attachments + send_outbox v43 fixed it
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T04:08:37.365Z
---

Measured 9 Sep 2026, when the founder asked for the accountant's weekly report "as pdf":

- `public.notifications` had 19 columns and **not one could carry a document**.
- `supabase/functions/send_outbox/index.ts` built the Resend payload as
  `{from, to, reply_to, subject, html}` — the word "attachment" appeared nowhere in its 214 lines.

So every agent that produced a document could only ever send a **link** to it. The accountant's
weekly report was being delivered as a signed URL that expires in seven days.

**Fixed:** `notifications.attachments` jsonb holds REFERENCES (`{bucket, path, filename}`), never
bytes — the object already lives in storage and a poller reads 40 rows every two minutes. Trigger
`a20_notifications_attachment_policy` RAISES (unlike `a10` founder-mail, which silently returns
null) on: a bucket outside `finance-reports, finance-docs, agent-docs, reports, compliance-docs`;
a path containing `..`; a filename outside `[A-Za-z0-9 ._-]`; more than 5 entries. `send_outbox`
v43 downloads each object with the service role, base64s it, and **fails the row rather than
sending a covering note with nothing attached** — a 20 MB ceiling enforced there because only the
sender knows the size.

Proved end to end against production: pdf_native → `finance-reports` → notification → Resend
accepted, `sent=1 attached=1`, addressed to `delivered@resend.dev` so no human received a probe.

Note: `pdf_native` **names its own path** and ignores a caller-supplied `path` — always use the
`path` it returns, never the one you asked for. The credential scoped to call `send_outbox` is
`cred_fn_resilience_ping` (`fn.resilience_ping`, scope includes send_outbox, alert_founder,
dropbox_backup, pdf_native).

Related: [[the-agent-delivers-its-own-work]], [[founder-mail-goes-through-founder-mail-policy]],
[[a-status-column-is-not-a-delivery-record]].
