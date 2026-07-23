# QuotesDone OS — Backend Reference (edge functions)

**Purpose.** Developer-shareable reference for the QuotesDone "OS": the 122 Supabase **edge functions** (Deno / TypeScript) that run the autonomous back office, separate from the three surface chapters (`CUSTOMER_PORTAL.md`, `SUPPLIER_PORTAL.md`, `WEBSITE.md`) which cover the other 47 customer-, supplier- and website-facing functions.

**Provenance.** Every entry below was written directly from the source in `supabase/functions/<name>/index.ts`. The repo is byte-identical to production (verified in the git-mirror audit), so this documents what is actually deployed as of **24 Jul 2026**. Project ref: `htdblwldjkcgjvmqkbeh`.

**Scope note — this is the edge-function half of the OS.** The OS also has a large PostgreSQL layer: ~90 `pg_cron` jobs, many of which call SQL functions (`run_agent(...)`, `fn_chief_of_staff()`, `fn_finance_ai()`, `fn_security_ai()`, …). Those database-side agents are the OS's other half and are **out of scope for this file** (they warrant a companion "OS database functions" chapter). Appendix A maps only the crons that drive the edge functions documented here.

---

## How the OS is wired

**Invocation patterns.** Edge functions are triggered three ways:
1. **`pg_cron` → `net.http_post`** — the dominant pattern. A scheduled Postgres job POSTs to `https://<project>.supabase.co/functions/v1/<fn>` with a JSON body carrying an auth secret. See Appendix A.
2. **Internal fan-out** — one function calls another (e.g. `email_cron` → `send_outbox`, `make_pdf` → `pdf_native`, `reg_fetch` → `kb_ingest`).
3. **Direct HTTP** — a handful are called by the frontend/OS console or external webhooks (Resend, WhatsApp, Stripe).

**Auth models** (the in-code gate, since almost all run `verify_jwt=false` and self-authenticate):
- **`__secret`** — `body.__secret === app_secrets.inbound_secret`. The default machine-to-machine gate for cron/internal calls.
- **`x-internal-key`** — header equals a named secret (e.g. `postiz_publish_key`), used by a few internal callers.
- **JWT + admin** — a Supabase user JWT whose email is in `app_secrets.admin_emails` (resolved via the `fn_role_of` RPC). Used by console/admin surfaces.
- **`x-os-key`** — an OS console bypass key (still accepted by `os_ops`/`os_pages` alongside JWT).
- **MFA** — `agent_act` additionally requires a live `admin_mfa_sessions` row for money-moving actions.
- **Customer JWT** — `project_consultant` and `attach_photos` are scoped to a customer's own JWT.
- **Public** — `public_stats`, `stripe_setup_page`, `home-ar` serve unauthenticated.

**LLM stack.** Most AI functions call **OpenRouter** with a Sonnet-first ladder: `anthropic/claude-sonnet-5` primary → `anthropic/claude-opus-4.8` fallback, via the shared client **`_shared/llm.ts`** (`makeLlm(LADDER)`, 25s abort timeout). Imported by: agent_act, agent_brain, agents, category_provision, category_reqs, copilot*, email_triage, exec_agents, messages_api*, project_consultant, prompt_gate (*copilot/messages_api are in the portal chapters). Older functions still inline their own OpenRouter helper. **`designer`** is the only function calling OpenAI directly (`gpt-image-1`). Embeddings (`kb_embed`, `kb_search`) use the in-region built-in `Supabase.ai.Session('gte-small')` — no external API.

**Disabled / kill-switched surfaces** (present but inert — do not re-enable without review): `voice_otp`, `voice_otp_capture`, `dev_login`, `qa_login`, `src_io` all return HTTP 410; `qa_mint` is live but double-gated behind a `qa_mint_enabled` kill-switch (keep OFF in prod).

---

## Contents

