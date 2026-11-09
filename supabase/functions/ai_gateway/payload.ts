// ai_gateway/payload.ts — what the payload needs (capabilities) and which parameters a model supports. Moved verbatim from index.ts (9 Nov 2026).
import type { Msg } from './shared.ts';

// What the payload actually needs, read off the payload itself. A caller that has to declare
// "this has an image in it" will eventually forget to, and the failure mode is a provider error
// nobody can trace. Reading it here means vision/audio can never be mis-routed by omission.
// deno-lint-ignore no-explicit-any
// OpenRouter's supported_parameters per model. response_format FAILS a request on a model that lacks
// it, so "unknown" means "do not send". The list is loaded once per isolate, refreshed hourly, and
// started BEFORE the attempt loop with a short timeout: an attempt never waits on it, and a list
// that has not arrived yet reads as unknown for that attempt (the caller's own parser is the fallback).
const PARAMS_TTL_MS = 60 * 60 * 1000;
let _params: Map<string, Set<string>> | null = null;
let _paramsAt = 0;
let _paramsLoading: Promise<void> | null = null;
export function loadSupportedParams(): void {
  if (_paramsLoading || (_params && Date.now() - _paramsAt < PARAMS_TTL_MS)) return;
  _paramsLoading = fetch('https://openrouter.ai/api/v1/models', { signal: AbortSignal.timeout(1500) })
    .then((r) => r.ok ? r.json() : null)
    .then((j) => {
      if (!j?.data) return;
      // deno-lint-ignore no-explicit-any
      _params = new Map(j.data.map((d: any) => [String(d.id), new Set<string>((d.supported_parameters ?? []).map(String))]));
      _paramsAt = Date.now();
    })
    .catch(() => {})
    .finally(() => { _paramsLoading = null; });
}
export function supportedParams(model: string): Set<string> | null {
  return _params?.get(model) ?? null;
}

export function inferCaps(msgs: Msg[], tools?: any[]): { caps: string[]; hasBinary: boolean } {
  const caps = new Set<string>();
  let hasBinary = false;
  for (const m of msgs) {
    const c = m?.content;
    if (!Array.isArray(c)) continue;
    for (const part of c) {
      const t = String((part as Record<string, unknown>)?.type || '');
      if (t === 'image_url' || t === 'image') { caps.add('vision'); hasBinary = true; }
      else if (t === 'input_audio' || t === 'audio') { caps.add('audio'); hasBinary = true; }
      else if (t === 'file') { caps.add('vision'); hasBinary = true; }  // file-parser feeds pages to the vision path
    }
  }
  if (Array.isArray(tools) && tools.length) caps.add('tools');
  return { caps: Array.from(caps), hasBinary };
}
