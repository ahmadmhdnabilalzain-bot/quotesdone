import { siteCors } from '../_shared/site_origins.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { annotate, observe } from '../_shared/observe.ts';
import { asLocale, registeredLocale } from '../_shared/registered_locale.ts';
import { codeEmail } from '../_shared/code_email.ts';
import { otpCeiling, prefixBlocked } from '../_shared/otp_guard.ts';
import { resendWithRetry } from '../_shared/resend_send.ts';
import { blocksTransactional } from '../_shared/suppression_policy.ts';
import { FIXTURE_CAPTURE_NOTE, FIXTURE_REFUSAL, isDemoEmail, isDemoPhone } from '../_shared/demo_identity.ts';
import { channelOfRow, failoverStep, isOwnRow, nextChannel, RESEND_GAP_S, sidOfRow, sendWhatsAppFirst, voiceAfterSms, type VerifySent } from '../_shared/whatsapp_choice.ts';
import { checkOwnCode, ownMarker, ownMessageStatus, ownSent, sendOwnWhatsAppCode, type WaCodeDeps } from '../_shared/wa_code.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail } from '../_shared/sanctioned.ts';
const SB_URL = Deno.env.get('SUPABASE_URL')!, SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// `admin` is the system's service-role client and must NEVER sign anybody in. See mintSession.
const admin = createClient(SB_URL, SB_SERVICE);
// Access-Control-Max-Age (15 Nov 2026, customer_support): the preflight `send` paid is remembered for two hours (Chromium's ceiling),
// so `verify`, typed a minute later, no longer waits on a second OPTIONS round trip to ap-southeast-1 before its POST leaves (the
// Fetch standard's default is 5 seconds; the code e-mail to the registration form measured 3,026 and 3,078 ms against 3,000).
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Max-Age': '7200' };
const reply = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
// 18 SEP 2026: Math.random() is not a credential generator. V8's PRNG is seeded per isolate and its
// state is recoverable from a handful of outputs, so a caller who can make this function issue codes
// to an address they control could predict the next one issued to somebody else. A sign-in code is a
// credential; it comes from the CSPRNG. The modulo is on a 32-bit draw over 900000, whose bias is
// ~2e-4 of one code — far below the 1e-6 guess probability the attempt caps already bound.
function code6() { const b = new Uint32Array(1); crypto.getRandomValues(b); return String(100000 + (b[0] % 900000)); }
// Sign-in codes are stored hashed. A 6-digit code is only safe if guesses are
// capped, so verify is limited per issued code AND per caller.
const EMAIL_VERIFY_MAX_ATTEMPTS = 5;
const EMAIL_VERIFY_PER_IP_HOUR = 30;
const EMAIL_VERIFY_PER_EMAIL_HOUR = 10;
// Sign-in codes are stored as HMAC-SHA256(code, server key), never a bare hash. A 6-digit code
// has only 10^6 possibilities, so an unsalted SHA-256 of the code is reversible from a single
// table leak by precomputing all a million hashes. The HMAC key (app_secrets.otp_hmac_key) makes
// a leaked token_hash useless without the key; we fail closed if the key is missing rather than
// silently fall back to a weak hash.
let _otpKey: string | null = null;
async function otpKey(): Promise<string> {
  if (_otpKey) return _otpKey;
  const k = await sec('otp_hmac_key');
  if (!k) throw new Error('otp_hmac_key_missing');
  _otpKey = k; return k;
}
async function otpHash(code: string): Promise<string> {
  const ck = await crypto.subtle.importKey('raw', new TextEncoder().encode(await otpKey()), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(code));
  return Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
// A WhatsApp sign-in code we send ourselves, without Verify's USD 0.05 a code (ledger 1252, _shared/wa_code.ts).
// The login code is bound to the number only: the account is resolved from the number after the code, as before.
const waDeps: WaCodeDeps = { admin, secret: sec, hmac: otpHash };
// The code compare itself lives in public.fn_login_otp_email_verify since 6 Oct 2026 (H1): it compares
// the keyed HMAC of the guess, whose bytes a caller cannot choose without otp_hmac_key, so the timing of
// the compare reveals nothing about the stored value. See the header of that SQL file.
async function twilioAuth() { const sid = await sec('twilio_api_key_sid'); const secret = await sec('twilio_api_key_secret'); const va = await sec('twilio_verify_service_sid'); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }
// ONE RETRY ON 429 (21 Sep 2026). Resend allows 10 requests a second per team, shared with send_outbox
// draining a campaign on the same key; a code refused for a busy second is retried once rather than lost.
// The call lives in _shared/resend_send.ts so login_otp and kyc cannot drift apart.
async function sendEmail(to: string, subject: string, html: string, text?: string) { const key = await sec('resend_api_key'); if (!key) return false; const from = (await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>'; const reply_to = (await sec('email_reply_info')) || 'info@quotesdone.com'; return await resendWithRetry(key, { from, to, subject, html, ...(text ? { text } : {}), reply_to }); }

// SUPPRESSION BYPASS 27 Jul 2026 ----------------------------------------------------------------
// send_outbox was the ONLY sender in the codebase that consulted email_suppressions. sendEmail()
// above builds its own Resend call, so a sign-in code went out to any address a caller typed in -
// including the 27 hard_bounce:permanent rows resend_webhook has recorded. Re-mailing a mailbox
// Resend has already told us rejects permanently is exactly what burns the sender reputation the
// suppression list exists to protect, and the code could never arrive anyway: the user sat waiting
// for an email that bounced while we returned ok:true. Transactional or not, we do not send, and we
// say so instead of silently succeeding. Fails OPEN on a lookup error - a suppression-table outage
// must not lock every user out of sign-in.
async function isSuppressed(email: string): Promise<boolean> {
  // 22 Sep 2026: an 'unsubscribe' row is a marketing opt-out and never refuses a code (_shared/suppression_policy.ts).
  try { const { data } = await admin.from('email_suppressions').select('reason').eq('email', email).maybeSingle(); return !!data && blocksTransactional(data.reason); }
  catch (_e) { return false; }
}

// ABUSE CONTROL 19 Jul 2026 --------------------------------------------------------------------
// The SMS branch was rate limited per PHONE NUMBER only (6/hour). With allow_signup:true the
// "does this number have an account?" check is skipped, so an attacker could walk a list of UAE
// mobile numbers and have QuotesDone send a real, billable Twilio SMS to each one - 6 per number
// per hour with no ceiling on how many DIFFERENT numbers. That is both unbounded spend on our
// Twilio account and SMS harassment of third parties sent in our name.
// Per-number capping alone cannot stop that, because each new victim is a fresh bucket. These add
// a per-CALLER cap and an absolute hourly ceiling on the signup path so the blast radius is bounded
// even if someone scripts it. A legitimate person signing up never comes close to either.
const SMS_PER_IP_HOUR = 10;
const SMS_SIGNUP_GLOBAL_HOUR = 60;
// THE LIMITER FAILS CLOSED (pre-launch security pass, 6 Oct 2026, M1). It used to answer "allowed"
// when rl_check errored or threw, so a database fault removed the cap on code guesses AND on billable
// SMS sends at the same moment. On a sign-in endpoint a limiter that cannot answer is a refusal: the
// person is told to retry in a minute, and the IT engineer gets one finding per key family per hour
// so the outage is seen without paging on every request.
type Gate = 'ok' | 'limited' | 'down';
async function rl(key: string, limit: number, seconds: number): Promise<Gate> {
  let why = '';
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); if (!error) return data === false ? 'limited' : 'ok'; why = error.message; }
  catch (e) { why = String((e as Error)?.message || e); }
  const family = key.split(':')[0];
  try {
    await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: 'login_otp_limiter_unavailable:' + family,
      p_title: 'The sign-in rate limiter could not answer, so sign-in requests were refused',
      p_where: 'supabase/functions/login_otp rl() -> public.rl_check',
      p_blast: 'Every sign-in code send or check that needs this limiter is refused with 503 until rl_check answers again.',
      p_affected: 1, p_evidence: { key_family: family, error: why.slice(0, 300) } });
  } catch (_e) { /* the refusal below stands even if the finding cannot be written */ }
  return 'down';
}
// A refusal because the limiter is down says "retry", not "you tried too often".
const LIMITER_DOWN = { error: 'Sign-in is briefly unavailable. Please try again in a minute.', code: 'limiter_unavailable' };
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'login_otp', status, counts, note: String(note || '').slice(0, 500), finished_at: new Date().toISOString() }); } catch (_e) { /* */ }
}

