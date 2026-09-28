// email_triage - reads un-triaged inbound emails, classifies them, and ANSWERS the customer in the same
// thread (28 Sep 2026, customer_support). Until then it only drafted a reply for a person to send, and with
// email_triage_enabled absent it never ran at all, so a customer's mail got no answer.
//
// THE FOUNDER'S RULES (28 Sep 2026): a customer gets a reply in under a minute, and no person is brought in
// unless the customer explicitly asks for one. So, per mail:
//   1. noAutoReply (_shared/customer_mail.ts) - the founder's own mail, no-reply / verification senders,
//      calendar replies, bounces and machine-written mail are marked and never answered;
//   2. classification exactly as before (the GLM queue for an unknown sender, the settled-spam rule, the
//      draft model for a known one). THE DRAFT (ai_draft_reply) IS STILL NEVER SENT: it is written by the
//      internal model, and it stays on the row for the Inbox;
//   3. the ANSWER is customer_support's own: needsAPerson, then think() over the company knowledge (a
//      verified answer on the customer-facing route), and under the model hold a reviewed knowledge passage
//      quoted verbatim, or an honest receipt whose promise the held question's replay keeps
//      (reasoned_delivery.ts, channel 'email'). It goes out through fn_inbox_send - the Inbox's own send, now
//      threaded with In-Reply-To - and send_outbox is woken at once rather than on its 2-minute poll.
// A mail that asks for a person gets a reply saying so and a pending inbound_review for the founder's Inbox.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
import { observe } from '../_shared/observe.ts';
import { drain as drainGlm } from '../_shared/glm_judgements.ts';
import { CORROBORATION_FLOOR, defaultDeps, think, type ThinkDeps } from '../_shared/think.ts';
import { knownSenderCategory } from '../_shared/triage_known_sender.ts';
import { composeMailReply, noAutoReply } from '../_shared/customer_mail.ts';
import { isArabic, langOf } from '../_shared/chat_answers.ts';
import { needsAPerson } from '../_shared/reasoned_decisions.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
const llm = makeLlm(SONNET_FIRST, { max: 700 }); // shared OpenRouter client (Sonnet-first ladder + 25s timeout)

const SYS = `You are the inbox assistant for QuotesDone, a UAE B2B anonymous quotation marketplace (customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small reveal fee to unlock the supplier they choose; suppliers pay no commission). You triage an incoming email addressed to the company and draft a reply the founder can send.\nReturn STRICT JSON ONLY: {"category":"supplier_document|supplier_question|customer_question|complaint|billing|partnership|spam|other","summary":"one factual sentence","reply":"a short, warm, professional reply in plain text, signed 'The QuotesDone Team'. Do not invent facts, prices, or commitments. If a document was sent, acknowledge receipt and say records will be updated. If it needs info you don't have, ask politely. If it is spam, set reply to an empty string."}\nReply with JSON only, no preamble.`;

type Mail = { id: number; from_email: string | null; to_email: string | null; subject: string | null; body: string | null; owner_role: string | null; raw: Record<string, unknown> | null };

/** A reviewed passage of the company knowledge close enough to stand as the answer on its own: no model,
 *  so it works under the hold. Same floor and same routine think() retrieves with. */
async function groundedPassage(deps: ThinkDeps, q: string, lang: 'en' | 'ar'): Promise<string | null> {
  const v = await deps.embed(q, 'gte').catch(() => null);
  if (!v) return null;
  const { data } = await deps.rpc('fn_reason_retrieve', { p_seat: 'customer_support', p_embedding: '[' + v.join(',') + ']', p_k: 6 });
  const hit = (Array.isArray(data) ? data : []).find((r: { trust?: string; similarity?: number; excerpt?: string }) =>
    r.trust !== 'pending_review' && Number(r.similarity) >= CORROBORATION_FLOOR && !!r.excerpt && isArabic(String(r.excerpt)) === (lang === 'ar'));
  return hit ? String(hit.excerpt) : null;
}

