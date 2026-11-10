// turn.ts - the state of ONE inbound WhatsApp turn. handleInbound was a single 1,200-line closure whose locals every
// later block read; split into modules (9 Nov 2026, customer_support) those locals live on this object, created once
// per request by newTurn() and passed to each phase in index.ts. Per request, never module scope: turns overlap.
// A field marked "set by X" is filled by that phase and read only by the phases after it.
import type { waConversation } from '../_shared/wa_history.ts';
import type { holdUnwritten, modelSays } from './model_says.ts';
import type { MenuDeps, menuTurn } from './menu_flow.ts';
import { waRow } from './wa_row.ts';
import { admin, mkLog } from './shared.ts';

export type Aud = 'customer' | 'supplier' | 'visitor' | 'founder';
export type SayResult = Awaited<ReturnType<typeof modelSays>>;
// deno-lint-ignore no-explicit-any
type Rpc = Promise<{ data: any }>;

export interface WaTurn {
  logRun: ReturnType<typeof mkLog>;
  receivedAt: string;
  arrivalId: number | null;
  messageSidSeen: string;
  reviewP: Promise<unknown>;
  waInsert: (rcv: string, row: Record<string, unknown>) => Promise<{ error?: unknown }>;
  // set by acceptArrival (arrival.ts)
  From: string; Body: string; Profile: string; MessageSid: string; ListId: string; ButtonPayload: string;
  media: { url: string; mime: string }[];
  internalCaller: boolean;
  signatureVerified: boolean;
  // the reply state, written by the says (say.ts)
  modelEscalate: boolean;
  sayOutage: boolean;
  sayProblems: string[];
  sayAttempts: string[];
  factsAnswer: boolean;
  history: ReturnType<typeof waConversation> | null;
  forbidden: Promise<string[]> | null;
  // set by makeSay (say.ts)
  historyUnavailable: (error: string) => Promise<void>;
  askModel: (aud: Aud, situation: string, langGiven?: 'en' | 'ar', must?: string[], signal?: AbortSignal, extraCheck?: (t: string) => string[],
    lane?: { kind: 'status' | 'app'; databaseAnswer: string }) => Promise<SayResult>;
  adopt: (r: SayResult) => string;
  sayFor: (aud: Aud) => (situation: string, lang?: 'en' | 'ar', must?: string[], extraCheck?: (t: string) => string[]) => Promise<string>;
  say: (situation: string, lang?: 'en' | 'ar') => Promise<string>;
  /** The status and app lanes (status_lane.ts): status_reply, no brief, the last turns only; `databaseAnswer` names the must-carry refs. */
  sayLane: (lane: 'status' | 'app', facts: string, databaseAnswer: string) => Promise<string>;
  heldTurn: (aud: Aud, lang: 'en' | 'ar', situation: string, why: string) => ReturnType<typeof holdUnwritten>;
  // set by identify (identify.ts)
  audience: string;
  // deno-lint-ignore no-explicit-any
  known: any;
  timings: Record<string, number>;
  mark: (k: string) => void;
  prefetch: { timeline: Rpc; mine: Rpc; company: Rpc; faq: Promise<{ ctx: string; ids: number[] }> };
  // set by startClassification (classification.ts)
  menuDeps: MenuDeps;
  menuIn: Parameters<typeof menuTurn>[1];
  typedQuestion: boolean;
  needsPersonP: () => Promise<boolean | null>;
  // set by startSpeculation (speculation.ts)
  specAbort: AbortController;
  speculative: Promise<SayResult | null> | null;
  directiveRead: () => Promise<{ change?: boolean; amount?: unknown } | null>;
  // set by readTimeline (identify.ts)
  timelineEvents: number;
}

