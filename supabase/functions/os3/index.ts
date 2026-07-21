// os3 — page-server for the QuotesDone OS console. Reads pages.slug='os3'.
// Restored 2026-07-19: the site_deploy MAIN map fetches /functions/v1/os3, and this
// function was missing, so a deploy would ship a 404 body as the console. Mirrors `app`.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
Deno.serve(async () => {
  const { data } = await admin.from('pages').select('html').eq('slug', 'os3').maybeSingle();
  return new Response(data?.html || 'Not found', { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
});