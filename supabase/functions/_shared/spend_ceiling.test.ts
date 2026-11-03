import { assertEquals } from 'jsr:@std/assert@1';
import { ceilingVerdict, spendClassOf } from './spend_ceiling.ts';
import { INTERNAL_DUTY_SURFACE } from './think.ts';

Deno.test('a request that is neither a proven test run nor a declared internal duty is never counted, so never refused', () => {
  assertEquals(spendClassOf(null, undefined), null);
  assertEquals(spendClassOf(null, 'customer'), null);
  assertEquals(spendClassOf('', 'INTERNAL'), null);            // only the exact declaration counts
  assertEquals(spendClassOf('ab12cd34', undefined), 'test');
  assertEquals(spendClassOf('ab12cd34', 'internal'), 'test');  // a test run is a test run whatever it declares
  assertEquals(spendClassOf(null, 'internal'), 'internal');
});

Deno.test("only a seat's own scheduled work is an internal duty; a person's case never is", () => {
  for (const s of ['ceo.knowledge_refresh', 'it_engineer.postmortem', 'sales_engineer.root_cause', 'marketing.ceo_revision']) assertEquals(INTERNAL_DUTY_SURFACE.test(s), true, s);
  for (const s of ['wa_inbound.unwritten_reply', 'sql.fn_supplier_twin', 'sales_engineer.document_arabic', 'site_assistant.person', 'supplier_documents.subject', 'wa_inbound.needs_a_person']) assertEquals(INTERNAL_DUTY_SURFACE.test(s), false, s);
});

Deno.test('the ceiling refuses only on an explicit allowed:false; an error or an odd shape lets the duty run', () => {
  assertEquals(ceilingVerdict({ allowed: false, spent_usd: 10.2, ceiling_usd: 10, class: 'test' }, null).allowed, false);
  assertEquals(ceilingVerdict({ allowed: true }, null).allowed, true);
  assertEquals(ceilingVerdict(null, { message: 'boom' }).allowed, true);
  assertEquals(ceilingVerdict('yes', null).allowed, true);
  assertEquals(ceilingVerdict({}, null).allowed, true);
});
