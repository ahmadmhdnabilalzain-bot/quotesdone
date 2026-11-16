// sales_engineer — support_rating_due, support_rating, assist_history, reask_turns, assist.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { replyLanguageProblems, turnLang } from '../../_shared/chat_answers.ts';
import { acceptImages } from '../../_shared/chat_images.ts';
import { recallCases, recallTrace } from '../../_shared/case_recall.ts';
import { accountKey, clientHistory, fitHistory, openConversation } from '../../_shared/chat_history.ts';
import { answerFromBrief } from '../../_shared/brief_answer.ts';
import { allowedNumbers, companyBrief, figureSource, warmBrief } from '../../_shared/company_brief.ts';
import { aiSystem, replyProblems } from '../../_shared/ai_reply.ts';
import { guardSupportReply } from '../../_shared/support_reply_guard.ts';
import { preRevealIdentities } from '../../_shared/pre_reveal_identities.ts';
import { PORTAL_TURN_MS, portalRules, portalFacts, wrappedReply, plainLanguage, customerSafe } from '../portal_turn.ts';
import { heldBlock, heldState, replyFilter } from '../portal_conversation.ts';
import { EXTRACT_BY_MS, episodeStart, extractSlots, isQuestion, isUnsure, planState, sentencesOf, targets } from '../conversation_plan.ts';
import { capRule, capStage, dialectOf, mergeState, portalKey, readState, registerPatch, statusOfStage } from '../../_shared/inquiry_state.ts';
import { ADVISE_RULE, heldProblem, problemsFor, solutionsBlock, solutionStateText } from '../../_shared/solution_catalogue.ts';
import { taxonomyOf, tradeBlock, tradeContext } from '../../_shared/inquiry_trades.ts';
import { gatewayAsk, readInquiry, readingPatch } from '../../_shared/inquiry_reading.ts';
import { handOffAtCap } from '../lib/inquiry_cap.ts';
import { checkReadability } from '../../_shared/readability.ts';
import { REASK_CLAIM, reaskDue } from '../../_shared/reask.ts';
import { admin, J, sec, EMITTERS, type ActionCtx } from '../context.ts';
import { embed } from '../lib/embed.ts';
import { answerFromOwnQuotes } from '../lib/own_quotes.ts';
import { run } from '../lib/run.ts';
import { conversationEffort } from '../../_shared/effort_policy.ts';
import { lastTurn, replayOf } from '../../_shared/turn_replay.ts';
import { hashedKey, registerComplaint } from '../../_shared/complaint_register.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { loadCaseContext, recordCaseExchange } from '../../_shared/case_context.ts';

