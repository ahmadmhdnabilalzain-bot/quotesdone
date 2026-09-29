// deno test supabase/functions/_shared/it_rotate_by_api.test.ts
// Replays the ways a rotation can go: it works, the new key does not authenticate, the store fails, there is no
// baseline yet, and a retire row names the key in use.
// The rule under test: the old key is never left without a working replacement, the key in use is never deleted,
// the first run never rotates (it records when the current key was created), and no secret leaves the module.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rotateAndSettle, rotateTwilioKey, type RotateDeps } from './it_rotate_by_api.ts';

const SECRET = 'new-secret-value-never-returned';
function deps(o: { verifyOk?: boolean; storeFails?: boolean; storeCommitsThenErrors?: boolean; readBack?: string;
                   inUseUnreadable?: boolean; due?: boolean; baselineNeeded?: boolean; keyCreated?: string | null;
                   retireDue?: { id: number; old_ref: string }[] } = {}) {
  const calls: string[] = []; const rpcs: [string, Record<string, unknown> | undefined][] = [];
  const balanceAuth: string[] = [];
  // app_secrets as the rotation sees it: the record writes the new pair here, exactly as the SQL does.
  const secrets: Record<string, string> = { twilio_account_sid: 'AC1', twilio_auth_token: 'tok', twilio_api_key_sid: 'SKold' };
  let recorded = false;
  const d: RotateDeps = {
    sleep: async () => {},
    // AS resilience_ping's sec() ANSWERS (review of #1038): a failed or empty read is '' - it never throws. A mock
    // that threw here tested a branch production cannot reach. readBack: what the key-SID read returns once the
    // store has run; inUseUnreadable: the key-SID read returns '' from the start.
    sec: async (k) => {
      if (k === 'twilio_api_key_sid' && o.inUseUnreadable) return '';
      if (k === 'twilio_api_key_sid' && recorded && o.readBack !== undefined) return o.readBack;
      return secrets[k] ?? '';
    },
    rpc: async (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_it_provider_rotation_retire_due') return o.retireDue ?? [];
      if (fn === 'fn_it_provider_rotation_claim') return o.baselineNeeded ? { due: false, baseline_needed: true } : { due: o.due ?? true };
      if (fn === 'fn_it_provider_rotation_record') {
        if (o.storeFails) throw new Error('store failed');
        secrets.twilio_api_key_sid = String(args?.p_new_ref); secrets.twilio_api_key_secret = String(args?.p_new_secret);
        recorded = true;
        if (o.storeCommitsThenErrors || o.readBack !== undefined) throw new Error('upstream request timeout');
      }
      return null;
    },
    fetch: async (url, init) => {
      calls.push(init.method + ' ' + url);
      if (init.method === 'POST') return new Response(JSON.stringify({ sid: 'SKnew', secret: SECRET }), { status: 201 });
      if (init.method === 'DELETE') return new Response(null, { status: 204 });
      if (url.endsWith('/Keys/SKold.json')) {
        return new Response(JSON.stringify(o.keyCreated === null ? {} : { sid: 'SKold', date_created: o.keyCreated ?? 'Thu, 25 Jun 2026 19:05:32 +0000' }), { status: 200 });
      }
      // TWILIO AS IT ANSWERS (review of #1038): a Standard API key (user SK...) may read the balance but NOT the
      // account resource, which answers 401 / code 20003 - the mock used to say 200 to any GET and hid that.
      const user = atob(String((init.headers as Record<string, string>)?.Authorization ?? '').replace(/^Basic /, '')).split(':')[0];
      const denied = new Response(JSON.stringify({ code: 20003, message: 'Authenticate', status: 401 }), { status: 401 });
      if (user.startsWith('SK') && /\/Accounts\/AC1\.json$/.test(url)) return denied;
      if (/\/Accounts\/AC1\/Balance\.json$/.test(url)) {
        // The proof must be made WITH THE NEW KEY: anything else (the old key, the auth token) proves nothing about it.
        const auth = String((init.headers as Record<string, string>)?.Authorization ?? '');
        balanceAuth.push(auth);
        if (auth !== 'Basic ' + btoa('SKnew:' + SECRET)) return denied;
        return o.verifyOk === false ? denied : new Response(JSON.stringify({ balance: '12.34', currency: 'USD' }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    },
  };
  return { d, calls, rpcs, balanceAuth };
}

Deno.test('a due rotation creates, proves, stores and records the new key, and returns no secret', async () => {
  const { d, calls, rpcs } = deps();
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, true); assertEquals(r.old_ref, 'SKold'); assertEquals(r.new_ref, 'SKnew');
  assert(!JSON.stringify(r).includes(SECRET), 'the result must never carry the secret');
  assert(!calls.some((c) => c.startsWith('DELETE')), 'the old key is not deleted at rotation, only after the overlap');
  const rec = rpcs.find(([f]) => f === 'fn_it_provider_rotation_record')!;
  assertEquals(rec[1], { p_provider: 'twilio', p_old_ref: 'SKold', p_new_ref: 'SKnew', p_new_secret: SECRET });
});

Deno.test('a new key that does not authenticate is deleted and nothing is stored', async () => {
  const { d, calls, rpcs } = deps({ verifyOk: false });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, false); assertEquals(r.ok, false);
  assert(calls.includes('DELETE https://api.twilio.com/2010-04-01/Accounts/AC1/Keys/SKnew.json'));
  assert(!rpcs.some(([f]) => f === 'fn_it_provider_rotation_record'));
});

Deno.test('a failed store deletes the new key, so the old one stays the only one', async () => {
  const { d, calls } = deps({ storeFails: true });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, false);
  assert(calls.includes('DELETE https://api.twilio.com/2010-04-01/Accounts/AC1/Keys/SKnew.json'));
  assert(!JSON.stringify(r).includes(SECRET));
});

