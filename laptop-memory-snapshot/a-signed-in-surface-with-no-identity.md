---
name: a-signed-in-surface-with-no-identity
description: "Ask what a surface KNOWS about its caller — site_assistant took {message, path, history} and nothing else, so 'I can't see your account' was true, not a refusal."
metadata: 
  node_type: memory
  type: project
  originSessionId: 5cddcd24-7d49-4fa9-84c5-f33b74a74e52
  modified: 2026-08-13T02:28:20.665Z
---

The founder called the site assistant "a dumb chat bot". Measured cause, from `assistant_logs` on
13 Aug 2026 at 01:04–01:05 UTC, signed in, on `/me`: it answered *"I can't see your account or your
inquiries — only you can view those when you log in."* That was not a refusal or a bad prompt. The
function's request body was `{message, path, history}`. **It had no identity to reason with.**

Three separate causes hid behind one verdict, and only the first is about the prompt:

1. **No identity.** Fixed by accepting the session JWT and calling `fn_wa_context` — whose
   identifier now takes an email as well as a phone, so the web portal and WhatsApp share ONE copy
   of the pre-reveal rule instead of two.
2. **A stored FAQ answering a personal question.** `try_faq` let `fn_faq_answer` reply with NO MODEL
   (`llm_calls.model_used` NULL at 746 ms). "how to create inquiry" got an answer about *editing*
   one. Level-0 answering is right for visitors and wrong for anyone signed in.
3. **A silent model downgrade.** `fn_ai_route` reported `UNMAPPED function "site_assistant" -
   defaulted to general_drafting`. It had run `claude-sonnet-5` for 55 calls to 26 Jul and was on
   haiku by 13 Aug. Nothing failed, so nothing reported it. See [[green-pr-does-not-mean-deployable]].

**Why:** "the AI is bad" is a verdict about an output; the causes were an absent auth header, a
retrieval shortcut and a missing routing row. Rewriting the prompt would have fixed none of them.

**How to apply:** when a conversational surface gives a weak answer, before touching the prompt ask
(a) what does it KNOW about the caller, (b) did a model actually run — check `llm_calls.model_used`
and `latency_ms`, and (c) which task_class did `fn_ai_route` pick. Related:
[[an-error-string-that-was-our-own-timeout]], [[instruments-report-on-the-wrong-subject]].
