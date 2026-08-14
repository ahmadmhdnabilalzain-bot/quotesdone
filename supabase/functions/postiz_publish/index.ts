// postiz_publish v2 — the platform's own Postiz connector so agents publish to social autonomously.
// Keys stay server-side (app_secrets). Auth: __secret == inbound_secret.
// Actions:
//   test    -> GET /integrations (read-only; verifies key + lists channels)
//   upload  -> body {url}: fetch an image URL and upload it to Postiz's media store; returns {id, path}
//              (Postiz requires post images to be uploads.postiz.com objects, not arbitrary URLs).
//   post    -> body {channels:[names], text, title?, type?:'now'|'schedule'|'draft', when?:ISO,
//              image?:[{id,path}], image_url?:string}. If image_url is given (any public URL) it is
//              uploaded to Postiz first and attached automatically.
//   delete  -> body {id|ids[]}
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

const NEEDS_MEDIA = new Set(['instagram']);
async function base(): Promise<string> { return (await sec('postiz_api_url')) || 'https://api.postiz.com/public/v1'; }

// Upload an image (by URL) to Postiz; returns the Postiz media object {id, path, ...} or null.
async function uploadToPostiz(key: string, B: string, url: string): Promise<any> {
  try {
    const ir = await fetch(url); if (!ir.ok) return null;
    const blob = await ir.blob();
    const fd = new FormData();
    fd.append('file', blob, (url.split('/').pop() || 'image.png').split('?')[0]);
    const r = await fetch(B + '/upload', { method: 'POST', headers: { 'Authorization': key }, body: fd });
    const txt = await r.text(); let j: any; try { j = JSON.parse(txt); } catch (_e) { j = { raw: txt }; }
    if (!r.ok) return { error: j?.message || j?.error || txt, status: r.status };
    const obj = Array.isArray(j) ? j[0] : (j?.output || j?.data || j);
    return obj;
  } catch (e) { return { error: String((e as Error)?.message || e) }; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'postiz_publish');
  if (!__auth.ok) return J({ error: 'forbidden' }, 403);
  const key = await sec('postiz_api_key');
  if (!key) return J({ error: 'postiz_not_configured' }, 200);
  const B = await base();
  const H = { 'Authorization': key, 'Content-Type': 'application/json' };
  const started = new Date().toISOString();

  try {
    const action = String(body.action || 'post');

    if (action === 'test') {
      const r = await fetch(B + '/integrations', { headers: { 'Authorization': key } });
      const txt = await r.text(); let j: any; try { j = JSON.parse(txt); } catch (_e) { j = txt; }
      const list = Array.isArray(j) ? j.map((x: any) => ({ id: x.id, name: x.name, identifier: x.identifier, disabled: x.disabled })) : j;
      return J({ ok: r.ok, status: r.status, integrations: list });
    }

    if (action === 'upload') {
      if (!body.url) return J({ error: 'url required' }, 400);
      const obj = await uploadToPostiz(key, B, String(body.url));
      if (!obj || obj.error) return J({ ok: false, error: obj?.error || 'upload_failed', raw: obj }, 200);
      return J({ ok: true, image: { id: obj.id, path: obj.path || obj.url }, raw: obj });
    }

    if (action === 'post') {
      const text = String(body.text || '').trim();
      if (!text) return J({ error: 'empty_content' }, 400);
      const type = ['now', 'schedule', 'draft'].includes(String(body.type)) ? String(body.type) : 'now';
      const date = body.when ? new Date(body.when).toISOString() : new Date(Date.now() + 60000).toISOString();
      // Resolve the image: an already-Postiz image passes through; a plain image_url is uploaded first.
      let image: any[] = Array.isArray(body.image) ? body.image : [];
      if ((!image.length) && body.image_url) {
        // A published image has to have been LOOKED AT. The gate answers about the bytes that
        // are about to go out, not about the url, so a regenerated image is unreviewed by
        // construction. The digest is computed here from the same fetch the upload uses.
        const src = String(body.image_url);
        const subjectId = String(body.subject_id || src);
        let digest = '';
        try {
          const raw = new Uint8Array(await (await fetch(src)).arrayBuffer());
          const d = await crypto.subtle.digest('SHA-256', raw.slice().buffer as ArrayBuffer);
          digest = [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
        } catch (_e) { /* an unfetchable image is caught by the gate below as "no digest" */ }
        const { data: gate } = await admin.rpc('fn_artifact_publish_blocked',
          { p_subject_type: 'social_post', p_subject_id: subjectId, p_sha256: digest || null });
        if (!gate || (gate as Record<string, unknown>).blocked) {
          await admin.from('agent_runs').insert({ agent: 'postiz_publish', started_at: started,
            finished_at: new Date().toISOString(), status: 'error',
            counts: { blocked_by_artifact_review: 1 },
            note: 'refused to publish an image that has no passing artifact_review for these exact bytes' });
          return J({ error: 'artifact_review_required', gate, subject_id: subjectId, artifact_sha256: digest || null }, 409);
        }
        const obj = await uploadToPostiz(key, B, src);
        if (obj && !obj.error && obj.id) image = [{ id: obj.id, path: obj.path || obj.url }];
      }
      const wanted = (Array.isArray(body.channels) ? body.channels : []).map((c: any) => String(c).toLowerCase());
      const ir = await fetch(B + '/integrations', { headers: { 'Authorization': key } });
      const integ = await ir.json().catch(() => []);
      const live = Array.isArray(integ) ? integ.filter((x: any) => !x.disabled) : [];
      const findFor = (norm: string) => live.find((x: any) => { const id = String(x.identifier || ''); if (norm === 'x') return id === 'x' || id === 'twitter'; if (norm === 'linkedin') return id.startsWith('linkedin'); if (norm === 'instagram') return id.startsWith('instagram'); if (norm === 'facebook') return id === 'facebook'; return id === norm || id.startsWith(norm); });
      const posts: any[] = []; const skipped: string[] = [];
      for (const ch of wanted) {
        const norm = ch === 'twitter' ? 'x' : ch;
        const it = findFor(norm);
        if (!it) { skipped.push(ch + ' (not connected)'); continue; }
        const ident = String(it.identifier);
        const needsMedia = ident.startsWith('instagram') || NEEDS_MEDIA.has(norm);
        if (needsMedia && !image.length) { skipped.push(ident + ' (needs an image)'); continue; }
        const settings: any = { __type: ident };
        if (ident.startsWith('instagram')) settings.post_type = 'post';
        if (ident === 'x') settings.who_can_reply_post = 'everyone';
        posts.push({ integration: { id: it.id }, value: [{ content: text, image }], settings });
      }
      if (!posts.length) return J({ error: 'no_publishable_channels', skipped }, 200);
      const payload = { type, date, shortLink: false, tags: [], posts };
      const r = await fetch(B + '/posts', { method: 'POST', headers: H, body: JSON.stringify(payload) });
      const txt = await r.text(); let j: any; try { j = JSON.parse(txt); } catch (_e) { j = { raw: txt }; }
      await admin.from('agent_runs').insert({ agent: 'postiz_publish', started_at: started, finished_at: new Date().toISOString(), status: r.ok ? 'ok' : 'error', counts: { channels: posts.length, skipped: skipped.length, type, image: image.length }, note: r.ok ? null : String(txt).slice(0, 200) });
      if (!r.ok) return J({ ok: false, status: r.status, error: j?.message || j?.error || txt, skipped }, 200);
      const postId = j?.[0]?.postId || j?.postId || j?.id || (Array.isArray(j) ? j[0]?.id : null);
      return J({ ok: true, type, published_to: posts.length, post_id: postId, skipped, image: image.length, result: j });
    }

    if (action === 'delete') {
      const ids = Array.isArray(body.ids) ? body.ids : (body.id ? [body.id] : []);
      const out: any[] = [];
      for (const id of ids) { const r = await fetch(B + '/posts/' + id, { method: 'DELETE', headers: { 'Authorization': key } }); out.push({ id, status: r.status }); }
      return J({ ok: true, deleted: out });
    }

    return J({ error: 'unknown_action' }, 400);
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'postiz_publish', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: String(e).slice(0, 200) });
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
