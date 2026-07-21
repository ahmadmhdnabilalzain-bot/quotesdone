// extract_text - reads a PDF or image attachment and returns its text content (for the Secretary chat).
// Images -> vision; PDFs -> OpenRouter file-parser. Admin/secret only.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any){ if(body.__secret && body.__secret===(await sec('inbound_secret'))) return true; const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } }=await admin.auth.getUser(jwt); const allow=(await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
const PROMPT = 'Extract ALL readable text and content from this document faithfully, as clean plain text / markdown. Preserve tables (as markdown tables), headings, figures and key numbers. Do not summarise, do not add commentary — output ONLY the extracted content.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    if(!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    const filename = String(body.filename||'document');
    const mime = String(body.mime||'application/octet-stream');
    let b64 = String(body.b64||''); if(!b64) return J({ error:'b64 required' }, 400);
    const dataUrl = b64.startsWith('data:') ? b64 : ('data:'+mime+';base64,'+b64);
    const isImage = /image\//i.test(mime) || /\.(png|jpe?g|webp|gif|heic|heif)$/i.test(filename);
    const key = await sec('openrouter_api_key'); if(!key) return J({ error:'ai_unavailable' }, 500);
    let content: any; let plugins: any = undefined;
    if (isImage) content = [{ type:'text', text:PROMPT }, { type:'image_url', image_url:{ url:dataUrl } }];
    else { content = [{ type:'text', text:PROMPT }, { type:'file', file:{ filename, file_data:dataUrl } }]; plugins = [{ id:'file-parser', pdf:{ engine:'pdf-text' } }]; }
    let text=''; let last='';
    for (const model of ['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8']){
      try{
        const payload: any = { model, max_tokens: 4000, messages: [{ role:'user', content }] }; if(plugins) payload.plugins = plugins;
        const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method:'POST', headers:{ 'Authorization':'Bearer '+key, 'Content-Type':'application/json' }, body: JSON.stringify(payload) });
        const jd = await r.json(); const c = jd?.choices?.[0]?.message?.content; if(c && String(c).trim().length>5){ text = String(c).trim(); break; } last = jd?.error?.message || ('empty:'+model);
      }catch(e){ last='exc:'+model+':'+String((e as Error)?.message||e).slice(0,80); }
    }
    if(!text) return J({ ok:false, error:'extract_failed', detail:last }, 200);
    return J({ ok:true, text: text.slice(0, 16000), filename });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
