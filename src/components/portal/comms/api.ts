// SPEC §16 Communication Center — the typed client for supabase/functions/messages_api.
//
// EVERY TYPE BELOW IS TRANSCRIBED FROM THAT FUNCTION. A field that is not here is a field it does
// not serve, and the gaps are load-bearing, so they are named rather than left to be discovered:
//
//   * A thread is keyed by (inquiry_id, supplier_id) and carries NO project_id. §16 asks for
//     "everything attached to: project, RFQ, supplier"; the RFQ and the supplier are served, the
//     project is not, by either messages_api or public.messages/public.chat_threads.
//   * There is no attachment on a message. `send` accepts `body` and nothing else, and
//     public.messages has no file/attachment/document column. A file control in the composer would
//     therefore look like an attachment and be a discard — see the note in CommunicationCenter.
//   * WhatsApp, e-mail and calls ARE in this payload, and this comment said the opposite until
//     13 Aug 2026. otherChannels() was added to messages_api on 7 Aug and joins wa_messages on the
//     customer's own phone, inbound_messages on their own e-mail and customer_calls on their own
//     customer_id. Measured signed in as a real customer: `threads` returned a WhatsApp row with 10
//     messages and an e-mail row with 1 unread — while the surface above still said they were not
//     routed in, and `action:'thread'` rejected their null inquiry_id at the door. `channel_thread`
//     is the reader that closes that; a channel row carries `channel` and a null inquiry_id.
//
// Chat is GATED on purpose: it unlocks only after a paid reveal, and even then a chat must be
// requested and approved. `request_chat` may be answered outright by the category agent instead of
// opening one. That is the product, not a failure, and the surface renders all three outcomes.
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

export type Lang = 'en' | 'ar';

/** none = never requested · requested = awaiting review · open = live · banned = closed for policy. */
export type ChatStatus = 'none' | 'requested' | 'open' | 'banned' | string;

/** 'chat' is a supplier conversation on one RFQ; the other three are the customer's own
 *  correspondence with QuotesDone and carry inquiry_id: null. */
export type Channel = 'chat' | 'whatsapp' | 'email' | 'call';

/** One row of action:'threads'. */
export interface ThreadSummary {
  /** Absent on rows served before 7 Aug 2026; treated as 'chat'. */
  channel?: Channel;
  /** null on whatsapp / email / call rows — they are not about one RFQ. */
  inquiry_id: string;
  supplier_id: number;
  /** The supplier's company name — this list only exists after the reveal is paid. */
  counterpart: string;
  /** The RFQ's summary, falling back to its category. On a channel row, the channel's own subject. */
  subject: string;
  chat_status: ChatStatus;
  last: string | null;
  last_at: string | null;
  unread: number;
  /** How many messages the channel holds. Only on channel rows. */
  count?: number;
}

export interface ThreadsResponse {
  ok: true;
  /** null when the sign-in is neither a customer nor a claimed supplier — then threads is []. */
  role: 'customer' | 'supplier' | null;
  threads: ThreadSummary[];
}

export interface ChatMessage {
  id: number | string;
  /** 'quotesdone' only occurs on the whatsapp / email / call channels — those are the customer's
   *  correspondence with US, not with a supplier. */
  sender: 'customer' | 'supplier' | 'quotesdone';
  body: string;
  created_at: string;
  /** e-mail only. */
  subject?: string | null;
  /** call log only, in seconds. */
  duration_s?: number | null;
}

/** action:'channel_thread' — the customer's own WhatsApp / e-mail / call history with QuotesDone. */
export interface ChannelThreadResponse {
  ok: true;
  channel: Channel;
  counterpart: string;
  chat_status?: ChatStatus;
  messages: ChatMessage[];
  /** Present when the channel has nothing to match the customer to. */
  note?: string;
  unread_note?: string;
}

