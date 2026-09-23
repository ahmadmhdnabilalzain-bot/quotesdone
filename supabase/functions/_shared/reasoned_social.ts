// reasoned_social — what a public comment on the company's channels IS, reasoned, never matched.
// Seat: marketing. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
//
// Decision point 73, marketing_social.comment_classify. marketing_social_comments.ts classify() read the
// class off regex lists (RULES / ABUSE / ASKS): 'court' in a sentence made it sensitive_legal, 'stupid' hid a
// comment, a '?' made a question. The class decides whether a person's comment is HIDDEN, answered or handed
// to another seat, so it is now reasoned among the eight policy classes below (think(), the same engine as every
// migrated point). Held: null, queued under 'social_comment_class:<platform>:<id>'; processComment then hides
// nothing and says nothing, and reasoned_delivery.ts runs the comment through the policy when the hold lifts.
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';
import type { Class, Platform } from './marketing_social_comments.ts';

export const CLASSES: { id: Class; meaning: string }[] = [
  { id: 'spam_abuse', meaning: 'an insult or abuse aimed at us or others, or a spam pitch (followers, crypto, adult, unrelated promotion) — and it asks nothing and does not want to join or get a quote; a rude word inside a real question is NOT this' },
  { id: 'sensitive_legal', meaning: 'threatens legal action, police or a regulator, alleges fraud, or asks who a customer or supplier on a job is (identities stay anonymous)' },
  { id: 'complaint', meaning: 'a complaint about our service or a supplier: unanswered, overcharged, wants a refund, unhappy' },
  { id: 'supplier_enquiry', meaning: 'a company or tradesperson wanting to register, list their business or receive jobs as a supplier' },
  { id: 'sales_lead', meaning: 'someone who wants a quote, a price or a company for a specific job of their own' },
  { id: 'question', meaning: 'a question about how QuotesDone works, fees, coverage or signing up' },
  { id: 'praise', meaning: 'thanks, praise or encouragement, and nothing else' },
  { id: 'off_topic', meaning: 'anything else: an emoji, a tag of a friend, chat unrelated to the company' },
];

/** The comment policy class of one public comment (surface marketing_social.comment_classify). */
/** `retry`: a re-run of a comment whose first held question is already closed (a replay that died): a fresh dedupe key. */
export async function commentClass(deps: ThinkDeps, o: { platform: Platform; commentId: string; authorId: string; text: string; retry?: string }): Promise<Reasoned<Class>> {
  const result = await think(deps, {
    seat: 'marketing', surface: 'marketing_social.comment_classify', question: o.text.slice(0, 4000),
    dedupeKey: 'social_comment_class:' + o.platform + ':' + o.commentId + (o.retry ? ':' + o.retry : ''),
    subject: { platform: o.platform, message_id: o.commentId, user_id: o.authorId },
    context: { audience: 'visitor' },
    decision: { name: 'comment_class', options: CLASSES },
  });
  const choice = result.status === 'answered' ? result.decision?.choice ?? null : null;
  return { value: CLASSES.some((c) => c.id === choice) ? choice as Class : null, result };
}
