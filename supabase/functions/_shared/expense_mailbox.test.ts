import { assertEquals } from 'jsr:@std/assert@1';
import { mailboxMessages, registerRowsFor, sameVendor, survivingEntryId } from './expense_mailbox.ts';

const BOX = 'expenses@mail.quotesdone.com';
const since = Date.parse('2026-09-10T00:00:00Z');

Deno.test('only messages addressed to the mailbox, inside the window, are the mailbox', () => {
  const got = mailboxMessages([
    { id: 'a', to: ['Expenses@mail.quotesdone.com'], from: 'X@example.invalid', created_at: '2026-09-23T23:37:48Z' },
    { id: 'b', to: 'support@mail.quotesdone.com', created_at: '2026-09-23T00:00:00Z' },
    { id: 'c', to: [BOX], created_at: '2026-09-01T00:00:00Z' },            // before the window
    { id: 'd', to: ['my-expenses@example.invalid'], created_at: '2026-09-20T00:00:00Z' }, // a word, not the address
    { id: '', to: [BOX], created_at: '2026-09-20T00:00:00Z' },
  ], BOX, since);
  assertEquals(got.map((m) => m.id), ['a']);
  assertEquals(got[0].from, 'x@example.invalid');
});

Deno.test('a register row matches the booked vendor by identity, never as a pattern', () => {
  assertEquals(sameVendor(' GitHub ', 'github'), true);
  assertEquals(sameVendor('Git_ub', 'GitHub'), false);   // LIKE would have matched: '_' is any character
  assertEquals(sameVendor('Resend%', 'Resend Inc'), false);
});

Deno.test('registerRowsFor reads the active register and keeps only the same vendor', async () => {
  const rows = [{ id: 1, vendor: 'GitHub', expense_date: '2026-09-01' }, { id: 2, vendor: 'Git_ub', expense_date: null }];
  const admin = { from: () => ({ select: () => ({ eq: () => Promise.resolve({ data: rows }) }) }) };
  assertEquals(await registerRowsFor(admin, 'github'), [{ id: 1, expense_date: '2026-09-01' }]);
});

// A stub of the two reads survivingEntryId makes: by source_msg_id, then by id.
const entriesAdmin = (rows: { id: number; source_msg_id: string | null }[]) => ({
  from: () => ({ select: () => ({ eq: (col: string, v: unknown) => ({
    limit: () => Promise.resolve({ data: rows.filter((r) => (r as Record<string, unknown>)[col] === v).map((r) => ({ id: r.id })) }),
  }) }) }),
});

Deno.test('after a fold the surviving held entry is found by the message key, never the deleted receipt id', async () => {
  // receipt row 70 was folded into held entry 12; the key moved onto 12 and row 70 is gone
  const admin = entriesAdmin([{ id: 12, source_msg_id: 'resend:abc' }]);
  assertEquals(await survivingEntryId(admin, 70, 'resend:abc'), 12);
});

Deno.test('no fold: the inserted row is the survivor; a deleted row with no key holder files nothing', async () => {
  assertEquals(await survivingEntryId(entriesAdmin([{ id: 70, source_msg_id: 'resend:abc' }]), 70, 'resend:abc'), 70);
  assertEquals(await survivingEntryId(entriesAdmin([{ id: 70, source_msg_id: null }]), 70, null), 70);
  assertEquals(await survivingEntryId(entriesAdmin([]), 70, 'resend:gone'), null);
  assertEquals(await survivingEntryId(entriesAdmin([]), null, null), null);
});
