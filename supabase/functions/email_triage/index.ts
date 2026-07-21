// email_triage - reads un-triaged inbound emails, classifies + drafts a reply (LLM), surfaces to founder. Never sends.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
async function llm(sys: string, user: string, max = 700){ const key = await sec('openrouter_api_key'); if (!key) return null; const MODELS=['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8']; for(const model of MODELS){ for(let at=0; at<2; at++){ try { const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method:'POST', headers:{ 'Authorization':'Bearer '+key, 'Content-Type':'application/json' }, body: JSON.stringify({ model, max_tokens:max, messages:[{role:'system',content:sys},{role:'user',content:user}] }) }); const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c; } catch (_e) {} } } return null; }

const SYS = `You are the inbox assistant for QuotesDone, a UAE B2B anonymous quotation marketplace (customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small reveal fee to unlock the supplier they choose; suppliers pay no commission). You triage an incoming email addressed to the company and draft a reply the founder can send.\nReturn STRICT JSON ONLY: {"category":"supplier_document|supplier_question|customer_question|complaint|billing|partnership|spam|other","summary":"one factual sentence","reply":"a short, warm, professional reply in plain text, signed 'The QuotesDone Team'. Do not invent facts, prices, or commitments. If a document was sent, acknowledge receipt and say records will be updated. If it needs info you don't have, ask politely. If it is spam, set reply to an empty string."}\nReply with JSON only, no preamble.`;

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const { data: run } = await admin.from('agent_runs').insert({ agent: 'email_triage' }).select('id').maybeSingle();
    const counts = { triaged: 0, drafted: 0, spam: 0 };
    const { data: msgs } = await admin.from('inbound_messages').select('id,from_email,subject,body')
      .eq('needs_review', true).is('triaged_at', null).is('replied_at', null).order('created_at', { ascending: true }).limit(20);
    for (const m of (msgs || [])) {
      let category = 'other', summary = '', reply = '';
      const out = await llm(SYS, 'From: ' + (m.from_email||'') + '\nSubject: ' + (m.subject||'') + '\n\n' + String(m.body||'').slice(0, 4000), 800);
      if (out) { const mm = out.match(/\{[\s\S]*\}/); if (mm) { try { const pj = JSON.parse(mm[0]); category = String(pj.category||'other').slice(0,40); summary = String(pj.summary||'').slice(0,500); reply = String(pj.reply||'').slice(0,4000); } catch (_e) {} } }
      await admin.from('inbound_messages').update({ ai_category: category, ai_summary: summary, ai_draft_reply: reply || null, triaged_at: new Date().toISOString() }).eq('id', m.id);
      counts.triaged++;
      if (category === 'spam' || !reply) { counts.spam++; }
      else {
        counts.drafted++;
        // resolve any older generic review reminder for this message
        await admin.from('agent_actions').update({ status: 'auto_done', decided_by: 'email_triage', decided_at: new Date().toISOString() }).eq('target_table', 'inbound_messages').eq('target_id', String(m.id)).in('status', ['pending','held_for_review','proposed','open']).eq('kind','sla_review');
        await admin.from('agent_actions').insert({ agent: 'email', kind: 'inbound_review', status: 'pending', risk: 'low', title: 'Inbox: ' + String(m.subject||'(no subject)').slice(0,70) + ' — ' + category, recommendation: 'Review the AI draft in the Inbox and send (or edit) it.', target_table: 'inbound_messages', target_id: String(m.id), detail: { from: m.from_email, category, summary, draft: reply } });
      }
    }
    if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'ok', counts }).eq('id', run.id);
    return J({ ok: true, counts });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
