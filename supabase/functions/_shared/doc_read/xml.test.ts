// xml — the safe reader every OOXML / ODF / GAEB module uses.
// deno test --no-lock supabase/functions/_shared/doc_read/xml.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { findAll, parseXml, textOf } from './xml.ts';

Deno.test('reads namespaced elements, attributes, CDATA and the predefined and numeric entities', () => {
  const x = parseXml('<?xml version="1.0"?><w:document xmlns:w="u"><w:p><w:t xml:space="preserve">Tiles &amp; grout &#x0628;</w:t></w:p><w:p><w:t><![CDATA[<raw>]]></w:t></w:p></w:document>');
  const ts = findAll(x, 't');
  assertEquals(ts.map(textOf), ['Tiles & grout ب', '<raw>']);
  assertEquals(ts[0].attrs['xml:space'], 'preserve');
});

Deno.test('XXE and billion-laughs payloads are inert: the DTD is never interpreted', () => {
  const xxe = '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd"><!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]><r>&x;|&b;</r>';
  const t = textOf(parseXml(xxe));
  assertEquals(t, '&x;|&b;');
  assert(!t.includes('root:'));
});

Deno.test('a document nested beyond the depth ceiling is refused, not recursed into', () => {
  let threw = false;
  try { parseXml('<a>'.repeat(300)); } catch (e) { threw = String((e as Error).message) === 'xml_too_deep'; }
  assert(threw);
});