1. [Orchestration & the Agent Fleet](#orchestration-the-agent-fleet)
2. [OS Console, Ops, Health & Monitoring](#os-console-ops-health-monitoring)
3. [Email & Inbound Comms + OTP](#email-inbound-comms-otp)
4. [WhatsApp / SMS + Lead Ingestion & Scraping](#whatsapp-sms-lead-ingestion-scraping)
5. [Knowledge Base, Embeddings & Category Knowledge](#knowledge-base-embeddings-category-knowledge)
6. [Finance, Legal, Compliance, PDPL, Backup & Retention](#finance-legal-compliance-pdpl-backup-retention)
7. [Documents, Rendering, Extraction, Drawings & Assets](#documents-rendering-extraction-drawings-assets)
8. [Marketing, Social, SEO & i18n](#marketing-social-seo-i18n)
9. [Auth, QA, Dev & Deploy Infrastructure](#auth-qa-dev-deploy-infrastructure)

- [Appendix A — Cron schedule → edge function](#appendix-a--cron-schedule--edge-function)
- [Appendix B — Disabled & security-sensitive functions](#appendix-b--disabled--security-sensitive-functions)
- [Appendix C — Related chapters](#appendix-c--related-chapters)

---

## Orchestration & the Agent Fleet

### orchestrate
- **Purpose:** COO-style multi-agent teamwork — decomposes one founder request into per-agent sub-tasks, has each agent plan its part, returns a combined plan for one approval, then executes across agents and synthesises one result.
- **Invocation:** authenticated HTTP (admin console) or internal call with `__secret`.
- **Auth gate:** `authed()` = `body.__secret === app_secrets.inbound_secret` OR admin JWT whose email is in `app_secrets.admin_emails` (no MFA check here).
- **Input:** `{ mode:'plan'|'execute', instruction? (plan, ≤2500 chars), steps? (execute: array of {agent_key, actions[]}) }`.
- **Output:** plan mode → `{ok, narrative, steps:[{agent_key, agent_name, task, narrative, plan, model, error}]}`; execute mode → `{ok, results:[{agent_key, agent_name, results, error}], summary}`.
- **Logic:** plan: LLM (Opus 4.8→Sonnet 5) as "COO" breaks the request into ≤4 sub-tasks each assigned to one ROSTER agent key; filters to valid keys; each step is then planned in parallel by calling `agent_act` mode=plan. execute: for each step with actions, calls `agent_act` mode=execute; then an LLM writes a 2-4 sentence founder summary of successes/failures.
- **Depends on:** `app_secrets` (inbound_secret, admin_emails, openrouter_api_key); OpenRouter (openrouter.ai chat completions, models anthropic/claude-opus-4.8 + claude-sonnet-5); edge function `agent_act`. Hardcoded ROSTER of 14 role keys.
- **Notes:** clean. Has its own inline `opus()` LLM helper (does not use _shared/llm). Note ROSTER keys here (docs, onboarding, crm, marketing, pricing, cfo, bookkeeper, collections, followup, it, security, bd, legal, brief) differ from agent_act persona/KMAP keys, but agent_act tolerates unknown keys.

### agent_act
- **Purpose:** Conversational, action-capable CRM agents — each reads curated live data + company brain, chats in persona, and proposes exactly one whitelisted action the founder confirms.
- **Invocation:** authenticated HTTP (admin) or internal `__secret`. Called by `orchestrate`.
- **Auth gate:** `body.__secret === inbound_secret` OR admin JWT (email in `admin_emails`) AND a valid MFA session — `mfaOk()` checks `admin_mfa_sessions` for the JWT's `session_id` with unexpired `expires_at`; missing MFA returns `mfa_required` 401.
- **Input:** `{ action:'chat'|'confirm', agent, message, action_id?, history?, proposal? }`. Agent key may be `cat:<slug>` for category desks.
- **Output:** chat → `{ok, reply, proposal?}` where proposal = `{kind, args, label}`. confirm → executes the action and returns `{ok, result, url?}`.
- **Logic:** chat: `gatherContext` pulls this_alert (agent_actions), pending_actions, conditional security_events/licence_expiries/pending_suppliers/content_drafts by agent or message regex, open crm_tasks, and 7 count stats; `brainFor` loads role knowledge via RPC `fn_agent_context`; builds a heavy persona system prompt (UAE sales playbook, ACTION line contract) and calls shared LLM (Sonnet-first, max 900). Parses trailing `ACTION:` JSON, keeps it only if kind ∈ ALLOWED. confirm: dispatches by kind — resolve/dismiss_action (update agent_actions status), delete_file (only SAFE_DELETE buckets; also deletes matching security_events), add_note (crm_notes), approve/reject_supplier (updates leads + inserts notifications), send_message (notifications email), create_task (crm_tasks), post_content (email/whatsapp → notifications rows + content_drafts; social → calls `postiz_publish`, falls back to draft), ad_campaign (calls `meta_ads` quick_campaign, always PAUSED, saves crm_task), draft_doc (renders branded HTML, uploads to agent-docs bucket, returns signed URL).
- **Depends on:** `_shared/llm.ts` (makeLlm/SONNET_FIRST); `app_secrets` (inbound_secret, admin_emails, openrouter_api_key); RPC `fn_agent_context`; tables agent_actions, admin_mfa_sessions, security_events, leads, customers, inquiries, quotes, transactions, crm_tasks, crm_notes, content_drafts, notifications, category_agents; storage buckets quote-files/drawing-files/supplier-docs/receipt-files/agent-docs; edge functions `postiz_publish`, `meta_ads`.
- **Notes:** clean. Only function in this domain that enforces MFA.

### agent_autogen
- **Purpose:** When suppliers/inquiries arrive in a trade category not yet covered, auto-creates a full expert sales agent for it (persona + verified knowledge pack + intake checklist).
- **Invocation:** cron (daily) and callable internally.
- **Auth gate:** `body.__secret === inbound_secret` (else 403, logged).
- **Input:** `{ max? (1-5, default 3), category? (force provisioning of one named trade) }`.
- **Output:** `{ok, mode:'forced'|'scan', considered?, results:[{trade, ok, slug?, name?, topics?, checklist?, error?}]}`; logs to agent_runs; on creation inserts an agent_actions review item + notifies owner.
- **Logic:** loads existing category_agents; computes covered trades by token overlap. Forced mode provisions the given category. Scan mode tallies uncovered trades from claimed leads' `sector` and last-60-day inquiries' `category`, ranks by frequency, takes top `max`. `provision` → `generateFor` calls LLM (Sonnet-first ladder via `models` array) with GEN_SYS to emit strict JSON (name/emoji/slug/persona/6 knowledge topics/5-9 checklist fields); inserts category_agents row, agent_knowledge rows (key `cat:<slug>`), and upserts category_specs. Extensive failure accounting (empty knowledge, spec failures, save failures) drives run status.
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key, admin_emails); OpenRouter (Sonnet 5 + Opus 4.8); tables category_agents, agent_knowledge, category_specs, leads, inquiries, agent_actions, notifications, agent_runs.
- **Notes:** clean. Self-contained LLM helper (not _shared). Sonnet-first "for cost (fleet policy)".

### agent_brain
- **Purpose:** Back-end chat brain for the role agents — answers in-domain using knowledge base + KB retrieval + live snapshot, can hand off tasks to teammates, and auto-learns durable memory.
- **Invocation:** authenticated HTTP (admin console).
- **Auth gate:** admin JWT only — `admin.auth.getUser(jwt)`, email must be in `admin_emails` (default management@quotesdone.com); no `__secret` path.
- **Input:** `{ agent, message }`. Agent key ∈ NAMES or `cat:<slug>`.
- **Output:** `{reply}` (with any handoff notes appended).
- **Logic:** resolves agent meta (NAMES map or category_agents persona); loads last 10 agent_chats as history; `context()` builds a live snapshot (my pending agent_actions, recent agent_runs, unpaid supplier_dues sum, plus 9 counts); `knowledge()` loads agent_knowledge (_global + key) and recent agent_memory; `retrieve()` calls `kb_search` for semantic reference knowledge. Builds system prompt with teamwork `@@ACTIONS@@` handoff contract and calls shared LLM (Sonnet-first, max 1700). Parses handoffs → inserts pending agent_actions kind=handoff for teammates. Persists both chat turns; if the user message matches remember/policy regex, stores an instruction memory; runs background `learn()` (fast Sonnet call) to capture at most one new memory line.
- **Depends on:** `_shared/llm.ts`; `app_secrets` (inbound_secret, openrouter_api_key, admin_emails); edge function `kb_search`; tables agent_chats, agent_actions, agent_runs, supplier_dues, leads, inquiries, quotes, customers, content_drafts, transactions, security_events, agent_knowledge, agent_memory, category_agents.
- **Notes:** clean. No leading comment banner.

### agent_learnings_report
- **Purpose:** Weekly "what the agents learned" PDF — knowledge coverage, new KB chunks, gaps filled, agent activity, decisions logged.
- **Invocation:** cron (weekly) or authenticated HTTP; optional `notify` to email the founder.
- **Auth gate:** `body.__secret === inbound_secret` OR admin JWT — `isAdmin()` via RPC `fn_role_of` (owner/admin) or membership in `admin_emails`.
- **Input:** `{ __secret?, notify? }`.
- **Output:** `{ok, url, path, chunks, gaps_filled}`; renders a PDF into finance-reports/learnings; optionally queues a founder notification; logs agent_runs.
- **Logic:** gathers last-7-day kb_chunks, agent_actions, decision_log, plus RPC `fn_ws_knowledge` coverage KPIs; aggregates chunks by category, gaps-filled (title regex), actions by agent, decisions by actor; builds an HTML report and POSTs to `make_pdf` (bucket finance-reports, folder learnings). If notify, inserts a weekly_learnings notification.
- **Depends on:** `app_secrets` (inbound_secret, admin_emails); RPCs `fn_role_of`, `fn_ws_knowledge`; tables kb_chunks, agent_actions, decision_log, notifications, agent_runs; edge function `make_pdf`.
- **Notes:** clean.

### agents
- **Purpose:** The scheduled autonomous ops workers — one function hosting all cron agent jobs; risky actions are queued into agent_actions for approval, safe work runs automatically.
- **Invocation:** cron / internal `__secret`. Dispatched by `secretary` (SAFE_JOBS) and `secretary_act` (run_agent RPC targets it).
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ job }` where job ∈ onboarding | compliance | followup | finance | marketing | category_sales | bd_outreach | it_health | security.
- **Output:** `{ok, job, counts, note}`; every run recorded in agent_runs (start row then finish update).
- **Logic:** dispatches to the named job:
  - onboarding — queues approve_supplier actions for pending leads (flags missing licence/terms/expiry), and licence expiring/expired alerts for approved leads; advances lifecycle_stage.
  - followup — reveal nudges to customers with quotes-but-no-reveal, quote nudges to matched-but-not-quoted suppliers (via notifications), plus SLA alerts (refund pending, inbound review, no-supply).
  - marketing — LLM produces 5 content drafts (3 social/1 SEO/1 email) into content_drafts, queues a content_review.
  - category_sales — per active category_agents desk, queues hot_lead (quotes, unrevealed) or supply_gap (no matches) actions.
  - bd_outreach — plan mode drafts supplier invite emails into outreach (NOT sent); send mode (when bd_outreach_enabled=true) works the queue into notifications, capped by bd_daily_cap.
  - it_health — HTTP-checks 4 quotesdone.com pages into health_checks; queues incidents; flags failed agent runs; emails owner on downtime.
  - security — scans storage buckets (quote-files/drawing-files/supplier-docs/receipt-files) for dangerous/oversize/empty files → security_events + high-risk queue; counts chat_violations and banned users; emails owner on suspicious files.
  - compliance — polls active compliance_sources (reader/asset/HTML), hashes signatures, downloads changed docs to compliance-docs, LLM-classifies substantive regulatory changes, queues compliance_update actions.
  - finance — bookkeeping() builds a finance_snapshots row from expenses/expense_entries/transactions; cfo() writes LLM commentary, renders PDF+XLSX via `make_pdf`/`make_xlsx`, saves finance_reports, emails owner.
- **Depends on:** `_shared/llm.ts`; `app_secrets` (inbound_secret, openrouter_api_key, admin_emails, bd_outreach_enabled, bd_daily_cap); OpenRouter; edge functions `make_pdf`, `make_xlsx`; external r.jina.ai (compliance reader) + live quotesdone.com fetches; many tables (leads, inquiries, quotes, transactions, inquiry_matches, notifications, agent_actions, agent_runs, customers, content_drafts, seo_categories, category_agents, outreach, health_checks, security_events, chat_violations, compliance_sources, expenses, expense_entries, finance_snapshots, finance_reports, templates, inbound_messages); storage buckets above + compliance-docs, finance-reports, brand.
- **Notes:** clean but very large. This is the workhorse of the fleet; `secretary`/`agents` job names must stay in sync with the RUNMAP in `reflect` and SAFE_JOBS in `secretary`.

### exec_agents
- **Purpose:** Executive Intelligence layer — six AI "officers" each read live metrics and write a prioritized action plan into exec_reports.
- **Invocation:** cron / internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ action:'run'|'run_all'|'latest', officer?, limit? }`.
- **Output:** run → `{officer, report_id, recommendations, ai}`; run_all → `{ok, ran:[...]}`; latest → `{ok, reports}`.
- **Logic:** OFFICERS = strategy, operations, procurement_quality, data_science, product_ux, competitive; each maps to a metrics RPC (fn_strategy_metrics / fn_ops_metrics / fn_quality_metrics / fn_data_metrics / fn_voice_metrics). `runOfficer` calls the RPC, prompts the LLM (Sonnet-first) for strict JSON `{summary, findings, recommendations[]}`, inserts an exec_reports row, logs an agent_runs entry.
- **Depends on:** `_shared/llm.ts`; `app_secrets.inbound_secret` + openrouter_api_key; RPCs fn_strategy_metrics, fn_ops_metrics, fn_quality_metrics, fn_data_metrics, fn_voice_metrics; tables exec_reports, agent_runs.
- **Notes:** clean. competitive officer reuses fn_strategy_metrics and self-notes it needs an external data connector.


### reflect
- **Purpose:** Weekly self-improvement — each role agent reviews its own recent approved/rejected decisions and run outcomes and stores at most two durable "reflection" lessons in memory.
- **Invocation:** cron / internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** none beyond `__secret`.
- **Output:** `{ok, processed, added}`; logs an agent_runs 'reflect' row.
- **Logic:** for each of 12 AGENTS, gathers last-14-day agent_actions (approved/rejected) and mapped agent_runs (RUNMAP), asks the LLM (Sonnet-first, inline helper) for ≤2 lessons as JSON, dedupes against existing reflection memories, inserts new agent_memory rows (kind=reflection).
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key); OpenRouter; tables agent_actions, agent_runs, agent_memory.
- **Notes:** clean. Self-contained LLM helper (not _shared). No leading banner comment.

### secretary
- **Purpose:** The Secretary / chief-of-staff chat agent — the single agent the founder talks to; reads a cross-agent live snapshot and can dispatch handoffs, trigger jobs, send emails, and generate documents/PDFs/Excels.
- **Invocation:** authenticated HTTP (admin console).
- **Auth gate:** admin JWT only (email in admin_emails). Special action `log_denied` logs blocked non-admins; non-admin otherwise 403.
- **Input:** `{ action:'chat'|'history'|'log_denied'|'audit_login', message?, attachment_text?, attachment_name? }`.
- **Output:** chat → `{reply}` (with action notes appended); history → `{messages}`; log_denied/audit_login → `{ok}`.
- **Logic:** `snapshot()` aggregates pending agent_actions, recent runs, overdue commissions, and ~10 counts. Builds a chief-of-staff persona with `@@ACTIONS@@` contract supporting handoffs, run, emails, documents, pdfs, excels; calls LLM (Opus-first, inline helper, max 1800) with knowledge + snapshot + optional attachment text. Parses the actions block: handoffs → agent_actions; run → fires `agents` for SAFE_JOBS jobs (background); emails → notifications; documents → `doc_render`; pdfs → `doc_render` then `make_pdf`; excels → `make_xlsx`. Persists both chat turns, stores instruction memory on trigger words, background `learn()`. `logSec` records admin_login/admin_denied security_events and alerts owner on blocked attempts.
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key, admin_emails); OpenRouter (Opus 4.8 + Sonnet 5); edge functions `agents`, `doc_render`, `make_pdf`, `make_xlsx`; tables agent_chats, agent_actions, agent_runs, supplier_dues, leads, inquiries, quotes, customers, content_drafts, security_events, notifications, agent_memory, agent_knowledge.
- **Notes:** clean. Uses inline LLM helpers, not _shared. This is the `@@ACTIONS@@`-string version of the Secretary; `secretary_act` is the newer tool-calling version.

### secretary_act
- **Purpose:** Secretary v2 — the same chief-of-staff but driven by a real OpenRouter tool-calling loop; low-risk tools run immediately, high-stakes tools pause for a one-line founder confirm.
- **Invocation:** authenticated HTTP (admin) or server/testing `__secret`.
- **Auth gate:** `whoami()` — `__secret === inbound_secret` (actor 'founder') OR admin JWT (email in admin_emails).
- **Input:** `{ message, attachments?, history? }` for a command; `{ confirm_token, decision:'confirm'|'cancel' }` for the confirm path.
- **Output:** `{ok, reply, did?}` or `{ok, needs_confirmation:true, confirm_token, reply, did}`.
- **Logic:** builds a system prompt + team roster + brain (RPC fn_agent_context) and runs up to 5 tool-call rounds against OpenRouter (Sonnet 5 → Opus 4.8 → gpt-4o). TOOLS: get_status, team_roster, lookup, run_maintenance, draft_content, add_task, send_email, log_finance, issue_refund, supplier_decision, delete_files, post_content. HIGH-risk tools (issue_refund, supplier_decision, delete_files, post_content, and send_email to >3) are not executed inline — they're stored in agent_pending_actions with a token and returned for confirmation; the confirm path replays them. Every command/confirm logged in agent_command_log. run_maintenance calls RPCs run_health_check/fn_smoke/fn_security_scan/run_agent/qd_recompute_response or clears the test notification queue; log_finance→`finance_ingest`; delete_files→`asset_delete`.
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key, admin_emails); OpenRouter; RPC `fn_agent_context`, run_health_check, fn_smoke, fn_security_scan, run_agent, qd_recompute_response; edge functions `finance_ingest`, `asset_delete`; tables agent_pending_actions, agent_command_log, leads, customers, inquiries, transactions, notifications, content_drafts, crm_tasks, supplier_dues, category_agents.
- **Notes:** clean. Coexists with `secretary` (two implementations of the same role — one `@@ACTIONS@@`-string, one tool-calling). Uses inline OpenRouter helpers, not _shared.

### ea_meeting_summary
- **Purpose:** Executive-assistant meeting note-taker — turns a transcript/notes into a structured summary + decisions + action items, stores it, and creates tracked tasks.
- **Invocation:** internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ title?, attendees?, text|transcript (≥60 chars), meeting_at? }`.
- **Output:** `{ok, meeting_id, model, summary, decisions, action_items, tasks_created}`.
- **Logic:** LLM (Sonnet 5 → Opus 4.8, inline) produces strict JSON {summary, decisions, action_items[{task,owner,due}], follow_ups}; inserts an ea_meetings row; for each action item inserts an open crm_tasks row (parsing due date if present).
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key); OpenRouter; tables ea_meetings, crm_tasks.
- **Notes:** clean. Records/drafts only — never sends externally.

### prompt_gate
- **Purpose:** Prompt-quality gate — benchmark-scores prompt versions and decides auto-promote vs escalate to the founder.
- **Invocation:** internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ action:'gate'|'view'|'eval', key (required), version? }`.
- **Output:** view → active/candidate/recent_runs; eval → score + case detail; gate → `{ok, key, candidate_version, active_score, candidate_score, delta, sensitive, decision}`.
- **Logic:** `scoreVersion` runs each active prompt_benchmarks case through the candidate prompt then a strict LLM judge (0-100), weight-averages into a score, records prompt_eval_runs and updates prompt_versions.eval_score. gate scores active + candidate; if not sensitive (regex from decision_policy `prompt_sensitive_pattern`), delta ≥5 and candidate ≥60 → auto-promote via RPC `fn_prompt_approve_draft` and mark the pending approval action auto_done; otherwise escalate. Annotates the matching prompt_approval agent_actions with the eval detail.
- **Depends on:** `_shared/llm.ts` (Sonnet-first, temp 0); `app_secrets.inbound_secret` + openrouter_api_key; RPC `fn_prompt_approve_draft`; tables prompts, prompt_versions, prompt_benchmarks, prompt_eval_runs, decision_policy, agent_actions.
- **Notes:** clean. Pairs with prompt_improve (authoring) — this is the scoring/promotion half.

### prompt_improve
- **Purpose:** AI-Trainer authoring step — rewrites an underperforming system prompt via LLM, saves it as a DRAFT version (never touches the live active_version), and queues a founder approval.
- **Invocation:** internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ key (required), reason? }`.
- **Output:** `{ok, key, draft_version, model, chars}` (or no_change_suggested / error).
- **Logic:** loads current prompt via RPC `fn_prompt_get`; gathers recent founder-rejected agent_actions as evidence; LLM (Opus 4.8 → Sonnet 5, inline) rewrites the prompt; strips fences; if changed, saves a draft via RPC `fn_prompt_draft` and inserts a high-risk prompt_approval agent_actions item. Live prompt unchanged until the founder approves.
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key); OpenRouter; RPCs `fn_prompt_get`, `fn_prompt_draft`; table agent_actions (and prompt_versions target).
- **Notes:** clean.

### project_consultant
- **Purpose:** Customer-facing AI Project Consultant + Scope Builder — decomposes a plain-language project into supplier-quotable RFQs, itemizes a single scope, and can create the project + draft inquiries.
- **Invocation:** authenticated HTTP — customer Supabase JWT.
- **Auth gate:** `customer()` — JWT email must match a non-banned row in `customers`; else 401.
- **Input:** `{ action:'plan'|'scope'|'create', description?/brief?, category?, plan?, name? }`.
- **Output:** plan → `{ok, plan:{project, rfqs[], questions, permits, optional_services}}`; scope → `{ok, scope:{title, items, inclusions, exclusions, assumptions}}`; create → `{ok, project_id, rfqs_created}`.
- **Logic:** plan: LLM (Sonnet-first) as a UAE procurement consultant maps the project to platform categories (from category_specs) and emits strict JSON with budget/timeline/permits. scope: LLM itemizes one brief into a quotable scope. create: inserts a projects row for the customer, then a draft inquiries row per RFQ (status draft, brief_source project_consultant).
- **Depends on:** `_shared/llm.ts`; `app_secrets.inbound_secret` (implicit via sec helper) + openrouter_api_key; tables customers, category_specs, projects, inquiries.
- **Notes:** clean. Only fleet function gated on a customer (not admin) JWT.

### designer
- **Purpose:** The Designer agent's image engine — generates on-brand images via OpenAI gpt-image-1, hosts them publicly, returns a URL for Meta ads / Postiz / blog.
- **Invocation:** internal `__secret`.
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ action:'status'|'generate', prompt|brief, purpose?, size? }`.
- **Output:** status → readiness `{ok, ready, model, sizes, has_fallback}`; generate → `{ok, url, size, purpose}` (or not-configured / error responses at HTTP 200).
- **Logic:** requires app_secrets.openai_api_key; if absent, returns not-configured with an optional `default_post_image` fallback and logs a skipped run. Otherwise builds a brand style preamble + agent brain (RPC fn_agent_context), calls OpenAI images/generations (gpt-image-1, size mapped from purpose), decodes b64 PNG, uploads to the `brand` bucket (designer/…), inserts a content_drafts image row, logs agent_runs.
- **Depends on:** `app_secrets` (inbound_secret, openai_api_key, default_post_image); OpenAI Images API; RPC `fn_agent_context`; storage bucket `brand`; tables content_drafts, agent_runs.
- **Notes:** clean. The only function here using OpenAI directly (not OpenRouter).

### money_tests
- **Purpose:** Automated invariant checks for the payment paths + security regressions; alerts the founder on any failure.
- **Invocation:** cron (daily) sending `__secret`; header comment states verify_jwt stays true as defence-in-depth.
- **Auth gate:** `body.__secret === inbound_secret` (else 403). Fix H4 — previously effectively reachable by any anon-key holder.
- **Input:** `{ __secret }`.
- **Output:** `{ok, passed, failed, results[]}`; on failures queues a founder alert email; logs agent_runs.
- **Logic:** reads pricing_config id=1 and asserts reveal-fee math (3%, zero, monotonic, capped); asserts stripe_secret_key is sk_live_ and Stripe account charges_enabled; probes that sensitive tables (reveal_invoices, customers, transactions, app_secrets) and RPC funnel_metrics are NOT anon-readable; asserts stripe_checkout/stripe_confirm reject no-auth and anon tokens. On any failure inserts a money_test_fail notification to founder_email/admin_emails.
- **Depends on:** `app_secrets` (inbound_secret, stripe_secret_key, founder_email, admin_emails); Stripe API (api.stripe.com/v1/account); own PostgREST (anon key) + edge functions stripe_checkout/stripe_confirm as black-box targets; RPC funnel_metrics; tables pricing_config, notifications, agent_runs.
- **Notes:** clean. Embeds the project's public anon JWT as a constant to run the black-box denial probes.

### capability_agent
- **Purpose:** Reads a supplier's own documents (trade licence + company profile, catalogue if needed), determines exactly what work they can take on against a controlled vocabulary, tells them what's missing, and records what the supplier confirms as source of truth for matching.
- **Invocation:** internal `__secret` (server-side only; not wired into live matching).
- **Auth gate:** `body.__secret === inbound_secret` (else 403).
- **Input:** `{ action:'analyze'|'confirm'|'state', supplier_id?, probe_text? (diagnostic), plus confirm payload fields }`.
- **Output:** analyze → `{ok, stage, sufficient, can_submit, missing, proposed, confirm_summary, confirm_questions, documents_read, vocabulary_rejected}`; confirm → `{ok, confirmed, version, ...}`; state → `{ok, capability, confirmed, history}`.
- **Logic:** loads taxonomy_trade/taxonomy_role as the controlled vocabulary. analyze: for a supplier, requires license_doc_path + company_profile_doc_path (else returns blocking asks), downloads those + up to 3 catalogue docs from `supplier-docs`, base64-attaches them (PDF as file, images inline) and calls the model (Sonnet 5 → Opus 4.8, vision, cached system prompt) for strict capability JSON; validates codes against the vocabulary; decides sufficiency in code (≥1 trade, ≥1 role, ≥2 products) rather than trusting the model; persists an unconfirmed extraction to supplier_capabilities (review_status awaiting_confirmation/insufficient). probe_text mode analyses supplied text only, never persists. confirm: validates supplier-agreed trades/roles against vocabulary, upserts supplier_capabilities (review_status confirmed) and inserts a versioned supplier_capability_confirmation row.
- **Depends on:** `app_secrets` (inbound_secret, openrouter_api_key); OpenRouter (multimodal); storage bucket `supplier-docs`; tables leads, taxonomy_trade, taxonomy_role, supplier_capabilities, supplier_capability_confirmation.
- **Notes:** clean, but explicitly NOT connected to live matching yet (safe/dormant by design). Only fleet function using multimodal document/image input and prompt caching (cache_control).

---

## OS Console, Ops, Health & Monitoring

### os_ops
- **Purpose:** Admin-gated operational backend for the QuotesDone OS — reads CRM/finance/file data via RPCs, records an audit trail, and applies mutating decisions (approvals, edits, GL posting).
- **Invocation:** Authenticated HTTP (POST) from the OS UI; preview bypass via `x-os-key` header. CORS-enabled.
- **Auth gate:** `x-os-key === app_secrets.os_bypass_key` grants a synthetic `os-preview@quotesdone.com` identity; otherwise `Authorization: Bearer <token>` is resolved with `admin.auth.getUser`, then `isAdmin(email)` must pass (role via RPC `fn_role_of` is owner/admin, OR email is in `app_secrets.admin_emails`) else 403.
- **Input:** JSON body `{ action, ... }`. Actions: `audit_log`, `content_get`/`content_save`, `list`, `detail`, `supplier_stats`, `customer_stats`, `expiring_docs`, `dropbox`, `dropbox_link`, `files`, `file`, `stages_list`, `kb_approve`/`kb_reject`/`kb_gov`, `po_approve`, `cancel_inquiry`, `prompt_reject`, `action_decide`, `supplier_decide`, `customer_decide`, `doc_review_decide`, `note_add`, `task_create`/`task_done`, `rfq_stage`/`rfq_outcome`, `field_set`, `gl_post`. Additional per-action fields (entity, id, op, values, lines, etc.).
- **Output:** JSON `{ ok, data }` or `{ error }`. Side effects: writes to `os_audit_log`; updates/inserts across many tables (see Depends on); posts double-entry journals; returns signed Dropbox/storage URLs.
- **Logic:** Handles OPTIONS. Authenticates (bypass key or JWT+admin). Parses body/action. For any action NOT in the READONLY set, inserts an `os_audit_log` row (actor, action, entity, entity_id, detail) — wrapped so audit failure never blocks. Then dispatches: `audit_log` queries `os_audit_log` (filterable by actor/act/entity, limit ≤1000) returning columns+rows with truncated detail. `content_get`/`content_save` read/patch a whitelisted CONTENT map (board_reports, exec_reports, finance_reports, agent_actions, security_events) by allowed fields only. Read actions delegate to RPCs (`fn_os_list`, `fn_os_detail`, `fn_supplier_stats`, `fn_customer_stats`, `fn_expiring_docs`, `fn_dropbox_list`, `fn_entity_files`). `dropbox_link` mints a Dropbox temporary link via OAuth refresh-token flow (`dbxToken`). `file` creates a 300s signed storage URL (default bucket `supplier-docs`). `stages_list` reads active `crm_stages`. Decision actions call RPCs (`fn_kb_approve`, `fn_kb_gov_approve`, `fn_po_approve`, `fn_cancel_inquiry`, `fn_prompt_reject_draft`) or directly patch tables (kb_revisions, agent_actions, leads, customers, doc_reviews, crm_notes, crm_tasks, inquiries). `field_set` updates only whitelisted EDITABLE fields (inquiries/leads/crm_tasks/expenses) with type coercion. `gl_post` validates ≥2 lines, non-negative debits/credits, balanced (dr==cr), non-zero, all account codes exist in `gl_accounts`; inserts a draft `gl_journal` + `gl_journal_lines`, then calls RPC `fn_gl_post` (rolls back journal on line-insert failure). Unknown action → 400.
- **Depends on:** Tables: os_audit_log, board_reports, exec_reports, finance_reports, agent_actions, security_events, crm_stages, kb_revisions, leads, customers, doc_reviews, crm_notes, crm_tasks, inquiries, gl_accounts, gl_journal, gl_journal_lines, app_secrets; storage buckets (supplier-docs). RPCs: fn_role_of, fn_os_list, fn_os_detail, fn_supplier_stats, fn_customer_stats, fn_expiring_docs, fn_dropbox_list, fn_entity_files, fn_kb_approve, fn_kb_gov_approve, fn_po_approve, fn_cancel_inquiry, fn_prompt_reject_draft, fn_gl_post. Secrets: os_bypass_key, admin_emails, dropbox_app_key/dropbox_app_secret/dropbox_refresh_token. External: Dropbox API (oauth2/token, files/get_temporary_link).
- **Notes:** clean.

### os_pages
- **Purpose:** In-OS Content Studio backend: edit/translate legal & marketing pages, AI-generate new SEO service landing pages in the background, and publish the site.
- **Invocation:** Authenticated HTTP (POST) from the OS UI; `x-os-key` preview bypass. Uses `EdgeRuntime.waitUntil` for background generation.
- **Auth gate:** Identical to os_ops — `x-os-key === app_secrets.os_bypass_key` → preview identity, else Bearer JWT resolved to email + `isAdmin` (fn_role_of role owner/admin OR admin_emails list) else 403.
- **Input:** JSON `{ action, ... }`. Actions: `pages_list`, `page_get`, `page_save`, `translate`, `service_list`, `service_generate`, `service_delete`, `publish`. Fields: source (legal|marketing), slug, locale (en|ar), title, html, name.
- **Output:** JSON `{ ok, data }` / `{ error }`. Side effects: audit rows; updates `qd_deploy_src` JSON blobs (legal.json, marketing.json, services.json); triggers a production deploy.
- **Logic:** Handles OPTIONS, authenticates. Audit-logs the mutating actions (page_save/publish/translate/service_generate/service_delete), truncating html to a `[N chars]` marker. Content lives as JSON strings in `qd_deploy_src` keyed by path (`src/content/legal.json`, `marketing.json`, `services.json`), read via `readPath`/`readFile`. `pages_list` enumerates legal+marketing slugs (source, slug, en title, has_ar). `page_get` returns one locale's title+html. `page_save` patches title/html for a slug/locale and writes the blob back. `translate` calls the `translate_html` edge function (via `translateHtml`, which protects `{{LOC_THE}}`/`{{LOC}}` placeholders as sentinel tags) using model gpt-4o (legal) or gpt-4o-mini (marketing) to produce Arabic. `service_list` lists services.json slugs. `service_generate` slugifies the name, rejects duplicates, then background-runs `buildService`: clones the first existing service's EN html template via OpenRouter (claude-sonnet-5/gpt-4o) with strict structure-preserving system prompt, validates placeholders survived and tag count ≥60% of template, translates to AR (falls back to EN on failure), and writes the new slug into services.json. `service_delete` removes a slug. `publish` calls `deploy_next_preview` with `target: production`.
- **Depends on:** Table: qd_deploy_src, os_audit_log, app_secrets. Edge functions: translate_html, deploy_next_preview (both called with `__secret` = inbound_secret). External: OpenRouter chat/completions. Secrets: os_bypass_key, admin_emails, openrouter_api_key, inbound_secret.
- **Notes:** clean.


### ai_health
- **Purpose:** Lightweight AI-provider liveness monitor — pings OpenRouter's free `/key` endpoint (no tokens spent) and pages the operator only on the transition into an outage.
- **Invocation:** Cron (`ai_health_15min`) via secret-gated HTTP POST. Header comment states verify_jwt=false.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret`. Fails CLOSED: if the stored secret is missing → 503; if the supplied secret is absent/wrong → 403 (post-19-Jul-2026 security fix; empty POST no longer bypasses).
- **Input:** JSON body `{ __secret }` (cron may send none, which is now rejected).
- **Output:** JSON `{ ok, healthy, recovered/consecutive_fails/paged, detail }`. Side effects: heartbeat rows in `agent_runs`; on outage transition inserts `founder_alerts` + `notifications`; persists failure counter in `app_secrets.ai_health_fails`.
- **Logic:** Parses body, verifies secret (logging a diagnostic agent_runs row on every reject path). Fetches OpenRouter `/api/v1/key` with 8s abort timeout; `ok = r.ok`. Reads prior consecutive-fail count from `app_secrets.ai_health_fails` (THRESHOLD=2). Records a heartbeat `agent_runs` row with a rich note. If healthy: when prior≥THRESHOLD it logs recovery (`founder_alerts` event `ai_recovered` + `notifications` to first admin_email), resets counter to 0, returns healthy. If down: increments and stores counter; exactly when fails==THRESHOLD it pages — inserts a `crit` `founder_alerts` (`ai_provider_down`) and a queued `notifications` email to the first admin. Deduped by only firing on the boundary crossing. Unhandled exceptions log an error agent_runs row and return 500.
- **Depends on:** Tables: app_secrets, agent_runs, founder_alerts, notifications. External: OpenRouter (api/v1/key). Secrets: inbound_secret, openrouter_api_key, admin_emails, ai_health_fails (state).
- **Notes:** clean; extensively self-documenting via agent_runs notes.

### alert_founder
- **Purpose:** Logs a founder alert and pushes it via WhatsApp + branded email, but only when the alert is actionable.
- **Invocation:** Internal call from other edge functions (e.g. uptime_check) via secret-gated HTTP POST.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` else 403.
- **Input:** JSON `{ event, detail?, level?, force?, dedupe_key? }`.
- **Output:** JSON `{ ok, whatsapp, email, notified }` (or logged/deduped variants). Side effects: `founder_alerts` row (channel updated to reflect outcome); queued `notifications` email; optional WhatsApp send.
- **Logic:** Verifies secret. Requires non-empty `event` (truncated 140). Inserts a `founder_alerts` row with channel `pending`. Determines `shouldNotify = force || level ∈ ACTIONABLE` (warn/warning/critical/error/high/urgent/action/danger/fail/failed/alert/escalation). If not actionable → updates the row's channel to `logged` and returns notified:false. De-dupe: if a `founder_alert`-type `notifications` row with a matching subject fragment was sent in the last 6h → marks channel `deduped`, returns. Otherwise: for high-severity levels (critical/urgent/high/danger) with an `admin_mfa_phone` set, calls `send_whatsapp`; always queues a branded HTML email (`wrapInternal`, "ACTION NEEDED" template) to the first `admin_emails` entry; updates the alert row's channel to whatsapp/email/none.
- **Depends on:** Tables: app_secrets, founder_alerts, notifications. Edge function: send_whatsapp (with __secret). Secrets: inbound_secret, admin_mfa_phone, admin_emails, email_logo_url.
- **Notes:** clean.

### uptime_check
- **Purpose:** Checks live quotesdone.com pages; self-heals deploy-shaped failures by auto-redeploying once (silent), and escalates to the founder only if still broken next run.
- **Invocation:** Cron (uptime) via secret-gated HTTP POST.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret`. Fails CLOSED: missing stored secret → 503; absent/wrong supplied secret → 403 (post-19-Jul-2026 fix — empty POST previously ran with full authority and could trigger production redeploys).
- **Input:** JSON `{ __secret }`.
- **Output:** JSON `{ ok, checks, failures }` / `{ self_heal }` / `{ escalated }`. Side effects: `agent_runs` rows; `founder_alerts` rows; `app_secrets.uptime_last_autoheal` timestamp; may call deploy_next_preview and alert_founder.
- **Logic:** Verifies secret (diagnostic agent_runs on reject). Fetches 6 SSR pages (`/`, `/me`, `/portal`, `/services/`, `/ar/`, `/terms/`) with 12s timeout, flagging failures for non-2xx (`http_N`), missing expected marker string, or body < 500 bytes. Logs a run to `agent_runs`. If no failures: if an auto-heal happened within the last 2h, logs `uptime_recovered` and clears the heal timestamp; returns healthy. If failures: computes `deployShaped` (marker/empty/5xx/404/fetch_error) and `canHeal` (deploy-shaped AND >1h since last heal). Inserts a `founder_alerts` `site_down` row (info if healable, else crit). If canHeal → fires `deploy_next_preview` (production), stamps `uptime_last_autoheal`, returns self_heal. Otherwise escalates via `alert_founder` (level critical, dedupe_key `site_down`).
- **Depends on:** Tables: app_secrets, agent_runs, founder_alerts. Edge functions: deploy_next_preview, alert_founder. External: quotesdone.com live pages. Secrets: inbound_secret, uptime_last_autoheal (state).
- **Notes:** clean.

### vercel_status
- **Purpose:** Reads Vercel deployment status / filtered build-error logs for a given deployment id.
- **Invocation:** Internal call (secret-gated HTTP POST), used by deploy tooling.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` else 403.
- **Input:** JSON `{ __secret, id, action? }`. `action === 'logs'` for build events; otherwise returns deployment state.
- **Output:** For `logs`: `{ ok, lines }` (last 40 error-matching event lines). Otherwise `{ ok, readyState, aliasError }`.
- **Logic:** Verifies secret. Loads `vercel_token` + `vercel_team_id`. For `logs`, GETs Vercel `v3/deployments/{id}/events` (backward, limit 200), keeps lines matching error/fail/cannot/Module/Type/Syntax etc., last 40. Otherwise GETs `v13/deployments/{id}` and returns readyState + aliasError.
- **Depends on:** Table app_secrets. External: Vercel API (v3 events, v13 deployments). Secrets: inbound_secret, vercel_token, vercel_team_id.
- **Notes:** No CORS headers, no OPTIONS handling — internal-only utility.

### cost_snapshot
- **Purpose:** Weekly burn + revenue snapshot — computes revenue (paid reveal fees), 7-day activity, and live OpenRouter spend, then queues an owner email.
- **Invocation:** Cron (cost_snapshot_weekly) via secret-gated HTTP POST.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret`. Fails CLOSED: missing stored secret → 503; absent/wrong supplied secret → 403 (post-19-Jul-2026 fix — empty POST previously returned full financials and could be abused as an unauthenticated mailer).
- **Input:** JSON `{ __secret, email? }` (`email:false` suppresses the owner email).
- **Output:** JSON `{ ok, snapshot }`. Side effects: `agent_runs` run log; queued `notifications` email to owner.
- **Logic:** Verifies secret (diagnostic logRun on reject). Fetches OpenRouter `api/v1/credits` for total_credits/total_usage/remaining. Computes revenue from `transactions` where fee_status='paid' (sum reveal_fee) for 7d/30d/all-time by revealed_at. Counts 7-day activity: inquiries (by created_at), paid reveals (transactions by revealed_at), sent emails (notifications channel=email status=sent), agent runs, newly onboarded suppliers (leads claimed=true). Builds a snapshot object. Unless `email:false`, queues a plaintext summary `notifications` email to the first admin_emails entry. Logs an `agent_runs` row with status reflecting email-queue success and OpenRouter reachability.
- **Depends on:** Tables: app_secrets, agent_runs, transactions, inquiries, notifications, leads. External: OpenRouter (api/v1/credits). Secrets: inbound_secret, openrouter_api_key, admin_emails.
- **Notes:** Only OpenRouter has a live spend API wired; Apify/Twilio/Resend/Supabase are noted as manual.

### dr_drill
- **Purpose:** Disaster-recovery restore drill — downloads backup JSON, reloads into a staging table, and reports backup-vs-live row counts + schema-key integrity.
- **Invocation:** Cron (secret-gated HTTP POST). CORS-enabled. Imports supabase-js from esm.sh (not jsr).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (read directly from app_secrets); rejects with 401 if secret missing or mismatched.
- **Input:** JSON `{ __secret, day? }` (day = `YYYY-MM-DD` backup folder; defaults to latest).
- **Output:** JSON `{ ok, day, tables, total_restored, note }`. Side effects: wipes and repopulates `public.dr_restore` staging; `agent_runs` run log. Live tables untouched.
- **Logic:** Handles OPTIONS. Verifies secret. Resolves `day` (explicit, else latest dated folder in the `backups` storage bucket having manifest-shaped names). Clears `dr_restore` (delete where id≠0). For each of 6 business-critical tables (pricing_config, customers, quotes, inquiries, transactions, inquiry_matches) with a required key column: downloads `{day}/{table}.json` from the `backups` bucket, parses the array, inserts rows into `dr_restore` (as `{kind, row}`, chunked by 500), counts restored rows, checks the first row has the required key, counts live rows, and marks `restore_ok` when restored==backup rows AND key present. Aggregates total_restored and failed tables. Logs `ok` only if clean, else `error` with detailed failNotes.
- **Depends on:** Tables: app_secrets, dr_restore, agent_runs, and the 6 checked live tables; storage bucket `backups`. Secrets: inbound_secret.
- **Notes:** clean.

### pending_digest
- **Purpose:** Daily email to admins listing suppliers awaiting approval.
- **Invocation:** Cron (secret-gated HTTP POST).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` else 403.
- **Input:** JSON `{ __secret }`.
- **Output:** JSON `{ ok, pending, sent }`. Side effect: queued `notifications` email(s) (drained by send_outbox).
- **Logic:** Verifies secret. Queries `leads` where (claimed=true OR source in self_registered/email_inbound) AND approval_status in (pending, submitted), ordered by registration_submitted_at, limit 100. If none, returns "nothing to review". Builds a numbered plaintext list of up to 40 suppliers (name, emirate, sector, licence, submitted date, truncated AI review note) with an "…and N more" tail, and queues one `pending_digest` notification per admin email (from admin_emails, default management@quotesdone.com) linking to /crm.
- **Depends on:** Tables: app_secrets, leads, notifications. Secrets: inbound_secret, admin_emails.
- **Notes:** clean.

### public_stats
- **Purpose:** Public marketing counters (indexed suppliers, verified suppliers, categories, emirates) for the website.
- **Invocation:** Public HTTP (POST/GET-style; OPTIONS handled). CORS-enabled with 5-minute cache header.
- **Auth gate:** None — public. Uses the service-role key server-side only to run count queries (no data rows returned, just counts).
- **Input:** None.
- **Output:** JSON `{ suppliers_indexed, verified_suppliers, categories: 30, emirates: 7 }`.
- **Logic:** Handles OPTIONS. Uses PostgREST count via a `count()` helper (Prefer count=exact, Range 0-0, parsing content-range). Counts all `leads` (indexed) and `leads` with registration_submitted_at not null AND approval_status=approved (verified). Returns those plus hardcoded categories=30, emirates=7. On error returns zeros with an error string.
- **Depends on:** Table leads (via REST). Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. No app_secrets.
- **Notes:** categories/emirates are hardcoded constants, not computed.

### report_body
- **Purpose:** Returns the full stored text of a board/agent report for the OS reports viewer.
- **Invocation:** Authenticated HTTP (POST) from OS UI. CORS-enabled.
- **Auth gate:** `Authorization: Bearer <jwt>` resolved via `admin.auth.getUser`; user must have an email, and if `admin_emails` is non-empty the email must be in it (else 403 admin-only). 401 if no user.
- **Input:** JSON `{ id }` (numeric; report_registry.id maps 1:1 to board_reports.id).
- **Output:** JSON `{ ok, found, report }` where report is `{ id, title, report_type, week_start, body, kpis, created_at }`, or `{ ok, found:false }` if none.
- **Logic:** Handles OPTIONS. Authenticates JWT + admin_emails gate. Requires numeric `id`. Fetches the matching `board_reports` row and returns it.
- **Depends on:** Tables: app_secrets, board_reports. Secrets: admin_emails.
- **Notes:** clean.

### support_ai
- **Purpose:** In-app customer support chatbot — answers QuotesDone questions grounded in a fixed FAQ, live pricing, and the signed-in user's own account data.
- **Invocation:** Authenticated HTTP (POST) from the web app. CORS-enabled.
- **Auth gate:** No secret gate; requires a signed-in user. If no JWT/user resolves, returns a friendly "please sign in" reply with `auth_required:true` (200, not an error). All account data is scoped to the caller's own email.
- **Input:** JSON `{ messages: [{ role, content }] }` (last 12 user/assistant messages kept).
- **Output:** JSON `{ reply }` (or `{ auth_required }`). Side effect: inserts an `ai_usage` row per request (rate limiting).
- **Logic:** Handles OPTIONS. Filters/keeps last 12 valid messages (400 if none). Resolves the JWT to a user; unauthenticated → sign-in reply. Loads the customer by email; if found, fetches their last 8 `inquiries` and per-inquiry `quotes` counts to build ACCOUNT DATA context. Enforces a rate limit of 40 support messages/hour per email via `ai_usage`; over-limit → throttle reply. Loads `openrouter_api_key` (offline reply if missing) and `pricing_config` (authoritative pricing block). Composes a system prompt (FAQ + pricing + account data) and calls OpenRouter chat/completions trying models in order (claude-sonnet-4.6, gpt-4o, gemini-2.0-flash-001, llama-3.3-70b) until one returns content. Returns the reply, or a graceful fallback pointing to info@quotesdone.com. Language auto-mirrors the customer (English/Arabic).
- **Depends on:** Tables: customers, inquiries, quotes, ai_usage, app_secrets, pricing_config. External: OpenRouter (api/v1/chat/completions). Secrets: openrouter_api_key.
- **Notes:** clean.

---

## Email & Inbound Comms + OTP

### email_cron
- **Purpose:** Scheduled parent job that auto-detects Resend domain verification, flips `email_enabled` on, and triggers the outbox flush.
- **Invocation:** cron (runs every 2 minutes). Header comment does not state verify_jwt; it is secret-gated internally.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403, logged throttled).
- **Input:** JSON body `{ __secret, limit? }` (limit is not read here; only `__secret`).
- **Output:** `{ ok:true, enabled, verified, flush }`. Side effects: may update `app_secrets.email_enabled='true'`; inserts `agent_runs` rows (throttled/one-per-hour for recurring states, none for healthy idle runs).
- **Logic:**
  1. Reject if `__secret` mismatch (throttled `forbidden` log).
  2. Read `email_enabled`; treat as `enabled`/`verified`.
  3. If not enabled: fetch `resend_api_key` + `resend_domain_id`; GET `https://api.resend.com/domains/{did}`. If status `verified`, set `email_enabled='true'` and log `email_auto_enabled`; else record a `domainNote` (unverified/failed/missing creds).
  4. If enabled: POST to `{SUPABASE_URL}/functions/v1/send_outbox` with `{ __secret, limit:50 }`, capture JSON as `flush`; note HTTP errors.
  5. If disabled: count queued `notifications` (status queued/pending/null) and emit throttled `email_disabled` error explaining the pipeline is idle.
  6. Log an error run if the outbox flush failed.
- **Depends on:** DB tables `app_secrets`, `agent_runs`, `notifications`; secrets `inbound_secret`, `email_enabled`, `resend_api_key`, `resend_domain_id`; edge fn `send_outbox`; external API Resend (domains).
- **Notes:** clean. This is the only place a fully-disabled mail pipeline surfaces (send_outbox is never invoked while disabled).

### email_fix
- **Purpose:** Admin/enrichment RPC to list leads missing an email and bulk-apply crawled emails back onto them.
- **Invocation:** internal call / authenticated HTTP (secret-gated RPC).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, action }`. `action:'list'` → `{ after? }`. `action:'apply'` → `{ rows:[{id,email,domain?,mx?}], source? }`.
- **Output:** list → `{ rows:[{id,company_name,website,domain}] }`; apply → `{ ok:true, updated }`.
- **Logic:**
  - `list`: select up to 1000 leads where email is null/empty AND website not null AND `id > after`, ordered by id asc.
  - `apply`: for each row with id+email, update `leads` (email lowercased, `email_domain`, `email_verified=!!mx`, `enrich_source=source` default `web_crawl`) only where email is still null/empty; count successes.
  - Unknown action → 400.
- **Depends on:** DB table `leads`, `app_secrets`; secret `inbound_secret`. No external APIs.
- **Notes:** clean.

### email_triage
- **Purpose:** Reads un-triaged inbound emails, LLM-classifies and drafts a reply, and surfaces drafts to the founder; never sends.
- **Invocation:** internal call / cron (secret-gated).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret }`.
- **Output:** `{ ok:true, counts:{triaged,drafted,spam} }`. Side effects: updates `inbound_messages` (ai_category/summary/draft/triaged_at); inserts `agent_actions` (`inbound_review`) and resolves prior `sla_review` actions; writes an `agent_runs` row.
- **Logic:**
  1. Insert an `agent_runs` row (agent `email_triage`).
  2. Select up to 20 `inbound_messages` where `needs_review=true`, `triaged_at` null, `replied_at` null, oldest first.
  3. For each, call the shared LLM (`makeLlm(SONNET_FIRST,{max:700})`) with QuotesDone inbox SYS prompt on From/Subject/body (body sliced 4000 chars); parse strict-JSON `{category,summary,reply}`.
  4. Update the message with the AI fields + `triaged_at`.
  5. If category `spam` or empty reply → count as spam. Else: resolve any older pending `sla_review` actions on this message (set `auto_done`), then insert a `pending` low-risk `inbound_review` `agent_action` carrying the draft.
  6. Finalize the run with counts.
- **Depends on:** DB tables `agent_runs`, `inbound_messages`, `agent_actions`, `app_secrets`; secret `inbound_secret`; `_shared/llm.ts` (`makeLlm`, `SONNET_FIRST`); secret `openrouter_api_key` (via llm); external API OpenRouter (Sonnet-first).
- **Notes:** clean. Draft-only by design; a human sends from the Inbox.

### send_outbox
- **Purpose:** Flushes queued EMAIL notifications through Resend, honouring suppressions, daily cap, unsubscribe, supplier-send gate, stale guard, retries + dead-letter.
- **Invocation:** cron / internal call (invoked by email_cron). Header comment: `verify_jwt=false` (secret-gated).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403, throttled log). Preview mode also requires the secret via the same guard.
- **Input:** JSON `{ __secret, limit?, preview?, sample?, subject?, internal? }`.
- **Output:** `{ ok:true, sent, failed, retried, deadlettered, skipped, suppressed, held, pending, cap, remaining_today }` (or preview `{ ok:true, html }`). Side effects: updates `notifications` statuses (sent/queued/failed/skipped/suppressed/held) and attempts/last_error/sent_at; writes `agent_runs` rows (throttled for config states, none for idle).
- **Logic:**
  1. Preview: render internal/branded HTML template from a sample body and return (no send).
  2. Load config: `email_enabled`, `supplier_emails_enabled`, `email_stale_hours` (def 72), `resend_api_key`, from/reply addresses (supplier/info/docs), `email_logo_url`, signature name/title, templates `email_supplier`/`email_customer`, `daily_send_cap` (def 80).
  3. Compute `sentToday` (notifications sent since UTC midnight) and `remaining = cap - sentToday`.
  4. Fetch queued notifications (status queued/pending/null, oldest first, `limit` def 40).
  5. If `!email_enabled` or no Resend key → throttled `email_disabled` log, return without sending. If `remaining<=0` → throttled `cap_reached` log, return.
  6. Load `email_suppressions` for the batch recipients.
  7. Per notification: skip SMS channel; mark `skipped` if no to_email; `suppressed` if on suppression list; `held` if older than stale hours; determine supplier vs internal (admin/founder) by `to_role`; doc-requests (`isDocRequest(type)` regex on licence/renew/expir/doc-request) bypass the supplier gate, otherwise `held` if `supplier_emails_enabled` is false; stop if `sent>=remaining`.
  8. Choose from/reply addr, build unsubscribe URL for supplier mails (`unsubscribe?e=&t=HMAC`), render HTML via `tmpl()` (supplier wrapper template / customer template / internal `renderBody` structured HTML), POST to `https://api.resend.com/emails` (with List-Unsubscribe headers when unsub present).
  9. On success mark `sent`+`sent_at`; on failure `failNote()` increments attempts, re-queues, and dead-letters (`failed`) at `MAX_ATTEMPTS=3`.
  10. Log run: error if dead-lettered/failed, ok if any work done, nothing if idle.
- **Depends on:** DB tables `notifications`, `app_secrets`, `templates`, `email_suppressions`, `agent_runs`; secrets `inbound_secret`, `email_enabled`, `supplier_emails_enabled`, `email_stale_hours`, `resend_api_key`, `email_from_supplier`, `email_from_info`, `email_reply_supplier`, `email_reply_supplier_docs`, `email_reply_info`, `email_logo_url`, `email_signature_name`, `email_signature_title`, `daily_send_cap`; edge fn `unsubscribe` (URL only); external API Resend (send emails).
- **Notes:** clean. Own HMAC-SHA256 unsubscribe token (first 20 hex chars), matching the `unsubscribe` function.

### inbound_email
- **Purpose:** Generic inbound-email webhook: matches/creates a supplier lead from the sender, AI-profiles the email body + image attachments, and updates the lead.
- **Invocation:** public HTTP webhook (external) + accepts internal secret. CORS enabled.
- **Auth gate:** header `x-webhook-secret` or `body.__secret` must equal `app_secrets.inbound_webhook_secret` OR (backward-compat) `inbound_secret` (else 403).
- **Input:** JSON `{ from|sender, from_name?, subject?, text|body?, to?, attachments?:[{mime|content_type,data}] }`. POST only (405 otherwise; OPTIONS handled).
- **Output:** `{ ok:true, lead_id, company, matched_existing, created_new_lead, ai_ok, fields_updated }` (or a `needs_review` response for ambiguous multi-lead matches). Side effects: inserts/updates `leads`, inserts `inbound_messages`.
- **Logic:**
  1. Parse sender; require `fromEmail`. Compute domain; flag free-mail providers via `FREE` set.
  2. Match lead: exact `email` ilike (single → use; multiple → queue ambiguous `inbound_messages` needs_review and return). If none and domain is non-free, match by `email_domain`/`domain` ordered by reviews.
  3. If still none: infer sector via keyword map (`inferSector`), insert a new `leads` row (business_role `supplier`, source `email_inbound`, contacted true).
  4. Call `profile_ai` edge fn with `{ __secret:inbound_secret, company_name, sector, emirate, text, images }`; capture `profile`+`ai_ok`.
  5. Merge AI fields onto the lead via `setField` (skips empty; will not overwrite non-empty fields on `verified` leads): description, services, products, certifications, founded_year, company_size, company_type, contact_name, trade_license_no, capability_summary, service_emirates; infer sector if lead had none.
  6. Always set `contacted=true`, `portal_updated_at`; apply update if any fields.
  7. Insert `inbound_messages` record of the interaction.
- **Depends on:** DB tables `leads`, `inbound_messages`, `app_secrets`; secrets `inbound_webhook_secret`, `inbound_secret`; edge fn `profile_ai`; no direct external API (LLM is via profile_ai).
- **Notes:** clean. Distinct from `resend_inbound` — this is a generic/legacy inbound handler (no Svix verification, images passed inline in the body).

### resend_inbound
- **Purpose:** Resend inbound-email webhook that routes forwarded receipts to bookkeeping and supplier documents to storage + AI classification/auto-extraction onto the matched lead.
- **Invocation:** public HTTP webhook (Resend). Svix-signed.
- **Auth gate:** two factors — query token `?s=` must equal `inbound_secret` or `resend_inbound_token`, AND Svix signature (`svix-id/timestamp/signature`) verified against `resend_inbound_signing_secret` (HMAC-SHA256, 5-min replay window). Missing signing secret → 503; bad signature → 401; bad token → 403.
- **Input:** raw JSON Resend `email.received` event (`data` with email_id/from/to/subject/text/html/attachments). Query `?s=`.
- **Output:** `{ ok:true, ... }` variants (receipt booked/deduped/not-booked, or `matched_lead, stored, reviews, applied`). Side effects: inserts `expense_entries`, `expenses`, `inbound_messages`, `doc_reviews`, `notifications`; updates `leads`; uploads to storage buckets `receipt-files` and `supplier-docs`; writes `agent_runs`.
- **Logic:**
  1. Validate `?s=` token; read body once as raw text; require + verify Svix signature.
  2. Parse event; extract email_id, from/to/subject, body (`pickBody`, HTML stripped). If body/attachments thin, fetch full email from `https://api.resend.com/emails/inbound/{id}`.
  3. Determine `toLocal`, admin allowlist (`admin_emails`), expense forwarders (`expense_forwarders`), owner.
  4. **Receipt path** (`isReceiptish` on mailbox/subject/from): LLM-extract vendor/amount/currency/date/recurring/period via OpenRouter (`RECEIPT_SYS`, model `anthropic/claude-sonnet-5`). If sender not allowlisted → log to `inbound_messages` + notify, don't book. Dedup: any existing `expense_entries` for same vendor+date blocks booking (exact match = silent ignore; differing amount = flagged for review notification). Else archive receipt (PDF attachment or generated HTML) to `receipt-files`, insert `expense_entries`; if recurring, upsert `expenses`; notify owner `expense_logged`.
  5. **Document path** (no receipt): match `leads` by `email`/`claimed_by`. For up to 6 attachments: download bytes (`attachmentBytes` via content/url/Resend attachment API), upload to `supplier-docs`, LLM-classify (`SYS`). For `trade_license` → call `license_extract` (mode `license`) and apply licence no/authority/expiry/city/emirate/TRN (respecting existing values); for `company_profile`/`catalogue` → `license_extract` (mode `profile`) applying capability/services/products/emirates + doc paths. Insert `doc_reviews` per doc; track lost/upload/classify failures.
  6. Insert an `inbound_messages` summary; notify owner if records auto-updated; send supplier a `doc_received` notification. Log run (error if attachments lost/upload failed).
- **Depends on:** DB tables `app_secrets`, `expense_entries`, `expenses`, `leads`, `inbound_messages`, `doc_reviews`, `notifications`, `agent_runs`; storage buckets `receipt-files`, `supplier-docs`; secrets `inbound_secret`, `resend_inbound_token`, `resend_inbound_signing_secret`, `resend_api_key`, `openrouter_api_key`, `admin_emails`, `expense_forwarders`; edge fn `license_extract`; external APIs Resend (inbound emails/attachments) + OpenRouter (Claude Sonnet).
- **Notes:** clean. v13 hardened with Svix signature verification; v14 dedup by vendor+date (not amount) to stop double-counting redelivered receipts.

### resend_webhook
- **Purpose:** Receives Resend delivery events; on hard bounce or spam complaint, adds the recipient to `email_suppressions` so they're never emailed again.
- **Invocation:** public HTTP webhook (Resend). Svix-signed.
- **Auth gate:** two factors — query `?key=` must equal `resend_webhook_key` or `inbound_secret`, AND Svix signature verified against `resend_webhook_signing_secret` (HMAC-SHA256, 5-min window). Missing signing secret → 503; bad signature → 401; bad key → 403.
- **Input:** raw JSON Resend event `{ type|event, data:{to/email/recipient/recipients, bounce{type} } }`. Query `?key=`.
- **Output:** `{ ok:true, type, suppressed }`. Side effects: upserts `email_suppressions`; updates `leads.invite_status='bounced'`; inserts `error_events`; writes `agent_runs`.
- **Logic:**
  1. Validate `?key=`; read raw body once; require + verify Svix signature.
  2. Parse type; collect recipient emails (`emailsOf`).
  3. Detect complaint (`type` contains "complain") or hard bounce (`type` contains "bounce" and bounce type not transient/soft).
  4. If so and emails present: upsert each into `email_suppressions` (reason `spam_complaint` or `hard_bounce[:type]`, source `resend_webhook`); mark matching leads `invite_status='bounced'`; insert one `error_events` row.
  5. Log an ok run (suppressed count).
- **Depends on:** DB tables `app_secrets`, `email_suppressions`, `leads`, `error_events`, `agent_runs`; secrets `resend_webhook_key`, `inbound_secret`, `resend_webhook_signing_secret`; external API Resend (delivery events).
- **Notes:** clean. Catch-all returns HTTP 200 (with error body) so a thrown handler does not make Resend retry-storm; the exception is logged.

### unsubscribe
- **Purpose:** One-click unsubscribe landing page that adds the address to `email_suppressions`.
- **Invocation:** public HTTP (GET from email List-Unsubscribe link / user click).
- **Auth gate:** HMAC token — `?t` must equal first 20 hex chars of HMAC-SHA256(`inbound_secret`, lowercased email); else an "invalid link" page (400).
- **Input:** query params `e` (email), `t` (token).
- **Output:** HTML page (branded). Side effect: upserts `email_suppressions` (reason `unsubscribe`, source `link`).
- **Logic:** Compute expected token from `e` + `inbound_secret`; if `e`/`t`/secret missing or token mismatch → invalid-link page. Else upsert suppression and render an "Unsubscribed" confirmation. Errors render a soft "something went wrong / reply to be removed" page (HTTP 200).
- **Depends on:** DB tables `app_secrets`, `email_suppressions`; secret `inbound_secret`. No external APIs.
- **Notes:** clean. Token scheme mirrors `send_outbox`'s `unsubTok`.

### mobile_otp
- **Purpose:** Customer mobile-phone verification via Twilio Verify (send/check OTP), plus status and read-only diagnostics.
- **Invocation:** authenticated HTTP (customer Supabase JWT). Header comment: `verify_jwt=false` (validates JWT internally). CORS enabled.
- **Auth gate:** `send`/`verify`/`status` require a valid Supabase JWT (`admin.auth.getUser`) with an email; `diag` requires `body.__secret === inbound_secret`.
- **Input:** JSON `{ action, phone?, code?, __secret? }`. Actions: `status`, `send`, `verify`, `diag`.
- **Output:** JSON per action (`{ ok, sms_enabled, phone, phone_verified }` etc.). Side effects: inserts/updates `customers`; inserts/updates `customer_phone_otps` ledger.
- **Logic:**
  1. Read Twilio Verify creds (`twilio_verify_service_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`); `smsEnabled` if all present.
  2. `diag` (secret-gated): if creds missing report which; else GET the Verify service and report reachability/auth.
  3. Otherwise validate JWT → email; get-or-create `customers` row by email.
  4. `status`: return sms_enabled + stored phone/phone_verified.
  5. `send`: normalise phone (UAE defaults, `normPhone`); rate-limit to 5 sends / 10 min per customer via `customer_phone_otps` count; POST Twilio Verify `Verifications` (Channel sms); on success insert a ledger row (`code_hash:'twilio_verify'`, no code stored — Twilio holds it).
  6. `verify`: validate phone + 4–8 digit code; POST Twilio `VerificationCheck`; require `status==='approved'`; mark ledger rows consumed and set `customers.phone`+`phone_verified=true`.
- **Depends on:** DB tables `app_secrets`, `customers`, `customer_phone_otps`; secrets `twilio_verify_service_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`, `inbound_secret`; external API Twilio Verify (v2). Uses Supabase Auth (`admin.auth.getUser`).
- **Notes:** clean. Uses Twilio API-key Basic auth + a Verify service; no OTP code is ever stored locally.

### voice_otp
- **Purpose:** (Former) TwiML voice-OTP endpoint — DISABLED.
- **Invocation:** was public HTTP (Twilio voice webhook); now returns 410 for any request.
- **Auth gate:** none (that was the vulnerability — see Notes).
- **Input:** none read.
- **Output:** static TwiML `<Response><Say>This service is unavailable.</Say><Hangup/></Response>` at HTTP 410.
- **Logic:** Always returns the GONE TwiML; performs no work.
- **Depends on:** nothing (no DB/secret/external calls).
- **Notes:** DEAD / disabled 18 Jul 2026 (security). It previously emitted `voice_capture_token` in cleartext TwiML to anonymous callers, which was the only gate on `voice_otp_capture`. Kept as a 410 stub for discoverability/reversibility. Re-enable requires `twilio_auth_token` + X-Twilio-Signature validation.

### voice_otp_capture
- **Purpose:** (Former) captured spoken OTP digits into `app_secrets.voice_otp_last` — DISABLED, paired with voice_otp.
- **Invocation:** was public HTTP (Twilio Gather callback, gated by `?k=` token); now returns 410.
- **Auth gate:** none functional (returns 410 before any processing); the old `?k=` token scheme was the vulnerability.
- **Input:** none read.
- **Output:** static TwiML `<Response><Hangup/></Response>` at HTTP 410. Side effect: inserts an `agent_runs` error row noting a caller hit the disabled endpoint (stale callback or probe).
- **Logic:** Log the hit to `agent_runs`, then return the HANGUP TwiML.
- **Depends on:** DB table `agent_runs` (logging only); Supabase service client.
- **Notes:** DEAD / disabled 18 Jul 2026 (security). Was an unauthenticated write into `app_secrets` (`voice_otp_last`). Re-enable requires `twilio_auth_token` + X-Twilio-Signature validation and dropping the token-in-URL scheme.

---

## WhatsApp / SMS + Lead Ingestion & Scraping

### send_whatsapp
- **Purpose:** Sends WhatsApp messages via Twilio, either a single direct message or by draining the queued `channel='whatsapp'` notifications backlog using Meta-approved templates.
- **Invocation:** Internal call / cron (header comment: runs every 2 minutes). No `verify_jwt` comment; guarded by inbound secret.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, to?, body? }`. If `to`+`body` present → single direct send; otherwise flush mode (no extra params).
- **Output:** JSON. Direct mode: `{ ok, sid, error }`. Flush mode: `{ ok, sent, failed, skipped, requeued, unmapped, templates_ready }`. Side effects: sends Twilio messages; updates `notifications` rows to `sent`/`failed`/`skipped` (with `sent_at`); writes `agent_runs` rows (throttled to 1/hour per signal).
- **Logic:** Loads Twilio creds (`twilio_account_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`, `twilio_wa_from`); returns `whatsapp_not_configured` (200) if any missing. Reads `wa_templates_ready` flag and `wa_template_sids` map. Direct mode: `normPhone()` (defaults to +971 for local numbers), sends `Body` (truncated 1500) via `waSendBody`. Flush mode: selects up to 25 queued whatsapp notifications with a `to_phone`, ordered oldest first. For each, `tmplKey()` maps `type` to one of `supplier_new_inquiry` / `customer_new_quote` / `customer_supplier_unlocked` / `supplier_doc_expiry`. If templates ready + key mapped + SID registered → sends template via `waSendTemplate` with `ContentSid` and `ContentVariables` `{1: shortSummary, 2: url}` (url chosen by `varsFor`: suppliers→/suppliers, doc-expiry→/portal, else→/app). If not ready OR key mapped but SID missing → left `queued`, counted as `skipped`+`requeued`. If genuinely unmapped type → marked `skipped` in DB and surfaced as `unmapped`. Logs throttled error signals for `templates_not_ready`, `unmapped_type`, and Twilio rejections.
- **Depends on:** Tables `app_secrets`, `notifications`, `agent_runs`. Secrets `inbound_secret`, `twilio_account_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`, `twilio_wa_from`, `wa_templates_ready`, `wa_template_sids`. External: Twilio Messages API. Queued by SQL fns `fn_doc_final_notice` / `fn_reconcile_doc_blocks` (doc-expiry rows).
- **Notes:** clean. Uses Basic auth from API key SID/secret (not account auth token).

### wa_inbound
- **Purpose:** Smart LLM WhatsApp responder on the QuotesDone API number that answers supplier/customer questions and escalates when needed.
- **Invocation:** Public HTTP webhook (Twilio inbound), `verify_jwt=false` (stated in code). Also accepts authenticated JSON callers (test/replay harness).
- **Auth gate:** JSON path: `j.__secret === app_secrets.inbound_secret` (fails closed if missing/empty → sets `trusted`). Form (Twilio) path: `verifyTwilioSignature` (HMAC-SHA1 of full URL + sorted params vs `X-Twilio-Signature`, dormant until `twilio_auth_token` exists); if no token, falls back to `verifyProvenance` (REST lookup of the `MessageSid` against Twilio to confirm it exists, is inbound, and sender matches).
- **Input:** Twilio form params (`From`, `Body`, `ProfileName`, `MessageSid`/`SmsMessageSid`) or JSON `{ __secret, From, Body, ProfileName, MessageSid }`.
- **Output:** TwiML `<Response></Response>` (always 200 to Twilio, 403 on failed signature). Side effects: composes+sends a WhatsApp reply via Twilio (if `wa_autoreply_enabled='true'`); inserts `wa_messages` row; on send-failure/escalation inserts `founder_alerts` + `notifications`; writes `agent_runs` and throttled `founder_alerts`.
- **Logic:** Parses payload; rejects empty From/Body. Runs webhook authenticity (signature → provenance). On unverifiable form webhook: saves message to `wa_messages` with `sent:false`, alerts (throttled 30 min), does NOT run LLM or send. On verified: calls `fn_identify_contact(p_phone)` RPC to classify audience (supplier/customer/unknown), builds an audience-specific system prompt with SHARED/CUSTOMER/SUPPLIER facts, retrieves matching `company_faq` rows (`retrieveFaq` token-overlap scoring), pulls last 3 `wa_messages` for history, and calls OpenRouter (`llm`) trying `anthropic/claude-sonnet-5` then `anthropic/claude-opus-4.8`, expecting strict JSON `{reply, lang, audience, escalate}`. Falls back to a generic reply if LLM fails. Applies `bidiSafe()` (wraps LTR runs in U+2066/U+2069 isolates for Arabic). Sends reply if autoreply enabled; logs escalations and send failures to founder.
- **Depends on:** Tables `app_secrets`, `wa_messages`, `company_faq`, `founder_alerts`, `notifications`, `agent_runs`. RPC `fn_identify_contact`. Secrets `inbound_secret`, `twilio_account_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`, `twilio_wa_from`, `twilio_auth_token` (optional), `openrouter_api_key`, `wa_autoreply_enabled`, `admin_emails`. External: Twilio Messages API, OpenRouter.
- **Notes:** clean. Extensive inline security history (v10 provenance, v11 signature). Signature validation is implemented but dormant until `twilio_auth_token` is added.

### wa_template_setup
- **Purpose:** Manages the WhatsApp Content template for supplier document-expiry notices — create, submit for Meta approval, register the SID, and inspect delivery.
- **Invocation:** Internal/admin HTTP call. No `verify_jwt` comment; secret-guarded.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, action, ... }`. Actions: `status` (default), `create` (`language` en/ar), `delete` (`content_sid`), `msg_check` (`to`).
- **Output:** JSON with SIDs/statuses only (never echoes secrets). `create` returns `content_sid`, approval status, `registered_in_app_secrets`.
- **Logic:** Loads Twilio creds (returns `twilio_not_configured` 503 if key SID/secret missing). `create`: builds a `twilio/text` Content template (EN or AR body, both opening AND closing with literal text so Meta accepts `{{1}}`/`{{2}}`), POSTs to `content.twilio.com/v1/Content`, submits a `UTILITY`-category WhatsApp ApprovalRequest, and merges the new SID into `wa_template_sids` under key `supplier_doc_expiry` by language. `status`: for each registered language fetches its ApprovalRequests and returns Meta status/rejection reason. `msg_check`: lists last 5 Twilio messages to a number with status/error codes. `delete`: DELETEs a Content SID (validated `HX...` format).
- **Depends on:** Table `app_secrets`. Secrets `inbound_secret`, `twilio_account_sid`, `twilio_api_key_sid`, `twilio_api_key_secret`, `wa_template_sids`. External: Twilio Content API + Messages API.
- **Notes:** clean. Only manages the single `supplier_doc_expiry` template (`KEY` constant).

### wa_templates_watch
- **Purpose:** Polls Twilio for WhatsApp template approval; when ALL templates are approved, flips `wa_templates_ready='true'` and notifies the founder.
- **Invocation:** Cron (header: polls, self-unschedules when done). No auth gate.
- **Auth gate:** none (no secret check; unauthenticated).
- **Input:** none (ignores request body).
- **Output:** JSON `{ ok, total, approved, rejected, all_approved, statuses }`. Side effects: upserts `wa_templates_ready` secret; inserts founder `notifications`; calls `cron_unschedule_wa_watch`; writes `agent_runs`.
- **Logic:** Early-returns if `wa_templates_ready` already true. Loads Twilio key creds (logs throttled `no_twilio_creds` error if missing). Parses `wa_template_sids` map into `{name, sid}` pairs; errors if empty/unparseable. For each SID, GETs `content.twilio.com/v1/Content/<sid>/ApprovalRequests` and reads `whatsapp.status`. If all approved: upserts `wa_templates_ready='true'`, inserts a founder email notification (subject notes "All 6 WhatsApp templates approved"), and calls `cron_unschedule_wa_watch` RPC to stop polling; logs any write/notify/cron failures. Otherwise logs throttled errors for rejected or unreadable-status templates; still-pending = silent idle run.
- **Depends on:** Tables `app_secrets`, `notifications`, `agent_runs`. RPC `cron_unschedule_wa_watch`. Secrets `wa_templates_ready`, `twilio_api_key_sid`, `twilio_api_key_secret`, `wa_template_sids`, `founder_email`, `admin_emails`. External: Twilio Content API.
- **Notes:** clean. Imports supabase-js from `esm.sh` (others use `jsr:`). Header says "6 templates" but the map is data-driven.

### sup_dob
- **Purpose:** Persists supplier owner date-of-birth (KYC) onto the lead the caller has claimed.
- **Invocation:** Authenticated HTTP (browser, Supabase JWT). CORS-enabled.
- **Auth gate:** Supabase JWT via `admin.auth.getUser(jwt)`; requires `user.email` (else 401).
- **Input:** JSON `{ owner_dob }` (YYYY-MM-DD).
- **Output:** JSON `{ ok: true }` or error. Side effect: updates `leads.owner_dob`.
- **Logic:** Extracts Bearer JWT, resolves the user, validates `owner_dob` matches `^\d{4}-\d{2}-\d{2}$` (else `bad_date` 400), updates `leads.owner_dob` for all rows where `claimed_by` equals the user's lowercased email.
- **Depends on:** Table `leads`. External: Supabase Auth.
- **Notes:** clean. Tiny.

### apify_scrape
- **Purpose:** Drives Apify Google-Maps scraping (email-focused) into `public.leads`.
- **Invocation:** Internal HTTP call. Secret-guarded.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, action, ... }`. Actions: `account`, `start` (`actor`, `input`, `sector`, `emirate`, `label`, `requested`), `status` (`run_id?`), `collect` (`run_id`, `limit?`).
- **Output:** JSON per action. Side effects: inserts `scrape_runs` rows; upserts `leads` (on `place_id`, ignore duplicates).
- **Logic:** Reads `apify_token` (returns `no_apify_token` 200 if missing). `account`: queries Apify user/limits. `start`: POSTs an actor run (default `compass/crawler-google-places`), records a `scrape_runs` row with run/dataset IDs. `status`: single-run stats from Apify or a listing of recent `scrape_runs`. `collect`: loads the `scrape_runs` row, checks the run finished (SUCCEEDED/READY), fetches dataset items paginated from `fetched` offset (max 1000), maps each via `mapItem()` (extracts company/phone/website/domain/email/socials, drops noreply emails), keeps only rows with both `place_id` AND `email`, de-dupes within batch and against existing `leads` by `place_id` and `email`, then upserts new rows tagged with `sector`, `emirate`, `source='apify_YYYY-MM'`, `enrich_source='apify_maps_contacts'`. Updates run `fetched`/`inserted`/`status`.
- **Depends on:** Tables `app_secrets`, `scrape_runs`, `leads`. Secrets `inbound_secret`, `apify_token`. External: Apify API (Google Places actor).
- **Notes:** clean.

### yello_scrape
- **Purpose:** Scrapes the yello.ae UAE business directory (listings → profiles → emails) into `yello_staging`.
- **Invocation:** Internal HTTP call. Secret-guarded. CORS-enabled.
- **Auth gate:** `auth(body)` — `body.__secret === inbound_secret` OR `body.__test === test_token` (both read from `app_secrets`).
- **Input:** JSON `{ __secret|__test, action, ... }`. Actions: `stats`, `crawl_category` (`category`, `city?`, `from_page?`, `to_page?`), `crawl_profiles` (`limit?` ≤25), `crawl_emails` (`limit?` ≤20).
- **Output:** JSON per action. Side effects: upserts/updates `yello_staging` rows through pipeline stages `listed`→`profiled`→`emailed` (or `dead`).
- **Logic:** `stats`: aggregates staging rows by stage and counts with-email (also calls `exec_count_stage` RPC). `crawl_category`: fetches directory pages (up to 20 per call, 350ms delay), extracts `/company/<id>/<slug>` links via regex (`parseListing`), upserts each as stage `listed`. `crawl_profiles`: fetches listed rows' profile pages, `parseProfile()` scrapes name/website/phones/mobile/whatsapp/categories/manager/established, classifies `sector` via `sectorFor()` regex map, marks `profiled` (or `dead` on fetch failure). `crawl_emails`: for profiled rows with a website and no email, fetches website + `/contact`, `/contact-us`, `/about`, `extractEmails()` filters junk and scores by domain match / role prefix, stores best email and marks `emailed`.
- **Depends on:** Tables `app_secrets`, `yello_staging`. RPC `exec_count_stage`. Secrets `inbound_secret`, `test_token`. External: yello.ae (HTML scraping).
- **Notes:** clean. Still carries the dormant `__test`/`test_token` auth branch (no `test_token` row exists today; noted as inert in dir_ingest's comments).

### dir_ingest
- **Purpose:** Bulk-ingests externally-scraped supplier directory rows into `yello_staging`.
- **Invocation:** Internal HTTP call. Secret-guarded. CORS-enabled.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` only — fails closed if secret missing/empty. (The former `__test`/`test_token` branch was removed 19 Jul 2026 for security.)
- **Input:** JSON `{ __secret, action, rows? }`. Actions: `stats`, `ingest` (`rows[]` with `company_id` + optional name/slug/city/category/website/phone/whatsapp/email/sector).
- **Output:** JSON. `stats`: `{ total, with_email, by_stage, by_sector }`. `ingest`: `{ ok, received, upserted }`.
- **Logic:** `stats`: aggregates `yello_staging` by stage and (email-bearing) sector. `ingest`: filters rows requiring `company_id`, truncates/normalises fields, sets `email_source='directory'` and stage `emailed` if email present else `profiled`, and upserts in chunks of 200 on conflict `company_id`.
- **Depends on:** Tables `app_secrets`, `yello_staging`. Secret `inbound_secret`. External: none.
- **Notes:** clean. Feeds the same `yello_staging` pipeline as yello_scrape.

