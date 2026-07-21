// admin_detail - rich detail endpoints for the admin operations console. Admin-only or { __secret }.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function signDrawing(p?: string|null){ if(!p) return null; try{ const {data}=await admin.storage.from('drawing-files').createSignedUrl(p,3600); return data?.signedUrl||null; }catch{ return null; } }
async function signDoc(bucket: string, p?: string|null){ if(!p) return null; try{ const {data}=await admin.storage.from(bucket).createSignedUrl(p,3600); return data?.signedUrl||null; }catch{ return null; } }
function money(n: unknown){ const v=Number(n); return isFinite(v)?v:null; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    let authed = false, who = 'secret';
    if (body.__secret && body.__secret === (await sec('inbound_secret'))) authed = true;
    if (!authed) {
      const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) { authed = true; who = user.email.toLowerCase(); }
    }
    if (!authed) return J({ error:'forbidden' }, 403);
    const action = String(body.action||'');

    if (action === 'team_feed') {
      const ev: any[] = [];
      const { data: ho } = await admin.from('agent_actions').select('agent,kind,title,detail,created_at,status').eq('kind','handoff').order('created_at',{ascending:false}).limit(30);
      for (const h of ho||[]) ev.push({ ts:h.created_at, type:'handoff', text:(((h.detail&&((h.detail as any).from_name||(h.detail as any).from))||'An agent'))+' → '+h.agent+': '+String(h.title||'').replace(/^Handoff — /,''), status:h.status });
      try { const { data: lg } = await admin.from('agent_action_log').select('agent_key,action,ok,actor,created_at').order('created_at',{ascending:false}).limit(30); for (const l of lg||[]) ev.push({ ts:l.created_at, type:'action', text:l.agent_key+' '+(l.ok?'did':'tried')+' '+l.action+(l.actor&&l.actor!=='secret'?(' (by '+l.actor+')'):''), ok:l.ok }); } catch(_e){}
      try { const { data: rn } = await admin.from('agent_runs').select('agent,status,finished_at,counts').order('id',{ascending:false}).limit(15); for (const r of rn||[]) if(r.finished_at) ev.push({ ts:r.finished_at, type:'run', text:'Routine “'+r.agent+'” ran ('+r.status+')', status:r.status }); } catch(_e){}
      ev.sort((a,b)=> new Date(b.ts||0).getTime()-new Date(a.ts||0).getTime());
      return J({ ok:true, feed: ev.slice(0,60) });
    }

    if (action === 'recent_inquiries') {
      const lim = Math.min(Number(body.limit)||60, 200);
      const { data: inqs } = await admin.from('inquiries').select('id,created_at,category,summary,emirate,status,scope_type,budget,customer_id,routing').order('created_at',{ascending:false}).limit(lim);
      let rows = inqs||[];
      const qstr = String(body.q||'').trim().toLowerCase();
      if (qstr) rows = rows.filter((r:any)=> (String(r.summary||'')+' '+String(r.category||'')+' '+String(r.emirate||'')+' '+String(r.status||'')).toLowerCase().includes(qstr));
      const ids = rows.map((r:any)=>r.id); const custIds = Array.from(new Set(rows.map((r:any)=>r.customer_id).filter(Boolean)));
      const qc: Record<string,number> = {}; const mc: Record<string,number> = {};
      if (ids.length){ const { data: qs } = await admin.from('quotes').select('inquiry_id').in('inquiry_id', ids); for (const x of qs||[]) qc[(x as any).inquiry_id]=(qc[(x as any).inquiry_id]||0)+1; const { data: ms } = await admin.from('inquiry_matches').select('inquiry_id').in('inquiry_id', ids); for (const x of ms||[]) mc[(x as any).inquiry_id]=(mc[(x as any).inquiry_id]||0)+1; }
      const cm: Record<string,string> = {}; if (custIds.length){ const { data: cs } = await admin.from('customers').select('id,email').in('id', custIds); for (const c of cs||[]) cm[String((c as any).id)]=(c as any).email; }
      return J({ ok:true, inquiries: rows.map((r:any)=>({ id:r.id, created_at:r.created_at, category:r.category, summary:r.summary, emirate:r.emirate, status:r.status, scope_type:r.scope_type, budget:r.budget, customer_email: cm[String(r.customer_id)]||null, quotes: qc[r.id]||0, matches: mc[r.id]||0, primary_trade: (r.routing||{}).primary_trade||null })) });
    }

    if (action === 'inquiry_detail') {
      const id = String(body.inquiry_id||'');
      const { data: inq } = await admin.from('inquiries').select('*').eq('id', id).maybeSingle();
      if (!inq) return J({ error:'not_found' }, 404);
      const { data: cust } = inq.customer_id ? await admin.from('customers').select('id,email,full_name,phone,email_verified,created_at').eq('id', inq.customer_id).maybeSingle() : { data: null } as any;
      const { data: matches } = await admin.from('inquiry_matches').select('supplier_id,match_reason,similarity').eq('inquiry_id', id);
      const { data: quotes } = await admin.from('quotes').select('id,supplier_id,quote_amount,lead_time,validity,warranty,payment_terms,scope,conditions,exclusions,notes,status,source,created_at').eq('inquiry_id', id).order('created_at',{ascending:true});
      const supIds = Array.from(new Set([...(matches||[]).map((m:any)=>m.supplier_id), ...(quotes||[]).map((q:any)=>q.supplier_id)])).filter(Boolean);
      const supMap: Record<string,any> = {};
      if (supIds.length){ const { data: ls } = await admin.from('leads').select('id,company_name,emirate,approval_status,verified,rating,app_rating').in('id', supIds); for (const l of ls||[]) supMap[String(l.id)] = l; }
      const labelled = (quotes||[]).map((q:any,i:number)=>({ ...q, quote_amount: money(q.quote_amount), supplier_label:'Supplier '+(i+1), supplier_name: supMap[String(q.supplier_id)]?.company_name||('Lead #'+q.supplier_id), supplier_emirate: supMap[String(q.supplier_id)]?.emirate||null }));
      const matchOut = (matches||[]).map((m:any)=>({ supplier_id:m.supplier_id, company_name: supMap[String(m.supplier_id)]?.company_name||('Lead #'+m.supplier_id), approval_status: supMap[String(m.supplier_id)]?.approval_status||null, reason:m.match_reason||null }));
      const { data: txs } = await admin.from('transactions').select('quote_id,supplier_id,reveal_fee,fee_status,refund_status,revealed_at,created_at').eq('inquiry_id', id);
      const draw_url = await signDrawing(inq.drawing_file_path);
      const redacted: string[] = [];
      if (Array.isArray(inq.drawing_redacted_paths)) for (const p of inq.drawing_redacted_paths){ const u=await signDrawing(p); if(u) redacted.push(u); }
      return J({ ok:true, inquiry:{ id:inq.id, category:inq.category, summary:inq.summary, raw_input:inq.raw_input, spec:inq.spec, budget:inq.budget, emirate:inq.emirate, scope_type:inq.scope_type, trades:inq.trades, status:inq.status, created_at:inq.created_at, brief_source:inq.brief_source, boq:inq.boq, boq_confidence:inq.boq_confidence, outcome:inq.outcome, hired_supplier_id:inq.hired_supplier_id, routing:inq.routing||null, drawing_file_name:inq.drawing_file_name, drawing_url:draw_url, redacted_urls:redacted }, customer:cust||null, matches:matchOut, quotes:labelled, transactions:txs||[] });
    }

    if (action === 'quote_detail') {
      const id = String(body.quote_id||'');
      const { data: q } = await admin.from('quotes').select('*').eq('id', id).maybeSingle();
      if (!q) return J({ error:'not_found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,summary,category,emirate,customer_id').eq('id', q.inquiry_id).maybeSingle();
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,phone,email,approval_status,verified').eq('id', q.supplier_id).maybeSingle();
      const { data: sibs } = await admin.from('quotes').select('id,created_at').eq('inquiry_id', q.inquiry_id).order('created_at',{ascending:true});
      const idx = (sibs||[]).findIndex((s:any)=>s.id===q.id); const supN = idx>=0?idx+1:1;
      let orig=null; if (q.original_file_path){ orig = await signDoc('quote-files', q.original_file_path); }
      return J({ ok:true, quote:{ ...q, quote_amount: money(q.quote_amount), supplier_label:'Supplier '+supN }, inquiry:inq||null, supplier:sup||null, original_file_url:orig });
    }

    if (action === 'pending_approvals') {
      const { data: ls } = await admin.from('leads').select('*').or('approval_status.eq.pending,approval_status.eq.submitted').order('registration_submitted_at',{ascending:true,nullsFirst:false}).limit(100);
      const out = [] as any[];
      for (const l of ls||[]){
        const docs: Record<string,string> = {};
        for (const k of Object.keys(l)){ if(/(license|licence|trade|doc|catalog|profile).*(path)$/i.test(k) && typeof l[k]==='string' && l[k]){ const u=await signDoc('supplier-docs', l[k]); if(u) docs[k]=u; } }
        out.push({ id:l.id, company_name:l.company_name, name_corrected_from:l.name_corrected_from||null, license_city:l.license_city||null, license_expiry:l.license_expiry||l.expiry||null, doc_extracted_at:l.doc_extracted_at||null, capability_summary:l.capability_summary||null, emirate:l.emirate, email:l.email, phone:l.phone, registration_submitted_at:l.registration_submitted_at||null, approval_status:l.approval_status, docs });
      }
      return J({ ok:true, pending: out, count: out.length });
    }

    if (action === 'approve') {
      const id = Number(body.lead_id); if(!id) return J({ error:'lead_id required' },400);
      const { error } = await admin.from('leads').update({ approval_status:'approved', approved_at:new Date().toISOString(), approval_decided_by:who }).eq('id', id);
      if (error) return J({ error:error.message },500);
      return J({ ok:true, lead_id:id, approval_status:'approved' });
    }
    if (action === 'reject') {
      const id = Number(body.lead_id); if(!id) return J({ error:'lead_id required' },400);
      const { error } = await admin.from('leads').update({ approval_status:'rejected', approved_at:new Date().toISOString(), approval_decided_by:who, rejection_reason:String(body.reason||'').slice(0,500) }).eq('id', id);
      if (error) return J({ error:error.message },500);
      return J({ ok:true, lead_id:id, approval_status:'rejected' });
    }

    return J({ error:'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
