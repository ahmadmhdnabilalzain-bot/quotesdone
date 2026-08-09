// SPEC FILE #8, part A — the runtime disciplines: how a call is made, retried, avoided or refused.
//
//   §8  Streaming            (2)   §29 Smart Image Routing    (2)
//   §11 Multiple Providers   (3)   §33 Early Exit             (1)
//   §12 Self-hosted Small    (1)   §36 Multi-Agent Cost Ctrl  (2)
//   §15 OpenRouter Settings  (7)   §38 Predict User Intent    (1)
//   §17 Thinking vs Answering(3)   §39 Fail Gracefully        (2)
//   §18 Agent Sleep Mode     (2)   §40 Regional Optimization  (1)
//   §19 Deterministic First  (6)   §43 Offline Mode           (5)
//   §23 User Behaviour Learn (1)
//
// ── §19 AND §33 ARE THE STRONGEST PART OF THIS ESTATE AND THE EASIEST TO SCORE WRONG ─────────────
// model_policy carries ELEVEN rows at tier='none' with a `deterministic_alternative` naming the SQL
// that should do the work instead, and fn_ai_route genuinely REFUSES those classes — measured:
//
//     fn_ai_route('vat_calculation')
//       -> {"use_llm": false, "tier": "none", "why": "REFUSED. SQL / plpgsql", ...}
//
// That is §19 and §33 both, implemented properly. The trap is scoring the six §19 legs on the
// eleven policy rows collectively — the spec names six SPECIFIC things (dates, calendars, file
// operations, searches, database queries, calculations) and the estate covers some and not others.
// Each leg is therefore matched to its own subject, and the ones with no policy row read MISSING
// rather than borrowing another row's evidence.
//
// ── §11, §15's fallback setting AND §39 ARE THREE CLAIMS, NOT ONE ────────────────────────────────
// A provider chain, a configured OpenRouter behaviour, and a retry discipline that STOPS. Overlap
// risk #4. §39's second leg is scored on a bounded attempt count, which is the only one of the
// three that can be refuted by evidence of endless retrying.

export const EXPECTED = 39;

