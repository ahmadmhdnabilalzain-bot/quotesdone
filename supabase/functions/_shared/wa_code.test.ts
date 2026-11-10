// A WHATSAPP PHONE CODE WE SEND OURSELVES (ledger 1252: "USD 0.17 per OTP is way too much"). _shared/wa_code.ts.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { checkOwnCode, loginTemplateSid, macInput, newCode, ownMarker, ownMessageStatus, ownSent, sendOwnWhatsAppCode, type WaCodeDeps } from './wa_code.ts';
import { statusCallbackUrl } from './twilio_status.ts';
import { channelOfRow, isOwnRow, nextChannel, sidOfRow } from './whatsapp_choice.ts';

const SM = 'SM' + 'a'.repeat(32), HX_EN = 'HX' + '1'.repeat(32), HX_AR = 'HX' + '2'.repeat(32);
const PHONE = '+971501234567';
const SECRETS: Record<string, string> = { twilio_account_sid: 'AC' + '0'.repeat(32), twilio_api_key_sid: 'SK' + '0'.repeat(32), twilio_api_key_secret: 'x',
  twilio_wa_from: '+97140000000', wa_template_sids: JSON.stringify({ login_code: { en: HX_EN, ar: HX_AR } }) };
const hmac = (s: string) => Promise.resolve('mac(' + s + ')');

type Rpc = { fn: string; args: Record<string, unknown> };
function deps(o: { issue?: unknown; issueError?: boolean; verify?: unknown; twilio?: (url: string, init: RequestInit) => Response; secrets?: Record<string, string> } = {}) {
  const rpcs: Rpc[] = [], http: { url: string; body: string }[] = [];
  const admin = { rpc: (fn: string, args: Record<string, unknown>) => {
    rpcs.push({ fn, args });
    if (fn === 'fn_phone_code_issue') return Promise.resolve(o.issueError ? { data: null, error: { message: 'relation "phone_code" does not exist' } } : { data: o.issue ?? 41, error: null });
    if (fn === 'fn_phone_code_verify') return Promise.resolve({ data: 'verify' in o ? o.verify : 'wrong', error: null });
    return Promise.resolve({ data: null, error: null });
  } };
  const d: WaCodeDeps = { admin, hmac, secret: (k) => Promise.resolve((o.secrets ?? SECRETS)[k] ?? null),
    fetch: ((url: string, init: RequestInit = {}) => { http.push({ url: String(url), body: String(init.body ?? '') }); return Promise.resolve(o.twilio ? o.twilio(String(url), init) : new Response(JSON.stringify({ sid: SM, status: 'queued' }), { status: 201 })); }) as WaCodeDeps['fetch'] };
  return { d, rpcs, http };
}

Deno.test('a code is six digits, zero-padded, and a draw past the last whole million is redrawn (no modulo bias)', () => {
  assertEquals(newCode(() => 42), '000042');
  const draws = [4_294_967_295, 4_294_000_000, 1_234_567];
  assertEquals(newCode(() => draws.shift()!), '234567');
  for (let i = 0; i < 200; i++) assert(/^\d{6}$/.test(newCode()));
});

Deno.test('the template SID is the language one, English when that language has none, and nothing that is not an HX SID', () => {
  assertEquals(loginTemplateSid(SECRETS.wa_template_sids, 'ar'), HX_AR);
  assertEquals(loginTemplateSid(SECRETS.wa_template_sids, 'en'), HX_EN);
  assertEquals(loginTemplateSid({ login_code: { en: HX_EN } }, 'ar'), HX_EN);
  assertEquals(loginTemplateSid({ login_code: { en: 'pending' } }, 'en'), null);
  assertEquals(loginTemplateSid('{not json', 'en'), null);
  assertEquals(loginTemplateSid({}, 'en'), null);
});

Deno.test('the MAC binds purpose, number and account: the same digits for another purpose or account are a different MAC', () => {
  const a = macInput('kyc_phone', PHONE, 'A@x.invalid', '123456');
  assertEquals(a, macInput('kyc_phone', PHONE, 'a@x.invalid', '123456'));   // the email is the identity, case-folded
  assertNotEquals(a, macInput('kyc_whatsapp', PHONE, 'a@x.invalid', '123456'));
  assertNotEquals(a, macInput('kyc_phone', PHONE, 'b@x.invalid', '123456'));
  assertNotEquals(a, macInput('kyc_phone', '+971509999999', 'a@x.invalid', '123456'));
});

Deno.test('a clean send: the code goes by the login_code template, only its MAC is stored, and the message SID is recorded', async () => {
  const { d, rpcs, http } = deps();
  const r = await sendOwnWhatsAppCode(d, { phone: PHONE, purpose: 'login', binding: '', kind: 'customer', email: 'c@x.invalid', lang: 'ar' });
  assertEquals(r, { ok: true, sid: SM });
  assertEquals(http.length, 1);
  assert(http[0].url.endsWith('/Messages.json') && !http[0].url.includes('verify.twilio.com'));
  const form = new URLSearchParams(http[0].body);
  assertEquals([form.get('ContentSid'), form.get('To'), form.get('From')], [HX_AR, 'whatsapp:' + PHONE, 'whatsapp:+97140000000']);
  // every Twilio send reports its status (scripts/checks/every_twilio_send_reports_its_status.test.mjs): the code message
  // names the one URL wa_status verifies Twilio's signature against.
  assertEquals(form.get('StatusCallback'), statusCallbackUrl());
  assert(form.get('StatusCallback')!.endsWith('/functions/v1/wa_status?forceFunctionRegion=ap-southeast-1'), 'wa_status runs in the database region (R6, 10 Nov 2026)');
  const code = JSON.parse(form.get('ContentVariables')!)['1'];
  assert(/^\d{6}$/.test(code));
  const issue = rpcs.find((x) => x.fn === 'fn_phone_code_issue')!;
  assertEquals(issue.args.p_hash, 'mac(' + macInput('login', PHONE, '', code) + ')');
  assert(!JSON.stringify(rpcs).includes('"' + code + '"'), 'the bare code reached the database');
  assertEquals(rpcs.find((x) => x.fn === 'fn_phone_code_sent')!.args, { p_id: 41, p_message_sid: SM, p_accepted: true });
});

