// THE INVITATION OPEN (marketing, 3 Nov 2026). Founder: "I want us to know when someone opened our invitation email. If
// they read our email and chose not to register, this is very valuable information for the team and the CEO".
//
// THE RULING THIS CHANGES: founder_instruction 1301 (27 Oct 2026), "safer to not send links" -- the campaign email is plain
// text with no link (m365_lane.ts campaignMail). An open can only be seen through an image our own server serves, and its
// URL is a link inside an HTML part. So it is contained:
//   * app_secrets.invite_open_tracking: 'off' or a whole percentage (seeded '20'). 0 / 'off' = no call to the database and
//     the message is exactly today's (m365Mime with no html; open_tracking.test.ts compares the bytes).
//   * the TRACKED SHARE is chosen in the database (fn_invite_open_token: a fixed hash of the lead, so the arms compare);
//     a supplier_invite_seed (placement test) is never tracked, so GlockApps keeps measuring the untracked email.
//   * a tracked email is multipart/alternative: the SAME text part, byte for byte, and an HTML twin of that text with ONE
//     1x1 image at https://quotesdone.com/u/o/<token>.gif. No other image, no link, no style sheet, no tracking domain.
//   * the token is 32 random hex characters from the database, never the address or the lead id.
// The route that serves the image and records the open: src/app/u/o/[token]/route.ts -> fn_email_open_record.
// prevented by: supabase/functions/send_outbox/open_tracking.test.ts
import { M365_SEED_KIND } from './m365_lane.ts';

export const OPEN_TRACKED_TYPES = ['supplier_invite', 'supplier_invite_nudge'] as const;
export const OPEN_PATH = '/u/o/';
const TOKEN = /^[0-9a-f]{32}$/;
/** Our own hosts only: the pixel is never served from the project's supabase.co host or anyone else's. */
const FIRST_PARTY = /^(?:www\.)?quotesdone\.(?:com|ae)$/;

/** app_secrets.invite_open_tracking as a share 0-100: 'off', '', anything not a whole number = 0; '20' or '20%' = 20.
 *  The same reading as fn_invite_open_share in the database. */
export function openShare(v: string | undefined): number {
  const m = /^\s*(\d{1,3})\s*%?\s*$/.exec(String(v ?? ''));
  return m ? Math.min(100, parseInt(m[1], 10)) : 0;
}

/** Whether a row can carry the image at all (before the share is applied in the database). */
export function openTracks(row: { type?: unknown; kind?: unknown; to_role?: unknown; lang?: unknown }): boolean {
  return row.to_role === 'supplier' && (OPEN_TRACKED_TYPES as readonly unknown[]).includes(row.type) && row.kind !== M365_SEED_KIND && row.lang !== 'ar';
}

/** The pixel base from unsubscribe_public_base (https://quotesdone.com/u/unsubscribe -> https://quotesdone.com/u/o/), or ''
 *  when that base is not our own https domain: then nothing is tracked. */
export function pixelBase(unsubBase: string | undefined): string {
  try {
    const u = new URL(String(unsubBase || ''));
    return u.protocol === 'https:' && FIRST_PARTY.test(u.hostname) ? u.origin + OPEN_PATH : '';
  } catch { return ''; }
}

/** The image URL for a token from fn_invite_open_token, or '' for a missing or malformed one (the email is then untracked). */
export function pixelUrl(base: string, token: unknown): string {
  const t = String(token ?? '');
  return base && TOKEN.test(t) ? `${base}${t}.gif` : '';
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** The HTML twin of the plain text: each paragraph a <p>, each line break a <br>, every character escaped, and the one
 *  1x1 image last. Nothing else: no link, no other image, no style sheet, no web font. */
export function invitationHtml(text: string, pixel: string): string {
  const paras = String(text || '').replace(/\r\n?/g, '\n').split(/\n{2,}/).map((p) => '<p>' + esc(p).split('\n').join('<br>') + '</p>');
  return '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><div dir="ltr">' + paras.join('') +
    `<img src="${esc(pixel)}" width="1" height="1" alt="" style="display:block;width:1px;height:1px;border:0">` +
    '</div></body></html>';
}
