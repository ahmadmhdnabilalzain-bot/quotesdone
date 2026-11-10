// THE MARKETING SEAT'S DUTY LIST (post_results and scorecard since 23 Sep 2026, instruction 865): the 'duties' action runs every entry on every
// call (resilience_ping step 'marketing', every 30 minutes) before fn_marketing_tick. Owner of every entry: the marketing seat.
//
// The builds that fill it (founder instruction 721, 22 Sep 2026):
//   * publishing / analytics / ad spend — schedule the approved posts through Postiz, read each channel's
//     analytics, and report each platform day of spend with fn_marketing_records_ad_spend (never book it);
//   * the social inbox — answer DMs from company knowledge (fn_marketing_assist) and hand a conversation to
//     the founder with fn_marketing_asks_the_founder_to_take_over the moment someone asks for a person.
//
// HOW TO ADD ONE. Append an entry. A duty decides its own due-ness (return { due: false } when it is not
// time) and returns counts. It throws only on a real failure: the runtime turns a throw into an IT finding
// owned by the marketing seat (fn_it_duty_settle 'marketing_duties'), closed on the first run it passes.
// The Meta and Postiz credentials may be read ONLY under supabase/functions/marketing/ (rule 641,
// scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs). Email and WhatsApp go through
// customer_support (_shared/deliver.ts); replies on the company's own social channels are this seat's.

// Split into ./duties/*.ts on 9 Nov 2026 (a pure move); this file re-exports the same names.
export type { Admin, Duty, DutyContext } from './duties/types.ts';
export { isolated, marketingAsk, Skip } from './duties/shared.ts';
export { MAX_CLASS_QUESTIONS, reviveHeldComments, socialComments } from './duties/social_comments.ts';
export type { HeldCommentRow, ReviveIO } from './duties/social_comments.ts';
export { specHashText, visibleText } from './duties/platform_spec_freshness.ts';
export { profileText } from './duties/profile_text.ts';
export { geoAudit, judgeTrend, reviews, trendWatch } from './duties/trends_geo.ts';
export { blogArticle, draftJob, GIVE_UP_AFTER, reviewJob, reviseJob, runOneJob } from './duties/blog_article.ts';
export type { FailedRun, JobIO, ModelAnswer, ModelJob } from './duties/blog_article.ts';
export { DUTIES } from './duties/registry.ts';
