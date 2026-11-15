// accountant — reconciliation against what was paid and banked: reveal_reconcile, bank_statement.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
// 3 Nov 2026 — a paid reveal with no sale is found and recorded within the hour (action 'reveal_reconcile').
import { recordRevealSale } from '../../_shared/reveal_sale.ts';
import { clampDays, reportable, sweepReveals, type Mode } from '../../_shared/reveal_reconcile.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { chargeFacts, chargePaidAt } from '../../_shared/charge_facts.ts';
import { readStatement } from '../../_shared/bank_statement_parse.ts';
import { type ActionCtx, J, admin, run, sec } from '../context.ts';

export async function reconcileActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── REVEAL_RECONCILE: a paid reveal with no sale is found and recorded (3 Nov 2026) ───────────
    // The seat duty accountant.reveal_reconcile (scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql)
    // calls this every hour with its run id. The sweep is _shared/reveal_reconcile.ts: Stripe's paid reveal invoices
    // and PaymentIntents of the last N days against transactions, each one missing recorded through recordRevealSale.
    // Both keys are swept. A test-mode payment is recorded only when its quote belongs to a demo account (the rule
    // stripe_webhook's testEventIsDemo applies); any other is outcome 'test_mode_not_demo', a finding, never a ledger row.
    if (action === 'reveal_reconcile') {
      const runId = Number.isSafeInteger(Number(body.run_id)) && Number(body.run_id) > 0 ? Number(body.run_id) : null;
      const days = clampDays(body.days ?? 30);
      const keys: Record<Mode, string | undefined> = { live: await sec('stripe_secret_key'), test: await sec('stripe_secret_key_test') };
      // deno-lint-ignore no-explicit-any
      const S = async (mode: Mode, path: string): Promise<any | null> => {
        try {
          const r = await timedFetch('https://api.stripe.com/v1/' + path, { headers: { Authorization: 'Bearer ' + keys[mode] } });
          return r.ok ? await r.json().catch(() => null) : null;
        } catch (_e) { return null; }
      };
      const modes = (['live', 'test'] as Mode[]).filter((m) => keys[m]);
      let swept;
      try {
        swept = await sweepReveals({
          modes,
          list: async (mode, path) => { const j = await S(mode, path); return j && Array.isArray(j.data) ? { data: j.data, has_more: j.has_more === true } : null; },
          invoicePayment: async (mode, id) => {
            const j = await S(mode, 'invoice_payments?invoice=' + encodeURIComponent(id));
            const list = ((j?.data || []) as { status?: string; payment?: { payment_intent?: unknown } }[]).filter((x) => x?.payment?.payment_intent);
            const p = (list.find((x) => x.status === 'paid') || list[0])?.payment?.payment_intent as string | { id: string } | undefined;
            return p ? String(typeof p === 'string' ? p : p.id) : null;
          },
          readPayment: async (mode, pi) => {
            const j = await S(mode, 'payment_intents/' + encodeURIComponent(pi) + '?expand[]=latest_charge.balance_transaction');
            if (!j?.id) return null;
            const bt = j.latest_charge?.balance_transaction;
            return { status: String(j.status), amount_received: Number(j.amount_received || 0), amount_refunded: Number(j.latest_charge?.amount_refunded || 0),
              fee_fils: typeof bt?.fee === 'number' ? bt.fee : null, fee_details: bt?.fee_details ?? null, facts: chargeFacts(j, bt) };
          },
          findTransactions: async (q) => {
            const cols = 'id,quote_id,payment_ref,stripe_invoice_id';
            // 100 ids a request: a 30-day window of every paid reveal would otherwise be one URL of many kilobytes.
            const chunks = (xs: string[]) => Array.from({ length: Math.ceil(xs.length / 100) }, (_, i) => xs.slice(i * 100, i * 100 + 100));
            const parts = [];
            for (const [col, ids] of [['stripe_invoice_id', q.invoices], ['payment_ref', q.refs], ['quote_id', q.quotes]] as const) {
              for (const part of chunks(ids)) parts.push(await admin.from('transactions').select(cols).in(col, part));
            }
            const bad = parts.find((p) => p.error);
            // An unread book is not an empty book: recording against it could write a second sale.
            if (bad?.error) throw new Error('transactions could not be read: ' + bad.error.message);
            const seen = new Map<string, { id: string; quote_id: string | null; payment_ref: string | null; stripe_invoice_id: string | null }>();
            for (const p of parts) for (const t of (p.data || []) as { id: string; quote_id: string | null; payment_ref: string | null; stripe_invoice_id: string | null }[]) seen.set(String(t.id), { ...t, id: String(t.id) });
            return [...seen.values()];
          },
          isDemoQuote: async (quoteId) => {
            const { data: q } = await admin.from('quotes').select('inquiry_id').eq('id', quoteId).maybeSingle();
            if (!q?.inquiry_id) return false;
            const { data } = await admin.rpc('fn_inquiry_is_demo', { p_inquiry: q.inquiry_id });
            return data === true;
          },
          record: (a) => recordRevealSale(admin, a),
          // What Stripe kept, write-once, exactly as stripe_webhook's recordStripeFee: fn_gl_sync_business books it to 6100.
          recordFee: async (txId, feeFils, details, facts) => {
            await admin.from('transactions').update({ stripe_fee_fils: feeFils, stripe_fee_details: details }).eq('id', txId).is('stripe_fee_fils', null);
            // 13 Nov 2026: the charge's facts and paid time, then the accountant's check of the healed sale (as stripe_webhook does)
            if (facts && Object.keys(facts).length) await admin.from('transactions').update(facts).eq('id', txId).is('stripe_amount_received_fils', null);
            await admin.rpc('fn_accountant_reconciles_reveal', { p_tx: txId, p_from_handler: false });
          },
        }, { days, nowSec: Math.floor(Date.now() / 1000), maxPages: 5, maxRecords: 25, maxAttempts: 50, graceSeconds: 900 });
      } catch (e) {
        const msg = String((e as Error)?.message || e).slice(0, 300);
        await admin.rpc('fn_accountant_reveal_reconcile_record', { p_run_id: runId, p_r: { days, error: msg, modes: {}, outcomes: [] } });
        await run('reveal_reconcile', 'error', { run_id: runId }, 'the reveal sweep stopped: ' + msg);
        return J({ ok: false, error: msg }, 500);
      }
      for (const m of ['live', 'test'] as Mode[]) if (!keys[m]) swept.modes[m] = { basis: 'not_configured', invoices: 0, payment_intents: 0, truncated: false, reason: 'app_secrets holds no Stripe ' + m + ' key' };
      const { data: out, error: rErr } = await admin.rpc('fn_accountant_reveal_reconcile_record', { p_run_id: runId,
        p_r: { days, modes: swept.modes, checked: swept.checked, too_recent: swept.too_recent, outcomes: reportable(swept.outcomes) } });
      // STRIPE'S FIGURES, READ AGAIN (13 Nov 2026, review item 4). A sale whose card fee, amount or paid time Stripe did not
      // give at the payment, or whose exception the CEO asked to investigate, is read from Stripe here every hour: the
      // figures and the paid time are written once each, the objects kept as the check's snapshot, and the accountant's
      // check runs again (public.fn_accountant_payment_check_snapshot). Bounded: 25 a run, oldest first.
      const reread: Record<string, number> = { read: 0, unreadable: 0 };
      try {
        const { data: due } = await admin.rpc('fn_accountant_payment_checks_to_read', { p_limit: 25 });
        for (const d of (due || []) as { transaction_id: string; payment_ref: string | null; stripe_invoice_id: string | null; livemode: boolean | null; reason: string }[]) {
          if (!/^pi_/.test(String(d.payment_ref || ''))) { reread.unreadable++; continue; }
          // MODE UNKNOWN (a row an older deploy wrote, or no evidence at the backfill): asked of the live key first, then the
          // test key; a PaymentIntent exists in one mode only, and Stripe's own livemode is then written once.
          const modes: Mode[] = d.livemode === null ? ['live', 'test'] : [d.livemode ? 'live' : 'test'];
          let mode: Mode = modes[0];
          // deno-lint-ignore no-explicit-any
          let j: any = null;
          for (const m of modes) {
            if (!keys[m]) continue;
            j = await S(m, 'payment_intents/' + encodeURIComponent(String(d.payment_ref)) + '?expand[]=latest_charge.balance_transaction');
            if (j?.id) { mode = m; break; }
          }
          const bt = j?.latest_charge?.balance_transaction;
          if (!j?.id) { reread.unreadable++; continue; }
          if (d.livemode === null && typeof j.livemode === 'boolean') await admin.from('transactions').update({ livemode: j.livemode }).eq('id', d.transaction_id).is('livemode', null);
          if (typeof bt?.fee === 'number') await admin.from('transactions').update({ stripe_fee_fils: bt.fee, stripe_fee_details: bt.fee_details || null }).eq('id', d.transaction_id).is('stripe_fee_fils', null);
          const facts = chargeFacts(j, bt);
          if (Object.keys(facts).length) await admin.from('transactions').update(facts).eq('id', d.transaction_id).is('stripe_amount_received_fils', null);
          const paidAt = chargePaidAt(j, bt);
          if (paidAt) await admin.from('transactions').update({ paid_at: paidAt, paid_at_source: 'stripe' }).eq('id', d.transaction_id).is('paid_at', null);
          const inv = d.stripe_invoice_id ? await S(mode, 'invoices/' + encodeURIComponent(d.stripe_invoice_id)) : null;
          await admin.rpc('fn_accountant_payment_check_snapshot', { p_tx: d.transaction_id, p_snapshot: {
            read_for: d.reason, payment_intent: { id: j.id, status: j.status, amount: j.amount, amount_received: j.amount_received, currency: j.currency, livemode: j.livemode },
            charge: j.latest_charge ? { id: j.latest_charge.id, created: j.latest_charge.created, amount_refunded: j.latest_charge.amount_refunded, disputed: j.latest_charge.disputed } : null,
            balance_transaction: bt ? { id: bt.id, amount: bt.amount, fee: bt.fee, net: bt.net, currency: bt.currency, created: bt.created } : null,
            invoice: inv?.id ? { id: inv.id, number: inv.number, status: inv.status, total: inv.total, amount_paid: inv.amount_paid, currency: inv.currency } : null } });
          reread.read++;
        }
      } catch (_e) { reread.unreadable++; }
      const tally: Record<string, number> = {};
      for (const o of swept.outcomes) tally[o.outcome] = (tally[o.outcome] || 0) + 1;
      await run('reveal_reconcile', rErr ? 'error' : 'ok', { run_id: runId, days, checked: swept.checked, ...tally, stripe_reread: reread.read, stripe_reread_unreadable: reread.unreadable },
        rErr ? 'fn_accountant_reveal_reconcile_record raised: ' + rErr.message : undefined);
      // The result names counts and ids only: this endpoint answers every caller holding the seat's credential.
      return rErr ? J({ ok: false, error: rErr.message, outcomes: tally }, 500) : J({ ok: true, seat: 'accountant', outcomes: tally, result: out });
    }

    // ── BANK_STATEMENT: a statement handed in directly (CSV export or text) ───────────────────────
    if (action === 'bank_statement') {
      const src = String(body.source_ref || '').trim();
      if (!src) return J({ ok: false, error: 'source_ref is required' }, 400);
      const st = readStatement(String(body.csv || body.text || ''));
      const lines = st.lines;
      // A statement that prints its closing balance and adds up supplies closing_balance_aed / balance_on
      // itself (#659's field names) unless the caller gave them. One that does not add up supplies none.
      if (!st.problem && st.closing_balance_aed !== null && (body.closing_balance_aed === undefined || body.closing_balance_aed === null)) {
        body.closing_balance_aed = st.closing_balance_aed;
        body.balance_on = body.balance_on ?? st.period_to;
      }
      const { data, error } = await admin.rpc('fn_accountant_bank_statement_ingest', {
        p_account: String(body.account || 'mashreq'), p_source_ref: src,
        p_statement_month: body.month ?? (st.period_from ? st.period_from.slice(0, 8) + '01' : null),
        p_lines: lines, p_doc_path: null,
        p_note: st.problem ? 'handed in, and it does not add up, so none of it was booked: ' + st.problem
              : lines.length ? null : 'handed in, and no line could be read without guessing a sign' });
      if (error) return J({ ok: false, error: error.message }, 400);
      // The closing balance the statement prints (duty 1 of the five further duties): the CEO's cash and
      // runway read it. Only as printed, never worked out from the lines.
      let balance: unknown = null;
      if (body.closing_balance_aed !== undefined && body.closing_balance_aed !== null) {
        const { data: b, error: bErr } = await admin.rpc('fn_accountant_bank_balance_record', {
          p_source_ref: src, p_balance_aed: Number(body.closing_balance_aed), p_on: body.balance_on ?? null });
        if (bErr) return J({ ok: false, error: bErr.message, lines: lines.length }, 400);
        balance = b;
      }
      await run('bank_statement', 'ok', { lines: lines.length, closing_balance: balance !== null });
      return J({ ok: true, ...(data as Record<string, unknown>), closing_balance: balance });
    }
}
