// email_triage - reads un-triaged inbound emails, classifies them, and ANSWERS the customer in the same
// thread (28 Sep 2026, customer_support). Until then it only drafted a reply for a person to send, and with
// email_triage_enabled absent it never ran at all, so a customer's mail got no answer.
//
// THE FOUNDER'S RULES (28 Sep 2026): a customer gets a reply in under a minute, and no person is brought in
// unless the customer explicitly asks for one. So, per mail:
//   1. noAutoReply (_shared/customer_mail.ts) - the founder's own mail, no-reply / verification senders,
//      calendar replies, bounces and machine-written mail are marked and never answered;
//   2. classification exactly as before (the routine-judgement queue for an unknown sender, the settled-spam rule, the
//      draft model for a known one). THE DRAFT (ai_draft_reply) IS STILL NEVER SENT: it is written by the
//      internal model, and it stays on the row for the Inbox;
//   3. the ANSWER is customer_support's own: needsAPerson, then think() over the company knowledge (a
//      verified answer on the customer-facing route), and under the model hold a reviewed knowledge passage
//      quoted verbatim, or an honest receipt whose promise the held question's replay keeps
//      (reasoned_delivery.ts, channel 'email'). It goes out through fn_inbox_send - the Inbox's own send, now
//      threaded with In-Reply-To - and send_outbox is woken at once rather than on its 2-minute poll.
// A mail that asks for a person gets a reply saying so and a pending inbound_review for the founder's Inbox.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
import { observe } from '../_shared/observe.ts';
import { drain as drainJudgements } from '../_shared/routine_judgements.ts';
import { defaultDeps, think, type ThinkDeps } from '../_shared/think.ts';
import { knownSenderCategory } from '../_shared/triage_known_sender.ts';
import { mailFacts, SEPARATE_COMPANY_FACT, withClaimLink } from './account_facts.ts';
import { mailLoopHeld } from '../_shared/auto_reply_loop.ts';
import { answerableOnceRead, composeMailReply, declinedRowFields, EXPENSE_MAILBOX, invitationReplyAnswerable, noAutoReply, overDailyAnswerCap, tenantMailAnswerable } from '../_shared/customer_mail.ts';
import { audienceFor, declinedFields, type MailboxDecision, readingFacts, readSupplierMailbox } from './supplier_mailbox_reading.ts';
import { langOf } from '../_shared/chat_answers.ts';
import { needsAPerson } from '../_shared/reasoned_decisions.ts';
import { caseKeyOf } from '../_shared/support_fault_handover.ts';
import { fileReviewRequest } from '../_shared/review_request.ts';
import { aiReply, namesForbidden } from '../_shared/ai_reply.ts';
import { preRevealIdentities } from '../_shared/pre_reveal_identities.ts';
import { untrustedMail } from '../_shared/untrusted.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { TRIAGE_LLM } from './triage_llm.ts';
import { applyBackstop, backstopApplies, holdsUnread, readTriage, UNREAD_CATEGORY, UNREAD_SUMMARY } from './opt_out_backstop.ts';
import { beat, budgetLeft, closeStaleRuns } from './run_guard.ts';
import { J } from '../_shared/json_response.ts';
import { loadCaseContext, recordCaseExchange } from '../_shared/case_context.ts';
import { holdingRules, isStanding, type Standing } from '../_shared/escalation_clock.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
const llm = makeLlm(SONNET_FIRST, TRIAGE_LLM); // shared OpenRouter client (Sonnet-first ladder + 25s timeout); never served another mail's triage from the cache (triage_llm.ts)

