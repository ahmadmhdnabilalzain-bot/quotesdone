// A stop the word list misses is applied by the triage behind resend_inbound's gates, and never answered (28 Oct 2026,
// sales_engineer; ledger 1401 audit: "Please remove me / stop" to supplier@ was answered "Understood. We will not contact
// you again..." and the address stayed sendable). The client is a stub that records every call; no network, no model.
//   deno test --no-lock supabase/functions/email_triage/opt_out_backstop.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { applyBackstop, backstopApplies, type BackstopMail } from './opt_out_backstop.ts';

type Call = { table: string; op: string; args: unknown[]; chain: [string, unknown[]][] };
function stubDb(o: { invited?: number; upsertError?: string } = {}) {
  const calls: Call[] = [];
  const from = (table: string) => {
    const mk = (op: string, args: unknown[], result: unknown) => {
      const c: Call = { table, op, args, chain: [] }; calls.push(c);
      const b: Record<string, unknown> = {};
      for (const m of ['ilike', 'in', 'eq', 'is', 'select']) b[m] = (...a: unknown[]) => { c.chain.push([m, a]); return b; };
      b.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(result).then(res, rej);
      return b;
    };
    return {
      select: (...a: unknown[]) => mk('select', a, { count: o.invited ?? 1, data: null, error: null }),
      upsert: (...a: unknown[]) => mk('upsert', a, { error: o.upsertError ? { message: o.upsertError } : null }),
      update: (...a: unknown[]) => mk('update', a, { error: null }),
    };
  };
  return { calls, db: { from } };
}
const mail = (over: Partial<BackstopMail> = {}): BackstopMail => ({ id: 7, from_email: 'Owner@ZZ-Demo-Alu.example.invalid', raw: { sender_authenticated: true }, ...over });
const PROTECTED = ['management@quotesdone.com', 'founder@example.invalid'];

Deno.test("the backstop acts only on the model's opt_out, and only on an invited supplier's reply to supplier@", () => {
  assert(backstopApplies('opt_out', true));
  // any other mail (a customer's "cancel my request" to info@): the category is recorded, nothing else, he is answered as before
  assert(!backstopApplies('opt_out', false));
  for (const c of ['supplier_question', 'spam', 'other', '', null, undefined]) assert(!backstopApplies(c, true), String(c));
});

Deno.test('an invited, authenticated sender who asked to stop is suppressed exactly as an unsubscribe reply, and not answered', async () => {
  const { calls, db } = stubDb({ invited: 1 });
  const r = await applyBackstop(db, mail(), PROTECTED);
  assertEquals(r, { suppressed: true, why: '' });
  const gate = calls.find((c) => c.table === 'notifications')!;
  assertEquals(gate.chain.find((x) => x[0] === 'ilike')![1], ['to_email', 'owner@zz-demo-alu.example.invalid']);
  const types = gate.chain.find((x) => x[0] === 'in')![1][1] as string[];
  assert(types.includes('supplier_invite') && types.includes('supplier_invite_nudge'), types.join(','));
  const up = calls.find((c) => c.table === 'email_suppressions')!;
  assertEquals(up.op, 'upsert');
  assertEquals(up.args, [{ email: 'owner@zz-demo-alu.example.invalid', reason: 'unsubscribe', source: 'reply' }, { onConflict: 'email', ignoreDuplicates: true }]);
  const row = calls.find((c) => c.table === 'inbound_messages')!;
  assertEquals((row.args[0] as Record<string, unknown>).ai_category, 'opt_out');
  assertEquals((row.args[0] as Record<string, unknown>).needs_review, false);
  assertEquals((row.args[0] as Record<string, unknown>).ai_draft_reply, null);
  assertEquals(row.chain, [['eq', ['id', 7]]]);
});

Deno.test('a stop a gate refuses is never written, and is kept for a person', async () => {
  const cases: [string, Partial<BackstopMail>, { invited?: number }, RegExp][] = [
    ['our own domain', { from_email: 'ahmad@quotesdone.com' }, {}, /protected address/],
    ['an admin address', { from_email: 'Founder@example.invalid' }, {}, /protected address/],
    ['an unauthenticated From', { raw: { sender_authenticated: false } }, {}, /did not authenticate/],
    ['no verdict stored at all', { raw: null }, {}, /did not authenticate/],
    ['an address we never invited', {}, { invited: 0 }, /never sent this address/],
    ['no sender', { from_email: '' }, {}, /no sender address/],
  ];
  for (const [name, over, db0, why] of cases) {
    const { calls, db } = stubDb(db0);
    const r = await applyBackstop(db, mail(over), PROTECTED);
    assertEquals(r.suppressed, false, name);
    assert(why.test(r.why), name + ': ' + r.why);
    assertEquals(calls.filter((c) => c.table === 'email_suppressions').length, 0, name);
    const row = calls.find((c) => c.table === 'inbound_messages')!;
    assertEquals((row.args[0] as Record<string, unknown>).needs_review, true, name);
    assert(/NOT APPLIED/.test(String((row.args[0] as Record<string, unknown>).ai_summary)), name);
  }
});

Deno.test('a suppression that cannot be recorded is kept for a person, never reported as done', async () => {
  const { db } = stubDb({ invited: 1, upsertError: 'relation is locked' });
  const r = await applyBackstop(db, mail(), PROTECTED);
  assertEquals(r.suppressed, false);
  assert(/could not be recorded: relation is locked/.test(r.why));
});
