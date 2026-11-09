# syntax=docker/dockerfile:1.7
#
# QuotesDone in a container (it_engineer, 9 Nov 2026).
#
# One image definition for every way the code is run outside Vercel, so a bug reproduces the same way
# on the founder's laptop, in a cloud session and on any engineer's machine:
#
#   toolchain  node 24 + deno + supabase CLI + git, the exact versions scripts/cloud/setup.sh pins
#   deps       toolchain + node_modules from package-lock.json (cached until the lockfile changes)
#   dev        the source on top of deps; `next dev` by default. docker-compose.yml bind-mounts the repo
#              over /app instead, so edits are live and the git history the checks read is there.
#   build      `next build`, the same build Vercel runs
#   runner     the production server (`next start`) on port 3000, as a non-root user
#
# Production is still served by Vercel (web) and Supabase (edge functions, Postgres). This image does
# not replace either; it makes the code runnable, testable and debuggable anywhere. See
# docs/runbooks/docker.md for the commands.
#
# Docker Hub rate-limits anonymous pulls (429 measured 9 Nov 2026 from a cloud session). Any mirror of
# the official image works: --build-arg NODE_IMAGE=mirror.gcr.io/library/node:24-bookworm
#
# The FULL node image (not -slim) is deliberate: it already carries git, curl, unzip and the CA tooling,
# so the build installs nothing through apt. A network that blocks the Debian mirror (measured 9 Nov
# 2026: a cloud session's egress refuses deb.debian.org) can still build it. psql is not in the image;
# use `docker compose exec db psql -U postgres` for the throwaway database.
ARG NODE_IMAGE=node:24-bookworm
ARG RUNNER_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE} AS toolchain
ARG DENO_VERSION=2.9.4
ARG SUPABASE_VERSION=2.110.0
ARG TARGETARCH
ENV NEXT_TELEMETRY_DISABLED=1 \
    DENO_NO_UPDATE_CHECK=1 \
    DENO_NO_PACKAGE_JSON=1 \
    DENO_TLS_CA_STORE=system \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
# Optional extra root certificate, for a network that inspects TLS (a corporate proxy, a cloud
# session's egress proxy). Not needed on a normal connection; nothing is installed when it is absent.
#   docker build --secret id=extra_ca,src=/path/to/ca.crt ...
RUN --mount=type=secret,id=extra_ca,required=false \
    if [ -s /run/secrets/extra_ca ]; then \
      cp /run/secrets/extra_ca /usr/local/share/ca-certificates/extra-ca.crt && update-ca-certificates; \
    fi
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) DENO_TRIPLE=x86_64-unknown-linux-gnu ;; \
      arm64) DENO_TRIPLE=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported arch ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${DENO_TRIPLE}.zip" -o /tmp/deno.zip; \
    unzip -q /tmp/deno.zip -d /usr/local/bin; rm /tmp/deno.zip; \
    curl -fsSL --retry 3 "https://github.com/supabase/cli/releases/download/v${SUPABASE_VERSION}/supabase_linux_${TARGETARCH:-amd64}.tar.gz" \
      | tar -xz -C /usr/local/bin supabase; \
    deno --version; supabase --version; \
    git config --system --add safe.directory /app
WORKDIR /app

FROM toolchain AS deps
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund --loglevel=error

FROM deps AS dev
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--hostname", "0.0.0.0"]

FROM dev AS build
RUN npm run build

FROM ${RUNNER_IMAGE} AS runner
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
WORKDIR /app
COPY --from=build --chown=node:node /app/package.json /app/package-lock.json /app/next.config.mjs ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/public ./public
COPY --from=build --chown=node:node /app/messages ./messages
COPY --from=build --chown=node:node /app/src ./src
COPY --from=build --chown=node:node /app/.next ./.next
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# node, not npx: npx runs next as a child and swallows SIGTERM, so `docker stop` waited 10 s then SIGKILLed.
CMD ["node", "node_modules/next/dist/bin/next", "start"]
