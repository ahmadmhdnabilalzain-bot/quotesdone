// customer_api — the paid reveal and its refund: reveal, request_refund.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { revealCharge } from '../../_shared/reveal_fee.ts';
// One door decides whether a supplier may be revealed, and one predicate decides whether a quote is
// complete enough to be listed, ranked or revealed (customer-portal audit CP-01 / CP-09).
import { canReveal } from '../../_shared/reveal_guard.ts';
import { type ActionCtx, J, admin } from '../context.ts';
import { getCfg, refundRef } from '../lib/pricing.ts';
import { jobProblem } from '../job_problem.ts';

export async function revealActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, cust } = c;
    if (action === 'reveal') {
      const cfg = await getCfg(); const qid = String(body.quote_id || '');
      // ONE GUARD FOR EVERY REVEAL DOOR (_shared/reveal_guard.ts, audit CP-01 / CP-09). Ownership,
      // the quote's own status, the request's status, the sanctions ban (instruction 516 — a
      // customer must never pay to be handed a permanently closed party) and the completeness hold
      // are decided there, so stripe_checkout and stripe_confirm cannot check something different.
      const gate = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });
      if (!gate.ok) return J({ ok: false, error: gate.error, code: gate.code, message: gate.message, message_ar: gate.message_ar }, gate.status);
      const q = gate.quote;
      if (gate.already_revealed) { const { data: sup } = await admin.from('leads').select('company_name,phone,whatsapp,email,website,emirate').eq('id', q.supplier_id).maybeSingle(); return J({ ok: true, already_revealed: true, supplier: sup /* rulings 1228/1229: the customer only ever gets our template quotation as a PDF, never the supplier's own file */ }); }
      // The breakdown the confirm dialog prints is the one stripe_checkout charges: one module.
      // No readable rate, no price and no payment: never a guessed 3% (./reveal_rate.ts; getCfg filed the finding).
      if (!cfg) return J({ ok: false, error: 'reveal_rate_unavailable', code: 'reveal_rate_unavailable', message: 'Card payments are briefly unavailable. Your quotes are safe — please try again shortly.', message_ar: 'الدفع بالبطاقة غير متاح مؤقتًا. عروضك محفوظة — يُرجى المحاولة بعد قليل.' }, 503);
      const ch = revealCharge(Number(q.quote_amount), Number(cfg.standard_reveal_rate));
      return J({ ok: true, payment_required: true, quote_id: qid, quote_amount: q.quote_amount, reveal_fee: ch.base_fee, processing_fee: ch.processing_fee, total_charged: ch.total_charged, currency: 'AED' });
    }

    if (action === 'request_refund') {
      const qid = String(body.quote_id || '');
      const { data: tx } = await admin.from('transactions').select('id,customer_id').eq('quote_id', qid).maybeSingle();
      if (!tx || tx.customer_id !== cust.id) return J({ error: 'Transaction not found' }, 404);
      // ONE DOOR, ONE TRANSACTION (14 Sep 2026). Until today this action flipped the sale to
      // 'requested' first, then tried to open the case, threw the refusal away and told the customer
      // "received" anyway: e2e run 7 left a sale reading "requested" with no case, no handoff to the
      // accountant and no decision coming. Every check, the case, the sale's status and the
      // confirmation in the customer's registered language now happen inside
      // fn_refund_open_from_customer, or none of them do. The published terms let a customer complain
      // "at any time"; the five working days govern when the CEO may decide, not when they may ask.
      // 16 Nov 2026 (AFTER_REVEAL): the door names its channel; "the supplier is not responding" is also his word on contact,
      // read by the ladder beside the supplier's click (fn_reveal_contact_record inside the routine).
      const { data: rf, error: rfErr } = await admin.rpc('fn_refund_open_from_customer', { p_transaction_id: tx.id, p_requested_by: 'customer', p_channel: 'portal' });
      if (rfErr || !rf) {
        // NOT A POLICY REFUSAL: the one transaction rolled back (a guard, the confirmation handoff, the
        // database). The customer's claim is not lost -- they are told to try again -- but somebody must
        // see it, so it is an IT finding keyed on the sale (reopened, not duplicated, on a repeat).
        try {
          await admin.rpc('fn_it_engineer_finding_upsert', {
            p_issue_key: 'refund:request_failed:' + tx.id,
            p_title: 'A customer could not open a refund case: the request rolled back',
            p_where: 'customer_api request_refund -> public.fn_refund_open_from_customer',
            p_blast: 'customer_facing', p_affected: 1,
            p_evidence: { transaction_id: tx.id, customer_id: cust.id, error: String(rfErr?.message || 'no answer').slice(0, 600), at: new Date().toISOString() },
            p_raised_by: 'customer_api',
          });
        } catch (_e) { /* the finding is best-effort; the customer's answer below is not */ }
        return J({ ok: false, error: 'refund_request_failed', code: 'refund_request_failed', detail: rfErr?.message || 'no answer' }, 500);
      }
      const msg = rf.locale === 'ar' ? rf.message_ar : rf.message_en;
      if (!rf.ok) return J({ ok: false, error: rf.code, code: rf.code, message: msg, can_claim_later: rf.can_claim_later ?? null }, 400);
      return J({ ok: true, refund_status: 'requested', refund_id: rf.refund_id, refund_ref: refundRef(rf.refund_id),
        duplicate: rf.duplicate === true, decision_after: rf.decision_after ?? null, message: msg });
    }

    // "A PROBLEM WITH THIS JOB" (16 Nov 2026, AFTER_REVEAL): the one door every channel shares (../job_problem.ts). The model reads
    // what he wrote beside the revealed quotation; the refund button above stays for the plain "the supplier is not responding".
    if (action === 'job_problem') {
      const r = await jobProblem({
        saleOfQuote: async (quoteId) => {
          const { data } = await admin.from('transactions').select('id,customer_id,revealed_at').eq('quote_id', quoteId).maybeSingle();
          return data ? { id: String(data.id), customer_id: String(data.customer_id), revealed_at: data.revealed_at ?? null } : null;
        },
        door: async (args) => { const { data, error } = await admin.rpc('fn_customer_after_reveal_message', args); return { data, error }; },
      }, String(cust.id), body);
      return J(r.body, r.status);
    }
}
