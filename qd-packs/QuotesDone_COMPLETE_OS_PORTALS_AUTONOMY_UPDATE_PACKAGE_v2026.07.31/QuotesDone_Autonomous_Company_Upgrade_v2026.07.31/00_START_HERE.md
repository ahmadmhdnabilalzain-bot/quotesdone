# QuotesDone autonomous-company upgrade — start here

This package reconciles four things:

1. The founder's **Executive OS / Command Center** vision.
2. The founder's **Supplier Portal** vision.
3. The founder's **Customer Portal** vision.
4. The production backend/database export dated **29 July 2026**.

## The most important limitation

The production export explicitly excludes the Next.js frontend. Therefore this audit can verify deployed backend functions, database structures, workflows, jobs and APIs, but it **cannot certify which pages, components, animations, routes or visual interactions Claude implemented in the website repository**.

Claude must run the frontend audit in `01_MASTER/03_FRONTEND_REPOSITORY_AUDIT.md` before changing UI code.

## Recommended order

1. Read `01_MASTER/01_EXECUTIVE_AUDIT.md`.
2. Give Claude `01_MASTER/06_PASTE_THIS_TO_CLAUDE.md`.
3. Claude performs Phase 0 repository audit and maps every current frontend route/component.
4. Implement the shared autonomy foundation before expanding portal features.
5. Implement the customer and supplier portals in independently deployable phases.
6. Keep production locked until all acceptance gates pass in staging.

## Packages in this folder

- `01_MASTER` — reconciled architecture, priorities, governance and master Claude prompt.
- `02_OS_COMMAND_CENTER` — Executive OS audit and upgrade specification.
- `03_SUPPLIER_PORTAL` — supplier portal audit and target implementation.
- `04_CUSTOMER_PORTAL` — customer portal audit and target implementation.
- `05_SHARED_AUTONOMY_FOUNDATION` — event, workflow, decision, action and audit foundations required for unattended operation.
- `SOURCE_PLANS` — copies of the source visions used for traceability.

## Core conclusion

QuotesDone already has an unusually broad backend foundation. The ten Operating Systems, employee model, knowledge, memory, events, health, simulations, company reflection and many marketplace flows exist. The biggest remaining gap is **not the number of agents**. It is the gap between agents producing advice/drafts and the company reliably executing real, idempotent, policy-governed business actions end to end.