Deno.test('not due: no key is created; an overlap that ended deletes the old key and closes its row', async () => {
  const { d, calls, rpcs } = deps({ due: false, retireDue: [{ id: 7, old_ref: 'SKolder' }] });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, false); assertEquals(r.retired, ['SKolder']);
  assert(!calls.some((c) => c.startsWith('POST')));
  assert(rpcs.some(([f, a]) => f === 'fn_it_provider_rotation_retired' && a?.p_id === 7));
});

Deno.test('no baseline: the current key creation date is recorded and nothing is rotated', async () => {
  const { d, calls, rpcs } = deps({ baselineNeeded: true });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, false);
  assert(!calls.some((c) => c.startsWith('POST') || c.startsWith('DELETE')), 'the first run creates and deletes nothing');
  const b = rpcs.find(([f]) => f === 'fn_it_provider_rotation_baseline')!;
  assertEquals(b[1], { p_provider: 'twilio', p_ref: 'SKold', p_created_at: '2026-06-25T19:05:32.000Z' });
});

Deno.test('no baseline and no readable creation date: nothing is recorded and nothing is rotated', async () => {
  const { d, calls, rpcs } = deps({ baselineNeeded: true, keyCreated: null });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, false); assertEquals(r.ok, false);
  assert(!rpcs.some(([f]) => f === 'fn_it_provider_rotation_baseline'));
  assert(!calls.some((c) => c.startsWith('POST') || c.startsWith('DELETE')));
});

Deno.test('a retire row that names the key in use never deletes it', async () => {
  const { d, calls, rpcs } = deps({ due: false, retireDue: [{ id: 9, old_ref: 'SKold' }] });
  const r = await rotateTwilioKey(d);
  assertEquals(r.ok, false); assertEquals(r.retired, []);
  assert(!calls.some((c) => c.startsWith('DELETE')));
  assert(!rpcs.some(([f]) => f === 'fn_it_provider_rotation_retired'));
});

Deno.test('the new key is proved on Balance.json, the call a Standard key may make', async () => {
  const { d, calls, balanceAuth } = deps();
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, true);
  assert(calls.includes('GET https://api.twilio.com/2010-04-01/Accounts/AC1/Balance.json'));
  assertEquals(balanceAuth, ['Basic ' + btoa('SKnew:' + SECRET)], 'the balance is read with the NEW key sid and secret');
  assert(!calls.includes('GET https://api.twilio.com/2010-04-01/Accounts/AC1.json'), 'a Standard key is refused 20003 there');
});

