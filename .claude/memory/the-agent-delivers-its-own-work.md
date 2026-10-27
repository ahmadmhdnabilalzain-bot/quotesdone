---
name: the-agent-delivers-its-own-work
description: "When testing a seat, never hand-deliver its output — the delivery IS the test"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T04:01:15.674Z
---

9 Sep 2026. I rendered the accountant's weekly report PDF myself and sent it to the founder with
SendUserFile. He said: *"i didnt want you to share the pdf. i want the agent to do that cause we
wanna test him"*.

**Why:** a report I hand over proves the renderer works. It proves nothing about the seat. The
founder is testing whether the AGENT can do its job end to end — generate, address, and deliver —
and every step I perform on its behalf is a step that stays untested. Substituting myself for the
seat makes the demo pass and the company stay broken.

**How to apply:** when the founder asks for an agent's deliverable, build the seat's own delivery
path and let it send. Show him the evidence that the seat sent it (the outbox row, the message id,
the recipient), not the artefact carried by hand. Use SendUserFile only for MY work products —
audits, findings, screenshots — never for something a seat is supposed to produce and deliver.

Related: [[quotesdone-definition-of-done]], [[connected-is-a-claim-not-a-measurement]],
[[agents-are-expert-human-staff-who-act]].