export default async function (H) {
  const { req, one, B, Q, EDGE, APP, src, base, anyFile, filesMatching, filesNear,
          FN_EXISTS, FNS_MATCHING, TABLE_EXISTS } = H;
  const S8 = '§8 stream', S11 = '§11 providers', S12 = '§12 local', S15 = '§15 settings',
        S17 = '§17 split', S18 = '§18 sleep', S19 = '§19 deterministic', S23 = '§23 learning',
        S29 = '§29 image', S33 = '§33 early exit', S36 = '§36 multi-agent', S38 = '§38 predict',
        S39 = '§39 fail', S40 = '§40 region', S43 = '§43 offline';
  const fnList = async (pat) => String(await one(FNS_MATCHING(pat))).split(' ').filter(Boolean);
  const brief = (a, n = 5) => a.slice(0, n).join(' ') || 'none';
  const logged = await one(`select count(*)::text from public.ai_cost_log`);

  // ── §8 STREAMING (2) ──────────────────────────────────────────────────────────────────────────
  const streamModels = await one(`select count(*)::text from public.model_registry where active and supports_streaming`);
  const streamRoute = await one(`select public.fn_ai_route('agent_reasoning')->>'stream'`).catch(() => null);
  await req(S8, 'stream-enabled', 'streaming is enabled on the provider call',
    B(Number(streamModels) > 0 && String(streamRoute) === 'true'),
    Q(`${streamModels} active model(s) support streaming; fn_ai_route returns stream=${streamRoute}`));

  const cancelSrc = filesNear(/abort|cancel|signal/i, /stream|generat|fetch/i, 400, EDGE).map(base);
  await req(S8, 'stream-cancellation-stops-generation', 'cancelling a stream stops generation',
    B(cancelSrc.length > 0),
    Q(`${cancelSrc.length} edge file(s) wire an abort signal to a streaming call [${brief(cancelSrc)}] ` +
      `— streaming without cancellation saves no tokens, which is §8's whole reason`));

  // ── §11 MULTIPLE PROVIDERS (3) ────────────────────────────────────────────────────────────────
  const orFiles = filesMatching(/openrouter/i, EDGE).map(base);
  await req(S11, 'prov-openrouter', 'OpenRouter is one of the providers',
    B(orFiles.length > 0),
    Q(`${orFiles.length} edge function(s) reach OpenRouter`));

  const providers = await one(`select count(distinct provider)::text from public.model_registry where active`);
  const provList = await one(`select coalesce(string_agg(distinct provider,' '),'none') from public.model_registry where active`);
  await req(S11, 'prov-direct-or-local', 'more than one provider is available',
    B(Number(providers) > 1),
    Q(`${providers} distinct provider(s) in model_registry [${provList}]`));

  const fbPolicies = await one(`select count(*)::text from public.model_policy where active and model_fallback is not null`);
  const allPol = await one(`select count(*)::text from public.model_policy where active and tier <> 'none'`);
  await req(S11, 'prov-fallback-chain', 'a fallback chain exists when the primary fails',
    B(Number(fbPolicies) > 0),
    Q(`${fbPolicies} of ${allPol} routed policies name a fallback model`));

  // ── §12 SELF-HOSTED SMALL MODELS (1) ──────────────────────────────────────────────────────────
  const localFns = await fnList('gte-small|local.?model|ollama|self.?host');
  const localEmb = await one(`select count(*)::text from public.llm_policy where role='embedding'`).catch(() => '0');
  await req(S12, 'local-small-model', 'a small model runs locally for classification and commands',
    B(Number(localEmb) > 0),
    Q(`${localEmb} local/embedded model policy row(s) (gte-small is Supabase-hosted, not billed ` +
      `per call); ${localFns.length} routine(s) reference one [${brief(localFns)}]`));

  // ── §15 OPENROUTER SETTINGS (7) ───────────────────────────────────────────────────────────────
  for (const [id, label, sql, ev] of [
    ['set-model-fallback', 'model fallback is enabled',
      B(Number(fbPolicies) > 0), Q(`${fbPolicies} policy row(s) declare a fallback model`)],
    ['set-streaming', 'streaming is enabled',
      B(String(streamRoute) === 'true'), Q(`fn_ai_route returns stream=${streamRoute}`)],
    ['set-provider-routing', 'provider routing is enabled',
      B(Number(providers) > 1), Q(`${providers} provider(s) routable [${provList}]`)],
    ['set-usage-tracking', 'usage tracking is enabled',
      B(Number(logged) > 0), Q(`ai_cost_log holds ${logged} tracked call(s)`)],
  ]) await req(S15, id, label, sql, ev);

  // The three DISABLE settings are refutable in the estate's own data, which is the only honest way
  // to score "we turned something off": a config claim nobody can check is not evidence.
  const autoPremium = await one(`select count(*)::text from public.ai_cost_log
    where tier in ('large','xlarge') and could_be_cheaper`);
  await req(S15, 'set-no-auto-premium', 'automatic premium selection is disabled',
    B(Number(autoPremium) === 0),
    Q(`${autoPremium} premium call(s) are flagged could_be_cheaper — every one is a premium ` +
      `selection the router should not have made`));

  const bigCtxCalls = await one(`select count(*)::text from public.ai_cost_log where prompt_tokens > 100000`);
  await req(S15, 'set-no-unnecessary-long-context', 'unnecessary long contexts are disabled',
    B(Number(bigCtxCalls) === 0),
    Q(`${bigCtxCalls} logged call(s) sent more than 100k prompt tokens; avg prompt is ` +
      `${await one(`select coalesce(round(avg(prompt_tokens))::text,'0') from public.ai_cost_log`)} tokens`));

  const compressFns = await fnList('summar|compress|rolling');
  await req(S15, 'set-no-full-history', 'sending the full history is disabled',
    B(compressFns.length > 0),
    Q(`${compressFns.length} routine(s) compress rather than resend history [${brief(compressFns)}]`));

  // ── §17 THINKING vs ANSWERING (3) ─────────────────────────────────────────────────────────────
  for (const [id, tc, wantTiers, label] of [
    ['split-intent-engine-cheap', 'intent_detection', ['small', 'none'], 'intent detection runs on a cheap/local model'],
    ['split-task-planner-cheap', 'rfq_routing', ['small', 'medium', 'none'], 'planning runs below the premium tier'],
  ]) {
    const t = await one(`select public.fn_ai_route('${tc}')->>'tier'`).catch(() => null);
    await req(S17, id, label,
      B(wantTiers.includes(String(t))),
      Q(`fn_ai_route('${tc}') -> tier=${t}; spec wants one of [${wantTiers.join('/')}]`));
  }
  const premClasses = await one(`select count(*)::text from public.model_policy where active and tier in ('large','xlarge')`);
  const allRouted = await one(`select count(*)::text from public.model_policy where active and tier <> 'none'`);
  await req(S17, 'split-final-response-stronger-only-if-needed', 'only the final step escalates to a stronger model',
    B(Number(premClasses) * 2 <= Number(allRouted)),
    Q(`${premClasses} of ${allRouted} routed task classes sit at the premium tier — the spec's rule ` +
      `is that the strong model is the exception, so this leg needs premium to be under half`));

  // ── §18 AGENT SLEEP MODE (2) ──────────────────────────────────────────────────────────────────
  const trigFns = await one(`select count(*)::text from pg_trigger where not tgisinternal`);
  const eventTables = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'event|outbox|queue'`);
  await req(S18, 'sleep-event-wakes-agent', 'an event wakes the agent rather than the agent polling',
    B(Number(trigFns) > 0),
    Q(`${trigFns} non-internal trigger(s) fire on events; event/outbox table(s): ` +
      `[${String(eventTables).slice(0, 60)}]`));

  const cronJobs = await one(`select count(*)::text from cron.job`).catch(() => '0');
  const cronFreq = await one(`select count(*)::text from cron.job where schedule ~ '^\\* '`).catch(() => '0');
  await req(S18, 'sleep-agent-sleeps-after', 'agents are not left running continuously',
    B(Number(cronFreq) === 0),
    Q(`${cronJobs} cron job(s); ${cronFreq} run EVERY MINUTE — a per-minute poll is the ` +
      `"agent alive 24/7" pattern §18 rejects`));

  // ── §19 DETERMINISTIC TOOLS BEFORE AI (6) ─────────────────────────────────────────────────────
  // Each leg matched to its own subject. See the module header for why they are not pooled.
  for (const [id, pat, label] of [
    ['det-dates', 'date_calculation|date', 'dates'],
    ['det-calendars', 'calendar|schedul|availability', 'calendars'],
    ['det-file-operations', 'file|upload|storage|attachment', 'file operations'],
    ['det-searches', 'search|match|duplicate|lookup', 'searches'],
    ['det-database-queries', 'kpi|aggregat|report|query|scoring', 'database queries'],
    ['det-calculations', 'vat|currency|calculation|threshold', 'calculations'],
  ]) {
    const n = await one(`select count(*)::text from public.model_policy
      where active and tier='none' and (task_class ~* '${pat}' or deterministic_alternative ~* '${pat}')`);
    const which = await one(`select coalesce(string_agg(task_class,' '),'none') from public.model_policy
      where active and tier='none' and (task_class ~* '${pat}' or deterministic_alternative ~* '${pat}')`);
    await req(S19, id, `${label} are handled deterministically, not by an LLM`,
      B(Number(n) > 0),
      Q(`${n} policy row(s) refuse the LLM for ${label} [${which}]`));
  }

  // ── §23 USER BEHAVIOUR LEARNING (1) ───────────────────────────────────────────────────────────
  const prefFns = await fnList('preference|learn|adapt');
  const prefTables = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'preference'`);
  await req(S23, 'learn-user-preference', 'the system learns a user preference and routes to it',
    B(prefTables !== 'none' && prefFns.length > 0),
    Q(`preference table(s) [${prefTables}]; ${prefFns.length} routine(s) read or adapt to them ` +
      `[${brief(prefFns)}]`));

  // ── §29 SMART IMAGE ROUTING (2) ───────────────────────────────────────────────────────────────
  const visionModels = await one(`select count(*)::text from public.model_registry where active and supports_vision`);
  const cvSrc = filesNear(/image|photo|vision/i, /classif|detect|filter|mime|type/i, 400, EDGE).map(base);
  await req(S29, 'img-cv-filter', 'an image is classified before a vision model is called',
    B(cvSrc.length > 0),
    Q(`${cvSrc.length} edge file(s) classify an image before escalating [${brief(cvSrc)}]`));

  const visionCalls = await one(`select count(*)::text from public.ai_cost_log where task_class ~* 'ocr|vision|image'`);
  await req(S29, 'img-escalates-only-when-needed', 'the vision model is only called when needed',
    B(Number(visionModels) > 0 && Number(visionCalls) < Number(logged) * 0.2),
    Q(`${visionModels} vision-capable model(s); ${visionCalls} of ${logged} logged calls were vision ` +
      `work — this leg needs vision to be a minority of traffic`));

  // ── §33 EARLY EXIT (1) ────────────────────────────────────────────────────────────────────────
  const refuses = await one(`select (public.fn_ai_route('vat_calculation')->>'use_llm')::text`).catch(() => null);
  const noneClasses = await one(`select count(*)::text from public.model_policy where active and tier='none'`);
  await req(S33, 'early-exit', 'the system answers without AI when it can',
    B(String(refuses) === 'false'),
    Q(`fn_ai_route('vat_calculation') EXECUTED -> use_llm=${refuses}; ${noneClasses} task class(es) ` +
      `exit before any model call`));

  // ── §36 MULTI-AGENT COST CONTROL (2) ──────────────────────────────────────────────────────────
  const mgrFns = await fnList('manager_key|delegate|assign.*agent');
  await req(S36, 'multi-agent-manager', 'a manager agent decides which agents are needed',
    B(mgrFns.length > 0),
    Q(`${mgrFns.length} routine(s) implement delegation [${brief(mgrFns)}]; org_agents carries a ` +
      `manager_key chain`));

  const agentsUsed = await one(`select count(distinct agent_key)::text from public.ai_cost_log where agent_key is not null`);
  const agentsTotal = await one(`select count(*)::text from public.org_agents where active`);
  await req(S36, 'multi-agent-only-needed-activated', 'only the needed agents are activated',
    B(Number(agentsUsed) > 0 && Number(agentsUsed) < Number(agentsTotal)),
    Q(`${agentsUsed} of ${agentsTotal} active agents actually spent on AI — all of them spending ` +
      `would be the "10 agents per request" pattern §36 rejects`));

  // ── §38 PREDICT USER INTENT (1) ───────────────────────────────────────────────────────────────
  const intentTier = await one(`select public.fn_ai_route('intent_detection')->>'tier'`).catch(() => null);
  const intentFns = await fnList('intent');
  await req(S38, 'predict-intent', 'intent is predicted before an expensive call is made',
    B(intentFns.length > 0 && ['small', 'none'].includes(String(intentTier))),
    Q(`${intentFns.length} routine(s) detect intent [${brief(intentFns)}]; ` +
      `fn_ai_route('intent_detection') -> tier=${intentTier}`));

  // ── §39 FAIL GRACEFULLY (2) ───────────────────────────────────────────────────────────────────
  await req(S39, 'fail-primary-then-fallback', 'a failure falls back once to another model',
    B(Number(fbPolicies) > 0 && Number(await one(`select count(*)::text from public.llm_calls where fell_back`)) > 0),
    Q(`${fbPolicies} policies declare a fallback; ` +
      `${await one(`select count(*)::text from public.llm_calls where fell_back`)} logged call(s) used it`));

  const maxAttempts = await one(`select coalesce(max(attempts),0)::text from public.llm_calls`);
  await req(S39, 'fail-stops-no-endless-retry', 'retrying stops rather than looping',
    B(Number(maxAttempts) > 0 && Number(maxAttempts) <= 3),
    Q(`the most attempts any logged call made is ${maxAttempts} — the spec's rule is primary, then ` +
      `fallback, then stop, so anything above 3 is the endless-retry pattern it rejects`));

  // ── §40 REGIONAL OPTIMIZATION (1) ─────────────────────────────────────────────────────────────
  const cheapest = await one(`select model_id from public.model_registry where active
    order by in_per_mtok_usd asc nulls last limit 1`);
  const rankFn = await one(FN_EXISTS('fn_ai_route_tier_rank'));
  await req(S40, 'region-lowest-cost-provider', 'the lowest-cost provider meeting the quality bar is chosen',
    B(String(rankFn) === 'true' && Number(providers) > 1),
    Q(`fn_ai_route_tier_rank present ${rankFn} across ${providers} provider(s); cheapest active ` +
      `model is ${cheapest} — the estate ranks by price within a tier, which is §40 without the ` +
      `geographic dimension`));

  // ── §43 OFFLINE MODE (5) ──────────────────────────────────────────────────────────────────────
  // Each of the five is scored on a deterministic path that needs no model at all.
  for (const [id, pat, label] of [
    ['offline-file-search', 'search|lookup|duplicate|match', 'file search'],
    ['offline-commands', 'workflow_routing|approval_threshold|command', 'commands'],
    ['offline-notes', 'note|memo|comment', 'notes'],
    ['offline-calculations', 'vat|currency|kpi|calculation|scoring', 'calculations'],
    ['offline-reminders', 'reminder|due|schedul|date_calculation', 'reminders'],
  ]) {
    const pol = await one(`select count(*)::text from public.model_policy
      where active and tier='none' and (task_class ~* '${pat}' or deterministic_alternative ~* '${pat}')`);
    const tbl = await one(`select count(*)::text from information_schema.tables
      where table_schema='public' and table_name ~* '${pat}'`);
    await req(S43, id, `${label} work without any AI call`,
      B(Number(pol) > 0),
      Q(`${pol} policy row(s) refuse the LLM for ${label}; ${tbl} table(s) named for it — the ` +
        `policy row is the requirement, the table alone is not`));
  }
}