// Which other role already owns this address (leads.claimed_by = supplier, customers.email = customer).
// Only asked AFTER the code is verified, so the answer goes to the mailbox owner and nobody else.
async function roleConflict(kind: string, email: string): Promise<'supplier' | 'customer' | null> {
  if (kind === 'admin') return null;
  const [{ data: s }, { data: c }] = await Promise.all([
    admin.from('leads').select('id').eq('claimed_by', email).limit(1),
    admin.from('customers').select('id').eq('email', email).limit(1)]);
  const isSup = !!(s && s.length), isCust = !!(c && c.length);
  if (kind === 'customer' && isSup && !isCust) return 'supplier';
  if (kind === 'supplier' && isCust && !isSup) return 'customer';
  return null;
}
async function uidByEmail(email: string): Promise<string | null> { try { const { data } = await admin.rpc('auth_uid_by_email', { p_email: email }); return (data as string) || null; } catch { return null; } }
// A USER IS CREATED OR CONFIRMED ONLY ON A PROVEN EMAIL (13 Oct 2026, security review). createUser sets
// email_confirm: true, so the caller must say the address is proven; both callers reach here only after an
// email code (verify) or a phone code on a row whose phone AND email are verified.
async function ensureUser(email: string, emailProven: boolean, known?: Promise<string | null>) { if (!emailProven) return null; let uid = await (known ?? uidByEmail(email)); if (!uid) { const cr = await admin.auth.admin.createUser({ email, email_confirm: true, password: crypto.randomUUID() }); uid = cr.data?.user?.id || null; } return uid; }
// THE TWO READS A SESSION NEEDS GO OUT TOGETHER (11 Nov 2026, it_engineer; supplier registration certification).
// Measured on production at 11:38:31Z (edge_logs for the one request, a new supplier on a freshly booted isolate): the verify
// waited on twelve calls one after another - rl_check x2, the HMAC key, fn_login_otp_email_verify, the role pair, the leads
// update, the sanctions pair, auth_uid_by_email, createUser, generate_link, verify, fn_registered_locale - and in that slow
// database minute each hop cost 130-470 ms (origin_time; 12-30 ms on a normal minute), so the handler took 2,272 ms (2,798 ms
// at the browser) where the in-region median is ~510 ms. A returning account on a warm isolate waited on ten. Whether the address is sanctioned and
// which auth user it has are reads about an address whose code has ALREADY been proved; the caller starts them beside its
// own reads, and mintSession still refuses on `sanctioned` before it creates, links or verifies anything. A read that
// throws still fails closed: the rejection is held here and surfaces where mintSession awaits it.
// Prevented by: supabase/functions/login_otp/verify_speed.test.ts
type AccountFacts = { sanctioned: Promise<boolean>; uid: Promise<string | null> };
function accountFacts(email: string): AccountFacts {
  const sanctioned = sanctionedEmail(admin, email);
  sanctioned.catch(() => {});   // handled where mintSession awaits it; this only stops an early return leaving it unobserved
  return { sanctioned, uid: uidByEmail(email) };
}
// SIGN-IN NEVER BORROWS THE SYSTEM'S DATABASE CLIENT (15 Sep 2026). verifyOtp stores the session
// it gets back on the client it ran on, and supabase-js then sends that session's token on every
// later database call from that client. This ran on `admin`, so from the first verify onwards the
// service-role client spoke as the user who had just signed in: fn_registered_locale, the agent_runs
// insert and fn_it_engineer_finding_upsert answered 403 72 times each between 17:15Z and 23:49Z on
// 14 Sep (the `authenticated` role has no grant on any table or routine this function touches), so
// the registered language was never read and the failure reports were lost. `admin` is
// module-level, so in a warm isolate the next person's request inherited it too. The verify now runs
// on a client made for this one call and dropped with it. generateLink stays on admin.auth.admin,
// whose calls are always sent with the service key.
// A SANCTIONED PARTY NEVER GETS A SESSION (founder instruction 516, 18 Sep 2026). The check lives
// HERE rather than at the two call sites because this is the only function in the estate that mints
// a supplier or customer session, and a third caller written next year inherits the refusal for
// free. It is asked of public.sanctions_ban, not of leads.banned: a supplier banned for unpaid dues
// must still be able to sign in and pay them.
async function mintSession(email: string, emailProven: boolean, facts: AccountFacts = accountFacts(email)): Promise<{ access_token: string; refresh_token: string } | 'sanctioned' | null> {
  try {
    if (await facts.sanctioned) return 'sanctioned';
    if (!emailProven) return null;
    await ensureUser(email, emailProven, facts.uid);
    const { data } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
    const th = (data as any)?.properties?.hashed_token; if (!th) return null;
    const once = createClient(SB_URL, SB_SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: v, error } = await once.auth.verifyOtp({ type: 'email', token_hash: th } as any);
    if (error || !v?.session) return null;
    return { access_token: v.session.access_token, refresh_token: v.session.refresh_token };
  } catch { return null; }
}
// THE FOUNDER IS NEITHER A SUPPLIER NOR A CUSTOMER, which is why mobile sign-in could not reach
// him. This resolver knew two kinds — 'supplier' (leads.claimed_by) and 'customer'
// (customers.email) — and his number lives in app_secrets.admin_mfa_phone while `customers` holds
// no row for him at all. Every Twilio credential was provisioned and authenticating (Verify
// service "QuotesDone", HTTP 200), and the OS sign-in still emailed a code, because the phone
// could not be turned into an account. Checked FIRST and on the last nine digits like the other
// two branches, so +971 50 931 9355 and 0509319355 both land.
async function resolveAdminEmailByPhone(e164: string): Promise<string | null> {
  const admins = (await sec('admin_mfa_phone') || '').split(',').map((s) => s.replace(/\D/g, '')).filter((s) => s.length >= 9);
  const last9 = e164.replace(/\D/g, '').slice(-9);
  if (!admins.some((a) => a.slice(-9) === last9)) return null;
  const first = (await sec('admin_emails') || '').split(',')[0]?.trim().toLowerCase();
  return first || null;
}
// A PHONE NUMBER IS NOT AN IDENTITY (13 Aug 2026). The founder registered as a customer with
// djzaino@outlook.com, signed in on his mobile, and /me showed him management@quotesdone.com —
// somebody else's account. Three production records agree on why: app_secrets.admin_mfa_phone is
// his mobile (+971509319355), admin_emails[0] is management@quotesdone.com, and the line below
// consulted resolveAdminEmailByPhone FIRST and UNCONDITIONALLY — before it ever looked at `kind`.
// So a customer signing in by SMS from an admin's number was handed the admin's account every
// time. The 19:44:14 phone_verifications row records that resolver returning
// management@quotesdone.com, and auth.users.last_sign_in_at for that address is 19:44:27.
//
// The admin branch was added on 10 Aug to give the OS a mobile sign-in (b0bc419). That was right;
// putting it in the SHARED resolver was not. It now runs only for kind='admin', which /os sends.
//
// AND THE OTHER TWO BRANCHES COULD NOT BE TRUSTED EITHER: both were ilike + limit(1) with no
// ORDER BY, so with two rows on one number Postgres returned whichever it liked. Two customers
// share +971509319355 on production today. In the UAE a number is shared by families, colleagues
// and one office landline for a whole company, so `customers.phone` is deliberately NOT unique —
// see the comment on the column. The consequence of allowing it to repeat is that a phone may
// only ever CONFIRM an identity, never SELECT one: if a number maps to more than one account we
// refuse and ask for the email rather than guess which person is holding the handset.
// A PHONE MATCHES ONLY A ROW WHOSE PHONE AND EMAIL ARE BOTH VERIFIED (13 Oct 2026, security review).
// kyc save_customer stores an unverified number and a supplier claim keeps the scraped leads.phone, so
// anyone could put a victim's number on their own account and capture or lock out the victim's phone
// sign-in. otherRoleByPhone applies the same rule.
type PhoneOwner = { email: string } | { ambiguous: true } | null;
async function resolveEmailByPhone(kind: string, e164: string): Promise<PhoneOwner> {
  if (kind === 'admin') { const e = await resolveAdminEmailByPhone(e164); return e ? { email: e } : null; }
  const last9 = e164.replace(/\D/g, '').slice(-9);
  const col = kind === 'supplier' ? 'claimed_by' : 'email';
  const q = kind === 'supplier'
    ? admin.from('leads').select('claimed_by').not('claimed_by', 'is', null).eq('owner_phone_verified', true).eq('owner_email_verified', true).ilike('phone', '%' + last9).limit(5)
    : admin.from('customers').select('email').not('email', 'is', null).eq('phone_verified', true).eq('email_verified', true).ilike('phone', '%' + last9).limit(5);
  const { data } = await q;
  const owners = [...new Set((data || []).map((r: any) => String(r[col] || '').trim().toLowerCase()).filter(Boolean))];
  if (owners.length > 1) return { ambiguous: true };
  return owners.length ? { email: owners[0] } : null;
}
// THE CROSS-ROLE CHECK ON THE PHONE PATH (6 Oct 2026, review of #1245). role_guard used to refuse a
// customer sign-in on a supplier's number (and the reverse) before any code was sent. That answer now
// comes only after the code proves the handset: send texts the number when the OTHER role holds it, and
// verify answers role_conflict instead of a session. Asked of the account tables only, like the resolver.
async function otherRoleByPhone(kind: string, e164: string): Promise<'supplier' | 'customer' | null> {
  if (kind !== 'customer' && kind !== 'supplier') return null;
  const last9 = e164.replace(/\D/g, '').slice(-9);
  if (last9.length < 9) return null;
  const { data } = kind === 'customer'
    ? await admin.from('leads').select('claimed_by').not('claimed_by', 'is', null).eq('owner_phone_verified', true).eq('owner_email_verified', true).ilike('phone', '%' + last9).limit(1)
    : await admin.from('customers').select('email').not('email', 'is', null).eq('phone_verified', true).eq('email_verified', true).ilike('phone', '%' + last9).limit(1);
  return data && data.length ? (kind === 'customer' ? 'supplier' : 'customer') : null;
}
const ROLE_CONFLICT_MSG = { supplier: 'This mobile number is registered to a supplier account. Please use the Supplier portal to sign in.', customer: 'This mobile number is registered to a customer account. Please use the customer app to sign in.' };
const AMBIGUOUS_MSG = 'More than one QuotesDone account uses this mobile number, so we cannot tell which one is yours. Please sign in with your email address instead.';

