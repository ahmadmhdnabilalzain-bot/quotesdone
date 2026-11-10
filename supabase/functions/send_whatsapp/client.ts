// send_whatsapp's service client and secrets (split out of index.ts, 9 Nov 2026; a pure move).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { J } from '../_shared/json_response.ts';
import { secretOk } from '../_shared/internal_auth.ts';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export { J };
export async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.
/** Twilio codes that mean the recipient opted out of our messages (21610: replied STOP). Final, and never failed over. */
export const OPTED_OUT_CODES = new Set(['21610']);