export function newTurn(): WaTurn {
  const logRun = mkLog(Date.now());
  const receivedAt = new Date().toISOString();   // the inbound's arrival: wa_messages.created_at, so replied_at - created_at is the first-reply time
  // THE MESSAGE IS STORED ON ARRIVAL, NOT AFTER THE REPLY (19 Oct 2026, seat customer_support; sandbox run 5, S19).
  // Since #1335 the reply is model-written, and the turn's wa_messages row was written only once the model chain
  // finished: 73 s for the run-5 demo message (llm_failed after the hold). For those 73 s the customer's words
  // existed nowhere but in a waitUntil isolate, and an isolate killed by its wall-clock or CPU cap lost them for
  // good (wa_inbound_seen already held the MessageSid, so Twilio's redelivery was dropped as a duplicate).
  // arrivalId is the row written the moment the sender is authenticated (STORED ON ARRIVAL in arrival.ts); the FIRST
  // waInsert of the turn completes that row in place, later ones (a second row in one turn) insert as before.
  // Every wa_messages write goes through waRow (wa_row.ts): created_at = arrival, replied_at = reply sent.
  // Prevented by: arrival_is_stored_first.test.ts.
  const t = {
    logRun, receivedAt,
    arrivalId: null as number | null,
    messageSidSeen: '',
    // The review of a decision, started beside the reply (general_turn.ts) and awaited in the finally; it never throws (review_request.ts).
    reviewP: Promise.resolve(null) as Promise<unknown>,
    // ---- THE WORDS OF EVERY CONVERSATION REPLY (rulings 1195/1196/1197, 12 Oct 2026) ----------------------------
    // Code decides what happened; the model writes what is said, in this turn (model_says.ts). '' = no model
    // answered: nothing conversational is sent, the turn is recorded unsent (send_error 'no_model_reply').
    // Every sendWa below that carries conversation text sends a `say` result (no_unwritten_send.test.ts).
    // modelEscalate: the model's own reading that a person is needed (a complaint, a dispute, a request for one), OR-ed
    // with fn_wa_route's needs_a_person, so a complaint the router misses still reaches a person (review of #1335).
    modelEscalate: false,
    // OPENROUTER DOWN ON THIS TURN (founder_instruction 1339): set by the last say; heldTurn sends its fixed notice only then.
    sayOutage: false,
    // WHY THE LAST SAY'S DRAFTS WERE REFUSED (aiReply.problems): filed with the turn so the re-ask names them (_shared/reask.ts).
    sayProblems: [] as string[],
    // WHAT THE LAST SAY TRIED (aiReply.attempts: each call, each rewrite and the problems that refused it), kept on the turn's
    // row so a refused or rewritten reply names its reason (customer_support, 3 Nov 2026: 7 Luna rewrites in a run, no record why).
    sayAttempts: [] as string[],
    // THE TURN'S FACTS ALONE SAY WHAT TO TELL THEM (a person is needed): only then may modelSays's brief-less last chance run
    // (review of #1816). Set just before the main reply is asked; every earlier say runs without it.
    factsAnswer: false,
    // THE WHOLE CONVERSATION, EVERY TURN (2 Nov 2026): this number's earlier turns, read once per turn (_shared/wa_history.ts).
    history: null as ReturnType<typeof waConversation> | null,
    // THE OTHER PARTY BEFORE A REVEAL (3 Nov 2026, pre_reveal_identities.ts): read once per turn from the number's confirmed
    // owner (fn_whatsapp_owner); a reply naming a counterpart not yet revealed to them is refused. No owner: [].
    forbidden: null as Promise<string[]> | null,
  } as unknown as WaTurn;
  // RACE WITH THE SWEEP (review of #1457): the arrival row is completed only while it is still 'received'. If
  // fn_wa_arrival_sweep took it first (a turn past 5 minutes), the row stays 'escalated', this turn's record goes on a row
  // of its own, and fn_wa_arrival_turn_finished closes the action and suppresses a holding notice not yet sent.
  const waInsert = async (rcv: string, row: Record<string, unknown>) => {
    const id = t.arrivalId; t.arrivalId = null;
    if (id == null) return await admin.from('wa_messages').insert(waRow(rcv, row));
    const upd = await admin.from('wa_messages').update(waRow(rcv, row)).eq('id', id).eq('meta->>stage', 'received').select('id');
    if (upd.error || (upd.data?.length ?? 0) > 0) return upd;
    const own = await admin.from('wa_messages').insert(waRow(rcv, { ...row, meta: { ...((row.meta as Record<string, unknown>) || {}), after_sweep_of: id } }));
    await admin.rpc('fn_wa_arrival_turn_finished', { p_wa_message_id: id }).then(() => null, () => null);
    return own;
  };
  t.waInsert = waInsert;
  return t;
}