### reg_fetch
- **Purpose:** Downloads an official regulation/code PDF into the `compliance-docs` bucket, links it to `reg_catalog` + `compliance_sources`, and triggers indexing.
- **Invocation:** Internal HTTP call. Secret-guarded.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, catalog_id?, url?, authority?, topic? }`.
- **Output:** JSON. Success: `{ ok, authority, bytes, compliance_source_id, indexed }`. Rejection: `{ ok:false, note:'not_a_document', ... }`. Side effects: uploads to storage, inserts `compliance_sources`, updates `reg_catalog` status, calls `kb_ingest`.
- **Logic:** If `catalog_id` given, loads the `reg_catalog` row to fill url/authority/topic. Fetches the URL (follows redirects, custom UA). Detects a real PDF by content-type or `%PDF` magic bytes AND size ≥ 30000 bytes; otherwise marks the catalog row `needs_source` and returns `not_a_document`. Uploads the PDF to `compliance-docs/catalog/<id>_<ts>.pdf`, inserts a `compliance_sources` row (`fetch_mode='reg_fetch'`, active), updates the catalog to `downloaded` with `compliance_source_id`. Then POSTs to the `kb_ingest` edge function (passing `__secret` + the new source id) and, if it produced chunks, marks the catalog `indexed`.
- **Depends on:** Tables `reg_catalog`, `compliance_sources`, `app_secrets`; storage bucket `compliance-docs`. Secret `inbound_secret`. Other fn: `kb_ingest`. External: the source document URL.
- **Notes:** clean.

### vt_scan
- **Purpose:** Privacy-safe malware scanner — hashes storage files locally (SHA-256) and checks the hash against VirusTotal without ever uploading file contents.
- **Invocation:** Internal HTTP call (worklist supplied by `fn_run_vt`). Secret-guarded.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON `{ __secret, files:[{bucket, path, size}] }`.
- **Output:** JSON `{ ok, counts }` (checked/malicious/clean/unknown/errors/skipped). Side effects: inserts `vt_results`; on malware inserts `security_events`, `agent_actions`, and a `notifications` email; writes `agent_runs`.
- **Logic:** Opens an `agent_runs` row. Skips if no `virustotal_api_key`. For each file: skips (`skipped_large`) if >25 MB; downloads the blob from storage, computes SHA-256, GETs `virustotal.com/api/v3/files/<hash>`. HTTP 200 → reads `last_analysis_stats`, `malicious`+`suspicious`>0 ⇒ `malicious` else `clean`; 404 ⇒ `unknown`; else `error`. Records a `vt_results` row. On malicious: raises a high-severity `security_events` row, a pending high-risk `agent_actions` alert, and an admin email notification. Finalises the agent run with counts.
- **Depends on:** Tables `vt_results`, `security_events`, `agent_actions`, `notifications`, `agent_runs`, `app_secrets`; Supabase Storage. RPC/fn `fn_run_vt` (builds worklist upstream). Secrets `inbound_secret`, `virustotal_api_key`, `admin_emails`. External: VirusTotal API v3.
- **Notes:** clean.

### export_leads_csv
- **Purpose:** Streams the full `leads` table (with PII) as a downloadable CSV.
- **Invocation:** Authenticated/admin HTTP or internal secret call.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` OR a Supabase JWT whose email is in `admin_emails` (else 403). Deliberately not behind any shared test token.
- **Input:** JSON `{ __secret? }` and/or `Authorization: Bearer <jwt>`.
- **Output:** `text/csv` attachment (`quotesdone_leads.csv`), a fixed 33-column set, all cells double-quote-escaped.
- **Logic:** Authenticates (secret then admin JWT). Paginates `leads` 1000 rows at a time ordered by `id`, emitting a header row plus one CSV line per lead until exhausted.
- **Depends on:** Tables `leads`, `app_secrets`. Secrets `inbound_secret`, `admin_emails`. External: Supabase Auth.
- **Notes:** clean.

