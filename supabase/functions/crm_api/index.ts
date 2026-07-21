// crm_api v6 - CRM backend + admin SMS MFA + agent queue/detail + tasks + agent activity.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function signDoc(bucket: string, p?: string|null){ if(!p) return null; try{ const {data}=await admin.storage.from(bucket).createSignedUrl(p,3600); return data?.signedUrl||null; }catch{ return null; } }
const money = (n: unknown) => { const v = Number(n); return isFinite(v) ? v : null; };
const clampInt = (v: unknown, d: number, lo: number, hi: number) => { const n = parseInt(String(v),10); return isNaN(n) ? d : Math.max(lo, Math.min(hi, n)); };
const likeSafe = (s: unknown) => String(s ?? '').replace(/[%,()*\\]/g, ' ').trim().slice(0, 80);
async function cnt(t: string, mod?: (q: any)=>any){ let q = admin.from(t).select('id', { count: 'exact', head: true }); if (mod) q = mod(q); const { count } = await q; return count || 0; }
function jwtClaims(t: string){ try{ const p=String(t||'').split('.')[1]; if(!p) return {} as any; const s=atob(p.replace(/-/g,'+').replace(/_/g,'/')); return JSON.parse(s); }catch(_e){ return {} as any; } }
function maskPhone(p: string){ const s=String(p||''); return s.length>4 ? ('••• '+s.slice(-4)) : '•••'; }
async function mfaOk(sid: string){ if(!sid) return false; const { data } = await admin.from('admin_mfa_sessions').select('expires_at').eq('session_id', sid).gt('expires_at', new Date().toISOString()).maybeSingle(); return !!data; }
async function tw(path: string, params: Record<string,string>){ const ksid=await sec('twilio_api_key_sid'); const ksec=await sec('twilio_api_key_secret'); const svc=await sec('twilio_verify_service_sid'); if(!ksid||!ksec||!svc) return null; const auth=btoa(ksid+':'+ksec); const r=await fetch('https://verify.twilio.com/v2/Services/'+svc+path,{ method:'POST', headers:{ 'Authorization':'Basic '+auth, 'Content-Type':'application/x-www-form-urlencoded' }, body:new URLSearchParams(params) }); const j=await r.json().catch(()=>({})); return { ok:r.ok, j }; }
async function verifyStart(phone: string){ const r=await tw('/Verifications',{ To:phone, Channel:'sms' }); return !!(r && r.ok); }
async function verifyCheck(phone: string, code: string){ const r=await tw('/VerificationCheck',{ To:phone, Code:code }); return !!(r && r.ok && (r.j as any) && (r.j as any).status==='approved'); }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    let who = 'secret'; let authed = false; let jwt = '';
    if (body.__secret && body.__secret === (await sec('inbound_secret'))) authed = true;
    if (!authed) {
      jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) { authed = true; who = user.email.toLowerCase(); }
    }
    if (!authed) return J({ error: 'forbidden — not an admin' }, 403);
    const action = String(body.action || '');
    const viaSecret = (who === 'secret');
    let sid = ''; if (!viaSecret) { sid = (jwtClaims(jwt).session_id as string) || ''; }

    if (action === 'mfa_status') { const ph = await sec('admin_mfa_phone'); return J({ ok:true, required:true, configured: !!ph, phone_masked: ph?maskPhone(ph):null, passed: viaSecret?true:(await mfaOk(sid)) }); }
    if (action === 'mfa_start') { if (viaSecret) return J({ error:'login required' },400); const ph = await sec('admin_mfa_phone'); if(!ph) return J({ error:'mfa_phone_not_set' },400); const ok=await verifyStart(ph); if(!ok) return J({ error:'sms_failed' },502); return J({ ok:true, phone_masked: maskPhone(ph) }); }
    if (action === 'mfa_verify') { if (viaSecret) return J({ error:'login required' },400); if(!sid) return J({ error:'no_session' },400); const ph=await sec('admin_mfa_phone'); const code=String(body.code||'').trim(); if(!/^[0-9]{4,8}$/.test(code)) return J({ error:'bad_code' },400); const ok=await verifyCheck(ph as string, code); if(!ok) return J({ ok:false, error:'wrong_code' },200); await admin.from('admin_mfa_sessions').upsert({ session_id:sid, email:who, verified_at:new Date().toISOString(), expires_at:new Date(Date.now()+12*3600e3).toISOString() }); return J({ ok:true }); }

    const MFA_EXEMPT = ['meta','mfa_status','mfa_start','mfa_verify'];
    if (!viaSecret && !MFA_EXEMPT.includes(action)) { if (!(await mfaOk(sid))) return J({ error: 'mfa_required' }, 401); }

    const page = clampInt(body.page, 1, 1, 100000);
    const size = clampInt(body.size, 25, 5, 100);
    const from = (page - 1) * size, to = from + size - 1;
    const dir = String(body.dir || 'desc').toLowerCase() === 'asc';

    async function notesFor(entity: string, entity_id: string) {
      const { data } = await admin.from('crm_notes').select('id,body,author,created_at').eq('entity', entity).eq('entity_id', String(entity_id)).order('created_at', { ascending: false }).limit(50);
      return data || [];
    }

    if (action === 'dashboard') {
      const since7 = new Date(Date.now() - 7 * 864e5).toISOString();
      const supBase = (q: any) => q.or('claimed.eq.true,source.eq.self_registered,source.eq.email_inbound');
      const [pending_suppliers, total_suppliers, customers, inquiries_total, inquiries_7d, quotes_total, reveals_total, refunds_requested, agent_pending, violations_7d, chat_requests, open_tasks] = await Promise.all([
        cnt('leads', (q)=>supBase(q).in('approval_status', ['pending','submitted'])),
        cnt('leads', (q)=>supBase(q).eq('approval_status','approved')),
        cnt('customers'),
        cnt('inquiries'),
        cnt('inquiries', (q)=>q.gte('created_at', since7)),
        cnt('quotes'),
        cnt('transactions'),
        cnt('transactions', (q)=>q.eq('refund_status','requested')),
        cnt('agent_actions', (q)=>q.eq('status','pending')),
        cnt('chat_violations', (q)=>q.gte('created_at', since7)),
        cnt('chat_threads', (q)=>q.eq('status','requested')),
        cnt('crm_tasks', (q)=>q.eq('status','open')),
      ]);
      return J({ ok:true, stats: { pending_suppliers, total_suppliers, customers, inquiries_total, inquiries_7d, quotes_total, reveals_total, refunds_requested, agent_pending, violations_7d, chat_requests, open_tasks } });
    }

    if (action === 'agents_pending') {
      const { data } = await admin.from('agent_actions').select('id,agent,kind,status,risk,title,recommendation,target_table,detail,created_at').eq('status','pending').order('created_at',{ ascending:false }).limit(100);
      return J({ ok:true, rows: data || [] });
    }
    if (action === 'agent_action') {
      const id = Number(body.id); if(!id) return J({ error:'id required' }, 400);
      const { data } = await admin.from('agent_actions').select('*').eq('id', id).maybeSingle();
      if(!data) return J({ error:'not_found' }, 404);
      return J({ ok:true, action: data });
    }
    if (action === 'agent_runs_recent') {
      const ag = String(body.agent||'');
      let q = admin.from('agent_runs').select('id,agent,status,started_at,finished_at,counts').order('started_at',{ascending:false}).limit(15);
      if (ag) q = q.eq('agent', ag);
      const { data } = await q;
      return J({ ok:true, rows: data || [] });
    }

    if (action === 'tasks_list') {
      const st = String(body.status||'open');
      let q = admin.from('crm_tasks').select('*');
      if (st==='open' || st==='done') q = q.eq('status', st);
      const { data } = await q.order('created_at',{ascending:false}).limit(200);
      return J({ ok:true, rows: data || [] });
    }
    if (action === 'task_add') {
      const title = String(body.title||'').slice(0,200); if(!title) return J({ error:'title required' },400);
      const { error } = await admin.from('crm_tasks').insert({ title, detail:String(body.detail||'').slice(0,2000), priority:['low','normal','high'].includes(String(body.priority))?String(body.priority):'normal', due_date:/^\d{4}-\d{2}-\d{2}$/.test(String(body.due_date||''))?String(body.due_date):null, source: who });
      if (error) return J({ error: error.message },500);
      const { data } = await admin.from('crm_tasks').select('*').eq('status','open').order('created_at',{ascending:false}).limit(200);
      return J({ ok:true, rows: data || [] });
    }
    if (action === 'task_done') {
      const id = String(body.id||''); if(!id) return J({ error:'id required' },400);
      const st = String(body.op||'done')==='reopen' ? 'open' : 'done';
      const { error } = await admin.from('crm_tasks').update({ status: st, done_at: st==='done'?new Date().toISOString():null }).eq('id', id);
      if (error) return J({ error: error.message },500);
      const { data } = await admin.from('crm_tasks').select('*').eq('status','open').order('created_at',{ascending:false}).limit(200);
      return J({ ok:true, rows: data || [] });
    }

    if (action === 'list_suppliers') {
      const sortCol = ['portal_updated_at','company_name','registration_submitted_at','app_rating','license_expiry'].includes(String(body.sort)) ? String(body.sort) : 'portal_updated_at';
      let q = admin.from('leads').select('id,company_name,sector,emirate,approval_status,verified,banned,registration_status,registration_expires_at,app_rating,app_reviews,rating,reviews,email,phone,license_expiry,registration_submitted_at,portal_updated_at,ai_review_flags,tags,source,claimed', { count: 'exact' })
        .or('claimed.eq.true,source.eq.self_registered,source.eq.email_inbound');
      if (body.status) q = q.eq('approval_status', String(body.status));
      if (body.emirate) q = q.eq('emirate', String(body.emirate));
      if (body.reg) q = q.eq('registration_status', String(body.reg));
      if (body.banned === true) q = q.eq('banned', true);
      if (body.banned === false) q = q.or('banned.is.null,banned.eq.false');
      const term = likeSafe(body.q);
      if (term) q = q.or(`company_name.ilike.*${term}*,email.ilike.*${term}*,sector.ilike.*${term}*`);
      const { data, count, error } = await q.order(sortCol, { ascending: dir, nullsFirst: false }).range(from, to);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, rows: data || [], total: count || 0, page, size });
    }

    if (action === 'list_customers') {
      const sortCol = ['created_at','full_name'].includes(String(body.sort)) ? String(body.sort) : 'created_at';
      let q = admin.from('customers').select('id,full_name,email,phone,email_verified,phone_verified,banned,created_at', { count: 'exact' });
      if (body.banned === true) q = q.eq('banned', true);
      if (body.banned === false) q = q.or('banned.is.null,banned.eq.false');
      if (body.verified === true) q = q.eq('email_verified', true);
      const term = likeSafe(body.q);
      if (term) q = q.or(`full_name.ilike.*${term}*,email.ilike.*${term}*,phone.ilike.*${term}*`);
      const { data, count, error } = await q.order(sortCol, { ascending: dir, nullsFirst: false }).range(from, to);
      if (error) return J({ error: error.message }, 500);
      const rows = data || []; const ids = rows.map((r: any) => r.id);
      const inqC: Record<string, number> = {}; const spend: Record<string, number> = {};
      if (ids.length) {
        const { data: inq } = await admin.from('inquiries').select('customer_id').in('customer_id', ids); for (const x of inq || []) inqC[String((x as any).customer_id)] = (inqC[String((x as any).customer_id)] || 0) + 1;
        const { data: tx } = await admin.from('transactions').select('customer_id,reveal_fee').in('customer_id', ids); for (const x of tx || []) spend[String((x as any).customer_id)] = (spend[String((x as any).customer_id)] || 0) + (Number((x as any).reveal_fee) || 0);
      }
      return J({ ok: true, rows: rows.map((r: any) => ({ ...r, inquiries: inqC[String(r.id)] || 0, fees_paid: Math.round((spend[String(r.id)] || 0) * 100) / 100 })), total: count || 0, page, size });
    }

    if (action === 'list_deals') {
      let q = admin.from('inquiries').select('id,category,emirate,summary,status,scope_type,budget,created_at,customer_id,hired_supplier_id,outcome', { count: 'exact' });
      if (body.status) q = q.eq('status', String(body.status));
      if (body.emirate) q = q.eq('emirate', String(body.emirate));
      const term = likeSafe(body.q);
      if (term) q = q.or(`summary.ilike.*${term}*,category.ilike.*${term}*,emirate.ilike.*${term}*`);
      const { data, count, error } = await q.order('created_at', { ascending: dir, nullsFirst: false }).range(from, to);
      if (error) return J({ error: error.message }, 500);
      const rows = data || []; const ids = rows.map((r: any) => r.id); const cids = [...new Set(rows.map((r: any) => r.customer_id).filter(Boolean))];
      const mc: Record<string, number> = {}; const qc: Record<string, number> = {}; const rv: Record<string, number> = {}; const cm: Record<string, string> = {};
      if (ids.length) {
        const { data: m } = await admin.from('inquiry_matches').select('inquiry_id').in('inquiry_id', ids); for (const x of m || []) mc[(x as any).inquiry_id] = (mc[(x as any).inquiry_id] || 0) + 1;
        const { data: qs } = await admin.from('quotes').select('inquiry_id').in('inquiry_id', ids); for (const x of qs || []) qc[(x as any).inquiry_id] = (qc[(x as any).inquiry_id] || 0) + 1;
        const { data: tx } = await admin.from('transactions').select('inquiry_id').in('inquiry_id', ids); for (const x of tx || []) rv[(x as any).inquiry_id] = (rv[(x as any).inquiry_id] || 0) + 1;
      }
      if (cids.length) { const { data: cs } = await admin.from('customers').select('id,email,full_name').in('id', cids); for (const c of cs || []) cm[String((c as any).id)] = (c as any).full_name || (c as any).email; }
      return J({ ok: true, rows: rows.map((r: any) => ({ ...r, customer: cm[String(r.customer_id)] || null, matches: mc[r.id] || 0, quotes: qc[r.id] || 0, reveals: rv[r.id] || 0 })), total: count || 0, page, size });
    }

    if (action === 'supplier_detail') {
      const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400);
      const { data: l } = await admin.from('leads').select('*').eq('id', id).maybeSingle();
      if (!l) return J({ error: 'not_found' }, 404);
      const docs: Record<string, string> = {};
      for (const k of Object.keys(l)) { if (/(license|licence|trade|profile|catalog|iban|egr).*(path)$/i.test(k)) { const v = (l as any)[k]; if (typeof v === 'string' && v) { const u = await signDoc('supplier-docs', v); if (u) docs[k] = u; } else if (Array.isArray(v)) { for (let i=0;i<v.length;i++){ const u = await signDoc('supplier-docs', v[i]); if (u) docs[k+'_'+i] = u; } } } }
      const { data: quotes } = await admin.from('quotes').select('id,inquiry_id,quote_amount,status,created_at').eq('supplier_id', id).order('created_at', { ascending: false }).limit(20);
      const { data: tx } = await admin.from('transactions').select('inquiry_id,quote_amount,reveal_fee,revealed_at,fee_status').eq('supplier_id', id).order('revealed_at', { ascending: false }).limit(20);
      return J({ ok: true, supplier: l, docs, quotes: (quotes||[]).map((q:any)=>({ ...q, quote_amount: money(q.quote_amount) })), transactions: tx || [], notes: await notesFor('supplier', String(id)) });
    }

    if (action === 'customer_detail') {
      const id = String(body.id || ''); if (!id) return J({ error: 'id required' }, 400);
      const { data: c } = await admin.from('customers').select('*').eq('id', id).maybeSingle();
      if (!c) return J({ error: 'not_found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,category,emirate,summary,status,created_at,outcome').eq('customer_id', id).order('created_at', { ascending: false }).limit(30);
      const { data: tx } = await admin.from('transactions').select('inquiry_id,supplier_id,quote_amount,reveal_fee,revealed_at').eq('customer_id', id).order('revealed_at', { ascending: false }).limit(30);
      const supIds = [...new Set((tx||[]).map((t:any)=>t.supplier_id).filter(Boolean))]; const sm: Record<string,string> = {};
      if (supIds.length) { const { data: ls } = await admin.from('leads').select('id,company_name').in('id', supIds); for (const s of ls||[]) sm[String((s as any).id)] = (s as any).company_name; }
      return J({ ok: true, customer: c, inquiries: inq || [], transactions: (tx||[]).map((t:any)=>({ ...t, quote_amount: money(t.quote_amount), supplier_name: sm[String(t.supplier_id)] || ('Lead #'+t.supplier_id) })), notes: await notesFor('customer', String(id)) });
    }

    if (action === 'deal_detail') {
      const id = String(body.inquiry_id || body.id || ''); if (!id) return J({ error: 'id required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('*').eq('id', id).maybeSingle();
      if (!inq) return J({ error: 'not_found' }, 404);
      const { data: cust } = inq.customer_id ? await admin.from('customers').select('id,full_name,email,phone').eq('id', inq.customer_id).maybeSingle() : { data: null } as any;
      const { data: matches } = await admin.from('inquiry_matches').select('supplier_id,match_reason').eq('inquiry_id', id);
      const { data: quotes } = await admin.from('quotes').select('id,supplier_id,quote_amount,status,lead_time,scope,created_at,original_file_path,original_file_name,anonymized').eq('inquiry_id', id).order('quote_amount', { ascending: true });
      const supIds = [...new Set([...(matches||[]).map((m:any)=>m.supplier_id), ...(quotes||[]).map((q:any)=>q.supplier_id)])].filter(Boolean);
      const sm: Record<string,any> = {}; if (supIds.length) { const { data: ls } = await admin.from('leads').select('id,company_name,emirate,approval_status').in('id', supIds); for (const s of ls||[]) sm[String((s as any).id)] = s; }
      const qids = (quotes||[]).map((q:any)=>q.id); const cacheMap: Record<string,any> = {};
      if (qids.length) { const { data: pc } = await admin.from('quote_pdf_cache').select('quote_id,bucket,path').in('quote_id', qids); for (const c of pc||[]) { if(!cacheMap[String((c as any).quote_id)]) cacheMap[String((c as any).quote_id)] = c; } }
      const quoteRows = await Promise.all((quotes||[]).map(async (q:any,i:number)=>{
        const orig = q.original_file_path ? await signDoc('quote-files', q.original_file_path) : null;
        const c = cacheMap[String(q.id)];
        const qd = c ? await signDoc(c.bucket || 'quote-files', c.path) : null;
        return { ...q, quote_amount: money(q.quote_amount), label: 'Supplier '+String.fromCharCode(65+i), supplier_name: sm[String(q.supplier_id)]?.company_name || ('Lead #'+q.supplier_id), original_url: orig, original_name: q.original_file_name || null, qd_url: qd };
      }));
      const { data: tx } = await admin.from('transactions').select('quote_id,supplier_id,reveal_fee,fee_status,refund_status,revealed_at').eq('inquiry_id', id);
      return J({ ok: true, inquiry: inq, customer: cust || null,
        matches: (matches||[]).map((m:any)=>({ supplier_id:m.supplier_id, company_name: sm[String(m.supplier_id)]?.company_name || ('Lead #'+m.supplier_id), approval_status: sm[String(m.supplier_id)]?.approval_status || null, reason: m.match_reason })),
        quotes: quoteRows,
        transactions: tx || [], notes: await notesFor('deal', String(id)) });
    }

    if (action === 'note_add') {
      const entity = String(body.entity || ''); const entity_id = String(body.entity_id || ''); const text = String(body.body || '').trim().slice(0, 2000);
      if (!['supplier','customer','deal'].includes(entity) || !entity_id || !text) return J({ error: 'entity, entity_id and body required' }, 400);
      const { error } = await admin.from('crm_notes').insert({ entity, entity_id, body: text, author: who });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, notes: await notesFor(entity, entity_id) });
    }

    if (action === 'disputes_list') {
      const { data: tx } = await admin.from('transactions').select('id,quote_id,inquiry_id,supplier_id,customer_id,quote_amount,reveal_fee,refund_status,refund_deadline,revealed_at,created_at').eq('refund_status','requested').order('revealed_at',{ascending:false}).limit(100);
      const rows = tx || []; const sup=[...new Set(rows.map((r:any)=>r.supplier_id).filter(Boolean))]; const cus=[...new Set(rows.map((r:any)=>r.customer_id).filter(Boolean))]; const inq=[...new Set(rows.map((r:any)=>r.inquiry_id).filter(Boolean))];
      const sm:Record<string,string>={},cm:Record<string,string>={},im:Record<string,string>={};
      if(sup.length){const{data}=await admin.from('leads').select('id,company_name').in('id',sup);for(const x of data||[])sm[String((x as any).id)]=(x as any).company_name;}
      if(cus.length){const{data}=await admin.from('customers').select('id,full_name,email').in('id',cus);for(const x of data||[])cm[String((x as any).id)]=(x as any).full_name||(x as any).email;}
      if(inq.length){const{data}=await admin.from('inquiries').select('id,summary,category').in('id',inq);for(const x of data||[])im[String((x as any).id)]=(x as any).summary||(x as any).category;}
      const now=Date.now();
      return J({ ok:true, rows: rows.map((r:any)=>({ ...r, quote_amount:money(r.quote_amount), reveal_fee:money(r.reveal_fee), supplier_name:sm[String(r.supplier_id)]||('Lead #'+r.supplier_id), customer_name:cm[String(r.customer_id)]||null, inquiry_summary:im[String(r.inquiry_id)]||null, within_window: r.refund_deadline?(new Date(r.refund_deadline).getTime()>now):null })) });
    }
    if (action === 'refund_decide') {
      const id=Number(body.tx_id||body.id); const op=String(body.op||''); if(!id||!['approve','reject'].includes(op)) return J({error:'tx_id and op (approve|reject) required'},400);
      const { data: tx } = await admin.from('transactions').select('id,customer_id,inquiry_id').eq('id',id).maybeSingle(); if(!tx) return J({error:'not_found'},404);
      const { error } = await admin.from('transactions').update({ refund_status: op==='approve'?'approved':'rejected', fee_status: op==='approve'?'refund_pending':'paid' }).eq('id',id);
      if (error) return J({ error: error.message }, 500);
      try{ const { data: c } = await admin.from('customers').select('email').eq('id',tx.customer_id).maybeSingle(); if(c?.email) await admin.from('notifications').insert({ type:'refund_'+op, to_email:c.email, to_role:'customer', inquiry_id:tx.inquiry_id, subject: op==='approve'?'Your QuotesDone refund was approved':'About your QuotesDone refund request', body: op==='approve'?('Your reveal-fee refund has been approved and will be processed to your original payment method.'+(body.reason?(' Note: '+String(body.reason)):'')):('We have reviewed your refund request and are unable to approve it on this occasion.'+(body.reason?(' Reason: '+String(body.reason)):'')) }); }catch(_e){}
      return J({ ok:true });
    }

    if (action === 'chats_list') {
      const { data: threads } = await admin.from('chat_threads').select('inquiry_id,supplier_id,customer_id,status,reason,requested_by,category,strikes,created_at,opened_at').order('created_at',{ascending:false}).limit(100);
      const T = threads || []; const sup=[...new Set(T.map((t:any)=>t.supplier_id).filter(Boolean))];
      const sm:Record<string,string>={}; if(sup.length){const{data}=await admin.from('leads').select('id,company_name').in('id',sup);for(const x of data||[])sm[String((x as any).id)]=(x as any).company_name;}
      const { data: viol } = await admin.from('chat_violations').select('inquiry_id,supplier_id,sender_role,sender_email,matched,created_at').order('id',{ascending:false}).limit(60);
      return J({ ok:true, threads: T.map((t:any)=>({ ...t, supplier_name:sm[String(t.supplier_id)]||('Lead #'+t.supplier_id) })), violations: viol||[] });
    }
    if (action === 'chat_decide') {
      const iid=String(body.inquiry_id||''); const sid2=Number(body.supplier_id||0); const op=String(body.op||''); if(!iid||!sid2||!['open','decline'].includes(op)) return J({error:'inquiry_id, supplier_id, op (open|decline) required'},400);
      const { error } = await admin.from('chat_threads').update({ status: op==='open'?'open':'declined', opened_at: op==='open'?new Date().toISOString():null }).eq('inquiry_id',iid).eq('supplier_id',sid2);
      if (error) return J({ error: error.message }, 500);
      try{ await admin.from('agent_actions').update({ status: op==='open'?'approved':'rejected' }).eq('kind','open_chat').eq('target_id', iid+':'+sid2).eq('status','pending'); }catch(_e){}
      if(op==='open'){ try{
        const { data: th } = await admin.from('chat_threads').select('customer_id').eq('inquiry_id',iid).eq('supplier_id',sid2).maybeSingle();
        const { data: lead } = await admin.from('leads').select('claimed_by').eq('id',sid2).maybeSingle();
        const rows:any[]=[];
        if(lead?.claimed_by) rows.push({ type:'chat_opened', to_email:lead.claimed_by, to_role:'supplier', inquiry_id:iid, subject:'A chat was opened on QuotesDone', body:'A direct chat has been opened on a revealed inquiry. Log in to your portal to reply.' });
        if(th?.customer_id){ const { data: c } = await admin.from('customers').select('email').eq('id',th.customer_id).maybeSingle(); if(c?.email) rows.push({ type:'chat_opened', to_email:c.email, to_role:'customer', inquiry_id:iid, subject:'Your chat request was approved', body:'Your chat request has been approved. Log in to QuotesDone to message the supplier.' }); }
        if(rows.length) await admin.from('notifications').insert(rows);
      }catch(_e){} }
      return J({ ok:true });
    }

    async function supplierOp(id: number, op: string, reason?: string, value?: string) {
      const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by,tags').eq('id', id).maybeSingle();
      if (!lead) return { id, ok: false, error: 'not_found' };
      if (op === 'approve') { await admin.from('leads').update({ verified: true, approval_status: 'approved', lifecycle_stage: 'active', approved_at: new Date().toISOString(), approval_decided_by: who, portal_updated_at: new Date().toISOString() }).eq('id', id); if (lead.claimed_by) await admin.from('notifications').insert({ type: 'registration_approved', to_email: lead.claimed_by, to_role: 'supplier', lead_id: id, subject: "You're verified on QuotesDone", body: `Good news — ${lead.company_name} has been verified and approved on QuotesDone. You can now receive inquiries and submit quotes: https://quotesdone.com/suppliers/` }); }
      else if (op === 'reject') { await admin.from('leads').update({ approval_status: 'rejected', verified: false, approval_decided_by: who, rejection_reason: String(reason||'').slice(0,500), portal_updated_at: new Date().toISOString() }).eq('id', id); if (lead.claimed_by) await admin.from('notifications').insert({ type: 'registration_rejected', to_email: lead.claimed_by, to_role: 'supplier', lead_id: id, subject: 'QuotesDone registration — more info needed', body: `We reviewed the registration for ${lead.company_name} and need to verify some details before approving.${reason?(' Note: '+reason):''} Please update your profile in the portal.` }); }
      else if (op === 'ban') { await admin.from('leads').update({ banned: true, banned_reason: String(reason||'admin action').slice(0,300) }).eq('id', id); }
      else if (op === 'unban') { await admin.from('leads').update({ banned: false, banned_reason: null }).eq('id', id); }
      else if (op === 'tag') { const cur = Array.isArray(lead.tags) ? lead.tags : []; const t = String(value||'').trim().slice(0,40); if (t && !cur.includes(t)) await admin.from('leads').update({ tags: [...cur, t] }).eq('id', id); }
      else return { id, ok: false, error: 'bad_op' };
      return { id, ok: true };
    }
    async function customerOp(id: string, op: string, reason?: string) {
      if (op === 'ban') await admin.from('customers').update({ banned: true, banned_reason: String(reason||'admin action').slice(0,300) }).eq('id', id);
      else if (op === 'unban') await admin.from('customers').update({ banned: false, banned_reason: null }).eq('id', id);
      else return { id, ok: false, error: 'bad_op' };
      return { id, ok: true };
    }

    if (action === 'supplier_op') { const r = await supplierOp(Number(body.id), String(body.op), body.reason, body.value); return J(r.ok ? { ok: true } : { error: r.error }, r.ok ? 200 : 400); }
    if (action === 'customer_op') { const r = await customerOp(String(body.id), String(body.op), body.reason); return J(r.ok ? { ok: true } : { error: r.error }, r.ok ? 200 : 400); }

    if (action === 'bulk') {
      const entity = String(body.entity || ''); const op = String(body.op || ''); const ids = Array.isArray(body.ids) ? body.ids.slice(0, 200) : [];
      if (!ids.length) return J({ error: 'ids required' }, 400);
      const results: any[] = [];
      if (entity === 'supplier') { for (const id of ids) results.push(await supplierOp(Number(id), op, body.reason, body.value)); }
      else if (entity === 'customer') { for (const id of ids) results.push(await customerOp(String(id), op, body.reason)); }
      else return J({ error: 'bad entity' }, 400);
      const done = results.filter((r) => r.ok).length;
      return J({ ok: true, done, failed: results.length - done, results });
    }

    if (action === 'meta') {
      return J({ ok: true, emirates: ['Dubai','Abu Dhabi','Sharjah','Ajman','Ras Al Khaimah','Umm Al Quwain','Fujairah'], supplier_status: ['pending','approved','rejected','submitted'], deal_status: ['sent','quoted','revealed','completed','closed','cancelled'] });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
