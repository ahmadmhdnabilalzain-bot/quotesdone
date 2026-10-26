// The integration watch, replayed offline (it_engineer, 24 Sep 2026, instruction 979). Fails if a dead provider
// stops producing a finding, a passing retry stops counting as a self-fix, a missing secret is mistaken for a blip,
// an unreachable provider closes a finding, or a Postiz channel with refreshNeeded reads as connected.
//   deno test supabase/functions/_shared/integration_watch.test.ts supabase/functions/_shared/marketing_channels.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type Entry, founderMayBeAsked, integrationItems, isDue, REGISTRY, runEntry } from './integration_watch.ts';
import { channelState, socialIntegrationItems } from './marketing_channels.ts';

const noWait = () => Promise.resolve();
const sec = (m: Record<string, string>) => (k: string) => Promise.resolve(m[k] || '');
const env = () => undefined;
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
const stripe: Entry = REGISTRY.integrations.stripe;

Deno.test('a refused key is a failing integration with what broke, what was tried and the link', async () => {
  const o = await runEntry(() => Promise.resolve(reply(401, { error: { message: 'Invalid API Key' } })), 'stripe', stripe, sec({ stripe_secret_key: 'sk' }), env, noWait);
  assertEquals(o.state, 'failing');
  assert(o.what_broke!.includes('HTTP 401'));
  assertEquals(o.tried, ['retried after 3 s: still failing']);
});

Deno.test('a blip that passes on the retry is FIXED by the company, not a finding', async () => {
  let n = 0;
  const o = await runEntry(() => Promise.resolve(n++ === 0 ? reply(503, {}) : reply(200, {})), 'stripe', stripe, sec({ stripe_secret_key: 'sk' }), env, noWait);
  assertEquals(o.state, 'fixed');
});

Deno.test('an empty secret is a failure at once, never retried as a blip', async () => {
  let calls = 0;
  const o = await runEntry(() => { calls++; return Promise.resolve(reply(200, {})); }, 'stripe', stripe, sec({}), env, noWait);
  assertEquals(o.state, 'failing');
  assertEquals(calls, 0);
  assert(o.what_broke!.startsWith('not configured'));
});

Deno.test('expect: a Resend domain that is not verified fails', async () => {
  const o = await runEntry(() => Promise.resolve(reply(200, { status: 'failed' })), 'resend', REGISTRY.integrations.resend,
    sec({ resend_api_key: 'k', resend_domain_id: 'd' }), env, noWait);
  assertEquals(o.state, 'failing');
  assert(o.what_broke!.includes('expected verified'));
});

Deno.test('a Stripe webhook Stripe disabled is re-enabled: fixed, with what was tried', async () => {
  const f = (url: string, init?: RequestInit) => Promise.resolve(init?.method === 'POST'
    ? reply(200, { id: 'we_1', status: 'enabled' })
    : reply(200, { data: [{ id: 'we_1', url: 'https://x.supabase.co/functions/v1/stripe_webhook', status: 'disabled' }] }));
  const o = await runEntry(f, 'stripe_webhook', REGISTRY.integrations.stripe_webhook, sec({ stripe_secret_key: 'sk' }), env, noWait);
  assertEquals(o.state, 'fixed');
  assert(o.tried[0].startsWith('re-enabled endpoint we_1'));
});

Deno.test('an unreachable custom probe is NOT a reading: the item is carried, so nothing closes on it', async () => {
  const reg = { integrations: { stripe_webhook: REGISTRY.integrations.stripe_webhook } };
  const r = await integrationItems(() => Promise.reject(new Error('offline')), sec({ stripe_secret_key: 'sk' }), env, new Date(0), noWait, reg);
  assertEquals(r.items.length, 1);
  assertEquals(r.items[0].carried, true);
});

