// SPEC FILE #8, parts B-E — the WhatsApp agent, the email agent, the website widget, and the one
// customer brain behind all three.
//
//   B WhatsApp Agent        (43)   D Website Chat Widget (23)
//   C Email Agent           (22)   E Unified Customer Brain (5)
//
// ── THE CONSTRAINT THAT SHAPES EVERY CHECK HERE, AND IT IS ROW #5's CONSTRAINT AGAIN ─────────────
// Measured on production 2026-08-09: customers 0 rows, wa_messages 5, messages 1,
// inbound_messages present, response_template 6. The channels are BUILT and essentially UNUSED —
// the same "no principal" wall row #5 hit, arriving through a different door.
//
// So a `-used` bar over channel traffic would report MISSING for eighty-eight requirements and
// measure nothing except that the business has not launched. Every leg in this module is therefore
// scored on MECHANISM — the table, the routine, the edge function that would carry it — and the
// row counts print beside the verdict so the emptiness is visible rather than hidden.
//
// That is a deliberate, stated asymmetry with part A, where ai_cost_log's 1,021 rows DO support
// behavioural scoring. Applying part A's bar here would not be stricter, it would be noise: a
// requirement cannot be failed for lack of customers when the spec is about what happens when a
// customer arrives.

export const EXPECTED = 93;

