// THE MARKETING SEAT'S DUTY LIST — empty today, and real: the 'duties' action runs every entry on every
// call (resilience_ping step 'marketing', every 30 minutes) before fn_marketing_tick.
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
import { timedFetch } from '../_shared/timed_fetch.ts';
import { processComment, readX, readYouTube, youtubeToken, type CommentEvent } from '../_shared/marketing_social_comments.ts';
import { adminStore } from '../_shared/marketing_social_store.ts';
import { wantsHuman } from '../marketing_social_inbox/reply.ts';

// deno-lint-ignore no-explicit-any
export type Admin = any;
export interface DutyContext {
  admin: Admin;
  sec: (key: string) => Promise<string | undefined>;
  now: Date;
}
export interface Duty {
  name: string;
  run: (ctx: DutyContext) => Promise<Record<string, unknown>>;
}


// SOCIAL COMMENTS ON X AND YOUTUBE (instruction 866, 23 Sep 2026). Instagram and Facebook comments arrive by
// Meta webhook at marketing_social_inbox; X and YouTube have no webhook we can use, so each run reads what is
// new and hands every comment to the same policy. A platform with no credential is skipped and SAYS so
// (skipped: 'x: no x_user_token') — reading it is a count, never a silent zero. Credentials, by key name:
//   x_user_token, x_user_id                        (OAuth 2.0 user token: tweet.read tweet.write users.read)
//   youtube_client_id, youtube_client_secret, youtube_refresh_token, youtube_channel_id (scope youtube.force-ssl)
// Only comments from the last 24 hours are taken: an old comment answered today reads as a bot catching up.
export const socialComments: Duty = {
  name: 'social_comments',
  async run({ admin, sec, now }) {
    const gateway = Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway';
    const counts: Record<string, unknown> = { skipped: [] as string[] };
    const fresh = (e: CommentEvent) => now.getTime() - e.at.getTime() < 24 * 3600 * 1000;
    const runAll = async (platform: string, events: CommentEvent[], token: string) => {
      const store = adminStore(admin, timedFetch, async () => token, gateway);
      const out: Record<string, number> = {};
      for (const ev of events.filter(fresh)) {
        const o = await processComment(store, ev, wantsHuman(ev.text)).catch((e) => 'error:' + String(e?.message || e).slice(0, 60));
        out[o] = (out[o] || 0) + 1;
      }
      counts[platform] = { read: events.length, outcomes: out };
    };
    const [xt, xu] = [await sec('x_user_token'), await sec('x_user_id')];
    if (xt && xu) {
      const { data } = await admin.from('social_message').select('meta_message_id').eq('platform', 'x').eq('direction', 'in')
        .order('occurred_at', { ascending: false }).limit(1).maybeSingle();
      await runAll('x', await readX(timedFetch, xt, xu, data?.meta_message_id ?? null), xt);
    } else (counts.skipped as string[]).push('x: no x_user_token / x_user_id');
    const [ci, cs, rt, ch] = [await sec('youtube_client_id'), await sec('youtube_client_secret'), await sec('youtube_refresh_token'), await sec('youtube_channel_id')];
    if (ci && cs && rt && ch) {
      const token = await youtubeToken(timedFetch, ci, cs, rt);
      await runAll('youtube', await readYouTube(timedFetch, token, ch), token);
    } else (counts.skipped as string[]).push('youtube: no youtube_client_id / _client_secret / _refresh_token / _channel_id');
    return counts;
  },
};

export const DUTIES: Duty[] = [socialComments];