/** customer_support answers the mail in its thread. Returns how it was answered. */
async function answer(m: Mail, deps: ThinkDeps): Promise<string> {
  const q = ('Subject: ' + (m.subject || '') + '\n\n' + String(m.body || '')).slice(0, 4000);
  const lang = langOf(q);
  // A fixture (@example.invalid, the ZZ DEMO convention) is never queued for the replay (think.ts isFixtureRequest).
  const subject = { message_id: m.id, channel: 'email', ...(/@example\.invalid$/i.test(String(m.from_email || '')) ? { fixture: true } : {}) };
  const person = await needsAPerson(deps, { seat: 'customer_support', surface: 'email_triage.needs_a_person', message: q,
    audience: 'customer', dedupeKey: 'email_person:' + m.id, subject });
  let text: string, how: string;
  if (person.value === true) { text = composeMailReply({ lang, person: true }); how = 'person'; }
  else {
    const r = await think(deps, { seat: 'customer_support', surface: 'email_triage.reply', stakes: 'high', dedupeKey: 'email_reply:' + m.id, subject,
      question: `Answer this e-mail to QuotesDone as its customer support, in ${lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}, plain text, `
        + 'without a greeting or a sign-off (they are added). Never name another customer or supplier, never quote an unpublished price, never promise a date.\n\n' + q,
      context: { audience: 'customer', language: lang } });
    const verified = r.status === 'answered' && r.verified?.status === 'agreed' && r.answer.trim() ? r.answer.trim() : null;
    const passage = verified ? null : await groundedPassage(deps, q, lang);
    text = composeMailReply({ lang, answer: verified, passage });
    how = verified ? 'reasoned' : passage ? 'knowledge_passage' : 'receipt';
  }
  const { data: sent, error } = await admin.rpc('fn_inbox_send', { p_id: m.id, p_body: text, p_by: 'customer_support' });
  if (error || (sent as { error?: string } | null)?.error) throw new Error('fn_inbox_send: ' + (error?.message ?? (sent as { error?: string }).error));
  // Filed AFTER the send: fn_inbox_send closes the message's open review items, and this one must stay open.
  if (how === 'person') await admin.from('agent_actions').insert({ agent: 'email', kind: 'inbound_review', status: 'pending', risk: 'low',
    title: 'Inbox: a customer asked for a person — ' + String(m.subject || '(no subject)').slice(0, 60),
    recommendation: 'The customer asked to speak to a person and was told a member of the team will reply in the same thread. Reply from the Inbox.',
    target_table: 'inbound_messages', target_id: String(m.id), detail: { from: m.from_email, reasoning: person.result.answer.slice(0, 500) } });
  return how;
}

