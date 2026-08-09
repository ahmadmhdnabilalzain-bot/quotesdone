// SPEC FILE #8, part A — paying once for the same answer, and knowing which model earned it.
//
//   §7  Cache Everything          (2)   §32 Semantic Cache            (1)
//   §24 AI Quality Scoring        (3)   §35 Fine-Tuning / Distillation(1)
//   §25 Automatic Benchmarking    (6)   §44 Background Model Switching(2)
//   §26 Batch Processing          (1)
//
// ── THIS MODULE HOLDS THE PAIR THAT THE WHOLE ROW IS SCORED THE WAY IT IS BECAUSE OF ─────────────
// `cache-store-exists` and `cache-actually-hit` are one sentence in the spec ("Cache Everything")
// and two completely different facts on production. Measured 2026-08-09:
//
//     llm_cache table                                     exists, 12 columns
//     fn_llm_cache_get / _lookup / _put / _store          all four exist
//     llm_cache rows                                      0
//     ai_cost_log rows served from cache                  2 of 1,021
//
// The mechanism is complete and has essentially never run. A scorer that asked only the first
// question would print MET and hide the largest unrealised saving in the estate; one that asked
// only the second would print MISSING and imply there is something to build when the building is
// done. Both are asked, neither is averaged, and the runner prints a BUILT-BUT-UNUSED line.
//
// §32 is NOT a second helping of §7. A keyed cache and a MEANING-keyed cache are different claims,
// and §32 is scored on the embedding column being POPULATED and matched on — not on its existence.
// Overlap risk #1 in ROW8_REQUIREMENTS.md.

export const EXPECTED = 16;

