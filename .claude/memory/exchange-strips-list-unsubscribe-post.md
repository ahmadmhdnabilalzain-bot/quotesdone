---
name: exchange-strips-list-unsubscribe-post
description: "27 Oct 2026: mail sent through the M365 lane (supplier@) arrives with List-Unsubscribe (https + mailto) but WITHOUT List-Unsubscribe-Post; Exchange strips it. The fix is an Exchange transport rule, not code."
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

**How to apply:** do not chase this in code. The founder sets it in Exchange admin → Mail flow → Rules: if the sender is
supplier@quotesdone.com **and the message header `List-Unsubscribe` matches `.`** (it is present), set the message header `List-Unsubscribe-Post` to `List-Unsubscribe=One-Click`. The condition matters: supplier@ also sends one-to-one replies, and RFC 8058 pairs the Post header with an HTTPS List-Unsubscribe; Exchange keeps List-Unsubscribe (https + mailto arrived at Gmail), so the condition matches exactly the list mail. Re-measure
it with a seed send. Until that is done the opt-out is the "reply stop" line plus List-Unsubscribe.
