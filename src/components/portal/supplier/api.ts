// The one fetch helper for the supplier portal's edge-function calls. It lived inline in
// SupplierPortal.tsx; the RFQ, journey and insights components split out on 14 Sep 2026 need the same
// call, and a second copy is how two error-handling behaviours start.
//
// `_http` carries the status of a non-2xx answer (14 Sep 2026). The body alone cannot tell an expired
// session from a refusal — the gateway's "Invalid JWT" and a function's own 401 look different — so
// the portal could only show "Something went wrong" and a retry that could never succeed.
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';

export async function call(path: string, body: Record<string, unknown>, token?: string | null): Promise<any> {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({ ok: false, error: 'bad_response' }));
  if (!r.ok && j && typeof j === 'object') j._http = r.status;
  return j;
}
