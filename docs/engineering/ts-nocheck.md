# `@ts-nocheck`: the files type checking does not see

Owner: it_engineer. Measured 10 Nov 2026 on `it_engineer-code-organised-for-an-auditor` (base `origin/main` 6f9ebbd9b).
Register row: [tech-debt.md](tech-debt.md) TD-01.

## What was measured, and how

- `grep -rl '@ts-nocheck'` over `supabase/functions` and `src`, `.ts`/`.tsx`: **0 files in `supabase/functions`, 56 in
  `src`** (38 under `src/components/me`, 18 under `src/components/portal`). TD-01 said 12 on 9 Nov; the split of the two
  portals that day (PR #1876) carried the pragma into every module cut out of a nocheck file, so the count rose while the
  unchecked code stayed the same size.
- The pragma was removed from all 56 at once and `npx tsc --noEmit` run over the project (TypeScript 7.0.2, the repo's
  `tsconfig.json`): **1,208 errors, every one in a file that had carried the pragma; 6 files had none.**

## What changed in this pass (pure: type annotations only, no runtime change)

| file | errors without the pragma | done |
|---|---:|---|
| `src/components/me/CustomerPortal.tsx` | 0 | pragma removed |
| `src/components/me/styles.ts` | 0 | pragma removed |
| `src/components/me/shell/navGroups.ts` | 0 | pragma removed |
| `src/components/me/dashboard/lazyModules.tsx` | 0 | pragma removed |
| `src/components/portal/supplier/core/tabs.ts` | 0 | pragma removed |
| `src/components/portal/supplier/core/styles.ts` | 0 | pragma removed |
| `src/components/me/auth/AuthShell.tsx` | 2 | props typed (`lang: string`, `children: ReactNode`) |
| `src/components/me/requests/DetailFacts.tsx` | 2 | props typed; the inquiry row is `any` (no declared type exists yet, said in a comment) |
| `src/components/portal/supplier/core/session.ts` | 2 | token parameters typed `string` |
| `src/components/portal/supplier/core/copy.ts` | 5 | `t()` reads through a `Record<string, Record<string, string>>` view of the same table |
| `src/components/me/newRequest/BoqTable.tsx` | 6 | props typed; the drawing reader's JSON is `any` (no declared type yet) |
| `src/components/portal/supplier/core/upload.ts` | 6 | `File`/`Blob`/`string` parameters, `Promise<string>` for the base64 read |

**56 -> 44 files.** `npx tsc --noEmit` is clean with the 12 checked.

## What is left, and why it is not mechanical

Counts are from the all-at-once run above (an error is reported in the file that holds it; removing one file's pragma
does not move errors into another). "implicit any" is TS7005/7006/7018/7019/7031/7034/7053: a parameter or binding with
no type. "other" is mostly TS2339 (a property read on `{}` or `never`: state created by `useState({})` / `useState(null)`
and later filled from a server response), then TS2345/TS2554/TS2353/TS18047/TS2322. The implicit-any half is
mechanical only in the sense that `any` silences it; doing it properly needs the response shapes of `customer_api` and
`supplier_api` declared once (they are not today), and the "other" half is exactly those shapes. That is the work: **type
the two APIs' responses, then these files fall in a few at a time.**

| errors | implicit any | other | lines | file |
|---:|---:|---:|---:|---|
| 6 | 3 | 3 | 48 | `src/components/me/auth/Login.tsx` |
| 6 | 5 | 1 | 50 | `src/components/me/newRequest/helpers.ts` |
| 6 | 5 | 1 | 95 | `src/components/me/RevealGuarantee.tsx` |
| 6 | 6 | 0 | 55 | `src/components/portal/supplier/core/ClaimRefusal.tsx` |
| 7 | 6 | 1 | 52 | `src/components/me/api.ts` |
| 8 | 8 | 0 | 43 | `src/components/me/newRequest/RequirementsCard.tsx` |
| 9 | 5 | 4 | 34 | `src/components/me/ConciergeSteps.tsx` |
| 9 | 7 | 2 | 138 | `src/components/me/auth/CustomerPortalView.tsx` |
| 10 | 10 | 0 | 156 | `src/components/portal/supplier/core/Agreement.tsx` |
| 10 | 10 | 0 | 60 | `src/components/me/format.ts` |
| 10 | 10 | 0 | 63 | `src/components/me/shell/StatusParts.tsx` |
| 11 | 11 | 0 | 34 | `src/components/me/newRequest/Readiness.tsx` |
| 11 | 11 | 0 | 93 | `src/components/me/dashboard/ModuleWindow.tsx` |
| 12 | 9 | 3 | 94 | `src/components/me/MissingSpecs.tsx` |
| 13 | 13 | 0 | 48 | `src/components/me/requests/QuoteDocs.tsx` |
| 13 | 7 | 6 | 92 | `src/components/portal/supplier/core/Projects.tsx` |
| 14 | 11 | 3 | 147 | `src/components/me/requests/Contact.tsx` |
| 15 | 11 | 4 | 79 | `src/components/portal/supplier/core/Onboarding.tsx` |
| 15 | 14 | 1 | 140 | `src/components/portal/supplier/core/Login.tsx` |
| 15 | 6 | 9 | 251 | `src/components/portal/SupplierPortal.tsx` |
| 16 | 10 | 6 | 124 | `src/components/me/Clarifications.tsx` |
| 17 | 7 | 10 | 63 | `src/components/me/ConfirmDialog.tsx` |
| 17 | 9 | 8 | 72 | `src/components/me/auth/Authed.tsx` |
| 19 | 15 | 4 | 113 | `src/components/portal/supplier/core/HeaderMenus.tsx` |
| 19 | 19 | 0 | 71 | `src/components/me/SpecOffer.tsx` |
| 19 | 8 | 11 | 95 | `src/components/me/RevealPayment.tsx` |
| 20 | 19 | 1 | 73 | `src/components/portal/supplier/core/helpers.tsx` |
| 21 | 21 | 0 | 109 | `src/components/me/requests/Progress.tsx` |
| 23 | 22 | 1 | 641 | `src/components/me/portalText.ts` |
| 24 | 20 | 4 | 172 | `src/components/me/requests/QuoteCard.tsx` |
| 24 | 5 | 19 | 95 | `src/components/me/auth/ProfileGate.tsx` |
| 25 | 14 | 11 | 239 | `src/components/portal/supplier/core/ProfileForm.tsx` |
| 26 | 8 | 18 | 159 | `src/components/me/dashboard/AccountSettings.tsx` |
| 32 | 26 | 6 | 385 | `src/components/me/PortalShell.tsx` |
| 38 | 15 | 23 | 159 | `src/components/me/requests/Comparison.tsx` |
| 38 | 19 | 19 | 54 | `src/components/me/newRequest/RedactionEditor.tsx` |
| 38 | 26 | 12 | 173 | `src/components/me/requests/InquiryCard.tsx` |
| 41 | 16 | 25 | 202 | `src/components/portal/supplier/core/Billing.tsx` |
| 46 | 7 | 39 | 215 | `src/components/portal/supplier/core/Dashboard.tsx` |
| 47 | 30 | 17 | 197 | `src/components/portal/supplier/core/QuoteForm.tsx` |
| 48 | 18 | 30 | 286 | `src/components/me/shell/AssistantPanel.tsx` |
| 54 | 42 | 12 | 299 | `src/components/portal/supplier/core/Documents.tsx` |
| 118 | 59 | 59 | 671 | `src/components/me/dashboard/Dashboard.tsx` |
| 209 | 50 | 159 | 684 | `src/components/me/NewRequest.tsx` |
| **1185** | **653** | **532** | | **44 files** |

The smallest five (Login, helpers, RevealGuarantee, ClaimRefusal, api.ts) carry a real mismatch each besides the
missing annotations: `auth/Login.tsx` calls a three-to-four-argument function with two (TS2554, three times), and
`newRequest/helpers.ts` passes a value no overload of its callee accepts (TS2769). Those are signature questions to
settle with the callee's owner, not annotations.

`src/components/nocheck_files_have_no_redeclarations.test.mjs` keeps guarding what a nocheck file can still break
(a name declared twice kills the Vercel build).

Re-measure: strip the first line of each listed file in a scratch copy, run `npx tsc --noEmit`, count `error TS` per file.