const SYS = `You are the inbox assistant for QuotesDone, a UAE B2B anonymous quotation marketplace (customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small reveal fee to unlock the supplier they choose; suppliers pay no commission). You triage an incoming email addressed to the company and draft a reply the founder can send.\nReturn STRICT JSON ONLY: {"category":"supplier_document|supplier_question|customer_question|complaint|automated_decision_objection|automated_decision_person_review_request|billing|partnership|opt_out|spam|other","summary":"one factual sentence","reply":"a short, warm, professional reply in plain text, signed 'The QuotesDone Team'. Do not invent facts, prices, or commitments. If a document was sent, acknowledge receipt and say records will be updated. If it needs info you don't have, ask politely. If it is spam, set reply to an empty string. Use opt_out when the sender asks us to stop e-mailing them, to remove or unsubscribe them, or answers our supplier invitation with a refusal ("no", "not interested", "not relevant", "stop", in any language and however it is worded); a sender who asks a question, is interested in another trade, or asks us to replace a contact is not opt_out; for opt_out set reply to an empty string. Use automated_decision_person_review_request only when the sender explicitly asks that a person, rather than the system, review a decision the platform made automatically; the reply for it is the same as for automated_decision_objection. Use automated_decision_objection when the sender objects to, or asks for a review of, a decision the platform made automatically (a refund, a dispute or a verification); for either of those two categories the reply is exactly, in English: "QuotesDone Customer Support has received your objection and will reply within 10 working days. If it is not resolved, the QuotesDone operations team takes it up." or, when the email is in Arabic, exactly: "تسلّم فريق دعم العملاء في QuotesDone اعتراضكم، وسيردّ عليكم خلال 10 أيام عمل. وإن لم يُحسم، يتولاه فريق العمليات في QuotesDone.""}\nReply with JSON only, no preamble.`;

type Mail = { id: number; from_email: string | null; to_email: string | null; subject: string | null; body: string | null; owner_role: string | null; raw: Record<string, unknown> | null; lead_id?: number | null; provider_email_id?: string | null; created_at?: string | null };

/** customer_support answers the mail in its thread. Returns how it was answered. */
// WHO WROTE IS A FACT, NOT A GUESS (QA channels run, 19 Oct 2026). Every mail was answered with audience 'customer': a
// ZZ DEMO supplier's emailed quotation (inbound_messages 483) was answered as a customer question and told about the
// reveal fee. fn_mail_sender_known already names the sender's relation; a supplier is answered as a supplier, in English.
export function audienceOf(relation: unknown): 'customer' | 'supplier' { return relation === 'supplier' ? 'supplier' : 'customer'; }

/** The counterpart identities this sender may not be told: a supplier by its linked lead, a customer by the exact
 *  address. Spoofing the From only blocks names, it never reveals one, so no authentication is needed here. */
async function mailForbidden(m: Mail, audience: 'customer' | 'supplier'): Promise<string[]> {
  if (audience === 'supplier' && m.lead_id) return preRevealIdentities(admin, { leadId: Number(m.lead_id) });
  const addr = String(m.from_email || '').trim();
  if (!addr) return [];
  const { data } = await admin.from('customers').select('id').ilike('email', addr.replace(/[\\%_]/g, (c) => '\\' + c)).limit(1).maybeSingle();
  return data?.id ? preRevealIdentities(admin, { customerId: String(data.id) }) : [];
}

