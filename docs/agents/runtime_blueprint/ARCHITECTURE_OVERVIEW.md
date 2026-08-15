# Exact Runtime Architecture

## The one mandatory execution path

```text
Task / event / customer turn
  → canonical identity resolver
  → active role + department + manager
  → company objective and current stage
  → authority and risk classification
  → deterministic requirements / hard gates
  → scoped knowledge retrieval
  → tool-requirement planner
  → model router
  → agent execution
  → structured-output validator
  → append-only decision trace
  → independent reviewer when required
  → authorized action / handoff / refusal
  → KPI and outcome capture
  → management review
  → validated learning or remediation
```

No alternate employee path may bypass identity, knowledge, tool, authority, output validation or tracing.

## Organizational relationships

- A department owns an outcome.
- A role owns responsibilities, decisions, KPIs and authority.
- A runtime agent executes exactly one canonical role identity per turn.
- A model is selected by task class; it is not the employee identity.
- A category specialist is an on-demand knowledge overlay controlled by the inquiry owner.
- A committee membership does not create a second employee.
- An independent reviewer cannot be the effective creator of the reviewed work.

## Category overlay link

```text
Marketplace Director
  → RFQ Qualification Manager
  → Inquiry Router
  → one or more category overlays
  → structured missing fields / evidence / risks
  → RFQ Qualification Manager
  → supplier-safe brief
  → Independent Quote Evaluation / Supplier Verification as required
```

Category overlays cannot dispatch, approve a supplier, move money, expose customer identity, or override a regulatory/privacy gate.

## Model relationship

The model belongs to a task execution, not permanently to a human-style title. Each role has a default model policy, but deterministic rules and task-level routing take precedence. Managers and professional specialists default to Sonnet 5; routine operators use Haiku 4.5; multimodal extraction uses Gemini 3.6 Flash; independent review uses GPT-5.2 Exacto; Opus 5 is reserved for explicit critical escalation.
