// "AHMED SENT ME" IS HEARD AND KEPT (customer_support, 16 Nov 2026; agent W3_PEOPLE; CUSTOMER hole #11). The intake model reads how
// the customer says he heard of us, in his own words, and the referrer's number or address when he gave one; code only hands that to
// fn_customer_referral_record (scripts/sql/a_referral_is_recorded_counted_and_thanked.sql), which keeps it on his first request and
// thanks a referrer who is a verified customer once. Stubbed database: no network, no paid call.
// Each test fails if the behaviour it names is removed from inquiry_intake/customer_record.ts or its wiring in handle.ts.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { HEARD_ABOUT_US_FIELDS, recordReferral, referralOf } from './customer_record.ts';

Deno.test('the model\'s reading is kept as his words, with the referrer\'s contact only when he gave one', () => {
  assertEquals(referralOf({ heard_about_us: 'my neighbour Ahmed sent me', referrer_contact: '050 123 4567' }),
    { words: 'my neighbour Ahmed sent me', contact: '050 123 4567' });
  assertEquals(referralOf({ heard_about_us: '  saw you on Instagram ', referrer_contact: '' }), { words: 'saw you on Instagram', contact: null });
  assertEquals(referralOf({ heard_about_us: '' }), null);
  assertEquals(referralOf({ heard_about_us: null, referrer_contact: '050 123 4567' }), null);
  assertEquals(referralOf({}), null);
  assertEquals(referralOf(null), null);
  assertEquals(referralOf({ heard_about_us: 42 }), null);
  assertEquals(referralOf({ heard_about_us: 'x'.repeat(900) })!.words.length, 500);
});

Deno.test('the reading goes to the one routine with his id and the intake as its source; a failure never reaches the turn', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = async (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return { data: { ok: true, recorded: true }, error: null }; };
  const r = await recordReferral(rpc, 'c-1', { words: 'Ahmed sent me', contact: null }, 'intake-9');
  assertEquals(calls, [{ fn: 'fn_customer_referral_record', args: { p_customer: 'c-1', p_words: 'Ahmed sent me', p_contact: null, p_source: 'request_chat:intake-9' } }]);
  assertEquals(r, { ok: true, recorded: true });
  const broken = async () => { throw new Error('connection reset'); };
  assertEquals(await recordReferral(broken, 'c-1', { words: 'Ahmed sent me', contact: null }, 'intake-9'), null);
  assertEquals(await recordReferral(rpc, null, { words: 'Ahmed sent me', contact: null }, 'intake-9'), null);
});

Deno.test('the intake asks the model for it in the JSON it already returns, and records it without waiting', async () => {
  const src = await Deno.readTextFile(new URL('./handle.ts', import.meta.url));
  for (const f of HEARD_ABOUT_US_FIELDS) assert(src.includes(`\\"${f}\\": \\"<`), `the JSON shape names ${f}`);
  assertMatch(src, /referralOf\(out\)/);
  assertMatch(src, /void recordReferral\(/);
  // understanding is the model's: no keyword list decides that he was referred
  assert(!/sent me\|recommended\|heard/i.test(src), 'no keyword rule for a referral');
});
