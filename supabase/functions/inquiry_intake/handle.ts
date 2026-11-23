// inquiry_intake/handle.ts — the intake turn: one request, one conversation turn. Moved verbatim from index.ts (9 Nov 2026).
// Split by turn stage on 19 Nov 2026 (it_engineer; ledgers 1714/1715/1556: 1,418 lines here): owed_reply.ts (the poll),
// message_limit.ts (the 100-message cap), trade_reads.ts (checklist, ordered questions, specialist, field knowledge),
// intake_prompt.ts (the system prompt), interview_without_model.ts, restated_questions.ts, four_questions.ts,
// drawing_open_lines.ts, required_documents.ts and question_card.ts. This file keeps the turn's order and every write.
import { drawingNoteOf } from './attached_file.ts';
import { modelHeld } from '../_shared/llm_hold.ts';
import { asLocale } from '../_shared/registered_locale.ts';
import { questionText, questionsFor, buildBrief } from './interview.ts';
import { explainTerms } from '../_shared/customer_questions.ts';
import { stallOf, lastAskedKeys, phrasedOf, SENT_AS_IS, SALES_ENGINEER_WHATSAPP, settleModelTurn, replyFromState, requirementsFromModel, recordedRequirements, answerToQuestion, stampTurn, askedTurnsByKey, slotAskOf, heldReasonFor, heldReply, heldAsk, tappedHeldAnswer, intakeVoice, heldDraftOf, lastAskedKey, unknownHeldDraft, openSpecsBlock } from './slots.ts';
import { emirateOf, isAlAin, detectUrgency } from './classify.ts';
import { ACTOR, toStored, forCard, type Answers } from '../_shared/intake_requirements.ts';
import { stateServiceKeys as stateKeysInVocab } from '../_shared/profile_services.ts';
import { defaultDeps } from '../_shared/think.ts';
import { statedSpecs, tradeOf } from '../_shared/reasoned_decisions.ts';
import { guardSupportReply } from '../_shared/support_reply_guard.ts';
import { isOpenRouterDown } from '../_shared/openrouter_down.ts';
import { TurnClock, placeUserTurn, storedReply, turnIdOf, within } from './turn_clock.ts';
import { OPEN_STATUSES, newestOpenDraft, transcriptOf } from './resume.ts';
import { CORS, J, admin, logRun, parseJson, sanitizeInput, sec, serviceVocabKept } from './shared.ts';
import { type LlmFailure, llm } from './llm.ts';
import { kbFor } from './knowledge.ts';
import { supplierCount } from './supplier_count.ts';
import { accountKey, loadTranscript } from '../_shared/chat_history.ts';
import { capRule, capStage, carriedTurns, carryState, intakeKey, mergeState, openPortalEpisode, readState, registerPatch, saysDontKnow,
  stateSummary, statusOfStage, type Dialect, type InquiryState, type StatePatch } from '../_shared/inquiry_state.ts';
import { heldProblem, problemIndex, problemsFor, readSolution, serviceKeysOfChoice, solutionPatch, solutionsBlock, solutionStateText, stateServiceKeys } from '../_shared/solution_catalogue.ts';
import { SUPPLIER_TO_ADVISE, adviseUnknown, packFields, placeTrades, slugOfTrade, withUniversal, taxonomyBlock, taxonomyOf, tradeBlock, tradeContext, universalAnswers, validCodes, validServiceKeys, validTopics,
  type Placement, type TradeContext } from '../_shared/inquiry_trades.ts';
