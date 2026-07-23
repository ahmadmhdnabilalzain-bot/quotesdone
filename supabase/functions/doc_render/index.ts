// doc_render v9 - branded document generator. Opus writes ONLY the body (in the requested language); this wraps it in
// letterhead HTML (kept for on-screen view) AND renders a native branded PDF via pdf_native (pdf-lib, no CloudConvert).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, OPUS_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const llm = makeLlm(OPUS_FIRST, { max: 9000, temperature: 0.3 });
const URL_ = Deno.env.get('SUPABASE_URL')!;
const ASSET = URL_ + '/storage/v1/object/public/brand';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const CO = { name:'QuotesDone Technologies', licence:'DET E-Trader Licence No. 1633275', city:'Dubai, United Arab Emirates', email:'management@quotesdone.com', phone:'+971 50 931 9355', web:'quotesdone.com', signer:'Ahmad Alzain', title:'Founder & Managing Director' };
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any){ if(body.__secret && body.__secret===(await sec('inbound_secret'))) return true; const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } }=await admin.auth.getUser(jwt); const allow=(await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
function stripFences(s: string){ let t=String(s||'').trim(); const m=t.match(/```(?:html)?\s*([\s\S]*?)```/i); if(m) t=m[1].trim(); return t; }
function esc(s: string){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function dir(s:string){ return /[؀-ۿ]/.test(s) ? 'rtl' : 'ltr'; }

const STAMP = `<svg class=\"stamp\" width=\"152\" height=\"152\" viewBox=\"0 0 152 152\" xmlns=\"http://www.w3.org/2000/svg\"><defs><path id=\"qdtop\" d=\"M 16,76 A 60,60 0 0 1 136,76\" fill=\"none\"/></defs><g fill=\"none\" stroke=\"#0b5c54\" stroke-width=\"2.2\"><circle cx=\"76\" cy=\"76\" r=\"72\"/><circle cx=\"76\" cy=\"76\" r=\"56\"/></g><g fill=\"#0b5c54\" font-family=\"Arial,Helvetica,sans-serif\"><text font-size=\"10.5\" font-weight=\"700\" letter-spacing=\"0.7\"><textPath href=\"#qdtop\" startOffset=\"50%\" text-anchor=\"middle\">QUOTESDONE TECHNOLOGIES</textPath></text><text x=\"76\" y=\"63\" text-anchor=\"middle\" font-size=\"18\" font-weight=\"800\">QuotesDone</text><text x=\"76\" y=\"75\" text-anchor=\"middle\" font-size=\"7.5\" letter-spacing=\"2.5\" font-weight=\"600\">DUBAI · UAE</text><line x1=\"50\" y1=\"82\" x2=\"102\" y2=\"82\" stroke=\"#0b5c54\" stroke-width=\"0.9\"/><text x=\"76\" y=\"95\" text-anchor=\"middle\" font-size=\"9\" font-weight=\"700\" letter-spacing=\"0.4\">LICENCE 1633275</text><text x=\"76\" y=\"104\" text-anchor=\"middle\" font-size=\"6\" letter-spacing=\"1.5\" font-weight=\"600\">DET E-TRADER</text></g></svg>`;

function wrap(title: string, bodyHtml: string, rtl: boolean){
  const head = `<link rel=\"icon\" href=\"${ASSET}/favicon-32.png\">`;
  const css = `*{box-sizing:border-box}html,body{margin:0}body{font-family:Inter,-apple-system,Segoe UI,Arial,sans-serif;color:#15181d;font-size:13px;line-height:1.65;padding:0 0 90px}\n.page{max-width:780px;margin:0 auto;padding:32px 40px 0}\n.lh{display:flex;align-items:center;justify-content:space-between;gap:20px;border-bottom:3px solid #14B8A6;padding-bottom:14px}\n.lh img{height:40px;width:auto}\n.lh-co{text-align:right;font-size:11.5px;color:#475569;line-height:1.5}\n.lh-co .nm{font-size:14px;font-weight:800;color:#0C2330;letter-spacing:.2px}\n.doc-title{margin:26px 0 4px;font-size:21px;font-weight:800;color:#0C2330}\n.doc-meta{color:#64748b;font-size:11.5px;margin-bottom:14px}\nh2{font-size:15px;color:#0C2330;margin:22px 0 7px;border-bottom:1px solid #e8edf2;padding-bottom:4px}\nh3{font-size:13.5px;color:#0C2330;margin:16px 0 5px}\np{margin:0 0 10px}ul,ol{margin:0 0 10px;padding-left:20px}li{margin:3px 0}\ntable{width:100%;border-collapse:collapse;font-size:12.5px;margin:8px 0 14px}\nth,td{border:1px solid #e2e8f0;padding:7px 9px;text-align:left;vertical-align:top}th{background:#f1f5f9;color:#0C2330;font-weight:700}\n.sign{display:flex;justify-content:space-between;align-items:flex-end;gap:30px;margin:42px 0 10px;page-break-inside:avoid}\n.sign-l{margin-left:120px}\n.sign .lbl{font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.06em;margin-bottom:2px}\n.sig-img{height:60px;width:auto;display:block;margin:0 0 2px}\n.sig-rule{width:230px;border-bottom:1px solid #334155;margin:2px 0 6px}\n.sig-nm{font-weight:700;color:#0C2330}.sig-tt{font-size:11.5px;color:#475569}.sig-co{font-size:11.5px;color:#475569}\n.stamp{opacity:.85;transform:rotate(-8deg)}\n.ft{position:fixed;left:0;right:0;bottom:0;border-top:1px solid #e2e8f0;background:#fff;color:#7a8aa0;font-size:10px;text-align:center;padding:8px 40px;line-height:1.5}\nbody[dir=rtl] th,body[dir=rtl] td{text-align:right}\n@media print{.ft{position:fixed}}`;
  const header = `<div class=\"lh\" dir=\"ltr\"><img src=\"${ASSET}/qd_lockup_dark.png\" alt=\"QuotesDone\"><div class=\"lh-co\"><div class=\"nm\">${CO.name}</div><div>${CO.licence}</div><div>${CO.city}</div><div>${CO.email} · ${CO.phone}</div></div></div>`;
  const dateStr = new Date().toLocaleDateString('en-GB',{day:'2-digit',month:'long',year:'numeric'});
  const signBlock = `<div class=\"sign\" dir=\"ltr\"><div class=\"sign-l\"><div class=\"lbl\">Authorised signatory</div><img class=\"sig-img\" src=\"${ASSET}/qd_signature.png\" alt=\"Signature\"><div class=\"sig-rule\"></div><div class=\"sig-nm\">${esc(CO.signer)}</div><div class=\"sig-tt\">${esc(CO.title)}</div><div class=\"sig-co\">${CO.name}</div></div><div class=\"sign-r\">${STAMP}</div></div>`;
  const footer = `<div class=\"ft\">${CO.name} · ${CO.licence} · ${CO.city}<br>${CO.email} · ${CO.phone} · ${CO.web}</div>`;
  return `<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>${esc(title)}</title>${head}<style>${css}</style></head><body${rtl?' dir=\"rtl\"':''}><div class=\"page\">${header}<div class=\"doc-title\">${esc(title)}</div><div class=\"doc-meta\">${CO.city} · ${dateStr}</div>${bodyHtml}${signBlock}</div>${footer}</body></html>`;
}

const SYS = `You are the document writer for QuotesDone, a UAE B2B quotation marketplace. Produce ONLY the inner BODY of a document from the brief — the sections, paragraphs, tables and lists.\n\nHARD REQUIREMENTS:\n- Output ONLY an HTML FRAGMENT (the body content). DO NOT output <!doctype>, <html>, <head>, <style>, a logo, a letterhead/header, a signature, a stamp, or a footer — ALL of those are added automatically around your content. Do not repeat the document title as a heading (it is added automatically).\n- A signature block (authorised signatory name, title, company and the company stamp) is appended automatically AFTER your content. Therefore DO NOT write any closing signature, do NOT type a signatory name or job title, do NOT write '[Authorised Signatory]', and do NOT add the company name as a sign-off. Do NOT reference or mention 'the stamp below'. For a letter you MAY end with a simple salutation line.\n- Use semantic tags: <h2> for section headings, <h3> for sub-sections, <p> for paragraphs, <ul>/<ol> for lists, and <table><thead><tbody> for any tabular/figures data. No inline styles, no markdown, no code fences.\n- FOLLOW THE LAYOUT INSTRUCTIONS EXACTLY (sections, tables, columns, order). Write in clear, professional business language.\n- Use ONLY the data provided. Never invent figures, names, or facts; where a value is unknown use a clear [placeholder].`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    if(!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    const lang = ['en','ar','bi'].includes(String(body.lang)) ? String(body.lang) : 'en';
    const title = String(body.title||'Document').slice(0,160);
    const layout = String(body.layout||body.brief||body.instruction||'').slice(0,4000);
    if(!layout) return J({ error:'layout/brief required' }, 400);
    const data = body.data!=null ? (typeof body.data==='string'?body.data:JSON.stringify(body.data)).slice(0,8000) : '';
    const key = await sec('openrouter_api_key'); if(!key) return J({ error:'ai_unavailable' }, 500);
    const langDirective = lang==='ar' ? '\n\nLANGUAGE: Write the ENTIRE document body in formal Modern Standard Arabic (العربية الفصحى). Keep numbers, currency codes (AED) and proper names as-is.' : (lang==='bi' ? '\n\nLANGUAGE: Produce the document BILINGUALLY. For every section, write the English version first, then immediately its Modern Standard Arabic translation as a separate paragraph/heading. Keep numbers and AED as-is.' : '');
    const user = `DOCUMENT TITLE: ${title}\n\nLAYOUT / CONTENT INSTRUCTIONS:\n${layout}${langDirective}\n\nDATA TO USE${data?':\n'+data:' : (none provided — use [placeholders] where needed)'}`;
    let frag=''; let lastErr='';
    const c = await llm(SYS, user, 9000);
    if(c){ frag = stripFences(c); } else lastErr='empty';
    if(frag.length<40) return J({ error:'render_failed', detail:lastErr }, 502);
    frag = frag.replace(/<!doctype[\s\S]*?>/gi,'').replace(/<\/?(html|head|body)[^>]*>/gi,'').replace(/<style[\s\S]*?<\/style>/gi,'').trim();
    const rtl = lang==='ar' || (lang!=='bi' && dir(frag)==='rtl');
    const html = wrap(title, frag, rtl);
    const safe = title.replace(/[^\w.\-]+/g,'_').slice(0,60) || 'document';
    const stamp = new Date().toISOString().slice(0,10) + '/' + Date.now() + '_' + safe;
    const path = stamp + '.html';
    const up = await admin.storage.from('agent-docs').upload(path, new Blob([html], { type:'text/html' }), { contentType:'text/html', upsert:false });
    if(up.error) return J({ error:'store_failed', detail: up.error.message }, 500);
    const { data: signed } = await admin.storage.from('agent-docs').createSignedUrl(path, 7*24*3600);
    let pdf_url=null, pdf_path=null;
    if (body.pdf !== false){
      try { const secret=await sec('inbound_secret'); const pr = await fetch(`${URL_}/functions/v1/pdf_native`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: secret, title, body_html: frag, name: safe, lang, options:{ letterhead:true, sign: body.sign!==false, stamp: body.stamp!==false } }) }); const pj=await pr.json(); if(pj?.ok){ pdf_url=pj.url; pdf_path=pj.path; } } catch(_e){ /* */ }
    }
    return J({ ok:true, title, lang, path, url: signed?.signedUrl||null, pdf_url, pdf_path, bytes: html.length });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
