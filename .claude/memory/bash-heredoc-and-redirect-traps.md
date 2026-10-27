---
name: bash-heredoc-and-redirect-traps
description: "In this harness, Bash heredocs un-escape backslashes and a PostToolUse hook overwrites `> file` targets with its own \"[INFO] Recording command outcome\" text — write files with the Write tool or from inside node."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 10e5b45d-b519-46f1-b7ef-9fbfd4669e3c
  modified: 2026-08-23T03:07:56.384Z
---

Two tooling traps measured 23 Aug 2026 in this repository's Claude Code sessions:

1. `cat > file <<'EOF' … EOF` through the Bash tool collapses `\\n` to `\n` inside the written file
   (a JS regex `/\\n/g` arrived as `/\n/g`), so any script containing backslashes must be written
   with the Write tool, not a heredoc.
2. After a Bash command that redirects stdout with `>` or `>>`, a hook prints
   `[INFO] Recording command outcome: <cmd>` / `[OK] Command outcome recorded` and that text lands in
   the redirected file — `>` leaves a file holding ONLY the hook text, `>>` appends it. This is how
   `scripts/sql/MANIFEST.txt` acquired three stray lines (committed in c11dae6, removed on
   feat/phase-d-root-cause-rebuild).

**Why:** a census summary file came back as four hook lines and a manifest parser was fed hook
output; both cost diagnosis time before the cause was found.

**How to apply:** produce files from inside the node script (`fs.writeFileSync`) or with the Write
tool; never rely on shell redirection for a file that will be read later. See also
[[stage-paths-never-git-add-all]].

**UPDATE 3 Sep 2026 — it is not the heredoc, it is the Bash tool.** A single-quoted `node -e "..."` edit
lost its backslashes exactly the same way: a regex meant to read "word-char class, escaped dot" shipped
as `[w-]+.` and matched nothing — it took THREE deploys of send_outbox and one real email to a fixture
address to see it, because `deno eval` typed on the command line (no file write) still showed
match:true. Rule: any backslash inside a Bash-tool command string is halved on the way in, whether it
is a heredoc, a quoted -e argument, or a sed expression. Workarounds, in order: (1) write patterns
without backslashes at all — `[.]` for a literal dot, `[a-z0-9_-]` for the word class, `[$]` for a
dollar — which is what send_outbox now carries and is immune by construction; (2) use the Edit/Write
tool for any file that must contain a backslash; (3) after ANY edit that should carry a backslash,
grep the written line back before deploying. Never trust an edit you have not read back.

**UPDATE 3 Sep 2026 — gate on the check, never on the pipe.** Three commits in one session went in
with false claims because the commit was gated on the exit code of `node check | grep ...` — the
pipeline reports grep, not the check — or because a `;` inside an `&&` chain let the tail run
unconditionally. The shape that works: `OUT=$(node check 2>&1); CODE=$?` (command substitution keeps
the command's own exit code), then `if [ "$CODE" = "0" ]; then git add ... && git commit ...; fi`,
and no `;` anywhere inside the gated chain. A commit message that states a measurement must be written
AFTER that measurement is read, never before.

**The Bash tool sometimes re-executes a command (seen 3–4 Sep 2026).** An `echo/printf … >> scripts/sql/MANIFEST.txt`
landed twice, and once with its own flags (`--apply`, `--ddl`) as the line; a subagent saw the same.
Append manifest lines idempotently: `grep -q "$f" MANIFEST.txt || printf '%s\n' "$f" >> MANIFEST.txt`,
then `tail -3` and look. The manifest also carries ~20 pre-existing duplicate lines; the canonical
engine only flags a duplicate for files it is checking, so leave history alone and fix only yours.

**UPDATE 6 Sep 2026 — an apostrophe inside `node -e '...'` kills the whole chain.** A ratchet edit
carried the word "packet's" in a JS string inside a single-quoted `node -e`; bash closed the quote at
the apostrophe and the chain died with `syntax error near unexpected token ')'` before doing anything.
Same family: a JS regex character class `[^"\]` in a heredoc lost its backslash and became a syntax
error at parse time. Rule: anything longer than a one-liner, or containing an apostrophe, a backslash
or a regex, goes into the scratchpad with the Write tool and is run as `node file.mjs`. For matching
a marker in an error message use `indexOf('MARK|')` + `slice`, not a regex.
