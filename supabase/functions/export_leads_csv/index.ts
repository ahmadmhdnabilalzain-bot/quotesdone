import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

const COLS = ['id','company_name','sector','sub_type','emirate','city','street','website','domain','maps_website','maps_url','place_id','phone','phone_e164','email','email_verified','instagram','facebook','whatsapp','rating','reviews','website_status','permanently_closed','description','services','products','certifications','founded_year','company_size','company_type','business_role','capability_summary'];

function csvCell(v: unknown): string {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return '"' + s.replace(/"/g, '""') + '"';
}

Deno.serve(async (req) => {
  const body = await req.json().catch(() => ({}));
  // Auth: admin JWT (email in admin_emails) OR inbound_secret. Full-PII export must never be behind a shared test token.
  let authed = false;
  if (body?.__secret && (await requireInternal(admin, body.__secret, 'export_leads_csv')).ok) authed = true;
  if (!authed) {
    const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
    if (jwt) {
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails')||'').split(',').map((s)=>s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) authed = true;
    }
  }
  if (!authed) return new Response('forbidden', { status: 403 });

  const page = 1000;
  let from = 0;
  const lines: string[] = [COLS.join(',')];
  for (;;) {
    const { data, error } = await admin.from('leads').select(COLS.join(',')).order('id', { ascending: true }).range(from, from + page - 1);
    if (error) return new Response('error: ' + error.message, { status: 500 });
    if (!data || data.length === 0) break;
    // via unknown: with a runtime-built select list PostgREST types each row as GenericStringError,
    // which does not overlap Record<string, unknown>, so the direct assertion is rejected (TS2352).
    for (const row of data) lines.push(COLS.map((c) => csvCell((row as unknown as Record<string, unknown>)[c])).join(','));
    if (data.length < page) break;
    from += page;
  }
  return new Response(lines.join('\n'), { headers: { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': 'attachment; filename="quotesdone_leads.csv"' } });
});