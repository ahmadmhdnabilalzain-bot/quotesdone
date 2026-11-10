// The chat bubble's HTML (src/lib/chatRender.ts) is the one place a reply's text becomes markup through
// dangerouslySetInnerHTML, in the site widget and in the portal assistant. Security checklist audit, 10 Nov 2026:
// it ran four replace() calls over its own growing output, so an e-mail inside a URL wrote a second link INSIDE the
// first link's href, and a digit run in a URL wrote <bdi> inside the href. This replays those inputs and asserts that
// every attribute the renderer writes holds only the text it linked, and that no tag the text carried survives.
// Node 24 strips the types from the .ts module on import.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { render } from '../../src/lib/chatRender.ts';

const hrefs = (h) => [...h.matchAll(/href="([^"]*)"/g)].map((m) => m[1]);
const anchors = (h) => (h.match(/<a /g) || []).length;

test('an e-mail inside a URL stays part of the one link', () => {
  const h = render('https://a.co/x@b.co/onmouseover=alert(1)//');
  assert.equal(anchors(h), 1, h);
  assert.deepEqual(hrefs(h), ['https://a.co/x@b.co/onmouseover=alert(1)//']);
  assert.ok(!/href="[^"]*</.test(h), 'no tag is ever written inside an attribute');
});

test('a digit run in a URL does not break the href', () => {
  assert.deepEqual(hrefs(render('see https://quotesdone.com/blog/1234567890 now')), ['https://quotesdone.com/blog/1234567890']);
});

test('markup in the text is escaped, never rendered', () => {
  const h = render('<img src=x onerror=alert(1)> "q" \'s\' <script>alert(1)</script>');
  assert.ok(!/<img|<script/.test(h), h);
  assert.ok(h.includes('&lt;img') && h.includes('&quot;q&quot;') && h.includes('&#39;s&#39;'));
  const q = render('https://a.co/"onmouseover="alert(1)');
  assert.deepEqual(hrefs(q), ['https://a.co/&quot;onmouseover=&quot;alert(1)']);
});

test('only http(s), mailto and our own paths become links', () => {
  const h = render('javascript:alert(1) data:text/html,x vbscript:x');
  assert.equal(anchors(h), 0, h);
});

test('each kind still renders as before', () => {
  assert.equal(render('mail info@quotesdone.com'), 'mail <bdi><a href="mailto:info@quotesdone.com" style="color:#2DD4BF;font-weight:600">info@quotesdone.com</a></bdi>');
  assert.equal(render('go to /me today'), 'go to <bdi><a href="/me" style="color:#2DD4BF;font-weight:600">/me</a></bdi> today');
  assert.equal(render('call +971 4 123 4567'), 'call <bdi>+971 4 123 4567</bdi>');
  assert.equal(render('a\nb'), 'a<br>b');
  assert.equal(render('https://quotesdone.com/faq'), '<bdi><a href="https://quotesdone.com/faq" target="_blank" rel="noopener noreferrer" style="color:#2DD4BF;font-weight:600">https://quotesdone.com/faq</a></bdi>');
  assert.equal(render('/mexico is not ours'), '/mexico is not ours');
});

test('both chat surfaces use this renderer, and neither keeps a copy of its own', () => {
  for (const f of ['src/components/ChatWidget.tsx', 'src/components/me/shell/AssistantPanel.tsx']) {
    const src = readFileSync(new URL(`../../${f}`, import.meta.url), 'utf8');
    assert.match(src, /import \{ render \} from '@\/lib\/chatRender';/, f);
    assert.doesNotMatch(src, /\.replace\(\/\(https\?:/, `${f} must not linkify URLs itself`);
  }
});
