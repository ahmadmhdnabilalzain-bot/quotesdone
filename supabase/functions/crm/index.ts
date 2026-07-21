// crm page server — serves the CRM SPA HTML from the pages table (slug='crm').
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
Deno.serve(async () => {
  const { data } = await admin.from('pages').select('html').eq('slug', 'crm').maybeSingle();
  const html = (data && data.html) ? data.html : '<!doctype html><meta charset="utf-8"><title>CRM</title><body>CRM page not found.</body>';
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=30' } });
});
