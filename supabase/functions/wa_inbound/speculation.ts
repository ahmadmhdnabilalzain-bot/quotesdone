// speculation.ts - TWO READS THAT START BESIDE THE CLASSIFICATION: the reply composed on the commonest route (the speculative draft)
// and the supplier's price-change reading. Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support); both are
// aborted through specAbort when the turn is answered another way.
//
// WHEN ADOPTION MAY WIDEN, AND WHEN IT MAY NOT (review of branch B, 12 Nov 2026; the coordinator's decision: "a faster wrong answer
// is worse than a slow right one"). For a few hours the draft was adopted whenever the real facts added no figure, link or reference
// it lacked (5400590a5, reverted). Measured on the real handler, it then answered a change the database had MADE with "a request
// cannot be changed from WhatsApp", a cancel waiting for "yes 1043" with "your request has been cancelled", and a late request whose
// chase had just started (update by 13 Nov 17:00) with "quotes usually arrive within 3 to 5 working days"; and an adopted draft
// skipped the state reader, the turn count and the waiting-list join. A check that looks for missing figures never sees a wrong
// sentence. Adoption may come back ONLY when ALL of these hold:
//   1. the real route's intent is empty, or on a CLOSED list of fixed company answers (how it works, fees) whose database answer
//      carries no action and no state of the person's own rows;
//   2. never after a status or app lane (a lane's answer is the person's own state, and its decline is not a licence for a draft);
//   3. the turn's after-steps (the state reader, the turn count, the waiting-list join, the case step) run for an adopted draft
//      exactly as for a reply written on the real route (say.ts askModel; a_wrong_draft_is_never_sent_...test.ts pins them);
//   4. a PAID measurement on recorded turns shows the adopted drafts agree with the replies the real route writes.
// Until then it is adopted only on the same facts it was composed on (general_turn.ts sameFacts), as below.
// prevented by: wa_inbound/a_wrong_draft_is_never_sent_for_a_change_a_cancel_or_a_chase.test.ts, wa_inbound/no_unwritten_send.test.ts
import type { DirectiveReading } from './reprice_outage.ts';
import { supplierDirectiveAllowed } from './directive_gate.ts';
import { composeSituation } from './compose.ts';
import { GATEWAY, itFinding, sec, admin } from './shared.ts';
import type { WaTurn } from './turn.ts';

