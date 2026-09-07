# graphify
- **graphify** (`.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# quotesdone-session — ALWAYS APPLY
- **quotesdone-session** (`.claude/skills/quotesdone-session/SKILL.md`) — the founder's standing
  working rules for this repository: run continuously without check-ins, report only the single
  completion line or an honest hand-over, verify by execution in the same turn, deploy to the ONE
  Supabase project, merge via PR, never fabricate data to turn a gate green.

Load this skill at the START of every session on this repository, before any other work and without
being asked. It governs HOW the session is run; the session brief in `docs/sessions/` governs WHAT
is built. If the two ever conflict, the skill wins on conduct and the brief wins on scope.

# quotesdone-work-is-assigned — ALWAYS APPLY
- **quotesdone-work-is-assigned** (`.claude/skills/quotesdone-work-is-assigned/SKILL.md`) — the
  founder's rulings of 7 Sep 2026. There are exactly TWO agents — `ceo` and `customer_support` — and NO departments. Every change names its agent before the work starts and carries that name in the commit. No task exists unless the founder confirmed it.

Load this alongside `quotesdone-session` at the START of every session on this repository.

# quotesdone-build-until-done — ALWAYS APPLY
- **quotesdone-build-until-done** (`.claude/skills/quotesdone-build-until-done/SKILL.md`) — when the
  founder shares a build (a spec, a prompt, a knowledge pack, a ZIP, a list of requirements), the
  session does NOT stop until every requirement is built, proved by execution and CI is green, and
  the only thing said at the end is the one confirmation line. Blockers are worked around, not
  stopped at. Ruling of 7 Sep 2026.
