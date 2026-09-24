// THE FOUNDER'S REPLY TO THE MONTHLY SOCIAL CALENDAR (marketing, 23 Sep 2026).
//
// Founder, founder_instruction 872: "it's going to be shared with me on the email ... I can reply to the email
// and say approve and that's it". The calendar email carries an unguessable token twice: in its Reply-To
// (calendar+<token>@mail.quotesdone.com) and in its subject ("[ref <token>]"), because a mail client may reply
// to either. resend_inbound reads the reply with these two pure functions and hands the verdict to
// fn_marketing_calendar_reply, which checks the sender, the SPF/DKIM/DMARC verdict, the token, the content
// hash and the month before anything is approved. Tested in marketing_calendar_mail.test.ts.

const TOKEN = /[0-9a-f]{32}/;

/** The calendar token of a reply, from the address it was sent to or from its subject; null when neither. */
export function calendarTokenOf(m: { to?: string | null; subject?: string | null }): string | null {
  const to = String(m.to || '').toLowerCase();
  const t = to.match(/^calendar\+([0-9a-f]{32})@mail\.quotesdone\.com$/);
  if (t) return t[1];
  const s = String(m.subject || '').toLowerCase().match(/\[ref ([0-9a-f]{32})\]/);
  return s && TOKEN.test(s[1]) ? s[1] : null;
}

/** True when this inbound mail is a reply to a calendar email (by address or subject). */
export function isCalendarReply(m: { to?: string | null; subject?: string | null }): boolean {
  return calendarTokenOf(m) !== null || /^calendar\+/i.test(String(m.to || ''));
}

/**
 * What the reply says, from its OWN words only: the quoted email below it is cut off (lines starting '>',
 * and everything from an "On ... wrote:" / "From:" / "-----Original Message-----" / Arabic "كتب" header on).
 * Used by replyIntent and, as the text of a change request, by fn_marketing_calendar_reply.
 */
export function ownWords(text: string | null | undefined): string {
  const own: string[] = [];
  const all = String(text || '').replace(/\r/g, '').split('\n');
  for (let i = 0; i < all.length; i++) {
    const l = all[i].trim();
    if (/^>/.test(l)) break;
    if (/^_{5,}$/.test(l)) break;                      // Outlook's separator above the quoted mail
    // Gmail wraps a long "On <date>, <name> <addr> wrote:" header over two lines
    if (/^(on |في )/i.test(l) && /(wrote:|كتب:)$/i.test((l + ' ' + (all[i + 1] || '').trim()).trim())) break;
    if (/^(on .+wrote:|from:|sent from my|-+ ?original message ?-+|في .+ كتب|كتب .+:)/i.test(l)) break;
    if (/^-- ?$/.test(l)) break;                       // signature delimiter
    if (l) own.push(l);
  }
  return own.join('\n');
}

/**
 * 'approve' only when his own words are an approval and nothing else: an EXACT reply keyword, English or
 * Arabic ("approve", "approved", "ok approve", "موافق", "أوافق"...). Anything else he writes is a change
 * request the marketing seat acts on (fn_marketing_calendar_reply files it); an empty reply is 'unclear'.
 */
export function replyIntent(text: string | null | undefined): 'approve' | 'change' | 'unclear' {
  const said = ownWords(text).replace(/\n/g, ' ').toLowerCase()
    .replace(/[,،]/g, ' ').replace(/[.!؛;:\s]+$/g, '').replace(/^[\s.!]+/, '').replace(/\s+/g, ' ');
  const EN = /^(ok(ay)? )?(i )?(approve|approved)( it)?( thanks?| thank you)?$/;
  const AR = /^(نعم )?(موافق|أوافق|اوافق|تمت الموافقة|موافقة)( شكرا| شكراً)?$/;
  return EN.test(said) || AR.test(said) ? 'approve' : said ? 'change' : 'unclear';
}

/** The token of a reply to the monthly VIDEO IDEA PLAN email (plan+<token>@mail.quotesdone.com or "[plan <token>]"). */
export function planTokenOf(m: { to?: string | null; subject?: string | null }): string | null {
  const t = String(m.to || '').toLowerCase().match(/^plan\+([0-9a-f]{32})@mail\.quotesdone\.com$/);
  if (t) return t[1];
  const s = String(m.subject || '').toLowerCase().match(/\[plan ([0-9a-f]{32})\]/);
  return s ? s[1] : null;
}
