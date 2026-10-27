---
name: stage-paths-never-git-add-all
description: "The quotesdone working tree permanently carries session debris — playwright traces, screenshots, a licence PDF, skills-lock.json — so `git add -A` puts 418 unrelated files in the PR."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: b8f9a77d-66be-4ac4-aff5-ec6af2024801
  modified: 2026-08-14T08:58:22.387Z
---

14 Aug 2026. `git add -A` while committing the V3 work swept in 418 files left on disk by
earlier sessions: `.playwright-mcp/` traces, four `os-*.png` screenshots, `lic.pdf` and its
data URL, `MEMORY.md`, `skills-lock.json`, and nine `.claude/skills/vercel-*` directories. The
PR went from 37 files to 455 and had to be cleaned up after the fact.

**Why:** this repository's untracked set is not empty and never will be — the tooling writes
into the working tree. `-A` is only safe in a tree whose untracked files are all yours.

**How to apply:** stage explicit paths — `git add scripts/kb scripts/sql docs/knowledge
supabase/functions/<slug>` — and read `git status --porcelain` before the first commit of a
session so you know what was already lying there. If a broad add has already happened,
`git rm -r --cached` the debris in a follow-up commit: the PR's net diff (`main...HEAD`) is
computed from the tree, so a removal commit does clean it.
