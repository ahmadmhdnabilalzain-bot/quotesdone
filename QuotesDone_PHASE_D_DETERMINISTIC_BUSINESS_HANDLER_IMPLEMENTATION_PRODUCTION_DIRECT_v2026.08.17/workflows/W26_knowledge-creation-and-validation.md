# W26 — Knowledge creation and validation

- **Domain:** knowledge
- **Criticality:** high
- **Profile:** knowledge_cycle
- **Primary object:** `knowledge_change`
- **Accountable role:** `knowledge_director`
- **Start event:** Knowledge gap/change
- **Required end state:** Validated versioned knowledge or rejection
- **Founder boundary:** Author cannot self-validate

## Purpose

Create, independently validate, version, publish and retire company or category knowledge.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W26-S01` | Open knowledge gap or change | intake | `knowledge_director` | category_knowledge_curator; agent_workforce_capability_director |  | `W26-S02` |
| 2 | `W26-S02` | Define source and evidence plan | decision | `knowledge_director` | knowledge_engineer; taxonomy_governance_manager |  | `W26-S03` |
| 3 | `W26-S03` | Collect and register sources | execution | `knowledge_engineer` | market_intelligence_analyst; category_knowledge_curator; document_operations_specialist |  | `W26-S04` |
| 4 | `W26-S04` | Create or update knowledge | execution | `knowledge_engineer` | category_knowledge_curator; taxonomy_governance_manager |  | `W26-S05` |
| 5 | `W26-S05` | Review taxonomy and category fit | review | `taxonomy_governance_manager` | category_knowledge_curator |  | `W26-S06` |
| 6 | `W26-S06` | Independently validate knowledge | review | `knowledge_validator` |  |  | `W26-S07` |
| 7 | `W26-S07` | Publish approved knowledge version | execution | `knowledge_director` |  |  | `W26-S08` |
| 8 | `W26-S08` | Set review and expiry conditions | decision | `knowledge_director` | knowledge_validator |  | `W26-S09` |
| 9 | `W26-S09` | Close knowledge-change cycle | closure | `knowledge_director` |  |  | `WORKFLOW_COMPLETE` |

## Phase D requirement

For every step populate the handler matrix and prove actual caller, authoritative handler, typed contract, object mutations, rules/gates, state, idempotency, failure, review/handoff, trace and external-effect policy.

## Workflow acceptance

- deterministic happy path reaches required end state;
- failure/block path is visible;
- cancellation leaves no active derived work;
- replay creates no duplicate effect;
- no live external effect;
- no paid inference;
- no founder approval except a specific refund in W17.
