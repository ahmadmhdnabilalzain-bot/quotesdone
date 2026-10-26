import { assertEquals } from 'jsr:@std/assert@1';
import { competitorsNamed, modelCitation, parseRss, webCitation } from './marketing_trends.ts';

Deno.test('competitorsNamed reads brand names as whole phrases, the part before a bracket, never a fragment', () => {
  const names = ['Tradeling (Tradeling Group)', 'Biznex.ae', 'dubizzle Business Hub', 'Q Quotation', 'Made-in-China.com'];
  assertEquals(competitorsNamed('Try Tradeling or Biznex.ae; also dubizzle business hub.', names), ['Tradeling (Tradeling Group)', 'Biznex.ae', 'dubizzle Business Hub']);
  assertEquals(competitorsNamed('Tradelings are not a brand, and a quotation is a word.', names), []);
  assertEquals(competitorsNamed('Sourcing on Made-in-China.com works.', names), ['Made-in-China.com']);
});

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

Deno.test('Google Trends searches, which all link the feed, each get their own explore URL', () => {
  const xml = `<rss><channel><item><title>dubai rain</title><link>https://trends.google.com/trending/rss?geo=AE</link></item>
<item><title>villa waterproofing</title><link>https://trends.google.com/trending/rss?geo=AE</link></item></channel></rss>`;
  assertEquals(parseRss(xml).map((i) => i.url), [
    'https://trends.google.com/trends/explore?geo=AE&q=dubai%20rain',
    'https://trends.google.com/trends/explore?geo=AE&q=villa%20waterproofing',
  ]);
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