import { blockingGate, briefConditions, recordedSpecs, withPack } from './blocking_gate.ts';
import { photoAskDraft, photoAskOfTurn, photoPromptBlock, recordOf, recordSitePhotos, type SitePhotos } from '../_shared/site_photos.ts';
import { readCustomerRecord, recordBlock, recordIntakeExchange, recordReferral, referralOf, type CustomerRecord } from './customer_record.ts';
import { capTurn, summaryAtLimit } from './message_limit.ts';
import { readChecklists, readFieldKnowledge, readOrderedQuestions, readSpecialist } from './trade_reads.ts';
import { checklistTextOf, intakeSystemPrompt } from './intake_prompt.ts';
import { interviewWithoutModel } from './interview_without_model.ts';
import { fourQuestions } from './four_questions.ts';
import { drawingOpenLines } from './drawing_open_lines.ts';
import { readRequiredDocuments } from './required_documents.ts';
import { owedReply } from './owed_reply.ts';
import { dropRestatedQuestions } from './restated_questions.ts';
import { questionCard } from './question_card.ts';
import { acceptImages } from '../_shared/chat_images.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { PHOTO_WAIT_MS, claimsPhotoSeen, firstAsk, gatewayPhotoDeps, photoPromptNote, readPhotos, stampOf, unreadLead, type PhotoRead } from '../_shared/photo_reading.ts';

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // ONE CLOCK FOR THE WHOLE TURN (27 Oct 2026, turn_clock.ts): every model step below is cut at it, and its laps
  // say where the time went (agent_runs counts.laps; `timing` in the response to our own @example.invalid harness).
  const clock = new TurnClock();
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    // The body is read while the user is resolved: neither waits for the other.
    const [{ data: { user } }, b] = await Promise.all([admin.auth.getUser(jwt), req.json().catch(() => ({} as any))]);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    // A TURN STILL OWED THE MODEL'S ANSWER (./owed_reply.ts): read by the turn's id, never recomputed; no rate-limit slot.
    const pollId = turnIdOf(b?.poll_turn_id);
    if (pollId && b.intake_id) return await owedReply(email, b, pollId);
    // HIS NEWEST OPEN DRAFT, ON ANY RETURN (16 Nov 2026, ./resume.ts). `resume` reads it with its conversation and writes nothing:
    // a reload, another tab or his phone opens the request chat where he left it. No rate-limit slot.
    const openDrafts = () => admin.from('inquiry_intake').select('*').eq('email', email).in('status', [...OPEN_STATUSES])
      .order('updated_at', { ascending: false }).limit(5);
    if (b && b.resume === true && !String(b.text || '').trim()) {
      const { data: rows } = await openDrafts();
      const row = newestOpenDraft(rows as any[]);
      if (!row) return J({ ok: true, resumed: false, agent: ACTOR });
      return J({ ...storedReply(row), replayed: false, resumed: true, transcript: transcriptOf(row.turns), agent: ACTOR });
    }
    try { const { data: ok } = await admin.rpc('rl_check', { p_key: 'intake:' + email, p_limit: 60, p_seconds: 3600 }); if (ok === false) { await logRun('ok', { rate_limited: 1, intake_persisted: 0 }, 'Customer hit the intake rate limit (60/hour) and was turned away before their request was captured — their RFQ was not created and no supplier will ever see it unless they retry.'); return J({ error: 'You are sending requests too quickly. Please wait a moment and try again.' }, 429); } } catch (_e) { /* */ }
    // THE CUSTOMER RECORD IS CREATED HERE, NOT LOOKED UP AND ABANDONED.
    // This line used to be a select only. When it missed — which it did for everyone who came in
    // through intake rather than through the OTP or KYC paths — customer_id was written null and
    // no customer row ever appeared. Production shows the result: 7 inquiries, every one with a
    // null customer_id, and public.customers empty. The person is already AUTHENTICATED at this
    // point, so this materialises a customer that genuinely exists rather than inventing one.
    // 14 Sep 2026. A FOLLOW-UP ON A POSTED RFQ IS NOT AN INTAKE. The portal's "Ask the assistant
    // about this request" posted {text, inquiry_id} here with no intake_id; this function never read
    // inquiry_id, so every follow-up inserted a fresh orphan inquiry_intake draft and got a first-turn
    // intake prompt back — nothing reached the RFQ or a supplier (website audit 14 Sep, finding 9).
    // Follow-ups belong to customer_api rfq_note. Refused before any customer or draft row is written.
    if (b && b.inquiry_id && !b.intake_id) return J({ ok: false, error: 'use_rfq_note', message: 'Questions about a request you have already sent go on that request, not into a new one.' }, 200);
    // Three independent reads, asked together (turn_clock.ts): the customer, the trade list, and the draft this turn
    // continues. Each is used exactly as it was when they were asked one after another.
    const [custRead, specsRead, draftRead] = await Promise.all([
      admin.from('customers').select('id,locale').eq('email', email).maybeSingle(),
      admin.from('category_specs').select('category'),
      b.intake_id ? admin.from('inquiry_intake').select('*').eq('id', b.intake_id).maybeSingle()
        // a first message with no draft id continues his newest open draft, unless he chose a fresh request or a carried chat
        : (!b.fresh && b.carry_from !== 'portal') ? openDrafts().then((x: any) => ({ data: newestOpenDraft(x?.data || []) })) : Promise.resolve({ data: null }),
    ]);
    let cust = custRead.data;
    if (!cust) {
      // Created here, so this IS the registration: the page language they are using is what registers.
      const { data: made } = await admin.from('customers')
        .insert({ email, full_name: (user.user_metadata as any)?.full_name || email.split('@')[0], locale: asLocale(b.lang) })
        .select('id,locale').maybeSingle();
      cust = made || null;
    }
    const text = sanitizeInput(String(b.text || '').trim()).slice(0, 4000);
    const drawingBoq = b.drawing_boq || null;
    // A PHOTO WITH THIS MESSAGE (19 Nov 2026, founder ruling 1200; _shared/photo_reading.ts): only what chat_images accepts (at most
    // two, a JPEG/PNG/WebP data URL under its cap, or a file on our own storage); anything else is never fetched or sent on.
    const photosIn = acceptImages(b.images, new URL(Deno.env.get('SUPABASE_URL')!).host).images;

    const { data: allSpecs, error: specsErr } = specsRead;
    const validSlugs = (allSpecs || []).map((s: any) => String(s.category));
    if (specsErr || !validSlugs.length) { await logRun('error', { category_specs_loaded: validSlugs.length, specs_query_failed: specsErr ? 1 : 0 }, 'category_specs could not be loaded (' + String(specsErr?.message || 'query returned no rows') + ') — with no valid category slugs every trade is treated as invalid, so this customer request will be filed as \'general\' with no checklist and routed to the wrong suppliers or to none at all.'); }

    let draft: any = null;
    { const data = (draftRead as { data: any }).data; if (data && (data.email === email)) draft = data; }
    // "NEW REQUEST" AFTER A PORTAL CHAT OPENS PRE-FILLED (10 Nov 2026, founder ledger 1572; the design audit's G1). The portal
    // told the customer to press New request, and that opened a BLANK request chat (Dashboard.tsx passed only the homepage
    // draft), so they retold the whole job. With carry_from 'portal' and no request yet, the customer's newest portal job
    // that has not become a request (its state row, _shared/inquiry_state.ts openPortalEpisode) is carried in: every turn
    // of that job is the new request's conversation, marked carried, and its state (specs with their message, what they do
    // not know, the count, the dialect) becomes the request's. The turn below then reads it all as one conversation: the
    // extraction fills the checklist from what was said, and nothing already held is asked again. No job to carry: nothing
    // is created and the portal opens the request chat as before.
    let carry: { fromKey: string; turns: any[] } | null = null;
    if (!draft && b.carry_from === 'portal' && cust?.id) {
      const acct = accountKey('customer', String(cust.id));
      const ep = await openPortalEpisode(admin, acct);
      const tr = ep ? await loadTranscript(admin, acct) : null;
      const seeded = ep && tr ? carriedTurns(tr, Number(ep.episode_from) || 0) : [];
      if (!ep || !seeded.some((t) => t.role === 'user')) return J({ ok: true, carried: false, agent: ACTOR });
      carry = { fromKey: ep.conv_key, turns: seeded };
    }
    if (!draft) { const { data, error: draftErr } = await admin.from('inquiry_intake').insert({ customer_id: cust?.id || null, email, status: 'needs_info', turns: carry ? carry.turns : [], ...(carry ? { brief: { details: {}, state: 'interview', carried_from: carry.fromKey } } : {}) }).select('*').single(); draft = data; if (draftErr || !draft) { await logRun('error', { intake_persisted: 0 }, 'A customer-submitted inquiry failed to persist: insert into inquiry_intake returned ' + String(draftErr?.message || 'no row') + ' — this RFQ is lost at the front door, it will never be routed and no supplier will ever quote it.'); } }

    // The insert above logs a precise diagnostic when it fails - "this RFQ is lost at the front
    // door" - and then execution used to continue straight into draft.turns, so the caller got
    // "Cannot read properties of null (reading 'turns')" and the real reason stayed in a log
    // nobody was reading. Fail here, with the reason, in the response.
    if (!draft) {
      return J({
        error: 'intake_unavailable',
        message: 'Your request could not be saved. Nothing has been submitted - please try again.',
      }, 503);
    }

    const turns: any[] = Array.isArray(draft.turns) ? draft.turns : [];
    // THE REQUEST'S STATE (_shared/inquiry_state.ts): read beside everything else; a carried request takes its portal job's
    // state first. Absent or unreadable (the table is applied at merge), the row's own slots stand as before.
    const stKey = intakeKey(String(draft.id));
    const stateP: Promise<InquiryState | null> = carry ? carryState(admin, carry.fromKey, stKey, 'request_chat', String(draft.id)).then((x) => x ?? readState(admin, stKey)) : readState(admin, stKey);
    // THE WHOLE TAXONOMY AND THE HELD TRADES' PACKS (10 Nov 2026, founder ledger 1586; _shared/inquiry_trades.ts): every active
    // trade (cached per instance), and for the taxonomy codes the state already holds, their services, spec checklists,
    // authority and verified approvals. Both start now, beside the state; unreadable, the turn runs as before without them.
    const lang2: 'en' | 'ar' = asLocale((cust as any)?.locale) === 'ar' ? 'ar' : 'en';
    const taxP = taxonomyOf(admin);
    const ctxP: Promise<TradeContext | null> = Promise.all([stateP, taxP]).then(([s0, tax]) => tradeContext(admin, s0?.trade_codes ?? [], lang2, tax)).catch(() => null);
    // The spec the last reply asked, read BEFORE this message is placed: "I don't know" answers that spec.
    const askedKeyBefore = lastAskedKey(turns);
    // A RETRY IS NOT A SECOND MESSAGE (27 Oct 2026, turn_clock.ts placeUserTurn). The portal retries a turn it stopped
    // waiting for with the same turn_id; a message the server already recorded is answered again, never added twice.
    const placed = placeUserTurn(turns, text, turnIdOf(b.turn_id));
    clock.lap('read');
    // ── THE 100-MESSAGE LIMIT (10 Nov 2026, founder ledger 1572: "Hard limit 100 messages per inquiry") ──────────────
    // Every message counts, the customer's and ours, carried portal turns included (the limit is per inquiry). The reply
    // about to be written is message replyNo: from 80 only the missing required details are asked, from 95 the reply is the
    // summary of what is held and still open, at 100 it tells them the sales engineer has the whole request (the intake is
    // held and the spec.not_sure handoff opened), and past 100 nothing is sent at all.
    const replyNo = turns.length + 1;
    const stage = capStage(replyNo);
    const userTexts = (): string[] => turns.filter((t: any) => t && t.role === 'user').map((t: any) => String(t.text || ''));
    // "I don't know" to the spec the last reply asked, in any dialect (saysDontKnow): that spec is never asked again.
    const unknownNow: Record<string, string> = placed === 'added' && askedKeyBefore && text && saysDontKnow(text) ? { [askedKeyBefore]: text.slice(0, 200) } : {};
    // Every customer message, once. raw_input is saved as this same text below, so appending it here
    // doubled the whole conversation on every turn (measured 21 Sep 2026, inquiry_intake c99beee8:
    // the first message appeared three times in raw_input) and the 4000-character cut then lost the
    // end of what the customer wrote.
    const allText = turns.filter((t) => t.role === 'user').map((t) => t.text).join(' \n ');
    // THE SALES ENGINEER ANSWERS IN THE REGISTERED LANGUAGE (founder, 14 Sep 2026). This read the
    // script of what the customer typed, so an Arabic-registered customer who typed one line in
    // English was interviewed in English from then on. customers.locale decides; what they type in
    // either language is still understood.
    const ar = asLocale((cust as any)?.locale) === 'ar';
    // NEVER LEFT SILENT (founder ruling 1339; the independent review of #1646). When the model was up and refused every
    // draft (intakeVoice by 'none'), the turn is not left with an empty bubble and no code text is sent: it is filed for
    // the asynchronous re-ask (_shared/reask.ts, surface inquiry_intake.unwritten_reply). Within about a minute the model
    // is asked again (another family, these problems named, every guard again) and its answer is appended to this
    // conversation as the reply to this turn (reask_of); three refusals hand it to sales_engineer (held_question, the
    // 15-minute rule as a backstop). The portal shows "still working on your answer" (UI state) and polls by the turn's
    // id. Returns the turn id when filed. A harness turn (@example.invalid) and a retry of a turn are never filed.
    const fileReask = async (draftText: string, problems: string[] | undefined): Promise<string | null> => {
      const tid = placed === 'added' ? turnIdOf(b.turn_id) : null;
      if (!tid || email.endsWith('@example.invalid')) return null;
      const asked = (text ? text : '(they sent a file)').slice(0, 4000);   // what they wrote: the message, never a reply
      const subject = { channel: 'request_chat', intake_id: draft.id, turn_id: tid };
      const { data: hid } = await admin.rpc('fn_reason_hold', { p_seat: 'sales_engineer', p_surface: 'inquiry_intake.unwritten_reply', p_question: asked,
        p_request: { seat: 'sales_engineer', surface: 'inquiry_intake.unwritten_reply', subject, research: false, question: asked,
          context: { audience: 'customer', language: ar ? 'ar' : 'en', turn_id: 'intake:' + tid },
          reask: { message: asked, audience: 'customer', lang: ar ? 'ar' : 'en', channel: 'the website request chat',
            facts: 'WHAT TO SAY ON THIS TURN (decided by our systems from the request\'s state; convey it in your own words, change nothing in its meaning, add nothing):\n' + draftText.slice(0, 3000),
            problems: (problems ?? []).slice(0, 12) } },
        p_plan: {}, p_subject: subject, p_reason: 'model_up_no_safe_reply', p_dedupe_key: 'intake_unwritten:' + draft.id + ':' + tid }).then((r: { data: unknown }) => r, () => ({ data: null }));
      return Number(hid) ? tid : null;
    };
    // A retry of a turn that already landed is answered from the row, never recomputed (turn_clock.ts storedReply).
    if (placed === 'landed') {
      await logRun('ok', { intake_saved: 0, retry_replayed: 1, ms: clock.lap('replayed') }, 'the portal retried a turn that had already been answered; the stored reply was returned and nothing was recomputed');
      return J({ ...storedReply(draft),
      agent: ACTOR, agent_name: ar ? 'مهندس مبيعات QuotesDone' : 'QuotesDone sales engineer' });
    }

    // THE 100-MESSAGE LIMIT, MESSAGE 100 AND PAST IT (./message_limit.ts capTurn): held and handed to the sales engineer.
    if (stage === 'handoff' || stage === 'over') return await capTurn({ stage, replyNo, turns, draft, cust, text, ar, clock, allText, stKey, userTexts });

    // THE PHOTO IS READ BY A VISION MODEL, ONCE (19 Nov 2026, sales_engineer; founder ruling 1200: "custom wardrobe from a studio
    // photo: ask dimensions, shelves vs hanging"; _shared/photo_reading.ts). Before, no photo reached any model here. Started now,
    // beside the record and the trade's reads, on the sales engineer's reading route; the cache answers a photo already read (by
    // its hash). The turn waits PHOTO_WAIT_MS from the request at most: a read still running is 'late' for this turn and finishes
    // into the cache (waitUntil). The reading is internal context for the next question; the photo reaches a supplier only
    // through its own check (site_photo_gate.ts), unchanged. A retry that landed never reaches here (answered from the row).
    const keepRunning = (p: Promise<unknown>) => { (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime?.waitUntil?.(p); };
    const photoReadsP: Promise<PhotoRead[]> = photosIn.length
      ? readPhotos(gatewayPhotoDeps({ admin, gatewayUrl: Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', secret: () => sec('cred_fn_ai'), held: () => modelHeld(admin) }), photosIn, {
          seeds: seedTerms({ name: String((user.user_metadata as any)?.full_name || ''), email }), subject: { email, customer_id: cust?.id || null },
          waitMs: Math.max(1, clock.t0 + PHOTO_WAIT_MS - Date.now()), keep: keepRunning }).catch(() => [])
      : Promise.resolve([]);

    // HIS WHOLE RECORD, AS EVERY OTHER DOOR READS IT (16 Nov 2026, founder ledgers 1711-1713; customer_record.ts): his earlier
    // requests, the promises still open on his cases and his case, started NOW beside the trade's reads below and read only when the
    // prompt is built, each cut at CASE_READ_MS. This message is the case's message, the turns before it its history.
    const turnIdNow = turnIdOf(b.turn_id);
    const recordP = readCustomerRecord(defaultDeps(admin, 'sales_engineer'), { customerId: cust?.id ? String(cust.id) : null, email, message: text,
      past: placed === 'added' ? turns.slice(0, -1) : turns, lang: ar ? 'ar' : 'en', dedupeKey: 'case_match:intake:' + draft.id + ':' + (turnIdNow ?? replyNo) });
    let record: CustomerRecord | null = null;
    // After the reply that was really given and saved: the exchange onto his case (and any promise in it), never awaited.
    const recordExchange = (reply: string) => { if (placed === 'added' && text && String(reply || '').trim()) recordIntakeExchange(defaultDeps(admin, 'sales_engineer'), record, { theirMessage: text, ourReply: String(reply), intakeId: String(draft.id), turnId: turnIdNow }); };

    // The trade is never read off words (founder_instruction 886-903; the keyword map, _shared/trade_classify.ts,
    // is deleted): it is the one a previous turn stored, the drawing's, the model's reading below, or — when the
    // model gives none — REASONED among every category_specs row (tradeOf, surface inquiry_intake.trade).
    let category = draft.category || (drawingBoq && drawingBoq.category) || null;
    if (category && !validSlugs.includes(category)) category = null;
    // 23 Sep 2026 (founder_instruction 886-903): fn_kb_route_decide — alias substring matching over the operational
    // router — no longer picks the trade here, and no router question is asked from it. With no stored trade the
    // model reads it from the conversation; if it gives none, the trade is REASONED among every category_specs row
    // (tradeOf below), and under the hold the intake is HELD rather than routed on words (decision point 19; the
    // SQL router itself is registered as sql.fn_kb_route_decide).
    // THE EMIRATE IS THE MODEL'S (12 Nov 2026, rulings 1664/1666; LLM-first audit A1; classify.ts emirateOf says what it
    // replaced). Before the model answers, it is only what a ready brief already held; the model's reading of this turn,
    // when it names one of the emirates, replaces it below. Nothing here reads the customer's words for one.
    let emirate: string | null = emirateOf(draft.brief && typeof draft.brief === 'object' ? draft.brief.emirate : null);
    // The job is in the city of Al Ain (classify.ts): the emirate stays Abu Dhabi; only the utility line reads this.
    let alAin = !!(draft.brief && typeof draft.brief === 'object' && (draft.brief.al_ain === true || isAlAin(draft.brief.emirate)));

    // Gather checklist(s). For a multi-trade request, include EACH detected trade's REQUIRED fields so the
    // model does not anchor on one category and re-ask details already given for the other trades.
    const tradeSlugsForChecklist = Array.from(new Set([category].filter((c) => c && validSlugs.includes(c as string)))).slice(0, 4) as string[];
    // THE TRADE'S FOUR READS START TOGETHER (27 Oct 2026, turn_clock.ts). The checklist, the ordered questions, the
    // specialist and the field knowledge depend only on the trade and the message, and were asked one after another
    // (the knowledge alone up to 3 s). Each is started here and awaited exactly where it was read before; what each
    // block does with its answer is unchanged.
    const started = <T,>(f: () => PromiseLike<T>): Promise<T> => Promise.resolve().then(f);
    const specsP = tradeSlugsForChecklist.length ? started(() => admin.from('category_specs').select('category,label,fields').in('category', tradeSlugsForChecklist)) : null;
    const questionsP = category ? started(() => admin.rpc('fn_category_questions', { p_category: category, p_lang: ar ? 'ar' : 'en', p_limit: 14 })) : null;
    // The specialist is the agent whose key IS the trade (decision point inquiry_intake.specialist, below).
    const agentQ = () => admin.from('category_agents').select('slug,name,persona').eq('active', true).eq('slug', category).maybeSingle();
    const agentP = category && category !== 'general' ? started(agentQ) : null;
    const kbP = tradeSlugsForChecklist.length && text ? Promise.all(tradeSlugsForChecklist.slice(0, 2).map((s) => kbFor(s, text))) : null;
    // The checklist(s) of the trades read above (./trade_reads.ts readChecklists).
    const read0 = await readChecklists(specsP, tradeSlugsForChecklist, category);
    let checklist: any[] = read0.checklist;
    const perTradeChecklists = read0.perTradeChecklists;
    // THE HELD TRADE'S OWN CHECKLIST (ledger 1586): what an exact quote of that trade must state (trade_spec_checklist, every
    // one of the 223 trades has one). For a request no category_specs slug covers ('general', or none yet) its first
    // CHECKLIST_REQUIRED specs are REQUIRED, so the slot machinery asks them, holds them and derives readiness from them; under
    // a real slug they ride as optional expert questions and the slug's own keys stay the dispatch contract.
    // Only once a slug is stored: with none yet (turn 1, or a carried portal job), the model's slug loads its checklist below
    // first and the pack joins it there, so a pack can never stand in for the slug's own dispatch keys.
    let tradeCtx = await ctxP;
    // The checklist(s) of the placed trades this job is (the model names them in "checklist_topics"; held on the brief).
    const prevTopics: string[] = validTopics((draft.brief as any)?.checklist_topics, tradeCtx);
    if (category) checklist = withPack(checklist, tradeCtx, category, prevTopics);
    // THE ORDERED INTERVIEW (./trade_reads.ts readOrderedQuestions): the desks' qualification order, beside the checklist.
    const { orderedQuestions, askOrder } = await readOrderedQuestions(questionsP);
    const multiTrade = perTradeChecklists.length > 1;
    const checklistText = checklistTextOf(multiTrade, perTradeChecklists, checklist);   // ./intake_prompt.ts

    const catLabel = (perTradeChecklists.find((c) => c.slug === category)?.label) || category || '';
    // THE CATEGORY SPECIALIST (./trade_reads.ts readSpecialist): the agent whose key IS the trade, else the generic sales engineer.
    const { specialist } = await readSpecialist(agentP, turns);

    // THE SPECIALIST'S FIELD KNOWLEDGE (./trade_reads.ts readFieldKnowledge), retrieved by the customer's own words.
    const specialistKB = await readFieldKnowledge(kbP, tradeSlugsForChecklist);

    const convo = turns.map((t) => `${t.role === 'user' ? 'Customer' : 'Intake'}: ${t.text}`).join('\n');
    // What the request's state already holds (every fact with the message it came from, what they said they do not know),
    // and the cap's rule for this reply. A carried request's portal facts arrive this way on its first turn.
    const st = await stateP;
    const stateText = stateSummary(st);
    // THE EXPERT'S HALF (ledger 1572/1579/1586; _shared/solution_catalogue.ts): the reference options for the trade the
    // conversation is in (never chosen by the customer's words, ruling 890), else one line per known situation; the trade
    // block (services, what a supplier needs stated, authority, location rules); the whole taxonomy until a trade is held;
    // and what was offered and chosen so far.
    const taxonomy = await taxP;
    const refProblems = problemsFor({ slug: category && category !== 'general' ? category : null, codes: st?.trade_codes ?? [], held: heldProblem(st) });
    const solutionsText = refProblems.length ? solutionsBlock(refProblems, ar ? 'ar' : 'en') : problemIndex();
    const tradeText = tradeBlock(tradeCtx, ar ? 'ar' : 'en', prevTopics);
    // PHOTOS FOR A SITE-VISIT JOB (15 Nov 2026, founder ledger 1704; _shared/site_photos.ts): the shots each placed trade's job
    // checklist asks for, shown to the model until the one turn that asks; never again after it.
    // The record is the intake's own column (written by fn_site_photos_record in one statement: an upload between turns is on it).
    const photoRecord: SitePhotos | null = recordOf(draft);
    const photoText = photoPromptBlock(tradeCtx, prevTopics, turns, photoRecord, ar ? 'ar' : 'en');
    const taxonomyText = taxonomy && !(st?.trade_codes?.length) ? taxonomyBlock(taxonomy) : '';
    const solutionState = solutionStateText(st, ar ? 'ar' : 'en');
    const stageRule = capRule(stage, replyNo);
    // OPEN SPECS NOW (15 Nov 2026, journey A; rule 18): the required specs this request does not hold yet, how often each was asked,
    // and when the job does not need it, so the model reads every message against all of them, not only the last one asked.
    const askedSoFar = askedTurnsByKey(turns);
    const openSpecsText = openSpecsBlock(checklist, (draft.brief && typeof draft.brief === 'object' && draft.brief.details && typeof draft.brief.details === 'object') ? draft.brief.details : {}, askedSoFar, ar ? 'ar' : 'en');
    // WHAT THE FILE IS AND WHETHER IT IS ENOUGH (13 Nov 2026, sales_engineer; founder ruling 1683: "Did the sales engineer
    // actually verify that quotation is actually sufficient to be shared with the suppliers?"). The reading names the kind
    // and a sufficiency verdict with what a supplier of the trade still needs (drawing_boq SYS); this turn ASKS for those, in
    // plain words, one or two at a time, framed by this trade's checklist above, instead of sending a thin inquiry. "Send it
    // as it is" is an answer: what was not given is recorded in unknown_keys and the suppliers are told it is not known.
    const drawingNote = drawingBoq && drawingBoq.boq ? drawingNoteOf(drawingBoq) : '';
    // WHAT THE PHOTO SHOWS (ruling 1200): this turn's reading and the ones earlier turns stamped, with the questions it leaves open;
    // or, when this turn's photo could not be read, the rule never to say it was. In the message, not the system prompt (cached).
    const photoReads = await photoReadsP;
    if (photosIn.length) clock.lap('photo');
    const photoNote = photoPromptNote(photoReads, turns, ar ? 'ar' : 'en');
    const photoUnread = photoReads.some((r) => r.status === 'failed') && !photoReads.some((r) => r.status === 'read');
    const photoStamp = stampOf(photoReads);
    const slugList = validSlugs.concat(['general']).join(', ');

    // The system prompt: the identity (the specialist's trade voice, else the generic one), the rules and the JSON contract (./intake_prompt.ts).
    const sys = intakeSystemPrompt({ specialist, catLabel, category, multiTrade, checklistText, orderedQuestions, ar, tradeText, photoText, taxonomyText, solutionsText, slugList });

    // THE SYSTEM PROMPT IS THE SAME ON EVERY TURN OF A REQUEST, SO THE GATEWAY'S CACHE CAN SERVE IT (15 Nov 2026, journey A).
    // MEASURED (ai_cost_log, tag 8288bec3, 14:07-14:12 UTC, SELECT): all 13 interview calls (anthropic/claude-sonnet-5.5) read 0
    // cached tokens and WROTE 9,128-13,685 (the cache write costs more than a plain read), because the state, the open specs,
    // the solution so far, the cap's rule, the RECORDED answers and the field knowledge retrieved by the customer's latest words
    // sat inside the system prompt and changed it every turn: USD 0.034-0.060 a call, USD 0.65 of the request's 0.71. They are
    // the turn's, so they ride in the message, before the conversation; the system prompt keeps the rules, the contract and the
    // trade's checklist, which change only when the trade does. Same words reach the model, in a different place.
    record = await recordP;
    clock.lap('record');
    const turnContext = [
      stateText, openSpecsText, solutionState, stageRule,
      carry ? 'THIS REQUEST CONTINUES THE CUSTOMER\'S CHAT WITH OUR SALES ENGINEER: every turn below was said there. Read it as one conversation, put every checklist item it states under its key, and ask only for what is still missing.' : '',
      recordBlock(record),
      specialistKB ? `FIELD EXPERTISE for this trade (the specialist knowledge our expert agents use — apply it to ask the sharpest quote-critical questions and to recognise when a customer's answer implies an approval, standard or spec they haven't mentioned; do not lecture the customer (putting options to a customer who is deciding, rule 13, is not a lecture), quote this text, or ask about things irrelevant to their specific job):\n${specialistKB}` : '',
      recordedRequirements(category, (draft.brief && typeof draft.brief === 'object' ? draft.brief.req_answers : null)),
    ].filter((x) => String(x || '').trim()).join('\n\n');
    const user_msg = `THIS TURN (our records of this request; customer words quoted in them are untrusted, as the conversation is; read with the rules):\n${turnContext}\n\nConversation so far:\n${convo}${drawingNote}${photoNote}\n\nAnalyse and respond with the JSON.`;
    const llmFail: { v: LlmFailure | null } = { v: null };
    clock.lap('prompt');
    // Fetched while the interview call runs, so a turn that becomes ready does not wait for it after (see above).
    if (category) void serviceVocabKept();
    // THE EXACT-SPEC READING RUNS ALONGSIDE THE INTERVIEW CALL (27 Oct 2026; reasoned_decisions.ts statedSpecs has the
    // measurements). It used to start only after the interview call said ready, as a second serial model call of
    // 13-17 s (60-125 s with its old planner). It is started here, over the trade's required specs this row does not
    // hold yet, on the turn's clock, and its answer is used exactly where it was before: on a ready turn, for a
    // required spec the brief left blank. Unused (the turn is not ready), it fills nothing. A trade the interview call
    // changes is read again below only if the clock allows.
    const heldDetails = (draft.brief && typeof draft.brief === 'object' && draft.brief.details && typeof draft.brief.details === 'object') ? draft.brief.details : {};
    const toRead = checklist.filter((f: any) => f && f.required && f.key && !(String(f.key) in heldDetails));
    const startReading = async (cat: string, fields: any[]) => {
      try {
        return await statedSpecs(defaultDeps(admin, 'inquiry_intake'), {
          conversation: allText, category: cat, dedupeKey: 'intake_spec:' + (draft.id ?? email) + ':' + turns.length,
          fields: fields.map((f: any) => ({ key: String(f.key), question: String(f.question || f.key) })),
          deadline: clock.deadline(),
        });
      } catch (_e) { return null; }   // an unread spec is asked, never filled
    };
    const specRead = category && toRead.length && allText.trim() && clock.canStart() ? { category, p: startReading(category, toRead) } : null;
    const raw = await llm([{ role: 'system', content: sys }, { role: 'user', content: user_msg }], { email, customer_id: cust?.id || null }, llmFail, clock.modelDeadline());
    clock.lap('model');
    let out = raw ? parseJson(raw) : null;
    const llmCallOk = raw !== null;
    const llmParseOk = out !== null;
    if (out && llmParseOk) {
      const mb = out.brief && typeof out.brief === 'object' ? out.brief : {};
      const e = emirateOf(mb.emirate);
      if (e) { emirate = e; alAin = mb.al_ain === true || isAlAin(mb.emirate); }
    }
    // The answer to the emirate question code asked (below): the tapped name of one of the seven is a fixed payload.
    if (!emirate && draft.brief && typeof draft.brief === 'object' && draft.brief.emirate_asked === true) emirate = emirateOf(text);
    // What they asked us, answered by the model in the same reading (no second call), bounded (slots.ts answerToQuestion).
    const modelAnswer = out && llmParseOk ? answerToQuestion(out.answer_to_question) : '';
    // WHAT A WORD MEANS (15 Nov 2026, persona dry run: "شو يعني BTU؟" went unanswered and capacity was asked again five turns
    // later). The model names the words of our question their last message asks about (explain_terms); the reply explains them
    // first (its own answer, else _shared/customer_questions.ts GLOSSARY) and asks that question again in plain words (slots.ts
    // SlotOpts.rephrase). plain_question: its wording of the next question, for a spec with no vetted wording (SlotOpts.phrased).
    const explainNow: string[] = out && llmParseOk && Array.isArray(out.explain_terms) ? out.explain_terms.map((x: unknown) => String(x ?? '').trim()).filter(Boolean).slice(0, 4) : [];
    const meaning = modelAnswer || explainTerms(explainNow, ar ? 'ar' : 'en');
    const phrasedNow = out && llmParseOk ? phrasedOf(out.plain_question, ar ? 'ar' : 'en') : null;
    // OPENROUTER DOWN FOR THIS TURN (founder_instruction 1339, 27 Oct 2026): "the engineer and customer support never
    // replies without llm unless the server of open router is down". Only then may the customer read a code-written
    // draft (the interview's question, the state's sentence). A model that answered, even with JSON we could not parse,
    // is up: the draft is voiced by the model (slots.ts intakeVoice) before the reply leaves.
    let llmDown = !llmCallOk && isOpenRouterDown(llmFail.v?.error, llmFail.v?.http);
    // The model's own sentence as it wrote it. A reply that is not exactly this was composed by code and is voiced.
    let modelWrote: string | null = out && llmParseOk && typeof out.assistant_message === 'string' ? out.assistant_message : null;
    // HOW HE HEARD OF US (W3_PEOPLE, 16 Nov 2026; CUSTOMER #11): the model's reading of his own words, kept once on his first
    // request by fn_customer_referral_record (customer_record.ts); never awaited, never a keyword rule.
    { const heard = out && llmParseOk ? referralOf(out) : null; if (heard && cust?.id) void recordReferral((fn, args) => admin.rpc(fn, args), String(cust.id), heard, String(draft.id)); }
    // A RUN THE FOUNDER'S HOLD SHAPED IS NOT A FAILED RUN (22 Sep 2026, SEATS-08/CP-14). While the
    // hold is on there is no model to call, the deterministic interview below IS the designed path,
    // and logging it as 'error' put 592 false faults into agent_runs in 72 h — the watchers page on
    // status='error', so the intake's real failures were buried under its normal operation.
    if (!llmCallOk && await modelHeld(admin)) {
      await logRun('ok', { llm_call_ok: 0, llm_parse_ok: 0, keyword_fallback_used: 1, model_held: 1 },
        'The founder\'s OpenRouter hold is on (every llm_route_health route is open), so no model was called and this intake was run by the deterministic interview, which is the designed path under the hold.');
    }
    else if (!llmCallOk) { await logRun('error', { llm_call_ok: 0, llm_parse_ok: 0, keyword_fallback_used: 1 }, 'Intake LLM call failed for every model (or the OpenRouter key is missing), so this customer\'s brief was assembled by the crude keyword fallback instead of real comprehension — the RFQ may be mis-categorised, under-specified, or held at \'needs_info\' forever, and the customer will never learn why.'); }
    else if (!llmParseOk) { await logRun('error', { llm_call_ok: 1, llm_parse_ok: 0, keyword_fallback_used: 1 }, 'Intake LLM replied with unparseable JSON, so this customer\'s brief fell back to keyword guessing rather than the model — the brief that suppliers eventually quote against is degraded and may name the wrong trade.'); }

    // HELD, NOT GUESSED (23 Sep 2026, founder_instruction 886-903). With no model reading, the trade used
    // to come from the keyword map (detectCat / detectTrades), which filed "ground floor fire alarm" under
    // flooring. Now the trade is REASONED (think(), tradeOf over every category) — and while that reasoning
    // is held the inquiry is HELD: status 'held', nothing is decided, the customer is told it is being
    // reviewed, and fn_reason_held_resolve sets the reasoned trade the moment the hold lifts (the portal
    // then continues the interview). A trade already reasoned for this draft (brief.category_by) stands.
    // ONLY WHEN THERE IS NO TRADE (27 Oct 2026, turn_clock.ts). This reasoned the trade again on every turn the model
    // call failed, even when an earlier turn had stored one, which per the rule above already stands: production turn
    // 27 Oct 10:28 UTC spent 73 s here. A trade stored, or the drawing's, is kept and the interview continues on it.
    if (!out && !category && allText.trim() && !(draft.brief && draft.brief.category_by === 'reasoning')) {
      const t = await tradeOf(defaultDeps(admin, 'inquiry_intake'), {
        conversation: allText, candidates: validSlugs.map((slug: string) => ({ slug, label: slug.replace(/[-_]/g, ' ') })),
        dedupeKey: 'intake_trade:' + draft.id, deadline: clock.deadline(),
        // a harness customer's question is never queued for a paid replay (think.ts isFixtureRequest)
        subject: { intake_id: draft.id, ...(email.endsWith('@example.invalid') ? { fixture: true } : {}) },
      });
      if (t.value && validSlugs.includes(t.value)) {
        // The reasoned trade replaces the keyword one everywhere the deterministic interview reads it.
        category = t.value;
        const { data: cs } = await admin.from('category_specs').select('fields').eq('category', category).maybeSingle();
        checklist = Array.isArray(cs?.fields) ? cs.fields : [];
        draft.brief = { ...(draft.brief && typeof draft.brief === 'object' ? draft.brief : {}), category_by: 'reasoning' };
      } else {
        const heldDraft = ar
          ? 'شكرًا لكم. استلمنا طلبكم، ويراجعه الآن مهندس المبيعات لدينا لتحديد التخصص المناسب بدقة. سنكمل معكم هنا فور الانتهاء، ولا حاجة إلى إعادة كتابة أي شيء.'
          : 'Thank you — we have your request and our sales engineer is reviewing it now to identify exactly the right trade. We will continue with you here as soon as that is done; there is no need to type anything again.';
        // the model says it (1339); the draft itself only when OpenRouter is down. A reply-writing call: replyDeadline.
        const hv = llmDown ? { text: heldDraft, by: 'outage_fallback' as const }
          : await intakeVoice(defaultDeps(admin, 'inquiry_intake'), { draft: heldDraft, lang: ar ? 'ar' : 'en', message: text, conversation: turns, deadline: clock.replyDeadline() });
        const heldMsg = hv.text;
        // a refused turn is filed for the re-ask (fileReask above): no empty message, no code text
        const reaskTid = hv.by === 'none' ? await fileReask(heldDraft + '\nAsk no question unless the message above asks one.', hv.problems) : null;
        if (heldMsg) turns.push({ role: 'assistant', text: heldMsg, agent: ACTOR });
        if (heldMsg && photoStamp.length) turns[turns.length - 1].photo_readings = photoStamp;   // the reading stays in the context (ruling 1200)
        // A TURN THAT WAS NOT SAVED IS NOT ANSWERED AS IF IT WERE (3 Nov 2026, it_engineer, drill D10). This write's
        // result was never read: with PostgREST answering 503 PGRST000 / 504 PGRST003 (database restarting, pool
        // exhausted) the customer got ok:true and a reply while their message was on no row. supabase-js never retries a
        // PATCH, so the caller is told, as the draft insert above already does; the portal's resend carries the same
        // turn_id and placeUserTurn records it once. prevented by: supabase/functions/inquiry_intake/drill_database_unavailable.test.ts
        const { error: heldSaveErr } = await admin.from('inquiry_intake').update({ status: 'held', raw_input: allText.slice(0, 4000), turns, updated_at: new Date().toISOString() }).eq('id', draft.id);
        if (heldSaveErr) {
          await logRun('error', { intake_saved: 0, intake_held: 1 }, 'Held intake turn could not be saved to inquiry_intake (' + String(heldSaveErr.message) + ') - the customer was told to send it again; nothing of this turn is on the row.');
          return J({ error: 'intake_unavailable', message: 'Your request could not be saved. Nothing has been submitted - please try again.' }, 503);
        }
        recordExchange(heldMsg);
        await logRun('ok', { model_held: 1, intake_held: 1, llm_http: llmFail.v?.http ?? null, llm_error: llmFail.v?.error ?? null }, 'the trade could not be reasoned (' + (t.result.reason ?? 'held') + '), so the intake is held for review rather than guessed from keywords' + (llmFail.v ? '; gateway HTTP ' + llmFail.v.http + ' ' + llmFail.v.error + ' ' + llmFail.v.detail : ''));
        return J({ ok: true, intake_id: draft.id, status: 'held', category: null, trades: [], assistant_message: heldMsg, questions: [], next_question: null,
                   readiness: { filled: 0, required: 0, score: 0 }, readiness_score: 0, missing: [], brief: null, held_id: t.result.held_id ?? null, // The gateway's reason goes back only to our own harness subject; a customer never sees upstream detail.
                   ...(email.endsWith('@example.invalid') ? { held_reason: t.result.reason ?? 'held', llm_failure: llmFail.v } : {}), reply_by: hv.by,
                   pending: reaskTid !== null, ...(reaskTid ? { reask_turn_id: reaskTid } : {}), agent: ACTOR });
      }
    }

    // THE MODEL EXTRACTS, THE ROW DECIDES (7 Oct 2026, sales_engineer; ./slots.ts says what was measured).
    // Slots the model read this turn are merged with the ones earlier turns captured; status and missing
    // are derived from them, and a sentence written for a status the row does not hold is replaced.
    let slotDetails: Record<string, string> | null = null;
    let slotMissingKeys: string[] = [];
    let slotExhausted: string[] = [];
    let slotAsk: { key: string; text: string } | null = null;
    let slotRecorded: string[] = [];                       // keys this turn recorded, with the words they came from (stamped)
    let slotEvidence: Record<string, string> = {};
    let toldNow = false;                                   // this message told us something (stamped: stallOf does not count it)
    const slotUnknown = new Set<string>();   // specs the customer does not know: never asked again (slots.ts reconcileSlots)
    // The spec a held intake asks this turn (slots.ts heldAsk); remembered on the row so the next message is read
    // as its answer by code (readHeldAnswer), the way the deterministic interview reads asked_key.
    let heldNext: { key: string; text: string; options: string[] | null } | null = null;
    const slotLang = ar ? 'ar' : 'en';
    // Turn 1 has no stored trade, so the checklist is empty until the model names one: load the model's
    // trade's checklist here, or what the first message states is read against nothing and lost.
    if (out && llmParseOk && !checklist.length && out.category && validSlugs.includes(String(out.category))) {
      const { data: cs1 } = await admin.from('category_specs').select('fields').eq('category', String(out.category)).maybeSingle();
      if (Array.isArray(cs1?.fields)) checklist = cs1.fields;
    }
    // THE TRADES IN THE WHOLE TAXONOMY (ledger 1586): the codes the model placed this request in, kept only when they exist;
    // when they are new to the state, their packs are read now (one bounded read) so this turn's checklist already carries
    // the trade's own specs and the next turn's prompt its services and location rules.
    const modelCodes = out && llmParseOk ? validCodes(out.trade_codes, taxonomy) : [];
    let codesNow = modelCodes.length ? modelCodes : (st?.trade_codes ?? []);
    if (modelCodes.length && modelCodes.join() !== (tradeCtx?.codes ?? []).join()) tradeCtx = (await tradeContext(admin, modelCodes, ar ? 'ar' : 'en', taxonomy)) ?? tradeCtx;
    // THE PLACEMENT FOLLOWS THE CHOSEN SERVICES (evidence run of 10 Nov 2026, finding b1; _shared/inquiry_trades.ts
    // placeTrades): the trade that owns the chosen services is the placed trade, and a job one supplier type does is one
    // trade. The model's codes are the input; the services it named (and the ones the state or the chosen option hold)
    // decide. A placement that differs from the context read is read again, so the checklist asked IS the placed trade's.
    const keysIn = out && llmParseOk ? validServiceKeys(out.service_keys, tradeCtx?.services) : [];
    const heldKeys = (solution0: ReturnType<typeof readSolution> | null) => (solution0?.chosen_option ? serviceKeysOfChoice(solution0.chosen_option) : stateServiceKeys(st));
    const placement: Placement | null = codesNow.length ? placeTrades(codesNow, [...new Set([...heldKeys(out && llmParseOk ? readSolution(out) : null), ...keysIn])]) : null;
    if (placement && placement.by === 'services') {
      codesNow = placement.codes;
      if (codesNow.join() !== (tradeCtx?.codes ?? []).join()) tradeCtx = (await tradeContext(admin, codesNow, ar ? 'ar' : 'en', taxonomy)) ?? tradeCtx;
    }
    // The job's checklist(s): the ones the model named this turn, else the ones held from an earlier turn, else each trade's first.
    const modelTopics = out && llmParseOk ? validTopics(out.checklist_topics, tradeCtx) : [];
    const topicsNow: string[] = modelTopics.length ? modelTopics : validTopics(prevTopics, tradeCtx);
    // The trades whose site-visit condition the model judged applies to this job (a known condition on the brief).
    const siteVisitNow: string[] = out && llmParseOk && Array.isArray(out.site_visit) ? out.site_visit.map(String).filter((c: string) => (tradeCtx?.codes ?? []).includes(c)) : [];
    // THE ONE PHOTO ASK (founder ledger 1704): due on the first turn a visit applies to a trade whose checklist names shots, and never
    // again (the stamp on the turn and the record's `asked`). Optional: nothing below reads it for status or readiness. Photos the
    // portal sends (body.site_photos: each by its check job) are recorded by job, with the shot they answer.
    // Stamped also when the model asked by itself on a turn with no site_visit (photos_asked true; review item 7), so it is never
    // asked twice.
    const photoTurn = photoAskOfTurn(tradeCtx, topicsNow, siteVisitNow, turns, photoRecord, !!(out && llmParseOk && out.photos_asked === true));
    const photoAsk = photoTurn.shots;
    checklist = withPack(checklist, tradeCtx, String((out && out.category) || category || ''), topicsNow);
    // What the model put to them and what they chose (rule 13), and the services of their trades it named.
    const solution = out && llmParseOk ? readSolution(out) : null;
    // The service keys of the placed trades only (placeTrades): a request is never sent to a trade it was not placed in.
    const modelServiceKeys = placement && placement.by === 'services' ? keysIn.filter((k) => placement.keys.includes(k)) : keysIn;
    if (out && llmParseOk && checklist.length && out.status !== 'rejected') {
      // What the request's state recorded on any turn (the portal chat included) is held too, under the row's own details
      // (ruling 1631: read the history, never repeat; blocking_gate.ts recordedSpecs). Before 12 Nov only the row's details
      // were, so a spec the state held and the model's brief left out was asked again (final audit H1).
      const prevDet0 = { ...recordedSpecs(st, null), ...((draft.brief && typeof draft.brief === 'object' && draft.brief.details && typeof draft.brief.details === 'object') ? draft.brief.details : {}) };
      // THE ANSWER TO THE SPEC A HOLD ASKED IS READ BY CODE FIRST (27 Oct 2026, ledger 580; slots.ts says why).
      const heldKey = draft.brief && draft.brief.asked_on_hold === true ? String(draft.brief.asked_key || '') : '';
      // With the model's reading on this turn, code takes only a TAPPED option of the held spec (slots.ts tappedHeldAnswer).
      const heldVal = heldKey && !(heldKey in prevDet0) ? tappedHeldAnswer(checklist, heldKey, text) : null;
      const prevDet = heldVal ? { ...prevDet0, [heldKey]: heldVal } : prevDet0;
      const firstUser0 = String(turns.find((t: any) => t.role === 'user')?.text || allText);
      // NEVER ASKED AGAIN (ledger 1572): what the state holds as "does not know" (any turn, the portal chat included), what
      // this message said it does not know to the spec asked last (unknownNow), and the model's own unknown_keys.
      const modelUnknown = Array.isArray(out.unknown_keys) ? out.unknown_keys.map(String).filter((k: string) => checklist.some((f: any) => f && String(f.key) === k)) : [];
      for (const k of modelUnknown) if (!(k in unknownNow)) unknownNow[k] = text.slice(0, 200);
      const unknownKeys = new Set([...Object.keys(st?.unknown ?? {}), ...Object.keys(unknownNow)]);
      for (const k of unknownKeys) slotUnknown.add(k);   // a key filled after all is not open, so it is never held for this
      // A pack spec of the job they do not know is ANSWERED as "supplier to advise" (ledger 1587), so it is never held for.
      const packNow = packFields(tradeCtx, topicsNow);
      const prevDetAdvised = adviseUnknown(withUniversal(prevDet, packNow, universalAnswers({ specs: { ...(st?.specs ?? {}), ...prevDet }, emirate })), packNow, unknownKeys);
      // The customer's own words, so a detail the model cites is checked against what they actually wrote (rule 16, finding b2).
      // Did this message answer anything outside the checklist (the four questions, a "does not know")? Then a waiting question
      // is not asked again on this turn (slots.ts reconcileSlots `waiting`).
      const reqPrev0: Answers = (draft.brief && typeof draft.brief === 'object' && draft.brief.req_answers && typeof draft.brief.req_answers === 'object') ? draft.brief.req_answers : {};
      // a new answer, or one this message changed (the model's changed_answers: "actually supply only")
      const reqChangedNamed = new Set(Array.isArray(out.changed_answers) ? out.changed_answers.map(String) : []);
      const reqNewNow = Object.entries(requirementsFromModel(String(out.category || category || ''), out.requirements))
        .some(([k, a]) => !reqPrev0[k] || (reqChangedNamed.has(k) && JSON.stringify(reqPrev0[k]) !== JSON.stringify(a)));
      const settled = settleModelTurn(checklist, prevDetAdvised, out, slotLang, (d) => buildBrief(String(category || out.category || ''), d, allText, emirate, firstUser0), askedTurnsByKey(turns), slotUnknown, allText,
        { recordedElsewhere: reqNewNow || modelUnknown.some((k: string) => !(st?.unknown ?? {})[k]), lastText: text, stall: stallOf(turns), lastAsked: lastAskedKeys(turns),
          rephrase: explainNow.length > 0, phrased: phrasedNow });
      slotDetails = settled.details; slotMissingKeys = settled.missingKeys; slotExhausted = settled.held ? settled.exhausted : [];
      slotRecorded = settled.recorded ?? []; slotEvidence = settled.evidence ?? {};
      toldNow = slotRecorded.length > 0 || reqNewNow || modelUnknown.some((k: string) => !(st?.unknown ?? {})[k]) || Object.keys(unknownNow).length > 0;
      // The state's first askable question and its key: when that is the question asked, the key goes with it.
      slotAsk = slotAskOf(settled);
    }

    let interview: { details: Record<string, string>; asked_key: string | null } | null = null;
    let nextQuestion: { key: string | null; text: string; options: string[] | null; suggested?: string | null } | null = null;
    let readinessFields: { filled: number; required: number } | null = null;
    // THE DETERMINISTIC INTERVIEW WHEN THERE IS NO MODEL READING (./interview_without_model.ts says why it asks what it asks).
    if (!out) ({ out, interview, nextQuestion, readinessFields } = interviewWithoutModel({ ar, draft, tradeCtx, topicsNow, st, emirate, unknownNow, category, checklist,
      text, allText, askOrder, turns, catLabel, photoReads }));

    // A question that restates what the model itself listed as already provided is dropped (./restated_questions.ts).
    dropRestatedQuestions(out);

    // SEMANTIC INTERPRETER IN SHADOW MODE.
    // The model's category used to override the deterministic one unconditionally. Measured on
    // staging: "Aluminium windows: supply and install 40 units, 1200 x 1500 mm, villa in Dubai
    // Marina, powder coated, double glazed" was classified `flooring`. That loaded the flooring
    // checklist, so the intake asked "Which flooring?" and "Remove existing floor / need subfloor
    // levelling?" - questions this customer can never answer. readiness stuck at 40 across ten
    // turns and the inquiry could never be created. The customer was trapped.
    //
    // The keyword layer had it right the whole time (aluminium-and-glass-suppliers, weights 3
    // and 2, zero flooring matches) and was simply discarded. So: when deterministic evidence
    // exists and the model's category has none of it, the deterministic answer stands. The
    // disagreement is returned as classifier_override rather than swallowed, because a
    // suggestion that silently wins is not a suggestion.
    //
    // SUPERSEDED FOR THE MODEL PATH, 23 Sep 2026 (founder_instruction 886-903: "NO word matching
    // anywhere"). The keyword layer no longer overrules the model: a word map read "ground floor" as
    // flooring and "break glass" as glass (_shared/trade_classify.ts says so itself). When the model's
    // trade and the keyword evidence disagree, the disagreement is REASONED — think() weighs the
    // candidates against the customer's whole description (_shared/reasoned_decisions.ts tradeOf) — and
    // the reasoned trade stands. If that reasoning is held, the model's own reading stands; nothing is
    // decided by the word map. LATER THE SAME DAY the map itself was deleted (decision point 19,
    // shared.trade_classify): with no keyword evidence left there is nothing to disagree with.
    const classifierOverride: { model: string; kept: string; by?: string } | null = null;
    let requiredGate: { category: string; missing_keys: string[] } | null = null;
    let cat = out.category || category;
    // No word map is left to disagree with the model (23 Sep 2026): the model's trade stands, or the trade a
    // previous turn stored; with neither it is 'general' — no trade, never the nearest one.
    if (!cat || (!validSlugs.includes(cat) && cat !== 'general')) { cat = (validSlugs.includes(String(draft.category)) ? draft.category : null) || 'general'; }
    // The category follows the placement (finding b1): the placed primary trade's own slug when it has one ('wallpaper',
    // 'hvac', 'swimming-pools'); a trade with no slug keeps the model's category, as before.
    const placedSlug = placement && placement.by === 'services' ? slugOfTrade(placement.primary, validSlugs) : null;
    if (placedSlug) cat = placedSlug;
    category = cat;
    let status = ['rejected', 'needs_info', 'ready', 'held'].includes(out.status) ? out.status : 'needs_info';
    let settleOfferNow = false;   // this reply offers the sales engineer's help (said once per conversation; stamped on the turn)
    // HELD FOR SPECS (slots.ts MAX_OPEN_TURNS): only questions the customer has not answered in three turns are
    // left. The request is not ready and goes to no supplier; the sales engineer gets the same handoff the
    // not-sure path opens (kind spec.not_sure, registered), subject this intake. One per intake (fn_seat_handoff).
    if (status === 'held' && slotExhausted.length) {
      const { error: hErr } = await admin.rpc('fn_seat_handoff', { p_from: 'customer_support', p_to: 'sales_engineer', p_type: 'spec.not_sure',
        p_subject_table: 'inquiry_intake', p_subject_id: String(draft.id),
        p_payload: { intake_id: draft.id, customer_id: cust?.id || null, not_sure: slotExhausted, category,
          waiting_for: 'sales_engineer to help the customer settle these specs; asked three times without an answer' } });
      if (hErr) await logRun('error', { spec_handoff_failed: 1 }, 'intake held for unanswered specs but the sales_engineer handoff failed: ' + hErr.message);
      // The hold asks: the first open spec goes out as next_question with the checklist's options to tap, and every
      // open spec stays in questions / missing (slots.ts settleModelTurn), so a held turn never asks nothing.
      // A spec they said they do not know is never asked again, not even by the hold: only the specs asked three times
      // without an answer are offered again; when only unknown specs are left the reply says the sales engineer settles them.
      const askAgain = slotExhausted.filter((k) => !slotUnknown.has(k));
      heldNext = heldAsk(checklist, askAgain, slotLang);
      if (heldNext) nextQuestion = heldNext;
      // The customer is told WHICH questions are still open, by the model, in the inquiry language (slots.ts heldReply).
      // On the turn's clock (it had its own 40 s), but a reply always gets a real model attempt (turn_clock.ts
      // replyDeadline, the founder's ruling of 27 Oct): the open questions are listed by code only if the model fails.
      // The one question asked is heldNext's (its buttons go with it), and the sales engineer is offered once per conversation.
      const settleOffered = turns.some((t: any) => t && t.role === 'assistant' && t.settle_offered === true);
      const hr = askAgain.length ? await heldReply(defaultDeps(admin, 'inquiry_intake'), checklist, askAgain, slotLang, text, turns, clock.replyDeadline(),
          { ask: heldNext ? { key: heldNext.key, text: heldNext.text, options: heldNext.options } : null, offerSettle: !settleOffered, answer: meaning })
        : { text: '', outage: false, by: 'none' as const };
      if (askAgain.length && !settleOffered) settleOfferNow = true;
      // the model's held reply; the code list back means OpenRouter was down (1339); '' means the model is up but nothing
      // it wrote passed, so it is asked again below (intakeVoice) with the hold as its draft
      if (hr.by === 'outage_fallback') llmDown = true; else if (hr.by === 'model') modelWrote = hr.text;
      out.assistant_message = hr.text || (askAgain.length ? heldDraftOf(checklist, askAgain, slotLang, settleOfferNow) : unknownHeldDraft(checklist, slotExhausted, slotLang));
      clock.lap('held_reply');
    }
    // Stamp the answering agent on the turn so the next turn knows the specialist has already introduced itself.
    turns.push({ role: 'assistant', text: out.assistant_message || '', agent: ACTOR });
    // THE PHOTO'S READING STAYS IN THE CONTEXT (ruling 1200): stamped on this reply's turn, so a later turn without the photo still
    // asks from it (_shared/photo_reading.ts readingsOf). Internal: the turns never reach a supplier.
    if (photoStamp.length) turns[turns.length - 1].photo_readings = photoStamp;

    let trades = Array.isArray(out.trades) ? out.trades.map((s: any) => String(s)).filter((s: string) => validSlugs.includes(s)) : [];
    // ONE TRADE IS ONE TRADE (finding b1): a placement of one trade is one slug, whatever slugs the model listed beside it,
    // so the composer offers no "one contractor or separate quotes" choice for a job one supplier type does. A multi-trade
    // placement lists the placed trades' own slugs first.
    if (placement && placement.by === 'services') {
      const placedSlugs = placement.codes.map((c) => slugOfTrade(c, validSlugs)).filter((x): x is string => !!x);
      trades = placement.multi ? [...new Set([...placedSlugs, ...trades])] : (category && validSlugs.includes(category) ? [category] : []);
    }
    if (category && validSlugs.includes(category) && !trades.includes(category)) trades.unshift(category);
    if (trades.includes('flooring') && trades.includes('tiling')) trades = trades.filter((c: string) => c !== 'tiling');
    trades = Array.from(new Set(trades)).slice(0, 6);
    const urgency = ['emergency', 'urgent', 'normal'].includes(out.urgency) ? out.urgency : detectUrgency(allText);
    const plausibility = (out.plausibility && typeof out.plausibility === 'object') ? out.plausibility : null;
    let provenance = (out.provenance && typeof out.provenance === 'object') ? out.provenance : null;

    // ONE DEFINITION OF READY.
    // The intake used to declare 'ready' on the model's own say-so. dispatch is gated by
    // inquiries.rfq_ready, which the rfq_complete trigger computes from fn_rfq_score against the
    // CANONICAL keys in category_specs.fields. The model answered in its own vocabulary -
    // window_type, finish, accessories - while the scorer looked for element and dimensions_qty,
    // so a request the customer had fully answered scored 3 of 4 and the RFQ was created and then
    // never dispatched. dispatch_inquiry reports that as {skip:'not_rfq_ready'} and nothing
    // surfaces it: the customer sees their inquiry listed and simply never hears from a supplier.
    //
    // Required fields are now checked deterministically, under the same keys the scorer reads.
    // The model does not get to vote itself ready.
    if (status === 'ready' && category) {
      const { data: specRow } = await admin.from('category_specs').select('fields').eq('category', category).maybeSingle();
      const required = Array.isArray(specRow?.fields)
        ? specRow.fields.filter((f: any) => f && f.required && f.key)
        : [];
      const b = (out.brief && typeof out.brief === 'object') ? out.brief : {};
      const det = (b.details && typeof b.details === 'object') ? b.details : {};
      if (!b.details || typeof b.details !== 'object') b.details = det;
      if (slotDetails) for (const [k, v] of Object.entries(slotDetails)) if (det[k] === undefined) det[k] = v;
      // THE ANSWER UNDER ITS KEY IN details COUNTS, WHATEVER THE SUMMARY FIELD BESIDE IT SAYS (15 Nov 2026, journey A). This read
      // the brief's top-level field first (b.scope ?? det.scope): the summary's "scope" is '' until a request is ready (the prompt
      // lets it be), and '' is not null, so a scope recorded in details read as absent and "Supply and install?" was asked
      // again after the customer said it. Either place counts; an empty one never hides the other.
      const has = (v: unknown) => v !== undefined && v !== null && String(typeof v === 'object' ? JSON.stringify(v) : v).trim() !== '';
      const isAbsent = (f: any) => !has(det[f.key]) && !has(b[f.key]);
      // EXACT SPEC BY REASONING (23 Sep 2026, founder_instruction 886-903). fn_rfq_required_check used to
      // count a required spec as answered when a 4-letter token of any of its option labels appeared
      // anywhere in the text ("no preference on the frame" answered frame_material). That scan is gone
      // (scripts/sql/meaning_is_decided_by_reasoning_not_by_word_lists.sql). A field the brief left blank
      // is asked of think(): has the customer ALREADY stated it? It is filled only with the customer's own
      // words as evidence (the validator refuses a value it cannot find verbatim), and marked 'reasoned'.
      // Held: nothing is filled, and the field is simply asked.
      // ON THE TURN'S CLOCK (27 Oct 2026, turn_clock.ts): this reading was 60-125 s of every turn the model called
      // ready. It is now one reader pass (reasoned_decisions.ts statedSpecs), started alongside the interview call
      // (specRead) and cut at the clock. Not run, or not finished: nothing is filled and every blank field is asked
      // below — the gate holds.
      const blank = required.filter(isAbsent);
      // The reading started alongside the interview call answers for this trade; a trade the call changed is read
      // now, and only with MIN_STEP_MS left on the clock.
      const reading = !blank.length ? null
        : specRead && specRead.category === category ? specRead.p
        : clock.canStart() ? startReading(category, blank) : null;
      if (reading) {
        const stated = await reading;
        clock.lap('exact_spec');
        for (const [k, v] of Object.entries(stated?.value ?? {})) {
          if (v.value && blank.some((f: any) => f.key === k)) { det[k] = v.value; provenance = { ...(provenance || {}), [k]: 'reasoned' }; out.provenance = provenance; }
        }
      }
      const absent = required.filter(isAbsent);
      if (absent.length) {
        status = 'needs_info';
        out.status = 'needs_info';
        // the customer reads each open spec in plain words in his language (interview.ts questionsFor), never its English label
        // (review REVIEW_plain item 4: an Arabic chat got the English question here while the blocking gate below was plain)
        out.missing = questionsFor(absent, slotLang);
        out.questions = questionsFor(absent.slice(0, 4), slotLang);
        out.readiness = Math.min(Number(out.readiness) || 0, 80);
        // The model (or the slots) said 'ready' and the canonical gate did not agree: the reply is the state's.
        out.assistant_message = replyFromState('needs_info', out.questions[0] || null, slotLang);
        slotDetails = { ...(slotDetails || {}), ...Object.fromEntries(Object.entries(det).filter(([, v]) => v !== undefined && v !== null && String(v).trim() !== '').map(([k, v]) => [k, typeof v === 'object' ? JSON.stringify(v) : String(v)])) };
        // The brief exists but is not canonical; say which keys were wanted so the next turn can
        // ask for them by name instead of re-asking the whole checklist.
        requiredGate = { category, missing_keys: absent.map((f: any) => String(f.key)) };
      }
    }

    // ── THE BLOCKING SPECS OF EVERY PLACED TRADE (10 Nov 2026, founder ledger 1587) ──────────────────────────────────
    // "The interview happens ONCE ... complete enough that every supplier can quote without asking for a missing detail."
    // After the slug's canonical keys, the trades' own rule: every blocking spec of the job's checklist(s) answered, in the
    // state's specs or this turn's details, or recorded as "does not know" (sent as "supplier to advise"). On the model path
    // and the deterministic interview alike, so neither the model nor the slots can call a request ready without them.
    const specsHeld: Record<string, unknown> = { ...(st?.specs ?? {}), ...(slotDetails || {}), ...((interview && interview.details) || {}),
      ...((out.brief && typeof out.brief === 'object' && out.brief.details && typeof out.brief.details === 'object') ? out.brief.details : {}) };
    // The universal fields (payment terms, location and emirate, needed by, budget) are ONE answer for the whole request,
    // whichever trades list them: the held key, the emirate the conversation states, the four questions' date, the budget.
    const reqHeld: any = (draft.brief && typeof draft.brief === 'object' && draft.brief.req_answers) || {};
    const reqBy = reqHeld.required_by?.text ?? reqHeld.required_by?.date ?? (out && llmParseOk && category ? requirementsFromModel(category, out.requirements).required_by?.text : null) ?? null;
    const universalNow = universalAnswers({ specs: specsHeld, emirate, required_by: reqBy ? String(reqBy) : null,
      budget: st?.budget?.value ?? (typeof out?.brief?.budget === 'string' ? out.brief.budget : null) });
    const gate = blockingGate(status, tradeCtx, topicsNow, specsHeld, [...slotUnknown, ...Object.keys(st?.unknown ?? {}), ...Object.keys(unknownNow)], siteVisitNow, universalNow);
    if (gate.status !== status) {
      status = gate.status; out.status = gate.status;
      // the customer reads each open spec in plain words in their language (interview.ts questionText), never its label
      const plainQ = (o: { key: string; question: string }) => { const f = checklist.find((x: any) => x && String(x.key) === o.key); return f ? questionText(f, slotLang) : o.question; };
      out.missing = gate.verdict.open.map(plainQ);
      out.questions = gate.verdict.open.slice(0, 4).map(plainQ);
      out.readiness = Math.min(Number(out.readiness) || 0, 80);
      out.assistant_message = replyFromState('needs_info', out.questions[0] || null, slotLang);
      requiredGate = { category: String(category || 'general'), missing_keys: gate.verdict.open.map((o) => o.key) };
    }

    // THE SALES ENGINEER'S FOUR QUESTIONS, AND THE EMIRATE BEFORE THEM (founder, 14 Sep 2026; ./four_questions.ts).
    const reqLang = ar ? 'ar' : 'en';
    const prevBrief: any = (draft.brief && typeof draft.brief === 'object') ? draft.brief : {};
    const fq = fourQuestions({ ar, prevBrief, out, llmParseOk, category, placed, text, emirate, status, interview, turns, slotRecorded, allText, slotLang, nextQuestion });
    status = fq.status; nextQuestion = fq.nextQuestion;
    const { reqAnswers, reqAsked, reqRemaining, reqProgress, emirateAsked } = fq;

    // THE DRAWING'S OPEN LINES AND THE CAD ASK (14 Sep 2026; ./drawing_open_lines.ts).
    let tradeCodes: string[] = [];   // the taxonomy codes the count resolved (kept on the state as trade_codes)
    const dr = drawingOpenLines({ drawingBoq, prevBrief, text, status, ar, out, nextQuestion });
    nextQuestion = dr.nextQuestion;
    const { boqCheck, boqAsked, cadAsked } = dr;

    const brief = status === 'ready' ? (out.brief || null) : null;
    // the service keys the choice names: this turn's choice, else the one the state holds (any earlier turn, the portal's)
    const chosenKeys = solution?.chosen_option ? serviceKeysOfChoice(solution.chosen_option) : stateServiceKeys(st);
    if (brief) {
      if (codesNow.length) brief.trade_codes = codesNow;
      if (chosenKeys.length || modelServiceKeys.length) brief.service_keys = [...new Set([...chosenKeys, ...modelServiceKeys])];
      if (boqCheck) brief.boq_check = boqCheck;
      brief.category = category;
      // only an emirate on the closed list is stored (A1): the model's value when it is one, else the one held, else none.
      // With no model reading this turn (OpenRouter down: the deterministic interview built the brief) its own is kept.
      if (!llmParseOk && isAlAin(brief.emirate)) alAin = true;   // the deterministic interview read "Al Ain" as the place
      brief.emirate = emirate ?? (llmParseOk ? '' : emirateOf(brief.emirate) ?? '');
      brief.al_ain = alAin && brief.emirate === 'Abu Dhabi';
      if (emirate && !brief.location) brief.location = emirate;
      brief.trades = trades;
      brief.urgency = urgency;
      if (plausibility) brief.plausibility = plausibility;
      if (provenance) brief.provenance = provenance;
      // The four answers, in the stored contract shape create_inquiry copies onto the RFQ, and the
      // same answers as the summary card shows them for editing before Send.
      brief.requirements = toStored(category, reqAnswers, new Date());
      brief.requirement_questions = forCard(category, reqAnswers, reqLang);
      brief.recorded_by = ACTOR;
      // What the suppliers must advise and the known conditions (a site visit before a final price), on the brief and in
      // its details, which create_inquiry copies onto inquiries.spec (ledger 1587: nothing a supplier needs is hidden).
      briefConditions(brief, gate.verdict);
      brief.checklist_topics = topicsNow;

      // ── §3 THE TWO THINGS THE SPEC'S ASSISTANT SAYS BEFORE THE CUSTOMER PRESSES SEND ───────────
      // The spec's §3 panel is: "Required Documents: ✓ Technical specs ✓ Delivery timeline
      // ✓ Warranty" and "Recommended Suppliers: 18". Both were computable and neither was computed,
      // so the customer confirmed a brief without knowing what it would be asked for or how far it
      // would reach.
      //
      // REQUIRED DOCUMENTS: category_specs.compliance_checklist, the same list create_inquiry copies onto the RFQ (./required_documents.ts).
      // The documents list and the supplier count read different things and run together (27 Oct 2026, turn_clock.ts).
      const docsP = readRequiredDocuments(brief, category, emirate);

      // THE SUPPLIER COUNT IS THE REAL FAN-OUT, RUN BEFORE DISPATCH. fn_match_capability is the
      // same routine the dispatch path uses, called with the same trades and emirate, so the number
      // shown here is the number that will actually be reached — not an estimate of it. It is
      // capped at the dispatch limit rather than reported raw, because "18 suppliers" has to mean
      // eighteen suppliers will get this brief.
      // AND WITH THE SERVICES, OR IT IS NOT THE SAME CALL (22 Sep 2026, finding SP-F-01). From this
      // date the dispatch path passes p_services: when the brief names a service, only a supplier
      // whose confirmed service list covers one of them is invited. A count taken WITHOUT the
      // services would be a larger number than the fan-out it promises to be — the count and the
      // dispatch have to ask the same question. The keys are read from the customer's own words
      // and the drawing's BOQ exactly or by meaning (_shared/service_vocabulary.ts; no alias word since
      // 29 Sep 2026, ruling 890); a brief that names no known service, or one too long to read whole,
      // sends '{}' and the count stays trade-level, as before.
      // THE TRADES GO IN AS TAXONOMY CODES, AS DISPATCH SENDS THEM (10 Nov 2026, design audit: this passed the raw intake
      // slugs, so for 39 of the 56 trades — 'glass' is 'glazing', 'fitout' is 'interior_fitout', 'carpentry-joinery' is
      // 'joinery' — the card said 0 suppliers where dispatch would reach some). supplier_count.ts resolves them through
      // fn_taxonomy_trades_for exactly as sales_engineer/actions/operator.ts does before fn_match_capability.
      const countP = (async () => { try {
        // THE SERVICES ARE THE ONES THE MODEL NAMED OR THE CUSTOMER CHOSE (10 Nov 2026, ledger 1572/1573/1579/1586; 11 Nov 2026,
        // rulings 1627 and 1628): the state's keys, the chosen option's and the ones this model named for the job's trades, each
        // checked against the live vocabulary. None: the count is trade level, as dispatch is (sales_engineer operator.ts); the
        // prose is never read for keys by words or vectors (service_vocabulary.serviceKeysOf is deleted). The taxonomy codes sit
        // beside the slugs, so the card counts the same suppliers create_inquiry sends it to.
        const vocabNow = await serviceVocabKept();
        const live = new Set(vocabNow.map((v) => v.trade_code + '.' + v.code));
        const chosen = [...new Set([...stateKeysInVocab(await stateP, live), ...chosenKeys, ...modelServiceKeys])].filter((k) => live.has(k));
        const services = chosen;
        const c = await supplierCount(admin, { trades: [...new Set([...(trades.length ? trades : [category]).filter(Boolean) as string[], ...codesNow])], emirate: emirate || emirateOf(brief.emirate) || null, services });
        if (chosen.length) brief.service_keys = chosen;
        brief.supplier_count = c.count;
        brief.supplier_count_basis = c.basis;
        tradeCodes = c.codes;
      } catch (_e) { brief.supplier_count = null; brief.supplier_count_basis = 'matcher unavailable at intake time'; } })();
      // Both are shown on the summary card, neither decides anything: if they are not done by the clock the turn
      // answers without them (create_inquiry copies the documents list itself, and dispatch counts for itself).
      if (!(await within(Promise.all([docsP, countP]), clock.left(1_000)))) {
        if (brief.supplier_count === undefined) { brief.supplier_count = null; brief.supplier_count_basis = 'not counted within the turn; dispatch counts for itself'; }
        if (brief.required_documents === undefined) { brief.required_documents = []; brief.required_documents_source = 'not read within the turn; create_inquiry copies the checklist itself'; }
      }
      clock.lap('ready_reads');
    }

    // While the deterministic interview is running, `brief` carries its state — the answers so far
    // under their canonical keys, and which key was just asked, so the next message is parsed as the
    // answer to THAT question. create_inquiry only reads brief from a row whose status is 'ready'.
    // req_answers / req_asked carry the sales engineer's questions across turns exactly as details /
    // asked_key carry the category interview's.
    const drawingState = { ...(boqCheck ? { boq_check: boqCheck } : {}), boq_asked: boqAsked, cad_asked: cadAsked };
    const briefToSave = brief
      ? { ...brief, req_answers: reqAnswers, emirate_asked: emirateAsked, ...drawingState }
      // the emirate the model read on a turn that is not ready yet is kept (review of #1979: it was lost, and a later turn
      // where the model gave none counted across the UAE)
      : { ...(emirate ? { emirate, al_ain: alAin && emirate === 'Abu Dhabi' } : {}), emirate_asked: emirateAsked, details: interview ? interview.details : (slotDetails || prevBrief.details || {}), asked_key: interview ? interview.asked_key : (heldNext ? heldNext.key : null), ...(heldNext ? { asked_on_hold: true } : {}), state: 'interview', req_answers: reqAnswers, req_asked: reqAsked, checklist_topics: topicsNow, ...drawingState };
    // The photo record is NOT part of the brief this turn writes whole (review item 4): it is recorded after the save, in one
    // statement on its own column (recordSitePhotos), so a photo uploaded during this turn is never dropped by it.
    // The question card, the readiness bar and every open question (./question_card.ts).
    const card = questionCard({ checklist, status, requiredGate, out, slotAsk, slotLang, category, reqProgress, reqRemaining, readinessFields, nextQuestion });
    readinessFields = card.readinessFields; nextQuestion = card.nextQuestion;
    const { remainingQuestions } = card;
    // The reply is final only here (the canonical gate, the four questions and the drawing check all
    // rewrite it after the assistant turn was pushed). Save the CORRECTED reply, so a false "ready" is
    // neither kept in the history nor fed back to the model next turn (review of #1277).
    // THE WORDS ARE THE MODEL'S (founder_instruction 1339). Everything above decided WHAT this turn says. A reply that is
    // not the model's own sentence, untouched, was composed by code — replyFromState (the slots or the canonical gate
    // disagreed with the model's status), the "Thanks, noted. A few quick questions…" lead before the four questions, the
    // drawing confirm question and the CAD ask appended to it, HELD_FOR_SPECS, or the deterministic interview — and is
    // written now by the model from that draft and the one question to ask (slots.ts intakeVoice). A reply-writing call
    // gets clock.replyDeadline() (turn_clock.ts: the clock never turns a reply into code text). The draft goes out only
    // when OpenRouter is down.
    // THE CUSTOMER'S REGISTER (ledger 1572): the model's reading of their dialect, else the state's, else the code's markers.
    // The reply LANGUAGE stays the registered one (ruling 1008: the language selected when the inquiry was created).
    const DIALECTS = ['gulf', 'egyptian', 'levantine', 'msa', 'english', 'arabizi', 'mixed'];
    const modelDialect = out && DIALECTS.includes(String(out.dialect)) ? String(out.dialect) as Dialect : null;
    const register = registerPatch(userTexts(), slotLang);
    const replyDialect: Dialect | null = modelDialect ?? st?.dialect ?? register.dialect ?? null;
    const lastCustomerText = () => userTexts().slice(-1)[0] || '';
    // THE SUMMARY AT THE LIMIT (from message 95): the reply is what the request holds and what is still open, to confirm.
    if (stage === 'summarise' && status !== 'ready') out.assistant_message = summaryAtLimit((briefToSave as any).details, out.missing, ar);   // ./message_limit.ts
    let replyBy = 'model' as 'model' | 'outage_fallback' | 'none';   // asserted, not narrowed: voice() sets it in a closure
    let voiced: { draft: string; problems: string[] } = { draft: '', problems: [] };   // the last draft the model refused
    const voice = async (draftMsg: string) => {
      if (llmDown) { replyBy = 'outage_fallback'; return draftMsg; }
      const v = await intakeVoice(defaultDeps(admin, 'inquiry_intake'), { draft: draftMsg, lang: slotLang, message: text || lastCustomerText(),
        conversation: turns.slice(0, -1), next: nextQuestion ? { text: nextQuestion.text, options: nextQuestion.options } : null, deadline: clock.replyDeadline(),
        state: stateText, rule: stageRule, dialect: replyDialect });
      clock.lap('voice');
      replyBy = v.by;
      if (v.by === 'none') voiced = { draft: draftMsg, problems: v.problems ?? [] };
      return v.text;
    };
    // THE MODEL'S ANSWER TO WHAT THEY ASKED goes first in any reply code composed (review of #1979: at the last of the four
    // questions, or on any other code-written turn, it was dropped). A reply the model wrote itself already answers.
    if (meaning && String(out.assistant_message || '').trim() !== String(modelWrote ?? '').trim() && !String(out.assistant_message || '').includes(meaning)) {
      out.assistant_message = meaning + ' ' + String(out.assistant_message || '');
    }
    // The photo ask is IN the reply on the turn it is due: when the model's own reply did not ask, the list is added to the draft,
    // which the model then voices (1339: the customer reads the model's words).
    if (photoAsk.length && photoTurn.draft) out.assistant_message = `${String(out.assistant_message || '').trim()} ${photoAskDraft(photoAsk, slotLang)}`.trim();
    {
      // SENT AS IT IS (re-check of 15 Nov 2026, item 3): a ready request carrying a "supplier to advise" says so, and names the sales
      // engineer's WhatsApp line, so a customer who did not know some details is never left at a dead end.
      if (status === 'ready' && brief && brief.details && Object.values(brief.details).some((v) => v === SUPPLIER_TO_ADVISE)
          && !String(out.assistant_message || '').includes(SENT_AS_IS[slotLang])) out.assistant_message = `${String(out.assistant_message || '').trim()} ${SENT_AS_IS[slotLang]} ${SALES_ENGINEER_WHATSAPP[slotLang]}`;
      const draftMsg = String(out.assistant_message || '').trim();
      if (draftMsg && draftMsg !== String(modelWrote ?? '').trim()) out.assistant_message = await voice(draftMsg);
    }
    // A PHOTO NOT READ IS NEVER SAID TO BE READ (19 Nov 2026; _shared/photo_reading.ts). The prompt says so; when the reply still
    // says it saw the photo (a check on our reply's words, claimsPhotoSeen), it is written again by the model from what is true.
    if (photoUnread && claimsPhotoSeen(String(out.assistant_message || ''))) {
      out.assistant_message = await voice((unreadLead(photoReads, slotLang) + (nextQuestion?.text ?? '')).trim());
      clock.lap('photo_rewrite');
    }
    // THE REPLY GUARD RUNS ON THIS REPLY TOO (27 Oct 2026). The founder's rule (23 Sep) is that no reply names the licence
    // number or says "AI": the licence sentence is dropped and "AI" becomes "smart" (the model's own words, edited). A reply
    // carrying internal or prompt text is REFUSED and written again BY THE MODEL; the state's code text only when
    // OpenRouter is down (1339).
    const guarded = guardSupportReply(String(out.assistant_message || ''), slotLang);
    if (guarded.violations.length) {
      if (guarded.text) out.assistant_message = guarded.text;
      else {
        const ask = nextQuestion?.text ?? (Array.isArray(out.questions) && out.questions[0] ? String(out.questions[0]) : null);
        out.assistant_message = await voice(replyFromState(status, ask, slotLang));
        clock.lap('guard_rewrite');
      }
    }
    // THE BUBBLE IS NEVER LEFT EMPTY WHILE THE MODEL IS UP (1339; the review of #1646): every draft refused, so the turn is
    // filed for the re-ask and its answer is appended when it is written; the question card below still shows.
    const reaskTid = !String(out.assistant_message || '').trim() && replyBy === 'none'
      ? await fileReask(voiced.draft + (nextQuestion ? '\nTHE ONE QUESTION TO ASK NOW: ' + nextQuestion.text : '\nAsk no question unless the message above asks one.'), voiced.problems)
      : null;
    for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'assistant') { turns[i].text = out.assistant_message || ''; if (reaskTid) turns[i].reask_pending = reaskTid; if (settleOfferNow) turns[i].settle_offered = true; if (photoAsk.length) turns[i].photo_ask = photoAsk.map((p) => p.shot); break; }
    const missingKeys: string[] = status === 'ready' ? [] : (requiredGate ? requiredGate.missing_keys : slotMissingKeys);
    // WHAT THIS REPLY ASKED (slots.ts askedTurnsByKey: a spec is held after three ASKS, and the next question is one not yet asked):
    // the question card's key; else, when the model's own sentence asks, the keys it names ("asked_keys", known specs only), or
    // the state's first open spec when it names none.
    // Only an OPEN REQUIRED spec the model names counts as asked (review of 15 Nov 2026, item 2: a model naming an optional spec while
    // asking something else accrued no ask on any required spec, and the request sat at needs_info for 45 turns); else the state's.
    const openRequired = new Set(slotMissingKeys.filter((k) => !slotExhausted.includes(k)));
    const modelAskedKeys = out && llmParseOk && Array.isArray(out.asked_keys) ? out.asked_keys.map(String).filter((k: string) => openRequired.has(k)) : [];
    const askedKeys: string[] = nextQuestion?.key ? [String(nextQuestion.key)]
      : status !== 'ready' && Array.isArray(out.questions) && out.questions.length ? (modelAskedKeys.length ? modelAskedKeys : slotAsk ? [slotAsk.key] : []) : [];
    stampTurn(turns, { status, details: (briefToSave as any).details || {}, req_answers: reqAnswers, missing: Array.isArray(out.missing) ? out.missing.map(String) : [], missing_keys: missingKeys,
      asked_keys: askedKeys, ...(slotRecorded.length ? { recorded: slotRecorded, evidence: slotEvidence } : {}), ...(toldNow ? { told: true } : {}),
      reply: { next_question: nextQuestion, remaining_questions: remainingQuestions, readiness: readinessFields } });
    const { error: saveErr } = await admin.from('inquiry_intake').update({ category, status, raw_input: allText.slice(0, 4000), turns, brief: briefToSave, readiness: Math.max(0, Math.min(100, Number(out.readiness) || 0)), missing: out.missing || [], updated_at: new Date().toISOString() }).eq('id', draft.id);
    clock.lap('saved');
    // THE PHOTO RECORD (ledger 1704; review items 2, 4): the ask, the No-photos answer and any photo jobs sent with this turn, added in
    // one statement after the save. Before fn_site_photos_record is applied it records nothing; the stamp on the turn still holds.
    const b_photos = Array.isArray(b.site_photos) ? b.site_photos : [];
    const photosStored = photoAsk.length || b_photos.length || b.photos_declined === true
      ? await recordSitePhotos(admin, { table: 'inquiry_intake', id: String(draft.id), customerId: String(draft.customer_id || cust?.id || ''), email, photos: b_photos, via: 'portal', asked: photoAsk, declined: b.photos_declined === true })
      : photoRecord;
    // Where this turn's time went, on the run log (turn_clock.ts): read, prompt, model, exact_spec / held_reply, saved.
    const timing = { turn_ms: clock.lap('done'), laps: clock.laps, guard: guarded.violations, placed, reply_by: replyBy };
    if (saveErr) { await logRun('error', { intake_saved: 0, status_computed: status, brief_present: brief ? 1 : 0, llm_call_ok: llmCallOk ? 1 : 0, ...timing }, 'Intake result could not be saved back to inquiry_intake (' + String(saveErr.message) + ') — the brief of this turn was never persisted, so until the customer resends it the RFQ cannot be dispatched; they were answered 503 intake_unavailable.');
      // ...and the customer is now TOLD (3 Nov 2026, it_engineer, drill D10): this logged the loss and still answered
      // ok:true with a reply, so the portal showed a turn the database never held. Same answer as the draft insert's.
      // prevented by: supabase/functions/inquiry_intake/drill_database_unavailable.test.ts
      return J({ error: 'intake_unavailable', message: 'Your request could not be saved. Nothing has been submitted - please try again.' }, 503); }

    // THE STATE THIS TURN ESTABLISHED (_shared/inquiry_state.ts): the slots it settled, each with the customer message it
    // came from (the SQL keeps the first), what they do not know, the spec it asks now, the count, the register and the
    // stage. No model call: these are what the turn already read. Written beside the QA line and the run log.
    const statePatch: StatePatch & { specs: Record<string, string> } = { turn: userTexts().length, intake_id: String(draft.id), message_count: turns.length,
      // details.site_visit is our known condition, not something they said: it stays on the brief, never in the state's specs
      specs: Object.fromEntries(Object.entries((briefToSave as any).details || {}).filter(([k, v]) => k !== 'site_visit' && v !== undefined && v !== null && String(v).trim() !== '')
        .map(([k, v]) => [k, typeof v === 'object' ? JSON.stringify(v) : String(v)])),
      unknown: unknownNow, asked: nextQuestion?.key ? [String(nextQuestion.key)] : [],
      ...(category && category !== 'general' ? { trade: String(category) } : {}), status: statusOfStage(stage),
      ...(codesNow.length || tradeCodes.length ? { trade_codes: [...new Set([...codesNow, ...tradeCodes])] } : {}), ...register, ...(modelDialect ? { dialect: modelDialect, dialect_by: 'model' as const } : {}) };
    // THE EXPERT'S HALF OF THE STATE (ledger 1572): condition, options offered, the choice, the budget (this turn's, else the
    // brief's), and the service keys under specs.service_keys (the chosen option's, else the trade services the model named).
    if (solution) {
      const sp = solutionPatch({ ...solution, budget: solution.budget ?? (typeof out?.brief?.budget === 'string' && out.brief.budget.trim() ? out.brief.budget : null) });
      Object.assign(statePatch, { ...sp, specs: { ...statePatch.specs, ...(sp.specs ?? {}) } });
      if (solution.problem) statePatch.condition = { ...(statePatch.condition ?? {}), problem: solution.problem };
    }
    if (!statePatch.specs.service_keys && modelServiceKeys.length) statePatch.specs.service_keys = modelServiceKeys.join(', ');
    // The QA line and the run log are two independent writes: together, not one after the other.
    await Promise.all([
      mergeState(admin, stKey, 'request_chat', statePatch),
      (async () => { try { await admin.from('ai_qa_log').insert({ email, kind: 'intake', model: 'anthropic/claude-sonnet-5', input: { text: allText.slice(0, 1500), category }, output: { status, category, trades, urgency, readiness: Number(out.readiness) || 0, agent: ACTOR, knowledge: specialist ? specialist.slug : null }, flags: { plausibility, multi_trade: trades.length > 1, specialist: specialist ? specialist.slug : null } }); } catch (_e) { /* */ } })(),
      saveErr ? Promise.resolve() : logRun(llmCallOk && llmParseOk ? 'ok' : 'error', { intake_saved: 1, status_computed: status, readiness: Number(out.readiness) || 0, trades: trades.length, questions: Array.isArray(out.questions) ? out.questions.length : 0, brief_present: brief ? 1 : 0, llm_call_ok: llmCallOk ? 1 : 0, llm_parse_ok: llmParseOk ? 1 : 0, category_specs_loaded: validSlugs.length, specialist: specialist ? specialist.slug : null, ...timing }, (llmCallOk && llmParseOk) ? ('Intake turn completed normally: status=' + status + ', category=' + String(category) + ', trades=' + trades.length + ', agent=' + String(specialist ? specialist.slug : 'generic') + '. ' + (status === 'ready' ? 'Brief is supplier-ready and can be dispatched.' : 'RFQ is NOT yet dispatchable — it stays parked until the customer replies.')) : ('Intake turn completed but only via the keyword fallback (LLM unavailable/unparseable): status=' + status + ', category=' + String(category) + ' — this brief was not written by the model, so a request that is actually complete may be wrongly held at needs_info and never reach a supplier.')),
    ]);
    recordExchange(String(out.assistant_message || ''));

    return J({ ok: true, intake_id: draft.id, category, trades, classifier_override: classifierOverride, required_gate: requiredGate, urgency, plausibility, provenance, status, assistant_message: out.assistant_message || '', questions: Array.isArray(out.questions) ? out.questions.slice(0, 4) : [], next_question: nextQuestion, readiness: { filled: readinessFields.filled, required: readinessFields.required, score: Number(out.readiness) || 0 }, readiness_score: Number(out.readiness) || 0, missing: out.missing || [], brief, remaining_questions: remainingQuestions,
      // THE OPEN KEYS AND THE HOLD'S REASON GO BACK (stage2 run 321d13ae, 18 Oct 2026). Before a ready the
      // gate is null and next_question.key null, so the keys the row stamped never reached the caller: the
      // harness answered hvac "system_type" and plumbing "fixture_count" with its whole sheet three times,
      // slots.ts held the intake for unanswered specs, and the run printed "held (held)" with no reason.
      missing_keys: missingKeys,
      // THE PRICE-BLOCKING DETAILS (ledger 1587): which blocking specs of the job are still open, which go to the suppliers as
      // "supplier to advise", and every site-visit condition, so the portal shows what stands between this and a firm price.
      blocking: { open: gate.verdict.open.map((o) => o.key), advised: gate.verdict.advised.map((o) => o.key), site_visits: gate.verdict.site_visits.map((v) => v.text) },
      // THE PHOTO ASK, ONCE (ledger 1704): the shots, for the card with an upload button per shot; optional, never a hold.
      photo_ask: photoAsk.length ? { optional: true, shots: photoAsk.map((p) => ({ shot: p.shot, shot_ar: p.shot_ar, trade: p.trade })) } : null,
      site_photos: photosStored && (photosStored.asked.length || photosStored.photos.length) ? photosStored : null,
      // THE PHOTOS OF THIS MESSAGE (ruling 1200): how many were read and how many could not be (the reading itself stays internal)
      photos: photosIn.length ? { read: photoReads.filter((r) => r.status === 'read').length, unread: photoReads.filter((r) => r.status === 'failed').length } : null,
      ...(carry ? { carried: true, carried_turns: carry.turns.length } : {}), ...(stage !== 'normal' ? { stage } : {}),
      reply_by: replyBy,   // who wrote assistant_message: the model, or the code draft because OpenRouter was down (1339)
      pending: reaskTid !== null, ...(reaskTid ? { reask_turn_id: reaskTid } : {}),   // filed for the re-ask: the portal waits for it
      ...heldReasonFor(status, email, slotExhausted),
      // Where the time went goes back only to our own harness (scripts/e2e/intake_turn_latency.mjs).
      ...(email.endsWith('@example.invalid') ? { timing } : {}),
      agent: ACTOR, agent_name: ar ? 'مهندس مبيعات QuotesDone' : 'QuotesDone sales engineer' });
  } catch (e) { await logRun('error', { unhandled_exception: 1, intake_saved: 0 }, 'inquiry_intake threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e) + ' — the customer\'s RFQ was not captured or not updated, so it will never be routed to suppliers.'); return J({ error: String((e as Error)?.message || e) }, 500); }
}