### inquiry_ai
- **Purpose:** Turns a customer's free-text/photo/voice request into one structured, supplier-priceable brief (spec, category, compliance, follow-up questions) via a two-pass LLM pipeline.
- **Invocation:** Authenticated HTTP (customer app, Supabase JWT). CORS-enabled.
- **Auth gate:** Supabase JWT (`admin.auth.getUser`) OR `body.__test === app_secrets.test_token`; else 401. Plus a rate limit of 30 requests/hour per identity via `ai_usage`.
- **Input:** JSON `{ text?, emirate?, images?:[{mime,data}], __test? }` + Bearer JWT.
- **Output:** JSON: the parsed brief `{ ok, request_type, out_of_scope, category, emirate, spec, summary, scope_type, trades, compliance, missing, needs_more, agent, label, confidence, notes, fields }`, or `{ error, fallback }` (200) on AI failure.
- **Logic:** Authenticates and enforces the hourly limit (records an `ai_usage` row). Loads `openrouter_api_key`, the `category_specs` catalog, and the `compliance_ref` secret. Builds a multimodal prompt (customer text ≤6000 chars, up to 5 images, chosen emirate) and calls OpenRouter (`callModel`, models `claude-opus-4.8` then `claude-sonnet-5`) with the `SYS` intake prompt returning strict JSON. Normalises emirate (`normalizeEmirate` maps UAE districts to parent emirate), scope_type, trades, compliance. Then resolves the best-matching expert sales agent from `category_agents` (token-overlap scoring) and loads its persona + `agent_knowledge` (`agent_key='cat:<slug>'`), and runs a second "estimator" pass (`EST_SYS`) to finalise the question set. Merges/dedupes questions against captured spec (`mergeMissing`, caps at 8, appends a "Not sure" option to required selects), sets `needs_more`.
- **Depends on:** Tables `app_secrets`, `ai_usage`, `category_specs`, `category_agents`, `agent_knowledge`. Secrets `openrouter_api_key`, `compliance_ref`, `test_token`. External: OpenRouter (Anthropic models). Supabase Auth.
- **Notes:** clean. Retains the `__test`/`test_token` auth path (test_token row not present today).

### inquiry_dedup_check
- **Purpose:** Tells a signed-in customer whether their new request duplicates a recent inquiry.
- **Invocation:** Authenticated HTTP (customer app, Supabase JWT). CORS-enabled.
- **Auth gate:** Supabase JWT with `user.email` (else 401).
- **Input:** JSON `{ summary?|text?, hours? }` + Bearer JWT.
- **Output:** JSON `{ duplicate:false }` or `{ duplicate:true, inquiry:{...} }`.
- **Logic:** Resolves the user, looks up their `customers` row (no row ⇒ not a duplicate). Takes `summary` (≤500 chars; skips if <13 chars) and a window `hours` (clamped 1–720, default 72). Calls RPC `recent_duplicate_inquiry(p_customer, p_summary, p_window)`; if it returns an id, fetches that `inquiries` row and returns it.
- **Depends on:** Tables `customers`, `inquiries`. RPC `recent_duplicate_inquiry`. External: Supabase Auth.
- **Notes:** clean.

### claim_lookup
- **Purpose:** Public "is this your company?" check for the supplier lead-claim flow, keyed by an unguessable token.
- **Invocation:** Public HTTP (invited suppliers have no account yet). CORS-enabled.
- **Auth gate:** none by design — but requires a valid `leads.claim_token` UUID; the old numeric-`id` path is removed and rejected+logged.
- **Input:** JSON `{ token|t }` (UUID). Legacy `{ id|ref }` is rejected.
- **Output:** JSON `{ ok:true, company_name, emirate, claimable, already_claimed }` or an error shape (`invalid_link` 400, `not_found` 404, `temporarily_unavailable` 503). Side effect: writes `agent_runs`.
- **Logic:** Reads `token`/`t`. If absent but a numeric `id`/`ref` is present, logs a scrape/legacy-template warning and returns `invalid_link`. Validates UUID format. Looks up the `leads` row by `claim_token`; on DB error returns 503 (and logs that a valid supplier may have been wrongly turned away). If no row or `permanently_closed`, returns `not_found` (does not distinguish never-existed from closed). Otherwise returns company name + emirate and whether it is still claimable.
- **Depends on:** Tables `leads`, `agent_runs`. External: none.
- **Notes:** clean. v2 security fix — replaced enumerable sequential id with `claim_token` UUID (from `leads_claim_token_stop_enumeration` migration) to stop bulk harvesting of the 20,470-row lead DB.

### rate_dims
- **Purpose:** Persists the 6 reputation dimensions onto an existing review row, called right after `rate_supplier`.
- **Invocation:** Authenticated HTTP (customer app, Supabase JWT). CORS-enabled.
- **Auth gate:** Supabase JWT with `user.email`, and a matching `customers` row (else 401).
- **Input:** JSON `{ quote_id, r_communication?, r_quality?, r_punctuality?, r_documentation?, r_after_sales?, r_compliance? }` (each 1–5).
- **Output:** JSON `{ ok, updated }` or error. Side effects: updates `reviews`; calls `recompute_supplier_rating`.
- **Logic:** Resolves the user and their `customers` row. Requires `quote_id`. Collects the 6 dimension fields that are valid integers 1–5. Verifies the customer actually transacted: finds a `transactions` row matching `quote_id`+`customer_id` (else 403), then the `reviews` row for that transaction+customer (else 409 "submit overall rating first"). Applies the dimension patch to the review, then (best-effort) reads the quote's `supplier_id` and calls RPC `recompute_supplier_rating(p_supplier)`.
- **Depends on:** Tables `customers`, `transactions`, `reviews`, `quotes`. RPC `recompute_supplier_rating`. External: Supabase Auth.
- **Notes:** clean.

---

## Knowledge Base, Embeddings & Category Knowledge

### kb_autofill_gaps
- **Purpose:** Cron worker that finds service categories with zero knowledge chunks and autonomously fills the worst ones by delegating to kb_fill_gap.
- **Invocation:** cron (scheduled); callable via HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else logs an error run and returns 401.
- **Input:** JSON body `{ __secret, limit? }` — `limit` clamped to 1–5 (default 2).
- **Output:** `{ ok:true, filled:[...] }` where each entry is `{ category, ok, inserted, error, http }`. Side effects: writes an `agent_runs` row per invocation; on total failure POSTs to `alert_founder`.
- **Logic:** (1) Loads all `category_specs` (category,label). (2) For each, does a head count on `kb_chunks` filtered by category; collects those with zero chunks until `limit` gaps found. (3) If no gaps, logs "no gaps" and returns. (4) For each gap, POSTs to `<SUPABASE_URL>/functions/v1/kb_fill_gap` with `{__secret, category, label}` and records the result. (5) If no fill succeeded (`anyOk` false), POSTs a warn-level alert to `alert_founder`. (6) Builds a detailed note (all-failed / partial / all-filled, plus a warning if success reported but 0 chunks inserted) and logs an `agent_runs` row with status error when nothing succeeded or 0 inserted, else ok.
- **Depends on:** DB tables `category_specs`, `kb_chunks`, `agent_runs`; app_secrets key `inbound_secret`; edge functions `kb_fill_gap` and `alert_founder` (called over HTTP via `SUPABASE_URL/functions/v1`); env `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
- **Notes:** clean.

### kb_embed
- **Purpose:** Backfill worker that computes `gte-small` embeddings for unembedded `kb_chunks` rows and writes them into `embedding_gte`.
- **Invocation:** cron (frequent backfill); callable via HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else throttled-logs and returns 403.
- **Input:** JSON body `{ __secret, limit?, scope? }` — `limit` clamped 1–40 (default 10); `scope` (if not `'all'`, restricts to `source_kind='library'` first).
- **Output:** `{ ok:true, embedded, remaining }` (or `{ ok:true, done:true, embedded:0 }` when nothing to do). Side effect: updates `kb_chunks.embedding_gte`; writes throttled `agent_runs` rows.
- **Logic:** (1) Selects up to `limit` chunks where `embedding_gte IS NULL`, preferring `source_kind='library'` unless scope=all; if none found in library and scope!=all, retries across all chunks. (2) If nothing, returns done. (3) Runs the in-region `Supabase.ai.Session('gte-small')` model on `title + '\n' + content` truncated to 1200 chars with `{mean_pool:true, normalize:true}`. (4) Writes the vector back as a Postgres array literal `'[...]'`. (5) Counts remaining unembedded and logs a throttled progress/error run (distinguishing write-failures — which cause infinite re-picking — from progress).
- **Depends on:** DB table `kb_chunks`, `agent_runs`; app_secrets `inbound_secret`; built-in `Supabase.ai.Session` gte-small model (384-dim gte-small, no external API); env `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
- **Notes:** clean. `logThrottled` suppresses duplicate log signals within a 60-min window.

