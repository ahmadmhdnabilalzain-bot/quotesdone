// THE LAUNCH PATH, TESTED EVERY HOUR (21 Sep 2026, it_engineer). The supplier campaign launches ~23 Sep.
//
// WHAT WAS MISSING. The nightly journey (.github/workflows/nightly-journey.yml) runs once a day and the
// post-deploy smoke only after a merge. Between them nothing looked at the path a real invited supplier
// or a real customer takes, so a broken invitation page, a dead portal API or a sign-in endpoint that
// stopped answering would sit unseen for up to 24 hours in the middle of a campaign.
//
// WHAT THIS IS. The cheapest reading that proves each door on that path still opens, run hourly by
// resilience_ping (step `launchpath`, cadence in public.resilience_step) and by hand from
// scripts/e2e/launch_path.mjs, which imports THIS file — one list of probes, two callers.
//   1. the invitation link (/<lang>/portal?t=…) on www.quotesdone.com AND on the UAE host quotesdone.ae,
//      EN and AR: 200, an html page in that language (lang="ar" dir="rtl" for Arabic), no redirect loop
//   2. the customer's request page (/<lang>/me), EN and AR
//   3. the supplier portal API and the invitation lookup, pinned to the database region
//      (?forceFunctionRegion=ap-southeast-1, as src/lib/supaEnv.ts fnUrl does): each must ANSWER with its
//      own refusal — 401 unauthorized, 400 invalid_link — which proves the function booted and ran
//   4. the sign-in code request (login_otp send) for the reserved fixture mobile +971 50 000 0099
//   5. the five portal functions' health (the x-qd-warm door: 204 before auth or any DB read)
//
// WHY IT CANNOT REACH A PERSON OR WRITE A ROW (measured on production 21 Sep 2026, every answer below):
// - login_otp with an unregistered number answers 404 no_account BEFORE Twilio and writes nothing. If a
//   fixture ever registers that number the answer is FIXTURE_REFUSAL (isDemoPhone, before Twilio) —
//   also accepted. The EMAIL door is deliberately not probed: it inserts an email_verifications row and
//   hands a code to Resend even for @example.invalid.
// - claim_lookup gets a token that is not a UUID, so it refuses before reading leads. A well-formed
//   unknown UUID would write an agent_runs row whose note says "a run of these suggests a broken
//   outreach template" — an hourly probe would forge exactly that signal.
// - Pages are plain GETs; no JavaScript runs, so no client call is made from them.
// What it DOES leave: observe() records every 4xx as one `warn` agent_runs row (never paged, see
// _shared/observe.ts), so supplier_portal, claim_lookup and login_otp each gain one warn row an hour.
//
// WHAT IT DOES NOT PROVE. That a supplier can register or quote (scripts/e2e/supplier_registration_walk.mjs
// and the nightly journey do, with fixtures); that the page's JavaScript renders (no browser here); that a
// real code is delivered. It proves the doors answer, hourly, for the price of 14 requests.
//
// A FAILED PROBE IS RETRIED ONCE after RETRY_MS before it counts: a single dropped packet on an hourly
// check is not an incident, and every false alarm here costs the founder an email (263 in four days).

export type Probe = {
  id: string;
  url: string;
  init?: RequestInit;
  // null = pass, otherwise the reason it failed
  judge: (status: number, body: string, finalUrl: string, headers: Headers) => string | null;
};
export type ProbeResult = { id: string; ok: boolean; status: number; ms: number; why: string | null; retried: boolean };
export type LaunchPathResult = { ok: boolean; failed: ProbeResult[]; results: ProbeResult[]; ms: number };

export const SUPABASE_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
export const FN_REGION = 'ap-southeast-1';
export const HOSTS = ['https://www.quotesdone.com', 'https://quotesdone.ae'];
// A reserved fixture mobile (+971 50 000 00xx): _shared/demo_identity.ts isDemoPhone.
export const PROBE_MOBILE = '+971500000099';
const TIMEOUT_MS = 12_000;
const RETRY_MS = 3_000;

