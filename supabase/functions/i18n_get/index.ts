import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string | undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req) => {
  const b = await req.json().catch(() => ({} as any));
  const __exp = await sec('inbound_secret');
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, b?.__secret, 'i18n_get');
  if (!__auth.ok) return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
  let q = admin.from('qd_i18n').select('source, slug, title, html, status');
  if (b.source) q = q.eq('source', b.source);
  if (b.slug) q = q.eq('slug', b.slug);
  const { data } = await q;
  return new Response(JSON.stringify({ ok: true, rows: data || [] }), { headers: { 'Content-Type': 'application/json' } });
});