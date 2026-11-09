// customer_api — after the job: rate_supplier, add_review_photos, review_photos, supplier_history.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { NOT_LIVE_QUOTE_IN } from '../../_shared/quote_live.ts';
import { parseRatingInput } from '../rating_input.ts';
import { parseReviewPhotos } from '../review_photos.ts';
import { SANCTIONED_REFUSAL, sanctionedLead } from '../../_shared/sanctioned.ts';
import { type ActionCtx, J, admin } from '../context.ts';
import { signedReviewPhotos } from '../lib/storage.ts';
import { band, ratingOf } from '../lib/pricing.ts';

export async function reviewActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, cust } = c;
    // A CUSTOMER IS NEVER BLOCKED FROM RATING (operator, 17 Sep 2026). Measured on the production
    // journey: every star press returned HTTP 500 — SQLSTATE 23514, `reviews_reason_required` — and
    // public.reviews held 0 rows, so no rating had ever succeeded. The widget sends stars and no
    // comment; the constraint demanded a comment of 10+ characters. The constraint now reads
    // "a comment, IF GIVEN, must be 10+ characters"
    // (scripts/sql/a_customer_is_never_blocked_from_rating.sql) and this handler refuses a short one
    // BEFORE the write, in words the customer can read, rather than letting the database refuse it
    // as a 500. Who may rate and when is unchanged: a transaction on this quote, 1..5, one per job.
    if (action === 'rate_supplier') {
      const qid = String(body.quote_id || '');
      // The rule (stars alone suffice; a comment, if given, is 10+ characters) lives in
      // ./rating_input.ts with its tests, so the handler and the test read the same code.
      const parsed = parseRatingInput(body);
      if (!parsed.ok) return J({ error: parsed.error, code: parsed.code }, 400);
      const { rating, comment } = parsed;
      const { data: q } = await admin.from('quotes').select('id,supplier_id,inquiry_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found', code: 'not_found' }, 404);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'You can only rate a supplier you have revealed and dealt with.', code: 'forbidden' }, 403);
      const { error } = await admin.from('reviews').upsert({ supplier_id: q.supplier_id, customer_id: cust.id, inquiry_id: q.inquiry_id, transaction_id: tx.id, rating, comment }, { onConflict: 'transaction_id' });
      if (error) {
        // A 500 ON A USER ACTION IS ITSELF A DEFECT: the customer sees a broken product and we learn
        // nothing. Class 23 is an integrity violation — the database REFUSED the request, which is a
        // 4xx. Anything else is ours, and is still answered in words rather than with a raw driver
        // string that would put a constraint name in front of a customer.
        const sqlstate = String((error as { code?: string }).code || '');
        console.error('rate_supplier refused', JSON.stringify({ sqlstate, message: error.message, quote_id: qid }));
        if (sqlstate.startsWith('23')) return J({ error: 'We could not accept that rating. Please check what you entered and try again.', code: 'review_refused' }, 400);
        return J({ error: 'Could not save your rating. Please try again in a moment.', code: 'review_save_failed' }, 500);
      }
      await admin.rpc('recompute_supplier_rating', { p_supplier: q.supplier_id });
      return J({ ok: true });
    }

    // PHOTOS ON A POST-JOB REVIEW (T2). Only after the customer has rated (a review row exists for
    // THEIR transaction on this quote), at most 5 per review, images only — the rule is
    // ./review_photos.ts with its tests. Stored in the PRIVATE review-photos bucket under a random
    // name (never the customer's file name), camera metadata cut, served back only as signed URLs.
    // The supplier sees them in its Projects tab, which lists post-reveal jobs only.
    if (action === 'add_review_photos') {
      const qid = String(body.quote_id || '');
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'You can only add photos to a supplier you have revealed and dealt with.', code: 'forbidden' }, 403);
      const { data: rv } = await admin.from('reviews').select('id,photo_paths').eq('transaction_id', tx.id).maybeSingle();
      if (!rv) return J({ error: 'Rate the supplier first, then add photos.', code: 'review_required' }, 400);
      const existing: string[] = Array.isArray(rv.photo_paths) ? rv.photo_paths : [];
      const parsed = parseReviewPhotos(body.photos, existing.length);
      if (!parsed.ok) return J({ error: parsed.error, code: parsed.code }, 400);
      const added: string[] = [];
      for (const ph of parsed.photos) {
        const path = tx.id + '/' + crypto.randomUUID() + '.' + ph.ext;
        const up = await admin.storage.from('review-photos').upload(path, ph.bytes, { contentType: ph.mime, upsert: false });
        if (up.error) { if (added.length) await admin.storage.from('review-photos').remove(added); console.error('add_review_photos upload', up.error.message); return J({ error: 'Could not save your photos. Please try again in a moment.', code: 'photo_save_failed' }, 500); }
        added.push(path);
      }
      const all = existing.concat(added);
      // Written only if the row still holds what we read (two tabs, a double submit): otherwise the
      // later write would drop the earlier one's paths and both would pass the cap. Paths are
      // <uuid>/<uuid>.<ext>, so the array literal needs no quoting. The database check (max 5) is the
      // last line either way.
      const { data: upd, error } = await admin.from('reviews').update({ photo_paths: all }).eq('id', rv.id).filter('photo_paths', 'eq', '{' + existing.join(',') + '}').select('id');
      if (error || !upd || upd.length !== 1) { await admin.storage.from('review-photos').remove(added); console.error('add_review_photos update', error?.message || 'row changed'); return J({ error: 'Could not save your photos. Please try again in a moment.', code: 'photo_save_failed' }, error ? 500 : 409); }
      return J({ ok: true, photo_count: all.length, photo_urls: await signedReviewPhotos(all) });
    }
    // Read-only: the photos already on the customer's own review, so the picker shows them after a reload.
    if (action === 'review_photos') {
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', String(body.quote_id || '')).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Not found', code: 'not_found' }, 404);
      const { data: rv } = await admin.from('reviews').select('photo_paths').eq('transaction_id', tx.id).maybeSingle();
      return J({ ok: true, photo_urls: await signedReviewPhotos((rv?.photo_paths as string[]) || []) });
    }

    if (action === 'supplier_history') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,supplier_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      if (await sanctionedLead(admin, q.supplier_id)) return J(SANCTIONED_REFUSAL, 403);  // founder instruction 516: never shown to a customer
      // The reveal check gates what is RETURNED, not what may be read, so the three reads that only
      // need q.supplier_id run beside it instead of one after another (14 Sep 2026: four sequential
      // round trips here, then three more below).
      const [{ data: tx }, { data: sup }, { data: projs }, mine, { count: sentAll }] = await Promise.all([
        // PAID MEANS revealed_at, EVERYWHERE (review of #850, 22 Sep 2026). This was the one door
        // that accepted a transactions row's existence as proof of payment; every other door —
        // fn_customer_document_refs, the vault, the guard — reads revealed_at. Measured on
        // production the same day: 0 rows disagree, so this is alignment, not a behaviour change.
        admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).not('revealed_at', 'is', null).maybeSingle(),
        admin.from('leads').select('id,company_name,emirate,phone,whatsapp,email,website,app_rating,app_reviews,description,capability_summary,founded_year,company_type').eq('id', q.supplier_id).maybeSingle(),
        admin.from('transactions').select('revealed_at,quote_amount,inquiries(category,emirate)').eq('supplier_id', q.supplier_id).order('revealed_at', { ascending: false }).limit(20),
        admin.from('inquiries').select('id').eq('customer_id', cust.id).limit(500),
        admin.from('inquiry_matches').select('inquiry_id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id),
      ]);
      if (!tx) return J({ error: 'Reveal this supplier first to see their profile.' }, 403);
      const projects = (projs || []).map((p: any) => ({ category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, month: p.revealed_at ? new Date(p.revealed_at).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }) : null, value_band: band(Number(p.quote_amount)) }));
      // §13 "History: 17 RFQs, 8 Orders" — TWO DIFFERENT NUMBERS, and this action served only the
      // second. projects[] is built from transactions, i.e. from PAID REVEALS, so an RFQ that was
      // sent to this supplier and never quoted was invisible: a supplier who received eleven of
      // this customer's briefs and answered none of them read as "no history", which is the
      // opposite of what the customer needs to know about them.
      //
      // SCOPED TO THIS CUSTOMER, deliberately. §13 is headed "Customer Supplier Relationship
      // Management" — it is this buyer's relationship with this supplier, not the supplier's
      // platform-wide record, which they can already see as the rating. The platform-wide count is
      // returned beside it and labelled, so the two can never be mistaken for one another.
      const myInqIds = mine.data?.map((r: any) => r.id) || [];
      let rfqsSent = 0, quotesBack = 0;
      if (myInqIds.length) {
        const [{ count: sent }, { count: back }] = await Promise.all([
          admin.from('inquiry_matches').select('inquiry_id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id).in('inquiry_id', myInqIds),
          admin.from('quotes').select('id', { count: 'exact', head: true }).eq('supplier_id', q.supplier_id).in('inquiry_id', myInqIds).not('status', 'in', NOT_LIVE_QUOTE_IN),
        ]);
        rfqsSent = sent || 0;
        quotesBack = back || 0;
      }
      const relationship = {
        rfqs_sent: rfqsSent, quotes_returned: quotesBack, orders: projects.length,
        response_rate_pct: rfqsSent ? Math.round((quotesBack / rfqsSent) * 100) : null,
        scope: 'this customer',
        rfqs_sent_platform_wide: sentAll || 0,
      };
      return J({ ok: true, supplier: sup ? { ...sup, rating_display: ratingOf(sup) } : null, projects, projects_count: projects.length, relationship /* rulings 1228/1229: the customer only ever gets our template quotation as a PDF, never the supplier's own file */ });
    }
}
