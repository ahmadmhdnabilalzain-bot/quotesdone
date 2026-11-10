// extract_text - reads a PDF or image attachment and returns its text content (for the Secretary chat).
// Images -> vision; PDFs -> OpenRouter file-parser. Admin/secret only.
// Routed through ai_gateway (v3 multimodal + plugins passthrough) so the spend is logged and routed.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../_shared/admin_session.ts';
import { sanitizeOrMessage, SAFE_UPLOAD } from '../_shared/attachment.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An admin
// whose session has one factor gets the body naming the step instead of `true` (security audit 10 Nov 2026, item 1).
async function authed(req: Request, body: any): Promise<true | false | TwoStepBody> { if (body?.__secret && (await requireInternal(admin, body.__secret, 'extract_text')).ok) return true; const a = await adminCaller(admin, sec, req.headers.get('Authorization')); return a.kind === 'admin' ? true : a.kind === 'two_step_required' ? a.body : false; }
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
const PROMPT = 'Extract ALL readable text and content from this document faithfully, as clean plain text / markdown. Preserve tables (as markdown tables), headings, figures and key numbers. Do not summarise, do not add commentary — output ONLY the extracted content.';

Deno.serve(observe('extract_text', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    const ok = await authed(req, body);
    if (ok !== true) return J(ok || { error: 'forbidden' }, 403);
    const filename = String(body.filename||'document');
    const mime = String(body.mime||'application/octet-stream');
    let b64 = String(body.b64||''); if(!b64) return J({ error:'b64 required' }, 400);
    // AUDIT 9.1 (3 Aug 2026): this built a data URL from the CALLER'S declared mime and posted it
    // to the model. The bytes were never looked at, so a file claiming to be a PDF reached the
    // file-parser plugin as whatever it actually was. Sniff first, then build the URL from the
    // sniffed type.
    const __san = sanitizeOrMessage({ input: b64, declaredMime: mime, filename, allow: SAFE_UPLOAD });
    if (!__san.ok) return J(__san.body, __san.status);
    const __b64 = btoa(String.fromCharCode(...__san.result.bytes));
    const dataUrl = 'data:' + __san.result.mime + ';base64,' + __b64;
    const isImage = /^image\//.test(__san.result.mime);   // the sniffed type, not the claim
    const secret = await sec('cred_fn_ai'); if(!secret) return J({ error:'ai_unavailable' }, 500);
    let content: any; let plugins: any = undefined;
    if (isImage) content = [{ type:'text', text:PROMPT }, { type:'image_url', image_url:{ url:dataUrl } }];
    else { content = [{ type:'text', text:PROMPT }, { type:'file', file:{ filename, file_data:dataUrl } }]; plugins = [{ id:'file-parser', pdf:{ engine:'pdf-text' } }]; }
    let text=''; let last=''; let modelTruncated = false;
    try{
      // `max: 4000` removed 5 Aug 2026 against a document_extraction ceiling of 8000. This one was
      // self-defeating on its face: the PROMPT says "Extract ALL readable text and content from
      // this document faithfully... Do not summarise", and the caller then declared a result buffer
      // (text.slice(0, 16000) below, ~4,000 tokens) EXACTLY the size of the ceiling it imposed on
      // the model. Any document big enough to fill the buffer was cut mid-sentence and returned as
      // ok:true - the same shape as doc_extract and license_extract.
      const payload: any = { __secret: secret, fn: 'extract_text', input: [{ role:'user', content }] }; if(plugins) payload.plugins = plugins;
      const r = await fetch(GW, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify(payload) });
      const jd = await r.json();
      // Removing the ceiling alone would only MOVE the silent truncation from the model to the
      // buffer below, which is not closing the defect. ai_gateway reports both signals; use them.
      if (jd?.truncated === true || jd?.finish_reason === 'length') modelTruncated = true;
      const c = jd?.content; if(c && String(c).trim().length>5){ text = String(c).trim(); } else last = jd?.detail || jd?.error || jd?.why || 'empty:gateway';
    }catch(e){ last='exc:gateway:'+String((e as Error)?.message||e).slice(0,80); }
    // RULING 1177 (12 Oct 2026): the 'pdf-text' engine reads only a text layer, so a SCANNED PDF came back empty. It is
    // asked once more with the file itself and no text-only plugin, so the vision model reads the page.
    if(!text){
      try{
        const r = await fetch(GW, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'extract_text', input: [{ role:'user', content }] }), signal: AbortSignal.timeout(110_000) });
        const jd = await r.json();
        if (jd?.truncated === true || jd?.finish_reason === 'length') modelTruncated = true;
        const c = jd?.content; if(c && String(c).trim().length>5){ text = String(c).trim(); } else last = jd?.detail || jd?.error || jd?.why || last;
      }catch(e){ last='exc:gateway_retry:'+String((e as Error)?.message||e).slice(0,80); }
    }
    if(!text) return J({ ok:false, error:'extract_failed', detail:last }, 200);
    // The buffer stays - a caller asking for a document's text should not be handed an unbounded
    // string - but a truncated result is now LABELLED. "Extract ALL text" returning a silently
    // clipped document is a wrong answer wearing a right answer's clothes.
    const clipped = text.length > 16000;
    return J({ ok:true, text: text.slice(0, 16000), filename,
      truncated: clipped || modelTruncated,
      truncated_by: modelTruncated ? 'model_token_ceiling' : (clipped ? 'result_buffer_16000_chars' : null),
      full_length: text.length });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
}));
