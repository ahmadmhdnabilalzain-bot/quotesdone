---
name: an-order-is-a-conversation-until-its-outcome
description: "16 Nov 2026, founder (\"how do they talk to each other?\"): every plan order is a thread on its ceo.order hand-over: the seat's plan with its own tools, the CEO's answer, check-ins at milestones, a retro, the CEO's next decision and a lesson every seat reads; turns are held questions of the seat that speaks, checked by code"
metadata:
  type: project
---

Founder, 16 Nov 2026, about the CEO's order to the it_engineer (Microsoft inbox >= 80% by 8 Dec): "What will the IT do? What
if he can't? How do they talk to each other? How do the CEO conclude what to do next? ... every agent is working on his own."

**How an order runs now (scripts/sql/an_order_is_a_conversation_until_its_outcome.sql, duty ceo.order_threads hourly):**
- The thread IS the ceo.order hand-over (path plan or thread); `seat_order_thread` holds its state, `seat_order_turn` every turn.
  No parallel system: a turn is a held question of the speaking seat (`<seat>.order_plan|status|retro`,
  `ceo.order_answer|response|next`), reasoned by the one replay, applied by `fn_order_turn_applies`.
- Plan within 12 h (steps only with tools in `seat_capability`; needs; milestones) -> CEO answer (accept / adjust / withdraw +
  actions pull_in, commission, engineer_test, set_volume, adjust, spend) -> check-in at each milestone (behind: seat status +
  CEO response) -> retro at the end -> CEO next (close_met only on a met measure, extend once, replan, reassign, drop) + lesson to
  `seat_case_memory`, the pool (`order.lesson`) and every later turn.
- Every turn passes the plan bet's checks (`fn_order_text_refusals`: founder ask, refused acts, addresses; limits; message gates).
  A refused turn goes back once with its reasons; the second refusal blocks the thread, said in the founder's summary.
- think() learned `decision.authored`: an order turn's fields are the seat's own writing, asked beside the choice, with no
  verbatim evidence demanded (a reader's fields still need it). Before this, a held question with options AND fields never
  asked the model for the fields, and the validator refused any field without quoted evidence: check `fn_ambition_ask_fields`
  users (ceo_revision, experiments) if their fields come back empty.
- What only the Claude Code engineer session can do is `engineer_session_request` (capability build, GlockApps re-test;
  ruling 1344): done only with evidence (a decided test recorded after the request; a PR), and a done build flips the tool to
  available in the register.
- The founder's example, honestly: the it_engineer can read recorded verdicts, the sender readings (DNS read-only), the seed
  check, the transport rule and the M365 lane; it cannot run GlockApps, write DNS or warm up alone, and the M365 lane carries
  no replies (a build). So its plan is "partly" and the CEO files the re-test, the volume and the sales engineer's sub-order.

Related: [[the-ceo-plans-every-week-and-code-checks-every-order]], [[the-ceo-decides-inside-limits-held-as-data]],
[[the-invitation-gate-reads-the-glockapps-verdict]], [[the-llm-understands-code-only-checks]].
