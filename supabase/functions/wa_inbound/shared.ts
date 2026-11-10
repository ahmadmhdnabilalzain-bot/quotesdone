// shared.ts - the module-level state of wa_inbound, defined once here and imported by every module of the
// function: the service-role client, the ai_gateway URL, the empty Twilio answer, the app_secrets reader, the
// IT-engineer finding, the agent_runs logger and the throttled founder alert. Moved out of index.ts unchanged
// (9 Nov 2026, customer_support: index.ts was one 1,589-line file); nothing here reads a request.
import { perTurn, withTurnCache } from '../_shared/turn_cache.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { inDbRegion } from '../_shared/db_region.ts';
export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
// run in the database's region, not the caller's (_shared/db_region.ts: ~3 s of gateway work per call in us-east-1, ~0.4 s there)
export const GATEWAY = inDbRegion(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway');
export const TW = (s = 200) => new Response('<Response></Response>', { status: s, headers: { 'Content-Type': 'text/xml' } });
// ONE READ OF EACH SETTING PER TURN (it_engineer, 10 Nov 2026, channels audit R7): inside a turn (withTurnSecrets, index.ts)
// each key is read once and shared (_shared/turn_cache.ts); outside one it is read as before.
// prevented by: wa_inbound/a_turn_reads_each_setting_once_and_a_forgery_claims_nothing.test.ts
const readSetting = async (k: string) => { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; };
export const sec = perTurn(readSetting);
export const withTurnSecrets = withTurnCache;
// AN INTERNAL FAULT IS THE IT ENGINEER'S, NEVER THE CUSTOMER'S (22 Sep 2026). The person gets the
// courteous fallback; the real error goes here, deduplicated on its key, customer_facing because a
// WhatsApp answer was lost to it. Best effort: a failed finding must not cost the reply.
export async function itFinding(key: string, title: string, evidence: Record<string, unknown>): Promise<void> {
  try {
    await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: key, p_title: title, p_where: 'edge function wa_inbound', p_blast: 'customer_facing', p_affected: 1,
      p_evidence: evidence, p_ruled_out: [], p_undetermined: [], p_raised_by: 'customer_support',
    });
  } catch (e) { console.error('wa_inbound: IT finding not raised:', key, String((e as Error)?.message || e)); }
}

export function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'wa_inbound', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break the webhook */ }
  };
}

// Keep a forgery flood from burning the founder's inbox: one alert per event per 30 minutes.
export async function alertThrottled(event: string, level: string, detail: string) {
  try {
    const since = new Date(Date.now() - 30 * 60000).toISOString();
    const { count } = await admin.from('founder_alerts').select('id', { count: 'exact', head: true }).eq('event', event).gte('created_at', since);
    if ((count || 0) > 0) return false;
    await admin.from('founder_alerts').insert({ level, event, detail, channel: 'system' });
    return true;
  } catch (_e) { return false; }
}
