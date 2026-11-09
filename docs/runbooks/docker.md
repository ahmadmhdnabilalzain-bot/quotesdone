# Running QuotesDone in Docker

Owner: it_engineer. Written 9 Nov 2026, on the founder's instruction that the app must sit in a container,
so that any bug can be reproduced and troubleshot the same way on any machine.

Production does not change: the website is served by Vercel, and the edge functions and Postgres by the
one Supabase project. The container gives every person and every session the **same** toolchain (node 24,
deno 2.9.4, supabase CLI 2.110.0, the same `node_modules`), so "works on my machine" stops being a cause.

## The three commands

| command | what it does |
|---|---|
| `docker compose up app` | the website on http://localhost:3000, live-reloading the files on disk |
| `docker compose run --rm checks` | the offline gate: `npm run gate -- --offline` (typecheck, `deno check` of every edge function, the unit and check suite, the SSRF/fetch-timeout/drawing checks, `npm audit`, and the OTP race against a throwaway Postgres) |
| `docker compose run --rm shell` | a bash shell at the repo root with node, deno and the supabase CLI |

`checks` and `shell` sit behind the `tools` profile, so `docker compose up` starts only the website.

The production steps of the gate (parity, kernel gate, advisors: the ones that read the live project) are
listed as `SKIPPED (production step, --offline)`, never as PASS. They need `SUPABASE_ACCESS_TOKEN` and run
with `npm run gate` from a machine that holds it. An offline run refuses `--pr`, so it can never be posted
to a pull request as a certification.

## Configuration

Copy `.env.example` to `.env.local` and fill in only what you need. Compose loads `.env.local` into every
container when the file exists. With nothing set, the site talks to the production Supabase project through
its public publishable key, the same as a visitor's browser does.

## How it is built

`Dockerfile` has five stages: `toolchain` → `deps` (npm ci, cached until `package-lock.json` changes) → `dev`
→ `build` (`next build`, the build Vercel runs) → `runner` (the production server as a non-root user, with a
health check). Compose uses `dev` and bind-mounts the repository over `/app`. `node_modules` lives in a named
volume, so the Linux builds of native packages never mix with a Windows checkout.

To build and run the production image by hand:

```bash
docker build --target runner -t quotesdone-web .
docker run --rm -p 3000:3000 quotesdone-web
```

## Graceful shutdown

The runner image starts `node node_modules/next/dist/bin/next start` directly (not `npx`, which swallows SIGTERM), and the compose services run with `init: true` and `stop_grace_period: 10s`, so `docker stop` ends the server in about a second instead of waiting for SIGKILL.

## Troubleshooting

- **`429 Too Many Requests` from Docker Hub.** Anonymous pulls are rate-limited. Use any mirror of the
  official images: `NODE_IMAGE=mirror.gcr.io/library/node:24-bookworm POSTGRES_IMAGE=mirror.gcr.io/library/postgres:16 docker compose ...`,
  or `docker login`.
- **A network that inspects TLS** (a corporate proxy, a claude.ai cloud session) makes `curl` fail inside the
  build. Pass its root certificate as a build secret, and route the build through the proxy:
  `docker build --network=host --secret id=extra_ca,src=/path/to/ca.crt --build-arg HTTPS_PROXY=$HTTPS_PROXY ...`.
  In a claude.ai cloud session the certificate is `/root/.ccr/ca-bundle.crt`, and `dockerd` has to be started
  first (`dockerd &`). The Debian package mirror is refused there, which is why the image installs nothing
  through apt.
- **`dubious ownership` from git** inside the container: the image marks `/app` safe already. If you mount
  the repo somewhere else, run `git config --global --add safe.directory <path>`.
- **Dependencies changed** (`package-lock.json` moved): the `app` and `checks` services run `npm ci` on start
  into the volume. To start clean: `docker compose down -v`.
- **psql**: the image has none. Use the throwaway database's own: `docker compose exec db psql -U postgres`.
