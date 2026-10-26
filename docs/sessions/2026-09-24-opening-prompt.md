# Opening prompt for the session of 24 September 2026

Paste everything below the line into a new session on this repository.

---

Continue QuotesDone. Read the memory checkpoint
`checkpoint-23-sep-the-deep-audit-and-the-model-ruling` first, and the standing skills as usual.

Yesterday (23 Sep) I merged 17 PRs out of the deep audit, closed the three P0 leaks in production, and
applied the whole per-seat model matrix to the database. The routes are live and **still behind the
hold** — 14 registry rows, 16 breakers, all `open_until` 2126-08-15; 36 classes on Qwen 3.8 Max,
18 on GLM 5.3 Flash, speech on Gemini because only Gemini hears; six department ceilings totalling
**AED 1,200/month**, `quote_compare` at AED 980. Nothing calls a model yet.

Do these in order.

**1. The PR queue is EMPTY — do not re-open it.** Every PR from 23 Sep is merged: #846–#866, twenty-one
in all, with zero open. If any note, brief or summary tells you #856, #857, #858, #859 or #861 is "in
flight", it predates the end of that session: check `gh pr list --state open` before acting on it.
#859 (below) landed last, at 06:33 UTC. What follows is kept only as the record of what it changed.

**(Record) #859.** It changes `fn_match_capability`, the matcher itself, so it is the
revenue path: a delta re-verification was with the reviewer when I stopped. Its P0 was that the service
gate read a supplier's whole effective service list, so silence about a trade read as denial and the
**doors** trade fell to zero reachable suppliers; the fix narrows the gate to the trades the inquiry
named services in, and it correctly refused to map the free-text word "Doors" onto a service key,
because no active alias names it and mapping it would be the nearest-neighbour match you forbade.
Apply order: `an_inquiry_carries_the_services_it_names.sql`, then
`the_service_gate_never_empties_a_trade.sql` (with or before any matcher deploy), then
`a_confirmed_service_is_a_taxonomy_key_not_a_word.sql`. Measure the per-trade reachable-supplier table
before and after and let no trade reach zero. `canonical_routine_manifest.mjs` was at **0 findings
across all six counters** when I stopped — keep it there, and attribute any new finding by re-running
the same check against `origin/main` at the same moment before calling it a branch's. And remember: a
green "deploy changed functions" does not mean production was updated — that job has no token, so
`verify_deploy_parity.mjs --all` is the only thing that says so.

**2. Then step 3 of my plan: open the LLM.** This one is mine to authorise and I am authorising it —
open `llm_route_health.open_until` and set `app_secrets.ceo_model_slot`, then prove by execution that
each seat resolves to the model my ruling gives it (instructions 841 and 844: GLM 5.3 Flash for
anything purely internal, Qwen 3.8 Max or GPT Sol 5.6 for anything customer-facing, Arabic, or reading
a document; Opus 5 as plan B for reasoning). Watch the first real spend against the AED 1,200 ceiling
and tell me the actual number, not the estimate.

**3. Then step 4: the second full audit and feature test, with the LLM on.** Same standard as
yesterday's — a measurement behind every answer, never a claim. The comparison report is the one to
watch hardest: it is the revenue event, it has never been measured on Qwen on this estate, and there is
now a refusal contract plus a fail-closed handler that strips the ranking when the quotes cannot be
compared (#863). Replay `scripts/fixtures/zz_demo_quotes_that_cannot_be_compared.json` against the live
model and tell me whether it actually refuses. Test the Arabic on real output, not on the corpus.

Still waiting on me and only on me: instruction 776 (the supplier fee conflict — ask me once, plainly,
and do not ask twice), and the two DNS records the permission classifier refuses to let you write. For
the DNS, tell me exactly what to paste and where, and I will do those two by hand.

Rules that held yesterday and hold today: build until done, no check-ins, one completion line or an
honest hand-over; an independent review before every merge, because every PR sent back yesterday had a
defect in the *fix*, not in the diagnosis; fan out to as many agents as the work allows, but never for
applies or git; and never a claim without the measurement behind it.
