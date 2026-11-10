---
name: chromium-in-the-cloud-container-cuts-requests-at-30-seconds
description: "27 Oct 2026: in a cloud session container, Playwright Chromium fails a request longer than ~30 s with net::ERR_FAILED / MissingAllowOriginHeader while the server answers 200. Check function_edge_logs and repeat from Node before calling it a product defect."
metadata:
  type: feedback
  modified: 2026-11-10
---
# Chromium in the cloud container cuts a request at ~30 s

Measured 27 Oct 2026 (it_engineer, supplier registration walk; report
`docs/reports/supplier_registration_e2e_27_oct/SUPPLIER_REGISTRATION_E2E_27_OCT.md`).

In a cloud session container, a Playwright Chromium request that runs longer than about 30 s fails with
`net::ERR_FAILED`. CDP shows `corsError: MissingAllowOriginHeader`, on a connection to the container's egress
proxy at 127.0.0.1. Disabling HTTP/2 does not change it.

The same request gets the server's real 200 with the correct CORS header from all of these:
- Node fetch, with or without `apikey`, at 44–47 s
- curl through the same proxy, with Chrome's exact User-Agent, at 58 s

`function_edge_logs` shows the server answered 200 every time.

**So:** in a walk, a browser failure at about 30 s on a slow action is the container's network path until the
edge log says otherwise. Read `function_edge_logs` and repeat the call from Node before calling it a product defect.
A slow action is still worth fixing, though: anything that keeps a supplier waiting 40–60 s fails the same way
behind any short-timeout intermediary. That is why #1668 answers the Services confirm before reading the words.

**Re-measured 10 Nov 2026 (customer_support, supplier_full_walk c):** extract_quote answered 200 at 46 s on production
and at 30,974 ms on a local build, and the page received neither (production console: "blocked by CORS policy: No
'Access-Control-Allow-Origin' header"). A local `next build && next start` calls Supabase directly, like production,
so browser.mjs's preview route does not help. Set **`QD_ROUTE_FUNCTIONS_VIA_NODE=1`** (browser.mjs, opt-in): the
page's calls to the project's functions then go through Node, with the run tag added, and a walk judges the product
and not the container. With it, the same read once came back 546 WORKER_RESOURCE_LIMIT under another session's
concurrent document reads, so a 546 is a separate finding, not the cut.

Two more container facts from 27 Oct:
- Another session's `deno … --node-modules-dir=auto` relinked the shared `node_modules/playwright` to 1.64.1. That
  version wants browser build 1248, but `/opt/pw-browsers` has 1243. Give the worktree its own `node_modules` with
  playwright 1.63 rather than running `playwright install`.
- Harness teardown takes 4–12 minutes (one management-API statement per table). Give a walk's shell timeout room
  for it, or its rows outlive the run. Purge later by tag with the harness's own `teardown`.
