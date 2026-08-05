// attach_photos - persists a customer's REFERENCE photos into the inquiry package so matched suppliers
// receive them (anonymised) and can quote from them. Redact-only (no BOQ). Auth: customer JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const uid = (user.id || user.email).replace(/[^a-zA-Z0-9]/g, '').slice(0, 24) || 'anon';
    const body = await req.json().catch(() => ({}));
    // Accept either key. Every sibling on this path (drawing_boq, drawing_redact, customer_api's
    // analyze_drawing) reads `im.b64 || im.data`, and cad_convert emits `data` while the portal's
    // own drawing upload posts `b64`. This filtered on `data` alone, so a caller using the shape
    // the rest of the pipeline accepts would drop every photo and still return ok:true with an
    // empty paths array - the customer's reference photos would simply never reach the suppliers,
    // with nothing anywhere reporting a failure. No caller sends `b64` today; this is one word so
    // that none ever can.
    const images = (Array.isArray(body.images) ? body.images : [])
      .map((im: any) => (im && !im.data && im.b64) ? { ...im, data: im.b64 } : im)
      .filter((im: any) => im && im.data && im.mime).slice(0, 24);
    if (!images.length) return J({ ok: true, paths: [] });
    const secret = await sec('cred_fn_attach_photos');
    const prefix = `refphoto/${uid}/${Date.now()}`;
    // REDACTION PROVENANCE (5 Aug 2026). drawing_redact's recordRun already reads
    // `owner_customer_id` and `owner_email` off the request body - this caller simply never sent
    // them, so every drawing_redaction_runs row produced by the reference-photo path carried BOTH
    // as NULL. A redaction is a PRIVACY control, and its record could not be attributed to the
    // customer whose photos were redacted; `--purge` could only sweep such rows as unattributable,
    // and a single run could not clean up after itself at all.
    //
    // Resolved by EMAIL, not by user.id. customer_api's `me` creates the public.customers row with
    // a FRESH uuid rather than reusing the auth uid (§2.2 - the mechanism behind the 65 orphaned
    // customers), so user.id is NOT customers.id, and stamping it would record provenance against
    // a customer that does not exist - worse than recording none.
    const { data: cust } = await admin.from('customers').select('id').ilike('email', user.email).maybeSingle();
    let paths: string[] = [];
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, images, prefix, owner_customer_id: cust?.id || null, owner_email: user.email }) });
      const j = await r.json();
      if (j?.ok && Array.isArray(j.paths)) paths = j.paths.map((p: any) => String(p)).slice(0, 24);
    } catch (_e) { /* redaction best-effort */ }
    return J({ ok: true, paths });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
