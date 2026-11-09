---
name: docker-and-a-local-database-in-a-cloud-session
description: "9 Nov 2026: a claude.ai cloud session CAN run Docker and a full local Supabase Postgres. Start dockerd, pull through mirror.gcr.io (Docker Hub 429s), build with --network=host + the proxy CA as a build secret (deb.debian.org is refused, so the image installs nothing via apt). npm run db:local then rebuilds the whole public schema from the mirror and measures it."
metadata:
  type: reference
  modified: 2026-11-09
---

Measured 9 Nov 2026 in a cloud session (it_engineer):

- `docker` is installed but no daemon runs: `dockerd >/tmp/dockerd.log 2>&1 &` starts one in seconds.
  (The 28 Oct note "no Docker daemon" was about not starting one.)
- Docker Hub answers anonymous pulls with 429. `mirror.gcr.io/library/<image>` and
  `public.ecr.aws/docker/library/<image>` both work. `supabase start`/`supabase db start` pull from
  ghcr.io/public.ecr.aws and work as they are.
- Inside a build, the egress proxy on 127.0.0.1 is only reachable with `--network=host`; pass
  `--build-arg HTTPS_PROXY=$HTTPS_PROXY` (and http/no_proxy) and `--secret id=extra_ca,src=/root/.ccr/ca-bundle.crt`.
  The Debian mirror (deb.debian.org) is refused, which is why the Dockerfile uses the full node image and
  installs nothing through apt. Full commands: docs/runbooks/docker.md.
- `supabase db start` in a scratch `supabase init` folder gives Supabase Postgres 17.6.1.143; then
  `npm run db:local` (scripts/db/local_from_mirror.mjs) replays the committed mirror: 784/784 tables,
  88/88 views, all routines, 350/350 policies, 398/398 triggers, 92 cron jobs all switched off.
  docs/runbooks/local-database.md. A `supabase db reset --local` recreates the container, so anything
  docker-cp'd into it is gone afterwards.
- Never replay the raw mirror with psql against a database that pg_cron serves: its cron.schedule lines
  create ACTIVE jobs (it happened once on 9 Nov, locally: 1 job ran on an empty database, 0 HTTP requests).
  The builder creates every job switched off in the same statement.

Related: [[deno-node-modules-auto-breaks-next-build]], [[the-otp-race-step-runs-on-a-throwaway-postgres-in-the-cloud-container]].
