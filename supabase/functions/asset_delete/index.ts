// asset_delete — secret-gated removal of asset paths from an allow-listed bucket (test/demo cleanup).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
const ALLOW = ['quote-files','supplier-docs','drawing-files','agent-docs','brand'];
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(() => ({} as any));
    if (b.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const bucket = String(b.bucket || '');
    if (!ALLOW.includes(bucket)) return J({ error: 'bucket_not_allowed' }, 400);
    let paths: string[] = Array.isArray(b.paths) ? b.paths.map((p: any) => String(p)) : [];
    // optional prefix mode: list everything under a prefix and delete it
    if (b.prefix) {
      const pfx = String(b.prefix).replace(/\/$/, '');
      const { data } = await admin.storage.from(bucket).list(pfx, { limit: 1000 });
      for (const f of (data || [])) paths.push(pfx + '/' + f.name);
    }
    paths = [...new Set(paths)].filter(Boolean);
    if (!paths.length) return J({ error: 'no paths' }, 400);
    const { data, error } = await admin.storage.from(bucket).remove(paths);
    if (error) return J({ error: error.message }, 500);
    return J({ ok: true, removed: (data || []).length, paths });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
