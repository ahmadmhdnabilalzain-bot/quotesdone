import { assertEquals } from 'jsr:@std/assert@1';
import { disputeEvidenceForm, MAX_FIELD_CHARS } from './dispute_evidence.ts';

Deno.test('only Stripe evidence fields are sent, empty ones are dropped, and the receipt file is attached', () => {
  const f = disputeEvidenceForm({ customer_name: 'ZZ DEMO Customer', product_description: 'A paid reveal', service_date: '2026-09-14',
    uncategorized_text: '', not_a_stripe_field: 'x', customer_email_address: null }, { receipt: 'file_123' });
  assertEquals(f.get('evidence[customer_name]'), 'ZZ DEMO Customer');
  assertEquals(f.get('evidence[product_description]'), 'A paid reveal');
  assertEquals(f.get('evidence[service_date]'), '2026-09-14');
  assertEquals(f.has('evidence[uncategorized_text]'), false);
  assertEquals(f.has('evidence[customer_email_address]'), false);
  assertEquals(f.has('evidence[not_a_stripe_field]'), false);
  assertEquals(f.get('evidence[receipt]'), 'file_123');
  assertEquals(f.has('evidence[customer_signature]'), false);
  assertEquals(f.get('submit'), 'true');
});

Deno.test('a field is cut to Stripe\'s size and a non-file receipt id is never sent', () => {
  const f = disputeEvidenceForm({ access_activity_log: 'a'.repeat(MAX_FIELD_CHARS + 50) }, { receipt: 'not-a-file' }, false);
  assertEquals(f.get('evidence[access_activity_log]')!.length, MAX_FIELD_CHARS);
  assertEquals(f.has('evidence[receipt]'), false);
  assertEquals(f.get('submit'), 'false');
});

Deno.test('the signed-terms certificate goes up as customer_signature, and the CEO-only fields never leave', () => {
  const f = disputeEvidenceForm({ ceo_summary: 'REPEAT DISPUTER', ceo_prior_disputes: 2, uncategorized_text: 'x' }, { customer_signature: 'file_sig' }, false);
  assertEquals(f.get('evidence[customer_signature]'), 'file_sig');
  assertEquals([...f.keys()].some((k) => k.includes('ceo_')), false);
});
