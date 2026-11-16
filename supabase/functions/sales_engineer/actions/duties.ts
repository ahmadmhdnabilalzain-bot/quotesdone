// sales_engineer — lead_email_check, m365_ndr_headers, spec_offer_sweep.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { leadEmailCheckBatch } from '../lead_email_check.ts';
import { admin, J, type ActionCtx } from '../context.ts';
import { specOfferSweep } from '../lib/spec_offer.ts';
import { run } from '../lib/run.ts';
import { measureNdrHeaders } from '../../_shared/m365_sent_status.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { jobQuestionsSweep } from '../../_shared/job_question.ts';
import { lossReasonsSweep } from '../../supplier_api/loss_feedback.ts';

export async function dutiesActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, caller, action } = c;
    // ── ASSIST ─────────────────────────────────────────────────────────────────────────────────
    // The portal assistant. PortalShell.tsx called site_assistant — Support's function, and correct
    // on the public homepage but wrong inside the customer portal by the founder's ruling of 9 Sep.
    //
    // NO MODEL, so the answer is RETRIEVED OR ESCALATED. fn_sales_assist reads SEVEN corpora, not
    // one: sales_knowledge (1,136), ops_knowledge (9,139), kb_chunks (2,686,026), agent_knowledge
    // (2,556, of which 1,627 are the live 'cat:' technical body), support_knowledge (408),
    // category_specs (56) and category_quote_specs (141). The first build of this handler searched
    // sales_knowledge alone — 0.042% of what the seat is entitled to — and the founder rejected the
    // refusal that produced on 9 Sep: "there is no reason for him not to know whatsoever."
    //
    // THE FLOORS DID NOT MOVE, because a nearest neighbour is ALWAYS found and an unfiltered vector
    // search answers nonsense as confidently as it answers a real question. A row that HAS an
    // embedding must clear cosine 0.86 (fn_faq_answer's number) AND match the tsvector. A row that
    // has NO embedding — 93.8% of kb_chunks, all of support_knowledge, all 1,627 'cat:' rows —
    // cannot be put to the vector floor at all, so it must clear a stricter lexical-only bar
    // instead. The lexical index is the only instrument in this estate that returns nothing for
    // nothing, which is why it gates both routes.
    //
    // WHEN NOTHING CLEARS, SOMETHING STILL HAPPENS. The refusal string is gone. The routine records
    // the question in sales_knowledge_gap (deduplicated, counted — the acquisition backlog) and
    // opens an org_tasks row owned by sales_engineer, and the asker is given the task number and
    // the owner. Which records were retrieved, how close each was and which were cited are written
    // to sales_decision_log from INSIDE the retrieval routine, so this handler cannot forget to.
    // Kicked by the duty sales_engineer.lead_email_check. Only the seat's own credential or the founder.
    if (action === 'lead_email_check') {
      if (caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const res = await leadEmailCheckBatch((fn, args) => admin.rpc(fn, args) as never);
      await run('lead_email_check', 'ok', res);
      return J({ ok: true, ...res });
    }

    // READ-ONLY (review of #1792): which stamp headers Graph returns for the delivery reports in supplier@'s mailbox that
    // answer an M365 invitation, and whether tenantStampOf would accept each. Writes nothing.
    if (action === 'm365_ndr_headers') {
      if (caller.kind !== 'service' && caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const { data, error } = await admin.from('inbound_messages').select('id,raw').like('provider_email_id', 'm365:%')
        .like('raw->>in_reply_to', '%qd-notif-%').ilike('subject', '%undeliver%').order('id').limit(25);
      if (error) return J({ ok: false, error: error.message }, 500);
      const ids = (data || []).map((r) => String((r.raw as { message_id?: string } | null)?.message_id || '')).filter(Boolean);
      const { data: mb } = await admin.from('app_secrets').select('value').eq('key', 'invite_m365_mailbox').maybeSingle();
      return J(await measureNdrHeaders({ fetchFn: (u, i) => timedFetch(u, i || {}, 15_000), env: (k) => Deno.env.get(k), mailbox: mb?.value, messageIds: ids }));
    }

    if (action === 'spec_offer_sweep') {
      if (caller.kind !== 'service' && caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const res = await specOfferSweep(Math.max(1, Math.min(50, Number(body.limit) || 20)));
      await run('spec_offer_sweep', res.errors.length ? 'error' : 'ok', { checked: res.checked, offers_opened: res.offers_opened, offers_sent: res.offers_sent, reminders: res.reminders, lapsed: res.lapsed, errors: res.errors.length },
        res.errors.length ? res.errors.slice(0, 5).join(' | ') : undefined);
      return J({ ok: true, ...res });
    }

    // THE SUPPLIER'S OPEN LOOPS (16 Nov 2026, SUPPLIER holes 5 and 9; agent SUPPLIER_W2). On the 15-minute beat: every job question
    // owed a first reading is read against the request (_shared/job_question.ts) and every reminder owed goes to the customer once;
    // every losing supplier owed a reason gets one, written by the model from the customer's word and ex-VAT facts
    // (supplier_api/loss_feedback.ts). Both lists are routines (fn_job_questions_due, fn_supplier_loss_reasons_due), so a beat that
    // finds nothing costs no model call.
    if (action === 'supplier_loops_sweep') {
      if (caller.kind !== 'service' && caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const deps = defaultDeps(admin, 'sales_engineer');
      const ask = (max: number) => async (sys: string, input: string) => (await deps.llm('synthesise', sys, input, { taskClass: 'json_extraction', seat: 'sales_engineer', max, timeoutMs: 25_000, internal: true })).content ?? null;
      const limit = Math.max(1, Math.min(20, Number(body.limit) || 8));
      const [questions, losses] = await Promise.all([
        jobQuestionsSweep(admin, ask(500), limit).catch((e) => ({ error: String((e as Error)?.message || e) })),
        lossReasonsSweep(admin, ask(400), limit).catch((e) => ({ error: String((e as Error)?.message || e) })),
      ]);
      const failed = 'error' in questions || 'error' in losses;
      await run('supplier_loops_sweep', failed ? 'error' : 'ok', {
        questions_read: 'read' in questions ? questions.read.length : 0, reminders: 'chased' in questions ? questions.chased : 0,
        reasons_written: 'written' in losses ? losses.written : 0, reasons_refused: 'refused' in losses ? losses.refused : 0 },
        failed ? [('error' in questions ? questions.error : ''), ('error' in losses ? losses.error : '')].filter(Boolean).join(' | ').slice(0, 400) : undefined);
      return J({ ok: !failed, questions, losses });
    }
}
