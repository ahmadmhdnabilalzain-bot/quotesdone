---
name: a-sanity-check-that-counted-its-own-comment
description: A patch script's occurrence-count sanity check (expected 2 `trigger_consumed`) failed because the comment it inserted also named the token; it aborted after the MANIFEST line was appended, leaving an orphan line and a red canonical gate.
metadata:
  type: feedback
---

6 Sep 2026: `patch_register_class_c_fast.mjs` asserted `count(body, 'trigger_consumed') === 2`
(CTE + one reference). The explanatory comment it inserted contained the same word — three
occurrences — so the script exited before writing the file, but the MANIFEST line had already been
appended in the same chain: canonical engine "1 finding" for a file that did not exist.

**Why:** the count included prose. A sanity check on a token must count code occurrences, or the
prose must not name the token, or the expected number must be derived from the replacement strings
(`armNew` + `cte`) rather than typed.

**How to apply:** compute the expectation from the pieces you are inserting; append the MANIFEST
line only AFTER the file exists (`test -f "$f" && grep -q ... || printf`). See
[[bash-heredoc-and-redirect-traps]] and [[new-sql-file-needs-a-manifest-line]].
