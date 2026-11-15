# Anonymity fix round, 13 Nov 2026: common brief for every fix agent

Repository: /home/user/quotesdone. Do NOT work in that checkout (the main session uses it). Make your own
worktree from origin/main under /tmp/claude-0/ as your brief names it, and remove it when you hand back.
QuotesDone: UAE B2B procurement marketplace. Supabase project htdblwldjkcgjvmqkbeh (Postgres + Deno edge
functions under supabase/functions), Next.js website under src/.

## Read first
- `.claude/CLAUDE.md`, `.claude/memory/MEMORY.md` and the notes it indexes on identity, anonymity, drawings,
  brands, documents, the model reading first, and tests (the "identity shapes" note and its two over-redaction
  lists are binding: a fix that removes more than identity is a defect too).
- The audit brief `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/anon/COMMON.md`.
- The three audit reports in the same folder: `REPORT_A.md` (customer to supplier), `REPORT_B.md` (drawings),
  `REPORT_C.md` (supplier to customer). Each auditor's drivers, fixtures and outputs are in
  `anon/A_customer_to_supplier/`, `anon/B_drawings/`, `anon/C_supplier_to_customer/`. Their harnesses import from
  worktrees that no longer exist: point them at yours.

## The founder's ruling (ledger public.founder_instruction id 1683, 13 Nov 2026), the parts that bind you
"anonymity is the most important thing in this platform. … He removes the details of the existing supplier and
reformat the inquiry in our template and shares it with the suppliers … all the project details, the customer
details that are there in those drawings are removed … Suppliers … Anywhere in their quote, it shows their name,
their address, whatever. All those will be removed, reformatted in our template, and just the quotation itself,
content in terms of item name, description, warranty, services, country of origin. These details can be shared.
… there's no single document that goes in this platform unless it's under our template. … Dubai in general is
okay. We can keep that. But villa number, for example, has to be hidden. … Al Barsha 2, Villa 15 … Al Barsha and
Villa 15 need to be hidden when they are shared with the supplier. … These are extremely important because these
are the core of the app."
Standing rulings: 1663/1664/1666 the model reads documents and chats first, code never interprets first; code is
the BACKSTOP that must hold when the model is careless. 1671/1672 every document is a PDF on our template.

## Rules of the round
- The emirate may cross. Nothing below the emirate may: area, community, street, building, tower, villa, unit,
  plot, Makani, coordinates, a landmark ("near Mall of the Emirates"), in English or Arabic.
- Every leak you close gets a PLANTED fixture in a permanent test (the auditor's probe strings and files are the
  starting corpus), and every fix is run against the over-redaction lists: quantities, dimensions, levels, model
  numbers, standards, warranties and countries of origin must survive. Report both numbers: leaks closed, and
  legitimate strings wrongly removed (must be 0, or named).
- Fail closed without a person: when in doubt REMOVE the span (or withhold the field) and say so in the document
  ("[site details withheld]"); do not create a state that waits for a human unless the report names why nothing
  else is possible.
- No paid model call. No call of any kind to production: read code, run offline (deno test, node checks, the
  auditors' drivers). SELECT-only reads of production are allowed where you need a shape or a count.
- ZZ DEMO identities only in fixtures. Never touch or print anything of leads 19398 or 158318. Never print a secret.
- You may NOT deploy, apply SQL, merge, change a switch or write to Dropbox. If your fix needs SQL, write the file
  under scripts/sql with its probe and a pending note exactly as the `quotesdone-apply-discipline` skill says
  (.claude/skills/quotesdone-apply-discipline/SKILL.md), and say so in the hand-back.
- Stay inside the files your brief gives you. If a fix needs a file another agent owns, do NOT edit it: say what
  is needed in the hand-back.
- Tests to run before hand-back: `deno test` for every function folder you touched with
  `--no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. --allow-net=127.0.0.1`,
  the relevant `scripts/checks/*` (run a single check file with node; do NOT run `scripts/checks/run.mjs --help`,
  it runs all 700), `npx tsc --noEmit` if you touched src/.
- Commits: seat prefix as your brief says; each commit message ends with exactly these two lines:
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01MHFn2pe3REUYi65EDVrW7G`
  No model names anywhere else. Push your branch; open NO pull request.
- Comments carry the measurement (what leaked, on what input, date), as the auditor-readable skill requires.
- Disk is tight (about 5 GB): no videos, no large OCR corpora runs unless your brief asks; delete what you generate.

## Hand-back (under 60 lines)
1. Each leak in your scope: CLOSED (file:line, the fixture that proves it) / NOT CLOSED (why) / NEEDS THE FOUNDER.
2. Leaks closed N of M on the planted corpus; legitimate strings wrongly removed (list).
3. Tests and checks run, with counts.
4. What a second reader (a model of another family checking the final text before it crosses) would still be
   needed for: the shapes no code rule can catch.
5. SQL to apply, functions to deploy, in order. 6. What you are unsure of.
