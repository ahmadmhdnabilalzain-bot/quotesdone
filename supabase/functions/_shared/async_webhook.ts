// async_webhook — acknowledge a provider's webhook at once, and do the work after the reply.
// Seat: it_engineer (shared platform). 23 Sep 2026.
//
// WHY. Twilio gives a WhatsApp webhook 15 seconds and Meta about 20; a webhook that is late is retried,
// and one that keeps being late is disabled. Reasoning (think(): a plan, retrieval, a written answer,
// sometimes an independent check) is several model calls — it cannot sit inside that window. So the
// channel handlers answer the webhook immediately and hand the message to EdgeRuntime.waitUntil, which
// keeps the worker alive until the reply has been composed and sent through the provider's REST API.
// The reply never rode in the webhook response (wa_inbound answers with an empty <Response/>), so nothing
// the customer sees changes except that it can no longer be cut off by the provider's clock.
//
// THE BODY IS READ BEFORE THE ACK. A request body is tied to its connection; once the response is sent it
// may not be readable. `detach` copies it into a fresh Request first (the signature check needs the same
// URL, headers and every parameter, so all of them travel).
// ponytail: no durable inbox. If the worker dies mid-work the message is lost after the 200; the
// idempotency row (wa_inbound_seen / social_message) is written first, so add a sweep over those if it happens.

// deno-lint-ignore no-explicit-any
type WaitUntil = (p: Promise<unknown>) => void;
export function runtimeWaitUntil(): WaitUntil | null {
  // deno-lint-ignore no-explicit-any
  const er = (globalThis as any).EdgeRuntime;
  return typeof er?.waitUntil === 'function' ? (p) => er.waitUntil(p) : null;
}

/** A copy of the request whose body is already in memory, safe to read after the response has gone. */
export async function detach(req: Request): Promise<Request> {
  const body = await req.arrayBuffer();
  return new Request(req.url, { method: req.method, headers: req.headers, body: body.byteLength ? body : undefined });
}

/** Return `ack` now; run `work` after it. A failure is logged, never thrown into a response already sent. */
export function ackThenWork(ack: Response, work: () => Promise<unknown>, label: string, waitUntil: WaitUntil | null = runtimeWaitUntil()): Response {
  const p = (async () => { try { await work(); } catch (e) { console.error(label + ' background work failed:', String((e as Error)?.message || e)); } })();
  if (waitUntil) waitUntil(p);
  return ack;
}
