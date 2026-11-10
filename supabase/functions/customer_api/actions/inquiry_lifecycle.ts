// customer_api — a request after it is posted: missing_specs / add_missing_specs, rfq_note, my_inquiries,
// spec_offer_reply, complete_inquiry, edit_inquiry, cancel_inquiry.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move);
// split again from actions/inquiries.ts the same day (sales_engineer) into inquiry_create.ts and this.
import { NOT_LIVE_QUOTE_IN } from '../../_shared/quote_live.ts';
import { redactBoq } from '../../_shared/anonymise.ts';
import { notSureKeys, specHandoffArgs } from '../spec_handoff.ts';
import { HELD_NOTICE, hasArabic, holdForEnglish, mailMatched, supplierMail } from '../../_shared/supplier_english.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { asLocale, documentLocale } from '../../_shared/registered_locale.ts';
import { labelQuotes } from '../../_shared/quote_labels.ts';
import { feeBaseOf, feeBasisLine, priceStated, vatStated } from '../../_shared/stated_price.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { acceptedMessage, apologyMessage, offerTexts, type OfferForText } from '../../_shared/line_specs/no_exact_spec.ts';
import { arabicTextsFor } from '../../_shared/reasoned_governance.ts';
import { sanctionedLeads } from '../../_shared/sanctioned.ts';
import { heldQuoteIds, itemsByQuote } from '../../_shared/reveal_guard.ts';
import { ctxOfQuote, generaliseQuoteTerms } from '../../_shared/quote_generalise.ts';
import { requestOf, reviewNotes, type ReviewNote } from '../../_shared/quote_review_notes.ts';
import { verifiedBadges } from '../../_shared/verified_badges.ts';
import { scrubIdentity } from '../../supplier_api/identity_scrub.ts';
import { type ActionCtx, J, admin } from '../context.ts';
import { isClosedRequest } from '../../_shared/request_closed.ts';
import { EDIT_WINDOW_MS, supplierLabel } from '../lib/inquiry_rules.ts';
import { signedDrawing } from '../lib/storage.ts';
import { buyerNameOf, matchAndNotify, notifyLosers } from '../lib/matching.ts';
import { answeredSeparately, separateQuotesOf } from '../lib/separate_quotes.ts';
import { hireStep } from '../lib/hire.ts';
import { getCfg, ratingBand, ratingOf, refundRef, revealFee, reviewCountBand, yearsBand } from '../lib/pricing.ts';

