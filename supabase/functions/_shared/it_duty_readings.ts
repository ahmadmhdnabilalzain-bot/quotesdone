// The readings the IT engineer's duties need and Postgres cannot take: HTTP to the sites, GitHub,
// Vercel, Stripe and the providers. This module only MEASURES; the routines decide
// (scripts/sql/the_it_engineer_runs_its_duties_every_hour.sql, and for duties 20, 22 and 24 the files
// named at each section below). No model call anywhere.
//
// Every reading carries a basis. A reading that could not be taken says so ('unavailable' + reason)
// and the deciding routine then leaves that duty's findings as they were: "could not look" never
// reads as "all clear".
import { HANDLED_STRIPE_EVENTS } from './stripe_events.ts';
import { isDemoEmail } from './demo_identity.ts';
import tls from 'node:tls';
import { type OpenPr, stalePullRequests, staleCandidates } from './stale_pull_requests.ts';

type Sec = (key: string) => Promise<string>;
type Got = { status: number; ok: boolean; json: unknown; text: string; error?: string };

const REPO = 'ahmadmhdnabilalzain-bot/quotesdone';
const ORIGINS = ['https://quotesdone.com', 'https://www.quotesdone.com', 'https://quotesdone.ae', 'https://www.quotesdone.ae'];
const DOMAINS = ['quotesdone.com', 'quotesdone.ae'];

async function get(url: string, init: RequestInit = {}): Promise<Got> {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
    const text = await r.text();
    let json: unknown = null;
    try { json = JSON.parse(text); } catch { /* not JSON: the status (or the text) is the reading */ }
    return { status: r.status, ok: r.ok, json, text };
  } catch (e) {
    return { status: 0, ok: false, json: null, text: '', error: String((e as Error)?.message || e).slice(0, 200) };
  }
}
// deno-lint-ignore no-explicit-any
const J = (g: Got) => g.json as any;
const unavailable = (reason: string) => ({ basis: 'unavailable', reason });

async function github(sec: Sec) {
  const token = await sec('github_token');
  if (!token) return unavailable('app_secrets.github_token is empty');
  const h = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' };
  const c = await get(`https://api.github.com/repos/${REPO}/commits/main`, { headers: h });
  if (!c.ok) return unavailable(`GitHub commits/main answered ${c.status || c.error}`);
  const sha = J(c).sha as string;
  const runs = await get(`https://api.github.com/repos/${REPO}/commits/${sha}/check-runs?per_page=100`, { headers: h });
  if (!runs.ok) return unavailable(`GitHub check-runs answered ${runs.status || runs.error}`);
  const conclusions: Record<string, string> = {};
  for (const r of J(runs).check_runs ?? []) conclusions[r.name] = r.conclusion ?? r.status;
  return { basis: 'measured', sha, committed_at: J(c).commit?.committer?.date ?? null, conclusions };
}