export async function portalActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, body, caller, action } = c;
    // The customer portal asks for and records the rating of a closed support case here (CSAT 1-5, CES 1-7):
    // the portal is the sales engineer's, so it never calls Support's widget. The asker's questions in 'assist'
    // reach their support case through the assistant_logs row it writes (path 'portal').
    if (action === 'support_rating_due') {
      if (caller?.kind !== 'customer') return J({ error: 'forbidden' }, 403);
      const { data, error } = await admin.rpc('fn_support_rating_due', { p_party_kind: 'customer', p_party_id: caller.customerId });
      return error ? J({ error: 'rating_due_failed' }, 400) : J({ ok: true, due: data || [] });
    }
    if (action === 'support_rating') {
      if (caller?.kind !== 'customer') return J({ error: 'forbidden' }, 403);
      const { data, error } = await admin.rpc('fn_support_portal_rate', {
        p_party_kind: 'customer', p_party_id: caller.customerId, p_case_ref: String(body.case_ref || ''),
        p_csat: body.csat == null ? null : Number(body.csat), p_ces: body.ces == null ? null : Number(body.ces),
        p_comment: body.comment ? String(body.comment).slice(0, 2000) : null });
      return error ? J({ error: 'rating_failed' }, 400) : J(data);
    }

    // THE PORTAL CHAT IS REDRAWN FROM THE DATABASE (ruling 1255): every turn of the customer's one conversation, including
    // what they said on the website widget before signing up (widget_conv, adopted into the account here).
    if (action === 'assist_history') {
      const acct = caller.kind === 'customer' ? accountKey('customer', caller.customerId) : '';
      if (!acct) return J({ turns: [] });
      const c = await openConversation(admin, { account: acct, visitorConv: body.widget_conv, adopt: body.adopt === true });   // the portal sends adopt once, right after sign-in
      // THE TURNS STILL OWED AN ANSWER (_shared/reask.ts): the portal shows "still working on your answer" for 'working' and
      // "with your sales engineer" for 'with_team' until the reply fills the row. UI state, never a turn of the conversation.
      const { data: owedRows } = await admin.from('assistant_logs').select('id,message,path,created_at').eq('conv_id', acct).is('reply', null)
        .in('path', ['portal:pending', 'portal:with_team']).order('id', { ascending: false }).limit(5);
      const waiting = (owedRows ?? []).map((w: { id: number; message: string | null; path: string; created_at: string }) =>
        ({ id: w.id, message: w.message ?? '', state: w.path === 'portal:with_team' ? 'with_team' : 'working', since: w.created_at }));
      return J({ turns: c.turns ?? [], adopted: c.adopted, pending: !!c.pending, waiting });
    }
    // THE ASYNCHRONOUS RE-ASK (_shared/reask.ts): called by pg_cron (fn_reask_kick, every minute, only when a turn is due)
    // with this seat's own credential. Refused turns of the portal, WhatsApp and the supplier quotation thread are asked
    // again and delivered into their own conversation; a turn refused REASK_MAX_ATTEMPTS times is handed to its seat.
    if (action === 'reask_turns') {
      if (caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const res = await reaskDue(admin, { limit: Math.max(1, Math.min(REASK_CLAIM, Number(body.limit) || REASK_CLAIM)) });
      await run('reask_turns', res.ok === false ? 'error' : 'ok', { claimed: res.claimed ?? 0, rows: res.rows ?? null }, res.ok === false ? String(res.error) : undefined);
      return J(res);
    }
    if (action === 'assist') {
      // ── ONE TURN, ON A CLOCK (customer_support owns the conversation, it_engineer the latency; 27 Oct 2026) ──
      // MEASURED BEFORE (production, ZZ DEMO wardrobe replay 27 Oct 07:41-08:13Z, agent_runs fn:sales_engineer + ai_cost_log):
      // every turn took 58-150 s and turn 7 hit the 150 s edge wall as a 504, so the portal printed its error line. Per
      // turn the old road made 3-5 SERIAL model calls on gpt-6-luna-pro: a planning call (routine_employee_reasoning,
      // 18-31 s, ~22k prompt tokens), the answer (customer_communication, 13-48 s, 35-62k prompt tokens and growing with
      // every turn because the plan's per-step retrieval and the whole transcript rode in one payload), on 4 of 14 turns an
      // independent check plus a corrective rewrite (+40 s), on 8 of 14 a plain-language rewrite (16-35 s), and none of it
      // bounded. supportReply/think was built for deliberate seat decisions, not a chat turn.
      // NOW the turn is answered exactly as the website widget already answers a signed-in customer (rulings 1195/1196,
      // 1219): ONE streamed model call, class customer_portal_assistant (claude-sonnet-5.5, gpt-6-luna-pro behind it; no new
      // model, no routing change), given the company brief, this seat's retrieved records and the customer's own quotes as
      // facts, every sentence checked before it is shown, a failed check rewritten by the model, and the whole ladder inside
      // PORTAL_TURN_MS (portal_turn.ts). The reads before the call run side by side, not one after another.
      const t0 = Date.now(); const T: Record<string, number> = {}; const lap = (k: string) => { T[k] = Date.now() - t0; };
      const deadline = t0 + PORTAL_TURN_MS;
      const message = String(body.message || '').trim();
      if (!message) return J({ error: 'message_required' }, 400);
      const lang = turnLang(message, String(body.lang || ''), clientHistory(body.history));   // a mixed message keeps the conversation's language (3 Nov 2026)
      // THE WHOLE CONVERSATION (_shared/chat_history.ts, 18 Oct 2026). PortalShell always sent its history and this
      // handler never read it: every portal turn reached the model alone, so on 14 Oct the founder's 2 m x 1.2 m wardrobe
      // was asked for again one turn later (assistant_logs 3695). Every turn is stored under conv_id, scoped to the
      // caller the session resolved (never the body), and read back whole; the browser's copy only fills the first turn.
      // ruling 1255: ONE conversation per customer (the same key the widget writes when they are signed in), and the
      // visitor chat from before sign-up was adopted into it by assist_history (adopt flag), never here.
      const acct = caller.kind === 'customer' ? accountKey('customer', caller.customerId) : '';
      // A MESSAGE SENT TWICE IN A ROW IS ANSWERED ONCE (ruling 1631, _shared/turn_replay.ts): assistant_logs 4875 was the same
      // portal message 1 s after the first, answered again by a second model call. The stored answer is returned; nothing is stored.
      if (acct) {
        const again = replayOf(await lastTurn(admin, acct), message);
        if (again) return J({ ok: true, seat: 'sales_engineer', answered: true, reply: again.reply, replayed: true, basis: 'the answer already given to this same message' });
      }
      const pConvo = acct ? openConversation(admin, { account: acct }) : Promise.resolve({ key: '', turns: null, adopted: 0 });
      const rpc = async (f: string, args: Record<string, unknown>) => { const x = await admin.rpc(f, args); return { data: x.data, error: x.error }; };
      const pKey = sec('cred_fn_sales_engineer');
      // the conversation as stored (or, on its first turn, as the browser sent it), read once for the plan and the answer
      const pTurns = pConvo.then((c) => {
        const tr = c.turns && c.turns.length ? c.turns : clientHistory(body.history).filter((h, i, a) => !(i === a.length - 1 && h.role === 'user' && h.content === message));
        return tr.map((t) => ({ role: t.role === 'assistant' ? 'assistant' as const : 'user' as const, content: t.content }));
      });
      // ONE TRADE PACK (company_brief.ts, 3 Nov 2026): the trade of THIS job's plan (conversation_plan.ts), so the pack is the
      // playbook the plan's state block speaks of; the live reads start now, before the conversation is read (warmBrief)
      warmBrief(rpc);
      const pBrief = pTurns.then((tr) => companyBrief(rpc, [], '', lang, [], undefined, { trade: planState(tr, message).plan?.key ?? null }));
      // WHAT THE DETECTORS CANNOT READ (conversation_plan.ts, 27 Oct 2026): in a job conversation with must-haves still
      // open, a bounded json_extraction call reads the message beside the retrieval below, never past EXTRACT_BY_MS
      const pExtract = Promise.all([pTurns, pKey]).then(([tr, k]) => k ? extractSlots({ gateway: Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', secret: k,
        st: planState(tr, message), lastSeat: [...tr].reverse().find((t) => t.role === 'assistant')?.content ?? '', message, deadline: t0 + EXTRACT_BY_MS }) : null)
        .catch(() => null);
      // ── THE EXPERT'S HALF (10 Nov 2026, sales_engineer; founder ledger 1572, 1579, 1586) ──────────────────────────────
      // This job's state (its episode's row of public.inquiry_state: the trades it is placed in, the options already put
      // and the one chosen), the whole taxonomy, and the packs of the job's trades (the state's taxonomy codes, else the
      // plan's slug resolved through fn_taxonomy_trades_for as dispatch resolves it). All read beside everything else.
      const pState = acct ? pTurns.then((tr) => readState(admin, portalKey(acct, episodeStart([...tr, { role: 'user' as const, content: message }])))).catch(() => null) : Promise.resolve(null);
      const pTax = taxonomyOf(admin);
      const pCtx = Promise.all([pState, pTurns, pTax]).then(async ([st0, tr, tax]) => {
        const slug = planState(tr, message).plan?.key ?? null;
        let codes = st0?.trade_codes ?? [];
        if (!codes.length && slug) { const { data } = await admin.rpc('fn_taxonomy_trades_for', { p_slugs: [slug] }); codes = Array.isArray(data) ? data.map(String) : []; }
        return { slug, ctx: await tradeContext(admin, codes, lang, tax) };
      }).catch(() => ({ slug: null as string | null, ctx: null }));
      // THE STATE READER (_shared/inquiry_reading.ts): one bounded json_extraction call that reads which trades this job is,
      // what our last reply offered and what this message chose, for the state the NEXT turn reads. Never awaited by the reply.
      const pReading = Promise.all([pTurns, pTax, pCtx, pState, pKey]).then(([tr, tax, c, st0, k]) => {
        if (!k || !tax || caller.kind !== 'customer') return null;
        const problems = problemsFor({ slug: c.slug, codes: c.ctx?.codes ?? [], held: heldProblem(st0) });
        return readInquiry(gatewayAsk({ gateway: Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', secret: k, fn: 'sales_engineer', agent: 'sales_engineer' }),
          { taxonomy: tax, problems, services: c.ctx?.services, lastSeat: [...tr].reverse().find((t) => t.role === 'assistant')?.content ?? '', message, heldCodes: st0?.trade_codes ?? [] },
          t0 + PORTAL_TURN_MS - 5_000);
      }).catch(() => null);

      // ── A QUESTION ABOUT THE CUSTOMER'S OWN QUOTE IS ANSWERED FROM THAT QUOTE (21 Sep 2026) ──
      // No corpus holds this customer's quote; the quotes table does. Their quotes, scoped in SQL to inquiries.customer_id =
      // the resolved session, are given to the model as facts (portal_turn.portalFacts). The supplier is named only where a
      // transactions row proves the reveal was paid; before that it is the same "Supplier A" letter the compare table prints.
      const pOwn = caller.kind === 'customer' ? answerFromOwnQuotes(caller.customerId, message, lang) : Promise.resolve(null);
      // the suppliers on their jobs not yet revealed to them: a reply naming one is refused (pre_reveal_identities.ts)
      const pForbidden = caller.kind === 'customer' ? preRevealIdentities(admin, { customerId: String(caller.customerId) }) : Promise.resolve([] as string[]);

      // THE EMBEDDING IS BOUNDED. Measured 21 Sep 2026: fn_sales_assist answers in 0.09 s without a
      // vector; the audit's >2 min portal reply was the in-function gte-small session warming up.
      // A vector adds recall only for rows that ALSO corroborate lexically, so 1.5 s is all it gets;
      // past that the lexical routes answer alone rather than the customer waiting.
      const vec = await Promise.race([embed(message), new Promise<null>((r) => setTimeout(() => r(null), 1500))]);
      lap('embed');
      // PAST CASES BEFORE THE ANSWER (23 Sep 2026): has this seat met this question before, and how did it end? The same
      // vector, so no second embedding. Recorded on the judgement only: a past case's text never enters a customer prompt.
      // fn_sales_assist reads the seat's seven corpora, records what it retrieved, and files the gap when nothing clears.
      const [memory, assisted] = await Promise.all([
        recallCases(admin, { seat: 'sales_engineer', path: 'assist', situation: message, embedding: vec }),
        admin.rpc('fn_sales_assist', {
          p_text: message, p_embedding: vec,
          p_min_similarity: Number(body.min_similarity ?? 0.86),
          p_min_rank: Number(body.min_rank ?? 0.05),
          p_k: Number(body.k ?? 5),
          p_actor: 'sales_engineer',
        }),
      ]);
      const { data, error } = assisted;
      if (error) return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);
      const r = data as Record<string, unknown>;
      // NOTHING INTERNAL OR UNVERIFIED REACHES A CUSTOMER (#1567/#1569, the 7 Oct stating rule; independent review of #1640,
      // 27 Oct 2026). fn_sales_assist reads sales_knowledge, ops_knowledge, agent_knowledge, support_knowledge and kb_chunks
      // without the audience and eligibility rules fn_reason_retrieve applies; a record's text would ride in the facts AND
      // make its figures "known" to the figure check. portal_turn.customerSafe drops them here, before the call, and fails
      // closed (a failed lookup withholds that corpus's every record; a corpus with no rule is withheld unless it is named
      // in PASS_THROUGH). The rules and the 27 Oct counts are in portal_turn.ts.
      const all = await customerSafe((r.records || []) as Array<Record<string, unknown>>, async (rule, ids) => {
        const x = await admin.from(rule.table).select(rule.select).in(rule.key, ids);
        return { data: x.data as Record<string, unknown>[] | null, error: x.error };
      });
      const [own, convo, brief, key, turns, extract, forbidden, stE, ce] = await Promise.all([pOwn, pConvo, pBrief, pKey, pTurns, pExtract, pForbidden, pState, pCtx]);
      lap('reads');
      const ownQuote = own?.facts ?? null;
      const convKey = convo.key;
      // ── THE INQUIRY'S STATE AND ITS 100-MESSAGE LIMIT (10 Nov 2026, founder ledger 1572; _shared/inquiry_state.ts) ──
      // One conversation per customer holds many jobs (ruling 1255); the job from its episode start (after the last confirmed
      // summary, conversation_plan.episodeStart) is one inquiry, and every message of it counts, theirs and ours. Code decides
      // the stage of THIS reply: from 80 only the missing must-haves, from 95 the summary, at 100 the hand-off to the sales
      // engineer (the request is written for them, lib/inquiry_cap.ts), past 100 nothing is sent.
      const job = [...turns, { role: 'user' as const, content: message }];
      const from = episodeStart(job);
      const replyNo = job.length - from + 1;
      const stage = capStage(replyNo);
      const episodeKey = acct ? portalKey(acct, from) : '';
      const theirs = job.slice(from).filter((t) => t.role === 'user').map((t) => t.content);
      const dialect = dialectOf(theirs)?.dialect ?? null;
      const atCap = (category: string | null, open: string[]) => caller.kind === 'customer' && episodeKey
        ? handOffAtCap(admin, { customerId: String(caller.customerId), episodeKey, transcript: job, from, category, open }) : Promise.resolve(null);
      if (stage === 'over') {
        // MESSAGE 101 IS NEVER SENT: the question is kept on the conversation, marked as with the sales engineer (the portal
        // shows "with your sales engineer", UI state), and the hand-off is made sure of. No model is called.
        const st0 = planState(turns, message);
        const h = await atCap(st0.plan?.key ?? null, st0.open);
        try { await admin.from('assistant_logs').insert({ message, reply: null, seat: 'sales_engineer', answered: false, ...(convKey ? { conv_id: convKey } : {}),
          audience: caller.kind === 'customer' ? 'customer:' + caller.customerId : caller.kind, path: 'portal:with_team' }); } catch { /* the hand-off stands */ }
        if (episodeKey) await mergeState(admin, episodeKey, 'portal_assistant', { turn: theirs.length, message_count: replyNo - 1, status: 'handed_off' });
        await run('assist', 'ok', { answered: false, capped: true, reply_no: replyNo, handoff: h, ms: T });
        return J({ ok: false, seat: 'sales_engineer', answered: false, error: 'no_answer', outage: false, pending: true, capped: true, held_id: h?.handoffId ?? null }, 503);
      }
      // the facts change per turn, so they ride with the message, after the cached brief, rules and earlier turns
      const facts = portalFacts({ facts: ownQuote ? 'THEIR OWN REQUESTS AND QUOTES (scoped in SQL to this customer; this IS what you can see of their account):\n' + ownQuote : '', passages: all });
      const sys = '\n\n' + aiSystem({ seat: 'sales_engineer', channel: 'the signed-in customer portal', audience: 'customer', lang, message, rules: portalRules(), plainText: true, dialect }, lang);
      const allowed = figureSource(brief) + '\n' + facts + '\n' + sys;
      const known = allowedNumbers(brief, facts, sys);   // the brief's figures read once per brief (company_brief.ts, 11 Nov 2026 load test)
      // a photo or drawing the customer sent (ruling 1200): only what chat_images accepts reaches the model
      const images = acceptImages(body.images, new URL(Deno.env.get('SUPABASE_URL')!).host).images;
      const past = fitHistory(turns, message);
      // WHAT THE CONVERSATION ALREADY HOLDS (portal_conversation.ts; 27 Oct 2026, the bank's re-asks and unasked lines): read
      // from the whole stored conversation, not the fitted window, shown to the model as "do not ask again", and enforced
      // sentence by sentence after it (replyFilter: a re-ask or an unasked line is dropped, never shown).
      // and since 27 Oct evening, the plan's state (conversation_plan.ts): what code asks next, or the summary
      const held = heldState(turns, message, extract?.slots ?? null, stage);
      // a job plan states the stage's rule in its own block (conversation_plan.stateBlock); a conversation with no plan gets it here
      const known_ = [heldBlock(held), held.plan.plan ? '' : capRule(stage, replyNo)].filter(Boolean).join('\n\n');
      // A JOB CONVERSATION IS THE EXPERT INTERVIEW (ledger 1572/1586): the ADVISE rule, the solution so far, the job's trades
      // (services, what a supplier needs stated, authority, location rules) and the reference options for its trade, never
      // chosen by the customer's words (ruling 890). It runs on the interview class, inquiry_qualification_conversation (the
      // T3 interview class; which model that is, is model_policy's). Outside a job the portal assistant's class answers.
      const refProblems = problemsFor({ slug: ce.slug, codes: ce.ctx?.codes ?? [], held: heldProblem(stE) });
      const jobTalk = !!(held.plan.plan || ce.ctx?.codes.length || refProblems.length || stE?.options_offered?.length);
      // the ADVISE rule rides on every customer turn (a first message about a bus rental has no plan and no trade yet)
      const expert = caller.kind !== 'customer' ? '' : jobTalk ? [ADVISE_RULE, solutionStateText(stE, lang), tradeBlock(ce.ctx, lang), solutionsBlock(refProblems, lang)].filter(Boolean).join('\n\n') : ADVISE_RULE;
      const emit = EMITTERS.get(req) ?? (() => {});
      // THE CASE (ruling 1635, _shared/case_context.ts): the customer's open cases on every channel, the same-matter decision,
      // and the case summary in the cached prefix with only the case's last turns (the held block above still reads them all)
      const kase = await loadCaseContext(defaultDeps(admin, 'sales_engineer'), { channel: 'portal', seat: 'sales_engineer', audience: 'customer', message, lang, sys, past,
        partyId: caller.kind === 'customer' ? caller.customerId : null, email: caller.kind === 'customer' ? caller.email : null,
        dedupeKey: 'case_match:portal:' + (convKey || acct) + ':' + turns.length });
      const a = key ? await answerFromBrief({
        gateway: Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', secret: key, fn: 'sales_engineer', agent: 'sales_engineer',
        taskClass: jobTalk ? 'inquiry_qualification_conversation' : 'customer_portal_assistant', brief, sys: kase.sys, effort: conversationEffort(message),   // ruling 1630: medium, high when not straightforward
        max: images.length ? 1200 : 900, images, deadline,
        input: [...kase.past, { role: 'user', content: (facts ? facts + '\n\n' : '') + (expert ? expert + '\n\n' : '') + (known_ ? known_ + '\n\n' : '') + 'MESSAGE:\n' + message.slice(0, 4000) }],
        // the hand-off reply asks nothing, so a reply without a question is not sent back for one
        drop: () => { const f = replyFilter(held); return stage === 'handoff' ? Object.assign((x: string) => f(x), { end: () => null }) : f; },
        // the same rules aiReply holds every conversation reply to (figures, policy, reply guard, another party's identity),
        // sentence by sentence; a deferral is a whole-answer judgement (aiReply), never one sentence's, so it is not run here
        check: (t: string) => [...guardSupportReply(t, lang).violations.map((v) => 'it breaks the reply rule "' + v + '"'),
          ...replyProblems(t, known, { allowed, forbidden }).filter((p) => !/defers/.test(p)), ...wrappedReply(t), ...plainLanguage(t, lang)],
        checkWhole: (t: string) => replyLanguageProblems(t, lang),   // the language is a whole-reply rule: a contact line or an English spec is one sentence in the other script
      }, emit) : { reply: '', model: null, attempts: ['no gateway credential'], rewrites: 0, streamed: false, error: 'no_model_credential', outage: true };
      lap('reply');
      const reply = a.reply.trim();
      // the case summary after the reply that was given (runs past the response; never awaited)
      if (reply) recordCaseExchange(defaultDeps(admin, 'sales_engineer'), kase, { theirMessage: message, ourReply: reply,
        subject: caller.kind === 'customer' ? { customer_id: caller.customerId, ...(/^ZZ ?DEMO/i.test(message) ? { fixture: true } : {}) } : undefined });
      // the model was up and nothing it wrote passed: this turn is owed the model's answer (the re-ask below)
      const owed = !reply && a.outage !== true;
      let logId: number | null = null;
      try {
        const { data: logged } = await admin.from('assistant_logs').insert({ message, reply: reply || null, seat: 'sales_engineer', answered: !!reply, ...(convKey ? { conv_id: convKey } : {}),
          audience: caller.kind === 'customer' ? 'customer:' + caller.customerId : caller.kind, path: reply ? 'portal:reasoned' : owed ? 'portal:pending' : 'portal',
          gap_task_id: (r.task_id as number | undefined) ?? null }).select('id').maybeSingle();  // the gap fn_sales_assist filed stays linked (review of #1043)
        logId = Number(logged?.id) || null;
      } catch { /* the customer already has the answer; logging must not change the outcome */ }
      // THE STATE THIS TURN ESTABLISHED (the plan's own reading: no model call). Specs carry the customer message they came
      // from (the SQL keeps the first), "does not know" is the must-have the last reply asked when this message says so,
      // asked is what this reply asks. The cap's hand-off is made after the reply that announces it.
      if (episodeKey) {
        const plan = held.plan;
        const lastSeat = [...turns].reverse().find((t) => t.role === 'assistant')?.content ?? '';
        const askedBefore = sentencesOf(lastSeat).filter(isQuestion).flatMap((q) => targets(q, plan.plan));
        const unsure = isUnsure(message) ? askedBefore.filter((id) => plan.toConfirm.has(id)) : [];
        const asked = reply ? [...new Set(sentencesOf(reply).filter(isQuestion).flatMap((q) => targets(q, plan.plan)))] : [];
        // the reader's answer (started beside the reads; by now normally done), bounded so the turn never waits long for it
        const reading = await Promise.race([pReading, new Promise<null>((r) => setTimeout(() => r(null), Math.max(0, Math.min(8_000, deadline - Date.now()))))]);
        const rp = reading ? readingPatch(reading) : {};
        // A COMPLAINT ENTERS THE REGISTER (customer_support, 16 Nov 2026, COO hole H2): the turn reading above says it in the same
        // call; the ticket is opened once for this turn, linked to the signed-in customer (complaint_register.ts). Its
        // acknowledgement is the model-written e-mail the deadline duty owes (the reply has already streamed). Never throws.
        if (reading?.complaint && caller.kind === 'customer') {
          await registerComplaint((fn, args) => admin.rpc(fn, args), { channel: 'portal', sourceKey: await hashedKey('portal', episodeKey + ':' + turns.length),
            message, reading: reading.complaint, email: caller.email ?? null, partyKind: 'customer', partyId: String(caller.customerId),
            lang: lang === 'ar' ? 'ar' : 'en', fixture: /^ZZ ?DEMO/i.test(message) });
        }
        const statePatch = { turn: theirs.length, party_key: acct, episode_from: from, message_count: reply ? replyNo : replyNo - 1,
          ...rp,
          specs: { ...Object.fromEntries([...plan.filled].map(([id, v]) => [id, String(v).slice(0, 300)])), ...(rp.specs ?? {}) },
          ...(reading?.problem ? { condition: { ...(rp.condition ?? {}), problem: reading.problem } } : {}),
          unknown: Object.fromEntries(unsure.map((id) => [id, message.slice(0, 200)])), asked,
          ...(plan.plan ? { trade: plan.plan.key } : {}), status: statusOfStage(stage), ...registerPatch(theirs, lang) };
        await mergeState(admin, episodeKey, 'portal_assistant', statePatch);
        if (stage === 'handoff') await atCap(plan.plan?.key ?? null, plan.open);
      }
      if (reply) {
        // the plain-language score of the reply that went out, for the monthly self-review, as supportReply recorded it
        try {
          const rd = checkReadability(reply, lang);
          await admin.rpc('fn_support_reply_readability_log', { p_channel: 'portal', p_lang: lang, p_path: 'reasoned', p_rewritten: a.rewrites > 0,
            p_score: rd.score, p_tone: rd.tone, p_issues: rd.issues, p_reason: null, p_demo: /^ZZ DEMO/.test(message) });
        } catch { /* the reply matters more than its score */ }
        await run('assist', 'ok', { answered: true, basis: 'reasoned', model: a.model, attempts: a.attempts, dropped: a.dropped ?? [], ms: T, precedent: recallTrace(memory),
          plan: held.plan.plan ? { trade: held.plan.plan.key, mode: held.plan.mode, next: held.plan.next, also: held.plan.also, to_confirm: [...held.plan.toConfirm],
            extracted: extract ? { ms: extract.ms, slots: Object.keys(extract.slots) } : null } : null });
        return J({ ok: true, seat: 'sales_engineer', answered: true, reply, basis: 'composed by the model from the brief, the retrieved records and their own quotes', model: a.model });
      }
      // NO REPLY INSIDE THE TURN (rulings 1195/1196: code writes no reply text). The question is logged with the gap
      // fn_sales_assist filed and the conversation stays open. `outage` (founder_instruction 1339, openrouter_down.ts): true
      // only when OpenRouter was down (no call reached a model); only then does the portal show its own "saved" line. With the
      // model up and every draft refused (answerFromBrief already kept its passing sentences and asked it once more), the
      // portal shows no code-written text.
      const outage = a.outage === true;
      // NEVER LEFT SILENT (independent review of #1640, 27 Oct 2026). With the model up and every draft refused, the turn is
      // filed for the asynchronous re-ask (_shared/reask.ts): within about a minute the model is asked again on another
      // family with these problems named, every guard runs again (customerSafe re-run on these records, the plain-language
      // gate, the figure check, the reply guard), and the answer fills THIS assistant_logs row, so the portal shows it
      // under the question. After its last refused attempt the turn goes to this seat (held_question). The portal shows
      // "still working on your answer" meanwhile: UI state, not a reply. A turn the server could not log is not filed.
      let held_id: number | null = null;
      if (owed && logId) {
        try {
          const subject = { channel: 'portal', log_id: logId, ...(convKey ? { conv_id: convKey } : {}), ...(caller.kind === 'customer' ? { customer_id: caller.customerId } : {}) };
          const { data: hid } = await admin.rpc('fn_reason_hold', { p_seat: 'sales_engineer', p_surface: 'sales_engineer.portal_unwritten', p_question: message.slice(0, 4000),
            p_request: { seat: 'sales_engineer', surface: 'sales_engineer.portal_unwritten', subject, research: false,
              question: message.slice(0, 4000),
              context: { audience: 'customer', language: lang, turn_id: 'portal:' + logId },
              reask: { message: message.slice(0, 4000), own_facts: ownQuote ? 'THEIR OWN REQUESTS AND QUOTES (scoped in SQL to this customer; this IS what you can see of their account):\n' + ownQuote : '',
                passages: all.slice(0, 12).map((x) => ({ title: x.title, content: String(x.content ?? '').slice(0, 1200), corpus: x.corpus, record_id: x.record_id })),
                audience: 'customer', lang, channel: 'the signed-in customer portal', problems: (a.problems ?? []).slice(0, 12) } },
            p_plan: {}, p_subject: subject, p_reason: 'model_up_no_safe_reply', p_dedupe_key: 'portal_unwritten:' + logId });
          held_id = Number(hid) || null;
        } catch { /* unfiled: the 503 below still says no answer; the panel keeps its pending state only when held_id is set */ }
      }
      // NOT FILED: the row must not keep 'portal:pending', or assist_history would show "still working on your answer" under
      // a turn nothing will ever answer (review of #1657, 27 Oct 2026). Conditional: a reply that landed meanwhile is kept.
      if (owed && logId && held_id === null) {
        try { await admin.from('assistant_logs').update({ path: 'portal' }).eq('id', logId).is('reply', null).eq('path', 'portal:pending'); } catch { /* best effort */ }
      }
      const pending = held_id !== null;
      await run('assist', 'error', { answered: false, outage, pending, held_id, attempts: a.attempts, ms: T, task_id: r.task_id ?? null, precedent: recallTrace(memory) });
      return J({ ok: false, seat: 'sales_engineer', answered: false, error: 'no_answer', outage, attempts: a.attempts, pending, held_id, task_id: r.task_id ?? null }, 503);
    }
}