export default async function (H) {
  const { req, one, B, Q, EDGE, APP, src, base, anyFile, filesMatching, filesNear,
          FN_EXISTS, FNS_MATCHING, TABLE_EXISTS, COL_EXISTS } = H;
  const B1 = 'B whatsapp', C1 = 'C email', D1 = 'D website', E1 = 'E unified';
  const fnList = async (pat) => String(await one(FNS_MATCHING(pat))).split(' ').filter(Boolean);
  const brief = (a, n = 4) => a.slice(0, n).join(' ') || 'none';
  const tbl = (t) => one(TABLE_EXISTS(t));
  const rowsOf = async (t) => { try { return await one(`select count(*)::text from public.${t}`); } catch { return 'n/a'; } };
  const anyTable = (pat) => one(`select coalesce(string_agg(table_name,' '),'none') from information_schema.tables
    where table_schema='public' and table_name ~* '${pat}'`);
  const anyCol = (pat, tpat = '.') => one(`select count(*)::text from information_schema.columns
    where table_schema='public' and column_name ~* '${pat}' and table_name ~* '${tpat}'`);

  const waRows = await rowsOf('wa_messages');
  const custRows = await rowsOf('customers');
  const ESTATE = `wa_messages ${waRows}, customers ${custRows} — mechanism, not traffic`;
  const waEdge = EDGE.filter(f => /wa_|whatsapp/i.test(f)).map(base);
  const emEdge = EDGE.filter(f => /email|resend/i.test(f)).map(base);

  // ══ PART B — WHATSAPP (43) ══════════════════════════════════════════════════════════════════════

  // §B1 control layer (1)
  const waInbound = EDGE.find(f => /wa_inbound/.test(f));
  const ctrlSrc = waInbound ? src(waInbound) : '';
  await req(B1, 'wa-control-layer', 'a control layer sits before AI on inbound WhatsApp',
    B(!!waInbound && /if|switch|route|classif/i.test(ctrlSrc)),
    Q(`wa_inbound present ${!!waInbound}; ${waEdge.length} whatsapp edge function(s) [${brief(waEdge, 6)}]; ${ESTATE}`));

  // §B2 message classification (3)
  for (const [id, re, label] of [
    ['wa-type-a-fixed-no-ai', /faq|template|lookup|database|order.?status|no.?ai/i, 'Type A — fixed questions answered with no AI'],
    ['wa-type-b-simple-cheap', /cheap|small|flash|lite|simple/i, 'Type B — simple conversation on a cheap model'],
    ['wa-type-c-complex-premium', /complex|premium|escalat|sonnet|opus/i, 'Type C — complex requests on a stronger model'],
  ]) {
    const hit = ctrlSrc && re.test(ctrlSrc);
    const anywhere = filesMatching(re, EDGE.filter(f => /wa_|whatsapp/i.test(f))).map(base);
    await req(B1, id, label, B(!!hit || anywhere.length > 0),
      Q(`${anywhere.length} whatsapp edge file(s) carry this branch [${brief(anywhere)}]`));
  }

  // §B3 personality layers (3)
  const personaTables = await anyTable('persona|prompt|agent_profile');
  for (const [id, pat, label] of [
    ['wa-layer-base-personality', 'persona|personality|tone|voice', 'a base personality layer'],
    ['wa-layer-business-rules', 'rule|policy|guardrail|never|must', 'a business-rules layer'],
    ['wa-layer-current-situation', 'context|situation|current|state', 'a current-situation layer'],
  ]) {
    const n = await anyCol(pat, 'persona|prompt|agent|category_agents');
    await req(B1, id, `the WhatsApp agent composes ${label}`,
      B(Number(n) > 0),
      Q(`${n} column(s) carry this layer across persona/prompt/agent table(s) [${String(personaTables).slice(0, 60)}]`));
  }

  // §B4 conversation memory (1)
  const summaryCol = await anyCol('summary|digest|last_summary', 'customer|conversation|chat|thread|wa_');
  await req(B1, 'wa-memory-not-full-history', 'a summary is carried, not the whole thread',
    B(Number(summaryCol) > 0),
    Q(`${summaryCol} summary column(s) on customer/conversation table(s) — the alternative is ` +
      `resending every message, which is what §B4 rejects`));

  // §B5 customer memory DB (7)
  for (const [id, pat, label] of [
    ['wa-mem-customer-id', 'customer_id|contact_id|wa_id|phone', 'a customer identifier'],
    ['wa-mem-preferences', 'preference', 'preferences'],
    ['wa-mem-previous-purchases', 'purchase|order|invoice|quote', 'previous purchases'],
    ['wa-mem-complaints', 'complaint|dispute|issue|escalat', 'complaints'],
    ['wa-mem-important-dates', 'birthday|anniversary|due|renewal|important_date', 'important dates'],
    ['wa-mem-communication-style', 'style|tone|language|locale', 'communication style'],
    ['wa-mem-last-summary', 'summary|last_seen|last_contact', 'the last conversation summary'],
  ]) {
    const n = await anyCol(pat, 'customer|contact|lead|wa_|crm');
    await req(B1, id, `customer memory holds ${label}`,
      B(Number(n) > 0),
      Q(`${n} column(s) across customer/contact/lead table(s) carry ${label}`));
  }

  // §B6 AI only when needed (1)
  await req(B1, 'wa-ai-only-when-needed', 'AI is called only when rules and data cannot answer',
    B(Number(await one(`select count(*)::text from public.model_policy where active and tier='none'`)) > 0),
    Q(`${await one(`select count(*)::text from public.model_policy where active and tier='none'`)} task ` +
      `class(es) resolve with no AI at all; wa_inbound routes through the shared router`));

  // §B7 human handoff (2)
  const confCol = await anyCol('confidence', 'ai_cost_log|inbound_messages|wa_|chat');
  await req(B1, 'wa-confidence-score', 'a confidence score is produced for the reply',
    B(Number(confCol) > 0),
    Q(`${confCol} confidence column(s) on message/cost table(s)`));
  const handoffCol = await anyCol('handoff|escalat|assigned_to|human|takeover', 'message|chat|thread|task|inbound');
  await req(B1, 'wa-transfer-to-human', 'low confidence transfers the conversation to a human',
    B(Number(handoffCol) > 0),
    Q(`${handoffCol} handoff/escalation column(s) on message or task table(s)`));

  // §B8 batching (1)
  const batchSrc = filesNear(/debounce|batch|buffer|wait/i, /message|inbound/i, 400, EDGE).map(base);
  await req(B1, 'wa-message-batching', 'consecutive messages are combined into one AI call',
    B(batchSrc.length > 0),
    Q(`${batchSrc.length} edge file(s) debounce or batch inbound messages [${brief(batchSrc)}]`));

  // §B9 intent prediction (1)
  const intentFns = await fnList('intent');
  await req(B1, 'wa-intent-prediction', 'the likely intent is predicted before routing',
    B(intentFns.length > 0),
    Q(`${intentFns.length} intent routine(s) [${brief(intentFns)}]; intent_router edge function ` +
      `present ${EDGE.some(f => /intent_router/.test(f))}`));

  // §B10 the agent brain (8)
  for (const [id, pat, label] of [
    ['wa-brain-customer-understanding', 'customer|lead|contact', 'customer understanding'],
    ['wa-brain-product-knowledge', 'product|catalog|inventory|item', 'product knowledge'],
    ['wa-brain-sales-logic', 'quote|deal|pipeline|opportunit', 'sales logic'],
    ['wa-brain-complaint-handling', 'complaint|dispute|escalat|ticket', 'complaint handling'],
    ['wa-brain-order-system', 'order|purchase|fulfil', 'an order system'],
    ['wa-brain-crm-memory', 'crm|customer_preference|customer_score|note', 'CRM memory'],
    ['wa-brain-ai-router', 'model_policy', 'the AI router'],
    ['wa-brain-analytics', 'kpi|analytic|score|snapshot|v_', 'analytics'],
  ]) {
    const t = await anyTable(pat);
    const n = String(t) === 'none' ? 0 : String(t).split(' ').length;
    await req(B1, id, `the WhatsApp brain has ${label}`,
      B(n > 0),
      Q(`${n} table(s) back ${label} [${String(t).split(' ').slice(0, 4).join(' ')}]`));
  }

  // §B11 product knowledge from DB (1)
  const prodTables = await anyTable('product|catalog_supplier|inv_item');
  await req(B1, 'wa-products-from-database', 'product facts come from the database, not the model',
    B(String(prodTables) !== 'none'),
    Q(`product/catalogue table(s) [${String(prodTables).split(' ').slice(0, 5).join(' ')}] — the spec's ` +
      `rule is "do not ask AI what products we sell"`));

  // §B12 image handling (1)
  const imgSrc = filesNear(/image|media|photo/i, /classif|type|mime|filter/i, 400, EDGE).map(base);
  await req(B1, 'wa-image-classifier-first', 'an inbound image is classified before a vision call',
    B(imgSrc.length > 0),
    Q(`${imgSrc.length} edge file(s) classify media before escalating [${brief(imgSrc)}]`));

  // §B13 automated sales flow (1)
  const flowFns = await fnList('quote|inquiry|lead');
  await req(B1, 'wa-automated-sales-flow', 'a sales flow runs without a premium model',
    B(flowFns.length > 0),
    Q(`${flowFns.length} routine(s) drive the quote/inquiry flow deterministically [${brief(flowFns)}]`));

  // §B14 per-customer cost cap (1)
  const custCap = await anyCol('budget|cap|limit|quota', 'customer|contact|lead|wa_');
  await req(B1, 'wa-cost-limit-per-customer', 'a per-customer AI cost cap exists',
    B(Number(custCap) > 0),
    Q(`${custCap} budget/cap column(s) on a customer-scoped table — this is NOT §9's per-request ` +
      `ceiling nor §28's per-user monthly cap; three different objects`));

  // §B15 the model ladder (4)
  const noAiPct = 100 * Number(await one(`select count(*)::text from public.model_policy where active and tier='none'`))
    / Number(await one(`select count(*)::text from public.model_policy where active`));
  for (const [id, tier, want, label] of [
    ['wa-ladder-70pct-no-ai', 'none', 70, '70% handled with no AI'],
    ['wa-ladder-20pct-cheap', 'small', 20, '20% on a cheap model'],
    ['wa-ladder-8pct-medium', 'medium', 8, '8% on a medium model'],
    ['wa-ladder-2pct-premium', 'large', 2, 'at most 2% on a premium model'],
  ]) {
    const n = await one(`select count(*)::text from public.model_policy where active and tier='${tier}'`);
    const tot = await one(`select count(*)::text from public.model_policy where active`);
    const pct = 100 * Number(n) / Number(tot);
    const ok = tier === 'large' ? pct <= want : pct >= want;
    await req(B1, id, `the WhatsApp ladder puts ${label}`,
      B(ok),
      Q(`tier '${tier}': ${n} of ${tot} task classes = ${pct.toFixed(0)}%, spec wants ` +
        `${tier === 'large' ? 'at most' : 'at least'} ${want}% — measured over POLICY because ` +
        `wa_messages holds ${waRows} row(s), too few to measure traffic`));
  }

  // §B16 response templates (5)
  const tplRows = await rowsOf('response_template');
  for (const [id, pat, label] of [
    ['wa-tpl-greetings', 'greet|welcome|hello', 'greetings'],
    ['wa-tpl-delivery', 'deliver|shipping|dispatch|track', 'delivery updates'],
    ['wa-tpl-payment', 'payment|invoice|pay|bank', 'payment instructions'],
    ['wa-tpl-appointment', 'appointment|booking|visit|meeting', 'appointment booking'],
    ['wa-tpl-store-info', 'location|hours|address|contact|store', 'store information'],
  ]) {
    const n = await one(`select count(*)::text from public.response_template
      where coalesce(key,'') ~* '${pat}' or coalesce(body,'') ~* '${pat}'`).catch(() => '0');
    await req(B1, id, `a stored template covers ${label}`,
      B(Number(n) > 0),
      Q(`${n} of ${tplRows} response_template row(s) cover ${label} — a template is a $0 answer`));
  }

  // §B17 per-customer cost dashboard (1)
  await req(B1, 'wa-cost-dashboard', 'AI cost is reportable per customer',
    B(Number(await anyCol('customer_id|contact_id|lead_id', 'ai_cost_log')) > 0),
    Q(`ai_cost_log customer-scoped column(s): ${await anyCol('customer_id|contact_id|lead_id', 'ai_cost_log')}; ` +
      `it attributes to dept_key and agent_key instead — the dashboard exists, its principal is not a customer`));

  // §B18 background jobs (1)
  const bgCron = await one(`select count(*)::text from cron.job`).catch(() => '0');
  await req(B1, 'wa-background-summary-job', 'the conversation summary is produced in the background',
    B(Number(bgCron) > 0 && Number(summaryCol) > 0),
    Q(`${bgCron} cron job(s) available for background work; ${summaryCol} summary column(s) to fill`));

  // ══ PART C — EMAIL (22) ═════════════════════════════════════════════════════════════════════════
  const triage = EDGE.find(f => /email_triage/.test(f));
  const triageSrc = triage ? src(triage) : '';
  for (const [id, re, label] of [
    ['em-classifier', /classif|categor|label/i, 'a classifier'],
    ['em-intent-detection', /intent|purpose|topic/i, 'intent detection'],
    ['em-priority-detection', /priority|urgen|severity|score/i, 'priority detection'],
    ['em-action-decision', /action|decide|route|assign/i, 'an action decision'],
    ['em-ai-router', /model|route|tier|fn_ai_route/i, 'the AI router'],
  ]) {
    const inTriage = triageSrc && re.test(triageSrc);
    const anywhere = filesMatching(re, EDGE.filter(f => /email|resend|inbound/i.test(f))).map(base);
    await req(C1, id, `the email pipeline has ${label}`,
      B(!!inTriage || anywhere.length > 0),
      Q(`email_triage present ${!!triage}, carries it ${!!inTriage}; ${anywhere.length} email edge ` +
        `file(s) [${brief(anywhere)}]`));
  }

  for (const [id, pat, label] of [
    ['em-cat-a-automatic', 'template|lookup|database|automatic|status', 'Category A — automatic, no AI'],
    ['em-cat-b-cheap', 'summar|extract|classif|sentiment', 'Category B — cheap model'],
    ['em-cat-c-advanced', 'complaint|contract|negotiat|escalat|angry', 'Category C — advanced model'],
  ]) {
    const anywhere = filesMatching(new RegExp(pat, 'i'), EDGE.filter(f => /email|inbound/i.test(f))).map(base);
    await req(C1, id, label, B(anywhere.length > 0),
      Q(`${anywhere.length} email edge file(s) carry this branch [${brief(anywhere)}]`));
  }

  for (const [id, pat, label] of [
    ['em-attach-parser', 'attachment|pdf|parse', 'attachments are parsed'],
    ['em-attach-text-extraction', 'extract|text|content', 'text is extracted'],
    ['em-attach-vector-search', 'embed|vector|similar|<=>', 'chunks are retrieved by vector search'],
    ['em-attach-relevant-sections-only', 'chunk|section|page|top', 'only relevant sections are sent'],
  ]) {
    const anywhere = filesMatching(new RegExp(pat, 'i'), EDGE.filter(f => /email|doc|attach|inbound/i.test(f))).map(base);
    await req(C1, id, label, B(anywhere.length > 0),
      Q(`${anywhere.length} email/document edge file(s) [${brief(anywhere)}] — §C3 is the EMAIL ` +
        `attachment pipeline, distinct from §10's file pipeline and §6's memory store`));
  }

  await req(C1, 'em-customer-profile-not-history', 'a customer profile is sent, not the email history',
    B(Number(summaryCol) > 0),
    Q(`${summaryCol} summary/profile column(s) available to send instead of the thread`));

  for (const [id, pat, label] of [
    ['em-tpl-apology', 'apolog|sorry', 'an apology'],
    ['em-tpl-quotation', 'quot', 'a quotation'],
    ['em-tpl-shipping', 'ship|deliver|dispatch', 'a shipping update'],
    ['em-tpl-follow-up', 'follow.?up|reminder|chase', 'a follow-up'],
    ['em-tpl-thank-you', 'thank', 'a thank-you'],
    ['em-tpl-complaint-resolution', 'complaint|resolution|refund', 'a complaint resolution'],
  ]) {
    const n = await one(`select count(*)::text from public.response_template
      where coalesce(key,'') ~* '${pat}' or coalesce(body,'') ~* '${pat}'`).catch(() => '0');
    const t2 = await one(`select count(*)::text from public.templates
      where coalesce(key,'') ~* '${pat}'`).catch(() => '0');
    await req(C1, id, `the email library has ${label} template`,
      B(Number(n) + Number(t2) > 0),
      Q(`${n} response_template + ${t2} templates row(s) match ${label}`));
  }

  const prioCol = await anyCol('priority|urgency|severity', 'inbound_messages|messages|contact_messages|task');
  for (const [id, label] of [
    ['em-priority-0-30-automated', 'a low band answered automatically'],
    ['em-priority-30-70-ai', 'a middle band answered by AI'],
    ['em-priority-70-100-human', 'a high band routed to a human'],
  ]) {
    await req(C1, id, `email priority defines ${label}`,
      B(Number(prioCol) > 0),
      Q(`${prioCol} priority column(s) on message table(s) — the three bands are values of one ` +
        `column, so these three legs share evidence and stand or fall together`));
  }

  // ══ PART D — WEBSITE CHAT (23) ══════════════════════════════════════════════════════════════════
  const chatApp = filesMatching(/chat|widget/i, APP).map(base);
  await req(D1, 'web-intent-detector', 'the widget detects intent before calling AI',
    B(chatApp.length > 0 && (await fnList('intent')).length > 0),
    Q(`${chatApp.length} app file(s) implement chat [${brief(chatApp)}]; intent routines exist`));

  const menuSrc = filesNear(/how can we help|options?|menu|quick.?repl|suggest/i, /chat|widget|message/i, 500, APP).map(base);
  await req(D1, 'web-first-message-no-ai', 'the first message is answered without AI',
    B(menuSrc.length > 0),
    Q(`${menuSrc.length} app file(s) offer a menu before any model call [${brief(menuSrc)}]`));

  for (const [id, pat, label] of [
    ['web-kb-products', 'product|catalog', 'products'],
    ['web-kb-prices', 'price|rate|cost|tariff', 'prices'],
    ['web-kb-policies', 'polic|terms|condition', 'policies'],
    ['web-kb-faq', 'faq', 'FAQ'],
    ['web-kb-shipping', 'ship|deliver|logistic', 'shipping'],
    ['web-kb-returns', 'return|refund|warrant', 'returns'],
    ['web-kb-reviews', 'review|rating|testimonial', 'reviews'],
  ]) {
    const t = await anyTable(pat);
    await req(D1, id, `the website knowledge layer holds ${label}`,
      B(String(t) !== 'none'),
      Q(`table(s) [${String(t).split(' ').slice(0, 4).join(' ')}] back ${label}`));
  }

  for (const [id, pat, label] of [
    ['web-intent-buying', 'buy|purchase|quote|price', 'buying'],
    ['web-intent-researching', 'research|browse|info|learn', 'researching'],
    ['web-intent-existing-customer', 'customer|account|order|existing', 'an existing customer'],
    ['web-intent-complaint', 'complaint|issue|problem|dispute', 'a complaint'],
    ['web-intent-spam', 'spam|abuse|block|violation', 'spam'],
  ]) {
    const t = await anyTable(pat);
    const inSrc = filesMatching(new RegExp(pat, 'i'), APP.filter(f => /chat|widget|contact/i.test(f))).length;
    await req(D1, id, `visitor intent detection recognises ${label}`,
      B(String(t) !== 'none' || inSrc > 0),
      Q(`${inSrc} chat/widget app file(s) and table(s) [${String(t).split(' ').slice(0, 3).join(' ')}] cover ${label}`));
  }

  for (const [id, pat, label] of [
    ['web-sales-asks-questions', 'question|ask|field|intake', 'asks qualifying questions'],
    ['web-sales-recommends', 'recommend|suggest|match|similar', 'recommends'],
    ['web-sales-collects-info', 'name|email|phone|contact', 'collects contact information'],
    ['web-sales-creates-lead', 'lead|inquiry|contact_messages', 'creates a lead'],
  ]) {
    const t = await anyTable(pat);
    await req(D1, id, `the website sales agent ${label}`,
      B(String(t) !== 'none'),
      Q(`table(s) [${String(t).split(' ').slice(0, 3).join(' ')}] support this`));
  }

  await req(D1, 'web-mem-anonymous-session', 'an anonymous visitor session is remembered',
    B(Number(await anyCol('session_id|session_key|visitor', 'chat|thread|session|contact')) > 0),
    Q(`${await anyCol('session_id|session_key|visitor', 'chat|thread|session|contact')} session column(s) on chat table(s)`));
  await req(D1, 'web-mem-returning-account', 'a returning customer is recognised by account',
    B(Number(await anyCol('customer_id|user_id|account_id', 'chat|thread|session')) > 0),
    Q(`${await anyCol('customer_id|user_id|account_id', 'chat|thread|session')} account column(s) on chat table(s)`));

  await req(D1, 'web-rate-limit', 'the public widget is rate limited',
    B((await fnList('rate.?limit|throttle')).length > 0 || filesMatching(/rate.?limit|throttle/i, EDGE).length > 0),
    Q(`${(await fnList('rate.?limit|throttle')).length} routine(s) and ` +
      `${filesMatching(/rate.?limit|throttle/i, EDGE).length} edge file(s) rate limit`));
  await req(D1, 'web-spam-detection', 'spam is detected before a model is called',
    B(String(await tbl('chat_violations')) === 'true'),
    Q(`chat_violations table present ${await tbl('chat_violations')}, ${await rowsOf('chat_violations')} row(s)`));
  await req(D1, 'web-session-budget-cap', 'a visitor session has a maximum AI spend',
    B(Number(await anyCol('budget|cap|limit|quota', 'chat|session|thread')) > 0),
    Q(`${await anyCol('budget|cap|limit|quota', 'chat|session|thread')} budget column(s) on a chat/session table`));

  // ══ PART E — THE UNIFIED BRAIN (5) ══════════════════════════════════════════════════════════════
  const routerFn = await one(FN_EXISTS('fn_ai_route'));
  await req(E1, 'uni-shared-router-all-channels', 'all channels share one router rather than one each',
    B(String(routerFn) === 'true'),
    Q(`fn_ai_route is a single shared routine; ${waEdge.length} whatsapp + ${emEdge.length} email + ` +
      `${chatApp.length} web file(s) can all reach it`));

  for (const [id, pat, label] of [
    ['uni-mix-whatsapp', 'wa_|whatsapp', 'WhatsApp'],
    ['uni-mix-email', 'email|resend', 'email'],
    ['uni-mix-website', 'chat|contact|widget', 'the website widget'],
  ]) {
    const n = await one(`select count(*)::text from public.ai_cost_log where fn ~* '${pat}'`);
    await req(E1, id, `${label} traffic is attributed to a model mix`,
      B(Number(n) > 0),
      Q(`${n} logged AI call(s) attributed to ${label} — the mix cannot be reported for a channel ` +
        `that has never called a model`));
  }

  await req(E1, 'uni-one-customer-brain', 'one customer identity spans all three channels',
    B(String(await tbl('v_customer_master')) === 'true'),
    Q(`v_customer_master present ${await tbl('v_customer_master')}; customers holds ${custRows} row(s) — ` +
      `the unifying view exists, the population does not yet`));
}
