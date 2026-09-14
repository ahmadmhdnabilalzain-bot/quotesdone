// The readings the IT engineer's duties need and Postgres cannot take: HTTP to the sites, GitHub,
// Vercel, Stripe and the providers. This module only MEASURES; public.fn_it_duties decides.
// (scripts/sql/the_it_engineer_runs_its_duties_every_hour.sql). No model call anywhere.
//
// Every reading carries a basis. A reading that could not be taken says so ('unavailable' + reason)
// and fn_it_duties then leaves that duty's findings as they were: "could not look" never reads as
// "all clear".
import { HANDLED_STRIPE_EVENTS } from './stripe_events.ts';

type Sec = (key: string) => Promise<string>;
type Got = { status: number; ok: boolean; json: unknown; error?: string };

const REPO = 'ahmadmhdnabilalzain-bot/quotesdone';
const ORIGINS = ['https://quotesdone.com', 'https://www.quotesdone.com', 'https://quotesdone.ae', 'https://www.quotesdone.ae'];
const DOMAINS = ['quotesdone.com', 'quotesdone.ae'];

async function get(url: string, init: RequestInit = {}): Promise<Got> {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
    const text = await r.text();
    let json: unknown = null;
    try { json = JSON.parse(text); } catch { /* not JSON: the status is the reading */ }
    return { status: r.status, ok: r.ok, json };
  } catch (e) {
    return { status: 0, ok: false, json: null, error: String((e as Error)?.message || e).slice(0, 200) };
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
async function expiries() {
  const out: Record<string, unknown> = {};
  await Promise.all(DOMAINS.map(async (dom) => {
    const r = await get(`https://rdap.org/domain/${dom}`);
    // deno-lint-ignore no-explicit-any
    const ev = (J(r)?.events ?? []).find((e: any) => e.eventAction === 'expiration');
    out[`domain:${dom}`] = ev ? { basis: 'measured', expires_on: String(ev.eventDate).slice(0, 10) }
                              : unavailable(`RDAP answered ${r.status || r.error} without an expiration event`);
    const c = await get(`https://crt.sh/?q=${dom}&output=json&exclude=expired`);
    const now = Date.now();
    // deno-lint-ignore no-explicit-any
    const valid = Array.isArray(J(c)) ? (J(c) as any[]).filter((x) => Date.parse(x.not_before) <= now) : [];
    const latest = valid.map((x) => String(x.not_after)).sort().pop();
    out[`tls:${dom}`] = latest ? { basis: 'measured', expires_on: latest.slice(0, 10) }
                               : unavailable(`crt.sh answered ${c.status || c.error} with no valid certificate`);
  }));
  return out;
}

// Does each provider credential still work today? A harmless authenticated GET per provider.
async function providers(sec: Sec) {
  const [sl, st, rs, tSid, tKey, tSec, dbKey, dbSecret, dbRefresh, gh] = await Promise.all([
    sec('stripe_secret_key'), sec('stripe_secret_key_test'), sec('resend_api_key'), sec('twilio_account_sid'),
    sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('dropbox_app_key'), sec('dropbox_app_secret'),
    sec('dropbox_refresh_token'), sec('github_token')]);
  const probe = async (owner_seat: string, present: boolean, run: () => Promise<Got>) => {
    if (!present) return { ...unavailable('credential not in app_secrets'), owner_seat };
    const g = await run();
    return { basis: g.status ? 'measured' : 'unavailable', status: g.status || null, owner_seat, error: g.error ?? null };
  };
  const bearer = (k: string) => ({ headers: { Authorization: `Bearer ${k}` } });
  return {
    stripe_live: await probe('accountant', !!sl, () => get('https://api.stripe.com/v1/balance', bearer(sl))),
    stripe_test: await probe('accountant', !!st, () => get('https://api.stripe.com/v1/balance', bearer(st))),
    resend: await probe('customer_support', !!rs, () => get('https://api.resend.com/domains', bearer(rs))),
    twilio: await probe('customer_support', !!(tSid && tKey && tSec), () =>
      get(`https://api.twilio.com/2010-04-01/Accounts/${tSid}.json`, { headers: { Authorization: 'Basic ' + btoa(`${tKey}:${tSec}`) } })),
    dropbox: await probe('sales_engineer', !!(dbKey && dbSecret && dbRefresh), async () => {
      const g = await get('https://api.dropboxapi.com/oauth2/token', { method: 'POST',
        body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: dbRefresh, client_id: dbKey, client_secret: dbSecret }) });
      // Dropbox answers a revoked refresh token with 400 invalid_grant: that is a refused credential.
      return J(g)?.error === 'invalid_grant' ? { ...g, status: 401 } : g;
    }),
    github: await probe('ceo', !!gh, () => get(`https://api.github.com/repos/${REPO}`, bearer(gh))),
  };
}

async function stripe(sec: Sec) {
  const since = Math.floor(Date.now() / 1000) - 72 * 3600;
  // A session younger than 15 minutes may still be on its way through the webhook.
  const settled = Math.floor(Date.now() / 1000) - 15 * 60;
  const mode = async (key: string) => {
    if (!key) return unavailable('no key in app_secrets');
    const h = { headers: { Authorization: `Bearer ${key}` } };
    const [s, r, w] = await Promise.all([
      get(`https://api.stripe.com/v1/checkout/sessions?status=complete&limit=100&created[gte]=${since}`, h),
      get(`https://api.stripe.com/v1/refunds?limit=100&created[gte]=${since}`, h),
      get('https://api.stripe.com/v1/webhook_endpoints?limit=100', h)]);
    if (!s.ok || !r.ok || !w.ok) return unavailable(`Stripe answered sessions ${s.status}, refunds ${r.status}, webhooks ${w.status}`);
    return {
      basis: 'measured',
      // deno-lint-ignore no-explicit-any
      paid_sessions: (J(s).data ?? []).filter((x: any) => x.payment_status === 'paid' && x.created <= settled)
        // deno-lint-ignore no-explicit-any
        .map((x: any) => ({ id: x.id, payment_intent: x.payment_intent, amount_total: x.amount_total, created: x.created })),
      // deno-lint-ignore no-explicit-any
      refunds: (J(r).data ?? []).filter((x: any) => x.created <= settled)
        // deno-lint-ignore no-explicit-any
        .map((x: any) => ({ id: x.id, payment_intent: x.payment_intent, amount: x.amount, status: x.status })),
      // deno-lint-ignore no-explicit-any
      webhooks: (J(w).data ?? []).map((x: any) => ({ url: x.url, status: x.status, enabled_events: x.enabled_events })),
    };
  };
  const [live, test] = await Promise.all([mode(await sec('stripe_secret_key')), mode(await sec('stripe_secret_key_test'))]);
  return { live, test, handled: [...HANDLED_STRIPE_EVENTS] };
}

export async function takeDutyReadings(sec: Sec) {
  const gh = await github(sec);
  const [v, s, e, p, st] = await Promise.all([
    vercel(sec, (gh as { sha?: string }).sha ?? null, (gh as { committed_at?: string }).committed_at ?? null),
    sites(), expiries(), providers(sec), stripe(sec)]);
  return { taken_at: new Date().toISOString(), github: gh, vercel: v, sites: s, expiries: e, providers: p, stripe: st };
}
