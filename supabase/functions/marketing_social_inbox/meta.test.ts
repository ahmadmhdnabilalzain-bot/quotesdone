// deno test supabase/functions/marketing_social_inbox/meta.test.ts
// The Meta webhook contract: signature, handshake, event parsing (echoes and our own comments are
// never answered), the 24-hour window and the send shape. Mocked payloads only; ZZDEMO ids.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { clip, handshake, maxLen, OUR_METADATA, parseEvents, sendRequest, verifySignature, withinWindow } from './meta.ts';

const SECRET = 'zz-demo-app-secret';
async function sign(body: string, secret = SECRET): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)));
  return 'sha256=' + [...mac].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const PAGE = 'ZZDEMO_PAGE_1';
const dm = (text: string, extra: Record<string, unknown> = {}) => ({
  object: 'instagram',
  entry: [{ id: PAGE, time: Date.now(), messaging: [{ sender: { id: 'ZZDEMO_USER_1' }, recipient: { id: PAGE }, timestamp: Date.now(), message: { mid: 'ZZDEMO_MID_1', text, ...extra } }] }],
});

Deno.test('signature: a body signed with the app secret passes', async () => {
  const body = JSON.stringify(dm('hello'));
  assert(await verifySignature(body, await sign(body), SECRET));
});
Deno.test('signature: a tampered body, a wrong secret, a missing header, a missing secret and a sha1 header all fail', async () => {
  const body = JSON.stringify(dm('hello'));
  const good = await sign(body);
  assertEquals(await verifySignature(body.replace('hello', 'hellp'), good, SECRET), false);
  assertEquals(await verifySignature(body, await sign(body, 'other'), SECRET), false);
  assertEquals(await verifySignature(body, null, SECRET), false);
  assertEquals(await verifySignature(body, good, undefined), false);
  assertEquals(await verifySignature(body, good.replace('sha256=', 'sha1='), SECRET), false);
});

Deno.test('handshake: the right token returns the challenge; anything else is refused', () => {
  const u = (q: string) => new URL('https://x.invalid/functions/v1/marketing_social_inbox?' + q);
  assertEquals(handshake(u('hub.mode=subscribe&hub.verify_token=zz-tok&hub.challenge=123'), 'zz-tok'), '123');
  assertEquals(handshake(u('hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=123'), 'zz-tok'), null);
  assertEquals(handshake(u('hub.mode=unsubscribe&hub.verify_token=zz-tok&hub.challenge=123'), 'zz-tok'), null);
  assertEquals(handshake(u('hub.mode=subscribe&hub.verify_token=zz-tok&hub.challenge=123'), undefined), null);
  assertEquals(handshake(u('hub.mode=subscribe&hub.verify_token=&hub.challenge=123'), undefined), null);
});

