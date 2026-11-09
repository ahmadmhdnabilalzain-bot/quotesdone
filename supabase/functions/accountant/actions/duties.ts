// accountant — the hourly duties: payouts, fees, disputes, the charge audit, the close, the mailbox check.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
// 14 Sep 2026 — the duties (founder: "yea add them all", "yea add them"). Nothing is re-implemented:
// the charge audit uses the #616 formula itself, the statement reader and the dispute form are pure
// modules with their own tests.
import { revealChargeFor, absorbedStripeCost } from '../../_shared/reveal_fee.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { reasonBankLines } from '../../_shared/reasoned_books.ts';
import { draftDisputes } from '../../_shared/dispute_draft.ts';
import { type InboundItem, type MailboxMessage, mailboxMessages } from '../../_shared/expense_mailbox.ts';
import { type ActionCtx, EXPENSE_MAILBOX, J, SUPA_URL, admin, run, sec } from '../context.ts';

export async function dutyActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── DUTIES (14 Sep 2026) ───────────────────────────────────────────────────────────────────
    // The founder: "yea add them all" and "yea add them". resilience_ping calls this every tick under
    // the seat's credential; fn_accountant_duties_due lets it run at most once in 55 minutes. This
    // action takes only the readings the database cannot take — Stripe's payouts and the balance
    // transactions behind each new one, Stripe's own fee and tax transactions, disputes, and the charge
    // audit computed with the #616 formula — and hands them to fn_accountant_duties, which decides.
    // Then it answers every dispute that is waiting and renders any closed month's PDF and CSV.
    // A reading that could not be taken is passed as 'unreadable' with its reason, never as empty.
    if (action === 'duties') {
      const { data: due } = await admin.rpc('fn_accountant_duties_due');
      if (due !== true && body.force !== true) return J({ ok: true, seat: 'accountant', skipped: 'the duties ran within the last 55 minutes' });
      const since = Math.floor(Date.now() / 1000) - 45 * 86400;
      // deno-lint-ignore no-explicit-any
      const S = async (key: string, path: string): Promise<{ ok: boolean; status: number; j: any }> => {
        const r = await fetch('https://api.stripe.com/v1/' + path, { headers: { Authorization: 'Bearer ' + key } });
        return { ok: r.ok, status: r.status, j: await r.json().catch(() => ({})) };
      };
      const keys = { live: await sec('stripe_secret_key'), test: await sec('stripe_secret_key_test') };
      const stripe: Record<string, unknown> = {};
      for (const mode of ['live', 'test'] as const) {
        const key = keys[mode];
        if (!key) { stripe[mode] = { basis: 'not_configured', reason: 'app_secrets holds no Stripe ' + mode + ' key' }; continue; }
        try {
          const po = await S(key, 'payouts?limit=100&created[gte]=' + since);
          if (!po.ok) throw new Error('GET /v1/payouts returned HTTP ' + po.status);
          const { data: known } = await admin.from('stripe_payout').select('id').not('txn_count', 'is', null);
          const have = new Set((known || []).map((r: { id: string }) => r.id));
          const payouts: Record<string, unknown>[] = [];
          for (const p of (po.j.data || []) as Record<string, unknown>[]) {
            const row: Record<string, unknown> = { ...p };
            // Stripe lists a payout's balance transactions only for automatic payouts.
            if (!have.has(String(p.id)) && p.automatic === true && p.status === 'paid') {
              let n = 0, net = 0, after = '';
              for (let page = 0; page < 20; page++) {
                const bt = await S(key, 'balance_transactions?payout=' + p.id + '&limit=100' + (after ? '&starting_after=' + after : ''));
                if (!bt.ok) break;
                const items = (bt.j.data || []) as Record<string, unknown>[];
                for (const t of items) if (t.type !== 'payout') { n++; net += Number(t.net || 0); }
                if (!bt.j.has_more || !items.length) { row.txn_count = n; row.txn_net = net; break; }
                after = String(items[items.length - 1].id);
              }
            }
            payouts.push(row);
          }
          const feeBts: unknown[] = [];
          for (const type of ['stripe_fee', 'tax']) {
            const f = await S(key, 'balance_transactions?type=' + type + '&limit=100&created[gte]=' + since);
            if (!f.ok) throw new Error('GET /v1/balance_transactions?type=' + type + ' returned HTTP ' + f.status);
            feeBts.push(...(f.j.data || []));
          }
          const dp = await S(key, 'disputes?limit=100&created[gte]=' + since);
          if (!dp.ok) throw new Error('GET /v1/disputes returned HTTP ' + dp.status);
          stripe[mode] = { basis: 'measured', payouts, fee_bts: feeBts, disputes: dp.j.data || [] };
        } catch (e) { stripe[mode] = { basis: 'unreadable', reason: String((e as Error)?.message || e) }; }
      }

      // THE CHARGE AUDIT (duty 10): expected from revealChargeFor, actual from the balance transaction.
      let chargeAudit: Record<string, unknown>[] | null = [];
      const { data: cands, error: cErr } = await admin.rpc('fn_accountant_charge_audit_candidates', { p_limit: 200 });
      if (cErr) chargeAudit = null;
      for (const c of (cands || []) as Record<string, unknown>[]) {
        let got: { ok: boolean; status: number; j: Record<string, any> } | null = null;
        for (const k of [keys.live, keys.test]) {
          if (!k) continue;
          const r = await S(k, 'payment_intents/' + encodeURIComponent(String(c.payment_ref)) + '?expand[]=latest_charge.balance_transaction');
          if (r.ok) { got = r; break; }
        }
        const pi = got?.j; const bt = pi?.latest_charge?.balance_transaction;
        if (!pi || !bt || typeof bt.amount !== 'number') continue;   // not auditable yet; re-tried next run
        const basis = pi.metadata?.fee_basis === 'domestic' ? 'domestic' : 'international';
        const exp = revealChargeFor(Number(c.quote_amount), Number(c.rate), basis);
        const actualTotal = bt.amount / 100;
        chargeAudit!.push({
          transaction_id: c.transaction_id, livemode: pi.livemode === true, basis,
          quote_amount: Number(c.quote_amount), rate: Number(c.rate),
          expected_total: exp.total_charged, expected_processing: exp.processing_fee,
          actual_total: actualTotal, actual_fee_fils: bt.fee,
          // No shortfall exists any more: the buyer pays the 3% only and QuotesDone absorbs Stripe (24 Sep 2026).
          // diff_aed (actual - expected) > 0 is the finding that matters: a buyer charged more than the 3%.
          evidence: { absorbed_stripe_cost_aed: absorbedStripeCost({ total_charged: actualTotal, actual_card_fee_fils: Number(bt.fee) }), payment_intent: pi.id, balance_transaction: bt.id, currency: bt.currency, fee_details: bt.fee_details,
                      basis_source: pi.metadata?.fee_basis ? 'payment metadata' : 'no fee_basis on the payment: the Checkout Session flow prices at the international basis' },
        });
      }

      // WHAT EACH NEW STATEMENT LINE IS, reasoned before the duties book it (decision point sql.accountant_bank_lines):
      // a line not yet reasoned has kind NULL and every booking routine skips it; under the hold it waits in the queue.
      const bankLines = await reasonBankLines(defaultDeps(admin, 'accountant'));
      const { data: out, error: dErr } = await admin.rpc('fn_accountant_duties', { p_r: { stripe, charge_audit: chargeAudit, bank_lines: bankLines } });
      if (dErr) { await run('duties', 'error', {}, 'fn_accountant_duties raised: ' + dErr.message); return J({ ok: false, error: dErr.message }, 500); }

      // DISPUTES (duty 7). SUBMITTING IS FINAL — Stripe takes one submission — so it happens in two steps
      // (review of #645): (1) the evidence is SAVED at Stripe as a draft (submit=false) the moment it is
      // assembled, and the CEO gets a review item; (2) it is submitted only when
      // fn_accountant_disputes_to_submit names a trigger: the CEO's approval, or his silence at T-24h.
      const answered: Record<string, unknown>[] = [];
      answered.push(...await draftDisputes(admin, keys));   // _shared/dispute_draft.ts; stripe_webhook runs it on charge.dispute.created too
      const { data: toSubmit } = await admin.rpc('fn_accountant_disputes_to_submit');
      for (const s of (toSubmit || []) as Record<string, any>[]) {
        const key = s.livemode ? keys.live : keys.test;
        if (!key || !s.trigger) continue;
        // The evidence is already saved on the dispute; this call only submits it.
        const r = await fetch('https://api.stripe.com/v1/disputes/' + encodeURIComponent(String(s.dispute)), {
          method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({ submit: 'true', 'metadata[submit_trigger]': String(s.trigger) }).toString(),
        });
        const j = await r.json().catch(() => ({}));
        await admin.rpc('fn_accountant_dispute_submitted', { p_id: s.dispute, p_ok: r.ok,
          p_response: r.ok ? { id: j.id, status: j.status } : null,
          p_error: r.ok ? null : 'HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 300),
          p_trigger: String(s.trigger) });
        answered.push({ dispute: s.dispute, submitted: r.ok, trigger: s.trigger });
      }

      // RENDER EVERY CLOSED MONTH THAT HAS NO DOCUMENT YET (duty 8): PDF and CSV, English.
      const rendered: Record<string, unknown>[] = [];
      const { data: pend } = await admin.from('accountant_month_close').select('month').is('rendered_at', null).order('month').limit(3);
      const cred = await sec('cred_fn_accountant');
      for (const p of (pend || []) as { month: string }[]) {
        const { data: doc, error: docErr } = await admin.rpc('fn_accountant_month_close_document', { p_month: p.month });
        if (docErr || !doc) { rendered.push({ month: p.month, error: docErr?.message || 'no document' }); continue; }
        const dd = doc as Record<string, any>;
        const folder = 'accountant/close/' + dd.month;
        const csvPath = folder + '/' + dd.name + '.csv';
        const cu = await admin.storage.from('finance-reports').upload(csvPath, new Blob([String(dd.csv)], { type: 'text/csv' }), { upsert: true });
        let pdfPath: string | null = null; let perr = '';
        if (cred) {
          try {
            const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: cred, title: dd.title, blocks: dd.blocks, bucket: 'finance-reports', folder, name: dd.name,
                                     options: { letterhead: true, strict_glyphs: true } }), signal: AbortSignal.timeout(55000) });
            const j = await r.json().catch(() => null);
            if (r.ok && j?.ok && j?.path) pdfPath = String(j.path); else perr = 'pdf_native ' + r.status;
          } catch (e) { perr = String((e as Error)?.message || e); }
        } else perr = 'cred_fn_accountant unreadable';
        if (pdfPath && !cu.error) {
          await admin.rpc('fn_accountant_month_close_attach', { p_month: p.month, p_bucket: 'finance-reports', p_pdf_path: pdfPath, p_csv_path: csvPath });
          rendered.push({ month: dd.month, pdf: pdfPath, csv: csvPath });
        } else rendered.push({ month: dd.month, error: perr || cu.error?.message });
      }

      // THE FOUNDER'S CLOSE PACK (instruction 1009, upgrade 8): one short PDF per built pack, then
      // fn_accountant_founder_close_pack_attach sends it through fn_notify_founder. A render failure is
      // recorded on the pack and retried next tick; the day-5 miss is reported by the SQL duty.
      const { data: packs } = await admin.from('accountant_founder_close_pack').select('month').is('rendered_at', null).order('month').limit(2);
      for (const p of (packs || []) as { month: string }[]) {
        const { data: doc, error: docErr } = await admin.rpc('fn_accountant_founder_close_pack_document', { p_month: p.month });
        if (docErr || !doc) { rendered.push({ close_pack: p.month, error: docErr?.message || 'no document' }); continue; }
        const dd = doc as Record<string, any>;
        let pdfPath: string | null = null; let perr = '';
        if (cred) {
          try {
            const r = await fetch(SUPA_URL + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: cred, title: dd.title, blocks: dd.blocks, bucket: 'finance-reports',
                                     folder: 'accountant/close-pack/' + dd.month, name: dd.name,
                                     options: { letterhead: true, strict_glyphs: true } }), signal: AbortSignal.timeout(55000) });
            const j = await r.json().catch(() => null);
            if (r.ok && j?.ok && j?.path) pdfPath = String(j.path); else perr = 'pdf_native ' + r.status;
          } catch (e) { perr = String((e as Error)?.message || e); }
        } else perr = 'cred_fn_accountant unreadable';
        const { data: sent, error: aErr } = await admin.rpc('fn_accountant_founder_close_pack_attach',
          { p_month: p.month, p_bucket: 'finance-reports', p_pdf_path: pdfPath, p_error: perr || null });
        rendered.push({ close_pack: dd.month, pdf: pdfPath, sent, error: aErr?.message || perr || undefined });
      }

      // FILE THE YEAR-END PACK WHEN IT FALLS DUE (duty 4 of the five further duties, 14 Sep 2026): seven CSVs
      // from the books into the private backups bucket; the attach queues them for Dropbox, and the
      // it_engineer's backup loop verifies each one arrived.
      const yearEnd: Record<string, unknown>[] = [];
      const { data: yDue } = await admin.rpc('fn_accountant_year_end_pack_due');
      if (yDue) {
        const { data: ydoc, error: yErr } = await admin.rpc('fn_accountant_year_end_pack_document', { p_year: yDue });
        if (yErr || !ydoc) yearEnd.push({ year: yDue, error: yErr?.message || 'no document' });
        else {
          const yd = ydoc as { year: number; folder: string; files: { name: string; csv: string }[] };
          const files: { name: string; bucket: string; path: string }[] = [];
          let yFail = '';
          for (const f of yd.files) {
            const p = yd.folder + '/' + f.name;
            const up = await admin.storage.from('backups').upload(p, new Blob([f.csv], { type: 'text/csv' }), { upsert: true });
            if (up.error) { yFail = f.name + ': ' + up.error.message; break; }
            files.push({ name: f.name, bucket: 'backups', path: p });
          }
          if (!yFail) {
            const { error: aErr } = await admin.rpc('fn_accountant_year_end_pack_attach', { p_year: yd.year, p_files: files });
            if (aErr) yFail = aErr.message;
          }
          yearEnd.push(yFail ? { year: yd.year, error: yFail } : { year: yd.year, files: files.length });
        }
      }

      // IS THE EXPENSES MAILBOX QUIET, OR IS THE INTAKE SILENT? (ledger 983, 24 Sep 2026, GAPS Accountant 1.)
      // One page of Resend's inbound list, newest first, the last 14 days; the verdict and findings are SQL's.
      let mailbox: unknown = null;
      {
        const rkey = await sec('resend_api_key');
        let listErr: string | null = rkey ? null : 'app_secrets.resend_api_key is unreadable';
        let msgs: MailboxMessage[] = [];
        if (rkey) {
          // The list covers every mailbox, newest first: page until a page reaches past the window, at most 10.
          const since = Date.now() - 14 * 86400000;
          try {
            let after = ''; let pages = 0;
            for (;;) {
              const r = await fetch('https://api.resend.com/emails/inbound?limit=100' + (after ? '&after=' + encodeURIComponent(after) : ''),
                { headers: { Authorization: 'Bearer ' + rkey }, signal: AbortSignal.timeout(15000) });
              // deno-lint-ignore no-explicit-any
              const j: any = await r.json().catch(() => ({}));
              if (!r.ok) { listErr = 'HTTP ' + r.status; break; }
              const items = (j.data || j.items || []) as InboundItem[];
              msgs.push(...mailboxMessages(items, EXPENSE_MAILBOX, since));
              pages++;
              const oldest = Date.parse(String(items[items.length - 1]?.created_at || ''));
              if (!j.has_more || !items.length || (Number.isFinite(oldest) && oldest < since)) break;
              if (pages >= 10) { listErr = 'more than 1,000 inbound messages in 14 days; the list was not read to the end of the window'; break; }
              after = String(items[items.length - 1].id);
            }
          } catch (e) { listErr = String((e as Error)?.message || e).slice(0, 200); }
        }
        const { data: mb, error: mbErr } = await admin.rpc('fn_accountant_mailbox_check_record', { p_messages: msgs, p_list_error: listErr });
        mailbox = mbErr ? { error: mbErr.message } : mb;
      }

      await run('duties', 'ok', { mailbox: (mailbox as Record<string, unknown>)?.verdict ?? null, bank_lines: bankLines, disputes_answered: answered.length, months_rendered: rendered.length, year_end: yearEnd.length,
        stripe_live: (stripe.live as Record<string, unknown>)?.basis, stripe_test: (stripe.test as Record<string, unknown>)?.basis });
      return J({ ok: true, seat: 'accountant', result: out, mailbox, disputes_answered: answered, months_rendered: rendered, year_end: yearEnd });
    }
}
