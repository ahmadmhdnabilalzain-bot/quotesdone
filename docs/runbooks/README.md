# Runbooks

Step-by-step procedures for running QuotesDone. Owner: it_engineer. Release and rollback procedures that
predate this folder live in [../it/](../it/): [ROLLBACK.md](../it/ROLLBACK.md) and
[BACKUP_RPO_RTO.md](../it/BACKUP_RPO_RTO.md).

| Runbook | What it is for |
|---|---|
| [incident-response.md](incident-response.md) | Severity levels, the first 15 minutes, where to look, who decides what |
| [restore-and-disaster-recovery.md](restore-and-disaster-recovery.md) | PITR vs the daily export vs the Dropbox copy; running a restore drill on a branch; what to record |
| [release-without-ci.md](release-without-ci.md) | Shipping with GitHub Actions off: what runs instead, and where |
| [local-database.md](local-database.md) | A local Postgres with the whole production schema, built from the repo in ~15 s and measured object by object |
| [docker.md](docker.md) | Running the site, the checks and a shell in Docker; graceful shutdown; troubleshooting |
| [cloud-sessions.md](cloud-sessions.md) | Running Claude Code on this repo from claude.ai/code |
| [keys.md](keys.md) | Every key a session needs, where to copy it from, where it is stored (names only) |
| [admin-two-step-sign-in.md](admin-two-step-sign-in.md) | Admin two-step sign-in (authenticator app): enrolment at /admin, recovering a lost phone, the release steps |
| [kb_chunks_rewrite.md](kb_chunks_rewrite.md) | Giving `public.kb_chunks` dead space back to the disk (copy-and-swap) |
