// postiz_publish v1 — the platform's own Postiz connector so agents publish to social autonomously.
// Keys stay server-side (app_secrets). Auth: __secret == inbound_secret.
// Actions:
//   test  -> GET /public/v1/integrations (read-only; verifies key + lists channels)
//   post  -> body {channels:[names], text, title?, type?:'now'|'schedule'|'draft', when?:ISO, image?:[{id,path}]}
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

// which social channels need media (won't accept text-only)
const NEEDS_MEDIA = new Set(['instagram']);
const TYPE_MAP: Record<string, string> = { x: 'x', twitter: 'x', linkedin: 'linkedin', facebook: 'facebook', instagram: 'instagram' };

async function base(): Promise<string> { return (await sec('postiz_api_url')) || 'https://api.postiz.com/public/v1'; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
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

    if (action === 'post') {
      const text = String(body.text || '').trim();
      if (!text) return J({ error: 'empty_content' }, 400);
      const type = ['now', 'schedule', 'draft'].includes(String(body.type)) ? String(body.type) : 'now';
      const date = body.when ? new Date(body.when).toISOString() : new Date(Date.now() + 60000).toISOString();
      const image = Array.isArray(body.image) ? body.image : [];
      const wanted = (Array.isArray(body.channels) ? body.channels : []).map((c: any) => String(c).toLowerCase());
      // resolve channels against the LIVE integration list so __type matches the real identifier
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
      await admin.from('agent_runs').insert({ agent: 'postiz_publish', started_at: started, finished_at: new Date().toISOString(), status: r.ok ? 'ok' : 'error', counts: { channels: posts.length, skipped: skipped.length, type }, note: r.ok ? null : String(txt).slice(0, 200) });
      if (!r.ok) return J({ ok: false, status: r.status, error: j?.message || j?.error || txt, skipped }, 200);
      const postId = j?.[0]?.postId || j?.postId || j?.id || (Array.isArray(j) ? j[0]?.id : null);
      return J({ ok: true, type, published_to: posts.length, post_id: postId, skipped, result: j });
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
