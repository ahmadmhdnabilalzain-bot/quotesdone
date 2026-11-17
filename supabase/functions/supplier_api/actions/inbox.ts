// supplier_api — the jobs: inbox, projects, ack_contact.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { defaultDeps } from '../../_shared/think.ts';
import { boqWithArabic } from '../../_shared/boq_arabic.ts';
import { boqReadings, liveReadingStore } from '../../_shared/reasoned_documents.ts';
import { arabicOf } from '../../_shared/reasoned_governance.ts';
// A DRAWING PAGE THAT FAILS TO SIGN IS COUNTED, LOGGED AND RAISED - never silently dropped from the
// inbox (18 Sep 2026, sales_engineer). See _shared/drawing_pages.ts for the production measurement.
import { drawingWithheld, signRedactedDrawings } from '../../_shared/drawing_pages.ts';
import { pagesFollowFor } from '../../_shared/drawing_pages_follow.ts';
import { releasedSitePhotos, sitePhotosSection } from '../site_photos_door.ts';
import { jobNo } from '../quote_review.ts';
// The identity scrubbers (scrubIdentity, inboxField, inboxBoq) live in ./identity_scrub.ts.
import { supplierCopy } from '../what_a_supplier_receives.ts';
import { lossFeedbackShown } from '../loss_feedback.ts';
import { type ActionCtx, J, admin, failed } from '../context.ts';
import { CONCLUDED, UUID_RE } from '../lib/fields.ts';