Deno.test('a failed rotation is settled as an open finding, and a clean run settles it closed', async () => {
  const bad = deps({ verifyOk: false });
  const r = await rotateAndSettle(bad.d);
  assertEquals(r.ok, false);
  const s = bad.rpcs.find(([f]) => f === 'fn_it_duty_settle')!;
  assertEquals(s[1]?.p_duty, 'rotate_by_api');
  const items = s[1]?.p_items as { item: string; title: string }[];
  assertEquals(items.length, 1); assertEquals(items[0].item, 'twilio');
  assert(!JSON.stringify(s[1]).includes(SECRET), 'no secret reaches the finding');

  const good = deps();
  await rotateAndSettle(good.d);
  assertEquals(good.rpcs.find(([f]) => f === 'fn_it_duty_settle')![1]?.p_items, []);
});

Deno.test('a store that committed but reported an error never deletes the now-live key', async () => {
  const { d, calls } = deps({ storeCommitsThenErrors: true });
  const r = await rotateTwilioKey(d);
  assertEquals(r.rotated, true); assertEquals(r.new_ref, 'SKnew');
  assert(!calls.some((c) => c.startsWith('DELETE')), 'SKnew is what sign-in OTP now uses; deleting it would stop every code');
  assert(!JSON.stringify(r).includes(SECRET));
});

Deno.test("a committed store whose read-back is '' keeps the new key, fails the run and raises an unverified finding", async () => {
  const { d, calls, rpcs } = deps({ readBack: '' });
  const r = await rotateAndSettle(d);
  assertEquals(r.ok, false); assertEquals(r.new_ref, 'SKnew');
  assert(!calls.some((c) => c.startsWith('DELETE')), "'' proves nothing: SKnew may be the live key, so it is never deleted");
  const items = rpcs.find(([f]) => f === 'fn_it_duty_settle')![1]?.p_items as { title: string }[];
  assertEquals(items.length, 1); assert(/unverified/i.test(items[0].title), items[0].title);
  assert(!JSON.stringify(r).includes(SECRET));
});

Deno.test('a store error whose read-back names neither key keeps the new key and fails the run', async () => {
  const { d, calls } = deps({ readBack: 'SKsomeoneelse' });
  const r = await rotateTwilioKey(d);
  assertEquals(r.ok, false); assertEquals(r.rotated, false);
  assert(!calls.some((c) => c.startsWith('DELETE')), 'only a read-back of the OLD key proves the new one is unused');
});

Deno.test("a retire step whose key in use reads '' deletes nothing", async () => {
  const { d, calls, rpcs } = deps({ due: false, inUseUnreadable: true, retireDue: [{ id: 11, old_ref: 'SKold' }, { id: 12, old_ref: 'SKolder' }] });
  const r = await rotateTwilioKey(d);
  assertEquals(r.ok, false); assertEquals(r.retired, []);
  assert(!calls.some((c) => c.startsWith('DELETE')), 'an unread key in use could be any of them; none is deleted');
  assert(!rpcs.some(([f]) => f === 'fn_it_provider_rotation_retired'));
});

Deno.test('a thrown step is settled too, never lost', async () => {
  const { d, rpcs } = deps();
  // sec() never throws (it answers ''); an rpc can, so the throw comes from the first rpc.
  const boom: RotateDeps = { ...d, rpc: async (fn, args) => {
    if (fn === 'fn_it_provider_rotation_retire_due') throw new Error('database unreachable');
    return d.rpc(fn, args);
  } };
  const r = await rotateAndSettle(boom);
  assertEquals(r.ok, false);
  assertEquals((rpcs.find(([f]) => f === 'fn_it_duty_settle')![1]?.p_items as unknown[]).length, 1);
});

Deno.test("the '' in-use key refuses to rotate: no new key is minted, the run fails UNVERIFIED", async () => {
  const { d, calls } = deps({ inUseUnreadable: true, due: true });
  const r = await rotateTwilioKey(d);
  assertEquals(r.ok, false); assertEquals(r.rotated, false);
  assert(String(r.error).startsWith('UNVERIFIED'), String(r.error));
  assert(!calls.some((c) => c.startsWith('POST') && c.includes('/Keys.json')), 'a new key was minted with no key in use read');
});
