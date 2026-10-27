---
name: m365-app-already-exists
description: "18 Oct — a Microsoft 365 app ALREADY exists (quotesdone.com tenant, supplier@quotesdone.com sender, M365_* edge secrets); never ask the founder to register a new Microsoft app"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-18T18:18:44.821Z
---

The quotesdone.com tenant already has an Entra app used by send_outbox's M365 lane (send as supplier@quotesdone.com; credentials are the M365_* edge secrets in m365_lane.ts, client-credentials flow). On 18 Oct I wrongly started registering a new app in the doratajewelries tenant for the Outlook placement seed; the founder: "we already made this earlier for supplier@quotesdone.com… are you losing memory?"

**Why:** asking him to redo finished setup costs his trust and his time.
**How to apply:** for any Microsoft/Outlook/Graph need, first reuse the existing M365 app (check `M365_SECRET_NAMES`, `invite_m365_mailbox`) — only if a permission is genuinely missing, give him the single "Grant admin consent" link on that existing app. Related: [[connected-is-a-claim-not-a-measurement]].
