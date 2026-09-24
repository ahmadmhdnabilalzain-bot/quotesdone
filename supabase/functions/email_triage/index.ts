// email_triage - reads un-triaged inbound emails, classifies + drafts a reply (LLM), surfaces to founder. Never sends.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
import { observe } from '../_shared/observe.ts';
import { drain as drainGlm } from '../_shared/glm_judgements.ts';
import { defaultDeps } from '../_shared/think.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const llm = makeLlm(SONNET_FIRST, { max: 700 }); // shared OpenRouter client (Sonnet-first ladder + 25s timeout)

const SYS = `You are the inbox assistant for QuotesDone, a UAE B2B anonymous quotation marketplace (customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small reveal fee to unlock the supplier they choose; suppliers pay no commission). You triage an incoming email addressed to the company and draft a reply the founder can send.\nReturn STRICT JSON ONLY: {"category":"supplier_document|supplier_question|customer_question|complaint|billing|partnership|spam|other","summary":"one factual sentence","reply":"a short, warm, professional reply in plain text, signed 'The QuotesDone Team'. Do not invent facts, prices, or commitments. If a document was sent, acknowledge receipt and say records will be updated. If it needs info you don't have, ask politely. If it is spam, set reply to an empty string."}\nReply with JSON only, no preamble.`;

Deno.serve(observe('email_triage', async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'email_triage');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const { data: run } = await admin.from('agent_runs').insert({ agent: 'email_triage' }).select('id').maybeSingle();
    const counts = { triaged: 0, drafted: 0, spam: 0, unknown_sender_to_glm: 0 };
    const glmIds: number[] = [];
    const { data: msgs } = await admin.from('inbound_messages').select('id,from_email,subject,body')
      .eq('needs_review', true).is('triaged_at', null).is('replied_at', null).or('ai_category.is.null,ai_category.neq.glm_queued').order('created_at', { ascending: true }).limit(20);
    for (const m of (msgs || [])) {
      // AN UNKNOWN SENDER IS JUDGED ON GLM (24 Sep 2026, founder's approval; _shared/glm_judgements.ts). A sender who is
      // no lead, customer or staff address (fn_glm_sender_known, exact address) is queued for GLM 5.3 Flash behind its
      // daily cap; known senders keep the path below unchanged. A row already queued is not queued again.
      const { data: relation, error: relErr } = await admin.rpc('fn_glm_sender_known', { p_email: String(m.from_email || '') });
      if (!relErr && !relation) {
        const { data: gid } = await admin.rpc('fn_glm_judgement_enqueue', { p_kind: 'unknown_sender_mail', p_subject_key: String(m.id),
          p_input: { message_id: m.id, from: m.from_email, subject: m.subject, body: String(m.body || '').slice(0, 4000) } });
        // Marked, so a held backlog never crowds known senders out of this run's 20; the judgement overwrites it.
        if (gid) { glmIds.push(Number(gid)); counts.unknown_sender_to_glm++; await admin.from('inbound_messages').update({ ai_category: 'glm_queued' }).eq('id', m.id).is('triaged_at', null); }
        continue;
      }
      let category = 'other', summary = '', reply = '';
      // THE SENDER'S CASE TIMELINE (14 Sep 2026): customer_support is the only seat on email, so the
      // draft is written knowing what every seat has already done with this person. Deterministic
      // (fn_contact_timeline); a failure to read it leaves the draft ungrounded, never the mail unread.
      let tlText = '';
      try {
        const { data: tl } = await admin.rpc('fn_contact_timeline', { p_contact: String(m.from_email || ''), p_limit: 30 });
        const ev = (tl as any)?.events;
        if (Array.isArray(ev) && ev.length) tlText = '\n\nSENDER CASE TIMELINE (newest first; do not contradict it, do not promise what it shows is already done):\n' + JSON.stringify(ev).slice(0, 6000);
      } catch (_e) { tlText = ''; }
      const out = await llm(SYS, 'From: ' + (m.from_email||'') + '\nSubject: ' + (m.subject||'') + '\n\n' + String(m.body||'').slice(0, 4000) + tlText, 800);
      if (out) { const mm = out.match(/\{[\s\S]*\}/); if (mm) { try { const pj = JSON.parse(mm[0]); category = String(pj.category||'other').slice(0,40); summary = String(pj.summary||'').slice(0,500); reply = String(pj.reply||'').slice(0,4000); } catch (_e) {} } }
      const { error: markErr } = await admin.from('inbound_messages').update({ ai_category: category, ai_summary: summary, ai_draft_reply: reply || null, triaged_at: new Date().toISOString() }).eq('id', m.id);
      // An answer that cannot be recorded is paid for again on the next run (22 Sep 2026, instruction
      // 705): stop the batch rather than read the rest of the inbox into the same failing write.
      if (markErr) { if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'error', counts, note: 'email_triage stopped: could not record the triage of inbound message ' + m.id + ' (' + String(markErr.message).slice(0, 160) + '); continuing would re-read and re-pay for it on every run.' }).eq('id', run.id); return J({ ok: false, error: 'mark_failed', counts }, 500); }
      counts.triaged++;
      if (category === 'spam' || !reply) { counts.spam++; }
      else {
        counts.drafted++;
        // resolve any older generic review reminder for this message
        await admin.from('agent_actions').update({ status: 'auto_done', decided_by: 'email_triage', decided_at: new Date().toISOString() }).eq('target_table', 'inbound_messages').eq('target_id', String(m.id)).in('status', ['pending','held_for_review','proposed','open']).eq('kind','sla_review');
        await admin.from('agent_actions').insert({ agent: 'email', kind: 'inbound_review', status: 'pending', risk: 'low', title: 'Inbox: ' + String(m.subject||'(no subject)').slice(0,70) + ' — ' + category, recommendation: 'Review the AI draft in the Inbox and send (or edit) it.', target_table: 'inbound_messages', target_id: String(m.id), detail: { from: m.from_email, category, summary, draft: reply } });
      }
    }
    // Judge the unknown senders now; any held (the hold, the cap) stay queued for resilience_ping. Never a word list.
    const glm = glmIds.length ? await drainGlm(defaultDeps(admin, 'email_triage'), glmIds.length, glmIds) : null;
    if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'ok', counts: { ...counts, glm } }).eq('id', run.id);
    return J({ ok: true, counts });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
