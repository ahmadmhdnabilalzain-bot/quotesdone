
# Cross-Department Handoff Runtime Contract

Every handoff must contain:

- handoff run ID;
- canonical handoff ID;
- source workflow/step/run;
- sender role and department;
- receiving role and department;
- business object/version;
- evidence/output packet hash;
- requested next action;
- receiving acceptance criteria;
- rejection conditions;
- return owner;
- SLA and due time;
- status history;
- trace IDs.

The sender remains accountable until acceptance. A rejected handoff must identify the exact missing/invalid requirement and return owner. No task may disappear between departments.

Managers can see overdue, rejected and blocked handoffs. The command center can query them by command/task/workflow.
