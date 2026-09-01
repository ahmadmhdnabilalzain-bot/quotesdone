export const meta = {
  name: 'build-it-cyber-veteran-knowledge',
  description: 'Build the deep IT/cybersecurity knowledge layer (Step 3) at world-class depth: internal system mastery + professional body + threat intelligence + AI-security frontier, mapped to QuotesDone',
  phases: [
    { title: 'Map our system', detail: 'agents read the real code, schema and controls' },
    { title: 'Author the expertise', detail: 'professional + frontier + standards mapped to our stack' },
  ],
}

const RECORDS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    domain: { type: 'string' },
    records: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          title: { type: 'string', description: 'specific, searchable title' },
          subdomain: { type: 'string' },
          content: { type: 'string', description: 'deep, accurate reference an engineer/security agent would actually use, 600-2200 chars' },
          keywords: { type: 'array', items: { type: 'string' } },
          source_note: { type: 'string', description: 'for mapped records: which real artifact/standard this is grounded in' },
        },
        required: ['title', 'content', 'keywords'],
      },
    },
  },
  required: ['domain', 'records'],
}

const COMMON = `You are building the permanent knowledge base for QuotesDone's IT and cybersecurity AI agents (the product_eng and assurance departments) so they operate at the level of a world-class senior engineer / security lead who has worked here for 20 years. QuotesDone is an autonomous AI-run procurement marketplace (buyers post inquiries, suppliers quote, the platform reveals a top-3 comparison for a fee). Stack: Next.js/React frontend, Supabase (Postgres + PostgREST + Deno edge functions), a Postgres "kernel" that governs an AI agent workforce, crons, Stripe (payments), Twilio (SMS/voice), OpenRouter (inference). ONE Supabase project: htdblwldjkcgjvmqkbeh.
Produce knowledge records that are DEEP, ACCURATE and DIRECTLY USABLE — not generic filler. Every record must earn its place. Return ONLY the structured object.`

const SOURCED = COMMON + `
This is a MAPPING task: your records must describe QuotesDone's ACTUAL system, grounded in real artifacts. To read them:
- Load the Supabase MCP read tool via ToolSearch: query "select:mcp__94696680-91a7-4449-a548-ded2e7d4eae8__execute_sql", then run READ-ONLY SQL (SELECT only — never write/DDL) against project htdblwldjkcgjvmqkbeh.
- Read code with Read/Grep/Glob under C:/Users/Opera/quotesdone (edge functions in supabase/functions/, schema in supabase/schema/full_schema.sql), and orient with graphify-out/ (the code knowledge graph).
Cite real names (functions, tables, policies, files) in source_note. NEVER invent our configuration — if you cannot verify a detail, say so rather than guessing.`

const AUTHORED = COMMON + `
This is an EXPERTISE-AUTHORING task: write the professional/industry knowledge a world-class practitioner carries, but MAP every item onto QuotesDone's exact stack (Postgres/Supabase/Deno/Next.js + an AI agent workforce) so it is actionable HERE, not abstract. Where useful, read our real code/schema (Read/Grep/Glob under C:/Users/Opera/quotesdone, or the Supabase MCP read tool via ToolSearch, READ-ONLY) to ground the mapping. Be technically precise and current; name the standard/CVE/technique in source_note. Do not fabricate specifics about our config you have not verified — describe the risk and the check instead.`

