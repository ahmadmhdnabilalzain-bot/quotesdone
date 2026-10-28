---
name: a-test-can-guard-a-file-from-another-directory
description: "28 Oct 2026: #1658 skipped npm-test and hand-ran site_assistant/'s own tests, but the test that guards site_assistant's exits is _shared/widget_reply_effects.test.ts, and it stayed red on main until #1729. Find the tests that read a changed file by its path, not by its directory."
metadata:
  type: feedback
  modified: 2026-10-28
---

**What happened (measured 28 Oct 2026, customer_support).** #1658 sent the homepage visitor-cap reply through the
model, and it merged as 0b9e242 on 27 Oct. Its gate ran with `npm run gate -- --skip=npm-test,alarms-quiet`. The
suites it ran by hand were `deno test site_assistant/` (13 passed) and two `scripts/checks` files.

The test that guards site_assistant's exits is not in that directory. It is
`supabase/functions/_shared/widget_reply_effects.test.ts`, which reads `../site_assistant/index.ts` as text. It counted
the visitor cap's `return J({ reply` as a second answering exit and failed 2 vs 1 on every run of main until #1729.
Nothing was filed twice. The expectation was stale, and #1729 now names the cap exit and gives it its own contract.

**The rule.** A test can guard a file from another directory. When npm-test is skipped, the tests to run by hand are
every test that names the changed file, found by its path:

    grep -rl "site_assistant/index.ts" --include='*.test.*' --include='*.check.*' supabase scripts

On 28 Oct this found 12 files: 11 in `scripts/checks/` and the `_shared` deno test. Swap in the path you changed.
Better still, do not skip npm-test on a PR that changes a runtime file. Run it in the background (it is the gate's
slow step: over 90 min with a token, measured 26 Oct) and do other work meanwhile.

Related: [[ci-runs-locally-ubicloud-stopped]], [[ci-green-does-not-mean-npm-test-green]], [[a-fixs-own-check-measures-the-case-the-fix-handles]].