// The invitation is judged on the <html> tag the server rendered. Vercel sends a UAE caller from
// www.quotesdone.com to quotesdone.ae and drops the default /en prefix (both measured), so the final URL
// is judged on its path only, and a redirect loop surfaces as fetch's own "redirect count exceeded".
const page = (lang: 'en' | 'ar', path: string) =>
  (status: number, body: string, finalUrl: string): string | null => {
    if (status !== 200) return 'HTTP ' + status;
    const html = (body.match(/<html[^>]*>/i) || [''])[0];
    if (!html) return 'no <html> element in the response';
    if (!new RegExp(`lang="${lang}"`).test(html)) return `served ${html.slice(0, 120)} for /${lang}`;
    if (lang === 'ar' && !/dir="rtl"/.test(html)) return 'the Arabic page is not dir="rtl"';
    if (!new URL(finalUrl).pathname.includes(path)) return 'landed on ' + finalUrl;
    return null;
  };

const fnUrl = (name: string) => `${SUPABASE_URL}/functions/v1/${name}?forceFunctionRegion=${FN_REGION}`;
const post = (anon: string, body: unknown): RequestInit => ({
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + anon, apikey: anon },
  body: JSON.stringify(body),
});
const withProbe = (init: RequestInit, secret?: string): RequestInit =>
  secret ? { ...init, headers: { ...(init.headers as Record<string, string>), 'x-qd-probe': secret } } : init;
const json = (body: string): Record<string, unknown> => { try { return JSON.parse(body); } catch { return {}; } };

// An answer from a function the gateway ran somewhere other than the database region is a regression of
// the 21 Sep region pin (src/lib/supaEnv.ts): every serial DB hop crosses an ocean again.
const inRegion = (h: Headers): string | null => {
  const r = h.get('x-sb-edge-region');
  return r && r !== FN_REGION ? `ran in ${r}, not ${FN_REGION}` : null;
};

export function launchPathProbes(anon: string, probeSecret?: string): Probe[] {
  const probes: Probe[] = [];
  // Not a real claim token, and it does not need to be: the page is server-rendered the same for any t,
  // and a GET runs none of the client code that would look it up.
  const t = '00000000-0000-4000-8000-000000000000';
  for (const host of HOSTS) {
    for (const lang of ['en', 'ar'] as const) {
      probes.push({ id: `invite:${new URL(host).host}:${lang}`, url: `${host}/${lang}/portal?t=${t}`, judge: page(lang, 'portal') });
    }
  }
  for (const lang of ['en', 'ar'] as const) {
    probes.push({ id: `customer:${lang}`, url: `${HOSTS[0]}/${lang}/me`, judge: page(lang, 'me') });
  }
  probes.push({
    // probeSecret (resilience_ping's scoped credential) marks this deliberate 401 as our own traffic, so
    // refusal_rate does not count it (_shared/probe_caller.ts, incident 508). It proves nothing else: the
    // call is still unauthenticated and must still be refused.
    id: 'api:supplier_portal', url: fnUrl('supplier_portal'), init: withProbe(post(anon, { action: 'dashboard' }), probeSecret),
    judge: (s, b, _u, h) => (s === 401 && json(b).error === 'unauthorized' ? inRegion(h) : `HTTP ${s} ${b.slice(0, 120)}`),
  });
  probes.push({
    id: 'api:claim_lookup', url: fnUrl('claim_lookup'), init: withProbe(post(anon, { t: 'launch-path-probe' }), probeSecret),
    judge: (s, b, _u, h) => (s === 400 && json(b).error === 'invalid_link' ? inRegion(h) : `HTTP ${s} ${b.slice(0, 120)}`),
  });
  probes.push({
    id: 'signin:login_otp', url: fnUrl('login_otp'),
    init: post(anon, { action: 'send', identifier: PROBE_MOBILE, user_kind: 'supplier' }),
    judge: (s, b, _u, h) => {
      const j = json(b);
      if ((s === 404 && j.no_account === true) || j.code === 'fixture_number') return inRegion(h);
      // Anything else — above all a 200 ok — means this number reached a sending path. Say so loudly.
      return `HTTP ${s} ${b.slice(0, 120)}`;
    },
  });
  for (const fn of ['kyc', 'customer_api', 'customer_portal', 'project_api', 'messages_api', 'supplier_api', 'supplier_pay']) {  // supplier_portal and claim_lookup already have api: probes above
    probes.push({
      id: 'health:' + fn, url: fnUrl(fn), init: { method: 'GET', headers: { 'x-qd-warm': '1', Authorization: 'Bearer ' + anon } },
      judge: (s) => (s === 204 ? null : 'HTTP ' + s),
    });
  }
  return probes;
}

