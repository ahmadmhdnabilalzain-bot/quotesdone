// crm_pipeline v3 - MERGED: restores the #272 UI contract (pipeline board / deal_set_stage /
// activity_list / activity_add) AND keeps the Odoo-grade analytics (pipeline_report, stages,
// lost reasons, deal_update, activities_list, activity_done). Additive to crm_api.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function jwtClaims(t: string){ try{ const p=String(t||'').split('.')[1]; if(!p) return {} as any; const s=atob(p.replace(/-/g,'+').replace(/_/g,'/')); return JSON.parse(s); }catch(_e){ return {} as any; } }
async function mfaOk(sid: string){ if(!sid) return false; const { data } = await admin.from('admin_mfa_sessions').select('expires_at').eq('session_id', sid).gt('expires_at', new Date().toISOString()).maybeSingle(); return !!data; }
const num = (v: unknown) => { if (v===null||v===undefined||v==='') return null; const n = Number(v); return isFinite(n) ? n : null; };
const ENTITIES = ['supplier','customer','deal'];
const ATYPES = ['call','meeting','email','todo','note','stage_change'];

async function timelineFor(entity: string, entity_id: string){
  const { data } = await admin.from('crm_activities').select('id,type,subject,body,actor,due_at,done,done_at,created_at')
    .eq('entity', entity).eq('entity_id', String(entity_id)).order('created_at',{ ascending:false }).limit(80);
  return data || [];
}
async function applyStageMove(id: string, stageKey: string, who: string, extra: Record<string, unknown> = {}) {
  const { data: st } = await admin.from('crm_stages').select('*').eq('key', stageKey).eq('active', true).maybeSingle();
  if (!st) return { ok:false, error:'unknown stage' };
  const patch: Record<string, unknown> = { pipeline_stage: st.key, stage_changed_at: new Date().toISOString(), ...extra };
  if (st.is_won) { patch.status = 'completed'; patch.outcome = 'won'; patch.completed_at = new Date().toISOString(); }
  else if (st.is_lost) { patch.status = 'cancelled'; patch.outcome = 'lost'; }
  const { error } = await admin.from('inquiries').update(patch).eq('id', id);
  if (error) return { ok:false, error: error.message };
  try { await admin.from('crm_activities').insert({ entity:'deal', entity_id:id, type:'stage_change', subject:'Moved to '+st.label, actor:who, done:true, done_at:new Date().toISOString() }); } catch(_e){}
  return { ok:true, stage: st };
}

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
    const sid = viaSecret ? '' : ((jwtClaims(jwt).session_id as string) || '');
    const MFA_EXEMPT = ['meta','stages_list','lost_reasons'];
    if (!viaSecret && !MFA_EXEMPT.includes(action)) { if (!(await mfaOk(sid))) return J({ error: 'mfa_required' }, 401); }

    if (action === 'meta') return J({ ok:true, entities: ENTITIES, activity_types: ATYPES });

    if (action === 'stages_list') {
      const { data } = await admin.from('crm_stages').select('*').eq('active', true).order('sort_order');
      return J({ ok:true, stages: data || [] });
    }
    if (action === 'lost_reasons') {
      const { data } = await admin.from('crm_lost_reasons').select('id,label').eq('active', true).order('sort_order');
      return J({ ok:true, reasons: data || [] });
    }

    // ---- Kanban board (#272 UI contract) + folded-in KPIs ----
    if (action === 'pipeline') {
      const { data: stages } = await admin.from('crm_stages').select('*').eq('active', true).order('sort_order');
      const { data: inq } = await admin.from('inquiries')
        .select('id,summary,category,emirate,budget,customer_id,pipeline_stage,expected_value')
        .order('created_at', { ascending: false }).limit(500);
      const rows = inq || [];
      const cids = [...new Set(rows.map((r:any)=>r.customer_id).filter(Boolean))];
      const cm: Record<string,string> = {};
      if (cids.length) { const { data: cs } = await admin.from('customers').select('id,full_name,email').in('id', cids); for (const c of cs||[]) cm[String((c as any).id)] = (c as any).full_name || (c as any).email; }
      const ids = rows.map((r:any)=>r.id);
      const qc: Record<string, number> = {};
      if (ids.length) { const { data: qs } = await admin.from('quotes').select('inquiry_id').in('inquiry_id', ids); for (const q of qs||[]) qc[String((q as any).inquiry_id)] = (qc[String((q as any).inquiry_id)]||0)+1; }
      const validKeys = new Set((stages||[]).map((s:any)=>s.key));
      const board = (stages||[]).map((s:any)=>{
        const deals = rows.filter((r:any)=> (validKeys.has(r.pipeline_stage) ? r.pipeline_stage : 'new') === s.key)
          .slice(0, 100)
          .map((r:any)=>({ id:r.id, summary:r.summary, category:r.category, emirate:r.emirate, budget:r.budget, customer: cm[String(r.customer_id)]||null, quotes: qc[String(r.id)]||0 }));
        const value = rows.filter((r:any)=> (validKeys.has(r.pipeline_stage) ? r.pipeline_stage : 'new') === s.key).reduce((a:number,r:any)=> a + (Number(r.expected_value)||0), 0);
        return { stage:s.key, label:s.label, probability:s.probability, is_won:s.is_won, is_lost:s.is_lost, count: deals.length, value: Math.round(value), deals };
      });
      const { data: kpis } = await admin.from('crm_deal_kpis').select('*').maybeSingle();
      const won = kpis?.won_deals || 0, lost = kpis?.lost_deals || 0;
      const win_rate = (won + lost) > 0 ? Math.round((won / (won + lost)) * 1000) / 10 : null;
      return J({ ok:true, board, kpis: { ...(kpis||{}), win_rate } });
    }

    // ---- Analytics (Odoo-grade) ----
    if (action === 'pipeline_report') {
      const { data: report } = await admin.from('crm_pipeline_report').select('*').order('sort_order');
      const { data: kpis } = await admin.from('crm_deal_kpis').select('*').maybeSingle();
      const won = kpis?.won_deals || 0, lost = kpis?.lost_deals || 0;
      const win_rate = (won + lost) > 0 ? Math.round((won / (won + lost)) * 1000) / 10 : null;
      return J({ ok:true, report: report || [], kpis: { ...(kpis||{}), win_rate } });
    }

    // ---- Stage move: support both names ----
    if (action === 'deal_set_stage' || action === 'deal_update') {
      const id = String(body.inquiry_id || body.id || ''); if (!id) return J({ error:'inquiry_id required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('id').eq('id', id).maybeSingle();
      if (!inq) return J({ error:'not_found' }, 404);
      const extra: Record<string, unknown> = {};
      if (body.expected_value !== undefined) extra.expected_value = num(body.expected_value);
      if (body.deal_owner !== undefined) extra.deal_owner = String(body.deal_owner).slice(0,120);
      if (body.lost_reason !== undefined) extra.lost_reason = String(body.lost_reason).slice(0,200);
      if (body.stage !== undefined) {
        const r = await applyStageMove(id, String(body.stage), who, extra);
        return r.ok ? J({ ok:true, stage: (r as any).stage?.key }) : J({ error: r.error }, 400);
      }
      if (Object.keys(extra).length) { const { error } = await admin.from('inquiries').update(extra).eq('id', id); if (error) return J({ error: error.message }, 500); return J({ ok:true, patched: Object.keys(extra) }); }
      return J({ error:'nothing to update' }, 400);
    }

    // ---- Activities: support both list names + both response keys ----
    if (action === 'activity_list' || action === 'activities_list') {
      const entity = String(body.entity || ''); const entity_id = String(body.entity_id || '');
      if (entity && entity_id) {
        if (!ENTITIES.includes(entity)) return J({ error:'bad entity' }, 400);
        const rows = await timelineFor(entity, entity_id);
        const next = rows.filter((a:any)=>!a.done && a.due_at).sort((a:any,b:any)=> new Date(a.due_at).getTime()-new Date(b.due_at).getTime())[0] || null;
        return J({ ok:true, timeline: rows, activities: rows, next_activity: next });
      }
      let q = admin.from('crm_activities').select('id,entity,entity_id,type,subject,actor,due_at,done,created_at').eq('done', false);
      if (body.overdue === true) q = q.lt('due_at', new Date().toISOString());
      const { data } = await q.not('due_at','is',null).order('due_at',{ ascending:true }).limit(200);
      return J({ ok:true, timeline: data || [], activities: data || [] });
    }
    if (action === 'activity_add') {
      const entity = String(body.entity || ''); const entity_id = String(body.entity_id || '');
      const type = ATYPES.includes(String(body.type)) ? String(body.type) : 'todo';
      const subject = String(body.subject || '').slice(0,200);
      const bodyText = String(body.body || '').slice(0,2000) || null;
      if (!ENTITIES.includes(entity) || !entity_id || (!subject && !bodyText)) return J({ error:'entity, entity_id and subject/body required' }, 400);
      const due = /^\d{4}-\d{2}-\d{2}/.test(String(body.due_at||'')) ? new Date(String(body.due_at)).toISOString() : null;
      const { error } = await admin.from('crm_activities').insert({ entity, entity_id, type, subject: subject || type, body: bodyText, actor:who, due_at:due, done:false });
      if (error) return J({ error: error.message }, 500);
      return J({ ok:true, timeline: await timelineFor(entity, entity_id) });
    }
    if (action === 'activity_done') {
      const aid = String(body.id || ''); if (!aid) return J({ error:'id required' }, 400);
      const reopen = String(body.op||'') === 'reopen';
      const { data: a } = await admin.from('crm_activities').select('entity,entity_id').eq('id', aid).maybeSingle();
      const { error } = await admin.from('crm_activities').update({ done: !reopen, done_at: reopen ? null : new Date().toISOString() }).eq('id', aid);
      if (error) return J({ error: error.message }, 500);
      if (a) return J({ ok:true, timeline: await timelineFor(a.entity, a.entity_id) });
      return J({ ok:true });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
