// One POST to a customer-authed edge function. The shape of every response lives in ./model.
//
// The helper is named `call` and takes the function name as its first literal argument, matching
// CustomerPortal's own client — the portal's convention, not a new one. It is deliberately NOT
// generic: `call<T>('procurement_api', …)` reads identically to a human and is a different string
// to every tool that greps this repository for what a customer's page can reach, and a generic
// parameter is not worth being invisible to them. The wire is JSON either way, so each call site
// casts once, at the boundary, to the transcription in ./model.
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';

export type ApiResult = { ok: true; data: Record<string, unknown> } | { ok: false; error: string };

/**
 * Errors are RETURNED, never thrown, so every caller has to render them. A swallowed error is how a
 * surface ends up showing an encouraging empty state over a failure — "no approvals pending" when
 * the truth is "we could not ask". `error` is passed through verbatim; the components map the codes
 * they know to human text and print the rest as-is rather than inventing a friendlier lie.
 */
export async function call(fn: string, body: Record<string, unknown>, token: string): Promise<ApiResult> {
  try {
    const r = await fetch(fnUrl(fn), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token || SUPA_ANON}` },
      body: JSON.stringify(body),
    });
    const json = (await r.json().catch(() => null)) as Record<string, unknown> | null;
    if (!json) return { ok: false, error: 'no_response' };
    if (typeof json.error === 'string') return { ok: false, error: json.error };
    if (!r.ok) return { ok: false, error: `http_${r.status}` };
    return { ok: true, data: json };
  } catch (e) {
    return { ok: false, error: (e as Error)?.message || 'network_error' };
  }
}