export interface ThreadResponse {
  ok: true;
  role?: 'customer' | 'supplier';
  counterpart?: string;
  chat_status?: ChatStatus;
  /** true when the chat is not open — messages is then [] and `note` says why. */
  locked?: boolean;
  /** The platform's off-platform-contact warning. Rendered VERBATIM: it is the term the customer
   *  accepted at sign-up and carries a stated AED 10,000 penalty. Paraphrasing it is a liability. */
  warning?: string;
  messages: ChatMessage[];
  note?: string;
}

/** `send` has three outcomes and two of them are refusals. `ok:false` here is not a transport error. */
export interface SendResponse {
  ok: boolean;
  message?: ChatMessage;
  /** true when the message was refused for containing contact details. */
  blocked?: boolean;
  /** true when it was HELD for review rather than causing a ban. */
  review?: boolean;
  warning?: string;
}

/** `request_chat` may answer the question instead of opening a chat. All three shapes are real. */
export interface RequestChatResponse {
  ok: boolean;
  /** The category agent resolved it — `answer` is the reply and no chat was opened. */
  answered?: boolean;
  answer?: string;
  /** Sent to a human for review. */
  requested?: boolean;
  status?: ChatStatus;
  note?: string;
}

export type CommsResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string };

/**
 * One POST to a customer-authed edge function, named as a LITERAL first argument.
 *
 * The function name used to be interpolated into the URL (`${SUPA_FN}/messages_api`), which works
 * and is invisible: `call('messages_api', { action: 'thread' })` is one grep away from answering
 * "what can a customer's page reach, and with which actions", and a template literal is not. That
 * question is asked by the row #4 scorer, by the deploy-parity checker and by anyone auditing what
 * a customer JWT can open — this is the same convention approvals/api.ts already uses, for the same
 * stated reason.
 *
 * Errors are RETURNED, never thrown, so every caller has to render them: a swallowed error is how
 * an inbox ends up showing "no messages" over a failure to ask.
 */
export async function call<T>(fn: string, body: Record<string, unknown>, token: string): Promise<CommsResult<T>> {
  try {
    const r = await fetch(`${SUPA_FN}/${fn}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
      body: JSON.stringify(body),
    });
    const json = (await r.json().catch(() => null)) as Record<string, unknown> | null;
    if (!json) return { ok: false, error: 'no_response' };
    if (typeof json.error === 'string') return { ok: false, error: json.error };
    if (!r.ok) return { ok: false, error: `http_${r.status}` };
    return { ok: true, data: json as T };
  } catch (e) {
    return { ok: false, error: (e as Error)?.message || 'network_error' };
  }
}

/** Kept as an alias so nothing outside this file has to change with the rename. */
export const messagesApi = <T,>(token: string, body: Record<string, unknown>) => call<T>('messages_api', body, token);

export const listThreads = (token: string) =>
  call<ThreadsResponse>('messages_api', { action: 'threads' }, token);

export const openThread = (token: string, inquiry_id: string, supplier_id: number) =>
  call<ThreadResponse>('messages_api', { action: 'thread', inquiry_id, supplier_id }, token);

/** Read one of the three non-chat channels. Scoped server-side to the customer's OWN phone /
 *  e-mail / customer_id — the same join keys the list itself is built from. */
export const openChannel = (token: string, channel: Channel) =>
  call<ChannelThreadResponse>('messages_api', { action: 'channel_thread', channel }, token);

export const sendMessage = (token: string, inquiry_id: string, supplier_id: number, body: string, attachment_path?: string | null, attachment_name?: string | null) =>
  call<SendResponse>('messages_api', { action: 'send', inquiry_id, supplier_id, body, attachment_path: attachment_path || null, attachment_name: attachment_name || null }, token);

export const requestChat = (token: string, inquiry_id: string, supplier_id: number, question: string) =>
  call<RequestChatResponse>('messages_api', { action: 'request_chat', inquiry_id, supplier_id, question }, token);