export async function inquiryLifecycleActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
  const { email, cust } = c;

    // THE CUSTOMER'S FOLLOW-UP REACHES THE RFQ (website audit 14 Sep 2026, BROKEN). "Ask the
    // assistant about this request" posted to inquiry_intake, which ignores inquiry_id, so every
    // follow-up became an orphan intake draft and no supplier ever saw it. A follow-up is now an
    // addendum: stored on public.rfq_clarification as a born-answered note (the same table the
    // pre-reveal Q&A uses, so a supplier reads one list), scrubbed of contact details and the
    // customer's own name, and emailed to every matched supplier through the same queue the
    // original invitation used.
    // A REQUEST HELD FOR ITS SPECS IS COMPLETED BY ITS CUSTOMER (customer_support, 29 Sep 2026; founder ledger 1018).
    // missing_specs: one field per required spec the hold check (fn_rfq_required_check) finds missing, asked in the
    // intake's plain words in the customer's language. add_missing_specs: the answers go through the one door
    // (fn_inquiry_add_missing_specs), which writes them under the key the check reads, lets the row's trigger re-run
    // the check, notes them on the request and tells every matched supplier. A request that is now complete and had
    // reached no supplier is offered to the matcher here, exactly as at posting. The e-mail reply path uses the same
    // door (source email_reply). scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql
    if (action === 'missing_specs' || action === 'add_missing_specs') {
      const iid = String(body.inquiry_id || '');
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,summary,budget,status').eq('id', iid).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ ok: false, error: 'not_your_inquiry' }, 403);
      if (action === 'missing_specs') {
        const { data, error } = await admin.rpc('fn_inquiry_missing_specs', { p_inquiry: iid, p_lang: documentLocale(body.lang, cust.locale) });
        if (error) return J({ ok: false, error: 'missing_specs_unavailable' }, 503);
        return J({ ok: true, ...(data as Record<string, unknown>) });
      }
      // The same scrub every supplier-facing text passes: the answers reach the matched suppliers.
      const answers: Record<string, string> = {}; const hits: string[] = [];
      const raw = (body.answers && typeof body.answers === 'object') ? body.answers as Record<string, unknown> : {};
      for (const [k, v] of Object.entries(raw).slice(0, 40)) {
        const clean = String(scrubIdentity(String(v ?? '').slice(0, 300), cust.full_name, hits) || '').trim();
        if (clean.replace(/\[removed\]/g, '').trim()) answers[String(k).slice(0, 80)] = clean;
      }
      // "Not sure" records no answer: it opens a handoff to the sales engineer for those specs (./spec_handoff.ts).
      const unsure = notSureKeys(body.not_sure);
      const hand = specHandoffArgs(iid, cust.id, unsure);
      let handoff: number | null = null;
      if (hand) {
        const { data: hid, error: herr } = await admin.rpc('fn_seat_handoff', hand);
        if (herr) return J({ ok: false, error: 'handoff_failed' }, 500);
        handoff = (hid as number) ?? null;
      }
      if (!Object.keys(answers).length && hand) return J({ ok: true, released: false, handoff, not_sure: unsure });
      const { data: res, error } = await admin.rpc('fn_inquiry_add_missing_specs', { p_inquiry: iid, p_customer: cust.id, p_answers: answers, p_source: 'customer_portal' });
      if (error) return J({ ok: false, error: 'save_failed' }, 500);
      const r = (res || {}) as Record<string, any>;
      if (!r.ok) return J({ ok: false, error: r.error || 'save_failed', missing: r.missing ?? null }, r.error === 'not_your_inquiry' ? 403 : r.error === 'inquiry_closed' ? 409 : 400);
      let matches: number | null = null;
      if (r.ready === true && r.reached_suppliers === false) {
        ({ matches } = await matchAndNotify(iid, { category: String(inq.category || ''), emirate: inq.emirate ?? null, summary: String(inq.summary || ''),
          budget: inq.budget ?? null, extra: ' The customer completed the details this trade needs.' }));
      }
      // An answer in Arabic script was saved as written and its supplier copy is held for its English
      // (fn_inquiry_add_missing_specs files it for the replay; _shared/supplier_english.ts finishEnglish sends it).
      const held = r.held_for_english === true ? { notice: HELD_NOTICE.ar, notice_en: HELD_NOTICE.en } : {};
      return J({ ...r, ...held, released: r.ready === true, matches, removed: hits.length, handoff });
    }

    if (action === 'rfq_note') {
      const iid = String(body.inquiry_id || '');
      const raw = String(body.text || '').trim().slice(0, 1500);
      if (!iid || raw.length < 2) return J({ error: 'text_required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status').eq('id', iid).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'not_your_inquiry' }, 403);
      // expired and lost too (_shared/request_closed.ts): a note on an expired request was mailed to every matched supplier.
      if (isClosedRequest(inq.status)) return J({ error: 'inquiry_closed' }, 409);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recentNotes } = await admin.from('rfq_clarification').select('id', { count: 'exact', head: true }).eq('inquiry_id', iid).eq('kind', 'note').gte('asked_at', hourAgo);
      if ((recentNotes || 0) >= 10) return J({ error: 'too_many_notes' }, 429);
      const hits: string[] = [];
      const clean = String(scrubIdentity(raw, cust.full_name, hits) || '').trim();
      if (clean.replace(/\[removed\]/g, '').trim().length < 2) return J({ error: 'text_required' }, 400);
      // Every matched supplier reads this note, and suppliers read English only (_shared/supplier_english.ts):
      // Arabic is kept as written and the supplier copy is held until the model route writes its English.
      const nowIso = new Date().toISOString();
      if (hasArabic(clean)) {
        const { data: held, error: herr } = await admin.from('rfq_clarification').insert({ inquiry_id: iid, supplier_id: null, kind: 'note', answer: null,
          answer_as_written: clean, english_held_at: nowIso, answered_at: nowIso, source: 'rfq_note' }).select('id').single();
        if (herr || !held) return J({ error: 'save_failed' }, 500);
        try { await holdForEnglish(admin, Number(held.id), clean); } catch (_e) { return J({ error: 'save_failed' }, 500); }
        return J({ ok: true, id: held.id, text: clean, notified: 0, removed: hits.length, held_for_english: true, notice: HELD_NOTICE.ar, notice_en: HELD_NOTICE.en });
      }
      const { data: ins, error: nerr } = await admin.from('rfq_clarification').insert({ inquiry_id: iid, supplier_id: null, kind: 'note', answer: clean, answered_at: nowIso, source: 'rfq_note' }).select('id').single();
      if (nerr || !ins) return J({ error: 'save_failed' }, 500);
      const notified = await mailMatched(admin, iid, supplierMail('note', inq, null, clean));
      return J({ ok: true, id: ins.id, text: clean, notified, removed: hits.length });
    }

    if (action === 'my_inquiries') {
      // rfq_no is the human reference (spec §8, "RFQ #88291"). The primary key is a uuid, which is
      // not a number a customer can read out on the phone or quote in an email to a supplier.
      // §7 spec, §8 stage, §9 applied filters. THREE THINGS WERE COMPUTED AND NEVER SERVED:
      //   pipeline_stage/stage_changed_at — recorded on every inquiry, while the browser derived
      //     the stage from quotes.length and anyRevealed. A guess sitting on top of a fact.
      //   routing — the filters the matcher actually applied (job_type, primary_trade, reasoning).
      //     Spec §9 shows them back to the customer; they never left the database.
      //   floor / required_by / delivery_window — added 7 Aug for §6 and §7.
      const cols = 'id,category,emirate,summary,spec,status,created_at,budget,scope_type,brief_source,drawing_file_path,drawing_file_name,boq,boq_confidence,hired_supplier_id,outcome,parent_inquiry_id,trades,rfq_no,pipeline_stage,stage_changed_at,routing,floor,required_by,delivery_window,project_id,rfq_ready,repeat_of';
      // ONE READ AT A TIME WAS THE OVERVIEW'S CRITICAL PATH (15 Sep 2026). Measured with the e2e
      // harness's per-call timing on production (smoke run 34888342875 and a probe of 8 page loads):
      // the six dashboard calls already start together, and my_inquiries answers last (1.40-1.61 s
      // warm) because it made eleven database reads one after another. Each read below waits only for
      // what it needs, so they run in four waves: [cfg, requests, sales, reviews] -> children ->
      // [quotes, matches, open offers, refunds] -> [supplier rows, supplier performance].
      // The answer is unchanged; only the waiting is.
      const [cfg, { data: tops }, txRes, { data: revs }] = await Promise.all([
        getCfg(),
        admin.from('inquiries').select(cols).eq('customer_id', cust.id).is('parent_inquiry_id', null).order('created_at', { ascending: false }).limit(25),
        admin.from('transactions').select('id,quote_id,revealed_at,supplier_ack_at,refund_status,refund_deadline,total_charged').eq('customer_id', cust.id),
        admin.from('reviews').select('transaction_id').eq('customer_id', cust.id),
      ]);
      const topIds = (tops || []).map((i) => i.id);
      let kids: any[] = [];
      if (topIds.length) { const { data: ch } = await admin.from('inquiries').select(cols).in('parent_inquiry_id', topIds).order('created_at', { ascending: true }); kids = ch || []; }
      const kidsByParent: Record<string, any[]> = {};
      for (const k of kids) { (kidsByParent[String(k.parent_inquiry_id)] ||= []).push(k); }
      const ids = [...topIds, ...kids.map((k) => k.id)];
      const txs: any[] = ids.length ? (txRes.data || []) : [];
      if (ids.length && txRes.error) console.error('my_inquiries: transactions read failed —', txRes.error.message);
      const txIds = txs.map((t) => t.id);
      const [qsRes, msRes, sosRes, rfsRes] = await Promise.all([
        ids.length ? admin.from('quotes').select('id,inquiry_id,supplier_id,option_no,quote_amount,price_ex_vat,gross_amount,discount_amount,discount_label,vat_treatment,vat_amount,amount_as_stated,terms_spec,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,source,created_at,expires_at').in('inquiry_id', ids).not('status', 'in', NOT_LIVE_QUOTE_IN).order('quote_amount', { ascending: true }) : null,
        ids.length ? admin.from('inquiry_matches').select('inquiry_id,supplier_id,similarity,match_reason').in('inquiry_id', ids) : null,
        ids.length ? admin.from('spec_alternative_offer').select('id,inquiry_id,line_no,item,attr,label_en,label_ar,requested,alternatives,state,reply_by').in('inquiry_id', ids).eq('customer_id', cust.id).eq('state', 'open').order('opened_at', { ascending: true }) : null,
        txIds.length ? admin.from('refunds').select('id,transaction_id,refund_decision_id').in('transaction_id', txIds) : null,
      ]);
      const allQuotes: Record<string, any>[] = qsRes?.data || [];
      // WHAT THE PORTAL MAY LIST IS WHAT THE COMPARISON MAY RANK (customer-portal audit CP-01 and
      // CP-15, 22 Sep 2026). This action filtered on status <> 'draft' alone, so two kinds of quote
      // reached the customer's screen that no other surface will act on:
      //   * a quote ON HOLD for missing details — quote_compare withholds it from the ranking and
      //     both tables (the founder's hold rule, 14 Sep 2026), yet it was listed here with a
      //     Reveal button, so the customer could pay 3% for the one quote we refuse to stand behind.
      //   * a quote from a SANCTIONED supplier — never shown to a customer (instruction 516). The
      //     ban lands after the quote was submitted, so the row survives the matcher.
      // Both are now excluded from the list and the held ones are COUNTED (`on_hold` per request),
      // because a quote that vanished with no explanation is its own defect. A quote the customer
      // has already paid to reveal is never withdrawn: that disclosure is theirs.
      const paidQuoteIds = new Set(txs.map((t) => String(t.quote_id)));
      // THE LAST THREE WAVES ARE ONE (coordinator ruling G5, 19 Oct 2026). The sanctions read, the
      // quote lines and the supplier rows each waited for the one before, though all three need only
      // the quote list. In Postgres each is under 4 ms (pg_stat_statements max); what they cost was
      // three edge-to-database round trips back to back. The supplier rows are now read for every
      // quoting supplier — a superset of the listed ones, used only through supMeta lookups of quotes
      // that survive the filters, so the answer is unchanged.
      const allSupIds = [...new Set(allQuotes.map((q) => q.supplier_id).filter((x) => x != null))] as (string | number)[];
      const [sanctionedSup, itemsOf, supRows] = await Promise.all([
        sanctionedLeads(admin, allSupIds),
        itemsByQuote(admin, allQuotes.map((q) => String(q.id))),
        allSupIds.length ? Promise.all([admin.from('leads').select('id,company_name,app_rating,app_reviews,emirate,founded_year,rv_response_rate,rv_reveals,verified,licence_gate_reason,license_doc_path,license_expiry,company_profile_doc_path').in('id', allSupIds), admin.from('supplier_perf').select('supplier_id,won,win_rate').in('supplier_id', allSupIds)]) : null,
      ]);
      const inqById = new Map<string, any>([...(tops || []), ...kids].map((i: any) => [String(i.id), i]));
      // The requests already re-posted as separate quotes per trade: their question is answered (lib/separate_quotes.ts).
      const answeredSep = answeredSeparately(tops);
      const heldIds = new Set<string>();
      for (const [iid, row] of inqById) {
        const mine = allQuotes.filter((q) => String(q.inquiry_id) === iid && !paidQuoteIds.has(String(q.id)));
        if (!mine.length) continue;
        for (const id of heldQuoteIds(mine.map((q) => ({ quote: q, items: itemsOf[String(q.id)] || [] })), row.category ?? null, row.spec)) heldIds.add(id);
      }
      const onHoldByInq: Record<string, number> = {};
      for (const q of allQuotes) if (heldIds.has(String(q.id))) onHoldByInq[String(q.inquiry_id)] = (onHoldByInq[String(q.inquiry_id)] || 0) + 1;
      const quotes: Record<string, any>[] = allQuotes.filter((q) => !heldIds.has(String(q.id)) && !sanctionedSup.has(String(q.supplier_id)));
      // How many suppliers the request actually reached. Without this the portal cannot tell
      // "waiting for quotes" apart from "this reached nobody", and shows hope either way.
      const matchedBy: Record<string, number> = {};
      // WHY a given supplier was contacted. inquiry_matches.match_reason is the ONLY place the
      // system records it; this read kept a COUNT and threw the text away, so the only surface
      // rendering a reason was OsxShell — /os, staff-only. It is now served, keyed by supplier, and
      // REVEAL-GATED in the row mapper below.
      //
      // The gate is not optional. route_inquiry builds its candidate list as `#<id> — <Company
      // Name>` (route_inquiry/index.ts:305) and asks the model for a free-text reason per
      // candidate, so a reason may name the supplier outright. Emitting it pre-reveal would hand
      // over the identity the reveal fee exists to sell.
      //
      // THE MATCH PERCENTAGE IS NOW SERVED. It used not to be, and the reason was correct at the
      // time: both writer sites passed the literal null, so every row held null in every
      // environment and a "% match" here would have been invented rather than surfaced. Both
      // writers now store the score their matcher actually computed, normalised to 0..1 (see
      // matchAndNotify above), so there is a real number to serve.
      //
      // NOT REVEAL-GATED, unlike match_reason. A percentage names nobody — it is a number about the
      // fit between a brief and an anonymous quote — so it costs the reveal fee nothing. The reason
      // text is gated because route_inquiry builds its candidate list as `#<id> — <Company Name>`
      // (route_inquiry/index.ts) and asks the model for free-text per candidate, so a reason may
      // name the supplier outright and emitting it pre-reveal would hand over the identity the
      // reveal fee exists to sell.
      //
      // NULL MEANS NOT SCORED AND MUST RENDER AS ABSENT. A match written on the legacy
      // AI-adjudicator path carries no number at all; serving 0 there would tell the customer this
      // supplier is a 0% fit, which is a different and false claim. null travels as null.
      const reasonBySup: Record<string, string> = {};
      const pctBySup: Record<string, number> = {};
      const bestPct: Record<string, number> = {};
      try { const ms = msRes?.data; for (const m of (ms || [])) { matchedBy[String(m.inquiry_id)] = (matchedBy[String(m.inquiry_id)] || 0) + 1; if (m.match_reason) reasonBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = String(m.match_reason); const sim = m.similarity == null ? null : Number(m.similarity); if (sim != null && Number.isFinite(sim)) { const pct = Math.round(sim * 100); pctBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = pct; if (pct > (bestPct[String(m.inquiry_id)] ?? -1)) bestPct[String(m.inquiry_id)] = pct; } } } catch (_e) { /* */ }
      const supIds = [...new Set(quotes.map((q) => q.supplier_id))];
      const supMeta: Record<string, any> = {};
      if (supIds.length && supRows) { const [{ data: ls }, { data: perf }] = supRows; const perfById: Record<string, any> = {}; for (const p of (perf||[])) perfById[String(p.supplier_id)] = p; const _yr = new Date().getFullYear(); for (const l of ls || []) supMeta[String(l.id)] = { r: ratingOf(l), name: l.company_name || null, emirate: l.emirate, verified: !!l.verified, vb: verifiedBadges(l), years_active: l.founded_year ? Math.max(0, _yr - Number(l.founded_year)) : null, jobs_won: (perfById[String(l.id)]||{}).won ?? 0, win_rate: (perfById[String(l.id)]||{}).win_rate ?? null, rr: Number(l.rv_reveals) > 0 && l.rv_response_rate != null ? Number(l.rv_response_rate) : null }; }
      const revealedQ = new Set<string>(); const txByQuote: Record<string, string> = {}; const revealAtByQuote: Record<string, string | null> = {};
      // 21 Sep 2026 (customer audit, finding 17): the portal said "AED 778 paid" for a card charged
      // AED 816.37 — it printed the 3% fee, not transactions.total_charged (fee + card processing).
      const chargedByQuote: Record<string, number | null> = {};
      // public.transactions HAS NO created_at COLUMN - in staging or in production. Selecting it
      // made PostgREST answer 400, so `txs` came back null, `for (const t of txs || [])` iterated
      // nothing, and revealedQ stayed empty: NO QUOTE WAS EVER MARKED REVEALED. The customer paid
      // the reveal fee, `reveal` wrote the transactions row, and the portal went on showing
      // "Supplier A" with banded ratings and supplier_ref null, forever. Found 5 Aug 2026 by the
      // first fixture that ever created a transactions row - the journey never reveals, so a green
      // 37/37 said nothing about it. revealed_at is the column that exists; there is no fallback.
      // The Reveal Guarantee clock on the customer's own job needs the facts the refund ladder runs
      // on — when they paid, whether the supplier acknowledged, and any refund already in motion.
      // All four are columns on the sale; nothing is inferred.
      const guaranteeByQuote: Record<string, Record<string, unknown>> = {};
      if (ids.length) { for (const t of txs) { revealedQ.add(String(t.quote_id)); txByQuote[String(t.quote_id)] = String(t.id); revealAtByQuote[String(t.quote_id)] = t.revealed_at || null; chargedByQuote[String(t.quote_id)] = t.total_charged == null ? null : Number(t.total_charged); guaranteeByQuote[String(t.quote_id)] = { revealed_at: t.revealed_at || null, supplier_ack_at: t.supplier_ack_at || null, refund_status: t.refund_status || null, refund_deadline: t.refund_deadline || null }; }
        // D4 (14 Sep 2026): the refund case and the chief executive's decision behind it, so the
        // customer can quote both. refunds.refund_decision_id references ceo_approval(decision_id);
        // it is null until the decision exists, and the portal says "awaiting" rather than inventing one.
        if (txIds.length) { const rfs = rfsRes?.data; const qByTx: Record<string, string> = {}; for (const [qk, tk] of Object.entries(txByQuote)) qByTx[tk] = qk; for (const rf of rfs || []) { const g = guaranteeByQuote[qByTx[String(rf.transaction_id)]]; if (g) { g.refund_ref = refundRef(rf.id); g.decision_ref = rf.refund_decision_id ? 'QD-D-' + rf.refund_decision_id : null; } } } }
      const ratedTx = new Set((revs || []).map((r) => String(r.transaction_id)));
      // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the open question, with its
      // alternatives as values and supplier COUNTS only (the table cannot hold anything else).
      const offersBy: Record<string, unknown[]> = {};
      if (ids.length) { const sos = sosRes?.data; for (const s of sos || []) { const { inquiry_id, ...rest } = s as Record<string, unknown>; (offersBy[String(inquiry_id)] ||= []).push(rest); } }
      const now = new Date();
      // Pre-reveal quote rows carry BANDS only (see ratingBand/reviewCountBand/yearsBand above);
      // rating_source, emirate and win_rate are set to undefined so JSON.stringify omits the keys
      // outright rather than shipping a null the client could still reason about. Revealed quotes
      // — a transactions row exists for that quote_id — keep the exact values, unchanged.
      // §9 THE APPLIED FILTERS, WITHOUT THE FREE TEXT. inquiries.routing records what the matcher
      // did: job_type, primary_trade, emirate and how many suppliers it evaluated. It ALSO records
      // `reasoning`, which route_inquiry generates against a candidate list built as
      // `#<id> — <Company Name>` and can therefore name a supplier outright — the same hazard that
      // makes match_reason reveal-gated. The filters are shown back; the free text is not, and this
      // projection is why: serving routing whole would leak the identity the reveal fee sells.
      const appliedFilters = (r: any) => {
        if (!r || typeof r !== 'object') return null;
        const n = Array.isArray(r.evaluated) ? r.evaluated.length : (Number.isFinite(Number(r.evaluated)) ? Number(r.evaluated) : null);
        const f = { job_type: r.job_type ?? null, primary_trade: r.primary_trade ?? null, emirate: r.emirate ?? null, evaluated: n };
        return (f.job_type || f.primary_trade || f.emirate || f.evaluated != null) ? f : null;
      };
      // THE SALES ENGINEER'S NOTES AND THE GENERIC WORDS (founder ledger 1588-1589, 10 Nov 2026). Every quote listed
      // carries the review of it against this request (EN and AR, naming no brand), and an unrevealed quote's own words
      // — scope, notes, exclusions, conditions, terms — are generalised: a brand becomes "<tier> <origin> brand", a
      // model number is withheld, the supplier's name inside its text becomes "the supplier". These fields were served
      // verbatim, so "Supply of Grohe Eurosmart 33265003 mixers" told the customer the make and model before the reveal.
      const reviewByQuote: Record<string, ReviewNote[]> = {};
      for (const q of quotes) {
        const qid = String(q.id); const items = itemsOf[String(q.id)] || []; const nm = supMeta[String(q.supplier_id)]?.name ?? null;
        const inqRow = inqById.get(String(q.inquiry_id));
        try { reviewByQuote[qid] = inqRow ? reviewNotes({ request: requestOf(inqRow), quote: q, lines: items, supplierNames: nm ? [nm] : [] }) : []; } catch (_e) { reviewByQuote[qid] = []; }
        if (!revealedQ.has(qid)) Object.assign(q, generaliseQuoteTerms({ notes: q.notes, lead_time: q.lead_time, validity: q.validity, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions }, ctxOfQuote(items, nm ? [nm] : [])));
      }
      const mapRow = async (i: any) => ({ id: i.id, rfq_no: i.rfq_no ?? null, category: i.category, emirate: i.emirate, summary: i.summary, spec: i.spec, status: i.status, created_at: i.created_at,
        // §8: the stage the LIFECYCLE recorded, not one the browser guessed from quotes.length.
        pipeline_stage: i.pipeline_stage ?? null, stage_changed_at: i.stage_changed_at ?? null,
        applied_filters: appliedFilters(i.routing),
        // A turnkey request no single contractor matched: how many specialists could quote it per trade, so the card asks
        // the customer whether they want separate quotes (finding c of 10 Nov 2026). A number only, never a name.
        // Asked once: not once the per-trade copy exists (lib/separate_quotes.ts, customer-journey audit 10 Nov 2026).
        separate_quotes: separateQuotesOf(i, answeredSep),
        // §6/§7: the floor this RFQ is scoped to, and the delivery window the assistant extracted.
        floor: i.floor ?? null, required_by: i.required_by ?? null, delivery_window: i.delivery_window ?? null,
        project_id: i.project_id ?? null, budget: i.budget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: i.boq || null, boq_confidence: i.boq_confidence || null, drawing_file_name: i.drawing_file_name || null, hired_supplier_id: i.hired_supplier_id ?? null, outcome: i.outcome ?? null, trades: i.trades || null, matched_suppliers: matchedBy[String(i.id)] || 0, best_match_pct: bestPct[String(i.id)] ?? null,
        // ONE EDIT WINDOW, ONE NUMBER (customer-portal audit CP-06, 22 Sep 2026). This said 24 hours
        // while fn_edit_inquiry refuses after 1 hour and the minutes counter beside it counted down
        // from 60, so the portal offered an Edit button for 23 hours that the server always refused.
        editable: (i.status === 'sent') && ((Date.now() - new Date(i.created_at).getTime()) < EDIT_WINDOW_MS), edit_minutes_left: (i.status === 'sent') ? Math.max(0, Math.round((EDIT_WINDOW_MS - (Date.now() - new Date(i.created_at).getTime()))/60000)) : 0,
        // How many quotes are on hold for missing details and are therefore not in the list below.
        on_hold: onHoldByInq[String(i.id)] || 0, drawing_file_url: await signedDrawing(i.drawing_file_path), spec_offers: offersBy[String(i.id)] || [], quotes: quotes.filter((q) => q.inquiry_id === i.id).map((q, idx, arr) => { const lab = labelQuotes(arr.map((x: any) => ({ id: String(x.id), supplier_id: x.supplier_id, option_no: x.option_no }))).get(String(q.id)); const m = supMeta[String(q.supplier_id)] || {}; const r = m.r || {}; const revealed = revealedQ.has(String(q.id)); return { id: q.id, supplier_ref: revealed ? q.supplier_id : null, label: lab ? lab.en : 'Supplier ' + supplierLabel(idx), label_ar: lab ? lab.ar : null, option_no: q.option_no ?? 1, price: q.quote_amount, reveal_fee: revealFee(Number(feeBaseOf(q) ?? 0), cfg), price_stated: priceStated(q, 'en'), price_stated_ar: priceStated(q, 'ar'), gross_amount: q.gross_amount ?? null, discount_amount: q.discount_amount ?? null, discount_label: q.discount_label ?? null, vat_treatment: q.vat_treatment ?? null, vat_stated: vatStated(q, 'en'), vat_stated_ar: vatStated(q, 'ar'), fee_basis: feeBasisLine(feeBaseOf(q), cfg ? cfg.standard_reveal_rate : null, 'en'), fee_basis_ar: feeBasisLine(feeBaseOf(q), cfg ? cfg.standard_reveal_rate : null, 'ar'), notes: q.notes, lead_time: q.lead_time, validity: q.validity, expires_at: q.expires_at ?? null, expired: q.expires_at ? (new Date(q.expires_at) < now) : false, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, review_notes: (reviewByQuote[String(q.id)] || []).map((n) => ({ code: n.code, severity: n.severity, line_no: n.line_no, en: n.en, ar: n.ar })), source: q.source || 'form', status: q.status, revealed, revealed_at: revealAtByQuote[String(q.id)] || null, supplier_name: revealed ? (m.name ?? null) : undefined, total_charged: revealed ? (chargedByQuote[String(q.id)] ?? null) : undefined, guarantee: revealed ? (guaranteeByQuote[String(q.id)] || null) : undefined, rated: ratedTx.has(String(txByQuote[String(q.id)] || '')), rating: revealed ? (r.value ?? null) : ratingBand(r.value), rating_count: revealed ? (r.count ?? 0) : reviewCountBand(r.count), rating_source: revealed ? (r.source || null) : undefined, match_reason: revealed ? (reasonBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null) : undefined, match_pct: pctBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null, emirate: revealed ? (m.emirate ?? null) : undefined, verified: m.verified ?? false, years_active: revealed ? (m.years_active ?? null) : yearsBand(m.years_active), jobs_won: m.jobs_won ?? 0, win_rate: revealed ? (m.win_rate ?? null) : undefined,
          // W9 badges: only measured facts, null when absent. Pre-reveal the response rate is floored
          // to a 10% band and the rating stays out (the banded rating above already shows it), so a
          // badge can never be an exact fingerprint of one company.
          badges: { licence_verified: m.vb ? m.vb.licence_verified : false, documents_complete: m.vb ? m.vb.documents_complete : false, response_rate: m.rr == null ? null : (revealed ? m.rr : Math.floor((m.rr <= 1 ? m.rr : m.rr / 100) * 10) / 10), jobs_completed: Number(m.jobs_won) > 0 ? Number(m.jobs_won) : null, rating: revealed && typeof r.value === 'number' ? r.value : null } }; }) });
      // EACH mapRow AWAITS A STORAGE ROUND TRIP (signedDrawing) THAT THE OLD LOOP SERIALISED. Up to
      // 25 top-level rows plus every child were signed one at a time — an N+1 sequential-await chain
      // on the Overview's critical path (e2e run 6, 14 Sep 2026: 6.5s vs run 5's 1.6-1.8s, growing
      // with the number of ZZ DEMO rows that carry a drawing). None of these rows' signed URLs depend
      // on each other, so they run together; wall time is now the slowest ONE, not the sum.
      const out = await Promise.all((tops || []).map(async (i) => {
        // mapRow returns an object literal, so its inferred type has no is_combined / child_count /
        // children. The combined-project decoration below is genuinely dynamic - only split parents
        // get it - so the row is typed as an open record rather than the literal's shape.
        const row: Record<string, any> = await mapRow(i);
        const ch = kidsByParent[String(i.id)];
        if (ch && ch.length) { row.is_combined = true; row.child_count = ch.length; row.children = await Promise.all(ch.map((c: any) => mapRow(c))); }
        return row;
      }));
      // `locale` added 5 Aug 2026. customers.locale was stored and, from the portal's point of
      // view, never served: the brief called it "stored and never served", which measurement shows
      // is not quite right - `me` returns the whole customer row via select('*'), locale included.
      // But THE PORTAL NEVER CALLS `me`. It calls `kyc state` and this action, so the field was on
      // the wire only where nothing was listening, and CustomerPortal fell back to
      // localStorage['qd-lang'] and the NEXT_LOCALE cookie. A customer who set Arabic on one device
      // got English on the next, and the Arabic journey exercised a path the portal could not reach.
      // promo is always false: there is no promotional reveal rate (founder, 6 Sep 2026); the key stays so no reader breaks.
      // The ladder's numbers, from the same row the refund sweep and the supplier email read, so the
      // portal's timeline cannot drift from what is actually enforced (5 / 3 / 7-14 on 14 Sep 2026).
      const pc = (cfg || {}) as unknown as Record<string, number | null | undefined>;
      const guarantee_terms = { window_days: pc.refund_window_working_days ?? null, chase_after_days: pc.chase_after_working_days ?? null, bank_min_days: pc.bank_settlement_working_days_min ?? null, bank_max_days: pc.bank_settlement_working_days_max ?? null };
      return J({ inquiries: out, locale: cust.locale || null, promo: false, guarantee_terms });
    }

    // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the customer answers in the portal.
    // The routine records it (owner check, open state, which option, when, channel 'portal', inquiry
    // closed on "no"); customer_support then confirms or apologises in the registered language.
    if (action === 'spec_offer_reply') {
      const offerId = Number(body.offer_id); const choice = String(body.choice || '').trim();
      if (!Number.isFinite(offerId) || offerId <= 0 || !choice) return J({ error: 'bad_request' }, 400);
      const { data: res, error: aErr } = await admin.rpc('fn_spec_offer_answer', { p_offer: offerId, p_customer: cust.id, p_choice: choice, p_channel: 'portal' });
      if (aErr) { console.error('spec_offer_reply:', aErr.message); return J({ error: 'spec_offer_failed' }, 500); }
      if (!res?.ok) return J({ error: res?.error || 'spec_offer_failed', state: res?.state ?? null }, res?.error === 'not_your_offer' ? 403 : res?.error === 'not_found' ? 404 : 409);
      try {
        const { data: o } = await admin.from('spec_alternative_offer').select('id,inquiry_id,item,label_en,label_ar,requested,alternatives,accepted_value').eq('id', offerId).maybeSingle();
        const { data: c } = await admin.from('customers').select('email,locale').eq('id', cust.id).maybeSingle();
        const { data: inqRow } = await admin.from('inquiries').select('rfq_no').eq('id', String(res.inquiry_id)).maybeSingle();
        const lang = asLocale(c?.locale ?? cust.locale);
        const arTexts = res.state === 'accepted' && o ? await arabicTextsFor(defaultDeps(admin, 'customer_api'), lang, offerTexts(o as OfferForText), { fileOnly: true }) : undefined;
        const msg = res.state === 'accepted' ? acceptedMessage(o as OfferForText, lang, { rfqNo: inqRow?.rfq_no, arTexts }) : apologyMessage(o as OfferForText, lang, 'declined', { rfqNo: inqRow?.rfq_no });
        const kind = res.state === 'accepted' ? 'accepted' : 'apology_declined';
        // customer_support asks and answers the alternatives question (finding SP-F-08, 22 Sep 2026;
        // the same change in sales_engineer/index.ts carries the reasoning). The `type` is unchanged.
        const base = { type: 'spec_offer_' + kind, kind: 'customer_support_spec_offer_' + kind, to_role: 'customer', inquiry_id: String(res.inquiry_id), subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'customer_support', sender: 'customer_support' };
        const rows: Record<string, unknown>[] = [];
        if (c?.email) rows.push({ ...base, channel: 'email', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:email` });
        // WhatsApp consent is the confirmed WhatsApp number, nothing else (#322): the row names the customer by
        // email and the a03 trigger addresses it to their confirmed number, or records why it was not sent.
        if (c?.email) rows.push({ ...base, channel: 'whatsapp', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:whatsapp` });
        // An Arabic confirmation with a line not yet reasoned is PARKED with its placeholders and sent by
        // fn_arabic_outbound_flush the moment the Arabic exists — never sent with English in it.
        if (msg.untranslated?.length && rows.length) {
          const { error: pErr } = await admin.rpc('fn_arabic_outbound_park', { p_texts: msg.untranslated, p_rows: rows });
          // A failed park is an error, never a send: the message has placeholders in it.
          if (pErr) throw new Error('the Arabic confirmation could not be parked: ' + pErr.message);
          rows.length = 0;
        }
        const { data: sent } = rows.length ? await requestDelivery(admin, rows) : { data: [] };
        await admin.rpc('fn_spec_offer_mark', { p_offer: offerId, p_action: 'answered', p_notification_ids: (sent || []).map((d) => d.notification_id).filter((x) => typeof x === 'number') });
      } catch (e) {
        const why = String((e as Error)?.message || e);
        console.error('spec_offer_reply: confirmation not queued —', why);
        // The answer is recorded; the confirmation is not. It is never silent: customer_support's CEO report names it.
        try {
          await admin.rpc('fn_support_report_to_ceo', { p_idempotency_key: 'spec_offer_confirmation_failed:' + offerId, p_severity: 'routine',
            p_subject: 'A customer\'s choice was recorded but its confirmation could not be queued', p_evidence: { offer_id: offerId, error: why.slice(0, 500) },
            p_attempted: ['recorded the answer', 'queued or parked the confirmation'], p_requested: 'Send the confirmation by hand or re-queue it.' });
        } catch (_e) { /* the console line above still stands */ }
      }
      return J({ ok: true, state: res.state, inquiry_closed: !!res.inquiry_closed });
    }

    if (action === 'complete_inquiry') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary,status,hired_supplier_id').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Reveal this supplier first.' }, 403);
      // HIRE IS IDEMPOTENT (customer-portal audit CP-11, 22 Sep 2026). Every press of "Hire" wrote
      // the same row again AND re-ran notifyLosers, so the losing suppliers were emailed "the
      // customer chose another supplier" once per press. The second press of the same button on
      // the same supplier now answers ok and sends nothing; a DIFFERENT supplier on a job already
      // awarded is refused rather than silently re-awarded.
      // A hire the day-3/day-14 follow-up recorded (hired_supplier_id only) is completed by this press, not
      // answered "already completed" over a request left 'revealed' with its losing suppliers never told (lib/hire.ts).
      const step = hireStep(inq, q.supplier_id);
      if (step.kind !== 'award') {
        return step.kind === 'already_completed'
          ? J({ ok: true, already_completed: true })
          : J({ ok: false, error: 'already_hired', code: 'already_hired', message: 'You have already hired a supplier for this request.', message_ar: 'لقد اخترت مورّدًا لهذا الطلب بالفعل.' }, 409);
      }
      // The award itself is the lock: only the press that changes the row wins it, so two presses that arrive
      // together still send one round of notices.
      const award = admin.from('inquiries').update({ status: 'completed', hired_supplier_id: q.supplier_id, completed_at: new Date().toISOString(), outcome: 'hired' }).eq('id', inq.id);
      const { data: won } = step.from === 'unhired'
        ? await award.is('hired_supplier_id', null).select('id')
        : await award.eq('hired_supplier_id', q.supplier_id).neq('status', 'completed').select('id');
      if (!won || !won.length) return J({ ok: true, already_completed: true });
      await notifyLosers(String(inq.id), inq.summary ?? null, Number(q.supplier_id));
      return J({ ok: true });
    }

    if (action === 'edit_inquiry') {
      const iid = String(body.inquiry_id || '');
      const patch = (body.patch && typeof body.patch === 'object') ? body.patch : body;
      // WHAT A CUSTOMER MAY EDIT IN PLACE (customer-portal audit CP-04, 22 Sep 2026). This forwarded
      // spec, boq, trades, keywords and raw_input straight into fn_edit_inquiry, which writes them
      // to the row with no anonymity scrub and no requirements check — the two gates create_inquiry
      // puts every one of those fields through (scrubDeep / redactBoq for the customer's identity,
      // intake_requirements for the answers suppliers quote against). An edit could therefore put
      // the customer's own name into a BOQ line the suppliers read, or empty the requirements that
      // the hold rule measures quotes against.
      //   Only the three fields that carry no structure are editable here: the summary (scrubbed
      //   with the same scrubber every supplier-facing text goes through), the budget and the
      //   emirate. A change to the scope, the BOQ or the trades is a new request — the portal's own
      //   Edit form offers nothing else.
      const clean: Record<string, unknown> = {};
      for (const k of ['budget', 'emirate']) if (patch[k] !== undefined) clean[k] = patch[k];
      if (patch.summary !== undefined) {
        const bn = await buyerNameOf(String(iid));
        // A name we could not read is a name we cannot scrub: the edit is refused rather than
        // written unscrubbed (the rule buyerName/scrubIdentity already enforce on every send).
        if (!bn.resolved) return J({ ok: false, error: 'summary_not_editable', code: 'summary_not_editable', message: 'We could not check this text for your own details just now. Please try again in a moment.', message_ar: 'تعذّر التحقق من خلو النص من بياناتك الآن. يُرجى المحاولة بعد لحظات.' }, 503);
        clean.summary = scrubIdentity(String(patch.summary).slice(0, 500), bn.name, []) || '';
      }
      if (!Object.keys(clean).length) return J({ ok: false, error: 'nothing_editable', code: 'nothing_editable', message: 'Only the description, the budget and the emirate can be changed. For anything else, please post a new request.', message_ar: 'يمكن تعديل الوصف والميزانية والإمارة فقط. لأي تغيير آخر يُرجى إنشاء طلب جديد.' }, 400);
      const { data: r } = await admin.rpc('fn_edit_inquiry', { p_inquiry: iid, p_customer: cust.id, p_patch: clean });
      if (r?.error) return J({ error: r.message || r.error, editable_until: r.editable_until }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'cancel_inquiry') {
      const iid = String(body.inquiry_id || '');
      const reason = body.reason ? String(body.reason).slice(0, 300) : null;
      const { data: r } = await admin.rpc('fn_cancel_inquiry', { p_inquiry: iid, p_customer: cust.id, p_reason: reason });
      if (r?.error) return J({ error: r.message || r.error }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }
}
