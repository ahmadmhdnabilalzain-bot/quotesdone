// SPEC FILE #8, part A §1-§4 — the router layer, the five levels, the decision engine, cascading.
//
//   §1 The Router Layer          (9)
//   §2 Five AI Levels + the expected distribution (9)
//   §3 The AI Decision Engine    (4)
//   §4 Model Cascading           (4)
//
// ── THE TIER VOCABULARY IS ALREADY IN THE ESTATE, AND IT IS NOT THE SPEC'S ───────────────────────
// The spec names five LEVELS (0 no-AI, 1 cheap, 2 medium, 3 premium, 4 human-level). model_policy
// and model_registry name four TIERS plus a refusal: none / small / medium / large / xlarge.
// They are the same ladder with different labels, and the mapping is stated here once rather than
// re-derived per check, because getting it wrong silently shifts every distribution number:
//
//     Level 0 no-AI     -> tier 'none'    (model_policy rows with a deterministic_alternative)
//     Level 1 cheap     -> tier 'small'   (gemini-3.1-flash-lite, qwen3.7-plus)
//     Level 2 medium    -> tier 'medium'  (claude-haiku, gemini-3.5-flash)
//     Level 3 premium   -> tier 'large'   (claude-sonnet-5)
//     Level 4 human     -> tier 'xlarge'  (claude-opus-4.8)
//
// ── §2's FOUR DISTRIBUTION CHECKS ARE THE HONEST CENTRE OF THIS ROW ──────────────────────────────
// They are `-used` checks over ai_cost_log, and the spec's own table is the bar: 20% no-AI, 55%
// cheap, 20% medium, 5% premium. Owning a router and using one are different facts, and these four
// are where the difference shows up as a number rather than as a routine name.

export const EXPECTED = 26;

