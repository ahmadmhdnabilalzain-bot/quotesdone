---
name: code-extremely-well-built
description: "Founder 14 Sep 2026 — code must be extremely well built; every helper PR gets an independent code+security review before merge. What can be coded is coded, EXCEPT understanding a document or a person, which is the model's (rulings 1663, 1664, 1666 of 12 Nov 2026: see the-llm-understands-code-only-checks)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T14:16:55.462Z
---

"the code need to be extremely well built" and "i am not saying no LLM at all. but if something can be coded then we do it" (14 Sep 2026).

**Why:** he will hand the code to an external auditor; operations must not depend on a model where rules can do the job.
He added: "not only these five helpers. it should be always" — this is permanent, every session, every PR (mine included), not a one-off for today's helpers.
**How to apply:** build helpers open PRs but never self-merge; I run an independent code review (ecc:code-reviewer / typescript-reviewer / security-reviewer / database-reviewer as fits) and the helper fixes findings before merge. Anything a rule/SQL/code can do is coded; a model is used for genuinely open-ended work (reading arbitrary drawings/documents, free-text conversation). CORRECTED 12 Nov 2026 (ledger 1663, 1664, 1666): this note used to say "code first, LLM only where code can't" in its description and "always with a deterministic fallback" here, without a limit, and sessions applied both to reading trade licences, company profiles and chats. The founder: "our rule is not code first in such thing. That's why we have LLM." Where a document or a person has to be understood the model reads and code neither interprets first nor overrides it; a code fallback that guesses meaning is not a fallback, it is the defect that refused his own valid licence. See [[the-llm-understands-code-only-checks]]. Exception he granted 14 Sep: "in the case of the boq and drawing, i dont mind using LLM to confirm the result" — coded extraction is primary; one scoped vision call (route drawing_boq_confirm, own caps, flag off until he confirms the per-drawing cost) confirms it; disagreements become customer questions. The global OpenRouter hold stays for everything else. Related: [[nothing-is-one-way]], [[always-name-the-seat]].
