#!/usr/bin/env bash
# Prepares a Linux machine for a QuotesDone Claude Code session (owner: it_engineer, 26 Oct 2026).
#
# Built for claude.ai/code cloud sessions, which the founder runs from his phone with nothing on his
# Windows laptop. It installs the tools a session needs, then checks that every required environment
# variable is present. It never prints a value. Guide: docs/runbooks/cloud-sessions.md.
#
#   bash scripts/cloud/setup.sh            install what is missing, then the self-check
#   bash scripts/cloud/setup.sh --check    the self-check only
#
# Idempotent: a tool already at the right version is left alone, so a second run takes seconds.
# .claude/settings.json runs it at SessionStart only when CLAUDE_CODE_REMOTE=true (a cloud session).
# Versions match CI (.github/workflows/checks.yml: node 24, deno 2.x) and the laptop of 26 Oct 2026.
set -uo pipefail

NODE_MAJOR="${QD_NODE_MAJOR:-24}"
DENO_VERSION="${QD_DENO_VERSION:-2.9.4}"
SUPABASE_VERSION="${QD_SUPABASE_VERSION:-2.110.0}"
GH_VERSION="${QD_GH_VERSION:-2.96.0}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="${QD_TOOLS_DIR:-$HOME/.qd-tools}"
BIN="$HOME/.local/bin"
mkdir -p "$TOOLS" "$BIN"
export PATH="$BIN:$PATH"

say() { printf '[qd-setup] %s\n' "$*"; }

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64; NODE_ARCH=x64; DENO_TRIPLE=x86_64-unknown-linux-gnu ;;
  aarch64|arm64) ARCH=arm64; NODE_ARCH=arm64; DENO_TRIPLE=aarch64-unknown-linux-gnu ;;
  *) say "unsupported CPU $(uname -m)"; exit 1 ;;
esac

fetch() { curl -fsSL --retry 3 --connect-timeout 20 "$1" -o "$2"; }

unzip_to() {  # unzip_to <zip> <dir>: unzip is not on every image
  if command -v unzip >/dev/null 2>&1; then unzip -oq "$1" -d "$2"
  else python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"; fi
}

install_node() {
  local have; have="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')"
  if [ "${have:-0}" -ge "$NODE_MAJOR" ] 2>/dev/null; then return 0; fi
  say "installing node $NODE_MAJOR (found ${have:-none})"
  local base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x" tmp; tmp="$(mktemp -d)"
  local file; file="$(curl -fsSL "$base/SHASUMS256.txt" | awk '{print $2}' | grep -E "^node-v[0-9.]+-linux-${NODE_ARCH}\.tar\.xz$" | head -1)"
  [ -n "$file" ] || { say "could not find a node $NODE_MAJOR build for linux-$NODE_ARCH"; return 1; }
  fetch "$base/$file" "$tmp/node.tar.xz" || return 1
  curl -fsSL "$base/SHASUMS256.txt" | grep " $file\$" | sed "s| $file\$| $tmp/node.tar.xz|" | sha256sum -c --quiet - || { say "node checksum mismatch"; return 1; }
  rm -rf "$TOOLS/node" && mkdir -p "$TOOLS/node" && tar -xJf "$tmp/node.tar.xz" -C "$TOOLS/node" --strip-components=1
  for b in node npm npx; do ln -sf "$TOOLS/node/bin/$b" "$BIN/$b"; done
  rm -rf "$tmp"
}

install_deno() {
  if deno --version 2>/dev/null | head -1 | grep -q "deno $DENO_VERSION "; then return 0; fi
  say "installing deno $DENO_VERSION"
  local tmp; tmp="$(mktemp -d)"
  fetch "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${DENO_TRIPLE}.zip" "$tmp/deno.zip" || return 1
  unzip_to "$tmp/deno.zip" "$TOOLS/deno-$DENO_VERSION" && ln -sf "$TOOLS/deno-$DENO_VERSION/deno" "$BIN/deno"
  chmod +x "$BIN/deno"; rm -rf "$tmp"
}

install_supabase() {
  if [ "$(supabase --version 2>/dev/null)" = "$SUPABASE_VERSION" ]; then return 0; fi
  say "installing supabase CLI $SUPABASE_VERSION"
  local tmp; tmp="$(mktemp -d)"
  fetch "https://github.com/supabase/cli/releases/download/v${SUPABASE_VERSION}/supabase_linux_${ARCH}.tar.gz" "$tmp/sb.tgz" || return 1
  mkdir -p "$TOOLS/supabase-$SUPABASE_VERSION" && tar -xzf "$tmp/sb.tgz" -C "$TOOLS/supabase-$SUPABASE_VERSION"
  ln -sf "$TOOLS/supabase-$SUPABASE_VERSION/supabase" "$BIN/supabase"; rm -rf "$tmp"
}

install_gh() {
  if gh --version 2>/dev/null | head -1 | grep -q "gh version $GH_VERSION "; then return 0; fi
  say "installing gh $GH_VERSION"
  local tmp; tmp="$(mktemp -d)"
  fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" "$tmp/gh.tgz" || return 1
  rm -rf "$TOOLS/gh-$GH_VERSION" && mkdir -p "$TOOLS/gh-$GH_VERSION" && tar -xzf "$tmp/gh.tgz" -C "$TOOLS/gh-$GH_VERSION" --strip-components=1
  ln -sf "$TOOLS/gh-$GH_VERSION/bin/gh" "$BIN/gh"; rm -rf "$tmp"
}

install_packages() {
  [ -d "$REPO/node_modules" ] && return 0
  say "installing npm packages (npm ci)"
  (cd "$REPO" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci --no-audit --no-fund --loglevel=error)
}

FAILED=()
if [ "${1:-}" != "--check" ]; then
  for step in install_node install_deno install_supabase install_gh install_packages; do
    "$step" || FAILED+=("$step")
  done
  # Later commands in this session see the installed tools (SessionStart hooks get CLAUDE_ENV_FILE).
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then echo "export PATH=\"$BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"; fi
fi

# ── self-check: names only, never a value ──────────────────────────────────────────────────────
# Required: without these a session cannot read or change production, or open a PR.
REQUIRED=(SUPABASE_ACCESS_TOKEN GH_TOKEN)
# Optional: one script each; their own error names them when missing.
OPTIONAL=(QD_AI_GATEWAY_SECRET)

MISSING=()
[ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_TOKEN:-}" ] && export GH_TOKEN="$GITHUB_TOKEN"  # gh accepts either
for v in "${REQUIRED[@]}"; do [ -n "${!v:-}" ] || MISSING+=("$v"); done
for v in "${OPTIONAL[@]}"; do [ -n "${!v:-}" ] || say "optional $v not set (only scripts/eval/reasoning_eval.mjs --live needs it)"; done

for t in node deno supabase gh; do
  if command -v "$t" >/dev/null 2>&1; then say "$t: $("$t" --version 2>/dev/null | head -1)"; else say "$t: NOT INSTALLED"; MISSING+=("tool:$t"); fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then say "install steps that failed: ${FAILED[*]} (check the environment's network access)"; fi
if [ "${#MISSING[@]}" -gt 0 ]; then
  say "MISSING: ${MISSING[*]} -- add each variable in the claude.ai/code environment settings (docs/runbooks/cloud-sessions.md)"
  exit 1
fi
say "ready: every required variable is present and node, deno, supabase and gh are installed"