// THE SIGN-IN CODE MAY GO BY WHATSAPP (founder, 18 Sep 2026), AND ONLY TO A NUMBER THE ACCOUNT
// ITSELF CONFIRMED IS ON WHATSAPP.
//
// kyc's whatsapp_* actions (14 Sep) already prove a WhatsApp number by sending a code over WhatsApp
// to it, and write whatsapp_phone only together with whatsapp_verified_at. This reads that proof and
// nothing else: an unconfirmed mobile keeps going by SMS. Asking Verify for Channel=whatsapp on a
// number that is not on WhatsApp does not fall back — it fails — so the gate is what stops a
// sign-in from breaking, not a nicety.
//
// An SMS or voice code is never generated, stored, logged or seen here: Twilio Verify holds it. A WhatsApp
// code is generated here since 27 Oct 2026 (ledger 1252, _shared/wa_code.ts) and only its HMAC is stored
// (public.phone_code), never the code; it leaves this function only inside the Messages API call.
// 'admin' is deliberately absent: the founder is neither a customers row nor a claimed lead, and
// app_secrets.admin_mfa_phone carries no WhatsApp confirmation, so his sign-in stays on SMS.
async function confirmedWhatsApp(kind: string, email: string, e164: string): Promise<boolean> {
  if (kind !== 'customer' && kind !== 'supplier') return false;
  const last9 = e164.replace(/\D/g, '').slice(-9);
  if (last9.length < 9) return false;
  try {
    const q = kind === 'supplier'
      ? admin.from('leads').select('whatsapp_phone,whatsapp_verified_at').eq('claimed_by', email).limit(5)
      : admin.from('customers').select('whatsapp_phone,whatsapp_verified_at').eq('email', email).limit(5);
    const { data } = await q;
    return (data || []).some((r: { whatsapp_phone?: string | null; whatsapp_verified_at?: string | null }) =>
      !!r.whatsapp_verified_at && String(r.whatsapp_phone || '').replace(/\D/g, '').slice(-9) === last9);
  } catch (_e) { return false; }   // a read failure means SMS, never a lost sign-in
}

