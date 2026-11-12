import { siteCors } from '../_shared/site_origins.ts';
// kyc — passwordless account completion: mobile (SMS) + email verification, REQUIRED DOB (18+) profile, terms->signed PDF.
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { annotate, observe } from '../_shared/observe.ts';
import { FIXTURE_CAPTURE_NOTE, FIXTURE_REFUSAL, isDemoEmail, isDemoPhone } from '../_shared/demo_identity.ts';
import { dobProblem } from '../_shared/account_rule.ts';
import { clientIp, supplierAcceptanceStands, supplierTermsRecord, FULL_NAME_REQUIRED, acceptanceNeedsName } from '../_shared/supplier_terms.ts';
import { customerTermsRecord } from '../_shared/customer_terms.ts';
import { asLocale, registeredLocale } from '../_shared/registered_locale.ts';
import { codeEmail } from '../_shared/code_email.ts';
import { askedPatch, channelOfRow, choosePatch, waDeliveredCode, failoverStep, isOwnRow, nextChannel, RESEND_GAP_S, sidOfRow, parseChoiceOpt, sendWhatsAppFirst, verifiedPatch, voiceAfterSms, waAfterMobileVerified, whatsappState, type Patch, type VerifySent, type WhatsAppRow } from '../_shared/whatsapp_choice.ts';
import { checkOwnCode, ownMarker, ownMessageStatus, ownSent, sendOwnWhatsAppCode, type WaCodeDeps } from '../_shared/wa_code.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail } from '../_shared/sanctioned.ts';
import { resendWithRetry } from '../_shared/resend_send.ts';
import { blocksTransactional } from '../_shared/suppression_policy.ts';
// THE UAE MOBILE RULE IS ENFORCED HERE TOO, NOT ONLY IN THE BROWSER (SP-A-05, 22 Sep 2026).
// TWIN: src/components/portal/supplier/uaeMobile.ts — _shared/uae_mobile.ts holds the one regex both
// sides use, and src/components/portal/supplier/serverCopy.ts owns the EN/AR for `bad_mobile`.
import { uaeMobile } from '../_shared/uae_mobile.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
// LATENCY (28 Sep 2026, it_engineer): the hourly SLO measured kyc p95 9,767 ms against 2,500. The database is in
// ap-southeast-1 and the platform runs a call in the region nearest the CALLER, so every SEQUENTIAL round trip
// costs ~0.2-0.3 s from the US and ~0.1 s from India; 'state' made five in a row and send_sms up to nine. The
// fix is fewer serial trips: provider keys are cached per isolate for a minute (secCached), the reads every action
// needs go out together, and the audit rows are written after the response. A minute is well inside a rotation's
// overlap (internal credentials; the Twilio API key is kept at least 24 h); should Twilio still answer 401
// (a key rotated and retired under a warm isolate), twilioVerifyPost drops the cache and retries once on a fresh read.
// sec() itself stays byte-identical to every other function's (scripts/checks/shared_helpers_agree.test.mjs).
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
const SEC_TTL_MS = 60_000;
const _sec = new Map<string, { v: string; at: number }>();
async function secCached(k: string): Promise<string | null> {
  const hit = _sec.get(k); if (hit && Date.now() - hit.at < SEC_TTL_MS) return hit.v;
  const v = await sec(k);
  if (v) _sec.set(k, { v, at: Date.now() }); else _sec.delete(k); // an absent or failed read is never cached
  return v;
}
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
function code6() { return String(Math.floor(100000 + Math.random() * 900000)); }
// SECURITY FIX (27 Jul 2026): email codes here were stored in PLAINTEXT (email_verifications.token)
// and checked with .eq('token', code) — a WHERE clause on the secret. A wrong guess simply matched no
// row, so nothing could be counted: no attempt cap, no lockout, no per-caller ceiling. 10^6 codes is
// minutes of scripted guessing. login_otp documented and fixed exactly this on 19–21 Jul; kyc never
// got the same treatment. Same approach copied here: HMAC-SHA256(code, app_secrets.otp_hmac_key) at
// rest (an unsalted hash of a 6-digit code is reversible from one table leak by precomputing all a
// million), fail closed if the key is absent rather than downgrade, guesses counted on the row and
// capped, plus a per-IP ceiling. email_verifications already carries attempts + token_hash (login_otp
// uses both), so no schema change is involved.
const KYC_EMAIL_MAX_ATTEMPTS = 5;
const KYC_EMAIL_VERIFY_PER_IP_HOUR = 30;
let _otpKey: string | null = null;
async function otpKey(): Promise<string> { if (_otpKey) return _otpKey; const k = await sec('otp_hmac_key'); if (!k) throw new Error('otp_hmac_key_missing'); _otpKey = k; return k; }
// A WhatsApp phone code we send ourselves, without Verify's USD 0.05 a code (ledger 1252, _shared/wa_code.ts). kyc
// codes are bound to the signed-in account's email as well as the number: one account's code verifies nothing for another.
const waDeps: WaCodeDeps = { admin, secret: secCached, hmac: (s) => otpHash(s) };
async function otpHash(code: string): Promise<string> { const ck = await crypto.subtle.importKey('raw', new TextEncoder().encode(await otpKey()), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); const mac = await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(code)); return Array.from(new Uint8Array(mac)).map((x) => x.toString(16).padStart(2, '0')).join(''); }
async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // limiter unavailable must not lock legitimate users out of account completion
}
async function twilioAuth() { const [sid, secret, va] = await Promise.all([secCached('twilio_api_key_sid'), secCached('twilio_api_key_secret'), secCached('twilio_verify_service_sid')]); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }
type TwAuth = { hdr: string; va: string };
// ONE Verify send, ONE check, ONE per-number limit for every channel (14 Sep 2026). send_sms owned
// these inline; the WhatsApp question needs the identical machinery on Channel=whatsapp, and two
// copies of a rate limit is how one of them ends up looser. The limit counts phone_verifications rows
// for the number in the last hour regardless of channel, so SMS, call and WhatsApp share 5 per hour.
// PER ACCOUNT TOO (21 Sep 2026, registration-day surge review). The cap above was per NUMBER only, so
// one signed-in account could walk a list of numbers at 5 billable Verify sends each (~$0.17 per SMS to
// the UAE) with nothing in this function stopping it - the hole login_otp closed on 19 Jul. On a
// campaign day that is also SMS sent in our name to strangers. A real supplier verifies one mobile,
// perhaps after a typo and a resend or two, so 8 sends per account per hour across every number and
// channel is never reached honestly.
const KYC_PHONE_SENDS_PER_NUMBER_HOUR = 5;
const KYC_PHONE_SENDS_PER_ACCOUNT_HOUR = 8;
async function phoneRateLimited(phone: string, email: string): Promise<boolean> {
  const since = new Date(Date.now() - 3600e3).toISOString();
  const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', phone).gte('created_at', since);
  if ((count || 0) >= KYC_PHONE_SENDS_PER_NUMBER_HOUR) return true;
  const mine = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('email', email).gte('created_at', since);
  return (mine.count || 0) >= KYC_PHONE_SENDS_PER_ACCOUNT_HOUR;
}
// A 401 FROM TWILIO RE-READS THE KEY AND TRIES ONCE MORE (29 Sep 2026, review of #1038). The pair is cached for
// up to SEC_TTL_MS, and it_engineer now rotates the Twilio API key by API. The old key is kept for at least 24 h
// after a rotation, so a cached key should never be a deleted one; this is the second line: a rejected key drops
// the cached pair, reads app_secrets again and retries once, only if the pair actually changed.
const TW_KEYS = ['twilio_api_key_sid', 'twilio_api_key_secret', 'twilio_verify_service_sid'];
async function twilioVerifyPost(tw: TwAuth, path: string, body: URLSearchParams): Promise<Response> {
  const post = () => timedFetch(`https://verify.twilio.com/v2/Services/${tw.va}/${path}`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  let r = await post();
  if (r.status === 401) {
    for (const k of TW_KEYS) _sec.delete(k);
    const fresh = await twilioAuth();
    if (fresh && (fresh.hdr !== tw.hdr || fresh.va !== tw.va)) { tw.hdr = fresh.hdr; tw.va = fresh.va; r = await post(); }
  }
  return r;
}
async function verifySend(tw: TwAuth, phone: string, channel: string, locale: string) {
  const r = await twilioVerifyPost(tw, 'Verifications', new URLSearchParams({ To: phone, Channel: channel, Locale: locale }));
  const jd: any = await r.json().catch(() => ({}));
  return { r, jd };
}
async function verifyCheck(tw: TwAuth, phone: string, code: string): Promise<boolean> {
  const r = await twilioVerifyPost(tw, 'VerificationCheck', new URLSearchParams({ To: phone, Code: code }));
  const jd: any = await r.json().catch(() => ({}));
  return jd?.status === 'approved';
}
// ONE RETRY ON 429 (21 Sep 2026). Resend allows 10 requests a second per team, shared with send_outbox
// draining a campaign on the same key; a code refused for a busy second is retried once rather than lost.
// The call lives in _shared/resend_send.ts so login_otp and kyc cannot drift apart.
async function sendEmail(to: string, subject: string, html: string) { const [key, fromS, replyS] = await Promise.all([secCached('resend_api_key'), secCached('email_from_info'), secCached('email_reply_info')]); if (!key) return false; const from = fromS || 'QuotesDone <info@quotesdone.com>'; const reply_to = replyS || 'info@quotesdone.com'; return await resendWithRetry(key, { from, to, subject, html, reply_to }); }
// SUPPRESSION BYPASS 28 Jul 2026 ----------------------------------------------------------------
// login_otp and contact_submit both consult email_suppressions before handing anything to Resend,
// and send_outbox queries the same table. kyc did not: sendEmail() above builds its own Resend call,
// so the "Confirm your QuotesDone email" code went to whatever address the session carries -
// including one Resend has already told us rejects mail permanently. A user correctly refused at
// sign-in by login_otp for exactly this reason reaches the same mailbox one screen later through
// account setup, which is the domain-reputation damage the list exists to prevent. Same check, same
// shape of refusal and the same agent_runs note as login_otp, so there is one mechanism and not two.
// Fails OPEN on a lookup error - a suppression-table outage must not block account completion.
async function isSuppressed(email: string): Promise<boolean> {
  // 22 Sep 2026: an 'unsubscribe' row is a marketing opt-out and never refuses a code (_shared/suppression_policy.ts).
  try { const { data } = await admin.from('email_suppressions').select('reason').eq('email', email).maybeSingle(); return !!data && blocksTransactional(data.reason); }
  catch (_e) { return false; }
}

// Observability: identity state changes and delivery failures land in agent_runs.
// The read-only 'state' action is not logged (high volume, no failure mode worth tracking).
function mkLog(t0: number) {
  // Written AFTER the response when the runtime allows it (EdgeRuntime.waitUntil keeps the isolate alive for
  // it), so a user never waits on an audit row. Without the runtime (deno test) it is awaited as before.
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    const w = (async () => { try {
      await admin.from('agent_runs').insert({ agent: 'kyc', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break account completion */ } })();
    const rt = (globalThis as any).EdgeRuntime;
    if (typeof rt?.waitUntil === 'function') rt.waitUntil(w); else await w;
  };
}

// The action goes onto the observe row, so the hourly p95 can be read per action and not only per function.
Deno.serve(siteCors(observe('kyc', async (req) => {
  const meta: { action?: string; fixture?: boolean } = {};
  const res = await handle(req, meta);
  // A reserved test identity (@example.invalid, _shared/demo_identity.ts) is our harness, never a person: the row
  // says so, and fn_it_engineer_latency_slo leaves it out of the error budget (it_engineer, 29 Sep 2026).
  return meta.action ? annotate(res, { action: meta.action, ...(meta.fixture ? { caller: 'fixture', fixture: 1 } : {}) }) : res;
})));

async function handle(req: Request, meta: { action?: string; fixture?: boolean }): Promise<Response> {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    // ONE round trip for everything every action reads, instead of five in a row. The sanction check still
    // decides before anything is written or answered; it simply no longer waits alone.
    const LEAD_COLS = 'id,contact_name,signatory_name,phone,owner_dob,owner_email_verified,owner_phone_verified,accepted_terms_at,accepted_terms_version,signed_terms_url,company_name';
    const CUST_COLS = 'id,full_name,phone,date_of_birth,email_verified,phone_verified,tos_accepted_at,tos_version,signed_terms_url';
    const WA_COLS = 'whatsapp_phone,whatsapp_verified_at,whatsapp_opt,whatsapp_asked_at';
    const [sanctioned, bodyIn, leadR, custR, leadWaR, custWaR] = await Promise.all([
      sanctionedEmail(admin, email),
      req.json().catch(() => ({} as any)),
      admin.from('leads').select(LEAD_COLS).eq('claimed_by', email).maybeSingle(),
      admin.from('customers').select(CUST_COLS).eq('email', email).maybeSingle(),
      admin.from('leads').select(WA_COLS).eq('claimed_by', email).maybeSingle(),
      admin.from('customers').select(WA_COLS).eq('email', email).maybeSingle(),
    ]);
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026; security review the
    // same day found this function authenticated a supplier by leads.claimed_by and asked
    // nothing about the ban). Above everything this function does, so it covers what is written
    // here next year too.
    if (sanctioned) return J(SANCTIONED_REFUSAL, 403);
    const b = bodyIn; const action = String(b.action || ''); meta.action = action.slice(0, 40);
    // Every action that sends or checks a Twilio Verify code refuses a fixture number first.
    if (['send_sms', 'verify_sms', 'whatsapp_send_code', 'whatsapp_verify', 'phone_failover'].includes(action) && isDemoPhone(toE164(String(b.phone || '')))) {
      await logRun('skipped', { action, captured: 1 }, FIXTURE_CAPTURE_NOTE);
      return J(FIXTURE_REFUSAL);
    }

    const lead = leadR.data as any; const cust = custR.data as any;
    const kind = lead ? 'supplier' : 'customer';

    // The whatsapp_* columns are read in their OWN query, not added to the two selects above. A
    // select naming a column that does not exist returns data=null, and a null lead flips every
    // supplier to kind='customer' - so deploying this before the schema would have mis-routed every
    // action for every supplier. Isolated here, the worst case is a logged read error.
    const waTable = kind === 'supplier' ? 'leads' : 'customers';
    const waKey = kind === 'supplier' ? 'claimed_by' : 'email';
    // readWa runs before any write in every action that calls it, so the prefetched row is the current one.
    const readWa = async (): Promise<WhatsAppRow | null> => {
      const { data, error } = kind === 'supplier' ? leadWaR : custWaR;
      if (error) { await logRun('error', { action, kind, stage: 'whatsapp_read' }, 'kyc could not read the whatsapp_* columns on ' + waTable + ': ' + error.message); return null; }
      return data as WhatsAppRow | null;
    };
    const writeWa = async (patch: Patch): Promise<boolean> => {
      const { data, error } = await admin.from(waTable).update(patch).eq(waKey, email).select('id');
      if (!error && (data?.length || 0) > 0) return true;
      // Same rule as verify_email: a customer may have a session and no customers row yet.
      if (!error && kind === 'customer') {
        const ins = await admin.from('customers').insert({ email, locale: asLocale(b.lang), ...patch });
        if (!ins.error) return true;
        await logRun('error', { action, kind, stage: 'whatsapp_write' }, 'kyc could not create the customers row for the WhatsApp answer: ' + ins.error.message);
        return false;
      }
      await logRun('error', { action, kind, stage: 'whatsapp_write' }, 'kyc could not save the WhatsApp answer on ' + waTable + ': ' + (error ? error.message : 'no row matched'));
      return false;
    };
    const saveFailed = () => J({ ok: false, error: 'save_failed', code: 'save_failed' }, 500);

    if (action === 'state') {
      // SECURITY FIX (27 Jul 2026): 'state' derived `emailProven` from the auth provider's
      // email_confirmed_at / confirmed_at and, on a plain READ, flipped owner_email_verified /
      // email_verified to true. That flag proves nothing on this platform: every auth user is minted
      // with email_confirm:true (login_otp ensureUser, and auth_api before it was retired), so
      // emailProven was ALWAYS true and the first 'state' call self-granted email verification to
      // anyone holding a session — including a session obtained by SMS alone, which never touches the
      // address. Email is proven only by the 6-digit code this function itself sends and checks
      // (send_email -> verify_email). A read must not mutate identity state, so the persist-what-we-
      // report insert from the earlier fix is gone too: with nothing granted here there is nothing to
      // persist, and a customer with no row is simply not verified yet (save_customer /
      // verify_email create it). Response shape is unchanged for CustomerPortal / SupplierPortal.
      const whatsapp = whatsappState(await readWa());
      if (kind === 'supplier') {
        const ev = !!lead!.owner_email_verified;
        return J({ ok: true, kind, email, full_name: lead!.contact_name, phone: lead!.phone, dob: lead!.owner_dob, email_verified: ev, phone_verified: !!lead!.owner_phone_verified, terms_signed: !!lead!.signed_terms_url, whatsapp });
      }
      const c = cust || {} as any;
      const ev = !!c.email_verified;
      return J({ ok: true, kind, email, full_name: c.full_name || '', phone: c.phone || '', dob: c.date_of_birth || '', email_verified: ev, phone_verified: !!c.phone_verified, terms_signed: !!c.signed_terms_url, whatsapp });
    }

    if (action === 'save_customer') {
      const full_name = String(b.full_name || '').trim().slice(0, 120); const phone = String(b.phone || '').trim().slice(0, 40); const dob = String(b.dob || '').trim();
      if (full_name.length < 2) return J({ error: 'Please enter your name.', code: 'enter_name' }, 400);
      // SP-A-05, the third door nobody named (review of #858, 22 Sep 2026). This action has no `kind`
      // gate, so a SUPPLIER session can post here and write a customers row keyed by their own email
      // carrying any 7+ digit number. That row is not cosmetic: login_otp's resolveEmailByPhone maps
      // an incoming number back to an account, so a junk or foreign number saved here resolves a
      // phone sign-in to the supplier's address. Customers keep the loose rule for the documented
      // Dubai landline fallback (+9714…, verified by voice call, 12 Aug 2026).
      if (kind === 'supplier' && !uaeMobile(phone)) return J({ error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      if (phone.replace(/\D/g, '').length < 7) return J({ error: 'Please enter a valid mobile number.', code: 'bad_mobile' }, 400);
      // DATE OF BIRTH IS REQUIRED AND UNDER-18 IS REFUSED (founder's account rule, 14 Sep 2026 — see
      // _shared/account_rule.ts). This used to keep an 18-120 date and silently DROP anything else, so
      // an under-18 user was never told no and a profile could complete with no DOB at all. Now a
      // missing, unparseable or under-18 date answers a code and saves nothing. An empty field falls
      // back to the stored DOB so the Account tab (which edits name/phone only) keeps working.
      const dobUse = dob || String((cust as any)?.date_of_birth || '');
      const dp = dobProblem(dobUse);
      if (dp) {
        const message = dp === 'under_18' ? 'You must be 18 or over to use QuotesDone.' : dp === 'dob_required' ? 'Please enter your date of birth.' : 'Please enter a valid date of birth.';
        return J({ error: dp, code: dp, message }, 400);
      }
      const row: any = { email, full_name, phone, date_of_birth: dobUse.slice(0, 10) };
      // CHANGING A VERIFIED NUMBER MUST UN-VERIFY IT (13 Aug 2026).
      //
      // This wrote `phone` and left `phone_verified` alone, so any caller holding a customer
      // session could POST a DIFFERENT number and keep the verified flag. That flag is not
      // cosmetic: create_inquiry gates on it, fn_wa_context scopes a WhatsApp conversation by it,
      // and login_otp's resolveEmailByPhone maps an incoming number back to an account with
      // `limit 1` — so a number written onto the wrong account can resolve a real person's phone
      // sign-in to somebody else's row. Verification means "we sent a code to THIS number and it
      // came back"; the moment the number changes, that sentence is no longer true about it.
      //
      // Compared digits-only because the same number is stored as +9715…, 05…, and with spaces,
      // and a formatting change is not a new number. Re-verifying is the ProfileGate's existing
      // flow: phone_verified false makes the gate render again on the next load, which is exactly
      // where the Send SMS control lives.
      const digits = (v: unknown) => String(v || '').replace(/\D/g, '');
      const phoneChanged = !!cust && digits((cust as any).phone) !== digits(phone);
      if (phoneChanged) row.phone_verified = false;
      // A first save IS the registration: it records the page language. An update never touches
      // locale - that changes only through Account settings (customer_api set_locale).
      if (cust) await admin.from('customers').update(row).eq('id', cust.id); else await admin.from('customers').insert({ ...row, locale: asLocale(b.lang) });
      if (phoneChanged) await logRun('ok', { action, kind, phone_reverify: 1 }, 'A customer changed their mobile number, so phone_verified was cleared and they must verify the new number before create_inquiry will accept a request. This is the intended behaviour, not a regression.');
      else await logRun('ok', { action, kind, created: !cust }, '');
      return J({ ok: true, phone_reverify_required: phoneChanged });
    }

    if (action === 'send_email') {
      // Checked BEFORE the row is inserted so we never mint a code that cannot be delivered.
      if (await isSuppressed(email)) {
        await logRun('error', { action, kind, suppressed: 1, channel: 'email' }, 'kyc refused to email a verification code to ' + email + ' - it is in email_suppressions (hard bounce, spam complaint or a guardrail block - an unsubscribe never refuses a code). No code was issued and no Resend call was made. If this is a real user, confirm the mailbox works and delete their email_suppressions row; do not remove this check.');
        return J({ error: 'We cannot email this address - it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.', code: 'email_suppressed', suppressed: true }, 403);
      }
      // The same 8-an-hour ceiling login_otp puts on sign-in codes; this branch had none (21 Sep 2026).
      const since = new Date(Date.now() - 3600e3).toISOString();
      const { count: sentLastHour } = await admin.from('email_verifications').select('id', { count: 'exact', head: true }).eq('email', email).gte('created_at', since);
      if ((sentLastHour || 0) >= 8) return J({ ok: false, error: 'Too many code requests. Please try again later.', code: 'rate_limited' }, 429);
      const c = code6();
      // 27 Jul 2026: store token_hash (HMAC), never the bare code. token stays NULL from here on;
      // verify_email still honours a plaintext token row so codes issued before this deploy work out
      // their 10 minutes. Expiry was and stays 10 minutes and is enforced on the verify side.
      await admin.from('email_verifications').insert({ email, token_hash: await otpHash(c), purpose: 'kyc', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      // previously the send result was discarded: a failed send left the user waiting with no trace
      const codeAr = (await registeredLocale(admin, { role: kind, email }, b.lang)) === 'ar';
      const mail = codeEmail('confirm', c, codeAr);
      const sent = await sendEmail(email, mail.subject, mail.html);
      // A code that did not leave is not "sent" (21 Sep 2026): this answered ok:true either way, so the
      // screen said "we emailed you a code" over a Resend refusal and the supplier waited for nothing.
      if (!sent) { await logRun('error', { action, kind }, 'verification email failed to send (Resend rejected or key missing) - user cannot verify'); return J({ ok: false, error: 'Could not send the email code. Please try again in a minute.', code: 'email_not_sent' }, 502); }
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }
    if (action === 'verify_email') {
      const c = String(b.code || '').replace(/\D/g, '');
      if (!c) return J({ error: 'Enter the 6-digit code.', code: 'enter_code' }, 400);
      // SECURITY FIX (27 Jul 2026): see the OTP note at the top. The lookup used to put the code in
      // the WHERE clause, so a wrong guess was indistinguishable from "no code" and could not be
      // counted — unlimited guesses at 10^6. Now: cap per caller BEFORE touching the row, fetch the
      // newest live code, compare in code, count the miss, and burn the code on the 5th.
      const vip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
      if (!(await rl('kyc_verify_email_ip:' + vip, KYC_EMAIL_VERIFY_PER_IP_HOUR, 3600))) {
        await logRun('error', { action, kind, rate_limited: 1, scope: 'verify_ip' }, 'kyc blocked a caller making more than ' + KYC_EMAIL_VERIFY_PER_IP_HOUR + ' email-code attempts in an hour. A real person never reaches this; sustained hits mean someone is guessing codes.');
        return J({ error: 'Too many attempts. Please request a new code.', code: 'too_many_attempts' }, 429);
      }
      // limit(1) + [0], NOT maybeSingle(): a user who pressed send twice has two live rows and
      // maybeSingle() errors on >1 and returns null, which would reject BOTH codes (login_otp's
      // self-inflicted lockout, 21 Jul). limit(1) deterministically takes the newest.
      const { data: rows } = await admin.from('email_verifications').select('*').eq('email', email).eq('purpose', 'kyc').is('used_at', null).order('created_at', { ascending: false }).limit(1);
      const row = rows && rows[0];
      if (!row) return J({ error: 'Incorrect or expired code.', code: 'wrong_code' }, 400);
      if (new Date(row.expires_at) < new Date()) return J({ error: 'That code has expired.', code: 'code_expired' }, 400);
      if ((row.attempts || 0) >= KYC_EMAIL_MAX_ATTEMPTS) {
        await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
        await logRun('error', { action, kind, locked: 1 }, 'kyc burned an email code after ' + KYC_EMAIL_MAX_ATTEMPTS + ' wrong guesses; the user must request a new one. Sustained hits on one account mean someone is guessing.');
        return J({ error: 'Too many incorrect attempts. Please request a new code.', code: 'code_burned' }, 429);
      }
      // row.token is only set for codes issued before hashing shipped on 27 Jul 2026
      const match = row.token_hash ? ((await otpHash(c)) === row.token_hash) : (!!row.token && c === row.token);
      if (!match) { await admin.from('email_verifications').update({ attempts: (row.attempts || 0) + 1 }).eq('id', row.id); return J({ error: 'Incorrect or expired code.', code: 'wrong_code' }, 400); }
      // verified_at: this code was entered RIGHT, the one mark public.fn_email_proven counts (10 Nov 2026,
      // an_email_is_proven_only_by_a_code_that_was_verified.sql); the burn above sets used_at only.
      const at = new Date().toISOString();
      await admin.from('email_verifications').update({ used_at: at, verified_at: at }).eq('id', row.id);
      // 27 Jul 2026: 'state' no longer creates the customers row as a side effect of a read, so this
      // must not assume one exists — an .update() on a missing row silently persists nothing and the
      // user would loop on the verify step forever. Insert it, falling back to update on a race.
      if (kind === 'supplier') await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email);
      else if (cust) await admin.from('customers').update({ email_verified: true }).eq('email', email);
      else { const ins = await admin.from('customers').insert({ email, email_verified: true, locale: asLocale(b.lang) }); if (ins.error) await admin.from('customers').update({ email_verified: true }).eq('email', email); }
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'send_sms') {
      // SP-A-05: a SUPPLIER's mobile must satisfy the same +9715XXXXXXXX rule the sign-up form applies
      // in the browser, so posting straight to this function cannot get a junk number past it and leave
      // the supplier waiting on an SMS Twilio accepted and never delivered. CUSTOMERS keep toE164: the
      // landline fallback below is real (a Dubai landline, +9714…, verified by voice call, 12 Aug 2026)
      // and the UAE-mobile rule would refuse it before Twilio was ever asked.
      const phone = kind === 'supplier' ? uaeMobile(b.phone) : toE164(String(b.phone || ''));
      if (!phone) return J({ error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio_api_key_sid / secret / verify_service_sid'); return J({ error: 'SMS is not configured.', code: 'sms_unavailable' }, 500); }
      if (await phoneRateLimited(phone, email)) { await logRun('ok', { action, kind, rate_limited: true }, 'rate limit hit: 5+ code requests for this number in the last hour'); return J({ error: 'Too many code requests. Please try again later.', code: 'sms_rate_limited' }, 429); }
      // LANDLINE FALLBACK (12 Aug 2026). Twilio Verify refuses SMS to a landline with error 21635,
      // and the only customer on file registered a Dubai landline: Twilio Lookup returns
      // type=landline for +97142587734, and a real send returned HTTP 400 / 21635. So the one
      // button on the screen could never verify him, and create_inquiry's phone_verified gate kept
      // the RFQ door shut. Verify carries the SAME code by voice on Channel=call, which a landline
      // answers - proven by execution against that number (HTTP 201, status pending). Fall back
      // automatically and tell the caller which channel actually carried it, so the screen can say
      // "we are calling you" instead of asking him to watch for an SMS that cannot arrive.
      // Locale: the SMS or voice call speaks the registered language (founder, 14 Sep 2026).
      const vLocale = await registeredLocale(admin, { role: kind, email }, b.lang);
      // WHATSAPP ONLY WHEN THE USER CHOSE IT (it_engineer, 18 Oct 2026; review of #1432). The screen offers
      // "Send the code on WhatsApp" and "by SMS"; the signed-in user typed this number and picked one.
      // _shared/whatsapp_choice.ts nextChannel: a second request after a WhatsApp code goes by SMS. Resends
      // are spaced by the locked rl_check (one per RESEND_GAP_S per number), checked before Twilio is asked.
      if (!(await rl('otp_gap:' + phone, 1, RESEND_GAP_S))) return J({ error: 'A code is on its way. Please wait a few seconds before asking for another.', code: 'resend_too_soon', retry_after: RESEND_GAP_S }, 429);
      const { data: lastRow } = await admin.from('phone_verifications').select('code').eq('phone', phone)
        .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString()).order('created_at', { ascending: false }).limit(1).maybeSingle();
      const pick = nextChannel({ e164: phone, asked: b.channel, lastChannel: channelOfRow(lastRow?.code) });
      const send = async (c: 'whatsapp' | 'sms' | 'call') => verifySend(tw, phone, c, vLocale);
      const one = async (c: 'sms' | 'call'): Promise<VerifySent> => { const x = await send(c); return x.r.ok && x.jd?.status !== 'canceled' ? { ...x, refused: null, ok: true, channel: c } : { ...x, refused: null, ok: false, channel: null }; };
      // ledger 1252: a WhatsApp code is ours (USD 0.0157), not Verify's (0.0657); anything short of a clean send uses Verify.
      const own = pick === 'whatsapp' ? await sendOwnWhatsAppCode(waDeps, { phone, purpose: 'kyc_phone', binding: email, kind, email, lang: vLocale }) : null;
      let res: VerifySent = own?.ok ? ownSent(own.sid) : pick === 'whatsapp' ? await sendWhatsAppFirst(send) : await one(pick);
      // 21635 is the landline refusal kept from 12 Aug; voiceAfterSms covers the other SMS-unreachable codes.
      if (!res.ok && res.jd?.code === 21635 && pick === 'sms') res = await one('call');
      res = await voiceAfterSms(res, send);
      const { r, jd } = res; const channel = res.channel || pick;
      if (!res.ok) { await logRun('error', { action, kind, http: r.status, channel }, 'twilio verify send failed on channel ' + channel + ': ' + String(jd?.message || jd?.status || '').slice(0, 200)); return J({ error: 'Could not send the code. Please try again in a minute.', code: 'sms_send_failed' }, 502); }
      // The row carries the delivered channel and Verify's SID (never the code) so phone_failover can read
      // the WhatsApp message's delivery status.
      const sid = /^VE\w+$/.test(String(jd?.sid || '')) ? ':' + jd.sid : '';
      await admin.from('phone_verifications').insert({ email, phone, code: own?.ok ? ownMarker(own.sid) : 'twilio:' + channel + sid, user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      await logRun('ok', { action, kind, channel }, '');
      return J({ ok: true, channel });
    }
    // PHONE_FAILOVER (it_engineer, 18 Oct 2026; review of #1432). The screen calls this at fixed times after a
    // WhatsApp code went out. It reads Twilio's delivery status for that message and, when Twilio reports it
    // undelivered or failed, or it is still not delivered FAILOVER_AFTER_S after the send, sends the SAME code
    // (one Verify verification) to the same number by SMS - once, under a locked rl_check key per verification.
    if (action === 'phone_failover') {
      const phone = kind === 'supplier' ? uaeMobile(b.phone) : toE164(String(b.phone || ''));
      if (!phone) return J({ error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      const { data: row } = await admin.from('phone_verifications').select('code,created_at').eq('phone', phone).eq('email', email)
        .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString()).order('created_at', { ascending: false }).limit(1).maybeSingle();
      const sid = sidOfRow(row?.code);
      if (!row || channelOfRow(row.code) !== 'whatsapp' || !sid) return J({ ok: true, state: 'nothing_to_do' });
      const tw = await twilioAuth(); if (!tw) return J({ ok: true, state: 'nothing_to_do' });
      // our own WhatsApp code is read from the Messages API (ledger 1252), a Verify one from Verify's Attempts
      let status: string | null = null;
      if (isOwnRow(row.code)) status = await ownMessageStatus(waDeps, sid);
      else {
        const ar = await timedFetch(`https://verify.twilio.com/v2/Attempts?VerificationSid=${sid}&Channel=whatsapp&PageSize=5`, { headers: { Authorization: tw.hdr } });
        const aj: any = await ar.json().catch(() => ({}));
        status = (aj?.attempts || [])[0]?.channel_data?.message_status ?? null;
      }
      const step = failoverStep(status, Date.now() - Date.parse(row.created_at));
      if (step !== 'sms') return J({ ok: true, state: step === 'none' ? 'delivered' : 'waiting' });
      if (!(await rl('otp_failover:' + sid, 1, 600)) || await phoneRateLimited(phone, email)) return J({ ok: true, state: 'waiting' });
      const vLocale = await registeredLocale(admin, { role: kind, email }, b.lang);
      const x = await verifySend(tw, phone, 'sms', vLocale);
      if (!x.r.ok || x.jd?.status === 'canceled') { await logRun('error', { action, kind, http: x.r.status, wa_status: status }, 'whatsapp failover SMS refused: ' + String(x.jd?.message || x.jd?.status || '').slice(0, 200)); return J({ ok: false, state: 'failed', code: 'sms_send_failed' }, 502); }
      await admin.from('phone_verifications').insert({ email, phone, code: 'twilio:sms:' + sid, user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      await logRun('ok', { action, kind, failover: 1, wa_status: status }, '');
      return J({ ok: true, state: 'sent_sms', channel: 'sms' });
    }
    if (action === 'verify_sms') {
      // SP-A-05 WAS ONLY HALF CLOSED (review of #858, 22 Sep 2026). send_sms applied the UAE-mobile
      // rule; THIS action did not, and this is the one that writes. A caller could post
      // whatsapp_send_code with +447700900000 (Verify happily sends to it), then verify_sms with the
      // code, and line below wrote leads.phone = that number with owner_phone_verified = true — a
      // supplier record carrying a verified non-UAE mobile, exactly what the rule exists to prevent.
      // Customers keep toE164 for the documented Dubai landline fallback (+9714…, 12 Aug 2026).
      const phone = kind === 'supplier' ? uaeMobile(b.phone) : toE164(String(b.phone || ''));
      const code = String(b.code || '').replace(/\D/g, '');
      if (kind === 'supplier' && !phone) return J({ error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      if (!phone || !code) return J({ error: 'Enter the 6-digit code.', code: 'enter_code' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio credentials'); return J({ error: 'SMS is not configured.', code: 'sms_unavailable' }, 500); }
      // ours first (ledger 1252); otherwise it is a Verify code (SMS, voice, the SMS failover, a Verify WhatsApp code)
      if ((await checkOwnCode(waDeps, { phone, purpose: 'kyc_phone', binding: email, code })) !== 'ok' && !(await verifyCheck(tw, phone, code))) return J({ error: 'Incorrect or expired code.', code: 'wrong_code' }, 400);
      if (kind === 'supplier') await admin.from('leads').update({ owner_phone_verified: true, phone }).eq('claimed_by', email); else await admin.from('customers').update({ phone_verified: true, phone }).eq('email', email);
      // A CODE THAT ARRIVED ON WHATSAPP IS PROOF OF THE WHATSAPP NUMBER (2 Nov 2026, customer_support). The user chose
      // "send the code on WhatsApp" and typed back what that message carried: the same proof whatsapp_verify takes, so the
      // number is confirmed for WhatsApp now (verifiedPatch) and a text from it is recognised (fn_whatsapp_owner). The
      // consent rule is unchanged: only a code actually DELIVERED on WhatsApp counts (the last row's channel; an SMS or
      // call failover row says 'sms'/'call' and confirms nothing), and the user picked that channel.
      // Prevented by: _shared/whatsapp_choice.test.ts (waDeliveredCode).
      const { data: lastCodeRow } = await admin.from('phone_verifications').select('code').eq('phone', phone).eq('email', email)
        .gte('created_at', new Date(Date.now() - 10 * 60e3).toISOString()).order('created_at', { ascending: false }).limit(1).maybeSingle();
      // ...and an answer "same" about the old number is asked again when the new one was proven by SMS (D2/R1; waAfterMobileVerified).
      const waNow = waDeliveredCode(lastCodeRow?.code) ? null : await readWa();
      const waPatch = waAfterMobileVerified(waNow?.whatsapp_opt, phone, waDeliveredCode(lastCodeRow?.code), new Date().toISOString());
      if (waPatch) await writeWa(waPatch);
      await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    // ---- "Is this number on WhatsApp?" (founder, 14 Sep 2026; pure rules in _shared/whatsapp_choice.ts)
    // Every refusal carries a `code` the portal maps to EN/AR text. Nothing is stored about a number
    // until Twilio approves a code sent to it over WhatsApp itself; only whatsapp_asked_at moves early.
    if (action === 'whatsapp_choose') {
      const opt = parseChoiceOpt(b.opt);
      if (!opt) return J({ ok: false, error: 'bad_opt', code: 'bad_opt' }, 400);
      const mobileVerified = kind === 'supplier' ? !!lead!.owner_phone_verified : !!(cust as any)?.phone_verified;
      const mobile = mobileVerified ? toE164(String((kind === 'supplier' ? lead!.phone : (cust as any)?.phone) || '')) : '';
      const patch = choosePatch(opt, mobile || null, new Date().toISOString());
      if (!patch) return J({ ok: false, error: 'mobile_not_verified', code: 'mobile_not_verified' }, 400);
      if (!(await writeWa(patch))) return saveFailed();
      await logRun('ok', { action, kind, opt }, '');
      return J({ ok: true, whatsapp: whatsappState(patch as WhatsAppRow) });
    }
    // WHATSAPP FIRST, SMS ON REFUSAL (founder, 15 Sep 2026: "live on the portal now, not after Meta").
    // Every attempt asks Verify for Channel=whatsapp; only Verify's template / sender refusal
    // (_shared/whatsapp_choice.ts REFUSED_CODES) sends the same code by SMS to the SAME number. The code
    // is checked by the same Verify service whichever channel carried it, so whatsapp_verify is unchanged.
    // The delivered channel is recorded in phone_verifications.code as 'twilio:<channel>' (the column only
    // ever held the marker 'twilio'; no reader compares it), so the day WhatsApp starts delivering shows
    // up in the table with no code change.
    if (action === 'whatsapp_send_code') {
      // SP-A-05, the same hole as verify_sms above (review of #858, 22 Sep 2026): this action sent a
      // billable Verify code to ANY 8+ digit number for a supplier, which is the first half of the
      // bypass that ended with a verified non-UAE number on the supplier record.
      const phone = kind === 'supplier' ? uaeMobile(b.phone) : toE164(String(b.phone || ''));
      if (kind === 'supplier' && !phone) return J({ ok: false, error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      if (!phone) return J({ ok: false, error: 'bad_phone', code: 'bad_phone' }, 400);
      // A reserved fixture number never reaches this line: the shared guard above (isDemoPhone, #681)
      // refuses it first, reading the phone exactly as `phone` is read here, so the number it checks is
      // the number sent to Twilio below.
      const tw = await twilioAuth();
      if (!tw) { await logRun('error', { action, kind }, 'WhatsApp code not sent: missing twilio_api_key_sid / secret / verify_service_sid'); return J({ ok: false, error: 'whatsapp_unavailable', code: 'whatsapp_unavailable' }, 200); }
      if (await phoneRateLimited(phone, email)) { await logRun('ok', { action, kind, rate_limited: true }, 'rate limit hit: 5+ code requests for this number in the last hour (SMS, call and WhatsApp share it)'); return J({ ok: false, error: 'rate_limited', code: 'rate_limited' }, 429); }
      if (!(await writeWa(askedPatch(new Date().toISOString())))) return saveFailed();
      const vLocale = await registeredLocale(admin, { role: kind, email }, b.lang);
      // ledger 1252: this code proves the number is on WhatsApp, so it is ours by the login_code template (USD 0.0157);
      // Verify (WhatsApp, then SMS on its template refusal) only when our send is not clean.
      const own = await sendOwnWhatsAppCode(waDeps, { phone, purpose: 'kyc_whatsapp', binding: email, kind, email, lang: vLocale });
      const res: VerifySent = own.ok ? ownSent(own.sid) : await sendWhatsAppFirst((ch) => verifySend(tw, phone, ch, vLocale));
      if (!res.ok) {
        await logRun('error', { action, kind, http: res.r.status, twilio_code: res.jd?.code ?? null, whatsapp_refused: res.refused }, 'twilio verify send failed' + (res.refused ? ' on SMS after WhatsApp was refused (' + res.refused + ')' : ' on channel whatsapp') + ': ' + String(res.jd?.message || res.jd?.status || '').slice(0, 200));
        return J({ ok: false, error: 'send_failed', code: 'send_failed', twilio_code: res.jd?.code ?? null }, 502);
      }
      // The row is the rate-limit ledger shared with send_sms, not a record of the number as the
      // account's WhatsApp - that is written only by whatsapp_verify.
      const marker = own.ok ? ownMarker(own.sid) : 'twilio:' + res.channel;
      const pv = await admin.from('phone_verifications').insert({ email, phone, code: marker, user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      if (pv.error) await logRun('error', { action, kind, stage: 'phone_verifications' }, 'WhatsApp code sent but the rate-limit row was not written: ' + pv.error.message);
      else await logRun('ok', { action, kind, channel: res.channel, whatsapp_refused: res.refused }, res.channel === 'whatsapp' ? '' : 'The WhatsApp-number code went by SMS: ' + (res.refused ? 'Verify refused the WhatsApp channel (' + res.refused + ')' : 'Verify accepted Channel=whatsapp and delivered by SMS itself') + '. Expected until Meta approves the Authentication template.');
      return J({ ok: true, channel: res.channel });
    }
    if (action === 'whatsapp_verify') {
      // SP-A-05. The reviewer named send_code and verify_sms; THIS action writes too — it puts the
      // number in leads.whatsapp_phone with whatsapp_verified_at set, so without the rule a supplier
      // record ends up with a verified non-UAE WhatsApp number even when leads.phone is clean.
      const phone = kind === 'supplier' ? uaeMobile(b.phone) : toE164(String(b.phone || ''));
      const code = String(b.code || '').replace(/\D/g, '');
      if (kind === 'supplier' && !phone) return J({ ok: false, error: 'Enter a valid UAE mobile number, for example 05X XXX XXXX.', code: 'bad_mobile' }, 400);
      if (!phone) return J({ ok: false, error: 'bad_phone', code: 'bad_phone' }, 400);
      if (!code) return J({ ok: false, error: 'wrong_code', code: 'wrong_code' }, 400);
      const tw = await twilioAuth();
      if (!tw) { await logRun('error', { action, kind }, 'WhatsApp code not checked: missing twilio credentials'); return J({ ok: false, error: 'whatsapp_unavailable', code: 'whatsapp_unavailable' }, 200); }
      if ((await checkOwnCode(waDeps, { phone, purpose: 'kyc_whatsapp', binding: email, code })) !== 'ok' && !(await verifyCheck(tw, phone, code))) return J({ ok: false, error: 'wrong_code', code: 'wrong_code' }, 400);
      const patch = verifiedPatch(phone, new Date().toISOString());
      if (!(await writeWa(patch))) return saveFailed();
      const used = await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
      if (used.error) await logRun('error', { action, kind, stage: 'phone_verifications' }, 'WhatsApp number verified but its phone_verifications rows were not marked used: ' + used.error.message);
      else await logRun('ok', { action, kind }, '');
      return J({ ok: true, whatsapp: whatsappState(patch as WhatsAppRow) });
    }
    if (action === 'whatsapp_later') {
      if (!(await writeWa(askedPatch(new Date().toISOString())))) return saveFailed();
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'accept_terms') {
      meta.fixture = isDemoEmail(email);
      // A customer cannot finish the account without an 18+ date of birth on file (account rule).
      if (kind === 'customer') { const dp = dobProblem((cust as any)?.date_of_birth); if (dp) return J({ error: dp, code: dp }, 400); }
      // THE WHATSAPP QUESTION IS PART OF SIGN-UP (founder, 15 Sep 2026: "It's in the sign up"). A
      // customer's FIRST acceptance is the end of sign-up, so it waits for the answer. A customer who
      // accepted before the question existed is not refused here (re-acceptance of a new version); the
      // dashboard asks them once instead. Suppliers are held at supplier_api save_profile, which is
      // where their sign-up completes.
      if (kind === 'customer' && !(cust as any)?.tos_accepted_at && !whatsappState(await readWa()).opt) return J({ error: 'whatsapp_unanswered', code: 'whatsapp_unanswered', message: 'Tell us whether your mobile is also your WhatsApp number first.' }, 400);
      const ip = clientIp(req);
      const nowIso = new Date().toISOString();
      // ONE SOURCE OF TRUTH FOR THE VERSION (2 Aug 2026, external code review). 'v4' and 'v3' were
      // hard-coded here, supplier_api read app_secrets('terms_version') (a key that did not exist,
      // so it recorded 'v2'), and compliance_archive printed "Version 4" on the certificate. Three
      // independent answers to "which document did this business actually sign?", which is the one
      // question an acceptance record exists to answer. All three now read the same secrets.
      const custV = (await sec('customer_terms_version')) || 'v3';
      // ONE ACCEPTANCE RECORD (15 Sep 2026). The portal records the supplier's acceptance through supplier_api
      // (version, IP, SHA-256 of the text) and then calls this to issue the certificate. Rewriting it here
      // replaced that record with one carrying no hash. It is written here only when the current version
      // is not already on file, and then through the same helper (_shared/supplier_terms.ts).
      if (kind === 'supplier') {
        // 2 Nov 2026 (ceo): an acceptance of a version the current one carries (a contact-only revision) stands
        // and is not rewritten, so no second acceptance and no second certificate (_shared/supplier_terms.ts).
        if (!(lead as any)?.accepted_terms_at || !(await supplierAcceptanceStands(sec, (lead as any)?.accepted_terms_version))) {
          // never a nameless FIRST acceptance (review of #1987, S5): the portal records it through supplier_api accept_terms with his full name
          if (acceptanceNeedsName(lead as { accepted_terms_at?: unknown; signatory_name?: unknown } | null, null)) return J({ ...FULL_NAME_REQUIRED }, 400);
          const rec = await supplierTermsRecord(sec, ip, req.headers.get('user-agent') || '');
          if (!rec) return J({ error: 'the current agreement version is not set', code: 'no_terms_version' }, 500);
          await admin.from('leads').update(rec).eq('claimed_by', email);
        }
      }
      else {
        // 6 Oct 2026 (release review of #1240): the SHA of the accepted text is recorded, as for suppliers
        // (_shared/customer_terms.ts). Written separately so a database without the column cannot fail the acceptance.
        // ONE ACCEPTANCE PER VERSION (12 Oct 2026, founder audit): a second accept_terms for the version already
        // on file (a double click, a retry: measured 51 s apart on 3 Oct) rewrote tos_accepted_at, and the later
        // acceptance time made compliance_archive issue a SECOND certificate for one acceptance. The record is
        // written only when this version is not yet accepted, exactly as for suppliers above.
        if (!(cust as any)?.tos_accepted_at || (cust as any)?.tos_version !== custV) {
          await admin.from('customers').update({ tos_accepted_at: nowIso, tos_version: custV, tos_ip: ip }).eq('email', email);
          const rec = await customerTermsRecord(sec, ip);
          if (rec && rec.tos_version === custV) await admin.from('customers').update({ tos_sha256: rec.tos_sha256 }).eq('email', email).then(() => null, () => null);
        }
        // PROMOTIONAL MESSAGES ARE OPT-IN (19 Oct 2026, founder, legal finding 2; seat: ceo). The separate, unticked
        // box beside the terms. Recorded only when it is exactly true; never required. Written on its own so a
        // database without the column cannot fail the acceptance. The outbox gate is
        // scripts/sql/promotional_messages_are_opt_in_and_the_outbox_checks_the_consent.sql.
        if (b.marketing_consent === true) await admin.from('customers').update({ marketing_consent: true, marketing_consent_at: nowIso, marketing_consent_source: 'signup' }).eq('email', email).then(() => null, () => null);
      }
      // A CUSTOMER'S CERTIFICATE IS ISSUED AFTER THE ANSWER (it_engineer, 29 Sep 2026, finding
      // duty:latency_slo:kyc:error_budget). Every one of the 12 over-budget kyc runs in 30 days was an
      // accept_terms waiting 2.9-12 s on compliance_archive rendering the signed PDF (6 customer, 5 supplier,
      // 1 unlabelled; server errors 0; all 12 on 28-29 Sep, when no real customer or supplier row recorded an acceptance). No
      // customer-side caller reads signed_url, so a customer is answered once the acceptance is RECORDED and the
      // render finishes in the background (EdgeRuntime.waitUntil, as the audit row). A failed render is still
      // logged 'error' exactly as before.
      const certify = (async () => {
        let signed_url = null; let signErr = '';
        try { const secret = await sec('cred_fn_kyc'); const r = await timedFetch(`${FN}/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, action: 'sign', kind, email }) }, 45_000); const jd = await r.json(); signed_url = jd?.signed_url || null; if (!signed_url) signErr = String(jd?.error || jd?.detail || 'no signed_url returned').slice(0, 200); } catch (e) { signErr = String((e as Error)?.message || e).slice(0, 200); }
        // terms acceptance is recorded either way; a missing signed PDF is a compliance-trail gap worth surfacing
        if (!signed_url) await logRun('error', { action, kind, terms_recorded: true, signed_pdf: false }, 'terms accepted but signed PDF not produced: ' + signErr);
        else await logRun('ok', { action, kind, terms_recorded: true, signed_pdf: true }, '');
        return signed_url;
      })();
      // NEITHER PARTY WAITS (E2E stage 1, D8, 30 Sep 2026). SupplierPortal calls this AFTER save_profile has
      // recorded the acceptance and only checks `ok`; supplier_api no longer polls for the PDF, and
      // z20_leads_mandatory_item_landed_reverifies verifies the supplier when signed_terms_path lands. So a
      // supplier, like a customer, is answered once the acceptance is recorded; a failed render is logged 'error'.
      const rt = (globalThis as any).EdgeRuntime;
      if (typeof rt?.waitUntil === 'function') { rt.waitUntil(certify); return J({ ok: true, signed_url: null, certificate: 'issuing' }); }
      return J({ ok: true, signed_url: await certify });
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m);
    // The raw message belongs in the log, never in the browser (the SP-I-01 rule, applied here too).
    return J({ error: 'Something went wrong. Please try again.', code: 'unexpected_error' }, 500); }
}
