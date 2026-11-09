// accountant — refunds: refund_request (to the CEO), execute_refunds (to Stripe).
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
// A refund sent to Stripe at a STATED amount, idempotent on a key this seat chooses, against the exact
// payment it reverses (a checkout-session reference is resolved to its payment intent first).
// deno-lint-ignore no-explicit-any
import { confirmRefundOutcome, refundIdempotencyKey, refundKey, stripeRefund } from '../../_shared/stripe_refund.ts';
import { isDemoEmail } from '../../_shared/demo_identity.ts';
import { type ActionCtx, J, admin, run, sec } from '../context.ts';

export async function refundActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── REFUND_REQUEST ─────────────────────────────────────────────────────────────────────────
    // "takes approval from CEO on refunds." (founder, 9 September 2026)
    //
    // THE SEAT PREPARES; THE CEO DECIDES. This is not a policy this file implements by declining —
    // it is a policy the DATABASE enforces and this file obeys. accountant.refund_decision carries
    // max_amount_aed = 0, so fn_agent_may_act refuses EVERY refund amount and names the route
    // 'ceo_case_decision'. That refusal is not swallowed and it is not an error: it is the
    // instruction, and it is turned into a real decision request.
    //
    // fn_ceo_request_decision IS REUSED RATHER THAN REPLACED. It already refuses without BOTH a
    // recommendation and evidence, and its refusal text is better than anything invented here, so
    // this handler does not pre-validate either one — it passes them down and returns whatever the
    // database says, verbatim. A second path to the CEO would be a second set of rules to keep in
    // step, and the one that drifted would be this one.
    if (action === 'refund_request') {
      const amount = Number(body.amount_aed);
      if (!Number.isFinite(amount) || amount <= 0) {
        return J({ error: 'amount_aed_required', note: 'A refund with no amount cannot be put to a ceiling, so it cannot be routed either.' }, 400);
      }

      const { data: mayRaw, error: mayErr } = await admin.rpc('fn_agent_may_act', {
        p_grantee_role_id: 'accountant', p_action_class: 'refund', p_amount_aed: amount,
      });
      if (mayErr) {
        await run('refund_request', 'error', { amount_aed: amount }, mayErr.message);
        return J({ ok: false, error: 'grant_check_failed', detail: mayErr.message }, 503);
      }
      const may = (mayRaw || {}) as Record<string, unknown>;

      // THE BRANCH THAT DOES NOT FIRE TODAY, and is here anyway rather than assumed away. Measured
      // 9 Sep 2026: fn_agent_may_act('accountant','refund',1) refuses with route
      // 'ceo_case_decision'. If a future ceiling ever permitted an amount, this seat still would
      // not execute the refund — refunds_api does that, after a decision — so it says exactly that
      // instead of quietly doing nothing or, worse, claiming a refund happened.
      if (may.may_act === true) {
        await run('refund_request', 'ok', { amount_aed: amount, routed: false });
        return J({
          ok: true, seat: 'accountant', routed_to_ceo: false, ...may,
          note: 'The standing grant admitted this amount, so no CEO decision was requested. This function still does not execute refunds; execution lives in refunds_api.',
        });
      }

      // THE EVIDENCE IS ASSEMBLED, NOT ASSERTED. Every field below is either something the caller
      // supplied or something just measured; nothing is inferred. If the caller supplied no
      // evidence of its own the object is still non-empty, which is deliberate: the refusal
      // fn_ceo_request_decision owes a caller is about a MISSING RECOMMENDATION, and burying that
      // behind an empty-evidence refusal would hide the more useful of the two.
      const evidence = {
        amount_aed: amount,
        currency: String(body.currency || 'AED'),
        transaction_id: body.transaction_id ?? null,
        refund_id: body.refund_id ?? null,
        customer_reason: body.reason ?? null,
        // THE REFUSAL VERBATIM, NOT A RESHAPED COPY OF IT. Measured 9 Sep 2026: on a refusal
        // fn_agent_may_act returns {may_act, reason, route} and NOTHING ELSE — `grant` and `limit`
        // exist only on the permit path. An earlier draft named those two keys anyway and recorded
        // grant: null, ceiling_aed: null into the CEO's evidence, which reads as "there is no grant
        // and no ceiling" when the truth is that the refusal does not carry them. Spreading what
        // the database actually returned cannot invent a field it did not send.
        grant_refusal: { ...may },
        prepared_by: 'accountant',
        prepared_at: new Date().toISOString(),
        ...(body.evidence && typeof body.evidence === 'object' ? body.evidence as Record<string, unknown> : {}),
      };

      const caseId = Number(body.case_id);
      const { data: reqRaw, error: reqErr } = await admin.rpc('fn_ceo_request_decision', {
        p_case_id: Number.isFinite(caseId) && caseId > 0 ? caseId : null,
        p_subject: String(body.subject || `Refund of AED ${amount} needs a CEO decision`),
        p_evidence: evidence,
        p_recommendation: String(body.recommendation ?? ''),
        p_idempotency_key: String(body.idempotency_key || `accountant-refund-${body.transaction_id ?? body.refund_id ?? amount}`),
      });
      if (reqErr) {
        await run('refund_request', 'error', { amount_aed: amount }, reqErr.message);
        return J({ ok: false, error: 'decision_request_failed', detail: reqErr.message }, 503);
      }

      const decision = (reqRaw || {}) as Record<string, unknown>;
      // The database's own refusal, returned verbatim and with its own status. It is not an
      // internal error and it is not reshaped into one.
      if (decision.ok !== true) {
        await run('refund_request', 'refused', { amount_aed: amount }, String(decision.reason || 'refused'));
        return J({ ok: false, seat: 'accountant', routed_to_ceo: false, refused_by: 'fn_ceo_request_decision', ...decision }, 400);
      }

      await run('refund_request', 'ok', {
        amount_aed: amount, routed: true,
        report_id: (decision.report as Record<string, unknown> | undefined)?.report_id ?? null,
      });
      return J({
        ok: true,
        seat: 'accountant',
        routed_to_ceo: true,
        amount_aed: amount,
        grant_refusal: evidence.grant_refusal,
        decision_request: decision,
        basis: 'fn_agent_may_act refused this amount against accountant.refund_decision (ceiling 0, the founder\'s ruling rather than a limit awaiting a number) and named the route ceo_case_decision. fn_ceo_request_decision then opened the decision with the evidence and the recommendation. No refund was executed and no case was closed: the CEO receiving it is not the CEO deciding it.',
      });
    }

    // ── EXECUTE_REFUNDS ────────────────────────────────────────────────────────────────────────
    // (1) Every refund the CEO approved and nobody has sent: to Stripe at refunds.amount_fils (which
    //     a00 holds equal to what the customer paid), then recorded through fn_refund_settle -- the
    //     webhook's own settler -- so the charge, the two messages and the CEO's re-verification follow
    //     from the one door. Held entirely while the CEO's breaker is on.
    // (2) The Stripe fixes the mismatch playbook handed this seat (refund the difference, retry once,
    //     cancel a duplicate). These run while paused: they ARE the fix.
    if (action === 'execute_refunds') {
      const { data: paused } = await admin.rpc('fn_refunds_paused');
      // THE KEY FOLLOWS THE PAYER (14 Sep 2026). Until today one stripe_secret_key (LIVE) was read here
      // and used for every refund and every fix, test payments included. Each payment is now refunded
      // with the key of the mode it was made in, and a payer this seat cannot identify is refused
      // rather than guessed (_shared/stripe_refund.ts reads the payment back and checks livemode).
      const deps = { secret: sec };
      const payerIsDemo = async (customerId: unknown, paymentRef?: unknown, stripeRefundId?: unknown): Promise<boolean | null> => {
        let cid = customerId ? String(customerId) : '';
        if (!cid && paymentRef) cid = String((await admin.from('transactions').select('customer_id').eq('payment_ref', String(paymentRef)).maybeSingle()).data?.customer_id || '');
        if (!cid && stripeRefundId) cid = String((await admin.from('refunds').select('customer_id').eq('stripe_refund_id', String(stripeRefundId)).maybeSingle()).data?.customer_id || '');
        if (!cid) return null;
        const { data: c } = await admin.from('customers').select('email').eq('id', cid).maybeSingle();
        return c ? isDemoEmail(c.email) : null;
      };
      // One refund only, when named (the e2e harness drives a single ZZ DEMO case this way and must
      // never sweep anyone else's approved refund along with it).
      const onlyRefund = body.refund_id != null ? Number(body.refund_id) : null;
      const results: Array<Record<string, unknown>> = [];
      const settle = (refund: Record<string, unknown>, pi: string) => admin.rpc('fn_refund_settle', {
        p_stripe_refund_id: String(refund.id), p_status: String(refund.status || 'processing'),
        p_amount_fils: Number(refund.amount || 0) || null, p_payment_intent: pi, p_amount_source: 'stripe_api',
      });

      if (paused !== true) {
        let aq = admin.from('refunds')
          .select('id,transaction_id,customer_id,supplier_lead_id,amount_fils,stripe_payment_intent,refund_decision_id,status')
          .not('refund_decision_id', 'is', null).in('status', ['requested', 'approved']).is('stripe_refund_id', null);
        if (onlyRefund != null) aq = aq.eq('id', onlyRefund);
        const { data: approved } = await aq.limit(20);
        for (const r of approved || []) {
          // Before Stripe, because afterwards the money is gone: the refunds guard refuses 'processing'
          // before the transaction's refund_deadline, and a refund paid but unrecordable is the worst case.
          const { data: tr } = await admin.from('transactions').select('refund_deadline').eq('id', r.transaction_id).maybeSingle();
          if (tr?.refund_deadline && Date.now() < new Date(tr.refund_deadline).getTime()) {
            results.push({ refund_id: r.id, error: 'refund_window_not_yet_open', decision_after: tr.refund_deadline }); continue;
          }
          // THE ONE DECISION (29 Sep 2026): a CEO-decided refund still 'requested' is approved here through
          // fn_refund_decide, which runs the second-seat check. The database refuses paying it from 'requested'
          // (z04_refund_approval_is_the_one_decision), so this is asked before Stripe, never after.
          if (r.status === 'requested') {
            const { data: dec, error: decErr } = await admin.rpc('fn_refund_decide', { p_refund_id: r.id, p_approve: true, p_decided_by: 'ceo' });
            if (decErr || dec?.ok !== true) { results.push({ refund_id: r.id, error: 'not_approved', decide: decErr?.message ?? dec }); continue; }
          }
          // THE SCREEN BEFORE MONEY MOVES (29 Sep 2026, founder ledger 1018). A high-severity fraud flag on the
          // customer or the supplier holds the refund for review: nothing is sent, nobody is banned, and
          // customer_support tells the customer. Fail closed: a screen that cannot answer sends nothing either.
          const { data: scr, error: scrErr } = await admin.rpc('fn_accountant_money_screen', {
            p_move: 'refund', p_ref: String(r.id), p_customer: r.customer_id ?? null, p_supplier: r.supplier_lead_id ?? null });
          if (scrErr) { results.push({ refund_id: r.id, error: 'money_screen_failed: ' + String(scrErr.message || scrErr).slice(0, 300) }); continue; }
          if (scr?.hold === true) { results.push({ refund_id: r.id, held: 'fraud_review', hold_id: scr.hold_id }); continue; }
          const demo = await payerIsDemo(r.customer_id, r.stripe_payment_intent);
          if (demo === null) { results.push({ refund_id: r.id, error: 'payer_unknown: the Stripe mode of this payment cannot be known, nothing sent' }); continue; }
          const res = await stripeRefund(deps, { demoPayer: demo, ref: String(r.stripe_payment_intent || ''), amountFils: Number(r.amount_fils), idem: refundIdempotencyKey(String(r.transaction_id)),
            metadata: { refund_id: String(r.id), transaction_id: String(r.transaction_id || ''), approved_by: 'ceo' } });
          if (!res.ok) { results.push({ refund_id: r.id, error: res.error }); continue; }
          await admin.from('refunds').update({ status: 'processing', stripe_refund_id: String(res.refund.id) }).eq('id', r.id).is('stripe_refund_id', null);
          await settle(res.refund, res.pi);
          results.push({ refund_id: r.id, stripe_refund_id: res.refund.id, status: res.refund.status, mode: res.mode });
        }
      }

      // A single named refund (the harness) never picks up anyone's incident fixes.
      const { data: fixes } = onlyRefund != null ? { data: [] } : await admin.from('agent_actions').select('id,detail')
        .eq('kind', 'handoff').eq('agent', 'accountant').eq('status', 'pending').filter('detail->>type', 'eq', 'incident.fix').limit(20);
      for (const f of fixes || []) {
        const d = (f.detail || {}) as Record<string, unknown>;
        const firstRefundId = Array.isArray(d.refund_ids) ? (d.refund_ids as string[])[0] : undefined;
        const demo = await payerIsDemo(null, d.payment_ref, firstRefundId);
        if (demo === null) {
          await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: 'the paying customer is not on record, so the Stripe mode of the payment cannot be known; nothing was sent' });
          results.push({ fix: f.id, error: 'payer_unknown' }); continue;
        }
        if (d.fix === 'refund_difference' || d.fix === 'retry_refund') {
          // ONE RAIL FOR THE PLAYBOOK TOO (PR #640 re-review, 14 Sep 2026). Until today these sent a
          // refund to Stripe under 'qd_incident_<fix>' and only recorded it afterwards; fn_refund_settle
          // then filed the top-up as an external row with no transaction, outside every per-payment
          // guard. Now the money is RESERVED on public.refunds first, through every guard on the table
          // (the window, the CEO decision, and a01's cap: never more than the customer paid), and only
          // then sent, under a key rooted in the transaction. A refusal releases the reservation.
          const txId = String(d.transaction_id || '');
          const failFix = async (why: string) => { await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: why.slice(0, 500) }); results.push({ fix: f.id, error: why }); };
          let rowId = 0, amount = 0, idem = '';
          if (d.fix === 'refund_difference') {
            const { data: rv, error: rvErr } = await admin.rpc('fn_accountant_reserves_topup',
              { p_transaction_id: txId, p_amount_fils: Number(d.amount_fils || 0), p_fix_id: f.id });
            if (rvErr || !rv?.ok) { await failFix(rvErr?.message || String(rv?.reason || 'the top-up could not be reserved')); continue; }
            rowId = Number(rv.refund_id); amount = Number(rv.amount_fils); idem = refundIdempotencyKey(txId, 'topup' + rowId);
          } else {
            rowId = Number(d.refund_id);
            const { data: rr, error: rrErr } = await admin.from('refunds').update({ status: 'processing' })
              .eq('id', rowId).eq('status', 'failed').select('amount_fils').maybeSingle();
            if (rrErr || !rr) { await failFix(rrErr?.message || 'refund #' + rowId + ' is not a failed refund that can be retried'); continue; }
            amount = Number(rr.amount_fils); idem = refundIdempotencyKey(txId, 'retry' + f.id);
          }
          const res = await stripeRefund(deps, { demoPayer: demo, ref: String(d.payment_ref || ''), amountFils: amount, idem,
            metadata: { incident_id: String(d.incident_id || ''), fix: String(d.fix), refund_id: String(rowId) } });
          // deno-lint-ignore no-explicit-any
          let sent: { refund: any; pi: string };
          if (res.ok) sent = { refund: res.refund, pi: res.pi };
          else {
            // NEVER RELEASE BLIND (re-review): a timeout or a 5xx may have moved the money. Stripe is
            // asked what exists under our key first; only a confirmed refusal releases the reservation.
            const out = await confirmRefundOutcome(deps, { demoPayer: demo, ref: String(d.payment_ref || ''), idem }, res);
            if (out.outcome === 'hold') {
              // Reservation kept and the fix left pending: the next run resends under the SAME key, so
              // Stripe returns the original refund if it exists and creates it once if it does not.
              results.push({ fix: f.id, refund_id: rowId, held: true, error: out.error }); continue;
            }
            if (out.outcome === 'release') {
              await admin.from('refunds').update({ status: d.fix === 'retry_refund' ? 'failed' : 'cancelled', failure_reason: out.error.slice(0, 500) })
                .eq('id', rowId).eq('status', d.fix === 'retry_refund' ? 'processing' : 'requested');
              await failFix(out.error); continue;
            }
            sent = { refund: out.refund, pi: out.pi };
          }
          await admin.from('refunds').update({ status: 'processing', stripe_refund_id: String(sent.refund.id) }).eq('id', rowId);
          // Recorded first, so the re-verification the completion triggers already sees this money.
          await settle(sent.refund, sent.pi);
          await admin.rpc('fn_seat_handoff_complete', { p_id: f.id, p_evidence: { stripe_refund_id: sent.refund.id, amount_fils: sent.refund.amount, status: sent.refund.status } });
          results.push({ fix: f.id, stripe_refund_id: sent.refund.id });
        } else if (d.fix === 'cancel_duplicate') {
          const ids = Array.isArray(d.refund_ids) ? (d.refund_ids as string[]).slice(1) : [];
          const k = await refundKey(deps, demo);
          if (!k.ok) { await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: k.error }); results.push({ fix: f.id, error: k.error }); continue; }
          let cancelled = 0; let lastErr = '';
          for (const rid of ids) {
            const cr = await fetch('https://api.stripe.com/v1/refunds/' + encodeURIComponent(rid) + '/cancel',
              { method: 'POST', headers: { Authorization: 'Bearer ' + k.sk } });
            const cj = await cr.json().catch(() => ({}));
            if (cr.ok) cancelled++; else lastErr = String(cj?.error?.message || cr.status);
          }
          if (ids.length && cancelled === ids.length) await admin.rpc('fn_seat_handoff_complete', { p_id: f.id, p_evidence: { cancelled: ids } });
          else await admin.rpc('fn_accountant_incident_fix_failed', { p_id: f.id, p_reason: 'Stripe would not cancel the duplicate: ' + (lastErr || 'nothing to cancel') });
          results.push({ fix: f.id, cancelled, of: ids.length });
        }
      }
      await run('execute_refunds', 'ok', { executed: results.length, paused: paused === true });
      return J({ ok: true, seat: 'accountant', paused: paused === true, results });
    }
}
