# Journey evidence pack, 10 Nov 2026: harness, the stopped real run, and three product findings

Seat: customer_support. Founder ledger 1604 ("proof, not a test summary"), spend cap ledger 1595.
Harness: `scripts/e2e/evidence_pack.mjs` (`--dry` = models off; the real run is capped by its rehearsal window).
Binaries (screenshots, PDFs, the recording) are not in git; the pack is delivered as a zip.

## Where it stands

| run | tag | models | what it did | USD (ai_cost_log by tag) | teardown |
|---|---|---|---|---:|---|
| dry 1-5 | 1cb58b6d, 1328b26a, 8953729f, (dry3), (dry5) | off | all four journeys end to end, then J1, J3 and J4 again after each fix | 0.0000 | 0 leftovers each; every notification `suppressed` |
| real 1 | 6bcb8f03 | on, cap 4 | journey 1 complete; stopped in journey 2 (findings a-c) | **0.5227** (51 calls: inquiry_intake, quote_extract, supplier_api) | purged with `run.mjs --purge-tag`, plus 2 signed-terms PDFs removed by hand; 0 rows, 0 objects, window closed |
| real 2 | 9002e219 | on, cap 3.4 | stopped on the coordinator's STOP about a minute in (1 customer, 1 supplier made) | 0.0000 | purged; 0 leftovers, window closed |

Dispatch: real run 1 was stopped before the harness's own safety step, so no one counted its notifications by
status before teardown deleted them. That is not measured. The capture guard (`zzzz_notifications_demo_capture`)
was installed, and every dry run of the same flows counted 0 sent/queued/pending, every row `suppressed`.

The real run waits on the fixes below. It is run once, after they are deployed.

## (a) The hold desk cannot supply the detail its own release demands

**What happened (real run 1, journey 1, request 1dc22dce-0a77-43fa-9fca-5775daf28c7d, RFQ 164464).** Four suppliers
uploaded a quotation PDF (`extract_quote` read each one by code, `submit_quote` with `source: 'upload'`). Each quote was
held (`code: spec_hold`). On the hold desk each supplier filled every field `spec_hold` showed. `spec_fill` answered
`HTTP 200 complete: true`. `spec_approve {confirm: true}` then answered `HTTP 409 code: still_missing`, and the hold went back to `open`.

| quote | supplier (ZZ DEMO) | spec_hold asked | spec_fill | spec_approve |
|---|---|---|---|---|
| 1be9b3fa-6abf-4f0f-9c44-0293e1e1802a | Al Noor Interiors | line 2: species, thickness_mm, finish, edge_band, fire_rating, brand, standard; line 3: roll_size, brand; line 4: profile_system, standard, component_main | 200 complete:true | 409 still_missing |
| e7e62988-23bf-4128-8523-ca3e192703b0 | Gulf Panel Systems | same | 200 complete:true | 409 still_missing |
| 593d63f5-c70e-4d8b-80c3-80f445a44847 | Emirates Wall Concepts | same | 200 complete:true | 409 still_missing |
| 6665a06c-3684-4ea0-9ddb-99eaae690777 | Marina Decor Contracting | same | 200 complete:true | 409 still_missing |

After the 409, the reopened `quote_spec_hold.missing` held line-scope items with `attr: "specification"`, labelled
"Your line 1 (Removal and disposal of existing PVC wall panels): state the exact exact specification (what it is,
material, size, make and model)", with the same item for line 2. The read was cut at 1,500 characters, so lines 1-2
are certain and lines 3-4 were not read. None of the four ever reached the customer, so journey 1 had 0 live
quotes: no comparison, no reveal, no invoice.

**Root cause.**
- `supabase/functions/supplier_api/actions/quotes.ts:136-141` (`spec_hold`) builds the form from
  `deskAssess(...)` alone (`formSchema(a, lines)`). It never reads the stored hold's `missing`.
- `supabase/functions/_shared/line_specs/workflow.ts:238-244` (`formSchema`) lists only `a.lines` with `defs`, plus
  `termsAsked(a.missing)`.
- `supabase/functions/supplier_api/actions/quotes.ts:165-178` (`spec_approve`) gives `approve()` a precheck that runs
  `reviewQuotation(..., readWorking(...))`, the quotation review with reasoning. Its issues become missing items through `issueAsMissing`.
- `supabase/functions/_shared/line_specs/workflow.ts:443-446`: a precheck with issues puts the hold back to `open`
  carrying them, and answers `still_missing`.
- The detail it demands is `SPEC_ATTR` (`supabase/functions/_shared/line_specs/assess.ts:208-211`, code
  `specification`). It is asked for a line of a composite quote whose trade was not read. The request had been
  placed as `fitout` (finding b), which is a composite, so the review asked it. The desk's own assessment did not.

So the precheck and the form ask different questions, the hold carries the precheck's answer, and the form never
shows it. A supplier who fills in everything shown loops on 409 with nothing on screen to fix. This is the same class
as the validity case that `deskAssess` already fixes (workflow.ts:211-216, "the hold desk asks everything its release asks").