async function answer(m: Mail, deps: ThinkDeps, audience: 'customer' | 'supplier' = 'customer', facts = ''): Promise<string> {
  // THE MAIL IS DATA (3 Nov 2026, release qualification): every prompt below carries it fenced (untrusted.ts), so a line
  // in the body reading "ignore your rules" is something the sender wrote, never an instruction to the model.
  const q = untrustedMail(m.subject, m.body);
  const lang = audience === 'supplier' ? 'en' : langOf(String(m.subject || '') + ' ' + String(m.body || ''));   // suppliers always English (28 Sep 2026)
  // the other party on the sender's jobs not yet revealed to them: a reply naming one is refused (pre_reveal_identities.ts)
  const forbidden = await mailForbidden(m, audience);
  // A fixture (@example.invalid, the ZZ DEMO convention) is never queued for the replay (think.ts isFixtureRequest).
  const subject = { message_id: m.id, channel: 'email', ...(/@example\.invalid$/i.test(String(m.from_email || '')) ? { fixture: true } : {}) };
  // A fault the sender reports is handed to the it_engineer (ruling 1705, support_fault_handover.ts): the sender's address is what
  // this channel already holds, so they are told by e-mail when the fix is verified. The case key is a hash of the thread.
  const person = await needsAPerson(deps, { seat: 'customer_support', surface: 'email_triage.needs_a_person', message: q,
    audience, dedupeKey: 'email_person:' + m.id, subject,
    fault: { channel: 'email', caseKey: await caseKeyOf('email', String(m.from_email || '') + ':' + String(m.subject || '').replace(/^(re|fwd?):\s*/gi, '').slice(0, 120)),
             email: String(m.from_email || '') || null, lang, audience, conversation: [] } });
  // EVERY E-MAIL REPLY IS WRITTEN BY A MODEL (rulings 1195/1196, 12 Oct 2026): the reasoned, independently checked answer
  // when it agrees; otherwise a direct model reply from the company brief (aiReply). The quoted knowledge passage, the
  // person-handoff sentence and the "we received it" receipt are gone. No model at all: nothing is sent (it throws, and
  // the message stays unanswered for the next run).
  let text: string, how: string;
  // THE HELD REPLY IS FILED ONLY IF NO REPLY WENT (3 Nov 2026, it_engineer, drill D2). think() files the reply question
  // in the held queue whenever it cannot finish (email_triage.reply, dedupe email_reply:<id>), and the direct model reply
  // below then answers the mail at once. resilience_ping's replay answered the same question again later and
  // reasoned_delivery sent it through fn_inbox_send, which does not look at replied_at: measured in the drill, a model
  // that answered but whose reasoning was refused produced TWO replies in the thread, one now and one on the next replay.
  // The hold is kept back and filed only when this answer throws (nothing was sent), which is the case the replay exists
  // for: the model down now, the answer delivered when it is back. needs_a_person's hold is untouched (its replay sends
  // only when a person was asked for). prevented by: email_triage/drill_triage_faults.test.ts
  // THE CASE (ruling 1635, _shared/case_context.ts): the sender's open cases on every channel and the same-matter decision;
  // both reply roads read the case summary (aiReply in its cached prefix, the reasoned answer as its context's case).
  const kase = await loadCaseContext(deps, { channel: 'email', seat: 'customer_support', audience, message: q, lang, dedupeKey: 'case_match:email:' + m.id,
    email: m.from_email, partyId: audience === 'supplier' && m.lead_id ? String(m.lead_id) : null });
  const keptBack: Record<string, unknown>[] = [];
  const replyDeps: ThinkDeps = { ...deps, rpc: async (f, args) => {
    if (f === 'fn_reason_hold' && args?.p_surface === 'email_triage.reply') { keptBack.push(args); return { data: null, error: null }; }
    return await deps.rpc(f, args);
  } };
  // the person's open escalations and the founder's availability (case_context.ts `standing`) are facts both reply roads read
  const replyFacts = [facts, kase.standing].filter(Boolean).join('\n\n');
  const standing: Standing | null = isStanding(person.standing) ? person.standing : null;
  try {
    const direct = async (note: string) => (await aiReply(deps, { ...kase.reply, seat: 'customer_support', channel: 'e-mail', audience, lang, message: q,
      subject, forbidden, ...(replyFacts ? { facts: replyFacts } : {}), rules: 'An e-mail body without a greeting or a sign-off (they are added). Never promise a date.' + note })).reply;
    if (standing) {
      // A JOURNALIST, A LAWYER OR A REGULATOR (16 Nov 2026, hole hunt item 4): the model's reading of who writes (needsAPerson's
      // `standing`, the same call) gives the company's holding line from the brief (section 14), never a new-customer answer; the case
      // goes to the CEO on a clock (below, after the send).
      const body = await direct(holdingRules(standing));
      if (!body) throw new Error('no model answered the e-mail');
      text = composeMailReply({ lang, answer: body }); how = standing;
    } else if (person.value === true) {
      const body = await direct(' They asked to speak to a person: say plainly that their request is now with the manager who decides at QuotesDone and that we will write back to them by e-mail, and answer whatever else they asked.');
      if (!body) throw new Error('no model answered the e-mail');
      text = composeMailReply({ lang, answer: withClaimLink(body, facts) }); how = 'person';
      // a person asked to review an automated decision (ledger 1152): filed with the seat that owns it (review_route)
      await fileReviewRequest(admin, deps, { channel: 'email', requester: String(m.from_email || 'unknown sender'), message: q,
        surface: 'email_triage.review_of_decision', dedupeKey: String(m.id), subjectTable: 'inbound_messages', subjectId: String(m.id) });
    } else {
      const r = await think(replyDeps, { seat: 'customer_support', surface: 'email_triage.reply', stakes: 'high', dedupeKey: 'email_reply:' + m.id, subject,
        question: `Answer this e-mail to QuotesDone as its customer support, in ${lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}, plain text, `
          + 'without a greeting or a sign-off (they are added). Never name another customer or supplier, never quote an unpublished price, never promise a date.\n\n' + q,
        context: { audience, language: lang, ...(facts || kase.standing ? { profile: { ...(facts ? { own_account: facts } : {}), ...(kase.standing ? { escalations_and_availability: kase.standing } : {}) } } : {}), ...kase.context } });
      // a reasoned answer naming a counterpart is not sent: the direct reply below is held to the same list by aiReply
      const verified = r.status === 'answered' && r.verified?.status === 'agreed' && r.answer.trim() && !namesForbidden(r.answer, forbidden) ? r.answer.trim() : null;
      const body = verified ?? await direct('');
      if (!body) throw new Error('no model answered the e-mail');
      text = composeMailReply({ lang, answer: withClaimLink(body, facts) });   // every path carries the invited supplier's link
      how = verified ? 'reasoned' : 'direct';
    }
    const { data: sent, error } = await admin.rpc('fn_inbox_send', { p_id: m.id, p_body: text, p_by: 'customer_support' });
    if (error || (sent as { error?: string } | null)?.error) throw new Error('fn_inbox_send: ' + (error?.message ?? (sent as { error?: string }).error));
    // the case summary after the reply that went (runs past the response; never awaited)
    recordCaseExchange(deps, kase, { theirMessage: q, ourReply: text, subject });
    // THE PROMISE GETS ITS CLOCK (16 Nov 2026, escalation_clock.ts): a person asked for, or a journalist, lawyer or regulator answered
    // with the holding line, is a case the CEO seat decides; what we just sent is what we promised. Same subject as the review
    // request's clock (inbound_messages, this id), so the two land on one clock. A failure never costs the reply that went.
    if (how === 'person' || isStanding(how)) await openMailClock(m, how as 'person' | Standing, text, lang, audience);
  } catch (e) {
    for (const args of keptBack) await deps.rpc('fn_reason_hold', args).catch(() => null);   // nothing went: the replay answers it
    throw e;
  }
  // Filed AFTER the send: fn_inbox_send closes the message's open review items, and this one must stay open.
  if (how === 'person') await admin.from('agent_actions').insert({ agent: 'email', kind: 'inbound_review', status: 'pending', risk: 'low',
    title: 'Inbox: a customer asked for a person — ' + String(m.subject || '(no subject)').slice(0, 60),
    recommendation: 'The customer asked to speak to a person. The CEO seat decides it on its escalation clock and customer_support writes them the decision, or an honest status when the clock runs out (visibility only).',
    target_table: 'inbound_messages', target_id: String(m.id), detail: { from: m.from_email, reasoning: person.result.answer.slice(0, 500) } });
  return how;
}

