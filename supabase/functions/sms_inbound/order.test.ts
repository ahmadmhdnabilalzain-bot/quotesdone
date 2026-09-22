// THE ORDER OF sms_inbound IS ITS FLOOD BOUND, so the order is asserted and not just commented.
//
// The first version of this function rate-limited on 'sms_inbound:' + params.From BEFORE verifying
// the X-Twilio-Signature. params is attacker-controlled body content at that point, so rotating From
// per request minted a fresh 40/hour bucket every time: a flood bought one ai_rate_limit row, one
// sms_messages insert, one founder_alerts lookup and one agent_runs insert per request, unbounded.
// Independent review caught it before it shipped. This test is what would catch it next time — it
// reads the source, because the property is WHERE the calls are, not what they return.
//
//   deno test --allow-read supabase/functions/sms_inbound/order.test.ts
import { assert } from 'jsr:@std/assert@1';

const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
// Two ways this check could match itself into a false verdict, both hit on its first run:
//   1. the comments explain this very bug, so comment lines are dropped;
//   2. the helpers above the handler contain the same table calls the handler causes, and a helper's
//      position in the file is not the order things RUN in. So the ordering is judged over the
//      HANDLER BODY only — everything from Deno.serve( on — by the position of the CALL SITES.
const noComments = src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
const body = noComments.slice(noComments.indexOf('Deno.serve('));
assert(body.length > 500, 'the handler body was not found; this test is reading the wrong thing');

const at = (re: RegExp) => body.search(re);

Deno.test('the signature is verified before any rate limit and before any write', () => {
  const sig = at(/verifyInboundSignature\(/);
  assert(sig > 0, 'sms_inbound must verify the Twilio signature');
  for (const [what, re] of [
    ['the rate limiter', /withinLimit\(/],
    ['the message insert', /\brecord\(/],
    ['the founder alert', /alertThrottled\(/],
    ['the run log', /\blogRun\(/],
  ] as const) {
    const i = at(re);
    // -1 means absent, which also fails: a bound that is not there is not a bound.
    assert(i > sig, `${what} must not run before the signature check (found at ${i} — -1 is absent — signature at ${sig})`);
  }
});

Deno.test('an unverified request is capped on a CONSTANT bucket, never on its own From', () => {
  assert(/withinLimit\(\s*'sms_inbound:unsigned'/.test(body),
    "the unsigned path must key fn_rate_limit on the literal bucket 'sms_inbound:unsigned'");
  // A bucket built by string concatenation may only appear AFTER the refusal path has returned.
  const refusalEnds = body.lastIndexOf('return XML(403)');
  const keyed = at(/withinLimit\(\s*'sms_inbound:'\s*\+/);
  assert(keyed > refusalEnds && refusalEnds > 0,
    'a per-sender bucket may only be used once the signature has held');
});

Deno.test('the limiter fails closed for a forgery and open for a signed sender', () => {
  // withinLimit(bucket, limit, onError): the third argument is the answer when the limiter is down.
  assert(/withinLimit\(\s*'sms_inbound:unsigned'\s*,\s*UNSIGNED_PER_HOUR\s*,\s*false\s*\)/.test(body),
    'a forgery must be refused when the limiter is unreachable — nothing is lost by refusing it');
  assert(/withinLimit\(\s*'sms_inbound:'\s*\+\s*from\s*,\s*SMS_PER_HOUR\s*,\s*true\s*\)/.test(body),
    'a signed sender must be let through when the limiter is unreachable — a real message would be lost');
});

Deno.test('it records and never sends, and answers only empty TwiML', () => {
  // The note strings NAME send_sms as the sender on this channel, so the test looks for a send being
  // MADE: a queued notification, or a call to another function.
  assert(!/from\(\s*['"]notifications['"]\s*\)/.test(noComments), 'sms_inbound must not queue a notification');
  assert(!/functions\/v1\//.test(noComments), 'sms_inbound must not call another edge function');
  assert(!/requestDelivery|resend_send|sendWhatsApp/.test(noComments), 'sms_inbound must not send anything');
  assert(noComments.includes('<Response></Response>'), 'the answer to Twilio is an empty <Response/>');
});
