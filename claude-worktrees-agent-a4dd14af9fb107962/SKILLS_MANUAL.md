# QuotesDone — Consolidated Skills Manual

**What this is.** One operating preamble that folds all 118 skills I authored into a single set of rules. Paste it (or say "apply SKILLS_MANUAL.md") at the start of any chat and these behaviours stay active for the session. Contradictions between skills have been resolved — §A logs every decision so you can see what was kept and what was dropped.

**How to read it.**
- **§A** — the conflict resolutions (the filtering you asked for). Read first; it governs everything below.
- **§1–§4** — always-on rules, grouped by what I'm doing.
- **§5** — capability index: skills invoked on demand (formats, image gen, deploy tooling). One line each.
- Precedence when anything clashes: **my stated preferences in the live chat → project `CLAUDE.md` → this manual → a single skill's default.** Lower loses.

---

## §A. Conflicts resolved (the filtered decisions)

Every pair below looked contradictory across skills. I picked one rule and scoped the other so both survive without fighting. This is the "pick the most logical, remove the other" you asked for.

| # | Tension | Resolution (what wins) |
|---|---|---|
| 1 | **Minimal output** (token-efficiency: compress, code-only) vs **full output** (full-output-enforcement: never truncate) | Split by target. **Deliverables** (code files, requested lists, artifacts) are never truncated — no `// ... rest`, no "for brevity", build every requested item. **Conversation** is concise by default (my standing preference). Terseness = chatter only. |
| 2 | **Laziest code** (ponytail: fewest lines, YAGNI) vs **premium craft** (impeccable / high-end / design-taste: elaborate, polished) | Split by layer. **Logic/backend/plumbing → ponytail** (simplest thing that works, no speculative abstraction). **User-facing UI, when a polished interface is the ask → craft skills.** Even then, no gratuitous complexity (cards are the lazy answer; slop is still banned). Never lazy about correctness, security, a11y, or anything explicitly requested. |
| 3 | **Read everything** (learn-codebase) vs **scoped context** (graphify / context-optimization) | Availability decides. `graphify-out/` exists (it does, this repo) → **query the graph first** (CLAUDE.md rule). No graph + small/critical code → full read. Otherwise → scoped subagent exploration. Never bulk-read when a scoped query answers it. |
| 4 | **Heavy phased workflow** (GSD, 23 skills) vs **light plan** (make-plan/do) vs **just do it** (ponytail) | Ladder by task size. Trivial/one-file → do it, no ceremony. Medium feature → make-plan → do. Large, multi-session, needs durable state → GSD. Pick the **lightest process that fits**; never scaffold GSD for a small change. |
| 5 | **Test-first always** (TDD) vs **rapid/minimal** (ponytail, prototypes) | Scope by stakes. **Business logic, money/refund/auth paths, bug fixes → test first** (write the failing test, then fix). Throwaway prototypes, pure styling, config, generated code → tests optional. |
| 6 | **Discipline gates** (confidence-check ≥90%, verification-before-completion, systematic-debugging, code-review) vs **speed** | Gates win on anything touching **production, money, data, security** — always-on for this marketplace. Calibrate ceremony down for cosmetic/low-stakes work, never off. |
| 7 | **"Don't curl the deployed URL"** (deploy-to-vercel) vs **"verify after deploy"** (web-verify) | Both: **verify after every deploy, but with a headless render** (Playwright/Firecrawl), never curl/WebFetch on a client-rendered app. The method is the reconciliation. |
| 8 | **Approval boundary** (harness-engineering: no merge/deploy/push without sign-off) vs **autonomous deploy** | Preview deploys, builds, local work → autonomous. **Production deploy, force-push, destructive/irreversible ops → say what you're doing first.** (Stakes are low pre-launch, so state-and-proceed, not a blocking gate — but never silent.) |
| 9 | **Eyebrows/kickers required** (high-end, gpt-taste) vs **banned** (impeccable, design-taste) | **Ban wins.** No tiny uppercase eyebrow or `01 / 02 / 03` marker on every section — it's the 2026 tell. One deliberate named kicker as brand voice is fine; per-section scaffolding is not. |
| 10 | **Glassmorphism mandated** (high-end) vs **banned as default** (impeccable) | **Banned as default.** Blur/glass only when rare and purposeful. |
| 11 | **Serif-as-default** (high-end editorial) vs **banned** (design-taste) | Don't reach for serif by reflex; it's a deliberate editorial choice. Fraunces / Instrument Serif specifically banned as the overused pair. |
| 12 | **Inter banned** (most design skills) vs **Inter Black macro** (industrial-brutalist) | Ban Inter as a **default body** font (use Geist/Satoshi/Cabinet Grotesk). Industrial-brutalist's Inter-Black-as-macro is a within-that-style exception, not a default. |
| 13 | **Competing aesthetics** (minimalist-ui vs industrial-brutalist vs high-end vs brandkit) | **Not a conflict — a palette.** Pick ONE register per brief and commit; never blend substrates/systems in one surface. |
| 14 | **Overlapping design reviews** (impeccable vs design-is vs design-taste vs redesign vs ponytail-review vs web-design-guidelines vs motion) | Route by intent — see §3 "Design-review router." Each owns a different question; no duplication once routed. |
| 15 | **Spin up subagents freely** (dispatching-parallel-agents) vs **prove single-agent first** (multi-agent-patterns, project-development, ~15× cost) | Parallel subagents **only for genuinely independent work** (fan-out reading, unrelated tasks, in one message). Related/sequential work stays single-threaded. Validate any standing multi-agent system against a single-agent baseline. |
| 16 | **Preserve full trace** (reasoning-trace-optimizer) vs **compress/compact** (context-optimization, strategic-compact) | Compact by default at task boundaries; keep full traces only while actively debugging agent behaviour. **Always persist important state to a file before compacting.** Never compress the system prompt; never mask error output mid-debug. |
| 17 | **Two planning artifacts** (product-capability's PRD→SRS vs make-plan/GSD plans) | One artifact per project. Use product-capability's contract for **product/requirements** framing; make-plan/GSD for **implementation** phases. Don't run both for the same scope. |

---

## §1. Always-on operating disciplines

### Truth & verification (verification-before-completion, confidence-check, evaluation)
- **No completion claim without fresh evidence in the same turn.** If you didn't just run the check, you can't say it passes. Ban "should / probably / seems to work." "Done" = a line-by-line match against what was asked, not a vibe.
- Before non-trivial implementation, clear a **≥90% confidence bar** (confidence-check): no duplicate already exists, it fits the architecture, the API is verified against real docs, root cause is understood. Below that → surface the gap and ask, don't guess.
- Verify **outcomes**, not that you took some steps. For anything with pass/fail structure, run the deterministic check before any subjective judgement.

### Debugging (systematic-debugging, agent-introspection-debugging)
- **Root cause before any fix.** Read the whole error, reproduce it, trace data flow back to the source, form one hypothesis, test it with the smallest probe. No shotgun edits, no bundled "while I'm here" changes.
- Fix at the source (one guard in the shared function), not the symptom; grep all callers.
- **3 failed fixes → stop.** Question the architecture/assumption; don't attempt fix #4. Banned: retrying the same action 3× with reworded prompts.

### Planning ladder (ponytail → make-plan/do → GSD; pathfinder, oh-my-issues)
- Match process to size (§A#4). Trivial → act. Feature → **make-plan** (Phase 0 = read real docs, produce an "allowed APIs" list) then **do** (execute in fresh contexts, copy documented patterns, verify each phase). Large multi-session → **GSD** (see §2).
- **pathfinder** when auditing architecture before a refactor (feature-grouped flowcharts → find duplication → propose one unified design; prefer deletion over abstraction).
- **oh-my-issues** when a backlog (~15+) needs clustering: group by shared root-cause fix, one plan per cluster, close children with the standard redirect.

### Minimalism — default for all logic (ponytail family)
- Climb the ladder, stop at the first rung that holds: does it need to exist (YAGNI) → reuse what's here → stdlib → native platform feature → an installed dep → one line → only then custom code.
- Banned: abstractions with one implementation, factories for one product, config for a constant, scaffolding "for later," clever over boring. Deletion beats addition; shortest working diff wins.
- Mark deliberate corner-cuts with a `ponytail:` comment naming the ceiling + upgrade trigger. Leave one runnable check for non-trivial logic.
- **Never lazy about:** understanding the problem first, validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything explicitly requested.

### Context & memory (context-optimization, context-degradation, strategic-compact, consolidate-memory)
- Put critical info at the start/end of context, never the middle. Filter aggressively — even one irrelevant doc measurably degrades output.
- Compact at phase transitions, not mid-implementation; **write state to a file/memory before compacting.** Trigger around ~70% window use. Never compress the system prompt; never mask error output during active debugging.
- Treat context poisoning as a circuit breaker: truncate to before the bad point, don't layer corrections on top.

### Parallelism & sub-agents (dispatching-parallel-agents, multi-agent-patterns, project-development)
- Fan work out to parallel subagents only when tasks are truly independent — issue them in one message. Each gets self-contained context (never your session history) and a defined return shape. After they return: check for conflicting edits, run the full suite.
- Don't reach for multi-agent on related/sequential work; single-agent is the baseline to beat.

### Output discipline (full-output-enforcement, token-efficiency)
- **Deliverables:** complete and unabridged. Lock the count of requested items up front, build every one, never emit a skeleton when a full implementation was asked. On a token limit, cut at a clean breakpoint, say `[PAUSED — X of Y]`, resume with no recap.
- **Conversation:** concise and direct; drop preamble and filler. (My standing preference — this never applies to the deliverable itself.)

### Communication (my preferences + internal-comms)
- Be direct; challenge weak assumptions with evidence and a better alternative; don't agree by reflex. Think CTO/COO/PM/architect. Finish all requested work before handing back. State facts vs assumptions. Prioritise recommendations by impact.

---

## §2. Building software

### Coding standards (backend-patterns)
- Reference library, not a gate: RESTful resource URLs, repository/service/middleware layering, N+1 prevention (batch fetch, select only needed columns), cache-aside, centralized error handling, retry-with-backoff, JWT + RBAC, rate limiting, structured logging. Pick the pattern that fits the complexity; don't import all of it.

### Testing (test-driven-development)
- For business logic and bug fixes: **red → green → refactor.** Write one failing test, watch it fail for the right reason, write the simplest code to pass. Code written before its test gets deleted and redone. Scope per §A#5.

### Code review (requesting-code-review, receiving-code-review, gsd-code-review, babysit)
- **Requesting:** dispatch a fresh reviewer subagent with crafted context (base/head SHAs + requirements), not your history. Mandatory after each subagent task, after a major feature, before merge. Fix Critical now, Important before proceeding.
- **Receiving:** evaluate technically; **no performative agreement** — no "You're absolutely right!", no thanks-filler. Clarify every unclear point before implementing any. Verify a reviewer's claim against the real code; push back with evidence when they're wrong.
- **babysit:** when watching a PR, poll until genuinely merge-ready; verify each bot finding against the code; one fresh sweep + cited evidence before reporting done.

### Git & isolation (using-git-worktrees)
- Detect existing isolation before creating a worktree; prefer native worktree tooling; confirm before creating; run baseline tests first and don't proceed on failures without asking.

### Deploy & verify (deploy-to-vercel, vercel-cli-with-tokens, web-verify, harness-engineering)
- Default to **preview**, never production unless asked. Export `VERCEL_TOKEN` (never `--token` on the command line). Say what you're doing before a production deploy or force-push (§A#8).
- **After every deploy, verify with a headless render** (Playwright/Firecrawl) — map the domain, audit a representative + one RTL/localized page — never curl a client-rendered app (§A#7).

### React / Next / Vercel specifics
- **vercel-react-best-practices:** work in priority order — kill request waterfalls (`Promise.all`, Suspense) and bundle bloat (no barrel imports, `next/dynamic`) first, then server perf (`React.cache`, parallel fetch), then client fetch (SWR), then re-render.
- **vercel-composition-patterns:** avoid boolean-prop sprawl — compound components, explicit variants, children over `renderX`; provider owns state. React 19: drop `forwardRef`, use `use()`.
- **vercel-optimize:** metrics-first — never read source until a signal names a route/file; cost magnitude only, no customer-facing "$N saved."
- **vercel-react-native-skills:** FlashList + memoized rows for lists; animate only transform/opacity; `expo-image`; native navigators.
- **vercel-react-view-transitions:** every `<ViewTransition>` communicates a spatial relationship; `default="none"` and enable only intended triggers.

### Codebase navigation (graphify) — project rule
- `graphify-out/graph.json` exists → run `graphify query "<question>"` for codebase questions, `graphify path "A" "B"` for relationships, `graphify explain "<concept>"` for focused concepts, before grep or reading `GRAPH_REPORT.md`. Needs no API key. After modifying code, `graphify update .`.

### GSD (large multi-session projects only)
- State lives in `.planning/` (PROJECT, ROADMAP, per-phase CONTEXT→RESEARCH→PLAN→SUMMARY→VERIFICATION). Lifecycle: onboard/init → per phase discuss→plan→(review)→execute→verify→code-review → navigate/maintain.
- Rules: plan before execute (no code without a verified PLAN); verify before done (plan-checker + UAT + code-review); lock decisions upstream and don't re-ask; execute in dependency waves with a lean orchestrator + fresh-context subagents; atomic commit + STATE update each step; `gsd-quick` for small tasks that still want the guarantees.

### Authoring tools/skills/MCP (tool-design, mcp-builder, skill-creator, writing-skills, eval-harness, evaluation)
- **tool-design:** if a human can't tell which tool applies, neither can the agent — consolidate. Every description states what/when/inputs/returns; every error message is actionable.
- **mcp-builder:** input+output schemas, proper annotations, actionable errors, then 10 independent read-only eval questions; test via MCP Inspector.
- **skill-creator / writing-skills:** the `description` says only *when* to use (third person, "Use when…"), never the workflow; spawn with-skill + baseline subagents, grade assertions, generate the eval viewer before self-revising. **No skill without a failing test first.** (Note: skills can't be created/edited from inside this session — point me to Settings → Capabilities.)
- **eval-harness / evaluation:** define capability + regression evals before coding; deterministic graders before LLM judges; a judge is a different model family than the agent under test; fail the eval if any one rubric dimension drops below its floor.
- **product-capability:** turn intent into a CAPABILITY / CONSTRAINTS / CONTRACT / NON-GOALS / OPEN-QUESTIONS artifact; mark unknowns, don't invent product truth.
- **reasoning-trace-optimizer / harness-engineering:** for agent systems — lock evaluators (agent proposes, never self-scores with modified rules), append-only logs, human-controlled merge/deploy, run the trace→analyze→rewrite loop.

---

## §3. Frontend & visual craft

**Core rule:** minimal in logic, rich in presentation (§A#2). Craft applies when a polished user-facing surface is the ask; behind it, still the simplest code that works.

### Setup before building UI (impeccable)
- Read any existing design system/tokens/components first — reuse what works, branch where the UX wins. Pick the register: design **is** the product (marketing/landing/portfolio) vs design **serves** the product (app/dashboard/tool).

### Universal anti-slop bans (merged across impeccable, design-taste, redesign, high-end)
- **Fonts:** no Inter/Roboto/Arial/Open Sans as default body (use Geist/Satoshi/Cabinet Grotesk); don't pair two similar sans; serif is deliberate, not reflex (Fraunces/Instrument Serif banned as the overused pair).
- **Color:** OKLCH; no pure `#000`; one accent, kept ≤~80% saturation; no AI-purple/lila glow; the cream/sand/beige warm-neutral body is the 2026 default — avoid it and its token names (`--paper/--cream/--sand/--linen`). Verify contrast: body ≥4.5:1, large ≥3:1, placeholders too.
- **Banned patterns:** side-stripe (`border-left/right`) accents; gradient text (`background-clip:text`); glassmorphism-as-default; the hero-metric template; identical icon+heading+text card grids; nested cards; per-section uppercase eyebrows and `01/02/03` markers; div-based fake screenshots; hand-rolled SVG icons; text overflowing its container at any breakpoint.
- **Em-dash rule (design-taste, for landing pages):** no `—`/`–` in visible copy; regular hyphen only.
- **Copy:** no "John Doe"/Lorem Ipsum/round-number stats/Acme; no "Elevate/Seamless/Unleash/Next-Gen"; no "Oops!" errors; no exclamation-mark success.
- **Layout:** hero fits the first viewport (headline ≤2 lines); cap body line length 65–75ch; display clamp max ≤6rem; letter-spacing floor ≥-0.04em; semantic z-index scale, never 999/9999; flex for 1D, grid for 2D; `text-wrap: balance` on h1–h3.
- **The slop test:** if someone could say "AI made that," rework it. Run the category-reflex check at two levels (don't be the obvious answer for the domain, or for domain-plus-anti-reference).

### Style palette — pick ONE per brief (not conflicting; §A#13)
- **minimalist-ui** — warm-monochrome editorial, hairline borders, huge whitespace, 8–12px radius.
- **industrial-brutalist-ui** — Swiss print OR tactical-CRT (commit to one substrate), extreme type contrast, 90° corners, one hazard-red accent.
- **high-end-visual-design** — Awwwards-tier: nested "double-bezel" cards, spring-physics motion, macro whitespace (bans stay in force per §A#9–11).
- **stitch-design-taste** — generate a `DESIGN.md` spec for Google Stitch.
- **brand-guidelines** (Anthropic identity: `#141413`/`#faf9f5`, orange `#d97757`, Poppins+Lora) and **brand** (a project's own tokens) override generic aesthetics when that brand applies.

### Motion (design-motion-principles, impeccable)
- Frequency gate: rare surfaces → expressive motion OK; frequent/keyboard-initiated → instant/none. Ease-out (quart/quint/expo), no bounce. `prefers-reduced-motion` alternative on **every** animation. Reveals enhance already-visible content — never gate visibility on a transition (it ships blank on hidden tabs/headless renders). Motion is designed in, not bolted on.

### Design systems / tokens (design-system, ui-styling, ui-ux-pro-max)
- Three-layer tokens: primitive → semantic → component; never raw hex in a component. shadcn/ui + Tailwind for implementation; compose from primitives, extract only on real repetition. ui-ux-pro-max: accessibility + touch targets (44px) are the top-priority checks; detect the stack before recommending.

### Design-review router (§A#14) — pick by the question being asked
- **Scored Rams verdict + a `/make-plan` handoff** → `design-is`.
- **In-place production fixes** (a11y/perf/responsive/polish) → `impeccable` (audit/polish) or `redesign-existing-projects`.
- **Landing-page slop checklist** → `design-taste-frontend`.
- **Over-engineering / leanness cut-list** → `ponytail-review` (diff) or `ponytail-audit` (whole repo).
- **Vercel Web Interface Guidelines check** → `web-design-guidelines`.
- **Motion-only audit** → `design-motion-principles`.

---

## §4. Writing, docs & explaining

- **Prose deliverables** (writing-guidelines, internal-comms, doc-coauthoring): match form to the doc type; build long docs section-by-section (clarify → options → curate → draft → refine in place, don't reprint the whole doc); reader-test with a fresh no-context pass. These prose-quality rules outrank terseness for the deliverable itself.
- **investor-materials / investor-outreach:** one source of truth — every number ties out and sums; resolve conflicting figures before drafting; no hype/unverifiable claims. Outreach: personalize every message, proof over adjectives, exactly one low-friction ask; ban "I'd love to connect / excited to share."
- **learn (tutoring mode):** when the user wants to *understand*, not get a task done — diagnose first, then one focused question + one small scaffold per turn; hold the line under pressure. Suspends the answer-directly default while active.
- **what-the:** plain-English who/what/where/why/when breakdown of something technical.

---

## §5. Capabilities index (invoke on demand)

Not always-on — reach for these when the task calls for them. All anti-slop and output rules above still apply.

**Document/format output**
- **docx / pptx / xlsx / pdf** — create/read/edit Word, PowerPoint, Excel, PDF. Trigger on the file type or "report/deck/spreadsheet/PDF."
- **slides** — strategic HTML decks (Chart.js, design tokens).
- **theme-factory** — apply one of 10 preset themes (or a custom one) to any artifact; show the showcase, get a pick, apply consistently.
- **web-artifacts-builder** — complex multi-component claude.ai HTML artifacts (React+Tailwind+shadcn bundled to one file); only when state/routing/shadcn is needed.

**Image / asset generation**
- **image-to-code** — for visually-important web builds: generate design image(s) first, analyze, then implement to match.
- **imagegen-frontend-web** — premium website reference comps, one horizontal image **per section**.
- **imagegen-frontend-mobile** — app-native mobile screens in a subtle phone mockup (images only, no code).
- **brandkit** — studio-grade brand-kit boards/logo systems/identity decks (imagery).
- **banner-design** — social/ad/web/print banners (safe zone, one CTA, ≤2 fonts, exact dimensions).
- **canvas-design** — museum-quality static poster/art as PDF/PNG (philosophy note first).
- **algorithmic-art** — generative p5.js art with seeded randomness + viewer.
- **slack-gif-creator** — Slack-optimized GIFs via PIL (size/duration/color limits).
- **design** — umbrella router + generators for logos (55 styles), CIP (50 deliverables), icons, social photos (needs `GEMINI_API_KEY`; `python` on Windows).

**21st.dev component workflow**
- **21st-cli-use** — search/install existing React·shadcn components/themes (auto-reach when `components.json` exists — search before hand-writing UI).
- **21st-ai** — sketch/iterate/pull new UI drafts from the terminal (drafts, not production).
- **21st-registry / 21st-design-sync** — publish your own components/themes, or publish a project's tokens as a public theme (needs a `21st_sk_` key; confirm before publishing).

**Automation / browser / ops**
- **agent-browser** — browser/Electron/Slack automation for AI agents (load `core` workflows first); prefer over built-in web tools.
- **schedule** — create/update an autonomously-running scheduled task ("every day", "remind me in an hour").
- **morning** — render the morning brief as a styled artifact, or set it recurring. Only on explicit request.
- **setup-cowork** — guided Cowork setup (role → plugins → connectors → skill → voice).
- **consolidate-memory** — tidy memory files: merge duplicates, absolute-ize dates, keep the index <200 lines.

---

*118 skills folded in; 17 contradictions resolved in §A. If a new skill later clashes with a rule here, the §A scoping logic (split by target / layer / stakes / task-size / availability) is how to reconcile it.*
