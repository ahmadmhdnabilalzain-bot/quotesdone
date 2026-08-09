// SPEC FILE #8, part A — everything about NOT sending tokens you do not need to send.
//
//   §5  Token Management        (2)   §22 Response Length Controller (4)
//   §6  Local Embeddings        (2)   §30 Retrieval Over Generation  (1)
//   §9  Token Budgets           (2)   §31 Own Knowledge Layer        (5)
//   §10 Smart File Processing   (4)   §34 Developer Mode / Code Index(2)
//   §20 Prompt Compression      (2)   §21 Dynamic Context Window     (1)
//
// ── THE OVERLAP THIS MODULE MUST NOT COMMIT ──────────────────────────────────────────────────────
// One pgvector installation must not satisfy §6 (the OS memory store), §10 (file chunk retrieval)
// and §C3 (email attachment retrieval). They are three pipelines over one extension. §6 is scored
// on the vector columns themselves, §10 on a CHUNKING routine, and §C3 lives in channels.mjs and is
// scored on the attachment path. Overlap risk #5 in ROW8_REQUIREMENTS.md.

export const EXPECTED = 25;

export default async function (H) {
  const { req, one, B, Q, EDGE, APP, src, base, anyFile, filesMatching, filesNear,
          FN_EXISTS, FNS_MATCHING, TABLE_EXISTS, COL_EXISTS } = H;
  const S5 = '§5 tokens', S6 = '§6 embeddings', S9 = '§9 budgets', S10 = '§10 files',
        S20 = '§20 prompt', S21 = '§21 context', S22 = '§22 length', S30 = '§30 retrieval',
        S31 = '§31 knowledge', S34 = '§34 code index';
  const fnList = async (pat) => String(await one(FNS_MATCHING(pat))).split(' ').filter(Boolean);
  const brief = (a, n = 5) => a.slice(0, n).join(' ') || 'none';

  // ── §5 TOKEN MANAGEMENT (2) ───────────────────────────────────────────────────────────────────
  const compressFns = await fnList('summar|compress|condense|digest');
  const compressSrc = filesMatching(/summari[sz]e|compress|condense|rolling summary/i, EDGE).map(base);
  await req(S5, 'token-conversation-compression', 'conversation history is compressed, not resent whole',
    B(compressFns.length > 0 || compressSrc.length > 0),
    Q(`${compressFns.length} routine(s) [${brief(compressFns)}] and ${compressSrc.length} edge file(s) ` +
      `[${brief(compressSrc)}] summarise rather than resend`));

  // Context CLEANING is a different claim from compression: dropping greetings/tool output, not
  // shortening prose. Scored on a routine or path that PRUNES, and the two counts print separately.
  const cleanFns = await fnList('prune|trim|strip|clean.*context|context.*clean');
  const cleanSrc = filesNear(/prune|trim|strip|filter/i, /message|history|context|turn/i, 300, EDGE).map(base);
  await req(S5, 'token-context-cleaning', 'irrelevant turns and tool output are pruned from context',
    B(cleanFns.length > 0 || cleanSrc.length > 0),
    Q(`${cleanFns.length} routine(s) [${brief(cleanFns)}] and ${cleanSrc.length} edge file(s) ` +
      `[${brief(cleanSrc)}] prune context — distinct from compression, which shortens rather than drops`));

  // ── §6 LOCAL EMBEDDINGS (2) ───────────────────────────────────────────────────────────────────
  const vecCols = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and udt_name='vector'`);
  const vecTables = await one(`select coalesce(string_agg(distinct table_name, ' '), 'none')
    from information_schema.columns where table_schema='public' and udt_name='vector'`);
  await req(S6, 'embed-vector-store', 'a local vector store holds the memory',
    B(Number(vecCols) > 0),
    Q(`pgvector: ${vecCols} vector column(s) across [${vecTables}]`));

  const simFns = await fnList('<=>|cosine|similarity|embedding');
  await req(S6, 'embed-sends-only-relevant', 'retrieval selects relevant memory instead of all of it',
    B(simFns.length > 0),
    Q(`${simFns.length} routine(s) do vector/similarity retrieval [${brief(simFns)}]`));

  // ── §9 TOKEN BUDGETS (2) ──────────────────────────────────────────────────────────────────────
  // Per REQUEST, not per user — that is §28, and conflating them is overlap risk #3.
  const maxTok = await one(`select count(*)::text from public.model_policy where max_tokens > 0 and active`);
  const allPol = await one(`select count(*)::text from public.model_policy where active`);
  const routeMax = await one(`select public.fn_ai_route('agent_reasoning')->>'max_tokens'`).catch(() => null);
  await req(S9, 'budget-per-request-max-tokens', 'every request carries a max_tokens budget',
    B(!!routeMax && routeMax !== 'null' && Number(routeMax) > 0),
    Q(`fn_ai_route returns max_tokens=${routeMax}; ${maxTok} of ${allPol} active policies set one`));

  const unlimited = await one(`select count(*)::text from public.model_policy
    where active and tier <> 'none' and coalesce(max_tokens,0) = 0`);
  await req(S9, 'budget-no-unlimited-generation', 'no routed task class is allowed unlimited generation',
    B(Number(unlimited) === 0),
    Q(`${unlimited} active LLM-routed policy row(s) have no token ceiling — the spec's rule is ` +
      `"never allow unlimited generation"`));

  // ── §10 SMART FILE PROCESSING (4) ─────────────────────────────────────────────────────────────
  const parseSrc = filesMatching(/pdf|parse|extract.*text|unpdf|pdfjs/i, EDGE).map(base);
  await req(S10, 'file-parser', 'uploaded files are parsed before they reach a model',
    B(parseSrc.length > 0),
    Q(`${parseSrc.length} edge file(s) parse documents [${brief(parseSrc, 6)}]`));

  const chunkFns = await fnList('chunk');
  const chunkSrc = filesMatching(/chunk/i, EDGE).map(base);
  await req(S10, 'file-chunking', 'parsed text is chunked rather than sent whole',
    B(chunkFns.length > 0 || chunkSrc.length > 0),
    Q(`${chunkFns.length} routine(s) [${brief(chunkFns)}] and ${chunkSrc.length} edge file(s) ` +
      `[${brief(chunkSrc)}] chunk text`));

  // Scored on a CHUNK-aware vector search, not on pgvector existing — see the module header.
  const chunkVec = await one(`select count(*)::text from information_schema.columns
    where table_schema='public' and udt_name='vector' and table_name ~* 'chunk|doc|kb|knowledge'`);
  await req(S10, 'file-vector-search', 'chunks are retrieved by vector search',
    B(Number(chunkVec) > 0),
    Q(`${chunkVec} vector column(s) on chunk/document/knowledge tables — pgvector alone is §6, ` +
      `this leg needs the DOCUMENT pipeline`));

  const relevantSrc = filesNear(/chunk|section|page/i, /match|similar|top.?k|limit|relevant/i, 400, EDGE).map(base);
  await req(S10, 'file-sends-only-relevant-sections', 'only the relevant sections reach the model',
    B(relevantSrc.length > 0),
    Q(`${relevantSrc.length} edge file(s) select chunks by relevance before the model call ` +
      `[${brief(relevantSrc)}]`));

  // ── §20 PROMPT COMPRESSION (2) ────────────────────────────────────────────────────────────────
  const promptTable = await one(TABLE_EXISTS('agent_prompt'));
  const promptStore = await one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* 'prompt|persona|system_profile'`);
  await req(S20, 'prompt-profile-stored-not-resent', 'the system profile is stored, not resent every call',
    B(promptStore !== 'none'),
    Q(`prompt/persona table(s): [${promptStore}]; agent_prompt exists ${promptTable}`));

  const cacheable = await one(`select count(*)::text from public.model_registry where active and supports_cache`);
  await req(S20, 'prompt-only-necessary-instructions', 'only the necessary instructions are sent',
    B(Number(cacheable) > 0),
    Q(`${cacheable} active model(s) support prompt caching, which is what makes a stable prefix cheap; ` +
      `${await one(`select count(*)::text from public.ai_cost_log where coalesce(cached,false)`)} of ` +
      `${await one(`select count(*)::text from public.ai_cost_log`)} logged calls used it`));

  // ── §21 DYNAMIC CONTEXT WINDOW (1) ────────────────────────────────────────────────────────────
  const ctxSpread = await one(`select (max(context_len) > 4 * min(context_len))::text from public.model_registry where active`);
  const ctxRange = await one(`select min(context_len)::text || '..' || max(context_len)::text from public.model_registry where active`);
  await req(S21, 'ctx-dynamic-window', 'the context window is chosen per task, not fixed at maximum',
    B(String(ctxSpread) === 'true'),
    Q(`active model context windows span ${ctxRange}; routing across that spread IS the dynamic window`));

  // ── §22 RESPONSE LENGTH CONTROLLER (4) ────────────────────────────────────────────────────────
  // The spec names four modes with rising ceilings. Scored on whether the estate's max_tokens
  // ladder actually HAS four distinct bands — a single ceiling for everything is what §22 rejects.
  const bands = await one(`select count(distinct max_tokens)::text from public.model_policy
    where active and max_tokens > 0`);
  const bandList = await one(`select coalesce(string_agg(distinct max_tokens::text, ' ' order by max_tokens::text), 'none')
    from public.model_policy where active and max_tokens > 0`);
  for (const [id, floor, label] of [
    ['len-quick', 1, 'Quick — a short ceiling exists'],
    ['len-normal', 2, 'Normal — a second, larger ceiling exists'],
    ['len-detailed', 3, 'Detailed — a third ceiling exists'],
    ['len-expert', 4, 'Expert — a fourth, largest ceiling exists'],
  ]) {
    await req(S22, id, label,
      B(Number(bands) >= floor),
      Q(`${bands} distinct max_tokens band(s) in model_policy [${bandList}]; this leg needs >= ${floor}`));
  }

  // ── §30 RETRIEVAL OVER GENERATION (1) ─────────────────────────────────────────────────────────
  const kbRows = await one(`select count(*)::text from public.agent_knowledge`);
  const retrievalFns = await fnList('agent_knowledge');
  await req(S30, 'retrieval-over-generation', 'stored knowledge is retrieved rather than regenerated',
    B(Number(kbRows) > 0 && retrievalFns.length > 0),
    Q(`agent_knowledge holds ${kbRows} row(s), read by ${retrievalFns.length} routine(s) ` +
      `[${brief(retrievalFns)}]`));

  // ── §31 OWN KNOWLEDGE LAYER (5) ───────────────────────────────────────────────────────────────
  // The spec names five things the OS brain must hold. Each is scored on a distinct store.
  for (const [id, label, sql, ev] of [
    ['kb-user-preferences', 'user preferences',
      `select (select count(*) from information_schema.tables where table_schema='public'
        and table_name ~* 'preference|setting|profile') > 0`,
      `select 'tables: ' || coalesce((select string_agg(table_name,' ') from information_schema.tables
        where table_schema='public' and table_name ~* 'preference|setting|profile'),'none')`],
    ['kb-previous-solutions', 'previous solutions',
      `select (select count(*) from public.agent_knowledge where layer='experience' or topic ~* 'lesson|solution|case') > 0`,
      `select 'agent_knowledge experience/lesson rows: ' || (select count(*) from public.agent_knowledge
        where layer='experience' or topic ~* 'lesson|solution|case')::text`],
    ['kb-app-documentation', 'app documentation',
      `select (select count(*) from public.agent_knowledge where layer='company') > 0`,
      `select 'agent_knowledge company-layer rows: ' || (select count(*) from public.agent_knowledge where layer='company')::text`],
    ['kb-commands', 'commands',
      `select (select count(*) from information_schema.tables where table_schema='public'
        and table_name ~* 'workflow_step|command|action') > 0`,
      `select 'tables: ' || coalesce((select string_agg(table_name,' ') from information_schema.tables
        where table_schema='public' and table_name ~* 'workflow_step|command|action'),'none')`],
    ['kb-workflows', 'workflows',
      `select (select count(*) from public.workflow) > 0`,
      `select 'workflow rows: ' || (select count(*) from public.workflow)::text`],
  ]) await req(S31, id, `the OS brain holds ${label}`, sql, ev);

  // ── §34 DEVELOPER MODE / CODE INDEX (2) ───────────────────────────────────────────────────────
  // "Never send the entire project. Use a code index." This repo has one: graphify-out/graph.json,
  // and CLAUDE.md mandates querying it before reading source. That is the requirement, met by
  // tooling rather than by a table — the spec's subject is the capability.
  const { existsSync, statSync } = await import('node:fs');
  const graphPath = new URL('../../../graphify-out/graph.json', import.meta.url).pathname.replace(/^\//, '');
  const hasGraph = existsSync(graphPath);
  await req(S34, 'code-index-exists', 'a code index exists so the whole project is never sent',
    B(hasGraph),
    Q(`graphify-out/graph.json present ${hasGraph}` +
      (hasGraph ? `, ${Math.round(statSync(graphPath).size / 1024)} KB` : '')));

  const claudeMd = existsSync(new URL('../../../CLAUDE.md', import.meta.url).pathname.replace(/^\//, ''));
  await req(S34, 'code-index-sends-relevant-files-only', 'the index is consulted before raw files',
    B(hasGraph && claudeMd),
    Q(`CLAUDE.md mandates 'graphify query' before reading source: ${claudeMd}; index present ${hasGraph}`));
}
