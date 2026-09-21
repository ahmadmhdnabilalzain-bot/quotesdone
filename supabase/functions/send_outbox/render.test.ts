// render.test.ts - the campaign invitation renders its portal link as a real, clickable <a href>.
// Run: deno test supabase/functions/send_outbox/render.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { linkify, tmpl } from './render.ts';

// The shape enqueue_supplier_invites writes: the link alone on its own line, then prose.
const LINK = 'https://quotesdone.com/en/portal?t=9ebb2794-c5d8-4453-8ce1-b5c41b5b7f82';
const BODY = `Dear ZZ DEMO Co,\n\nTo join, open your supplier portal here:\n\n${LINK}\n\nand complete a short company profile.`;
const WRAPPER = '<html><body>{{LOGO}}<div>{{BODY}}</div>{{NAME}} {{TITLE}} {{REPLY}}{{UNSUB}}</body></html>';
const base = { body: BODY, logo: '', name: 'n', title: 't', channelEmail: 'supplier@quotesdone.com', unsub: '' };

Deno.test('supplier wrapper: the invitation link is an anchor', () => {
  const html = tmpl({ ...base, wrapper: WRAPPER });
  assert(html.includes(`<a href="${LINK}"`), 'the portal URL must be an <a href>, not plain text');
});

Deno.test('external fallback (no wrapper): the link is an anchor', () => {
  const html = tmpl({ ...base, internal: false });
  assert(html.includes(`<a href="${LINK}"`));
});

Deno.test('trailing punctuation stays outside the link; a quote cannot break out of href', () => {
  assertEquals(linkify('open https://x.ae/portal.'), 'open <a href="https://x.ae/portal" style="color:#6EE7D4">https://x.ae/portal</a>.');
  assert(!linkify('https://x.ae/a"onmouseover="y').includes('onmouseover="y"'));
});
