-- the_number_of_suppliers_who_may_quote_is_not_capped_anywhere.sql
-- Seat: customer_support (the knowledge rows customers and suppliers read). Founder ruling of 24 Sep 2026: ANY number of
-- suppliers may quote; "top 3" is only the comparison report. Re-check of 12 Nov 2026 (R5): WhatsApp twice said "usually a
-- handful, with the number capped", from FAQ 13, 43, 67 and their Arabic 604, 751, 712.
-- THE SOURCE IS src/content/company_facts.json (canonical_statements.any_number_may_quote, with the exact wrong sentences and their
-- fixes). This file is the KNOWLEDGE-ROW SECTION of `node scripts/legal/sync_company_facts.mjs --emit-sql` run on 12 Nov 2026
-- against production (the 11 rows it found: 6 company_faq, the compiled FAQ in agent_knowledge, 4 kb_chunks), each guarded by the
-- md5 of the row as read, embedding cleared so it is re-embedded. Copied as generated, except that each statement's trailing
-- comment quoting the wording it replaced is left out (it repeated the forbidden cap, and the Arabic check reads comments).
-- LEFT OUT, ON PURPOSE: the same run also emitted the signed-registry section (customer terms v11, Supplier Agreement v17 and
-- their app_secrets pins), because production's registry differs from the repository's legal.json. That is not this change and
-- would make every supplier and customer accept new terms; it is reported to the main session, not applied here. Also left
-- out: the four decision_policy money keys the generator re-asserts on every run (refund and non-response fees and rates; not this
-- file's subject, review of branch B).
-- Apply: any order against the deploys. It ends with a verdict row.

-- knowledge rows (11)
update public.company_faq set answer = $qd$The Smart Engine shortlists suppliers by real capability, keywords and the emirates they serve, then judges each candidate on whether they can genuinely do your exact job. Only genuinely-capable suppliers are invited — a wrong match is treated as worse than no match — and any number of the invited suppliers may quote: there is no fixed limit.$qd$, embedding_gte = null where id = '67' and md5(answer) = '326a51ced78adc10c6357be017dcae9f';
update public.company_faq set answer = $qd$Only the suppliers who can genuinely fulfil your job — never a mass blast, and any number of them may quote: there is no fixed limit, and you see every quotation that arrives. The comparison report recommends the strongest three by value.$qd$, embedding_gte = null where id = '13' and md5(answer) = 'c1e44079c33bb33b287f219f5fa4c9be';
update public.company_faq set answer = $qd$Only suppliers who can genuinely do the job, never a mass blast, and any number of them may quote: there is no fixed limit. The customer sees every quotation, and the comparison report recommends the strongest three by value.$qd$, embedding_gte = null where id = '43' and md5(answer) = '1a3f670b2a809769162bb7bfc0c914d6';
update public.company_faq set answer = $qd$الموردون القادرون فعليًا على تنفيذ عملكم فقط، وليس إرسالًا جماعيًا، ويمكن لأي عدد منهم أن يقدّم عرض سعر؛ فلا يوجد حدّ ثابت، وتطّلعون على كل عرض يصل. ويوصي تقرير المقارنة بأفضل ثلاثة عروض من حيث القيمة.$qd$, embedding_gte = null where id = '604' and md5(answer) = 'bcf1a1310d9fd58d232257d964c575f7';
update public.company_faq set answer = $qd$يضع المحرك الذكي قائمة مختصرة بالموردين وفق القدرة الحقيقية والكلمات المفتاحية والإمارات التي يخدمونها، ثم يقيّم كل مرشّح بما إذا كان قادرًا فعلًا على تنفيذ عملكم بالتحديد. ولا يُدعى سوى الموردين المؤهلين فعليًا — فالمطابقة الخاطئة أسوأ من عدم المطابقة — ويمكن لأي عدد من الموردين المدعوّين أن يقدّموا عروضهم؛ فلا يوجد حدّ ثابت.$qd$, embedding_gte = null where id = '712' and md5(answer) = 'ccaa25ee5fc529d385d9f20daf25b5cc';
update public.company_faq set answer = $qd$يصل الطلب إلى الموردين القادرين فعليًا على تنفيذ العمل، وليس إرسالًا جماعيًا، ويمكن لأي عدد منهم أن يقدّم عرض سعر؛ فلا يوجد حدّ ثابت. ويطّلع العميل على كل عرض، ويوصي تقرير المقارنة بأفضل ثلاثة عروض من حيث القيمة.$qd$, embedding_gte = null where id = '751' and md5(answer) = 'd6a683990987a2a168f4c7ddd59a679c';
update public.agent_knowledge set content = $qd$QUOTESDONE COMPANY FAQ — canonical answers every agent must use verbatim-in-spirit (founder-approved). If asked anything here, answer consistently with this. Do not contradict it or invent beyond it.

## [AI Explainability] Which knowledge was retrieved?
Each decision draws on retrieved kb_chunks and agent_knowledge; kb_usage_log records what knowledge was used, and agent cards cite the source records so a reviewer can see the inputs behind an answer.
(Audience: internal)

## [AI Explainability] Which regulations were used?
For compliance/legal outputs, the cited authority chunks (kb_chunks carry citation + source) are shown; Legal AI references the specific UAE codes/clauses it relied on rather than asserting from memory.
(Audience: internal)

## [AI Explainability] Which supplier capabilities were considered?
The matched candidates and the capability summaries/embeddings that drove the match are recorded on inquiry_matches, and the comparison shows per-supplier (anonymised A/B/C) capability and spec fit.
(Audience: internal)

## [AI Explainability] Which business rules influenced the outcome?
The gates and boosts that applied — eligibility exclusions, verification boosts, the completeness gate, no-commission, anonymity — are the same configurable rules described under Business Rules Engine; the card's reasoning notes which ones fired.
(Audience: internal)

## [AI Explainability] Which assumptions were made?
The Smart Engine states assumptions in its reasoning summary (e.g. inferred spec or assumed quantity) and, when key detail is missing, asks to clarify rather than assume silently.
(Audience: internal)

## [AI Explainability] Which uncertainties remain?
Low-confidence or ambiguous points are flagged in the reasoning and, below threshold, escalated rather than acted on — the card shows what is uncertain instead of hiding it.
(Audience: internal)

## [AI Explainability] Why was not another supplier selected?
Because it ranked lower on capability fit, was ineligible (blocked/expired docs/strikes), or fell outside the filters (emirate/role/product); the ranking inputs make the exclusion explainable. Honest gap: the per-candidate why-not is reconstructable from the match inputs but is not yet rendered as a one-click rejection reason for every non-selected supplier.
(Audience: internal)

## [AI Explainability] How does the platform explain why a supplier was matched to a request?
fn_match_explain returns the same ranking the matching engine uses, but with the score broken into its parts: semantic similarity to the request, a performance boost (up to +0.05 from the supplier's performance score), a claimed-profile boost (+0.03), and an approved-status boost (+0.02), plus a plain-language reason string. This makes every match auditable - you can see exactly why one supplier ranked above another.
(Audience: internal)

## [AI Governance] Which decisions may the Smart Engine make autonomously?
Only low-risk, reversible, internal ones: drafting content and recommendations, ranking and matching candidate suppliers, computing KPIs and health scores, generating draft documents, enqueueing backups, and surfacing alerts and triage. In short — anything that produces a suggestion, a draft, or a read-only computation. It never takes an irreversible or money/permission-affecting action on its own.
(Audience: internal)

## [AI Governance] Which decisions always require human approval?
Anything irreversible or sensitive: sending a message or email to a user, publishing content, charging or refunding money, issuing a legal demand letter, approving or rejecting a supplier's verification, permission or security changes, deleting data, and changing business rules, prompts or knowledge. These are raised as approval cards and wait for the founder.
(Audience: internal)

## [AI Governance] How are AI confidence thresholds defined?
In matching and adjudication the engine is deliberately conservative — "a wrong match is worse than no match" — so low-confidence results are withheld or escalated rather than acted on. Thresholds are set per task and are tunable; below threshold means no auto-suggestion and escalation to a human. Honest note: these thresholds are heuristic and config-driven, not a formally calibrated probability model.
(Audience: internal)

## [AI Governance] How are AI recommendations explained?
Every agent action card carries a plain-language reasoning summary and a click-through to the source record or document that drove it (the click-through to source feature). Quote comparisons show per-supplier rationale, spec deviations and flags. Recommendations are traceable, not black-box — a reviewer can always see why.
(Audience: internal)

## [AI Governance] How is AI bias monitored?
Honest: there is no formal statistical bias-audit pipeline yet. The structural mitigations are real, though: matching is based on stated capabilities and specifications, and suppliers are anonymised (A/B/C) in comparisons, so decisions rest on merit rather than identity — and oversight catches skewed outputs before they act. A formal bias-monitoring process is a gap for later.
(Audience: internal)

## [AI Governance] How are AI models evaluated?
Evaluated continuously by a prompt-benchmark harness. Each candidate prompt/model is scored against a fixed set of graded test cases (currently 21 active cases across the RFQ-intake and quote-review agents, covering ambiguous requests, multi-trade jobs, jurisdiction/scope, UAE regulatory scenarios, spec deviations, marketplace anonymity, and supplier-reliability history). Runs are stored in prompt_eval_runs and the latest score per prompt is exposed via v_eval_latest. A change only ships if it beats the current baseline, and it auto-rolls-back if a later run regresses (auto-promote/rollback governance). Live agent quality is also tracked through the AI observability dashboard (v_ai_observability, v_ai_agent_health).
(Audience: internal)

## [AI Governance] How is AI performance measured?
Per-agent quality metrics from the AI Trainer, benchmark scores on prompt versions, domain KPIs (e.g. matching precision, agent throughput, review outcomes), and — a genuinely useful real-world signal — the rate at which the founder approves vs overrides agent cards. Honest note: there is no single unified model-observability dashboard yet; these signals live in a few places.
(Audience: internal)

## [AI Governance] How are AI failures investigated?
A bad output shows up as a rejected/overridden action card or a flagged item; because each carries its reasoning and a source link, it is traceable to what caused it. The offending prompt can be rolled back (fn_prompt_rollback), a corrected version benchmarked before re-promotion, and the cause and fix recorded in the session log and knowledge. Honest note: investigation is manual and founder-led rather than a formal incident process (this ties to the incident-response runbook already on the flagged list).
(Audience: internal)

## [AI Knowledge Coverage] How is knowledge coverage measured?
Via knowledge_kpis: coverage_pct, knowledge_coverage_pct and playbook_coverage_pct, computed as the share of categories that have knowledge, regulations, specs and playbooks out of categories_total (cat_with_knowledge / cat_with_regs / cat_with_playbook). Snapshots are kept in knowledge_kpi_snapshots.
(Audience: internal)

## [AI Knowledge Coverage] Which domains have weak coverage?
Categories that have some knowledge but no playbook or regulations, or a low coverage_pct — surfaced by the Knowledge Curator and the weekly learn_gaps job. New supplier categories auto-trigger provisioning (scan_new_supplier_categories to category_provision).
(Audience: internal)

## [AI Knowledge Coverage] How are coverage gaps detected?
learn_gaps (weekly) plus knowledge_kpis deltas and kb_usage_log — comparing topics actually queried (topics_queried_30d) against what is covered, so demanded-but-thin domains stand out. New categories detected on the supplier side auto-trigger knowledge provisioning.
(Audience: internal)

## [AI Knowledge Coverage] How are retraining priorities determined?
From learn_gaps findings, eval/benchmark failures, rising human-override rates, and low-coverage categories. Retraining here means updating prompts and knowledge (hosted LLMs, no model training) — the weakest, most-queried gaps are prioritised.
(Audience: internal)

## [AI Knowledge Coverage] How is knowledge completeness monitored?
Daily by the Knowledge Curator via knowledge_kpis — coverage_pct, accuracy_pct, freshness_pct and usage_reach_pct — with knowledge_kpi_snapshots preserving the trend over time.
(Audience: internal)

## [AI Memory & Learning] What information do agents remember?
Two stores: agent_knowledge (durable, curated per-agent knowledge — topic + content + priority, including the compiled Company FAQ in _global) and agent_memory (things learned or reflected on during operation — kind learned or reflection, with a source and an importance weight). They remember policies, canonical answers, lessons from past runs and reflections — not customer personal data beyond what a task needs.
(Audience: internal)

## [AI Memory & Learning] What is temporary memory?
Working context for the task at hand — the current RFQ, the records just retrieved, the conversation — used to reach a decision and not retained as long-term knowledge. Lower-importance agent_memory entries act as short-lived context. Honest: there is no hard time-to-live tier; temporary is effectively low-importance/working context versus the durable stores.
(Audience: internal)

## [AI Memory & Learning] What is permanent memory?
The durable stores: agent_knowledge (curated per-agent knowledge, including the compiled Company FAQ in _global) and higher-importance agent_memory entries. These persist across runs and drive consistent agent behaviour.
(Audience: internal)

## [AI Memory & Learning] How are lessons learned stored?
As agent_memory rows of kind learned (with a source and importance) and, weekly, reflection entries produced by the reflect job that reviews recent activity. High-value lessons can be promoted into curated agent_knowledge under oversight.
(Audience: internal)

## [AI Memory & Learning] How are previous projects reused?
Past RFQs, quotes, matches and comparisons remain in the database and feed retrieval and supplier performance (supplier_perf: matched/quoted/won). The Smart Engine draws on this history when matching and advising; snapshots such as quote comparisons are preserved.
(Audience: internal)

## [AI Memory & Learning] Can agents learn automatically?
Partly. They automatically accumulate reflections (weekly reflect) and learned notes, and performance metrics update continuously. But changes that affect behaviour — prompt changes, new canonical knowledge — go through governance (eval/benchmark + founder approval) rather than silent self-modification. Oversight-first: learning surfaces, humans promote.
(Audience: internal)

## [AI Memory & Learning] How are incorrect memories removed?
A wrong agent_memory/agent_knowledge entry is corrected or deleted under oversight (as done this session when correcting the malware-scanning answers). Canonical answers live in company_faq — the single source of truth — so a fix there recompiles the agents' knowledge. Honest: there is no automatic unlearn; removal is a governed edit.
(Audience: internal)

## [AI Memory & Learning] How is memory versioned?
Curated knowledge (kb_revisions) is versioned with author/reviewer/status/decision timestamps; company_faq edits carry source_note history and recompile on change. Honest gap: agent_memory rows themselves are not individually versioned — versioning lives on the curated knowledge layer.
(Audience: internal)

## [AI Memory & Learning] How are memories searched?
By agent scope (agent_key), relevance (full-text over content and semantic retrieval over kb_chunks), importance and recency. The compiled Company FAQ is always available to every agent via _global.
(Audience: internal)

## [AI Memory & Learning] How is memory quality measured?
Via the AI Trainer (per-agent quality), knowledge KPIs (knowledge_kpis), kb_usage_log (what knowledge is actually used) and eval/benchmark scores. Honest: there is no single memory-quality score; quality is inferred from agent output quality, usage and review status.
(Audience: internal)

## [AI Memory & Learning] How do things an agent learns become permanent, curated knowledge?
Agent learnings live in agent_memory. High-value memories that have not yet been promoted are surfaced in v_memory_promotion_candidates (ranked by importance). When you approve one, fn_promote_memory(memory_id, category) graduates it into the canonical knowledge base (kb_chunks), where it is full-text indexed and semantically embedded like any other knowledge, and becomes retrievable by all agents. Promotions are tracked in memory_promotions so nothing is promoted twice. This keeps a human in the loop between what an agent picked up and what becomes official knowledge.
(Audience: internal)

## [AI Security] How are AI prompts protected?
Every agent's prompt (persona and instructions) lives server-side in the database — never in the browser or client — and is only ever read by the backend. Prompts are versioned, and changes flow through a governed process: staged as a draft, reviewed, then promoted live. Users cannot see or alter an agent's system prompt, and the instruction/data boundary means content an agent reads (a request, a document, a web page) is treated as information to act on, never as new instructions.
(Audience: internal)

## [AI Security] Can prompts be modified?
Yes, but only through the governed pipeline. A change is created as a new draft version, can be evaluated/benchmarked, and is promoted live on approval; a misbehaving live prompt can be rolled back to a previous version. Agents cannot silently rewrite their own live prompts — prompt changes are a reviewed, versioned, reversible administrative action.
(Audience: internal)

## [AI Security] How is prompt versioning managed?
Prompts are stored with full version history (a prompts registry plus a prompt-versions table). Each version is retained, one is marked live, and evaluation/benchmark runs are recorded against versions so quality can be compared before promotion. Promotion and rollback are explicit operations, so you can always see which prompt is live, what changed, and revert.
(Audience: internal)

## [AI Security] How are prompt injections prevented?
By a strict instruction/data boundary and grounding. System prompts are fixed server-side; anything an agent reads — a customer's words, an uploaded document, a supplier profile, retrieved knowledge — is handled as data to analyse, not commands to obey, and briefs are anonymised and structured first. Agents answer only from approved knowledge and cannot take irreversible actions on their own, so an instruction embedded in content cannot make an agent exfiltrate data, move money, or act outside its lane.
(Audience: internal)

## [AI Security] How are jailbreak attempts detected?
Multiple guardrails rather than one filter. Agents are constrained by fixed instructions and produce structured, validated output (strict JSON that is parsed and range-checked); off-pattern or low-confidence output is rejected or held for review; and, critically, no agent can perform a sensitive or irreversible action regardless of what a prompt says, because those are gated behind human approval. Manipulative inputs surface as flags for oversight rather than silently succeeding.
(Audience: internal)

## [AI Security] How are hallucinations minimized?
Grounding first: agents retrieve and answer from the approved knowledge base (company facts, category knowledge, indexed UAE regulations) and are instructed never to invent specs, prices or identities — if something is not stated, they flag it rather than guess. Outputs are low-temperature and structured, the matcher follows "a wrong match is worse than no match" (it can return nothing rather than fabricate a fit), and an AI-Trainer process grades answer quality over time. Low-confidence results are held for a human.
(Audience: internal)

## [AI Security] Must AI retrieve knowledge before answering?
Yes — agents are grounded, not free-form. Before responding, an agent is given its persona plus the relevant knowledge: the canonical company answers, the category-specific quoting knowledge, and any applicable UAE regulations; the matcher retrieves supplier capabilities before adjudicating. This retrieval-before-answer design ties responses to verified, citable facts rather than the model's memory.
(Audience: internal)

## [AI Security] How are AI decisions logged?
Comprehensively. Agent runs are recorded (what ran, when, result); matching/routing decisions store full reasoning (job type, candidates evaluated, why each was included/excluded); recommendations, approvals and escalations go to the action ledger with who decided and when; and evaluation/benchmark runs are kept for prompts and matching. Every consequential AI decision leaves an auditable trail.
(Audience: internal)

## [AI Security] How are AI confidence scores calculated?
Confidence reflects the quality and clarity of inputs and the model's own assessment. For matching it comes from how well a supplier's capabilities fit the actual scope (retrieval similarity plus the adjudicator's judgement); for generated content and extractions, agents mark low-confidence when inputs are thin, ambiguous, conflicting or novel. These are not one universal probability — they are per-task signals whose main job is to trigger caution: low confidence makes the engine exclude rather than guess and routes the decision to a human.
(Audience: internal)

## [AI Security] When must AI escalate to a human?
Whenever a decision is sensitive, irreversible or uncertain — anything touching money, publishing, access/permissions, suspensions or legal matters; any new knowledge needing approval before going live; low-confidence outputs; and anything outside the agent's grounded knowledge. In all these the agent surfaces a recommendation and waits for approval rather than acting — the oversight-first rule.
(Audience: internal)

## [AI Security] How are AI permissions restricted?
Agents act through the same gated backend as everyone else, under an internal service identity, boxed in by the oversight model: they can read what they need and can propose or recommend, but cannot execute sensitive or irreversible actions on their own — those require a human approval step. An agent's effective permission is "surface, recommend, escalate," never unilateral action on money, access or published content.
(Audience: internal)

## [AI Security] Can AI access all customer data?
The backend the agents run on has broad read access to do its work, but agents operate on anonymised, task-scoped briefs and never expose one party's data to another — a supplier-facing agent never sees a customer's identity, and a customer only ever sees their own data. Access is purpose-bound, happens server-side under logging, and identities stay masked until a paid reveal. Agents use data to serve a task; they do not hand it across parties.
(Audience: internal)

## [AI Security] Can AI modify financial data?
No autonomous changes to money. Financial records (charges, refunds, commissions/dues, ledger entries) are produced by governed flows — for example a Stripe payment confirmed by a verified webhook, or a scheduled reconciliation — not by an agent deciding to alter a balance. Agents can compute, analyse and recommend (flag an overdue charge, draft a report), but do not rewrite financial data; anything sensitive routes through human approval.
(Audience: internal)

## [AI Security] Can AI approve payments?
No. Agents never approve, release or move money. Customer payments go through Stripe; refunds and any money movement require the proper flow and human authorisation; the founder approves sensitive money actions through the oversight queue. An agent's role around payments is limited to surfacing, computing and recommending — the approval is always a human decision.
(Audience: internal)

## [AI Self-Monitoring] How is hallucination rate measured?
We do not publish a single numeric "hallucination rate" - that would be misleading. Instead we constrain and measure factuality several ways: (1) agents answer from retrieved, cited knowledge (kb_chunks and the approved Company FAQ) rather than free recall; (2) the prompt-benchmark harness (21 graded cases) rubric-checks whether answers fabricate specs, misread a requested specification, or over-claim, and a regression blocks the release; (3) the AI observability dashboard tracks each agent's override/rejection rate and average confidence, while knowledge KPIs track accuracy, freshness and coverage; (4) low-confidence answers are escalated to a human approval queue rather than sent. This is honest measurement of grounding and human-override signals, not a marketing number.
(Audience: internal)

## [AI Self-Monitoring] How is answer quality measured?
AI Trainer per-agent quality scores, prompt benchmark scores, eval pass rates, and the founder's approve-versus-override rate on agent cards.
(Audience: internal)

## [AI Self-Monitoring] How are weak domains detected?
learn_gaps (weekly) and match_eval surface where retrieval or answers are thin or where matching precision drops; category knowledge gaps trigger provisioning.
(Audience: internal)

## [AI Self-Monitoring] How is prompt performance measured?
prompt_eval_runs + prompt_benchmarks score each prompt version against seed cases before promotion; regressions block promotion and can roll back.
(Audience: internal)

## [AI Self-Monitoring] When is retraining required?
There is no model training here (hosted LLMs via OpenRouter); retraining means updating prompts/knowledge. It is triggered when eval/benchmark scores drop, learn_gaps finds recurring misses, or override rates rise — then a new prompt/knowledge version is drafted, benchmarked and approved.
(Audience: internal)

## [AI Self-Monitoring] How are failed conversations reviewed?
Poor outcomes surface as overridden/rejected agent cards, low review scores, and qa_suite/smoke findings; the AI Trainer and founder review them, and fixes flow through prompt/knowledge governance.
(Audience: internal)

## [AI Self-Monitoring] How is AI agent health and observability monitored?
All Smart Engine signals are unified in one live AI observability dashboard backed by two database views. v_ai_observability gives the 24-hour picture: agent runs and errors, the open human-approval queue, average evaluation score, knowledge-base confidence, coverage and embedding progress, and how many knowledge chunks are due for review. v_ai_agent_health gives per-agent 30-day detail: runs, errors, action volume, a human-override/rejection proxy rate, average confidence, and last-run time. Errors are caught via agent run status, and anything low-confidence is routed to a human approval queue instead of acting autonomously. The dashboard refreshes live from the database each time it is opened.
(Audience: internal)

## [AI Self-Monitoring] Is the platform security posture audited on a schedule?
Yes. Alongside the existing daily backup, monthly disaster-recovery restore drill (dr_drill), malware hash-scanning (vt_scan), fraud scan (fn_fraud_scan) and security scan (fn_security_scan), a daily security self-audit (cron security_selfaudit_daily calling fn_security_selfaudit) snapshots the database security posture: the number of public tables with row-level security disabled (must stay 0 under deny-by-default), tables with RLS enabled but no policy (the intentional service-role-only tables), SECURITY DEFINER views, and definer functions callable by anonymous users. If any public table ever has RLS disabled it raises a high-severity security event. Snapshots are retained in security_selfaudit_snapshots so posture drift is visible over time. A managed advisor baseline on 2026-07-11 recorded 17 ERROR, 86 WARN and 165 INFO findings; the INFO class is the deny-by-default design, and the ERROR/WARN classes are queued for careful, application-safe review.
(Audience: internal)

## [AI Self-Monitoring] Does the platform alert when AI quality degrades?
Yes. A daily watch (cron ai_quality_watch_daily calling fn_ai_quality_watch) checks for two things: evaluation regressions (a prompt's latest benchmark score dropping more than 5 points below its previous run, or below 70 absolute) and override spikes (a human-facing agent's rejection rate jumping more than 20 points above its own trailing average). Anything it finds is written to security_events (kind eval_regression / override_spike), raised as an ai_quality_alert action, and emailed to the founder - deduplicated so you are not spammed. Per-agent override history is snapshotted in ai_quality_snapshots so spikes can be detected over time.
(Audience: internal)

## [API Security] How are APIs authenticated?
Every backend endpoint is an Edge Function that authenticates its caller first. User calls carry a Supabase-issued JWT in the Authorization header, validated for signature, expiry and user. Service-to-service and scheduled calls present a shared internal secret instead. Inbound third-party webhooks (e.g. Stripe) are authenticated by verifying a cryptographic signature. Any unauthenticated public read uses a restricted anon key that is still bound by row-level security.
(Audience: internal)

## [API Security] How are APIs authorised?
After authentication, each function resolves the caller's role and checks both the permission for the action and ownership of the target record before running logic — a customer can only act on their own inquiries; admin endpoints admit only owner/admin roles. Row-level security is a second, independent gate. Failing any check returns 401/403 with no data.
(Audience: internal)

## [API Security] How is rate limiting implemented?
Rate limiting is applied where abuse matters most — the auth flows cap attempts (email links and SMS codes are limited per email/number per hour, reset requests throttled), and money/reveal flows are idempotent so repeats cannot double-charge. The managed platform (Supabase/Vercel) provides baseline network-level protection. There is not a single global API-gateway rate limiter yet; limits are targeted at the endpoints that need them and can be broadened as traffic grows.
(Audience: internal)

## [API Security] How are API keys rotated?
Third-party keys and the internal service secret live in the server-side, RLS-protected secrets table, so rotating one is a single update there — no code change, no redeploy — effective on the next call. Because keys are read at call time rather than baked into the build, rotation is fast and low-risk; a compromised key can be replaced immediately.
(Audience: internal)

## [API Security] How are webhooks verified?
Inbound webhooks are cryptographically verified before they are trusted. The Stripe webhook recomputes the HMAC-SHA256 signature over the raw payload using the signing secret and compares it to the Stripe-Signature header, rejecting anything that does not match. Internal service webhooks are gated by the shared internal secret. An unverified webhook is discarded with a 400.
(Audience: internal)

## [API Security] How are replay attacks prevented?
Several layers. Signed webhooks include a timestamp and are accepted only inside a short tolerance window (about 10 minutes for Stripe), so a captured old delivery is rejected. One-time tokens (email confirmation, password reset, OTP) are single-use and expire quickly. And money/dispatch operations are idempotent (keyed on the underlying record), so a replayed request cannot create a second charge, match or reveal.
(Audience: internal)

## [API Security] How are CORS policies configured?
Edge Functions set explicit CORS headers and handle preflight (OPTIONS) requests, permitting only the headers and methods the app needs (Authorization, Content-Type; POST/OPTIONS). CORS is a browser convenience, not the security boundary — every request is still authenticated and authorised server-side and constrained by RLS, so a permissive origin cannot reach protected data without valid credentials.
(Audience: internal)

## [API Security] How are API errors sanitized?
User-facing responses return clear, generic messages — no stack traces, SQL, secrets or connection strings are exposed to clients. Auth flows are deliberately vague where it matters (reset responses do not reveal whether an email exists) to prevent enumeration. Full diagnostic detail stays server-side in logs, not returned to the caller.
(Audience: internal)

## [API Security] How are request IDs generated?
Requests are traceable through platform-assigned identifiers: Vercel and Supabase attach request/execution IDs to each call and its logs, and outbound calls made from the database (via pg_net) carry their own request IDs whose responses are recorded. These let a specific request be followed across the frontend, the function and any downstream call when investigating an issue.
(Audience: internal)

## [API Security] How are API logs retained?
Function and database request logs are retained by the managed platform (Supabase/Vercel) for monitoring and debugging within their retention windows. On top of that, business-level activity — agent runs, decisions, approvals, money events, notifications — is written to durable tables that persist as long as the records do. So there is both short-term infrastructure logging and a long-term, queryable audit trail.
(Audience: internal)

## [Authentication] How do users authenticate?
Users authenticate with email and password through Supabase Auth (the managed identity service). On sign-up they create an account (with an 18+ age check), confirm their email via a one-time link, and — where enabled — verify their mobile by SMS code. On sign-in, Supabase Auth issues a signed session (a JWT access token plus a refresh token) that the app sends on every backend call; Edge Functions verify it before running any logic. Internal OS/admin access additionally checks the user's role.
(Audience: internal)

## [Authentication] Which authentication methods are supported?
Email-and-password sign-in via Supabase Auth is the primary method for both customers and suppliers. Email confirmation (one-time link) and SMS phone verification (Twilio Verify, six-digit code) validate identity at sign-up. Internal staff/admin access is the same email login plus a role check. There is no social/SSO login today, though Supabase Auth can add providers if needed.
(Audience: internal)

## [Authentication] Is MFA supported?
A phone one-time-code step (SMS via Twilio Verify) is used alongside email confirmation to verify accounts, adding a second factor at onboarding when enabled. Ongoing, per-login multi-factor (e.g. an authenticator/TOTP app) is not enforced today, but the identity layer (Supabase Auth) supports adding it — most sensibly for admin/OS accounts first.
(Audience: internal)

## [Authentication] How are passwords stored?
Passwords are never stored by QuotesDone in readable form and never touch our database or logs. They are handled entirely by Supabase Auth, which keeps only a salted one-way hash (bcrypt). The application only ever passes a password to the managed auth service to set or verify it — it cannot read it back. A minimum length (8+ characters) is enforced.
(Audience: internal)

## [Authentication] How are password resets handled?
A user requests a reset by email; if an account exists, a single-use link with a short expiry (one hour) is emailed. Following it lets them set a new password, which the managed auth service re-hashes. The flow is enumeration-safe (same response whether or not the email exists), single-use, expiring, and rate-limited against abuse.
(Audience: internal)

## [Authentication] How are sessions managed?
Sessions are managed by Supabase Auth. On sign-in the user gets a short-lived JWT access token and a longer-lived refresh token, held by the Supabase client in the browser. The access token accompanies each backend request; as it nears expiry the client transparently exchanges the refresh token for a new one, so the user stays signed in without re-entering credentials. Signing out revokes the session.
(Audience: internal)

## [Authentication] How are JWTs validated?
Every privileged backend call carries the JWT in the Authorization header. The Edge Function validates it against Supabase Auth (signature, expiry, and resolving the user) and only then runs — mapping the user to a customer, supplier or admin and enforcing role and ownership before touching data. Requests with a missing, invalid or expired token are rejected (401). Service-to-service and scheduled calls use a separate internal secret instead of a user JWT.
(Audience: internal)

## [Authentication] What happens when a token expires?
An expired access token is rejected by the backend. In normal use the client refreshes it silently (via the refresh token) before it lapses, so the user is not interrupted. If the session can no longer be refreshed — after a long absence or a sign-out — the user is asked to sign in again. No privileged action ever runs on an expired token.
(Audience: internal)

## [Authentication] How are refresh tokens secured?
Refresh tokens are issued and rotated by Supabase Auth and stored by the Supabase client on the user's device, transmitted only over HTTPS. They rotate (each refresh issues a new one and invalidates the old), can be revoked (sign-out or admin action), and are never placed in URLs or exposed to logs. Because all sensitive logic runs server-side, a token alone still cannot bypass the role and ownership checks each request enforces.
(Audience: internal)

## [Authentication] How are inactive sessions terminated?
Access tokens are short-lived and every sensitive request re-verifies the token and the user's role, so a stale token cannot act. A session ends when the user signs out or an admin revokes it, and one that can no longer be refreshed forces a fresh sign-in. Absolute and idle session timeouts can be enforced through the auth configuration — recommended especially for admin/OS accounts — so long-inactive sessions are logged out automatically.
(Audience: internal)

## [Authorization] Which user roles exist?
Three tiers. Marketplace roles: customer (buyer), supplier (seller), and guest (unauthenticated). Internal/staff roles, in order of privilege: owner (the founder), admin, ops, finance, support, and agent (Smart Engine service accounts). A user's role is resolved from an explicit assignment first, then falls back to owner (on the admin list), supplier (a claimed lead), customer (a registered account), or guest.
(Audience: internal)

## [Authorization] How are permissions assigned?
Permissions are role-based. Staff/agent roles are assigned explicitly in a roles / user-roles table with a role-to-permissions mapping; marketplace roles are derived from the person's relationship to the data (a claimed supplier lead becomes a supplier, a registered account becomes a customer). On top of the role, the database enforces row-level security and every privileged Edge Function re-checks the caller's role and their ownership of the specific record before acting.
(Audience: internal)

## [Authorization] What is RBAC?
Role-based access control — access is granted by the role a user holds rather than per-user rules. QuotesDone uses it: a small set of roles (owner, admin, ops, finance, support, agent, supplier, customer, guest) each carry defined permissions, users map to roles, and the backend checks the role on every request. Privileges change by moving a user between roles, not by editing scattered rules.
(Audience: internal)

## [Authorization] Is ABAC implemented?
Not as a separate policy engine, but attribute/ownership checks are layered on top of RBAC. Beyond "what role are you," the system enforces "is this yours" — a customer sees only their own inquiries, a supplier only their own profile and quotes, files open only via short-lived signed links, and flags like verification status, licence validity and matching-block are checked. These relationship/attribute checks act like ABAC where it matters.
(Audience: internal)

## [Authorization] How are permissions inherited?
Roles are ranked and higher roles subsume lower ones — owner is most privileged, then admin, then the specialised staff roles; when a user holds more than one role, the most privileged wins. Marketplace roles do not inherit staff privileges. The model is deliberately flat and explicit rather than a deep inheritance tree, so access stays predictable.
(Audience: internal)

## [Authorization] How are API permissions validated?
On every privileged call the Edge Function validates the JWT, resolves the caller's role, and confirms both the required permission for that action and ownership of the target record before running any logic — all server-side. The database's row-level security is a second, independent gate. Service-to-service and scheduled calls carry a separate internal secret instead of a user role. Anything failing these checks is refused.
(Audience: internal)

## [Authorization] Can permissions be overridden?
No self-service or silent override. Elevated access comes only from an explicit role assignment by the owner/admin, and the Smart Engine agents cannot override the oversight gates — sensitive or irreversible actions are surfaced for human approval rather than force-executed. Any change to who can do what is a deliberate, recorded administrative action.
(Audience: internal)

## [Authorization] How are admin privileges controlled?
Admin/OS access is tightly gated: the internal OS backend admits only owner/admin roles (resolved from the role table plus the trusted admin-email list) and checks the caller's identity on every action. Admins act through the same audited APIs as everyone else — not direct database access — and the most sensitive operations still route through the approval queue. The admin list and role assignments are themselves controlled by the owner.
(Audience: internal)

## [Authorization] How are temporary permissions granted?
Through time-boxed, scoped grants rather than standing access: documents are reached via short-lived signed URLs that expire in minutes; email-confirmation, password-reset and phone-code tokens are single-use and expire quickly; internal service calls use a rotatable shared secret scoped to server-to-server use. There is no general temporary-role hand-out — elevation is an explicit role change, and transient access is always narrow and self-expiring.
(Audience: internal)

## [Authorization] How are privileged actions audited?
Privileged and agent actions are recorded. The approval/action ledger captures each sensitive decision with who decided, when, and the outcome; agent runs, matching/routing decisions, cancellations, backups, notifications and money events are logged with timestamps. Because all privileged work goes through server-side APIs (not raw database access) and the Smart Engine is oversight-first, there is a consistent trail of what was proposed, what a human approved, and what was executed.
(Audience: internal)

## [Availability] What uptime target is maintained?
QuotesDone aims for high availability by building on managed, highly-available platforms — Vercel for the site and Supabase for the backend, which target around 99.9%+ — and by running a scheduled uptime check with founder alerts. Honestly, QuotesDone does not publish its own contractual SLA yet; the practical target is "always-on" with rapid detection and recovery, inheriting the providers' availability. A formal internal uptime objective can be set and measured as the business matures.
(Audience: internal)

## [Availability] How is redundancy implemented?
Largely inherited from the managed stack. The public site is static and served from Vercel's global CDN, replicated across many edge locations. The backend runs on Supabase (AWS), which provides managed availability, automated backups and infrastructure redundancy. Documents have an independent second copy in the company's Dropbox. Edge Functions are stateless, so they scale and recover across the platform's capacity. Honest note: the database runs as a managed primary — cross-region replicas/high-availability tiers are plan-dependent and a scaling decision as volume grows.
(Audience: internal)

## [Availability] How are deployments performed with minimal downtime?
Effectively zero-downtime. The website is published as an atomic Vercel deployment: a new immutable build is prepared and promoted in one switch, with instant rollback if needed — visitors are never served a half-updated site. Backend Edge Functions are deployed one at a time and versioned, so a new version takes over cleanly without a service window. Database changes go through incremental migrations, most applied online. There is no "site down for maintenance" step in normal releases.
(Audience: internal)

## [Availability] How are maintenance windows managed?
Routine platform maintenance (of the managed database and hosting) is handled by the providers with their own high-availability practices, so it generally does not require QuotesDone to schedule downtime. QuotesDone's own changes are incremental and hot-deployed rather than needing a window. If a change ever did need a brief window, it would be scheduled for a low-traffic period and communicated. Today, planned downtime is the exception, not a regular event.
(Audience: internal)

## [Availability] How are rolling updates performed?
Because the system is composed of many small, independently deployable pieces, updates roll out piece by piece rather than as one big-bang release: each Edge Function is deployed on its own and versioned; the static site is swapped atomically; agents and scheduled jobs are updated independently. This lets a change ship and be verified in isolation — and be rolled back on its own if needed — without taking the whole platform offline.
(Audience: internal)

## [Availability] How is failover handled?
Infrastructure failover is provided by the managed platforms — Vercel automatically routes around unhealthy edge locations, and Supabase/AWS handle underlying infrastructure faults — while the stateless Edge Functions simply recover as capacity returns. On top of that, the uptime check plus founder alerts catch problems quickly, and the independent Dropbox backup and database backups mean data can be recovered even in a worst case. Honest note: automatic, self-managed cross-region database failover is not in place (it depends on a higher-availability database tier); adopting a high-availability database configuration is the natural next step for stronger failover as the platform scales.
(Audience: internal)

## [Business Continuity] How does the business continue if an AI service is unavailable?
The Smart Engine calls its models through OpenRouter with multiple model fallbacks, so a single model going down usually just shifts to another. If the whole LLM provider is unavailable, the oversight-first design protects the business: agents never auto-act, so a stalled agent means items simply wait for human review rather than producing wrong actions. The core marketplace — posting RFQs, submitting quotes, reveals, payments — does not depend on the LLM, so it keeps working; only the smart layers (match suggestions, quote comparisons, agent recommendations) pause. Honest note: those smart features stay unavailable until the provider recovers; there is no on-prem model fallback.
(Audience: internal)

## [Business Continuity] What happens if Stripe is unavailable?
New payments (reveal fee, supplier subscription) cannot be taken while Stripe is down. The webhook is idempotent and signature-verified with a tolerance window, so when Stripe recovers, its retried events reconcile cleanly with no double-charging. Everything that is not a payment continues normally. Honest gap: Stripe is the only processor — there is no alternative payment rail today.
(Audience: internal)

## [Business Continuity] What happens if Dropbox is unavailable?
Little impact, because Dropbox is a secondary backup mirror, not the system of record. The originals live in Supabase Storage and are also covered by Supabase's managed daily backups. If Dropbox is offline, the 15-minute backup queue just retries later — the pending doc_backups rows stay queued and catch up when it returns. Nothing user-facing depends on Dropbox.
(Audience: internal)

## [Business Continuity] What happens if email delivery fails?
The platform keeps running. Where SMS OTP is enabled it can carry verification, and critical notifications, alerts and collections items are also surfaced in-app (agent action cards / notifications), so the founder and users still see them even if an email does not arrive. Honest gap: failed emails are not yet on a robust retry / dead-letter queue with a delivery dashboard — that is a monitoring gap, mitigated today by the in-app cards for anything important.
(Audience: internal)

## [Business Continuity] What happens if SMS delivery fails?
SMS (Twilio Verify OTP) is one verification factor, gated by the sms_enabled flag. If SMS is failing, verification can fall back to email verification plus the age gate, and sms_enabled can be switched off so sign-ups are not blocked. Honest note: this temporarily removes one security factor until SMS is restored.
(Audience: internal)

## [Business Continuity] What happens if the database is temporarily unavailable?
This is the genuine hard dependency: if Postgres is down, the application backend is down (it runs as a single managed primary — see Availability). Supabase handles infrastructure-level recovery, and because the public site is static on Vercel's CDN, the marketing and FAQ pages stay reachable and serve cached content even while the app backend is impaired. Worst-case data recovery is restore-from-backup. Honest note: there is no self-managed hot standby / read-replica failover yet — a high-availability database tier is the planned next step.
(Audience: internal)

## [Business Continuity] What happens if an external government verification service is offline?
Verification is deferred, not skipped. If an external source (e.g. trade-licence lookup) is offline, the supplier stays in a pending/unverified state and the matching and reveal gating hold until verification completes — oversight-first means the platform will not auto-approve to work around an outage. The check is queued and finished when the service returns. Honest note: there is no auto-pass fallback, which is deliberate — deferring is safer than approving unverified sellers.
(Audience: internal)

## [Business Rules Engine] How is supplier ranking calculated?
Two layers. Retrieval (match_suppliers) ranks candidates by semantic capability fit — pgvector similarity (1 minus cosine distance) between the RFQ embedding and each supplier's capability embedding — plus small boosts: +0.05x performance score, +0.03 if the profile is claimed/registered, +0.02 if approved; filtered by emirate/role/product/min-rating and excluding matching-blocked suppliers. A full-text variant runs alongside for hybrid retrieval. The Smart Engine then adjudicates the shortlist conservatively (a wrong match is worse than no match). Ranking is capability-first, lightly adjusted for track record and verification.
(Audience: internal)

## [Business Rules Engine] How is supplier priority determined?
Within a matched set, priority favours best capability fit, then verified (claimed/approved) status and higher performance, while health/risk gates apply (banned, matching-blocked, 3+ strikes, or compliance under 40 are effectively excluded). It is about who is surfaced/invited first — there is no pay-to-rank queue-jump.
(Audience: internal)

## [Business Rules Engine] How are invitations distributed?
Two separate things: (a) RFQ routing — when a buyer posts, dispatch_inquiry notifies the matched, eligible suppliers, with a guard that stops incomplete matches from being dispatched; (b) directory onboarding invites — enqueue_supplier_invites reaches unclaimed directory leads, gated by an invite_enabled flag and a daily cap (default 40), one per email, skipping suppressed/opted-out addresses. Both are governed and capped.
(Audience: internal)

## [Business Rules Engine] How are conflicts of interest handled?
Structurally minimised: buyers stay anonymous to suppliers, suppliers cannot see each other's quotes (blind quoting), and QuotesDone takes no commission on won jobs — so there is no financial incentive to steer a buyer anywhere. Matching is on stated capability + verification, not relationships. Honest gap: there is no automated same-owner/duplicate-entity COI detector yet beyond duplicate-account checks. Update (2026-07-11): a v_supplier_coi detector now flags claimed suppliers sharing a phone, WhatsApp, email, TRN or trade-licence number — surfacing likely same-owner/duplicate entities for review.
(Audience: internal)

## [Business Rules Engine] How are tie-breakers resolved?
When capability fit is close, the ordering formula breaks ties by performance score, then verified (claimed/approved) status, then health signals (compliance/response/recency) — favouring the more reliable, active, verified supplier. Ties never resolve randomly or toward whoever paid.
(Audience: internal)

## [Business Rules Engine] How is RFQ priority calculated?
RFQs are handled in arrival order with a completeness gate: one missing the detail needed to match well is clarified first (run_rfq_clarify) rather than dispatched to weak matches. There is no paid fast lane for buyers — urgency is served by clarify-then-dispatch, not priority payments.
(Audience: internal)

## [Business Rules Engine] How is quotation weighting calculated?
In the buyer's comparison, quotes are weighed on total price, itemised line detail, spec compliance/deviations, and completeness — not on supplier identity (suppliers are anonymised A/B/C). Detailed, spec-matching quotes beat vague lump sums (itemised quotes are enforced at entry). The tool surfaces trade-offs; it does not auto-pick a winner.
(Audience: internal)

## [Business Rules Engine] When does the Smart Engine override normal routing?
Rarely and conservatively — it withholds or reroutes when confidence is low, when a supplier is ineligible (banned, matching-blocked, expired critical docs, 3+ strikes), or when an RFQ is too incomplete to match, in which case it escalates to clarify or human review rather than dispatch. An override never silently picks a favourite; it holds or escalates.
(Audience: internal)

## [Business Rules Engine] When are suppliers excluded?
When matching_blocked or banned is set, an unsettled non-response fine holds them, chat strikes hit 3, critical compliance is missing/expired (trade licence/insurance pushing compliance under 40), or registration has lapsed. match_suppliers hard-excludes matching-blocked suppliers at the query level; health scoring pushes high-risk ones down or out.
(Audience: internal)

## [Business Rules Engine] How is fairness maintained?
Blind, anonymous quoting (no identity-based favouritism); no commission (no incentive to steer); merit-based matching on capability + verification; no pay-to-rank; capped, opt-out-respecting invitations; and every routing decision is explainable and auditable. Honest note: the free-onboarding tier and the small verification boosts are a deliberate, disclosed thumb-on-scale toward verified suppliers — fairness here means merit + verification, not treating verified and unverified identically.
(Audience: internal)

## [Company Identity] What is QuotesDone?
QuotesDone is a UAE B2B anonymous quotation marketplace based in Dubai. A customer (buyer) posts what they need — by text, voice, photo or drawing — and our Smart Engine turns it into a clear, priceable brief and matches it to vetted suppliers (sellers) who submit anonymised quotes. The buyer compares the quotes and pays a 3% reveal fee on the quote they choose to unlock that seller's identity and contact details. It is operated by QuotesDone Technologies, a Dubai DET-licensed business (E-Trader Licence No. 1633275).

## [Company Identity] Why was QuotesDone created?
QuotesDone was created to fix how construction and services buying works in the UAE: getting several comparable quotes today means chasing suppliers one by one, sharing your contact details up front, then fielding calls and haggling — while suppliers waste time on jobs that aren't really theirs. QuotesDone lets a buyer describe a job once and receive comparable, anonymised quotes from genuinely capable suppliers, staying in control until they choose.

## [Company Identity] What problem does QuotesDone solve?
For buyers: sourcing multiple trustworthy, comparable quotes is slow and opaque, and once your number is out you get spammed and pressured. For sellers: most leads are irrelevant or already shopped around. QuotesDone solves both — the buyer posts once, Smart Engine structures the request and routes it only to suppliers who can genuinely do it, quotes come back structured, comparable and quality-checked, and everything stays anonymous with no off-platform contact until the buyer pays to reveal their chosen supplier.

## [Company Identity] Who is QuotesDone for?
Two sides. Customers (buyers) — UAE businesses and individuals who need to buy construction, fit-out, MEP and related products or services and want fast, comparable quotes without exposing themselves to spam. Suppliers (sellers) — vetted UAE contractors, fabricators, tradespeople and suppliers who want qualified, relevant job requests they can quote on.

## [Company Identity] What industries does QuotesDone support?
Construction and the built-environment services around it: building & fit-out / interior design, MEP (electrical, fire, HVAC, plumbing), aluminium & glass, joinery & custom furniture, flooring & tiling, false ceilings & gypsum, painting, waterproofing, landscaping & swimming pools, signage, CCTV & security systems, smart-home automation, solar, facilities management, cleaning, pest control, movers, AC maintenance and more — with new trades added automatically as suppliers register them.

## [Company Identity] What countries does QuotesDone operate in?
QuotesDone currently operates in the United Arab Emirates — all seven emirates — and is based in Dubai. Expansion to Saudi Arabia (KSA) is planned but not yet live.

## [Company Identity] What is the company's long-term vision?
To become the trusted procurement layer for the region — the default way buyers source and compare quotes across the GCC — expanding from the UAE into Saudi Arabia and beyond, and growing from single-job RFQs toward Smart-Engine-assisted procurement for larger, multi-trade projects.

## [Company Identity] What are the company's core values?
Anonymity & buyer control (no off-platform contact before reveal); Honesty (agents never over-promise or invent — answers are grounded in real data); Fair, quality-comparable quotes; Supplier respect (relevant matches only, seller-friendly economics); Trust & accountability (licensed entity, vetted suppliers, auditable and reversible Smart Engine).

## [Company Identity] How is QuotesDone different from competitors?
Four things: (1) Anonymity — buyers and sellers don't exchange contact details until the buyer chooses and pays to reveal, so no spam and no going around the platform. (2) Sharp Smart Engine matching — an Smart Engine reads the actual job and routes it only to suppliers who can genuinely do it, instead of blasting every lead to everyone. (3) Structured, comparable, quality-checked quotes, not messy free-text. (4) Seller-friendly economics — suppliers pay no commission on won jobs and start free; the buyer pays only on the quote they actually choose: a 3% reveal fee.

## [Company Identity] What makes QuotesDone trustworthy?
It is a licensed Dubai business (QuotesDone Technologies, DET E-Trader Licence No. 1633275). Suppliers are vetted (licence/KYC checks). Buyer and seller details stay masked until a paid reveal, protecting both sides. Quotes are structured and quality-gated so buyers compare like-for-like. The Smart Engine is governed and grounded — it answers from verified company and regulatory knowledge rather than guessing, sensitive actions are logged and reversible, and data is handled under UAE PDPL with security controls.

## [Company Policies] Supplier onboarding policy
Suppliers self-register or claim an existing listing, submit their trade licence and KYC documents, and are verified before going live (verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held). Approval is merit-based — there is no paid ranking or advertising. Registration is free for the first 1,000 registered suppliers, who remain free permanently; every supplier after them pays an annual subscription of AED 1,000, with no fixed start date.

## [Company Policies] Customer onboarding policy
Customers sign up with phone/email verification and accept the Terms & Conditions (a signed copy is stored). Posting requests, receiving and comparing quotes is free; a customer pays only the 3% reveal fee on the quote they choose to unlock. Customers remain anonymous to suppliers until they reveal.

## [Company Policies] Document policy
Documents (licences, profiles, catalogues, drawings, quotes, signed terms) upload up to 1 GB into access-controlled storage; large files are stored in full and auto-distilled for the Smart Engine. Originals are backed up to Dropbox in an organized tree. Files open only via short-lived signed links to authorized users; parties never see each other's private documents.

## [Company Policies] Privacy policy
Customer and supplier identities stay masked (suppliers appear as A/B/C to customers; customers are anonymous to suppliers) until a paid reveal. Personal data is used only to operate the marketplace, is never sold, and is handled under UAE PDPL with least-privilege access. Data-subject access and erasure requests are supported.

## [Company Policies] Data retention policy
Operational records and documents are retained while an account is active and for as long as needed to run the marketplace and meet legal, tax and dispute obligations; backups are kept in Dropbox. Erasure requests are honored under PDPL, subject to legal holds. Agents never hard-delete data — removal is a governed, human-approved action.

## [Company Policies] AI governance policy
The Smart Engine is oversight-first: agents surface, recommend and escalate, but never take irreversible action without founder approval. Low-confidence output is held for review; matching follows "a wrong match is worse than no match"; anonymity is enforced; and changes to agent knowledge are gated, reviewable and reversible (with rollback). Agents answer only from approved, grounded knowledge.

## [Company Policies] Knowledge governance policy
There is one canonical knowledge base. New or changed knowledge (categories, regulations, company facts) is staged and approved before it goes live; the Knowledge Curator monitors coverage and staleness. Agents cite official sources and stay brand-neutral — no manufacturer endorsements or recommended-brand lists.

## [Company Policies] Security policy
Access is deny-by-default with role-gated admin and least-privilege service access; all business logic runs server-side and secrets are never exposed. Data is encrypted in transit and at rest, documents are reached only via short-lived signed links, and the Security agent continuously monitors posture and risk. Each party sees only their own data.

## [Company Policies] Refund policy
Refunds are returned to the customer's original payment method via Stripe, and every refund is the founder's decision — none is automatic. The ladder runs from the customer's payment: if the revealed supplier has not responded by working day 3, our Customer Success Director chases them with the customer copied; still silent on working day 5, the founder is notified for the final call; no response to that and everything the customer paid (the 3% reveal fee) is refunded, with banks taking 7-14 working days to show it. The non-responding supplier then owes the refunded fee plus an AED 500 administrative fee and 12% per annum simple interest (the rate agreed in Supplier Agreement v14; 9% under v13 or earlier), except where such a charge is not permitted under UAE law, and is held from new matches until it is settled. Working days are Monday to Friday, UAE public holidays excluded. Other refund requests made within the 5-working-day refund window are reviewed and, if valid, refunded the same way.

## [Company Policies] Suspension policy
Suspension (matching blocked) is a reversible hold that stops new matches and quoting; a ban removes a party from the marketplace. Triggers include compliance lapses (e.g. an expired licence), repeated non-response, unpaid dues, or policy and behaviour violations. Actions are recorded with a reason and applied under admin authority; reinstatement follows remediation.

## [Company Policies] Commission policy
QuotesDone charges suppliers no commission on won jobs — suppliers keep 100% of the job value. The only amounts collected from suppliers are the annual subscription (AED 1,000/year, never applicable to the first 1,000 suppliers who registered, applying from the 1,001st registration onward with no fixed start date) and a non-response charge (the exact amount refunded to the customer, which is the 3% reveal fee, the payment processor fee QuotesDone could not recover (from Supplier Agreement v14) plus an AED 500 administrative fee and 12% per annum interest from the due date) if a supplier ignores a customer who paid to reveal them, applied except where not permitted under UAE law. The customer separately pays a 3% facilitation fee only when they choose to reveal a supplier's contact details.

## [Company Policies] Quality policy
Quotes must be itemized and detailed (no lump-sum guesses), so customers compare like-for-like and the comparison catches hidden costs, low-spec substitutions and missing items. Suppliers are vetted and rated on merit; agents are grounded in approved knowledge and continuously trained. The guiding principle throughout is accuracy over volume.

## [Customer] How does QuotesDone work?
You describe what you need (words, voice, a photo or a drawing). Our Smart Engine turns it into a clear brief and matches it to vetted suppliers who can genuinely do the job; they send anonymised quotes. You compare them and, when you pick one, pay a 3% reveal fee to unlock that supplier's identity and contact details.
(Audience: customer)

## [Customer] What happens after I submit an inquiry?
The Smart Engine structures your request and may ask a few quick questions to make it complete, then matches and invites the suppliers who can genuinely do it. You are notified as anonymised quotes come in, and you track everything in the app.
(Audience: customer)

## [Customer] How many suppliers receive my RFQ?
Only the suppliers who can genuinely fulfil your job — never a mass blast, and any number of them may quote: there is no fixed limit, and you see every quotation that arrives. The comparison report recommends the strongest three by value.
(Audience: customer)

## [Customer] How are suppliers selected?
The Smart Engine reads your actual job and matches by real capability and location, inviting only suppliers who can truly deliver it. A wrong match is treated as worse than no match, so irrelevant suppliers are filtered out.
(Audience: customer)

## [Customer] Can I choose which suppliers receive my inquiry?
The Smart Engine selects the right suppliers for you — this keeps the process fair, fast and fully anonymous, so you do not hand-pick from a directory.
(Audience: customer)

## [Customer] Is my identity hidden?
Yes — completely. Suppliers never see your name, phone, email, company or exact address; only the job and general area/emirate. Uploaded drawings are automatically redacted to remove identifying details.
(Audience: customer)

## [Customer] When is my identity revealed?
Never before you choose. Your details (and the supplier's) stay hidden until you pick a quote and pay the 3% reveal fee to unlock that one supplier.
(Audience: customer)

## [Customer] Can I cancel an inquiry?
Yes — there is a cancel button, so you can cancel an inquiry (before you reveal a supplier, at no cost — you only ever pay at the reveal step). We keep a record of cancellations, and if cancelling becomes a habit we will send you a polite, professional note explaining that repeated cancellations affect suppliers who take time to prepare quotes.
(Audience: customer)

## [Customer] Can I edit an inquiry?
Yes — you can edit an inquiry within 1 hour of submitting it. After that window, if something important changes, please create a new inquiry so suppliers quote the correct scope.
(Audience: customer)

## [Customer] Can I upload drawings?
Yes — you can add drawings, photos or a short video. Drawings are automatically redacted to strip any identifying details before suppliers see them.
(Audience: customer)

## [Customer] Can I upload BOQs?
Yes — you can attach a bill of quantities (BOQ), and the Smart Engine uses it to structure your request so suppliers price against your exact items.
(Audience: customer)

## [Customer] Can I invite my own supplier?
No — customers cannot invite their own suppliers. QuotesDone sources and vets the suppliers for you, which keeps every quote anonymous, fair and quality-checked.
(Audience: customer)

## [Customer] Can I request revisions?
There are no quote revisions. You compare the quotes as submitted; if none suit, you can decline them all at no cost and post a clearer inquiry. After you reveal your chosen supplier, you arrange any changes with them directly through the platform.
(Audience: customer)

## [Customer] Can I reject all quotations?
Yes — you are never obliged to accept any quote. You only pay when you choose to reveal a supplier, so declining every quote costs you nothing.
(Audience: customer)

## [Customer] Can I reopen an inquiry?
There is no reopen — simply create a new inquiry and suppliers will quote afresh.
(Audience: customer)

## [Customer] How long does the process take?
It depends on the job, but 3-5 working days is realistic to receive quotes, and you are notified as each one arrives. Once you reveal a supplier, they have 5 working days from your payment to respond: we chase them for you after 3 working days, our founder makes the final call on day 5, and if they are still silent everything you paid is refunded (banks take 7-14 working days to show it).
(Audience: customer)

## [Customer] Can I negotiate?
Yes — once you have revealed your chosen supplier, you can discuss scope, price and timing with them directly through the platform. Before reveal, everything stays anonymous, so you simply compare the quotes as submitted.
(Audience: customer)

## [Customer] What happens after selecting a supplier?
You pay the 3% reveal fee and that supplier's identity and contact details unlock for you. A transaction is created, the supplier is notified to respond, and you continue with them through the platform.
(Audience: customer)

## [Customer] How do I pay?
You pay the reveal fee securely by card or Apple Pay through our checkout. It is only charged when you choose to reveal a supplier.
(Audience: customer)

## [Customer] What are the platform fees?
As a customer you pay one fee: a 3% reveal fee on the value of the quote you choose (no cap), and only on that chosen quote. There are no other charges to you. Suppliers pay no commission on won jobs.
(Audience: customer)

## [Customer] Can I get a refund?
Yes, in defined cases — most notably if the supplier you revealed does not respond within 5 working days of your payment. We chase them after 3 working days with you copied; on day 5 our founder makes the final call, and if the supplier is still silent everything you paid is refunded to your original payment method. Every refund is the founder's decision — none is automatic — and banks take 7-14 working days to show it. Other refunds follow our Refund Policy.
(Audience: customer)

## [Customer] What if the supplier disappears?
If a revealed supplier does not respond within 5 working days of your payment (we chase them after 3 working days, and our founder makes the final call on day 5), you are refunded the reveal fee in full. That supplier then owes the refunded fee plus an AED 500 administrative fee and 12% per annum interest, and is blocked from new matches until it is settled.
(Audience: customer)

## [Customer] What if I receive poor quotations?
Every quote must pass a quality bar before it reaches you, and the Smart Engine coaches suppliers to be complete and itemised. If you are still not satisfied, you can decline them all at no cost — you only pay when you choose to reveal a supplier.
(Audience: customer)

## [Customer] What if I made a mistake?
You can edit your inquiry within 1 hour of submitting it to fix a mistake. Past that window, cancel the inquiry and create a corrected one — cancelling before reveal costs nothing.
(Audience: customer)

## [Customer] What if my project changes?
If your project changes within 1 hour of submitting, edit the inquiry directly. Otherwise create a new inquiry with the updated scope so suppliers quote accurately. If it changes after you have revealed a supplier, arrange the changes with them directly through the platform.
(Audience: customer)

## [Customer Intelligence] How is customer health measured?
A 0-100 composite: engagement 25% + satisfaction 30% + progress 25% + service 20%. Engagement = recency + number of RFQs; satisfaction = review ratings minus disputes/bad-reviews/strikes; progress = share of active RFQs that advanced (got quotes/revealed/won); service = response speed minus disputes. It also outputs a risk tier.
(Audience: internal)

## [Customer Intelligence] How is customer lifetime value calculated?
v_customer_ltv now computes it: revenue-to-date from paid reveal fees per customer, plus inquiries, completions, last activity and a value tier (none/low/medium/high). Honest note: this is realised revenue-to-date + engagement, not a forward-projected/trained lifetime-value model — a predictive LTV is the next step.
(Audience: internal)

## [Customer Intelligence] How is repeat-business probability estimated?
Proxied today by the customer_health engagement and progress signals (recent activity, multiple RFQs, completions) and dormancy flags — not a trained propensity model. A dormant, low-engagement customer is treated as low repeat-likelihood and targeted for re-engagement.
(Audience: internal)

## [Customer Intelligence] How are fraudulent customers detected?
Through disputes/refund patterns (transactions), bad reviews, chat strikes, the 18+ and verification gates at signup, duplicate-account checks, and fraud_flags/v_fraud_score. High-risk customers surface in the customer_health risk tier and to the Security/Fraud checks.
(Audience: internal)

## [Customer Intelligence] How are inactive customers re-engaged?
The Customer Success agent flags dormant customers (no activity for 45+ days) and stalled RFQs and proposes re-engagement (reminders/outreach) as oversight cards — drafted for approval, not auto-blasted.
(Audience: internal)

## [Data Governance] Who owns each dataset?
The founder is the data owner/controller, and a data_owner_registry table now records, per table, the owner, the steward agent, a data classification (PII/financial/knowledge/security/secret) and notes — starting with the core tables. Operationally each domain agent stewards its tables. Changes to the registry are captured in the append-only audit trail.
(Audience: internal)

## [Data Governance] Who may modify a dataset?
Access is RBAC-gated (roles/user_roles/role_permissions) with RLS deny-by-default; service-role backend functions perform writes under oversight. Sensitive changes require founder approval.
(Audience: internal)

## [Data Governance] Who may delete data?
Deletion is tightly constrained: storage has a delete-guard, the audit log is append-only, and record deletion is a governed, founder-approved action — not something agents do. The default is retain-and-protect (PDPL erasure is handled through a proper flow).
(Audience: internal)

## [Data Governance] Who approves schema changes?
The founder. Schema changes ship as forward-only migrations, applied and verified under oversight; any change to roles/permissions/critical config is now recorded in security_audit_log.
(Audience: internal)

## [Data Governance] How are migrations reviewed?
They are authored, applied and verified live (smoke tests, re-queries) under founder oversight, and listed in the migration history. Honest: there is no separate multi-reviewer PR gate yet (single founder + agent + verification).
(Audience: internal)

## [Data Governance] How is data lineage tracked?
Partially: backups + manifests, the audit trail for governance tables, source/citation on knowledge (kb_chunks), and source tags on records (e.g. lead source). Honest gap: there is no end-to-end automated data-lineage/catalog tool — lineage is reconstructable from sources + audit, not a dedicated lineage graph.
(Audience: internal)

## [Data Governance] How are duplicate records merged?
Dedup checks exist at key points (supplier directory scoping, one-account-per-email, backup dedupe keys, quote-set signatures). Honest: there is no universal master de-dup/merge engine across all entities — it is per-domain checks.
(Audience: internal)

## [Data Governance] How is master data governed?
Canonical reference data lives in config tables (config-as-data) and curated knowledge (company_faq single source of truth, agent_knowledge), changed only under approval with the audit trail. Honest: there is no formal MDM platform — governance is config-as-data + approval + audit.
(Audience: internal)

## [Data Governance] Can a person request access to or erasure of their personal data (UAE PDPL)?
Yes. Requests are captured in pdpl_requests and handled by three governed functions. fn_pdpl_export(email) compiles everything held about a subject across customers, inquiries, supplier leads, notifications, outreach, verifications and AI-usage logs (access/portability). fn_pdpl_erase_plan(email) is a dry run showing exactly how many rows in each table would change. fn_pdpl_redact(request_id) performs the erasure - but only after the request is marked approved, and it anonymises personal fields (name, phone, email, date of birth) rather than hard-deleting, so legally-required financial and audit records survive. Each redaction writes a high-severity security event. The email do-not-contact suppression list is deliberately retained so an erased person is not accidentally re-contacted.
(Audience: internal)

## [Data Security] Which encryption algorithms are used?
QuotesDone relies on the strong, industry-standard encryption provided by its managed infrastructure. Data at rest is encrypted with AES-256 (Supabase, backed by AWS; likewise Dropbox for document backups); data in transit is protected by TLS (HTTPS, TLS 1.2+). Passwords are one-way hashed with bcrypt by the managed auth service. We do not roll our own cryptography — we use the vetted algorithms these platforms provide.
(Audience: internal)

## [Data Security] Is encryption applied at rest?
Yes. The database, file storage and backups are encrypted at rest by the managed platform (AES-256 on AWS-backed Supabase). Uploaded documents in Storage and the Dropbox backup copies are likewise encrypted at rest. No sensitive data sits on disk in plaintext.
(Audience: internal)

## [Data Security] Is encryption applied in transit?
Yes, everywhere. All traffic — browser to site (Vercel/HTTPS), app to backend (Supabase over TLS), and backend to third parties (Stripe, Twilio, Resend, Dropbox, the LLM gateway) — travels over TLS/HTTPS, and signed file links are HTTPS-only. There are no plaintext network paths.
(Audience: internal)

## [Data Security] How are secrets managed?
All backend secrets live in an access-controlled secrets table protected by row-level security with no read policies — so only the backend's service role can read it; no customer, supplier, admin session or anonymous client can. Platform-level secrets (like the service-role key) are held in the managed Edge Function secret store. Secrets are read server-side at call time and never shipped to the browser.
(Audience: internal)

## [Data Security] How are API keys protected?
Third-party API keys (Stripe, Twilio, Resend, Dropbox, the LLM gateway, Meta) are stored only in that server-side secrets table and used only inside Edge Functions. They are never embedded in the frontend, never sent to the client, and never written to logs or URLs — and can be rotated centrally without code changes.
(Audience: internal)

## [Data Security] How are database credentials stored?
The database is managed by Supabase; the privileged service-role key used by Edge Functions is held in the platform's secret store (an environment secret), not in code or the repository, and connections run over TLS. The browser never holds database credentials — it only calls Edge Functions, which connect on its behalf under strict checks.
(Audience: internal)

## [Data Security] How are environment variables managed?
Runtime configuration and secrets for Edge Functions are provided through the platform's managed environment/secret store (e.g. the Supabase URL and service-role key), injected at runtime — not committed to source control and not exposed to the client. Application-level keys are additionally kept in the RLS-protected secrets table.
(Audience: internal)

## [Data Security] How are backups encrypted?
Both layers are encrypted. The database's automated backups are encrypted at rest by the managed platform. The organised document backup to Dropbox is uploaded over HTTPS and stored encrypted at rest by Dropbox (AES-256), inside the company's own controlled account. The backup process only ever reads and uploads — it never weakens access on the originals.
(Audience: internal)

## [Data Security] How is sensitive data masked?
Anonymity is core: suppliers appear to customers only as A/B/C, and customers stay anonymous to suppliers until a paid reveal, so identities are masked by default. Documents open only through short-lived signed links to authorised users, uploaded drawings can be redacted before sharing, secrets are never returned to clients, and each party sees only their own data. PII is minimised and never placed in URLs or logs.
(Audience: internal)

## [Database Security] Which database is used?
PostgreSQL (v17), managed by Supabase on AWS. It is the single source of truth for all platform data — accounts, inquiries, quotes, transactions, the knowledge base, agent state — with Postgres's relational integrity, transactions and security, plus extensions for scheduling (pg_cron), outbound calls (pg_net), full-text search and vector similarity.
(Audience: internal)

## [Database Security] How is Row Level Security implemented?
RLS is enforced in the database itself, beneath the application, and is deny-by-default: with RLS on and no permissive policy, no client can read or write a row. The public apps use restricted keys subject to RLS, so a browser can never reach data it is not entitled to; all privileged work goes through Edge Functions using the service role, which then apply their own role and ownership checks. RLS is the last line of defence even if an app-layer check were missed.
(Audience: internal)

## [Database Security] Which tables use RLS?
All of them — every one of the platform's public tables (currently 164 of 164) has RLS enabled, a 100% deny-by-default posture. Access is granted only through the backend's service role or an explicit policy, never by default.
(Audience: internal)

## [Database Security] How are SQL injections prevented?
User input never becomes SQL. All access uses parameterised queries (the Supabase client and SQL functions bind values as parameters, not string concatenation), so input is treated as data, not code. Business logic lives in typed SQL functions and server-side Edge Functions; the browser never composes queries, and the Smart Engine agents do not write raw SQL against production. RLS provides defence-in-depth on top.
(Audience: internal)

## [Database Security] How are database migrations managed?
Schema changes are applied as versioned, tracked migrations (each recorded with a name/timestamp in a migrations table) rather than ad-hoc edits, so the schema history is auditable and reproducible. Changes move forward through new migrations (and are reversed by a further migration), keeping every environment consistent.
(Audience: internal)

## [Database Security] How is referential integrity maintained?
By the database: relationships use foreign keys, and data quality is enforced with constraints — primary keys, unique constraints (e.g. one account per email, one match per supplier+inquiry), not-null and check constraints — so orphaned or malformed records are rejected at write time. Multi-step changes run inside transactions, so they either fully apply or fully roll back.
(Audience: internal)

## [Database Security] How are audit logs stored?
In dedicated tables plus the platform's own logs. The approval/action ledger records each sensitive decision (who, when, outcome); agent runs, matching/routing decisions, cancellations, notifications, backups and money events each write to their own tables with timestamps; and Supabase retains database and function logs at the infrastructure level. Together these give a durable trail of what happened and who authorised it.
(Audience: internal)

## [Database Security] How are deleted records handled?
Conservatively and under oversight. The Smart Engine agents never hard-delete data on their own — permanent deletion is a governed, human-approved action. Most removals are status changes (cancelled, banned, waived, blocked) that preserve history, and even Storage has a guard that blocks accidental object deletion. The default is to retain and mark, not erase.
(Audience: internal)

## [Database Security] Is soft delete implemented?
Yes, broadly. Business records are retired by status/flag rather than physical deletion — inquiries marked cancelled, suppliers banned or matching-blocked, dues waived, records archived — so nothing needed for history, audit, disputes or tax is lost. True erasure is reserved for explicit, approved cases (e.g. a data-subject request under PDPL, subject to legal holds).
(Audience: internal)

## [Database Security] How is data archived?
Through retention plus backup: completed items (e.g. closed RFQs) can be archived rather than deleted, documents and generated records are mirrored to the organised Dropbox backup tree, and the database's managed backups provide point-in-time recovery. Records are kept while an account is active and as long as legal, tax and dispute obligations require, then handled per the data-retention policy — archived and recoverable, not lost.
(Audience: internal)

## [Decision Engine] How is supplier score calculated?
From supplier_health — a 0-100 composite (quality 30% + compliance 30% + response 20% + retention 20%) — plus supplier_perf (perf_score derived from matched/quoted/won and ratings). This drives ranking and eligibility gates.
(Audience: internal)

## [Decision Engine] How does the engine prioritise an RFQ?
RFQs are handled in arrival order behind a completeness gate (rfq_ready/completeness): an incomplete RFQ is clarified first (run_rfq_clarify) rather than dispatched to weak matches. There is no paid priority — urgency is served by clarify-then-dispatch.
(Audience: internal)

## [Decision Engine] How does the engine score quotation quality?
Quotes carry quality/structured flags and are enforced to be itemised at entry; the comparison weighs line detail, spec compliance/deviations, completeness, lead time and terms — not supplier identity (anonymised A/B/C).
(Audience: internal)

## [Decision Engine] How are business rules weighted?
Rules live as config-as-data (collections_config, pricing_config, feature_flags) and as explicit formula weights — the ranking boosts and the health composite (30/30/20/20). All are tunable under founder approval with the audit trail.
(Audience: internal)

## [Decision Engine] How are conflicting rules resolved?
Oversight-first and conservative: on conflict the engine defaults to withhold/escalate rather than force an action (a wrong action is worse than none), and for knowledge, official sources take precedence. Unresolved conflicts go to human review.
(Audience: internal)

## [Decision Engine] How are confidence scores computed?
Matching uses retrieval similarity plus an adjudication confidence recorded on agent_actions.confidence; knowledge uses v_kb_confidence. These are heuristic/threshold-based signals, not calibrated probabilities.
(Audience: internal)

## [Decision Engine] How are explanations generated?
Every agent action card carries a plain-language reasoning summary naming the rules and knowledge it used, plus a click-through to the source record; comparisons show per-supplier rationale. Explanations are traceable, not black-box.
(Audience: internal)

## [Decision Logic & Explainability] Why was this supplier selected?
A supplier is selected only when the matching engine judges they can genuinely do the actual job. After building an anonymised, priceable brief, the engine shortlists candidates by combining meaning-based (vector) and keyword search over supplier capabilities, then an adjudicator model evaluates each shortlisted supplier against the real scope. A supplier is invited only if their verified capabilities (category, services, products, coverage, authorizations) match what the job requires. The reason for each selection is recorded.

## [Decision Logic & Explainability] Why was not another supplier invited?
Because the engine was not confident they truly fit — the rule is "a wrong match is worse than no match." A supplier is left out if their capabilities do not cover the scope, they are in a different (even adjacent) trade, they are unverified/suspended/licence-expired, or a fan-out cap was reached after better-fitting suppliers were chosen. It is a fit decision, not a judgement of their overall quality, and the exclusion reason is logged.

## [Decision Logic & Explainability] How is the supplier match score calculated?
It is a two-stage judgement, not one opaque number. First, retrieval ranks suppliers by how closely their capability profile matches the brief (semantic similarity plus keyword overlap). Second, an adjudicator model scores each shortlisted supplier on whether they can actually deliver the specific scope — trade fit, required products/brands, coverage area, authorizations, compliance — and keeps only genuine fits. Precision is prioritised over volume.

## [Decision Logic & Explainability] How is the RFQ completeness score determined?
Intake turns the request into a structured brief and checks it against that category's qualification playbook — the questions needed to scope that trade (dimensions, materials, quantities, emirate/site, authority requirements). Completeness reflects how many essential fields are present. It is marked ready to match only when complete enough for suppliers to quote accurately.

## [Decision Logic & Explainability] Why did AI request additional information?
Because a detail essential to an accurate quote was missing or ambiguous. The playbook flags the gap (unspecified material grade, missing measurements, unclear authority requirement) and the agent asks rather than guessing — guessing produces misleading quotes. Requesting information protects both sides and improves match and quote quality.

## [Decision Logic & Explainability] Why was a quotation rejected?
Quotes must be complete and itemized. One lacking required detail (line items, scope, pricing basis) is held as an incomplete draft rather than accepted, and incomplete drafts are excluded from the customer's comparison. This keeps every quote comparable like-for-like and stops vague lump sums or hidden-scope quotes from misleading the customer.

## [Decision Logic & Explainability] How are recommendations ranked?
In the comparison, recommendations are ranked by best match to what the customer asked for at the lowest price — not simply cheapest or highest-rated. The engine checks each quote against the requested specification and items, flags spec deviations and missing scope, and ranks a top-3 with trade-offs stated plainly ("best spec match and cheaper, but longer delivery"). Supplier merit informs, but genuine fit and value lead.

## [Decision Logic & Explainability] What evidence supports this recommendation?
Every recommendation is grounded in checkable inputs: the customer's actual brief and item list, the content of each submitted quote (scope, materials, price, lead time, warranty, terms), the supplier's verified capabilities, and the relevant UAE regulatory knowledge. Agents cite these and never invent specs or identities — if something is not stated in a quote, it is flagged to confirm rather than assumed.

## [Decision Logic & Explainability] Which regulations or standards influenced the decision?
Where a request touches a regulated system (electrical/DEWA, fire/Civil Defence, security/SIRA, signage/Municipality, free-zone Trakhees/DDA), the relevant UAE authority and standard are pulled from the knowledge base and applied — in qualification (which approvals a job needs) and in comparison (flagging quotes that ignore or under-spec a code). Agents point to the official source of record and frame compliance as something to verify, never asserting non-compliance as fact.

## [Decision Logic & Explainability] What factors affect confidence scores?
Confidence rises with clear, complete, verified inputs and falls with ambiguity or thin data — a vague or incomplete brief, a supplier with sparse capability information, conflicting or missing quote details, or a newly-seen category. Low confidence makes the engine more conservative (it excludes rather than guesses) and, for anything sensitive, routes the decision to a human.

## [Decision Logic & Explainability] When does AI escalate to a human?
The Smart Engine is oversight-first: it surfaces, recommends and escalates but never takes an irreversible or sensitive action on its own. It escalates when confidence is low; when a decision touches money, publishing, access, suspensions or legal matters; when new knowledge needs approval before going live; or when a case falls outside its grounded knowledge. A human reviews and approves before it proceeds.

## [Decision Logic & Explainability] What would change the recommendation?
Recommendations update as inputs change. New or corrected request details, additional or revised quotes, updated supplier capabilities or compliance status, a change in the customer's stated priorities, or updated regulatory knowledge can all shift the ranking. Because every decision is grounded in current data and its reasoning is recorded, the "why" can always be revisited when the facts change.

## [Development Standards] What are the coding standards?
Backend logic is TypeScript on Deno (Edge Functions) with SQL for the database; conventions in force include service-role-only functions gated by inbound_secret, row-level-security deny-by-default, and consistent brand terminology (Smart Engine, buyers/sellers). Syntax is validated at deploy time (the Edge Function bundler rejects broken code; page JavaScript is checked with node --check before publish). Honest gap: there is no formal written style guide or automated linter enforced in a pipeline yet.
(Audience: internal)

## [Development Standards] What is the branching strategy?
Honest: there is not a formal git-flow today. Changes are applied to the live Supabase project through forward-only migrations, and Edge Functions are versioned by the platform on each deploy. Supabase's dev-branch feature is available but not part of a routine workflow. A proper feature-branch + staging model is a sensible step once more than one engineer is involved.
(Audience: internal)

## [Development Standards] What is the pull request process?
Honest: there is no formal pull-request / merge-request workflow at present. The gate is the founder-oversight model — changes are proposed, the founder approves, then they are applied. A real PR process with required approvals should be adopted as the team grows.
(Audience: internal)

## [Development Standards] What are the code review requirements?
Honest: there is no second-engineer peer review today (founder + Smart Engine). Review consists of founder oversight plus the agent's own verification — syntax checks, live smoke tests, and re-querying results after each change. Formal peer code review is a planned addition for when there is an engineering team.
(Audience: internal)

## [Development Standards] What are the testing requirements?
Honest: there is no automated test suite or CI test gate yet. Each change is verified manually with live smoke tests — e.g. node --check on page scripts, calling the deployed function against real data, re-querying the database, and built-in self-test operations (as used for the backup engine). This is a known gap; an automated test suite with a CI gate is recommended.
(Audience: internal)

## [Development Standards] What is the deployment approval process?
Oversight-first: nothing irreversible or sensitive ships without founder approval. Mechanically, a release is an Edge Function deploy and/or a site_deploy re-run, each verified immediately afterward (function response checked, site regression-checked). There is no separate change-advisory board or release manager — the founder is the approver.
(Audience: internal)

## [Development Standards] What is the release versioning approach?
Edge Functions carry platform version numbers (v1, v2, and so on), and the database advances through forward-only migrations that are individually listed. Honest gap: there is no formal semantic app version, git tags, or a maintained CHANGELOG — the per-feature session logs written to the outputs folder currently serve as the informal change record.
(Audience: internal)

## [Development Standards] What is the rollback procedure?
Layered: an Edge Function is rolled back by redeploying the previous version; the static site can be reverted instantly because Vercel keeps immutable deployments and lets a prior one be promoted; prompts have a built-in fn_prompt_rollback. Database changes are rolled back by forward-fix migrations plus, if needed, restoring from the daily managed backup (PITR is on the planned list). Honest note: the database has no automatic transactional down-migrations — recovery is forward-fix or restore-from-backup.
(Audience: internal)

## [Development Standards] What are the documentation requirements?
Every feature gets a written session log in the outputs folder (the established, verified pattern), the company-knowledge FAQ documents how the platform actually behaves, and llms.txt describes the site for machines. Honest gap: there is no formal architecture document, repo README set, or operational runbook library yet (the incident-response runbook is already on the flagged-gaps list).
(Audience: internal)

## [Documents] Which file types are accepted?
Common formats: images (JPG, PNG), PDFs, and CAD drawings (DWG, DXF — automatically converted so they can be read). You can upload photos, drawings, bills of quantities, and quotation PDFs.

## [Documents] Maximum file size?
There is no small size limit — you can upload large drawings and documents (up to about 1 GB). Very large files upload fastest as PDFs or the key sheets, which also gives the quickest analysis.

## [Documents] How are files stored?
In private, access-controlled cloud storage that is not publicly accessible. Files are served only to your own account through short-lived signed links.

## [Documents] How are versions managed?
Documents are version-controlled — an update creates a new version rather than overwriting the history, so there is a traceable record. Requests (RFQs) are also versioned when they change.

## [Documents] How are drawings handled?
When you upload a drawing, the Smart Engine reads it to draft a bill of quantities and structure your brief, and it automatically redacts identifying details before any supplier sees it — keeping you anonymous. Your original files stay private to you.

## [Documents] How are PDFs analysed?
The Smart Engine extracts the content of PDFs — drawings, bills of quantities, or your own quotation — to build a clean, structured brief or quote, pulling out line items and specifications and stripping identity or prices where needed for anonymity.

## [Documents] How are documents archived?
Completed requests and their documents are archived to durable off-site storage on a schedule, kept for record-keeping and retrievable later. A Document Controller tracks the inventory and retention.

## [Executive KPIs] What KPIs are shown daily to the CEO?
The daily founder brief (fn_founder_brief, ~08:30 Dubai) shows pipeline, pending approvals, hot leads, supply gaps and BD, alongside the strategy KPIs: cash, monthly_burn, runway_months, revenue_30d, margin_pct, active_suppliers_90d, top_supplier_share_pct, under_supplied_categories and open_risks with the top risk.
(Audience: internal)

## [Executive KPIs] How is company health calculated?
As a roll-up across domains: finance (runway, burn, margin), supplier and customer health, operations health and security posture — surfaced in the executive command center and summarised in strategy_kpis. Honest: it is a composite of the domain scores, not a single formally-weighted index.
(Audience: internal)

## [Executive KPIs] How is overall marketplace health calculated?
From liquidity (demand versus approved-supplier coverage), supplier and customer health, response/fulfilment signals, and under-supplied categories — the same inputs the Marketplace Intelligence views expose.
(Audience: internal)

## [Executive KPIs] How are AI health and confidence reported?
Through the AI Trainer (per-agent quality), v_ai_quality_proxy (30-day human override rate), the latest eval scores (v_eval_latest), and knowledge_kpis (accuracy_pct, freshness_pct). Together these give a health-and-confidence read on the Smart Engine.
(Audience: internal)

## [Executive KPIs] How are strategic risks summarized?
strategy_risks scores each risk as likelihood x impact with a mitigation, source and status; the highest becomes top_risk / top_risk_score in strategy_kpis, and fn_strategy_ai + the weekly board report summarise them for the founder.
(Audience: internal)

## [Executive KPIs] How are forecasts generated?
The finance forecast (finance_kpis + fn_finance_ai) projects revenue, cash and runway from recent trends and known inflows/outflows. Honest note (2026-07-11): a true ML/statistical forecast is not feasible yet — there is essentially no transaction history to learn from (one paid reveal to date), so a trend-and-assumption forecast is the correct approach until real revenue history accumulates. It will graduate to a proper statistical model once there is enough data.
(Audience: internal)

## [File Security] Which file types are allowed?
The platform accepts the business documents and images it needs — trade licences, VAT/insurance/ISO certificates, company profiles and catalogues, drawings, and quote files — as PDFs and images (JPEG/PNG), with drawings/CAD supported in the relevant flow. The supplier-documents store is explicitly restricted to PDF and image types; the drawing and quote stores accept the formats those flows use. It is a document-and-image intake, not a general file host.
(Audience: internal)

## [File Security] Which file types are blocked?
Anything outside the expected document/image/drawing set. Executables, scripts and similar active content are not part of the accepted types and have no path to run — uploads are treated purely as documents to store, render or read, never as programs. The supplier-docs bucket enforces an explicit allow-list (PDF/JPEG/PNG) at the storage layer.
(Audience: internal)

## [File Security] Maximum upload size?
Up to 1 GB per file. The document, drawing and quote stores are set to a 1 GB limit (raised so large catalogues and company profiles are accepted), and the project-wide ceiling matches. Very large files upload directly to storage via a signed upload URL rather than through the app, so size does not strain the request path.
(Audience: internal)

## [File Security] Are uploaded files scanned for malware?
Yes — uploaded files are scanned. A daily job (vt_scan) computes each new file's SHA-256 and checks it against VirusTotal's known-malware database in a privacy-safe way — the file contents are never uploaded, only the hash is checked — across quote files, drawing files, supplier documents and receipts. A malicious hit raises a high-severity security event, a high-risk approval card for the founder, and an email alert, and the file is flagged for immediate removal. This runs on top of structural protections: files sit in isolated private buckets, are never executed, are only read/rendered or distilled by the Smart Engine, are served only through short-lived signed links to authorised users, and the supplier store is limited to PDF/image types. Honest nuance: this is known-malware hash lookup, so a brand-new/never-seen file returns "unknown" rather than a verdict — full novel-file sandboxing/content analysis is not yet in place and is the natural next enhancement.
(Audience: internal)

## [File Security] How are PDFs processed?
PDFs are stored privately and processed by conversion, not execution: pages are rendered to images so the Smart Engine can read a licence, distil a catalogue or extract a bill of quantities, and generated documents (reports, letters, comparisons) are produced through the branded PDF pipeline. They open for authorised users only via time-limited signed links. PDFs are never run — only rendered and read.
(Audience: internal)

## [File Security] How are drawing files handled and secured?
Drawings live in a private store. They can be converted (CAD/large formats normalised), read to extract a structured bill of quantities, and — importantly — redacted before being shared with suppliers, so a customer's identifying details on a drawing are stripped to preserve anonymity. Very large drawings upload directly to storage and are linked. Suppliers only ever see the redacted, task-relevant version through a signed link.
(Audience: internal)

## [File Security] How are file permissions managed?
Every bucket except public brand/site assets is private, with row-level security on the storage layer. No file is world-readable; the only way to open one is a short-lived signed URL minted by a gated Edge Function after it checks the caller's role and ownership. A customer reaches only their own files, a supplier only theirs, admins through audited endpoints — nobody can guess or share a durable link to someone else's document.
(Audience: internal)

## [File Security] How are archived files protected?
Archived and backup copies inherit the same protections: private, access-controlled storage plus the company's own Dropbox backup, both encrypted at rest and reached only over HTTPS. The backup process is read-and-upload only and never weakens access on the originals, and storage has a guard blocking accidental object deletion. Access to archives is the same signed-link, role-checked path as live files.
(Audience: internal)

## [File Security] How is Dropbox secured?
Server-side only: it authenticates with a stored OAuth refresh token (in the RLS-protected secrets table, never in the client), is scoped to the QuotesDone backup folders, and communicates over HTTPS to Dropbox, which encrypts data at rest. It only ever reads/indexes and uploads — never deletes anything in Dropbox — and writes into the company's own controlled account. Customers and suppliers have no access to it.
(Audience: internal)

## [File Security] How are deleted files handled?
Cautiously. Storage has a protection that blocks direct deletion of objects, so files are not casually or accidentally removed; the Dropbox backup never deletes originals; and removals of stored documents are governed, human-approved actions, not something an agent does. Where a genuine erasure is required (e.g. an approved PDPL data-subject request, subject to legal holds), it is handled deliberately through the proper flow — the default is retain-and-protect.
(Audience: internal)

## [Financial] What is the 3% fee?
The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission.

## [Financial] When is it charged?
Only at the reveal step — when a customer picks a quote and chooses to unlock that supplier. Nothing is charged for posting a request, receiving quotes, or comparing them; you pay only when you decide to proceed with a supplier.

## [Financial] How do invoices work?
When a customer pays a reveal fee, an invoice for that fee is generated automatically and available in the app. Suppliers who are liable for the annual subscription (that is, those outside the first 1,000 registered) receive an invoice for it when it falls due. All invoices are issued by QuotesDone Technologies (see the VAT note below on current tax treatment).

## [Financial] Which payment methods are accepted?
Payments are made securely by card or Apple Pay through our Stripe checkout — both the customer reveal fee and the supplier annual subscription.

## [Financial] How are VAT invoices generated?
QuotesDone Technologies is not currently VAT-registered, so invoices are issued without VAT and without a TRN. If and when the company becomes VAT-registered, VAT will be applied and shown on invoices together with the TRN.

## [Financial] How are refunds processed?
Refunds are returned to your original payment method through Stripe and every one is approved by our founder — none is automatic. The clearest case is a silent supplier: if the supplier you revealed does not respond within 5 working days of your payment (we chase them after 3 working days, and the founder makes the final call on day 5), everything you paid is refunded. Banks usually take 7-14 working days to show the refund. Other refund requests made within the refund window are reviewed the same way.

## [Financial] How are commissions collected?
There are no commissions — suppliers keep 100% of their won jobs. The only amounts ever collected from suppliers are the annual subscription (AED 1,000/year, which never applies to the first 1,000 suppliers who registered and has no fixed start date — it applies from the 1,001st registration onward) and any non-response fee. Both are paid on the supplier portal via Stripe. Unpaid amounts are followed up and the account is paused from new matches until they are settled.

## [Financial] How are overdue payments handled?
We send reminders first. If an amount due — a supplier subscription or a non-response fee — stays unpaid, the account is paused from receiving new matches until it is settled on the portal.

## [Future Vision] Why is QuotesDone building AI employees?
QuotesDone is built AI-first: rather than scaling by adding headcount, it runs on a team of Smart Engine agents — matching, supplier and customer success, finance, marketing, knowledge, legal, security and operations. This lets a lean UAE business deliver enterprise-grade service around the clock — faster, consistent, and grounded in verified knowledge. The agents are oversight-first: they surface, recommend and escalate, but a human approves anything sensitive or irreversible. The goal is leverage and quality, not replacing human judgment.

## [Future Vision] What is the long-term roadmap?
The near-term focus is depth in the UAE B2B market: sharper matching, more suppliers with rich verified capabilities, and continuously improving quote quality and comparisons. Beyond that, the direction is broader category coverage, deeper supplier and customer tooling, stronger analytics, and — as demand justifies — integrations (e.g. ERP/procurement) and possibly a partner API. Roadmap items are pursued deliberately and launched only when genuinely ready; we prefer to under-promise and over-deliver.

## [Future Vision] Will the platform expand internationally?
The immediate priority is to win the UAE market and prove the model. The platform is built to be adaptable — its knowledge base, categories and compliance rules are structured so new jurisdictions can be added — so international expansion (starting with the wider GCC) is a natural future direction once the UAE foundation is strong. It is not live yet, and any new market would launch with locally-grounded regulatory knowledge, not a copy-paste.

## [Future Vision] Will more industries be supported?
Yes — the platform is designed to grow its category coverage. When a supplier registers a trade QuotesDone has not seen, the Smart Engine can stand up a new category agent with the right qualification questions and knowledge (with founder approval before that knowledge goes live), so coverage expands without losing quality. Over time this extends across more construction, fit-out, MEP, facilities and related B2B trades, and into adjacent industries as demand appears — always grounded in real, verified requirements for each field.

## [Future Vision] How will AI continue to evolve?
The Smart Engine improves continuously and safely: agents are graded and trained on real outcomes, their knowledge is curated and kept current with the latest UAE regulations, and their prompts and models can be upgraded, reviewed and rolled back under governance. As underlying AI models improve, QuotesDone adopts them where they raise accuracy — but the oversight-first principle stays fixed: more capability, always under human control, always grounded in verified knowledge rather than guesswork. The aim is an AI workforce that gets sharper over time while staying trustworthy.

## [Governance] Who owns each module?
Honest: the founder is the ultimate owner and accountable party for every module. Operationally, each domain is run by a dedicated Smart Engine agent under oversight — Finance AI, Supplier Success, Customer Success, Marketing AI, Legal AI, Security AI, Operations AI, Knowledge Curator, Document Controller and Executive Assistant. So ownership means the founder is accountable and a named agent operates each domain day-to-day; there are no separate human module owners yet.
(Audience: internal)

## [Governance] Who approves production deployments?
The founder. There is no change-advisory board or separate release manager — under the oversight-first model, the founder is the single approver, and every deploy is verified immediately afterward.
(Audience: internal)

## [Governance] Who approves security changes?
The founder, given their sensitivity. Changes to secrets, row-level-security policies or service-to-service gating are proposed with rationale and applied only on founder approval; secrets remain service-role-only and are never exposed to clients.
(Audience: internal)

## [Governance] Who approves AI prompt changes?
Prompt changes run through formal governance: a new version is drafted, benchmarked and evaluated against saved cases (prompt_versions, prompt_eval_runs, prompt_benchmarks), then promoted via fn_prompt_approve_draft, with fn_prompt_rollback always available. The founder approves promotion; the auto-promote/rollback rule operates only within oversight thresholds.
(Audience: internal)

## [Governance] Who approves knowledge base updates?
The founder. Company-knowledge answers are drafted and only become live once approved — the fn_company_faq_sync trigger compiles only approved rows into the agents' _global knowledge, and ingested authority documents are reviewed and promoted on approval. Nothing reaches the agents or the public FAQ without that approval step.
(Audience: internal)

## [Governance] How are critical business rules managed?
Critical rules live as data in config tables, not hard-coded — for example collections settings (interest_pa, admin_fee, escalate_working_days), the 3% reveal fee, and the AED 1,000 annual subscription. This keeps them tunable and auditable, and changes go through founder approval. Honest gap: edits to these config tables are not yet versioned with a formal change-log — adding one is a sensible improvement.
(Audience: internal)

## [Governance] How are feature flags governed?
Flags such as sms_enabled switch capabilities on and off; they live in config/settings tables and are changed only under founder oversight. Honest note: these are simple configuration booleans, not a dedicated feature-flag service with targeting, gradual rollout and its own audit trail — sufficient at current scale, upgradeable later.
(Audience: internal)

## [Governance] How are emergency changes handled?
Oversight-first still applies, but urgent fixes — disabling a misbehaving cron, voiding a wrongful charge, blocking a supplier — can be made quickly by the founder and are recorded in the session logs and agent action cards. A recent real example is the commission-engine fix: the discrepancy was flagged, the founder decided the policy, the change was applied and voided the wrongful charge, and it was logged. Honest gap: there is no formal documented emergency-change / break-glass runbook yet (this ties to the incident-response runbook already on the flagged list).
(Audience: internal)

## [Incident Response] What constitutes a security incident?
Any event that threatens the confidentiality, integrity or availability of the platform or its data: unauthorised access or a data exposure, a compromised account, a leaked secret or API key, payment fraud or tampering, malicious file/content, unexpected data changes, or an outage with security impact. Suspicious signals — abnormal access patterns, repeated auth failures, a failed signature check, an unexpected privileged change — are treated as potential incidents to investigate.
(Audience: internal)

## [Incident Response] Who is notified (incident)?
The founder is the incident owner and is alerted immediately (the platform can raise a founder alert automatically). Depending on the incident: affected users are notified where their data or account is involved; the payment processor (Stripe) is engaged for payment fraud; and for a personal-data breach, the notification obligations under UAE PDPL are followed (informing the regulator and affected individuals as required). Notification is need-to-know and proportionate.
(Audience: internal)

## [Incident Response] How are incidents classified?
By severity, on impact and likelihood — the same critical / high / medium / low framing the Security agent uses for risk. Classification weighs what is affected (money, personal data, credentials, availability), how many are affected, and whether it is contained, and it drives response speed and who is involved. High/critical items escalate straight to the founder; lower ones are logged and handled in course.
(Audience: internal)

## [Incident Response] How are compromised accounts handled?
Contain first, then remediate. Sessions can be revoked and access suspended (matching-blocked or banned), a password reset forced, and any exposed credentials rotated; the activity is investigated against the logs to gauge scope. The owner is notified, and access is restored only once it is secured. Because sensitive actions are gated and each request re-checks identity and role, a stolen session cannot quietly perform privileged actions in the meantime.
(Audience: internal)

## [Incident Response] How are compromised suppliers handled?
A suspected-compromised supplier is immediately held out of matching so no new RFQs or reveals flow to them, their documents and recent activity are reviewed, and — if warranted — the account is suspended or banned with the reason recorded. Affected customers are protected (reveals paused, refunds handled where appropriate), the owner is contacted to re-secure the account, and reinstatement follows verified remediation.
(Audience: internal)

## [Incident Response] How are compromised documents handled?
Exposure is naturally limited because documents are private and only reachable through short-lived signed links, so revoking access is largely a matter of links expiring and storage staying locked; access can be further restricted, links regenerated, and affected files quarantined or replaced. The scope of any exposure is assessed from the logs, and if personal data was involved the PDPL breach process applies. Redaction (e.g. on drawings) and per-party isolation limit the blast radius in the first place.
(Audience: internal)

## [Incident Response] How are compromised APIs handled?
Because keys and the internal service secret live in one server-side store, a suspected compromise is contained fast: the affected key or secret is rotated with a single update (no redeploy) so the old one stops working immediately, the affected function can be disabled or redeployed, and logs are reviewed for misuse. The payment path is additionally protected by signature verification, so a leaked endpoint alone cannot forge paid events. Rotation and revocation are the front-line response.
(Audience: internal)

## [Incident Response] How is recovery performed?
Restore, rotate, verify, resume. Data can be recovered from the managed database's backups and the organised document backup; compromised secrets/keys are rotated; the affected component is redeployed from known-good code; and integrity is checked before service is fully resumed. Recovery steps that touch money, access or published content go through the oversight approval path rather than being auto-applied, so remediation itself stays controlled.
(Audience: internal)

## [Incident Response] How are incidents documented?
Each incident is recorded — what happened, when, severity, systems and users affected, the actions taken and by whom — drawing on the action ledger, agent-run and money logs, and the platform's request logs for the timeline, with a post-incident review to capture cause and prevention. Honest note: a formal standalone incident-response runbook and a dedicated incident register are worth formalising as the company grows; today the trail is assembled from the audit ledger and logs plus a written record of the response.
(Audience: internal)

## [Integrations] Which payment gateways are supported?
Payments run through Stripe. It handles both money flows: the customer's reveal fee (3% of the quote, to unlock a supplier's contact) and the supplier's annual subscription (AED 1,000/year). Stripe events are reconciled so access is granted only on a confirmed payment. No other gateways are offered at this time.

## [Integrations] How does Dropbox integration work?
Dropbox is the platform's secure document backup — an administrator-side integration, not something customers or suppliers see. It works two ways: it indexes the company's QuotesDone Dropbox folders so documents are searchable inside the OS, and it automatically mirrors originals and auto-generated documents into an organized /QuotesDone Backup tree (Customers/… and Suppliers/<category>/…) every 15 minutes. It only reads and uploads — it never deletes anything in Dropbox.

## [Integrations] Can suppliers integrate ERP systems?
Not at this stage. Suppliers work through the QuotesDone portal — registering, receiving matched RFQs, and submitting itemized quotes there. There is no direct ERP connector (e.g. SAP, Oracle, Odoo) today. An ERP/quote integration could be added to the roadmap if demand grows, but it is not live.

## [Integrations] Can customers integrate procurement software?
Not currently. Customers post RFQs and receive quotes through the QuotesDone app; there is no punch-out or e-procurement connector (e.g. Ariba, Coupa, Oracle Procurement) at this time. It is a possible future addition, but not available today.

## [Integrations] Which APIs are available?
QuotesDone runs on its own secure backend and connects to trusted third-party services behind the scenes: Stripe (payments), Dropbox (document backup), Twilio (SMS and voice OTP), WhatsApp (notifications), an email service (transactional mail), a large-language-model gateway (the Smart Engine), and Meta Ads (marketing). There is no public or partner API exposed to customers or suppliers yet — all interaction is through the app and portal. A published API could be offered later if there is demand.

## [Knowledge Confidence & Governance] How is confidence assigned to each knowledge article?
v_kb_confidence scores each chunk 0-100 from citation quality, title, substance and dating, alongside the kb_revisions review workflow (status + ai_validation + reviewer). knowledge_kpis also tracks accuracy_pct and freshness_pct. With effective dates now populated, the base averages about 97. Honest: it is a signal-based score, not a probabilistic per-fact measure.
(Audience: internal)

## [Knowledge Confidence & Governance] What metadata is stored for every knowledge item?
Each kb_chunks row stores: source_kind, source_id, category, title, content, citation, effective_date, a full-text index (fts) and created_at. On top: data_owner_registry classification, and kb_revisions (version, status, author, reviewer, review_notes, ai_validation, decided_at) for curated entries.
(Audience: internal)

## [Knowledge Confidence & Governance] How is the original source tracked?
Every chunk carries source_kind + source_id and a citation pointing back to the origin document; ingested authority documents keep their citation so an answer can be traced to the exact source.
(Audience: internal)

## [Knowledge Confidence & Governance] How are effective/expiry dates managed?
kb_chunks.effective_date carries the as-of date (baselined 2026-07-11 to ingestion date; the Knowledge Curator refines these to real publication dates over time). v_kb_review_due surfaces undated/expired/aging chunks, and knowledge_kpis tracks freshness (regs_fresh, specs_fresh, freshness_pct). Honest: expiry is handled via effective_date + review rather than a separate per-item expiry field.
(Audience: internal)

## [Knowledge Confidence & Governance] How are superseded regulations linked?
Two ways now: kb_revisions versioning (a new version supersedes the prior, which is retained), and an explicit regulations.supersedes_id link that records which regulation replaces which — surfaced as a "supersedes" edge in the knowledge graph. The structure is in place; the Curator populates which older regulation each new one replaces (0 linked so far).
(Audience: internal)

## [Knowledge Confidence & Governance] Who approves knowledge updates?
The founder. The Knowledge Curator surfaces changes; company_faq answers are founder-approved before the sync trigger compiles them to agents; kb_revisions require a reviewer + ai_validation before status becomes approved. Nothing reaches the agents unapproved.
(Audience: internal)

## [Knowledge Confidence & Governance] How is evidence attached?
Via the citation and the source document on each kb_chunks row (and, for compliance, the specific cited clause). Agent action cards link through to the source record so a reviewer can open the evidence behind any output.
(Audience: internal)

## [Knowledge Confidence & Governance] How is knowledge risk classified?
By data_owner_registry classification and the kb_revisions review status, and now an explicit per-article tier via v_kb_risk: regulations = high (compliance/legal), materials and trade knowledge = medium (technical/spec), general documents = low. Today that is 43 high, 360 medium and 1,365 low. Compliance-critical knowledge is gated more tightly by review.
(Audience: internal)

## [Knowledge Platform] Where does technical knowledge come from?
From official, authoritative sources: UAE regulations and codes from the issuing authorities (DEWA, Dubai Civil Defence, Dubai Municipality, MoIAT/ESMA, SIRA and others), recognised standards, manufacturer and material data, and curated company knowledge — all ingested, indexed and made searchable so the Smart Engine can retrieve and cite it. Copyrighted standards are referenced to their official source, not reproduced.

## [Knowledge Platform] How are regulations updated?
Regulatory sources are monitored for change; new or updated codes are ingested into the library, and high-stakes regulatory updates are held for founder approval before they publish to the agents. A daily Knowledge Curator tracks coverage and freshness so gaps are surfaced.

## [Knowledge Platform] How are manufacturers verified?
QuotesDone does not run an endorsement list. Manufacturer and product data lives in the knowledge base, and what matters is that a product meets the required UAE approvals for the job (ECAS-conformant, DCD-listed, DEWA-approved). On the supplier side, company documents such as the trade licence are verified at registration.

## [Knowledge Platform] How are standards maintained?
Standards — UAE.S/GSO plus the referenced ISO, EN, IEC, NFPA and ASHRAE — are catalogued with where they apply per category, reviewed for currency, and updated as editions change. Copyrighted standard texts are referenced to the official source rather than hosted.

## [Knowledge Platform] How is knowledge validated?
Every change goes through a governed pipeline: submit, then automated validation, then review and approval before it goes live. Answers must be grounded in these verified sources, and anything flagged or failing validation is held out until it is fixed.

## [Knowledge Platform] How often is knowledge updated?
Continuously. Source monitoring and ingestion run on a schedule, a daily Knowledge Curator refreshes coverage and freshness, company facts auto-sync, and updates land as sources change — with sensitive updates gated on approval.

## [Knowledge Platform] How is outdated information removed?
Superseded content is replaced or retired: revisions are version-controlled, stale sources are flagged by freshness checks, and resolved items are automatically closed — so the agents do not rely on out-of-date information.

## [Knowledge Platform] Who approves new knowledge?
You do, for anything high-stakes. New or updated regulations and sensitive knowledge are queued for founder approval before they publish to the agents, while routine low-risk updates flow through the validated pipeline automatically. Nothing sensitive goes live unreviewed.

## [Knowledge Quality] How is conflicting information resolved?
Official sources take precedence. When two sources conflict, the more authoritative and most-recent (effective_date) wins, and the Knowledge Curator/Legal review flags it; canonical answers in company_faq are the tie-breaker for agent behaviour. A confident-but-wrong answer is worse than deferring, so unresolved conflicts escalate rather than pick arbitrarily.
(Audience: internal)

## [Knowledge Quality] How are duplicate regulations merged?
Ingested authority documents are chunked (kb_chunks) with a source and citation; duplicates and overlaps are consolidated during curation, keeping the authoritative citation. Honest: dedup is curation-assisted, not a fully automatic entity-resolution engine.
(Audience: internal)

## [Knowledge Quality] How is stale knowledge detected?
Surfaced via v_kb_review_due, which lists chunks that are undated, past their effective date, weak-cited or aging — a curator worklist. Honest finding (2026-07-11): all 1,768 chunks currently lack an effective/as-of date, so they all show as "undated", meaning staleness cannot be time-detected until dates are populated. Populating effective dates is the real next step; there is still no automated upstream watcher that detects when a source regulation itself changes.
(Audience: internal)

## [Knowledge Quality] How are superseded regulations archived?
Via kb_revisions: a new version supersedes the old, and the old revision is retained (status/decided_at) rather than deleted — an auditable history. company_faq answers are updated in place with source_note history.
(Audience: internal)

## [Knowledge Quality] How is confidence assigned to knowledge?
Now scored explicitly: v_kb_confidence gives each knowledge chunk a 0-100 confidence from citation quality, title, substance and dating, alongside the kb_revisions review workflow (status + ai_validation + reviewer) for curated knowledge. Today the base averages about 80 (all 1,768 chunks are cited) and is capped at 80 because chunks are not yet dated — adding effective dates lifts them toward 100. Honest: it is a signal-based score, not a probabilistic per-fact measure.
(Audience: internal)

## [Knowledge Quality] How is knowledge tested before publication?
kb_revisions includes an ai_validation step and a human reviewer before status becomes approved; company_faq answers are founder-approved before the sync trigger compiles them to agents; prompt changes are benchmarked. Nothing reaches agents unapproved.
(Audience: internal)

## [Knowledge Quality] How are broken references detected?
Now guarded by v_kb_citation_check, which flags any knowledge chunk with a missing or too-short citation (0 today — all 1,768 chunks are cited), plus kb_usage_log tracking what is retrieved and learn_gaps surfacing gaps. Honest gap remains: there is no automated dead-link/URL checker that verifies a citation still resolves.
(Audience: internal)

## [Knowledge Quality] How often is knowledge reviewed?
Continuously by daily agents (Knowledge Curator, Document Controller, Legal AI) plus weekly learn_gaps and eval runs; expiry-dated items are reviewed as they approach their effective/expiry dates. Honest: there is no fixed calendar review SLA per document yet.
(Audience: internal)

## [Knowledge Relationships] How are regulations linked to products, brands, suppliers and RFQs?
Through the shared category tag, semantic embeddings (pgvector), and now an extended knowledge graph: regulations are nodes with applies_to edges to their categories (43 links today), and categories already connect to RFQs and suppliers — so a regulation reaches the RFQs and suppliers in its category through the graph. Honest note: brands, standards and manufacturers are not yet separate tables/nodes (they live inside knowledge chunks and quote line-items), so they are linked by content/category rather than explicit graph nodes.
(Audience: internal)

## [Knowledge Relationships] How are manufacturers linked to standards?
Through the knowledge base (kb_chunks): manufacturers and standards are captured as knowledge tagged to the same category and cross-referenced by content and citation. Honest: this is content/category linkage, not yet explicit manufacturer-to-standard graph edges.
(Audience: internal)

## [Knowledge Relationships] How are projects linked to knowledge?
Via the inquiry/project (inquiries.project_id) and its category, which map to the applicable specs, playbooks and regulations for that category; retrieval pulls that knowledge when the project is worked.
(Audience: internal)

## [Knowledge Relationships] How are quotations linked to regulations?
Through the parent RFQ's category, which maps to the applicable regulations and specs; the Smart Engine references those when adjudicating and comparing quotes for compliance.
(Audience: internal)

## [Knowledge Relationships] How are related knowledge discovered automatically?
By semantic similarity (pgvector) and full-text search over kb_chunks, plus category adjacency and the knowledge graph edges — so relevant chunks are pulled together at query time even without an explicit hand-made link.
(Audience: internal)

## [Marketplace] How are suppliers ranked?
Ranking is merit-based, never pay-to-rank. It reflects real performance — customer reviews, responsiveness, win rate and how well a supplier genuinely fits the job — and for any given request the Smart Engine also weighs capability, the emirates served and similarity to the job. Suppliers rise by performing well.

## [Marketplace] How are categories managed?
QuotesDone runs a taxonomy of trades, each with its own qualification playbook. When a supplier registers a trade we do not yet have, the Smart Engine automatically provisions a new category — persona, intake questions and category knowledge — with the founder reviewing the generated knowledge before it reaches full quality.

## [Marketplace] How are duplicate suppliers prevented?
Suppliers are matched to a single company listing keyed on their trade licence and company identity, and the directory is de-duplicated — so a company is not represented twice. Duplicate or suspicious registrations are flagged in review.

## [Marketplace] How is fraud detected?
Through automated fraud scanning and anomaly checks, contact-leak detection in the in-platform chat, decoy/canary traps, and document checks — with suspicious accounts flagged and, where warranted, blocked from matching. The anonymity model itself removes much of the incentive to game the system.

## [Marketplace] How are disputes managed?
Disputes follow a defined process: you raise the issue, it is reviewed with the full record, and it is resolved through the platform — including refunds where appropriate, which settle against the original transaction. The goal is a fair outcome for both sides.

## [Marketplace] How is supplier quality measured?
By real outcomes: multi-dimension customer reviews (communication, quality, punctuality, documentation, after-sales and compliance), the supplier's dispute record, responsiveness, and the quality of the quotes they submit — combined into a reputation score customers can see.

## [Marketplace] How are customer ratings calculated?
After a completed deal, the customer leaves a multi-dimension review, and only a customer who actually revealed and dealt with a supplier can rate them — so ratings are genuine. These reviews feed the supplier's overall reputation score.

## [Marketplace Health] What is marketplace liquidity?
The balance of active buyers (RFQs) against responsive, verified suppliers per category and emirate — enough qualified suppliers to get real quotes on each RFQ. It is monitored via demand (marketing_category_demand) versus coverage (reg_coverage).
(Audience: internal)

## [Marketplace Health] Which categories are underserved?
Surfaced by comparing RFQ demand to registered/approved supplier coverage per category (marketing_category_demand + reg_coverage); categories with demand but thin approved supply are flagged for recruitment.
(Audience: internal)

## [Marketplace Health] Which Emirates have insufficient supplier coverage?
reg_coverage breaks registered/approved suppliers down by emirate and category; low-coverage emirates for in-demand categories are flagged.
(Audience: internal)

## [Marketplace Health] Which suppliers are overloaded?
v_supplier_load now measures it: active matched RFQs (open, non-cancelled) per claimed supplier versus their response rate, with an overloaded flag (10+ active matches and response under 50%). Honest note: it is a starting heuristic gauge, not a real-time capacity model.
(Audience: internal)

## [Marketplace Health] Which customers have waited too long?
customer_health flags stalled RFQs (e.g. qualifying with no quotes for 2+ days, quoted for 7+ days, revealed-but-not-completed for 30+ days); these surface to Customer Success.
(Audience: internal)

## [Marketplace Health] Where are quotation bottlenecks?
In the RFQ pipeline stages (qualifying, matched, quoted, revealed): stages where RFQs stall — no quotes, slow supplier response — are visible via the stalled flags and pipeline-stage timing.
(Audience: internal)

## [Marketplace Health] Which categories need recruitment?
The underserved/low-coverage categories feed the recruitment target list; the directory-invite engine and Marketing AI focus onboarding there.
(Audience: internal)

## [Marketplace Intelligence] Which categories lack suppliers?
Surfaced by comparing demand (marketing_category_demand) to approved-supplier coverage (reg_coverage), and rolled up in strategy_kpis.under_supplied_categories — categories with real RFQ demand but thin approved supply are flagged for recruitment.
(Audience: internal)

## [Marketplace Intelligence] Which Emirates have insufficient coverage?
reg_coverage breaks registered/approved suppliers down by emirate and category; low-coverage emirates for in-demand categories are flagged for targeted onboarding.
(Audience: internal)

## [Marketplace Intelligence] Which RFQs receive no quotations?
RFQs with zero quotes past a window are tracked (no_quote_notified + run_no_quote_nudges nudges suppliers), and customer_health flags them as stalled so Customer Success can step in.
(Audience: internal)

## [Marketplace Intelligence] Which categories have the slowest response times?
Now built: v_mkt_response_by_category reports, per category, the RFQ count, how many got quoted, the average hours to first quote, and the no-quote percentage — slowest categories sort to the top. Also reflected in customer_health response hours.
(Audience: internal)

## [Marketplace Intelligence] Which brands dominate each category?
Now built: v_mkt_brand_by_category aggregates the brand fields on quote line items by category (line count, distinct suppliers, total amount) so you can see which brands appear most per category. It reads from quote_items.brand, so it fills in as itemised, branded quotes accumulate (0 today while early quotes lack per-line brands).
(Audience: internal)

## [Marketplace Intelligence] Which jobs are over budget?
Now built: v_mkt_over_budget lists jobs where the cheapest live quote exceeds the buyer's stated budget, with the overrun amount. Honest note: budget is a free-text field, so the view best-effort parses the first number in it — treat it as indicative. It currently flags a small number of real over-budget jobs.
(Audience: internal)

## [Marketplace Intelligence] Which jobs are underpriced?
Now built: v_mkt_underpriced lists quotes flagged suspiciously_low against the category price band (via fn_price_confidence), alongside the category median — complementing the existing abnormal_price fraud flag. Budget-versus-quote adds a second lens.
(Audience: internal)

## [Operational Runbooks] What happens if Dropbox fails?
Little impact — Dropbox is a secondary backup mirror, not the system of record. Originals stay in Supabase Storage (plus managed daily backups). The 15-minute backup queue retries later and catches up when Dropbox returns.
(Audience: internal)

## [Operational Runbooks] What happens if Supabase is unavailable?
This is the hard dependency: the backend (database + functions + storage) is down. The static site and FAQ stay up on Vercel (cached). Supabase's managed platform handles infra recovery; worst-case is restore-from-backup. There is no self-managed standby. See IR Runbook section 3.
(Audience: internal)

## [Operational Runbooks] What happens if OpenRouter is unavailable?
The Smart Engine's model gateway is down, so agents cannot call models. Oversight-first means work queues for review rather than acting wrongly; the core marketplace (post RFQ, quote, reveal, pay) keeps working. Multiple model fallbacks reduce single-model outages.
(Audience: internal)

## [Operational Runbooks] What happens if Claude is unavailable?
Claude is one model reached via OpenRouter; the router falls back to other models (e.g. Sonnet/GPT). Quality may vary but the pipeline continues, and low-confidence outputs escalate rather than act.
(Audience: internal)

## [Operational Runbooks] What happens if GPT is unavailable?
Same as any single model — it is a fallback option via OpenRouter, not a single point of failure; the router routes around it to an available model.
(Audience: internal)

## [Operational Runbooks] What happens if OCR fails?
Document extraction (doc_extract) fails for that file; the original is still stored and backed up, the document is queued/retried, and it is flagged for manual handling. Nothing is lost — extraction is enrichment, not the system of record.
(Audience: internal)

## [Operational Runbooks] What happens if a deployment fails?
The bundler rejects broken code before it goes live (syntax gate), Edge Functions are versioned (redeploy the previous one), and the static site is an atomic Vercel swap with instant rollback. A failed deploy does not take the live version down. See IR Runbook rollback.
(Audience: internal)

## [Operational Runbooks] What happens if backups fail?
agent_runs logs each backup run's status; a failed logical backup is visible there, the managed daily backups still run independently, and the Dropbox mirror + dr_drill surface problems. Honest gap: there is no dedicated backup-failure alert yet — it is visible in agent_runs but not actively paged; adding an alert is a quick enhancement.
(Audience: internal)

## [Operations] What happens if a supplier is suspended?
A suspended supplier is immediately excluded from matching — the Smart Engine routes no new RFQs to them and they cannot submit new quotes — but nothing is deleted and the reason is recorded. Suspension (matching blocked) is reversible; a full ban removes them from the marketplace. Both are oversight-first: agents surface the risk and recommend, but the action is applied under admin authority, not automatically. Anything the supplier already committed to is handled case by case.

## [Operations] What happens if a licence expires?
Trade licences — plus insurance, ISO and manufacturer authorizations — have their expiry dates tracked continuously. As expiry nears, reminders go out and the item is flagged on the supplier's compliance scorecard. Once expired, the supplier is treated as non-compliant and held out of matching until a valid renewal is uploaded; re-verification requires current documents. It is a hold pending renewal, never an auto-deletion.

## [Operations] What happens if payment fails?
Money flows through Stripe. If a customer's reveal payment (the 3% fee to unlock a supplier's contact) fails, the contact simply is not revealed and they can retry — nothing is charged and no identity is exposed. If a supplier's annual subscription (AED 1,000/year) payment fails, their registration is not activated or lapses, pausing new matching until it is paid. Failed payments never silently grant access; the platform reconciles Stripe events so records stay accurate.

## [Operations] What happens if AI confidence is low?
Low confidence triggers caution, not action. In matching, the rule is "a wrong match is worse than no match" — if the engine is not confident a supplier truly fits, it excludes them and can return zero matches rather than guess. Elsewhere (capability write-ups, new-category knowledge, document reads) low-confidence output is marked and held for founder review before it is published or acted on. It escalates to a human rather than proceeding.

## [Operations] What happens if an RFQ is incomplete?
The intake agent turns the customer's words and photos into a structured brief and checks completeness against the category's qualification playbook. If key details are missing, the RFQ is not marked ready and is not dispatched to suppliers — the customer is asked for the missing information (and can edit within 1 hour). It only enters matching once it is complete enough to quote accurately, protecting both sides from bad matches.

## [Operations] What happens if no suppliers accept?
Two cases. If the engine finds no genuinely suitable supplier, it deliberately contacts no one (never random sends) and raises an internal coverage-gap signal telling the team exactly which trade and emirate to recruit. If suppliers were matched but none respond, response is tracked and the customer is kept informed; the request can be broadened or escalated. The customer is never handed a random or unsuitable supplier just to fill the slot.

## [Operations] What happens if regulations change?
UAE codes and authority requirements live in the knowledge base, and the Knowledge Curator watches for stale or missing compliance content. When rules change, updated authority documents are ingested and — under the oversight-first model — approved before going live; category requirements, qualification playbooks and agent knowledge are then updated. Agents always retrieve the current requirements and point users to the official source of record, so guidance stays aligned with the latest regulations.

## [Performance] What is the maximum supported concurrent users?
There is no formally load-tested published number yet. In practice, concurrency is bounded by Supabase's managed connection pooling and Edge Function auto-scaling (both scale on the plan), while the public site — being fully static on Vercel's CDN — serves effectively unlimited concurrent readers. Honest note: a proper load test has not been run, so QuotesDone should not quote a hard concurrent-user figure; the architecture handles typical B2B-marketplace concurrency comfortably, and a benchmark should precede any specific claim.
(Audience: internal)

## [Performance] What is the maximum number of suppliers supported?
No hard cap. The supplier directory already holds 20,000+ entries and the database handles that comfortably; Postgres scales to millions of rows, and storage/compute grow with the plan. The practical ceiling is commercial, not technical.
(Audience: internal)

## [Performance] What is the maximum number of RFQs (inquiries) supported?
No hard cap. Each RFQ is a database row, indexed by status, date and customer; Postgres handles millions of rows without issue. Volume scales with the plan's storage.
(Audience: internal)

## [Performance] What is the maximum number of quotations supported?
Same as RFQs — quotations are indexed rows with no fixed limit, scaling with database storage. No architectural ceiling at any realistic marketplace volume.
(Audience: internal)

## [Performance] What is the maximum file size?
Supplier attachments and catalogues accept up to 1 GB per file (large uploads use a chunked path so big catalogues do not fail); typical drawings and documents are a few MB. The storage buckets enforce the limit.
(Audience: internal)

## [Performance] What is the database optimisation strategy?
Postgres 17 with purpose-built indexes (btree on foreign keys, status and dates; GIN for full-text search; pgvector for embeddings), row-level security throughout, managed connection pooling, and heavy work pushed to scheduled/queued Edge Functions and cron rather than the request path. Honest gap: there is no formal query-performance monitoring / APM dashboard yet — slow-query profiling is a sensible next step.
(Audience: internal)

## [Performance] What is the caching strategy?
The public site is fully static and cached at Vercel's edge CDN worldwide, so most public traffic never touches the database. Agent knowledge is pre-compiled into _global (computed once on approval, not recomputed per query), and live artifact reads are cached. Honest note: there is no application-level cache (e.g. Redis) in front of the dynamic APIs today — each dynamic call hits Postgres directly; a cache layer can be added if load ever demands it.
(Audience: internal)

## [Performance] What is the CDN strategy?
Vercel's global CDN serves the static site and assets from edge locations close to each visitor, automatically. User documents are served through short-lived signed URLs from Supabase Storage (itself CDN-backed), so files are delivered quickly without exposing internal paths.
(Audience: internal)

## [Performance] What is the search indexing strategy?
Hybrid retrieval: Postgres full-text search (tsvector/GIN) combined with pgvector semantic embeddings, then Smart Engine adjudication on top — deliberately conservative, since a wrong match is worse than no match. The supplier directory and catalogue content are indexed for this. Honest note: no external search engine (Elasticsearch/Algolia) is used; Postgres FTS + pgvector covers the current scale, and a dedicated search service is an option if volume grows substantially.
(Audience: internal)

## [Platform Architecture] What is QuotesDone's system architecture?
A serverless, AI-first architecture on Supabase and Vercel. The backend is Supabase — PostgreSQL (with row-level security), Auth, Storage, and Deno/TypeScript Edge Functions — where all business logic lives as edge functions (running with service-role access) plus SQL functions. The Smart Engine agents are edge functions that call an LLM gateway and read a governed knowledge base. The frontend is a static site on Vercel. Event-driven and async work runs through database triggers, pg_net (outbound HTTP) and pg_cron (scheduling). Third-party capabilities (payments, messaging, email, backup, ads) sit behind the backend.
(Audience: internal)

## [Platform Architecture] Why was this architecture chosen?
It maximises leverage for a lean, AI-first company: serverless components scale automatically and cost little when idle; Postgres gives one strong, consistent source of truth with security enforced at the row level; edge functions keep all sensitive logic server-side. Static hosting makes the public site fast and cheap to serve globally. Keeping business rules in the database and edge functions (not the client) makes the system secure, auditable, and easy for the Smart Engine agents to operate under human oversight.
(Audience: internal)

## [Platform Architecture] Which technologies are used?
Supabase (PostgreSQL, Auth, Storage, Edge Functions on Deno/TypeScript), pg_cron and pg_net for scheduling and outbound calls, and vector embeddings plus full-text search for matching and knowledge retrieval. The frontend is static HTML/CSS/JS on Vercel. The Smart Engine uses an LLM gateway (OpenRouter, with Claude Opus/Sonnet and fallbacks). Integrations: Stripe (payments), Twilio and WhatsApp (messaging/OTP), an email service (Resend), Dropbox (document backup), and Meta Ads (marketing).
(Audience: internal)

## [Platform Architecture] How are frontend and backend separated?
Cleanly. The frontend is a static, pre-rendered site (marketing pages, customer app, supplier portal, internal OS) served from Vercel's CDN — it holds no business logic or secrets. It talks to the backend only through authenticated calls to Supabase Edge Functions, which enforce auth and run all logic against the database with service-role access. Secrets never reach the browser, and the client never runs privileged queries directly against the database.
(Audience: internal)

## [Platform Architecture] How are Edge Functions used?
They are the backbone: they serve each page (rendering HTML from the pages table), expose the action-based APIs the apps call (customer, supplier, OS), run every Smart Engine agent, and handle integrations and webhooks (Stripe, messaging, Dropbox). They run server-side with service-role access, are individually deployable and versioned, and are gated by JWT/role for user calls or a shared internal secret for service-to-service and scheduled calls.
(Audience: internal)

## [Platform Architecture] How are APIs versioned?
Each Edge Function is versioned by the platform on every deploy (v1, v2, …), so changes are tracked and reversible. The internal service APIs are action-based — one function endpoint that routes on an action field — rather than versioned REST paths, and each carries an explicit version in its code, so behaviour can evolve without breaking callers. There is no public/partner API yet; all interaction is through the apps and portal.
(Audience: internal)

## [Platform Architecture] How are services decoupled?
Services are small, single-responsibility edge functions that communicate through the database and events rather than tight coupling. Triggers and pg_net fire follow-on work asynchronously (e.g. a finalized RFQ automatically triggers matching and seller notification), pg_cron runs recurring jobs (backups, collections, reminders, evaluations), and functions call each other through gated internal endpoints. Each piece is independently deployable and testable.
(Audience: internal)

## [Platform Architecture] What is the application lifecycle?
A user loads a static page from Vercel; the app calls an Edge Function with the user's auth token; the function verifies identity and role, runs the business logic (SQL functions, the LLM gateway, integrations) with service-role access, and returns JSON the UI renders. Sensitive or irreversible steps raise an approval item for a human instead of completing automatically. Longer or recurring work (matching, backups, collections) happens asynchronously via triggers and scheduled jobs.
(Audience: internal)

## [Platform Architecture] How are deployments managed?
Three tracks: database changes as versioned migrations; Edge Functions deployed individually, each getting a new platform version; and the public website rebuilt by a deploy function that pre-renders every route into static files and pushes a new Vercel production deployment. Configuration and secrets live in a secured store, not in code. Each track is independently releasable and reversible.
(Audience: internal)

## [Platform Architecture] How is scalability achieved?
Every layer scales independently: the static site from Vercel's global CDN; stateless Edge Functions that scale automatically with load; a managed, scalable Postgres. Heavy or bulk work is moved off the request path into scheduled jobs and batched processing, responses are cached where safe, and vector + full-text retrieval keeps matching fast as data grows. Being serverless and stateless, it absorbs spikes without manual capacity planning.
(Audience: internal)

## [Quotation] What makes a good quotation?
A complete, itemised, transparently-priced quote: line items with brand/model, specifications, quantities and unit prices, plus scope, materials, lead time, validity, warranty, payment terms and any exclusions. Good quotes are easy for the customer to compare and win more often.

## [Quotation] What fields are mandatory?
The required sections for that category — typically: scope of work; itemised line items (BOQ) with brand/model, specifications, quantities and unit prices; materials; lead time; validity; warranty; payment terms; and exclusions. A quote must include these to pass the quality bar and reach the customer.

## [Quotation] What documents must be attached?
The itemised quote itself is what is required. You may optionally attach your own official company quotation (PDF) — the platform also generates a clean, anonymised version — and datasheets are recommended for regulated or branded items. Company documents such as your trade licence are handled once at registration, not per quote.

## [Quotation] How are quotations compared?
Side by side and anonymised (Supplier A, B, C), all normalised against the same brief so it is like-for-like. The customer sees each quote's price, inclusions and exclusions, lead time, warranty and terms, alongside a price-confidence band to sanity-check value.

## [Quotation] What is a BOQ?
A BOQ (Bill of Quantities) is the itemised list of materials and works — each with its quantity and unit — that a quotation is priced against. It makes quotes precise and directly comparable.

## [Quotation] What is included in the comparison?
For each quote: the price, the line items, scope/inclusions and exclusions, lead time, validity, warranty and payment terms, plus the supplier's rating and verification status and a price-confidence band. Everything the customer needs to choose on value, not just the lowest number.

## [Quotation] What happens if a quotation is missing information?
Quotes must pass a quality bar before the customer sees them. If something important is missing, the Smart Engine coaches the supplier to complete it, and the quote is held as a draft until it meets the standard — so customers only compare complete quotes.

## [Quotation] Can the Smart Engine reject quotations?
It does not reject you outright — it enforces a quality standard. A quote below the required completeness score is held as a draft with specific coaching on what to add, and is released to the customer once it meets the bar. This protects everyone: customers get complete quotes, and good suppliers are not undercut by half-finished ones.

## [Quotation] How are quotation scores calculated?
Each quote is scored on how completely it covers the category's required sections and how well it is itemised — scope, line items with brand/model and specs, quantities and unit prices, and the commercial terms. It must reach the quality threshold to be submittable to the customer.

## [Quotation] Can suppliers revise quotations?
Yes, before Reveal. Under Supplier Agreement §12, a quotation is valid for 30 days from submission unless the supplier refreshes or withdraws it before Reveal, and the supplier is bound by a quotation that is revealed within that validity period. After Reveal, the contract for the work is solely between the supplier and the customer, on terms they agree; QuotesDone is not a party to it.

## [QuotesDone Constitution] Constitution: Never guess.
Agents retrieve before answering; below confidence they escalate rather than fabricate. Enforced by the retrieve-first design and eval checks.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Always retrieve before answering.
Hybrid retrieval (full-text + pgvector) grounds every substantive answer; kb_usage_log records what was used.
(Audience: internal)

## [QuotesDone Constitution] Constitution: A wrong supplier is worse than no supplier.
Matching is deliberately conservative; low-confidence matches are withheld or escalated, never forced.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Customer anonymity is never compromised.
Buyers are anonymous to suppliers end-to-end; identity is revealed only via the paid reveal the customer controls, with blind quoting throughout.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every recommendation must be explainable.
Agent cards carry reasoning plus click-through to source; comparisons show per-supplier rationale.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every important decision must be auditable.
agent_actions history, the append-only security_audit_log for governance changes, and per-feature session logs provide the trail.
(Audience: internal)

## [QuotesDone Constitution] Constitution: AI may recommend but not execute irreversible actions without approval.
Oversight-first: sends, charges, publishing, deletion and permission/legal actions all require founder approval.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Structured data is preferred over free text.
Itemised quotes are enforced, business rules are config-as-data, supplier capability is enriched into structured fields, and typed records are preferred over prose.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Official sources take precedence over third-party information.
Knowledge ranks authoritative, cited sources first; conflicts resolve toward official and most-recent.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Security defaults to deny-by-default.
RLS is deny-by-default on every table; RBAC is least-privilege; secrets are service-role-only.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every workflow must be recoverable.
Daily managed + logical backups, dr_drill restore drills, versioned functions, known rollback paths and the IR runbook keep workflows recoverable.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every business rule must be configurable rather than hard-coded.
Config-as-data (collections_config, pricing_config, feature_flags and similar) keeps rules tunable under approval with an audit trail.
(Audience: internal)

## [Reporting] What reports can customers see?
Customers see reporting scoped only to their own requests — never other customers' or the wider marketplace. Per inquiry they see its live status (matched → quoted → revealed), the quotes received (supplier identities stay hidden until they choose to reveal), and the Smart Engine's Quote Comparison Report: a plain-language, side-by-side analysis of their anonymized quotes (Supplier A/B/C) with a ranked top-3 recommendation, what each price actually buys, spec deviations, missing items, watch-outs and advice. There are no cross-customer or marketplace-wide dashboards.

## [Reporting] What reports can suppliers see?
Suppliers see reporting about their own account only. In the portal this includes their profile / digital twin, their reputation and merit standing, and performance metrics — RFQs matched to them, quotes submitted, win rate, response rate and rating — plus an exposure view (RFQs in their categories in the last 30 days and whether they were matched). They see the itemized quotes they submitted. They never see other suppliers' data, customer identities, or competitors' pricing.

## [Reporting] What reports can administrators see?
Administrators see the full picture inside the QuotesDone OS: an Executive Command Center; Finance/CFO reports (P&L, cash, forecasts); Supplier 360 and Customer 360 workspaces; RFQ/procurement; and Marketing, Knowledge, Documents, Operations, Legal, Security and Governance workspaces, plus each Smart Engine agent's operations panel. Reports export as branded PDFs, span every KPI and record, and support click-through to the underlying source.

## [Reporting] Which KPIs are monitored?
KPIs are grouped by domain, each with a live scorecard: Marketplace health (supply/demand, coverage gaps); Suppliers (health, match/quote/win rates, response rate, rating, licences expiring, compliance); Customers (activity, retention, health); Finance (revenue, reveal fees, commission owed/paid, forecast); Marketing (category demand, campaign performance); Knowledge (coverage, playbook coverage, curator health); and Operations, Legal, Security, Documents, Governance and Strategy scorecards. Matching quality is tracked separately as precision/recall.

## [Reporting] How are analytics calculated?
Analytics are computed directly from the platform's own operational data — inquiries, matches, quotes, transactions, reveals, reviews and agent actions — by SQL views that run on live data, with no manual entry. For example: win rate = deals won ÷ quotes submitted; quote rate = quotes ÷ RFQs matched; response rate = reveals responded ÷ reveals received; commission owed = sum of unpaid dues; supplier/customer health = weighted composite scores; matching precision/recall from the evaluation harness. Figures refresh as the underlying data changes, so every report reflects the current state.

## [RFQ] What is an RFQ?
RFQ means Request for Quotation — your job request. On QuotesDone you describe what you need (in words, voice, a photo or a drawing) and the Smart Engine turns it into one clear, structured brief that suppliers can price against.

## [RFQ] What information is mandatory in an RFQ?
Enough for a supplier to give a firm price without contacting you: what you need, the key specifications and quantities for that type of work, the general area and emirate, and any drawings or bill of quantities you have. The exact must-have fields depend on the category, and the Smart Engine asks you for anything still missing.

## [RFQ] How does the Smart Engine qualify an RFQ?
It reads your words, photos or drawings, structures them into a supplier-ready brief, applies the qualification playbook for that category to ask the right questions, and scores how complete the request is — only sending it out once it is ready to be priced.

## [RFQ] What makes an RFQ complete?
It is complete when it contains everything a supplier needs to return a firm fixed price without meeting you: clear scope, the price-driving specs and quantities for that category, the area and emirate, and any needed visuals. At that point it is marked ready and goes to matched suppliers.

## [RFQ] What happens if information is missing?
The Smart Engine asks you a few easy, tap-to-answer questions to fill the gaps. If something is genuinely unknown, it is recorded as an open item for the supplier to propose — so you are never stuck — and the request only goes out once it is complete enough to price.

## [RFQ] Can the Smart Engine estimate budgets?
It does not invent a budget or price for you — suppliers set the price. Budget is optional. What it can show is a price-confidence band (a typical range from comparable jobs) so you can sanity-check the quotes you receive.

## [RFQ] Can the Smart Engine estimate timelines?
It will not promise a delivery date — each supplier states their own lead time in their quote. As a rule of thumb, quotes themselves usually arrive within 3-5 working days.

## [RFQ] Can the Smart Engine recommend specifications?
It will not push technical choices on you. Where a choice is technical, it notes it as "supplier to propose suitable options with prices." It uses category knowledge and UAE codes to make sure the brief captures what matters and to flag compliance — but the supplier proposes and prices the technical specification.

## [RFQ] How are suppliers matched (RFQ)?
The Smart Engine shortlists suppliers by real capability, keywords and the emirates they serve, then judges each candidate on whether they can genuinely do your exact job. Only genuinely-capable suppliers are invited — a wrong match is treated as worse than no match — and any number of the invited suppliers may quote: there is no fixed limit.

## [RFQ] How is RFQ quality measured?
Each request is scored for completeness against the category checklist and playbook, and must reach the "ready" bar before it is sent to suppliers. (Separately, suppliers' quotes are quality-gated too, so what you compare is complete and like-for-like.)

## [Security] How is data encrypted?
Your data is encrypted in transit (every connection uses TLS/HTTPS) and at rest on our managed cloud database and storage. Card payments are handled entirely by Stripe, so payment-card details never touch our own servers.

## [Security] How are documents protected?
Files such as licences, drawings and quotations are kept in private storage that is not publicly accessible. They are reached only through the app using short-lived signed links, uploads are scanned for malware, and customer drawings are automatically redacted to remove identifying details before any supplier sees them.

## [Security] Who can access my files?
Only you and the parties who are supposed to. The platform serves your files to your own account, and identities stay hidden between customer and supplier until a paid reveal. There is no open or public access to files — everything is served through the backend with strict authorisation.

## [Security] How are permissions managed?
The database is deny-by-default — nothing is readable directly with a public key. Every read and write goes through backend functions that check who you are and what you are allowed to do (role-based access), and admin areas require additional authentication, including multi-factor authentication.

## [Security] How are backups performed?
The system is backed up on a regular schedule to durable off-site storage, and disaster-recovery drills are run to confirm data can be restored. Completed requests are also archived separately.

## [Security] How are cyber attacks detected?
Through continuous automated monitoring: security scans, fraud checks, malware scanning of uploads, decoy/canary traps, and health and uptime checks — with alerts raised to the founder when something looks wrong. Suspicious activity, such as attempts to share contacts off-platform, is flagged.

## [Security] What happens during a security incident?
There is a defined response: the issue is detected and alerted, contained, and investigated using the immutable audit logs; affected parties are informed as appropriate; sensitive actions are reversible; and data can be restored from backups if needed. Personal data — and any breach — is handled responsibly under UAE data-protection law (PDPL).

## [Security Testing] How often are penetration tests performed?
Honest: no third-party penetration test has been commissioned yet — this is a real gap. Present-day assurance comes from the managed-platform security (Supabase/Vercel/AWS), row-level-security deny-by-default, and the oversight model. A professional external pen test is recommended before or alongside meaningful scale.
(Audience: internal)

## [Security Testing] How often are vulnerability scans run?
Honest: there is no scheduled automated vulnerability scanner (e.g. recurring DAST) today. The closest real control is Supabase's built-in Security Advisor, which lints for RLS gaps, exposed policies and misconfigurations and can be run on demand. Formal, scheduled scanning is a gap to add.
(Audience: internal)

## [Security Testing] How are dependencies monitored for CVEs?
Honest: there is no automated CVE/dependency alerting (no Dependabot/Snyk-style tooling) wired up. This is partly mitigated because the backend runs on Deno with a small, explicit set of imports and the managed platforms patch their own runtimes — but application-level dependency-CVE monitoring is a gap worth closing.
(Audience: internal)

## [Security Testing] How are OWASP Top 10 risks mitigated?
This has genuine substance. Injection — the database is accessed through parameterized queries, and RLS constrains every table. Broken access control — RLS is deny-by-default with RBAC roles on top; all public tables have RLS enabled. Auth failures — Supabase Auth with bcrypt, rate limiting, email verification, SMS OTP and an 18+ gate. Secrets/exposure — secrets are service-role-only and never sent to clients; internal paths are never exposed. Misconfiguration — reduced by the managed platform plus RLS-enabled everywhere. Honest notes within the Top 10: uploaded files ARE scanned against VirusTotal (known-malware hash lookup, daily) — though novel-file sandboxing is not yet in place — while application dependency-CVE monitoring and some logging/monitoring coverage are still uneven. So: strong on access-control, injection and auth; weaker on supply-chain and parts of logging/monitoring.
(Audience: internal)

## [Security Testing] How are third-party libraries reviewed?
Honest: the dependency surface is kept deliberately small and imports are explicit/pinned, and new libraries are added consciously rather than casually — which limits risk. But there is no formal security review or software bill-of-materials (SBOM) process. The small surface helps; a formal review step is a gap.
(Audience: internal)

## [Security Testing] How are secrets scanned before deployment?
Honest: secrets live in the app_secrets table and platform secret store (service-role-only) and are kept out of client code and the codebase by convention and by the service-role isolation itself. But there is no automated pre-deploy secret scanner (e.g. gitleaks/trufflehog) acting as a gate. Discipline plus service-role isolation protect today; an automated scan is a gap.
(Audience: internal)

## [Security Testing] How are security regressions prevented?
Primarily structural: RLS is deny-by-default, so a newly created table is closed until a policy is explicitly and deliberately added; the Supabase Security Advisor catches RLS/policy regressions; and all security changes require founder approval. Honest gap: there is no automated security-regression test suite in CI — prevention rests on the deny-by-default posture, the advisor, and oversight rather than an automated gate.
(Audience: internal)

## [Smart Engine] What does the Smart Engine do?
It runs QuotesDone end to end: it understands a customer's request and turns it into a clear brief, matches it to genuinely-capable suppliers, checks quote quality, answers questions using verified UAE knowledge, and handles routine operations — always grounded in real data, never inventing prices, brands or rules.

## [Smart Engine] What decisions can the Smart Engine make?
Low-risk, reversible, well-understood ones on its own: structuring a brief, asking clarifying questions, matching and inviting suppliers, scoring RFQ and quote completeness, surfacing the applicable regulations, drafting communications, and routine housekeeping — and every action is logged.

## [Smart Engine] What can't the Smart Engine decide?
Anything sensitive or irreversible is gated to a human (the founder): moving or refunding money, publishing legal or contract documents, changing pricing or policy, approving high-stakes regulatory content, or anything it is not confident about. It prepares and recommends; a person approves.

## [Smart Engine] How accurate is the Smart Engine?
It is built for accuracy over guesswork: answers must be grounded in retrieved, verified sources (UAE codes, company knowledge), and it is benchmarked and monitored. When it is not sure, it says so or defers rather than inventing an answer. No system is perfect, which is why grounding, review and human oversight are built in.

## [Smart Engine] Does the Smart Engine guess?
No — it is designed not to. A hard grounding rule requires answers to come from verified knowledge; if the information is not there, it asks you, records it as an open item, or escalates — rather than fabricating specifications, prices or regulations.

## [Smart Engine] How does the Smart Engine use knowledge?
It retrieves from a curated knowledge base — UAE regulations and standards, category expertise, materials and company facts — and grounds its answers in those sources. The knowledge is version-controlled and reviewed before it goes live.

## [Smart Engine] When does the Smart Engine escalate?
Whenever an action is sensitive, irreversible, low-confidence or outside policy — money, legal/contract publishing, pricing or policy changes, high-stakes compliance — it stops and routes it to the founder for approval, with the full context and its recommendation.

## [Smart Engine] How is the Smart Engine monitored?
Every decision passes a governance gate and is written to an immutable log; sensitive actions keep a before-image so they can be undone; and health checks, evaluations and a dedicated Trainer track quality continuously, with alerts surfacing anything that needs attention.

## [Smart Engine] Can the Smart Engine make mistakes?
Yes — any system can, and QuotesDone is built assuming it: grounding to reduce errors, a quality bar on quotes and RFQs, human approval on anything sensitive, an immutable audit trail, and reversibility on sensitive actions — so mistakes are caught, contained and correctable.

## [Smart Engine] How is the Smart Engine continuously improved?
It improves within guardrails: benchmarks and evaluations score its prompts and answers, a Trainer monitors each agent's quality, proposed improvements are tested before going live (only non-sensitive ones auto-promote, always with rollback), and lessons from closed cases feed back into its knowledge.

## [Supplier] How do I register?
Register on the QuotesDone supplier portal: claim or create your company listing, then upload your business documents (trade licence and the others requested). The Smart Engine reviews them and, once approved, you start receiving relevant, anonymised job requests to quote on.
(Audience: supplier)

## [Supplier] What documents are required?
Your valid UAE trade licence is the key document. You will also be asked for supporting details such as your VAT certificate (TRN), bank IBAN, insurance, and your company profile or product catalogue. Keeping your licence and insurance valid keeps your account active.
(Audience: supplier)

## [Supplier] How is my company verified?
Your uploaded documents are read and checked automatically (licence details, issuing authority, expiry) and reviewed for validity and relevance before your account is approved. We confirm your licensed legal name and trade so customers can trust who they are dealing with.
(Audience: supplier)

## [Supplier] How long does verification take?
Verification is fast — up to a maximum of 3 working days once your documents are complete. If anything needs fixing, we tell you exactly what is required.
(Audience: supplier)

## [Supplier] Why was my account rejected?
We rarely reject suppliers. You cannot finish signing up until you have uploaded the required documents on the supplier portal, so an incomplete registration simply is not completed rather than rejected. If a document is invalid or expired, we ask you to update it — fix it and you are good to go.
(Audience: supplier)

## [Supplier] How are projects assigned?
The Smart Engine reads each customer job and matches it to suppliers who can genuinely do it, based on your real capabilities and the emirates you serve. Only genuinely-capable suppliers are invited — you will not be spammed with irrelevant jobs.
(Audience: supplier)

## [Supplier] Can I decline invitations?
Yes — you are free to ignore any invitation that is not right for you; there is no penalty for not quoting. (The only charge is if a customer pays to reveal you and you then ignore them.)
(Audience: supplier)

## [Supplier] How many suppliers receive the same RFQ?
Only suppliers who can genuinely do the job, never a mass blast, and any number of them may quote: there is no fixed limit. The customer sees every quotation, and the comparison report recommends the strongest three by value.
(Audience: supplier)

## [Supplier] How do I submit quotations?
You quote from your supplier portal. Enter an itemised quotation — your line items with brand/model, specifications, quantities and unit prices, plus scope, lead time, validity, warranty and terms. Your quote reaches the customer anonymised; your identity stays hidden until they pay to reveal you.
(Audience: supplier)

## [Supplier] What information is mandatory?
A complete, itemised quote: scope of work; line items with brand/model and specifications; quantities and unit prices; materials; lead time; validity; warranty; payment terms; and any exclusions. Quotes must meet a quality bar before they reach the customer — the Smart Engine coaches you if something important is missing.
(Audience: supplier)

## [Supplier] Can I revise quotations?
Yes, before Reveal. Under Supplier Agreement §12, a quotation is valid for 30 days from submission unless you refresh or withdraw it before Reveal, and you are bound by a quotation that is revealed within that validity period. After Reveal, the contract for the work is solely between you and the customer, on terms you agree; QuotesDone is not a party to it.
(Audience: supplier)

## [Supplier] Can I withdraw a quotation?
Yes — you can withdraw a quotation before a customer reveals it.
(Audience: supplier)

## [Supplier] When do I know if I won?
You are notified the moment a customer pays to reveal your quote — that is your signal to respond and proceed. If the customer chooses another supplier, we let you know too, so you are never left wondering.
(Audience: supplier)

## [Supplier] How are commissions calculated?
There is no commission on won jobs — you keep 100% of the job value. The only charge tied to a job is the non-response charge if you ignore a customer who paid to reveal you: the exact amount refunded to the customer (the 3% reveal fee), the payment processor fee QuotesDone could not recover (from Supplier Agreement v14), an AED 500 administrative fee, and simple interest at 12% a year (or the maximum lawful rate) from the due date.
(Audience: supplier)

## [Supplier] When do I pay?
You pay nothing to quote and nothing when you win — there is no commission. Registration is free for the first 1,000 suppliers who register, and those suppliers stay free permanently. Every supplier who registers after them pays an annual subscription of AED 1,000; there is no fixed start date — it simply applies from the 1,001st registration onward. The subscription is paid on the supplier portal via secure Stripe checkout. The only other possible charge is a non-response fee if you ignore a customer who has already paid to reveal your details.
(Audience: supplier)

## [Supplier] What happens if I don't pay?
If your annual subscription (or a non-response fee) is due and left unpaid, your account is paused from receiving new matches until it is settled on the portal. We remind you first.
(Audience: supplier)

## [Supplier] How is my supplier score calculated?
Your score reflects real performance: customer reviews across communication, quality, punctuality, documentation, after-sales and compliance, plus your responsiveness and dispute record. It builds a trusted reputation that customers can see.
(Audience: supplier)

## [Supplier] How do I improve my ranking?
Respond quickly, submit complete well-itemised quotes, deliver well and earn strong reviews, keep your licence and documents valid, and stay compliant. Merit — not payment — drives your ranking.
(Audience: supplier)

## [Supplier] Can I advertise?
There is no advertising on QuotesDone. Instead, every supplier earns a rating against QuotesDone''s standards based on real performance — you stand out by delivering well, not by paying.
(Audience: supplier)

## [Supplier] Can I operate in multiple Emirates?
Yes — you set the emirates you serve, and you are matched to jobs in each of them.
(Audience: supplier)

## [Supplier] Can I operate in multiple categories?
Yes — you can cover multiple trades/categories. Keep your capabilities profile complete and accurate so the Smart Engine matches you to the right jobs.
(Audience: supplier)

## [Supplier] Is there a subscription fee for suppliers?
Not for the first 1,000 suppliers who register — and never for them. Registration is free for the first 1,000 registered suppliers, who are exempt permanently. Every supplier who registers after them pays an annual subscription of AED 1,000 per year; there is no fixed start date — it applies from the 1,001st registration onward. There is never any commission on the jobs you win.

## [Supplier Intelligence] How is supplier health calculated?
A 0-100 composite: quality 30% + compliance 30% + response 20% + retention 20%. Quality = best of performance score / review quality / rating. Compliance = trade licence + insurance + establishment card + TRN present-and-valid, minus penalties for chat strikes and expired ISO/manufacturer authorisation. Response = reveal-response rate (or quote rate). Retention = recency of activity + active registration. It also outputs a risk tier (high/medium/low).
(Audience: internal)

## [Supplier Intelligence] How is supplier reliability measured?
Mainly the response and retention components plus non-response history: reveal-response rate, quote rate, recency, and any non-response fines or chat strikes. A supplier who is invited but repeatedly does not respond drops on reliability and can be matching-blocked.
(Audience: internal)

## [Supplier Intelligence] How is response quality measured?
From reviews scored across quality, documentation and compliance dimensions (averaged), plus win and quote rates in supplier_perf. Detailed, compliant quotes and good post-job reviews raise it.
(Audience: internal)

## [Supplier Intelligence] How is quotation quality scored?
Itemised quotes are enforced at entry; the comparison engine assesses line detail, spec compliance/deviations and completeness. Vague lump-sum quotes score lower than detailed, spec-matching ones.
(Audience: internal)

## [Supplier Intelligence] How is delivery performance measured?
Honest gap: QuotesDone is an anonymous quotation marketplace up to the reveal, so it does not yet track post-reveal fulfilment/delivery directly. Delivery is proxied by post-job reviews (which can reflect delivery) and win rate, not a dedicated on-time-delivery metric. A post-job delivery/outcome capture is a candidate enhancement.
(Audience: internal)

## [Supplier Intelligence] How are complaints weighted?
Through reviews (low ratings on quality/documentation/compliance), chat strikes and disputes; these reduce the quality/compliance components and can raise the risk tier or trigger a matching block. Repeated complaints escalate.
(Audience: internal)

## [Supplier Intelligence] How is supplier risk calculated?
supplier_health outputs a risk tier: high if banned/matching-blocked/strikes 3+/compliance under 40/health under 40; medium if compliance under 75, any strikes, low retention or health under 65; else low. Expired critical documents and non-response fines push risk up.
(Audience: internal)

## [Supplier Intelligence] How is fraud probability calculated?
fn_fraud_scan flags abnormal signals (e.g. pricing far outside the category band) into fraud_flags; v_fraud_score aggregates open flags into a 0-100 per-actor score with a tier. Honest: it is a rules/heuristic score today, not a trained probabilistic model.
(Audience: internal)

## [System Governance] What are the platform's architectural principles?
Oversight-first (surface, recommend, escalate — never take an irreversible action without founder approval); managed-platform-first (build on Supabase/Vercel rather than self-running infrastructure); config-as-data (critical business rules are tunable data, not hard-coded); deny-by-default security (RLS on every table); single source of truth (e.g. company_faq feeds both the agents and the public site); stateless, independently deployable functions; merit-and-anonymity-based matching; and honesty over overclaiming.
(Audience: internal)

## [System Governance] What coding practices are mandatory?
Backend functions are service-role-only and gated by inbound_secret; database access is parameterized; RLS must be enabled on every new table; secrets and internal file paths are never exposed to clients; brand terminology (Smart Engine; buyers/sellers) is used consistently; syntax is validated before deploy; the change is verified live afterward; and a session log is written. Honest note: these are enforced by convention and oversight, not yet by an automated linter or CI gate.
(Audience: internal)

## [System Governance] What security principles are mandatory?
Deny-by-default RLS; least-privilege RBAC; secrets held service-role-only; founder approval required for any security change; no irreversible action without approval; privacy-preserving defaults; and defer-do-not-bypass when a verification dependency is unavailable.
(Audience: internal)

## [System Governance] What compliance principles are mandatory?
Grounding in UAE law (VAT; the commercial-transactions interest cap; civil-code limits on penalties); the approved no-commission model; legal actions always draft to founder-approve to send, with the signed Terms as evidence; a "this is not legal advice — a UAE lawyer must review" stance on legal templates; the 18+ age gate; and adherence to the data-retention and privacy policies. Honest note: there is no formal external compliance certification (SOC 2 / ISO 27001) yet.
(Audience: internal)

## [System Governance] What data quality standards are enforced?
Itemized, detailed quotes are required (no vague lump sums); supplier capability data is enriched at registration; verification gates matching and reveal; duplication is controlled (backup dedupe keys, quote-set comparison signatures); and canonical answers must be approved before agents use them. Real registered suppliers are kept distinct from the 20,000+ directory leads. Honest gap: there is no formal data-quality monitoring/validation dashboard yet.
(Audience: internal)

## [System Governance] What documentation standards are enforced?
A session log per feature, company_faq documenting real platform behaviour, and llms.txt for machine readers. Honest gap: no formal architecture document or operational runbook library yet.
(Audience: internal)

## [System Governance] What testing standards are enforced?
A live smoke test and verification after every change; a matching-precision benchmark harness; prompt eval/benchmarking before any prompt promotion; and built-in self-test operations for pipelines (e.g. the backup engine). Honest note: there is no automated CI test suite — testing is manual plus targeted harnesses.
(Audience: internal)

## [System Governance] What constitutes production readiness?
Under the working definition: the change is built, syntax-validated, verified live against real data with no regression, gated behind founder approval for anything sensitive, has a known rollback path, keeps secrets isolated and RLS in place, and is documented in a session log. Honest note: this is the operative oversight-based definition — not a formal production-readiness checklist enforced in a pipeline.
(Audience: internal)

## [Technical] What regulations apply?
It depends on the trade and emirate. The Smart Engine draws on an indexed UAE regulatory library and flags the codes relevant to your specific job — for example DEWA for electrical, Dubai Civil Defence (UAE Fire & Life Safety Code) for fire, Dubai Municipality (Al Sa'fat green building, drainage) for buildings, SIRA for security/CCTV, MoIAT/ESMA (ECAS) for products, and Trakhees/DDA inside free zones. The supplier remains responsible for code-compliant design and obtaining authority approvals.

## [Technical] Which standards are used?
UAE.S / GSO national standards, plus the international standards that UAE code references where they apply to the trade (for example ISO and EN, IEC / BS 7671 for wiring, ASHRAE for HVAC, NFPA for fire). The Smart Engine surfaces the standards relevant to your category rather than a single universal list.

## [Technical] Which manufacturers are approved?
QuotesDone does not run its own approved-manufacturer list or endorse particular companies. What matters is that the products quoted meet the required UAE approvals for the job — for example DCD-listed fire products, ESMA/ECAS-conformant regulated products, or DEWA-approved electrical equipment. The Smart Engine references recognised authority approvals; the supplier proposes compliant products.

## [Technical] Which brands are recommended?
QuotesDone is brand-neutral — it does not push or rank specific brands. It makes sure whatever brand is quoted meets the required specifications, standards and UAE approvals for your job; the supplier proposes the brand and you choose. This keeps the marketplace fair and unbiased.

## [Technical] Which materials are suitable?
It depends on the application. The Smart Engine uses its materials knowledge and category specifications to make sure your brief captures suitable material options and the things that drive their price, and notes where the supplier should propose options. It does not dictate a single material — it ensures the choice is captured and compliant.

## [Technical] What certifications are required?
Trade- and product-dependent: for example ECAS/EQM product conformity (MoIAT/ESMA) for regulated goods, SIRA licensing for security work, DCD approvals for fire systems, and manufacturer authorisation for certain branded equipment — alongside the supplier's own valid trade licence and insurance. The Smart Engine flags the certifications relevant to your job.

## [Technical] What warranties are acceptable?
There is no single fixed rule — warranty is a required field in every quote, so it is always stated and easy to compare. Typical UAE practice (such as a workmanship warranty plus the manufacturer's product warranty) is captured per category, and you decide what is acceptable for your job.

## [Technical] What testing is required?
It depends on the system — for example pressure testing for plumbing, insulation-resistance and earthing tests for electrical (DEWA), testing and commissioning for fire systems (DCD/NFPA), or flood tests for waterproofing. The Smart Engine makes sure testing and commissioning are captured in the scope where relevant; the supplier performs and certifies them.

## [Technical] What inspections are required?
Authority inspections depend on the trade — for example a Dubai Civil Defence fire inspection before occupancy, DEWA inspection and energisation for electrical, Dubai Municipality inspections for building works, and Trakhees/DDA inspections inside free zones. The Smart Engine flags the inspections relevant to your job; the supplier or consultant coordinates them.

## [Technical] What approvals are required?
Authority approvals depend on the work and location — DEWA (electrical/utility), Dubai Civil Defence (fire & life safety), Dubai Municipality (building, drainage, green building), SIRA (security), MoIAT/ESMA (product conformity), GCAA (near airports), Trakhees/DDA (free zones) and KHDA (schools/nurseries). The Smart Engine identifies which apply to your job; obtaining them is the supplier's or consultant's responsibility.

## [User Verification] Is customer identity verified?
Customers go through lightweight verification suited to an anonymous B2B marketplace, not full ID/KYC. At sign-up we confirm a working email, apply an 18+ age check, capture and (where enabled) verify a mobile, and record acceptance of the Terms (signed copy stored). No passports or Emirates IDs — the aim is a genuine, reachable account while the customer stays anonymous to suppliers until they reveal.
(Audience: internal)

## [User Verification] Which verification methods are used (customer)?
Email confirmation via a one-time link; SMS six-digit code (Twilio Verify) where enabled; an 18+ age gate; and recorded Terms acceptance with timestamp and IP.
(Audience: internal)

## [User Verification] Is email verification required?
Yes — the customer account is not active until the email is confirmed via the one-time link (24-hour expiry, resendable, rate-limited).
(Audience: internal)

## [User Verification] Is phone verification required?
A mobile is always captured at sign-up, and SMS one-time-code verification is applied when the SMS channel is enabled; the account carries a phone-verified status. It is built as a standard step.
(Audience: internal)

## [User Verification] How are duplicate accounts detected?
Primarily by email — accounts are keyed to a unique verified email, and sign-up blocks a second verified account on the same email (pointing the person to sign in or reset). Phone numbers and behavioural signals add further duplicate/abuse detection.
(Audience: internal)

## [User Verification] Which supplier documents are mandatory?
The core mandatory document is a valid UAE trade licence. Depending on trade, additional documents are requested and checked — establishment card, VAT/TRN certificate, bank/IBAN letter, insurance, ISO certificates, manufacturer authorisations, company profile and catalogues. The licence gates registration; the rest strengthen the profile and are required where the category or job demands.
(Audience: internal)

## [User Verification] How is the UAE Trade Licence verified?
The Smart Engine reads the uploaded licence (extracting licence number, issuing authority, expiry, and licensed company name), those fields are format- and consistency-checked (name matches, not expired), an AI reviewer flags anomalies, and a human admin gives final approval — within a maximum of three working days. Verified against the official licence document, not a live government API.
(Audience: internal)

## [User Verification] How is VAT registration verified?
The TRN is captured and checked for valid format (a UAE TRN is 15 digits) and consistency with the licence and company name, with the VAT certificate on file; mismatches or malformed numbers are flagged. Not every supplier is VAT-registered; where they are, the TRN and certificate are recorded.
(Audience: internal)

## [User Verification] How is company ownership verified?
Through the licence and supporting documents — the licensed company name, the owner/partner or signatory on the licence and establishment card, and the person who accepts the Terms and completes registration (name, contact, signed acceptance with timestamp and IP). Consistency between signatory, account and licence is checked; discrepancies are flagged.
(Audience: internal)

## [User Verification] How are insurance certificates verified?
The certificate is uploaded and recorded with its expiry; presence and validity are checked and shown on the compliance scorecard, and expiry is tracked continuously and flagged as it nears lapse.
(Audience: internal)

## [User Verification] How are ISO certifications verified?
ISO certificates are uploaded, recorded, and their expiry tracked with reminders as they near lapse. They strengthen standing and can be required for jobs that call for them.
(Audience: internal)

## [User Verification] How are manufacturer authorisations verified?
Brand/manufacturer authorisation letters are uploaded and recorded against the brands the supplier claims, with validity/expiry tracked. They matter where a job specifies a brand — the engine can weigh whether the supplier is genuinely authorised — and expiring ones are flagged.
(Audience: internal)

## [User Verification] How are references validated?
Client references and project history are captured as part of the profile and feed the engine's view of capability. They can be spot-checked during review but are supporting evidence, not a hard gate — the mandatory gate is the trade licence and the document/consistency checks.
(Audience: internal)

## [User Verification] How are expired documents detected?
Every dated document (trade licence, insurance, ISO, manufacturer authorisations) has its expiry stored and monitored by a scheduled check. Approaching expiries surface on the compliance scorecard and trigger reminders; once expired, the supplier is treated as non-compliant and held out of matching until a valid renewal is uploaded.
(Audience: internal)

## [User Verification] What causes supplier rejection?
No valid trade licence; an expired or mismatched licence; a company name/owner that does not reconcile; junk/placeholder data; failed format/consistency checks (bad TRN/IBAN); signs of fraud or misrepresentation; or a trade the platform cannot lawfully support. Rejection is a human decision informed by the AI review, with the reason recorded.
(Audience: internal)

## [User Verification] What causes supplier suspension?
For an approved supplier: a compliance lapse (expired licence/insurance), repeated non-response to customers who paid to reveal them, unpaid dues (e.g. an outstanding non-response charge), or policy/behaviour violations and unresolved disputes. Suspension is reversible, recorded with a reason, and applied under admin authority.
(Audience: internal)

## [User Verification] What causes supplier reinstatement?
Remediation of whatever triggered the suspension — renewing the document, settling the amount, resolving the dispute, or correcting the behaviour — after which an admin lifts the matching block. A deliberate, recorded decision; the supplier returns to normal matching once compliant.
(Audience: internal)$qd$, embedding_gte = null where id = '1047' and md5(content) = 'a8b08145956c0065ad565bb72227690e';
update public.kb_chunks set content = $qd$## [RFQ] How are suppliers matched (RFQ)?
The Smart Engine shortlists suppliers by real capability, keywords and the emirates they serve, then judges each candidate on whether they can genuinely do your exact job. Only genuinely-capable suppliers are invited — a wrong match is treated as worse than no match — and any number of the invited suppliers may quote: there is no fixed limit.
$qd$, embedding_gte = null where id = '174634' and md5(content) = '9d7b816355b102cfa83acc705e013e70';
update public.kb_chunks set content = $qd$## [Customer] How many suppliers receive my RFQ?
Only the suppliers who can genuinely fulfil your job — never a mass blast, and any number of them may quote: there is no fixed limit, and you see every quotation that arrives. The comparison report recommends the strongest three by value.
(Audience: customer)
$qd$, embedding_gte = null where id = '174373' and md5(content) = '90534549816ea0635e45ae3a380ab5c8';
update public.kb_chunks set content = $qd$## [Supplier] How many suppliers receive the same RFQ?
Only suppliers who can genuinely do the job, never a mass blast, and any number of them may quote: there is no fixed limit. The customer sees every quotation, and the comparison report recommends the strongest three by value.
(Audience: supplier)
$qd$, embedding_gte = null where id = '174667' and md5(content) = '6f4c6c22631067ae491b115bfc34edb6';
update public.kb_chunks set content = $qd$QUOTESDONE COMPANY FAQ — canonical answers every agent must use verbatim-in-spirit (founder-approved). If asked anything here, answer consistently with this. Do not contradict it or invent beyond it.

## [AI Explainability] Which knowledge was retrieved?
Each decision draws on retrieved kb_chunks and agent_knowledge; kb_usage_log records what knowledge was used, and agent cards cite the source records so a reviewer can see the inputs behind an answer.
(Audience: internal)

## [AI Explainability] Which regulations were used?
For compliance/legal outputs, the cited authority chunks (kb_chunks carry citation + source) are shown; Legal AI references the specific UAE codes/clauses it relied on rather than asserting from memory.
(Audience: internal)

## [AI Explainability] Which supplier capabilities were considered?
The matched candidates and the capability summaries/embeddings that drove the match are recorded on inquiry_matches, and the comparison shows per-supplier (anonymised A/B/C) capability and spec fit.
(Audience: internal)

## [AI Explainability] Which business rules influenced the outcome?
The gates and boosts that applied — eligibility exclusions, verification boosts, the completeness gate, no-commission, anonymity — are the same configurable rules described under Business Rules Engine; the card's reasoning notes which ones fired.
(Audience: internal)

## [AI Explainability] Which assumptions were made?
The Smart Engine states assumptions in its reasoning summary (e.g. inferred spec or assumed quantity) and, when key detail is missing, asks to clarify rather than assume silently.
(Audience: internal)

## [AI Explainability] Which uncertainties remain?
Low-confidence or ambiguous points are flagged in the reasoning and, below threshold, escalated rather than acted on — the card shows what is uncertain instead of hiding it.
(Audience: internal)

## [AI Explainability] Why was not another supplier selected?
Because it ranked lower on capability fit, was ineligible (blocked/expired docs/strikes), or fell outside the filters (emirate/role/product); the ranking inputs make the exclusion explainable. Honest gap: the per-candidate why-not is reconstructable from the match inputs but is not yet rendered as a one-click rejection reason for every non-selected supplier.
(Audience: internal)

## [AI Explainability] How does the platform explain why a supplier was matched to a request?
fn_match_explain returns the same ranking the matching engine uses, but with the score broken into its parts: semantic similarity to the request, a performance boost (up to +0.05 from the supplier's performance score), a claimed-profile boost (+0.03), and an approved-status boost (+0.02), plus a plain-language reason string. This makes every match auditable - you can see exactly why one supplier ranked above another.
(Audience: internal)

## [AI Governance] Which decisions may the Smart Engine make autonomously?
Only low-risk, reversible, internal ones: drafting content and recommendations, ranking and matching candidate suppliers, computing KPIs and health scores, generating draft documents, enqueueing backups, and surfacing alerts and triage. In short — anything that produces a suggestion, a draft, or a read-only computation. It never takes an irreversible or money/permission-affecting action on its own.
(Audience: internal)

## [AI Governance] Which decisions always require human approval?
Anything irreversible or sensitive: sending a message or email to a user, publishing content, charging or refunding money, issuing a legal demand letter, approving or rejecting a supplier's verification, permission or security changes, deleting data, and changing business rules, prompts or knowledge. These are raised as approval cards and wait for the founder.
(Audience: internal)

## [AI Governance] How are AI confidence thresholds defined?
In matching and adjudication the engine is deliberately conservative — "a wrong match is worse than no match" — so low-confidence results are withheld or escalated rather than acted on. Thresholds are set per task and are tunable; below threshold means no auto-suggestion and escalation to a human. Honest note: these thresholds are heuristic and config-driven, not a formally calibrated probability model.
(Audience: internal)

## [AI Governance] How are AI recommendations explained?
Every agent action card carries a plain-language reasoning summary and a click-through to the source record or document that drove it (the click-through to source feature). Quote comparisons show per-supplier rationale, spec deviations and flags. Recommendations are traceable, not black-box — a reviewer can always see why.
(Audience: internal)

## [AI Governance] How is AI bias monitored?
Honest: there is no formal statistical bias-audit pipeline yet. The structural mitigations are real, though: matching is based on stated capabilities and specifications, and suppliers are anonymised (A/B/C) in comparisons, so decisions rest on merit rather than identity — and oversight catches skewed outputs before they act. A formal bias-monitoring process is a gap for later.
(Audience: internal)

## [AI Governance] How are AI models evaluated?
Evaluated continuously by a prompt-benchmark harness. Each candidate prompt/model is scored against a fixed set of graded test cases (currently 21 active cases across the RFQ-intake and quote-review agents, covering ambiguous requests, multi-trade jobs, jurisdiction/scope, UAE regulatory scenarios, spec deviations, marketplace anonymity, and supplier-reliability history). Runs are stored in prompt_eval_runs and the latest score per prompt is exposed via v_eval_latest. A change only ships if it beats the current baseline, and it auto-rolls-back if a later run regresses (auto-promote/rollback governance). Live agent quality is also tracked through the AI observability dashboard (v_ai_observability, v_ai_agent_health).
(Audience: internal)

## [AI Governance] How is AI performance measured?
Per-agent quality metrics from the AI Trainer, benchmark scores on prompt versions, domain KPIs (e.g. matching precision, agent throughput, review outcomes), and — a genuinely useful real-world signal — the rate at which the founder approves vs overrides agent cards. Honest note: there is no single unified model-observability dashboard yet; these signals live in a few places.
(Audience: internal)

## [AI Governance] How are AI failures investigated?
A bad output shows up as a rejected/overridden action card or a flagged item; because each carries its reasoning and a source link, it is traceable to what caused it. The offending prompt can be rolled back (fn_prompt_rollback), a corrected version benchmarked before re-promotion, and the cause and fix recorded in the session log and knowledge. Honest note: investigation is manual and founder-led rather than a formal incident process (this ties to the incident-response runbook already on the flagged list).
(Audience: internal)

## [AI Knowledge Coverage] How is knowledge coverage measured?
Via knowledge_kpis: coverage_pct, knowledge_coverage_pct and playbook_coverage_pct, computed as the share of categories that have knowledge, regulations, specs and playbooks out of categories_total (cat_with_knowledge / cat_with_regs / cat_with_playbook). Snapshots are kept in knowledge_kpi_snapshots.
(Audience: internal)

## [AI Knowledge Coverage] Which domains have weak coverage?
Categories that have some knowledge but no playbook or regulations, or a low coverage_pct — surfaced by the Knowledge Curator and the weekly learn_gaps job. New supplier categories auto-trigger provisioning (scan_new_supplier_categories to category_provision).
(Audience: internal)

## [AI Knowledge Coverage] How are coverage gaps detected?
learn_gaps (weekly) plus knowledge_kpis deltas and kb_usage_log — comparing topics actually queried (topics_queried_30d) against what is covered, so demanded-but-thin domains stand out. New categories detected on the supplier side auto-trigger knowledge provisioning.
(Audience: internal)

## [AI Knowledge Coverage] How are retraining priorities determined?
From learn_gaps findings, eval/benchmark failures, rising human-override rates, and low-coverage categories. Retraining here means updating prompts and knowledge (hosted LLMs, no model training) — the weakest, most-queried gaps are prioritised.
(Audience: internal)

## [AI Knowledge Coverage] How is knowledge completeness monitored?
Daily by the Knowledge Curator via knowledge_kpis — coverage_pct, accuracy_pct, freshness_pct and usage_reach_pct — with knowledge_kpi_snapshots preserving the trend over time.
(Audience: internal)

## [AI Memory & Learning] What information do agents remember?
Two stores: agent_knowledge (durable, curated per-agent knowledge — topic + content + priority, including the compiled Company FAQ in _global) and agent_memory (things learned or reflected on during operation — kind learned or reflection, with a source and an importance weight). They remember policies, canonical answers, lessons from past runs and reflections — not customer personal data beyond what a task needs.
(Audience: internal)

## [AI Memory & Learning] What is temporary memory?
Working context for the task at hand — the current RFQ, the records just retrieved, the conversation — used to reach a decision and not retained as long-term knowledge. Lower-importance agent_memory entries act as short-lived context. Honest: there is no hard time-to-live tier; temporary is effectively low-importance/working context versus the durable stores.
(Audience: internal)

## [AI Memory & Learning] What is permanent memory?
The durable stores: agent_knowledge (curated per-agent knowledge, including the compiled Company FAQ in _global) and higher-importance agent_memory entries. These persist across runs and drive consistent agent behaviour.
(Audience: internal)

## [AI Memory & Learning] How are lessons learned stored?
As agent_memory rows of kind learned (with a source and importance) and, weekly, reflection entries produced by the reflect job that reviews recent activity. High-value lessons can be promoted into curated agent_knowledge under oversight.
(Audience: internal)

## [AI Memory & Learning] How are previous projects reused?
Past RFQs, quotes, matches and comparisons remain in the database and feed retrieval and supplier performance (supplier_perf: matched/quoted/won). The Smart Engine draws on this history when matching and advising; snapshots such as quote comparisons are preserved.
(Audience: internal)

## [AI Memory & Learning] Can agents learn automatically?
Partly. They automatically accumulate reflections (weekly reflect) and learned notes, and performance metrics update continuously. But changes that affect behaviour — prompt changes, new canonical knowledge — go through governance (eval/benchmark + founder approval) rather than silent self-modification. Oversight-first: learning surfaces, humans promote.
(Audience: internal)

## [AI Memory & Learning] How are incorrect memories removed?
A wrong agent_memory/agent_knowledge entry is corrected or deleted under oversight (as done this session when correcting the malware-scanning answers). Canonical answers live in company_faq — the single source of truth — so a fix there recompiles the agents' knowledge. Honest: there is no automatic unlearn; removal is a governed edit.
(Audience: internal)

## [AI Memory & Learning] How is memory versioned?
Curated knowledge (kb_revisions) is versioned with author/reviewer/status/decision timestamps; company_faq edits carry source_note history and recompile on change. Honest gap: agent_memory rows themselves are not individually versioned — versioning lives on the curated knowledge layer.
(Audience: internal)

## [AI Memory & Learning] How are memories searched?
By agent scope (agent_key), relevance (full-text over content and semantic retrieval over kb_chunks), importance and recency. The compiled Company FAQ is always available to every agent via _global.
(Audience: internal)

## [AI Memory & Learning] How is memory quality measured?
Via the AI Trainer (per-agent quality), knowledge KPIs (knowledge_kpis), kb_usage_log (what knowledge is actually used) and eval/benchmark scores. Honest: there is no single memory-quality score; quality is inferred from agent output quality, usage and review status.
(Audience: internal)

## [AI Memory & Learning] How do things an agent learns become permanent, curated knowledge?
Agent learnings live in agent_memory. High-value memories that have not yet been promoted are surfaced in v_memory_promotion_candidates (ranked by importance). When you approve one, fn_promote_memory(memory_id, category) graduates it into the canonical knowledge base (kb_chunks), where it is full-text indexed and semantically embedded like any other knowledge, and becomes retrievable by all agents. Promotions are tracked in memory_promotions so nothing is promoted twice. This keeps a human in the loop between what an agent picked up and what becomes official knowledge.
(Audience: internal)

## [AI Security] How are AI prompts protected?
Every agent's prompt (persona and instructions) lives server-side in the database — never in the browser or client — and is only ever read by the backend. Prompts are versioned, and changes flow through a governed process: staged as a draft, reviewed, then promoted live. Users cannot see or alter an agent's system prompt, and the instruction/data boundary means content an agent reads (a request, a document, a web page) is treated as information to act on, never as new instructions.
(Audience: internal)

## [AI Security] Can prompts be modified?
Yes, but only through the governed pipeline. A change is created as a new draft version, can be evaluated/benchmarked, and is promoted live on approval; a misbehaving live prompt can be rolled back to a previous version. Agents cannot silently rewrite their own live prompts — prompt changes are a reviewed, versioned, reversible administrative action.
(Audience: internal)

## [AI Security] How is prompt versioning managed?
Prompts are stored with full version history (a prompts registry plus a prompt-versions table). Each version is retained, one is marked live, and evaluation/benchmark runs are recorded against versions so quality can be compared before promotion. Promotion and rollback are explicit operations, so you can always see which prompt is live, what changed, and revert.
(Audience: internal)

## [AI Security] How are prompt injections prevented?
By a strict instruction/data boundary and grounding. System prompts are fixed server-side; anything an agent reads — a customer's words, an uploaded document, a supplier profile, retrieved knowledge — is handled as data to analyse, not commands to obey, and briefs are anonymised and structured first. Agents answer only from approved knowledge and cannot take irreversible actions on their own, so an instruction embedded in content cannot make an agent exfiltrate data, move money, or act outside its lane.
(Audience: internal)

## [AI Security] How are jailbreak attempts detected?
Multiple guardrails rather than one filter. Agents are constrained by fixed instructions and produce structured, validated output (strict JSON that is parsed and range-checked); off-pattern or low-confidence output is rejected or held for review; and, critically, no agent can perform a sensitive or irreversible action regardless of what a prompt says, because those are gated behind human approval. Manipulative inputs surface as flags for oversight rather than silently succeeding.
(Audience: internal)

## [AI Security] How are hallucinations minimized?
Grounding first: agents retrieve and answer from the approved knowledge base (company facts, category knowledge, indexed UAE regulations) and are instructed never to invent specs, prices or identities — if something is not stated, they flag it rather than guess. Outputs are low-temperature and structured, the matcher follows "a wrong match is worse than no match" (it can return nothing rather than fabricate a fit), and an AI-Trainer process grades answer quality over time. Low-confidence results are held for a human.
(Audience: internal)

## [AI Security] Must AI retrieve knowledge before answering?
Yes — agents are grounded, not free-form. Before responding, an agent is given its persona plus the relevant knowledge: the canonical company answers, the category-specific quoting knowledge, and any applicable UAE regulations; the matcher retrieves supplier capabilities before adjudicating. This retrieval-before-answer design ties responses to verified, citable facts rather than the model's memory.
(Audience: internal)

## [AI Security] How are AI decisions logged?
Comprehensively. Agent runs are recorded (what ran, when, result); matching/routing decisions store full reasoning (job type, candidates evaluated, why each was included/excluded); recommendations, approvals and escalations go to the action ledger with who decided and when; and evaluation/benchmark runs are kept for prompts and matching. Every consequential AI decision leaves an auditable trail.
(Audience: internal)

## [AI Security] How are AI confidence scores calculated?
Confidence reflects the quality and clarity of inputs and the model's own assessment. For matching it comes from how well a supplier's capabilities fit the actual scope (retrieval similarity plus the adjudicator's judgement); for generated content and extractions, agents mark low-confidence when inputs are thin, ambiguous, conflicting or novel. These are not one universal probability — they are per-task signals whose main job is to trigger caution: low confidence makes the engine exclude rather than guess and routes the decision to a human.
(Audience: internal)

## [AI Security] When must AI escalate to a human?
Whenever a decision is sensitive, irreversible or uncertain — anything touching money, publishing, access/permissions, suspensions or legal matters; any new knowledge needing approval before going live; low-confidence outputs; and anything outside the agent's grounded knowledge. In all these the agent surfaces a recommendation and waits for approval rather than acting — the oversight-first rule.
(Audience: internal)

## [AI Security] How are AI permissions restricted?
Agents act through the same gated backend as everyone else, under an internal service identity, boxed in by the oversight model: they can read what they need and can propose or recommend, but cannot execute sensitive or irreversible actions on their own — those require a human approval step. An agent's effective permission is "surface, recommend, escalate," never unilateral action on money, access or published content.
(Audience: internal)

## [AI Security] Can AI access all customer data?
The backend the agents run on has broad read access to do its work, but agents operate on anonymised, task-scoped briefs and never expose one party's data to another — a supplier-facing agent never sees a customer's identity, and a customer only ever sees their own data. Access is purpose-bound, happens server-side under logging, and identities stay masked until a paid reveal. Agents use data to serve a task; they do not hand it across parties.
(Audience: internal)

## [AI Security] Can AI modify financial data?
No autonomous changes to money. Financial records (charges, refunds, commissions/dues, ledger entries) are produced by governed flows — for example a Stripe payment confirmed by a verified webhook, or a scheduled reconciliation — not by an agent deciding to alter a balance. Agents can compute, analyse and recommend (flag an overdue charge, draft a report), but do not rewrite financial data; anything sensitive routes through human approval.
(Audience: internal)

## [AI Security] Can AI approve payments?
No. Agents never approve, release or move money. Customer payments go through Stripe; refunds and any money movement require the proper flow and human authorisation; the founder approves sensitive money actions through the oversight queue. An agent's role around payments is limited to surfacing, computing and recommending — the approval is always a human decision.
(Audience: internal)

## [AI Self-Monitoring] How is hallucination rate measured?
We do not publish a single numeric "hallucination rate" - that would be misleading. Instead we constrain and measure factuality several ways: (1) agents answer from retrieved, cited knowledge (kb_chunks and the approved Company FAQ) rather than free recall; (2) the prompt-benchmark harness (21 graded cases) rubric-checks whether answers fabricate specs, misread a requested specification, or over-claim, and a regression blocks the release; (3) the AI observability dashboard tracks each agent's override/rejection rate and average confidence, while knowledge KPIs track accuracy, freshness and coverage; (4) low-confidence answers are escalated to a human approval queue rather than sent. This is honest measurement of grounding and human-override signals, not a marketing number.
(Audience: internal)

## [AI Self-Monitoring] How is answer quality measured?
AI Trainer per-agent quality scores, prompt benchmark scores, eval pass rates, and the founder's approve-versus-override rate on agent cards.
(Audience: internal)

## [AI Self-Monitoring] How are weak domains detected?
learn_gaps (weekly) and match_eval surface where retrieval or answers are thin or where matching precision drops; category knowledge gaps trigger provisioning.
(Audience: internal)

## [AI Self-Monitoring] How is prompt performance measured?
prompt_eval_runs + prompt_benchmarks score each prompt version against seed cases before promotion; regressions block promotion and can roll back.
(Audience: internal)

## [AI Self-Monitoring] When is retraining required?
There is no model training here (hosted LLMs via OpenRouter); retraining means updating prompts/knowledge. It is triggered when eval/benchmark scores drop, learn_gaps finds recurring misses, or override rates rise — then a new prompt/knowledge version is drafted, benchmarked and approved.
(Audience: internal)

## [AI Self-Monitoring] How are failed conversations reviewed?
Poor outcomes surface as overridden/rejected agent cards, low review scores, and qa_suite/smoke findings; the AI Trainer and founder review them, and fixes flow through prompt/knowledge governance.
(Audience: internal)

## [AI Self-Monitoring] How is AI agent health and observability monitored?
All Smart Engine signals are unified in one live AI observability dashboard backed by two database views. v_ai_observability gives the 24-hour picture: agent runs and errors, the open human-approval queue, average evaluation score, knowledge-base confidence, coverage and embedding progress, and how many knowledge chunks are due for review. v_ai_agent_health gives per-agent 30-day detail: runs, errors, action volume, a human-override/rejection proxy rate, average confidence, and last-run time. Errors are caught via agent run status, and anything low-confidence is routed to a human approval queue instead of acting autonomously. The dashboard refreshes live from the database each time it is opened.
(Audience: internal)

## [AI Self-Monitoring] Is the platform security posture audited on a schedule?
Yes. Alongside the existing daily backup, monthly disaster-recovery restore drill (dr_drill), malware hash-scanning (vt_scan), fraud scan (fn_fraud_scan) and security scan (fn_security_scan), a daily security self-audit (cron security_selfaudit_daily calling fn_security_selfaudit) snapshots the database security posture: the number of public tables with row-level security disabled (must stay 0 under deny-by-default), tables with RLS enabled but no policy (the intentional service-role-only tables), SECURITY DEFINER views, and definer functions callable by anonymous users. If any public table ever has RLS disabled it raises a high-severity security event. Snapshots are retained in security_selfaudit_snapshots so posture drift is visible over time. A managed advisor baseline on 2026-07-11 recorded 17 ERROR, 86 WARN and 165 INFO findings; the INFO class is the deny-by-default design, and the ERROR/WARN classes are queued for careful, application-safe review.
(Audience: internal)

## [AI Self-Monitoring] Does the platform alert when AI quality degrades?
Yes. A daily watch (cron ai_quality_watch_daily calling fn_ai_quality_watch) checks for two things: evaluation regressions (a prompt's latest benchmark score dropping more than 5 points below its previous run, or below 70 absolute) and override spikes (a human-facing agent's rejection rate jumping more than 20 points above its own trailing average). Anything it finds is written to security_events (kind eval_regression / override_spike), raised as an ai_quality_alert action, and emailed to the founder - deduplicated so you are not spammed. Per-agent override history is snapshotted in ai_quality_snapshots so spikes can be detected over time.
(Audience: internal)

## [API Security] How are APIs authenticated?
Every backend endpoint is an Edge Function that authenticates its caller first. User calls carry a Supabase-issued JWT in the Authorization header, validated for signature, expiry and user. Service-to-service and scheduled calls present a shared internal secret instead. Inbound third-party webhooks (e.g. Stripe) are authenticated by verifying a cryptographic signature. Any unauthenticated public read uses a restricted anon key that is still bound by row-level security.
(Audience: internal)

## [API Security] How are APIs authorised?
After authentication, each function resolves the caller's role and checks both the permission for the action and ownership of the target record before running logic — a customer can only act on their own inquiries; admin endpoints admit only owner/admin roles. Row-level security is a second, independent gate. Failing any check returns 401/403 with no data.
(Audience: internal)

## [API Security] How is rate limiting implemented?
Rate limiting is applied where abuse matters most — the auth flows cap attempts (email links and SMS codes are limited per email/number per hour, reset requests throttled), and money/reveal flows are idempotent so repeats cannot double-charge. The managed platform (Supabase/Vercel) provides baseline network-level protection. There is not a single global API-gateway rate limiter yet; limits are targeted at the endpoints that need them and can be broadened as traffic grows.
(Audience: internal)

## [API Security] How are API keys rotated?
Third-party keys and the internal service secret live in the server-side, RLS-protected secrets table, so rotating one is a single update there — no code change, no redeploy — effective on the next call. Because keys are read at call time rather than baked into the build, rotation is fast and low-risk; a compromised key can be replaced immediately.
(Audience: internal)

## [API Security] How are webhooks verified?
Inbound webhooks are cryptographically verified before they are trusted. The Stripe webhook recomputes the HMAC-SHA256 signature over the raw payload using the signing secret and compares it to the Stripe-Signature header, rejecting anything that does not match. Internal service webhooks are gated by the shared internal secret. An unverified webhook is discarded with a 400.
(Audience: internal)

## [API Security] How are replay attacks prevented?
Several layers. Signed webhooks include a timestamp and are accepted only inside a short tolerance window (about 10 minutes for Stripe), so a captured old delivery is rejected. One-time tokens (email confirmation, password reset, OTP) are single-use and expire quickly. And money/dispatch operations are idempotent (keyed on the underlying record), so a replayed request cannot create a second charge, match or reveal.
(Audience: internal)

## [API Security] How are CORS policies configured?
Edge Functions set explicit CORS headers and handle preflight (OPTIONS) requests, permitting only the headers and methods the app needs (Authorization, Content-Type; POST/OPTIONS). CORS is a browser convenience, not the security boundary — every request is still authenticated and authorised server-side and constrained by RLS, so a permissive origin cannot reach protected data without valid credentials.
(Audience: internal)

## [API Security] How are API errors sanitized?
User-facing responses return clear, generic messages — no stack traces, SQL, secrets or connection strings are exposed to clients. Auth flows are deliberately vague where it matters (reset responses do not reveal whether an email exists) to prevent enumeration. Full diagnostic detail stays server-side in logs, not returned to the caller.
(Audience: internal)

## [API Security] How are request IDs generated?
Requests are traceable through platform-assigned identifiers: Vercel and Supabase attach request/execution IDs to each call and its logs, and outbound calls made from the database (via pg_net) carry their own request IDs whose responses are recorded. These let a specific request be followed across the frontend, the function and any downstream call when investigating an issue.
(Audience: internal)

## [API Security] How are API logs retained?
Function and database request logs are retained by the managed platform (Supabase/Vercel) for monitoring and debugging within their retention windows. On top of that, business-level activity — agent runs, decisions, approvals, money events, notifications — is written to durable tables that persist as long as the records do. So there is both short-term infrastructure logging and a long-term, queryable audit trail.
(Audience: internal)

## [Authentication] How do users authenticate?
Users authenticate with email and password through Supabase Auth (the managed identity service). On sign-up they create an account (with an 18+ age check), confirm their email via a one-time link, and — where enabled — verify their mobile by SMS code. On sign-in, Supabase Auth issues a signed session (a JWT access token plus a refresh token) that the app sends on every backend call; Edge Functions verify it before running any logic. Internal OS/admin access additionally checks the user's role.
(Audience: internal)

## [Authentication] Which authentication methods are supported?
Email-and-password sign-in via Supabase Auth is the primary method for both customers and suppliers. Email confirmation (one-time link) and SMS phone verification (Twilio Verify, six-digit code) validate identity at sign-up. Internal staff/admin access is the same email login plus a role check. There is no social/SSO login today, though Supabase Auth can add providers if needed.
(Audience: internal)

## [Authentication] Is MFA supported?
A phone one-time-code step (SMS via Twilio Verify) is used alongside email confirmation to verify accounts, adding a second factor at onboarding when enabled. Ongoing, per-login multi-factor (e.g. an authenticator/TOTP app) is not enforced today, but the identity layer (Supabase Auth) supports adding it — most sensibly for admin/OS accounts first.
(Audience: internal)

## [Authentication] How are passwords stored?
Passwords are never stored by QuotesDone in readable form and never touch our database or logs. They are handled entirely by Supabase Auth, which keeps only a salted one-way hash (bcrypt). The application only ever passes a password to the managed auth service to set or verify it — it cannot read it back. A minimum length (8+ characters) is enforced.
(Audience: internal)

## [Authentication] How are password resets handled?
A user requests a reset by email; if an account exists, a single-use link with a short expiry (one hour) is emailed. Following it lets them set a new password, which the managed auth service re-hashes. The flow is enumeration-safe (same response whether or not the email exists), single-use, expiring, and rate-limited against abuse.
(Audience: internal)

## [Authentication] How are sessions managed?
Sessions are managed by Supabase Auth. On sign-in the user gets a short-lived JWT access token and a longer-lived refresh token, held by the Supabase client in the browser. The access token accompanies each backend request; as it nears expiry the client transparently exchanges the refresh token for a new one, so the user stays signed in without re-entering credentials. Signing out revokes the session.
(Audience: internal)

## [Authentication] How are JWTs validated?
Every privileged backend call carries the JWT in the Authorization header. The Edge Function validates it against Supabase Auth (signature, expiry, and resolving the user) and only then runs — mapping the user to a customer, supplier or admin and enforcing role and ownership before touching data. Requests with a missing, invalid or expired token are rejected (401). Service-to-service and scheduled calls use a separate internal secret instead of a user JWT.
(Audience: internal)

## [Authentication] What happens when a token expires?
An expired access token is rejected by the backend. In normal use the client refreshes it silently (via the refresh token) before it lapses, so the user is not interrupted. If the session can no longer be refreshed — after a long absence or a sign-out — the user is asked to sign in again. No privileged action ever runs on an expired token.
(Audience: internal)

## [Authentication] How are refresh tokens secured?
Refresh tokens are issued and rotated by Supabase Auth and stored by the Supabase client on the user's device, transmitted only over HTTPS. They rotate (each refresh issues a new one and invalidates the old), can be revoked (sign-out or admin action), and are never placed in URLs or exposed to logs. Because all sensitive logic runs server-side, a token alone still cannot bypass the role and ownership checks each request enforces.
(Audience: internal)

## [Authentication] How are inactive sessions terminated?
Access tokens are short-lived and every sensitive request re-verifies the token and the user's role, so a stale token cannot act. A session ends when the user signs out or an admin revokes it, and one that can no longer be refreshed forces a fresh sign-in. Absolute and idle session timeouts can be enforced through the auth configuration — recommended especially for admin/OS accounts — so long-inactive sessions are logged out automatically.
(Audience: internal)

## [Authorization] Which user roles exist?
Three tiers. Marketplace roles: customer (buyer), supplier (seller), and guest (unauthenticated). Internal/staff roles, in order of privilege: owner (the founder), admin, ops, finance, support, and agent (Smart Engine service accounts). A user's role is resolved from an explicit assignment first, then falls back to owner (on the admin list), supplier (a claimed lead), customer (a registered account), or guest.
(Audience: internal)

## [Authorization] How are permissions assigned?
Permissions are role-based. Staff/agent roles are assigned explicitly in a roles / user-roles table with a role-to-permissions mapping; marketplace roles are derived from the person's relationship to the data (a claimed supplier lead becomes a supplier, a registered account becomes a customer). On top of the role, the database enforces row-level security and every privileged Edge Function re-checks the caller's role and their ownership of the specific record before acting.
(Audience: internal)

## [Authorization] What is RBAC?
Role-based access control — access is granted by the role a user holds rather than per-user rules. QuotesDone uses it: a small set of roles (owner, admin, ops, finance, support, agent, supplier, customer, guest) each carry defined permissions, users map to roles, and the backend checks the role on every request. Privileges change by moving a user between roles, not by editing scattered rules.
(Audience: internal)

## [Authorization] Is ABAC implemented?
Not as a separate policy engine, but attribute/ownership checks are layered on top of RBAC. Beyond "what role are you," the system enforces "is this yours" — a customer sees only their own inquiries, a supplier only their own profile and quotes, files open only via short-lived signed links, and flags like verification status, licence validity and matching-block are checked. These relationship/attribute checks act like ABAC where it matters.
(Audience: internal)

## [Authorization] How are permissions inherited?
Roles are ranked and higher roles subsume lower ones — owner is most privileged, then admin, then the specialised staff roles; when a user holds more than one role, the most privileged wins. Marketplace roles do not inherit staff privileges. The model is deliberately flat and explicit rather than a deep inheritance tree, so access stays predictable.
(Audience: internal)

## [Authorization] How are API permissions validated?
On every privileged call the Edge Function validates the JWT, resolves the caller's role, and confirms both the required permission for that action and ownership of the target record before running any logic — all server-side. The database's row-level security is a second, independent gate. Service-to-service and scheduled calls carry a separate internal secret instead of a user role. Anything failing these checks is refused.
(Audience: internal)

## [Authorization] Can permissions be overridden?
No self-service or silent override. Elevated access comes only from an explicit role assignment by the owner/admin, and the Smart Engine agents cannot override the oversight gates — sensitive or irreversible actions are surfaced for human approval rather than force-executed. Any change to who can do what is a deliberate, recorded administrative action.
(Audience: internal)

## [Authorization] How are admin privileges controlled?
Admin/OS access is tightly gated: the internal OS backend admits only owner/admin roles (resolved from the role table plus the trusted admin-email list) and checks the caller's identity on every action. Admins act through the same audited APIs as everyone else — not direct database access — and the most sensitive operations still route through the approval queue. The admin list and role assignments are themselves controlled by the owner.
(Audience: internal)

## [Authorization] How are temporary permissions granted?
Through time-boxed, scoped grants rather than standing access: documents are reached via short-lived signed URLs that expire in minutes; email-confirmation, password-reset and phone-code tokens are single-use and expire quickly; internal service calls use a rotatable shared secret scoped to server-to-server use. There is no general temporary-role hand-out — elevation is an explicit role change, and transient access is always narrow and self-expiring.
(Audience: internal)

## [Authorization] How are privileged actions audited?
Privileged and agent actions are recorded. The approval/action ledger captures each sensitive decision with who decided, when, and the outcome; agent runs, matching/routing decisions, cancellations, backups, notifications and money events are logged with timestamps. Because all privileged work goes through server-side APIs (not raw database access) and the Smart Engine is oversight-first, there is a consistent trail of what was proposed, what a human approved, and what was executed.
(Audience: internal)

## [Availability] What uptime target is maintained?
QuotesDone aims for high availability by building on managed, highly-available platforms — Vercel for the site and Supabase for the backend, which target around 99.9%+ — and by running a scheduled uptime check with founder alerts. Honestly, QuotesDone does not publish its own contractual SLA yet; the practical target is "always-on" with rapid detection and recovery, inheriting the providers' availability. A formal internal uptime objective can be set and measured as the business matures.
(Audience: internal)

## [Availability] How is redundancy implemented?
Largely inherited from the managed stack. The public site is static and served from Vercel's global CDN, replicated across many edge locations. The backend runs on Supabase (AWS), which provides managed availability, automated backups and infrastructure redundancy. Documents have an independent second copy in the company's Dropbox. Edge Functions are stateless, so they scale and recover across the platform's capacity. Honest note: the database runs as a managed primary — cross-region replicas/high-availability tiers are plan-dependent and a scaling decision as volume grows.
(Audience: internal)

## [Availability] How are deployments performed with minimal downtime?
Effectively zero-downtime. The website is published as an atomic Vercel deployment: a new immutable build is prepared and promoted in one switch, with instant rollback if needed — visitors are never served a half-updated site. Backend Edge Functions are deployed one at a time and versioned, so a new version takes over cleanly without a service window. Database changes go through incremental migrations, most applied online. There is no "site down for maintenance" step in normal releases.
(Audience: internal)

## [Availability] How are maintenance windows managed?
Routine platform maintenance (of the managed database and hosting) is handled by the providers with their own high-availability practices, so it generally does not require QuotesDone to schedule downtime. QuotesDone's own changes are incremental and hot-deployed rather than needing a window. If a change ever did need a brief window, it would be scheduled for a low-traffic period and communicated. Today, planned downtime is the exception, not a regular event.
(Audience: internal)

## [Availability] How are rolling updates performed?
Because the system is composed of many small, independently deployable pieces, updates roll out piece by piece rather than as one big-bang release: each Edge Function is deployed on its own and versioned; the static site is swapped atomically; agents and scheduled jobs are updated independently. This lets a change ship and be verified in isolation — and be rolled back on its own if needed — without taking the whole platform offline.
(Audience: internal)

## [Availability] How is failover handled?
Infrastructure failover is provided by the managed platforms — Vercel automatically routes around unhealthy edge locations, and Supabase/AWS handle underlying infrastructure faults — while the stateless Edge Functions simply recover as capacity returns. On top of that, the uptime check plus founder alerts catch problems quickly, and the independent Dropbox backup and database backups mean data can be recovered even in a worst case. Honest note: automatic, self-managed cross-region database failover is not in place (it depends on a higher-availability database tier); adopting a high-availability database configuration is the natural next step for stronger failover as the platform scales.
(Audience: internal)

## [Business Continuity] How does the business continue if an AI service is unavailable?
The Smart Engine calls its models through OpenRouter with multiple model fallbacks, so a single model going down usually just shifts to another. If the whole LLM provider is unavailable, the oversight-first design protects the business: agents never auto-act, so a stalled agent means items simply wait for human review rather than producing wrong actions. The core marketplace — posting RFQs, submitting quotes, reveals, payments — does not depend on the LLM, so it keeps working; only the smart layers (match suggestions, quote comparisons, agent recommendations) pause. Honest note: those smart features stay unavailable until the provider recovers; there is no on-prem model fallback.
(Audience: internal)

## [Business Continuity] What happens if Stripe is unavailable?
New payments (reveal fee, supplier subscription) cannot be taken while Stripe is down. The webhook is idempotent and signature-verified with a tolerance window, so when Stripe recovers, its retried events reconcile cleanly with no double-charging. Everything that is not a payment continues normally. Honest gap: Stripe is the only processor — there is no alternative payment rail today.
(Audience: internal)

## [Business Continuity] What happens if Dropbox is unavailable?
Little impact, because Dropbox is a secondary backup mirror, not the system of record. The originals live in Supabase Storage and are also covered by Supabase's managed daily backups. If Dropbox is offline, the 15-minute backup queue just retries later — the pending doc_backups rows stay queued and catch up when it returns. Nothing user-facing depends on Dropbox.
(Audience: internal)

## [Business Continuity] What happens if email delivery fails?
The platform keeps running. Where SMS OTP is enabled it can carry verification, and critical notifications, alerts and collections items are also surfaced in-app (agent action cards / notifications), so the founder and users still see them even if an email does not arrive. Honest gap: failed emails are not yet on a robust retry / dead-letter queue with a delivery dashboard — that is a monitoring gap, mitigated today by the in-app cards for anything important.
(Audience: internal)

## [Business Continuity] What happens if SMS delivery fails?
SMS (Twilio Verify OTP) is one verification factor, gated by the sms_enabled flag. If SMS is failing, verification can fall back to email verification plus the age gate, and sms_enabled can be switched off so sign-ups are not blocked. Honest note: this temporarily removes one security factor until SMS is restored.
(Audience: internal)

## [Business Continuity] What happens if the database is temporarily unavailable?
This is the genuine hard dependency: if Postgres is down, the application backend is down (it runs as a single managed primary — see Availability). Supabase handles infrastructure-level recovery, and because the public site is static on Vercel's CDN, the marketing and FAQ pages stay reachable and serve cached content even while the app backend is impaired. Worst-case data recovery is restore-from-backup. Honest note: there is no self-managed hot standby / read-replica failover yet — a high-availability database tier is the planned next step.
(Audience: internal)

## [Business Continuity] What happens if an external government verification service is offline?
Verification is deferred, not skipped. If an external source (e.g. trade-licence lookup) is offline, the supplier stays in a pending/unverified state and the matching and reveal gating hold until verification completes — oversight-first means the platform will not auto-approve to work around an outage. The check is queued and finished when the service returns. Honest note: there is no auto-pass fallback, which is deliberate — deferring is safer than approving unverified sellers.
(Audience: internal)

## [Business Rules Engine] How is supplier ranking calculated?
Two layers. Retrieval (match_suppliers) ranks candidates by semantic capability fit — pgvector similarity (1 minus cosine distance) between the RFQ embedding and each supplier's capability embedding — plus small boosts: +0.05x performance score, +0.03 if the profile is claimed/registered, +0.02 if approved; filtered by emirate/role/product/min-rating and excluding matching-blocked suppliers. A full-text variant runs alongside for hybrid retrieval. The Smart Engine then adjudicates the shortlist conservatively (a wrong match is worse than no match). Ranking is capability-first, lightly adjusted for track record and verification.
(Audience: internal)

## [Business Rules Engine] How is supplier priority determined?
Within a matched set, priority favours best capability fit, then verified (claimed/approved) status and higher performance, while health/risk gates apply (banned, matching-blocked, 3+ strikes, or compliance under 40 are effectively excluded). It is about who is surfaced/invited first — there is no pay-to-rank queue-jump.
(Audience: internal)

## [Business Rules Engine] How are invitations distributed?
Two separate things: (a) RFQ routing — when a buyer posts, dispatch_inquiry notifies the matched, eligible suppliers, with a guard that stops incomplete matches from being dispatched; (b) directory onboarding invites — enqueue_supplier_invites reaches unclaimed directory leads, gated by an invite_enabled flag and a daily cap (default 40), one per email, skipping suppressed/opted-out addresses. Both are governed and capped.
(Audience: internal)

## [Business Rules Engine] How are conflicts of interest handled?
Structurally minimised: buyers stay anonymous to suppliers, suppliers cannot see each other's quotes (blind quoting), and QuotesDone takes no commission on won jobs — so there is no financial incentive to steer a buyer anywhere. Matching is on stated capability + verification, not relationships. Honest gap: there is no automated same-owner/duplicate-entity COI detector yet beyond duplicate-account checks. Update (2026-07-11): a v_supplier_coi detector now flags claimed suppliers sharing a phone, WhatsApp, email, TRN or trade-licence number — surfacing likely same-owner/duplicate entities for review.
(Audience: internal)

## [Business Rules Engine] How are tie-breakers resolved?
When capability fit is close, the ordering formula breaks ties by performance score, then verified (claimed/approved) status, then health signals (compliance/response/recency) — favouring the more reliable, active, verified supplier. Ties never resolve randomly or toward whoever paid.
(Audience: internal)

## [Business Rules Engine] How is RFQ priority calculated?
RFQs are handled in arrival order with a completeness gate: one missing the detail needed to match well is clarified first (run_rfq_clarify) rather than dispatched to weak matches. There is no paid fast lane for buyers — urgency is served by clarify-then-dispatch, not priority payments.
(Audience: internal)

## [Business Rules Engine] How is quotation weighting calculated?
In the buyer's comparison, quotes are weighed on total price, itemised line detail, spec compliance/deviations, and completeness — not on supplier identity (suppliers are anonymised A/B/C). Detailed, spec-matching quotes beat vague lump sums (itemised quotes are enforced at entry). The tool surfaces trade-offs; it does not auto-pick a winner.
(Audience: internal)

## [Business Rules Engine] When does the Smart Engine override normal routing?
Rarely and conservatively — it withholds or reroutes when confidence is low, when a supplier is ineligible (banned, matching-blocked, expired critical docs, 3+ strikes), or when an RFQ is too incomplete to match, in which case it escalates to clarify or human review rather than dispatch. An override never silently picks a favourite; it holds or escalates.
(Audience: internal)

## [Business Rules Engine] When are suppliers excluded?
When matching_blocked or banned is set, an unsettled non-response fine holds them, chat strikes hit 3, critical compliance is missing/expired (trade licence/insurance pushing compliance under 40), or registration has lapsed. match_suppliers hard-excludes matching-blocked suppliers at the query level; health scoring pushes high-risk ones down or out.
(Audience: internal)

## [Business Rules Engine] How is fairness maintained?
Blind, anonymous quoting (no identity-based favouritism); no commission (no incentive to steer); merit-based matching on capability + verification; no pay-to-rank; capped, opt-out-respecting invitations; and every routing decision is explainable and auditable. Honest note: the free-onboarding tier and the small verification boosts are a deliberate, disclosed thumb-on-scale toward verified suppliers — fairness here means merit + verification, not treating verified and unverified identically.
(Audience: internal)

## [Company Identity] What is QuotesDone?
QuotesDone is a UAE B2B anonymous quotation marketplace based in Dubai. A customer (buyer) posts what they need — by text, voice, photo or drawing — and our Smart Engine turns it into a clear, priceable brief and matches it to vetted suppliers (sellers) who submit anonymised quotes. The buyer compares the quotes and pays a 3% reveal fee on the quote they choose to unlock that seller's identity and contact details. It is operated by QuotesDone Technologies, a Dubai DET-licensed business (E-Trader Licence No. 1633275).

## [Company Identity] Why was QuotesDone created?
QuotesDone was created to fix how construction and services buying works in the UAE: getting several comparable quotes today means chasing suppliers one by one, sharing your contact details up front, then fielding calls and haggling — while suppliers waste time on jobs that aren't really theirs. QuotesDone lets a buyer describe a job once and receive comparable, anonymised quotes from genuinely capable suppliers, staying in control until they choose.

## [Company Identity] What problem does QuotesDone solve?
For buyers: sourcing multiple trustworthy, comparable quotes is slow and opaque, and once your number is out you get spammed and pressured. For sellers: most leads are irrelevant or already shopped around. QuotesDone solves both — the buyer posts once, Smart Engine structures the request and routes it only to suppliers who can genuinely do it, quotes come back structured, comparable and quality-checked, and everything stays anonymous with no off-platform contact until the buyer pays to reveal their chosen supplier.

## [Company Identity] Who is QuotesDone for?
Two sides. Customers (buyers) — UAE businesses and individuals who need to buy construction, fit-out, MEP and related products or services and want fast, comparable quotes without exposing themselves to spam. Suppliers (sellers) — vetted UAE contractors, fabricators, tradespeople and suppliers who want qualified, relevant job requests they can quote on.

## [Company Identity] What industries does QuotesDone support?
Construction and the built-environment services around it: building & fit-out / interior design, MEP (electrical, fire, HVAC, plumbing), aluminium & glass, joinery & custom furniture, flooring & tiling, false ceilings & gypsum, painting, waterproofing, landscaping & swimming pools, signage, CCTV & security systems, smart-home automation, solar, facilities management, cleaning, pest control, movers, AC maintenance and more — with new trades added automatically as suppliers register them.

## [Company Identity] What countries does QuotesDone operate in?
QuotesDone currently operates in the United Arab Emirates — all seven emirates — and is based in Dubai. Expansion to Saudi Arabia (KSA) is planned but not yet live.

## [Company Identity] What is the company's long-term vision?
To become the trusted procurement layer for the region — the default way buyers source and compare quotes across the GCC — expanding from the UAE into Saudi Arabia and beyond, and growing from single-job RFQs toward Smart-Engine-assisted procurement for larger, multi-trade projects.

## [Company Identity] What are the company's core values?
Anonymity & buyer control (no off-platform contact before reveal); Honesty (agents never over-promise or invent — answers are grounded in real data); Fair, quality-comparable quotes; Supplier respect (relevant matches only, seller-friendly economics); Trust & accountability (licensed entity, vetted suppliers, auditable and reversible Smart Engine).

## [Company Identity] How is QuotesDone different from competitors?
Four things: (1) Anonymity — buyers and sellers don't exchange contact details until the buyer chooses and pays to reveal, so no spam and no going around the platform. (2) Sharp Smart Engine matching — an Smart Engine reads the actual job and routes it only to suppliers who can genuinely do it, instead of blasting every lead to everyone. (3) Structured, comparable, quality-checked quotes, not messy free-text. (4) Seller-friendly economics — suppliers pay no commission on won jobs and start free; the buyer only pays a 3% reveal fee on the quote they actually choose.

## [Company Identity] What makes QuotesDone trustworthy?
It is a licensed Dubai business (QuotesDone Technologies, DET E-Trader Licence No. 1633275). Suppliers are vetted (licence/KYC checks). Buyer and seller details stay masked until a paid reveal, protecting both sides. Quotes are structured and quality-gated so buyers compare like-for-like. The Smart Engine is governed and grounded — it answers from verified company and regulatory knowledge rather than guessing, sensitive actions are logged and reversible, and data is handled under UAE PDPL with security controls.

## [Company Policies] Supplier onboarding policy
Suppliers self-register or claim an existing listing, submit their trade licence and KYC documents, and are verified before going live (verification within a maximum of 3 working days; approval is automatic once the documents pass these checks and the supplier has confirmed its services, and a licence from a foreign or unconfirmed issuing authority is held). Approval is merit-based — there is no paid ranking or advertising. Registration is free for the first 1,000 registered suppliers, who remain free permanently; every supplier after them pays an annual subscription of AED 1,000, with no fixed start date.

## [Company Policies] Customer onboarding policy
Customers sign up with phone/email verification and accept the Terms & Conditions (a signed copy is stored). Posting requests, receiving and comparing quotes is free; a customer pays only the 3% reveal fee on the quote they choose to unlock. Customers remain anonymous to suppliers until they reveal.

## [Company Policies] Document policy
Documents (licences, profiles, catalogues, drawings, quotes, signed terms) upload up to 1 GB into access-controlled storage; large files are stored in full and auto-distilled for the Smart Engine. Originals are backed up to Dropbox in an organized tree. Files open only via short-lived signed links to authorized users; parties never see each other's private documents.

## [Company Policies] Privacy policy
Customer and supplier identities stay masked (suppliers appear as A/B/C to customers; customers are anonymous to suppliers) until a paid reveal. Personal data is used only to operate the marketplace, is never sold, and is handled under UAE PDPL with least-privilege access. Data-subject access and erasure requests are supported.

## [Company Policies] Data retention policy
Operational records and documents are retained while an account is active and for as long as needed to run the marketplace and meet legal, tax and dispute obligations; backups are kept in Dropbox. Erasure requests are honored under PDPL, subject to legal holds. Agents never hard-delete data — removal is a governed, human-approved action.

## [Company Policies] AI governance policy
The Smart Engine is oversight-first: agents surface, recommend and escalate, but never take irreversible action without founder approval. Low-confidence output is held for review; matching follows "a wrong match is worse than no match"; anonymity is enforced; and changes to agent knowledge are gated, reviewable and reversible (with rollback). Agents answer only from approved, grounded knowledge.

## [Company Policies] Knowledge governance policy
There is one canonical knowledge base. New or changed knowledge (categories, regulations, company facts) is staged and approved before it goes live; the Knowledge Curator monitors coverage and staleness. Agents cite official sources and stay brand-neutral — no manufacturer endorsements or recommended-brand lists.

## [Company Policies] Security policy
Access is deny-by-default with role-gated admin and least-privilege service access; all business logic runs server-side and secrets are never exposed. Data is encrypted in transit and at rest, documents are reached only via short-lived signed links, and the Security agent continuously monitors posture and risk. Each party sees only their own data.

## [Company Policies] Refund policy
Refunds are returned to the customer's original payment method via Stripe, and every refund is the founder's decision — none is automatic. The ladder runs from the customer's payment: if the revealed supplier has not responded by working day 3, our Customer Success Director chases them with the customer copied; still silent on working day 5, the founder is notified for the final call; no response to that and the customer's 3% reveal fee is refunded in full, with banks taking 7-14 working days to show it. The non-responding supplier then owes the refunded fee plus an AED 500 administrative fee and 12% per annum simple interest (the rate agreed in Supplier Agreement v14; 9% under v13 or earlier), except where such a charge is not permitted under UAE law, and is held from new matches until it is settled. Working days are Monday to Friday, UAE public holidays excluded. Other refund requests made within the 5-working-day refund window are reviewed and, if valid, refunded the same way.

## [Company Policies] Suspension policy
Suspension (matching blocked) is a reversible hold that stops new matches and quoting; a ban removes a party from the marketplace. Triggers include compliance lapses (e.g. an expired licence), repeated non-response, unpaid dues, or policy and behaviour violations. Actions are recorded with a reason and applied under admin authority; reinstatement follows remediation.

## [Company Policies] Commission policy
QuotesDone charges suppliers no commission on won jobs — suppliers keep 100% of the job value. The only amounts collected from suppliers are the annual subscription (AED 1,000/year, never applicable to the first 1,000 suppliers who registered, applying from the 1,001st registration onward with no fixed start date) and a non-response charge (the customer's refunded reveal fee plus an AED 500 administrative fee and 12% per annum interest) if a supplier ignores a customer who paid to reveal them, applied except where not permitted under UAE law. The customer separately pays a 3% facilitation fee only when they choose to reveal a supplier's contact details.

## [Company Policies] Quality policy
Quotes must be itemized and detailed (no lump-sum guesses), so customers compare like-for-like and the comparison catches hidden costs, low-spec substitutions and missing items. Suppliers are vetted and rated on merit; agents are grounded in approved knowledge and continuously trained. The guiding principle throughout is accuracy over volume.

## [Customer] How does QuotesDone work?
You describe what you need (words, voice, a photo or a drawing). Our Smart Engine turns it into a clear brief and matches it to vetted suppliers who can genuinely do the job; they send anonymised quotes. You compare them and, when you pick one, pay a 3% reveal fee to unlock that supplier's identity and contact details.
(Audience: customer)

## [Customer] What happens after I submit an inquiry?
The Smart Engine structures your request and may ask a few quick questions to make it complete, then matches and invites the suppliers who can genuinely do it. You are notified as anonymised quotes come in, and you track everything in the app.
(Audience: customer)

## [Customer] How many suppliers receive my RFQ?
Only the suppliers who can genuinely fulfil your job — never a mass blast, and any number of them may quote: there is no fixed limit, and you see every quotation that arrives. The comparison report recommends the strongest three by value.
(Audience: customer)

## [Customer] How are suppliers selected?
The Smart Engine reads your actual job and matches by real capability and location, inviting only suppliers who can truly deliver it. A wrong match is treated as worse than no match, so irrelevant suppliers are filtered out.
(Audience: customer)

## [Customer] Can I choose which suppliers receive my inquiry?
The Smart Engine selects the right suppliers for you — this keeps the process fair, fast and fully anonymous, so you do not hand-pick from a directory.
(Audience: customer)

## [Customer] Is my identity hidden?
Yes — completely. Suppliers never see your name, phone, email, company or exact address; only the job and general area/emirate. Uploaded drawings are automatically redacted to remove identifying details.
(Audience: customer)

## [Customer] When is my identity revealed?
Never before you choose. Your details (and the supplier's) stay hidden until you pick a quote and pay the 3% reveal fee to unlock that one supplier.
(Audience: customer)

## [Customer] Can I cancel an inquiry?
Yes — there is a cancel button, so you can cancel an inquiry (before you reveal a supplier, at no cost — you only ever pay at the reveal step). We keep a record of cancellations, and if cancelling becomes a habit we will send you a polite, professional note explaining that repeated cancellations affect suppliers who take time to prepare quotes.
(Audience: customer)

## [Customer] Can I edit an inquiry?
Yes — you can edit an inquiry within 1 hour of submitting it. After that window, if something important changes, please create a new inquiry so suppliers quote the correct scope.
(Audience: customer)

## [Customer] Can I upload drawings?
Yes — you can add drawings, photos or a short video. Drawings are automatically redacted to strip any identifying details before suppliers see them.
(Audience: customer)

## [Customer] Can I upload BOQs?
Yes — you can attach a bill of quantities (BOQ), and the Smart Engine uses it to structure your request so suppliers price against your exact items.
(Audience: customer)

## [Customer] Can I invite my own supplier?
No — customers cannot invite their own suppliers. QuotesDone sources and vets the suppliers for you, which keeps every quote anonymous, fair and quality-checked.
(Audience: customer)

## [Customer] Can I request revisions?
There are no quote revisions. You compare the quotes as submitted; if none suit, you can decline them all at no cost and post a clearer inquiry. After you reveal your chosen supplier, you arrange any changes with them directly through the platform.
(Audience: customer)

## [Customer] Can I reject all quotations?
Yes — you are never obliged to accept any quote. You only pay when you choose to reveal a supplier, so declining every quote costs you nothing.
(Audience: customer)

## [Customer] Can I reopen an inquiry?
There is no reopen — simply create a new inquiry and suppliers will quote afresh.
(Audience: customer)

## [Customer] How long does the process take?
It depends on the job, but 3-5 working days is realistic to receive quotes, and you are notified as each one arrives. Once you reveal a supplier, they have 5 working days from your payment to respond: we chase them for you after 3 working days, our founder makes the final call on day 5, and if they are still silent your reveal fee is refunded in full (banks take 7-14 working days to show it).
(Audience: customer)

## [Customer] Can I negotiate?
Yes — once you have revealed your chosen supplier, you can discuss scope, price and timing with them directly through the platform. Before reveal, everything stays anonymous, so you simply compare the quotes as submitted.
(Audience: customer)

## [Customer] What happens after selecting a supplier?
You pay the 3% reveal fee and that supplier's identity and contact details unlock for you. A transaction is created, the supplier is notified to respond, and you continue with them through the platform.
(Audience: customer)

## [Customer] How do I pay?
You pay the reveal fee securely by card or Apple Pay through our checkout. It is only charged when you choose to reveal a supplier.
(Audience: customer)

## [Customer] What are the platform fees?
As a customer you pay one fee: a 3% reveal fee on the value of the quote you choose (no cap), and only on that chosen quote. There are no other charges to you. Suppliers pay no commission on won jobs.
(Audience: customer)

## [Customer] Can I get a refund?
Yes, in defined cases — most notably if the supplier you revealed does not respond within 5 working days of your payment. We chase them after 3 working days with you copied; on day 5 our founder makes the final call, and if the supplier is still silent your reveal fee is refunded in full to your original payment method. Every refund is the founder's decision — none is automatic — and banks take 7-14 working days to show it. Other refunds follow our Refund Policy.
(Audience: customer)

## [Customer] What if the supplier disappears?
If a revealed supplier does not respond within 5 working days of your payment (we chase them after 3 working days, and our founder makes the final call on day 5), you are refunded the reveal fee in full. That supplier then owes the refunded fee plus an AED 500 administrative fee and 12% per annum interest, and is blocked from new matches until it is settled.
(Audience: customer)

## [Customer] What if I receive poor quotations?
Every quote must pass a quality bar before it reaches you, and the Smart Engine coaches suppliers to be complete and itemised. If you are still not satisfied, you can decline them all at no cost — you only pay when you choose to reveal a supplier.
(Audience: customer)

## [Customer] What if I made a mistake?
You can edit your inquiry within 1 hour of submitting it to fix a mistake. Past that window, cancel the inquiry and create a corrected one — cancelling before reveal costs nothing.
(Audience: customer)

## [Customer] What if my project changes?
If your project changes within 1 hour of submitting, edit the inquiry directly. Otherwise create a new inquiry with the updated scope so suppliers quote accurately. If it changes after you have revealed a supplier, arrange the changes with them directly through the platform.
(Audience: customer)

## [Customer Intelligence] How is customer health measured?
A 0-100 composite: engagement 25% + satisfaction 30% + progress 25% + service 20%. Engagement = recency + number of RFQs; satisfaction = review ratings minus disputes/bad-reviews/strikes; progress = share of active RFQs that advanced (got quotes/revealed/won); service = response speed minus disputes. It also outputs a risk tier.
(Audience: internal)

## [Customer Intelligence] How is customer lifetime value calculated?
v_customer_ltv now computes it: revenue-to-date from paid reveal fees per customer, plus inquiries, completions, last activity and a value tier (none/low/medium/high). Honest note: this is realised revenue-to-date + engagement, not a forward-projected/trained lifetime-value model — a predictive LTV is the next step.
(Audience: internal)

## [Customer Intelligence] How is repeat-business probability estimated?
Proxied today by the customer_health engagement and progress signals (recent activity, multiple RFQs, completions) and dormancy flags — not a trained propensity model. A dormant, low-engagement customer is treated as low repeat-likelihood and targeted for re-engagement.
(Audience: internal)

## [Customer Intelligence] How are fraudulent customers detected?
Through disputes/refund patterns (transactions), bad reviews, chat strikes, the 18+ and verification gates at signup, duplicate-account checks, and fraud_flags/v_fraud_score. High-risk customers surface in the customer_health risk tier and to the Security/Fraud checks.
(Audience: internal)

## [Customer Intelligence] How are inactive customers re-engaged?
The Customer Success agent flags dormant customers (no activity for 45+ days) and stalled RFQs and proposes re-engagement (reminders/outreach) as oversight cards — drafted for approval, not auto-blasted.
(Audience: internal)

## [Data Governance] Who owns each dataset?
The founder is the data owner/controller, and a data_owner_registry table now records, per table, the owner, the steward agent, a data classification (PII/financial/knowledge/security/secret) and notes — starting with the core tables. Operationally each domain agent stewards its tables. Changes to the registry are captured in the append-only audit trail.
(Audience: internal)

## [Data Governance] Who may modify a dataset?
Access is RBAC-gated (roles/user_roles/role_permissions) with RLS deny-by-default; service-role backend functions perform writes under oversight. Sensitive changes require founder approval.
(Audience: internal)

## [Data Governance] Who may delete data?
Deletion is tightly constrained: storage has a delete-guard, the audit log is append-only, and record deletion is a governed, founder-approved action — not something agents do. The default is retain-and-protect (PDPL erasure is handled through a proper flow).
(Audience: internal)

## [Data Governance] Who approves schema changes?
The founder. Schema changes ship as forward-only migrations, applied and verified under oversight; any change to roles/permissions/critical config is now recorded in security_audit_log.
(Audience: internal)

## [Data Governance] How are migrations reviewed?
They are authored, applied and verified live (smoke tests, re-queries) under founder oversight, and listed in the migration history. Honest: there is no separate multi-reviewer PR gate yet (single founder + agent + verification).
(Audience: internal)

## [Data Governance] How is data lineage tracked?
Partially: backups + manifests, the audit trail for governance tables, source/citation on knowledge (kb_chunks), and source tags on records (e.g. lead source). Honest gap: there is no end-to-end automated data-lineage/catalog tool — lineage is reconstructable from sources + audit, not a dedicated lineage graph.
(Audience: internal)

## [Data Governance] How are duplicate records merged?
Dedup checks exist at key points (supplier directory scoping, one-account-per-email, backup dedupe keys, quote-set signatures). Honest: there is no universal master de-dup/merge engine across all entities — it is per-domain checks.
(Audience: internal)

## [Data Governance] How is master data governed?
Canonical reference data lives in config tables (config-as-data) and curated knowledge (company_faq single source of truth, agent_knowledge), changed only under approval with the audit trail. Honest: there is no formal MDM platform — governance is config-as-data + approval + audit.
(Audience: internal)

## [Data Governance] Can a person request access to or erasure of their personal data (UAE PDPL)?
Yes. Requests are captured in pdpl_requests and handled by three governed functions. fn_pdpl_export(email) compiles everything held about a subject across customers, inquiries, supplier leads, notifications, outreach, verifications and AI-usage logs (access/portability). fn_pdpl_erase_plan(email) is a dry run showing exactly how many rows in each table would change. fn_pdpl_redact(request_id) performs the erasure - but only after the request is marked approved, and it anonymises personal fields (name, phone, email, date of birth) rather than hard-deleting, so legally-required financial and audit records survive. Each redaction writes a high-severity security event. The email do-not-contact suppression list is deliberately retained so an erased person is not accidentally re-contacted.
(Audience: internal)

## [Data Security] Which encryption algorithms are used?
QuotesDone relies on the strong, industry-standard encryption provided by its managed infrastructure. Data at rest is encrypted with AES-256 (Supabase, backed by AWS; likewise Dropbox for document backups); data in transit is protected by TLS (HTTPS, TLS 1.2+). Passwords are one-way hashed with bcrypt by the managed auth service. We do not roll our own cryptography — we use the vetted algorithms these platforms provide.
(Audience: internal)

## [Data Security] Is encryption applied at rest?
Yes. The database, file storage and backups are encrypted at rest by the managed platform (AES-256 on AWS-backed Supabase). Uploaded documents in Storage and the Dropbox backup copies are likewise encrypted at rest. No sensitive data sits on disk in plaintext.
(Audience: internal)

## [Data Security] Is encryption applied in transit?
Yes, everywhere. All traffic — browser to site (Vercel/HTTPS), app to backend (Supabase over TLS), and backend to third parties (Stripe, Twilio, Resend, Dropbox, the LLM gateway) — travels over TLS/HTTPS, and signed file links are HTTPS-only. There are no plaintext network paths.
(Audience: internal)

## [Data Security] How are secrets managed?
All backend secrets live in an access-controlled secrets table protected by row-level security with no read policies — so only the backend's service role can read it; no customer, supplier, admin session or anonymous client can. Platform-level secrets (like the service-role key) are held in the managed Edge Function secret store. Secrets are read server-side at call time and never shipped to the browser.
(Audience: internal)

## [Data Security] How are API keys protected?
Third-party API keys (Stripe, Twilio, Resend, Dropbox, the LLM gateway, Meta) are stored only in that server-side secrets table and used only inside Edge Functions. They are never embedded in the frontend, never sent to the client, and never written to logs or URLs — and can be rotated centrally without code changes.
(Audience: internal)

## [Data Security] How are database credentials stored?
The database is managed by Supabase; the privileged service-role key used by Edge Functions is held in the platform's secret store (an environment secret), not in code or the repository, and connections run over TLS. The browser never holds database credentials — it only calls Edge Functions, which connect on its behalf under strict checks.
(Audience: internal)

## [Data Security] How are environment variables managed?
Runtime configuration and secrets for Edge Functions are provided through the platform's managed environment/secret store (e.g. the Supabase URL and service-role key), injected at runtime — not committed to source control and not exposed to the client. Application-level keys are additionally kept in the RLS-protected secrets table.
(Audience: internal)

## [Data Security] How are backups encrypted?
Both layers are encrypted. The database's automated backups are encrypted at rest by the managed platform. The organised document backup to Dropbox is uploaded over HTTPS and stored encrypted at rest by Dropbox (AES-256), inside the company's own controlled account. The backup process only ever reads and uploads — it never weakens access on the originals.
(Audience: internal)

## [Data Security] How is sensitive data masked?
Anonymity is core: suppliers appear to customers only as A/B/C, and customers stay anonymous to suppliers until a paid reveal, so identities are masked by default. Documents open only through short-lived signed links to authorised users, uploaded drawings can be redacted before sharing, secrets are never returned to clients, and each party sees only their own data. PII is minimised and never placed in URLs or logs.
(Audience: internal)

## [Database Security] Which database is used?
PostgreSQL (v17), managed by Supabase on AWS. It is the single source of truth for all platform data — accounts, inquiries, quotes, transactions, the knowledge base, agent state — with Postgres's relational integrity, transactions and security, plus extensions for scheduling (pg_cron), outbound calls (pg_net), full-text search and vector similarity.
(Audience: internal)

## [Database Security] How is Row Level Security implemented?
RLS is enforced in the database itself, beneath the application, and is deny-by-default: with RLS on and no permissive policy, no client can read or write a row. The public apps use restricted keys subject to RLS, so a browser can never reach data it is not entitled to; all privileged work goes through Edge Functions using the service role, which then apply their own role and ownership checks. RLS is the last line of defence even if an app-layer check were missed.
(Audience: internal)

## [Database Security] Which tables use RLS?
All of them — every one of the platform's public tables (currently 164 of 164) has RLS enabled, a 100% deny-by-default posture. Access is granted only through the backend's service role or an explicit policy, never by default.
(Audience: internal)

## [Database Security] How are SQL injections prevented?
User input never becomes SQL. All access uses parameterised queries (the Supabase client and SQL functions bind values as parameters, not string concatenation), so input is treated as data, not code. Business logic lives in typed SQL functions and server-side Edge Functions; the browser never composes queries, and the Smart Engine agents do not write raw SQL against production. RLS provides defence-in-depth on top.
(Audience: internal)

## [Database Security] How are database migrations managed?
Schema changes are applied as versioned, tracked migrations (each recorded with a name/timestamp in a migrations table) rather than ad-hoc edits, so the schema history is auditable and reproducible. Changes move forward through new migrations (and are reversed by a further migration), keeping every environment consistent.
(Audience: internal)

## [Database Security] How is referential integrity maintained?
By the database: relationships use foreign keys, and data quality is enforced with constraints — primary keys, unique constraints (e.g. one account per email, one match per supplier+inquiry), not-null and check constraints — so orphaned or malformed records are rejected at write time. Multi-step changes run inside transactions, so they either fully apply or fully roll back.
(Audience: internal)

## [Database Security] How are audit logs stored?
In dedicated tables plus the platform's own logs. The approval/action ledger records each sensitive decision (who, when, outcome); agent runs, matching/routing decisions, cancellations, notifications, backups and money events each write to their own tables with timestamps; and Supabase retains database and function logs at the infrastructure level. Together these give a durable trail of what happened and who authorised it.
(Audience: internal)

## [Database Security] How are deleted records handled?
Conservatively and under oversight. The Smart Engine agents never hard-delete data on their own — permanent deletion is a governed, human-approved action. Most removals are status changes (cancelled, banned, waived, blocked) that preserve history, and even Storage has a guard that blocks accidental object deletion. The default is to retain and mark, not erase.
(Audience: internal)

## [Database Security] Is soft delete implemented?
Yes, broadly. Business records are retired by status/flag rather than physical deletion — inquiries marked cancelled, suppliers banned or matching-blocked, dues waived, records archived — so nothing needed for history, audit, disputes or tax is lost. True erasure is reserved for explicit, approved cases (e.g. a data-subject request under PDPL, subject to legal holds).
(Audience: internal)

## [Database Security] How is data archived?
Through retention plus backup: completed items (e.g. closed RFQs) can be archived rather than deleted, documents and generated records are mirrored to the organised Dropbox backup tree, and the database's managed backups provide point-in-time recovery. Records are kept while an account is active and as long as legal, tax and dispute obligations require, then handled per the data-retention policy — archived and recoverable, not lost.
(Audience: internal)

## [Decision Engine] How is supplier score calculated?
From supplier_health — a 0-100 composite (quality 30% + compliance 30% + response 20% + retention 20%) — plus supplier_perf (perf_score derived from matched/quoted/won and ratings). This drives ranking and eligibility gates.
(Audience: internal)

## [Decision Engine] How does the engine prioritise an RFQ?
RFQs are handled in arrival order behind a completeness gate (rfq_ready/completeness): an incomplete RFQ is clarified first (run_rfq_clarify) rather than dispatched to weak matches. There is no paid priority — urgency is served by clarify-then-dispatch.
(Audience: internal)

## [Decision Engine] How does the engine score quotation quality?
Quotes carry quality/structured flags and are enforced to be itemised at entry; the comparison weighs line detail, spec compliance/deviations, completeness, lead time and terms — not supplier identity (anonymised A/B/C).
(Audience: internal)

## [Decision Engine] How are business rules weighted?
Rules live as config-as-data (collections_config, pricing_config, feature_flags) and as explicit formula weights — the ranking boosts and the health composite (30/30/20/20). All are tunable under founder approval with the audit trail.
(Audience: internal)

## [Decision Engine] How are conflicting rules resolved?
Oversight-first and conservative: on conflict the engine defaults to withhold/escalate rather than force an action (a wrong action is worse than none), and for knowledge, official sources take precedence. Unresolved conflicts go to human review.
(Audience: internal)

## [Decision Engine] How are confidence scores computed?
Matching uses retrieval similarity plus an adjudication confidence recorded on agent_actions.confidence; knowledge uses v_kb_confidence. These are heuristic/threshold-based signals, not calibrated probabilities.
(Audience: internal)

## [Decision Engine] How are explanations generated?
Every agent action card carries a plain-language reasoning summary naming the rules and knowledge it used, plus a click-through to the source record; comparisons show per-supplier rationale. Explanations are traceable, not black-box.
(Audience: internal)

## [Decision Logic & Explainability] Why was this supplier selected?
A supplier is selected only when the matching engine judges they can genuinely do the actual job. After building an anonymised, priceable brief, the engine shortlists candidates by combining meaning-based (vector) and keyword search over supplier capabilities, then an adjudicator model evaluates each shortlisted supplier against the real scope. A supplier is invited only if their verified capabilities (category, services, products, coverage, authorizations) match what the job requires. The reason for each selection is recorded.

## [Decision Logic & Explainability] Why was not another supplier invited?
Because the engine was not confident they truly fit — the rule is "a wrong match is worse than no match." A supplier is left out if their capabilities do not cover the scope, they are in a different (even adjacent) trade, they are unverified/suspended/licence-expired, or a fan-out cap was reached after better-fitting suppliers were chosen. It is a fit decision, not a judgement of their overall quality, and the exclusion reason is logged.

## [Decision Logic & Explainability] How is the supplier match score calculated?
It is a two-stage judgement, not one opaque number. First, retrieval ranks suppliers by how closely their capability profile matches the brief (semantic similarity plus keyword overlap). Second, an adjudicator model scores each shortlisted supplier on whether they can actually deliver the specific scope — trade fit, required products/brands, coverage area, authorizations, compliance — and keeps only genuine fits. Precision is prioritised over volume.

## [Decision Logic & Explainability] How is the RFQ completeness score determined?
Intake turns the request into a structured brief and checks it against that category's qualification playbook — the questions needed to scope that trade (dimensions, materials, quantities, emirate/site, authority requirements). Completeness reflects how many essential fields are present. It is marked ready to match only when complete enough for suppliers to quote accurately.

## [Decision Logic & Explainability] Why did AI request additional information?
Because a detail essential to an accurate quote was missing or ambiguous. The playbook flags the gap (unspecified material grade, missing measurements, unclear authority requirement) and the agent asks rather than guessing — guessing produces misleading quotes. Requesting information protects both sides and improves match and quote quality.

## [Decision Logic & Explainability] Why was a quotation rejected?
Quotes must be complete and itemized. One lacking required detail (line items, scope, pricing basis) is held as an incomplete draft rather than accepted, and incomplete drafts are excluded from the customer's comparison. This keeps every quote comparable like-for-like and stops vague lump sums or hidden-scope quotes from misleading the customer.

## [Decision Logic & Explainability] How are recommendations ranked?
In the comparison, recommendations are ranked by best match to what the customer asked for at the lowest price — not simply cheapest or highest-rated. The engine checks each quote against the requested specification and items, flags spec deviations and missing scope, and ranks a top-3 with trade-offs stated plainly ("best spec match and cheaper, but longer delivery"). Supplier merit informs, but genuine fit and value lead.

## [Decision Logic & Explainability] What evidence supports this recommendation?
Every recommendation is grounded in checkable inputs: the customer's actual brief and item list, the content of each submitted quote (scope, materials, price, lead time, warranty, terms), the supplier's verified capabilities, and the relevant UAE regulatory knowledge. Agents cite these and never invent specs or identities — if something is not stated in a quote, it is flagged to confirm rather than assumed.

## [Decision Logic & Explainability] Which regulations or standards influenced the decision?
Where a request touches a regulated system (electrical/DEWA, fire/Civil Defence, security/SIRA, signage/Municipality, free-zone Trakhees/DDA), the relevant UAE authority and standard are pulled from the knowledge base and applied — in qualification (which approvals a job needs) and in comparison (flagging quotes that ignore or under-spec a code). Agents point to the official source of record and frame compliance as something to verify, never asserting non-compliance as fact.

## [Decision Logic & Explainability] What factors affect confidence scores?
Confidence rises with clear, complete, verified inputs and falls with ambiguity or thin data — a vague or incomplete brief, a supplier with sparse capability information, conflicting or missing quote details, or a newly-seen category. Low confidence makes the engine more conservative (it excludes rather than guesses) and, for anything sensitive, routes the decision to a human.

## [Decision Logic & Explainability] When does AI escalate to a human?
The Smart Engine is oversight-first: it surfaces, recommends and escalates but never takes an irreversible or sensitive action on its own. It escalates when confidence is low; when a decision touches money, publishing, access, suspensions or legal matters; when new knowledge needs approval before going live; or when a case falls outside its grounded knowledge. A human reviews and approves before it proceeds.

## [Decision Logic & Explainability] What would change the recommendation?
Recommendations update as inputs change. New or corrected request details, additional or revised quotes, updated supplier capabilities or compliance status, a change in the customer's stated priorities, or updated regulatory knowledge can all shift the ranking. Because every decision is grounded in current data and its reasoning is recorded, the "why" can always be revisited when the facts change.

## [Development Standards] What are the coding standards?
Backend logic is TypeScript on Deno (Edge Functions) with SQL for the database; conventions in force include service-role-only functions gated by inbound_secret, row-level-security deny-by-default, and consistent brand terminology (Smart Engine, buyers/sellers). Syntax is validated at deploy time (the Edge Function bundler rejects broken code; page JavaScript is checked with node --check before publish). Honest gap: there is no formal written style guide or automated linter enforced in a pipeline yet.
(Audience: internal)

## [Development Standards] What is the branching strategy?
Honest: there is not a formal git-flow today. Changes are applied to the live Supabase project through forward-only migrations, and Edge Functions are versioned by the platform on each deploy. Supabase's dev-branch feature is available but not part of a routine workflow. A proper feature-branch + staging model is a sensible step once more than one engineer is involved.
(Audience: internal)

## [Development Standards] What is the pull request process?
Honest: there is no formal pull-request / merge-request workflow at present. The gate is the founder-oversight model — changes are proposed, the founder approves, then they are applied. A real PR process with required approvals should be adopted as the team grows.
(Audience: internal)

## [Development Standards] What are the code review requirements?
Honest: there is no second-engineer peer review today (founder + Smart Engine). Review consists of founder oversight plus the agent's own verification — syntax checks, live smoke tests, and re-querying results after each change. Formal peer code review is a planned addition for when there is an engineering team.
(Audience: internal)

## [Development Standards] What are the testing requirements?
Honest: there is no automated test suite or CI test gate yet. Each change is verified manually with live smoke tests — e.g. node --check on page scripts, calling the deployed function against real data, re-querying the database, and built-in self-test operations (as used for the backup engine). This is a known gap; an automated test suite with a CI gate is recommended.
(Audience: internal)

## [Development Standards] What is the deployment approval process?
Oversight-first: nothing irreversible or sensitive ships without founder approval. Mechanically, a release is an Edge Function deploy and/or a site_deploy re-run, each verified immediately afterward (function response checked, site regression-checked). There is no separate change-advisory board or release manager — the founder is the approver.
(Audience: internal)

## [Development Standards] What is the release versioning approach?
Edge Functions carry platform version numbers (v1, v2, and so on), and the database advances through forward-only migrations that are individually listed. Honest gap: there is no formal semantic app version, git tags, or a maintained CHANGELOG — the per-feature session logs written to the outputs folder currently serve as the informal change record.
(Audience: internal)

## [Development Standards] What is the rollback procedure?
Layered: an Edge Function is rolled back by redeploying the previous version; the static site can be reverted instantly because Vercel keeps immutable deployments and lets a prior one be promoted; prompts have a built-in fn_prompt_rollback. Database changes are rolled back by forward-fix migrations plus, if needed, restoring from the daily managed backup (PITR is on the planned list). Honest note: the database has no automatic transactional down-migrations — recovery is forward-fix or restore-from-backup.
(Audience: internal)

## [Development Standards] What are the documentation requirements?
Every feature gets a written session log in the outputs folder (the established, verified pattern), the company-knowledge FAQ documents how the platform actually behaves, and llms.txt describes the site for machines. Honest gap: there is no formal architecture document, repo README set, or operational runbook library yet (the incident-response runbook is already on the flagged-gaps list).
(Audience: internal)

## [Documents] Which file types are accepted?
Common formats: images (JPG, PNG), PDFs, and CAD drawings (DWG, DXF — automatically converted so they can be read). You can upload photos, drawings, bills of quantities, and quotation PDFs.

## [Documents] Maximum file size?
There is no small size limit — you can upload large drawings and documents (up to about 1 GB). Very large files upload fastest as PDFs or the key sheets, which also gives the quickest analysis.

## [Documents] How are files stored?
In private, access-controlled cloud storage that is not publicly accessible. Files are served only to your own account through short-lived signed links.

## [Documents] How are versions managed?
Documents are version-controlled — an update creates a new version rather than overwriting the history, so there is a traceable record. Requests (RFQs) are also versioned when they change.

## [Documents] How are drawings handled?
When you upload a drawing, the Smart Engine reads it to draft a bill of quantities and structure your brief, and it automatically redacts identifying details before any supplier sees it — keeping you anonymous. Your original files stay private to you.

## [Documents] How are PDFs analysed?
The Smart Engine extracts the content of PDFs — drawings, bills of quantities, or your own quotation — to build a clean, structured brief or quote, pulling out line items and specifications and stripping identity or prices where needed for anonymity.

## [Documents] How are documents archived?
Completed requests and their documents are archived to durable off-site storage on a schedule, kept for record-keeping and retrievable later. A Document Controller tracks the inventory and retention.

## [Executive KPIs] What KPIs are shown daily to the CEO?
The daily founder brief (fn_founder_brief, ~08:30 Dubai) shows pipeline, pending approvals, hot leads, supply gaps and BD, alongside the strategy KPIs: cash, monthly_burn, runway_months, revenue_30d, margin_pct, active_suppliers_90d, top_supplier_share_pct, under_supplied_categories and open_risks with the top risk.
(Audience: internal)

## [Executive KPIs] How is company health calculated?
As a roll-up across domains: finance (runway, burn, margin), supplier and customer health, operations health and security posture — surfaced in the executive command center and summarised in strategy_kpis. Honest: it is a composite of the domain scores, not a single formally-weighted index.
(Audience: internal)

## [Executive KPIs] How is overall marketplace health calculated?
From liquidity (demand versus approved-supplier coverage), supplier and customer health, response/fulfilment signals, and under-supplied categories — the same inputs the Marketplace Intelligence views expose.
(Audience: internal)

## [Executive KPIs] How are AI health and confidence reported?
Through the AI Trainer (per-agent quality), v_ai_quality_proxy (30-day human override rate), the latest eval scores (v_eval_latest), and knowledge_kpis (accuracy_pct, freshness_pct). Together these give a health-and-confidence read on the Smart Engine.
(Audience: internal)

## [Executive KPIs] How are strategic risks summarized?
strategy_risks scores each risk as likelihood x impact with a mitigation, source and status; the highest becomes top_risk / top_risk_score in strategy_kpis, and fn_strategy_ai + the weekly board report summarise them for the founder.
(Audience: internal)

## [Executive KPIs] How are forecasts generated?
The finance forecast (finance_kpis + fn_finance_ai) projects revenue, cash and runway from recent trends and known inflows/outflows. Honest note (2026-07-11): a true ML/statistical forecast is not feasible yet — there is essentially no transaction history to learn from (one paid reveal to date), so a trend-and-assumption forecast is the correct approach until real revenue history accumulates. It will graduate to a proper statistical model once there is enough data.
(Audience: internal)

## [File Security] Which file types are allowed?
The platform accepts the business documents and images it needs — trade licences, VAT/insurance/ISO certificates, company profiles and catalogues, drawings, and quote files — as PDFs and images (JPEG/PNG), with drawings/CAD supported in the relevant flow. The supplier-documents store is explicitly restricted to PDF and image types; the drawing and quote stores accept the formats those flows use. It is a document-and-image intake, not a general file host.
(Audience: internal)

## [File Security] Which file types are blocked?
Anything outside the expected document/image/drawing set. Executables, scripts and similar active content are not part of the accepted types and have no path to run — uploads are treated purely as documents to store, render or read, never as programs. The supplier-docs bucket enforces an explicit allow-list (PDF/JPEG/PNG) at the storage layer.
(Audience: internal)

## [File Security] Maximum upload size?
Up to 1 GB per file. The document, drawing and quote stores are set to a 1 GB limit (raised so large catalogues and company profiles are accepted), and the project-wide ceiling matches. Very large files upload directly to storage via a signed upload URL rather than through the app, so size does not strain the request path.
(Audience: internal)

## [File Security] Are uploaded files scanned for malware?
Yes — uploaded files are scanned. A daily job (vt_scan) computes each new file's SHA-256 and checks it against VirusTotal's known-malware database in a privacy-safe way — the file contents are never uploaded, only the hash is checked — across quote files, drawing files, supplier documents and receipts. A malicious hit raises a high-severity security event, a high-risk approval card for the founder, and an email alert, and the file is flagged for immediate removal. This runs on top of structural protections: files sit in isolated private buckets, are never executed, are only read/rendered or distilled by the Smart Engine, are served only through short-lived signed links to authorised users, and the supplier store is limited to PDF/image types. Honest nuance: this is known-malware hash lookup, so a brand-new/never-seen file returns "unknown" rather than a verdict — full novel-file sandboxing/content analysis is not yet in place and is the natural next enhancement.
(Audience: internal)

## [File Security] How are PDFs processed?
PDFs are stored privately and processed by conversion, not execution: pages are rendered to images so the Smart Engine can read a licence, distil a catalogue or extract a bill of quantities, and generated documents (reports, letters, comparisons) are produced through the branded PDF pipeline. They open for authorised users only via time-limited signed links. PDFs are never run — only rendered and read.
(Audience: internal)

## [File Security] How are drawing files handled and secured?
Drawings live in a private store. They can be converted (CAD/large formats normalised), read to extract a structured bill of quantities, and — importantly — redacted before being shared with suppliers, so a customer's identifying details on a drawing are stripped to preserve anonymity. Very large drawings upload directly to storage and are linked. Suppliers only ever see the redacted, task-relevant version through a signed link.
(Audience: internal)

## [File Security] How are file permissions managed?
Every bucket except public brand/site assets is private, with row-level security on the storage layer. No file is world-readable; the only way to open one is a short-lived signed URL minted by a gated Edge Function after it checks the caller's role and ownership. A customer reaches only their own files, a supplier only theirs, admins through audited endpoints — nobody can guess or share a durable link to someone else's document.
(Audience: internal)

## [File Security] How are archived files protected?
Archived and backup copies inherit the same protections: private, access-controlled storage plus the company's own Dropbox backup, both encrypted at rest and reached only over HTTPS. The backup process is read-and-upload only and never weakens access on the originals, and storage has a guard blocking accidental object deletion. Access to archives is the same signed-link, role-checked path as live files.
(Audience: internal)

## [File Security] How is Dropbox secured?
Server-side only: it authenticates with a stored OAuth refresh token (in the RLS-protected secrets table, never in the client), is scoped to the QuotesDone backup folders, and communicates over HTTPS to Dropbox, which encrypts data at rest. It only ever reads/indexes and uploads — never deletes anything in Dropbox — and writes into the company's own controlled account. Customers and suppliers have no access to it.
(Audience: internal)

## [File Security] How are deleted files handled?
Cautiously. Storage has a protection that blocks direct deletion of objects, so files are not casually or accidentally removed; the Dropbox backup never deletes originals; and removals of stored documents are governed, human-approved actions, not something an agent does. Where a genuine erasure is required (e.g. an approved PDPL data-subject request, subject to legal holds), it is handled deliberately through the proper flow — the default is retain-and-protect.
(Audience: internal)

## [Financial] What is the 3% fee?
The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform's main charge and it is paid by the customer — suppliers pay no commission.

## [Financial] When is it charged?
Only at the reveal step — when a customer picks a quote and chooses to unlock that supplier. Nothing is charged for posting a request, receiving quotes, or comparing them; you pay only when you decide to proceed with a supplier.

## [Financial] How do invoices work?
When a customer pays a reveal fee, an invoice for that fee is generated automatically and available in the app. Suppliers who are liable for the annual subscription (that is, those outside the first 1,000 registered) receive an invoice for it when it falls due. All invoices are issued by QuotesDone Technologies (see the VAT note below on current tax treatment).

## [Financial] Which payment methods are accepted?
Payments are made securely by card or Apple Pay through our Stripe checkout — both the customer reveal fee and the supplier annual subscription.

## [Financial] How are VAT invoices generated?
QuotesDone Technologies is not currently VAT-registered, so invoices are issued without VAT and without a TRN. If and when the company becomes VAT-registered, VAT will be applied and shown on invoices together with the TRN.

## [Financial] How are refunds processed?
Refunds are returned to your original payment method through Stripe and every one is approved by our founder — none is automatic. The clearest case is a silent supplier: if the supplier you revealed does not respond within 5 working days of your payment (we chase them after 3 working days, and the founder makes the final call on day 5), your reveal fee is refunded in full. Banks usually take 7-14 working days to show the refund. Other refund requests made within the refund window are reviewed the same way.

## [Financial] How are commissions collected?
There are no commissions — suppliers keep 100% of their won jobs. The only amounts ever collected from suppliers are the annual subscription (AED 1,000/year, which never applies to the first 1,000 suppliers who registered and has no fixed start date — it applies from the 1,001st registration onward) and any non-response fee. Both are paid on the supplier portal via Stripe. Unpaid amounts are followed up and the account is paused from new matches until they are settled.

## [Financial] How are overdue payments handled?
We send reminders first. If an amount due — a supplier subscription or a non-response fee — stays unpaid, the account is paused from receiving new matches until it is settled on the portal.

## [Future Vision] Why is QuotesDone building AI employees?
QuotesDone is built AI-first: rather than scaling by adding headcount, it runs on a team of Smart Engine agents — matching, supplier and customer success, finance, marketing, knowledge, legal, security and operations. This lets a lean UAE business deliver enterprise-grade service around the clock — faster, consistent, and grounded in verified knowledge. The agents are oversight-first: they surface, recommend and escalate, but a human approves anything sensitive or irreversible. The goal is leverage and quality, not replacing human judgment.

## [Future Vision] What is the long-term roadmap?
The near-term focus is depth in the UAE B2B market: sharper matching, more suppliers with rich verified capabilities, and continuously improving quote quality and comparisons. Beyond that, the direction is broader category coverage, deeper supplier and customer tooling, stronger analytics, and — as demand justifies — integrations (e.g. ERP/procurement) and possibly a partner API. Roadmap items are pursued deliberately and launched only when genuinely ready; we prefer to under-promise and over-deliver.

## [Future Vision] Will the platform expand internationally?
The immediate priority is to win the UAE market and prove the model. The platform is built to be adaptable — its knowledge base, categories and compliance rules are structured so new jurisdictions can be added — so international expansion (starting with the wider GCC) is a natural future direction once the UAE foundation is strong. It is not live yet, and any new market would launch with locally-grounded regulatory knowledge, not a copy-paste.

## [Future Vision] Will more industries be supported?
Yes — the platform is designed to grow its category coverage. When a supplier registers a trade QuotesDone has not seen, the Smart Engine can stand up a new category agent with the right qualification questions and knowledge (with founder approval before that knowledge goes live), so coverage expands without losing quality. Over time this extends across more construction, fit-out, MEP, facilities and related B2B trades, and into adjacent industries as demand appears — always grounded in real, verified requirements for each field.

## [Future Vision] How will AI continue to evolve?
The Smart Engine improves continuously and safely: agents are graded and trained on real outcomes, their knowledge is curated and kept current with the latest UAE regulations, and their prompts and models can be upgraded, reviewed and rolled back under governance. As underlying AI models improve, QuotesDone adopts them where they raise accuracy — but the oversight-first principle stays fixed: more capability, always under human control, always grounded in verified knowledge rather than guesswork. The aim is an AI workforce that gets sharper over time while staying trustworthy.

## [Governance] Who owns each module?
Honest: the founder is the ultimate owner and accountable party for every module. Operationally, each domain is run by a dedicated Smart Engine agent under oversight — Finance AI, Supplier Success, Customer Success, Marketing AI, Legal AI, Security AI, Operations AI, Knowledge Curator, Document Controller and Executive Assistant. So ownership means the founder is accountable and a named agent operates each domain day-to-day; there are no separate human module owners yet.
(Audience: internal)

## [Governance] Who approves production deployments?
The founder. There is no change-advisory board or separate release manager — under the oversight-first model, the founder is the single approver, and every deploy is verified immediately afterward.
(Audience: internal)

## [Governance] Who approves security changes?
The founder, given their sensitivity. Changes to secrets, row-level-security policies or service-to-service gating are proposed with rationale and applied only on founder approval; secrets remain service-role-only and are never exposed to clients.
(Audience: internal)

## [Governance] Who approves AI prompt changes?
Prompt changes run through formal governance: a new version is drafted, benchmarked and evaluated against saved cases (prompt_versions, prompt_eval_runs, prompt_benchmarks), then promoted via fn_prompt_approve_draft, with fn_prompt_rollback always available. The founder approves promotion; the auto-promote/rollback rule operates only within oversight thresholds.
(Audience: internal)

## [Governance] Who approves knowledge base updates?
The founder. Company-knowledge answers are drafted and only become live once approved — the fn_company_faq_sync trigger compiles only approved rows into the agents' _global knowledge, and ingested authority documents are reviewed and promoted on approval. Nothing reaches the agents or the public FAQ without that approval step.
(Audience: internal)

## [Governance] How are critical business rules managed?
Critical rules live as data in config tables, not hard-coded — for example collections settings (interest_pa, admin_fee, escalate_working_days), the 3% reveal fee, and the AED 1,000 annual subscription. This keeps them tunable and auditable, and changes go through founder approval. Honest gap: edits to these config tables are not yet versioned with a formal change-log — adding one is a sensible improvement.
(Audience: internal)

## [Governance] How are feature flags governed?
Flags such as sms_enabled switch capabilities on and off; they live in config/settings tables and are changed only under founder oversight. Honest note: these are simple configuration booleans, not a dedicated feature-flag service with targeting, gradual rollout and its own audit trail — sufficient at current scale, upgradeable later.
(Audience: internal)

## [Governance] How are emergency changes handled?
Oversight-first still applies, but urgent fixes — disabling a misbehaving cron, voiding a wrongful charge, blocking a supplier — can be made quickly by the founder and are recorded in the session logs and agent action cards. A recent real example is the commission-engine fix: the discrepancy was flagged, the founder decided the policy, the change was applied and voided the wrongful charge, and it was logged. Honest gap: there is no formal documented emergency-change / break-glass runbook yet (this ties to the incident-response runbook already on the flagged list).
(Audience: internal)

## [Incident Response] What constitutes a security incident?
Any event that threatens the confidentiality, integrity or availability of the platform or its data: unauthorised access or a data exposure, a compromised account, a leaked secret or API key, payment fraud or tampering, malicious file/content, unexpected data changes, or an outage with security impact. Suspicious signals — abnormal access patterns, repeated auth failures, a failed signature check, an unexpected privileged change — are treated as potential incidents to investigate.
(Audience: internal)

## [Incident Response] Who is notified (incident)?
The founder is the incident owner and is alerted immediately (the platform can raise a founder alert automatically). Depending on the incident: affected users are notified where their data or account is involved; the payment processor (Stripe) is engaged for payment fraud; and for a personal-data breach, the notification obligations under UAE PDPL are followed (informing the regulator and affected individuals as required). Notification is need-to-know and proportionate.
(Audience: internal)

## [Incident Response] How are incidents classified?
By severity, on impact and likelihood — the same critical / high / medium / low framing the Security agent uses for risk. Classification weighs what is affected (money, personal data, credentials, availability), how many are affected, and whether it is contained, and it drives response speed and who is involved. High/critical items escalate straight to the founder; lower ones are logged and handled in course.
(Audience: internal)

## [Incident Response] How are compromised accounts handled?
Contain first, then remediate. Sessions can be revoked and access suspended (matching-blocked or banned), a password reset forced, and any exposed credentials rotated; the activity is investigated against the logs to gauge scope. The owner is notified, and access is restored only once it is secured. Because sensitive actions are gated and each request re-checks identity and role, a stolen session cannot quietly perform privileged actions in the meantime.
(Audience: internal)

## [Incident Response] How are compromised suppliers handled?
A suspected-compromised supplier is immediately held out of matching so no new RFQs or reveals flow to them, their documents and recent activity are reviewed, and — if warranted — the account is suspended or banned with the reason recorded. Affected customers are protected (reveals paused, refunds handled where appropriate), the owner is contacted to re-secure the account, and reinstatement follows verified remediation.
(Audience: internal)

## [Incident Response] How are compromised documents handled?
Exposure is naturally limited because documents are private and only reachable through short-lived signed links, so revoking access is largely a matter of links expiring and storage staying locked; access can be further restricted, links regenerated, and affected files quarantined or replaced. The scope of any exposure is assessed from the logs, and if personal data was involved the PDPL breach process applies. Redaction (e.g. on drawings) and per-party isolation limit the blast radius in the first place.
(Audience: internal)

## [Incident Response] How are compromised APIs handled?
Because keys and the internal service secret live in one server-side store, a suspected compromise is contained fast: the affected key or secret is rotated with a single update (no redeploy) so the old one stops working immediately, the affected function can be disabled or redeployed, and logs are reviewed for misuse. The payment path is additionally protected by signature verification, so a leaked endpoint alone cannot forge paid events. Rotation and revocation are the front-line response.
(Audience: internal)

## [Incident Response] How is recovery performed?
Restore, rotate, verify, resume. Data can be recovered from the managed database's backups and the organised document backup; compromised secrets/keys are rotated; the affected component is redeployed from known-good code; and integrity is checked before service is fully resumed. Recovery steps that touch money, access or published content go through the oversight approval path rather than being auto-applied, so remediation itself stays controlled.
(Audience: internal)

## [Incident Response] How are incidents documented?
Each incident is recorded — what happened, when, severity, systems and users affected, the actions taken and by whom — drawing on the action ledger, agent-run and money logs, and the platform's request logs for the timeline, with a post-incident review to capture cause and prevention. Honest note: a formal standalone incident-response runbook and a dedicated incident register are worth formalising as the company grows; today the trail is assembled from the audit ledger and logs plus a written record of the response.
(Audience: internal)

## [Integrations] Which payment gateways are supported?
Payments run through Stripe. It handles both money flows: the customer's reveal fee (3% of the quote, to unlock a supplier's contact) and the supplier's annual subscription (AED 1,000/year). Stripe events are reconciled so access is granted only on a confirmed payment. No other gateways are offered at this time.

## [Integrations] How does Dropbox integration work?
Dropbox is the platform's secure document backup — an administrator-side integration, not something customers or suppliers see. It works two ways: it indexes the company's QuotesDone Dropbox folders so documents are searchable inside the OS, and it automatically mirrors originals and auto-generated documents into an organized /QuotesDone Backup tree (Customers/… and Suppliers/<category>/…) every 15 minutes. It only reads and uploads — it never deletes anything in Dropbox.

## [Integrations] Can suppliers integrate ERP systems?
Not at this stage. Suppliers work through the QuotesDone portal — registering, receiving matched RFQs, and submitting itemized quotes there. There is no direct ERP connector (e.g. SAP, Oracle, Odoo) today. An ERP/quote integration could be added to the roadmap if demand grows, but it is not live.

## [Integrations] Can customers integrate procurement software?
Not currently. Customers post RFQs and receive quotes through the QuotesDone app; there is no punch-out or e-procurement connector (e.g. Ariba, Coupa, Oracle Procurement) at this time. It is a possible future addition, but not available today.

## [Integrations] Which APIs are available?
QuotesDone runs on its own secure backend and connects to trusted third-party services behind the scenes: Stripe (payments), Dropbox (document backup), Twilio (SMS and voice OTP), WhatsApp (notifications), an email service (transactional mail), a large-language-model gateway (the Smart Engine), and Meta Ads (marketing). There is no public or partner API exposed to customers or suppliers yet — all interaction is through the app and portal. A published API could be offered later if there is demand.

## [Knowledge Confidence & Governance] How is confidence assigned to each knowledge article?
v_kb_confidence scores each chunk 0-100 from citation quality, title, substance and dating, alongside the kb_revisions review workflow (status + ai_validation + reviewer). knowledge_kpis also tracks accuracy_pct and freshness_pct. With effective dates now populated, the base averages about 97. Honest: it is a signal-based score, not a probabilistic per-fact measure.
(Audience: internal)

## [Knowledge Confidence & Governance] What metadata is stored for every knowledge item?
Each kb_chunks row stores: source_kind, source_id, category, title, content, citation, effective_date, a full-text index (fts) and created_at. On top: data_owner_registry classification, and kb_revisions (version, status, author, reviewer, review_notes, ai_validation, decided_at) for curated entries.
(Audience: internal)

## [Knowledge Confidence & Governance] How is the original source tracked?
Every chunk carries source_kind + source_id and a citation pointing back to the origin document; ingested authority documents keep their citation so an answer can be traced to the exact source.
(Audience: internal)

## [Knowledge Confidence & Governance] How are effective/expiry dates managed?
kb_chunks.effective_date carries the as-of date (baselined 2026-07-11 to ingestion date; the Knowledge Curator refines these to real publication dates over time). v_kb_review_due surfaces undated/expired/aging chunks, and knowledge_kpis tracks freshness (regs_fresh, specs_fresh, freshness_pct). Honest: expiry is handled via effective_date + review rather than a separate per-item expiry field.
(Audience: internal)

## [Knowledge Confidence & Governance] How are superseded regulations linked?
Two ways now: kb_revisions versioning (a new version supersedes the prior, which is retained), and an explicit regulations.supersedes_id link that records which regulation replaces which — surfaced as a "supersedes" edge in the knowledge graph. The structure is in place; the Curator populates which older regulation each new one replaces (0 linked so far).
(Audience: internal)

## [Knowledge Confidence & Governance] Who approves knowledge updates?
The founder. The Knowledge Curator surfaces changes; company_faq answers are founder-approved before the sync trigger compiles them to agents; kb_revisions require a reviewer + ai_validation before status becomes approved. Nothing reaches the agents unapproved.
(Audience: internal)

## [Knowledge Confidence & Governance] How is evidence attached?
Via the citation and the source document on each kb_chunks row (and, for compliance, the specific cited clause). Agent action cards link through to the source record so a reviewer can open the evidence behind any output.
(Audience: internal)

## [Knowledge Confidence & Governance] How is knowledge risk classified?
By data_owner_registry classification and the kb_revisions review status, and now an explicit per-article tier via v_kb_risk: regulations = high (compliance/legal), materials and trade knowledge = medium (technical/spec), general documents = low. Today that is 43 high, 360 medium and 1,365 low. Compliance-critical knowledge is gated more tightly by review.
(Audience: internal)

## [Knowledge Platform] Where does technical knowledge come from?
From official, authoritative sources: UAE regulations and codes from the issuing authorities (DEWA, Dubai Civil Defence, Dubai Municipality, MoIAT/ESMA, SIRA and others), recognised standards, manufacturer and material data, and curated company knowledge — all ingested, indexed and made searchable so the Smart Engine can retrieve and cite it. Copyrighted standards are referenced to their official source, not reproduced.

## [Knowledge Platform] How are regulations updated?
Regulatory sources are monitored for change; new or updated codes are ingested into the library, and high-stakes regulatory updates are held for founder approval before they publish to the agents. A daily Knowledge Curator tracks coverage and freshness so gaps are surfaced.

## [Knowledge Platform] How are manufacturers verified?
QuotesDone does not run an endorsement list. Manufacturer and product data lives in the knowledge base, and what matters is that a product meets the required UAE approvals for the job (ECAS-conformant, DCD-listed, DEWA-approved). On the supplier side, company documents such as the trade licence are verified at registration.

## [Knowledge Platform] How are standards maintained?
Standards — UAE.S/GSO plus the referenced ISO, EN, IEC, NFPA and ASHRAE — are catalogued with where they apply per category, reviewed for currency, and updated as editions change. Copyrighted standard texts are referenced to the official source rather than hosted.

## [Knowledge Platform] How is knowledge validated?
Every change goes through a governed pipeline: submit, then automated validation, then review and approval before it goes live. Answers must be grounded in these verified sources, and anything flagged or failing validation is held out until it is fixed.

## [Knowledge Platform] How often is knowledge updated?
Continuously. Source monitoring and ingestion run on a schedule, a daily Knowledge Curator refreshes coverage and freshness, company facts auto-sync, and updates land as sources change — with sensitive updates gated on approval.

## [Knowledge Platform] How is outdated information removed?
Superseded content is replaced or retired: revisions are version-controlled, stale sources are flagged by freshness checks, and resolved items are automatically closed — so the agents do not rely on out-of-date information.

## [Knowledge Platform] Who approves new knowledge?
You do, for anything high-stakes. New or updated regulations and sensitive knowledge are queued for founder approval before they publish to the agents, while routine low-risk updates flow through the validated pipeline automatically. Nothing sensitive goes live unreviewed.

## [Knowledge Quality] How is conflicting information resolved?
Official sources take precedence. When two sources conflict, the more authoritative and most-recent (effective_date) wins, and the Knowledge Curator/Legal review flags it; canonical answers in company_faq are the tie-breaker for agent behaviour. A confident-but-wrong answer is worse than deferring, so unresolved conflicts escalate rather than pick arbitrarily.
(Audience: internal)

## [Knowledge Quality] How are duplicate regulations merged?
Ingested authority documents are chunked (kb_chunks) with a source and citation; duplicates and overlaps are consolidated during curation, keeping the authoritative citation. Honest: dedup is curation-assisted, not a fully automatic entity-resolution engine.
(Audience: internal)

## [Knowledge Quality] How is stale knowledge detected?
Surfaced via v_kb_review_due, which lists chunks that are undated, past their effective date, weak-cited or aging — a curator worklist. Honest finding (2026-07-11): all 1,768 chunks currently lack an effective/as-of date, so they all show as "undated", meaning staleness cannot be time-detected until dates are populated. Populating effective dates is the real next step; there is still no automated upstream watcher that detects when a source regulation itself changes.
(Audience: internal)

## [Knowledge Quality] How are superseded regulations archived?
Via kb_revisions: a new version supersedes the old, and the old revision is retained (status/decided_at) rather than deleted — an auditable history. company_faq answers are updated in place with source_note history.
(Audience: internal)

## [Knowledge Quality] How is confidence assigned to knowledge?
Now scored explicitly: v_kb_confidence gives each knowledge chunk a 0-100 confidence from citation quality, title, substance and dating, alongside the kb_revisions review workflow (status + ai_validation + reviewer) for curated knowledge. Today the base averages about 80 (all 1,768 chunks are cited) and is capped at 80 because chunks are not yet dated — adding effective dates lifts them toward 100. Honest: it is a signal-based score, not a probabilistic per-fact measure.
(Audience: internal)

## [Knowledge Quality] How is knowledge tested before publication?
kb_revisions includes an ai_validation step and a human reviewer before status becomes approved; company_faq answers are founder-approved before the sync trigger compiles them to agents; prompt changes are benchmarked. Nothing reaches agents unapproved.
(Audience: internal)

## [Knowledge Quality] How are broken references detected?
Now guarded by v_kb_citation_check, which flags any knowledge chunk with a missing or too-short citation (0 today — all 1,768 chunks are cited), plus kb_usage_log tracking what is retrieved and learn_gaps surfacing gaps. Honest gap remains: there is no automated dead-link/URL checker that verifies a citation still resolves.
(Audience: internal)

## [Knowledge Quality] How often is knowledge reviewed?
Continuously by daily agents (Knowledge Curator, Document Controller, Legal AI) plus weekly learn_gaps and eval runs; expiry-dated items are reviewed as they approach their effective/expiry dates. Honest: there is no fixed calendar review SLA per document yet.
(Audience: internal)

## [Knowledge Relationships] How are regulations linked to products, brands, suppliers and RFQs?
Through the shared category tag, semantic embeddings (pgvector), and now an extended knowledge graph: regulations are nodes with applies_to edges to their categories (43 links today), and categories already connect to RFQs and suppliers — so a regulation reaches the RFQs and suppliers in its category through the graph. Honest note: brands, standards and manufacturers are not yet separate tables/nodes (they live inside knowledge chunks and quote line-items), so they are linked by content/category rather than explicit graph nodes.
(Audience: internal)

## [Knowledge Relationships] How are manufacturers linked to standards?
Through the knowledge base (kb_chunks): manufacturers and standards are captured as knowledge tagged to the same category and cross-referenced by content and citation. Honest: this is content/category linkage, not yet explicit manufacturer-to-standard graph edges.
(Audience: internal)

## [Knowledge Relationships] How are projects linked to knowledge?
Via the inquiry/project (inquiries.project_id) and its category, which map to the applicable specs, playbooks and regulations for that category; retrieval pulls that knowledge when the project is worked.
(Audience: internal)

## [Knowledge Relationships] How are quotations linked to regulations?
Through the parent RFQ's category, which maps to the applicable regulations and specs; the Smart Engine references those when adjudicating and comparing quotes for compliance.
(Audience: internal)

## [Knowledge Relationships] How are related knowledge discovered automatically?
By semantic similarity (pgvector) and full-text search over kb_chunks, plus category adjacency and the knowledge graph edges — so relevant chunks are pulled together at query time even without an explicit hand-made link.
(Audience: internal)

## [Marketplace] How are suppliers ranked?
Ranking is merit-based, never pay-to-rank. It reflects real performance — customer reviews, responsiveness, win rate and how well a supplier genuinely fits the job — and for any given request the Smart Engine also weighs capability, the emirates served and similarity to the job. Suppliers rise by performing well.

## [Marketplace] How are categories managed?
QuotesDone runs a taxonomy of trades, each with its own qualification playbook. When a supplier registers a trade we do not yet have, the Smart Engine automatically provisions a new category — persona, intake questions and category knowledge — with the founder reviewing the generated knowledge before it reaches full quality.

## [Marketplace] How are duplicate suppliers prevented?
Suppliers are matched to a single company listing keyed on their trade licence and company identity, and the directory is de-duplicated — so a company is not represented twice. Duplicate or suspicious registrations are flagged in review.

## [Marketplace] How is fraud detected?
Through automated fraud scanning and anomaly checks, contact-leak detection in the in-platform chat, decoy/canary traps, and document checks — with suspicious accounts flagged and, where warranted, blocked from matching. The anonymity model itself removes much of the incentive to game the system.

## [Marketplace] How are disputes managed?
Disputes follow a defined process: you raise the issue, it is reviewed with the full record, and it is resolved through the platform — including refunds where appropriate, which settle against the original transaction. The goal is a fair outcome for both sides.

## [Marketplace] How is supplier quality measured?
By real outcomes: multi-dimension customer reviews (communication, quality, punctuality, documentation, after-sales and compliance), the supplier's dispute record, responsiveness, and the quality of the quotes they submit — combined into a reputation score customers can see.

## [Marketplace] How are customer ratings calculated?
After a completed deal, the customer leaves a multi-dimension review, and only a customer who actually revealed and dealt with a supplier can rate them — so ratings are genuine. These reviews feed the supplier's overall reputation score.

## [Marketplace Health] What is marketplace liquidity?
The balance of active buyers (RFQs) against responsive, verified suppliers per category and emirate — enough qualified suppliers to get real quotes on each RFQ. It is monitored via demand (marketing_category_demand) versus coverage (reg_coverage).
(Audience: internal)

## [Marketplace Health] Which categories are underserved?
Surfaced by comparing RFQ demand to registered/approved supplier coverage per category (marketing_category_demand + reg_coverage); categories with demand but thin approved supply are flagged for recruitment.
(Audience: internal)

## [Marketplace Health] Which Emirates have insufficient supplier coverage?
reg_coverage breaks registered/approved suppliers down by emirate and category; low-coverage emirates for in-demand categories are flagged.
(Audience: internal)

## [Marketplace Health] Which suppliers are overloaded?
v_supplier_load now measures it: active matched RFQs (open, non-cancelled) per claimed supplier versus their response rate, with an overloaded flag (10+ active matches and response under 50%). Honest note: it is a starting heuristic gauge, not a real-time capacity model.
(Audience: internal)

## [Marketplace Health] Which customers have waited too long?
customer_health flags stalled RFQs (e.g. qualifying with no quotes for 2+ days, quoted for 7+ days, revealed-but-not-completed for 30+ days); these surface to Customer Success.
(Audience: internal)

## [Marketplace Health] Where are quotation bottlenecks?
In the RFQ pipeline stages (qualifying, matched, quoted, revealed): stages where RFQs stall — no quotes, slow supplier response — are visible via the stalled flags and pipeline-stage timing.
(Audience: internal)

## [Marketplace Health] Which categories need recruitment?
The underserved/low-coverage categories feed the recruitment target list; the directory-invite engine and Marketing AI focus onboarding there.
(Audience: internal)

## [Marketplace Intelligence] Which categories lack suppliers?
Surfaced by comparing demand (marketing_category_demand) to approved-supplier coverage (reg_coverage), and rolled up in strategy_kpis.under_supplied_categories — categories with real RFQ demand but thin approved supply are flagged for recruitment.
(Audience: internal)

## [Marketplace Intelligence] Which Emirates have insufficient coverage?
reg_coverage breaks registered/approved suppliers down by emirate and category; low-coverage emirates for in-demand categories are flagged for targeted onboarding.
(Audience: internal)

## [Marketplace Intelligence] Which RFQs receive no quotations?
RFQs with zero quotes past a window are tracked (no_quote_notified + run_no_quote_nudges nudges suppliers), and customer_health flags them as stalled so Customer Success can step in.
(Audience: internal)

## [Marketplace Intelligence] Which categories have the slowest response times?
Now built: v_mkt_response_by_category reports, per category, the RFQ count, how many got quoted, the average hours to first quote, and the no-quote percentage — slowest categories sort to the top. Also reflected in customer_health response hours.
(Audience: internal)

## [Marketplace Intelligence] Which brands dominate each category?
Now built: v_mkt_brand_by_category aggregates the brand fields on quote line items by category (line count, distinct suppliers, total amount) so you can see which brands appear most per category. It reads from quote_items.brand, so it fills in as itemised, branded quotes accumulate (0 today while early quotes lack per-line brands).
(Audience: internal)

## [Marketplace Intelligence] Which jobs are over budget?
Now built: v_mkt_over_budget lists jobs where the cheapest live quote exceeds the buyer's stated budget, with the overrun amount. Honest note: budget is a free-text field, so the view best-effort parses the first number in it — treat it as indicative. It currently flags a small number of real over-budget jobs.
(Audience: internal)

## [Marketplace Intelligence] Which jobs are underpriced?
Now built: v_mkt_underpriced lists quotes flagged suspiciously_low against the category price band (via fn_price_confidence), alongside the category median — complementing the existing abnormal_price fraud flag. Budget-versus-quote adds a second lens.
(Audience: internal)

## [Operational Runbooks] What happens if Dropbox fails?
Little impact — Dropbox is a secondary backup mirror, not the system of record. Originals stay in Supabase Storage (plus managed daily backups). The 15-minute backup queue retries later and catches up when Dropbox returns.
(Audience: internal)

## [Operational Runbooks] What happens if Supabase is unavailable?
This is the hard dependency: the backend (database + functions + storage) is down. The static site and FAQ stay up on Vercel (cached). Supabase's managed platform handles infra recovery; worst-case is restore-from-backup. There is no self-managed standby. See IR Runbook section 3.
(Audience: internal)

## [Operational Runbooks] What happens if OpenRouter is unavailable?
The Smart Engine's model gateway is down, so agents cannot call models. Oversight-first means work queues for review rather than acting wrongly; the core marketplace (post RFQ, quote, reveal, pay) keeps working. Multiple model fallbacks reduce single-model outages.
(Audience: internal)

## [Operational Runbooks] What happens if Claude is unavailable?
Claude is one model reached via OpenRouter; the router falls back to other models (e.g. Sonnet/GPT). Quality may vary but the pipeline continues, and low-confidence outputs escalate rather than act.
(Audience: internal)

## [Operational Runbooks] What happens if GPT is unavailable?
Same as any single model — it is a fallback option via OpenRouter, not a single point of failure; the router routes around it to an available model.
(Audience: internal)

## [Operational Runbooks] What happens if OCR fails?
Document extraction (doc_extract) fails for that file; the original is still stored and backed up, the document is queued/retried, and it is flagged for manual handling. Nothing is lost — extraction is enrichment, not the system of record.
(Audience: internal)

## [Operational Runbooks] What happens if a deployment fails?
The bundler rejects broken code before it goes live (syntax gate), Edge Functions are versioned (redeploy the previous one), and the static site is an atomic Vercel swap with instant rollback. A failed deploy does not take the live version down. See IR Runbook rollback.
(Audience: internal)

## [Operational Runbooks] What happens if backups fail?
agent_runs logs each backup run's status; a failed logical backup is visible there, the managed daily backups still run independently, and the Dropbox mirror + dr_drill surface problems. Honest gap: there is no dedicated backup-failure alert yet — it is visible in agent_runs but not actively paged; adding an alert is a quick enhancement.
(Audience: internal)

## [Operations] What happens if a supplier is suspended?
A suspended supplier is immediately excluded from matching — the Smart Engine routes no new RFQs to them and they cannot submit new quotes — but nothing is deleted and the reason is recorded. Suspension (matching blocked) is reversible; a full ban removes them from the marketplace. Both are oversight-first: agents surface the risk and recommend, but the action is applied under admin authority, not automatically. Anything the supplier already committed to is handled case by case.

## [Operations] What happens if a licence expires?
Trade licences — plus insurance, ISO and manufacturer authorizations — have their expiry dates tracked continuously. As expiry nears, reminders go out and the item is flagged on the supplier's compliance scorecard. Once expired, the supplier is treated as non-compliant and held out of matching until a valid renewal is uploaded; re-verification requires current documents. It is a hold pending renewal, never an auto-deletion.

## [Operations] What happens if payment fails?
Money flows through Stripe. If a customer's reveal payment (the 3% fee to unlock a supplier's contact) fails, the contact simply is not revealed and they can retry — nothing is charged and no identity is exposed. If a supplier's annual subscription (AED 1,000/year) payment fails, their registration is not activated or lapses, pausing new matching until it is paid. Failed payments never silently grant access; the platform reconciles Stripe events so records stay accurate.

## [Operations] What happens if AI confidence is low?
Low confidence triggers caution, not action. In matching, the rule is "a wrong match is worse than no match" — if the engine is not confident a supplier truly fits, it excludes them and can return zero matches rather than guess. Elsewhere (capability write-ups, new-category knowledge, document reads) low-confidence output is marked and held for founder review before it is published or acted on. It escalates to a human rather than proceeding.

## [Operations] What happens if an RFQ is incomplete?
The intake agent turns the customer's words and photos into a structured brief and checks completeness against the category's qualification playbook. If key details are missing, the RFQ is not marked ready and is not dispatched to suppliers — the customer is asked for the missing information (and can edit within 1 hour). It only enters matching once it is complete enough to quote accurately, protecting both sides from bad matches.

## [Operations] What happens if no suppliers accept?
Two cases. If the engine finds no genuinely suitable supplier, it deliberately contacts no one (never random sends) and raises an internal coverage-gap signal telling the team exactly which trade and emirate to recruit. If suppliers were matched but none respond, response is tracked and the customer is kept informed; the request can be broadened or escalated. The customer is never handed a random or unsuitable supplier just to fill the slot.

## [Operations] What happens if regulations change?
UAE codes and authority requirements live in the knowledge base, and the Knowledge Curator watches for stale or missing compliance content. When rules change, updated authority documents are ingested and — under the oversight-first model — approved before going live; category requirements, qualification playbooks and agent knowledge are then updated. Agents always retrieve the current requirements and point users to the official source of record, so guidance stays aligned with the latest regulations.

## [Performance] What is the maximum supported concurrent users?
There is no formally load-tested published number yet. In practice, concurrency is bounded by Supabase's managed connection pooling and Edge Function auto-scaling (both scale on the plan), while the public site — being fully static on Vercel's CDN — serves effectively unlimited concurrent readers. Honest note: a proper load test has not been run, so QuotesDone should not quote a hard concurrent-user figure; the architecture handles typical B2B-marketplace concurrency comfortably, and a benchmark should precede any specific claim.
(Audience: internal)

## [Performance] What is the maximum number of suppliers supported?
No hard cap. The supplier directory already holds 20,000+ entries and the database handles that comfortably; Postgres scales to millions of rows, and storage/compute grow with the plan. The practical ceiling is commercial, not technical.
(Audience: internal)

## [Performance] What is the maximum number of RFQs (inquiries) supported?
No hard cap. Each RFQ is a database row, indexed by status, date and customer; Postgres handles millions of rows without issue. Volume scales with the plan's storage.
(Audience: internal)

## [Performance] What is the maximum number of quotations supported?
Same as RFQs — quotations are indexed rows with no fixed limit, scaling with database storage. No architectural ceiling at any realistic marketplace volume.
(Audience: internal)

## [Performance] What is the maximum file size?
Supplier attachments and catalogues accept up to 1 GB per file (large uploads use a chunked path so big catalogues do not fail); typical drawings and documents are a few MB. The storage buckets enforce the limit.
(Audience: internal)

## [Performance] What is the database optimisation strategy?
Postgres 17 with purpose-built indexes (btree on foreign keys, status and dates; GIN for full-text search; pgvector for embeddings), row-level security throughout, managed connection pooling, and heavy work pushed to scheduled/queued Edge Functions and cron rather than the request path. Honest gap: there is no formal query-performance monitoring / APM dashboard yet — slow-query profiling is a sensible next step.
(Audience: internal)

## [Performance] What is the caching strategy?
The public site is fully static and cached at Vercel's edge CDN worldwide, so most public traffic never touches the database. Agent knowledge is pre-compiled into _global (computed once on approval, not recomputed per query), and live artifact reads are cached. Honest note: there is no application-level cache (e.g. Redis) in front of the dynamic APIs today — each dynamic call hits Postgres directly; a cache layer can be added if load ever demands it.
(Audience: internal)

## [Performance] What is the CDN strategy?
Vercel's global CDN serves the static site and assets from edge locations close to each visitor, automatically. User documents are served through short-lived signed URLs from Supabase Storage (itself CDN-backed), so files are delivered quickly without exposing internal paths.
(Audience: internal)

## [Performance] What is the search indexing strategy?
Hybrid retrieval: Postgres full-text search (tsvector/GIN) combined with pgvector semantic embeddings, then Smart Engine adjudication on top — deliberately conservative, since a wrong match is worse than no match. The supplier directory and catalogue content are indexed for this. Honest note: no external search engine (Elasticsearch/Algolia) is used; Postgres FTS + pgvector covers the current scale, and a dedicated search service is an option if volume grows substantially.
(Audience: internal)

## [Platform Architecture] What is QuotesDone's system architecture?
A serverless, AI-first architecture on Supabase and Vercel. The backend is Supabase — PostgreSQL (with row-level security), Auth, Storage, and Deno/TypeScript Edge Functions — where all business logic lives as edge functions (running with service-role access) plus SQL functions. The Smart Engine agents are edge functions that call an LLM gateway and read a governed knowledge base. The frontend is a static site on Vercel. Event-driven and async work runs through database triggers, pg_net (outbound HTTP) and pg_cron (scheduling). Third-party capabilities (payments, messaging, email, backup, ads) sit behind the backend.
(Audience: internal)

## [Platform Architecture] Why was this architecture chosen?
It maximises leverage for a lean, AI-first company: serverless components scale automatically and cost little when idle; Postgres gives one strong, consistent source of truth with security enforced at the row level; edge functions keep all sensitive logic server-side. Static hosting makes the public site fast and cheap to serve globally. Keeping business rules in the database and edge functions (not the client) makes the system secure, auditable, and easy for the Smart Engine agents to operate under human oversight.
(Audience: internal)

## [Platform Architecture] Which technologies are used?
Supabase (PostgreSQL, Auth, Storage, Edge Functions on Deno/TypeScript), pg_cron and pg_net for scheduling and outbound calls, and vector embeddings plus full-text search for matching and knowledge retrieval. The frontend is static HTML/CSS/JS on Vercel. The Smart Engine uses an LLM gateway (OpenRouter, with Claude Opus/Sonnet and fallbacks). Integrations: Stripe (payments), Twilio and WhatsApp (messaging/OTP), an email service (Resend), Dropbox (document backup), and Meta Ads (marketing).
(Audience: internal)

## [Platform Architecture] How are frontend and backend separated?
Cleanly. The frontend is a static, pre-rendered site (marketing pages, customer app, supplier portal, internal OS) served from Vercel's CDN — it holds no business logic or secrets. It talks to the backend only through authenticated calls to Supabase Edge Functions, which enforce auth and run all logic against the database with service-role access. Secrets never reach the browser, and the client never runs privileged queries directly against the database.
(Audience: internal)

## [Platform Architecture] How are Edge Functions used?
They are the backbone: they serve each page (rendering HTML from the pages table), expose the action-based APIs the apps call (customer, supplier, OS), run every Smart Engine agent, and handle integrations and webhooks (Stripe, messaging, Dropbox). They run server-side with service-role access, are individually deployable and versioned, and are gated by JWT/role for user calls or a shared internal secret for service-to-service and scheduled calls.
(Audience: internal)

## [Platform Architecture] How are APIs versioned?
Each Edge Function is versioned by the platform on every deploy (v1, v2, …), so changes are tracked and reversible. The internal service APIs are action-based — one function endpoint that routes on an action field — rather than versioned REST paths, and each carries an explicit version in its code, so behaviour can evolve without breaking callers. There is no public/partner API yet; all interaction is through the apps and portal.
(Audience: internal)

## [Platform Architecture] How are services decoupled?
Services are small, single-responsibility edge functions that communicate through the database and events rather than tight coupling. Triggers and pg_net fire follow-on work asynchronously (e.g. a finalized RFQ automatically triggers matching and seller notification), pg_cron runs recurring jobs (backups, collections, reminders, evaluations), and functions call each other through gated internal endpoints. Each piece is independently deployable and testable.
(Audience: internal)

## [Platform Architecture] What is the application lifecycle?
A user loads a static page from Vercel; the app calls an Edge Function with the user's auth token; the function verifies identity and role, runs the business logic (SQL functions, the LLM gateway, integrations) with service-role access, and returns JSON the UI renders. Sensitive or irreversible steps raise an approval item for a human instead of completing automatically. Longer or recurring work (matching, backups, collections) happens asynchronously via triggers and scheduled jobs.
(Audience: internal)

## [Platform Architecture] How are deployments managed?
Three tracks: database changes as versioned migrations; Edge Functions deployed individually, each getting a new platform version; and the public website rebuilt by a deploy function that pre-renders every route into static files and pushes a new Vercel production deployment. Configuration and secrets live in a secured store, not in code. Each track is independently releasable and reversible.
(Audience: internal)

## [Platform Architecture] How is scalability achieved?
Every layer scales independently: the static site from Vercel's global CDN; stateless Edge Functions that scale automatically with load; a managed, scalable Postgres. Heavy or bulk work is moved off the request path into scheduled jobs and batched processing, responses are cached where safe, and vector + full-text retrieval keeps matching fast as data grows. Being serverless and stateless, it absorbs spikes without manual capacity planning.
(Audience: internal)

## [Quotation] What makes a good quotation?
A complete, itemised, transparently-priced quote: line items with brand/model, specifications, quantities and unit prices, plus scope, materials, lead time, validity, warranty, payment terms and any exclusions. Good quotes are easy for the customer to compare and win more often.

## [Quotation] What fields are mandatory?
The required sections for that category — typically: scope of work; itemised line items (BOQ) with brand/model, specifications, quantities and unit prices; materials; lead time; validity; warranty; payment terms; and exclusions. A quote must include these to pass the quality bar and reach the customer.

## [Quotation] What documents must be attached?
The itemised quote itself is what is required. You may optionally attach your own official company quotation (PDF) — the platform also generates a clean, anonymised version — and datasheets are recommended for regulated or branded items. Company documents such as your trade licence are handled once at registration, not per quote.

## [Quotation] How are quotations compared?
Side by side and anonymised (Supplier A, B, C), all normalised against the same brief so it is like-for-like. The customer sees each quote's price, inclusions and exclusions, lead time, warranty and terms, alongside a price-confidence band to sanity-check value.

## [Quotation] What is a BOQ?
A BOQ (Bill of Quantities) is the itemised list of materials and works — each with its quantity and unit — that a quotation is priced against. It makes quotes precise and directly comparable.

## [Quotation] What is included in the comparison?
For each quote: the price, the line items, scope/inclusions and exclusions, lead time, validity, warranty and payment terms, plus the supplier's rating and verification status and a price-confidence band. Everything the customer needs to choose on value, not just the lowest number.

## [Quotation] What happens if a quotation is missing information?
Quotes must pass a quality bar before the customer sees them. If something important is missing, the Smart Engine coaches the supplier to complete it, and the quote is held as a draft until it meets the standard — so customers only compare complete quotes.

## [Quotation] Can the Smart Engine reject quotations?
It does not reject you outright — it enforces a quality standard. A quote below the required completeness score is held as a draft with specific coaching on what to add, and is released to the customer once it meets the bar. This protects everyone: customers get complete quotes, and good suppliers are not undercut by half-finished ones.

## [Quotation] How are quotation scores calculated?
Each quote is scored on how completely it covers the category's required sections and how well it is itemised — scope, line items with brand/model and specs, quantities and unit prices, and the commercial terms. It must reach the quality threshold to be submittable to the customer.

## [Quotation] Can suppliers revise quotations?
No — once a supplier submits a quotation it is final, so it should be reviewed carefully before sending. After a customer reveals a supplier, any changes are arranged directly between them, off the comparison.

## [QuotesDone Constitution] Constitution: Never guess.
Agents retrieve before answering; below confidence they escalate rather than fabricate. Enforced by the retrieve-first design and eval checks.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Always retrieve before answering.
Hybrid retrieval (full-text + pgvector) grounds every substantive answer; kb_usage_log records what was used.
(Audience: internal)

## [QuotesDone Constitution] Constitution: A wrong supplier is worse than no supplier.
Matching is deliberately conservative; low-confidence matches are withheld or escalated, never forced.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Customer anonymity is never compromised.
Buyers are anonymous to suppliers end-to-end; identity is revealed only via the paid reveal the customer controls, with blind quoting throughout.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every recommendation must be explainable.
Agent cards carry reasoning plus click-through to source; comparisons show per-supplier rationale.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every important decision must be auditable.
agent_actions history, the append-only security_audit_log for governance changes, and per-feature session logs provide the trail.
(Audience: internal)

## [QuotesDone Constitution] Constitution: AI may recommend but not execute irreversible actions without approval.
Oversight-first: sends, charges, publishing, deletion and permission/legal actions all require founder approval.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Structured data is preferred over free text.
Itemised quotes are enforced, business rules are config-as-data, supplier capability is enriched into structured fields, and typed records are preferred over prose.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Official sources take precedence over third-party information.
Knowledge ranks authoritative, cited sources first; conflicts resolve toward official and most-recent.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Security defaults to deny-by-default.
RLS is deny-by-default on every table; RBAC is least-privilege; secrets are service-role-only.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every workflow must be recoverable.
Daily managed + logical backups, dr_drill restore drills, versioned functions, known rollback paths and the IR runbook keep workflows recoverable.
(Audience: internal)

## [QuotesDone Constitution] Constitution: Every business rule must be configurable rather than hard-coded.
Config-as-data (collections_config, pricing_config, feature_flags and similar) keeps rules tunable under approval with an audit trail.
(Audience: internal)

## [Reporting] What reports can customers see?
Customers see reporting scoped only to their own requests — never other customers' or the wider marketplace. Per inquiry they see its live status (matched → quoted → revealed), the quotes received (supplier identities stay hidden until they choose to reveal), and the Smart Engine's Quote Comparison Report: a plain-language, side-by-side analysis of their anonymized quotes (Supplier A/B/C) with a ranked top-3 recommendation, what each price actually buys, spec deviations, missing items, watch-outs and advice. There are no cross-customer or marketplace-wide dashboards.

## [Reporting] What reports can suppliers see?
Suppliers see reporting about their own account only. In the portal this includes their profile / digital twin, their reputation and merit standing, and performance metrics — RFQs matched to them, quotes submitted, win rate, response rate and rating — plus an exposure view (RFQs in their categories in the last 30 days and whether they were matched). They see the itemized quotes they submitted. They never see other suppliers' data, customer identities, or competitors' pricing.

## [Reporting] What reports can administrators see?
Administrators see the full picture inside the QuotesDone OS: an Executive Command Center; Finance/CFO reports (P&L, cash, forecasts); Supplier 360 and Customer 360 workspaces; RFQ/procurement; and Marketing, Knowledge, Documents, Operations, Legal, Security and Governance workspaces, plus each Smart Engine agent's operations panel. Reports export as branded PDFs, span every KPI and record, and support click-through to the underlying source.

## [Reporting] Which KPIs are monitored?
KPIs are grouped by domain, each with a live scorecard: Marketplace health (supply/demand, coverage gaps); Suppliers (health, match/quote/win rates, response rate, rating, licences expiring, compliance); Customers (activity, retention, health); Finance (revenue, reveal fees, commission owed/paid, forecast); Marketing (category demand, campaign performance); Knowledge (coverage, playbook coverage, curator health); and Operations, Legal, Security, Documents, Governance and Strategy scorecards. Matching quality is tracked separately as precision/recall.

## [Reporting] How are analytics calculated?
Analytics are computed directly from the platform's own operational data — inquiries, matches, quotes, transactions, reveals, reviews and agent actions — by SQL views that run on live data, with no manual entry. For example: win rate = deals won ÷ quotes submitted; quote rate = quotes ÷ RFQs matched; response rate = reveals responded ÷ reveals received; commission owed = sum of unpaid dues; supplier/customer health = weighted composite scores; matching precision/recall from the evaluation harness. Figures refresh as the underlying data changes, so every report reflects the current state.

## [RFQ] What is an RFQ?
RFQ means Request for Quotation — your job request. On QuotesDone you describe what you need (in words, voice, a photo or a drawing) and the Smart Engine turns it into one clear, structured brief that suppliers can price against.

## [RFQ] What information is mandatory in an RFQ?
Enough for a supplier to give a firm price without contacting you: what you need, the key specifications and quantities for that type of work, the general area and emirate, and any drawings or bill of quantities you have. The exact must-have fields depend on the category, and the Smart Engine asks you for anything still missing.

## [RFQ] How does the Smart Engine qualify an RFQ?
It reads your words, photos or drawings, structures them into a supplier-ready brief, applies the qualification playbook for that category to ask the right questions, and scores how complete the request is — only sending it out once it is ready to be priced.

## [RFQ] What makes an RFQ complete?
It is complete when it contains everything a supplier needs to return a firm fixed price without meeting you: clear scope, the price-driving specs and quantities for that category, the area and emirate, and any needed visuals. At that point it is marked ready and goes to matched suppliers.

## [RFQ] What happens if information is missing?
The Smart Engine asks you a few easy, tap-to-answer questions to fill the gaps. If something is genuinely unknown, it is recorded as an open item for the supplier to propose — so you are never stuck — and the request only goes out once it is complete enough to price.

## [RFQ] Can the Smart Engine estimate budgets?
It does not invent a budget or price for you — suppliers set the price. Budget is optional. What it can show is a price-confidence band (a typical range from comparable jobs) so you can sanity-check the quotes you receive.

## [RFQ] Can the Smart Engine estimate timelines?
It will not promise a delivery date — each supplier states their own lead time in their quote. As a rule of thumb, quotes themselves usually arrive within 3-5 working days.

## [RFQ] Can the Smart Engine recommend specifications?
It will not push technical choices on you. Where a choice is technical, it notes it as "supplier to propose suitable options with prices." It uses category knowledge and UAE codes to make sure the brief captures what matters and to flag compliance — but the supplier proposes and prices the technical specification.

## [RFQ] How are suppliers matched (RFQ)?
The Smart Engine shortlists suppliers by real capability, keywords and the emirates they serve, then judges each candidate on whether they can genuinely do your exact job. Only genuinely-capable suppliers are invited — a wrong match is treated as worse than no match — and any number of the invited suppliers may quote: there is no fixed limit.

## [RFQ] How is RFQ quality measured?
Each request is scored for completeness against the category checklist and playbook, and must reach the "ready" bar before it is sent to suppliers. (Separately, suppliers' quotes are quality-gated too, so what you compare is complete and like-for-like.)

## [Security] How is data encrypted?
Your data is encrypted in transit (every connection uses TLS/HTTPS) and at rest on our managed cloud database and storage. Card payments are handled entirely by Stripe, so payment-card details never touch our own servers.

## [Security] How are documents protected?
Files such as licences, drawings and quotations are kept in private storage that is not publicly accessible. They are reached only through the app using short-lived signed links, uploads are scanned for malware, and customer drawings are automatically redacted to remove identifying details before any supplier sees them.

## [Security] Who can access my files?
Only you and the parties who are supposed to. The platform serves your files to your own account, and identities stay hidden between customer and supplier until a paid reveal. There is no open or public access to files — everything is served through the backend with strict authorisation.

## [Security] How are permissions managed?
The database is deny-by-default — nothing is readable directly with a public key. Every read and write goes through backend functions that check who you are and what you are allowed to do (role-based access), and admin areas require additional authentication, including multi-factor authentication.

## [Security] How are backups performed?
The system is backed up on a regular schedule to durable off-site storage, and disaster-recovery drills are run to confirm data can be restored. Completed requests are also archived separately.

## [Security] How are cyber attacks detected?
Through continuous automated monitoring: security scans, fraud checks, malware scanning of uploads, decoy/canary traps, and health and uptime checks — with alerts raised to the founder when something looks wrong. Suspicious activity, such as attempts to share contacts off-platform, is flagged.

## [Security] What happens during a security incident?
There is a defined response: the issue is detected and alerted, contained, and investigated using the immutable audit logs; affected parties are informed as appropriate; sensitive actions are reversible; and data can be restored from backups if needed. Personal data — and any breach — is handled responsibly under UAE data-protection law (PDPL).

## [Security Testing] How often are penetration tests performed?
Honest: no third-party penetration test has been commissioned yet — this is a real gap. Present-day assurance comes from the managed-platform security (Supabase/Vercel/AWS), row-level-security deny-by-default, and the oversight model. A professional external pen test is recommended before or alongside meaningful scale.
(Audience: internal)

## [Security Testing] How often are vulnerability scans run?
Honest: there is no scheduled automated vulnerability scanner (e.g. recurring DAST) today. The closest real control is Supabase's built-in Security Advisor, which lints for RLS gaps, exposed policies and misconfigurations and can be run on demand. Formal, scheduled scanning is a gap to add.
(Audience: internal)

## [Security Testing] How are dependencies monitored for CVEs?
Honest: there is no automated CVE/dependency alerting (no Dependabot/Snyk-style tooling) wired up. This is partly mitigated because the backend runs on Deno with a small, explicit set of imports and the managed platforms patch their own runtimes — but application-level dependency-CVE monitoring is a gap worth closing.
(Audience: internal)

## [Security Testing] How are OWASP Top 10 risks mitigated?
This has genuine substance. Injection — the database is accessed through parameterized queries, and RLS constrains every table. Broken access control — RLS is deny-by-default with RBAC roles on top; all public tables have RLS enabled. Auth failures — Supabase Auth with bcrypt, rate limiting, email verification, SMS OTP and an 18+ gate. Secrets/exposure — secrets are service-role-only and never sent to clients; internal paths are never exposed. Misconfiguration — reduced by the managed platform plus RLS-enabled everywhere. Honest notes within the Top 10: uploaded files ARE scanned against VirusTotal (known-malware hash lookup, daily) — though novel-file sandboxing is not yet in place — while application dependency-CVE monitoring and some logging/monitoring coverage are still uneven. So: strong on access-control, injection and auth; weaker on supply-chain and parts of logging/monitoring.
(Audience: internal)

## [Security Testing] How are third-party libraries reviewed?
Honest: the dependency surface is kept deliberately small and imports are explicit/pinned, and new libraries are added consciously rather than casually — which limits risk. But there is no formal security review or software bill-of-materials (SBOM) process. The small surface helps; a formal review step is a gap.
(Audience: internal)

## [Security Testing] How are secrets scanned before deployment?
Honest: secrets live in the app_secrets table and platform secret store (service-role-only) and are kept out of client code and the codebase by convention and by the service-role isolation itself. But there is no automated pre-deploy secret scanner (e.g. gitleaks/trufflehog) acting as a gate. Discipline plus service-role isolation protect today; an automated scan is a gap.
(Audience: internal)

## [Security Testing] How are security regressions prevented?
Primarily structural: RLS is deny-by-default, so a newly created table is closed until a policy is explicitly and deliberately added; the Supabase Security Advisor catches RLS/policy regressions; and all security changes require founder approval. Honest gap: there is no automated security-regression test suite in CI — prevention rests on the deny-by-default posture, the advisor, and oversight rather than an automated gate.
(Audience: internal)

## [Smart Engine] What does the Smart Engine do?
It runs QuotesDone end to end: it understands a customer's request and turns it into a clear brief, matches it to genuinely-capable suppliers, checks quote quality, answers questions using verified UAE knowledge, and handles routine operations — always grounded in real data, never inventing prices, brands or rules.

## [Smart Engine] What decisions can the Smart Engine make?
Low-risk, reversible, well-understood ones on its own: structuring a brief, asking clarifying questions, matching and inviting suppliers, scoring RFQ and quote completeness, surfacing the applicable regulations, drafting communications, and routine housekeeping — and every action is logged.

## [Smart Engine] What can't the Smart Engine decide?
Anything sensitive or irreversible is gated to a human (the founder): moving or refunding money, publishing legal or contract documents, changing pricing or policy, approving high-stakes regulatory content, or anything it is not confident about. It prepares and recommends; a person approves.

## [Smart Engine] How accurate is the Smart Engine?
It is built for accuracy over guesswork: answers must be grounded in retrieved, verified sources (UAE codes, company knowledge), and it is benchmarked and monitored. When it is not sure, it says so or defers rather than inventing an answer. No system is perfect, which is why grounding, review and human oversight are built in.

## [Smart Engine] Does the Smart Engine guess?
No — it is designed not to. A hard grounding rule requires answers to come from verified knowledge; if the information is not there, it asks you, records it as an open item, or escalates — rather than fabricating specifications, prices or regulations.

## [Smart Engine] How does the Smart Engine use knowledge?
It retrieves from a curated knowledge base — UAE regulations and standards, category expertise, materials and company facts — and grounds its answers in those sources. The knowledge is version-controlled and reviewed before it goes live.

## [Smart Engine] When does the Smart Engine escalate?
Whenever an action is sensitive, irreversible, low-confidence or outside policy — money, legal/contract publishing, pricing or policy changes, high-stakes compliance — it stops and routes it to the founder for approval, with the full context and its recommendation.

## [Smart Engine] How is the Smart Engine monitored?
Every decision passes a governance gate and is written to an immutable log; sensitive actions keep a before-image so they can be undone; and health checks, evaluations and a dedicated Trainer track quality continuously, with alerts surfacing anything that needs attention.

## [Smart Engine] Can the Smart Engine make mistakes?
Yes — any system can, and QuotesDone is built assuming it: grounding to reduce errors, a quality bar on quotes and RFQs, human approval on anything sensitive, an immutable audit trail, and reversibility on sensitive actions — so mistakes are caught, contained and correctable.

## [Smart Engine] How is the Smart Engine continuously improved?
It improves within guardrails: benchmarks and evaluations score its prompts and answers, a Trainer monitors each agent's quality, proposed improvements are tested before going live (only non-sensitive ones auto-promote, always with rollback), and lessons from closed cases feed back into its knowledge.

## [Supplier] How do I register?
Register on the QuotesDone supplier portal: claim or create your company listing, then upload your business documents (trade licence and the others requested). The Smart Engine reviews them and, once approved, you start receiving relevant, anonymised job requests to quote on.
(Audience: supplier)

## [Supplier] What documents are required?
Your valid UAE trade licence is the key document. You will also be asked for supporting details such as your VAT certificate (TRN), bank IBAN, insurance, and your company profile or product catalogue. Keeping your licence and insurance valid keeps your account active.
(Audience: supplier)

## [Supplier] How is my company verified?
Your uploaded documents are read and checked automatically (licence details, issuing authority, expiry) and reviewed for validity and relevance before your account is approved. We confirm your licensed legal name and trade so customers can trust who they are dealing with.
(Audience: supplier)

## [Supplier] How long does verification take?
Verification is fast — up to a maximum of 3 working days once your documents are complete. If anything needs fixing, we tell you exactly what is required.
(Audience: supplier)

## [Supplier] Why was my account rejected?
We rarely reject suppliers. You cannot finish signing up until you have uploaded the required documents on the supplier portal, so an incomplete registration simply is not completed rather than rejected. If a document is invalid or expired, we ask you to update it — fix it and you are good to go.
(Audience: supplier)

## [Supplier] How are projects assigned?
The Smart Engine reads each customer job and matches it to suppliers who can genuinely do it, based on your real capabilities and the emirates you serve. Only genuinely-capable suppliers are invited — you will not be spammed with irrelevant jobs.
(Audience: supplier)

## [Supplier] Can I decline invitations?
Yes — you are free to ignore any invitation that is not right for you; there is no penalty for not quoting. (The only charge is if a customer pays to reveal you and you then ignore them.)
(Audience: supplier)

## [Supplier] How many suppliers receive the same RFQ?
Only suppliers who can genuinely do the job, never a mass blast, and any number of them may quote: there is no fixed limit. The customer sees every quotation, and the comparison report recommends the strongest three by value.
(Audience: supplier)

## [Supplier] How do I submit quotations?
You quote from your supplier portal. Enter an itemised quotation — your line items with brand/model, specifications, quantities and unit prices, plus scope, lead time, validity, warranty and terms. Your quote reaches the customer anonymised; your identity stays hidden until they pay to reveal you.
(Audience: supplier)

## [Supplier] What information is mandatory?
A complete, itemised quote: scope of work; line items with brand/model and specifications; quantities and unit prices; materials; lead time; validity; warranty; payment terms; and any exclusions. Quotes must meet a quality bar before they reach the customer — the Smart Engine coaches you if something important is missing.
(Audience: supplier)

## [Supplier] Can I revise quotations?
No — once you submit a quotation it is final, so review it carefully before sending. After a customer reveals you, you are free to adjust anything directly with them — by that point the platform''s job is done.
(Audience: supplier)

## [Supplier] Can I withdraw a quotation?
Yes — you can withdraw a quotation before a customer reveals it.
(Audience: supplier)

## [Supplier] When do I know if I won?
You are notified the moment a customer pays to reveal your quote — that is your signal to respond and proceed. If the customer chooses another supplier, we let you know too, so you are never left wondering.
(Audience: supplier)

## [Supplier] How are commissions calculated?
There is no commission on won jobs — you keep 100% of the job value. The only charge tied to a job is the non-response charge if you ignore a customer who paid to reveal you: the customer's refunded reveal fee plus an AED 500 administrative fee and 12% per annum interest.
(Audience: supplier)

## [Supplier] When do I pay?
You pay nothing to quote and nothing when you win — there is no commission. Registration is free for the first 1,000 suppliers who register, and those suppliers stay free permanently. Every supplier who registers after them pays an annual subscription of AED 1,000; there is no fixed start date — it simply applies from the 1,001st registration onward. The subscription is paid on the supplier portal via secure Stripe checkout. The only other possible charge is a non-response fee if you ignore a customer who has already paid to reveal your details.
(Audience: supplier)

## [Supplier] What happens if I don't pay?
If your annual subscription (or a non-response fee) is due and left unpaid, your account is paused from receiving new matches until it is settled on the portal. We remind you first.
(Audience: supplier)

## [Supplier] How is my supplier score calculated?
Your score reflects real performance: customer reviews across communication, quality, punctuality, documentation, after-sales and compliance, plus your responsiveness and dispute record. It builds a trusted reputation that customers can see.
(Audience: supplier)

## [Supplier] How do I improve my ranking?
Respond quickly, submit complete well-itemised quotes, deliver well and earn strong reviews, keep your licence and documents valid, and stay compliant. Merit — not payment — drives your ranking.
(Audience: supplier)

## [Supplier] Can I advertise?
There is no advertising on QuotesDone. Instead, every supplier earns a rating against QuotesDone''s standards based on real performance — you stand out by delivering well, not by paying.
(Audience: supplier)

## [Supplier] Can I operate in multiple Emirates?
Yes — you set the emirates you serve, and you are matched to jobs in each of them.
(Audience: supplier)

## [Supplier] Can I operate in multiple categories?
Yes — you can cover multiple trades/categories. Keep your capabilities profile complete and accurate so the Smart Engine matches you to the right jobs.
(Audience: supplier)

## [Supplier] Is there a subscription fee for suppliers?
Not for the first 1,000 suppliers who register — and never for them. Registration is free for the first 1,000 registered suppliers, who are exempt permanently. Every supplier who registers after them pays an annual subscription of AED 1,000 per year; there is no fixed start date — it applies from the 1,001st registration onward. There is never any commission on the jobs you win.

## [Supplier Intelligence] How is supplier health calculated?
A 0-100 composite: quality 30% + compliance 30% + response 20% + retention 20%. Quality = best of performance score / review quality / rating. Compliance = trade licence + insurance + establishment card + TRN present-and-valid, minus penalties for chat strikes and expired ISO/manufacturer authorisation. Response = reveal-response rate (or quote rate). Retention = recency of activity + active registration. It also outputs a risk tier (high/medium/low).
(Audience: internal)

## [Supplier Intelligence] How is supplier reliability measured?
Mainly the response and retention components plus non-response history: reveal-response rate, quote rate, recency, and any non-response fines or chat strikes. A supplier who is invited but repeatedly does not respond drops on reliability and can be matching-blocked.
(Audience: internal)

## [Supplier Intelligence] How is response quality measured?
From reviews scored across quality, documentation and compliance dimensions (averaged), plus win and quote rates in supplier_perf. Detailed, compliant quotes and good post-job reviews raise it.
(Audience: internal)

## [Supplier Intelligence] How is quotation quality scored?
Itemised quotes are enforced at entry; the comparison engine assesses line detail, spec compliance/deviations and completeness. Vague lump-sum quotes score lower than detailed, spec-matching ones.
(Audience: internal)

## [Supplier Intelligence] How is delivery performance measured?
Honest gap: QuotesDone is an anonymous quotation marketplace up to the reveal, so it does not yet track post-reveal fulfilment/delivery directly. Delivery is proxied by post-job reviews (which can reflect delivery) and win rate, not a dedicated on-time-delivery metric. A post-job delivery/outcome capture is a candidate enhancement.
(Audience: internal)

## [Supplier Intelligence] How are complaints weighted?
Through reviews (low ratings on quality/documentation/compliance), chat strikes and disputes; these reduce the quality/compliance components and can raise the risk tier or trigger a matching block. Repeated complaints escalate.
(Audience: internal)

## [Supplier Intelligence] How is supplier risk calculated?
supplier_health outputs a risk tier: high if banned/matching-blocked/strikes 3+/compliance under 40/health under 40; medium if compliance under 75, any strikes, low retention or health under 65; else low. Expired critical documents and non-response fines push risk up.
(Audience: internal)

## [Supplier Intelligence] How is fraud probability calculated?
fn_fraud_scan flags abnormal signals (e.g. pricing far outside the category band) into fraud_flags; v_fraud_score aggregates open flags into a 0-100 per-actor score with a tier. Honest: it is a rules/heuristic score today, not a trained probabilistic model.
(Audience: internal)

## [System Governance] What are the platform's architectural principles?
Oversight-first (surface, recommend, escalate — never take an irreversible action without founder approval); managed-platform-first (build on Supabase/Vercel rather than self-running infrastructure); config-as-data (critical business rules are tunable data, not hard-coded); deny-by-default security (RLS on every table); single source of truth (e.g. company_faq feeds both the agents and the public site); stateless, independently deployable functions; merit-and-anonymity-based matching; and honesty over overclaiming.
(Audience: internal)

## [System Governance] What coding practices are mandatory?
Backend functions are service-role-only and gated by inbound_secret; database access is parameterized; RLS must be enabled on every new table; secrets and internal file paths are never exposed to clients; brand terminology (Smart Engine; buyers/sellers) is used consistently; syntax is validated before deploy; the change is verified live afterward; and a session log is written. Honest note: these are enforced by convention and oversight, not yet by an automated linter or CI gate.
(Audience: internal)

## [System Governance] What security principles are mandatory?
Deny-by-default RLS; least-privilege RBAC; secrets held service-role-only; founder approval required for any security change; no irreversible action without approval; privacy-preserving defaults; and defer-do-not-bypass when a verification dependency is unavailable.
(Audience: internal)

## [System Governance] What compliance principles are mandatory?
Grounding in UAE law (VAT; the commercial-transactions interest cap; civil-code limits on penalties); the approved no-commission model; legal actions always draft to founder-approve to send, with the signed Terms as evidence; a "this is not legal advice — a UAE lawyer must review" stance on legal templates; the 18+ age gate; and adherence to the data-retention and privacy policies. Honest note: there is no formal external compliance certification (SOC 2 / ISO 27001) yet.
(Audience: internal)

## [System Governance] What data quality standards are enforced?
Itemized, detailed quotes are required (no vague lump sums); supplier capability data is enriched at registration; verification gates matching and reveal; duplication is controlled (backup dedupe keys, quote-set comparison signatures); and canonical answers must be approved before agents use them. Real registered suppliers are kept distinct from the 20,000+ directory leads. Honest gap: there is no formal data-quality monitoring/validation dashboard yet.
(Audience: internal)

## [System Governance] What documentation standards are enforced?
A session log per feature, company_faq documenting real platform behaviour, and llms.txt for machine readers. Honest gap: no formal architecture document or operational runbook library yet.
(Audience: internal)

## [System Governance] What testing standards are enforced?
A live smoke test and verification after every change; a matching-precision benchmark harness; prompt eval/benchmarking before any prompt promotion; and built-in self-test operations for pipelines (e.g. the backup engine). Honest note: there is no automated CI test suite — testing is manual plus targeted harnesses.
(Audience: internal)

## [System Governance] What constitutes production readiness?
Under the working definition: the change is built, syntax-validated, verified live against real data with no regression, gated behind founder approval for anything sensitive, has a known rollback path, keeps secrets isolated and RLS in place, and is documented in a session log. Honest note: this is the operative oversight-based definition — not a formal production-readiness checklist enforced in a pipeline.
(Audience: internal)

## [Technical] What regulations apply?
It depends on the trade and emirate. The Smart Engine draws on an indexed UAE regulatory library and flags the codes relevant to your specific job — for example DEWA for electrical, Dubai Civil Defence (UAE Fire & Life Safety Code) for fire, Dubai Municipality (Al Sa'fat green building, drainage) for buildings, SIRA for security/CCTV, MoIAT/ESMA (ECAS) for products, and Trakhees/DDA inside free zones. The supplier remains responsible for code-compliant design and obtaining authority approvals.

## [Technical] Which standards are used?
UAE.S / GSO national standards, plus the international standards that UAE code references where they apply to the trade (for example ISO and EN, IEC / BS 7671 for wiring, ASHRAE for HVAC, NFPA for fire). The Smart Engine surfaces the standards relevant to your category rather than a single universal list.

## [Technical] Which manufacturers are approved?
QuotesDone does not run its own approved-manufacturer list or endorse particular companies. What matters is that the products quoted meet the required UAE approvals for the job — for example DCD-listed fire products, ESMA/ECAS-conformant regulated products, or DEWA-approved electrical equipment. The Smart Engine references recognised authority approvals; the supplier proposes compliant products.

## [Technical] Which brands are recommended?
QuotesDone is brand-neutral — it does not push or rank specific brands. It makes sure whatever brand is quoted meets the required specifications, standards and UAE approvals for your job; the supplier proposes the brand and you choose. This keeps the marketplace fair and unbiased.

## [Technical] Which materials are suitable?
It depends on the application. The Smart Engine uses its materials knowledge and category specifications to make sure your brief captures suitable material options and the things that drive their price, and notes where the supplier should propose options. It does not dictate a single material — it ensures the choice is captured and compliant.

## [Technical] What certifications are required?
Trade- and product-dependent: for example ECAS/EQM product conformity (MoIAT/ESMA) for regulated goods, SIRA licensing for security work, DCD approvals for fire systems, and manufacturer authorisation for certain branded equipment — alongside the supplier's own valid trade licence and insurance. The Smart Engine flags the certifications relevant to your job.

## [Technical] What warranties are acceptable?
There is no single fixed rule — warranty is a required field in every quote, so it is always stated and easy to compare. Typical UAE practice (such as a workmanship warranty plus the manufacturer's product warranty) is captured per category, and you decide what is acceptable for your job.

## [Technical] What testing is required?
It depends on the system — for example pressure testing for plumbing, insulation-resistance and earthing tests for electrical (DEWA), testing and commissioning for fire systems (DCD/NFPA), or flood tests for waterproofing. The Smart Engine makes sure testing and commissioning are captured in the scope where relevant; the supplier performs and certifies them.

## [Technical] What inspections are required?
Authority inspections depend on the trade — for example a Dubai Civil Defence fire inspection before occupancy, DEWA inspection and energisation for electrical, Dubai Municipality inspections for building works, and Trakhees/DDA inspections inside free zones. The Smart Engine flags the inspections relevant to your job; the supplier or consultant coordinates them.

## [Technical] What approvals are required?
Authority approvals depend on the work and location — DEWA (electrical/utility), Dubai Civil Defence (fire & life safety), Dubai Municipality (building, drainage, green building), SIRA (security), MoIAT/ESMA (product conformity), GCAA (near airports), Trakhees/DDA (free zones) and KHDA (schools/nurseries). The Smart Engine identifies which apply to your job; obtaining them is the supplier's or consultant's responsibility.

## [User Verification] Is customer identity verified?
Customers go through lightweight verification suited to an anonymous B2B marketplace, not full ID/KYC. At sign-up we confirm a working email, apply an 18+ age check, capture and (where enabled) verify a mobile, and record acceptance of the Terms (signed copy stored). No passports or Emirates IDs — the aim is a genuine, reachable account while the customer stays anonymous to suppliers until they reveal.
(Audience: internal)

## [User Verification] Which verification methods are used (customer)?
Email confirmation via a one-time link; SMS six-digit code (Twilio Verify) where enabled; an 18+ age gate; and recorded Terms acceptance with timestamp and IP.
(Audience: internal)

## [User Verification] Is email verification required?
Yes — the customer account is not active until the email is confirmed via the one-time link (24-hour expiry, resendable, rate-limited).
(Audience: internal)

## [User Verification] Is phone verification required?
A mobile is always captured at sign-up, and SMS one-time-code verification is applied when the SMS channel is enabled; the account carries a phone-verified status. It is built as a standard step.
(Audience: internal)

## [User Verification] How are duplicate accounts detected?
Primarily by email — accounts are keyed to a unique verified email, and sign-up blocks a second verified account on the same email (pointing the person to sign in or reset). Phone numbers and behavioural signals add further duplicate/abuse detection.
(Audience: internal)

## [User Verification] Which supplier documents are mandatory?
The core mandatory document is a valid UAE trade licence. Depending on trade, additional documents are requested and checked — establishment card, VAT/TRN certificate, bank/IBAN letter, insurance, ISO certificates, manufacturer authorisations, company profile and catalogues. The licence gates registration; the rest strengthen the profile and are required where the category or job demands.
(Audience: internal)

## [User Verification] How is the UAE Trade Licence verified?
The Smart Engine reads the uploaded licence (extracting licence number, issuing authority, expiry, and licensed company name), those fields are format- and consistency-checked (name matches, not expired), an AI reviewer flags anomalies, and a human admin gives final approval — within a maximum of three working days. Verified against the official licence document, not a live government API.
(Audience: internal)

## [User Verification] How is VAT registration verified?
The TRN is captured and checked for valid format (a UAE TRN is 15 digits) and consistency with the licence and company name, with the VAT certificate on file; mismatches or malformed numbers are flagged. Not every supplier is VAT-registered; where they are, the TRN and certificate are recorded.
(Audience: internal)

## [User Verification] How is company ownership verified?
Through the licence and supporting documents — the licensed company name, the owner/partner or signatory on the licence and establishment card, and the person who accepts the Terms and completes registration (name, contact, signed acceptance with timestamp and IP). Consistency between signatory, account and licence is checked; discrepancies are flagged.
(Audience: internal)

## [User Verification] How are insurance certificates verified?
The certificate is uploaded and recorded with its expiry; presence and validity are checked and shown on the compliance scorecard, and expiry is tracked continuously and flagged as it nears lapse.
(Audience: internal)

## [User Verification] How are ISO certifications verified?
ISO certificates are uploaded, recorded, and their expiry tracked with reminders as they near lapse. They strengthen standing and can be required for jobs that call for them.
(Audience: internal)

## [User Verification] How are manufacturer authorisations verified?
Brand/manufacturer authorisation letters are uploaded and recorded against the brands the supplier claims, with validity/expiry tracked. They matter where a job specifies a brand — the engine can weigh whether the supplier is genuinely authorised — and expiring ones are flagged.
(Audience: internal)

## [User Verification] How are references validated?
Client references and project history are captured as part of the profile and feed the engine's view of capability. They can be spot-checked during review but are supporting evidence, not a hard gate — the mandatory gate is the trade licence and the document/consistency checks.
(Audience: internal)

## [User Verification] How are expired documents detected?
Every dated document (trade licence, insurance, ISO, manufacturer authorisations) has its expiry stored and monitored by a scheduled check. Approaching expiries surface on the compliance scorecard and trigger reminders; once expired, the supplier is treated as non-compliant and held out of matching until a valid renewal is uploaded.
(Audience: internal)

## [User Verification] What causes supplier rejection?
No valid trade licence; an expired or mismatched licence; a company name/owner that does not reconcile; junk/placeholder data; failed format/consistency checks (bad TRN/IBAN); signs of fraud or misrepresentation; or a trade the platform cannot lawfully support. Rejection is a human decision informed by the AI review, with the reason recorded.
(Audience: internal)

## [User Verification] What causes supplier suspension?
For an approved supplier: a compliance lapse (expired licence/insurance), repeated non-response to customers who paid to reveal them, unpaid dues (e.g. an outstanding non-response charge), or policy/behaviour violations and unresolved disputes. Suspension is reversible, recorded with a reason, and applied under admin authority.
(Audience: internal)

## [User Verification] What causes supplier reinstatement?
Remediation of whatever triggered the suspension — renewing the document, settling the amount, resolving the dispute, or correcting the behaviour — after which an admin lifts the matching block. A deliberate, recorded decision; the supplier returns to normal matching once compliant.
(Audience: internal)$qd$, embedding_gte = null where id = '177559' and md5(content) = '524e8201df310e3a6bdd71eddefb51eb';

-- re-render the company knowledge the seats read
do $s$ begin perform public.fn_company_org_directory_sync(); perform public.fn_company_self_knowledge_sync(); end $s$;

-- verdict

select case when exists (select 1 from public.company_faq where id in (13, 43, 67, 604, 712, 751)
                          and answer ~* '(usually a handful|is capped to keep|the number is capped|عدد محدود وليس|فالعدد مقيّد|سقف لعددهم)')
            then 'PROBE FAILED: an FAQ answer still caps the number of suppliers who may quote'
            when (select count(*) from public.company_faq where id in (13, 43, 67, 604, 712, 751) and answer ~ '(any number|لأي عدد)') <> 6
            then 'PROBE FAILED: not every corrected answer states that any number may quote'
            -- the five compiled copies too (review round 2): an md5 guard that no longer matches updates nothing, silently
            when exists (select 1 from public.agent_knowledge where id = '1047' and content ~* '(usually a handful|is capped to keep|the number is capped)')
              or exists (select 1 from public.kb_chunks where id in ('174634', '174373', '174667', '177559') and content ~* '(usually a handful|is capped to keep|the number is capped)')
            then 'PROBE FAILED: a compiled copy still caps the number of suppliers who may quote'
            else 'PROBE OK' end as verdict;
