// pending_digest - daily email to admins listing suppliers awaiting approval. Secret-guarded; queues a notification (drained by send_outbox).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function dt(s: unknown){ if(!s) return '-'; try { return new Date(String(s)).toLocaleDateString('en-GB',{ day:'2-digit', month:'short' }); } catch { return String(s); } }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'pending_digest');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const { data: rows } = await admin.from('leads')
      .select('id,company_name,emirate,sector,trade_license_no,license_expiry,registration_submitted_at,ai_review_notes')
      .or('claimed.eq.true,source.eq.self_registered,source.eq.email_inbound')
      .in('approval_status', ['pending','submitted'])
      .order('registration_submitted_at', { ascending: true, nullsFirst: false })
      .limit(100);
    const pending = rows || [];
    if (!pending.length) return J({ ok: true, pending: 0, sent: false, note: 'nothing to review' });
    const adminEmails = String((await sec('admin_emails')) || 'management@quotesdone.com').split(',').map(s=>s.trim()).filter(Boolean);
    const items = pending.slice(0, 40).map((l:any,i:number)=> `${i+1}. ${l.company_name||'(no name)'}${l.emirate?(' — '+l.emirate):''}${l.sector?(' · '+l.sector):''}${l.trade_license_no?(' · licence '+l.trade_license_no):''}${l.registration_submitted_at?(' · submitted '+dt(l.registration_submitted_at)):''}${l.ai_review_notes?('\n     AI: '+String(l.ai_review_notes).slice(0,160)):''}`).join('\n');
    const extra = pending.length > 40 ? `\n\n…and ${pending.length-40} more.` : '';
    const subject = `${pending.length} supplier${pending.length===1?'':'s'} awaiting approval — QuotesDone`;
    const bodyText = `Good morning. You have ${pending.length} supplier${pending.length===1?'':'s'} pending review on QuotesDone:\n\n${items}${extra}\n\nReview, approve or reject them in the OS console:\nhttps://quotesdone.com/os\n\n(You can approve several at once with the bulk action bar.)`;
    const notifs = adminEmails.map((to)=>({ type: 'pending_digest', to_email: to, to_role: 'admin', subject, body: bodyText }));
    const { error } = await admin.from('notifications').insert(notifs);
    if (error) return J({ ok:false, error: error.message }, 500);
    return J({ ok: true, pending: pending.length, sent: notifs.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
