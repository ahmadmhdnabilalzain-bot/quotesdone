import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const { data: sec } = await admin.from('app_secrets').select('value').eq('key','inbound_secret').maybeSingle();
    if (!sec?.value || body.__secret !== sec.value) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || '');
    if (action === 'list') {
      const after = Number(body.after || 0);
      const { data, error } = await admin.from('leads')
        .select('id,company_name,website,domain')
        .or('email.is.null,email.eq.')
        .not('website','is',null)
        .gt('id', after)
        .order('id', { ascending: true })
        .limit(1000);
      if (error) return J({ error: error.message }, 500);
      return J({ rows: data || [] });
    }
    if (action === 'apply') {
      const rows = Array.isArray(body.rows) ? body.rows : [];
      const src = String(body.source || 'web_crawl');
      let updated = 0;
      for (const r of rows) {
        if (!r?.id || !r?.email) continue;
        const { error } = await admin.from('leads')
          .update({ email: String(r.email).toLowerCase(), email_domain: r.domain ?? null, email_verified: !!r.mx, enrich_source: src })
          .eq('id', r.id).or('email.is.null,email.eq.');
        if (!error) updated++;
      }
      return J({ ok: true, updated });
    }
    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
