// sign_upload — returns a direct-to-storage signed upload URL so the browser can PUT large files
// (drawings, catalogues, company profiles) straight into private storage, bypassing the base64-
// through-function path. Auth: any signed-in user (JWT). Bucket is allowlisted; path is scoped to
// the user's id. Used by the customer app (drawings) and the supplier portal (catalogues/profiles).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
function safeName(n: string){ return String(n||'file').replace(/[^\w.\-]+/g,'_').slice(0,120); }
const BUCKETS: Record<string,string> = { drawing: 'drawing-files', 'drawing-files': 'drawing-files', supplier: 'supplier-docs', 'supplier-docs': 'supplier-docs' };
const PREFIX: Record<string,string> = { 'drawing-files': 'drawings', 'supplier-docs': 'uploads' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error:'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(()=>({} as any));
    const bucket = BUCKETS[String(body.bucket||'drawing-files')] || 'drawing-files';
    // scope path by a stable per-user key (email localpart hashed enough for a folder)
    const uid = email.replace(/[^a-z0-9]+/g,'_').slice(0,40);
    const name = safeName(body.file_name || 'upload');
    const path = `${PREFIX[bucket]}/${uid}/${Date.now()}_${name}`;
    const { data, error } = await admin.storage.from(bucket).createSignedUploadUrl(path);
    if (error) return J({ error: error.message }, 500);
    return J({ ok: true, bucket, path, token: (data as any).token, signed_url: (data as any).signedUrl });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
