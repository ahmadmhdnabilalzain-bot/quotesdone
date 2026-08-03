// ea_meeting_summary - the Executive Assistant's meeting note-taker. Turns a transcript/notes into a structured
// summary + decisions + action items, stores it in ea_meetings, and creates tracked tasks (crm_tasks) for the
// action items. Internal use; drafts/records only — never sends anything externally.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const llm = makeLlm(SONNET_FIRST, { max: 1600, temperature: 0.2 });
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t:string){ let s=String(t||'').trim(); const f=s.match(/```(?:json)?\s*([\s\S]*?)```/i); if(f)s=f[1]; try{return JSON.parse(s);}catch{} const m=s.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return null; }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'ea_meeting_summary');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const title = String(body.title || 'Meeting');
    const attendees = Array.isArray(body.attendees) ? body.attendees : [];
    let text = String(body.text || body.transcript || '').trim();
    if (!text || text.length < 60) return J({ error: 'no_transcript', note: 'Provide {text} or {transcript} of the meeting.' });
    if (text.length > 60000) text = text.slice(0, 60000);
    const sys = 'You are an executive assistant summarising a meeting for a busy UAE startup founder. Be concise and practical. Return STRICT JSON only: {"summary": string (4-6 sentences), "decisions": string[], "action_items": [{"task": string, "owner": string, "due": string|null}], "follow_ups": string[]}. Owner defaults to "founder" if unclear. Do not invent commitments not in the text.';
    const usr = 'MEETING: '+title+'\nATTENDEES: '+attendees.join(', ')+'\n\nTRANSCRIPT/NOTES:\n"""\n'+text+'\n"""';
    const key = await sec('openrouter_api_key'); if (!key) return J({ error:'ai_unavailable' });
    let parsed:any=null; let used='';
    { const c=(await llm(sys, usr, 1600))||''; const p=parseJson(c); if(p){parsed=p;used=SONNET_FIRST[0];} }
    if (!parsed) return J({ error:'llm_failed' });
    const { data: mrow } = await admin.from('ea_meetings').insert({ title, meeting_at: body.meeting_at || new Date().toISOString(), attendees, summary: parsed.summary, decisions: parsed.decisions||[], action_items: parsed.action_items||[], source:'ea_meeting_summary' }).select('id').single();
    let tasks = 0;
    for (const ai of (parsed.action_items||[])) {
      const tt = String(ai.task||'').trim(); if (!tt) continue;
      const dueRaw = String(ai.due||'').trim();
      const dueDate = /^\d{4}-\d{2}-\d{2}/.test(dueRaw) ? dueRaw.slice(0,10) : null;
      const detail = 'From meeting: '+title + (ai.owner?(' — owner: '+ai.owner):'') + (dueRaw && !dueDate ? (' — due: '+dueRaw) : '');
      const { error } = await admin.from('crm_tasks').insert({ title: tt, detail, status:'open', priority:'medium', source:'ea:meeting', entity:'meeting', entity_id: String(mrow?.id||''), due_date: dueDate });
      if (!error) tasks++;
    }
    return J({ ok:true, meeting_id: mrow?.id, model: used, summary: parsed.summary, decisions: parsed.decisions, action_items: parsed.action_items, tasks_created: tasks });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