export async function inboxActions(c: ActionCtx): Promise<Response | undefined> {
  const { email, body, action } = c;
    if (action === 'inbox') {
      const { data: sup } = await admin.from('leads').select('id,approval_status').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // `inquiry_id` narrows the inbox to one job (the inquiry detail and the review read one); it only
      // ever narrows the caller's own matches, never widens them.
      const only = typeof body.inquiry_id === 'string' && UUID_RE.test(body.inquiry_id) ? body.inquiry_id.toLowerCase() : null;
      const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id); const ids = (matches || []).map((m) => m.inquiry_id).filter((x) => !only || String(x).toLowerCase() === only);
      if (!ids.length) return J({ inquiries: [], approval_status: sup.approval_status });
      // "NOT FOR ME" (16 Nov 2026, sales_engineer): which of his requests he already declined. A read of its own, so an inbox served
      // before a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql (the column) is applied still opens.
      const declinedSet = new Set<string>(await (async () => {
        try {
          const r = await admin.from('inquiry_matches').select('inquiry_id,declined_at').eq('supplier_id', sup.id).not('declined_at', 'is', null);
          return r.error ? [] : (r.data || []).map((x: { inquiry_id: string }) => String(x.inquiry_id));
        } catch (_e) { return []; }
      })());
      // SUPPLIER-SAFE PROJECTION (independent audit 9.3). The supplier inbox used to read the raw
      // inquiries row and redact on the way out, which meant every present and future
      // supplier-facing endpoint had to remember to do the same. public.inquiries_supplier_safe is
      // the single supplier-facing projection: it serves the *_masked columns under their normal
      // names and does not expose customer_id at all, so a buyer cannot be correlated across RFQs.
      // Write-time masking was hardened first (migration harden_inquiry_masking_for_supplier_safe_view)
      // so this is not a downgrade - before that it missed UAE landlines, bare domains and the
      // buyer's own name, all of which the retrieval-time scrub did catch.
      // scrubIdentity below is deliberately kept as a second, independent layer.
      const { data: inq } = await admin.from('inquiries_supplier_safe').select('id,category,emirate,summary,spec,created_at,budget,scope_type,brief_source,boq,boq_confidence,drawing_redacted_paths,status,outcome,hired_supplier_id').in('id', ids).order('created_at', { ascending: false }).limit(25);
      const { data: myq } = await admin.from('quotes').select('id,inquiry_id,option_no,quote_amount,price_ex_vat,amount_as_stated,vat_treatment,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,source,original_file_name,submittable').eq('supplier_id', sup.id).in('inquiry_id', ids);
      // A DRAFT COULD NOT BE REOPENED (14 Sep 2026). The portal only ever offered the quote form on an
      // RFQ with no quote, so a quote the accept rule held as a draft sat there with "Complete it"
      // leading back to a card with no form, and nothing said what was missing. The inbox now carries
      // the quote's own lines (so the form reopens with them) and, for a draft, the codes
      // fn_quote_structured_score reports missing — the same codes the preflight and the coaching mail
      // use, so the three cannot disagree. The scorer is STABLE: this is a read.
      const qIds = (myq || []).map((x) => x.id).filter(Boolean);
      const itemsOf: Record<string, any[]> = {};
      if (qIds.length) {
        const { data: qi } = await admin.from('quote_items').select('quote_id,line_no,description,qty,unit,unit_price').in('quote_id', qIds).order('line_no', { ascending: true });
        for (const r of (qi || [])) (itemsOf[String(r.quote_id)] ||= []).push({ description: r.description, qty: r.qty, unit: r.unit, unit_price: r.unit_price });
      }
      // A live hold (the sales engineer's, 14 Sep 2026) rides on its quote, so the card can say which
      // line and which detail is missing and offer the two ways out.
      const holdOf: Record<string, any> = {};
      if (qIds.length) {
        const { data: hs } = await admin.from('quote_spec_hold').select('quote_id,state,missing,opened_at').in('quote_id', qIds).in('state', ['open', 'awaiting_approval']);
        for (const h of (hs || [])) holdOf[String(h.quote_id)] = { state: h.state, missing: h.missing, opened_at: h.opened_at };
      }
      // Every option is its own quote; an RFQ card lists them all, option 1 first.
      const qmap: Record<string, any[]> = {};
      const optsOf = (inqId: unknown) => (qmap[String(inqId)] || []).slice().sort((a, b) => (Number(a.option_no) || 1) - (Number(b.option_no) || 1));
      for (const x of (myq || [])) {
        let missing: string[] | null = null;
        if (x.status === 'draft') { try { const { data: sc } = await admin.rpc('fn_quote_structured_score', { p_quote: String(x.id) }); missing = Array.isArray((sc as any)?.missing) ? (sc as any).missing : null; } catch (_e) { /* the list is advice; the form still opens */ } }
        (qmap[String(x.inquiry_id)] ||= []).push({ ...x, items: itemsOf[String(x.id)] || [], missing, spec_hold: holdOf[String(x.id)] || null });
      }
      // WHY THIS QUOTE LOST (T3, 5 Oct 2026; 16 Nov 2026 SUPPLIER hole 9, ./loss_feedback.ts). The reason is the one the sales
      // engineer's model WROTE once from the customer's own word and the ex-VAT facts (public.supplier_loss_reason); nothing of the
      // chosen quotation is read here any more. A concluded job he did not win shows its reason, or that it is being written; a
      // request that ended revealed or expired shows one once it is written.
      {
        const sent = (q: any) => q.status !== 'draft' && q.status !== 'withdrawn';
        const withQuotes = (inq || []).filter((i) => (qmap[String(i.id)] || []).some(sent)).map((i) => String(i.id));
        const storedOf: Record<string, { text: string }> = {};
        if (withQuotes.length) {
          const { data: lr } = await admin.from('supplier_loss_reason').select('inquiry_id,text').eq('supplier_id', sup.id).in('inquiry_id', withQuotes)
            .then((r: any) => r, () => ({ data: [] }));
          for (const x of (lr || [])) storedOf[String(x.inquiry_id)] = { text: String(x.text) };
        }
        const lostIds = (inq || []).filter((i) => withQuotes.includes(String(i.id)) && Number(i.hired_supplier_id) !== Number(sup.id)
          && (CONCLUDED.includes(String(i.status)) || storedOf[String(i.id)])).map((i) => String(i.id));
        for (const id of lostIds) for (const q of qmap[id]) if (sent(q)) q.loss_feedback = lossFeedbackShown(storedOf[id]);
      }
      // Reveal gate for the scrub below. customer_api treats the mere existence of a transactions
      // row as "revealed" (line ~430: every tx row for the customer goes into revealedQ with no
      // further filter), and this function's own `projects` action already treats a supplier's
      // transactions rows as its paid-for jobs. Reusing that exact definition rather than
      // inventing a new one is what keeps post-reveal behaviour identical.
      // 13 Nov 2026 (anonymity audit A, L6): only a row with revealed_at set is a reveal, as every other door reads it
      // (the `projects` action below, customer_api). Every insert sets revealed_at today, so this changed nothing that was
      // measured; it closes the door a pending or refunded row without one would have opened.
      const { data: txs } = await admin.from('transactions').select('inquiry_id').eq('supplier_id', sup.id).in('inquiry_id', ids).not('revealed_at', 'is', null);
      const revealedInq = new Set((txs || []).map((t) => String(t.inquiry_id)));
      // customer_id is selected ONLY to look up the buyer's own name for scrubIdentity. It is
      // never placed on the response - it is a stable id that would let a supplier correlate a
      // buyer across RFQs.
      // REGRESSION FIX 3 Aug 2026. When this select moved from `inquiries` to
      // `inquiries_supplier_safe` (audit 2.x), the safe view stopped exposing customer_id - which
      // is correct, a supplier must never receive it. But this block still read r.customer_id off
      // the view's rows, so custIds was ALWAYS empty, custName was ALWAYS empty, and buyerName was
      // ALWAYS null. scrubIdentity therefore lost its "buyer's own name" input entirely: the second
      // independent layer had been silently switched off, leaving only the write-time masking.
      // deno check caught it as a type error; the runtime effect was invisible.
      //
      // The owner is now read from the raw table under the service role, keyed by inquiry id. It
      // exists only inside this function to feed the scrubber and is never placed on the response.
      // AUDIT 1.5 EXTENSION (4 Aug 2026). FAIL CLOSED, the way customer_api already does.
      //
      // Both lookups below dropped their `error`. On a failed read ownerOf/custName stayed empty,
      // buyerName came out null, and scrubIdentity(text, null, hits) silently skips the name
      // pattern and RETURNS THE TEXT ANYWAY — so the buyer's name would go out in summary, spec,
      // boq and budget to every matched supplier pre-reveal, with no 503, no drop and no log.
      // The customer→supplier direction got a {resolved} discriminator on 3 Aug; this inbox, the
      // surface that actually serves buyer free text pre-reveal, had no such concept.
      //
      // The database is not a backstop: mask_contacts() strips contacts and leaves names —
      // 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]', verified on production.
      //
      // Note the asymmetry `ownerResolved` encodes. An inquiry with no customer_id is RESOLVED
      // with nothing to scrub; a lookup that ERRORED is not resolved, and its free text must be
      // dropped. A supplier who receives less detail can still quote; a buyer whose name reached
      // eight strangers cannot be un-sent. This is a batch read, so a single error drops the whole
      // page's free text — coarser than customer_api's per-inquiry check, deliberately so.
      let ownerResolved = true;
      const ownerOf: Record<string, string> = {};
      const projectOf: Record<string, string> = {};
      // rfq_no rides on the owner read: the ONE job number (audit 21 Sep 2026, finding 7), read from the
      // table because the supplier-safe projection does not carry it and a sequence number identifies nobody.
      const rfqOf: Record<string, number | null> = {};
      // WITHHELD, SAID OUT LOUD (22 Sep 2026, sales_engineer). A customer's file that could not be shared
      // without identifying them (a held drawing, any CAD file) left the supplier with no drawing and no
      // word that one existed. Only the FACT is read here — the path never leaves this function.
      const hasOriginal = new Set<string>();
      // PAGES THAT FOLLOW (17 Nov 2026 evening, _shared/drawing_pages_follow.ts): a request whose drawing's sheets are still being
      // checked says so, instead of "withheld"; the CAD read routine attaches them and tells this supplier when they are.
      let pagesFollow = new Set<string>();
      { const { data: owners, error: eOwners } = await admin.from('inquiries').select('id,customer_id,project_id,rfq_no,drawing_file_path').in('id', ids);
        if (!eOwners) pagesFollow = await pagesFollowFor(admin, owners || []);
        if (eOwners) ownerResolved = false;
        else for (const o of (owners || [])) { rfqOf[String(o.id)] = o?.rfq_no ?? null; if (o?.drawing_file_path) hasOriginal.add(String(o.id)); if (o?.customer_id) ownerOf[String(o.id)] = String(o.customer_id); if (o?.project_id) projectOf[String(o.id)] = String(o.project_id); } }
      const custIds = Array.from(new Set(Object.values(ownerOf)));
      const custName: Record<string, string> = {};
      // 14 Sep 2026 (founder: nothing that identifies the customer may reach a supplier). The buyer's
      // email, phone and PROJECT NAME are read too: they are the seed list _shared/anonymise removes
      // wherever it appears, because the leak audit measured project names reaching suppliers inside
      // BOQ lines that no pattern could recognise.
      const custRow: Record<string, any> = {};
      if (ownerResolved && custIds.length) { const { data: cs, error: eCust } = await admin.from('customers').select('id,full_name,email,phone').in('id', custIds); if (eCust) ownerResolved = false; else for (const c of (cs || [])) { custRow[String(c.id)] = c; if (c.full_name) custName[String(c.id)] = String(c.full_name); } }
      const projName: Record<string, string> = {};
      { const pids = Array.from(new Set(Object.values(projectOf)));
        if (ownerResolved && pids.length) { const { data: ps, error: eP } = await admin.from('projects').select('id,name').in('id', pids); if (eP) ownerResolved = false; else for (const p of (ps || [])) if (p.name) projName[String(p.id)] = String(p.name); } }
      if (!ownerResolved) {
        // Say so. The worst property of the previous behaviour was not that it failed open — it
        // was that it failed open in silence, so the failure had no observable consequence at all.
        try {
          await admin.from('agent_runs').insert({
            agent: 'supplier_api', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
            counts: { signal: 'buyer_identity_unresolved', inquiries: ids.length },
            note: ('supplier inbox: the inquiry owner could not be read, so customer-authored text was dropped from '
              + ids.length + ' pre-reveal inquiry row(s) rather than emitted unscrubbed.').slice(0, 500),
          });
        } catch (_e) { /* never let the trail block the response */ }
      }
      // Sign every redacted drawing page for the whole inbox page at once. A page that cannot be signed
      // is counted and raised rather than dropped in silence; the pages that did sign are still served.
      const pagesOf = await signRedactedDrawings(admin, (inq || []).map((i) => ({ id: i.id, paths: i.drawing_redacted_paths })));
      // PHOTOS FROM THE SITE (15 Nov 2026, ledger 1704; ../site_photos_door.ts): only copies the worker's check released and
      // recorded, signed by the same recorded-path signer as the drawings; the shots provided and not provided; the visit line.
      const photoDoor = await releasedSitePhotos(admin, (inq || []).map((i) => i.id));
      const photoJobs = (i: any): string[] => (photoDoor.records.get(String(i.id))?.photos ?? []).map((p) => String(p?.job_id || '')).filter((j) => photoDoor.paths.has(j));
      const photoPagesOf = await signRedactedDrawings(admin, (inq || []).map((i) => ({ id: i.id, paths: photoJobs(i).map((j) => photoDoor.paths.get(j)) })));
      const photosOf = (i: any) => {
        const jobs = photoJobs(i), sp = photoPagesOf[String(i.id)];
        // a URL is attributed to its job only when every released copy signed (the signer keeps the order of what it served)
        const signed = new Map<string, string>(sp && sp.served === jobs.length ? jobs.map((j, k) => [j, sp.urls[k]] as [string, string]) : []);
        return sitePhotosSection(photoDoor.records.get(String(i.id)) ?? null, signed);
      };
      const out: any[] = [];
      const gatedBoqs: unknown[] = [];
      for (const i of (inq || [])) {
        const dp = pagesOf[String(i.id)] || { urls: [], expected: 0, served: 0, failed: 0 };
        const pages: string[] = dp.urls;
        const concluded = CONCLUDED.includes(String(i.status));
        const youWon = i.hired_supplier_id != null && Number(i.hired_supplier_id) === Number(sup.id);
        // Pre-reveal, the buyer's own free text is scrubbed on the way out. Once this supplier
        // has a transactions row for this inquiry the reveal has been paid for, and summary /
        // spec / boq are served byte-identically to before this change.
        const revealed = revealedInq.has(String(i.id));
        const hits: string[] = [];
        const buyerName = custName[ownerOf[String(i.id)] || ''] || null;
        // ownerResolved === false means we could not READ the owner, which is not the same as
        // "this inquiry has no owner". We cannot scrub a name we could not read, so the buyer's
        // own text is withheld rather than emitted unscrubbed. Category, emirate, status, quote
        // and the redacted drawings still go out — enough to log in and quote.
        const owner = custRow[ownerOf[String(i.id)] || ''] || {};
        // The customer's stated site is a seed too (what_a_supplier_receives.ts, 13 Nov 2026): "Al Barsha 2" in spec.location
        // is removed from the summary, the brief and the BOQ, so an older row whose summary names the area is safe on read.
        const buyer = { name: buyerName, email: owner.email || '', phone: owner.phone || '', project: projName[projectOf[String(i.id)] || ''] || '' };
        // ONE ROW AS A SUPPLIER RECEIVES IT (13 Nov 2026, supplier_api/what_a_supplier_receives.ts supplierCopy). Before a reveal
        // the summary, the brief, the budget and the BOQ pass the one gate every supplier door shares: the buyer's name, e-mail,
        // phone and project, the stated site and the old supplier's terms are seeds, the brief loses its customer-only keys and
        // its address answers are reduced to what names nobody, a quotation's BOQ is rebuilt as our inquiry, and a field the
        // residual scan cannot prove clean is WITHHELD (the history of each field's gate: SP-F-04 22 Sep, #854, 29 Jul). After the
        // reveal the customer is released (his words and his site) and the old supplier never is (rulings 1683/1686).
        const c = supplierCopy(i, { revealed, ownerResolved, buyer }, hits);
        const sSummary = c.summary, summaryWithheld = c.summary_withheld, sSpec = c.spec, specWithheld = c.spec_withheld;
        const sBudget = c.budget, budgetWithheld = c.budget_withheld, boqWithheld = c.boq_withheld;
        const sBoqAr = c.boq || null;   // its Arabic headings are added after the loop
        if (!revealed && c.boq) gatedBoqs.push(c.boq);   // only a gated BOQ's headings may be reasoned over
        // The scope in Arabic is the REASONED translation of the (already scrubbed) summary, filled in after the
        // loop in one batch (decision point trade_glossary_ar); until it exists — under the model hold — it stays
        // null and the portal shows the customer's own words, never a partial or word-by-word reading.
        const sSummaryAr: string | null = null;
        out.push({ id: i.id, rfq_no: rfqOf[String(i.id)] ?? null, job_no: jobNo({ id: String(i.id), rfq_no: rfqOf[String(i.id)] }), category: i.category, emirate: i.emirate, summary: sSummary, summary_withheld: summaryWithheld, summary_ar: sSummaryAr, spec: sSpec, spec_withheld: specWithheld, created_at: i.created_at, budget: sBudget || null, budget_withheld: budgetWithheld, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: sBoqAr || null, boq_withheld: boqWithheld, boq_confidence: i.boq_confidence || null, drawing_file_name: null, drawing_file_url: null, drawing_pages: pages, drawing_pages_expected: dp.expected, drawing_pages_served: dp.served, drawing_pages_failed: dp.failed, drawing_withheld: drawingWithheld(hasOriginal.has(String(i.id)), dp.expected) && !(pagesFollow.has(String(i.id)) && dp.expected === 0), drawing_pages_follow: pagesFollow.has(String(i.id)) && dp.expected === 0, site_photos: photosOf(i), status: i.status, concluded, you_won: youWon, revealed, declined: declinedSet.has(String(i.id)), quote: optsOf(i.id)[0] || null, quotes: optsOf(i.id) });
      }
      // The BOQ read in Arabic (audit 21 Sep 2026, findings 26/27). Which Arabic heading a section means is
      // reasoned (decision point documents.boq_arabic) over the GATED BOQs only — a revealed BOQ is the customer's
      // unscrubbed text, so it only looks up readings already remembered and never adds a heading of its own.
      // Under the hold an unread heading keeps its original words.
      const served = out.filter((o) => o.boq);
      if (served.length) {
        const readings = await boqReadings(defaultDeps(admin, 'supplier_api'), liveReadingStore(admin), gatedBoqs, served.map((o) => o.boq)).catch(() => ({} as Record<string, string>));
        for (const o of served) o.boq = boqWithArabic(o.boq, readings);
      }
      const summaries = out.map((o) => o.summary).filter((x): x is string => typeof x === 'string' && !!x.trim());
      if (summaries.length) {
        try {
          const ar = await arabicOf(defaultDeps(admin, 'supplier_api'), { texts: summaries, fileOnly: true });   // a list never waits on a model
          for (const o of out) if (typeof o.summary === 'string' && ar.map[o.summary.trim()]) o.summary_ar = ar.map[o.summary.trim()];
        } catch (_e) { /* the portal shows the customer's own words */ }
      }
      return J({ inquiries: out, approval_status: sup.approval_status });
    }

    if (action === 'projects') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // A REVEALED JOB WITH NO WAY TO REACH THE CUSTOMER (14 Sep 2026). A transactions row is the
      // reveal — the customer paid to know this supplier — and the signed Supplier Agreement (v9, cl.
      // 11 and 33) then obliges the supplier to respond within 5 working days, chased at 3. The tab
      // listed category, amount and date only: no customer name or number, no deadline, and no way to
      // say "done". The contact is served HERE and only here, keyed on the supplier's own transactions
      // rows, so it cannot reach a supplier before a reveal. Deadlines come from fn_reveal_window (13 Nov 2026), the one
      // source of the window: from the payment, on the working-day calendar refund_flow and the nudges use.
      const { data: projs } = await admin.from('transactions').select('id,quote_id,inquiry_id,customer_id,revealed_at,quote_amount,refund_deadline,supplier_ack_at,refund_status,inquiries(category,emirate,summary,spec)').eq('supplier_id', sup.id).not('revealed_at', 'is', null).order('revealed_at', { ascending: false }).limit(50);
      const custIds = Array.from(new Set((projs || []).map((p: any) => p.customer_id).filter(Boolean)));
      const cust: Record<string, any> = {};
      if (custIds.length) { const { data: cs } = await admin.from('customers').select('id,full_name,email,phone').in('id', custIds); for (const c of (cs || [])) cust[String(c.id)] = c; }
      // THE COMPANY THE BUYER IS BILLED AS (16 Nov 2026, public.reveal_bill_to): on his revealed jobs only, so the supplier addresses
      // the formal quotation and invoices to it (company, TRN, PO reference). Never on a job that is not revealed (these rows are sales).
      const billTo: Record<string, any> = {};
      const qids = (projs || []).map((p: any) => p.quote_id).filter(Boolean);
      if (qids.length) { const { data: bts } = await admin.from('reveal_bill_to').select('quote_id,company,trn,po_ref').in('quote_id', qids); for (const b of (bts || [])) billTo[String(b.quote_id)] = { company: b.company, trn: b.trn ?? null, po_ref: b.po_ref ?? null }; }
      // The window of one sale, from the one source (public.fn_reveal_window, 13 Nov 2026): counted from the payment.
      const winCache: Record<string, any> = {};
      const win = async (tx: string) => { if (tx in winCache) return winCache[tx]; try { const { data } = await admin.rpc('fn_reveal_window', { p_tx: tx }); return (winCache[tx] = data || null); } catch (_e) { return (winCache[tx] = null); } };
      // The customer's post-job review (T2): stars, words and photos, on the supplier's own revealed
      // jobs only. Photos come from the private review-photos bucket as 1-hour signed URLs.
      const rvBy: Record<string, any> = {};
      const txIds = (projs || []).map((p: any) => p.id);
      if (txIds.length) { const { data: rvs } = await admin.from('reviews').select('transaction_id,rating,comment,photo_paths,created_at').in('transaction_id', txIds); for (const r of (rvs || [])) rvBy[String(r.transaction_id)] = r; }
      const photoUrl = async (p: string) => { try { const { data } = await admin.storage.from('review-photos').createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      const out: any[] = [];
      for (const p of (projs || []) as any[]) {
        const c = cust[String(p.customer_id)] || {};
        out.push({ id: p.id, inquiry_id: p.inquiry_id, category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, summary: p.inquiries?.summary || null,
          revealed_at: p.revealed_at, amount: p.quote_amount, acknowledged_at: p.supplier_ack_at || null, refund_status: p.refund_status || null,
          chase_at: (await win(p.id))?.chase_at ?? null, respond_by: p.refund_deadline || ((await win(p.id))?.ends_at ?? null),
          // The exact site is released by the reveal (13 Nov 2026, founder ruling 1683): the customer-only key the request
          // stored it under (_shared/site_location.ts), else the address answer of an older row. Shown with the contact card.
          customer: { name: c.full_name || null, email: c.email || null, phone: c.phone || null, site: String(p.inquiries?.spec?.site_location || p.inquiries?.spec?.location || '').trim() || null },
          bill_to: billTo[String(p.quote_id)] || null,
          review: rvBy[String(p.id)] ? { rating: rvBy[String(p.id)].rating, comment: rvBy[String(p.id)].comment || null, created_at: rvBy[String(p.id)].created_at,
            photo_urls: (await Promise.all(((rvBy[String(p.id)].photo_paths || []) as string[]).map(photoUrl))).filter(Boolean) } : null });
      }
      return J({ ok: true, projects: out });
    }
    // "I have contacted the customer" from inside the portal. supplier_ack does the same from the
    // reminder e-mail's one-click link (by ack_token); this is the signed-in door to the same column,
    // scoped to the caller's own transaction, and it stops the nudges the same way.
    if (action === 'ack_contact') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(); if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const txId = String(body.transaction_id || ''); if (!UUID_RE.test(txId)) return J({ error: 'invalid transaction', code: 'invalid_transaction' }, 400);
      const { data: t } = await admin.from('transactions').select('id,supplier_id,supplier_ack_at').eq('id', txId).maybeSingle();
      if (!t || Number(t.supplier_id) !== Number(sup.id)) return J({ error: 'not found', code: 'not_found' }, 404);
      if (t.supplier_ack_at) return J({ ok: true, acknowledged_at: t.supplier_ack_at });
      const now = new Date().toISOString();
      const { error } = await admin.from('transactions').update({ supplier_ack_at: now }).eq('id', txId).is('supplier_ack_at', null);
      if (error) return failed(String(action), error);
      return J({ ok: true, acknowledged_at: now });
    }
}
