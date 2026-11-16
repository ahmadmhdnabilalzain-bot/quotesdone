// compose.ts - THE REPLY'S FACTS, composed from a route: who they are, their own record, the database's own answer, the approved FAQ
// and the live company block, as the situation the model answers from. Moved out of index.ts's handleInbound unchanged (9 Nov 2026,
// customer_support); it was a closure over the turn's audience and prefetched reads, which it now takes from the turn.
import type { WaTurn } from './turn.ts';
import { generaliseOwnRequestFacts, OWN_REQUEST_RULE, withoutDuplicateRequests } from '../_shared/own_request_facts.ts';

// THE REPLY'S FACTS, composed from a route (customer_support, 2 Nov 2026). A function so the reply can be started BEFORE the
// classification returns, on the route the commonest class gives (see `speculative` below), and again on the real route when the
// class turned out otherwise. Reads only the prefetched facts and the route it is given; it writes nothing.
export async function composeSituation(t: WaTurn, rt: Record<string, unknown> | null): Promise<{ situation: string; ids: number[]; lean: string }> {
  const { audience, known, prefetch } = t;
  let timeline: any = null;
  try { const { data: tl } = await prefetch.timeline; timeline = tl || null; } catch (_e) { timeline = null; }
  const timelineEvents = Number(timeline?.event_count ?? 0);
  const detReply = String(rt?.deterministic_reply || '');
  let audienceBlock: string;
  if (audience === 'supplier') {
    audienceBlock = `AUDIENCE: this number belongs to a REGISTERED SUPPLIER${known?.name ? ' (' + known.name + ')' : ''}${known?.approved ? ', already verified' : ', registration not yet verified'}. Treat them as a supplier. You may naturally acknowledge that they are registered with us, but never recite ANOTHER person's private details. Their OWN record is supplied below and you may state it back to them plainly - that is the point of this channel.`;
  } else if (audience === 'customer') {
    // ledger 1711 (16 Nov 2026): his own record carries what he asked and what his portal shows him; the model answers from it
    audienceBlock = `AUDIENCE: this number belongs to a REGISTERED CUSTOMER. Treat them as a customer. Do NOT bring up supplier subscriptions, founding-supplier exemptions, supplier fines or supplier recruitment.\n` + OWN_REQUEST_RULE;
  } else {
    audienceBlock = `AUDIENCE: UNKNOWN - this number is not in our records. Most people messaging this number are UAE SUPPLIERS who received our invitation, but customers write too. Work out which they are from their wording (a supplier talks about registering, their trade licence, receiving jobs, their company; a customer talks about needing a price, getting quotes, a job they want done). If it is genuinely unclear and the answer would differ, ask ONE short friendly question to find out before giving fee details.`;
  }

  // THEIR OWN RECORD, SCOPED IN SQL (v15, 13 Aug 2026). "Is my profile approved", "how many
  // inquiries did I miss", "what was my last quotation", "how many suppliers received my
  // inquiry", "what were I quoted on average" are all data questions about the SENDER. The
  // scoping is done by fn_wa_context in SQL off their phone number, so this prompt can never be
  // talked into another person's rows — the model is handed facts, it does not request them.
  // Pre-reveal a customer gets each quote's letter and price, as his portal shows it, and never a supplier's name, contact or
  // brand (16 Nov 2026, ledger 1711; the anonymity decision is in a_customer_is_answered_from_his_whole_request_on_every_channel.sql).
  // The fact pack below carries the same request list, so the own record points at it rather than sending it twice.
  let ownRecord = '';
  try {
    const { data: mine } = await prefetch.mine;
    if (mine && (mine as any).known === true) ownRecord = '\n\nTHIS SENDER\'S OWN RECORD (read live; it is theirs, so you may state it back to them, and you must never state anyone else\'s):\n'
      + JSON.stringify(generaliseOwnRequestFacts(withoutDuplicateRequests(mine as Record<string, unknown>, rt?.fact_pack))) + '\n';
    else if (mine && (mine as any).known === false) ownRecord = '\n\nTHIS SENDER\'S OWN RECORD: no account matches this number, so answer generally and invite them to register or sign in rather than guessing at their status.\n';
  } catch (_e) { /* fall through with no record rather than dropping the message */ }
  if (timeline && timelineEvents > 0) ownRecord += '\n\nTHIS SENDER\'S CASE TIMELINE (newest first; every channel and every seat; theirs only). Never contradict it, and never repeat something it shows was already sent unless they ask:\n' + JSON.stringify((timeline as any).events) + '\n';

  // THE MODEL GETS THE SAME PACK THE DATABASE ANSWERED FROM. fn_wa_route was reached above and
  // said a model is needed; its fact_pack and model_brief carry the sender's own rows, the
  // company register, the list of things that are genuinely unknown, and the rules the model may
  // not break. Appending them here is what stops the model filling a gap from memory.
  let brainPack = '';
  if (rt?.fact_pack) {
    // fn_wa_model_brief (rt.model_brief, the old STANDING BRIEF) is NOT sent any more (customer_support, 19 Oct 2026).
    // It predates the reply rules in _shared/ai_reply.ts and contradicts them: its "ABSOLUTE RULE ON SUBJECT" made the
    // model answer "how long does installation usually take?" with fn_wa_off_topic_reply's "QuotesDone inquiries only"
    // sentence (runs 0f48ea10 and c95eb7da, EN and AR), and it said "say you will check", which the answer standard forbids.
    brainPack = '\n\nFACT PACK (the ONLY source for any fact about this person, their own jobs and quotes, and any '
      + 'QuotesDone fee; a trade, material, timing or specification question is answered from your own expertise):\n'
      + JSON.stringify(generaliseOwnRequestFacts(rt.fact_pack)) + '\n';
  }

  // THE COMPANY BLOCK — customer_support's half of the founder's 9 Sep 2026 ruling: "the company
  // knowledge is literally connected to every seat automatically. Any seat that we made, the
  // company knowledge should be there."
  //
  // p_audience => 'public' is deliberate and is the reason the parameter exists. This channel
  // answers strangers and suppliers; the INTERNAL block carries the seat list, the founder's
  // standing decisions and the revenue targets, and none of that belongs in a WhatsApp reply. The
  // public half is identity, what we sell, the published hard rules and the licence/VAT position,
  // every figure read from company_registration and pricing_config on this message.
  //
  // IT REPLACES A DEADLINE THAT NO LONGER EXISTS. This prompt told suppliers "free until 31 July
  // 2027; AED 1,000/year from 1 August 2027". The founder ruled on 6 September that there is no
  // calendar date at all — charging begins with registration number 1,001, whenever that happens —
  // and pricing_config.supplier_charging_starts has been NULL since. A price typed into a prompt
  // cannot be corrected by correcting the company.
  let companyBlock = '';
  try {
    const { data: cc } = await prefetch.company;
    companyBlock = String((cc as Record<string, unknown> | null)?.block || '');
  } catch (_e) { companyBlock = ''; } // a thinner grounding beats a dropped WhatsApp message

  const { ctx, ids } = await prefetch.faq;
  // THE REPLY IS THE MODEL'S (1195-1197, _shared/ai_reply.ts via model_says.ts): the company brief, the model chain
  // (conversation_reply: claude-sonnet-5.5 -> gemini -> another family; ruling 1219), the figure and reply guard with a model rewrite, suppliers in English.
  // Everything code knows about this message goes in as facts: who they are, their own record, the database's own
  // answer for the intent it recognised, the approved FAQ for it, the live company block.
  const situation = [audienceBlock,
    ownRecord.trim(), brainPack.trim(),
    detReply ? 'OUR DATABASE ANSWER FOR THIS MESSAGE (facts to use; the words are yours):\n' + detReply : '',
    ctx ? 'APPROVED FAQ FOR THIS MESSAGE (may be for the other audience; apply the audience rules):\n' + ctx : '',
    // they are writing to +1 218 316 6814 already (final audit 12 Nov 2026, W5; model_says.ts WA_PERSON_RULE says what the hand-off is)
    rt?.needs_a_person === true ? 'They need a person: say their message has been passed to our team (working hours Mon-Fri 9am-6pm GST). For a member of the team to reply to them here on WhatsApp, they can send MENU and choose "Talk to a person". By e-mail: management@quotesdone.com. Never give them a phone or WhatsApp number: they are writing to ours.' : '',
    'Never volunteer supplier-side commercial terms to a customer. Do not promise that quote requests arrive immediately.',
    companyBlock ? 'COMPANY BLOCK (live):\n' + companyBlock : ''].filter(Boolean).join('\n\n');
  // THE STATUS LANE'S FACTS (status_lane.ts, ruling 1571): who they are, their own record, the database's answer, and nothing
  // about the company beyond what that answer says. No FAQ and no company block: a status answer states their rows.
  const lean = [audienceBlock, ownRecord.trim(), brainPack.trim(),
    detReply ? 'OUR DATABASE ANSWER FOR THIS MESSAGE (facts to use; the words are yours):\n' + detReply : '',
    'Never volunteer supplier-side commercial terms to a customer. Do not promise that quote requests arrive immediately.'].filter(Boolean).join('\n\n');
  return { situation, ids, lean };
}