export default async function (H) {
  const { req, one, B, Q, EDGE, base, filesMatching, filesNear, FN_EXISTS, FNS_MATCHING, TABLE_EXISTS } = H;
  const S7 = '§7 cache', S24 = '§24 quality', S25 = '§25 benchmark', S26 = '§26 batch',
        S32 = '§32 semantic', S35 = '§35 distill', S44 = '§44 switching';
  const fnList = async (pat) => String(await one(FNS_MATCHING(pat))).split(' ').filter(Boolean);
  const brief = (a, n = 5) => a.slice(0, n).join(' ') || 'none';
  const logged = await one(`select count(*)::text from public.ai_cost_log`);

  // ── §7 CACHE (2) — THE PAIR ───────────────────────────────────────────────────────────────────
  const cacheTable = await one(TABLE_EXISTS('llm_cache'));
  const cacheFns = await fnList('llm_cache');
  await req(S7, 'cache-store-exists', 'an answer cache exists, keyed by question fingerprint',
    B(String(cacheTable) === 'true' && cacheFns.length > 0),
    Q(`llm_cache table ${cacheTable}; ${cacheFns.length} routine(s) read/write it [${brief(cacheFns, 6)}]`));

  const cacheRows = await one(`select count(*)::text from public.llm_cache`);
  const cacheHits = await one(`select count(*)::text from public.ai_cost_log where coalesce(cached,false)`);
  const savedUsd = await one(`select coalesce(round(sum(saved_usd)::numeric,2),0)::text from public.llm_cache`);
  await req(S7, 'cache-actually-hit', 'the cache is actually serving answers in production',
    B(Number(cacheRows) > 0 && Number(cacheHits) > 0),
    Q(`llm_cache holds ${cacheRows} row(s); ${cacheHits} of ${logged} logged call(s) were served from ` +
      `cache; USD ${savedUsd} recorded as saved — the mechanism exists (see cache-store-exists), ` +
      `this leg asks whether it RUNS`));

  // ── §32 SEMANTIC CACHE (1) ────────────────────────────────────────────────────────────────────
  // Populated and matched on, not merely declared. A NULL embedding column is an exact-match cache
  // wearing a semantic cache's schema.
  const embCol = await one(`select exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='llm_cache' and column_name='embedding_gte')`);
  const embPop = Number(cacheRows) > 0
    ? await one(`select count(*)::text from public.llm_cache where embedding_gte is not null`) : '0';
  const semFns = await fnList('embedding_gte|<=>');
  await req(S32, 'cache-semantic', 'the cache matches on MEANING, not only on an exact hash',
    B(Number(embPop) > 0),
    Q(`llm_cache.embedding_gte column ${embCol}, populated on ${embPop} of ${cacheRows} row(s); ` +
      `${semFns.length} routine(s) do vector matching [${brief(semFns)}] — a NULL embedding column ` +
      `is an exact-match cache wearing a semantic cache's schema`));

  // ── §24 QUALITY SCORING (3) ───────────────────────────────────────────────────────────────────
  const outcomeTable = await one(TABLE_EXISTS('model_outcome'));
  const outcomeRows = outcomeTable ? await one(`select count(*)::text from public.model_outcome`) : '0';
  await req(S24, 'qual-score-recorded', 'a quality score is recorded per answer',
    B(Number(outcomeRows) > 0),
    Q(`model_outcome table ${outcomeTable}, ${outcomeRows} row(s); ` +
      `v_ai_quality_proxy present ${await one(TABLE_EXISTS('v_ai_quality_proxy'))}`));

  const qualPerModel = await one(`select count(*)::text from public.model_registry where quality_score is not null`);
  const regModels = await one(`select count(*)::text from public.model_registry`);
  await req(S24, 'qual-score-per-model', 'the score is held per model',
    B(Number(qualPerModel) > 0),
    Q(`model_registry.quality_score populated on ${qualPerModel} of ${regModels} model(s)`));

  const qualPerTask = outcomeTable
    ? await one(`select (select count(*) from information_schema.columns where table_schema='public'
        and table_name='model_outcome' and column_name ~* 'task')::text` ) : '0';
  await req(S24, 'qual-score-per-task', 'the score is held per task class',
    B(Number(qualPerTask) > 0 && Number(outcomeRows) > 0),
    Q(`model_outcome has ${qualPerTask} task-class column(s) and ${outcomeRows} row(s) — both are ` +
      `needed: a task column with no rows scores nothing`));

  // ── §25 BENCHMARKING (6) ──────────────────────────────────────────────────────────────────────
  // "Do not choose models based on reputation. Run your own tests." The spec names six categories.
  // Each is scored on whether the benchmark estate holds a RESULT for it, not on fn_model_benchmark
  // existing — a benchmark routine that has never been run has benchmarked nothing.
  const benchFn = await one(FN_EXISTS('fn_model_benchmark'));
  for (const [id, pat, label] of [
    ['bench-coding', 'cod(e|ing)|program|sql', 'coding'],
    ['bench-reasoning', 'reason|decision|analys', 'reasoning'],
    ['bench-writing', 'writ|draft|content|communication', 'writing'],
    ['bench-vision', 'vision|image|ocr|visual', 'vision'],
    ['bench-documents', 'document|extract|pdf', 'documents'],
    ['bench-math', 'math|calculat|arithmetic|vat|currency', 'math'],
  ]) {
    const n = Number(outcomeRows) > 0
      ? await one(`select count(*)::text from public.model_outcome where task_class ~* '${pat}'`).catch(() => '0')
      : '0';
    await req(S25, id, `models are benchmarked on ${label}`,
      B(Number(n) > 0),
      Q(`${n} benchmark result(s) for ${label} in model_outcome (${outcomeRows} row(s) total); ` +
        `fn_model_benchmark present ${benchFn} — a routine that has never run has benchmarked nothing`));
  }

  // ── §26 BATCH PROCESSING (1) ──────────────────────────────────────────────────────────────────
  const batchFns = await fnList('batch');
  const batchSrc = filesMatching(/batch/i, EDGE).map(base);
  await req(S26, 'batch-processing', 'non-urgent work is batched rather than sent one call at a time',
    B(batchFns.length > 0 || batchSrc.length > 0),
    Q(`${batchFns.length} routine(s) [${brief(batchFns)}] and ${batchSrc.length} edge file(s) ` +
      `[${brief(batchSrc)}] batch work`));

  // ── §35 DISTILLATION (1) ──────────────────────────────────────────────────────────────────────
  const distillFns = await fnList('distil|fine.?tun|training.?set');
  await req(S35, 'distill-from-successful-responses', 'successful answers are collected to train smaller models',
    B(distillFns.length > 0),
    Q(`${distillFns.length} routine(s) collect answers for distillation [${brief(distillFns)}]; ` +
      `model_outcome holds ${outcomeRows} scored answer(s), which is the corpus this would need`));

  // ── §44 BACKGROUND MODEL SWITCHING (2) ────────────────────────────────────────────────────────
  const priceCols = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and table_name='model_registry'
    and column_name in ('in_per_mtok_usd','out_per_mtok_usd','quality_score')`);
  await req(S44, 'switch-registry-tracks-price-quality', 'a registry tracks each model price and quality',
    B(Number(priceCols) >= 3),
    Q(`model_registry carries ${priceCols} of 3 price/quality column(s) over ${regModels} model(s); ` +
      `quality_score populated on ${qualPerModel}`));

  const autoFn = await one(FN_EXISTS('fn_model_autoswitch'));
  const offCat = await one(`select count(*)::text from public.v_model_policy_offcatalog`).catch(() => 'n/a');
  await req(S44, 'switch-automatic', 'a cheaper-and-better model is switched to automatically',
    B(String(autoFn) === 'true' && Number(qualPerModel) > 0),
    Q(`fn_model_autoswitch present ${autoFn}; but it needs quality_score, populated on ` +
      `${qualPerModel} of ${regModels} model(s); v_model_policy_offcatalog rows: ${offCat}`));
}
