// alert_founder v3 (6 Sep 2026) - the HTTP door to fn_notify_founder, nothing more.
//
// v2 decided for itself whether to email the founder (an ACTIONABLE level set, a 6h/24h dedupe, a direct
// Twilio send) and every DB routine that called it reached his inbox with a department's work. The decision
// now lives in ONE place, public.founder_mail_policy, and fn_notify_founder applies it: an allowed kind is
// queued for send_outbox (and WhatsApp for severe levels); anything else opens ONE org_task for the kind's
// owner role and never emails him. A caller that names no kind is routed, never emailed.
// Body: { event, detail?, level?, kind?, dedupe_key?, force? }   Secret-guarded (fn_internal_auth).
//   kind        founder_mail_policy.kind (e.g. platform_down, ai_credit_low, pdpl_request)
//   dedupe_key  at most one delivery per key per 24h for an ALLOWED kind (kept from v2)
//   force       a non-actionable level (info/ok/healthy) is only logged unless force:true
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const ACTIONABLE = new Set(['warn','warning','critical','error','high','urgent','action','danger','fail','failed','alert','escalation']);
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate asks fn_internal_auth, which accepts both the per-context
    // credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'alert_founder');
    if (!__auth.ok) return J({ error:'forbidden' }, 403);
    const event = String(body.event||'').slice(0,140); if(!event) return J({ error:'event required' }, 400);
    const detail = String(body.detail||'').slice(0,1000);
    const level = String(body.level||'info').toLowerCase();
    const kind = body.kind ? String(body.kind).slice(0, 80) : null;
    const dedupeKey = body.dedupe_key ? String(body.dedupe_key).slice(0, 200) : null;
    if (!(body.force === true || ACTIONABLE.has(level))) {
      await admin.from('founder_alerts').insert({ level, event, detail, channel:'logged', dedupe_key: dedupeKey });
      return J({ ok:true, notified:false, logged:true, reason:'non-actionable level suppressed (no email sent)' });
    }
    const { data, error } = await admin.rpc('fn_notify_founder', {
      p_event: event, p_detail: detail, p_level: level, p_kind: kind, p_dedupe_key: dedupeKey, p_owner_agent: null });
    if (error) return J({ error: error.message }, 500);
    const r = (data || {}) as Record<string, unknown>;
    return J({ ok:true, notified: r.emailed === true, mode: r.mode, kind: r.kind ?? kind, task_id: r.task_id ?? null,
               deduped: r.deduped === true, email: r.emailed === true });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