async function vercel(sec: Sec, sha: string | null, committedAt: string | null) {
  if (!sha) return unavailable('no main commit was read');
  const [token, team, prj] = await Promise.all([sec('vercel_token'), sec('vercel_team_id'), sec('vercel_project_id')]);
  if (!token || !prj) return unavailable('app_secrets.vercel_token or vercel_project_id is empty');
  const q = `projectId=${encodeURIComponent(prj)}&target=production&limit=20` + (team ? `&teamId=${encodeURIComponent(team)}` : '');
  const r = await get(`https://api.vercel.com/v6/deployments?${q}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) return unavailable(`Vercel deployments answered ${r.status || r.error}`);
  // deno-lint-ignore no-explicit-any
  const d = (J(r).deployments ?? []).find((x: any) => x.meta?.githubCommitSha === sha);
  // A merge less than 30 minutes old may simply not have a deployment yet.
  const young = committedAt && Date.now() - Date.parse(committedAt) < 30 * 60 * 1000;
  return { basis: 'measured', sha, state: d ? (d.state ?? d.readyState) : (young ? 'QUEUED' : 'NOT_FOUND'), uid: d?.uid ?? null };
}

async function sites() {
  return Promise.all(ORIGINS.map(async (url) => {
    const t0 = Date.now();
    const g = await get(url, { redirect: 'manual' });
    return { url, status: g.status || null, ms: Date.now() - t0, error: g.error ?? null };
  }));
}

// Domain expiry from RDAP (rdap.org forwards to the registry's server); the certificate in service
// from crt.sh, as the latest not_after of certificates already valid.
// The Meta marketing token is NOT read here. Until 22 Sep 2026 duty 20 sent it to Meta's debug_token on
// every due run to learn its expiry. Founder rule 641 (22 Sep 2026): Meta and social are wired to no agent
// until the marketing seat exists, so the token is held for that seat, unread, and its renewal date is
// that seat's to watch. Recorded in public.company_policy_decision 'meta_and_social_held_for_marketing';
// scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs fails if a seat's code reads it.
async function expiries(_sec: Sec) {
  const out: Record<string, unknown> = {};
  await Promise.all(DOMAINS.map(async (dom) => {
    const r = await get(`https://rdap.org/domain/${dom}`);
    // deno-lint-ignore no-explicit-any
    const ev = (J(r)?.events ?? []).find((e: any) => e.eventAction === 'expiration');
    out[`domain:${dom}`] = ev ? { basis: 'measured', expires_on: String(ev.eventDate).slice(0, 10) }
                              : unavailable(`RDAP answered ${r.status || r.error} without an expiration event`);
    const served = await servedCertNotAfter(dom);
    const c = served ? null : await get(`https://crt.sh/?q=${dom}&output=json&exclude=expired`);
    out[`tls:${dom}`] = tlsExpiry(served, c ? J(c) : null, Date.now())
      ?? unavailable(`no TLS handshake reading, and crt.sh answered ${c?.status || c?.error} with no valid certificate`);
  }));
  return out;
}

// THE CERTIFICATE IN SERVICE IS THE ONE THE HANDSHAKE PRESENTS (it_engineer, 19 Oct 2026). Until then this read
// crt.sh only, which lags: on 19 Oct duty:expiry:tls said quotesdone.ae/.com expire 8-9 Nov while the served
// Let's Encrypt certs (renewed by Vercel 9-11 Oct) run to 7-9 Jan 2027. crt.sh is now only the fallback, and from
// it the newest not_after among certificates already valid. Returns an ISO not_after or null when unreadable.
export async function servedCertNotAfter(host: string, timeoutMs = 10000): Promise<string | null> {
  return await new Promise((resolve) => {
    let done = false;
    const finish = (v: string | null) => { if (!done) { done = true; clearTimeout(t); try { s.destroy(); } catch { /* closed */ } resolve(v); } };
    const t = setTimeout(() => finish(null), timeoutMs);
    const s = tls.connect({ host, port: 443, servername: host }, () => {
      const to = s.getPeerCertificate()?.valid_to; const ms = to ? Date.parse(to) : NaN;
      finish(Number.isFinite(ms) ? new Date(ms).toISOString() : null);
    });
    s.on('error', () => finish(null));
  });
}

/** The expiry reading: the served certificate when read, else the newest not_after of crt.sh rows valid at now. */
export function tlsExpiry(servedNotAfter: string | null, crtRows: unknown, now: number) {
  if (servedNotAfter) return { basis: 'measured', source: 'tls_handshake', expires_on: servedNotAfter.slice(0, 10) };
  // deno-lint-ignore no-explicit-any
  const rows = Array.isArray(crtRows) ? (crtRows as any[]) : [];
  const ms = rows.filter((x) => Date.parse(x?.not_before) <= now && Date.parse(x?.not_after) > now)
    .map((x) => Date.parse(x.not_after)).filter(Number.isFinite);
  return ms.length ? { basis: 'measured', source: 'crt.sh', expires_on: new Date(Math.max(...ms)).toISOString().slice(0, 10) } : null;
}

// THE PROVIDER CREDENTIAL PROBES MOVED (it_engineer, 24 Sep 2026, founder instruction 979). They were read here
// once an hour and filed as duty:credential. Every external integration is now one entry in
// integration_registry.json, probed every 15 minutes by integration_watch.ts and filed as duty:integration, so
// there is ONE owner. fn_it_duties leaves duty:credential untouched when the providers reading is absent.

