import { siteCors } from '../_shared/site_origins.ts';
// role_guard v2 - one identity per role. Tells the client if an email/phone already belongs to the
// OTHER role, before any OTP code is sent.
//
// SECURITY HARDENING 19 Jul 2026 ---------------------------------------------------------------
// This endpoint is unauthenticated BY DESIGN and must stay that way: it runs before an OTP is
// sent, when the person has no account and there is nobody to authenticate. A secret gate would
// break the sign-up flow. But v1 was a free membership oracle - anyone could POST any email or
// phone number and learn whether it was registered on QuotesDone, which:
//   - lets a scraped mailing list be validated against our user base,
//   - tells a phisher which UAE companies are our suppliers ("we know you supply via QuotesDone"),
//   - is a personal-data disclosure under PDPL with no consent and no logging.
//
// Two changes, neither of which touches the sign-up UX:
//
// 1. STOP OVER-ANSWERING. v1 returned `belongsTo` ('supplier' | 'customer' | 'both' | null) on
//    every call - a direct membership answer. The front end never used it: CustomerPortal.tsx and
//    SupplierPortal.tsx read ONLY `conflict`. So `belongsTo` was disclosure for nothing and is now
//    removed. `conflict` is still returned because the flow genuinely needs it, but it is non-null
//    only in the true cross-role case, which is the minimum needed to show the message.
//
// 2. RATE LIMIT. Bulk validation of a list is the actual threat, not a single lookup. Capped per
//    identifier and per caller IP via the existing rl_check RPC. A blocked caller gets a neutral
//    response, never a different answer, so the limiter cannot itself be used as an oracle.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const T0 = Date.now();

async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'role_guard', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break sign-up */ }
}

async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // limiter unavailable must not block genuine sign-ups
}

Deno.serve(siteCors(observe('role_guard', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const b = await req.json().catch(() => ({} as any));
    const kind = b.user_kind === 'supplier' ? 'supplier' : 'customer';
    const idRaw = String(b.identifier || '').trim();
    if (!idRaw) return J({ ok: true, kind, conflict: null });

    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    // Per-IP cap is the anti-list-validation control; per-identifier cap stops hammering one target.
    const ipOk = await rl('role_guard_ip:' + ip, 40, 3600);
    const idOk = await rl('role_guard_id:' + idRaw.toLowerCase(), 10, 3600);
    if (!ipOk || !idOk) {
      await logRun('error', { rate_limited: 1, scope: !ipOk ? 'ip' : 'identifier' },
        'role_guard rate-limited a caller (' + (!ipOk ? 'per-IP cap' : 'per-identifier cap') + '). This endpoint is deliberately public for pre-OTP sign-up, so the cap is what stops it being used to validate a scraped email or phone list against our user base. A genuine person signing up never approaches this rate; sustained hits are worth investigating.');
      // Neutral answer - identical to "no conflict" so the limiter cannot be probed as an oracle.
      return J({ ok: true, kind, conflict: null });
    }

    // THE SAME ANSWER FOR EVERY IDENTIFIER (pre-launch security pass, 6 Oct 2026, M3). Even with
    // belongsTo gone, `conflict` still told an anonymous caller that an address or phone was registered
    // in the OTHER role, and the per-IP cap is beaten by spreading requests across addresses. The
    // cross-role refusal now happens in login_otp AFTER the code is verified (code role_conflict), where
    // only the mailbox owner can see it, so this endpoint looks nothing up and answers alike for every
    // identifier. It stays deployed, rate limited, so a portal page cached before this change still
    // gets a well-formed answer.
    return J({ ok: true, kind, conflict: null });
  } catch (e) {
    await logRun('error', { unhandled_exception: 1 }, 'role_guard threw an unhandled exception: ' + String((e as Error)?.message || e).slice(0, 200) + ' - the sign-up flow could not check for a cross-role conflict, so a person may be allowed to register in both roles.');
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
})));
