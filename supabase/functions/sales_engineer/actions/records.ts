// sales_engineer — conversations, report, ask_accountant.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { admin, J, type ActionCtx } from '../context.ts';
import { run } from '../lib/run.ts';

export async function recordsActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, caller, action } = c;
    // ── CONVERSATIONS ──────────────────────────────────────────────────────────────────────────
    // The founder, 14 Sep 2026: "all conversations need to be saved and the sales agent has access
    // to them at any time. just in case we needed them for any reason". Every store - email in and
    // out, WhatsApp, portal chat, clarifications, the website assistant, forms - read whole through
    // fn_conversation_record, with a link to the PDF kept in the backups bucket. A customer caller
    // reads its own record and nobody else's: the party comes from the session, never the body.
    if (action === 'conversations') {
      const contact = caller.kind === 'customer' ? 'customer:' + caller.customerId : String(body.contact || '').trim();
      const { data, error } = await admin.rpc('fn_conversation_record', { p_contact: contact, p_limit: Number(body.limit ?? 200) });
      if (error) return J({ ok: false, error: 'record_failed', detail: error.message }, 503);
      const rec = data as { messages?: Array<Record<string, unknown>> } & Record<string, unknown>;
      for (const m of (rec.messages || []).slice(0, 50)) {
        const pdf = m.pdf as { bucket?: string; path?: string } | null;
        if (pdf?.bucket && pdf.path) {
          const { data: s } = await admin.storage.from(pdf.bucket).createSignedUrl(pdf.path, 3600);
          m.pdf_url = s?.signedUrl ?? null;
        }
      }
      await run('conversations', 'ok', { messages: Array.isArray(rec.messages) ? rec.messages.length : 0 });
      return J({ seat: 'sales_engineer', ...rec });
    }

    // ── REPORT ─────────────────────────────────────────────────────────────────────────────────
    // "he does the comparison reports, he basically fill the reports for suppliers and customers
    // about jobs won / supplier ratings / customer total spend literally everything related to
    // both portals." Every figure carries its basis — true_zero / measured / unknown /
    // derived_not_earned — because three different facts print as the character 0 on this
    // database today and collapsing them would be the misinformation, not the zero.
    //
    // A CUSTOMER CALLER MAY ONLY READ ITSELF. The party is taken from the resolved session, not
    // from the body, so a portal caller cannot widen what it can see by renaming the subject.
    if (action === 'report') {
      let kind = String(body.party_kind || '').trim().toLowerCase();
      let id = String(body.party_id ?? '').trim();
      if (caller.kind === 'customer') { kind = 'customer'; id = caller.customerId; }
      if (!kind || !id) return J({ error: 'party_kind_and_party_id_required' }, 400);

      const { data, error } = await admin.rpc('fn_sales_portal_report', { p_party_kind: kind, p_party_id: id });
      if (error) return J({ ok: false, error: 'report_failed', detail: error.message }, 503);
      await run('report', 'ok', { party_kind: kind });
      return J(data);
    }

    // ── ASK_ACCOUNTANT ─────────────────────────────────────────────────────────────────────────
    // A customer asks about a charge, an invoice or a refund in the portal. The founder, 14 Sep 2026:
    // "the accountant need to be in communication back and forth with the sales agent." The portal
    // voice stays this seat's; the figures are the accountant's. The question is handed over
    // (billing.question), the accountant reads the books and hands the facts back (billing.answer), and
    // they are shown here and delivered by customer_support. No figure is composed in this file.
    if (action === 'ask_accountant') {
      const question = String(body.question || body.message || '').trim().slice(0, 1000);
      if (!question) return J({ error: 'question_required' }, 400);
      const customerId = caller.kind === 'customer' ? caller.customerId : String(body.customer_id || '');
      if (!customerId) return J({ error: 'customer_id_required' }, 400);
      const { data: hid, error: hErr } = await admin.rpc('fn_seat_handoff', {
        p_from: 'sales_engineer', p_to: 'accountant', p_type: 'billing.question', p_subject_table: 'customers',
        p_subject_id: customerId + ':' + crypto.randomUUID(),
        p_payload: { party: 'customer', customer_id: customerId, transaction_id: body.transaction_id || null, question },
      });
      if (hErr) return J({ ok: false, error: 'handoff_failed', detail: hErr.message }, 503);
      const { data: ans } = await admin.from('agent_actions').select('evidence,status')
        .eq('kind', 'handoff').eq('target_id', 'billing.answer:' + String(hid)).maybeSingle();
      await run('ask_accountant', 'ok', { handoff_id: hid, answered: ans?.status === 'done' });
      return J({ ok: true, seat: 'sales_engineer', handoff_id: hid,
        facts: (ans?.evidence as Record<string, unknown> | null)?.facts ?? [], delivered_by: 'customer_support, by email' });
    }
}