### kb_fill_gap
- **Purpose:** Generates UAE-specific trade knowledge (4–6 sections) for a single category via an LLM and inserts it as `source_kind='generated'` chunks.
- **Invocation:** internal call from kb_autofill_gaps; also authenticated HTTP (admin JWT). Handles CORS OPTIONS. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')` OR a Bearer token whose user email passes `isAdmin` (via RPC `fn_role_of` returning owner/admin, or membership in `app_secrets.admin_emails`).
- **Input:** JSON body `{ __secret? , category (required), label? }` (label defaults to category).
- **Output:** `{ ok:true, inserted, category }`. Side effects: inserts rows into `kb_chunks`; best-effort `agent_actions` row (agent `knowledge_curator`).
- **Logic:** (1) Auth check. (2) Requires `category`; loads `openrouter_api_key`. (3) Calls OpenRouter (`anthropic/claude-sonnet-5`, temp 0.2) with a prompt demanding STRICT JSON `{sections:[{title,content}]}` covering scope, UAE regs/authorities (SIRA, Dubai Municipality, Civil Defence, DEWA, ADDC, ESMA, TDRA…), materials/brands, AED pricing drivers, quality red flags, timeline. (4) `parseSections` strips code fences and extracts the sections array; one retry if empty; 502 `generation_failed` if still empty. (5) Maps up to 8 sections to `kb_chunks` rows (source_kind='generated', citation built from category/title, effective_date=today) and bulk-inserts. (6) Logs an `agent_actions` row.
- **Depends on:** DB `kb_chunks`, `agent_actions`, `app_secrets`; RPC `fn_role_of`; app_secrets `inbound_secret`, `admin_emails`, `openrouter_api_key`; external OpenRouter API (claude-sonnet-5).
- **Notes:** clean.

### kb_import
- **Purpose:** One-off importer for uploaded knowledge libraries — signs an upload URL, then ingests `imports/kb_final.json` into `kb_chunks` as `source_kind='library'` via a safe staging swap.
- **Invocation:** manual/secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, op }` where op is `'sign'` or `'ingest'`.
- **Output:** For `sign`: `{ ok:true, full_url, path }`. For `ingest`: `{ ok:true, inserted }`. Side effects: creates `backups` storage bucket; writes/replaces chunks in `kb_chunks`.
- **Logic:** `sign` — creates (or ignores existing) private `backups` bucket and returns a signed upload URL for `imports/kb_final.json`. `ingest` — downloads that JSON; must be an array; clears any prior `library_staging` rows; batches of 200 insert as `source_kind='library_staging'` (mapping category/title/content/citation, effective_date=today); on any batch error it deletes staging and aborts leaving live library intact; only after all batches succeed does it delete the old `source_kind='library'` rows and promote staging → library via update. Promote-failure leaves new chunks under `library_staging`.
- **Depends on:** DB `kb_chunks`, `app_secrets`; storage bucket `backups` (path `imports/kb_final.json`); app_secrets `inbound_secret`; env `SUPABASE_URL`.
- **Notes:** clean. H14 audit note in code: staging-swap design prevents wiping the live library on mid-import failure.

### kb_ingest
- **Purpose:** Extracts full text from downloaded authority/compliance PDFs (compliance-docs bucket) and indexes them as `source_kind='document'` chunks for exact-clause FTS retrieval.
- **Invocation:** internal/cron drainer over HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else throttled-logs and 403.
- **Input:** JSON body `{ __secret, id?, min_bytes? }`. With `id`: ingest one specific `compliance_sources` row. Without: queue mode processes ONE not-yet-ingested real PDF. `min_bytes` default 50000.
- **Output:** `{ ok:true, results:[...] }` or `{ ok:true, mode:'queue', processed, remaining_estimate }`. Side effects: deletes+inserts `kb_chunks` rows; writes `agent_runs`.
- **Logic:** (1) Auth. (2) If `id` given, load that `compliance_sources` row and `ingestOne` it. (3) Queue mode: load all `compliance_sources` with non-null `doc_path`, filter to content-type containing `pdf` and `doc_bytes >= min_bytes`, and process the first with zero existing `compliance:<id>#%` chunks. `ingestOne`: downloads the PDF from `compliance-docs`, uses unpdf (`getDocumentProxy`+`extractText mergePages`) to get text, `chunkText` splits by paragraphs to ~1800 chars (min 40 chars), deletes prior `compliance:<id>#%` chunks, inserts new rows (source_kind='document', source_id=`compliance:<id>#i`, category=null, title=topic, citation=`authority — topic [url]`) in batches of 100. Extensive throttled logging for download/no-text(scanned)/insert failures that would block the queue.
- **Depends on:** DB `compliance_sources`, `kb_chunks`, `agent_runs`; storage bucket `compliance-docs`; npm `unpdf@0.11.0`; app_secrets `inbound_secret`; env `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
- **Notes:** clean.

### kb_ingest_text
- **Purpose:** Ingests clean markdown/text knowledge directly into `kb_chunks` (source_kind='document'), also storing the raw source file for reference.
- **Invocation:** secret/key-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__key === sec('kb_ingest_key')` OR `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __key|__secret, source_id (required), text (required, ≥40 chars), title?, category?, citation? }`.
- **Output:** `{ ok:true, source_id, chunks, stored }`. Side effects: uploads `uae_library/<source_id>.md` to compliance-docs; deletes+inserts `kb_chunks`.
- **Logic:** (1) Auth. (2) Validate source_id and text length. (3) Best-effort upload of raw markdown to `compliance-docs/uae_library/<sanitized>.md` (upsert). (4) `chunkText` (~1800 chars, min 40). (5) Delete prior `uae_kb:<source_id>#%` chunks (idempotent). (6) Insert rows (source_kind='document', source_id=`uae_kb:<source_id>#i`, category, title, citation, effective_date=null) in batches of 100. Returns count inserted and stored path.
- **Depends on:** DB `kb_chunks`, `app_secrets`; storage bucket `compliance-docs`; app_secrets `kb_ingest_key`, `inbound_secret`.
- **Notes:** clean.

### kb_retrieve
- **Purpose:** RAG retrieval endpoint over the knowledge corpus via the `kb_query` SQL RPC (FTS-based), returning ranked cited snippets to ground agent answers.
- **Invocation:** internal call from agents over HTTP POST. Handles CORS OPTIONS. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, query, category?, limit? }` — query sliced to 500 chars; limit clamped 1–20 (default 8).
- **Output:** `{ ok:true, results, grounding }` where `grounding` is a numbered `[n] title / snippet / Source: citation` string.
- **Logic:** (1) Auth. (2) Calls RPC `kb_query(p_query, p_category, p_limit)`. (3) Maps rows into a formatted grounding block and returns rows + grounding.
- **Depends on:** SQL RPC `kb_query`; DB `app_secrets`; app_secrets `inbound_secret`.
- **Notes:** clean. Simpler/FTS-only sibling of kb_search (which adds semantic vectors + RRF).

### kb_search
- **Purpose:** Hybrid knowledge retrieval combining semantic (gte-small vector) and full-text search, merged with Reciprocal Rank Fusion (RRF).
- **Invocation:** internal call over HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, query (required), k?, category? }` — query sliced to 800; k clamped 1–20 (default 8).
- **Output:** `{ ok:true, query, count, results }` where each result has id, category, title, citation, snippet, similarity, via (e.g. `semantic+keyword`).
- **Logic:** (1) Auth + query required. (2) Semantic pass (best-effort): runs `Supabase.ai.Session('gte-small')` on the query, calls RPC `kb_match(query_embedding, match_count=20, p_category)`, adds results with RRF weight `1/(60+rank)`. (3) Full-text pass: `kb_chunks.textSearch('fts', query, {type:'websearch', config:'english'})` limit 20, optional category filter, added with RRF. (4) Merges by chunk id, sums RRF scores, sorts desc, returns top k with tags. Semantic failure falls back silently to keyword only.
- **Depends on:** DB `kb_chunks` (fts column), `app_secrets`; SQL RPC `kb_match`; built-in `Supabase.ai.Session` gte-small; app_secrets `inbound_secret`.
- **Notes:** clean. RRF constant `RRF_K = 60`.

### learn_gaps
- **Purpose:** Self-improving intake: examines inquiries that were matched to suppliers but got ZERO quotes, asks an LLM estimator per category which quote-critical fields are missing, and merges new questions into that category's intake checklist.
- **Invocation:** weekly cron; callable via HTTP POST (`{job:'run'}`). Handles CORS OPTIONS. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else logs error and 403.
- **Input:** JSON body `{ __secret, max_categories? (1–8, def 4), min_cases? (def 2), since_days? (min 2, def 3) }`.
- **Output:** `{ ok:true, categories_reviewed, results }`. Side effects: updates/inserts `category_specs.fields`; inserts `agent_actions` review cards; writes `agent_runs`.
- **Logic:** (1) Auth + require `openrouter_api_key`. (2) Loads open (not completed/accepted/closed/cancelled) `inquiries` created between 45 days ago and `since_days` ago, with a category, capped 1500. (3) Bulk-fetches (chunks of 200) `inquiry_matches` and `quotes` to build hasMatch/hasQuote sets (H15 audit fix replacing per-inquiry queries). (4) Groups briefs (summary + spec) by category for inquiries that have a match but no quote. (5) Selects categories with ≥`min_cases`, top `max_categories`. (6) Per category: loads current `category_specs.fields`, calls `llm` (OpenRouter models sonnet-5 then opus-4.8, temp 0.2) with a UAE-estimator system prompt returning STRICT JSON `{fields:[...]}` (≤3 new quote-critical fields), filters out keys already present, normalizes them (source='learned'), merges (cap 22 fields), updates/inserts `category_specs`, and inserts an `agent_actions` review card (kind checklist_improved, pending, low risk). (7) Rich note + logs an `agent_runs` row (error status on save/parse/all-failed conditions).
- **Depends on:** DB `inquiries`, `inquiry_matches`, `quotes`, `category_specs`, `agent_actions`, `agent_runs`, `app_secrets`; app_secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter (claude-sonnet-5 / claude-opus-4.8).
- **Notes:** clean.

### export_all_knowledge
- **Purpose:** Renders the complete agent knowledge base (global + fixed specialists + category sales agents) as a single Markdown document.
- **Invocation:** secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else returns plain `forbidden` 403.
- **Input:** JSON body `{ __secret }`.
- **Output:** `text/markdown` document (not JSON). No writes.
- **Logic:** (1) Auth. (2) Loads all `agent_knowledge` rows (agent_key, topic, content, priority) ordered by priority desc, and active `category_agents` (slug, name, persona). (3) Groups knowledge by agent_key. (4) Builds Markdown: header with live pull date and category count; GLOBAL section (`_global`); FIXED SPECIALIST AGENTS iterating a hardcoded `FIXED` map (brief, secretary, cfo, legal, collections, bookkeeper, onboarding, docs, security, it, followup, bd, marketing); CATEGORY SALES AGENTS section listing each active category with persona and topic-ordered knowledge entries (fixed topic order array). Date/counts computed at runtime (OPEN_ISSUES #6 fix — previously hardcoded).
- **Depends on:** DB `agent_knowledge`, `category_agents`, `app_secrets`; app_secrets `inbound_secret`.
- **Notes:** clean.

### export_cat_knowledge
- **Purpose:** Renders only the category sales agents' deep knowledge packs (persona + per-topic knowledge) as Markdown.
- **Invocation:** secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else plain `forbidden` 403.
- **Input:** JSON body `{ __secret }`.
- **Output:** `text/markdown` document. No writes.
- **Logic:** (1) Auth. (2) Loads active `category_agents` (slug,name,persona) and `agent_knowledge` rows with `agent_key LIKE 'cat:%'` ordered by priority. (3) Groups by agent_key. (4) Emits Markdown header (runtime category count + pull date), then per category the persona and knowledge entries sorted by a preferred topic order then priority.
- **Depends on:** DB `category_agents`, `agent_knowledge`, `app_secrets`; app_secrets `inbound_secret`.
- **Notes:** clean. Category-only subset of export_all_knowledge.

### gen_category_knowledge
- **Purpose:** Generates a dense UAE field-expertise brief (codes/standards/specs) per active category and stores it as an `agent_knowledge` row (topic "Field expertise — UAE codes, standards & specs").
- **Invocation:** cron/secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else logs error and 403.
- **Input:** JSON body `{ __secret, limit? (1–24, def 8), force? }`.
- **Output:** `{ ok:true, generated, covered, total, remaining }`. Side effects: deletes+inserts `agent_knowledge` rows; writes `agent_runs`.
- **Logic:** (1) Auth + require `openrouter_api_key`. (2) Determines categories already having the field-knowledge topic; unless `force`, excludes them; takes up to `limit`. (3) In parallel per category, calls OpenRouter (`models: sonnet-5, opus-4.8`, max 700, temp 0.3) with a detailed system prompt demanding a 230–340-word UAE-specific brief on governing authority/approvals, standards, scope/specs, price drivers, compliance pitfalls, with a hard rule never to invent code numbers. (4) If output >120 chars, deletes the old row for that category+topic and inserts the new one (priority 8, content capped 4000 chars); short outputs counted as failures. (5) Recomputes coverage and logs a detailed `agent_runs` note (error status on insert failures or zero generated).
- **Depends on:** DB `agent_knowledge`, `category_agents`, `agent_runs`, `app_secrets`; app_secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter (claude-sonnet-5 / claude-opus-4.8).
- **Notes:** clean. Uses its own inline `llm` helper (not _shared/llm).

### gen_category_personas
- **Purpose:** Generates a 70–110-word second-person sales-agent persona/charter per active category and stores it in `category_agents.persona`.
- **Invocation:** cron/secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else logs error and 403.
- **Input:** JSON body `{ __secret, limit? (1–24, def 8), force? }`.
- **Output:** `{ ok:true, generated, remaining }`. Side effects: updates `category_agents.persona`; writes `agent_runs`.
- **Logic:** (1) Auth + require `openrouter_api_key`. (2) Selects active `category_agents`; unless `force`, only those with null persona; up to `limit`. (3) In parallel per category, calls OpenRouter (`models: sonnet-5, opus-4.8`, max 420, temp 0.4) with a system prompt to write a UAE-specific expert sales persona for that trade. (4) If output >60 chars, updates `persona` (capped 2000 chars); short outputs counted as failures. (5) Counts remaining personas-null and logs a detailed `agent_runs` run (error on update failures or zero generated).
- **Depends on:** DB `category_agents`, `agent_runs`, `app_secrets`; app_secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter (claude-sonnet-5 / claude-opus-4.8).
- **Notes:** clean. Inline `llm` helper.

### category_provision
- **Purpose:** When a supplier self-registers a trade not in the catalog, classify it against existing category agents; if genuinely new, auto-provision a full-parity agent (persona/playbook/spec LIVE; AI quoting knowledge + reg mapping staged PENDING for founder approval).
- **Invocation:** internal call over HTTP POST (e.g. from supplier onboarding). No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, raw_category|category (required), hint_services?, lead_id? }`.
- **Output:** `{ ok:true, action }` — action is `matched` (with matched_slug/confidence/reason), `exists`, or `provisioned` (with slug, name, live[], pending[], reg_matches, review_action_id). Side effects: inserts `category_agents`, `qualification_playbooks`, `category_specs` (upsert), `agent_actions` review card; may update `leads.categories`.
- **Logic:** (1) Auth + require raw category. (2) Loads active service `category_agents` (excludes underscore/internal slugs) as a catalog. (3) LLM classify (shared _shared/llm makeLlm SONNET_FIRST, max 1600, temp 0) returns JSON `{match, confidence, proposed_slug, proposed_name, reason}`; if it matches an existing slug, updates lead and returns matched. (4) Else slugify a new slug/name; idempotent check — if agent exists, return exists. (5) LLM generate (up to 2 attempts, 3800 tokens) a minified-JSON parity kit: emoji, persona, knowledge (200–350 words), questions (8–11 RFQ objects), reg_keywords, supplier_requirements, compliance_checklist; 502 if generation fails. (6) LIVE writes: insert `category_agents` (persona/emoji/active), insert `qualification_playbooks` (v1 active with questions), upsert `category_specs` (label + supplier_requirements + compliance_checklist). (7) Reg-mapping proposal: load up to 200 `regulations` and match by reg_keywords into title/authority, top 8. (8) Insert a founder review `agent_actions` card (agent knowledge_curator, kind category_knowledge, pending, medium risk) carrying the pending knowledge + reg matches. (9) Optionally set `leads.categories`.
- **Depends on:** DB `category_agents`, `qualification_playbooks`, `category_specs`, `regulations`, `agent_actions`, `leads`, `app_secrets`; `_shared/llm.ts` (makeLlm, SONNET_FIRST); app_secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter (sonnet-5 / opus-4.8 via shared client).
- **Notes:** clean. Hybrid model: intake artifacts go live immediately, quoting knowledge gated behind approval.

### category_reqs
- **Purpose:** AI generator for per-category UAE supplier requirements + compliance checklists, written into `category_specs`.
- **Invocation:** secret-gated HTTP POST. Handles CORS OPTIONS. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, action ('generate'|'backfill'), category? (for generate), limit? (backfill, 1–8, def 3) }`.
- **Output:** `generate`: `{ ok, category }`. `backfill`: `{ ok:true, generated:[...], remaining_unfilled }`. Side effect: updates `category_specs` (supplier_requirements, compliance_checklist, reqs_updated_at).
- **Logic:** (1) Auth. (2) `generate`: verify the category exists in `category_specs`, then `genOne` — LLM (shared makeLlm SONNET_FIRST, max 1400, temp 0.2) with a UAE-onboarding system prompt returning JSON `{supplier_requirements:[...], compliance_checklist:[...]}`; parse and update the row. (3) `backfill`: find up to `limit` `category_specs` rows with null `supplier_requirements` and `genOne` each, collecting successes.
- **Depends on:** DB `category_specs`, `app_secrets`; `_shared/llm.ts` (makeLlm, SONNET_FIRST); app_secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter (sonnet-5 / opus-4.8 via shared client).
- **Notes:** clean.

### licence_reminder
- **Purpose:** Finds active suppliers whose UAE trade licence expires within N days (or recently expired) and queues a branded renewal-request email inviting them to reply with the new licence.
- **Invocation:** cron; callable via secret-gated HTTP POST. No verify_jwt comment.
- **Auth gate:** `body.__secret === sec('inbound_secret')`; else 403.
- **Input:** JSON body `{ __secret, days? (1–60, def 7), resend_after_days? (3–30, def 10) }`.
- **Output:** `{ ok:true, candidates, queued, skipped, window_days, sample }`. Side effect: inserts `notifications` rows (type licence_renewal_reminder, channel email, status queued).
- **Logic:** (1) Auth. (2) Computes an expiry window from 30 days ago (to chase already-expired) up to `days` in the future. (3) Loads up to 500 `leads` that are approved + claimed + not-null license_expiry within the window. (4) Per lead: skip if banned or no valid recipient (claimed_by || email); de-dupe by checking for a recent `notifications` row of the same type/lead within `resend_after_days`; compute days-to-expiry and craft a subject/body (expired vs expires-soon wording, includes trade_license_no if present) asking the supplier to REPLY with the renewed licence (auto-processed by resend_inbound at docs@mail.quotesdone.com). (5) Insert the queued notification; tally queued/skipped and a sample list.
- **Depends on:** DB `leads`, `notifications`, `app_secrets`; app_secrets `inbound_secret`; downstream: emails are sent by the notifications dispatcher and replies handled by `resend_inbound` (referenced in comments, not called directly).
- **Notes:** clean.

---

## Finance, Legal, Compliance, PDPL, Backup & Retention

### finance_doc
- **Purpose:** Store an original finance PDF/receipt, AI-extract it, post the resulting entry via finance_ingest, and queue the original for Dropbox backup.
- **Invocation:** Authenticated HTTP (admin JWT) or internal/server call with `__secret`. CORS-enabled (OPTIONS handled).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret`, OR Bearer JWT whose email passes `isAdmin()` — role from RPC `fn_role_of` is `owner`/`admin`, or the email is in `app_secrets.admin_emails`.
- **Input:** `{ __secret?, filename, mime, b64 }` — base64 file (strips `data:...,` prefix).
- **Output:** `{ ok, path, extracted_chars, parsed, logged }`. Side effects: uploads original to `finance-docs` storage bucket at `YYYY-MM/<ts>-<safeName>`; inserts an `expense_entries`/`expenses` row via finance_ingest; inserts a `doc_backups` row (status `pending`).
- **Logic:** (1) Decode base64, sanitize filename, upload bytes to `finance-docs`. (2) POST original to `extract_text` (with `__secret`) to get text. (3) If text > 10 chars and `openrouter_api_key` present, call OpenRouter model `anthropic/claude-sonnet-5` with a strict-JSON prompt to extract a UAE finance entry (`kind` expense/income/subscription, amount in AED incl VAT, vendor, category, description, cycle). (4) If parsed `amount > 0`, attach `source='invoice_upload'`, `doc_path`, `doc_name`, `doc_content_type` and POST to `finance_ingest` `action:log`. (5) Best-effort insert into `doc_backups` (bucket `finance-docs`, dropbox_path `/QuotesDone Backup/Finance/YYYY-MM/<safe>`, dedupe_key `finance-docs:<path>`).
- **Depends on:** Tables `app_secrets`, `doc_backups`; storage bucket `finance-docs`; RPC `fn_role_of`; edge functions `extract_text`, `finance_ingest`; secrets `inbound_secret`, `admin_emails`, `openrouter_api_key`; external OpenRouter API.
- **Notes:** clean.

### finance_ingest
- **Purpose:** Record finance entries (expenses/income/subscriptions), forecast upcoming recurring payments, and run the subscription due-date reminder.
- **Invocation:** Authenticated HTTP (admin JWT), internal server call, or cron (via `__secret`).
- **Auth gate:** `whoami()` — `body.__secret === inbound_secret`, OR Bearer JWT whose email is in `app_secrets.admin_emails`. Returns 403 otherwise.
- **Input:** `{ __secret?, action }` where action ∈ `log|forecast|remind`. `log` takes `entry` (or top-level fields): `kind, amount, vendor, currency, category, description/note, source, cycle, next_due, doc_path/doc_name/doc_content_type`. `forecast` takes `days` (1–120). `remind` takes `reminder_days` (1–30).
- **Output:** JSON per action. Side effects: inserts into `expenses` (subscriptions) or `expense_entries` (one-off expense/income); `remind` inserts a `notifications` row and updates `expenses.last_reminded_at`.
- **Logic:** `doLog`: normalizes amount/vendor/etc. For `subscription` computes `next_due` (explicit or `addCycle(now, cycle)`), dedupes against active `expenses` with same vendor+amount+cadence, else inserts. For expense/income signs the amount (income stored negative), dedupes on `doc_path` in `expense_entries`, else inserts. `doForecast`: lists active `expenses` due within horizon, computes normalized `monthly_recurring_aed` and 30-day one-off spend from `expense_entries`. `doRemind`: rolls past-due subscriptions forward via `addCycle` (guard 60), finds subs due within window not reminded in last 6 days, queues one `notifications` email to `founderEmail()`, stamps `last_reminded_at`.
- **Depends on:** Tables `app_secrets`, `expenses`, `expense_entries`, `notifications`; secrets `inbound_secret`, `admin_emails`, `founder_email`/`email_founder`/`founder_notify_email`.
- **Notes:** clean. Contains H8 OS-audit dedupe fixes (subscription and doc_path duplicates).

### collections_legal
- **Purpose:** Non-response fine lifecycle — sends reminders, and at 30 working days unpaid escalates by applying lawful interest + admin fee, drafting a demand letter and a case-support file (PDFs), backing them to Dropbox, and raising a founder approval card before the demand is sent.
- **Invocation:** Cron / internal call (`__secret`).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** `{ __secret }` (no other params; operates over open supplier dues).
- **Output:** `{ ok, reminded, escalated, results[] }`. Side effects: `notifications` (reminders + founder alert), `supplier_dues` updates (status/legal_stage/amounts/paths), `leads.matching_blocked`, `doc_backups` inserts, `agent_actions` approval card, PDFs in `supplier-docs/legal`.
- **Logic:** Loads `collections_config` (id=1) with defaults `interest_pa 0.09, admin_fee 250, escalate_working_days 30, reminder_max 3`. (1) Reminders: selects `supplier_dues` in due/pending/reminded with null `legal_stage` and `reminders < reminder_max`; skips if reminded within 4 days; inserts a portal `notifications` row (looks up supplier via `leads`), bumps reminders. (2) Escalation: RPC `fn_dues_to_escalate(p_days)` returns overdue rows; computes interest = principal × interest_pa × days_overdue/365, plus admin_fee, plus total; renders demand + case PDFs via `make_pdf` (bucket `supplier-docs`, folder `legal`); updates `supplier_dues` to legal stage with amounts and paths (`fine_amount` deliberately 0 — C1 fix so interest isn't double-billed); sets `leads.matching_blocked`; inserts two `doc_backups`; inserts a high-risk `agent_actions` card (`kind:dues_legal_demand`) and a founder `notifications` alert. Never auto-sends.
- **Depends on:** Tables `app_secrets`, `collections_config`, `supplier_dues`, `leads`, `notifications`, `doc_backups`, `agent_actions`; RPC `fn_dues_to_escalate`; edge function `make_pdf`; storage `supplier-docs`; secrets `inbound_secret`, `admin_emails`.
- **Notes:** clean. UAE-law-specific (Fed. Decree-Law 50/2022 interest cap, Art. 293 moral damages). Explicit "not legal advice" framing; oversight approval required before issue.

### legal_draft
- **Purpose:** AI-drafts a formal UAE legal document (letter of demand, legal notice, final warning, or draft statement of claim) to a defaulting supplier, rendered as a branded PDF.
- **Invocation:** Internal call (`__secret`).
- **Auth gate:** `b.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** `{ __secret, doc_type, pay_days, supplier_id?, company?, breach?, notes?, ... }` plus optional override facts (`commission_principal`, `accrued_charges`, `total_claimed`, `quote_id`, `emirate`, `trade_license_no`, `contact_disclosure_incidents`).
- **Output:** `{ ok, doc_type, title, company, total_claimed, pdf_url, pdf_path, html_path, path, text }`. Side effects: writes an `agent_runs` row; PDF to `finance-reports/legal`; HTML fallback copy to `finance-reports`.
- **Logic:** If `supplier_id`, gathers facts from `leads`, open `supplier_dues` (sums principal/charges/quote value into line items), and counts `chat_violations` (contact-disclosure incidents). Merges any override facts. Calls OpenRouter (`llm` with fallback models `anthropic/claude-sonnet-5` then `anthropic/claude-opus-4.8`) using a detailed UAE in-house-counsel system prompt (cites Electronic Transactions Law 46/2021, 2% commission / 14-day term, 1%/month late charge, AED 250 admin fee under 50/2022, Civil Law 5/1985, AED 10,000 circumvention sum). Converts returned text to HTML, renders a branded PDF via `make_pdf` (options letterhead/sign/stamp), stores an HTML fallback, logs the run.
- **Depends on:** Tables `app_secrets`, `leads`, `supplier_dues`, `chat_violations`, `agent_runs`; storage `finance-reports`; edge function `make_pdf`; secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter API.
- **Notes:** clean. Note: cites a 2% commission / 12% p.a. model, whereas collections_legal uses a no-commission / 9% p.a. model — two distinct legal-drafting paths in the codebase.

