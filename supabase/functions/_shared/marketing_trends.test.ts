import { assertEquals } from 'jsr:@std/assert@1';
import { modelCitation, parseDuckResults, parseRss, webCitation } from './marketing_trends.ts';

const RSS = `<?xml version="1.0"?><rss><channel><title>feed</title>
<item><title><![CDATA[ZZ DEMO Dubai fit-out demand rises &amp; more]]></title><link>https://example.invalid/a</link><pubDate>Wed, 23 Sep 2026 08:00:00 GMT</pubDate></item>
<item><title>no link</title></item>
<item><title>ZZ DEMO second</title><link>https://example.invalid/b</link></item>
</channel></rss>`;

Deno.test('an RSS feed parses to items with a link and a title; one without a link is skipped', () => {
  const items = parseRss(RSS);
  assertEquals(items.length, 2);
  assertEquals(items[0], { url: 'https://example.invalid/a', title: 'ZZ DEMO Dubai fit-out demand rises & more', published_at: '2026-09-23T08:00:00.000Z' });
  assertEquals(items[1].published_at, null);
  assertEquals(parseRss(RSS, 1).length, 1);
});

Deno.test('the web engine cites us only when our own domain is a result, with its rank', () => {
  assertEquals(webCitation([{ url: 'https://other.example.invalid' }, { url: 'https://www.quotesdone.ae/blog/x' }]),
    { cited: true, rank: 2, evidence: 'https://www.quotesdone.ae/blog/x' });
  assertEquals(webCitation([{ url: 'https://quotesdone.ae.evil.example.invalid/' }]).cited, false);
  assertEquals(webCitation([]).cited, false);
});

Deno.test('the model engine cites us when the answer names QuotesDone or our domain', () => {
  assertEquals(modelCitation('Try Quotes Done for this.').cited, true);
  assertEquals(modelCitation('see quotesdone.com').cited, true);
  assertEquals(modelCitation('Ask three contractors directly.').cited, false);
  assertEquals(modelCitation('Get your quotes done by licensed contractors.').cited, false);
});

Deno.test('DuckDuckGo results are unwrapped to their target URL', () => {
  const html = '<a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.quotesdone.ae%2F&amp;rut=x">Quotes<b>Done</b></a>';
  assertEquals(parseDuckResults(html), [{ url: 'https://www.quotesdone.ae/', title: 'QuotesDone' }]);
});
