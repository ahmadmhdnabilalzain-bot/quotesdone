import { assertEquals } from 'jsr:@std/assert';
import { heldFromRows } from './llm_hold.ts';

const now = new Date('2026-09-22T12:00:00Z');

Deno.test('every route open in the future is the hold', () => {
  assertEquals(heldFromRows([{ open_until: '2126-08-15T02:51:36Z' }, { open_until: '2126-08-15T02:51:36Z' }], now), true);
});

Deno.test('one released route is not the hold', () => {
  assertEquals(heldFromRows([{ open_until: '2126-08-15T02:51:36Z' }, { open_until: null }], now), false);
});

Deno.test('a circuit that has already expired is not the hold', () => {
  assertEquals(heldFromRows([{ open_until: '2026-09-22T11:00:00Z' }], now), false);
});

Deno.test('no rows is not a hold — the gateway decides', () => {
  assertEquals(heldFromRows([], now), false);
  assertEquals(heldFromRows(null, now), false);
});
