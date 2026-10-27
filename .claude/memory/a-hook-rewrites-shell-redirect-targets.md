# A post-command hook overwrites shell redirect targets

Seen 6 Sep 2026 while assembling `docs/KNOWLEDGE_PLAN_2026-09-06.md`: `cat parts > docs/file.md` produced the right file, and a moment later the file held 183 bytes of "[INFO] Recording command outcome … [OK] Command outcome recorded" — a post-command hook re-used the command's `>` target for its own log. The verification in the same command passed; the next command found the file destroyed.

Rule: never build a deliverable through `>` or `>>` in a Bash command in this repository. Assemble with the Write tool, or with `node -e` / a script that calls `fs.writeFileSync`, and re-check the file in a *later* command before relying on it.
