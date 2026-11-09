import { SEAT } from '../quote_review.ts';
import { type ReviewRepo } from './types.ts';

// ---------------------------------------------------------------------------------------------
// The production repository: the service-role client. It never deletes: the thread is a
// conversation store (founder, 14 Sep 2026: "all conversations need to be saved").
// ---------------------------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
export function supabaseReviewRepo(admin: any): ReviewRepo {
  // deno-lint-ignore no-explicit-any
  const must = <T = any>(r: { data?: T; error?: { message: string } | null }): T => { if (r.error) throw new Error(r.error.message); return r.data as T; };
  const COLS = 'id,inquiry_id,supplier_id,owner_email,status,choice,original_file_path,original_file_name,extracted,working,last_review,reviewing_since,total_amount,currency,submitted_quote_ids,completed_at,created_at,updated_at';
  return {
    async review(inquiryId, supplierId) { return must(await admin.from('quote_reviews').select(COLS).eq('inquiry_id', inquiryId).eq('supplier_id', supplierId).maybeSingle()) ?? null; },
    async reviewsOf(supplierId) { return must(await admin.from('quote_reviews').select('inquiry_id,status,updated_at').eq('supplier_id', supplierId).limit(200)) ?? []; },
    async createReview(r) {
      // Two tabs opening the same job at once: the unique (inquiry, supplier) pair decides, and the loser reads the winner.
      const ins = await admin.from('quote_reviews').insert({ ...r, status: 'open', owner_seat: SEAT }).select(COLS).single();
      if (!ins.error) return ins.data;
      const got = must(await admin.from('quote_reviews').select(COLS).eq('inquiry_id', r.inquiry_id).eq('supplier_id', r.supplier_id).maybeSingle());
      if (!got) throw new Error(ins.error.message);
      return got;
    },
    async updateReview(id, patch) { must(await admin.from('quote_reviews').update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id)); },
    async claim(id, from, to) {
      const now = new Date().toISOString();
      const rows = must<{ id: string }[]>(await admin.from('quote_reviews').update({ status: to, reviewing_since: now, updated_at: now }).eq('id', id).in('status', from).select('id'));
      return Array.isArray(rows) && rows.length > 0;
    },
    async addMessage(m) { return must(await admin.from('quote_review_messages').insert(m).select('id,review_id,role,kind,body,body_ar,attachments,issues,created_at').single()); },
    async messages(reviewId) { return must(await admin.from('quote_review_messages').select('id,review_id,role,kind,body,body_ar,attachments,issues,created_at').eq('review_id', reviewId).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(500)) ?? []; },
    async requests(reviewId, onlyOpen) { let q = admin.from('quote_review_request').select('*').eq('review_id', reviewId); if (onlyOpen) q = q.eq('state', 'open'); return must(await q.order('id', { ascending: true })) ?? []; },
    async addRequests(rows) { if (rows.length) must(await admin.from('quote_review_request').insert(rows)); },
    async closeRequests(ids, state, messageId) { if (ids.length) must(await admin.from('quote_review_request').update({ state, answered_message_id: messageId, answered_at: new Date().toISOString() }).in('id', ids).eq('state', 'open')); },
    async storeFile(path, bytes, mime) { const up = await admin.storage.from('quote-files').upload(path, bytes, { contentType: mime, upsert: false }); return !up.error; },
    async signFile(bucket, path) { try { const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; } catch (_e) { return null; } },
    async recordReader(inquiryId, supplierId, model) {
      const { error } = await admin.from('quote_extraction_model').upsert({ subject_key: `${supplierId}:${inquiryId}`, model, extracted_at: new Date().toISOString() });
      if (error) console.error('quote_extraction_model: ' + error.message);
    },
    async log(counts, note) { try { await admin.from('agent_runs').insert({ agent: SEAT, status: 'ok', started_at: new Date().toISOString(), finished_at: new Date().toISOString(), counts, note: note.slice(0, 500) }); } catch (_e) { /* the trail never blocks the conversation */ } },
  };
}
