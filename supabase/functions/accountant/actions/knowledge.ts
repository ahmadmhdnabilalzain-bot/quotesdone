// accountant — the seat's own knowledge: assist.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { recallCases } from '../../_shared/case_recall.ts';
import { type ActionCtx, J, admin, run } from '../context.ts';
import { embed } from '../lib/embed.ts';

export async function knowledgeActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // THE KNOWLEDGE HAD NO ENTRY POINT. 113 accountant records were authored, embedded and proved
    // to answer 35 of 35 questions — and nothing could reach them: fn_accountant_assist was granted
    // to nobody and called from nowhere, so the seat that owns the money could not consult its own
    // corpus. A finished capability with no entry point is indistinguishable from an absent one.
    //
    // NO MODEL RUNS HERE. The embedding is gte-small in-region (free, not a paid route), and the
    // answer is ASSEMBLED FROM CITED RECORDS, never generated. That is deliberate for a finance
    // seat: an invented VAT rate reads exactly like a correct one. If nothing clears the floor the
    // seat says so and hands off, rather than improvising an answer about somebody's tax position.
    if (action === 'assist') {
      const question = String(body.question || body.message || '').trim();
      if (!question) return J({ error: 'question_required' }, 400);

      const vec = await embed(question);
      // Past cases before the answer (23 Sep 2026): refunds, classifications, and what other seats
      // finalised on the same subject. Returned as evidence beside the knowledge.
      const memory = await recallCases(admin, { seat: 'accountant', path: 'assist', situation: question, embedding: vec, otherSeats: true });
      const { data, error } = await admin.rpc('fn_accountant_assist', {
        p_text: question,
        p_embedding: vec,
        p_min_similarity: Number(body.min_similarity ?? 0.86),
        p_min_rank: Number(body.min_rank ?? 0.05),
        p_k: Number(body.k ?? 5),
        p_min_overlap: Number(body.min_overlap ?? 0.60),
      });
      if (error) {
        await run('assist', 'error', {}, error.message);
        return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);
      }

      const r = (data || {}) as Record<string, unknown>;
      const recs = (r.records || []) as Array<Record<string, unknown>>;
      // Each passage names the record it came from AND what kind of claim it is. A finance answer
      // that does not say whether it is quoting general method, this company's own ruling, or the
      // shape of an obligation whose figures must be read from the FTA is a worse answer than one
      // that does — the corpus deliberately holds no rates, and the reply must not hide that.
      const reply = r.answered === true
        ? recs.map((x) =>
            String(x.title || '(untitled)') + '\n' +
            '[' + String(x.doc_key ?? x.id ?? 'record') +
            (x.epistemic_status ? ' · ' + String(x.epistemic_status) : '') + ']\n' +
            String(x.content)).join('\n\n')
        : String(r.handoff || 'I do not have that in my knowledge, and I will not guess at a figure. This needs to be resolved from the Federal Tax Authority\'s current publication or put to the CEO.');

      await run('assist', 'ok', {
        answered: r.answered === true,
        cited: Array.isArray(r.cited) ? r.cited.length : 0,
        refusal: r.refusal ?? null,
      });

      return J({
        ok: true,
        seat: 'accountant',
        answered: r.answered === true,
        reply,
        precedent: memory,
        cited: r.cited ?? [],
        refusal: r.refusal ?? null,
        basis: 'Retrieved from accountant_knowledge and assembled from the cited records. No model generated this text, and the corpus deliberately holds no tax rate, threshold or deadline — those are read from the Federal Tax Authority for the period concerned.',
      });
    }
}
