# memory — READ FIRST, every session
- **`.claude/memory/MEMORY.md`** — Claude's operating memory for QuotesDone: the founder's standing
  rulings, facts about the estate, lessons, and the latest checkpoints, one subject per file. Read the
  index before any other work. Founder's ruling of 26 Oct 2026 (ledger 1278): GitHub is the single
  source of truth and nothing lives only on the laptop, so this folder is the one copy.
- When a session learns something a future session needs, it edits or adds the file in
  `.claude/memory/` and lands it **by PR**, the same as code. A note kept only in a local
  `~/.claude/projects/.../memory/` folder does not count.
- Reports and evidence go to `docs/reports/` (see `docs/reports/README.md`), never to a laptop folder.

# graphify
- **graphify** (`.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# quotesdone-skills-and-plugins-first — ALWAYS APPLY, BEFORE EVERY TASK
- **quotesdone-skills-and-plugins-first** (`.claude/skills/quotesdone-skills-and-plugins-first/SKILL.md`)
  — the founder's ruling of 14 Sep 2026: before proceeding with any task, check the installed skills,
  plugins and MCP servers for anything that makes the result more advanced, load it, pass it to every
  subagent, and say which were used. Runs in every session.

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
  founder's rulings of 7 Sep 2026. Every change belongs to a seat that exists (read the live seats), and there are no departments. Every change names its agent before the work starts and carries that name in the commit. No task exists unless the founder confirmed it.

Load this alongside `quotesdone-session` at the START of every session on this repository.

# quotesdone-build-until-done — ALWAYS APPLY
- **quotesdone-build-until-done** (`.claude/skills/quotesdone-build-until-done/SKILL.md`) — when the
  founder shares a build (a spec, a prompt, a knowledge pack, a ZIP, a list of requirements), the
  session does NOT stop until every requirement is built, proved by execution and the local gate
  passes (`npm run gate`; GitHub Actions is off since 26 Oct 2026, ledger 1279, so "CI green" means
  the local gate, not a GitHub check), and the only thing said at the end is the one confirmation line. Blockers are worked around, not
  stopped at. Ruling of 7 Sep 2026.

# quotesdone-parallel-agents — ALWAYS APPLY
- **quotesdone-parallel-agents** (`.claude/skills/quotesdone-parallel-agents/SKILL.md`) — the
  founder's ruling of 8 Sep 2026: "use as many agents possible to speed up the process". Fan out by
  default — independent tool calls in ONE message, independent investigations to subagents launched
  together, long work to the background while you pick up something else. Serial only where a step
  genuinely depends on the one before it, and NEVER for production writes, applies or git. Capped at
  5 agents at once, with Sonnet for simple tasks (1 Nov 2026, ledger 1417).

Load this alongside `quotesdone-session` at the START of every session on this repository.

# quotesdone-apply-discipline — ALWAYS APPLY
- **quotesdone-apply-discipline** (`.claude/skills/quotesdone-apply-discipline/SKILL.md`) — the
  mechanical checklist for changing production, written 9 Sep 2026 on the founder's instruction
  after CI caught the same four omissions three times in one session: an apply without its MANIFEST
  line, a new routine without a revoke and a pinned `search_path`, a new table with RLS on and no
  policy, and a commit missing a directory the change touched. Also: a probe that `raise exception`s
  rolls back the DDL in its own file, `CREATE` grants EXECUTE to PUBLIC where `CREATE OR REPLACE`
  does not, a revoke names a signature so every overload must be enumerated, and a check that greps
  source will match your own comment.

Load this before applying SQL, creating a routine or a table, or committing. The pattern behind
every item is the same — the check caught it, not the session. These steps move the catch earlier.

# quotesdone-organised-like-an-auditor-will-read-it — ALWAYS APPLY
- **quotesdone-organised-like-an-auditor-will-read-it**
  (`.claude/skills/quotesdone-organised-like-an-auditor-will-read-it/SKILL.md`) — the founder's
  ruling of 10 Sep 2026: the code must be organised as though a real software engineer built it,
  because one day he will hand it to an external auditor, and *"I can't understand shit, it's all
  mixed everywhere"* is not an acceptable outcome. He tied this directly to a repeated failure —
  decisions we finalise get forgotten and he has to re-state them — because **a decision with no
  obvious home is a decision that will be lost**. Covers: his words go into
  `public.founder_instruction` the moment he says them, not at session end; one subject one file;
  the index must not point at nothing, and a count is not a finding until you know what you counted
  (a quick loop reported 348 dead MANIFEST entries; they were comment lines, and the index is
  clean); where each kind of thing lives; comments carry the measurement; look for what already owns
  the subject
  before writing a second one; scratch never enters the repository; and a probe must be incapable
  of reaching a real person rather than merely careful to clean up.

Load this before creating any file, routine, table or check, and before closing any session.