### legal_ingest
- **Purpose:** Bulk upsert of legal documents (terms/policies) into the `legal_documents` table.
- **Invocation:** Internal call (`__secret`).
- **Auth gate:** `b.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** `{ __secret, items: [{ slug, title, category, summary, body_html, version }] }`.
- **Output:** `{ ok, upserted, errors[], received }`.
- **Logic:** Iterates `items`; requires slug, title, and `body_html` ≥ 40 chars (else skipped); coerces `category` to `internal` or `public` (default public); upserts into `legal_documents` on conflict `slug` with `body_html` truncated to 60000 chars, `effective_date`/`updated_at` set to today, version default `1.0`.
- **Depends on:** Tables `app_secrets`, `legal_documents`; secret `inbound_secret`.
- **Notes:** clean. Small ingestion utility.

### legal_review
- **Purpose:** AI-assisted review of a contract/NDA/agreement — flags missing or risky clauses against a checklist and produces a plain summary; always marks needs_licensed_review.
- **Invocation:** Internal call (`__secret`).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** `{ __secret, kind, title, text }` or `{ slug }` (loads `legal_documents.body_html`, stripped of tags). Requires ≥ 100 chars text; truncated to 60000.
- **Output:** `{ ok, review_id, model, risk_level, summary, risk_flags[], missing_clauses[], lawyer_questions[], disclaimer }`. Side effects: inserts `legal_reviews`; high-risk inserts `agent_actions`; logs `agent_runs`.
- **Logic:** Builds a contracts-analyst system prompt (checklist incl. UAE PDPL, governing law/jurisdiction) demanding strict JSON. Tries models `anthropic/claude-opus-4.8` then `anthropic/claude-sonnet-5` with `response_format json_object`. Uses a robust `parseJson` that repairs truncated/fenced output (balances braces, closes strings). Inserts a `legal_reviews` row (`needs_licensed_review:true`). If `risk_level==='high'` or any high-severity flag, inserts a high-risk `agent_actions` card (`kind:legal_flag`) for the founder. Logs run counts.
- **Depends on:** Tables `app_secrets`, `legal_documents`, `legal_reviews`, `agent_actions`, `agent_runs`; secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter API.
- **Notes:** clean. Explicit "not legal advice" disclaimer; never self-resolves material risks.

### compliance_archive
- **Purpose:** Generate signed T&C acceptance certificates (PDF), maintain the customer register (XLSX), and mirror both to Dropbox.
- **Invocation:** Authenticated HTTP (admin JWT) or internal (`__secret`). CORS-enabled.
- **Auth gate:** `authed()` — `body.__secret === inbound_secret`, OR Bearer JWT whose email is in `app_secrets.admin_emails`.
- **Input:** `{ __secret?, action }` where action ∈ `ping|sign|register`. `sign` takes `kind` (customer/supplier), `email` or `id`.
- **Output:** JSON per action. Side effects: creates `signed-terms` bucket; renders certificate PDF; updates `customers`/`leads` signed-terms fields; builds `registers/customers-register.xlsx`; Dropbox uploads under `/QuotesDone Backup`.
- **Logic:** `ping` checks Dropbox token. `sign`: loads the customer (`customers`) or supplier (`leads`) record, loads terms text (`supplier_terms_html` secret for suppliers; `pages` slug `legal_terms_body` for customers), computes SHA-256 of the terms, assembles acceptance fields (name, DOB, IP, timestamps in UTC + Dubai GST), renders a branded certificate via `pdf_native` (letterhead/sign/stamp), stores a 10-year signed URL back on the record, downloads the PDF and uploads to Dropbox (`dbxUpload`, refresh-token OAuth), and for customers rebuilds+mirrors the register. `register`: rebuilds the XLSX (`buildRegister` reads all `customers`, embeds 10-year signed URLs to each signed PDF) and mirrors to Dropbox.
- **Depends on:** Tables `app_secrets`, `customers`, `leads`, `pages`; storage bucket `signed-terms`; edge function `pdf_native`; secrets `inbound_secret`, `admin_emails`, `dropbox_app_key`/`dropbox_app_secret`/`dropbox_refresh_token`, `supplier_terms_html`; external Dropbox API; `xlsx` (esm.sh) library.
- **Notes:** clean. Does its own Dropbox OAuth/upload inline (does not use dropbox_backup).

### pdpl_erase
- **Purpose:** Complete an approved PDPL erasure request — delete the subject's uploaded files from storage, then run the DB PII redaction RPC.
- **Invocation:** Internal/admin call (`__secret`). CORS-enabled.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise). Also requires the `pdpl_requests` row status to be `approved` (409 otherwise).
- **Input:** `{ __secret, request_id }`.
- **Output:** `{ ok, subject, files_removed:{...}, db_redaction }`.
- **Logic:** Loads `pdpl_requests` by id, checks status `approved`, resolves the subject email. Gathers supplier KYC docs from `leads` (license/company_profile/egr/iban/catalog paths) + the supplier's `quotes.original_file_path`, and customer drawings from `inquiries` (`drawing_file_path` + `drawing_redacted_paths`). Removes files from buckets `supplier-docs`, `drawing-files`, `quote-files`. Then calls RPC `fn_pdpl_redact(p_request_id)` (which also flips the request to completed and logs a security_event).
- **Depends on:** Tables `app_secrets`, `pdpl_requests`, `leads`, `quotes`, `customers`, `inquiries`; storage buckets `supplier-docs`, `drawing-files`, `quote-files`; RPC `fn_pdpl_redact`; secret `inbound_secret`.
- **Notes:** clean. Note: this deletes Supabase storage + DB PII; Dropbox-side erasure of the same subject is handled separately by `dropbox_backup op:pdpl_erase`.

### pdpl_request
- **Purpose:** Public endpoint for UAE PDPL data export/delete requests; logs the request and notifies the founder.
- **Invocation:** Public HTTP. CORS-enabled.
- **Auth gate:** None (public). Rate-limited: max 3 requests per email in the last 24h (429).
- **Input:** `{ kind: export|delete, email, role?, details? }`.
- **Output:** `{ ok, id, message }` (or validation errors 400/429/500).
- **Logic:** Validates `kind` and email format; checks 24h request count per email; inserts a `pdpl_requests` row (`kind, email, role, details` truncated to 1000). Fires a best-effort `alert_founder` call (with `inbound_secret`, level `action`). Returns a "within 30 days" acknowledgment message.
- **Depends on:** Tables `app_secrets`, `pdpl_requests`; edge function `alert_founder`; secret `inbound_secret`.
- **Notes:** clean. Public intake; the actual erasure is done later by pdpl_erase once approved.

### retention_purge
- **Purpose:** Data-minimisation job — delete transient customer drawing files (originals + redacted) for inquiries concluded more than N months ago, then null their DB paths.
- **Invocation:** Cron (weekly) / internal call (`__secret`).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise, with a descriptive agent_runs error log).
- **Input:** `{ __secret, months? }` (default 6, clamped 1–60).
- **Output:** `{ ok, months, cutoff, inquiries_scanned, files_removed, rows_cleared }`.
- **Logic:** Computes cutoff = now − months×30 days. Selects up to 500 `inquiries` with status completed/closed/cancelled and `created_at < cutoff`. For each with drawings whose `completed_at` is also before cutoff, collects `drawing_file_path` + `drawing_redacted_paths`. Removes the deduped set from bucket `drawing-files`, then nulls those columns on the matching inquiries. Keeps supplier quote files and KYC docs (handled elsewhere). Logs detailed ok/error notes to `agent_runs`.
- **Depends on:** Tables `app_secrets`, `inquiries`, `agent_runs`; storage bucket `drawing-files`; secret `inbound_secret`.
- **Notes:** clean. Heavy defensive logging describing consequences of each failure mode.

### reveal_invoice
- **Purpose:** Generate (or return cached) the customer-facing PDF invoice/receipt for a paid supplier-contact reveal.
- **Invocation:** Authenticated HTTP (customer JWT). CORS-enabled.
- **Auth gate:** Bearer JWT resolved via `admin.auth.getUser`; must map to a `customers` row; the transaction's `customer_id` must equal the caller's customer id (ownership check, 403).
- **Input:** `{ quote_id }` + Authorization Bearer token.
- **Output:** `{ ok, url, invoice_no, cached? }`. Side effects: upserts `reveal_invoices`; PDF via `pdf_native`; logs `agent_runs`.
- **Logic:** Authenticates the customer, loads the paid `transactions` row for `quote_id`, enforces ownership. Returns a cached invoice (signed URL from `reveal_invoices`) if present. Otherwise builds invoice HTML: if `company_trn` secret set it renders a VAT "Tax Invoice" (splits fee into subtotal + 5% VAT); else a plain "Payment Receipt" with a no-VAT note. Renders via `pdf_native` (letterhead/sign/stamp), caches the row in `reveal_invoices`, returns a signed URL. Logs each outcome to `agent_runs`.
- **Depends on:** Tables `customers`, `transactions`, `reveal_invoices`, `inquiries`, `app_secrets`, `agent_runs`; edge function `pdf_native`; secrets `company_trn`, `inbound_secret`; storage (default `agent-docs` bucket).
- **Notes:** clean.

### backup
- **Purpose:** Full nightly logical backup — dumps core DB tables to JSON and inventories every storage bucket, into the `backups` bucket with a manifest.
- **Invocation:** Cron / internal call (`__secret`).
- **Auth gate:** `b.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** `{ __secret }`.
- **Output:** `{ ok, stamp, manifest }` (or `{ error }` with 200 on failure). Side effects: uploads `<YYYY-MM-DD>/<table>.json`, `_storage_<bucket>.json`, `_manifest.json` to bucket `backups`; logs `agent_runs`.
- **Logic:** Ensures `backups` bucket. Paginated `dumpTable` (1000/page, cap 200k) of a fixed `FULL` list (customers, inquiries, quotes, transactions, supplier_dues, reviews, questions, inquiry_matches, agent_knowledge, agent_memory, agent_chats, pricing_config, category_specs, category_agents, content_drafts, expenses, reveal_invoices) plus `leads` with a reduced column subset (no embedding vectors). Recursively lists every bucket except `backups` (capped 20k files / depth 6) writing a per-bucket file inventory. Writes a `_manifest.json` with table counts, per-bucket file/byte totals, and total bytes. Logs run to `agent_runs`.
- **Depends on:** Tables `app_secrets`, `agent_runs`, and all dumped tables; storage bucket `backups` + all other buckets (read); secret `inbound_secret`.
- **Notes:** clean. This is the DB/storage snapshot; the document-level Dropbox mirror is `dropbox_backup`.

### dropbox_backup
- **Purpose:** Organized Dropbox document backup — uploads queued storage files and on-demand generated PDFs into `/QuotesDone Backup`; also performs PDPL file erasure in Dropbox.
- **Invocation:** Cron / internal call (`__secret`).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (throttled error log + 403 otherwise).
- **Input:** `{ __secret, op?, mode?, limit?, request_id? }`. `op` ∈ `selftest|pdpl_erase` (default: queue processing).
- **Output:** JSON per branch (selftest / pdpl_erase counts / backup counts + results). Side effects: Dropbox uploads/deletes; updates `doc_backups`/`pdpl_erase_files`; `security_events` insert; `agent_runs` logs.
- **Logic:** Obtains a Dropbox access token via stored refresh-token OAuth (`dropbox_app_key/secret/refresh_token`). `selftest`: uploads then deletes a probe file. `pdpl_erase`: reads pending `pdpl_erase_files` for a request, deletes each from Dropbox (`delete_v2`, tolerating not_found) and from storage, marks rows erased/error, writes a high-severity `security_events` row. Default: unless `mode:process_only`, calls RPC `fn_enqueue_doc_backups` to enqueue; then processes up to `limit` (≤25) `doc_backups` rows (status pending/error, attempts<5). `generated` rows with no path are first rendered via `renderGenerated` (supplier_details/customer_details/inquiry_summary/comparison — the last via `quote_compare` and stored in `quote_comparisons`) through `make_pdf`. Files are downloaded from storage and uploaded to Dropbox — single upload ≤140MB, chunked upload_session for larger, skip >1GB — then rows marked done. Extensive throttled failure logging.
- **Depends on:** Tables `app_secrets`, `doc_backups`, `pdpl_erase_files`, `security_events`, `agent_runs`, `leads`, `customers`, `inquiries`, `quote_comparisons`; RPCs `fn_enqueue_doc_backups`; edge functions `make_pdf`, `quote_compare`; secrets `inbound_secret`, `dropbox_app_key`, `dropbox_app_secret`, `dropbox_refresh_token`; external Dropbox API.
- **Notes:** clean. Read-only on Supabase storage except the pdpl_erase op.

### dropbox_oauth
- **Purpose:** Self-service HTML page to connect the QuotesDone Dropbox (authorization-code exchange → stores refresh token) plus a diagnostics endpoint.
- **Invocation:** Public HTTP (GET connect page / POST code exchange), gated by a key in the URL/form.
- **Auth gate:** URL/form `k` (or `?diag=`) must equal `app_secrets.dropbox_oauth_key`. No JWT.
- **Input:** GET `?k=<gate>` (connect page) or `?diag=<gate>` (diagnostics); POST form `{ k, code }`.
- **Output:** HTML pages; diagnostics returns JSON. Side effects: updates `app_secrets.dropbox_refresh_token`; triggers a first `dropbox_sync`; enables the cron via RPC.
- **Logic:** GET with valid gate renders a page linking to Dropbox's `oauth2/authorize` (offline access, force_reapprove) and a form to paste the access code. `?diag` refreshes the stored token and reports the token's Dropbox account, root folders, and whether `/QuotesDone Backup` is visible. POST exchanges the `code` for tokens (`authorization_code` grant with `dropbox_app_key`/`dropbox_app_secret`); on success stores the `refresh_token` into `app_secrets`, fires `dropbox_sync` (with `inbound_secret`), and calls RPC `fn_enable_dropbox_sync`, then confirms the linked account.
- **Depends on:** Table `app_secrets`; RPC `fn_enable_dropbox_sync`; edge function `dropbox_sync`; secrets `dropbox_oauth_key`, `dropbox_app_key`, `dropbox_app_secret`, `dropbox_refresh_token`, `inbound_secret`; external Dropbox OAuth API.
- **Notes:** clean.

### dropbox_sync
- **Purpose:** Index specific QuotesDone Dropbox folders into `dropbox_files` (read/index only, never deletes in Dropbox); prunes stale local rows on a complete sync.
- **Invocation:** Cron (daily) / internal call (`__secret`).
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (throttled error log + 403 otherwise).
- **Input:** `{ __secret, paths? }` (paths override the `dropbox_roots` secret).
- **Output:** `{ ok, roots, per_root[], files, folders, upserted, pruned, complete }`.
- **Logic:** Gets a Dropbox access token via refresh-token OAuth. Determines roots from `body.paths`, else JSON in `dropbox_roots` secret, else defaults `['/QuotesDone Backup','/quotes done']`. For each root, recursively `list_folder` (recursive, paginated via cursor, 200-page guard) and upserts each entry into `dropbox_files` on conflict `dropbox_id` (path, name, is_folder, size, content_hash, server_modified, synced_at). Only on a fully complete sync of all roots, deletes `dropbox_files` rows with `synced_at < runStart` (prune). Rich throttled failure logging for root errors, upsert failures, truncation, and empty results.
- **Depends on:** Tables `app_secrets`, `dropbox_files`, `agent_runs`; secrets `inbound_secret`, `dropbox_roots`, `dropbox_app_key`, `dropbox_app_secret`, `dropbox_refresh_token`; external Dropbox API.
- **Notes:** clean. Scoped to QD folders so the shared account's large jewelry/media tree is ignored.

### archive_rfq
- **Purpose:** Archive a COMPLETED RFQ as one atomic case — structured data, copied uploaded files, AI conversations, version history, invoices, audit log, and an AI post-mortem summary.
- **Invocation:** Cron / internal call (`__secret`).
- **Auth gate:** `body.__secret === inbound_secret` (401 with descriptive agent_runs log otherwise).
- **Input:** `{ __secret, inquiry_id?, force? }` (without `inquiry_id`, auto-picks an unarchived inquiry completed > 90 days ago).
- **Output:** `{ ok, rfq_id, archive_path, checksum, files_copied, files_total, ai_conversations, versions, quotes, lessons }`. Side effects: uploads `case.json` + `final_report.md` + copied files under `backups/archives/RFQ-<id>/`; upserts `rfq_archives`; logs `agent_runs`.
- **Logic:** Selects the target inquiry (explicit or the oldest completed/accepted/closed >90d not yet in `rfq_archives`). Gathers customer, `inquiry_matches`, `leads` (suppliers), `quotes`, `messages`, `chat_threads`, `transactions`, `reveal_invoices`, `notifications` (audit), `agent_chats` (by customer identifiers), and `doc_versions` history. Copies the actual uploaded files (drawing original + redacted, quotation files) from their buckets into the archive folder in `backups`. Assembles a 12-section package, generates an AI post-mortem (`aiSummary` via OpenRouter, models sonnet-5 then opus-4.8, strict JSON summary + lessons), writes `case.json` (with SHA-256 checksum) and `final_report.md`, and upserts the searchable `rfq_archives` index row. Accumulates per-step warnings and logs them.
- **Depends on:** Tables `app_secrets`, `inquiries`, `customers`, `inquiry_matches`, `leads`, `quotes`, `messages`, `chat_threads`, `transactions`, `reveal_invoices`, `notifications`, `agent_chats`, `doc_versions`, `rfq_archives`, `agent_runs`; storage buckets `drawing-files`, `quote-files`, `backups`; secrets `inbound_secret`, `openrouter_api_key`; external OpenRouter API.
- **Notes:** clean. Imports supabase-js from esm.sh (others use jsr). Extensive consequence-oriented failure logging.

### stripe_setup
- **Purpose:** Token-gated endpoint for the founder to save LIVE/TEST Stripe keys and check account status (key values never returned or logged).
- **Invocation:** Authenticated HTTP (custom token). CORS-enabled.
- **Auth gate:** `body.token === app_secrets.stripe_setup_token` (403 `bad_token` otherwise). Not a JWT.
- **Input:** `{ token, action? }`; `save` takes `{ sk?, pk?, whsec? }`; `status` takes none.
- **Output:** `{ ok, key_mode, charges_enabled, payouts_enabled, country, default_currency, saved?, warnings? }`.
- **Logic:** Verifies the setup token. `status`: reads stored `stripe_secret_key`, derives mode (LIVE/TEST/none), and queries Stripe `/v1/account` to report charges/payouts/country/currency. `save`: validates key prefixes (`sk_live_`/`sk_test_`, `pk_...`, `whsec_`), warns if a test secret key is supplied, upserts each provided key into `app_secrets` (`stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`), then verifies the now-stored secret key against Stripe `/v1/account`.
- **Depends on:** Table `app_secrets`; secrets `stripe_setup_token`, `stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`; external Stripe API.
- **Notes:** clean.

---

## Documents, Rendering, Extraction, Drawings & Assets

### make_pdf
- **Purpose:** Thin delegator that turns caller HTML (or a fetched URL) into a branded native PDF by forwarding to `pdf_native`, defaulting brand letterhead on.
- **Invocation:** authenticated HTTP (admin) or internal call from another fn (via `__secret`).
- **Auth gate:** `authed()` — passes if `body.__secret === app_secrets.inbound_secret`, else validates `Authorization` Bearer JWT via `admin.auth.getUser` and requires the user email to be in `app_secrets.admin_emails` (comma list).
- **Input:** `{ html?, url?, title?, name?, folder?, bucket?('agent-docs'), lang?('en'), options?, plain?, raw?, __secret? }`. Needs `html` or a fetchable `url` (>=20 chars).
- **Output:** By default JSON proxied from `pdf_native` (`{ok,url,path,bytes}` shape). If `raw:true`, streams the raw `application/pdf` bytes. Side effect: PDF stored by `pdf_native`.
- **Logic:** Reads body; if no `html` but `url` given, fetches URL text. Detects a doc_render letterhead doc via `class="doc-title"` or `qd_lockup_dark` markers. If letterhead, `letterheadFragment()` slices the inner content between `class="doc-meta"` and the `sign`/`ft` blocks and sets `options={letterhead,sign,stamp:true,...}`; otherwise `bodyInner()` strips scripts/styles/head and the first `<h1>` to get body content. Unless `plain` is set, forces `options.letterhead=true`. Builds payload with `__secret=inbound_secret`, `title` (from body or `extractTitle()` from `<title>`/`.doc-title`/`<h1>`), `body_html=frag`, name/folder/bucket/lang/options/raw, POSTs to `${SUPABASE_URL}/functions/v1/pdf_native`, returns its response (or raw bytes).
- **Depends on:** DB table `app_secrets` (keys `inbound_secret`, `admin_emails`); edge function `pdf_native`; `jsr:@supabase/supabase-js@2`. No direct PDF library (delegated).
- **Notes:** clean. Pure delegator (v6) — pdf-lib rendering lives in `pdf_native`.

### make_xlsx
- **Purpose:** Native `.xlsx` generator (SheetJS) from row arrays or multi-sheet definitions; stores the workbook and returns a signed URL.
- **Invocation:** authenticated HTTP (admin) or internal call via `__secret`.
- **Auth gate:** `authed()` — `body.__secret === inbound_secret`, else Bearer JWT user email must be in `admin_emails`.
- **Input:** `{ sheets?:[{name,rows}], rows?, sheet_name?, name?('workbook'), folder?, bucket?('agent-docs'), __secret? }`. Needs `sheets` or `rows`.
- **Output:** `{ ok, bucket, path, url(7-day signed), bytes, sheets }` or error. Side effect: uploads xlsx to storage.
- **Logic:** Normalizes to `sheets` (wraps `rows` as one sheet named `sheet_name||'Sheet1'`). For each sheet builds a worksheet via `XLSX.utils.aoa_to_sheet`, computes per-column widths (min 10, max 60, len+2), sanitizes sheet name (strips `\/?*[]:`, 31-char cap), appends. Writes workbook as array, uploads to bucket at `folder-or-YYYY-MM-DD/<epoch>_<safeName>.xlsx` (upsert), creates a 7-day signed URL.
- **Depends on:** DB `app_secrets` (`inbound_secret`, `admin_emails`); storage bucket `agent-docs` (or caller `bucket`); libs `https://esm.sh/xlsx@0.18.5` (SheetJS), supabase-js.
- **Notes:** clean.