**Not measured.** I have not measured whether `fillIn` (workflow.ts:330) would accept a `specification` value if the
form offered one. It did not happen in the HVAC or transport journeys only because run 1 never reached their quotes.

**Workaround in the harness, which a real supplier can also do.** The quotation PDFs carry a `Specification` column,
which `quote_from_document.ts` `roleOf` maps to the line (role `spec`), so the line states its specification at upload.

## (b) A PVC wall-panel job was placed as interior design and fit-out, then went "ready" with blocking specs unanswered

**The customer's words (first message, typed in /me, New request):**
"Hello. In our office in Business Bay, Dubai, we have an MDF partition wall covered with PVC wall panels. The panels
are old, scratched and some are coming off. We want the old PVC panels removed and new PVC wall panels installed on
the same MDF partition."

**Where the intake placed it:** `brief.category: "interior-design"`, `brief.trades: ["interior-design", "carpentry-joinery"]`,
`brief.trade_codes: ["interior_fitout", "joinery"]`, and the inquiry stored `category: "fitout"`. The service keys were
right: `["wallpaper.wall_cladding", "wallpaper.wall_panels", "interior_fitout.refurbishment", "joinery.wood_panelling"]`.
The wall-panel trade itself (`wallpaper`, whose services are "Wall panels" and "Wall cladding") is not among the trades.

**Checklists it asked from** (`public.trade_spec_checklist`):
- `interior_fitout:fitout-spec-checklist`, blocking: location, landlord handover condition and fit-out guide, use/occupancy,
  design brief or drawings, MEP scope, authority approvals and responsibility.
- `joinery:spec-checklist`, blocking: item type, dimensions from site measurement, core material and thickness, veneer,
  ironmongery and hardware, quantity per item.
- `gypsum:partition-spec-checklist` (asked on turn 1: partition type, fire rating in minutes, acoustic rating Rw/STC,
  board EN 520 type).
- The "Give the specifications" guide on screen showed `design_consultancy:spec-checklist` ("Design consultancy -
  what the buyer must state: project type and area; design stages included; deliverables; ...").

**How it went "ready".** The sales engineer asked "MEP scope" and the customer answered the date. It asked
"Authority approvals and responsibility" and the customer answered the warranty. Each answer was recorded as the
answer to the question asked. This is the ready brief, verbatim:

```json
"spec_mep_scope": "We need it finished by 15 December 2026.",
"spec_authority_approvals_and_responsibility": "At least 2 years warranty on materials and installation."
```

The turn before ready read `status "held", readiness {"filled":15,"required":20,"score":80}`. Its open items were
"Authority approvals and responsibility" and "Do you need a warranty, and for how long at least?". The next turn read
`status "ready", readiness {"filled":20,"required":20,"score":80}` ("Thank you — that is everything suppliers need").
On the ready screen, the chips still open under "Tap a question to answer it" were:
- "Does the job involve any electrical, AC or lighting work on or near the wall, such as moving sockets or switches?"
- "Does the building management need to approve the work, and who will arrange that, you or the contractor?"

So the two blocking specs were "answered" by text that does not answer them. The suppliers' PDF and inquiry show
those values. The brief's `site_visit` / known condition read: "A site visit is unavoidable before a firm fit-out
price, to check the landlord handover condition, existing MEP and access. | Site visit needed before a final price ... fitted joinery is always re-measured before production."

## (c) The live matcher invited no supplier

Request 1dc22dce-0a77-43fa-9fca-5775daf28c7d: `create_inquiry` answered `matches: 0`, and `inquiry_matches` held no row.
Trades `interior_fitout, joinery` (brief slugs `interior-design, carpentry-joinery`). Service keys
`wallpaper.wall_cladding, wallpaper.wall_panels, interior_fitout.refurbishment, joinery.wood_panelling`. Emirate Dubai.
The five ZZ DEMO suppliers of the run were `wallpaper` suppliers, with confirmed services Wall panels and Wall
cladding (services_rewrite then services_save_rewrite).

**Measured cause: the request was sent as `scope_type: "turnkey"`, which routes with `p_need: "whole_scope"`.** In
that need, only a `turnkey_fitout` role passes.
- The stored request read `scope_type: "turnkey"`, trades `["interior-design","carpentry-joinery"]`, category `fitout`.
- `src/components/me/NewRequest.tsx:72` preselects `combineMode = 'turnkey'` (ruling 1021: one contractor by
  default). `NewRequest.tsx:452` sends it as `scope_type` whenever the brief names two or more trades.
- `supabase/functions/sales_engineer/actions/operator.ts` (match) turns a `scope_type` containing "turnkey" into
  `need = 'whole_scope'` and calls `fn_match_capability` with it.

A probe after teardown reproduced it with one fresh ZZ DEMO `wallpaper` supplier: wall_panels, wall_cladding,
supply_install and removal confirmed through services_rewrite and services_save_rewrite, roles contractor,
installer and supplier, models off, cost 0. It called the RPC read-only and was torn down with 0 leftovers.

| p_trades | p_need | p_services | rows | the wallpaper supplier |
|---|---|---|---:|---|
| interior_fitout, joinery | executes | the four keys above | 1 | matched, score 15: "reached through wallpaper (the named service's trade ...) · 2/4 services · in Dubai" |
| interior_fitout, joinery | **whole_scope** | the four keys above | **0** | not matched |
| wallpaper | executes | the four keys above | 1 | matched, score 15 |

So the matcher reaches a supplier through a named service's trade, and it would have found this run's five
suppliers. The request asked only for a turnkey fit-out contractor. The customer never chose that: it is the
composer's preselected default, applied because (b) placed a one-trade job (PVC wall panels) under two trades.

## Harness notes (for the re-run)

- Playwright 1.65 in the repo's node_modules expects chromium build 1254 and ffmpeg 1013. The container had 1243
  and 1011, and 1011 could not encode video. The container's own copies were symlinked (`/opt/pw-browsers/*-1254`,
  `ffmpeg-1013 -> /usr/bin/ffmpeg`). That is an environment fix, not a repo change.
