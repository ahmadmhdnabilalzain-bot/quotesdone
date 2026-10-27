---
name: a-verifier-that-reads-what-it-expects
description: A vision verifier can report identifiers verbatim from a solid black rectangle — always open the published image before believing either verifier.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 8c3f363e-c107-4cc8-a2b7-67b6692cd25a
  modified: 2026-08-13T13:28:16.707Z
---

13 Aug 2026. `drawing_redact`'s two model calls never named a task_class, so `fn_ai_route` fell
through to `general_drafting` instead of the pack's `redaction_detection` policy. Naming the policy
looked like an obvious win. On staging it made the verifier **refuse correctly-redacted pages** and
list the fixture's eight planted identifiers verbatim — company, client, project, plot, phone,
email, web, drawing number — as "still legible".

They were not. The published JPGs were pulled from the `drawing-files` bucket and looked at: the
title block is one solid black rectangle and the watermark is covered by a staircase of black
boxes. The verifier reported what a title block *usually* contains, primed by its own prompt.

**Why:** a model asked "what identity can you still read here?" will answer with the identity it
expects, and a `found` list reads exactly like evidence. Two sessions could have chased a leak that
does not exist, or "fixed" the redactor to satisfy a hallucination.

**How to apply:** on any vision-verification path, the tiebreaker is the artefact, not either
model. Pull the published bytes and LOOK. Also: a `model_policy` row that governs nothing is
normally a build order ([[specs-are-upgrades-not-repairs]]), but adopt it by measuring, not by
authority — this one was measured and rejected. Recorded at the call site in
`supabase/functions/drawing_redact/index.ts` so the next session does not repeat it.
