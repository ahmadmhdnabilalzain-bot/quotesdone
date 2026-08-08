// One POST to supabase/functions/project_api. Shapes and derivations live in ./model.
import { SUPA_ANON, SUPA_FN } from '@/lib/supaEnv';

export type ApiResult<T> = { ok: true; data: T } | { ok: false; error: string };

/**
 * Errors are returned, never thrown, so every caller has to render them — a swallowed error is how
 * a surface ends up showing an encouraging empty state over a failure. `error` is passed through
 * verbatim (e.g. 'unauthorized', 'not_found'); components map the codes they know to human text via
 * strings.ts and show the rest as-is rather than inventing a friendlier lie.
 */
export async function projectApi<T>(token: string, body: Record<string, unknown>): Promise<ApiResult<T>> {
  try {
    const r = await fetch(`${SUPA_FN}/project_api`, {
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