Deno.test('Twilio refuses the template: no code is claimed sent, and the stored one is spent at once', async () => {
  const { d, rpcs } = deps({ twilio: () => new Response(JSON.stringify({ code: 63016, message: 'outside window' }), { status: 400 }) });
  const r = await sendOwnWhatsAppCode(d, { phone: PHONE, purpose: 'login', binding: '', kind: 'customer', email: '', lang: 'en' });
  assertEquals(r, { ok: false, why: 'twilio_63016' });
  assertEquals(rpcs.find((x) => x.fn === 'fn_phone_code_sent')!.args.p_accepted, false);
});

Deno.test('a send that throws spends the stored code too', async () => {
  const { d, rpcs } = deps({ twilio: () => { throw new Error('timeout'); } });
  const r = await sendOwnWhatsAppCode(d, { phone: PHONE, purpose: 'login', binding: '', kind: 'customer', email: '', lang: 'en' });
  assertEquals(r.ok, false);
  assertEquals(rpcs.find((x) => x.fn === 'fn_phone_code_sent')!.args.p_accepted, false);
});

Deno.test('before the table is applied, or with no template SID, nothing is sent and the caller uses Verify', async () => {
  const a = deps({ issueError: true });
  assertEquals((await sendOwnWhatsAppCode(a.d, { phone: PHONE, purpose: 'login', binding: '', kind: 'customer', email: '', lang: 'en' })).ok, false);
  assertEquals(a.http.length, 0);
  const b = deps({ secrets: { ...SECRETS, wa_template_sids: '{}' } });
  assertEquals((await sendOwnWhatsAppCode(b.d, { phone: PHONE, purpose: 'login', binding: '', kind: 'customer', email: '', lang: 'en' })), { ok: false, why: 'not_configured' });
  assertEquals([b.http.length, b.rpcs.length], [0, 0]);
});

Deno.test('a fixture number is never texted', async () => {
  const { d, rpcs, http } = deps();
  assertEquals((await sendOwnWhatsAppCode(d, { phone: '+971500000042', purpose: 'login', binding: '', kind: 'customer', email: '', lang: 'en' })).ok, false);
  assertEquals([http.length, rpcs.length], [0, 0]);
});

Deno.test('the check sends the MAC of the guess for its purpose, number and account, and reads the verdict', async () => {
  const { d, rpcs } = deps({ verify: 'ok' });
  assertEquals(await checkOwnCode(d, { phone: PHONE, purpose: 'kyc_phone', binding: 'a@x.invalid', code: '123456' }), 'ok');
  assertEquals(rpcs[0].args, { p_phone: PHONE, p_purpose: 'kyc_phone', p_hash: 'mac(' + macInput('kyc_phone', PHONE, 'a@x.invalid', '123456') + ')', p_max_attempts: 5 });
  assertEquals(await checkOwnCode(deps({ verify: null }).d, { phone: PHONE, purpose: 'login', binding: '', code: '123456' }), 'unavailable');
  const n = deps({ verify: 'ok' });
  assertEquals(await checkOwnCode(n.d, { phone: PHONE, purpose: 'login', binding: '', code: '12345' }), 'wrong');
  assertEquals(n.rpcs.length, 0, 'a malformed guess is not even counted');
});

Deno.test('the SMS failover reads our message from the Messages API', async () => {
  const { d, http } = deps({ twilio: () => new Response(JSON.stringify({ sid: SM, status: 'undelivered' })) });
  assertEquals(await ownMessageStatus(d, SM), 'undelivered');
  assert(http[0].url.endsWith('/Messages/' + SM + '.json'));
  assertEquals(await ownMessageStatus(d, 'VE' + 'a'.repeat(32)), null);
});

Deno.test('our row marker reads as a WhatsApp code with its message SID, and a resend after it goes by SMS', () => {
  const m = ownMarker(SM);
  assertEquals([channelOfRow(m), sidOfRow(m), isOwnRow(m)], ['whatsapp', SM, true]);
  assertEquals([channelOfRow('twilio:sms:' + SM), sidOfRow('twilio:sms:' + SM), isOwnRow('twilio:sms:' + SM)], ['sms', SM, false]);
  assertEquals(isOwnRow('twilio:whatsapp:VE' + 'a'.repeat(32)), false);
  assertEquals(channelOfRow('qd:whatsapp:123456'), null);   // a 6-digit code is never a valid row
  assertEquals(nextChannel({ e164: PHONE, lastChannel: channelOfRow(m), waConfirmed: true }), 'sms');
  const s = ownSent(SM);
  assertEquals([s.ok, s.channel, s.refused, s.jd.sid], [true, 'whatsapp', null, SM]);
});