// A REHEARSAL'S STRIPE OBJECT IS NOT A GAP IN THE BOOKS (15 Sep 2026, accountant).
// The e2e harness pays demo reveals with Stripe's TEST key, then its teardown deletes the demo
// transaction; the Stripe object stays, so every rehearsal left a permanent "Stripe took it, our books
// do not record it" finding. An object is a rehearsal only when BOTH hold:
//   - it lives in TEST mode — a LIVE object is never a rehearsal, whatever it carries; and
//   - its payer email is a reserved demo address (isDemoEmail, the same rule stripe_checkout uses
//     on the server to serve a demo account the test key and never the live one).
// Metadata is deliberately not consulted: the email comes from the signed-in account, not the browser.
// A test object with any other payer, or no email at all, is still reconciled and still raises.
export function isRehearsal(mode: 'live' | 'test', payerEmail: unknown): boolean {
  return mode === 'test' && isDemoEmail(payerEmail);
}
// deno-lint-ignore no-explicit-any
export const sessionPayer = (x: any) => x?.customer_details?.email ?? x?.customer_email ?? null;
// deno-lint-ignore no-explicit-any
export const refundPayer = (x: any) =>
  x?.charge?.billing_details?.email ?? x?.charge?.receipt_email ?? x?.charge?.customer?.email ?? null;

// Splits one mode's settled sessions and refunds into what the books must record and the rehearsals.
// `key` is the secret the objects were read with: the 'test' bucket is treated as test only when that
// key really is a Stripe test key, so a live key mis-stored under stripe_secret_key_test drops nothing.
// deno-lint-ignore no-explicit-any
export function splitRehearsals(name: 'live' | 'test', key: string, sessions: any[], refunds: any[]) {
  const m = name === 'test' && /^[sr]k_test_/.test(key) ? 'test' : 'live';
  // deno-lint-ignore no-explicit-any
  const rs = (x: any) => isRehearsal(m, sessionPayer(x)), rr = (x: any) => isRehearsal(m, refundPayer(x));
  return {
    sessions: sessions.filter((x) => !rs(x)), refunds: refunds.filter((x) => !rr(x)),
    rehearsal: { sessions: sessions.filter(rs).map((x) => x.id), refunds: refunds.filter(rr).map((x) => x.id) },
  };
}

async function stripe(sec: Sec) {
  const since = Math.floor(Date.now() / 1000) - 72 * 3600;
  // A session younger than 15 minutes may still be on its way through the webhook.
  const settled = Math.floor(Date.now() / 1000) - 15 * 60;
  const mode = async (name: 'live' | 'test', key: string) => {
    if (!key) return unavailable('no key in app_secrets');
    const h = { headers: { Authorization: `Bearer ${key}` } };
    const [s, r, w] = await Promise.all([
      get(`https://api.stripe.com/v1/checkout/sessions?status=complete&limit=100&created[gte]=${since}`, h),
      // The charge (and its customer) carries the payer's email a refund itself does not.
      get(`https://api.stripe.com/v1/refunds?limit=100&created[gte]=${since}&expand[]=data.charge.customer`, h),
      get('https://api.stripe.com/v1/webhook_endpoints?limit=100', h)]);
    if (!s.ok || !r.ok || !w.ok) return unavailable(`Stripe answered sessions ${s.status}, refunds ${r.status}, webhooks ${w.status}`);
    const split = splitRehearsals(name, key,
      // deno-lint-ignore no-explicit-any
      (J(s).data ?? []).filter((x: any) => x.payment_status === 'paid' && x.created <= settled),
      // deno-lint-ignore no-explicit-any
      (J(r).data ?? []).filter((x: any) => x.created <= settled));
    return {
      basis: 'measured',
      paid_sessions: split.sessions
        // deno-lint-ignore no-explicit-any
        .map((x: any) => ({ id: x.id, payment_intent: x.payment_intent, amount_total: x.amount_total, created: x.created })),
      refunds: split.refunds
        // deno-lint-ignore no-explicit-any
        .map((x: any) => ({ id: x.id, payment_intent: x.payment_intent, amount: x.amount, status: x.status })),
      // Kept in the reading as the record: rehearsal, no books expected.
      rehearsal: split.rehearsal,
      // deno-lint-ignore no-explicit-any
      webhooks: (J(w).data ?? []).map((x: any) => ({ url: x.url, status: x.status, enabled_events: x.enabled_events })),
    };
  };
  const [live, test] = await Promise.all([mode('live', await sec('stripe_secret_key')), mode('test', await sec('stripe_secret_key_test'))]);
  return { live, test, handled: [...HANDLED_STRIPE_EVENTS] };
}

