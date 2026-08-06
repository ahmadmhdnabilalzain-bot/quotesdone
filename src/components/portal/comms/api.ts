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
//   * WhatsApp, email and calls are NOT in this payload. messages_api opens chat_threads, messages,
//     transactions, leads, customers, inquiries, category_agents, chat_violations, notifications,
//     app_secrets and agent_actions — not wa_messages, not inbound_messages, and no call log
//     (production has no table that logs a call against an inquiry, supplier or customer at all).
//
// Chat is GATED on purpose: it unlocks only after a paid reveal, and even then a chat must be
// requested and approved. `request_chat` may be answered outright by the category agent instead of
// opening one. That is the product, not a failure, and the surface renders all three outcomes.
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

export type Lang = 'en' | 'ar';

/** none = never requested · requested = awaiting review · open = live · banned = closed for policy. */
export type ChatStatus = 'none' | 'requested' | 'open' | 'banned' | string;

/** One row of action:'threads'. */
export interface ThreadSummary {
  inquiry_id: string;
  supplier_id: number;
  /** The supplier's company name — this list only exists after the reveal is paid. */
  counterpart: string;
  /** The RFQ's summary, falling back to its category. */
  subject: string;
  chat_status: ChatStatus;
  last: string | null;
  last_at: string | null;
  unread: number;
}

export interface ThreadsResponse {
  ok: true;
  /** null when the sign-in is neither a customer nor a claimed supplier — then threads is []. */
  role: 'customer' | 'supplier' | null;
  threads: ThreadSummary[];
}

export interface ChatMessage {
  id: number;
  sender: 'customer' | 'supplier';
  body: string;
  created_at: string;
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

/** One POST to messages_api. Errors are returned, never thrown, so every caller must render them. */
export async function messagesApi<T>(token: string, body: Record<string, unknown>): Promise<CommsResult<T>> {
  try {
    const r = await fetch(`${SUPA_FN}/messages_api`, {
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

export const listThreads = (token: string) =>
  messagesApi<ThreadsResponse>(token, { action: 'threads' });

export const openThread = (token: string, inquiry_id: string, supplier_id: number) =>
  messagesApi<ThreadResponse>(token, { action: 'thread', inquiry_id, supplier_id });

export const sendMessage = (token: string, inquiry_id: string, supplier_id: number, body: string) =>
  messagesApi<SendResponse>(token, { action: 'send', inquiry_id, supplier_id, body });

export const requestChat = (token: string, inquiry_id: string, supplier_id: number, question: string) =>
  messagesApi<RequestChatResponse>(token, { action: 'request_chat', inquiry_id, supplier_id, question });
