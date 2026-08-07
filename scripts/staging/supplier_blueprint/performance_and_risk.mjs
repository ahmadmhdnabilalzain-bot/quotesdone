// SPEC FILE #5, sections 13-17 — Performance, Market, AI Employee, Documents, Risk.
//
//   13. Supplier Performance Intelligence (9) — "a LIVING score": five bars and an overall
//   14. Market Intelligence               (7) — demand trend, market price, competitor count
//   15. Supplier AI Employee              (7) — "why am I losing RFQs?" and a real answer
//   16. Supplier Document Intelligence    (8) — "documents are ALIVE, not stored files"
//   17. Supplier Risk Protection          (8) — four monitored signals, warned with a cause
//
// ── THIS MODULE SCORES THE ROW'S CENTRAL CLAIM, SO ITS EMPTY-ESTATE RULE MATTERS MOST ────────────
// Measured on production before these checks were written:
//   supplier_score columns: lead_id, response_rate, avg_response_hours, quotes_submitted,
//   quotes_won, rejection_count, price_index, quality_rating, reliability, last_active, computed_at
//   — 20,464 rows, reliability non-null on ALL of them.
// §13's five bars are not hypothetical. Quality, Delivery, Response and Pricing all have a real
// column computed for every company on production. A MISSING in §13 is therefore NEVER "no data";
// it is "computed for twenty thousand companies and shown to none of them", and every evidence
// string says so with the row count attached so no future reader can mistake the two.
//
// The inverse also holds and is scored honestly. §17's certificate-expiry monitor has a REAL active
// cron — doc_expiry_daily, 05:20 nightly, running fn_doc_expiry_scan(). It also has nothing to
// scan: license_expiry and iso_expiry are non-null on 0 of 20,464 rows. The mechanism is the
// verdict and the emptiness is the evidence, because a check that failed a working monitor for
// having no data would be unsatisfiable until the business had customers.
//
// ── EVERY LESSON FROM ROUNDS 1-4 IS APPLIED PRE-EMPTIVELY ────────────────────────────────────────
//  · P_FILES / P for any "the portal does X" leg. ChatWidget.tsx has produced a false MET in THREE
//    sections already (§2, §4, §11); §15 is the next obvious victim and is fenced from the start.
//  · near()/filesNear()/fnsNear() for any two-thing leg — windowed WITHIN one file or one function,
//    never across a join, because SupplierPortal.tsx is 81,811 chars holding six unrelated features.
//  · A SUBJECT gate on generic vocabulary. §9 taught this the hard way: /scope/ matched OAuth,
//    /expires_at/ matched the OTP's own expiry. §16 and §17 are full of the same hazard — an expiry
//    date is meaningless without knowing WHAT expires.
//  · Row counts printed beside every verdict, never used as one.
import {
  S, P, FILES, P_FILES, FNS, fileSrc, fnSrc, n, has, filesMatching, fnsMatching, fnsWithBoth,
  near, filesNear, fnsNear, delivered, cover, B, Q, READERS_SQL, NROWS_SQL,
} from '../supplier_checks.mjs';

export const EXPECTED = 39;

