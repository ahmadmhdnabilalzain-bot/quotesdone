// alert_founder v2 - logs a founder alert and pushes it via WhatsApp + branded email ONLY when it is actionable.
// Non-actionable / 'all good' alerts (level info/ok/healthy) are logged but NOT emailed, so the founder only
// hears about things that need attention. Pass force:true to always notify. Secret-guarded (inbound_secret).
// Body: { event, detail?, level?, force?, dedupe_key? }
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const ACTIONABLE = new Set(['warn','warning','critical','error','high','urgent','action','danger','fail','failed','alert','escalation']);
function wrapInternal(subject: string, bodyText: string, logo: string) {
  const logoTag = logo ? `<img src="${logo}" width="34" height="34" alt="QuotesDone" style="border-radius:8px;display:block"/>` : '';
  const esc = (s: string) => (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const bodyHtml = esc(bodyText).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:#0d9488">$1</a>').replace(/\n/g,'<br>');
  return `<!doctype html><html><body style="margin:0;background:#f6f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2937"><div style="max-width:600px;margin:0 auto;padding:24px"><div style="background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:28px"><div style="display:flex;align-items:center;gap:10px;margin-bottom:6px">${logoTag}<div style="font-weight:800;font-size:18px;color:#0d9488">Quotes<span style="color:#111827">Done</span></div><div style="margin-left:auto;font-size:11px;font-weight:700;color:#b91c1c;background:#fef2f2;border:1px solid #fecaca;border-radius:999px;padding:3px 10px">ACTION NEEDED</div></div><h2 style="margin:14px 0 12px;font-size:19px;line-height:1.3;color:#0f172a">${esc(subject)}</h2><div style="font-size:15px;line-height:1.6;color:#1f2937">${bodyHtml}</div><div style="margin-top:22px;padding-top:14px;border-top:1px solid #eef0f2;font-size:13px;color:#6b7280">Open the OS to act: <a href="https://quotesdone.com/os" style="color:#0d9488">quotesdone.com/os</a></div></div><div style="text-align:center;color:#9ca3af;font-size:12px;margin-top:14px">QuotesDone OS &middot; founder alert &middot; Dubai, UAE</div></div></body></html>`;
}
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error:'forbidden' }, 403);
    const event = String(body.event||'').slice(0,140); if(!event) return J({ error:'event required' }, 400);
    const detail = String(body.detail||'').slice(0,1000);
    const level = String(body.level||'info').toLowerCase();
    const force = body.force === true;
    await admin.from('founder_alerts').insert({ level, event, detail, channel:'pending' });
    const shouldNotify = force || ACTIONABLE.has(level);
    if (!shouldNotify) {
      await admin.from('founder_alerts').update({ channel: 'logged' }).eq('event', event).order('created_at',{ascending:false}).limit(1);
      return J({ ok:true, notified:false, logged:true, reason:'non-actionable level suppressed (no email sent)' });
    }
    // De-dupe: if the same event was emailed in the last 6h, skip a repeat email (still logged above).
    if (body.dedupe_key || event) {
      const key = String(body.dedupe_key || event);
      const since = new Date(Date.now() - 6*3600e3).toISOString();
      const { count } = await admin.from('notifications').select('id', { count:'exact', head:true }).eq('type','founder_alert').ilike('subject', '%'+key.slice(0,60)+'%').gte('created_at', since).eq('status','sent');
      if ((count||0) > 0) { await admin.from('founder_alerts').update({ channel:'deduped' }).eq('event',event).order('created_at',{ascending:false}).limit(1); return J({ ok:true, notified:false, deduped:true }); }
    }
    const msg = `[${level.toUpperCase()}] ${event}${detail? '\n\n'+detail : ''}`;
    let wa=false, email=false;
    const phone = await sec('admin_mfa_phone'); const inbound = await sec('inbound_secret');
    if (phone && ['critical','urgent','high','danger'].includes(level)) {
      const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send_whatsapp`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: inbound, to: phone, body: 'QuotesDone ['+level+']: '+event+(detail?' — '+detail:'') }) });
      const jd = await r.json().catch(()=>({})); wa = !!jd?.ok;
    }
    const admins = (await sec('admin_emails')||'').split(/[,;\s]+/).filter(Boolean);
    if (admins[0]) { const logo=(await sec('email_logo_url'))||''; await admin.from('notifications').insert({ type:'founder_alert', to_email: admins[0], to_role:'founder', subject:`[Action needed] ${event}`, body: msg, html: wrapInternal(event, detail || event, logo), status:'queued', channel:'email' }); email=true; }
    await admin.from('founder_alerts').update({ channel: wa?'whatsapp':(email?'email':'none') }).eq('event',event).order('created_at',{ascending:false}).limit(1);
    return J({ ok:true, whatsapp:wa, email, notified:true });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
