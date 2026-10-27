---
name: a-comment-that-kept-a-bypass-alive
description: resend_inbound stayed the estate's last direct OpenRouter call for a month because a comment said "the gateway does not proxy image payloads yet"; the gateway had accepted multimodal `messages` since 11 Aug. Re-measure the reason a disclosed bypass gives before carrying it forward.
metadata:
  type: feedback
---

6 Sep 2026: the provider-direct register disclosed resend_inbound as a bypass with the function's
own comment as the reason (no image proxy). ai_gateway line 149/181 had taken a full OpenAI
`messages` array with image parts (inferCaps marks vision) since 11 Aug. The fix was eleven lines:
makeLlmRich with `{messages}`, a scoped credential (fn.resend_inbound), ratchet 2 -> 1.

**Why:** a disclosure entry quotes a reason once and nobody re-tests it; the reason outlived the
constraint by almost a month.

**How to apply:** when a register/ratchet carries a "because X is not possible yet" entry, test X
before accepting the entry — one grep of the gateway would have shown it. See
[[a-documented-impossibility-is-still-a-claim]] and [[the-hold-is-on-routes-the-key-is-on-twelve-functions]].