Deno.serve(observe('email_triage', async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'email_triage');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const { data: run } = await admin.from('agent_runs').insert({ agent: 'email_triage' }).select('id').maybeSingle();
    const counts = { triaged: 0, drafted: 0, spam: 0, unknown_sender_to_glm: 0, not_answered: 0, answered: 0, answer_failed: 0 } as Record<string, number>;
    const glmIds: number[] = [];
    const deps = defaultDeps(admin, 'email_triage');
    const founder = [...String((await sec('admin_emails')) || '').split(','), String((await sec('founder_email')) || '')].map((s) => s.trim()).filter(Boolean);
    // resend_inbound names the message it just stored, so its reply does not wait for the 15-minute tick.
    let sel = admin.from('inbound_messages').select('id,from_email,to_email,subject,body,owner_role,raw')
      .eq('needs_review', true).is('triaged_at', null).is('replied_at', null).is('owner_role', null).or('ai_category.is.null,ai_category.neq.glm_queued');
    if (Number(body?.message_id) > 0) sel = sel.eq('id', Number(body.message_id));
    const { data: msgs } = await sel.order('created_at', { ascending: true }).limit(20);
    const reply1 = async (m: Mail) => {
      try { const how = await answer(m, deps); counts.answered++; counts['answered_' + how] = (counts['answered_' + how] || 0) + 1; }
      catch (e) { counts.answer_failed++; console.error('email_triage answer', m.id, String((e as Error)?.message || e)); }
    };
    for (const m of ((msgs || []) as Mail[])) {
      // 1. NEVER ANSWERED: the founder, no-reply and verification senders, calendar replies, bounces.
      const skip = noAutoReply(m, founder);
      if (skip) {
        await admin.from('inbound_messages').update({ ai_category: 'no_auto_reply', ai_summary: 'Not answered automatically: ' + skip + ' (customer_mail.ts noAutoReply).', triaged_at: new Date().toISOString() }).eq('id', m.id);
        counts.not_answered++; continue;
      }
      // AN UNKNOWN SENDER IS JUDGED ON GLM (24 Sep 2026, founder's approval; _shared/glm_judgements.ts). A sender who is
      // no lead, customer or staff address (fn_glm_sender_known, exact address) is queued for GLM 5.3 Flash (no
      // per-day limit, founder_instruction 987); known senders keep the path below unchanged. A row already queued is not queued again.
      const { data: relation, error: relErr } = await admin.rpc('fn_glm_sender_known', { p_email: String(m.from_email || '') });
      if (!relErr && !relation) {
        const { data: gid } = await admin.rpc('fn_glm_judgement_enqueue', { p_kind: 'unknown_sender_mail', p_subject_key: String(m.id),
          p_input: { message_id: m.id, from: m.from_email, subject: m.subject, body: String(m.body || '').slice(0, 4000) } });
        // Marked, so a held backlog never crowds known senders out of this run's 20; the judgement overwrites it.
        if (gid) { glmIds.push(Number(gid)); counts.unknown_sender_to_glm++; await admin.from('inbound_messages').update({ ai_category: 'glm_queued' }).eq('id', m.id).is('triaged_at', null); }
        // An unknown sender is usually a new customer: answered now, whatever GLM later files as its category.
        await reply1(m);
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
      // A SETTLED SENDER (24 Sep 2026, it_engineer): the exact from_email's own earlier triages decide spam with no model.
      const { data: prior } = await admin.from('inbound_messages').select('ai_category').eq('from_email', String(m.from_email || '')).neq('id', m.id)
        .not('triaged_at', 'is', null).order('triaged_at', { ascending: false }).limit(10);
      const settled = m.from_email ? knownSenderCategory((prior || []).map((p: any) => p.ai_category)) : null;
      if (settled) { category = settled; summary = 'Known sender: every earlier mail from this exact address was triaged spam (no model called).'; }
      const out = settled ? null : await llm(SYS, 'From: ' + (m.from_email||'') + '\nSubject: ' + (m.subject||'') + '\n\n' + String(m.body||'').slice(0, 4000) + tlText, 800);
      if (out) { const mm = out.match(/\{[\s\S]*\}/); if (mm) { try { const pj = JSON.parse(mm[0]); category = String(pj.category||'other').slice(0,40); summary = String(pj.summary||'').slice(0,500); reply = String(pj.reply||'').slice(0,4000); } catch (_e) {} } }
      const { error: markErr } = await admin.from('inbound_messages').update({ ai_category: category, ai_summary: summary, ai_draft_reply: reply || null, triaged_at: new Date().toISOString() }).eq('id', m.id);
      // An answer that cannot be recorded is paid for again on the next run (22 Sep 2026, instruction
      // 705): stop the batch rather than read the rest of the inbox into the same failing write.
      if (markErr) { if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: 'error', counts, note: 'email_triage stopped: could not record the triage of inbound message ' + m.id + ' (' + String(markErr.message).slice(0, 160) + '); continuing would re-read and re-pay for it on every run.' }).eq('id', run.id); return J({ ok: false, error: 'mark_failed', counts }, 500); }
      counts.triaged++;
      if (category === 'spam') { counts.spam++; continue; }
      if (reply) counts.drafted++;
      await reply1(m);
    }
    // THE REPLY LEAVES NOW, not on the outbox's 2-minute poll (the founder's "under a minute").
    if (counts.answered) {
      try {
        const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/send_outbox', { method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '') },
          body: JSON.stringify({ __secret: await sec('cred_fn_email_triage'), limit: 20 }) }, 30_000);
        await r.body?.cancel().catch(() => {});
      } catch (_e) { /* the 2-minute poll still sends it */ }
    }
    // Judge the unknown senders now; any held (the model hold) stay queued for resilience_ping. Never a word list.
    const glm = glmIds.length ? await drainGlm(deps, glmIds.length, glmIds) : null;
    if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status: counts.answer_failed ? 'error' : 'ok', counts: { ...counts, glm } }).eq('id', run.id);
    return J({ ok: true, counts });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
