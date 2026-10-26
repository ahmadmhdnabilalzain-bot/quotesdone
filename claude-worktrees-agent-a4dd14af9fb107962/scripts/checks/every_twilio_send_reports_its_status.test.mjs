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

// A POST to .../Messages.json: the fetch URL names Messages.json (no SID path, no query) and the
// options object that follows says POST.
function messagePosts(text) {
  const found = [];
  const re = /fetch\(([^;]{0,200}?)Messages\.json[`'"]\s*,\s*\{([^}]{0,160})/g;
  let m;
  while ((m = re.exec(text))) if (/method\s*:\s*['"]POST['"]/.test(m[2])) found.push(m.index);
  return found;
}

test('every POST to Twilio Messages.json carries a StatusCallback', () => {
  let total = 0;
  const bad = [];
  for (const f of tsFiles(FN)) {
    const t = readFileSync(f, 'utf8');
    const posts = messagePosts(t).length;
    if (!posts) continue;
    total += posts;
    const callbacks = (t.match(/StatusCallback['"]?\s*[:,]\s*statusCallbackUrl\(\)/g) || []).length;
    if (callbacks < posts) bad.push(`${f.slice(REPO.length)}: ${posts} Messages.json POST(s), ${callbacks} StatusCallback`);
  }
  assert.ok(total >= 4, `the scan found only ${total} Messages.json POSTs; send_whatsapp (2), send_sms and wa_inbound are expected`);
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
  const rp = src('supabase/functions/resilience_ping/index.ts');
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