Deno.test('a passing probe is sent as RECOVERED, never as a failure or a carried item', async () => {
  const reg = { integrations: { stripe: REGISTRY.integrations.stripe } };
  const r = await integrationItems(() => Promise.resolve(reply(200, {})), sec({ stripe_secret_key: 'sk' }), env, new Date(0), noWait, reg);
  assertEquals(r.items.length, 1);
  assertEquals(r.items[0].recovered, true);
  assertEquals((r.items[0].evidence as Record<string, unknown>).recovered, true);
  assertEquals(r.items[0].carried, undefined);
});

Deno.test('an hourly entry runs on one beat in four; a 15-minute entry on every beat', () => {
  const beats = [0, 1, 2, 3].map((i) => new Date(i * 900_000));
  assertEquals(beats.filter((d) => isDue({ kind: 'http', every_minutes: 60 }, d)).length, 1);
  assertEquals(beats.filter((d) => isDue({ kind: 'http' }, d)).length, 4);
});

Deno.test('Postiz: refreshNeeded, disabled and inBetweenSteps are each dead; the live twin wins', () => {
  const l = (x: Record<string, unknown>) => ({ id: '1', identifier: 'facebook', ...x });
  assertEquals(channelState([l({ refreshNeeded: true })], 'facebook').state, 'refresh_needed');
  assertEquals(channelState([l({ inBetweenSteps: true })], 'facebook').state, 'in_between_steps');
  assertEquals(channelState([l({ disabled: true })], 'facebook').state, 'disabled');
  assertEquals(channelState([], 'facebook').state, 'missing');
  assertEquals(channelState([l({ refreshNeeded: true }), l({ id: '2' })], 'facebook').state, 'ok');
});

Deno.test('a disconnected Facebook is one item that names the channel and the reconnect link', () => {
  const items = socialIntegrationItems({ status: 200, list: [{ id: '9', identifier: 'facebook', refreshNeeded: true },
    { id: '1', identifier: 'instagram-standalone' }, { id: '2', identifier: 'linkedin-page' }, { id: '3', identifier: 'x' },
    { id: '4', identifier: 'youtube' }, { id: '5', identifier: 'tiktok-business' }] }, { state: 'ok' });
  assertEquals(items.map((i) => i.item), ['postiz:facebook']);
  assert(items[0].title.startsWith('Facebook is disconnected in Postiz'));
  assert(items[0].title.includes('https://platform.postiz.com/launches'));
});

Deno.test('Postiz unreadable: the API is the finding and every channel is carried, not closed', () => {
  const items = socialIntegrationItems({ status: 401, list: [], error: 'unauthorized' }, { state: 'unknown' });
  assertEquals(items[0].item, 'postiz:api');
  assert(items.slice(1).every((i) => i.carried));
});

// 5 Oct 2026 (notifications#84149): a keyless endpoint has no account holder, so it never reaches the founder.
Deno.test('a keyless integration is never the founder\'s; an account-backed one still is', () => {
  const keyless = { secrets: [], probe: { kind: 'http', auth: 'none' } };
  assertEquals(founderMayBeAsked(keyless), false);
  assertEquals(founderMayBeAsked({ probe: { kind: 'http' } }), false);
  assertEquals(founderMayBeAsked({ secrets: [], probe: { kind: 'http', auth: 'bearer:resend_api_key' } }), true);
  assertEquals(founderMayBeAsked({ secrets: ['x'], probe: { kind: 'http', auth: 'none' } }), true);
  assertEquals(founderMayBeAsked({ secrets: [], probe: { kind: 'custom' } }), true);
  assertEquals(founderMayBeAsked({ secrets: [], notify_founder: false, probe: { kind: 'http', auth: 'bearer:k' } }), false);
  for (const [k, e] of Object.entries(REGISTRY.integrations)) {
    if (e.probe.kind === 'http' && (e.probe.auth ?? 'none') === 'none' && !(e.secrets?.length)) assertEquals(founderMayBeAsked(e), false, k);
  }
});