### doc_render
- **Purpose:** Branded document generator — an LLM writes only the body from a brief, which is wrapped in QuotesDone letterhead HTML and also rendered to a native branded PDF via `pdf_native`.
- **Invocation:** authenticated HTTP (admin) or internal via `__secret`.
- **Auth gate:** `authed()` — `body.__secret === inbound_secret`, else Bearer JWT email in `admin_emails`.
- **Input:** `{ title?, layout?|brief?|instruction? (required), lang?('en'|'ar'|'bi'), data?, pdf?, sign?, stamp?, __secret? }`.
- **Output:** `{ ok, title, lang, path, url(7-day signed HTML), pdf_url, pdf_path, bytes }`. Side effects: uploads `.html` to `agent-docs`; PDF created/stored by `pdf_native`.
- **Logic:** Validates lang (en/ar/bi), caps title(160)/layout(4000)/data(8000). Requires `openrouter_api_key`. Adds an Arabic or bilingual language directive. Calls OpenRouter chat completions trying models `anthropic/claude-opus-4.8` then `anthropic/claude-sonnet-5` (max_tokens 9000, temp 0.3) with a strict system prompt (`SYS`) instructing body-only HTML fragment (no doctype/head/letterhead/signature). Strips code fences and any leaked html/head/body/style tags. Determines RTL (Arabic or auto-detected Arabic chars). `wrap()` builds full branded HTML: inline CSS, letterhead header with `qd_lockup_dark.png` logo and hard-coded company block (`CO`: QuotesDone Technologies, DET E-Trader Licence 1633275, Dubai, management@quotesdone.com, +971 50 931 9355), doc title, meta date, body, signature block (`qd_signature.png`, signer Ahmad Alzain, Founder & Managing Director) with inline SVG company stamp, and fixed footer. Uploads HTML to `agent-docs` at `YYYY-MM-DD/<epoch>_<safeTitle>.html` (no upsert), signs 7 days. Unless `pdf===false`, POSTs `{__secret, title, body_html:frag, name, lang, options:{letterhead, sign, stamp}}` to `pdf_native` and returns its `url`/`path`.
- **Depends on:** DB `app_secrets` (`inbound_secret`, `admin_emails`, `openrouter_api_key`); storage buckets `agent-docs` and public `brand` (logo/signature assets served from `/storage/v1/object/public/brand`); edge function `pdf_native`; external OpenRouter API (Claude models); supabase-js.
- **Notes:** clean. Company identity and stamp SVG are hard-coded constants.

### extract_text
- **Purpose:** OCR/parse a PDF or image attachment into clean plain-text/markdown (for the Secretary chat).
- **Invocation:** authenticated HTTP (admin) or internal via `__secret`.
- **Auth gate:** `authed()` — `body.__secret === inbound_secret`, else Bearer JWT email in `admin_emails`.
- **Input:** `{ filename?, mime?, b64 (required), __secret? }`. `b64` may be raw base64 or a `data:` URL.
- **Output:** `{ ok:true, text (<=16000 chars), filename }`, or `{ ok:false, error:'extract_failed', detail }` (still HTTP 200), or 400/500 on missing input.
- **Logic:** Builds a data URL from `b64`+`mime`. Detects images by mime `image/` or filename extension. Requires `openrouter_api_key`. For images sends `{text prompt, image_url}`; for PDFs/other sends `{text prompt, file}` plus `plugins:[{id:'file-parser', pdf:{engine:'pdf-text'}}]`. Prompt (`PROMPT`) demands faithful extraction preserving tables/headings/numbers, no summary. Tries models `anthropic/claude-sonnet-5` then `anthropic/claude-opus-4.8` (max_tokens 4000); returns first non-trivial content, truncated to 16000 chars.
- **Depends on:** DB `app_secrets` (`inbound_secret`, `admin_emails`, `openrouter_api_key`); external OpenRouter API with the `file-parser` PDF plugin; supabase-js. No storage writes.
- **Notes:** clean.

### cad_convert
- **Purpose:** Convert an uploaded DWG/DXF CAD file into rasterized PNG page images via CloudConvert.
- **Invocation:** internal call via `__secret` (POST).
- **Auth gate:** `body.__secret === inbound_secret` (no JWT path).
- **Input:** `{ b64 (required, data-url prefix stripped), filename?('drawing.dwg'), __probe?, __secret? }`.
- **Output:** `{ ok:true, images:[{mime:'image/png', data:<b64>}], pages }` (max 10 pages). On any failure returns `{ ok:false, error:..., detail? }` at HTTP 200 (`no_converter`, `no_file`, `convert_create_failed`, `convert_failed`, `timeout`, `no_output`, `download_failed`, etc.). `__probe` returns job-creation diagnostics.
- **Logic:** Requires `cloudconvert_api_key` (else `no_converter`). Determines `input_format` (dxf else dwg). Creates a CloudConvert job with three tasks: `import/base64`, `convert` to PNG at `pixel_density:200`, `export/url`. Polls the job up to 16 times (3.5s interval, ~56s) checking task statuses; bails on conversion/job error. When export task finishes, downloads up to 10 result files (20s timeout each), base64-encodes each into the `images` array. Uses `AbortController` timeouts on all fetches (`jf`).
- **Depends on:** DB `app_secrets` (`inbound_secret`, `cloudconvert_api_key`); external CloudConvert API v2; supabase-js. No storage writes (returns images inline).
- **Notes:** clean. Errors deliberately returned at HTTP 200 for caller convenience.

### drawing_boq
- **Purpose:** LLM quantity-surveyor that reads construction/fit-out/MEP drawing pages and produces a privacy-scrubbed draft Bill of Quantities JSON for supplier matching.
- **Invocation:** internal call via `__secret` (POST).
- **Auth gate:** `body.__secret === inbound_secret`.
- **Input:** `{ images?:[{b64|data, mime}], file_b64?, mime?, filename?, hint?, __debug?, __secret? }`. Needs `images` or `file_b64`.
- **Output:** `{ ok:true, boq:{ drawing_type, category, summary, scale_detected, total_area_sqm, boq:[{section,description,qty,unit,basis,confidence}], keywords, assumptions, missing_info, confidence } }`. `__debug` returns content length/finish_reason. Errors 400/500/502.
- **Logic:** Requires `openrouter_api_key`. Builds a vision message from up to 10 images (or a single image/file attachment via data URL). System prompt (`SYS`) casts model as a UAE quantity surveyor with strict privacy rules (never emit client/consultant/contractor names, project/plot/makani numbers, contacts, addresses) and demands measurable BOQ line items in a fixed JSON schema with a single `category` from a fixed trade list (`CATS`). Calls OpenRouter with fallback models `anthropic/claude-sonnet-5`→`anthropic/claude-opus-4.8` (max_tokens 8000, temp 0.1, QuotesDone referer/title headers). Parses JSON (with brace-extraction fallback), then defensively normalizes and runs `scrub()` (strips emails and URLs to `[removed]`) over every text field, caps boq to 120 items, keywords 12, assumptions/missing_info 20; coerces numbers and confidence enums.
- **Depends on:** DB `app_secrets` (`inbound_secret`, `openrouter_api_key`); external OpenRouter API (Claude vision + file-parser for PDF attachment); supabase-js. No storage writes.
- **Notes:** clean.

### drawing_redact
- **Purpose:** Detects and blacks out identifying title-block/logo/contact regions on drawing pages so a redacted copy can be shared with competing suppliers.
- **Invocation:** internal call via `__secret` (POST).
- **Auth gate:** `body.__secret === inbound_secret`.
- **Input:** `{ images?:[{b64|data, mime}] (max 8), prefix?, __secret? }`.
- **Output:** `{ ok:true, paths:[storage paths], pages_in, pages_out, skipped }`. Side effect: uploads redacted JPEGs to `drawing-files`.
- **Logic:** Requires `openrouter_api_key`. Sanitizes `prefix` (default `redacted/<epoch>`). Sends up to 8 page images to OpenRouter (fallback models `anthropic/claude-sonnet-5`→`anthropic/claude-opus-4.8`, max_tokens 2000, temp 0) with system prompt (`SYS`) instructing generous detection of identifying regions returned as fractional `{x,y,w,h}` boxes per page (`has_identity`/`regions`). Parses the JSON; **fail-closed**: if a page is flagged `has_identity` but no regions were returned, it is skipped (not shared). For each processable page, decodes via imagescript, downscales to max width 1600, and composites solid black boxes over each region expanded by a 3% margin, then encodes JPEG (q82) and uploads to `drawing-files` at `<prefix>_p<i>.jpg` (upsert). Detection failures / upload errors increment `skipped`.
- **Depends on:** DB `app_secrets` (`inbound_secret`, `openrouter_api_key`); storage bucket `drawing-files`; external OpenRouter API (Claude vision); library `deno.land/x/imagescript@1.2.17`; supabase-js.
- **Notes:** clean. Intentionally fail-closed to avoid leaking un-cleanable pages.

### attach_photos
- **Purpose:** Persists a customer's reference photos into an inquiry package (anonymised via redaction) so matched suppliers can quote from them.
- **Invocation:** authenticated HTTP — customer JWT.
- **Auth gate:** Bearer JWT resolved by `admin.auth.getUser`; requires a signed-in user with an email (401 otherwise). No admin/allow-list check — any authenticated user.
- **Input:** `{ images?:[{data, mime}] (max 24) }` + `Authorization` header.
- **Output:** `{ ok:true, paths:[redacted storage paths] }`.
- **Logic:** Validates JWT user, derives a sanitized `uid` from user id/email. Filters images requiring `data`+`mime` (max 24). Best-effort calls `drawing_redact` (POST with service-role Bearer + `__secret=inbound_secret`, prefix `refphoto/<uid>/<epoch>`) to redact/store; returns the resulting paths (redact-only, no BOQ). Redaction errors are swallowed (returns `paths:[]`).
- **Depends on:** DB `app_secrets` (`inbound_secret`); edge function `drawing_redact` (which writes to `drawing-files`); env `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`; supabase-js.
- **Notes:** clean. Storage writes happen inside `drawing_redact`, not here.

### assets_ingest
- **Purpose:** Makes agents asset-aware by syncing the Dropbox "/QuotesDone Backup/Assets" folder — folding text assets into `agent_knowledge` and writing a compact folder-grouped manifest of binary assets.
- **Invocation:** internal call / cron via `__secret` (POST).
- **Auth gate:** `body.__secret === inbound_secret`.
- **Input:** `{ __secret? }` (no other params).
- **Output:** `{ ok:true, path:'/QuotesDone Backup/Assets', files, folders, text_ingested, folders:{name:count} }`. Side effects: deletes+re-inserts rows in `agent_knowledge`; inserts a run row in `agent_runs`.
- **Logic:** Obtains a Dropbox access token via OAuth refresh-token grant (`dropbox_app_key`/`dropbox_app_secret`/`dropbox_refresh_token`). Ensures the Assets folder exists, then lists it recursively (paged via list_folder/continue, guard 20). Groups files by first folder segment (count/bytes/example filenames, preferring notable names like logo/kit/guide). Downloads text files (md/txt/csv/json/html <200KB) up to 12000 chars each into `textEntries`. Wipes prior asset knowledge (deletes the manifest topic and all `Asset text: %` topics under `agent_key='_global'`). Builds a capped human-readable manifest of folders/examples, inserts it as topic "Company assets (auto-synced from Dropbox)" (priority 60) and inserts each text asset (priority 45). Records an `agent_runs` row (ok/error) with counts.
- **Depends on:** DB tables `app_secrets` (`inbound_secret`, `dropbox_app_key`, `dropbox_app_secret`, `dropbox_refresh_token`), `agent_knowledge`, `agent_runs`; external Dropbox API (oauth2/token, files list/download/create_folder); supabase-js.
- **Notes:** clean (v2). Errors returned at HTTP 200 and logged to `agent_runs`.

### asset_delete
- **Purpose:** Secret-gated removal of storage paths from an allow-listed set of buckets (test/demo cleanup).
- **Invocation:** internal call via `__secret` (POST).
- **Auth gate:** `body.__secret === inbound_secret`.
- **Input:** `{ bucket (required, must be allow-listed), paths?:[string], prefix?, __secret? }`.
- **Output:** `{ ok:true, removed, paths }`, or error (`forbidden`/`bucket_not_allowed`/`no paths`).
- **Logic:** Validates secret and that `bucket` is in `ALLOW = ['quote-files','supplier-docs','drawing-files','agent-docs','brand']`. Collects `paths`; if `prefix` given, lists up to 1000 objects under it and appends `prefix/name` for each. Dedupes/filters, then `storage.remove(paths)`. Returns count removed.
- **Depends on:** DB `app_secrets` (`inbound_secret`); storage buckets in the allow-list; supabase-js.
- **Notes:** clean. Minimal utility.

### stripe_setup_page
- **Purpose:** Serves a private, no-index HTML form for pasting Stripe live keys; the form posts them to the token-gated `stripe_setup` function.
- **Invocation:** public HTTP GET (serves static HTML to anyone).
- **Auth gate:** None on the page itself (public). Security relies on the `?t=YOUR_TOKEN` token the browser forwards to `stripe_setup`, plus a hard-coded anon key used only for the fetch.
- **Input:** none server-side; the page reads `?t=` from the URL and form fields (sk_live_, pk_live_, whsec_) client-side.
- **Output:** `text/html` page. No server-side side effects; the browser POSTs `{token, action:'save'|'status', sk, pk, whsec}` to `stripe_setup`.
- **Logic:** `Deno.serve` returns a static HTML string. Embedded JS: `tok()` reads `?t`, `call()` POSTs to the hard-coded `stripe_setup` function URL with the anon key as Authorization/apikey plus `{token}`; Save sends the three key fields, Check status sends `action:'status'`; `show()` renders results (saved keys, warnings, key_mode, charges/payouts enabled, country/currency).
- **Depends on:** edge function `stripe_setup` (does the actual token-gated save/status). Hard-codes the project's anon JWT and the `stripe_setup` URL. No DB/storage/secrets access in this function.
- **Notes:** clean. Contains a hard-coded public anon key and project ref (`htdblwldjkcgjvmqkbeh`) — expected for a public form, not a real secret.

---

## Marketing, Social, SEO & i18n

### meta_ads
- **Purpose:** Platform connector for Meta (Facebook/Instagram) ad campaigns that can read the ad account, list campaigns, pull insights, and create PAUSED campaigns/ad sets (never activates spend).
- **Invocation:** Authenticated HTTP (agent/tool call). No verify_jwt comment in file.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403 forbidden).
- **Input:** JSON body `{ __secret, action }`. Actions: `test` (default), `list`, `insights` (`days` 1-90), `quick_campaign` (`name`, `objective` ∈ OUTCOME_TRAFFIC/LEADS/ENGAGEMENT/AWARENESS/SALES, `daily_budget_aed` floor 20, `countries[]` default `['AE']`).
- **Output:** JSON per action. `test` → account fields; `list` → campaigns; `insights` → account-level metrics; `quick_campaign` → `{ campaign_id, adset_id, status:'PAUSED', note, ... }`. Side effect: writes an `agent_runs` row on quick_campaign and on errors.
- **Logic:** Loads `meta_access_token`, `meta_ad_account_id`, `meta_api_version` (default v21.0). Returns `meta_not_configured` if token/account missing. Normalizes account to `act_<id>`. Builds Graph API base `https://graph.facebook.com/<ver>`. `test`: GET account fields. `list`: GET `/campaigns` (limit 25). `insights`: GET `/insights` with date_preset chosen from days. `quick_campaign`: (1) POST a PAUSED campaign with `special_ad_categories:[]`; if it fails, logs agent_runs error and returns; (2) POST a PAUSED ad set — daily_budget in fils (AED*100), billing_event IMPRESSIONS, optimization_goal REACH for AWARENESS else LINK_CLICKS, bid_strategy LOWEST_COST_WITHOUT_CAP, targeting geo countries + age 18-65; logs agent_runs. All objects created PAUSED — activation is a manual human step in Ads Manager.
- **Depends on:** DB tables `app_secrets`, `agent_runs`; app_secrets keys `inbound_secret`, `meta_access_token`, `meta_ad_account_id`, `meta_api_version` (optional), `meta_page_id` (optional, mentioned in header only); external Meta Graph API. Uses `jsr:@supabase/supabase-js@2`.
- **Notes:** clean. Safety-by-design: only ever creates PAUSED objects, never spends.

### meta_sync
- **Purpose:** Pulls QuotesDone Meta campaign insights into `public.meta_insights`, filtered to campaigns whose name contains a configured filter so the founder's unrelated DJ campaigns are excluded.
- **Invocation:** Authenticated HTTP / cron-style sync. No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else logs error + 403).
- **Input:** JSON body `{ __secret }`. No other params.
- **Output:** JSON `{ ok, campaigns, upserts, sample }` (or `{ disabled:true }` / error). Side effects: upserts rows into `meta_insights` (2 per campaign: last_30d + maximum), writes `agent_runs` log rows.
- **Logic:** Loads `meta_access_token`, `meta_ad_account_id`, `meta_campaign_filter` (default 'QuotesDone'). Returns `{disabled:true}` if token or account missing. GETs `/<act>/campaigns` from Graph v21.0 with a server-side name-CONTAIN filter, then re-filters client-side (case-insensitive) on the filter string. For each matched campaign, for each date_preset in `['last_30d','maximum']`: GET `/insights` (spend, impressions, clicks, reach, ctr, cpc, actions); builds a record and upserts into `meta_insights` on conflict `campaign_id,time_window`. `resultsFrom()` derives a `results` count from the actions array based on objective (lead / link_click / post_engagement / video_view / clicks fallback). Tracks INSIGHT_ERRORS, EMPTY_INSIGHTS, UPSERT_FAILS and composes a detailed health note; run status is `error` if any upsert failed, any insight errored, or zero campaigns matched.
- **Depends on:** DB tables `app_secrets`, `meta_insights`, `agent_runs`; app_secrets keys `inbound_secret`, `meta_access_token` (ads_read), `meta_ad_account_id`, `meta_campaign_filter` (optional); external Meta Graph API. Currency hardcoded 'AED'. Does NOT post to the GL.
- **Notes:** clean. Zero-filled rows on insight failure are noted as a known caveat (silently understates spend).

### postiz_publish
- **Purpose:** Platform's own Postiz connector so agents can publish/schedule/draft social posts and manage channels server-side.
- **Invocation:** Authenticated HTTP (called by agents and by social_stage). No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret, action }`. Actions: `test`; `post` `{ channels:[names], text, title?, type?:'now'|'schedule'|'draft', when?:ISO, image?:[{id,path}] }`; `delete` `{ ids[] | id }`.
- **Output:** JSON. `test` → `{ ok, integrations[] }`; `post` → `{ ok, type, published_to, post_id, skipped, result }` or error with skipped list; `delete` → `{ ok, deleted[] }`. Side effect: writes `agent_runs` on post.
- **Logic:** Loads `postiz_api_key`; base URL from `postiz_api_url` (default `https://api.postiz.com/public/v1`). Returns `postiz_not_configured` if no key. `test`: GET `/integrations`, returns id/name/identifier/disabled. `post`: validates non-empty text; type default 'now'; date defaults to now+60s; resolves requested channel names against the LIVE integration list (filtering out disabled), matching normalized names (twitter→x, linkedin*, instagram*, facebook) to real identifiers; skips channels not connected. Instagram (and NEEDS_MEDIA set) require an image or are skipped. Builds per-channel `settings.__type` (+ instagram post_type='post', x who_can_reply_post='everyone'), POSTs `{ type, date, shortLink:false, tags:[], posts[] }` to `/posts`, parses postId from several shapes. `delete`: DELETEs each id.
- **Depends on:** DB tables `app_secrets`, `agent_runs`; app_secrets keys `inbound_secret`, `postiz_api_key`, `postiz_api_url` (optional); external Postiz API.
- **Notes:** clean.

### social_stage
- **Purpose:** Hourly-style pipeline step that reads pending social content drafts and hands them to postiz_publish as drafts, then marks them staged.
- **Invocation:** Cron/internal (no request body used beyond auth header). Calls postiz_publish internally.
- **Auth gate:** `x-internal-key` header must equal `app_secrets.postiz_publish_key` (else 401). If the secret is missing, all calls fail (logged).
- **Input:** HTTP request with `x-internal-key` header. No body params consumed.
- **Output:** JSON `{ ok, staged, results }` (or paused/no-drafts messages). Side effects: calls postiz_publish per draft; PATCHes `content_drafts` (staged_at, status='staged'); writes `agent_runs` logs (throttled for repeated signals).
- **Logic:** Validates `x-internal-key` against `postiz_publish_key`. GO-LIVE GATE: reads `marketing_golive`; if not 'true', returns `{ paused:true }` without work (idle, not logged). Otherwise loads `default_post_image`, selects up to 10 `content_drafts` where `channel=social AND staged_at IS NULL` ordered by created_at asc. For each draft, content = body (trimmed) or title; empty drafts skipped. Fetches `inbound_secret` and POSTs to `/functions/v1/postiz_publish` with `{ __secret, action:'post', text, channels:['instagram','linkedin','x','facebook'], type:'draft', image }`. On success, PATCHes the draft to staged. Composes health notes for failed publishes (kept pending, retried), patch failures (risk of duplicate posts), and empty drafts; logs to agent_runs. Uses direct PostgREST/REST fetches (not the JS client). `logThrottled` suppresses duplicate signal logs within a window.
- **Depends on:** DB tables `app_secrets`, `content_drafts`, `agent_runs`; app_secrets keys `postiz_publish_key`, `marketing_golive`, `default_post_image`, `inbound_secret`; edge function `postiz_publish`. Uses `jsr:@supabase/functions-js/edge-runtime.d.ts`.
- **Notes:** clean. Header comment (H13) documents a past bug where it sent the wrong contract to postiz_publish (x-internal-key + {content,mode,image_url}), silently 403ing the whole social pipeline; now aligned to postiz_publish's `__secret`/`{action,text,type,image}` contract.

### seo_gen
- **Purpose:** AI-generates intro/includes/faqs content for ungenerated `seo_categories` rows in a concurrent batch.
- **Invocation:** Authenticated HTTP. No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret }`. No other params.
- **Output:** JSON `{ ok, done, remaining }` (or `{finished:true, done:0}` when none left, `no_ai` if no key). Side effect: updates `seo_categories` rows.
- **Logic:** Loads `openrouter_api_key` (returns `no_ai` if absent). Selects up to 20 `seo_categories` where `generated=false`, ordered by `sort`. For each, `genOne()` calls OpenRouter chat completions (model `anthropic/claude-sonnet-4.6`, max_tokens 1200, temp 0.4) with a UAE home-services SEO system prompt demanding STRICT JSON `{intro (~110-140 words), includes[6], faqs[3]}`. Robust JSON parse (extracts first `{...}` block on failure). On a valid parse with intro, updates the row (intro capped 2000 chars, includes ≤8, faqs ≤5, `generated=true`, updated_at). Runs all rows via `Promise.all`; counts successes; returns remaining ungenerated count.
- **Depends on:** DB tables `app_secrets`, `seo_categories`; app_secrets keys `inbound_secret`, `openrouter_api_key`; external OpenRouter (Anthropic Claude Sonnet 4.6).
- **Notes:** clean. Does not write agent_runs.

### blog_weekly
- **Purpose:** Autonomous weekly SEO blog engine — generates one fresh long-tail post from the marketing brain, avoids duplicate topics, publishes to blog_posts (or drafts), and files a review task.
- **Invocation:** Authenticated HTTP / weekly cron. No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret, publish?:bool=true, topic? }` (topic is accepted in header contract but not read in code).
- **Output:** JSON `{ ok, published, id, slug, title, keyword, url }` (or `generation_failed`/error). Side effects: inserts a `blog_posts` row, a `crm_tasks` review task, and an `agent_runs` log.
- **Logic:** Fetches last 40 blog titles to avoid duplicates. Loads marketing brand context via RPC `fn_agent_context('marketing', 5000)`. `llmJSON()` calls OpenRouter trying models `anthropic/claude-sonnet-5` then `anthropic/claude-opus-4.8` (max_tokens 3500, temp 0.6), strips code fences, extracts `{...}`, returns parsed JSON. System prompt describes QuotesDone as a UAE B2B anonymous quotation marketplace (3% reveal fee); user prompt demands ONE 700-1000 word HTML article with h2/h3/FAQ, 2 internal links, returning minified JSON `{title, meta_desc, excerpt, category, keyword, body_html}` (no h1). Builds slug via slugify (dedupes with a timestamp suffix if slug exists), computes next `sort`, inserts the post (published flag from `publish`, published_at set when publishing, body capped 40000 chars). Inserts a low-priority `crm_tasks` review task (source `agent:marketing`) and an agent_runs 'ok' row.
- **Depends on:** DB tables `app_secrets`, `blog_posts`, `crm_tasks`, `agent_runs`; RPC `fn_agent_context`; app_secrets keys `inbound_secret`, `openrouter_api_key`; external OpenRouter (Claude Sonnet 5 / Opus 4.8).
- **Notes:** clean. `topic` param in the header comment is not actually consumed.

