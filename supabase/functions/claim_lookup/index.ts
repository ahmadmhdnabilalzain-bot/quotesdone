// claim_lookup v2 - public "is this your company?" check for the supplier claim flow.
//
// SECURITY FIX 19 Jul 2026 ---------------------------------------------------------------------
// v1 accepted { id } - the sequential leads.id primary key - and returned company_name + emirate
// to any anonymous caller. Walking id = 1,2,3... therefore dumped the entire 20,470-row supplier
// lead database: the core commercial asset of the marketplace, and the thing the whole anonymous
// model exists to protect. It was not an authentication bug (this endpoint is public BY DESIGN -
// an invited supplier has no account yet, so there is nobody to authenticate), it was an
// IDENTIFIER bug: the lookup key was guessable.
//
// v2 accepts only leads.claim_token, an unguessable UUID added in the
// leads_claim_token_stop_enumeration migration. Guessing one is infeasible, so the endpoint stays
// public while bulk harvesting stops.
//
// The raw-id path is deliberately REMOVED rather than deprecated: zero claim invitations had been
// sent and zero leads claimed when this shipped, so nothing in the wild depends on it. Anything
// still calling with { id } is either stale internal code or someone enumerating - both of which
// we want to see, so those calls are rejected AND logged rather than silently supported.
//
// OUTREACH MUST NOW LINK WITH THE TOKEN, e.g.
//     https://quotesdone.com/claim?t=<leads.claim_token>
// Never put leads.id in a supplier invitation.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const T0 = Date.now();

async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'claim_lookup', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the lookup */ }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const token = String(body.token || body.t || '').trim();

    // Reject-and-log the old enumerable shape. A burst of these is a scrape in progress.
    if (!token && (body.id || body.ref)) {
      await logRun('error', { rejected_legacy_id: 1, asked_id: Number(body.id || body.ref) || null },
        'claim_lookup was called with a numeric lead id, which is no longer accepted. Until 19 Jul 2026 this returned company_name and emirate for any sequential id, allowing the whole 20,470-row supplier database to be enumerated. Either an outreach template still builds links with leads.id (fix the template to use claim_token) or someone is attempting a scrape.');
      return J({ ok: false, error: 'invalid_link', message: 'This claim link is out of date. Please use the link from your latest invitation, or contact management@quotesdone.com.' }, 400);
    }

    if (!token || !UUID_RE.test(token)) {
      return J({ ok: false, error: 'invalid_link', message: 'This claim link is not valid. Please use the link from your invitation.' }, 400);
    }

    const { data: l, error } = await admin.from('leads')
      .select('id,company_name,emirate,claimed,approval_status,permanently_closed')
      .eq('claim_token', token).maybeSingle();

    if (error) {
      await logRun('error', { lookup_ok: 0 }, 'claim_lookup could not read the leads table (' + String(error.message).slice(0, 140) + '), so a supplier with a VALID invitation link was told their link is invalid. This is a database failure, not a bad link - the supplier may abandon the claim.');
      return J({ ok: false, error: 'temporarily_unavailable', message: 'We could not check this link just now. Please try again shortly.' }, 503);
    }

    // Unknown token: do not distinguish "never existed" from "closed" in the response.
    if (!l || l.permanently_closed) {
      await logRun('ok', { found: 0 }, 'claim_lookup received a well-formed token that matched no available lead. With unguessable tokens this should be rare; a run of these suggests a broken outreach template rather than probing, since tokens cannot be guessed.');
      return J({ ok: false, error: 'not_found', message: 'This claim link is no longer available. Please contact management@quotesdone.com.' }, 404);
    }

    await logRun('ok', { found: 1, already_claimed: l.claimed ? 1 : 0 },
      'claim_lookup resolved a valid invitation token' + (l.claimed ? ' for a lead that has ALREADY been claimed - the supplier will be told it is taken.' : ' for an unclaimed lead; the supplier can proceed to claim it.'));

    return J({ ok: true, company_name: l.company_name || null, emirate: l.emirate || null,
      claimable: !l.claimed, already_claimed: !!l.claimed });
  } catch (e) {
    await logRun('error', { unhandled_exception: 1 }, 'claim_lookup threw an unhandled exception: ' + String((e as Error)?.message || e).slice(0, 200) + ' - a supplier trying to claim their listing was blocked for an internal reason.');
    return J({ ok: false, error: 'error' }, 500);
  }
});
