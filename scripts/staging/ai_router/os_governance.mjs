// SPEC FILE #8, part A — who is allowed to spend what, and who notices when it goes wrong.
//
//   §13 AI Profiles          (3)   §37 Internal AI Credits    (4)
//   §14 Monitoring Dashboard (6)   §41 The AI Accountant      (5)
//   §27 Queue System         (3)   §42 Human Feedback Loop    (3)
//   §28 AI Spending Limits   (3)
//
// ── §14 AND §41 ARE NOT THE SAME REQUIREMENT ─────────────────────────────────────────────────────
// A dashboard REPORTS a number; an accountant RAISES AN ALARM about it. The spec is explicit —
// §41's example output is "Document summarization costs increased 42%. Switch to Model X." — so
// §41's legs are scored on something that fires, not on a view that could be read. This estate has
// eight observability views, which is a strong §14 and says nothing about §41. Overlap risk #6.
//
// ── §28 IS PER-USER, §9 IS PER-REQUEST, §B14 IS PER-CUSTOMER ─────────────────────────────────────
// Three different objects, and the spec names all three. This module owns only the per-user monthly
// cap. Overlap risk #3.

export const EXPECTED = 27;

export default async function (H) {
  const { req, one, B, Q, EDGE, APP, base, filesMatching, filesNear, FN_EXISTS, FNS_MATCHING, TABLE_EXISTS } = H;
  const S13 = '§13 profiles', S14 = '§14 dashboard', S27 = '§27 queue', S28 = '§28 spend',
        S37 = '§37 credits', S41 = '§41 accountant', S42 = '§42 feedback';
  const fnList = async (pat) => String(await one(FNS_MATCHING(pat))).split(' ').filter(Boolean);
  const brief = (a, n = 5) => a.slice(0, n).join(' ') || 'none';
  const logged = await one(`select count(*)::text from public.ai_cost_log`);
  const viewList = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.views
    where table_schema='public' and table_name ~* 'ai_|llm|cost|spend'`);

  // ── §13 AI PROFILES (3) ───────────────────────────────────────────────────────────────────────
  // "Instead of every user getting maximum AI." The estate's analogue of a profile is a TIER
  // ceiling that a caller is held to. Each of the three named profiles needs a distinct band.
  const tiers = await one(`select count(distinct tier)::text from public.model_policy where active and tier <> 'none'`);
  const tierList = await one(`select coalesce(string_agg(distinct tier,' '),'none') from public.model_policy
    where active and tier <> 'none'`);
  const profileTable = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'ai_profile|service_tier|plan'`);
  for (const [id, need, label] of [
    ['profile-economy', 1, 'Economy — cheap models, low cost'],
    ['profile-balanced', 2, 'Balanced — normal models'],
    ['profile-professional', 3, 'Professional — premium models, maximum quality'],
  ]) {
    await req(S13, id, label,
      B(profileTable !== 'none' && Number(tiers) >= need),
      Q(`profile/plan table(s): [${profileTable}]; ${tiers} routed tier band(s) [${tierList}] — a ` +
        `profile needs a table that BINDS a user to a band, not only the bands`));
  }

  // ── §14 MONITORING DASHBOARD (6) ──────────────────────────────────────────────────────────────
  // Each of the spec's six fields is scored on the column that carries it AND on that column being
  // populated, because a dashboard field that is always null reports nothing.
  for (const [id, col, label, tbl] of [
    ['dash-request-count', null, 'request count', 'ai_cost_log'],
    ['dash-tokens', 'prompt_tokens', 'tokens', 'ai_cost_log'],
    ['dash-model-used', 'model_used', 'model used', 'ai_cost_log'],
    ['dash-cost', 'cost_aed', 'cost', 'ai_cost_log'],
    ['dash-failures', 'ok', 'failures', 'ai_cost_log'],
    ['dash-avg-quality', 'confidence', 'average response quality', 'ai_cost_log'],
  ]) {
    if (col === null) {
      await req(S14, id, `the dashboard reports ${label}`,
        B(Number(logged) > 0),
        Q(`ai_cost_log holds ${logged} row(s); observability views: [${viewList}]`));
      continue;
    }
    const pop = await one(`select count(*)::text from public.ai_cost_log where ${col} is not null`);
    await req(S14, id, `the dashboard reports ${label}`,
      B(Number(pop) > 0),
      Q(`ai_cost_log.${col} populated on ${pop} of ${logged} row(s) — a dashboard field that is ` +
        `always null reports nothing`));
  }

  // ── §27 QUEUE SYSTEM (3) ──────────────────────────────────────────────────────────────────────
  const qTable = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'queue|job|task'`);
  const prioCol = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and column_name ~* 'priority|urgency' and table_name ~* 'queue|job|task'`);
  for (const [id, label] of [
    ['queue-urgent', 'URGENT priority'],
    ['queue-normal', 'NORMAL priority'],
    ['queue-background', 'BACKGROUND priority'],
  ]) {
    await req(S27, id, `the AI task queue supports ${label}`,
      B(Number(prioCol) > 0),
      Q(`${prioCol} priority column(s) on queue/job/task table(s) [${String(qTable).slice(0, 70)}] — ` +
        `the three bands are values of one column, so all three legs share this evidence and ` +
        `stand or fall together`));
  }

  // ── §28 AI SPENDING LIMITS (3) ────────────────────────────────────────────────────────────────
  // Per-USER monthly caps. The estate has DEPARTMENT budgets, which is the same mechanism aimed at
  // a different principal — that difference is printed rather than glossed.
  const budgets = await one(`select count(*)::text from public.v_ai_spend where monthly_aed::numeric > 0`).catch(() => '0');
  const userCap = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and column_name ~* 'monthly_aed|spend_cap|ai_budget'
    and table_name ~* 'user|customer|account|plan'`);
  const guardFn = await one(FN_EXISTS('fn_ai_spend_guard'));
  for (const [id, label] of [
    ['spend-limit-free', 'a free tier cap'],
    ['spend-limit-premium', 'a premium tier cap'],
    ['spend-limit-enterprise', 'an enterprise / custom cap'],
  ]) {
    await req(S28, id, `spending limits define ${label}`,
      B(Number(userCap) > 0),
      Q(`${userCap} per-USER spend-cap column(s); ${budgets} DEPARTMENT budget(s) are set and ` +
        `fn_ai_spend_guard present ${guardFn} — the mechanism exists but its principal is a ` +
        `department, not a user, which is what §28 asks for`));
  }

  // ── §37 INTERNAL AI CREDITS (4) ───────────────────────────────────────────────────────────────
  // The spec's ladder is 0 / 1 / 5 / 20 credits by tier. The estate prices in AED per token rather
  // than in credits; that is the same idea with a different unit, so each leg is scored on whether
  // the corresponding BAND is separately priced.
  for (const [id, tier, label] of [
    ['credit-0-simple', 'none', 'a zero-cost band for work that needs no AI'],
    ['credit-1-small', 'small', 'a cheapest band'],
    ['credit-5-medium', 'medium', 'a mid band'],
    ['credit-20-premium', 'large', 'a premium band'],
  ]) {
    const priced = tier === 'none'
      ? await one(`select count(*)::text from public.model_policy where active and tier='none'`)
      : await one(`select count(*)::text from public.model_registry where active and tier='${tier}'
          and in_per_mtok_usd is not null`);
    await req(S37, id, `the cost ladder has ${label}`,
      B(Number(priced) > 0),
      Q(`tier '${tier}': ${priced} priced entr(y/ies) — the estate prices in AED per million ` +
        `tokens rather than in credits, which is the same ladder in a different unit`));
  }

  // ── §41 THE AI ACCOUNTANT (5) ─────────────────────────────────────────────────────────────────
  // Scored on something that FIRES. See the module header.
  const alertFns = await fnList('emit_.*budget|budget_exceeded|alert');
  for (const [id, label, sql, ev] of [
    ['acct-spending', 'tracks spending',
      `select (select count(*) from public.ai_cost_log where cost_aed is not null) > 0`,
      Q(`${await one(`select count(*)::text from public.ai_cost_log where cost_aed is not null`)} of ${logged} calls carry a cost`)],
    ['acct-token-waste', 'identifies token waste',
      `select (select count(*) from public.v_cost_optimisation where could_downgrade > 0) > 0`,
      Q(`v_cost_optimisation flags ` +
        `${await one(`select coalesce(sum(could_downgrade),0)::text from public.v_cost_optimisation`).catch(() => 'n/a')} ` +
        `downgradable call(s)`)],
    ['acct-expensive-users', 'names the expensive principals',
      `select (select count(*) from public.ai_cost_log where dept_key is not null or agent_key is not null) > 0`,
      Q(`${await one(`select count(*)::text from public.ai_cost_log where dept_key is not null or agent_key is not null`)} ` +
        `of ${logged} calls are attributed to a department or agent`)],
    ['acct-expensive-tasks', 'names the expensive tasks',
      `select (select count(*) from public.ai_cost_log where task_class is not null) > 0`,
      Q(`${await one(`select count(*)::text from public.ai_cost_log where task_class is not null`)} of ${logged} ` +
        `calls are classified; ${await one(`select count(*)::text from public.ai_cost_log where task_class is null`)} are NOT`)],
    ['acct-optimization-alerts', 'raises an optimisation alert',
      B(alertFns.length > 0 && Number(await one(`select count(*)::text from public.ai_cost_log where could_be_cheaper`).catch(() => '0')) > 0),
      Q(`${alertFns.length} alert routine(s) [${brief(alertFns)}]; ` +
        `${await one(`select count(*)::text from public.ai_cost_log where could_be_cheaper`).catch(() => 'n/a')} call(s) ` +
        `flagged could_be_cheaper — §41 needs an alert that FIRES, not a view that could be read`)],
  ]) await req(S41, id, `the AI accountant ${label}`, sql, ev);

  // ── §42 HUMAN FEEDBACK LOOP (3) ───────────────────────────────────────────────────────────────
  const fbTable = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'feedback|rating|thumbs|review'`);
  const fbCols = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and column_name ~* 'thumbs|helpful|rating|score'
    and table_name ~* 'feedback|outcome|answer|response'`);
  await req(S42, 'feedback-thumbs', 'thumbs up / down is collected on answers',
    B(Number(fbCols) > 0),
    Q(`${fbCols} rating column(s) on feedback/outcome table(s) [${String(fbTable).slice(0, 60)}]`));

  const editCols = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and column_name ~* 'edited|corrected|revised|override'`);
  await req(S42, 'feedback-edits', 'user edits to an answer are captured',
    B(Number(editCols) > 0),
    Q(`${editCols} column(s) record an edit/correction/override of a generated answer`));

  const loopFns = await fnList('outcome_eval|feedback|autoswitch');
  await req(S42, 'feedback-improves-routing', 'the feedback changes future routing',
    B(loopFns.length > 0 && Number(await one(`select count(*)::text from public.model_outcome`).catch(() => '0')) > 0),
    Q(`${loopFns.length} routine(s) close the loop [${brief(loopFns)}]; model_outcome holds ` +
      `${await one(`select count(*)::text from public.model_outcome`).catch(() => 'n/a')} row(s) — ` +
      `a loop with no observations changes no routing`));
}
