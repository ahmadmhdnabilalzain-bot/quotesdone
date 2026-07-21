// licence_reminder - finds active suppliers whose UAE trade licence expires within N days (or recently expired)
// and queues a branded renewal-request email asking them to REPLY with the new licence. The reply lands at
// docs@mail.quotesdone.com and is auto-extracted/applied by resend_inbound. De-duped so it sends once per cycle.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
function parseDate(v: unknown): Date | null { if(!v) return null; const d=new Date(String(v)); return isNaN(d.getTime())?null:d; }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const windowDays = Math.max(1, Math.min(60, Number(body.days) || 7));
    const reDays = Math.max(3, Math.min(30, Number(body.resend_after_days) || 10));
    const now = Date.now();
    const upper = new Date(now + windowDays*864e5).toISOString();
    const lower = new Date(now - 30*864e5).toISOString(); // also chase up to 30 days expired
    // Only real onboarded suppliers: approved + claimed + not banned + has a licence date.
    const { data: leads } = await admin.from('leads')
      .select('id,company_name,email,claimed_by,license_expiry,trade_license_no,approval_status,banned')
      .eq('approval_status','approved').eq('claimed',true)
      .not('license_expiry','is',null)
      .lte('license_expiry', upper).gte('license_expiry', lower)
      .limit(500);
    let queued = 0, skipped = 0; const sample: string[] = [];
    for (const l of (leads||[])) {
      if (l.banned === true) { skipped++; continue; }
      const to = String(l.claimed_by || l.email || '').trim();
      if (!to || to.indexOf('@') < 0) { skipped++; continue; }
      // de-dupe: already reminded this cycle?
      const { data: recent } = await admin.from('notifications').select('id').eq('type','licence_renewal_reminder').eq('lead_id', l.id).gte('created_at', new Date(now - reDays*864e5).toISOString()).limit(1);
      if (recent && recent.length) { skipped++; continue; }
      const exp = parseDate(l.license_expiry); if(!exp) { skipped++; continue; }
      const days = Math.round((exp.getTime() - now)/864e5);
      const co = String(l.company_name || 'there');
      const licLine = l.trade_license_no ? (' (licence no. ' + l.trade_license_no + ')') : '';
      const when = days < 0 ? ('expired on ' + l.license_expiry) : (days === 0 ? 'expires today' : ('expires on ' + l.license_expiry + ' (in ' + days + ' day' + (days===1?'':'s') + ')'));
      const subject = days < 0 ? ('Action needed: your trade licence has expired — ' + co) : ('Reminder: your trade licence ' + (days<=1?'expires very soon':('expires in ' + days + ' days')) + ' — ' + co);
      const bodyTxt = 'Dear ' + co + ',\n\nOur records show your UAE trade licence' + licLine + ' ' + when + '. To keep your QuotesDone supplier profile active and continue receiving customer job requests, please send us your renewed trade licence.\n\nHow: simply REPLY to this email with the renewed trade licence attached (PDF or a clear photo). Our system will read it and update your account automatically — you do not need to do anything else.\n\nIf you have already renewed, please reply with the latest copy so our records stay current. Thank you for being part of QuotesDone.';
      const { error } = await admin.from('notifications').insert({ type:'licence_renewal_reminder', to_email: to, to_role:'supplier', lead_id: l.id, channel:'email', subject, body: bodyTxt, status:'queued' });
      if (!error) { queued++; if (sample.length < 10) sample.push(co + ' (' + days + 'd) -> ' + to); } else skipped++;
    }
    return J({ ok: true, candidates: (leads||[]).length, queued, skipped, window_days: windowDays, sample });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
