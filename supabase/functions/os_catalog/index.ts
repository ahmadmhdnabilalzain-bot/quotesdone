// os_catalog — Phase 3 Category & Spec management backend.
// Admin-gated. Lets a non-developer edit intake questions and quote-gate specs, and
// test the gate live against a sample quote. Every mutation is audit-logged.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false; const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner', 'admin'].includes(String(data || '').toLowerCase())) return true; } catch (_e) { /* */ }
  try { const { data } = await admin.from('app_secrets').select('value').eq('key', 'admin_emails').maybeSingle(); const list = String((data as any)?.value || '').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) { /* */ }
  return false;
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return J({ error: 'unauthorized' }, 401);
    const { data: u, error: uerr } = await admin.auth.getUser(token);
    const email = u?.user?.email || '';
    if (uerr || !email) return J({ error: 'unauthorized' }, 401);
    if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);

    const b = await req.json().catch(() => ({} as any));
    const action = String(b?.action || '');

    if (action === 'list') {
      const { data, error } = await admin.rpc('fn_os_catalog_list');
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { categories: data || [] } });
    }
    if (action === 'get') {
      const { data, error } = await admin.rpc('fn_os_catalog_get', { p_category: String(b.category || '') });
      if (error) return J({ error: error.message }, 500);
      if (!data) return J({ error: 'category_not_found' }, 404);
      return J({ ok: true, data });
    }
    if (action === 'save_fields') {
      const { data, error } = await admin.rpc('fn_os_catalog_save_fields', { p_category: String(b.category || ''), p_fields: b.fields ?? [], p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'spec_upsert') {
      const { data, error } = await admin.rpc('fn_os_catalog_spec_upsert', { p_id: b.id ?? null, p_spec_group: String(b.spec_group || ''), p_aspect: String(b.aspect || ''), p_label: String(b.label || ''), p_regex: String(b.match_regex || ''), p_mandatory: !!b.mandatory, p_note: String(b.note || ''), p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'spec_delete') {
      const { data, error } = await admin.rpc('fn_os_catalog_spec_delete', { p_id: Number(b.id), p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'test_gate') {
      const { data, error } = await admin.rpc('fn_os_catalog_test_gate', { p_category: String(b.category || ''), p_sample: String(b.sample || '') });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
