// The Resend payload send_outbox posts, and the inbox-placement rules it must satisfy
// (22 Sep 2026, customer_support; founder instruction 633: "they must land in the inbox").
//
// Moved out of index.ts so the exact message — headers, text part, links — can be built and checked
// without a server or a send: payload.test.ts replays each rule, and
// scripts/invitation_inbox_check.mjs renders the LIVE invitation through the same functions.
// Pure: no Deno or network APIs.

export type ResendMail = {
  from: string; to: string[]; reply_to: string; subject: string; html: string; text: string;
  headers?: Record<string, string>;
};

export function resendPayload(o: {
  from: string; to: string; reply: string; subject: string; html: string; text: string;
  unsub: string; unsubMailto: string;
  /** notifications.in_reply_to: the Message-ID this answers, so the reply lands in the customer's own thread. */
  inReplyTo?: string | null;
}): ResendMail {
  // An empty html sends a plain-text-only message (the supplier campaign email, 27 Oct 2026): no html key at all.
  const mail: ResendMail = { from: o.from, to: [o.to], reply_to: o.reply, subject: o.subject || 'QuotesDone', html: o.html, text: o.text };
  if (!o.html) delete (mail as Partial<ResendMail>).html;
  const irt = String(o.inReplyTo ?? '').trim();
  if (irt) {
    const id = irt.startsWith('<') ? irt : '<' + irt + '>';
    mail.headers = { ...(mail.headers || {}), 'In-Reply-To': id, 'References': id };
  }
  // RFC 8058 one-click: an https URL that accepts POST, plus the mailto fallback. Gmail and Yahoo
  // require this on bulk mail since Feb 2024; Microsoft since May 2025.
  if (o.unsub) {
    mail.headers = {
      ...(mail.headers || {}),
      'List-Unsubscribe': `<${o.unsub}>, <mailto:${o.unsubMailto}?subject=unsubscribe>`,
      'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
    };
  }
  return mail;
}

/**
 * Point the frame's brand assets at our own domain. mail-tester.com (22 Sep 2026) took 0.5 off the
 * invitation for SpamAssassin URI_NOVOWEL, fired by the project host in the logo URL (and the
 * unsubscribe link, which send_outbox builds from unsubscribe_public_base). No base = unchanged.
 */
export function ownDomain(html: string, projectUrl: string, assetBase: string): string {
  if (!assetBase || !projectUrl) return html;
  return html.split(`${projectUrl.replace(/\/+$/, '')}/storage/v1/object/public/brand/`).join(`${assetBase.replace(/\/+$/, '')}/`);
}

// Link shorteners and redirectors: a cold message carrying one is a phishing signal to every filter.
const SHORTENERS = /^(bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|buff\.ly|rebrand\.ly|cutt\.ly|shorturl\.at|rb\.gy|lnkd\.in|resend-clicks\.com|.*\.resend\.dev)$/i;
// Words and marks content filters score in a SUBJECT line. "free" is deliberately NOT here: the live
// subject carries "(free, no commission)" and SpamAssassin 4.0.2 at mail-tester.com scored it 0 (22 Sep 2026).
const SUBJECT_TRIGGERS = /\b(100%|guarantee[d]?|act now|urgent|winner|risk[- ]free|cash|\$\$+|click here|limited time)\b|!{2,}/i;

export type Lint = { rule: string; ok: boolean; detail: string };

/** Every rule a cold supplier invitation must pass to have a fair chance at the inbox. */
export function inboxLint(mail: ResendMail, allowedHosts: string[]): Lint[] {
  const out: Lint[] = [];
  const add = (rule: string, ok: boolean, detail = '') => out.push({ rule, ok, detail });
  const hosts = [...mail.html.matchAll(/(?:href|src)="(https?:\/\/[^"]+)"/gi)].map((m) => m[1]);
  const textUrls = [...mail.text.matchAll(/https?:\/\/\S+/g)].map((m) => m[0]);
  const hostOf = (u: string) => { try { return new URL(u).hostname.toLowerCase(); } catch { return '(unparseable)'; } };
  const allowed = (h: string) => allowedHosts.some((a) => h === a || h.endsWith('.' + a));

  add('text/plain alternative present', mail.text.trim().length > 200, `${mail.text.length} chars`);
  const htmlLinks = hosts.filter((u) => !/\.(png|jpe?g|gif|webp|svg)(\?|$)/i.test(u));
  add('every link in the text part is also in the HTML part', textUrls.every((u) => mail.html.includes(u.replace(/&/g, '&amp;')) || mail.html.includes(u)),
      textUrls.filter((u) => !mail.html.includes(u.replace(/&/g, '&amp;')) && !mail.html.includes(u)).join(' '));
  add('links and images only on our own hosts', [...hosts, ...textUrls].every((u) => allowed(hostOf(u))),
      [...new Set([...hosts, ...textUrls].map(hostOf).filter((h) => !allowed(h)))].join(', '));
  add('no link shortener or click-tracking redirect', [...hosts, ...textUrls].every((u) => !SHORTENERS.test(hostOf(u))));
  // SpamAssassin URI_NOVOWEL: a URI hostname with a long run of consonants reads as machine-generated.
  const noVowel = [...new Set([...hosts, ...textUrls].map(hostOf))].filter((h) => /[b-df-hj-np-tv-z]{7,}/i.test(h.replace(/\./g, ' ')));
  add('no hostname a spam filter reads as random (URI_NOVOWEL)', noVowel.length === 0, noVowel.join(', '));
  add('every link is https', [...htmlLinks, ...textUrls].every((u) => u.startsWith('https://')));
  add('not image-only', mail.html.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim().length > 300);
  add('UTF-8 declared', /<meta charset="utf-8">/i.test(mail.html));
  add('one-click List-Unsubscribe (RFC 8058)',
      /^<https:\/\/[^>]+>, <mailto:[^>]+>$/.test(mail.headers?.['List-Unsubscribe'] ?? '')
      && mail.headers?.['List-Unsubscribe-Post'] === 'List-Unsubscribe=One-Click');
  add('Reply-To is a real mailbox', /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(mail.reply_to) && !/no-?reply/i.test(mail.reply_to), mail.reply_to);
  add('From has a display name', /^[^<]+<[^>]+@[^>]+>$/.test(mail.from.trim()), mail.from);
  add('subject free of filter trigger words', !SUBJECT_TRIGGERS.test(mail.subject), (mail.subject.match(SUBJECT_TRIGGERS) || [''])[0]);
  add('subject not shouted', !/\b[A-Z]{5,}\b.*\b[A-Z]{5,}\b/.test(mail.subject.replace(/QuotesDone/g, '')));
  if (/[؀-ۿ]/.test(mail.text)) add('Arabic mail is right-to-left', /<html dir="rtl" lang="ar"/i.test(mail.html));
  return out;
}
