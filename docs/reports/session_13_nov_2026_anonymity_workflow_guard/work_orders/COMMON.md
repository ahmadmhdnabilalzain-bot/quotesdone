# Common rules for every agent of this session (13 Nov 2026, evening)

Repository: /home/user/quotesdone. NEVER work in that checkout. Make your own worktree under /tmp/claude-0/ as your
brief names it, and remove it when you hand back. QuotesDone: UAE B2B procurement marketplace; Supabase project
htdblwldjkcgjvmqkbeh (Postgres 17.6 + Deno edge functions under supabase/functions); Next.js site in src/.
Scratchpad (referred to as SP below): /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad

## Hard rules
1. NOTHING is rehearsed or executed against production: no `scripts/ci/rehearse_sql.mjs`, no `safe_replay`, no DDL, no
   EXPLAIN ANALYZE, no rehearsal mode of any check. This morning such rolled-back rehearsals held table locks on the live
   database and cancelled 103 live requests (a supplier's certificate, a quotation, a customer's terms acceptance).
   Light, time-bounded SELECTs only:
   `cd <your worktree> && NODE_USE_ENV_PROXY=1 node SP/q.mjs <file.sql>` (prints the LAST statement's result; keep your
   .sql files under SP/<your folder>/).
2. To EXECUTE SQL use a LOCAL Postgres 16 built from the schema mirror. The commands that worked today are at the end of
   `SP/handbacks/GUARD_REVIEW.md` (stand-ins: `SP/rg_standins.sql`; the probes also need seed rows: dummy
   `cred_db_internal` and `project_ref` in app_secrets, `org_role` and `org_agents` rows for the six seats, sequences
   advanced past seeded ids). Put the cluster at the path and port your brief gives, NEVER under /tmp/claude-0 (the sandbox
   resets its permissions) and not as root. Delete the cluster at the end. Postgres 16 has no `transaction_timeout`.
3. No paid model call (stub models in tests). No Stripe call. No deploy, no apply, no merge, no pull request, no message
   to any person. Never print a secret or a real person's details. Never touch leads 19398 and 158318.
4. For TypeScript checks that need node_modules: `ln -s /tmp/claude-0/gate2/node_modules node_modules` in your worktree.
   NEVER run `deno` with `--node-modules-dir=auto` and never `npm install` there (an agent did today and broke the shared
   tree). Deno tests always run as:
   `deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. --allow-net=127.0.0.1 <paths>`
   The `_shared` suite has ONE known failure on origin/main too (`catalogue_read.test.ts`, a tesseract wasm read
   permission): anything else failing is yours to explain.
5. Disk is about 5 GB free: no videos, no large corpora; delete what you generate.
6. Mark every result you report as LOCAL (local database), READ (from code) or SELECT (production read).
7. If you commit: prefix as your brief says; end each commit message with the attribution lines your harness gives you;
   name no other model anywhere. Push only to the branch your brief names.
8. This machine has restarted twice today and killed running agents. Work in small committed, pushed steps, and write
   a short progress note to `SP/progress/<your brief's name>.md` after each step (what is done, what is next), so a
   successor can continue. If such a note already exists when you start, read it first and continue from it.

## Read first, always
`.claude/CLAUDE.md`; `.claude/memory/MEMORY.md` and the notes it indexes that touch your subject;
`.claude/skills/quotesdone-apply-discipline/SKILL.md` if your work has SQL. All earlier independent reviews of today are
in `SP/show/REVIEW.md` under the headings your brief names.
