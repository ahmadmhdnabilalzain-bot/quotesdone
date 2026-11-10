---
name: checks-read-split-code-through-a-sources-helper
description: "9 Nov 2026: ~200 checks assert properties of source TEXT (customer_api/index.ts, CustomerPortal.tsx...). When a file is split, a check reading the old path reads a short router and asserts nothing. Read code through scripts/lib/function_sources.mjs (edge functions) and scripts/lib/portal_sources.mjs (portals). Also: the linter is oxlint, because typescript-eslint refuses TypeScript 7."
metadata:
  type: feedback
  modified: 2026-11-09
---

**The rule.** A check that reads code as text must read the code wherever it now lives.
- Edge function: `functionSource('<fn>')` from `scripts/lib/function_sources.mjs`: every runtime .ts file in
  the function folder, index.ts first, with tests, checks and fixtures left out. A deployed function IS its folder.
- Portals: `readCustomerPortal()` / `readSupplierPortal()` / `readSource(path)` from
  `scripts/lib/portal_sources.mjs`, a CLOSED ordered list. `portal_sources.test.mjs` fails when a file in a
  split folder is not listed. The order matters to one check: `company_facts_agree_everywhere` strips
  anything tag-like, and a `<` in `i < raw.length` hides text after it (an existing blind spot, worth fixing).
- `scripts/checks/arabic_reviewed_strings.json` is keyed by FILE PATH: a pure move must re-key the hashes,
  never re-review or drop them.

**Why.** On 9 Nov 2026 four god files were split (CustomerPortal 2,156 → 16 lines, SupplierPortal 2,084 → 251,
resilience_ping 2,034 → 323, customer_api/supplier_api). 62 checks read customer_api/supplier_api, 52 read
resilience_ping, ~40 read the portals. Each was repointed with its assertion unchanged. A `@ts-nocheck` file
can lose an import silently, because tsc does not see it, so splits of nocheck files were proved by
stripping `@ts-nocheck` temporarily and requiring 0 TS2304/TS2552/TS2305/TS2307 errors.

**Linting.** ESLint cannot run here: `typescript-eslint does not support TS 7.0`. oxlint 1.89.0 (pinned)
carries the same react, react-hooks, jsx-a11y, nextjs, import and unicorn rules (`npm run lint`,
`.oxlintrc.json`, policy and warning counts in docs/engineering/linting.md). `next lint` no longer exists in
Next 16.