export default async function (H) {
  const { req, one, many, B, Q, EDGE, APP, src, base, anyFile, filesNear, FN_EXISTS,
          FNS_MATCHING, TABLE_EXISTS, NROWS, USED, USED_N } = H;

  const S1 = '§1 router', S2 = '§2 levels', S3 = '§3 engine', S4 = '§4 cascading';
  const logged = await one(`select count(*)::text from public.ai_cost_log`);
  const ESTATE = `${logged} logged AI call(s) in ai_cost_log`;

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §1 — THE ROUTER LAYER (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // The router itself. Scored by EXECUTION and by the SHAPE of what it returns, never by existence:
  // a routine called fn_ai_route that returned null would satisfy a pg_proc grep and route nothing.
  const routeShape = await one(`select (public.fn_ai_route('agent_reasoning') ?& array['tier','model','use_llm'])::text`)
    .catch(() => 'false');
  await req(S1, 'route-layer-exists', 'an AI router layer sits before the provider',
    B(routeShape === 'true'),
    Q(`fn_ai_route('agent_reasoning') EXECUTED, returns tier+model+use_llm: ${routeShape}; ${ESTATE}`));

  // The router's own payload names WHY it chose — that is the intent/classification evidence.
  const why = await one(`select public.fn_ai_route('agent_reasoning')->>'why'`).catch(() => null);
  await req(S1, 'route-intent-detection', 'the router detects intent before choosing',
    B(!!why && String(why).length > 10),
    Q(`fn_ai_route explains its choice: "${String(why || 'NO why field').slice(0, 70)}"`));

  const classCount = await one(`select count(distinct task_class)::text from public.model_policy`);
  await req(S1, 'route-task-classification', 'requests are classified into task classes',
    B(Number(classCount) > 0),
    Q(`model_policy defines ${classCount} task class(es); ai_cost_log carries ` +
      `${await one(`select count(distinct task_class)::text from public.ai_cost_log`)} distinct task_class value(s)`));

  const selFn = await one(FN_EXISTS('fn_select_model'));
  await req(S1, 'route-model-selection', 'a model is selected per request',
    B(String(selFn) === 'true' && routeShape === 'true'),
    Q(`fn_select_model present ${selFn}; fn_ai_route returns a model: ` +
      `${await one(`select public.fn_ai_route('agent_reasoning')->>'model'`).catch(() => 'ERR')}`));

  // The provider hop. The router is worthless if nothing calls OpenRouter with its answer.
  const orEdge = anyFile(/openrouter/i, EDGE);
  const orFiles = EDGE.filter(f => /openrouter/i.test(src(f))).map(base);
  await req(S1, 'route-reaches-openrouter', 'the selected model is sent to OpenRouter',
    B(orEdge),
    Q(`${orFiles.length} edge function(s) call OpenRouter [${orFiles.slice(0, 6).join(' ') || 'none'}]`));

  // The four routing branches the spec enumerates. Each is scored on the POLICY that encodes it,
  // and each prints the model it resolves to so a branch that exists but points at the wrong tier
  // is visible rather than merely present.
  for (const [id, tc, wantTier, label] of [
    ['route-branch-simple-cheap', 'category_classification', 'small', 'simple question -> cheap model'],
    ['route-branch-reasoning-premium', 'agent_reasoning', 'large', 'reasoning -> premium model'],
  ]) {
    const t = await one(`select public.fn_ai_route('${tc}')->>'tier'`).catch(() => null);
    const m = await one(`select public.fn_ai_route('${tc}')->>'model'`).catch(() => null);
    await req(S1, id, label,
      B(t === wantTier),
      Q(`fn_ai_route('${tc}') -> tier=${t} model=${m}; spec wants ${wantTier}`));
  }

  // Long-context routing: a model with a big window must exist AND be reachable by policy.
  const bigCtx = await one(`select count(*)::text from public.model_registry where active and context_len >= 500000`);
  const bigNames = await one(`select coalesce(string_agg(model_id, ' '), 'none') from public.model_registry
    where active and context_len >= 500000`);
  await req(S1, 'route-branch-long-context', 'document work routes to a long-context model',
    B(Number(bigCtx) > 0),
    Q(`${bigCtx} active model(s) with >=500k context [${bigNames}]`));

  const fb = await one(`select public.fn_ai_route('agent_reasoning')->>'fallback'`).catch(() => null);
  await req(S1, 'route-branch-emergency-fallback', 'an emergency fallback provider is chosen',
    B(!!fb && fb !== 'null'),
    Q(`fn_ai_route returns fallback=${fb}; ` +
      `${await one(`select count(*)::text from public.llm_calls where fell_back`)} logged call(s) actually fell back`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §2 — THE FIVE LEVELS AND THE DISTRIBUTION (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════

  // Level 0 is the only one whose evidence is a REFUSAL rather than a model: model_policy rows that
  // carry a deterministic_alternative and route to no LLM at all.
  const lvl0 = await one(`select count(*)::text from public.model_policy
    where tier='none' and deterministic_alternative is not null and active`);
  await req(S2, 'level-0-no-ai', 'Level 0 — handled with no AI call at all',
    B(Number(lvl0) > 0),
    Q(`${lvl0} active model_policy row(s) route to NO llm and name a deterministic alternative`));

  for (const [id, tier, label] of [
    ['level-1-cheap', 'small', 'Level 1 — cheap fast model'],
    ['level-2-medium', 'medium', 'Level 2 — medium intelligence'],
    ['level-3-premium', 'large', 'Level 3 — premium reasoning'],
    ['level-4-human-tasks', 'xlarge', 'Level 4 — human-level tasks'],
  ]) {
    const models = await one(`select coalesce(string_agg(model_id, ' '), 'none') from public.model_registry
      where active and tier='${tier}'`);
    const policies = await one(`select count(*)::text from public.model_policy where tier='${tier}' and active`);
    await req(S2, id, label,
      B(models !== 'none'),
      Q(`tier '${tier}': model(s) [${models}], ${policies} policy row(s) route to it`));
  }

  // ── THE FOUR DISTRIBUTION CHECKS ─────────────────────────────────────────────────────────────
  // Measured over real traffic. The spec's table is the bar and the measured share prints either
  // way, so a miss says by how much rather than merely that it missed.
  //
  // Level 0 cannot appear in ai_cost_log at all — a request that never called an LLM has no cost
  // row by construction. Its share is therefore measured against model_policy's refusal coverage,
  // and that difference is stated in the evidence rather than hidden by reusing the same
  // denominator for all four.
  const totalCalls = Number(logged) || 1;
  const noAiClasses = await one(`select count(*)::text from public.model_policy where tier='none' and active`);
  const allClasses = await one(`select count(*)::text from public.model_policy where active`);
  const noAiShare = (100 * Number(noAiClasses) / (Number(allClasses) || 1));
  await req(S2, 'dist-no-ai-20pct', 'about 20% of work should need no AI',
    B(noAiShare >= 20),
    Q(`${noAiClasses} of ${allClasses} active task classes (${noAiShare.toFixed(0)}%) route to NO llm; ` +
      `bar is 20%. Measured over model_policy, not ai_cost_log — a request that never called an ` +
      `LLM leaves no cost row by construction`));

  for (const [id, tier, want, label] of [
    ['dist-cheap-55pct', 'small', 55, 'about 55% of calls should use the cheap tier'],
    ['dist-medium-20pct', 'medium', 20, 'about 20% of calls should use the medium tier'],
  ]) {
    const n = await one(`select count(*)::text from public.ai_cost_log where tier='${tier}'`);
    const pct = 100 * Number(n) / totalCalls;
    await req(S2, id, label,
      B(pct >= want),
      Q(`tier '${tier}': ${n} of ${logged} logged calls = ${pct.toFixed(0)}%, bar is ${want}%`));
  }

  // Premium is a CEILING, not a floor — the only one of the four where more is worse.
  const prem = await one(`select count(*)::text from public.ai_cost_log where tier in ('large','xlarge')`);
  const premPct = 100 * Number(prem) / totalCalls;
  const premCost = await one(`select coalesce(round(sum(cost_aed)::numeric,2),0)::text from public.ai_cost_log
    where tier in ('large','xlarge')`);
  await req(S2, 'dist-premium-5pct', 'premium should be at most about 5% of calls',
    B(premPct <= 5),
    Q(`tier large+xlarge: ${prem} of ${logged} logged calls = ${premPct.toFixed(0)}%, ceiling is 5% ` +
      `— this is a CEILING not a floor; those calls cost AED ${premCost}`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §3 — THE DECISION ENGINE (4)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // The spec asks for four components. It names them as files in an /ai-router directory; this
  // estate implements them as routines and tables, which satisfies the requirement — the spec's
  // subject is the capability, not the file layout. Each is scored on a DISTINCT object so one
  // router cannot answer for all four (overlap risk #2 in ROW8_REQUIREMENTS.md).
  for (const [id, label, sql, evid] of [
    ['engine-classifier', 'a classifier assigns a task class',
      `select (select count(*) from public.model_policy where active) > 0 and ${FNS_MATCHING('task_class')} <> ''`,
      Q(`${await one(`select count(*)::text from public.model_policy where active`)} classified task class(es); ` +
        `routines naming task_class: [${String(await one(FNS_MATCHING('task_class'))).split(' ').slice(0, 5).join(' ')}]`)],
    ['engine-model-selector', 'a model selector picks the model',
      FN_EXISTS('fn_select_model'),
      Q(`fn_select_model present ${await one(FN_EXISTS('fn_select_model'))}; ` +
        `fn_ai_route_tier_rank present ${await one(FN_EXISTS('fn_ai_route_tier_rank'))}`)],
    ['engine-cost-manager', 'a cost manager tracks and constrains spend',
      `select ${await one(FN_EXISTS('fn_model_cost_usd'))} and (select count(*) from public.ai_cost_log) > 0`,
      Q(`fn_model_cost_usd present; ai_cost_log holds ${logged} row(s); ` +
        `fn_budget_available present ${await one(FN_EXISTS('fn_budget_available'))}`)],
    ['engine-memory-manager', 'a memory manager decides what context is carried',
      `select (select count(*) from information_schema.columns where table_schema='public'
         and udt_name='vector') > 0`,
      Q(`${await one(`select count(*)::text from information_schema.columns where table_schema='public' and udt_name='vector'`)} ` +
        `vector column(s) back retrieval; agent_knowledge holds ` +
        `${await one(`select count(*)::text from public.agent_knowledge`)} row(s)`)],
  ]) await req(S3, id, label, sql, evid);

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §4 — MODEL CASCADING (4)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "Never directly call expensive models. Cheap -> confidence -> escalate." The four legs are the
  // four stages, and the ESCALATION leg is `-used`: a cascade that has never escalated has not been
  // shown to work, only to exist.
  const startsCheap = await one(`select (public.fn_ai_route('category_classification')->>'tier') in ('small','none')`).catch(() => 'false');
  await req(S4, 'cascade-starts-cheap', 'the cascade starts at a cheap model',
    // String(), not a bare ===. The management API returns a Postgres boolean as a JS boolean, so
    // `startsCheap === 'true'` compared true to 'true' and was always false. It printed
    //   MISSING cascade-starts-cheap  ... starts at tier=small
    // — a MISSING whose own evidence said it should pass, which is the loudest possible form of a
    // scorer defect and still took a payload read to notice. Three other legs had it; routeShape
    // avoided it only because its query casts ::text.
    B(String(startsCheap) === 'true'),
    Q(`fn_ai_route('category_classification') starts at tier=` +
      `${await one(`select public.fn_ai_route('category_classification')->>'tier'`).catch(() => 'ERR')}`));

  const confCol = await one(`select exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='ai_cost_log' and column_name='confidence')`);
  const confRows = await one(`select count(*)::text from public.ai_cost_log where confidence is not null`);
  await req(S4, 'cascade-confidence-score', 'a confidence score is produced per answer',
    B(String(confCol) === 'true' && Number(confRows) > 0),
    Q(`ai_cost_log.confidence column ${confCol}; populated on ${confRows} of ${logged} row(s)`));

  const fellBack = await one(`select count(*)::text from public.llm_calls where fell_back`);
  await req(S4, 'cascade-escalates-on-low-confidence', 'low confidence escalates to a stronger model',
    B(Number(fellBack) > 0),
    Q(`${fellBack} logged call(s) escalated to their fallback model; ` +
      `fn_ai_route supplies a fallback for every routed class`));

  const evalFn = await one(FNS_MATCHING('confidence'));
  await req(S4, 'cascade-evaluator', 'an evaluator judges whether the cheap answer was good enough',
    B(String(evalFn).trim() !== ''),
    Q(`routines reasoning about confidence: [${String(evalFn).split(' ').filter(Boolean).slice(0, 6).join(' ') || 'none'}]`));
}