export function startSpeculation(t: WaTurn): void {
  const { From, Body, audience, internalCaller, typedQuestion, askModel } = t;
  // THE REPLY STARTS BESIDE THE CLASSIFICATION (customer_support, 2 Nov 2026). Measured: the classification is 11-14 s of a 23-41 s
  // turn and the reply waited for it. The commonest class is "needs no person, no intent row fits" (p_needs_person false,
  // p_intent 'none'): the reply is composed on THAT route (fn_wa_route_dry: the same answer, no wa_answer_log row) and asked now.
  // When the classification says exactly that, this draft IS the reply; any other class (an intent, a person, a complaint, held)
  // discards it and the reply is asked on the real route as before. A discarded draft is never adopted, so it cannot escalate,
  // flag or be sent; the only send is the one at the end of the turn. Null (autoreply off, the dry route not applied) = no speculation.
  // A discarded draft is ABORTED (specAbort), so it stops costing; it also runs in its own rate bucket (askModel). A draft that
  // cannot start is never silent: the dry route missing or failing files an IT finding, and the turn takes the normal path.
  // ADOPTED WHEREVER THE REPLY DID NOT DEPEND ON THE ROUTE (it_engineer, 10 Nov 2026, WhatsApp latency R4/R5). The draft was
  // adopted only when the classification said exactly (no person, intent 'none'): 0 of 7 real turns in the channels audit. What
  // the reply is composed from is the situation composeSituation builds from the route; when the real route's situation is
  // the same text the draft was composed on, the draft answered the same facts, whatever the intent was called. `specFacts`
  // is that text, known as soon as the dry route is composed (before the draft's model call ends), so general_turn.ts decides
  // adoption without waiting on a draft it would discard.
  const specAbort = new AbortController();
  let setFacts: (s: string | null) => void = () => {};
  const specFacts = new Promise<string | null>((r) => { setFacts = r; });
  const speculative: Promise<Awaited<ReturnType<typeof askModel>> | null> | null = typedQuestion && audience !== 'founder'
    ? (async () => {
        if ((await sec('wa_autoreply_enabled')) !== 'true') { setFacts(null); return null; }
        const { data, error } = await admin.rpc('fn_wa_route_dry', { p_phone: From, p_body: Body.slice(0, 4000), p_needs_person: false, p_intent: 'none' });
        if (error || !data) {
          setFacts(null);
          await itFinding('wa_inbound:route_dry_unavailable', 'The WhatsApp reply cannot start beside the classification: fn_wa_route_dry failed or is not applied', { error: error?.message ?? 'returned nothing' });
          return null;
        }
        const { situation: s0 } = await composeSituation(t, data as Record<string, unknown>);
        setFacts(s0);
        return await askModel(audience === 'supplier' ? 'supplier' : audience === 'customer' ? 'customer' : 'visitor', s0, undefined, undefined, specAbort.signal);
      })().catch(async (e) => {
        setFacts(null);
        await itFinding('wa_inbound:speculative_reply_threw', 'The speculative WhatsApp reply threw; the turn took the normal path', { error: String((e as Error)?.message || e).slice(0, 300) });
        return null;
      })
    : null;
  if (!speculative) setFacts(null);
  // THE PRICE-CHANGE READING STARTS BESIDE THE CLASSIFICATION TOO (customer_support, 3 Nov 2026). It reads only the body,
  // yet it was asked after menuTurn had waited for the readings. Measured on the real exchange on main (run 41530397323,
  // ai_cost_log): on 14 of 14 supplier text turns the supplier_directive call started 0.75-0.95 s after the classification
  // ended and took 5.1-6.8 s, in series, so supplier turns were classified at 16.6-23.6 s against 11.6-12.7 s for a
  // number with no account. A turn the menu answers aborts it (specAbort), like the speculative draft.
  // A FAILED READING IS AN OUTAGE, NOT A "NO" (10 Nov 2026, customer_support; reprice_outage.ts): a gateway refusal, a
  // timeout or an answer with no JSON comes back as { outage: true }, so supplier_directive.ts can say so and queue it.
  // A turn the menu answered (specAbort) is not an outage: it reads as null, as before.
  let directiveP: Promise<DirectiveReading> | null = null;
  const directiveRead = () => (directiveP ??= (async () => {
    const gsecret = await sec('cred_fn_ai');
    const csys = 'Decide whether this message from a supplier is an INSTRUCTION TO CHANGE THEIR QUOTATION PRICE, and if so to what amount in AED.\n'
      + 'Return STRICT JSON ONLY. If it is: {"change":true,"amount":"<the new total price as a bare number, no currency, no commas>"}.\n'
      + 'Otherwise, including every question, every request for information, anything about their licence or profile, anything asking to CREATE a new quotation, and anything you are unsure about: {"change":false}.\n'
      + 'A relative instruction with no stated total ("drop it a bit", "make it cheaper") is NOT a change — return false, because I cannot act on an amount you had to invent.\n'
      // THE SAME READING NAMES HIS OTHER INSTRUCTIONS (16 Nov 2026, sales_engineer; _shared/supplier_instruction.ts reads them in full)
      + 'Also add "instruction": "not_for_me" if he says a job request we sent is not for him; "remove_work" if he asks us to stop sending him a kind of work; '
      + '"available" if he says he is available or back; "answer" if the message is a bare yes or no, or answers a question about removing work from his profile; '
      + '"confirm_figure" if he confirms that his quotation total is correct; '
      // AND THE COMPANY'S OWN ASKS (16 Nov 2026, customer_support; SUPPLIER holes 5, 6, 10, 12)
      + '"job_question" if he asks a question about the details or scope of a job request we sent him; "close_account" if he asks to close, '
      + 'delete or leave his QuotesDone account or answers about closing it; "customer_silent" if a customer who revealed him is not answering him; '
      + '"paid_leads" if he offers or asks to pay for more requests, priority, ranking or exclusivity; '
      // AND THE WAVE-3 ASKS (16 Nov 2026, review W3PEOPLE round 2: this reading never named them, so on WhatsApp they never reached the reader)
      + '"refer_company" if he asks how to invite or refer another company, or for his referral link; "owner_left" if he says the owner of his '
      + 'company has left or cannot be reached and asks to take over its account; "owner_keeps" if he says he is still the owner or does not agree '
      + 'that a member takes the company over; otherwise "none". Example: {"change":false,"instruction":"not_for_me"}.';
    const cr = await fetch(GATEWAY, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: gsecret, fn: 'supplier_directive', sys: csys, input: Body.slice(0, 600), temperature: 0, task_class: 'json_extraction', cache_ttl_min: 0 }),
      signal: AbortSignal.any([AbortSignal.timeout(40000), specAbort.signal]),
    });
    const cj = await cr.json().catch(() => ({} as Record<string, unknown>));
    if (!cr.ok || (cj as { ok?: unknown })?.ok === false) return { outage: true as const, why: 'gateway ' + String((cj as { error?: unknown })?.error || cr.status).slice(0, 80) };
    const cm = String((cj as { content?: string })?.content || '').match(/\{[\s\S]*\}/);
    return cm ? JSON.parse(cm[0]) : { outage: true as const, why: 'no reading in the answer' };
  })().catch((e) => (specAbort.signal.aborted ? null : { outage: true as const, why: String((e as Error)?.message || e).slice(0, 80) })));   // never swallowed: an outage is said (supplier_directive.ts)
  if (supplierDirectiveAllowed({ audience, internalCaller }) && typedQuestion) directiveRead();   // never read for a turn it cannot apply
  Object.assign(t, { specAbort, speculative, specFacts, directiveRead });
}
