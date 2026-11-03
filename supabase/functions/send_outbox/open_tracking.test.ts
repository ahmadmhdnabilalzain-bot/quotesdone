// deno test supabase/functions/send_outbox/open_tracking.test.ts
// The invitation open (open_tracking.ts, marketing, 3 Nov 2026): the switch, the first-party pixel, the token shape, the
// HTML twin (the same words, one image, no link) and the MIME (switch off = today's bytes; on = the same text part plus
// the HTML part). The database side (arm, token, classifier, funnel) is proved by
// scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo_probe.sql.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { invitationHtml, openShare, openTracks, pixelBase, pixelUrl, OPEN_TRACKED_TYPES } from './open_tracking.ts';
import { ANY_LINK, M365_SEED_KIND, campaignMail, m365Mime, qpEncode } from './m365_lane.ts';
import { resendPayload } from './payload.ts';

const TOKEN = '3c594d0e9b1f4a7c8d2e6f0a1b2c3d4e';
const BASE = 'https://quotesdone.com/u/o/';
const PIXEL = BASE + TOKEN + '.gif';
const decode = (b: string) => new TextDecoder().decode(Uint8Array.from(atob(b), (c) => c.charCodeAt(0)));
const camp = campaignMail({ type: 'supplier_invite', body: 'Hi Gulf Steel Works LLC team,', subject: 'x' }, { company: 'Gulf Steel Works LLC', trade: 'steel_fabrication' });
const MIME = { from: '"Ahmad Alzain, QuotesDone" <supplier@quotesdone.com>', to: 'sales@gulfsteel.example', reply: '', subject: camp.subject, text: camp.text,
  unsub: 'https://quotesdone.com/u/unsubscribe?e=sales%40gulfsteel.example&t=abc', unsubMailto: 'unsubscribe@mail.quotesdone.com',
  messageId: '<qd-notif-125323.1762156800000@quotesdone.com>', now: new Date('2026-11-03T09:00:00Z') };

