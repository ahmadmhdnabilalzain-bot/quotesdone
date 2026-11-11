# Linting the website

Linter: **oxlint 1.89.0** (`npm run lint`, config `.oxlintrc.json`, also a step of `npm run gate`).
ESLint is not used: typescript-eslint refuses TypeScript 7, which this repo uses.

Scope: the Next app under `src/`. Everything else (supabase, scripts, docs, knowledge, public,
tests, `.claude`, `.github`, `*.test.mjs`, `*.selfcheck.mjs`) is ignored in `ignorePatterns`.

Policy: `correctness` is **error**, so an error fails the gate. The rules below are **warn** because
fixing them changes runtime behaviour or markup semantics and each fix needs a browser to prove.
A warning is debt to burn down, not an exemption. Counts re-measured 11 Nov 2026 on `src/` (oxlint 1.89.0,
`origin/main` 5d20a57eb): **272 warnings, 0 errors**. The 9 Nov table summed to 268 while tech-debt TD-02 said 255, so the two disagreed;
the 4 added since are +1 prefer-tag-over-role, +2 exhaustive-deps and +1 react/refs.

`no-unused-vars` ignores names starting with `_` (args, vars, caught errors); the repo already uses
that convention.

| Rule | Count | Why it is warn |
|---|---|---|
| react/set-state-in-effect | 64 | Moving state out of an effect changes render timing. |
| react-hooks/exhaustive-deps | 48 | Adding a dependency re-runs the effect; many omissions are deliberate (load-once). |
| jsx-a11y/prefer-tag-over-role | 119 | `role="status"` to `<output>` etc. changes the element, its styling and its a11y tree. |
| jsx-a11y/click-events-have-key-events | 6 | Needs keyboard behaviour designed and tried. |
| jsx-a11y/no-static-element-interactions | 3 | Same: element or role choice changes semantics. |
| jsx-a11y/no-noninteractive-element-interactions | 4 | Same. |
| jsx-a11y/no-autofocus | 1 | Removing autofocus changes the focus flow. |
| jsx-a11y/label-has-associated-control | 2 | Needs markup change, checked with a screen reader. |
| jsx-a11y/control-has-associated-label | 5 | Needs accessible names written (and translated). |
| react/purity | 5 | Impure render calls (Date.now, Math.random); the fix moves them and changes output. |
| react/refs | 4 | Ref reads during render; the fix changes when values are read. |
| react/immutability | 3 | Mutation of props/state values; the fix changes identity semantics. |
| react/static-components | 3 | Components defined inside components; hoisting changes remount behaviour. |
| react/preserve-manual-memoization | 1 | Memo dependencies; fix changes memo behaviour. |
| nextjs/no-img-element | 4 | `<img>` to `next/image` changes loading, sizing and layout. |

Deliberate disables (each carries its reason in the comment): `heading-has-content` on two
headings whose content arrives through a spread (false positive); `no-redundant-roles` on three
elements whose explicit role is kept on purpose.
