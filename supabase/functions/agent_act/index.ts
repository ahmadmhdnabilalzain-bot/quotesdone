// agent_act - conversational, action-capable agents for the CRM. Admin-gated (secret or admin JWT + MFA).
// Agent reads curated live data + company brain, PROPOSES one whitelisted action, and drafts/publishes content on explicit founder confirm.
// Reasoning on Opus 4.8 (strongest) with Sonnet 5 automatic fallback + retry — robust to model hiccups/deprecations.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const esc = (x: unknown) => String(x ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function jwtClaims(t: string){ try{ const p=String(t||'').split('.')[1]; if(!p) return {} as any; return JSON.parse(atob(p.replace(/-/g,'+').replace(/_/g,'/'))); }catch(_e){ return {} as any; } }
async function mfaOk(sid: string){ if(!sid) return false; const { data } = await admin.from('admin_mfa_sessions').select('expires_at').eq('session_id', sid).gt('expires_at', new Date().toISOString()).maybeSingle(); return !!data; }
const llm = makeLlm(SONNET_FIRST, { max: 900 }); // shared OpenRouter client (Sonnet-first ladder + 25s timeout, generalises H9)

const PERSONAS: Record<string,string> = {
  security: 'the Security agent — you watch uploaded files and platform safety',
  bd_outreach: 'the Business Development agent — you draft and manage supplier outreach',
  bd: 'the Business Development agent — you draft and manage supplier outreach',
  brief: 'the Daily Brief agent — you summarise the business each morning',
  it_health: 'the IT / Uptime agent — you watch uptime and system health',
  it: 'the IT / Uptime agent — you watch uptime and system health',
  legal: 'the Legal Counsel — you flag legal and compliance matters',
  compliance: 'the Compliance agent — you track regulatory matters',
  collections: 'the Collections Accountant — you track supplier dues',
  doc_control: 'the Document Controller — you track supplier documents and licences',
  docs: 'the Document Controller — you track supplier documents and licences',
  finance: 'the Finance / CFO agent — you prepare financial summaries and guidance',
  cfo: 'the CFO — you own financial strategy, cashflow and reporting',
  bookkeeper: 'the Bookkeeper — you keep the ledger, expenses and reconciliations tidy',
  marketing: 'the Marketing agent — you plan, draft and publish content and campaigns',
  onboarding: 'the Onboarding / KYC agent — you verify and onboard new suppliers',
  followup: 'the Follow-up agent — you chase pending actions and keep deals moving',
  crm: 'the CRM / Supplier Manager — you keep supplier and customer records healthy',
  pricing: 'the Pricing agent — you advise on pricing, ranges and competitiveness',
  secretary: 'the Executive Assistant — you organise tasks, approvals and the founder’s day',
};
// map UI/persona keys -> agent_knowledge keys so each agent loads its own role knowledge (all also inherit _global)
const KMAP: Record<string,string> = { finance:'cfo', cfo:'cfo', bookkeeper:'bookkeeper', it_health:'it', it:'it', bd_outreach:'bd', bd:'bd', doc_control:'docs', docs:'docs', compliance:'legal', legal:'legal', marketing:'marketing', security:'security', collections:'collections', brief:'brief', onboarding:'onboarding', followup:'followup', secretary:'secretary', crm:'crm', pricing:'pricing' };
async function brainFor(agent: string){ try{ const key = KMAP[agent] || agent; const { data } = await admin./* _capped: fn_agent_context ignores any p_max_chars below 22,000 (measured 11 Aug 2026: ask 3,000 get ~30,000), so the cap on this line was decorative and LAYER 2b/2c were never emitted without a query. */ rpc('fn_agent_context_capped', { p_agent_key: key, p_max_chars: 6500 }); return data ? String(data) : ''; }catch(_e){ return ''; } }
const SAFE_DELETE = ['quote-files','drawing-files','supplier-docs','receipt-files','agent-docs'];
const ALLOWED = ['resolve_action','dismiss_action','delete_file','add_note','draft_doc','approve_supplier','reject_supplier','send_message','create_task','post_content','ad_campaign'];

