// customer_api — the customer's documents as files: compare_pdf, compare_csv, brief_pdf, quote_pdf.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { isLiveQuote } from '../../_shared/quote_live.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { documentLocale } from '../../_shared/registered_locale.ts';
import { compareTable, toCsv, quoteRef, jobNoOf, isCurrentDoc } from '../../_shared/quote_documents.ts';
import { arabicOf } from '../../_shared/reasoned_governance.ts';
import { type ActionCtx, J, PDF_LIMIT_PER_HOUR, admin } from '../context.ts';
import { signedDoc } from '../lib/storage.ts';
import { ARABIC_COMPARE_BUDGET_MS, buildBriefPdf, buildComparePdf, buildQuotePdf, compareMaskNames, fetchCompareAnalysis, heldReply, letterOf } from '../lib/pdfs.ts';

export async function reportActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, cust } = c;
    if (action === 'compare_pdf') {
      const iid = String(body.inquiry_id || '');
      // THE REGISTERED LANGUAGE IS THE DEFAULT; THE BUTTON PRESSED IS THE DOCUMENT ASKED FOR.
      // 21 Sep 2026 (customer-portal journey audit): an English-registered customer on the Arabic
      // portal pressed the Arabic report and got English. The portal sends lang: docLang, and this line
      // read customers.locale only — the same defect quote_pdf had (finding 4) and was fixed for alone.
      // Every customer document now routes through documentLocale (prevented by
      // customer_api/arabic_documents.test.ts, which fails if any document action reads the locale alone).
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      // Reuse the cached analysis when the quote set is unchanged; otherwise ask for a fresh one.
      let analysis: any = null;
      const started = Date.now();
      try {
        const got = await fetchCompareAnalysis(iid, lang);
        // A DOCUMENT THAT COULD NOT BE BUILT IS NOT AN HTTP 200 (audit CP-10). 409: the comparison
        // itself is unavailable (too few complete quotes, or the model is down), not the request.
        if (got.analysis) analysis = got.analysis; else return J({ ok: false, error: got.error, code: got.error, message: 'The comparison report is not available yet. Your quotes are unaffected.', message_ar: 'تقرير المقارنة غير متاح بعد. عروضك لم تتأثر.' }, 409);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      try {
        const { j, ref } = await buildComparePdf(analysis, inq, lang, started + ARABIC_COMPARE_BUDGET_MS);
        if ((j as any)?.held) return heldReply();
        // The Arabic report is in the customer's hands now: a waiter from an earlier held press is not sent again.
        if (j?.ok && j.url && lang === 'ar') await admin.from('arabic_compare_waiter').delete().eq('inquiry_id', iid);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    // W10: the comparison as a spreadsheet. Same ownership check, same rate limit and the same
    // quote_compare analysis as compare_pdf, rendered through the same compareTable().
    if (action === 'compare_csv') {
      const iid = String(body.inquiry_id || '');
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      let analysis: any = null;
      try {
        const got = await fetchCompareAnalysis(iid, lang);
        if (got.analysis) analysis = got.analysis; else return J({ ok: false, error: got.error, code: got.error, message: 'The comparison is not available yet. Your quotes are unaffected.', message_ar: 'المقارنة غير متاحة بعد. عروضك لم تتأثر.' }, 409);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      // The same supplier names the PDF masks (anonymity audit 13 Nov 2026, REPORT_C L7). Whether a CSV may exist beside
      // the PDF at all (ruling 1671) is the founder's question; until he answers, it is exactly as safe as the PDF.
      const maskNames = await compareMaskNames(iid);
      let side = compareTable(analysis, lang === 'ar', {}, maskNames);
      if (side && side.untranslated.length) {
        const ar = await arabicOf(defaultDeps(admin, 'customer_api'), { texts: side.untranslated, subject: { inquiry_id: iid } });
        side = ar.complete ? compareTable(analysis, true, ar.map, maskNames) : null;
        if (!side || side.untranslated.length) return heldReply();
      }
      if (!side) return J({ ok: false, error: 'comparison_unavailable', code: 'comparison_unavailable', message: 'The comparison is not available yet. Your quotes are unaffected.', message_ar: 'المقارنة غير متاحة بعد. عروضك لم تتأثر.' }, 409);
      return J({ ok: true, csv: toCsv(side.head, side.rows), filename: 'QD-' + jobNoOf(inq) + (lang === 'ar' ? '-مقارنة' : '-comparison') + '.csv' });
    }

    if (action === 'brief_pdf') {
      const iid = String(body.inquiry_id || '');
      const lang = documentLocale(body.lang, cust.locale);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate,budget,spec,boq,trades,drawing_file_name').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildBriefPdf(inq, lang);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'quote_pdf') {
      const qid = String(body.quote_id || '');
      // ONE LANGUAGE PER DOCUMENT, BOTH ALWAYS ON OFFER (founder, 14 Sep 2026). The old 'bi' file —
      // English page, then an "Arabic" page whose content was English whenever ai_gateway failed —
      // is no longer produced; its cache rows are simply never read again.
      // 21 Sep 2026 (customer audit, finding 4): the portal's "النسخة العربية" button sent lang:'ar'
      // and this line read customers.locale instead, so an English-registered customer could never
      // get the Arabic document the button promises ("both always on offer"). The registered locale
      // is the DEFAULT; an explicit request for the other language is the customer asking for the
      // second document, not a message being addressed in the wrong language.
      const lang = documentLocale(body.lang, cust.locale);
      const { data: q } = await admin.from('quotes').select('*').eq('id', qid).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,rfq_no,customer_id,category,summary,emirate,boq').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      // A draft is not a quote the customer has; it has no letter and no document.
      if (!isLiveQuote(q.status)) return J({ error: 'Quote not found' }, 404);
      const { data: cached } = await admin.from('quote_pdf_cache').select('bucket,path,created_at').eq('quote_id', qid).eq('lang', lang).maybeSingle();
      const touched = q.updated_at ? new Date(q.updated_at) : (q.created_at ? new Date(q.created_at) : null);
      // A cached file is served only if it was rendered by THIS layout (isCurrentDoc: DOC_VERSION is in the
      // file name). Measured 21 Sep 2026: 14 Arabic rows in quote_pdf_cache, the first from 14 Sep — every
      // one rendered before the Arabic fixes of #782/#790/#794 and served for as long as the quote itself
      // was untouched, so a customer kept getting the old, part-English document after the fix shipped.
      // ...and only if it carries the quote's letter as it is now (its ref is in the file name): a file made under the old price-rank
      // letter (journey A: two quotations both "QD-166739-A") is made again with the one letter (_shared/quote_labels.ts).
      const letterNow = await letterOf(q);
      // the stored letter could not be read: refuse and let the portal retry, never print a guessed letter (quote_labels.ts)
      if (letterNow === null) return J({ error: 'letter_unread', retry: true, message: 'Please try again in a moment.', message_ar: 'يُرجى المحاولة بعد قليل.' }, 503);
      const refNow = quoteRef(inq, letterNow);
      if (cached && isCurrentDoc(cached.path) && String(cached.path).includes(refNow + '-') && (!touched || new Date(cached.created_at) >= touched)) {
        const url = await signedDoc(cached.bucket, cached.path);
        if (url) return J({ ok: true, url, ref: refNow, lang, cached: true });
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildQuotePdf(q, inq, lang);
        if ((j as any)?.held) return heldReply();
        if (j?.ok && j.url) {
          try { await admin.from('quote_pdf_cache').upsert({ quote_id: qid, lang, customer_id: cust.id, bucket: j.bucket || 'agent-docs', path: j.path, created_at: new Date().toISOString() }, { onConflict: 'quote_id,lang' }); } catch (_e) { /* */ }
          return J({ ok: true, url: j.url, ref, lang });
        }
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }
}
