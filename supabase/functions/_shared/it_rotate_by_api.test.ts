// deno test supabase/functions/_shared/it_rotate_by_api.test.ts
// Replays the three ways a rotation can go: it works, the new key does not authenticate, the store fails.
// The rule under test: the old key is never left without a working replacement, and no secret leaves the module.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rotateTwilioKey, type RotateDeps } from './it_rotate_by_api.ts';

const SECRET = 'new-secret-value-never-returned';
function deps(o: { verifyOk?: boolean; storeFails?: boolean; due?: boolean; retireDue?: { id: number; old_ref: string }[] } = {}) {
  const calls: string[] = []; const rpcs: [string, Record<string, unknown> | undefined][] = [];
  const d: RotateDeps = {
    sleep: async () => {},
    sec: async (k) => ({ twilio_account_sid: 'AC1', twilio_auth_token: 'tok', twilio_api_key_sid: 'SKold' } as Record<string, string>)[k] ?? '',
    rpc: async (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_it_provider_rotation_retire_due') return o.retireDue ?? [];
      if (fn === 'fn_it_provider_rotation_claim') return { due: o.due ?? true };
      if (fn === 'fn_it_provider_rotation_record' && o.storeFails) throw new Error('store failed');
      return null;
    },
    fetch: async (url, init) => {
      calls.push(init.method + ' ' + url);
      if (init.method === 'POST') return new Response(JSON.stringify({ sid: 'SKnew', secret: SECRET }), { status: 201 });
      if (init.method === 'DELETE') return new Response(null, { status: 204 });
      return new Response('{}', { status: o.verifyOk === false ? 401 : 200 });
    },
  };
  return { d, calls, rpcs };
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