// The message as m365Mime built it before 3 Nov 2026, kept here verbatim so "off" is compared with today's bytes, not with itself.
const b64 = (s: string) => { const bytes = new TextEncoder().encode(s); let bin = ''; for (const x of bytes) bin += String.fromCharCode(x); return btoa(bin); };
const hdr = (s: string) => (/^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(s)}?=`);
const clean = (s: string) => String(s || '').replace(/[\r\n]+/g, ' ').trim();
function todayMime(o: typeof MIME): string {
  const lines = [`From: ${clean(o.from)}`, `To: ${clean(o.to)}`, ...(clean(o.reply) ? [`Reply-To: ${clean(o.reply)}`] : []), `Subject: ${hdr(clean(o.subject) || 'QuotesDone')}`,
    `Date: ${o.now.toUTCString()}`, `Message-ID: ${o.messageId}`, 'MIME-Version: 1.0'];
  if (o.unsub) lines.push(`List-Unsubscribe: <${clean(o.unsub)}>, <mailto:${o.unsubMailto}?subject=unsubscribe>`, 'List-Unsubscribe-Post: List-Unsubscribe=One-Click');
  lines.push('Content-Type: text/plain; charset=utf-8', 'Content-Transfer-Encoding: quoted-printable', '', qpEncode(o.text));
  return b64(lines.join('\r\n'));
}

Deno.test('the switch reads like the database: off / garbage = 0, a whole percentage, capped at 100', () => {
  for (const [v, want] of [[undefined, 0], ['', 0], ['off', 0], ['OFF', 0], ['x', 0], ['-5', 0], ['12.5', 0], ['0', 0], ['20', 20], [' 20% ', 20], ['100', 100], ['250', 100]] as const) {
    assertEquals(openShare(v), want, String(v));
  }
});

Deno.test('only an English supplier invitation or nudge can carry the image; never a placement seed or anyone else', () => {
  assertEquals([...OPEN_TRACKED_TYPES], ['supplier_invite', 'supplier_invite_nudge']);
  assert(openTracks({ type: 'supplier_invite', to_role: 'supplier', lang: 'en' }));
  assert(openTracks({ type: 'supplier_invite_nudge', to_role: 'supplier' }));
  assertFalse(openTracks({ type: 'supplier_invite_seed', to_role: 'supplier', kind: M365_SEED_KIND }));
  assertFalse(openTracks({ type: 'supplier_invite', to_role: 'supplier', kind: M365_SEED_KIND }));
  assertFalse(openTracks({ type: 'supplier_invite', to_role: 'customer' }));
  assertFalse(openTracks({ type: 'quote_received', to_role: 'supplier' }));
  assertFalse(openTracks({ type: 'supplier_invite', to_role: 'supplier', lang: 'ar' }));
});

Deno.test('the pixel is served only from our own https domain, and only for a 32-hex token', () => {
  assertEquals(pixelBase('https://quotesdone.com/u/unsubscribe'), BASE);
  assertEquals(pixelBase('https://www.quotesdone.ae/u/unsubscribe'), 'https://www.quotesdone.ae/u/o/');
  for (const bad of ['', undefined, 'not a url', 'http://quotesdone.com/u/unsubscribe', 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/unsubscribe',
    'https://quotesdone.com.evil.example/u', 'https://pixel.tracker.example/u']) assertEquals(pixelBase(bad), '', String(bad));
  assertEquals(pixelUrl(BASE, TOKEN), PIXEL);
  for (const t of [null, '', 'abc', TOKEN.toUpperCase(), TOKEN + '0', 'sales@gulfsteel.example', '154213']) assertEquals(pixelUrl(BASE, t), '', String(t));
  assertEquals(pixelUrl('', TOKEN), '');
});

Deno.test('the token carries neither the address nor the lead id, and is not derived from them', () => {
  const p = pixelUrl(BASE, TOKEN);
  assertFalse(p.includes('gulfsteel') || p.includes('%40') || p.includes('@'));
  // the database mints it: replace(gen_random_uuid()::text, '-', '') -- 122 random bits; nothing in this module hashes an address
  const src = Deno.readTextFileSync(new URL('./open_tracking.ts', import.meta.url));
  assertFalse(/crypto\.subtle|createHash|\bmd5\b|\bsha-?\d*\b|\bdigest\b/i.test(src.replace(/^\s*\/\/.*$/gm, '')), 'open_tracking.ts must not derive a token itself');
});

Deno.test('the HTML twin says the same words, carries exactly one image (the pixel) and no link', () => {
  const html = invitationHtml(camp.text, PIXEL);
  const words = (s: string) => s.replace(/<br>/g, '\n').replace(/<\/p><p>/g, '\n\n').replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  assertEquals(words(html), camp.text);
  assertEquals((html.match(/<img\b/g) || []).length, 1);
  assertEquals((html.match(/https?:\/\//g) || []).length, 1, 'one URL only, the pixel');
  assert(html.includes(`<img src="${PIXEL}" width="1" height="1" alt=""`));
  assertFalse(/<a\b|href=|<link\b|<script\b|@import|url\(|background/i.test(html), 'no link, script, style sheet or background image');
  assertFalse(ANY_LINK.test(words(html)), 'the visible words carry no link');
  // an attempt to smuggle markup through the text is escaped, never rendered
  assert(invitationHtml('a <b>"x"</b> & y', PIXEL).includes('<p>a &lt;b&gt;&quot;x&quot;&lt;/b&gt; &amp; y</p>'));
});

Deno.test('switch off: the MIME is byte-identical to the message before 3 Nov 2026', () => {
  assertEquals(m365Mime(MIME), todayMime(MIME));
  assertEquals(m365Mime({ ...MIME, html: '' }), todayMime(MIME));
  assertEquals(m365Mime({ ...MIME, reply: 'suppliers@mail.quotesdone.com' }), todayMime({ ...MIME, reply: 'suppliers@mail.quotesdone.com' }));
  assertFalse(decode(m365Mime(MIME)).includes('multipart'));
  // the Resend fallback: no html key at all, as before
  assertFalse('html' in resendPayload({ from: 'a@quotesdone.com', to: 'b@x.example', reply: '', subject: 's', html: '', text: camp.text, unsub: '', unsubMailto: '' }));
});

Deno.test('switch on: multipart/alternative, the identical text part first, the HTML twin second, one pixel', () => {
  const html = invitationHtml(camp.text, PIXEL);
  const raw = decode(m365Mime({ ...MIME, html }));
  const off = decode(todayMime(MIME));
  const boundary = /Content-Type: multipart\/alternative; boundary="([^"]+)"/.exec(raw)?.[1] || '';
  assert(boundary.startsWith('qd-alt-') && !/[^A-Za-z0-9-]/.test(boundary), boundary);
  // every header before the body is today's, in today's order
  const head = (s: string) => s.split('\r\n').filter((l) => /^[A-Za-z-]+: /.test(l) && !l.startsWith('Content-')).join('\n');
  assertEquals(head(raw.split(`--${boundary}`)[0]), head(off));
  const parts = raw.split(`--${boundary}`);
  assertEquals(parts.length, 4, 'preamble, text, html, closing');
  const textPart = parts[1].replace(/^\r\n/, '').replace(/\r\n$/, '');
  const offBody = off.slice(off.indexOf('Content-Type: text/plain'));
  assertEquals(textPart, offBody, 'the text part is the untracked body, byte for byte');
  assert(parts[2].includes('Content-Type: text/html; charset=utf-8') && parts[2].includes('Content-Transfer-Encoding: quoted-printable'));
  assert(parts[3].startsWith('--'), 'closing delimiter');
  const qpHtml = parts[2].split('\r\n\r\n').slice(1).join('\r\n\r\n').replace(/=\r\n/g, '').replace(/=([0-9A-F]{2})/g, (_m, h) => String.fromCharCode(parseInt(h, 16)));
  assert(qpHtml.includes(PIXEL) && (qpHtml.match(/<img\b/g) || []).length === 1);
  // the Resend fallback carries the same twin
  const r = resendPayload({ from: 'a@quotesdone.com', to: 'b@x.example', reply: '', subject: 's', html, text: camp.text, unsub: '', unsubMailto: '' });
  assertEquals(r.text, camp.text); assertEquals(r.html, html);
});

Deno.test('send_outbox calls the database only when the share is on, and a failure sends the untracked email', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/if \(!openPct \|\| !openBase \|\| !openTracks\(n\)\) return '';/.test(src), 'the off path must return before the rpc');
  assert(/admin\.rpc\('fn_invite_open_token'/.test(src));
  assert(/catch \{ return ''; \}/.test(src), 'an rpc throw must fall back to the untracked email');
  assert(/html: mHtml \}\)/.test(src) && /html: campHtml, text: camp\.text/.test(src), 'both routes carry the same twin');
});
