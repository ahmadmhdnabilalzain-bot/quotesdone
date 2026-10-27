---
name: a-refused-cdn-is-worked-around-in-the-check-not-in-production
description: "When the gate's network refuses cdn.jsdelivr.net, the check moves to npm; the deployed code keeps what was measured on production (27 Oct 2026)"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-27T16:00:00.000Z
---

# A refused CDN is worked around in the check, not in production (27 Oct 2026, it_engineer)

A Claude cloud container's egress proxy refuses cdn.jsdelivr.net (CONNECT 403). registry.npmjs.org, esm.sh,
jsr.io, deno.land and raw.githubusercontent.com answer; huggingface.co and unpkg.com do not. The founder cannot
change the allow-list, so two gate steps were moved off jsDelivr **without changing what production runs**:

- **deno-all** (`ml_embed.ts`): the code import stays jsDelivr's `transformers@3.8.1/+esm`. `npm:` failed to
  deploy (500, measured 24 Sep), and the npm entry is the Node build. A `// @ts-types="npm:@huggingface/transformers@3.8.1"`
  line above it is enough: `deno check` builds a types-only graph and never fetches the +esm. The edge bundler
  (supabase/edge-runtime, `type_check_mode()` defaults to `None`, so the graph is code-only) does not follow @ts-types, so the bundle is unchanged.
  This made PR #1636's gate-side import-map substitute unnecessary.
- **dwg**: production keeps jsDelivr FIRST for the LibreDWG .wasm. The npm tarball fallback costs 160-320 ms of
  gunzip CPU per cold isolate, under a 2 s cap. The check grants only `raw.githubusercontent.com,registry.npmjs.org`
  in --allow-net, so the jsDelivr fetch is refused at once and every read there proves the npm source.

The pattern: before moving production to a new host to suit the gate, ask what production measured. Then make
the check reach the same bytes or types another way.

Related: [[ci-runs-locally-ubicloud-stopped]].