export default async function (H) {
  const { req, one } = H;
  const S13 = 'perf', S14 = 'mkt', S15 = 'emp', S16 = 'doc', S17 = 'risk';

  const scoreRows = await one(NROWS_SQL('supplier_score'));
  const relRows = await one(NROWS_SQL('supplier_score', 'reliability is not null'));
  const ESTATE = `supplier_score ${scoreRows} row(s), reliability non-null on ${relRows} — a MISSING here is "computed and not shown"`;

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §13 — SUPPLIER PERFORMANCE INTELLIGENCE (9)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // KEPT DISTINCT FROM §4's TWO TILES. docs/sessions/ROW5_REQUIREMENTS.md logs this overlap: §4
  // draws Response and Quality as summary tiles on the command centre; §13 draws a FIVE-metric
  // health panel with bars. The panel leg below requires three or more metrics together in one
  // file, which two command-centre tiles cannot satisfy, so neither section can score the other's
  // implementation.
  const METRICS = [
    ['perf-quality', /quality[_ ]?(rating|score|pct)/i, 'quality_rating', 'Quality'],
    ['perf-delivery', /reliability|delivery[_ ]?(rate|score|performance)|on[_ ]?time/i, 'reliability', 'Delivery'],
    ['perf-response', /response[_ ]?rate|avg[_ ]?response[_ ]?hours/i, 'response_rate', 'Response'],
    ['perf-pricing', /price[_ ]?index|pricing[_ ]?(score|rating)/i, 'price_index', 'Pricing'],
  ];

  // The panel itself: three or more of the five metrics rendered together in ONE file.
  const panelFiles = P_FILES.filter((f) => {
    const src = fileSrc(f);
    return METRICS.filter(([, re]) => re.test(src)).length >= 3;
  });
  await req(S13, 'perf-health-panel', 'a SUPPLIER HEALTH panel with the five metrics together',
    B(panelFiles.length > 0),
    Q(`${panelFiles.length} portal file(s) carry 3+ health metrics together ` +
      `[${panelFiles.map(f => f.split('/').pop()).join(' ') || 'none'}] — two command-centre tiles are §4, not §13; ${ESTATE}`));

  for (const [id, re, col, label] of METRICS) {
    const colRows = await one(NROWS_SQL('supplier_score', `${col} is not null`));
    const shown = delivered(re, P);
    const served = fnsMatching(re);
    await req(S13, id, `the health panel shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]; ` +
        `supplier_score.${col} non-null on ${colRows} of ${scoreRows} row(s) — the data is not the blocker`));
  }

  const overallShown = delivered(/overall[_ ]?(score|rating)|health[_ ]?score|\/\s*100/i, P);
  const overallServed = fnsMatching(/overall[_ ]?(score|rating)|health[_ ]?score/i);
  await req(S13, 'perf-overall', 'an Overall score out of 100',
    B(overallShown && overallServed.length > 0),
    Q(`rendered ${overallShown ? 'yes' : 'NO'}, served by [${overallServed.join(' ') || 'NO fn'}]; ${ESTATE}`));

  // BARS, not bare numbers — the spec draws █████ for each metric. A width-driven element beside a
  // metric is the refutable form. Scored per file so the bar and the metric are genuinely together.
  const barFiles = P_FILES.filter((f) => METRICS.some(([, re]) => near(fileSrc(f), re, /width\s*:|w-\[|<progress|role=["']progressbar|bg-\w+\s+h-/i, 300)));
  await req(S13, 'perf-bars-rendered', 'the metrics render as bars, not bare numbers',
    B(barFiles.length > 0),
    Q(`${barFiles.length} portal file(s) put a width-driven element next to a health metric ` +
      `[${barFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // "A LIVING score." The refutable difference between living and static is RECOMPUTATION: an
  // active cron or scheduled routine that rewrites supplier_score. computed_at exists on the table,
  // so this is answerable directly.
  const scoreCron = await one(`select count(*)::text from cron.job
    where active and command ~* '\\ysupplier_score\\y|score'`);
  const scoreWriters = await one(`select count(distinct p.proname)::text from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p')
      and pg_get_functiondef(p.oid) ~* '\\ysupplier_score\\y'`);
  const freshRows = await one(NROWS_SQL('supplier_score', "computed_at > now() - interval '30 days'"));
  await req(S13, 'perf-living', 'the score is recomputed on a schedule, not a static column',
    B(Number(scoreCron) > 0),
    Q(`${scoreCron} active cron(s) recompute a score, ${scoreWriters} routine(s) touch supplier_score, ` +
      `${freshRows} of ${scoreRows} row(s) computed in the last 30d — a score written once is not living`));

  const perfVisible = filesMatching(/supplier_score|health[_ ]?score|performance[_ ]?panel/i, P_FILES);
  await req(S13, 'perf-supplier-visible', 'the health panel renders on the supplier surface',
    B(perfVisible.length > 0),
    Q(`${perfVisible.length} of ${P_FILES.length} portal file(s) name the score store ` +
      `[${perfVisible.map(f => f.split('/').pop()).join(' ') || 'none'}]; ${ESTATE}`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §14 — MARKET INTELLIGENCE (7)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // The SUBJECT gate matters here: "trend", "price" and "competitor" are generic. Each leg requires
  // the value near market subject matter in the same file or function.
  const MKTCTX = /market|demand|competitor|benchmark|industry/i;

  const mktFiles = filesNear(MKTCTX, /trend|price|demand|competitor/i, 400, P_FILES);
  await req(S14, 'mkt-panel', 'a Market Intelligence panel',
    B(mktFiles.length > 0),
    Q(`${mktFiles.length} portal file(s) pair market subject matter with market content ` +
      `[${mktFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  for (const [id, re, label] of [
    ['mkt-demand-trend', /demand[_ ]?trend|trend[_ ]?(pct|percent|direction)|↑|↓/i, 'a demand trend with direction'],
    ['mkt-most-requested', /most[_ ]?requested|top[_ ]?(category|demand|project)/i, 'the most-requested project type'],
    ['mkt-avg-market-price', /avg[_ ]?(market[_ ]?)?price|average[_ ]?price|market[_ ]?rate/i, 'an average market price'],
    ['mkt-competitor-count', /competitor[_ ]?count|competitors|\brivals\b/i, 'a competitor count'],
  ]) {
    const shown = delivered(re, P);
    const served = fnsNear(re, MKTCTX, 400);
    await req(S14, id, `market intelligence shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]`));
  }

  const mktFn = fnsNear(MKTCTX, /count\(|avg\(|sum\(|group by|percentile/i, 500);
  const mktRoutines = await one(`select count(distinct p.proname)::text from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p') and p.proname ~* 'market|demand|benchmark'`);
  await req(S14, 'mkt-routine', 'the market figures are computed from real demand data',
    B(mktFn.length > 0),
    Q(`${mktFn.length} reachable fn(s) aggregate market data [${mktFn.join(' ') || 'none'}]; ` +
      `${mktRoutines} market/demand routine(s) in public`));

  const chartFiles = filesNear(MKTCTX, /recharts|<svg|d3-|<path|chart|sparkline/i, 400, P_FILES);
  await req(S14, 'mkt-chart', 'the trend renders as a chart',
    B(chartFiles.length > 0),
    Q(`${chartFiles.length} portal file(s) pair market content with chart machinery ` +
      `[${chartFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §15 — SUPPLIER AI EMPLOYEE (7)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // FENCED FROM ChatWidget.tsx FROM THE START. It has produced a false MET in §2, §4 and §11, and
  // §15 — "every supplier gets an AI assistant" — is the single most inviting target left. Every
  // leg runs over P / P_FILES, and the support-chat vocabulary that fooled §4 intra-file is
  // subtracted here too, with both counts printed.
  const SUPPORT_CHAT = /ask[_ ]?(a )?question|ask[_ ]?placeholder|ask[_ ]?request|request[_ ]?(a )?chat|assistant_pre|answers instantly|handles most questions/i;
  const supportTok = n(SUPPORT_CHAT, P);

  const empFiles = filesNear(/assistant|ai[_ ]?employee|advisor/i, /your[_ ]?(performance|profile|rfq|business)|analys|recommend/i, 400, P_FILES);
  await req(S15, 'emp-assistant-present', 'an AI assistant is available on the supplier surface',
    B(empFiles.length > 0),
    Q(`${empFiles.length} portal file(s) pair an assistant with supplier-specific analysis ` +
      `[${empFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ` +
      `${supportTok} support-chat token(s) excluded — a help desk is not §15's AI employee`));

  const nlQ = filesNear(/why[_ ]?am[_ ]?i|why[_ ]?do[_ ]?i|ask[_ ]?the[_ ]?assistant|<textarea/i, /assistant|analys|advice/i, 400, P_FILES);
  await req(S15, 'emp-nl-question', 'it accepts free-form questions',
    B(nlQ.length > 0),
    Q(`${nlQ.length} portal file(s) pair a free-form input with assistant analysis ` +
      `[${nlQ.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const lossFn = fnsNear(/lost|losing|rejection|not[_ ]?won|declined/i, /reason|analys|breakdown|why/i, 500);
  await req(S15, 'emp-loss-analysis', 'it produces a lost-opportunity breakdown',
    B(lossFn.length > 0),
    Q(`${lossFn.length} fn(s) pair loss with reason analysis [${lossFn.join(' ') || 'none'}]; ` +
      `supplier_score.rejection_count exists, so the input is present`));

  const lossPct = filesNear(/lost|losing|rejection|declined/i, /\d+\s*%|pct|percent/i, 300, P_FILES);
  await req(S15, 'emp-loss-reasons-pct', 'the loss reasons carry percentages',
    B(lossPct.length > 0),
    Q(`${lossPct.length} portal file(s) put a percentage next to a loss reason ` +
      `[${lossPct.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const recFiles = filesNear(/recommend|you[_ ]?should|next[_ ]?step|suggested[_ ]?action/i, /upload|improve|update|add/i, 300, P_FILES);
  await req(S15, 'emp-recommendations', 'it recommends concrete actions',
    B(recFiles.length > 0),
    Q(`${recFiles.length} portal file(s) pair a recommendation with a concrete verb ` +
      `[${recFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // A recommendation the supplier cannot act on is a sentence. Requires the advice to sit next to
  // the affordance that performs it.
  const actionable = filesNear(/recommend|you[_ ]?should|suggested[_ ]?action/i, /onClick|href=|<button|setView|FilePick/i, 300, P_FILES);
  await req(S15, 'emp-recommendation-actionable', 'the recommendation links to the fix',
    B(actionable.length > 0),
    Q(`${actionable.length} portal file(s) put advice next to an actionable control ` +
      `[${actionable.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const agentFn = fnsNear(/prompt|system[_ ]?message|completion/i, /supplier|lead_id|your[_ ]?company/i, 600);
  await req(S15, 'emp-agent-routine', 'an agent routine backs it with supplier context',
    B(agentFn.length > 0),
    Q(`${agentFn.length} fn(s) pair an LLM prompt with supplier context [${agentFn.join(' ') || 'none'}]`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §16 — SUPPLIER DOCUMENT INTELLIGENCE (8)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "Documents are alive. NOT STORED FILES." The portal demonstrably stores files — that is §7's
  // uploader and the registration flow. §16 is the claim that a document KNOWS things about itself:
  // what it is, whether it is valid, when it expires, what it unlocked, and what it is worth.
  // A file path in a column satisfies none of that, so every leg requires the intelligence, and the
  // storage-only vocabulary is printed beside it.
  const STORAGE_ONLY = /_doc_path|_doc_name|storage\.from|upload|FilePick/i;
  const storageTok = n(STORAGE_ONLY, P);

  const docFiles = filesNear(/certificate|licen[cs]e|iso|document/i, /valid|expir|status|impact|used[_ ]?for/i, 400, P_FILES);
  await req(S16, 'doc-intelligence-panel', 'a document-intelligence panel',
    B(docFiles.length > 0),
    Q(`${docFiles.length} portal file(s) pair a document with intelligence about it ` +
      `[${docFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]; ` +
      `${storageTok} storage-only token(s) — a file path is not a living document`));

  const docIdent = fnsNear(/document|certificate|licen[cs]e/i, /classif|detect|type|kind|recognis|recogniz/i, 500);
  await req(S16, 'doc-identity', 'documents are recognised by type, not filename',
    B(docIdent.length > 0),
    Q(`${docIdent.length} fn(s) pair a document with type recognition [${docIdent.join(' ') || 'none'}]`));

  //
  // ── IDENTIFIER-SHAPED, NOT THE ENGLISH WORD NEAR A SUBJECT WORD ───────────────────────────────
  // `/\bvalid\b/ near /licence|document/` read MET and listed login_otp and kyc among its servers.
  // Both matched `email_verifications … expires_at` — THE OTP'S OWN EXPIRY — and supplier_api
  // matched the admin prose "Uploading a valid licence approves them". None of the three is a
  // document carrying a validity status. This is §9's plumbing defect in a new costume: proximity
  // to a subject word is not the same as being a field ABOUT that subject.
  //
  // A document status is a named thing: doc_status, license_status, verification_status ON A
  // DOCUMENT. The English word "valid" in a sentence is not.
  for (const [id, re, label] of [
    ['doc-status-valid', /(doc|document|licen[cs]e|iso|certificate)[_ ]?status|status:\s*['"](valid|expired|revoked)/i, 'a validity status'],
    ['doc-impact', /(doc|document|certificate)[_ ]?impact|impact[_ ]?(score|rating|level)|criticality/i, 'an impact rating'],
  ]) {
    const shown = delivered(re, P);
    const served = fnsMatching(re);
    const loose = fnsNear(id === 'doc-status-valid' ? /\bvalid\b/i : /impact/i, /document|certificate|licen[cs]e|iso/i, 400);
    await req(S16, id, `the document shows ${label}`,
      B(shown && served.length > 0),
      Q(`${label}: rendered ${shown ? 'yes' : 'NO'}, served by [${served.join(' ') || 'NO fn'}]; ` +
        `${loose.length} fn(s) merely put the English word near a document word [${loose.join(' ')}] — prose is not a field`));
  }

  // THE SUBJECT GATE, and §9 is why. An expiry date means nothing without knowing what expires —
  // /expires?_at/ matched the OTP's own expiry there and produced a false MET. Here it must be a
  // DOCUMENT's expiry. The estate has license_expiry / iso_expiry / manufacturer_auth_expiry, all
  // non-null on 0 of 20,464 rows, so the count is printed and the mechanism is the verdict.
  const licExp = await one(NROWS_SQL('leads', 'license_expiry is not null'));
  const isoExp = await one(NROWS_SQL('leads', 'iso_expiry is not null'));
  // The gate is a DOCUMENT-SCOPED FIELD NAME. `/expir/ near a document word` listed login_otp and
  // kyc as servers, and both were `email_verifications … expires_at` — the OTP's own expiry sitting
  // coincidentally within the window. supplier_api, by contrast, genuinely returns `license_expiry`
  // in its column list, and the identifier form keeps that MET while dropping the two false ones.
  const DOCEXP = /(licen[cs]e|iso|manufacturer_auth|insurance|cert\w*)[_ ]?expiry|expiry[_ ]?date/i;
  const expShown = filesNear(DOCEXP, /licen[cs]e|iso|certificate|document/i, 300, P_FILES);
  const expServed = fnsMatching(DOCEXP);
  const expLoose = fnsNear(/expir/i, /licen[cs]e|iso|certificate|document/i, 400);
  await req(S16, 'doc-expiry-date', 'the document shows its expiry date',
    B(expShown.length > 0 && expServed.length > 0),
    Q(`rendered on ${expShown.length} portal file(s), served by [${expServed.join(' ') || 'NO fn'}]; ` +
      `${expLoose.length} fn(s) match a loose /expir/ near a document word [${expLoose.join(' ')}] — ` +
      `login_otp/kyc are the OTP's own expiry; license_expiry non-null on ${licExp}, iso_expiry on ${isoExp} of 20464`));

  const usedFor = filesNear(/used[_ ]?for|unlocked|qualified[_ ]?you|enabled/i, /rfq|opportunit|inquir/i, 300, P_FILES);
  await req(S16, 'doc-used-for-count', 'the document shows how many RFQs it unlocked',
    B(usedFor.length > 0),
    Q(`${usedFor.length} portal file(s) tie a document to the opportunities it unlocked ` +
      `[${usedFor.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const docExtract = fnsNear(/document|licen[cs]e|certificate|pdf/i, /prompt|extract|ocr|parse|vision/i, 500);
  await req(S16, 'doc-extraction-routine', 'server-side document understanding',
    B(docExtract.length > 0),
    Q(`${docExtract.length} fn(s) pair a document with extraction [${docExtract.join(' ') || 'none'}]`));

  const docVisible = filesNear(/document|certificate|licen[cs]e/i, /valid|expir|impact|status/i, 400, P_FILES);
  await req(S16, 'doc-supplier-visible', 'the document panel renders on the supplier surface',
    B(docVisible.length > 0),
    Q(`${docVisible.length} of ${P_FILES.length} portal file(s) render document intelligence ` +
      `[${docVisible.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  // ════════════════════════════════════════════════════════════════════════════════════════════════
  // §17 — SUPPLIER RISK PROTECTION (8)
  // ════════════════════════════════════════════════════════════════════════════════════════════════
  //
  // "AI MONITORS" — so the four monitor legs are about a SCHEDULED routine, not a screen. Measured
  // before writing: doc_expiry_daily runs fn_doc_expiry_scan() nightly at 05:20 and is ACTIVE. That
  // is a real monitor with nothing to monitor, and it is scored MET on the mechanism with the
  // emptiness in its evidence — a check that failed a working monitor for having no data would be
  // unsatisfiable until the business had customers, which is the row #4 unsatisfiable-check defect.
  const activeCrons = await one(`select count(*)::text from cron.job where active`);

  const monitorCron = await one(`select count(*)::text from cron.job
    where active and command ~* 'expiry|expire|risk|complaint|performance|score'`);
  await req(S17, 'risk-monitor-routine', 'a monitoring routine runs on a schedule',
    B(Number(monitorCron) > 0),
    Q(`${monitorCron} active cron(s) monitor risk signals of ${activeCrons} active cron(s) total`));

  //
  // ── A WRITE KEYWORD INSIDE A REGEX LITERAL STILL LOOKS LIKE A WRITE ───────────────────────────
  // The performance-drop pattern contains the literal word `drop`, so qd_guard's read guard refused
  // the whole SELECT. These one() calls sit OUTSIDE req()'s try/catch, so the throw did not error a
  // single check — it aborted the module, and the last four requirements were never registered at
  // all. The runner's denominator assertion is the only reason this surfaced: `registered 35 checks,
  // expected 39`. Without it the run would have reported a clean 38/151 with four requirements
  // silently absent from the denominator, which INFLATES the percentage.
  //
  // Same root cause as the `do` bug in Q(): a keyword the guard scans for, sitting inside text that
  // is not a statement. SPLIT() defuses it in the SQL string itself.
  // Returns a PARENTHESISED expression, quotes included. `||` binds looser than `~*` in Postgres,
  // so `command ~* 'a' || 'b'` parses as `(command ~* 'a') || 'b'` — boolean concatenated with text
  // — and fails with 42804 "argument of AND must be type boolean". The parentheses are the fix.
  const SPLIT = (s) => "('" + s.replace(/\b(drop|delete|update|insert|alter|create|call|do)\b/gi,
    (m) => m.slice(0, 1) + "' || '" + m.slice(1)) + "')";
  for (const [id, rawPat, label] of [
    ['risk-monitor-cert-expiry', 'expiry|expire', 'certificate expiry'],
    ['risk-monitor-complaints', 'complaint|dispute|grievance', 'customer complaints'],
    ['risk-monitor-response-delays', 'response_rate|avg_response_hours|response[_ ]?delay|slow[_ ]?response', 'response delays'],
    ['risk-monitor-performance-drops', 'performance[_ ]?drop|score[_ ]?drop|declin|deterior', 'performance drops'],
  ]) {
    const sqlPat = SPLIT(rawPat);
    const cron = await one(`select count(*)::text from cron.job where active and command ~* ${sqlPat}`);
    const fn = await one(`select count(distinct p.proname)::text from pg_proc p
      join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p')
        and (p.proname ~* ${sqlPat} or pg_get_functiondef(p.oid) ~* ${sqlPat})`);
    await req(S17, id, `the monitor watches ${label}`,
      B(Number(cron) > 0),
      Q(`${label}: ${cron} active cron(s), ${fn} routine(s) reference it — a routine with no schedule is not a monitor`));
  }

  const warnFiles = filesNear(/warning|alert|at[_ ]?risk|attention/i, /performance|expir|delay|drop|complaint/i, 400, P_FILES);
  await req(S17, 'risk-warning-surface', 'warnings render to the supplier',
    B(warnFiles.length > 0),
    Q(`${warnFiles.length} portal file(s) pair a warning with a risk signal ` +
      `[${warnFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const causeFiles = filesNear(/cause|because|due[_ ]?to|reason/i, /warning|alert|drop|delay/i, 300, P_FILES);
  await req(S17, 'risk-warning-cause', 'the warning names its cause',
    B(causeFiles.length > 0),
    Q(`${causeFiles.length} portal file(s) put a cause next to a warning ` +
      `[${causeFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));

  const actFiles = filesNear(/recommended[_ ]?action|you[_ ]?should|to[_ ]?fix|resolve/i, /warning|alert|risk|expir/i, 300, P_FILES);
  await req(S17, 'risk-recommended-action', 'the warning carries a recommended action',
    B(actFiles.length > 0),
    Q(`${actFiles.length} portal file(s) pair a warning with a recommended action ` +
      `[${actFiles.map(f => f.split('/').pop()).join(' ') || 'none'}]`));
}
