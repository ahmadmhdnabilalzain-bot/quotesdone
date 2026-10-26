# Mandatory frontend repository audit

The static production export does not contain the Next.js application. Claude must complete this audit before implementing UI changes.

## Required output

Claude must create `docs/audit/frontend-current-state.md` containing:

1. Route inventory for customer, supplier and OS/admin areas.
2. Component inventory and ownership map.
3. State-management and data-fetching architecture.
4. Current API calls mapped to deployed edge functions/RPCs.
5. Authentication, role and locale handling.
6. English/Arabic route and translation coverage.
7. Responsive/mobile behavior.
8. Existing command palette, workspace, charts, timelines, graph and real-time subscriptions.
9. Dead pages, duplicate flows and legacy components.
10. Screenshot set for every current major route at desktop and mobile sizes.
11. A requirement traceability update marking each feature as implemented, partial, absent or obsolete.

## Search targets

Claude should search the repository for:

```text
customer_portal customer_api project_api messages_api quote_compare
supplier_portal supplier_api profile_ai
os_api os_ops os_pages os_automation secretary_chat
CommandPalette MissionControl DigitalTwin Timeline Graph Workspace
/customer /supplier /os /admin /portal
locale i18n rtl ar
```

## Rules

- Do not assume the export's API action exists in the frontend.
- Do not create a second portal if one already exists; refactor incrementally.
- Preserve working authentication and production routes.
- Identify which frontend features are already deployed before estimating work.
- No production deployment during the audit phase.
