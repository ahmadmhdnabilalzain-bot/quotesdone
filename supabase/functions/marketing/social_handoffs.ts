// THE TWO CONVERSATIONS A PUBLIC COMMENT STARTS (marketing, 23 Sep 2026). Lives in the seat's function directory
// so scripts/checks/payments_are_the_accountant.test.mjs finds each producer; used by the comment store
// (_shared/marketing_social_store.ts) for both the Meta webhook and the marketing duty. Marketing closes each
// one itself once the receiving seat has answered (fn_marketing_social_handoffs_close).
import type { Class, CommentEvent, HandoffType } from '../_shared/marketing_social_comments.ts';

// deno-lint-ignore no-explicit-any
export async function raiseSocialHandoff(admin: any, type: HandoffType, ev: CommentEvent, cls: Class, extra?: Record<string, unknown>): Promise<number | null> {
  const subject = { p_subject_table: 'social_message', p_subject_id: ev.platform + ':' + ev.commentId };
  const payload = { platform: ev.platform, account: ev.accountId, comment: ev.commentId, handle: ev.handle, text: ev.text.slice(0, 1000),
    thread: ev.threadId, classification: cls, ...(extra || {}) };
  const { data, error } = type === 'social.lead'
    ? await admin.rpc('fn_seat_handoff', { p_from: 'marketing', p_to: 'sales_engineer', p_type: 'social.lead', ...subject,
        p_payload: { ...payload, waiting_for: 'sales_engineer to answer the commenter privately' } })
    : await admin.rpc('fn_seat_handoff', { p_from: 'marketing', p_to: 'customer_support', p_type: 'social.escalation', ...subject,
        p_payload: { ...payload, waiting_for: 'customer_support to answer the commenter privately' } });
  if (error) throw new Error('handoff: ' + error.message);
  return (data as number) ?? null;
}
