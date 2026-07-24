# QuotesDone — Employee Architecture
**Onboarding & continuous learning for AI departments: employees, not chatbots**
Implemented in `suppliers DB`, 24 July 2026

---

## The principle

A chatbot with tools searches documents when asked. An employee was *inducted* into the company, *examined* before being trusted, works under *probation* until proven, reasons from *internalized* knowledge, verifies facts instead of guessing, and feeds what they learn back into the organization. This architecture makes every QuotesDone department the second thing.

Every department executive now possesses four independent knowledge layers, assembled in a fixed order into their working context on every task:

| Layer | Content | Source of truth | Refresh |
|---|---|---|---|
| **Identity & posture** | Who you are here: role, charter, north star, employment status, and the reasoning standard | org_agents + org_departments + org_onboarding | live |
| **L1 — Company knowledge** | The canon: what QuotesDone is, the money model, constitution, escalation rules, FAQ | agent_knowledge `_global` (layer=company) | pricing auto-syncs from pricing_config; company brief refreshes every 3h |
| **L2 — Professional expertise** | The executive's own 15–20-yr discipline: standards, playbooks, verified references | agent_knowledge per agent (layer=profession) | staleness policy per domain; guarded by the linter |
| **L3 — Operational state** | Live numbers, executed at context-assembly time from the department's health function | fn_ws_* views, run *now* | always live — never cached, never from memory |
| **L4 — Organizational experience** | What THIS company has learned: promoted lessons, closed cases, vetted memories | agent_knowledge (layer=experience) + lint-filtered agent_memory | governed weekly promotion |

**The posture line every executive now carries:** *"You are a senior executive employee, not a document-search AI. Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Ground each material claim in a layer. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction — never silently pick one. If your employment status is not certified, mark your outputs as provisional."*

---

## The employment lifecycle

```
hire (org_agents row)
  → ONBOARDING     four-layer exams (canon_eval, layered question bank)
  → PROBATION      L1+L2 ≥ 85%; first 3 outputs need founder/lead review
  → CERTIFIED      probation reviews done; recert due in 90 days
  → RECERT_DUE     certification expires; re-examination scheduled automatically
```

- **org_onboarding** — one row per executive: per-layer scores and exam dates, status, pass threshold (85), probation counters, recertification due date.
- **fn_onboarding_gate(agent)** — the runtime gate: returns whether this executive's outputs need review and why. Uncertified/unknown agents are always review-required. (Adoption point: call it wherever agent output is dispatched; wire `probation_reviews_done` increments into the founder-approval flow.)
- **fn_onboarding_ingest_runs()** — pulls exam results from canon_eval_runs into the lifecycle state machine.
- **fn_recert_rotate()** — weekly (Mon 06:40 UTC, replaces the old hardcoded followup-only eval): examines whichever executive has the oldest evidence, so certification pressure rotates across the whole roster automatically.

**Exam bank** (canon_eval_questions, now layer- and agent-scoped): 79 company-layer canon questions (existing) + 17 profession-layer questions written per executive (the CFO is asked how revenue is recognised and what to do when a supplier's bank details change; Security is asked its first three moves on a key leak; Collections is asked exactly what it may demand and at what interest) + state-layer and experience-layer questions that test whether the agent knows *where truth lives*, not just what it is.

---

## The continuous-learning loop

```
work happens → lesson recorded (org_memory kind=lesson)
  → 7-day stability window
  → forbidden-language lint (policy_rules)
      ├─ clean → promoted into Layer 4 of the owning department (fn_experience_promote, Sun 05:00 UTC)
      └─ contradicts policy → BLOCKED + founder alert (experience_promotion_blocked)
  → promoted lessons appear in every future context assembly
  → quarterly re-certification proves they stuck
```

Personal `agent_memory` is scratch, not truth: it is lint-filtered at context-assembly time, so a poisoned memory can never reach an executive's working context. (This was not hypothetical — two auto-learned memories stating a "2% reveal fee capped at AED 250" sat in the secretary's memory for a month. They evaded the old lint rules, so a new critical rule now catches pre-pivot pricing wording, the rows are deleted, and the weekly linter now scans **seven** stores: site source, FAQ, invite emails, agent_knowledge, dept_library, agent_memory, org_memory.)

---

## What changed technically

- `agent_knowledge.layer` column (company / profession / state / experience), all 250+ rows classified.
- `org_onboarding` table + lifecycle state machine; 16 executives enrolled (12 department brains incl. the new Analytics and Procurement heads, plus secretary, designer, followup carries its first exam score of 80%).
- **`fn_agent_context()` upgraded in place** — same signature the runtimes already call, so every agent adopted the four-layer employee context with zero edge-function changes. It now opens with identity + posture, reserves a slice for L2, orders L1 by priority, executes the department health function live for L3 (with an explicit "numbers come only from here" rule, and a refusal instruction if L3 is unavailable), and closes with promoted experience + lint-clean memories.
- `fn_onboarding_gate`, `fn_onboarding_ingest_runs`, `fn_recert_rotate`, `fn_experience_promote` — all service-role-only (no anon/PUBLIC execute, consistent with today's default-privileges hardening).
- Crons: `canon_eval_weekly` → rotates the whole roster; `experience_promote_weekly` → governed L4 promotion.
- New critical policy rule: "Old 2% reveal fee / AED 250 cap"; linter extended to memory stores. Full-scan result after all changes: **0 findings**.

## Verified live

- `fn_agent_context('marketing')` → 27k chars opening with "YOUR IDENTITY AT QUOTESDONE … You are Marketing lead … Employment status: onboarding. POSTURE: You are a senior executive employee, not a document-search AI…", followed by L2 (brand kit first), L1 canon, L3 executed live, L4 experience. ✔
- `fn_onboarding_gate('marketing')` → `outputs_need_review: true, reason: "not yet examined on the four knowledge layers"` — honest: nobody is certified until they pass. ✔
- Policy lint across all seven stores → 0 findings. ✔

---

## How to onboard a future department (the standing recipe)

1. **Hire:** insert the org_agents row + org_departments lead; write the L2 profession pack (role, professional standard, verified references, deepened playbook — the four-row pattern every current executive follows).
2. **Enroll:** insert its org_onboarding row (automatic for active org_agents on the next roster sync); add 2–3 profession-layer exam questions to canon_eval_questions.
3. **Examine:** the weekly rotation picks it up, or fire `fn_recert_rotate()` manually; it must clear 85% on L1 and L2.
4. **Probation:** its first 3 outputs carry `outputs_need_review = true` — review them.
5. **Certify:** the state machine promotes it; recertification is automatic every 90 days thereafter.

## What still needs the founder / next steps

1. **Run the initial examination round** — everyone is honestly `onboarding` until examined; the weekly rotation will work through the roster (~16 weeks), or I can fire the exams in a batch so the whole roster is scored this week.
2. **Wire probation review counting** — `probation_reviews_done` should increment when you approve an agent's output in the OS review flow (one small edge-function change; the DB side is ready).
3. **L3/L4 exam automation** — profession and company exams run through the existing canon_eval engine today; state/experience questions are in the bank and will be included in each agent's draw.