async function gatherContext(agent: string, message: string, action_id?: number){
  const ctx: any = {};
  if (action_id) { const { data } = await admin.from('agent_actions').select('id,agent,kind,status,risk,title,recommendation,target_table,detail,created_at').eq('id', action_id).maybeSingle(); if (data) ctx.this_alert = data; }
  const { data: pend } = await admin.from('agent_actions').select('id,agent,kind,risk,title,created_at').eq('status','pending').order('created_at',{ascending:false}).limit(12); ctx.pending_actions = pend || [];
  if (agent==='security' || /file|suspicious|upload|virus|malware|attach|scan/i.test(message)) { const { data: se } = await admin.from('security_events').select('kind,severity,source,subject,detail,created_at').order('created_at',{ascending:false}).limit(25); ctx.security_events = se || []; }
  if (agent==='doc_control' || agent==='docs' || /licen|document|expir|kyc/i.test(message)) { const { data: exp } = await admin.from('leads').select('company_name,license_expiry,approval_status').or('claimed.eq.true,source.eq.self_registered').not('license_expiry','is',null).order('license_expiry',{ascending:true}).limit(15); ctx.licence_expiries = exp || []; }
  if (/supplier|approve|reject|pending|register/i.test(message)) { const { data: sp } = await admin.from('leads').select('id,company_name,email,emirate,sector,approval_status,claimed_by').or('claimed.eq.true,source.eq.self_registered').in('approval_status',['pending','submitted']).order('registration_submitted_at',{ascending:false}).limit(15); ctx.pending_suppliers = sp || []; }
  if (agent==='marketing' || /content|post|campaign|caption|blog|social|draft/i.test(message)) { const { data: cd } = await admin.from('content_drafts').select('id,channel,title,status,created_at').order('created_at',{ascending:false}).limit(10); ctx.recent_content_drafts = cd || []; }
  const { data: tasks } = await admin.from('crm_tasks').select('id,title,status,priority,due_date').eq('status','open').order('created_at',{ascending:false}).limit(15); ctx.open_tasks = tasks || [];
  const since7 = new Date(Date.now()-7*864e5).toISOString();
  const [ps, ts, cu, iq, iq7, qt, rv] = await Promise.all([
    admin.from('leads').select('id',{count:'exact',head:true}).or('claimed.eq.true,source.eq.self_registered').in('approval_status',['pending','submitted']),
    admin.from('leads').select('id',{count:'exact',head:true}).or('claimed.eq.true,source.eq.self_registered').eq('approval_status','approved'),
    admin.from('customers').select('id',{count:'exact',head:true}),
    admin.from('inquiries').select('id',{count:'exact',head:true}),
    admin.from('inquiries').select('id',{count:'exact',head:true}).gte('created_at',since7),
    admin.from('quotes').select('id',{count:'exact',head:true}),
    admin.from('transactions').select('id',{count:'exact',head:true}),
  ]);
  ctx.stats = { suppliers_pending: ps.count||0, suppliers_approved: ts.count||0, customers: cu.count||0, inquiries_total: iq.count||0, inquiries_7d: iq7.count||0, quotes_total: qt.count||0, reveals_total: rv.count||0 };
  return ctx;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    let authed = false; let who = 'secret';
    if (body?.__secret && (await requireInternal(admin, body.__secret, 'agent_act')).ok) authed = true;
    if (!authed) {
      const jwt = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      const { data: { user } } = await admin.auth.getUser(jwt);
      const allow = (await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
      if (user?.email && allow.includes(user.email.toLowerCase())) { const sid=(jwtClaims(jwt).session_id as string)||''; if (await mfaOk(sid)) { authed = true; who = user.email.toLowerCase(); } else return J({ error:'mfa_required' },401); }
    }
    if (!authed) return J({ error:'forbidden' }, 403);
    const action = String(body.action||'chat');

    if (action === 'chat') {
      const agent = String(body.agent||'secretary');
      const message = String(body.message||'').slice(0, 2000);
      const action_id = body.action_id ? Number(body.action_id) : undefined;
      const history = Array.isArray(body.history) ? body.history.filter((m:any)=>m&&m.role&&m.content).slice(-8).map((m:any)=>({ role: m.role==='user'?'user':'assistant', content: String(m.content).slice(0,1500) })) : [];
      const ctx = await gatherContext(agent, message, action_id);
      const brain = await brainFor(agent);
      let persona = PERSONAS[agent] || ('the '+agent+' specialist for QuotesDone');
      if (agent.startsWith('cat:')) { const slug = agent.slice(4); let tname = slug.replace(/-/g,' '); try { const { data: ca } = await admin.from('category_agents').select('name').eq('slug', slug).maybeSingle(); if (ca?.name) tname = ca.name; } catch(_e){} persona = 'a veteran '+tname+' sales specialist with 20+ years closing deals in the UAE market, running the '+tname+' desk for QuotesDone'; }
      const sys = `You are ${persona}. QuotesDone is a UAE B2B anonymous quotation marketplace where a customer posts a job, verified UAE suppliers quote blind, and the customer pays a 3% reveal fee only on the quote they accept.\n\nIDENTITY & VOICE (critical): You are NOT a generic AI assistant and you never speak like one. You are a seasoned professional with 20+ years in your field in the UAE — you talk with the earned confidence, specificity and instincts of someone who has closed thousands of deals and seen every red flag, every trick and every objection. Be a sharp, warm, experienced colleague: direct, concrete, opinionated, never hedging, never robotic, and never say "as an AI". Lead with a real point of view backed by specific numbers, spec/brand examples and UAE-market realities.\n\nTWO KINDS OF FACTS — keep them separate: (1) TRADE & SALES EXPERTISE — industry norms, specs, what to check in a quote, pricing ranges, how to advise a buyer, competitive positioning: draw freely and confidently on your own 20-year expertise AND the COMPANY KNOWLEDGE; never refuse a trade question by saying it is "not in the data". (2) OUR OPERATIONAL FACTS — our own records, counts, live prices, policies, customer/supplier data, files: use ONLY the DATA and COMPANY KNOWLEDGE below and never invent a record, number, file or policy; if a specific one is not there, say what you can see and what you'd need.\n\nSALES PLAYBOOK (apply naturally, do not recite): qualify first (scope, budget, timeline, decision-maker, real pain) before pitching; diagnose then prescribe; handle objections head-on (price, trust, "I'll get my own quotes", "why anonymous?") with confident honest answers; use pricing psychology — give ranges and what drives them, and flag suspiciously low or high quotes and why; position QuotesDone's edge naturally (verified UAE suppliers competing blind, no time wasted chasing quotes, pay 3% only on the quote you accept, full anonymity until you choose); always end with a clear next step. Keep replies tight and high-signal.\n\nYou may PROPOSE exactly one action when clearly warranted. To propose, end your message with a final line starting with 'ACTION:' then minified JSON {\"kind\":\"<kind>\",\"args\":{...},\"label\":\"short button text\"}. Kinds:\n- resolve_action / dismiss_action — {\"id\":<agent_action id>} close a recommendation.\n- delete_file — {\"bucket\":<one of ${SAFE_DELETE.join(',')}>,\"path\":<exact path>} ONLY a specific dangerous file.\n- add_note — {\"entity\":\"supplier|customer|deal\",\"entity_id\":<id>,\"text\":<note>}.\n- approve_supplier / reject_supplier — {\"id\":<lead id>[,\"reason\":<text>]} approve or reject a supplier registration (notifies them).\n- send_message — {\"to_email\":<email>,\"to_role\":\"supplier|customer|admin\",\"subject\":<subject>,\"body\":<full message>} send an email/reply. Propose only when the founder asks to send or reply.\n- create_task — {\"title\":<title>[,\"detail\":<text>,\"priority\":\"low|normal|high\",\"due_date\":\"YYYY-MM-DD\"]} add a to-do to the founder's task list.\n- post_content — {\"channel\":\"email|whatsapp|social\",\"text\":<the full content>[,\"to\":[emails or phone numbers for email/whatsapp],\"title\":<short title>]} publish content. Use for Marketing. email/whatsapp send immediately on confirm; social publishes LIVE to your connected accounts (X, LinkedIn, Facebook; Instagram needs an image so text-only is skipped). Follow the brand voice in COMPANY KNOWLEDGE.\n- ad_campaign — {\"name\",\"objective\":\"OUTCOME_TRAFFIC|OUTCOME_LEADS|OUTCOME_ENGAGEMENT|OUTCOME_AWARENESS\",\"daily_budget_aed\":<number>,\"audience\":<who to target>,\"message\":<ad copy>,\"link\":\"https://quotesdone.com/...\"} design a Meta (Facebook/Instagram) ad campaign. On confirm it is created PAUSED for the founder to review and switch on in Ads Manager — it NEVER spends automatically. Design all the settings; the founder only approves and activates.\n- draft_doc — {\"title\":<title>,\"body\":<the FULL document text, plain or # markdown>} for a document/letter/reply to share. Write the complete document in body.\nPropose only when clearly warranted and safe. The founder confirms every action; you only propose. No ACTION line if none needed.\n\nCOMPANY KNOWLEDGE:\n${(brain||'(none loaded)').slice(0, 6500)}\n\nDATA:\n${JSON.stringify(ctx).slice(0, 8000)}`;
      const raw = await llm(sys, [...history, { role:'user', content: message }]);
      if (!raw) return J({ ok:true, reply:'(the agent could not respond just now — please try again)' });
      let reply = raw; let proposal: any = null;
      const idx = raw.lastIndexOf('ACTION:');
      if (idx >= 0) {
        reply = raw.slice(0, idx).trim();
        try { const jtxt = raw.slice(idx+7).trim().replace(/^```json/,'').replace(/```$/,'').trim(); const p = JSON.parse(jtxt); if (p && ALLOWED.includes(p.kind)) proposal = { kind:p.kind, args:p.args||{}, label: String(p.label||'Do it').slice(0,40) }; } catch(_e){}
      }
      return J({ ok:true, reply: reply || '(no reply)', proposal });
    }

    if (action === 'confirm') {
      const p = body.proposal || {}; const kind = String(p.kind||''); const args = p.args || {};
      if (kind === 'resolve_action' || kind === 'dismiss_action') {
        const id = Number(args.id); if(!id) return J({ error:'id required' },400);
        const st = kind==='resolve_action' ? 'done' : 'dismissed';
        const { error } = await admin.from('agent_actions').update({ status: st }).eq('id', id);
        if (error) return J({ error: error.message }, 500);
        return J({ ok:true, result: 'Recommendation marked '+st+'.' });
      }
      if (kind === 'delete_file') {
        const bucket = String(args.bucket||''); const path = String(args.path||'');
        if (!SAFE_DELETE.includes(bucket)) return J({ error:'bucket_not_allowed' },400);
        if (!path) return J({ error:'path required' },400);
        const { error } = await admin.storage.from(bucket).remove([path]);
        if (error) return J({ error: error.message }, 500);
        await admin.from('security_events').delete().eq('kind','suspicious_upload').eq('subject', path.slice(0,200));
        return J({ ok:true, result: 'File removed: '+bucket+'/'+path });
      }
      if (kind === 'add_note') {
        const entity = String(args.entity||''); const entity_id = String(args.entity_id||''); const text = String(args.text||'').slice(0,2000);
        if (!['supplier','customer','deal'].includes(entity) || !entity_id || !text) return J({ error:'bad_note_args' },400);
        const { error } = await admin.from('crm_notes').insert({ entity, entity_id, body: text, author: 'agent:'+(body.agent||'') });
        if (error) return J({ error: error.message }, 500);
        return J({ ok:true, result: 'Note added.' });
      }
      if (kind === 'approve_supplier' || kind === 'reject_supplier') {
        const id = Number(args.id); if(!id) return J({ error:'id required' },400);
        const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', id).maybeSingle();
        if(!lead) return J({ error:'not_found' },404);
        if (kind === 'approve_supplier') {
          await admin.from('leads').update({ verified:true, approval_status:'approved', lifecycle_stage:'active', approved_at:new Date().toISOString(), portal_updated_at:new Date().toISOString() }).eq('id', id);
          if (lead.claimed_by) await admin.from('notifications').insert({ type:'registration_approved', to_email:lead.claimed_by, to_role:'supplier', lead_id:id, subject:"You're verified on QuotesDone", body:`Good news — ${lead.company_name} has been verified and approved on QuotesDone. You can now receive inquiries and submit quotes: https://quotesdone.com/suppliers/` });
          return J({ ok:true, result:'Approved '+lead.company_name+'.' });
        } else {
          const reason = String(args.reason||'').slice(0,400);
          await admin.from('leads').update({ approval_status:'rejected', verified:false, rejection_reason:reason, portal_updated_at:new Date().toISOString() }).eq('id', id);
          if (lead.claimed_by) await admin.from('notifications').insert({ type:'registration_rejected', to_email:lead.claimed_by, to_role:'supplier', lead_id:id, subject:'QuotesDone registration — more info needed', body:`We reviewed the registration for ${lead.company_name} and need to verify some details before approving.${reason?(' Note: '+reason):''}` });
          return J({ ok:true, result:'Rejected '+lead.company_name+'.' });
        }
      }
      if (kind === 'send_message') {
        const to_email = String(args.to_email||'').trim(); const to_role = String(args.to_role||'admin'); const subject = String(args.subject||'(no subject)').slice(0,200); const bodyM = String(args.body||'').slice(0,5000);
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to_email)) return J({ error:'invalid_email' },400);
        if (!['supplier','customer','admin'].includes(to_role)) return J({ error:'bad_role' },400);
        const { error } = await admin.from('notifications').insert({ type:'agent_message', to_email, to_role, channel:'email', subject, body: bodyM });
        if (error) return J({ error: error.message }, 500);
        return J({ ok:true, result:'Email queued to '+to_email+' — it will send on the next email cycle.' });
      }
      if (kind === 'create_task') {
        const title = String(args.title||'').slice(0,200); if(!title) return J({ error:'title required' },400);
        const { error } = await admin.from('crm_tasks').insert({ title, detail:String(args.detail||'').slice(0,2000), priority:['low','normal','high'].includes(String(args.priority))?String(args.priority):'normal', due_date: /^\d{4}-\d{2}-\d{2}$/.test(String(args.due_date||''))?String(args.due_date):null, source:'agent:'+(body.agent||''), entity: args.entity?String(args.entity).slice(0,20):null, entity_id: args.entity_id?String(args.entity_id).slice(0,60):null });
        if (error) return J({ error: error.message }, 500);
        return J({ ok:true, result:'Task added: '+title });
      }
      if (kind === 'post_content') {
        const channel = String(args.channel||'').toLowerCase();
        const text = String(args.text||'').slice(0, 8000);
        const title = String(args.title||'').slice(0,140) || (text.slice(0,60).replace(/\n/g,' '));
        if (!text.trim()) return J({ error:'empty_content' },400);
        if (channel === 'email' || channel === 'whatsapp') {
          const to = Array.isArray(args.to) ? args.to.map((x:any)=>String(x).trim()).filter(Boolean) : [];
          if (!to.length) return J({ error:'need recipients for '+channel },400);
          const rows = to.slice(0,500).map((addr:string)=>({ type:'agent_post', to_email: channel==='email'?addr.slice(0,160):null, to_phone: channel==='whatsapp'?addr.slice(0,40):null, to_role:'external', channel, subject: title.slice(0,200), body: text }));
          const { error } = await admin.from('notifications').insert(rows);
          if (error) return J({ error: error.message }, 500);
          await admin.from('content_drafts').insert({ channel, title, body:text, status:'posted', source:'agent:'+(body.agent||'marketing') });
          return J({ ok:true, result:'Queued to '+to.length+' '+channel+' recipient(s) — sending on the next cycle.' });
        }
        const chans = (channel === 'social' || channel === 'all') ? ['x','linkedin','facebook','instagram'] : [channel];
        let pub: any = {}; try { const sk = await sec('cred_fn_agent_act'); const pr = await fetch(SUPA + '/functions/v1/postiz_publish', { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: sk, action:'post', type:'now', channels: chans, text, title }) }); pub = await pr.json(); } catch (e) { pub = { error: String((e as Error)?.message || e) }; }
        if (pub && pub.ok && (pub.published_to || 0) > 0) {
          await admin.from('content_drafts').insert({ channel: channel||'social', title, body:text, status:'posted', source:'agent:'+(body.agent||'marketing') });
          const skip = (pub.skipped && pub.skipped.length) ? (' Skipped: '+pub.skipped.join(', ')+'.') : '';
          return J({ ok:true, result:'Published live to '+pub.published_to+' channel(s) via Postiz.'+skip });
        }
        const { data: d } = await admin.from('content_drafts').insert({ channel: channel||'social', title, body:text, status:'ready', source:'agent:'+(body.agent||'marketing') }).select('id').maybeSingle();
        const why = (pub && pub.error) ? pub.error : ((pub && pub.skipped) ? ('nothing publishable — '+(pub.skipped||[]).join(', ')) : 'the social connector did not accept it');
        return J({ ok:true, result:'Saved as a ready-to-post draft (id '+(d?.id||'?')+') — could not publish now ('+why+'). It is queued in Content drafts for you to post.' });
      }
      if (kind === 'ad_campaign') {
        const name = String(args.name||'QuotesDone Campaign').slice(0,120);
        const plan = 'Objective: '+(args.objective||'OUTCOME_TRAFFIC')+'\\nDaily budget: AED '+(args.daily_budget_aed||50)+'\\nAudience: '+(args.audience||'UAE SMEs')+'\\nLink: '+(args.link||'https://quotesdone.com/app')+'\\n\\nAd copy:\\n'+(args.message||'');
        let mr: any = {}; try { const sk = await sec('cred_fn_agent_act'); const r = await fetch(SUPA + '/functions/v1/meta_ads', { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: sk, action:'quick_campaign', name, objective: args.objective, daily_budget_aed: args.daily_budget_aed, countries: args.countries }) }); mr = await r.json(); } catch (e) { mr = { error: String((e as Error)?.message || e) }; }
        if (mr && mr.ok && mr.campaign_id) {
          await admin.from('crm_tasks').insert({ title:'Review & launch Meta campaign: '+name, detail:'Created PAUSED in Meta Ads Manager.\\nCampaign: '+mr.campaign_id+'  Ad set: '+(mr.adset_id||'-')+'\\n\\n'+plan+'\\n\\nNext: add the ad creative in Ads Manager, then switch it ON to start spending.', priority:'normal', source:'agent:'+(body.agent||'marketing'), status:'open' });
          return J({ ok:true, result:'Created a PAUSED Meta campaign + ad set (campaign '+mr.campaign_id+'). Add the creative and switch it on in Ads Manager to start spending — I never activate it for you. Full plan saved as a task.' });
        }
        await admin.from('crm_tasks').insert({ title:'Meta campaign ready to launch: '+name, detail:plan+'\\n\\n(Meta Ads not connected yet. Add meta_access_token + meta_ad_account_id, then this can be created PAUSED.)', priority:'normal', source:'agent:'+(body.agent||'marketing'), status:'open' });
        const why = (mr && (mr.error || mr.adset_error)) || 'not connected';
        return J({ ok:true, result:'Meta Ads is not connected yet ('+why+'), so I saved the full campaign plan as a task. Once you add the Meta credentials I can create it PAUSED for your approval.' });
      }
      if (kind === 'draft_doc') {
        const title = String(args.title||'Document').slice(0,140);
        const bodyTxt = String(args.body||'').slice(0, 20000);
        const paras = esc(bodyTxt).split(/\n\n+/).map((pp)=>{ pp = pp.trim(); if(!pp) return ''; const hm = pp.match(/^(#{1,3})\s+([\s\S]+)/); if (hm) { const lvl = hm[1].length + 1; return '<h'+lvl+'>'+hm[2].replace(/\n/g,' ')+'</h'+lvl+'>'; } return '<p>'+pp.replace(/\n/g,'<br>')+'</p>'; }).join('');
        const html = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(title)+'</title><style>body{font-family:Georgia,\'Times New Roman\',serif;color:#1f2937;max-width:800px;margin:0 auto;padding:44px 30px;line-height:1.7}header{display:flex;align-items:center;gap:12px;border-bottom:3px solid #0E7C73;padding-bottom:14px;margin-bottom:26px}header img{height:38px;width:auto}header .b{font-family:Arial,Helvetica,sans-serif;font-weight:800;font-size:20px;color:#0E7C73}h1{font-size:24px;color:#0f172a;margin:0 0 14px}h2,h3,h4{color:#0E7C73;font-family:Arial,Helvetica,sans-serif}p{margin:10px 0}footer{margin-top:38px;border-top:1px solid #e5e7eb;padding-top:12px;color:#6b7280;font-size:12px;font-family:Arial,Helvetica,sans-serif}@media print{body{padding:0}}</style></head><body><header><img src="'+SUPA+'/storage/v1/object/public/brand/qd_mark.png" alt=""><span class="b">QuotesDone</span></header><h1>'+esc(title)+'</h1>'+paras+'<footer>Prepared by the '+esc(String(body.agent||'agent'))+' for QuotesDone · '+new Date().toISOString().slice(0,10)+' · Internal draft — review before use.</footer></body></html>';
        const slug = (title.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,40)) || 'doc';
        const path = 'agent-drafts/'+Date.now()+'-'+slug+'.html';
        const { error } = await admin.storage.from('agent-docs').upload(path, new TextEncoder().encode(html), { contentType:'text/html; charset=utf-8', upsert:true });
        if (error) return J({ error: error.message }, 500);
        const { data: su } = await admin.storage.from('agent-docs').createSignedUrl(path, 3600);
        return J({ ok:true, result: 'Document drafted: '+title, url: su?.signedUrl || null });
      }
      return J({ error:'unknown_action_kind' }, 400);
    }

    return J({ error:'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