async function once(p: Probe, f: typeof fetch): Promise<{ status: number; why: string | null; ms: number }> {
  const t0 = Date.now();
  try {
    const r = await f(p.url, { redirect: 'follow', ...p.init, signal: AbortSignal.timeout(TIMEOUT_MS) });
    const body = await r.text();
    return { status: r.status, why: p.judge(r.status, body, r.url || p.url, r.headers), ms: Date.now() - t0 };
  } catch (e) {
    const err = e as Error & { cause?: { message?: string } };
    return { status: 0, why: String(err?.message || e) + (err?.cause?.message ? ': ' + err.cause.message : ''), ms: Date.now() - t0 };
  }
}

export async function probeLaunchPath(anon: string, f: typeof fetch = fetch, retryMs = RETRY_MS, probeSecret?: string): Promise<LaunchPathResult> {
  const t0 = Date.now();
  const probes = launchPathProbes(anon, probeSecret);
  const first = await Promise.all(probes.map((p) => once(p, f)));
  if (first.some((r) => r.why)) await new Promise((s) => setTimeout(s, retryMs));
  const results: ProbeResult[] = await Promise.all(probes.map(async (p, i) => {
    if (!first[i].why) return { id: p.id, ok: true, status: first[i].status, ms: first[i].ms, why: null, retried: false };
    const r = await once(p, f);
    return { id: p.id, ok: !r.why, status: r.status, ms: r.ms, why: r.why, retried: true };
  }));
  const failed = results.filter((r) => !r.ok);
  return { ok: failed.length === 0, failed, results, ms: Date.now() - t0 };
}

// WHAT THE TICK DOES WITH A RESULT — ONE finding, and it does not flap.
// 'raise'  a probe failed twice running: fn_it_duty_settle('launch_path', [the one item]) opens or bumps
//          duty:launch_path:down. One issue key for the whole path, so an outage of six doors is one
//          finding with six lines of evidence, not six emails.
// 'hold'   everything passed but the finding was last seen under HOLD_MS ago: leave it open. Closing on
//          the first clean hour and reopening on the next blip is how a reopened finding emails the
//          founder again as a RECURRENCE (fn_it_engineer_finding_upsert keeps alert_count on purpose).
// 'settle' everything passed and nothing recent is open: fn_it_duty_settle('launch_path', []) closes it.
export const HOLD_MS = 2 * 3600e3;
export function launchPathAction(ok: boolean, openLastSeenAt: string | null, now = Date.now()): 'raise' | 'hold' | 'settle' {
  if (!ok) return 'raise';
  if (openLastSeenAt && now - Date.parse(openLastSeenAt) < HOLD_MS) return 'hold';
  return 'settle';
}

export function launchPathItem(r: LaunchPathResult) {
  return {
    item: 'down',
    title: `The launch path is broken: ${r.failed.length} of ${r.results.length} hourly probes failed twice (${r.failed.map((x) => x.id).join(', ')})`.slice(0, 300),
    owner_seat: 'it_engineer', subject: 'launch_path', blast: 'customer_facing', affected: 0,
    evidence: {
      failed: r.failed.map((x) => ({ id: x.id, status: x.status, why: x.why })),
      probes: r.results.length,
      look_at: 'run `node scripts/e2e/launch_path.mjs` for the same probes from anywhere; supabase/functions/_shared/launch_path.ts says what each one asserts',
    },
  };
}
