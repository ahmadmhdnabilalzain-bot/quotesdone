// EVERY TWILIO SEND REPORTS ITS STATUS — the recurrence check for 22 Sep 2026 (customer_support).
//
// Measured that day: no Messages.json POST in supabase/functions set StatusCallback and the WhatsApp
// sender had no status callback, so a WhatsApp Twilio accepted and Meta refused stayed 'sent' for ever.
// This FAILS if:
//   * any edge function POSTs to Twilio's Messages.json without a StatusCallback (a new send path, or
//     the parameter dropped from an existing one) — and the scan must find the known senders, because
//     a scan that finds nothing proves nothing;
//   * wa_status stops checking X-Twilio-Signature before it records, or loses verify_jwt=false (Twilio
//     cannot present a Supabase JWT, so every callback would be refused at the gateway);
//   * the backstop poll stops being called from resilience_ping's whatsappTick.
// Behaviour (ordering, idempotency, the failure handoff) is proved by
// scripts/sql/every_whatsapp_says_whether_it_arrived_probe.sql; signatures by
// supabase/functions/_shared/twilio_status.test.ts. Repository only; no token needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FN = join(REPO, 'supabase/functions');
const src = (p) => readFileSync(join(REPO, p), 'utf8');

function tsFiles(dir) {
  const out = [];
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) out.push(...tsFiles(p));
    else if (n.endsWith('.ts') && !n.endsWith('.test.ts')) out.push(p);
  }
  return out;
}

// A POST to .../Messages.json. It does NOT name the fetch function: on 22 Sep 2026 the it_engineer
// wrapped every outbound call in timedFetch() (CONN-04) and this regex, which began `fetch\(`, matched
// nothing in send_whatsapp any more — the scan found 3 where 4 were expected and only went red because
// of the `total >= 4` floor below. A guard that is blinded by a rename of the CALLER was asking the
// wrong question; what matters is that a POST goes to Messages.json, whoever makes it.
function messagePosts(text) {
  const found = [];
  const re = /Messages\.json[`'"]\s*,\s*\{([^}]{0,200})/g;
  let m;
  while ((m = re.exec(text))) if (/method\s*:\s*['"]POST['"]/.test(m[1])) found.push(m.index);
  return found;
}

// THE THING THAT MUST CARRY THE CALLBACK IS THE MESSAGE BODY, NOT THE fetch CALL (22 Sep 2026).
// Counting StatusCallbacks against fetch SITES stopped meaning anything the moment send_whatsapp put
// its two sends behind one shared twilioSend(): one POST site, two messages. Twilio's message body is
// a URLSearchParams carrying To and From, and that is what is counted now — send_sms (1),
// wa_inbound (1), send_whatsapp template + freeform (2) — so extracting or inlining a helper cannot
// change the number, and a FIFTH send path has to declare its own callback to pass.
function messageBodies(text) {
  const out = [];
  const re = /new URLSearchParams\(\{([^}]{0,400})\}/g;
  let m;
  while ((m = re.exec(text))) {
    if (!/\bTo\s*:/.test(m[1]) || !/\bFrom\s*:/.test(m[1])) continue;
    // Either the literal declares it, or the lines just after set it on the built form (wa_inbound
    // builds its body conditionally — MediaUrl, an interactive Content item — and sets it at the end).
    const after = text.slice(m.index, m.index + 1400);
    out.push({ at: m.index, body: m[1],
      callback: /StatusCallback['"]?\s*[:,]\s*statusCallbackUrl\(\)/.test(m[1])
             || /\.set\(\s*['"]StatusCallback['"]\s*,\s*statusCallbackUrl\(\)\s*\)/.test(after) });
  }
  return out;
}

test('every Twilio message body carries a StatusCallback', () => {
  let total = 0;
  const bad = [];
  const senders = [];
  for (const f of tsFiles(FN)) {
    const t = readFileSync(f, 'utf8');
    const posts = messagePosts(t).length;
    const bodies = messageBodies(t);
    // A file that POSTs to Messages.json but builds no recognisable Twilio body is a send path this
    // check cannot see, which is the same as no check at all for that path.
    if (posts && !bodies.length) bad.push(`${f.slice(REPO.length)}: ${posts} Messages.json POST(s) and no To/From body this check can read`);
    if (!bodies.length) continue;
    senders.push(f.slice(REPO.length));
    total += bodies.length;
    for (const b of bodies) if (!b.callback) bad.push(`${f.slice(REPO.length)}: a Twilio message body with no StatusCallback`);
  }
  assert.ok(total >= 4, `the scan found only ${total} Twilio message bodies in ${senders.join(', ') || '(nothing)'}; send_whatsapp (2), send_sms and wa_inbound are expected`);
  assert.deepEqual(bad, [], 'a Twilio send that never reports whether it arrived');
});

test('the callback URL is the one wa_status verifies against', () => {
  const t = src('supabase/functions/_shared/twilio_status.ts');
  assert.ok(t.includes("'/functions/v1/wa_status'"), 'statusCallbackUrl() no longer points at wa_status');
});

test('wa_status checks the signature before recording, fails closed, and is reachable by Twilio', () => {
  const t = src('supabase/functions/wa_status/index.ts');
  const check = t.indexOf('verifyTwilioSignature(token, statusCallbackUrl()');
  const refuse = t.indexOf('if (!check.valid)');
  const rec = t.indexOf("record(sid, status, params.ErrorCode");
  assert.ok(check > 0 && refuse > check && rec > refuse, 'wa_status records a callback without checking X-Twilio-Signature first');
  assert.ok(/\[functions\.wa_status\]\s*\nverify_jwt = false/.test(src('supabase/config.toml')),
    'wa_status needs verify_jwt = false: Twilio cannot present a Supabase JWT');
});

test('resilience_ping runs the status backstop on every tick', () => {
  const rp = functionSource('resilience_ping');
  const i = rp.indexOf('async function whatsappTick');
  const tick = rp.slice(i, rp.indexOf('\n}\n', i));
  assert.ok(tick.includes("FN + '/wa_status'") && tick.includes('poll: true'), 'whatsappTick no longer calls the wa_status backstop poll');
});

// 22 Sep 2026 (INT-01 / SEATS-03): the backstop asked Twilio for a field the claim does not return.
// fn_twilio_status_poll_claim answers (notification_id, sid); poll() read the notification column name
// instead, so every call fetched a URL ending in "undefined.json", got 404 and called the message
// unreadable - six times over notifications 35433, 35569 and 37899, every one of which answered HTTP 200
// status 'read' when asked by its real SID. deno check could not catch it (the rows come back untyped
// from rpc), so the field name is pinned here.
test('the backstop poll asks Twilio by the sid the claim returned', () => {
  const t = src('supabase/functions/wa_status/index.ts');
  assert.ok(/Messages\/\$\{r\.sid\}\.json/.test(t), 'wa_status no longer fetches Twilio by r.sid');
  assert.ok(!/r\.provider_message_id/.test(t), 'wa_status reads a field fn_twilio_status_poll_claim does not return');
  assert.ok(t.includes('fn_twilio_status_poll_failed'), 'a failed poll no longer records its HTTP status on the message');
});
