# Postmortem: `duty:security` — a definer routine any signed-in user could run

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `duty:security:authenticated_executable_definer:*` — 1 key |
| Handoffs covered | **1**, **critical** |
| Raised / closed | 23 Sep 2026 17:46Z / 23 Sep 2026 18:45Z ("the security duty no longer finds it") |
| Answering seat | ceo |

## Impact
`fn_task_is_demand(text)` was executable by `authenticated` with the definer's rights and no caller check. The routine
classifies an action class as revenue work (`governance_reads_keys_and_reasons_rather_than_spotting_words.sql`, section 1);
it reads a registry and returns a boolean. No evidence of misuse was looked for or found in this postmortem.

## Root cause
Postgres grants EXECUTE to PUBLIC on `CREATE FUNCTION`; a file that re-created the routine did not revoke from
`authenticated` (the class `quotesdone-apply-discipline` names: "CREATE grants EXECUTE to PUBLIC where CREATE OR
REPLACE does not").

## Detection
`it_engineer.security` duty, within an hour of the apply. Worked.

## Fix
Measured today: `has_function_privilege('authenticated','public.fn_task_is_demand(text)','execute')` = **false**.
The revoking commit was **not identified** in git; the routine's owning file was last changed in `12dc52b` (#891).

## Action items
1. **it_engineer** — none; the apply-discipline checklist already requires the revoke on every new routine.

## Handoff ids covered
`duty:security` (1): 85060.
