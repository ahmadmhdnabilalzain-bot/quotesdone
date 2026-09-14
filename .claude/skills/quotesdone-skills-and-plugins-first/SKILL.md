---
name: quotesdone-skills-and-plugins-first
description: ALWAYS APPLY, at the start of every task. Before doing any work, check the installed skills, plugins and MCP servers for anything that makes the result more advanced, load it, and use it. Founder's ruling of 14 Sep 2026.
---

# Skills and plugins first

The founder, 14 September 2026:

> *"always before proceeding with a task, check if there is any useful skill or plugin we have to
> use to make things more advanced. this skill should always run in any session we do"*

He has installed a large toolkit (design, 3D/motion, SEO, security, Vercel, v0, 21st.dev, browser
automation, Lighthouse, archify diagrams, Supabase, GitHub). A task done by hand when a skill for it
exists is a weaker result than he paid for.

## The step, before every task

1. **Name the task's kinds of work** — UI, 3D/motion, copy, Arabic, SEO, performance, security,
   database, edge function, verification, diagram, deploy.
2. **Look them up** in the available-skills list the session shows (and `ToolSearch` for deferred
   MCP tools). Pick every skill/plugin that raises the bar for those kinds of work.
3. **Load them with the Skill tool before writing code**, and pass the relevant ones to every
   subagent you launch by name in its prompt, so parallel agents use them too.
4. **Say in one line which ones you used** in the report, so he can see they were.
5. If a skill he would want is missing and it is on GitHub, inspect it (read its files, check it is
   what it claims) and install it; if it needs a login or key only he holds, tell him once.

## The usual matches on QuotesDone

| work | load |
|---|---|
| UI / pages / portals | `impeccable`, `high-end-visual-design`, `design-taste-frontend`, `21st:21st-ui-build` (21st.dev is signed in), `frontend-skills-pack`, `web-design-guidelines`, `vercel-react-best-practices` |
| visual drafts | v0 MCP (`createChat`, model v0-max) |
| 3D / motion | `design-motion-principles`, `ecc:motion-advanced`, `ecc:motion-patterns` |
| review of UI | `21st:21st-ui-review`, `design:accessibility-review`, `ecc:react-review` |
| SEO | `searchfit-seo:technical-seo`, `searchfit-seo:schema-markup`, `ecc:seo` |
| performance | `vercel-optimize`, `ecc:react-performance`, Lighthouse via chrome-devtools MCP |
| verification | Browser pane, `plugin:browser-use`, playwright MCP, `web-verify`, `verification-before-completion` |
| diagrams | `archify` |
| database / SQL | `quotesdone-apply-discipline`, `ecc:postgres-patterns`, `ecc:database-reviewer` agent |
| security | `security-review`, `ecc:security-review` |
| deploy | `deploy-to-vercel`, `vercel-cli-with-tokens` |

This table is a starting point, not a limit: the list the session shows is the source of truth.

## What this does NOT change

`quotesdone-session` still governs conduct (no check-ins, verify by execution, one Supabase
project), `quotesdone-work-is-assigned` still requires the owning seat, and a skill never overrides
the founder's rules — where a skill's generic advice conflicts with the brand or a ruling, the
ruling wins.