/** The clock for an e-mail escalation (fn_escalation_clock_open). Never throws: the reply has already gone. */
async function openMailClock(m: Mail, kind: 'person' | Standing, text: string, lang: string, audience: 'customer' | 'supplier'): Promise<void> {
  try {
    const { error } = await admin.rpc('fn_escalation_clock_open', { p_source_table: 'inbound_messages', p_source_id: String(m.id), p_kind: kind,
      p_channel: 'email', p_requester: String(m.from_email || ''), p_promised: text.slice(0, 2000), p_request_text: String(m.body || '').slice(0, 4000),
      p_subject_line: String(m.subject || '').slice(0, 300),
      p_detail: { lang: lang === 'ar' ? 'ar' : 'en', audience: kind === 'press' ? 'press' : kind === 'legal' ? 'counsel' : kind === 'regulator' ? 'regulator' : audience,
                  inbound_message_id: m.id } });
    if (error) console.error('email_triage clock', m.id, error.message);
  } catch (e) { console.error('email_triage clock', m.id, String((e as Error)?.message || e)); }
}

Deno.serve(observe('email_triage', async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'email_triage');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const startedAt = Date.now();
    // A run the platform ended without a word is closed here with its reason (run_guard.ts): a kill skips every catch.
    const closedStale = await closeStaleRuns(admin, 'email_triage');
    const { data: run } = await admin.from('agent_runs').insert({ agent: 'email_triage' }).select('id').maybeSingle();
    const counts = { triaged: 0, drafted: 0, spam: 0, unknown_sender_to_judgement: 0, not_answered: 0, answered: 0, answer_failed: 0 } as Record<string, number>;
    const judgementIds: number[] = [];
    const deps = defaultDeps(admin, 'email_triage');
    const founder = [...String((await sec('admin_emails')) || '').split(','), String((await sec('founder_email')) || '')].map((s) => s.trim()).filter(Boolean);
    // resend_inbound names the message it just stored, so its reply does not wait for the 15-minute tick.
    let sel = admin.from('inbound_messages').select('id,from_email,to_email,subject,body,owner_role,raw,lead_id,provider_email_id,created_at')
      .eq('needs_review', true).is('triaged_at', null).is('replied_at', null).is('owner_role', null).or('ai_category.is.null,ai_category.neq.routine_queued');
    if (Number(body?.message_id) > 0) sel = sel.eq('id', Number(body.message_id));
    // A FAILED READ IS NOT AN EMPTY INBOX (3 Nov 2026, it_engineer, drill D10). The error was dropped, so a statement
    // timeout here closed the run 'ok' with every count 0: the same row as a quiet inbox, while mail waited. The mail is
    // safe (nothing was taken, the next tick reads it again); the run now says the read failed, at error, so the watch
    // that reads agent_runs sees it. prevented by: email_triage/drill_triage_faults.test.ts
    const { data: msgs, error: readErr } = await sel.order('created_at', { ascending: true }).limit(20);
    if (readErr) {
      if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'error', counts: { ...counts, closed_stale_runs: closedStale },
        note: ('email_triage could not read the inbox (inbound_messages: ' + String(readErr.message) + '); no mail was taken, the next tick reads it again.').slice(0, 500) }).eq('id', run.id);
      return J({ ok: false, error: 'inbox_read_failed', counts }, 500);
    }
    const reply1 = async (m: Mail, audience: 'customer' | 'supplier' = 'customer', facts = '') => {
      try { const how = await answer(m, deps, audience, facts); counts.answered++; counts['answered_' + how] = (counts['answered_' + how] || 0) + 1; }
      catch (e) {
        counts.answer_failed++; console.error('email_triage answer', m.id, String((e as Error)?.message || e));
        // NEVER JUST WAITS (2 Nov 2026): a triaged row is not selected again, so a failed answer had no owner and no retry.
        // Nothing comes back to the founder (ledger 1438): the ceo seat holds it as a live handoff, idempotent per message.
        const { error: hoErr } = await admin.rpc('fn_seat_handoff', { p_from: 'customer_support', p_to: 'ceo', p_type: 'review.requested', p_subject_table: 'inbound_messages', p_subject_id: String(m.id),
          p_payload: { inbound_message_id: m.id, from_email: m.from_email, to_email: m.to_email, subject: String(m.subject || '').slice(0, 200), ask: 'customer_support could not write an answer, so the sender has heard nothing. Decide the answer and have it sent in the thread.', error: String((e as Error)?.message || e).slice(0, 300) } });
        if (hoErr) console.error('email_triage handoff', m.id, hoErr.message);
        else await admin.from('inbound_messages').update({ owner_role: 'ceo' }).eq('id', m.id).is('owner_role', null);
      }
    };
    for (const m of ((msgs || []) as Mail[])) {
      // A smaller unit: past the budget no NEW message is started; the rest stay untriaged for the next tick.
      if (!budgetLeft(startedAt)) { counts.deferred_over_budget = (counts.deferred_over_budget || 0) + 1; continue; }
      await beat(admin, run?.id, 'message ' + m.id + ' (triage)');
      // 0. THE SUPPLIER MAILBOX IS READ BEFORE IT IS ANSWERED (11 Nov 2026, customer_support, ruling 1633). supplier@ is also the
      // founder's own mailbox; Azure's account mail and two Microsoft support cases were answered with the registration
      // template on 9-10 Nov. Code rules first, then the model reads it at HIGH effort with the correspondence, and only a
      // supplier or a customer may be answered (supplier_mailbox_reading.ts). Not the supplier mailbox's mail: null, as before.
      const reading: MailboxDecision | null = await readSupplierMailbox(admin, deps, m);
      if (reading && !reading.may_reply) {
        // the mark is the claim, as below: a run whose mark lands on nothing leaves the mail to the run that took it
        const { data: tookRead } = await admin.from('inbound_messages').update({ ...declinedFields(reading), triaged_at: new Date().toISOString() })
          .eq('id', m.id).is('triaged_at', null).select('id');
        if (!tookRead?.length) { counts.taken_by_another_run = (counts.taken_by_another_run || 0) + 1; continue; }
        counts.not_answered++; counts['read_as_' + reading.reading] = (counts['read_as_' + reading.reading] || 0) + 1;
        continue;
      }
      // 1. NEVER ANSWERED: the founder, no-reply and verification senders, calendar replies, bounces.
      let skip = noAutoReply(m, founder);
      // set when the internal skip is lifted for an invited supplier's reply to supplier@: the opt_out backstop's scope (below)
      let invitationReply = false;
      // An invited supplier's reply to the invitation mailbox (supplier@) is the one 'internal' row that IS answered:
      // only when the sender is a lead, and every other rule (bounce, no-reply, auto-submitted, calendar) still applies
      // (customer_mail.ts invitationReplyAnswerable, 28 Oct 2026).
      if (skip === 'internal') {
        const { data: rel } = await admin.rpc('fn_mail_sender_known', { p_email: String(m.from_email || '') });
        // a lead who opted out (email_suppressions, exact address) is never answered here (review of #1699)
        const fromAddr = String(m.from_email || '').trim().toLowerCase();
        const { data: sup } = fromAddr ? await admin.from('email_suppressions').select('email').ilike('email', fromAddr.replace(/[\\%_]/g, (c) => '\\' + c)).limit(1) : { data: [] };
        if (invitationReplyAnswerable(m, rel, !!(sup && sup.length))) { skip = noAutoReply({ ...m, to_email: '' }, founder); invitationReply = !skip; }
        else if (tenantMailAnswerable(m, !!(sup && sup.length))) skip = noAutoReply({ ...m, to_email: '' }, founder);
        // anyone else on the supplier mailbox whose READING allowed an answer (step 0 above: a supplier or a customer; every
        // other reading has already left the loop): the mailbox no longer makes it 'internal', every other rule still applies
        else if (reading?.may_reply === true && answerableOnceRead(m, !!(sup && sup.length))) skip = noAutoReply({ ...m, to_email: '' }, founder);
      }
      // A reply never goes to the founder: fn_is_founder_own_inbox also names his personal inboxes, which admin_emails does not.
      if (!skip) { const { data: own } = await admin.rpc('fn_is_founder_own_inbox', { p_addr: String(m.from_email || '') }); if (own === true) skip = 'founder'; }
      if (!skip) {
        const { count } = await admin.from('notifications').select('id', { count: 'exact', head: true }).eq('type', 'inbound_reply')
          .ilike('to_email', String(m.from_email || '').trim().replace(/[\\%_]/g, (c) => '\\' + c)).gte('created_at', new Date(Date.now() - 86_400_000).toISOString());
        if (overDailyAnswerCap(count)) skip = 'daily_answer_cap';
      }
      // two machines never answer each other for ever: 3 answers in the hour with no human-sounding mail between (auto_reply_loop.ts)
      if (!skip && await mailLoopHeld(admin, m)) skip = 'auto_reply_loop';
      if (skip) {
        await admin.from('inbound_messages').update({ ai_category: 'no_auto_reply', ai_summary: 'Not answered automatically: ' + skip + ' (customer_mail.ts noAutoReply).', triaged_at: new Date().toISOString(), ...declinedRowFields(m) }).eq('id', m.id);
        counts.not_answered++; continue;
      }
      // AN UNKNOWN SENDER IS JUDGED ON THE ROUTINE CLASS (24 Sep 2026, founder's approval; _shared/routine_judgements.ts). A sender who is
      // no lead, customer or staff address (fn_mail_sender_known, exact address) is queued for the routine class, google/gemini-3.8-flash since 1056 (no
      // per-day limit, founder_instruction 987); known senders keep the path below unchanged. A row already queued is not queued again.
      const { data: relation, error: relErr } = await admin.rpc('fn_mail_sender_known', { p_email: String(m.from_email || '') });
      if (!relErr && !relation) {
        const { data: gid } = await admin.rpc('fn_routine_judgement_enqueue', { p_kind: 'unknown_sender_mail', p_subject_key: String(m.id),
          p_input: { message_id: m.id, from: m.from_email, subject: m.subject, body: String(m.body || '').slice(0, 4000) } });
        // Marked, so a held backlog never crowds known senders out of this run's 20; the judgement overwrites it.
        // ...and the mark is this run's claim (see TAKEN BY ANOTHER RUN below): no row back, another run is answering it.
        if (gid) {
          const { data: queuedHere } = await admin.from('inbound_messages').update({ ai_category: 'routine_queued' }).eq('id', m.id).is('triaged_at', null)
            .or('ai_category.is.null,ai_category.neq.routine_queued').select('id');
          if (!queuedHere?.length) { counts.taken_by_another_run = (counts.taken_by_another_run || 0) + 1; continue; }
          judgementIds.push(Number(gid)); counts.unknown_sender_to_judgement++;
        }
        // An unknown sender is usually a new customer: answered now, whatever the judgement later files as its category.
        // resend_inbound linked a lead by sender (leads.email or claimed_by): a supplier, answered as one, in English.
        // A supplier-mailbox mail is answered as what its reading said, knowing the correspondence (ruling 1631).
        const known = m.lead_id ? SEPARATE_COMPANY_FACT : '';
        await (reading ? reply1(m, audienceFor(m.lead_id ? 'supplier' : null, reading), [known, readingFacts(reading)].filter(Boolean).join('\n\n'))
          : m.lead_id ? reply1(m, 'supplier', SEPARATE_COMPANY_FACT) : reply1(m));
        continue;
      }
      let category = 'other', summary = '', reply = '', parsed = false;
      // THE SENDER'S CASE TIMELINE (14 Sep 2026): customer_support is the only seat on email, so the
      // draft is written knowing what every seat has already done with this person. Deterministic
      // (fn_contact_timeline); a failure to read it leaves the draft ungrounded, never the mail unread.
      let tlText = '';
      try {
        const { data: tl } = await admin.rpc('fn_contact_timeline', { p_contact: String(m.from_email || ''), p_limit: 30 });
        const ev = (tl as any)?.events;
        if (Array.isArray(ev) && ev.length) tlText = '\n\nSENDER CASE TIMELINE (newest first; do not contradict it, do not promise what it shows is already done):\n' + JSON.stringify(ev).slice(0, 6000);
      } catch (_e) { tlText = ''; }
      // A SETTLED SENDER (24 Sep 2026, it_engineer): the exact from_email's own earlier triages decide spam with no model.
      const { data: prior } = await admin.from('inbound_messages').select('ai_category').eq('from_email', String(m.from_email || '')).neq('id', m.id)
        .not('triaged_at', 'is', null).order('triaged_at', { ascending: false }).limit(10);
      const settled = m.from_email ? knownSenderCategory((prior || []).map((p: any) => p.ai_category)) : null;
      if (settled) { category = settled; summary = 'Known sender: every earlier mail from this exact address was triaged spam (no model called).'; parsed = true; }
      const out = settled ? null : await llm(SYS, 'From: ' + (m.from_email||'') + '\n' + untrustedMail(m.subject, m.body) + tlText, 800);
      if (!settled) ({ parsed, category, summary, reply } = readTriage(out));
      // makeLlm returns null on a failure or timeout; on the backstop's scope an unread classification is held, never answered (opt_out_backstop.ts).
      const held = holdsUnread(invitationReply, parsed);
      if (held) { category = UNREAD_CATEGORY; summary = UNREAD_SUMMARY; reply = ''; }
      // TAKEN BY ANOTHER RUN (3 Nov 2026, it_engineer, drill D2). resend_inbound wakes this function for the mail it just
      // stored while the 15-minute tick may be running, and both SELECTed the same untriaged row: the selection is not a
      // claim. Both marked it and both answered, so the customer got two replies (measured in the drill: two overlapping
      // runs, two fn_inbox_send). The mark is now the claim: it only lands on a row still untriaged, and a run whose mark
      // lands on nothing leaves the mail to the run that took it. prevented by: email_triage/drill_triage_faults.test.ts
      // (the statement keeps its `const { error: markErr }` shape: scripts/checks/no_paid_call_repeats_itself.test.mjs reads it)
      const took = { rows: 0 };
      const { error: markErr } = await admin.from('inbound_messages').update({ ai_category: category, ai_summary: summary, ai_draft_reply: reply || null, triaged_at: new Date().toISOString(), ...(held ? { needs_review: true } : {}) })
        .eq('id', m.id).is('triaged_at', null).select('id').then((r) => { took.rows = r.data?.length ?? 0; return r; });
      // An answer that cannot be recorded is paid for again on the next run (22 Sep 2026, instruction
      // 705): stop the batch rather than read the rest of the inbox into the same failing write.
      if (markErr) { if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'error', counts, note: 'email_triage stopped: could not record the triage of inbound message ' + m.id + ' (' + String(markErr.message).slice(0, 160) + '); continuing would re-read and re-pay for it on every run.' }).eq('id', run.id); return J({ ok: false, error: 'mark_failed', counts }, 500); }
      if (!took.rows) { counts.taken_by_another_run = (counts.taken_by_another_run || 0) + 1; continue; }
      counts.triaged++;
      if (held) { counts.held_unread = (counts.held_unread || 0) + 1; continue; }
      // An explicit request that a person review an automated decision (ruling 1264) goes through #1519's one door,
      // fileReviewRequest; same dedupe key as the answer path, so the request is filed once.
      if (category === 'automated_decision_person_review_request') {
        await fileReviewRequest(admin, deps, { channel: 'email', requester: String(m.from_email || 'unknown sender'),
          message: String(m.body || '').slice(0, 4000), surface: 'email_triage.review_of_decision', dedupeKey: String(m.id),
          subjectTable: 'inbound_messages', subjectId: String(m.id) });
      }
      // A STOP THE WORD LIST MISSED (28 Oct 2026, sales_engineer; ledger 1401 audit): the model read an invited supplier's
      // reply to supplier@ as opt_out. Applied behind resend_inbound's own gates and never answered (opt_out_backstop.ts).
      if (backstopApplies(category, invitationReply)) {
        const fwd = String((await sec('expense_forwarders')) || '').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean);
        const stop = await applyBackstop(admin, m, [...founder, ...fwd, EXPENSE_MAILBOX]);
        const k = stop.suppressed ? 'opted_out' : 'opt_out_kept_for_review';
        counts[k] = (counts[k] || 0) + 1;
        continue;
      }
      if (category === 'spam') { counts.spam++; continue; }
      if (reply) counts.drafted++;
      await beat(admin, run?.id, 'message ' + m.id + ' (answer)');
      const facts = await mailFacts(admin, String(m.from_email || ''), relation, (m as { raw?: unknown }).raw);
      await reply1(m, audienceOf(relation), reading ? [facts, readingFacts(reading)].filter(Boolean).join('\n\n') : facts);
    }
    // THE REPLY LEAVES NOW, not on the outbox's 2-minute poll (the founder's "under a minute").
    if (counts.answered) {
      try {
        const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/send_outbox', { method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '') },
          body: JSON.stringify({ __secret: await sec('cred_fn_email_triage'), limit: 20 }) }, 30_000);
        await r.body?.cancel().catch(() => {});
      } catch (_e) { /* the 2-minute poll still sends it */ }
    }
    // Judge the unknown senders now; any held (the model hold) stay queued for resilience_ping. Never a word list.
    const judgements = judgementIds.length ? await drainJudgements(deps, judgementIds.length, judgementIds) : null;
    if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: counts.answer_failed ? 'error' : 'ok', counts: { ...counts, judgements, closed_stale_runs: closedStale }, note: null }).eq('id', run.id);
    return J({ ok: true, counts });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