Deno.test('parse: an Instagram DM becomes one inbound event keyed on its mid', () => {
  const [e, ...rest] = parseEvents(dm('How does it work?'));
  assertEquals(rest.length, 0);
  assertEquals([e.platform, e.channel, e.userId, e.messageId, e.text, e.echo], ['instagram', 'dm', 'ZZDEMO_USER_1', 'ZZDEMO_MID_1', 'How does it work?', false]);
});
Deno.test('parse: an echo is flagged and keyed on the PERSON (recipient), never on us', () => {
  const body = { object: 'page', entry: [{ id: PAGE, messaging: [{ sender: { id: PAGE }, recipient: { id: 'ZZDEMO_USER_2' }, timestamp: Date.now(), message: { mid: 'm2', text: 'hi', is_echo: true, app_id: 42, metadata: OUR_METADATA } }] }] };
  const [e] = parseEvents(body);
  assertEquals([e.echo, e.userId, e.echoAppId, e.echoMetadata], [true, 'ZZDEMO_USER_2', '42', OUR_METADATA]);
});
Deno.test('parse: reads, deliveries, deleted and text-less messages carry nothing to answer', () => {
  const body = { object: 'page', entry: [{ id: PAGE, messaging: [
    { sender: { id: 'u' }, recipient: { id: PAGE }, read: { watermark: 1 } },
    { sender: { id: 'u' }, recipient: { id: PAGE }, delivery: { mids: ['x'] } },
    { sender: { id: 'u' }, recipient: { id: PAGE }, message: { mid: 'd', is_deleted: true } },
    { sender: { id: 'u' }, recipient: { id: PAGE }, message: { mid: 's', attachments: [{ type: 'image' }] } },
  ] }] };
  assertEquals(parseEvents(body).length, 0);
});
Deno.test('parse: Facebook and Instagram comments; our OWN comment is dropped (no reply loop)', () => {
  const fb = { object: 'page', entry: [{ id: PAGE, changes: [
    { field: 'feed', value: { item: 'comment', verb: 'add', comment_id: 'c1', post_id: 'p1', from: { id: 'ZZDEMO_U3', name: 'ZZ DEMO Commenter' }, message: 'price?', created_time: Math.floor(Date.now() / 1000) } },
    { field: 'feed', value: { item: 'comment', verb: 'add', comment_id: 'c2', post_id: 'p1', from: { id: PAGE, name: 'QuotesDone' }, message: 'our reply', created_time: 1 } },
    { field: 'feed', value: { item: 'reaction', verb: 'add', from: { id: 'x' } } },
  ] }] };
  const f = parseEvents(fb);
  assertEquals(f.map((e) => [e.channel, e.messageId, e.handle, e.parentId]), [['comment', 'c1', 'ZZ DEMO Commenter', 'p1']]);
  const ig = { object: 'instagram', entry: [{ id: PAGE, changes: [
    { field: 'comments', value: { id: 'ic1', text: 'how does it work', from: { id: 'ZZDEMO_U4', username: 'zzdemo_user' }, media: { id: 'mid1' } } },
    { field: 'comments', value: { id: 'ic2', text: 'thanks!', from: { id: PAGE, username: 'quotesdone' }, media: { id: 'mid1' } } },
  ] }] };
  assertEquals(parseEvents(ig).map((e) => e.messageId), ['ic1']);
  assertEquals(parseEvents({ object: 'whatsapp_business_account', entry: [] }).length, 0);
});

Deno.test('window: 23 hours is inside Meta\'s 24-hour window, 25 hours is outside', () => {
  const now = new Date('2026-09-22T12:00:00Z');
  assert(withinWindow(new Date(now.getTime() - 23 * 3600e3), now));
  assertEquals(withinWindow(new Date(now.getTime() - 25 * 3600e3), now), false);
});

Deno.test('send: DM, Instagram comment and Facebook comment requests go to the right Graph edge', () => {
  const [ig] = parseEvents(dm('hi'));
  const a = sendRequest(ig, 'hello', 'TOKEN');
  assert(a.url.startsWith('https://graph.facebook.com/v21.0/me/messages?access_token=TOKEN'));
  assertEquals(a.body, { recipient: { id: 'ZZDEMO_USER_1' }, messaging_type: 'RESPONSE', message: { text: 'hello' } });
  const fbDm = { ...ig, platform: 'facebook' as const };
  assertEquals((sendRequest(fbDm, 'x', 'T').body.message as any).metadata, OUR_METADATA);
  const igc = { ...ig, channel: 'comment' as const, messageId: 'ic1' };
  assert(sendRequest(igc, 'x', 'T').url.includes('/ic1/replies?'));
  const fbc = { ...igc, platform: 'facebook' as const, messageId: 'c1' };
  assert(sendRequest(fbc, 'x', 'T').url.includes('/c1/comments?'));
});

Deno.test('length: replies are clipped under each platform\'s limit', () => {
  assertEquals(maxLen('instagram', 'dm') < 1000, true);
  assertEquals(maxLen('facebook', 'dm') < 2000, true);
  assert(clip('word '.repeat(400), maxLen('facebook', 'comment')).length <= 300);
});
