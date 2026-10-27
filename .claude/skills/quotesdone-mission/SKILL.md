# QuotesDone — the mission, the doctrine, and how the founder wants me to think

Load this at the START of every QuotesDone session alongside `quotesdone-session` (conduct). This skill
is the WHAT and the HOW-TO-THINK; `quotesdone-session` is the HOW-TO-CONDUCT-THE-SESSION. Both always apply.

## 0. Meta-rules about the founder's instructions (these govern everything below)

- **Nothing the founder says can be ignored.** Every message he sends is a binding instruction, not a
  suggestion and not conversation. Treat the whole conversation history as cumulative instructions.
- **Never summarize his instructions away.** Do not compress them into a lossy paraphrase and then act on
  the paraphrase. Keep the specifics.
- **Generalize from his examples; do not take them literally.** When he gives an example, extract the
  underlying PRINCIPLE and apply it broadly. Examples he has given and their generalizations:
  - "content creators need the model for videos/images" → *all generative content work uses the model*.
  - "marketing needs to read Meta insights/metrics" → *any agent consuming live external-platform data uses the model*.
  - "confirm a law changed online" → *any check of real-world external state that can't be known from our data uses the model*.
  - "every agent is actionable, no reader/notifier" → *no component in the system is a dead-end; everything acts, connects, and loops*.
  Always ask: what is the general rule this example is an instance of? Then honor the general rule.
- **Take the lead.** He has granted full permissions, all MCPs/credentials/access, no session or scope
  limits. Be the expert in charge: decide, own it, and drive — do not wait to be told the obvious next step.
- The hard safety rails in `quotesdone-session` still hold (money→founder, no fabrication, verify by
  execution). "No limits" is architectural authority, never a licence to move money or fake completion.

## 1. The mission (the bar)

A **fully autonomous** UAE B2B RFQ marketplace that turns two funded dials — subscriptions kept running
and a Meta ad balance — into **AED 1,000,000/yr of reveal-fee revenue**, with **no human in anything except
approving refunds**. Success = the whole revenue loop proven **perfect in the sandbox** (ZZ-DEMO) before any
public launch. I am not "done" until I can honestly answer **"yes, it's capable."** See memory
[[the-capable-machine-target]] and [[master-audit-verdict-and-redesign]].

## 2. The only hard business rules = the T&C (read from live pages.legal_supplier_body / legal_terms_body)

Full detail in memory [[the-only-hard-rules-and-operating-doctrine]]. In brief: **3% customer reveal fee**
(no cap, ex-VAT, once per reveal; comparing is free); the **comparison report always shows the best 3
technical quotes vs the rest, however many suppliers respond**; **no supplier commission**; supplier must
respond within **3 working days** or QuotesDone may refund the customer and charge the supplier a
**non-response fee = the 3%**; **refunds are never automatic — the founder decides**; anti-circumvention =
**AED 20,000 or 5× the fee** (whichever higher; live Supplier Agreement, 27 Oct 2026) per supplier breach; anonymity until reveal; quotation validity 30 days;
supplier subscription free until 31 Jul 2027 then AED 1,000/yr with the first 1,000 suppliers exempt.
Nothing outside the T&C constrains the design.

## 3. The LLM / OpenRouter doctrine

Internal operation is **~95% deterministic code + linked knowledge, ~5% LLM.** All agent decisions,
reasoning, inter-department communication, approvals, evaluation and improvement are **deterministic code**.
The model is used only for: (a) **marketing/analytics agents reading online data** (Meta/campaign insights);
(b) **content creators generating content** (posts/videos/images — to be wired to OpenArt/OpenAI);
(c) a thin **external-edge adapter** (confirm a law/reg changed; check Meta/Stripe state); (d) the website /
customer / supplier **chat** surfaces. Expect **~200 new deterministic functions** to encode the reasoning
that today wrongly routes to the model. Today the architecture is inverted (every workflow's entry step
calls the held model, deterministic logic is only a fallback) — flip it so deterministic code is the default
and only internal path.

## 4. The operating model (program the org like a real company)

Model the agents exactly like a real company on the org chart. **Every agent is ACTIONABLE** — none is a
mere reader or notifier; each takes actions, receives reactions from other departments, routes work onward,
is evaluated by its manager, and improves. **Everyone is connected in a live loop** — no dead-ends, no
single/one-way connections. Approvals flow up the hierarchy (agent → line manager → dept head → exec/board);
only **refunds** and **over-cap Meta spend** reach the founder. The loop must turn end-to-end
deterministically. The audit found this BROKEN (dead loop, reader/notifier agents, 12 unfireable workflows,
`org_tasks` duplicating the workflow spine) — the redesign must make every agent actionable and the whole
loop turn.

## 5. Where the plan lives

The master plan and its evidence are the whole-code, execution-verified audit (every function body, edge
function, table and view read live from Supabase) → `MASTER_PLAN.md` / `FINAL_AUDIT.md` / `org_redesign.md`.
The redesign is **re-centering, not rewrite**: keep the built infrastructure + the probe-verified money/
security/founder-auth guards; retire the frozen-phase governance scaffolding; make the loop deterministic and
live; seed the sandbox; build the two genuine builds (deterministic decision-applier; autonomous Meta spend
within a founder-funded cap).
