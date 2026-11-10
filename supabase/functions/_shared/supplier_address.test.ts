// The address a supplier is written at: the one it signs in with, the listing's only when unclaimed (#1909 item 4).
import { assertEquals } from 'jsr:@std/assert@1';
import { supplierAddress } from './supplier_address.ts';

Deno.test('the sign-in address first, the listed one only when nobody claimed the company', () => {
  assertEquals(supplierAddress({ claimed_by: ' Owner@ZZ-Demo.example.invalid ', email: 'listing@zz-demo.example.invalid' }), 'owner@zz-demo.example.invalid');
  assertEquals(supplierAddress({ claimed_by: null, email: 'Listing@zz-demo.example.invalid' }), 'listing@zz-demo.example.invalid');
  assertEquals(supplierAddress({ claimed_by: '', email: '' }), null);
  assertEquals(supplierAddress({ email: 'not an address' }), null);
  assertEquals(supplierAddress(null), null);
});