export async function takeDutyReadings(sec: Sec) {
  const gh = await github(sec);
  const [v, s, e, st] = await Promise.all([
    vercel(sec, (gh as { sha?: string }).sha ?? null, (gh as { committed_at?: string }).committed_at ?? null),
    sites(), expiries(sec), stripe(sec)]);
  return { taken_at: new Date().toISOString(), github: gh, vercel: v, sites: s, expiries: e, stripe: st };
}

// ── DUTY 22: WHAT THE PROVIDERS BILL AGAINST, WHERE THEY PUBLISH IT ─────────────────────────────────
// fn_it_usage_watch (the_it_engineer_watches_every_bill_before_its_cap.sql) takes this. Supabase storage
// and the Resend send count are counted inside Postgres; Stripe has no cap to watch.

// Vercel's GET /v1/billing/charges answers FOCUS v1.3 as JSON Lines: one charge per line, BilledCost in
// BillingCurrency. Summed here; a line that does not parse is skipped and counted, never guessed.
export function sumFocusCharges(text: string): { total: number; currency: string | null; lines: number; unreadable: number } {
  let total = 0, lines = 0, unreadable = 0; let currency: string | null = null;
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const c = JSON.parse(line);
      const v = c.BilledCost === null || c.BilledCost === undefined || c.BilledCost === '' ? NaN : Number(c.BilledCost);
      if (Number.isFinite(v)) { total += v; lines++; currency = currency ?? (c.BillingCurrency ?? null); } else unreadable++;
    } catch { unreadable++; }
  }
  return { total: Math.round(total * 100) / 100, currency, lines, unreadable };
}

export async function takeUsageReadings(sec: Sec) {
  const [sid, kSid, kSec, vTok, vTeam] = await Promise.all([
    sec('twilio_account_sid'), sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('vercel_token'), sec('vercel_team_id')]);
  let twilio: Record<string, unknown> = unavailable('twilio_account_sid, twilio_api_key_sid or twilio_api_key_secret is empty');
  if (sid && kSid && kSec) {
    const g = await get(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Balance.json`,
      { headers: { Authorization: 'Basic ' + btoa(`${kSid}:${kSec}`) } });
    const b = Number(J(g)?.balance);
    twilio = g.ok && Number.isFinite(b) ? { basis: 'measured', balance: b, currency: J(g)?.currency ?? null }
                                        : unavailable(`Twilio Balance answered ${g.status || g.error}`);
  }
  let vercel: Record<string, unknown> = unavailable('app_secrets.vercel_token is empty');
  if (vTok) {
    const now = new Date();
    const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const q = `from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(now.toISOString())}`
            + (vTeam ? `&teamId=${encodeURIComponent(vTeam)}` : '');
    const g = await get(`https://api.vercel.com/v1/billing/charges?${q}`, { headers: { Authorization: `Bearer ${vTok}` } });
    if (g.ok) {
      const s = sumFocusCharges(g.text);
      vercel = { basis: 'measured', charges_month: s.total, currency: s.currency, lines: s.lines, unreadable: s.unreadable };
    } else {
      vercel = unavailable(`Vercel billing/charges answered ${g.status || g.error} (the token may carry no billing scope)`);
    }
  }
  return { taken_at: new Date().toISOString(), twilio, vercel };
}

