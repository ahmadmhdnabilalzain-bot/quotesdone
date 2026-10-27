---
name: checkpoint-19-oct-campaign-on-pr-drain
description: "READ FIRST on resume after 19 Oct 2026 — campaign switched on from 20 Oct, PR drain state, exam scores, open fixes"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-19T14:17:27.234Z
---

19 Oct 2026 (weekly usage ~91%; founder: keep going until the limit is fully used, then resume next week).

**Campaign:** founder ruled "turn the campaign on. from tomorrow onwards." First invites Tue 20 Oct (Dubai business hours). Caps per ruling 1231: 20/day, 30 from 26 Oct, 40 from 2 Nov, 50 from 9 Nov. The ceo-seat agent was switching it; verify the switch read-back, the outbox delivery proof, and that unsubscribe is deployed (#1549).

**20 Oct morning check (Dubai):** sender switched to supplier@quotesdone.com (founder 1274/1275). At ~09:15 read `invite_placement_check` for 2026-10-20 — both seed ids present; by ~09:30 a folder per inbox; verdict "inbox" → batch 10:00–17:00. "unread"/"not_found" at 12:00 = batch held. The M365 vs Resend lane must follow the GlockApps trial results (founder: "you used my glockapp trial also"). No production applies 08:30–17:00 Dubai on campaign days.

**Merged/live today:** #1567 + #1569 (internal facts, seat notes and unreviewed research are never shown to customers or suppliers), #1566 (31 PRs).

**PR drain:** 68 open, 49 approved. Integration round 5 (~40 PRs) CI running; serial merges #1577, #1531 (then apply the ruling-1260 file with founder:1260), #1573, #1576, #1572, #1439, #1548, #1392, #1580, #1581. Changes requested, fixers pending: #1370, #1369, #1193, #1182. #1575/#1574 changes requested. #1483 merges only if its 3 blind runs show 0 wrong.

**Exam 3 (real models):** ceo 65%, accountant 60%, it 53%, cs 49%, se 46%, marketing 36%. Target 90%. Main cause: grounding (the seat hedges on facts in its own pack), plus 23 gateway timeouts. The ceo agent is on the grounding fix + the market-pack ranking/multilingual-embedding fix (37 packs lose on ranking; Arabic recall ~0). Answer-key fixes in #1579.

Open founder decision: a multi-trade supplier who ticks services in only one trade — match in the other, ranked lower? (Currently exact-or-none, rule 438/439.)

Related: [[checkpoint-6-oct-evening-prelaunch]], [[openrouter-stays-on-all-tests-with-ai]]
