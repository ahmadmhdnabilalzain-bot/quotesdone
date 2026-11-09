// ai_gateway/shared.ts — the service client and the small helpers every stage of the gateway uses. Moved verbatim from index.ts (9 Nov 2026).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { embedGteRemote } from '../_shared/ml_embed_client.ts';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

export async function sec(k: string) {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return (data?.value as string) || '';
}
export const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// Free, in-region gte-small - RUN IN embed_ml, NOT IN THIS WORKER (it_engineer, 2 Nov 2026). Measured on production
// (function_edge_logs + function_logs, 1-2 Nov): 6 ai_gateway requests died "CPU Time exceeded" (HTTP 546). Four were
// {action:'embed'} calls of ~200 bytes from a Node client that died 400-450 ms after boot, two per worker: the model's
// inference threads spend the 2 s CPU allowance in a fraction of that wall time, and every request sharing the worker
// dies with it. The other two were chat calls whose semantic-cache embed ran in the same worker as the model call.
// embed_ml is the one place a model runs (the same gte-small, action 'gte', so the vector space never mixes); a call
// it cannot answer is a null here, exactly as a failed in-process run was. prevented by: ai_gateway/embed_is_remote.test.ts
export async function embed(text: string, timeoutMs = 8000): Promise<string | null> {
  const v = await embedGteRemote(admin, String(text).slice(0, 1200), 'ai_gateway', timeoutMs,
    (why) => console.error('ai_gateway embed: embed_ml gave no vector:', why.slice(0, 300)));
  return v ? '[' + v.join(',') + ']' : null;
}

export async function sha256(s: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, '0')).join('');
}

// Anthropic bills a cached prefix at ~10% of the prompt rate but requires a minimum cacheable
// block. Below roughly 1k tokens the cache write costs more than it saves, so only mark long
// system prompts. This is the single biggest lever we have: 94% of spend is input tokens.
export const CACHE_MIN_CHARS = 4000;

// supabase-js .rpc() returns a PostgrestFilterBuilder - it is thenable but NOT a Promise, so
// .catch() on it throws "admin.rpc(...).catch is not a function". Caught in dry-run testing.
// Every non-critical call (logging, cache writes) goes through here: telemetry must never be
// able to fail the business call it is describing.
export async function rpcSafe(name: string, args: Record<string, unknown>) {
  try { const { data } = await admin.rpc(name, args); return data; } catch (_e) { return null; }
}

// deno-lint-ignore no-explicit-any
export type Msg = { role: string; content?: any; [k: string]: unknown };