const DIMS = [
  { phase: 'Map our system', label: 'edge-function-attack-surface', prompt: SOURCED + `
DOMAIN: Edge-function attack surface & API map. Inventory the edge functions in supabase/functions/ (there are ~203). Group them by purpose (auth/portal, payments/Stripe, AI/inference, admin/os, webhooks, crons). For the security-relevant ones, record: what it does, its inputs, whether it enforces JWT (verify_jwt) or is public, what privileged action it can take, and the abuse/misuse risk. Produce records that let a security agent reason about "how could this entry point be attacked" and an engineer know what each function is for. Aim for a strong API/attack-surface map (10-16 records).` },
  { phase: 'Map our system', label: 'database-security-rls-grants', prompt: SOURCED + `
DOMAIN: Database security — RLS, grants, SECURITY DEFINER, PostgREST exposure. Query pg_policies (RLS policies + which tables have RLS enabled/disabled), role grants (information_schema.role_table_grants for anon/authenticated/service_role), and SECURITY DEFINER functions (pg_proc.prosecdef) and their search_path. Record: which tables are exposed to anon/authenticated via PostgREST and how RLS constrains them, the SECURITY DEFINER surface (definer functions run as owner — the classic privilege boundary), tables WITHOUT RLS that are reachable, and the real security boundaries. This is the core of our data attack surface (10-16 records).` },
  { phase: 'Map our system', label: 'kernel-and-app-controls', prompt: SOURCED + `
DOMAIN: Kernel & application security controls (what is DEFENDING us). Map the kernel guards: write-authority register, truncate guards (z00_kernel_truncate_guard), the a00_/z90_ freeze digests (Phase A/B baselines), the action-authority tiers on org_action_executor (advisory/gated/supervised/autonomous), founder-reserved actions (e.g. refunds), the org_authority_guard + change_reason audit pattern, and any RAISE-based enforcement triggers. Read the kernel SQL (scripts/sql/, graphify) and query pg_trigger/pg_proc. Record what each control prevents, how it fires, and how a security agent would VERIFY it is still active (not just assume). (10-16 records).` },
  { phase: 'Map our system', label: 'auth-identity-and-baseline', prompt: SOURCED + `
DOMAIN: Auth/identity model + the baseline of normal. (1) How customers, suppliers and the founder authenticate: JWT via PostgREST, the portal token storage keys (qd-cust-*, qd-sup-*), the founder-session gates, verify_jwt on functions. (2) The BASELINE OF NORMAL a detection would compare against: the active crons (query cron.job) and their normal cadence/row-effects, normal agent_runs activity, expected traffic shapes, where secrets live (Supabase Vault / function env — names only, NEVER values). Record enough that a security agent can recognise DEVIATION (an off-baseline cron, an unexpected definer call, a new grant) as a signal. (10-16 records).` },
  { phase: 'Map our system', label: 'infra-integrations-incident', prompt: SOURCED + `
DOMAIN: Infrastructure, third-party integrations & incident response. Map: the Supabase project + Vercel frontend + the cron scheduler; the external integrations (Stripe payments/webhooks, Twilio, OpenRouter inference) and the trust/verification each requires (e.g. Stripe webhook signature verification — check whether our webhook function verifies it); the deploy/change-safety path (apply_sql read-back, CI gates, PR-only to main, the frozen phases); and incident response — the security-incident workflow (W29 if present) and how to contain/recover. Read real code/schema. (10-16 records).` },

  { phase: 'Author the expertise', label: 'owasp-appsec-secure-coding', prompt: AUTHORED + `
DOMAIN: Web/application security (OWASP) + secure-coding standards, mapped to us. For each relevant OWASP Top 10 (2021) category — injection (esp. SQL injection in dynamic plpgsql / string-built queries), broken access control (RLS/grants/IDOR on our id-keyed tables), SSRF (our functions that fetch URLs), cryptographic failures, security misconfiguration, vulnerable components, auth failures, SSRF, logging/monitoring — give the concrete QuotesDone manifestation, how to spot it in Postgres/Deno/Next.js code, and the secure pattern (parameterised queries, format() %I/%L, least privilege, output encoding). Make it a real appsec playbook for THIS codebase. (10-16 records).` },
  { phase: 'Author the expertise', label: 'ai-agent-security-frontier', prompt: AUTHORED + `
DOMAIN: AI/agent security — the frontier, where "best in the world" is won. We are an AI company; our workforce IS AI agents. Cover the OWASP LLM Top 10 (prompt injection direct + indirect, insecure output handling, training/knowledge poisoning, model DoS/cost-exhaustion, supply chain, sensitive info disclosure, insecure plugin/tool design, excessive agency, overreliance, model theft) mapped to our architecture: agents that read knowledge records (poisoned-knowledge risk), tool/action executors (excessive agency → why founder-reserved gates + authority tiers exist), the context-assembly path, an agent socially-engineered by adversarial inquiry/quote text. Include indirect prompt injection via marketplace-submitted content (inquiries, supplier profiles). Give detection + defense for each. This is the most important dimension. (12-18 records).` },
  { phase: 'Author the expertise', label: 'threat-modeling-mitre-detection', prompt: AUTHORED + `
DOMAIN: Threat modeling, MITRE ATT&CK & detection engineering, mapped to us. Build a threat model for a Postgres-centric AI marketplace: the adversaries (fraudulent supplier, scraping competitor, malicious buyer, credential-stuffer, insider-via-compromised-agent), their goals and kill-chains referencing relevant MITRE ATT&CK techniques (valid accounts, exploit public-facing app, data from cloud db, exfiltration, resource hijacking = our OpenRouter cost). For each, the detection signal in OUR telemetry (agent_runs, cron logs, auth events, unusual RLS-bypassing definer calls, cost spikes) and the response. Turn "know normal" into concrete detection rules. (10-16 records).` },
  { phase: 'Author the expertise', label: 'compliance-standards-mapped', prompt: AUTHORED + `
DOMAIN: Compliance & standards mapped to our controls. PCI-DSS (we take payments via Stripe — SAQ scope, why we must never store PAN, tokenization, the webhook/redirect model that keeps us out of scope), UAE PDPL (personal data of buyers/suppliers — lawful basis, data-subject rights, retention, cross-border), and a SOC 2 / ISO 27001 posture (the trust-services criteria and which of our existing controls — RLS, audit trails, change_reason, freeze digests, least privilege — already map to them, and the gaps). Give the security/IT agents a real "are we compliant, and where are the gaps" reference. (10-16 records).` },
  { phase: 'Author the expertise', label: 'stack-threat-snapshot-cves', prompt: AUTHORED + `
DOMAIN: Live threat intelligence snapshot for our EXACT stack + hardening. For Postgres/Supabase, the Deno edge runtime, Next.js/React, and typical npm dependencies: the classes of known vulnerabilities and notable CVE patterns (as of your knowledge, dated), the hardening checklist for each (Postgres: RLS default-deny, revoke PUBLIC, search_path safety, extension surface; Supabase: service_role key hygiene, exposed schemas; Deno: permission flags, import integrity; Next.js: SSRF/headers/middleware auth, dependency audit). Be explicit that this is a DATED snapshot and MUST be refreshed against live advisories — describe the refresh mechanism (npm audit, Supabase advisors get_advisors, CVE feeds). (10-16 records).` },
  { phase: 'Author the expertise', label: 'sre-reliability-operations', prompt: AUTHORED + `
DOMAIN: SRE / operational excellence mapped to us, so "the platform is healthy essentially all the time" is real. Cover: reliability (SLIs/SLOs for a marketplace — inquiry-to-reveal path availability, payment success rate, agent-run success), observability (what to log/monitor across edge functions, crons, agent_runs, Supabase logs, Vercel), backup & recovery (Supabase PITR, what our RPO/RTO should be, restore drills), safe deploys (the apply-read-back + CI-gate + frozen-phase discipline as an ops control), capacity/cost (OpenRouter spend as an operational + security signal), and on-call/runbook thinking for an autonomous company. (10-16 records).` },
]

const results = await parallel(DIMS.map(d => () =>
  agent(d.prompt, { label: d.label, phase: d.phase, schema: RECORDS_SCHEMA })
    .then(r => ({ ...r, label: d.label, phase: d.phase }))
))

const ok = results.filter(Boolean)
const flat = ok.flatMap(r => (r.records || []).map(rec => ({ ...rec, domain: r.domain || r.label, label: r.label, phase: r.phase })))
log(`built ${flat.length} knowledge records across ${ok.length}/${DIMS.length} domains`)
return { total: flat.length, byDomain: ok.map(r => ({ domain: r.label, n: (r.records || []).length })), records: flat }
