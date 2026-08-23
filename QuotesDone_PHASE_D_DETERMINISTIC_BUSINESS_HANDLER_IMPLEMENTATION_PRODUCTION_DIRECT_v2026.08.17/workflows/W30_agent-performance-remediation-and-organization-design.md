# W30 — Agent performance, remediation and organization design

- **Domain:** people
- **Criticality:** high
- **Profile:** remediation_cycle
- **Primary object:** `capability_case`
- **Accountable role:** `agent_workforce_capability_director`
- **Start event:** Capability/KPI failure
- **Required end state:** Remediated/restricted/reassigned capability and verified result
- **Founder boundary:** No self-certification or unjustified role creation

## Purpose

Diagnose agent capability failures, restrict risk, remediate, verify and propose structural change only when evidence supports it.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W30-S01` | Open capability/performance case | intake | `agent_workforce_capability_director` | culture_performance_manager; relevant_manager |  | `W30-S02` |
| 2 | `W30-S02` | Validate the failure | review | `ai_quality_assurance_reviewer` | culture_performance_manager |  | `W30-S03` |
| 3 | `W30-S03` | Apply temporary restriction when required | decision | `agent_workforce_capability_director` |  | risk_governance_manager | `W30-S04` |
| 4 | `W30-S04` | Create remediation plan | execution | `learning_development_manager` | relevant_manager; knowledge_director |  | `W30-S05` |
| 5 | `W30-S05` | Execute remediation | execution | `agent_workforce_capability_director` | relevant_manager; learning_development_manager; process_improvement_manager |  | `W30-S06` |
| 6 | `W30-S06` | Independently verify remediation | review | `ai_quality_assurance_reviewer` | culture_performance_manager |  | `W30-S07` |
| 7 | `W30-S07` | Restore, continue restriction or reassign | decision | `agent_workforce_capability_director` | relevant_manager | risk_governance_manager | `W30-S08` |
| 8 | `W30-S08` | Assess structural cause | analysis | `organisation_design_lead` | process_improvement_manager; chief_of_staff |  | `W30-S09` |
| 9 | `W30-S09` | Source missing capability if required | execution | `recruitment_specialist` | agent_workforce_capability_director |  | `W30-S10` |
| 10 | `W30-S10` | Approve formal organizational change request | decision | `coo` | ceo; agent_workforce_capability_director; organisation_design_lead | founder | `W30-S11` |
| 11 | `W30-S11` | Close capability case | closure | `agent_workforce_capability_director` |  |  | `WORKFLOW_COMPLETE` |

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
