// _shared/llm.ts — canonical OpenRouter client for QuotesDone edge functions.
// One source for the transport + model fallback loop + 25s abort timeout (OS-audit H9, generalised).
// Callers bind a ladder via makeLlm(LADDER); existing call sites `llm(sys, input, max)` keep working.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const _admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

export async function sec(k: string){ const { data } = await _admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

export const OPUS_FIRST   = ['anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5'];
export const SONNET_FIRST = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];

export type Msg = { role: string; content: string };
export interface LlmDefaults { max?: number; timeoutMs?: number; temperature?: number; }

// Bind a model ladder → returns llm(sys, input, max?) with the QuotesDone fallback loop + abort timeout.
export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}){
  const dMax = def.max ?? 700, dTo = def.timeoutMs ?? 25000;
  return async function llm(sys: string, input: string | Msg[], max: number = dMax): Promise<string | null> {
    const key = await sec('openrouter_api_key'); if (!key) return null;
    const msgs: Msg[] = typeof input === 'string' ? [{ role: 'user', content: input }] : input;
    const base: Record<string, unknown> = { max_tokens: max, messages: [{ role: 'system', content: sys }, ...msgs] };
    if (def.temperature != null) base.temperature = def.temperature;
    for (const model of models){
      for (let at = 0; at < 2; at++){
        const ac = new AbortController(); const to = setTimeout(() => ac.abort(), dTo);
        try {
          const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify({ ...base, model }), signal: ac.signal });
          const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c;
        } catch (_e) { /* try next attempt / model */ } finally { clearTimeout(to); }
      }
    }
    return null;
  };
}
