// os2 — page-server for the legacy /os2 route (redirect stub → /os3). Reads pages.slug='os2'.
// Restored 2026-07-19 alongside os3 so site_deploy's MAIN fetch resolves instead of shipping a 404 body. Mirrors `app`.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
Deno.serve(async () => {
  const { data } = await admin.from('pages').select('html').eq('slug', 'os2').maybeSingle();
  return new Response(data?.html || 'Not found', { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
});