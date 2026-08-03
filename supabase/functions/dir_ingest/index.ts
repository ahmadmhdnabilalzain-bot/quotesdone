import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });

// SECURITY HARDENING 19 Jul 2026 ---------------------------------------------------------------
// This used to accept EITHER inbound_secret OR a shared 'test_token' as full authority:
//     return (body.__secret && body.__secret === sec.inbound_secret)
//         || (body.__test   && body.__test   === sec.test_token);
// A QA/test credential should never carry the same power as the production secret - this endpoint
// bulk-upserts into yello_staging, the supplier directory pipeline that ultimately feeds the leads
// table, so anyone holding the test token could inject or overwrite directory records at scale.
//
// app_secrets has no 'test_token' row today, so the branch was already inert and removing it breaks
// nothing. It is deleted rather than left dormant so that re-adding a test_token row for some
// unrelated test harness cannot silently re-grant production write access here.
// UPDATE 3 Aug 2026: the same dormant __test branch has now been removed from yello_scrape and
// profile_ai on this same reasoning, so no __test branch survives anywhere.
// AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
// per-context credential and the legacy shared secret, and records which one called. The
// fail-closed property established above is preserved and strengthened: requireInternal refuses
// an absent credential AND refuses when the verifier itself cannot be reached, rather than
// comparing against a value it failed to read.
async function auth(body: any): Promise<boolean> {
  return (await requireInternal(admin, body?.__secret, 'dir_ingest')).ok;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*' } });
  const body = await req.json().catch(() => ({}));
  if (!(await auth(body))) return J({ error: 'unauthorized' }, 401);

  try {
    if (body.action === 'stats') {
      const { data: rows } = await admin.from('yello_staging').select('stage,sector,email');
      const by: Record<string,number> = {}; const bySector: Record<string,number> = {}; let withEmail = 0;
      for (const r of (rows||[])) { by[r.stage]=(by[r.stage]||0)+1; if (r.email) { withEmail++; bySector[r.sector||'?']=(bySector[r.sector||'?']||0)+1; } }
      return J({ ok:true, total:(rows||[]).length, with_email: withEmail, by_stage: by, by_sector: bySector });
    }

    if (body.action === 'ingest') {
      const rows = Array.isArray(body.rows) ? body.rows : [];
      if (!rows.length) return J({ error:'no rows' }, 400);
      const clean = rows.filter((r:any)=>r && r.company_id).map((r:any)=>({
        company_id: String(r.company_id).slice(0,120),
        name: r.name ? String(r.name).slice(0,200) : null,
        slug: r.slug ? String(r.slug).slice(0,160) : null,
        city: r.city ? String(r.city).slice(0,60) : null,
        src_category: r.src_category ? String(r.src_category).slice(0,80) : null,
        categories: Array.isArray(r.categories) ? r.categories.slice(0,12) : null,
        website: r.website ? String(r.website).slice(0,200) : null,
        phone: r.phone ? String(r.phone).slice(0,40) : null,
        whatsapp: r.whatsapp ? String(r.whatsapp).slice(0,40) : null,
        email: r.email ? String(r.email).toLowerCase().slice(0,120) : null,
        email_source: r.email ? 'directory' : null,
        sector: r.sector ? String(r.sector).slice(0,40) : null,
        stage: r.email ? 'emailed' : 'profiled',
        updated_at: new Date().toISOString()
      }));
      // upsert in chunks
      let up = 0;
      for (let i=0;i<clean.length;i+=200) {
        const ch = clean.slice(i,i+200);
        const { error, count } = await admin.from('yello_staging').upsert(ch, { onConflict: 'company_id', count: 'exact' });
        if (error) return J({ error: error.message, at:i }, 200);
        up += ch.length;
      }
      return J({ ok:true, received: rows.length, upserted: up });
    }

    return J({ error:'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 200); }
});
