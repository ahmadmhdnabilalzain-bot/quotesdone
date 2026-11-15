// supplier_api — the supplier's own documents as PDF: quote_pdf, inquiry_pdf, receipts, receipt_pdf (one block, as it was).
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { CANONICAL_ORIGIN } from '../../_shared/site_origins.ts';
import { nativeArabic } from '../../_shared/reasoned_governance.ts';
import { readRevealRate, recordRateUnreadable } from '../../_shared/reveal_rate.ts';
import { DOC_VERSION, completenessOf, inquiryDocument, itemsOfRows, quoteDocument, quoteRef, type InquiryDocRow, type Item } from '../../_shared/quote_documents.ts';
import { duesLines, supplierInvoiceDocument, supplierReceiptDocument, type SupplierPayment } from '../../_shared/supplier_payment_documents.ts';
import { jobAlias } from '../../_shared/quote_labels.ts';
import { inquiryDocuments } from '../quote_review_actions.ts';
import { type ActionCtx, J, SUPA_URL, admin, secretVal } from '../context.ts';
import { UUID_RE } from '../lib/fields.ts';

export async function printActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, jwt, email, body, action, handle } = c;
    // A SUPPLIER'S OWN DOCUMENTS AS PDF (15 Sep 2026, sales_engineer). The customer could download every
    // quotation (customer_api quote_pdf); the supplier who wrote it could not, and had no receipt for a
    // charge it had paid. quote_pdf prints the SAME standardised quotation the customer receives
    // (_shared/quote_documents.ts quoteDocument), for this supplier's own quote only; receipts and
    // receipt_pdf list and print the dues this supplier has paid. pdf_native is reached with this
    // function's own scoped credential — fn.supplier_api's scope already holds pdf_native (measured
    // 15 Sep 2026 in internal_credential), so no credential or database change is needed.
    if (action === 'quote_pdf' || action === 'inquiry_pdf' || action === 'receipts' || action === 'receipt_pdf') {
      const { data: sup } = await admin.from('leads').select('id,company_name').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const lang: 'en' | 'ar' = SUPPLIER_LOCALE;   // a supplier's document is English whatever was asked (founder, 28 Sep 2026)
      const print = async (doc: Record<string, unknown>) => {
        const secret = await secretVal('cred_fn_supplier_api');
        if (!secret) return null;
        const r = await fetch(`${SUPA_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...doc, folder: 'supplier/' + sup.id, __secret: secret }) });
        const j = await r.json().catch(() => null);
        return j?.ok && j.url ? { url: String(j.url), bucket: String(j.bucket || 'agent-docs'), path: String(j.path || '') } : null;
      };
      // CACHED LIKE quote_pdf (21 Sep 2026, sales_engineer). The customer's quotation is cached in
      // quote_pdf_cache keyed on (quote_id, lang) and invalidated by quotes.updated_at. The supplier's
      // two documents cannot share that key (the same quote prints differently for each side: letter
      // 'S', no request text) and the inquiry has no updated_at at all, so public.supplier_document_cache
      // keys on (kind, subject, supplier, lang) and carries a hash of the INPUT that produced the file
      // (scripts/sql/the_inquiry_and_the_suppliers_own_quotation_are_cached_as_documents.sql). An edited
      // inquiry or quote changes the hash and is printed again; a reveal changes what the inbox serves
      // and so changes the hash too. The cache row is never read for anything but the file's location.
      const hashOf = async (input: unknown) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(input))))).map((b) => b.toString(16).padStart(2, '0')).join('');
      const sign = async (b: string, p: string) => { try { const { data } = await admin.storage.from(b).createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      // An Arabic document with a line not yet translated by reasoning (the founder's model hold): held, not half-printed.
      const ARABIC_HELD_REPLY = { ok: false, held: true, code: 'arabic_held',
        message: 'The document is being prepared and will be ready shortly. Please try again in a minute.' };
      const served = async (kind: 'inquiry' | 'quotation', subject: string, hash: string, build: () => Promise<{ doc: Record<string, unknown>; ref: string } | null>) => {
        const { data: hit } = await admin.from('supplier_document_cache').select('bucket,path,content_hash').eq('kind', kind).eq('subject_id', subject).eq('supplier_id', sup.id).eq('lang', lang).maybeSingle();
        if (hit && hit.content_hash === hash) { const url = await sign(hit.bucket, hit.path); if (url) return { url, cached: true }; }
        // The same per-hour ceiling customer_api holds (PDF_LIMIT_PER_HOUR = 40): a supplier who
        // regenerates in a loop is told so rather than served a queue of renders.
        const { count } = await admin.from('supplier_document_cache').select('kind', { count: 'exact', head: true }).eq('supplier_id', sup.id).gte('created_at', new Date(Date.now() - 3600e3).toISOString());
        if ((count || 0) >= 40) return { error: 'rate_limited' as const };
        const built = await build(); if (!built) return null;
        const out = await print(built.doc); if (!out) return null;
        try { await admin.from('supplier_document_cache').upsert({ kind, subject_id: subject, supplier_id: sup.id, lang, content_hash: hash, bucket: out.bucket, path: out.path, created_at: new Date().toISOString() }, { onConflict: 'kind,subject_id,supplier_id,lang' }); } catch (_e) { /* the file is served either way */ }
        return { url: out.url, cached: false, ref: built.ref };
      };

      if (action === 'quote_pdf') {
        const { data: q } = await admin.from('quotes').select('*').eq('id', String(body.quote_id || '')).eq('supplier_id', sup.id).maybeSingle();
        if (!q) return J({ error: 'Quote not found', code: 'not_found' }, 404);
        const [{ data: inq }, { data: qi }, { data: spec }, { data: matches }] = await Promise.all([
          admin.from('inquiries_supplier_safe').select('id,category,emirate').eq('id', q.inquiry_id).maybeSingle(),
          admin.from('quote_items').select('*').eq('quote_id', String(q.id)).order('line_no', { ascending: true }).limit(60),
          // the customer's intake answers decide what the completeness checks require (assess.ts); read
          // here for the checks only, never printed; rfq_no is the one job number (audit 21 Sep 2026, finding 7)
          admin.from('inquiries').select('spec,rfq_no').eq('id', q.inquiry_id).maybeSingle(),
          admin.from('inquiry_matches').select('id,supplier_id').eq('inquiry_id', q.inquiry_id).order('id', { ascending: true }),
        ]);
        // The completeness checks and each line's specs come from the hold desk's own reader
        // (_shared/quote_documents.ts completenessOf — audit 21 Sep 2026, finding 4).
        const done = completenessOf(q as any, itemsOfRows(qi), inq?.category ?? null, spec?.spec ?? null);
        const items: Item[] = done.items;
        // The customer's request text is NOT printed (summary: null): pre-reveal it reaches a supplier only
        // through the inbox's scrubbers, and this document must not become a second, unscrubbed door.
        // ONE ALIAS PER SUPPLIER PER JOB (audit 21 Sep 2026, finding 29: "Supplier A" in the question
        // thread, "Supplier S" on the quotation). The supplier's letter is its place in the job's match
        // order — the rule messages_api already uses for the question thread — never the customer's
        // price-rank letter, which a supplier must not learn.
        const order = [...new Set((matches || []).map((m: { supplier_id: number }) => Number(m.supplier_id)))];
        const letter = jobAlias(order, Number(sup.id)).replace(/^Supplier /, '');
        const inquiry = { id: String(q.inquiry_id), rfq_no: spec?.rfq_no ?? null, category: inq?.category ?? null, emirate: inq?.emirate ?? null, summary: null };
        const ref = quoteRef(inquiry, letter);
        // The supplier's own words in Arabic are reasoned; a line not yet translated holds the Arabic document.
        let heldAr = false;
        // The fee line prints pricing_config's rate (the one reveal_fee() charges); unread, the PDF is refused, never guessed.
        const rateRead = await readRevealRate(admin);
        if (!rateRead.ok) { await recordRateUnreadable(admin, 'supplier_api quotation PDF -> pricing_config', rateRead.error, { quote_id: q.id }); return J({ error: 'pdf_failed', code: 'reveal_rate_unread' }, 503); }
        const revealRate = rateRead.cfg.standard_reveal_rate;
        const r = await served('quotation', String(q.id), await hashOf({ q, items, inquiry, letter, checks: done.quote, layout: DOC_VERSION, revealRate }), async () => {
          const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => quoteDocument({ quote: done.quote, inquiry, items, letter, lang, arTexts, revealRate }), { subject: { quote_id: q.id } });
          if (!d.doc) { heldAr = true; return null; }
          return { doc: d.doc.body as Record<string, unknown>, ref };
        });
        if (heldAr) return J(ARABIC_HELD_REPLY, 202);
        if (r && 'error' in r) return J({ error: 'You have generated many PDFs recently. Please try again shortly.', code: 'rate_limited' }, 429);
        return r ? J({ ok: true, url: r.url, ref, lang, cached: r.cached }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
      }

      // THE INQUIRY AS A DOCUMENT (21 Sep 2026, sales_engineer; founder instruction 435). The job is read
      // through this function's own `inbox`, in-process with the caller's session, so the document holds
      // only what the inbox's scrubbers and its reveal gate let this supplier see — and a job this
      // supplier is not matched to does not exist for them. The attachments it lists are the ones
      // inquiry_documents offers, from the same list.
      if (action === 'inquiry_pdf') {
        const iid = typeof body.inquiry_id === 'string' && UUID_RE.test(body.inquiry_id) ? body.inquiry_id.toLowerCase() : null;
        if (!iid) return J({ error: 'not_found', code: 'not_found' }, 404);
        const r0 = await handle(new Request(req.url, { method: 'POST', headers: { Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'inbox', inquiry_id: iid }) }));
        const j0 = await r0.json().catch(() => ({}));
        const i = (j0.inquiries || []).find((x: any) => String(x.id) === iid);
        if (!i) return J({ error: 'not_found', code: 'not_found' }, 404);
        const d = inquiryDocuments(i);
        const row: InquiryDocRow = { id: String(i.id), rfq_no: i.rfq_no ?? null, category: i.category ?? null, emirate: i.emirate ?? null, summary: i.summary ?? null, budget: i.budget ?? null,
          scope_type: i.scope_type ?? null, created_at: i.created_at ?? null, brief_source: i.brief_source ?? null, spec: i.spec ?? null, boq: i.boq ?? null, boq_withheld: !!i.boq_withheld,
          documents: d.documents.map((x: any) => ({ kind: x.kind, name: x.name, lines: x.lines })), drawing_pages_failed: d.drawing_pages_failed };
        const ref = quoteRef(row, 'RFQ');
        // The signed drawing URLs are not on the row, so the hash is stable across signings.
        let heldAr = false;
        const r = await served('inquiry', iid, await hashOf({ row, layout: DOC_VERSION }), async () => {
          const d = await nativeArabic(defaultDeps(admin, 'supplier_api'), (arTexts) => inquiryDocument({ inquiry: row, lang, portalUrl: CANONICAL_ORIGIN + (lang === 'ar' ? '/ar/portal' : '/portal'), arTexts }), { subject: { inquiry_id: iid } });
          if (!d.doc) { heldAr = true; return null; }
          return { doc: d.doc.body as Record<string, unknown>, ref };
        });
        if (heldAr) return J(ARABIC_HELD_REPLY, 202);
        if (r && 'error' in r) return J({ error: 'You have generated many PDFs recently. Please try again shortly.', code: 'rate_limited' }, 429);
        return r ? J({ ok: true, url: r.url, ref, job_no: d.job, lang, cached: r.cached }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
      }

      // A paid due: stripe_webhook is the one writer of paid_at, so a row with it is a payment we recorded.
      const PAID = ['paid', 'settled'];
      const total = (d: any) => Math.round((Number(d.amount_due || 0) + Number(d.admin_fee || 0) + Number(d.interest_amount || 0) + Number(d.fine_amount || 0)) * 100) / 100;
      if (action === 'receipts') {
        const { data, error } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,currency,paid_at')
          .eq('supplier_id', sup.id).in('status', PAID).not('paid_at', 'is', null).order('paid_at', { ascending: false }).limit(50);
        if (error) return J({ error: 'temporarily_unavailable', code: 'temporarily_unavailable' }, 503);
        const { data: reg } = await admin.from('leads').select('registration_paid_at,registration_amount_aed').eq('id', sup.id).maybeSingle();
        const regRow = reg?.registration_paid_at && Number(reg.registration_amount_aed) > 0 ? [{ id: null, kind: 'registration', paid_at: reg.registration_paid_at, total: Number(reg.registration_amount_aed), currency: 'AED' }] : [];
        return J({ ok: true, receipts: [...regRow, ...(data || []).map((d: any) => ({ id: d.id, kind: 'dues', paid_at: d.paid_at, total: total(d), currency: d.currency || 'AED' }))] });
      }

      // OUR invoice and receipt for a payment to QuotesDone, on the template (audit 22 Sep 2026, finding 2):
      // _shared/supplier_payment_documents.ts. doc 'invoice' | 'receipt' (default receipt); kind
      // 'registration' prints the annual listing fee, otherwise the settled charges of one payment.
      const docKind: 'invoice' | 'receipt' = body.doc === 'invoice' ? 'invoice' : 'receipt';
      const build = docKind === 'invoice' ? supplierInvoiceDocument : supplierReceiptDocument;
      const { data: lead } = await admin.from('leads').select('email,registration_paid_at,subscription_paid_until,registration_payment_ref,registration_amount_aed').eq('id', sup.id).maybeSingle();
      let pay: SupplierPayment;
      if (body.kind === 'registration') {
        if (!lead?.registration_paid_at || !(Number(lead.registration_amount_aed) > 0)) return J({ error: 'Receipt not found', code: 'receipt_not_found' }, 404);
        const at = String(lead.registration_paid_at);
        pay = { kind: 'registration', ref: `QD-REG-${sup.id}-${at.slice(0, 4)}`, paid_at: at, payment_ref: String(lead.registration_payment_ref || '—'),
          supplier: { name: String(sup.company_name || '—'), email: lead.email ?? null },
          period: lead.subscription_paid_until ? { from: at.slice(0, 10), to: String(lead.subscription_paid_until) } : null,
          lines: [{ en: 'Annual supplier Subscription Fee', ar: 'رسوم الاشتراك السنوية للمورّد', amount: Number(lead.registration_amount_aed) }], total: Number(lead.registration_amount_aed) };
      } else {
        const { data: d } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,paid_at,payment_ref')
          .eq('id', Number(body.due_id) || 0).eq('supplier_id', sup.id).in('status', PAID).not('paid_at', 'is', null).maybeSingle();
        if (!d) return J({ error: 'Receipt not found', code: 'receipt_not_found' }, 404);
        // One payment settles every due in its checkout (stripe_webhook writes the same payment_ref on
        // each), so the document covers the whole payment and its total is what the card was charged.
        const { data: all } = await admin.from('supplier_dues').select('id,amount_due,admin_fee,interest_amount,fine_amount,paid_at,payment_ref')
          .eq('supplier_id', sup.id).in('status', PAID).eq('payment_ref', String(d.payment_ref || '')).order('id', { ascending: true });
        const rowsPaid = d.payment_ref && all?.length ? all : [d];
        const lines = duesLines(rowsPaid);
        pay = { kind: 'dues', ref: 'QD-DU-' + String(rowsPaid[0].id), paid_at: String(rowsPaid[0].paid_at), payment_ref: String(d.payment_ref || '—'),
          supplier: { name: String(sup.company_name || '—'), email: lead?.email ?? null }, lines, total: Math.round(lines.reduce((a, l) => a + l.amount, 0) * 100) / 100 };
      }
      const doc = build(pay, lang);
      const url = await print(doc as unknown as Record<string, unknown>);
      return url ? J({ ok: true, url: url.url, ref: pay.ref, doc: docKind, lang }) : J({ error: 'pdf_failed', code: 'pdf_failed' }, 502);
    }
}
