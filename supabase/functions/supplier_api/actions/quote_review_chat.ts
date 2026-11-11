// supplier_api — the quotation review with the sales engineer (REVIEW_ACTIONS, ./quote_review_actions.ts).
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { supabaseReviewRepo } from '../quote_review_flow.ts';
import { safeFilename, SAFE_DOCS } from '../../_shared/attachment.ts';
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { aiReply } from '../../_shared/ai_reply.ts';
import { preRevealIdentities } from '../../_shared/pre_reveal_identities.ts';
import { acceptImages } from '../../_shared/chat_images.ts';
import { quoteTerms } from '../../_shared/reasoned_suppliers.ts';
import { loadCaseContext, recordCaseExchange } from '../../_shared/case_context.ts';
// Inquiries received and the quotation review with the sales engineer (15 Sep 2026).
import { MAX_FILE, REVIEW_ACTIONS, reviewAction } from '../quote_review_actions.ts';
import { jobsIn, readWorking } from '../quote_review.ts';
import { type ActionCtx, J, admin } from '../context.ts';

export async function quoteReviewChatActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, jwt, email, body, action, handle } = c;
    // INQUIRIES RECEIVED and QUOTATIONS SUBMITTED (founder, 15 Sep 2026) — quote_review_actions.ts.
    // `self` runs this same function in-process with the caller's own session, so the conversation
    // reads the job only through `inbox` and its scrubbers, and submits only through `submit_quote`.
    if (REVIEW_ACTIONS.has(action)) {
      const self = async (b: Record<string, unknown>) => {
        const r = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify(b) }));
        return { status: r.status, json: await r.json().catch(() => ({})) };
      };
      const { data: sup } = await admin.from('leads').select('id,company_name,locale').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // The upload gate every supplier file passes: type by bytes, size, then the malware lookup.
      const scan = async (b64: string, filename: string, mime: string) => {
        const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename, allow: SAFE_DOCS, maxBytes: MAX_FILE,
          scan: { source: 'supplier_api.quote_review', subject: String(sup.id), filename, bucket: 'quote-files' } });
        if (!sc.ok) return { ok: false as const, status: sc.status, code: String(sc.body.error || 'file_refused'), message: String(sc.body.message || 'That file cannot be accepted.') };
        return { ok: true as const, bytes: sc.result.bytes, mime: sc.result.mime, name: safeFilename(filename, sc.result.mime) };
      };
      const out = await reviewAction({ sup: { id: Number(sup.id), company_name: sup.company_name ?? null, locale: SUPPLIER_LOCALE }, email, self, body, repo: supabaseReviewRepo(admin), scan,
        readTerms: async (text: string) => (await quoteTerms(defaultDeps(admin, 'supplier_api'), { text })).value,
        // The review reads the quotation the way the hold gate will (reasoned_matching.ts readQuote); held: nothing is read, every detail is asked.
        readWorking: (inq, w) => readWorking(defaultDeps(admin, 'supplier_api'), inq, w, 'review:' + inq.id + ':' + sup.id),
        // THE ENGINEER'S WORDS (rulings 1195-1197): the model writes every chat message from what the review decided, and
        // reads the supplier's next step (choose / submit) in the same call. Suppliers are always answered in English.
        voice: async (v) => {
          // THE CASE (ruling 1635, _shared/case_context.ts): the supplier's open cases on every channel and the same-matter
          // decision; aiReply then carries the case summary in its cached prefix and only the case's last turns. A step the
          // review writes without a message from them is routed on what the step is about.
          const kase = await loadCaseContext(defaultDeps(admin, 'supplier_api'), { channel: 'portal', seat: 'sales_engineer', audience: 'supplier',
            message: v.supplierMessage || v.situation.slice(0, 1500), partyId: String(sup.id), email, lang: 'en',
            dedupeKey: 'case_match:qr:' + sup.id + ':' + (v.conversation?.length ?? 0) + ':' + String(v.supplierMessage || v.kind).slice(0, 40) });
          const r = await aiReply(defaultDeps(admin, 'supplier_api'), { ...kase.reply,
            seat: 'sales_engineer', channel: 'the supplier portal quotation chat', audience: 'supplier', lang: 'en',
            message: v.supplierMessage || '(no message from them on this step: write your next message in the thread)',
            // a photo the supplier attached (already read, ruling 1177); acceptImages is the same gate the customer chat uses
            images: acceptImages(v.images, new URL(Deno.env.get('SUPABASE_URL')!).host).images,
            facts: v.situation, actions: v.actions, rateKey: 'qr:' + String(sup.id), ...(v.conversation?.length ? { conversation: v.conversation } : {}),
            // the customers on their jobs not yet revealed to them: a reply naming one is refused (pre_reveal_identities.ts)
            forbidden: await preRevealIdentities(admin, { leadId: Number(sup.id) }),
            rules: 'Plain text for the portal chat, no markdown headings. Keep every job number, figure, numbered point and button name from the facts exactly; a short numbered list is right when the facts list points.',
            // the job number is REQUIRED, not only asked for, in every message code decided (the greeting, the review, a notice,
            // the choice): said.ts jobsIn; 077cbbfc's openers for jobs 164941/164942 named none. A free answer to the
            // supplier's own question ('text') is not made to repeat it.
            must: v.kind === 'text' ? [] : jobsIn(v.situation),
            subject: /^ZZ DEMO/i.test(String(sup.company_name || '')) ? { fixture: true, supplier_id: Number(sup.id) } : { supplier_id: Number(sup.id) },
          });
          // the case summary after the message that was written (runs past the response; never awaited)
          if (r.reply) recordCaseExchange(defaultDeps(admin, 'supplier_api'), kase, { theirMessage: v.supplierMessage || '(no message from them on this step)', ourReply: r.reply,
            subject: /^ZZ DEMO/i.test(String(sup.company_name || '')) ? { fixture: true, supplier_id: Number(sup.id) } : { supplier_id: Number(sup.id) } });
          return { text: r.reply, action: r.action ?? null, outage: r.outage === true, problems: r.problems ?? [] };   // outage: OpenRouter down (1339)
        },
        // THE REVIEW RUNS OFF THE REQUEST (quote_review_flow.ts offRequest): the turn answers at once in 'reviewing',
        // and the runtime keeps the job alive after the response. The portal polls while it is reviewing.
        background: (job) => { const er = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime; if (er?.waitUntil) er.waitUntil(job); },
        // No model answer: the turn waits in sales_engineer's queue; the re-ask (_shared/reask.ts) asks the model again
        // within about a minute (another family, the refused drafts' problems named), posts the GUARDED answer into this
        // thread, and hands the turn to the seat after its last refused attempt. context.turn_id makes each turn its own
        // question (the same words in two threads were one qhash, and a failed one swallowed the other in fn_reason_hold).
        hold: async (v) => {
          const subject = { channel: 'portal', review_id: v.reviewId, supplier_id: Number(sup.id) };
          const q = (v.supplierMessage || '(the next message in the thread)').slice(0, 4000);
          await admin.rpc('fn_reason_hold', { p_seat: 'sales_engineer', p_surface: 'supplier_api.quote_review_unwritten', p_question: q,
            p_request: { seat: 'sales_engineer', surface: 'supplier_api.quote_review_unwritten', subject, research: false,
              question: `Write the sales engineer's next message in this supplier's quotation thread, in English. ${v.outage ? 'They were told we received their message.' : 'They have not had a reply yet.'}

WHAT THE REVIEW DECIDED (facts):
${v.situation.slice(0, 3000)}

THEIR MESSAGE:
${q}`,
              context: { audience: 'supplier', language: 'en', turn_id: 'qr:' + v.reviewId + ':' + q.slice(0, 40) },
              reask: { message: q, facts: v.situation.slice(0, 3000), audience: 'supplier', lang: 'en', channel: 'the supplier portal quotation chat', problems: (v.problems ?? []).slice(0, 12) } },
            p_plan: {}, p_subject: subject, p_reason: v.why, p_dedupe_key: 'qr_unwritten:' + v.reviewId + ':' + q.slice(0, 40) });
        } });
      return J(out.json, out.status);
    }
}
