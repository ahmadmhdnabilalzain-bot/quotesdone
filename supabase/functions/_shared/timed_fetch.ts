// EVERY OUTBOUND CALL HAS A CLOCK ON IT (22 Sep 2026, it_engineer, CONN-04).
//
// WHY THIS FILE EXISTS. The connectivity audit counted 113 `fetch(` sites in deployed functions with
// no `signal:` of any kind. A fetch with no signal is bounded only by the platform killing the isolate,
// so the caller cannot tell "the far end is slow" from "the far end will never answer": the request
// occupies the isolate until the wall-clock limit, the handler's own work after it never runs, and the
// row it was going to update stays as it was. That is how a Stripe webhook can be accepted, never
// processed, and leave nothing behind that says so.
//
// WHY NOT safeFetch (_shared/safe_url.ts). That one is for a URL THIS PROCESS DID NOT CHOOSE: it also
// refuses private addresses, re-checks the final URL after redirects and streams the body under a byte
// cap, and it returns the BYTES. It is the right tool for an attachment URL out of a request body and
// the wrong one for "POST JSON to our own ai_gateway and read the reply", which is what almost all of
// the 113 are. This is that second case and nothing more: the same Response a caller already handles,
// with a deadline.
//
// SCOPE OF THIS FUNCTION, stated rather than implied: it bounds the TIME TO THE RESPONSE HEADERS plus,
// because the signal stays live, the reading of the body — AbortSignal.timeout aborts a stream that has
// begun. It does not cap the number of bytes (safeFetch does) and it does not retry.
export const DEFAULT_TIMEOUT_MS = 15_000;

/**
 * fetch() that cannot wait forever. A caller that already passes its own `signal` keeps it — the
 * explicit one wins, so wrapping a call that was already bounded changes nothing.
 */
export function timedFetch(input: string | URL | Request, init: RequestInit = {}, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<Response> {
  return fetch(input, { ...init, signal: init.signal ?? AbortSignal.timeout(timeoutMs) });
}
