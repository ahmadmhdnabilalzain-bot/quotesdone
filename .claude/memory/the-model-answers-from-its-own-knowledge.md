---
name: the-model-answers-from-its-own-knowledge
description: "Founder ruling 28 Oct (ledger 1405): a reply costs what a plain chat costs — the model answers from its own knowledge; our collected knowledge is looked up when needed, never sent whole on every call"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-28T08:05:00.000Z
---

28 Oct 2026, ledger 1405 (after 1402, "open router burned 50 USD almost since yesterday"). The founder:

> "You would be able to answer it from your own knowledge because you are a trained model … It should cost
> the same on our platform. Am I right? If not, then there's something wrong. The reason we had that
> knowledge is that if there was a question that is extremely hard, and Sonnet was let's say confused …
> it can go back to those documents and knowledge we collected to double check."

He was right. Measured (ai_cost_log, 48 h to 28 Oct ~07:45Z; prices from model_registry, sonnet-5.5
$2/M in, $10/M out, $0.10/M cache read, 1-hour cache write $4/M):

```
plain Sonnet question (~1.5k in, ~300 out)                          ~$0.006
portal reply, prefix cached   150,941 in (149,856 cached), 222 out   $0.0199   (~3x)
portal reply, prefix cold     149,794 in (147,955 written), 94 out   $0.596    (~100x)
48 h total $36.20 — tests $27.87 (1,751 of 2,419 model calls)
```

The prefix was `companyBrief()` (_shared/company_brief.ts): BRIEF_TEXT, 122,789 tokens — all 10 trade
playbooks, all 7 UAE regulation digests, materials for every trade, a supplier how-to sent to customers
(compile_brief.mjs: "everything is always included -- no topic routing") — plus ALL 1,086 price rows,
plus on the site assistant the whole FAQ in both languages. A "hello" carried all of it.

**The rule:** a customer- or supplier-facing call carries
1. a short, byte-stable company card (who we are, how quotes work, the rules) — a few thousand tokens;
2. the model's own knowledge for general trade questions;
3. our own facts ONLY as the message needs them — that trade's price range, the matching FAQ rows in the
   customer's language, the one regulation that applies — retrieved, not prepended;
4. the full knowledge consulted on demand when the question is hard or the model is unsure.
Tests check logic on recorded model replies; only a small smoke set calls the real model, with its cost
stated. Size every prompt by what the call needs, and measure it — "it is cached" made a 148k-token
prefix look cheap per call while it cost 3x warm, 100x cold, and multiplied across test volume.

Related: [[routine-work-is-code-not-llm]], [[never-raise-openrouter-again]].
