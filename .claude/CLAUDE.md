# graphify
- **graphify** (`.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# quotesdone-session — ALWAYS APPLY
- **quotesdone-session** (`.claude/skills/quotesdone-session/SKILL.md`) — the founder's standing
  working rules for this repository: run continuously without check-ins, report only the single
  completion line or an honest hand-over, verify by execution in the same turn, deploy to BOTH
  Supabase projects, merge via PR, never fabricate data to turn a gate green.

Load this skill at the START of every session on this repository, before any other work and without
being asked. It governs HOW the session is run; the session brief in `docs/sessions/` governs WHAT
is built. If the two ever conflict, the skill wins on conduct and the brief wins on scope.