### translate_html
- **Purpose:** One-shot English→Arabic translation of an HTML fragment, preserving all tags/attributes/structure.
- **Invocation:** Authenticated HTTP (internal translation helper). No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret, html, model? }`.
- **Output:** JSON `{ ok, ar, model, usage }` (or error). No DB writes.
- **Logic:** Loads `openrouter_api_key` (500 `no_key` if absent). Requires `html` (400 `no_html`). Builds a model list `[model||'anthropic/claude-sonnet-5', 'openai/gpt-4o', 'openai/gpt-4o-mini']` (deduped) and sends OpenRouter chat completion with `models` (multi-model fallback), temp 0.2, max_tokens 8000, and a strict MSA-translation system prompt (preserve tags/attrs, don't translate brand/URLs/emails/numbers/AED, translate placeholder/title/aria-label/alt values). On non-OK returns `llm_failed`. Strips code fences from output and returns the Arabic HTML.
- **Depends on:** DB table `app_secrets`; app_secrets keys `inbound_secret`, `openrouter_api_key`; external OpenRouter (Claude Sonnet 5 / GPT-4o fallbacks).
- **Notes:** clean.

### translate_page
- **Purpose:** Chunked English→Arabic translation of a stored page's HTML, persisting per-chunk results and assembling a completed translation when all chunks are done.
- **Invocation:** Authenticated HTTP; designed for repeated/incremental calls (uses EdgeRuntime.waitUntil for background work). No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret, source, slug, model?='openai/gpt-4o-mini', limit?=5 (max 8) }`.
- **Output:** JSON `{ ok, source, slug, total, have, missing }`. Side effects: upserts `qd_i18n_chunks` rows and, when complete, a `qd_i18n` row.
- **Logic:** Loads `openrouter_api_key`. Reads source JSON from `qd_deploy_src` at path `src/content/<source>.json`, parses it, selects entry `data[slug]` (`{ html, title }`). Splits html into ~4500-char chunks on tag boundaries. Reads existing translated chunk indices from `qd_i18n_chunks`, computes missing set. `work()`: translates up to `limit` missing chunks via OpenRouter (temp 0.2, max_tokens 8000, MSA prompt that also preserves `{{...}}` placeholder tokens), upserting each into `qd_i18n_chunks`. After translating, if all chunks now exist, concatenates them in index order, translates the title (via gpt-4o-mini, stripping h1), and upserts the assembled `qd_i18n` row with `status='done'`. Runs `work()` in background via `EdgeRuntime.waitUntil` when available, else awaits inline.
- **Depends on:** DB tables `app_secrets`, `qd_deploy_src`, `qd_i18n_chunks`, `qd_i18n`; app_secrets keys `inbound_secret`, `openrouter_api_key`; external OpenRouter (default GPT-4o-mini).
- **Notes:** clean. Complements i18n_get (reader) and translate_html (single-fragment variant).

### i18n_get
- **Purpose:** Reads assembled Arabic translations back out of `qd_i18n`.
- **Invocation:** Authenticated HTTP (internal read). No verify_jwt comment.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (else 403).
- **Input:** JSON body `{ __secret, source?, slug? }` (optional filters).
- **Output:** JSON `{ ok, rows:[{ source, slug, title, html, status }] }`.
- **Logic:** Validates secret, selects `source,slug,title,html,status` from `qd_i18n`, optionally filtered by `source` and/or `slug`, returns the rows.
- **Depends on:** DB tables `app_secrets`, `qd_i18n`; app_secrets key `inbound_secret`.
- **Notes:** clean. Tiny reader companion to translate_page.

### home-ar
- **Purpose:** Serves the pre-rendered Arabic homepage HTML.
- **Invocation:** Public HTTP GET (no auth, no body).
- **Auth gate:** None / public.
- **Input:** None (ignores request).
- **Output:** Raw HTML (text/html; charset=utf-8, Cache-Control: no-store), or the literal string `Not found` if the row is absent.
- **Logic:** Selects `html` from `pages` where `slug='home-ar'` and returns it directly as an HTML response.
- **Depends on:** DB table `pages`. No secrets, no external APIs.
- **Notes:** clean. Minimal public page-server stub.

---

## Auth, QA, Dev & Deploy Infrastructure

### auth_api
- **Purpose:** Public email/password auth backend for customer and supplier signup, email verification, password reset, and Twilio SMS phone verification.
- **Invocation:** Public HTTP (unauthenticated; CORS `*`). Callers pass no JWT — actions are dispatched by `body.action`.
- **Auth gate:** None — fully public by design (it *is* the auth surface). Rate-limited per email/phone (≥6 email tokens/hr → 429; ≥5 SMS/hr → 429). Does its own input validation.
- **Input:** JSON `{ action, ... }`. Actions: `signup_customer` / `signup_supplier` (email, password, full_name, phone, dob, accept_terms, company_name for supplier), `verify_email` (token), `resend_verification` (email, user_kind), `forgot_password` (email, user_kind), `reset_password` (token, password), `sms_send` (email, phone, user_kind), `sms_verify` (email, phone, code, user_kind).
- **Output:** JSON `{ ok, ... }` or `{ error }`. Side effects: creates Supabase auth users (`email_confirm:true`), upserts `customers` or `leads` rows, inserts `email_verifications` / `phone_verifications` tokens, sends Resend emails, calls Twilio Verify, sets `email_verified`/`owner_email_verified`/`phone_verified`, on supplier signup sets `registration_status` (free vs due) from `pricing_config`.
- **Logic:** Signup validates email/password(≥8)/name/phone/DOB(18–120)/terms; rejects if a verified account already exists (customers.email_verified or leads.owner_email_verified). Creates auth user only if none exists — **explicitly refuses to touch an existing auth user** (see Notes). Writes profile row with TOS version (v3 customer / v4 supplier), IP, timestamp; for new suppliers computes free-tier vs paid registration fee via `registered_supplier_count` RPC. Issues a signup token, emails a confirm link (`/app` or `/suppliers?verify=`). `verify_email` marks token used and flips the verified flag. `forgot_password` always returns generic success but only emails if uid exists (1hr reset token). `reset_password` validates token, calls `admin.auth.admin.updateUserById` to set the new password. SMS actions gated by `sms_enabled` secret; use Twilio Verify service (send + check), skip silently if disabled.
- **Depends on:** Tables `app_secrets`, `customers`, `leads`, `email_verifications`, `phone_verifications`, `pricing_config`. RPCs `auth_uid_by_email`, `registered_supplier_count`. Edge fn `compliance_archive` (best-effort sign archive — helper `archiveSign` is defined but not called in current actions). app_secrets keys: `inbound_secret`, `resend_api_key`, `email_from_supplier`, `email_from_info`, `email_reply_info`, `public_site_url`, `sms_enabled`, `twilio_api_key_sid`, `twilio_api_key_secret`, `twilio_verify_service_sid`. External APIs: Resend, Twilio Verify.
- **Notes:** SECURITY-SENSITIVE (positive): contains an in-code documented fix (18 Jul 2026) — the signup "existing uid" branch previously overwrote passwords of existing accounts (account-takeover incl. admins); it now hard-returns 409 instead. `archiveSign` helper is currently dead code (defined, never invoked).

### dev_login
- **Purpose:** Former temporary QA login helper.
- **Invocation:** Public HTTP.
- **Auth gate:** None reachable — always returns 410.
- **Input:** Ignored.
- **Output:** `{ error: 'disabled' }` HTTP 410.
- **Logic:** Single line: returns disabled for every request.
- **Depends on:** Nothing.
- **Notes:** DEAD/DISABLED stub — permanently turned off (comment: "temporary QA helper and is permanently turned off"). Was an auth-bypass surface; now inert.

### qa_api
- **Purpose:** Anonymized pre-reveal Q&A between a customer and a supplier about a quote, with contact details stripped both directions.
- **Invocation:** Authenticated HTTP (Supabase JWT in Authorization header).
- **Auth gate:** JWT → `admin.auth.getUser(jwt)` → email; must be non-empty. Role derived by looking up `leads.claimed_by` (supplier) and `customers.email` (customer). Per-action role checks (customer-only vs supplier-only).
- **Input:** JSON `{ action, ... }`. `ask` (quote_id, question), `list` (quote_id), `inbox`, `answer` (id, answer).
- **Output:** JSON `{ ok, ... }`. Side effects: inserts `questions` rows, updates answers, inserts `notifications`.
- **Logic:** `ask` (customer): loads quote → inquiry (must belong to caller); blocks if a `transactions` row already exists for that supplier (already revealed → use Messages); caps at 3 pre-reveal questions per supplier/inquiry (else 429); strips contact info, inserts question, notifies the supplier's `claimed_by`. `list` (customer): returns that customer's Q&A thread for the quote. `inbox` (supplier): last 50 questions for the supplier with inquiry summary/emirate joined, plus pending count. `answer` (supplier): validates question ownership, strips contact info, sets answer + answered_at, notifies the customer.
- **Depends on:** Tables `leads`, `customers`, `quotes`, `inquiries`, `transactions`, `questions`, `notifications`. No app_secrets, no external APIs. Uses inline `stripContact()` regex scrubber (emails, links, phone numbers, whatsapp/telegram/instagram/etc.).
- **Notes:** Clean. Uses no `_shared` helpers (self-contained).

### qa_login
- **Purpose:** Former temporary QA session minter.
- **Invocation:** Public HTTP.
- **Auth gate:** None reachable — always returns 410.
- **Input:** Ignored.
- **Output:** `{ error: 'disabled' }` HTTP 410.
- **Logic:** Returns disabled for every request.
- **Depends on:** Nothing.
- **Notes:** DEAD/DISABLED stub — "permanently turned off after the launch-readiness audit." Was an auth-bypass surface; now inert.

### qa_mint
- **Purpose:** Creates a confirmed Supabase auth user with an arbitrary email/password (test-account primitive).
- **Invocation:** Internal/secret-guarded HTTP.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise) AND a second kill-switch: `app_secrets.qa_mint_enabled` must equal `'true'` (else 403, disabled).
- **Input:** JSON `{ __secret, email, password }` (password ≥8).
- **Output:** `{ ok:true, user_id }` or error. Side effect: creates a confirmed auth user.
- **Logic:** Verifies secret, verifies `qa_mint_enabled` flag, validates email + password length, calls `admin.auth.admin.createUser({ email, password, email_confirm:true })`.
- **Depends on:** Table `app_secrets` (keys `inbound_secret`, `qa_mint_enabled`). Supabase Admin auth API. No external APIs.
- **Notes:** SECURITY-SENSITIVE — in-code comment (M13 OS audit) flags this as "a standing account-creation primitive"; must stay OFF in production (default disabled unless `qa_mint_enabled=true`). Live but gated code, not a stub.

### qa_suite
- **Purpose:** Automated QA/security regression suite: probes RLS to ensure sensitive tables are not anon-readable, runs a positive control, checks payment/data invariants via `fn_smoke`, persists results and alerts on failure.
- **Invocation:** Authenticated/internal HTTP (intended as a scheduled/cron QA run); guarded by an internal key header.
- **Auth gate:** `x-internal-key` header must equal `app_secrets.postiz_publish_key` (reused as the guard secret); mismatch or missing guard → 401.
- **Input:** None meaningful (header `x-internal-key` only).
- **Output:** JSON `{ passed, total, failed, failing }`. Side effects: inserts `qa_results` row, inserts `agent_runs` log row, sends failure alert email via Resend to management@quotesdone.com.
- **Logic:** Loads `anon_key` secret. For each sensitive table (customers, app_secrets, leads, transactions, quotes, inquiries, messages, agent_knowledge, email_suppression, social_posts, qa_results, customer_phone_otps, inbound_messages) probes REST with the anon key — flags a LEAK if any rows return. Positive control: `category_specs` should be reachable (proves anon key valid). Calls `rpc/fn_smoke` for payment/data-integrity invariants (best-effort). Aggregates pass/fail, records inconclusive probes (counted as passing — noted as a blind spot), stores `qa_results`, emails alert if failing, and always logs a detailed `agent_runs` note. Never lets logging break the run.
- **Depends on:** REST tables `app_secrets`, `agent_runs`, `qa_results`, `category_specs`, plus all probed sensitive tables. RPC `fn_smoke`. app_secrets keys: `postiz_publish_key` (auth guard), `anon_key`, `resend_api_key`. External API: Resend. Uses raw `fetch` against Supabase REST (no supabase-js client).
- **Notes:** Clean but note two caveats baked into the code: the auth guard secret is `postiz_publish_key` (semantically odd — reused key); inconclusive probes are scored as PASS, so a real RLS leak on an errored probe could be hidden.

### deploy_next_preview
- **Purpose:** Deploys the `quotesdone-next` Next.js app to Vercel (production or preview) from source rows stored in the DB.
- **Invocation:** Internal/secret-guarded HTTP.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** JSON `{ __secret, target }` where target `'preview'` else defaults to `'production'`.
- **Output:** `{ ok:true, id, url, target, readyState, files, alias }` or error object (returned as HTTP 200 with `ok:false` for config/upload/deploy failures).
- **Logic:** Loads `vercel_token` + `vercel_team_id`. PATCHes the `quotesdone-next` project to disable deployment protection (ssoProtection/passwordProtection null). Reads all rows from `qd_deploy_src` (path,data), SHA-1 hashes each, uploads bytes to Vercel `/v2/files`, then creates a deployment via `/v13/deployments?forceNew=1` with `projectSettings.framework:'nextjs'` and the chosen target.
- **Depends on:** Table `qd_deploy_src`, `app_secrets` keys `inbound_secret`, `vercel_token`, `vercel_team_id`. External API: Vercel (v9 projects PATCH, v2 files, v13 deployments). Project name hardcoded `quotesdone-next`.
- **Notes:** Clean. Source content comes from `qd_deploy_src`, populated by `put_src`.

### site_deploy
- **Purpose:** Renders the full marketing/SEO site (home, app, Arabic, legal, contact, programmatic services×emirates pages, blog, sitemap/robots/llms.txt) and pushes a PRODUCTION deployment to Vercel (project `qd-site`).
- **Invocation:** Internal/secret-guarded HTTP.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** JSON `{ __secret }`.
- **Output:** `{ ok:true, deployment_id, url, readyState, files }` or `{ ok:false, error }` (HTTP 200). Side effect: a production Vercel deployment of the whole static site.
- **Logic:** Loads i18n chrome from brand storage. Fetches each MAIN page HTML from sibling edge functions (`/home`, `/home-ar`, `/app`, `/app-ar`, `/portal`, `/faq`, `/about`, `/legal?doc=...`). Appends `llms.txt` and a self-generated contact page. Reads `seo_categories` (generated=true) and `blog_posts` (published=true); generates a services hub, per-category and per-category×emirate SEO pages (7 emirates), blog hub + per-post pages (all styled via inline CSS, JSON-LD schema, procedurally generated SVG cover art), plus sitemap.xml and robots.txt. Uploads all files to Vercel `/v2/files` in chunks of 16 (SHA-1 digest), then creates a production deployment via `/v13/deployments?forceNew=1` with `framework:null`.
- **Depends on:** Tables `app_secrets`, `seo_categories`, `blog_posts`. Edge fns (fetched for HTML): `home`, `home-ar`, `app`, `app-ar`, `portal`, `faq`, `about`, `legal`; contact page form posts to `contact_submit`. app_secrets keys: `inbound_secret`, `vercel_token`, `vercel_team_id`, `vercel_project` (default `qd-site`). External API: Vercel. Brand assets from Supabase storage `/public/brand`.
- **Notes:** Clean. Contact page embeds a hardcoded anon JWT (`AK`) for the public `contact_submit` call — an anon key, expected to be public. Large template file but single-purpose.

### put_src
- **Purpose:** Writes/updates a single source file into the `qd_deploy_src` table (feeds `deploy_next_preview`).
- **Invocation:** Internal/secret-guarded HTTP.
- **Auth gate:** `body.__secret === app_secrets.inbound_secret` (403 otherwise).
- **Input:** JSON `{ __secret, path, data }` (data must be a string).
- **Output:** `{ ok:true, bytes }` or `{ error }`.
- **Logic:** Verifies secret, validates path + string data, upserts `{ path, data }` into `qd_deploy_src`.
- **Depends on:** Tables `qd_deploy_src`, `app_secrets` (key `inbound_secret`). No external APIs.
- **Notes:** Clean. Tiny writer that pairs with `deploy_next_preview`.

### src_io
- **Purpose:** Former source-file I/O endpoint.
- **Invocation:** Public HTTP.
- **Auth gate:** None reachable — always returns 410.
- **Input:** Ignored.
- **Output:** Plain text `gone`, HTTP 410.
- **Logic:** One line: returns 410 for every request.
- **Depends on:** Nothing.
- **Notes:** DEAD/DISABLED stub. Superseded by `put_src` / `deploy_next_preview`.

### project_api
- **Purpose:** Customer-facing Procurement Projects — group multiple RFQs (inquiries) under a project, plus a procurement dashboard.
- **Invocation:** Authenticated HTTP (customer Supabase JWT).
- **Auth gate:** `customer()` helper: JWT → `admin.auth.getUser` → email → `customers` row; rejects if missing or `banned` (401).
- **Input:** JSON `{ action, ... }`. Actions: `list`, `dashboard`, `create` (name, description, target_open_date, budget_total), `update` (id, name/description/status/target_open_date/budget_total), `detail` (id), `link`/`unlink` (inquiry_id, project_id).
- **Output:** JSON `{ ok, projects|project|dashboard|rfqs }`. Side effects: inserts/updates `projects` rows, sets `inquiries.project_id` on link/unlink.
- **Logic:** `list` returns `project_summary` rows for the customer. `dashboard` aggregates the customer's inquiries + transactions + project summaries into metrics: total/active RFQs, RFQs by status, reveals, fees paid (sum reveal_fee), distinct suppliers engaged, awarded count, avg first-response hours (first quote time minus inquiry created, best-effort), avg savings % (quote spread per RFQ with ≥2 quotes), and recent 12. `create`/`update` write to `projects` (ownership-scoped, status limited to active/completed/archived). `detail` returns the project plus its inquiries. `link`/`unlink` verify both the inquiry and target project belong to the customer, then set/clear `inquiries.project_id`.
- **Depends on:** Tables/views `customers`, `projects`, `project_summary` (view), `inquiries`, `transactions`, `quotes`. No app_secrets, no external APIs, no RPCs. Same auth model as `customer_api`.
- **Notes:** Clean. Self-contained (no `_shared` imports).

---

## Appendix A — Cron schedule → edge function

All schedules are **UTC** (Dubai = UTC+4). Only crons that drive an edge function in *this* reference are listed; ~60 further `pg_cron` jobs call SQL `fn_*` agents (the OS database layer, out of scope here).

### Direct HTTP crons

| Cron job | Schedule (UTC) | Edge function |
|---|---|---|
| `agent_autogen_daily` | `35 2 * * *` | agent_autogen |
| `agent_learnings_weekly` | `0 6 * * 1` | agent_learnings_report |
| `agent_reflect_weekly` | `0 2 * * 0` | reflect |
| `ai_health_15min` | `7,22,37,52 * * * *` | ai_health |
| `archive_completed_daily` | `20 4 * * *` (×5 loop) | archive_rfq |
| `assets_ingest_6h` | `15 */6 * * *` | assets_ingest |
| `backup_daily` | `30 3 * * *` | backup |
| `blog_weekly_mon` | `30 6 * * 1` | blog_weekly |
| `collections_legal_daily` | `15 6 * * *` | collections_legal |
| `cost_snapshot_weekly` | `0 7 * * 1` | cost_snapshot |
| `dr_drill_monthly` | `50 3 1 * *` | dr_drill |
| `dropbox_backup_scan` | `*/15 * * * *` | dropbox_backup |
| `dropbox_sync_daily` | `40 2 * * *` | dropbox_sync |
| `email_cron_2min` | `*/2 * * * *` | email_cron → send_outbox |
| `email_triage_hourly` | `20 * * * *` | email_triage |
| `exec-agents-weekly` | `0 6 * * 1` | exec_agents |
| `finance_reminders_daily` | `0 5 * * *` | finance_ingest |
| `gen_category_knowledge_daily` | `17 3 * * *` | gen_category_knowledge |
| `gen_category_personas_daily` | `15 2 * * *` | gen_category_personas |
| `kb_autofill_gaps_weekly` | `0 4 * * 0` | kb_autofill_gaps |
| `kb_embed_backfill` | `*/5 * * * *` | kb_embed |
| `kb_ingest_queue` | `*/20 * * * *` | kb_ingest |
| `learn_gaps_weekly` | `15 3 * * 1` | learn_gaps |
| `meta_sync_daily` | `35 3 * * *` | meta_sync |
| `money_tests_daily` | `30 3 * * *` | money_tests |
| `qa_suite_daily` | `37 3 * * *` | qa_suite |
| `retention_purge_weekly` | `0 3 * * 0` | retention_purge |
| `social_stage_hourly` | `17 * * * *` | social_stage |
| `supplier_invites_daily` | `0 9 * * *` | enqueue_supplier_invites (SQL) → queues invites for send_outbox |
| `uptime_check_15min` | `*/15 * * * *` | uptime_check |
| `wa_flush` | `*/2 * * * *` | send_whatsapp |
| `wa_templates_watch` | `*/15 * * * *` | wa_templates_watch |
| `invite_campaign_start` | `45 4 27 7 *` | one-shot: sets `invite_enabled=true` Mon 27 Jul, then self-unschedules |

### Agent-fleet crons (`select run_agent('<job>')` → the `agents` function)

| Cron job | Schedule (UTC) | Job |
|---|---|---|
| `agent_onboarding_hourly` | `23 * * * *` | onboarding |
| `agent_it_health_hourly` | `15 * * * *` | it_health |
| `agent_followup_daily` | `37 5 * * *` | followup |
| `agent_finance_weekly` | `0 4 * * 1` | finance |
| `agent_compliance_weekly` | `17 4 * * 1` | compliance |
| `agent_marketing_weekly` | `0 6 * * 1` | marketing |

> The `agents` function's job names must stay in sync with `reflect`'s RUNMAP and `secretary`'s SAFE_JOBS list.

---

## Appendix B — Disabled & security-sensitive functions

**Disabled (HTTP 410 stubs — inert, retained for reference):**
- `voice_otp`, `voice_otp_capture` — disabled 18 Jul 2026 (leaked capture token in cleartext; unauthenticated write to `app_secrets`).
- `dev_login`, `qa_login` — QA/dev auth helpers, turned off after launch-readiness audit.
- `src_io` — superseded by `put_src` / `deploy_next_preview`.

**Live but security-sensitive (handle with care):**
- `qa_mint` — account-creation primitive; double-gated (`inbound_secret` + `qa_mint_enabled` kill-switch). Keep OFF in production.
- `auth_api` — public auth surface; carries the 18 Jul 2026 fix preventing signup from overwriting an existing account. (Dead helper `archiveSign` defined but unused.)
- `agent_act` — the only money-moving agent path; MFA-gated via `admin_mfa_sessions`.
- `qa_suite` — scores inconclusive RLS probes as PASS (known blind spot); internal key reuses `postiz_publish_key`.

**Coexisting-implementation notes (not bugs, but a developer should know):**
- `secretary` (older `@@ACTIONS@@`-string form) and `secretary_act` (newer tool-calling form) both implement the Secretary role.
- `inbound_email` (generic/legacy, no Svix verification) and `resend_inbound` (Resend production webhook, `?s=` token + Svix signature) are two distinct inbound handlers.
- `collections_legal` (no-commission, 9% p.a.) and `legal_draft` (2% commission, 12% p.a.) encode two different legal-money models.
- `capability_agent` is fully built but **not wired into live matching** (dormant by design).

---

## Appendix C — Related chapters

- **`CUSTOMER_PORTAL.md`** — customer-facing functions (customer_api, quote_* , match, refunds, etc.).
- **`SUPPLIER_PORTAL.md`** — supplier-facing functions (supplier_api, supplier_portal, dispatch_inquiry, etc.).
- **`WEBSITE.md`** — public website functions (home, faq, contact_submit, site_assistant, etc.).
- **`OS_AUDIT.md`** — production-readiness audit of this OS (scores + findings + remediation log).

*End of OS backend reference — 120 edge functions across 9 domains.*