- The site's CSP (`connect-src`) refuses a fetch to any other host, so the voice note's audio is handed to the page
  as bytes. The microphone then gives `MediaRecorder` that audio, and everything after it is the product's own path.
- A quotation that leaves out a scope item cannot pass the upload form (the review refuses an unpriced BOQ line).
  That supplier goes through the quotation chat and says "BOQ line N excluded — by the client". The customer then
  sees the `scope_excluded` review note. This was measured in dry run 3: "This quote lists 'Removal and disposal of
  existing PVC wall panels' under its exclusions, but it is part of what you asked for. The price does not cover it."

## The re-run after #1896 (tag ea40c830, 19:11-20:01 UTC) and the registration (tag 8120d011, 20:09-20:28 UTC)

Stopped by founder ruling 1608 (a free code audit first) after journey 2. Journey 3 was not started: the harness
was sent SIGTERM at its first line, and its stop path counted, read the spend and tore down. The partial pack is
`QuotesDone_journey_evidence.zip`, delivered outside git.

| | USD (ai_cost_log by tag) | notifications counted BEFORE teardown | leftovers |
|---|---:|---|---|
| journeys 1-2 | 1.3920 (128 calls) | 53 e-mail + 51 WhatsApp, all `suppressed`, 0 dispatched | 2 notifications written after teardown (a journey-3 supplier's `supplier_approved`, both `suppressed`), removed with `run.mjs --purge-tag`; then 0 |
| registration | 0.0245 (9 calls) | none | 0, plus 0 on the Resend sink account |

Today's total, including real run 1 (0.5227): USD 1.9392.

**Fixed and seen working:** (b1) the PVC job was placed in `wallpaper`, one trade. (b2) No unrelated answer was recorded
as a spec. (c) Journey 2 was sent as `scope_type: single`; routing gave need `executes`, fan-out 8, and all five of
the run's HVAC suppliers were matched by the product.

**Still seen:**
1. **Journey 1 hold form ≠ release, line 3 material.** Quotes f5b1b5b6, 12266a2e, 080e2091 and a6f89b7f. The form
   showed line 2 material/roll_size/brand, line 3 roll_size/brand and line 4 material/roll_size/brand. The supplier
   filled all of them. `spec_fill` answered 200 `complete:false missing ["material"]`, and the hold went to
   `unresolved_at_decision`, missing `line 3 material` ("state the exact wallpaper type"). Quote 080e2091 was also
   missing line 4. That line's Specification column ("PVC panel 8 mm, 250 x 2800 mm, light oak matt, made in
   Germany, Class B-s1,d0") was not taken as the answer. Result: only the quotation-chat quote went live, so there
   was no comparison. With the fix agent.
2. **Journey 2's drawing did not reach suppliers.** The PDF drawing came back as an OCR read in the composer, with
   junk lines ("Stroked line length", "Closed shapes 81") and one line carrying title-block text, the client name
   misread as "Mir. 22 Demo Owner". `drawing_redacted_paths` was null on the request. The harness saw no
   `analyze_drawing` answer within 420 s. In the models-off dry run the same file was read from its text layer
   (12 lines) and redacted 1/1. Not diagnosed.
3. **Journey 2 Q2 (72b94ebd)** was released through the hold desk (`spec_approve released:true`), but quote_compare
   listed it as `held` with no rank. Not diagnosed.
4. **Journey 2 comparison: correct and expert.** The top 3 were Q3 (only full match), Q1 (same tier, made in
   Thailand) and Q5 (cheapest, Chinese brand, short warranty, late). The review notes named each origin deviation,
   warranty shortfall and late delivery. This is recorded as working, not as a defect.

**Harness issues, not product:**
- The composer's mount-time `carry_from:'portal'` call was taken as the opener's reply. The next line was sent
  before `intake_id` existed, which opened a stray intake (202a03c2). The fix is in the harness.
- On the quotation chat the harness answered "model / product code: As per the BOQ line", which the engineer
  rightly refused. A real supplier states a code.
- The registration's fixture-mobile path (the DB write while the form's kyc `state` read is held) did not register
  on this run, so Submit stopped at "Still needed: Verified mobile number, your WhatsApp answer". It worked in three
  dry runs that afternoon. Not diagnosed, and not shown to be a product defect.
