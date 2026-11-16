// after_reveal_door — the website widget's side of "a problem with this job" (customer_support, 16 Nov 2026, agent AFTER_REVEAL;
// holes CUSTOMER.md item 4). The widget had no refund or complaint door: a signed-in customer who wrote "the supplier I paid to
// reveal never called" or "he raised the price" got an answer and nothing else, and no case existed for any seat to read.
//
// NO NEW MODEL CALL AND NO KEYWORD. The widget already reasons, on every message, whether it needs a person: a complaint, a dispute,
// a refund demand, however it is worded (needsAPerson, _shared/reasoned_decisions.ts; site_assistant.person). When that reading
// says yes and the caller is a SIGNED-IN customer (identify(): the session's own e-mail, never typed into the chat), the message goes
// to the one door every channel shares (public.fn_customer_after_reveal_message, channel 'widget', no job). For the widget the door
// picks NO job itself (review AFTERREVEAL item 6: not "his only revealed job", not a number spotted in a chat turn): a model reading
// (customer_support.after_reveal_job) names the job or none, and only a named job is filed with the dispute intake, where the model
// reads it beside the revealed quotation: the supplier contacted him (from the widget he is asked to CONFIRM with one tap; the reading
// records nothing) / did not (the refund door) / a dispute that needs a case / nothing for a case. Whatever it reads, he is written to
// with the result on his own address (the widget's reply is already sent by then). An anonymous visitor has no job.
// prevented by: ./after_reveal_door.test.ts
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
export type Who = { audience: 'customer' | 'supplier'; id: string; email?: string | null } | null | undefined;
export type DoorOutcome = { filed: boolean; why: string; result?: Record<string, unknown> };

export async function fileAfterRevealProblem(rpc: Rpc, who: Who, message: string, person: boolean | null | undefined): Promise<DoorOutcome> {
  if (person !== true) return { filed: false, why: person === false ? 'the reading found nothing that needs a person' : 'not reasoned yet (held)' };
  if (!who || who.audience !== 'customer' || !who.id) return { filed: false, why: 'not a signed-in customer: no revealed job to attach' };
  const text = String(message || '').trim().slice(0, 4000);
  if (!text) return { filed: false, why: 'an empty message' };
  const { data, error } = await rpc('fn_customer_after_reveal_message', { p_customer: who.id, p_message: text, p_channel: 'widget', p_transaction: null });
  if (error) return { filed: false, why: 'the door failed: ' + error.message.slice(0, 200) };
  const r = (data ?? {}) as Record<string, unknown>;
  return r.ok === true ? { filed: true, why: 'filed with the dispute intake', result: r }
    : { filed: false, why: String(r.code ?? 'not opened'), result: r };
}
