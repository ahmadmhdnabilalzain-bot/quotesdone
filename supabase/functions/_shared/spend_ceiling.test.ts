import { assertEquals } from 'jsr:@std/assert@1';
import { ceilingVerdict, INTERNAL_DUTY_FNS, spendClassOf } from './spend_ceiling.ts';

Deno.test('a request that is neither a proven test run nor a declared internal duty is never counted, so never refused', () => {
  assertEquals(spendClassOf(null, undefined), null);
  assertEquals(spendClassOf(null, 'customer'), null);
  assertEquals(spendClassOf('', 'INTERNAL'), null);            // only the exact declaration counts
  assertEquals(spendClassOf('ab12cd34', undefined), 'test');
  assertEquals(spendClassOf('ab12cd34', 'internal'), 'test');  // a test run is a test run whatever it declares
  assertEquals(spendClassOf(null, 'internal'), 'internal');
});

Deno.test('email_triage answers real mail and is never an internal duty', () => {
  assertEquals(INTERNAL_DUTY_FNS.has('email_triage'), false);
  assertEquals(INTERNAL_DUTY_FNS.has('wa_inbound'), false);
  assertEquals(INTERNAL_DUTY_FNS.has('resilience_ping'), true);
});

Deno.test('the ceiling refuses only on an explicit allowed:false; an error or an odd shape lets the duty run', () => {
  assertEquals(ceilingVerdict({ allowed: false, spent_usd: 10.2, ceiling_usd: 10, class: 'test' }, null).allowed, false);
  assertEquals(ceilingVerdict({ allowed: true }, null).allowed, true);
  assertEquals(ceilingVerdict(null, { message: 'boom' }).allowed, true);
  assertEquals(ceilingVerdict('yes', null).allowed, true);
  assertEquals(ceilingVerdict({}, null).allowed, true);
});
