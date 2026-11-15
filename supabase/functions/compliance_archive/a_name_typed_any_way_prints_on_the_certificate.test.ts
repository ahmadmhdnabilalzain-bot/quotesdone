// A NAME TYPED ANY WAY PRINTS ON THE SUPPLIER'S CERTIFICATE (15 Nov 2026, customer_support; Monday checklist, founder ledger 1692).
//
// The Supplier Agreement step asks for one typed thing, the accepting person's full name (_shared/supplier_terms.ts personName:
// two words with a letter each, up to 120 characters, ANY script). It is printed on the signed acceptance certificate, which is a
// PDF from pdf_native (ruling 1671) and English for every supplier (ruling 1008: certLang answers 'en' for a supplier's locale).
// Nothing had rendered that certificate with a name a general manager in the UAE may really type: his name in Arabic letters,
// a name with an apostrophe or hyphen, a name with an emoji pasted from his phone's signature, or markup. A glyph the English
// fonts cannot draw is DROPPED by pdf_native (meta.glyphs_dropped), so a name in Arabic letters could print as an empty cell on
// the one document that records who accepted.
//
// This renders the English certificate offline through the real pdf_native with the committed brand fonts and says, per name,
// what is dropped. Markup must arrive escaped, never as a tag.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert';
import { certFields, certificate, identityRows, supplierCompany } from './certificate.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { personName } from '../_shared/supplier_terms.ts';

const BRAND = new URL('../pdf_native/fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => /.ttf$/.test(p) ? await Deno.readFile(new URL(p, BRAND)) : null;
const HASH = 'ab'.repeat(32);
const AGREEMENT = 'https://quotesdone.com/supplier-agreement';

function englishCertificate(signatory: string) {
  const row = { company_name: '', licence_legal_name: 'ZZ DEMO Monday Checklist Trading L.L.C.', trade_license_no: 'ZZ-1692-001',
    contact_name: signatory, signatory_name: signatory, locale: 'en' };
  const f = { ...certFields(row, 'supplier'), ...supplierCompany(row), phone: '+971500000040', email: 'qd-monday@example.invalid',
    terms_label: 'Supplier Agreement — Version 17', accepted_utc: '2026-11-16 06:00:00 UTC', accepted_iso: '2026-11-16T06:00:00Z', ip: '' };
  return { f, c: certificate(f, 'supplier', HASH, AGREEMENT, 'en') };
}

Deno.test('a Latin name with an apostrophe and a hyphen prints whole, nothing dropped', async () => {
  const name = "ZZ DEMO Mu'min Al-Hashimi";
  assert(personName(name), 'the agreement step accepts it');
  const { c } = englishCertificate(name);
  const r = await renderPdf({ title: c.title, lang: c.lang, body_html: c.body_html }, { fetchBytes });
  assert(r.ok, JSON.stringify((r as { body?: unknown }).body));
  if (r.ok) assertEquals(r.meta.glyphs_dropped, 0);
});

Deno.test('markup typed as a name is printed as text, never a tag', () => {
  const name = 'ZZ DEMO <script>alert(1)</script> Khan';
  assert(personName(name), 'the agreement step accepts it');
  const { c, f } = englishCertificate(name);
  assert(!c.body_html.includes('<script>'), 'a typed tag reached the certificate HTML unescaped');
  assert(identityRows(f, 'supplier', 'en').some(([k]) => k === 'Authorised signatory'));
  assertStringIncludes(c.body_html, '&lt;script&gt;');
});

// MEASURED, NOT ASSERTED AS GOOD: an Arabic-letter name and an emoji. The agreement step accepts both (personName counts letters
// of any script). What the English certificate does with them is recorded here so a change is seen; the Monday checklist names
// this as a known risk with its measured outcome (docs/release/monday-16-nov-invitation-checklist.md).
Deno.test('an Arabic-letter name and an emoji: what the English certificate prints is measured', async () => {
  const cases: Array<[string, string]> = [['arabic', 'ZZ DEMO محمد الهاشمي'], ['emoji', 'ZZ DEMO Omar Khan 🙂']];
  const seen: Record<string, number> = {};
  for (const [k, name] of cases) {
    assert(personName(name), `${k}: the agreement step accepts it`);
    const { c } = englishCertificate(name);
    assertStringIncludes(c.body_html, name.replace(/</g, '&lt;'), `${k}: the name reaches the certificate HTML`);
    const r = await renderPdf({ title: c.title, lang: c.lang, body_html: c.body_html }, { fetchBytes });
    assert(r.ok, `${k}: the certificate failed to render: ${JSON.stringify((r as { body?: unknown }).body)}`);
    if (r.ok) seen[k] = r.meta.glyphs_dropped;
  }
  console.log('glyphs dropped on the English certificate:', JSON.stringify(seen));
  // 15 Nov 2026: arabic 0, emoji 2 (the one emoji, a surrogate pair, is left out; the name around it prints). Arabic letters he
  // typed himself are his choice, not a message in Arabic (ruling 1008 as the certification's criterion 6 reads it).
  assertEquals(seen.arabic, 0, 'an Arabic-letter name is drawn on the English certificate');
  assert(seen.emoji <= 2, `an emoji costs more than itself: ${seen.emoji} glyphs dropped`);
});
