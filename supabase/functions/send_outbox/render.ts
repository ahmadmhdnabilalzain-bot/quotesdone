// The HTML frame every customer/supplier/internal email is rendered into. Moved out of index.ts on
// 21 Sep 2026 (customer_support) so the frame can be rendered and tested without starting the
// server: render.test.ts renders the real supplier invitation and asserts the unsubscribe link,
// the clickable portal link and the Arabic frame are all present.
import { BRAND, lockupImg } from '../_shared/brand.ts';
import { UNSUBSCRIBE_MAILBOX } from '../_shared/unsubscribe_mailbox.ts';
export function esc(s: string) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
// BRAND: the founder's kit is on file (public.company_brand). Every colour below is one of its
// rows, and this file now renders on NAVY, so it uses the on-navy pair throughout. The on-white
// link (teal-deep #0B8276) is gone from here -- it was correct when the mail was white and is
// near-invisible on #123041. Brand teal #14B8A6 remains an accent that never carries text.
// v18 (8 Sep 2026): renderBody's output is placed on the DARK internal card, so it needs the
// on-navy pair, not the on-white one. company_brand.contrast.links states it outright -- "On navy:
// teal-light #6EE7D4" -- and teal-deep #0B8276 is the on-WHITE link, near-invisible on #123041.
// The body colour had the same fault: #1f2937 is dark grey, which on navy is grey on black.
const DARK_LINK = '#6EE7D4', DARK_INK = '#EAF4F2';
export function linkify(s: string) { return s.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:' + DARK_LINK + '">$1</a>'); }

// Turn a plain-text agent body into structured HTML: ALL-CAPS short lines -> headings, -/• lines -> bullets, URLs -> links.
export function renderBody(raw: string) {
  const lines = String(raw || '').split('\n'); let html = ''; let inList = false;
  const closeList = () => { if (inList) { html += '</ul>'; inList = false; } };
  for (const line of lines) {
    const t = line.replace(/\s+$/, '');
    if (!t) { closeList(); html += '<div style="height:8px"></div>'; continue; }
    if (/^[=\-_]{3,}$/.test(t)) { continue; }
    if (/^\s*[-•*]\s+/.test(t)) { if (!inList) { html += '<ul style="margin:6px 0 6px 18px;padding:0">'; inList = true; } html += '<li style="margin:3px 0;font-size:15px;line-height:1.55;color:' + DARK_INK + '">' + linkify(esc(t.replace(/^\s*[-•*]\s+/, ''))) + '</li>'; continue; }
    closeList();
    if (t === t.toUpperCase() && /[A-Z]/.test(t) && t.length <= 64) { html += '<h3 style="margin:18px 0 6px;font-size:13px;font-weight:800;color:' + DARK_LINK + ';text-transform:uppercase;letter-spacing:.04em">' + esc(t) + '</h3>'; continue; }
    html += '<p style="margin:0 0 9px;font-size:15px;line-height:1.6;color:' + DARK_INK + '">' + linkify(esc(t)) + '</p>';
  }
  closeList();
  return html;
}
// THE PREHEADER (24 Sep 2026, marketing, ledger 993). The line an inbox shows beside the subject. With
// none, Gmail and Outlook fill it with the first words of the body ("Dear <company>,"), which says
// nothing. Hidden in the rendered mail and placed first inside <body>, where clients read it; the run
// of &zwnj;&nbsp; stops the client pulling body text in after it.
export function preheaderHtml(text: string): string {
  const t = String(text || '').trim();
  if (!t) return '';
  return `<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#06121B;opacity:0">${esc(t)}${'&zwnj;&nbsp;'.repeat(40)}</div>`;
}
type FrameOpts = { body: string; logo: string; name: string; title: string; channelEmail: string; unsub: string; wrapper?: string; internal?: boolean; subject?: string };
export function tmpl(opts: FrameOpts & { preheader?: string }) {
  const html = frame(opts);
  const pre = preheaderHtml(opts.preheader || '');
  return pre ? html.replace(/(<body[^>]*>)/i, `$1${pre}`) : html;
}
function frame(opts: FrameOpts) {
  const { body, logo, name, title, channelEmail, unsub, wrapper, internal, subject } = opts;
  // v17 (8 Sep 2026): the logo is the horizontal OnDark lockup, not the 192px PWA app tile, so
  // 34x34 with a border-radius would squash a wordmark into a square and round its corners off.
  //
  // v18 (8 Sep 2026, founder: "make the logo a bit bigger... everywhere from now it should [be
  // sized] in terms of the height"). Measured rather than nudged: the supplied lockup is a
  // 1859x460 box holding 1608x176 of artwork, so 62% of its height is empty alpha. At width 170
  // the box came out 42px tall and the visible wordmark 16px -- the same height as the 15px body
  // text beneath it, which is precisely what he was looking at. Widening the box would have spent
  // 62% of every added pixel on nothing.
  //
  // So the size now comes from lockupImg() in _shared/brand.ts, which uses the TRIMMED lockup and
  // takes a HEIGHT. One helper, so email, UI and PDF cannot drift apart, and one unit, because a
  // width means something different for every asset depending on the padding it was drawn inside.
  const logoTag = logo ? lockupImg({ ground: 'dark', height: BRAND.logoHeight.email }) : '';
  // The second way out names a mailbox that code reads (_shared/unsubscribe_mailbox.ts). Until 21 Sep 2026
  // it said "reply to this email", and replies went to a Microsoft 365 inbox nothing read.
  const unsubLine = unsub ? `<br><a href="${unsub}" style="color:#9ca3af">Unsubscribe</a> &middot; or email ${UNSUBSCRIBE_MAILBOX} to be removed.` : '';
  if (wrapper && wrapper.indexOf('{{BODY}}') >= 0) {
    return wrapper.split('{{LOGO}}').join(logoTag).split('{{BODY}}').join(linkify(esc(body))).split('{{NAME}}').join(esc(name)).split('{{TITLE}}').join(esc(title)).split('{{REPLY}}').join(esc(channelEmail)).split('{{UNSUB}}').join(unsubLine);
  }
  // v17 (8 Sep 2026): dark, on the brand kit's own navy, and table-based. This fallback is what
  // internal/admin mail uses (it takes no wrapper), and it had the same two faults the customer
  // template had: display:flex, which Outlook's Word engine ignores outright, and a light ground.
  // Colours and their contrast ratios come from company_brand, which records them measured:
  // paper #EAF4F2 on navy 14.4:1 AAA, muted #9DB2B2 7.3:1 AAA, teal-light #6EE7D4 10.8:1 AAA.
  // The kit also states the rule this file previously broke -- on navy the link is teal-light, and
  // brand teal #14B8A6 is an accent that must never carry text.
  const INK = '#EAF4F2', MUTED = '#9DB2B2', SURFACE = '#123041', GROUND = '#06121B', RULE = '#173A4B', DLINK = '#6EE7D4';
  const header = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td style="vertical-align:middle">${logoTag}</td>${internal ? `<td align="right" style="vertical-align:middle;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;color:${MUTED};letter-spacing:.06em">INTERNAL</td>` : ''}</tr></table>`;
  const titleBlock = (internal && subject) ? `<h2 style="margin:18px 0 12px;font-size:19px;line-height:1.3;color:#FFFFFF;font-family:Arial,Helvetica,sans-serif">${esc(subject)}</h2>` : '';
  const content = internal ? renderBody(body) : `<div dir="auto" style="font-size:15px;line-height:1.65;white-space:pre-wrap;color:${INK};text-align:start;unicode-bidi:plaintext">${esc(body)}</div>`;
  const sig = `<div style="margin-top:26px;padding-top:18px;border-top:1px solid ${RULE};font-size:13px;color:${MUTED};line-height:1.6"><div style="font-weight:700;color:#FFFFFF">${esc(name)}</div><div style="color:${INK}">${esc(title)}, QuotesDone</div><div style="margin-top:3px">${esc(channelEmail)} &middot; <a href="https://quotesdone.com" style="color:${DLINK};text-decoration:none">quotesdone.com</a></div></div>`;
  const footer = internal
    ? `<div style="text-align:center;color:${MUTED};font-size:12px;margin-top:16px;line-height:1.55">QuotesDone OS &middot; internal operations report &middot; Dubai, UAE<br>You're receiving this because you're an administrator of QuotesDone.</div>`
    : `<div style="text-align:center;color:${MUTED};font-size:12px;margin-top:16px;line-height:1.55">QuotesDone &middot; Al Furjan, Dubai, UAE<br>You're receiving this because your business is publicly listed and may match clients sourcing on QuotesDone.${unsubLine}</div>`;
  // bgcolor AND inline background on every coloured cell: different clients read different ones,
  // and Outlook is unreliable about background-color on a div.
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"></head><body style="margin:0;padding:0;background:${GROUND};font-family:Arial,Helvetica,sans-serif"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${GROUND}" style="background:${GROUND};padding:28px 12px"><tr><td align="center"><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" bgcolor="${SURFACE}" style="max-width:600px;width:100%;background:${SURFACE};border:1px solid ${RULE};border-radius:14px"><tr><td style="padding:30px">${header}${titleBlock}${content}${sig}</td></tr></table><table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%"><tr><td>${footer}</td></tr></table></td></tr></table></body></html>`;
}
