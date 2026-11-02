---
name: exchange-strips-list-unsubscribe-post
description: "27 Oct 2026: mail sent through the M365 lane (supplier@) arrived with List-Unsubscribe (https + mailto) but WITHOUT List-Unsubscribe-Post; Exchange strips it. FIXED 27 Oct 23:35Z: the transport rule 'QuotesDone supplier@ one-click unsubscribe' was created by it_engineer exo_transport_rule_apply and read back; the header at the recipient is not yet re-measured (GlockApps only, never his inboxes)."
metadata:
  type: project
  modified: 2026-10-27
---

Measured on 27 Oct 2026: test notification 112440 was sent from the M365 lane (`send_outbox/m365_lane.ts`) to Gmail.
It landed in Primary with no winmail.dat (TNEF had been fixed earlier that day: Remote domains → Default →
rich text Never). `List-Unsubscribe` carried the https link and `mailto:unsubscribe@mail.quotesdone.com`, but
`List-Unsubscribe-Post: List-Unsubscribe=One-Click` was missing, although the MIME we build includes it.

**Why:** Exchange Online rebuilds the header set on submission and drops List-Unsubscribe-Post. Gmail/Yahoo
bulk-sender rules expect one-click unsubscribe, so this costs deliverability before invitations resume.

**Can the app make the rule itself? (27 Oct, it_engineer.)** No record in the repo history (shallow from 21 Sep),
docs/reports, this memory folder or `public.founder_instruction` shows Exchange.ManageAsApp or an Exchange
Administrator role on the M365 app. The only measurements of its rights are Graph: Mail.Send read back on Entra
(ledger 1115, 5 Oct) and token roles Mail.Read / Mail.ReadWrite / Mail.Send (commit d2b616558, 18 Oct). A Graph
token cannot show Exchange rights, so `it_engineer` gained two service_role-only actions
(`supabase/functions/it_engineer/exo_transport_rule.ts`): `exo_roles` reads the roles of a token for
`https://outlook.office365.com/.default` and, if Exchange.ManageAsApp is there, runs a read-only Get-TransportRule
(the Entra role is not in any token, only Exchange's answer shows it); `exo_transport_rule_apply` creates the rule
"QuotesDone supplier@ one-click unsubscribe" through the EXO v3 InvokeCommand endpoint, idempotently. If the
probe says `missing_manage_as_app` or `missing_exchange_role`, the founder needs: API permission Office 365 Exchange
Online → Exchange.ManageAsApp (Application) + admin consent, and the Entra role Exchange Administrator on the app.

**MEASURED, 27 Oct 2026 (it_engineer, release of #1695, it_engineer v282).** The founder finished both Entra steps
at about 23:20Z. `exo_roles` at 23:34:56Z answered verdict **`ready`** at once (no propagation wait was needed):
Exchange token roles Exchange.AdminAPI.ManageAsApp, Exchange.ManageAsApp, Exchange.ManageAsAppV2, Mail.Read,
Mail.ReadWrite, Mail.Send, Organization.Read.All, Organization.ReadWrite.All, full_access_as_app; Graph token roles
Mail.Read, Mail.ReadBasic, Mail.ReadBasic.All, Mail.ReadWrite, Mail.Send; Get-TransportRule through InvokeCommand
answered HTTP 200 with **0** transport rules in the tenant. So the undocumented EXO v3 InvokeCommand endpoint works
app-only from the edge. `exo_transport_rule_apply` at 23:35:15Z answered **`created`**, and the read-back (and a
second `exo_roles` read, 1 rule in the tenant) shows: Name `QuotesDone supplier@ one-click unsubscribe`, State
Enabled, Mode Enforce, Priority 0, From `["supplier@quotesdone.com"]` (Exchange returned the address, not a display
name, so ruleDiff matched and `exists_differs` did not arise), if header `List-Unsubscribe` matches `["."]`, set
`List-Unsubscribe-Post` = `List-Unsubscribe=One-Click`. A second apply would answer `exists`.

**Not yet measured:** whether List-Unsubscribe-Post now arrives at the recipient. Re-measure with the next
**GlockApps** test of supplier@ (ledger 1312, 1344), reading the headers GlockApps reports. **Never** with a seed to
the founder's own inboxes ([[no-test-email-to-the-founders-own-inboxes]], 27 Oct 22:50Z).

**How it was to be applied by hand (superseded by the rule above, kept for the record):** the founder sets it in Exchange admin → Mail flow → Rules: if the sender is
supplier@quotesdone.com **and the message header `List-Unsubscribe` matches `.`** (it is present), set the message header `List-Unsubscribe-Post` to `List-Unsubscribe=One-Click`. The condition matters: supplier@ also sends one-to-one replies, and RFC 8058 pairs the Post header with an HTTPS List-Unsubscribe; Exchange keeps List-Unsubscribe (https + mailto arrived at Gmail), so the condition matches exactly the list mail.