// KEEP-WARM (11 Nov 2026, it_engineer). The slowest verify the certification measured (11:38:31Z) landed on an isolate that
// booted for it: function_logs "booted" at the request, and every first call from the new isolate paid a fresh connection.
// login_otp is the door to both portals and was in neither warm list. It now answers x-qd-warm like the nine portal
// functions: 204, before observe() (so no run row dilutes the refusal rate), before the body, auth or any database read.
// resilience_ping's warmPortal pings it with them, and a deploy warms it (scripts/lib/warm_functions.mjs warmable()).
Deno.serve(siteCors(async (req) => {
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  return await signIn(req);   // defined just below; a request only arrives once this module has finished loading
}));

const ACTIONS = new Set(['send', 'verify', 'failover']);
const signIn = observe('login_otp', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // OUR OWN TRAFFIC IS MARKED BY THE SERVER, NOT BY THE CALLER (22 Sep 2026). Every harness and probe
  // signs in on the reserved fixture block (+971 50 000 00xx, isDemoPhone), which no real person can
  // hold. This function sees the number, so it tags the run row `fixture: 1` and fn_it_detect's
  // refusal_rate leaves it out.
  // WHAT WAS ACTUALLY MEASURED, AS AT 22 SEP 2026 20:00Z — the Dubai day was still running, so the totals
  // below are a reading of that moment and will have grown; the invariants after them are what matter.
  // Re-derived over the Dubai day of 22 Sep (21 Sep 20:00Z - 22 Sep 20:00Z, agent 'fn:login_otp'):
  // 566 runs, 415 status 'warn'. 249 of those warns carry `fixture`; 166 do
  // NOT — and every one of the 166 is before 06:31:54Z, while the FIRST fixture-marked row is 06:50:31Z,
  // which is when this marking reached production. Classified: 159 sit in a burst of five or more calls
  // within 60 s (the 1x200 + 4x404 + 1x409 signature of
  // scripts/checks/a_phone_cannot_select_an_account.test.mjs, across ap-south-1, eu-central-1 and
  // ap-southeast-1) and 7 are lone 404s within two minutes of a resilience_ping tick (its launch-path
  // probe asks for a code for +971 50 000 0099). 0 unexplained. That is a burst heuristic, not an
  // identity: it says no refusal in the day has a shape a single person could produce, and the marking
  // below is what answers the question properly from here on.
  // EVERY ROW NAMES ITS CALLER CLASS (22 Sep 2026, UNSOLVED-04). Before, only the telemetry row of a fixture
  // call said so; the semantic row this function writes itself (logRun) carried nothing, so a refusal on
  // the email path or a semantic row without a twin could not be told from a person. `caller` is 'fixture'
  // (the reserved block / a reserved test address, decided here from the identifier) or 'person' (anything
  // else, counted as a person). `fixture: 1` stays alongside because fn_it_detect D9 keys on it.
  let fixture = false;
  // WHERE A SIGN-IN'S TIME GOES, ON ITS OWN RUN ROW (11 Nov 2026, it_engineer). The certification saw verify at 2,798 ms and
  // nothing on production said which call spent it: agent_runs held only the total, and edge_logs keep one day. Each stage
  // records the ms since the stage before it into counts.steps (limit, check, reads, session) with counts.action, so the
  // p50/p95 of every stage is a query on agent_runs. Durations only; never an address, a code or a token.
  let action = '';   // logged only when it is one of ACTIONS: the body is the caller's
  let tStep = Date.now();
  const steps: Record<string, number> = {};
  const step = (name: string) => { const now = Date.now(); steps[name] = now - tStep; tStep = now; };
  const cls = () => ({ ...(fixture ? { caller: 'fixture', fixture: 1 } : { caller: 'person' }), ...(ACTIONS.has(action) ? { action } : {}), ...(Object.keys(steps).length ? { steps: { ...steps } } : {}) });
  const J = (o: unknown, s = 200) => annotate(reply(o, s), cls());
  // The parameter is `counts`, never `c`: `c` is the issued OTP a few lines below, and
  // a_sign_in_code_goes_on_one_channel_and_is_never_logged.test.mjs reads a bare `c` inside a log call as
  // the code being written to a run row. It was a shadowed name, not a leak — and the check is right to
  // refuse a spelling that cannot be told apart from one.
  const log = (st: string, counts: Record<string, unknown>, n: string) => logRun(st, { ...counts, ...cls() }, n);
  try {
    const body = await req.json().catch(() => ({})); action = String(body.action || '');
    // Three kinds, not two. 'admin' is /os and is the ONLY kind that resolves a phone through
    // app_secrets.admin_mfa_phone; an unknown value still falls to 'customer', the least privileged.
    const kind = body.user_kind === 'supplier' ? 'supplier' : (body.user_kind === 'admin' ? 'admin' : 'customer');
    const idRaw = String(body.identifier || '').trim();
    const allowSignup = body.allow_signup === true;
    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
    // A reserved test address is the harness too (22 Sep 2026): its sign-ins that SUCCEED were still
    // counted as customers while its refused phone calls were not, which tilts the share toward health.
    fixture = isDemoPhone(toE164(idRaw)) || isDemoEmail(idRaw);

    if (action === 'send') {
      if (emailOk(idRaw)) {
        const email = idRaw.toLowerCase();
        // Checked BEFORE the row is inserted so we never mint a code that cannot be delivered.
        if (await isSuppressed(email)) {
          await log('error', { suppressed: 1, channel: 'email' }, 'login_otp refused to email a sign-in code to ' + email + ' - it is in email_suppressions (hard bounce, spam complaint or a guardrail block - an unsubscribe never refuses a code). No code was issued and no Resend call was made. If this is a real user, confirm the mailbox works and delete their email_suppressions row; do not remove this check.');
          return J({ error: 'We cannot email this address - it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.', code: 'email_suppressed', suppressed: true }, 403);
        }
        const since = new Date(Date.now() - 3600e3).toISOString();
        const { count } = await admin.from('email_verifications').select('id', { count: 'exact', head: true }).eq('email', email).gte('created_at', since);
        if ((count || 0) >= 8) return J({ error: 'Too many code requests. Please try again later.', code: 'rate_limited' }, 429);
        const c = code6();
        // A RESEND RETIRES EVERY EARLIER CODE, in the same transaction as the new one is written
        // (public.fn_login_otp_email_issue, review of #1245), so only the newest code can ever verify.
        const { error: issueErr } = await admin.rpc('fn_login_otp_email_issue', { p_email: email, p_hash: await otpHash(c), p_kind: kind, p_ttl_seconds: 600 });
        if (issueErr) { console.error('login_otp: issue routine failed —', issueErr.message); return J({ error: 'Could not send the email code. Please try again in a minute.', code: 'email_not_sent' }, 502); }
        const codeAr = (await registeredLocale(admin, { role: kind, email }, body.lang)) === 'ar';
        const mail = codeEmail('signin', c, codeAr);
        // A code that did not leave is not "sent" (21 Sep 2026). The result was discarded, so a Resend
        // refusal answered ok:true and the person waited on a code screen for an email that never came.
        if (!(await sendEmail(email, mail.subject, mail.html, mail.text))) {
          await log('error', { channel: 'email', not_sent: 1 }, 'login_otp could not hand a sign-in code to Resend (refused after one retry, or the key is missing). The caller was told to try again.');
          return J({ error: 'Could not send the email code. Please try again in a minute.', code: 'email_not_sent' }, 502);
        }
        return J({ ok: true, channel: 'email', identifier: email });
      }
      const e164 = toE164(idRaw);
      if (!e164) return J({ error: 'Enter a valid email address or UAE mobile number.', code: 'bad_identifier' }, 400);
      // WHO owns this number is decided BEFORE whether we can text it. Resolution is one indexed
      // query and needs no Twilio; running the credential check first meant a project without SMS
      // configured answered 503 to everything, so neither the ambiguity refusal nor the
      // no-account refusal could be exercised on staging at all - the guard was untestable on
      // half the estate. Identity first also fails fast before touching an external service.
      const owner = await resolveEmailByPhone(kind, e164);
      // Refuse an ambiguous number BEFORE the Twilio call: a code we could not attribute to one
      // account is a code we must not act on, so sending it would only cost money and mislead.
      if (owner && 'ambiguous' in owner) {
        // 'skipped', not 'error'. fn_os_health_brief counts agent_runs where status in
        // ('error','failed') and puts the total on the founder's health panel as
        // agent_runs_failed_24h. A guard doing exactly what it was built to do is not a failure,
        // and logging it as one taught the panel to report ~12 failures a day that were the
        // system working. 'skipped' already exists in this column alongside info and warn, and
        // the metric excludes it, so the refusal is still on the record and no longer counted as
        // a fault. The note is unchanged - the reasoning is the point of writing it down.
        await log('skipped', { ambiguous_phone: 1, kind }, 'login_otp refused an SMS sign-in because more than one ' + kind + ' account carries this mobile number. No SMS was sent and no Twilio charge was incurred. This is the guard working, not a fault: a shared number cannot select a person. The caller was asked to sign in with their email instead.');
        return annotate(J({ error: AMBIGUOUS_MSG, code: 'ambiguous_phone', ambiguous: true }, 409), { ambiguous_phone: 1 });
      }
      const acctEmail = owner ? owner.email : null;
      // AN UNKNOWN NUMBER IS REFUSED WHETHER OR NOT THE CALLER SAID "SIGN ME UP" (13 Aug 2026).
      //
      // allow_signup used to let this through to Twilio, and the flow could not complete: `send`
      // writes the phone_verifications row with email:'' for an unknown number, and `verify` then
      // has no account to resolve, so it answers "No account is registered with this number.
      // Please sign in with your email, or sign up first." - to somebody who had just tapped sign
      // up, AFTER we had paid to text them. Measured end to end: send returned 200 known:false and
      // left a row with an empty email.
      //
      // It is not a bug to fix by making verify create the account. Email is the identity here
      // (customers_email_lower_uidx), so an account created from a handset alone would have no
      // identity at all - no address to send a quote to, nothing for the ~20 server-side lookups
      // that key on email, and nothing a second device could ever sign in with. A phone confirms
      // an identity; it cannot mint one. So the sign-up path is email, and the refusal now happens
      // before the spend and says what to do instead.
      const otherRole = acctEmail ? null : await otherRoleByPhone(kind, e164);
      if (!acctEmail && !otherRole) {
        if (allowSignup) {
          // 'skipped' for the same reason as the ambiguity refusal above: expected, routine, and
          // not a fault. This one fires every time somebody tries to sign up with a phone number.
          await log('skipped', { sms_signup_refused: 1, kind }, 'login_otp refused to send a sign-up SMS to a number with no account. No SMS was sent and no Twilio charge was incurred. This is deliberate: email is the identity, so a phone alone cannot create an account, and letting this through only produced a paid-for code that verify would refuse. Sign-up is by email.');
          return annotate(J({ error: 'We cannot create an account from a mobile number - your email address is what identifies your account. Please sign up with your email, and you can add your mobile straight afterwards.', code: 'sms_signup_refused', no_account: true, signup_by_email: true }, 404), { sms_signup_refused: 1 });
        }
        // Do not send (and pay for) an SMS to a number that has no account. Tell the user first.
        return J({ error: "This mobile number isn't linked to a QuotesDone account yet. Please sign in with the email you registered with, or create your account first.", code: 'no_account_for_number', no_account: true }, 404);
      }
      // After the identity refusals (so a fixture number still answers 404/409 exactly as a real one
      // does) and before anything reaches Twilio: a fixture number is never texted.
      if (isDemoPhone(e164)) { await log('skipped', { kind, captured: 1, fixture: 1 }, FIXTURE_CAPTURE_NOTE); return J(FIXTURE_REFUSAL); }
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS sign-in is not enabled yet. Please sign in with your email.', code: 'sms_signin_unavailable' }, 503);

      // A prefix the IT engineer blocked for pumping gets no code (public.otp_blocked_prefix, duty 11).
      const pb = await prefixBlocked(admin, e164);
      if (pb.blocked) {
        await log('skipped', { prefix_blocked: 1 }, 'login_otp sent no SMS: the number is under a prefix the IT engineer blocked for OTP pumping. No Twilio charge was incurred.');
        return J({ error: 'SMS codes are not available for this number. Please sign in with your email.', code: 'sms_not_available_for_number' }, 403);
      }
      // Caller-level and global ceilings. Checked BEFORE the Twilio call so a blocked attempt costs nothing.
      // Read from public.it_threshold so the IT engineer's playbook can tighten them; the constants are
      // the fallback when that read fails, never a reason to refuse sign-in.
      const perIp = await otpCeiling(admin, 'otp_sms_per_ip_hour', SMS_PER_IP_HOUR);
      const perHour = await otpCeiling(admin, 'otp_signup_global_hour', SMS_SIGNUP_GLOBAL_HOUR);
      const ipGate = await rl('login_otp_sms_ip:' + ip, perIp, 3600);
      const globalGate: Gate = (!acctEmail && allowSignup) ? await rl('login_otp_sms_signup_global', perHour, 3600) : 'ok';
      if (ipGate === 'down' || globalGate === 'down') return J(LIMITER_DOWN, 503);
      const ipOk = ipGate === 'ok', globalOk = globalGate === 'ok';
      if (!ipOk || !globalOk) {
        await log('error', { rate_limited: 1, scope: !ipOk ? 'ip' : 'signup_global', signup_path: !acctEmail && allowSignup ? 1 : 0, guard_error: pb.error ?? null },
          !ipOk
            ? ('login_otp blocked a caller that asked for more than ' + perIp + ' SMS codes in an hour from one address. No SMS was sent and no Twilio charge was incurred. A real person signing in never reaches this - sustained hits mean someone is walking a list of numbers.')
            : ('login_otp hit the global hourly ceiling of ' + perHour + ' sign-up SMS messages. Further sign-up codes are refused this hour to cap Twilio spend. If genuine sign-ups are being turned away, raise it_threshold otp_signup_global_hour - do not remove the ceiling.'));
        return J({ error: 'Too many code requests. Please try again later.', code: 'rate_limited' }, 429);
      }

      const since = new Date(Date.now() - 3600e3).toISOString();
      const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', e164).gte('created_at', since);
      if ((count || 0) >= 6) return J({ error: 'Too many code requests. Please try again later.', code: 'rate_limited' }, 429);
      // WHATSAPP ONLY TO A CONFIRMED NUMBER (review of #1432), SMS when a WhatsApp code is asked for again
      // (_shared/whatsapp_choice.ts nextChannel). Resends are spaced by the locked rl_check before Twilio is asked.
      // No 'asked' channel here: an anonymous caller cannot steer a paid channel.
      const gap = await rl('otp_gap:' + e164, 1, RESEND_GAP_S);
      if (gap === 'down') return J(LIMITER_DOWN, 503);
      if (gap === 'limited') return J({ error: 'A code is on its way. Please wait a few seconds before asking for another.', code: 'resend_too_soon', retry_after: RESEND_GAP_S }, 429);
      const { data: lastRow } = await admin.from('phone_verifications').select('code').eq('phone', e164)
        .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString()).order('created_at', { ascending: false }).limit(1).maybeSingle();
      const pick = nextChannel({ e164, lastChannel: channelOfRow(lastRow?.code), waConfirmed: acctEmail ? await confirmedWhatsApp(kind, acctEmail, e164) : false });
      try {
        // Locale: Twilio Verify writes the SMS in the account holder's registered language.
        const smsLocale = await registeredLocale(admin, { role: kind, email: acctEmail || '' }, body.lang);
        const send = async (channel: 'whatsapp' | 'sms' | 'call') => {
          const r = await timedFetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: e164, Channel: channel, Locale: smsLocale }) });
          return { r, jd: await r.json() };
        };
        // ONE CODE, ONE CHANNEL. sendWhatsAppFirst tries SMS only when Verify refuses the WhatsApp
        // channel itself (a missing sender or an unapproved Authentication template — the three codes
        // in _shared/whatsapp_choice.ts), which means no code was delivered on the first attempt. Any
        // other Verify refusal is a send failure and is reported as one, never retried on the second
        // channel. Which channel goes first is pick (nextChannel above).
        const smsOnly = async (): Promise<VerifySent> => {
          const x = await send('sms');
          return x.r.ok && x.jd?.status !== 'canceled'
            ? { ...x, refused: null, ok: true, channel: 'sms' } : { ...x, refused: null, ok: false, channel: null };
        };
        // A WHATSAPP CODE GOES WITHOUT THE VERIFY FEE (ledger 1252): generated and checked here, sent by the approved
        // login_code template, USD 0.0157 instead of 0.0657. Anything short of a clean send falls through to Verify.
        const own = pick === 'whatsapp' ? await sendOwnWhatsAppCode(waDeps, { phone: e164, purpose: 'login', binding: '', kind, email: acctEmail || '', lang: smsLocale }) : null;
        const res = own?.ok ? ownSent(own.sid) : await voiceAfterSms(pick === 'whatsapp' ? await sendWhatsAppFirst(send) : await smsOnly(), send);
        // A WHATSAPP REFUSAL IS ONE FINDING, NOT A LOG LINE PER CODE (customer_support, 6 Oct 2026). Verify
        // refused its WhatsApp channel (sender or Authentication template), so this code went by SMS or voice.
        // The upsert is keyed by the refusal code, so a thousand sign-ins raise one open finding.
        if (res.refused) {
          await admin.rpc('fn_it_engineer_finding_upsert', {
            p_issue_key: 'login_otp:whatsapp_refused:' + res.refused,
            p_title: 'Sign-in codes cannot go by WhatsApp: Twilio Verify refused the channel (' + res.refused + ')',
            p_where: 'login_otp -> Twilio Verify', p_blast: 'customer_facing', p_affected: 1,
            p_evidence: { refused_code: res.refused, delivered_by: res.channel, effect: 'the code fell back to the next channel; no sign-in was lost' },
            p_ruled_out: [], p_undetermined: ['whether the Verify WhatsApp sender or its Authentication template is the missing piece'],
            p_raised_by: 'customer_support' }).then(() => {}, () => {});
        }
        if (!res.ok) return J({ error: 'Could not send the sign-in code. Please try again in a minute.', code: 'sms_send_failed' }, 502);
        // The delivered channel is recorded in phone_verifications.code (the column only ever held the
        // marker 'twilio'; no reader compares it), the same convention kyc's whatsapp_send_code uses,
        // so the day WhatsApp starts carrying sign-in codes is visible in the table with no code change.
        await admin.from('phone_verifications').insert({ email: acctEmail || '', phone: e164, code: own?.ok ? ownMarker(own.sid) : 'twilio:' + res.channel + (/^VE\w+$/.test(String(res.jd?.sid || '')) ? ':' + res.jd.sid : ''), user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
        // THE ANSWER DOES NOT NAME THE CHANNEL (security review, 18 Sep 2026). This endpoint takes no
        // session, and 'whatsapp' vs 'sms' would tell any anonymous caller holding a number that
        // resolves to one account whether THAT account has confirmed a WhatsApp number — private state
        // of somebody else's account, for the price of one rate-limited send to the victim's own
        // handset. The channel is in phone_verifications.code for us; the user finds the code in
        // whichever app it arrived in, and no screen branches on it (measured: neither CustomerPortal
        // nor SupplierPortal reads `channel`). The field is DROPPED rather than hard-coded to 'sms':
        // a payload that names the wrong channel is a lie, and an absent field is not.
        return J({ ok: true, identifier: e164, known: !!acctEmail });
      } catch (e) { console.error('login_otp: SMS send threw —', String((e as Error)?.message || e)); return J({ error: 'Could not send the SMS code.', code: 'sms_send_failed' }, 502); }
    }

    // FAILOVER (it_engineer, 18 Oct 2026; review of #1432). The sign-in screen calls this at fixed times after
    // every phone code request, whichever channel carried it. When the last code to the number went by WhatsApp,
    // this reads Twilio's delivery status for it and sends the SAME code by SMS when Twilio reports it undelivered
    // or failed, or it is still not delivered FAILOVER_AFTER_S after the send (_shared/whatsapp_choice.ts
    // failoverStep) - once per verification, under a locked rl_check key. The answer is ALWAYS {ok:true}: this
    // endpoint takes no session, and naming the channel or the delivery state would tell an anonymous caller
    // whether an account confirmed WhatsApp on that number.
    if (action === 'failover') {
      const e164 = toE164(idRaw);
      if (!e164 || isDemoPhone(e164)) return J({ ok: true });     // a fixture number never reaches Twilio
      const ipGate = await rl('login_otp_failover_ip:' + ip, 60, 3600);
      if (ipGate !== 'ok') return J({ ok: true });
      const { data: row } = await admin.from('phone_verifications').select('code,created_at,email').eq('phone', e164)
        .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString()).order('created_at', { ascending: false }).limit(1).maybeSingle();
      const sid = sidOfRow(row?.code);
      if (!row || channelOfRow(row.code) !== 'whatsapp' || !sid) return J({ ok: true });
      const tw = await twilioAuth(); if (!tw) return J({ ok: true });
      try {
        // our own WhatsApp code is read from the Messages API; a Verify one from Verify's Attempts
        let status: string | null = null;
        if (isOwnRow(row.code)) status = await ownMessageStatus(waDeps, sid);
        else {
          const ar = await timedFetch(`https://verify.twilio.com/v2/Attempts?VerificationSid=${sid}&Channel=whatsapp&PageSize=5`, { headers: { Authorization: tw.hdr } });
          const aj = await ar.json().catch(() => ({}));
          status = (aj?.attempts || [])[0]?.channel_data?.message_status ?? null;
        }
        if (failoverStep(status, Date.now() - Date.parse(row.created_at)) !== 'sms') return J({ ok: true });
        if ((await rl('otp_failover:' + sid, 1, 600)) !== 'ok') return J({ ok: true });
        const locale = await registeredLocale(admin, { role: kind, email: row.email || '' }, body.lang);
        const r = await timedFetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: e164, Channel: 'sms', Locale: locale }) });
        const jd = await r.json().catch(() => ({}));
        if (!r.ok || jd?.status === 'canceled') { await log('error', { failover: 1, http: r.status, wa_status: status }, 'login_otp could not send the failover SMS for a WhatsApp sign-in code: ' + String(jd?.message || jd?.status || '').slice(0, 200)); return J({ ok: true }); }
        await admin.from('phone_verifications').insert({ email: row.email || '', phone: e164, code: 'twilio:sms:' + sid, user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
        await log('ok', { failover: 1, wa_status: status }, '');
      } catch (e) { console.error('login_otp: failover threw -', String((e as Error)?.message || e)); }
      return J({ ok: true });
    }
    if (action === 'verify') {
      const code = String(body.code || '').replace(/\D/g, '');
      if (!code) return J({ error: 'Enter the code you received.', code: 'enter_code' }, 400);
      if (emailOk(idRaw)) {
        const email = idRaw.toLowerCase();
        // Cap guesses per caller AND per address before touching the row at all. The per-address cap is
        // the one an attacker cannot spread across IPs (pre-launch security pass, 6 Oct 2026, H1): ten
        // checks an hour for one email, whoever sends them, and the address is locked until the oldest
        // of those ten leaves the hour window. A person who mistypes twice and asks for a new code
        // never comes near it.
        // The two limiters stay one after the other on purpose: rl_check counts only a request it lets through, so an
        // address's bucket is spent only by a caller under the per-IP cap. Asked together, one capped IP could keep
        // filling any address's bucket and lock out as many accounts as it liked. The HMAC key read (a cold isolate's
        // only extra call) rides alongside them instead; the hash below waits on the same cached promise.
        const keyRead = otpKey().catch(() => null);
        const ipGate = await rl("login_otp_verify_ip:" + ip, EMAIL_VERIFY_PER_IP_HOUR, 3600);
        const idGate = ipGate === "ok" ? await rl("login_otp_verify_email:" + email, EMAIL_VERIFY_PER_EMAIL_HOUR, 3600) : ipGate;
        await keyRead;
        step('limit');
        if (ipGate === "down" || idGate === "down") return J(LIMITER_DOWN, 503);
        if (ipGate !== "ok" || idGate !== "ok") {
          await log("error", { rate_limited: 1, scope: ipGate !== "ok" ? "verify_ip" : "verify_email" }, ipGate !== "ok"
            ? "login_otp blocked a caller making more than " + EMAIL_VERIFY_PER_IP_HOUR + " code-verification attempts in an hour. A real person never reaches this; sustained hits mean someone is guessing codes."
            : "login_otp locked an address after " + EMAIL_VERIFY_PER_EMAIL_HOUR + " code-verification attempts in an hour, from any number of callers. The address can be verified again once the hour window clears; sustained hits mean someone is guessing that account's codes.");
          return J({ error: "Too many attempts. Please request a new code.", code: "too_many_attempts" }, 429);
        }
        // ONE STATEMENT DECIDES (H1). public.fn_login_otp_email_verify locks the newest live code,
        // refuses it expired, burns it at the cap, counts the guess, compares the HMAC and spends the
        // code only where it is still unspent, then answers one word. The old read-compare-write here
        // let parallel guesses share one counter value and let one code mint two sessions.
        // scripts/sql/a_sign_in_code_is_counted_compared_and_spent_in_one_statement.sql
        const { data: verdict, error: vErr } = await admin.rpc("fn_login_otp_email_verify", { p_email: email, p_hash: await otpHash(code), p_code: code, p_max_attempts: EMAIL_VERIFY_MAX_ATTEMPTS });
        step('check');
        if (vErr) { console.error("login_otp: verify routine failed —", vErr.message); return J({ error: "Verification failed, please try again.", code: "verify_failed" }, 502); }
        if (verdict === "expired") return J({ error: "That code has expired. Please request a new one.", code: "code_expired" }, 400);
        if (verdict === "burned") return J({ error: "Too many incorrect attempts. Please request a new code.", code: "code_burned" }, 429);
        if (verdict !== "ok") return J({ error: "Incorrect or expired code.", code: "wrong_code" }, 400);
        // ONE IDENTITY PER ROLE, DECIDED AFTER THE CODE (6 Oct 2026, M3). role_guard used to tell any
        // anonymous caller, before a code was sent, that an address belonged to the other role. The
        // same refusal now happens here, once the caller has proved they hold the mailbox, so it tells
        // them nothing they do not already own. No session is minted and no row is written.
        // Nothing about the address is read before this line (role_conflict.test.ts holds that). From here every read the
        // answer needs leaves at once: the role pair, the sanctions pair, the auth user and the registered language.
        const facts = accountFacts(email);
        const locale = registeredLocale(admin, { role: kind, email }, body.lang);
        const conflict = await roleConflict(kind, email);
        step('reads');
        if (conflict) return J({ error: conflict === "supplier" ? "This email is registered as a supplier. Please use the Supplier portal to sign in." : "This email is registered as a customer. Please use the customer app to sign in.", code: "role_conflict", conflict }, 409);
        // A FIRST-TIME CUSTOMER HAS NO ROW TO UPDATE (12 Aug 2026). This recorded proof of email
        // ownership with an UPDATE, and for someone signing in for the very first time there is
        // nothing to update: login_otp never creates a customers row, and the row that appears
        // seconds later - kyc save_customer, customer_api 'me', mobile_otp - inserts without the
        // flag. Nothing repairs it afterwards. Measured on production: the only real customer used
        // their code at 15:04:40 and kyc inserted the row at 15:05:26, so email_verified stayed
        // false and create_inquiry's first gate refused every request with "enter the 6-digit code
        // we email you" - the code they had just entered. Zero inquiries have ever been created.
        //
        // The supplier branch is safe for the opposite reason and is deliberately left an UPDATE:
        // a lead already exists to be claimed, so the row is always there (lead 30466 carries
        // owner_email_verified true from this same line). Creating a lead here would invent a
        // supplier out of a sign-in.
        //
        // Insert-then-fall-back-to-update is the shape kyc's own verify_email already uses; the
        // fallback covers the race where a concurrent caller inserts between the update and the
        // insert. customers.email has no unique index, so the insert cannot be an upsert.
        //
        // These writes and the session are independent (no trigger on auth.users; none on leads or customers reads auth),
        // so they run together: the session's three auth calls no longer queue behind them. A sanctioned party had these
        // rows written before the refusal as well; mintSession still refuses it before any user, link or session exists.
        let hasCompany: boolean | undefined;
        const recorded = (async () => {
          if (kind === 'customer') {
            const up = await admin.from('customers').update({ email_verified: true }).eq('email', email).select('id');
            if (!up.error && !(up.data || []).length) {
              // THIS IS THE REGISTRATION, so it records the language of the page they registered on
              // (founder, 14 Sep 2026). Before this the row took the column default 'en', so every
              // Arabic sign-up was registered as English and every later message followed that.
              const ins = await admin.from('customers').insert({ email, email_verified: true, locale: asLocale(body.lang) });
              if (ins.error) await admin.from('customers').update({ email_verified: true }).eq('email', email);
            }
          }
          // WHETHER THE SUPPLIER HAS A COMPANY YET, from the update this sign-in already makes (11 Nov 2026, customer_support;
          // registration certification finding 9). The portal waited for supplier_api `me` or supplier_portal `dashboard` after this
          // answer to learn it (verify 1.75 s, then me 1.39 s, on the free round's J5), so "Register your company" opened at 3.4 s
          // against 3 s. The rows the update touched say it, at no extra round trip. Only ever about the caller's own address.
          // Prevented by: scripts/checks/the_code_answer_says_whether_the_supplier_has_a_company.test.mjs
          if (kind === 'supplier') {
            const owned = await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email).select('id');
            if (!owned.error) hasCompany = (owned.data || []).length > 0;
          }
          // kind === 'admin' writes neither: the founder is not a customers row and not a claimed
          // lead. Before the third kind existed /os sent 'customer', so an admin email sign-in fell
          // into the else and ran an UPDATE on leads.claimed_by for the admin address.
        })();
        const [s] = await Promise.all([mintSession(email, true, facts), recorded]);
        step('session');
        if (s === 'sanctioned') return J(SANCTIONED_REFUSAL, 403); if (!s) return J({ error: 'Could not start your session. Please try again.', code: 'session_failed' }, 500);
        if (hasCompany !== undefined) Object.assign(s, { has_company: hasCompany });   // never sent when unknown
        return J({ ok: true, ...s, user_kind: kind, email, locale: await locale });
      }
      const e164 = toE164(idRaw); if (!e164) return J({ error: 'Enter a valid mobile number.', code: 'bad_mobile' }, 400);
      if (isDemoPhone(e164)) { await log('skipped', { kind, captured: 1, fixture: 1, action: 'verify' }, FIXTURE_CAPTURE_NOTE); return J(FIXTURE_REFUSAL); }
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS sign-in is not enabled yet.', code: 'sms_signin_unavailable' }, 503);
      try {
        // main's timedFetch (CONN-01..09) bounds the Twilio leg; #858's stable codes let the portal
        // translate the refusal; and the thrown message is logged SERVER-SIDE rather than returned as
        // `detail`, which is the leak SP-I-03 closed in thirteen other places — a Twilio exception
        // string is not for the browser. All three kept.
        // Our own WhatsApp code first (ledger 1252); anything else it can be is a Verify code (SMS, the SMS failover
        // after a WhatsApp code, voice, or a WhatsApp code Verify carried), so Verify is asked unless ours matched.
        const own = await checkOwnCode(waDeps, { phone: e164, purpose: 'login', binding: '', code });
        if (own !== 'ok') {
          const r = await timedFetch(`https://verify.twilio.com/v2/Services/${tw.va}/VerificationCheck`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: e164, Code: code }) });
          const jd = await r.json();
          if (jd?.status !== 'approved') {
            if (own === 'burned') return J({ error: 'Too many incorrect attempts. Please request a new code.', code: 'code_burned' }, 429);
            return J({ error: 'Incorrect or expired code.', code: 'wrong_code' }, 400);
          }
        }
      } catch (e) { console.error('login_otp: Verify check threw —', String((e as Error)?.message || e)); return J({ error: 'Verification failed, please try again.', code: 'verify_failed' }, 502); }
      step('check');
      // HISTORY IS NOT IDENTITY. This used to take the newest phone_verifications row for the
      // number and sign the caller in as whoever that row named — so on a shared handset you were
      // logged in as the last person who had asked for a code on it. That is the second half of
      // the same defect as the admin short-circuit, and it is gone: the account tables are the
      // only authority on who owns an address, and an ambiguous number is refused, not guessed.
      const owner = await resolveEmailByPhone(kind, e164);
      if (owner && 'ambiguous' in owner) return annotate(J({ error: AMBIGUOUS_MSG, code: 'ambiguous_phone', ambiguous: true }, 409), { ambiguous_phone: 1 });
      const email = owner ? owner.email : '';
      if (!email) {
        const other = await otherRoleByPhone(kind, e164);
        if (other) return J({ error: ROLE_CONFLICT_MSG[other], code: 'role_conflict_phone', conflict: other }, 409);
      }
      if (!email) return J({ error: 'No account is registered with this number. Please sign in with your email, or sign up first.', code: 'no_account_for_number' }, 404);
      step('reads');
      // The same shape as the email path: the two writes, the session and the registered language leave together.
      const locale = registeredLocale(admin, { role: kind, email }, body.lang);
      const recorded = Promise.all([
        kind === 'customer' ? admin.from('customers').update({ phone_verified: true }).eq('email', email) : null,
        admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', e164).is('used_at', null)]);
      const [s] = await Promise.all([mintSession(email, true), recorded]);
      step('session');
      if (s === 'sanctioned') return J(SANCTIONED_REFUSAL, 403); if (!s) return J({ error: 'Could not start your session. Please try again.', code: 'session_failed' }, 500);
      return J({ ok: true, ...s, user_kind: kind, email, locale: await locale });
    }

    return J({ error: 'Unknown action' }, 400);
  } catch (e) { console.error('login_otp: unhandled —', String((e as Error)?.message || e)); return J({ error: 'Something went wrong. Please try again.', code: 'unexpected_error' }, 500); }
// EVERY SIGN-IN IS LOGGED, NOT ONE A MINUTE (22 Sep 2026). observe() samples successes at one per 60 s per
// isolate and logs every refusal, and refusal_rate divides refusals by the rows it finds -- so on a busy
// minute the successes it could not see made the share of people turned away read higher than it was.
// Sign-in traffic is small; the true denominator is worth one row per request.
}, { okEveryMs: 0 });
