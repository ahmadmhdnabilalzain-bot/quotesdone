// sales_engineer — the customer's own quotes, given to the model as facts.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { NOT_LIVE_QUOTE_IN } from '../../_shared/quote_live.ts';
import { supplierLabel } from '../../_shared/quote_documents.ts';
import { type QuoteForAnswer } from '../../_shared/chat_answers.ts';
import { admin } from '../context.ts';
import { ctxOfQuote, generaliseQuoteTerms, generaliseText } from '../../_shared/quote_generalise.ts';
import { requestOf, reviewNotes } from '../../_shared/quote_review_notes.ts';
import { itemsByQuote } from '../../_shared/reveal_guard.ts';

// THE CUSTOMER'S OWN QUOTES, GIVEN TO THE MODEL AS FACTS. Scoped through inquiries to
// the resolved customer; drafts are never a quote the customer can see. The supplier label is the
// compare table's letter (live quotes by ascending price) unless a transactions row proves the
// reveal was paid — the same rule customer_api.letterOf applies, so the chat cannot name a
// supplier the quote PDF would not.
export async function answerFromOwnQuotes(customerId: string, message: string, lang: 'en' | 'ar') {
  try {
    const { data: inqs } = await admin.from('inquiries').select('id,rfq_no,category,summary,status,spec,boq').eq('customer_id', customerId).order('created_at', { ascending: false }).limit(50);
    const ids = (inqs || []).map((i: { id: string }) => i.id);
    // THE ACCOUNT ITSELF IS A FACT (browser proof, 2 Nov 2026): "what can you see in my account?" was answered "I can't see your
    // account" because only quotes were given, and nothing at all to a customer with a request and no quote yet, or with no request.
    if (!ids.length) return { facts: JSON.stringify({ requests: [], note: 'This customer has posted no request yet.' }) };
    const [{ data: qs }, { data: tx }] = await Promise.all([
      admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,status,exclusions,scope,conditions,warranty,lead_time,payment_terms,validity,notes,committed_items,created_at')
        .in('inquiry_id', ids).not('status', 'in', NOT_LIVE_QUOTE_IN).order('quote_amount', { ascending: true }).limit(60),
      admin.from('transactions').select('inquiry_id,supplier_id').eq('customer_id', customerId).not('revealed_at', 'is', null),
    ]);
    if (!qs || !qs.length) return { facts: JSON.stringify({ requests: (inqs || []).slice(0, 15).map((i: { rfq_no: string | null; category: string | null; summary: string | null; status: string | null }) => ({ rfq_no: i.rfq_no, category: i.category, summary: i.summary, status: i.status, quotes_received: 0 })), quotes: [], note: 'No quote has arrived yet on any request.' }).slice(0, 6000) };
    const revealed = new Set((tx || []).map((t: { inquiry_id: string; supplier_id: number }) => t.inquiry_id + ':' + t.supplier_id));
    const revealedIds = [...new Set((qs as Array<{ inquiry_id: string; supplier_id: number }>).filter((q) => revealed.has(q.inquiry_id + ':' + q.supplier_id)).map((q) => q.supplier_id))];
    const names = new Map<number, string>();
    if (revealedIds.length) {
      const { data: leads } = await admin.from('leads').select('id,company_name').in('id', revealedIds);
      for (const l of leads || []) names.set(Number(l.id), String(l.company_name || ''));
    }
    // BEFORE THE REVEAL THE CHAT NAMES NO BRAND, MODEL OR PRODUCT LINE EITHER (founder ledger 1589, 10 Nov 2026). These
    // facts went to the reply model verbatim — scope, notes, exclusions and the committed lines — so "which brand is
    // Supplier B?" could be answered with the make. An unrevealed quote's words are generalised here, against its own
    // lines' brand / model values and its supplier's name (read for that only, never given), and each quote carries
    // the sales engineer's notes on it against the request (ledger 1588), so the chat answers from the same review.
    const allSup = [...new Set((qs as Array<{ supplier_id: number }>).map((q) => q.supplier_id).filter((x) => x != null))];
    const ownName = new Map<number, string>();
    if (allSup.length) { const { data: ls } = await admin.from('leads').select('id,company_name').in('id', allSup); for (const l of ls || []) if (l.company_name) ownName.set(Number(l.id), String(l.company_name)); }
    const lineRows = await itemsByQuote(admin, (qs as Array<{ id: string }>).slice(0, 15).map((q) => String(q.id))).catch(() => ({} as Record<string, any[]>));
    const byInq = new Map<string, { rfq_no: string | null; category: string | null; summary: string | null }>((inqs || []).map((i: any) => [i.id, i]));
    const letterIdx = new Map<string, number>();
    const quotes: QuoteForAnswer[] = (qs as any[]).map((q) => {
      const n = letterIdx.get(q.inquiry_id) ?? 0; letterIdx.set(q.inquiry_id, n + 1);
      const inq = byInq.get(q.inquiry_id);
      const name = revealed.has(q.inquiry_id + ':' + q.supplier_id) ? names.get(Number(q.supplier_id)) : '';
      const items = Array.isArray(q.committed_items)
        ? q.committed_items.map((it: any) => [it?.description ?? it?.item ?? it?.name, it?.spec ?? it?.specification, it?.qty != null ? String(it.qty) + ' ' + String(it?.unit ?? '') : null].filter(Boolean).join(' — ')).join('\n')
        : null;
      const lines = lineRows[String(q.id)] || [];
      const sname = ownName.get(Number(q.supplier_id));
      const ctx = ctxOfQuote([...lines, ...(Array.isArray(q.committed_items) ? q.committed_items : [])], sname ? [sname] : []);
      const t = name ? q : generaliseQuoteTerms(q, ctx);
      let review: string[] | undefined;
      try { const ns = reviewNotes({ request: requestOf(inq), quote: q, lines, supplierNames: sname ? [sname] : [] }); review = ns.length ? ns.map((x) => (lang === 'ar' ? x.ar : x.en)) : undefined; } catch (_e) { review = undefined; }
      return {
        id: String(q.id), rfq_no: inq?.rfq_no ?? null, inquiry_category: inq?.category ?? null, inquiry_summary: inq?.summary ?? null,
        supplier_label: name || (lang === 'ar' ? 'المورّد ' + supplierLabel(n) : 'Supplier ' + supplierLabel(n)),
        amount: q.quote_amount == null ? null : Number(q.quote_amount), status: q.status,
        exclusions: t.exclusions, scope: t.scope, conditions: t.conditions, warranty: t.warranty,
        lead_time: t.lead_time, payment_terms: t.payment_terms, validity: t.validity, notes: t.notes,
        items: items && !name ? generaliseText(items, ctx).text : items, ...(review ? { sales_engineer_review: review } : {}),
      };
    });
    // EVERY QUOTE IS GIVEN, AND THE ONE REPLY CALL READS THEM (27 Oct 2026, ruling 1195: knowledge is given to the
    // model, which reasons). Until today a think() DECISION (quoteQuestion: a planning call plus a deciding call,
    // 40-60 s on gpt-6-luna-pro, measured on the 27 Oct replay's sibling calls) ran BEFORE the reply just to pick which
    // quote and field the question was about, and its pick was then turned into a sentence the reply model re-read.
    // Now the quotes are one facts block and the reply model answers from it in the same call. `lang` is unused: the
    // facts are data, the reply is written in the asker's language by the model.
    void lang; void message;
    const shown = quotes.slice(0, 15).map((q) => Object.fromEntries(Object.entries(q).filter(([k, v]) => k !== 'id' && v != null && v !== '')));
    const perInq = new Map<string, number>(); for (const q of qs as Array<{ inquiry_id: string }>) perInq.set(q.inquiry_id, (perInq.get(q.inquiry_id) ?? 0) + 1);
    const requests = (inqs || []).slice(0, 15).map((i: { id: string; rfq_no: string | null; category: string | null; summary: string | null; status: string | null }) => ({ rfq_no: i.rfq_no, category: i.category, summary: i.summary, status: i.status, quotes_received: perInq.get(i.id) ?? 0 }));
    return { facts: JSON.stringify({ requests, quotes: shown }).slice(0, 6000) };
  } catch { return null; }   // a read failure falls through to the corpora rather than failing the turn
}