// ── DUTY 24: IS A SIGNED REVISION REVIEWED? ─────────────────────────────────────────────────────────
// fn_it_change_revisions_record (a_routine_change_nobody_signed_is_a_finding_within_minutes.sql) takes
// this. Reviewed means an ancestor of main, or part of a pull request merged into main: the repository
// merges by squash, so the commit a worktree applied from is rarely itself on main. An answer GitHub did
// not give leaves verdict null, and the revision is asked again next tick.
export async function verifyRevisions(sec: Sec, revs: string[]) {
  if (!revs.length) return [];
  const token = await sec('github_token');
  if (!token) return revs.map((rev) => ({ rev, verdict: null, detail: { reason: 'app_secrets.github_token is empty' } }));
  const h = { headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' } };
  return Promise.all(revs.map(async (rev) => {
    const c = await get(`https://api.github.com/repos/${REPO}/compare/main...${rev}`, h);
    if (c.ok && ['behind', 'identical'].includes(J(c)?.status)) return { rev, verdict: 'on_main' };
    const p = await get(`https://api.github.com/repos/${REPO}/commits/${rev}/pulls`, h);
    if (p.ok && Array.isArray(J(p))) {
      // deno-lint-ignore no-explicit-any
      const prs = J(p) as any[];
      const merged = prs.find((x) => x.merged_at && x.base?.ref === 'main');
      if (merged) return { rev, verdict: 'merged_pr', pr_number: merged.number };
      const open = prs.find((x) => x.state === 'open' && x.base?.ref === 'main');
      if (open) return { rev, verdict: 'open_pr', pr_number: open.number };
    }
    // Only clean answers about the commit count as "not on main"; an outage or a 401 leaves it pending.
    const answered = (g: Got) => g.ok || g.status === 404 || g.status === 422;
    const detail = { compare: c.status || c.error, compare_status: J(c)?.status ?? null, pulls: p.status || p.error };
    return answered(c) && answered(p) ? { rev, verdict: 'not_on_main', detail } : { rev, verdict: null, detail };
  }));
}

// ── DUTY 25: WHICH OPEN PULL REQUESTS HAVE BEEN LEFT ALONE? ─────────────────────────────────────────
// fn_it_open_pull_requests_record (an_open_pull_request_nobody_touched_for_two_days_is_a_finding.sql) takes this.
// The same GitHub token and repository as verifyRevisions above; the decision itself is stale_pull_requests.ts (pure,
// tested). Every open pull request is listed (up to 10 pages of 100); the files of the STALE ones only are read, to say
// whether SQL is waiting. A list that could not be read in full is 'unavailable', never a short list: the routine closes
// a finding whose pull request is missing from the reading, so a partial list would close real findings.
export async function takeOpenPullRequests(sec: Sec, now = Date.now()) {
  const token = await sec('github_token');
  if (!token) return unavailable('app_secrets.github_token is empty');
  const h = { headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' } };
  const prs: OpenPr[] = [];
  for (let page = 1; page <= 10; page++) {
    const g = await get(`https://api.github.com/repos/${REPO}/pulls?state=open&per_page=100&page=${page}`, h);
    if (!g.ok || !Array.isArray(J(g))) return unavailable(`GitHub pulls (open, page ${page}) answered ${g.status || g.error}`);
    prs.push(...(J(g) as OpenPr[]));
    if ((J(g) as unknown[]).length < 100) break;
    if (page === 10) return unavailable('more than 1000 open pull requests: the list was not read in full');
  }
  const filesByNumber: Record<number, string[] | null> = {};
  await Promise.all(staleCandidates(prs, now).map(async (p) => {
    const names: string[] = [];
    for (let page = 1; page <= 10; page++) {
      const f = await get(`https://api.github.com/repos/${REPO}/pulls/${p.number}/files?per_page=100&page=${page}`, h);
      if (!f.ok || !Array.isArray(J(f))) { filesByNumber[p.number] = null; return; }   // unreadable: the flag is null
      // deno-lint-ignore no-explicit-any
      names.push(...(J(f) as any[]).map((x) => String(x.filename)));
      if ((J(f) as unknown[]).length < 100) break;
    }
    filesByNumber[p.number] = names;
  }));
  return {
    basis: 'measured', taken_at: new Date(now).toISOString(), open_count: prs.length,
    stale: stalePullRequests(prs, now, filesByNumber),
  };
}
