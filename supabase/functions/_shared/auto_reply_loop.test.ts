// Two machines never answer each other for ever (auto_reply_loop.ts). Run: deno test supabase/functions/_shared/auto_reply_loop.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { LOOP_CAP, loopVerdict, machineSounding, mailLoopHeld, type LoopEvent } from './auto_reply_loop.ts';

const MIN = 60_000;
const OOO = 'Thank you for contacting Al Noor Trading. We have received your message and our team will get back to you shortly.';

Deno.test('an auto-responder answering each of our replies: the fourth reply is stopped, the third was not', () => {
  const ev: LoopEvent[] = [{ at: 0, who: 'them', text: 'Hello, I need a quote for 20 doors' }];
  for (let i = 0; i < 3; i++) ev.push({ at: (i * 2 + 1) * MIN, who: 'us', text: 'reply ' + i }, { at: (i * 2 + 2) * MIN, who: 'them', text: OOO });
  assertEquals(loopVerdict(ev.slice(0, 5), 4 * MIN).stop, false, 'two replies since the person: go on');
  const v = loopVerdict(ev, 6 * MIN);
  assertEquals(v.oursSinceHuman, LOOP_CAP);
  assertEquals(v.stop, true);
});

Deno.test('one human-sounding message resets the count', () => {
  const ev: LoopEvent[] = [
    { at: 1 * MIN, who: 'us', text: 'a' }, { at: 2 * MIN, who: 'them', text: OOO },
    { at: 3 * MIN, who: 'us', text: 'b' }, { at: 4 * MIN, who: 'them', text: OOO },
    { at: 5 * MIN, who: 'us', text: 'c' }, { at: 6 * MIN, who: 'them', text: 'sorry, that was our system. yes, 20 doors please' },
  ];
  assertEquals(loopVerdict(ev, 6 * MIN).stop, false);
});

Deno.test('outside the hour nothing counts', () => {
  const ev: LoopEvent[] = [1, 2, 3].map((i) => ({ at: i * MIN, who: 'us' as const, text: 'x' }));
  assertEquals(loopVerdict(ev, 3 * MIN).stop, true);
  assertEquals(loopVerdict(ev, 3 * MIN + 61 * MIN).stop, false);
});

Deno.test('machine-sounding: auto-reply phrases in English and Arabic, and a long verbatim repeat; a person is not', () => {
  for (const t of ['Automatic reply: I am out of the office', "I'm currently on annual leave until Sunday", 'This is an automated message, please do not reply',
    'رد تلقائي: شكرًا لتواصلكم', 'أنا في إجازة حتى الأحد', OOO]) assert(machineSounding(t), t);
  for (const t of ['ok', 'Can you send the quote by Thursday?', 'شكرًا، أحتاج عرض سعر لعشرين باب', '']) assert(!machineSounding(t), t);
  const repeat = 'Please send your request to our sales desk';
  assert(!machineSounding(repeat));
  assert(machineSounding(repeat, [repeat]), 'the same 20+ characters again is a responder');
  assert(!machineSounding('hello', ['hello']), 'a short repeat is a person');
});

// email: the outbox's answers to the address and the inbox's mails from it, read for the last hour
function mailDb(ours: Record<string, unknown>[], theirs: Record<string, unknown>[], fail = false) {
  const rpcs: string[] = [];
  const admin = {
    from: (t: string) => {
      const q: Record<string, unknown> = {};
      for (const k of ['select', 'eq', 'in', 'ilike', 'gte']) q[k] = () => q;
      q.limit = () => Promise.resolve(fail ? { data: null, error: { message: 'timeout' } } : { data: t === 'notifications' ? ours : theirs, error: null });
      return q;
    },
    rpc: (fn: string) => { rpcs.push(fn); return Promise.resolve({ data: null, error: null }); },
  };
  return { admin, rpcs };
}
Deno.test('email: three answers to a ticket system inside the hour stop the fourth and raise a finding; a read failure never stops one', async () => {
  const now = Date.parse('2026-11-11T10:00:00Z');
  const iso = (min: number) => new Date(now - min * MIN).toISOString();
  const ours = [50, 30, 10].map((m) => ({ created_at: iso(m), sent_at: iso(m) }));
  const theirs = [{ id: 1, created_at: iso(55), subject: 'Quote for doors', body: 'We need 20 doors for a villa' },
    ...[40, 20].map((m, i) => ({ id: 2 + i, created_at: iso(m), subject: 'Automatic reply: Quote for doors', body: 'Your ticket number is 88' + i }))];
  const db = mailDb(ours, theirs);
  const m = { id: 9, from_email: 'Support@Example.invalid', subject: 'Automatic reply: Re: Quote for doors', body: 'Your ticket number is 889' };
  assertEquals(await mailLoopHeld(db.admin, m, now), true);
  assertEquals(db.rpcs, ['fn_it_engineer_finding_upsert']);
  assertEquals(await mailLoopHeld(mailDb(ours, theirs, true).admin, m, now), false, 'unreadable: answered as before');
  assertEquals(await mailLoopHeld(mailDb(ours, theirs).admin, { ...m, subject: 'Re: Quote for doors', body: 'Thanks, can you do Thursday?' }, now), false, 'a person');
});
