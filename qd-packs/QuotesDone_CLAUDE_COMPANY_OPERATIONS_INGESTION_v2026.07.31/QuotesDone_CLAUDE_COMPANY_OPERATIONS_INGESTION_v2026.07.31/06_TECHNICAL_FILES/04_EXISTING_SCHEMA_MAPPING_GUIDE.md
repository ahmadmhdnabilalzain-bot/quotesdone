# Existing-schema mapping guide

## Principle

Do not create a second operating system beside the one already in QuotesDone. Map the corpus to existing production concepts first.

## Existing objects to inspect

### Organization and authority

- `org_departments`
- `org_agents`
- `org_authority`
- `org_objectives`
- `org_tasks`
- `org_memory`
- `employee_authority`
- `delegation_rule`
- `decision_policy`
- `governance_policy`
- `governance_rule`

### Knowledge and learning

- `dept_library`
- `employee_knowledge`
- `employee_knowledge_standard`
- `agent_knowledge`
- `agent_memory`
- `institutional_memory`
- `kb_chunks`
- `kb_revisions`
- `knowledge_exam_questions`
- `knowledge_exam_results`

### Workflows and events

- `employee_workflow`
- `company_event`
- `event_subscription`
- `scenario_library`
- `risk_register`
- `decision_record`

### Audit and implementation evidence

- `agent_action_log`
- `os_audit_log`
- `security_audit_log`
- `integration_matrix`
- `implementation_map`

## Decision for each concept

Use exactly one:

- `reuse`: existing object fully owns the concept;
- `extend`: existing object is correct but lacks required fields;
- `create_staging`: no safe current owner; create staging only;
- `unresolved`: insufficient evidence;
- `reject`: concept conflicts with architecture or policy.

Store the rationale and evidence in `mapping_decisions`.

## Department mapping

The supplied crosswalk maps existing department keys to the 24 target operating departments. A split does not necessarily require separate tables. It may be implemented through teams, agent roles, scopes and workflows under one production department, provided ownership and authority remain unambiguous.

## Promotion rule

Promotion from staging to the operational system requires:

- owner approval;
- successful scenarios;
- permissions review;
- rollback;
- metric and audit coverage;
- no unresolved critical gap.
