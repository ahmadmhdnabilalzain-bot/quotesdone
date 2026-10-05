// THE IT ENGINEER'S INTEGRATION WATCH (it_engineer, 24 Sep 2026, founder instruction 979).
//
// "The IT engineer should have been notified when Facebook disconnected from Postiz, and about any similar
// issue" — widened the same day to every external service the company depends on. The list is DATA:
// integration_registry.json, one entry per integration. This module runs each entry's probe, tries the fix it
// can make itself, and returns the settle items for fn_it_integration_settle (duty 'integration'), which files
// one finding per integration by its exact key and closes it by that key when the probe passes again.
//
// WHAT EACH OUTCOME MEANS
//   ok                     nothing is filed; an open finding for it closes on this beat
//   fixed                  the probe failed, the fix worked, the re-probe passed: no finding, a self-fix row for
//                          the IT daily line (fn_it_daily_line counts them) and nothing to the founder
//   failing                a finding with what broke, what was tried, and the action and link a person needs
//   not measured (carried) the probe could not run (a secret missing is NOT this: that is a failure); an open
//                          finding is held as it stands, never closed on a reading nobody took
// 'marketing' entries are measured by the marketing seat's beat (rule 641: only it reads Meta/Postiz
// credentials) and 'covered' entries by the duty named in the registry, so this is never a second owner.
// No model call. Every fetch is injected so integration_watch.test.ts replays providers offline.
import registry from './integration_registry.json' with { type: 'json' };

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
type Sec = (k: string) => Promise<string>;
type Env = (k: string) => string | undefined;
export interface Probe { kind: string; method?: string; url?: string; auth?: string; ok?: number[]; expect?: { path: string; equals: string };
  every_minutes?: number; name?: string; secret?: string; function?: string; notify?: boolean }
export interface Entry { what: string; owner_seat: string; blast: string; probe: Probe; action?: string; link?: string; self_fix?: string;
  notify_founder?: boolean; notify_why?: string; secrets?: string[] }
export const REGISTRY = registry as unknown as { integrations: Record<string, Entry> };

export interface Outcome { integration: string; state: 'ok' | 'fixed' | 'failing' | 'not_measured'; what_broke?: string; tried: string[]; detail?: unknown }

/** Is this entry due on the beat that starts at `now`? 15-minute beats; an hourly entry runs on one beat in four. */
export function isDue(p: Probe, now: Date): boolean {
  const every = Math.max(15, p.every_minutes ?? 15);
  return Math.floor(now.getTime() / 900_000) % Math.round(every / 15) === 0;
}

async function fill(tpl: string, sec: Sec, env: Env): Promise<{ s: string; missing: string[] }> {
  const missing: string[] = [];
  let s = tpl;
  for (const m of [...tpl.matchAll(/\{(secret|env):([A-Za-z0-9_]+)\}/g)]) {
    const v = m[1] === 'secret' ? await sec(m[2]) : env(m[2]);
    if (!v) missing.push(m[1] === 'secret' ? 'app_secrets.' + m[2] : 'env ' + m[2]);
    s = s.replace(m[0], v || '');
  }
  return { s, missing };
}

async function headers(auth: string | undefined, sec: Sec, env: Env): Promise<{ h: Record<string, string>; missing: string[] }> {
  const a = (auth || 'none').split(':');
  const need = async (k: string) => (await sec(k)) || '';
  if (a[0] === 'none') return { h: {}, missing: [] };
  if (a[0] === 'bearer') { const v = await need(a[1]); return { h: { Authorization: 'Bearer ' + v }, missing: v ? [] : ['app_secrets.' + a[1]] }; }
  if (a[0] === 'basic') {
    const [u, p] = [await need(a[1]), await need(a[2])];
    return { h: { Authorization: 'Basic ' + btoa(u + ':' + p) }, missing: [!u && 'app_secrets.' + a[1], !p && 'app_secrets.' + a[2]].filter(Boolean) as string[] };
  }
  if (a[0] === 'header') { const v = await need(a[2]); return { h: { [a[1]]: v }, missing: v ? [] : ['app_secrets.' + a[2]] }; }
  if (a[0] === 'apikey') { const v = env(a[1]) || ''; return { h: { apikey: v, Authorization: 'Bearer ' + v }, missing: v ? [] : ['env ' + a[1]] }; }
  throw new Error('unknown auth ' + auth);
}

const pick = (j: unknown, path: string) => path.split('.').reduce<any>((o, k) => (o == null ? o : o[k]), j);

/** One generic HTTP probe. Returns null when it passed, else what broke. A network error is "unreachable". */
async function httpOnce(f: Fetch, p: Probe, sec: Sec, env: Env): Promise<{ broke: string | null; missing: string[] }> {
  const u = await fill(p.url || '', sec, env);
  const a = await headers(p.auth, sec, env);
  const missing = [...u.missing, ...a.missing];
  if (missing.length) return { broke: 'not configured: ' + missing.join(', ') + ' is empty', missing };
  try {
    const r = await f(u.s, { method: p.method || 'GET', headers: a.h, signal: AbortSignal.timeout(12000) });
    const text = await r.text();
    if (!(p.ok || [200]).includes(r.status)) return { broke: `answered HTTP ${r.status}${text ? ': ' + text.slice(0, 120).replace(/\s+/g, ' ') : ''}`, missing };
    if (p.expect) {
      let j: unknown = null; try { j = JSON.parse(text); } catch { /* not JSON */ }
      const got = pick(j, p.expect.path);
      if (String(got) !== p.expect.equals) return { broke: `${p.expect.path} is ${JSON.stringify(got ?? null)}, expected ${p.expect.equals}`, missing };
    }
    return { broke: null, missing };
  } catch (e) {
    return { broke: 'unreachable: ' + String((e as Error)?.message || e).slice(0, 120), missing };
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── the coded probes: the few that need more than one call or carry their own fix ─────────────────────
type Custom = (f: Fetch, p: Probe, sec: Sec, env: Env) => Promise<Omit<Outcome, 'integration'>>;
export const CUSTOM: Record<string, Custom> = {
  // A Stripe endpoint pointing at stripe_webhook that Stripe DISABLED (it does after days of failures) is
  // re-enabled: the one fix here that changes a provider's configuration, and only back to what we set.
  async stripe_webhook(f, p, sec) {
    const key = await sec(p.secret || 'stripe_secret_key');
    if (!key) return { state: 'failing', what_broke: 'not configured: app_secrets.stripe_secret_key is empty', tried: [] };
    const h = { Authorization: 'Bearer ' + key };
    const r = await f('https://api.stripe.com/v1/webhook_endpoints?limit=100', { headers: h, signal: AbortSignal.timeout(12000) }).catch(() => null);
    if (!r || !r.ok) return { state: 'not_measured', tried: [], detail: { status: r?.status ?? null } };
    const ours = ((await r.json()).data || []).filter((x: any) => String(x.url || '').includes('/functions/v1/' + (p.function || 'stripe_webhook')));
    if (!ours.length) return { state: 'failing', what_broke: 'no Stripe webhook endpoint points at stripe_webhook', tried: [] };
    if (ours.some((x: any) => x.status === 'enabled')) return { state: 'ok', tried: [] };
    const tried: string[] = [];
    for (const x of ours) {
      const u = await f('https://api.stripe.com/v1/webhook_endpoints/' + x.id, { method: 'POST', headers: { ...h, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'disabled=false', signal: AbortSignal.timeout(12000) }).catch(() => null);
      tried.push(`re-enabled endpoint ${x.id}: HTTP ${u?.status ?? 'unreachable'}`);
      if (u?.ok && (await u.json())?.status === 'enabled') return { state: 'fixed', what_broke: `endpoint ${x.id} was disabled by Stripe`, tried };
    }
    return { state: 'failing', what_broke: 'every Stripe endpoint pointing at stripe_webhook is disabled', tried };
  },
  async twilio_wa_sender(f, _p, sec) {
    const [kSid, kSec, from] = [await sec('twilio_api_key_sid'), await sec('twilio_api_key_secret'), await sec('twilio_wa_from')];
    if (!kSid || !kSec || !from) return { state: 'failing', what_broke: 'not configured: a Twilio API key or twilio_wa_from is empty', tried: [] };
    const r = await f('https://messaging.twilio.com/v2/Channels/Senders?Channel=whatsapp&PageSize=50',
      { headers: { Authorization: 'Basic ' + btoa(kSid + ':' + kSec) }, signal: AbortSignal.timeout(12000) }).catch(() => null);
    if (!r || !r.ok) return { state: r ? 'failing' : 'not_measured', what_broke: r ? 'Twilio Senders answered HTTP ' + r.status : undefined, tried: [] };
    const digits = from.replace(/\D/g, '');
    const s = ((await r.json()).senders || []).find((x: any) => String(x.sender_id || '').replace(/\D/g, '') === digits);
    if (!s) return { state: 'failing', what_broke: `no WhatsApp sender for +${digits} in the Twilio account`, tried: [] };
    return s.status === 'ONLINE' ? { state: 'ok', tried: [] } : { state: 'failing', what_broke: `the WhatsApp sender +${digits} is ${s.status}, not ONLINE`, tried: [] };
  },
  // 11200 / 11205: Twilio could not fetch our webhook URL. A monitor read of the last hour.
  async twilio_webhook_errors(f, _p, sec) {
    const [sid, kSid, kSec] = [await sec('twilio_account_sid'), await sec('twilio_api_key_sid'), await sec('twilio_api_key_secret')];
    if (!sid || !kSid || !kSec) return { state: 'failing', what_broke: 'not configured: a Twilio API key is empty', tried: [] };
    const since = new Date(Date.now() - 3600_000).toISOString();
    const r = await f('https://monitor.twilio.com/v1/Alerts?PageSize=50&StartDate=' + encodeURIComponent(since),
      { headers: { Authorization: 'Basic ' + btoa(kSid + ':' + kSec) }, signal: AbortSignal.timeout(12000) }).catch(() => null);
    if (!r || !r.ok) return { state: 'not_measured', tried: [], detail: { status: r?.status ?? null } };
    const bad = ((await r.json()).alerts || []).filter((x: any) => ['11200', '11205'].includes(String(x.error_code)));
    return bad.length ? { state: 'failing', what_broke: `${bad.length} Twilio webhook call(s) in the last hour could not reach our endpoint (error ${bad[0].error_code})`,
                         tried: [], detail: { urls: [...new Set(bad.map((x: any) => x.request_url).filter(Boolean))].slice(0, 5) } }
                      : { state: 'ok', tried: [] };
  },
  async dropbox_refresh(f, _p, sec) {
    const [k, s, t] = [await sec('dropbox_app_key'), await sec('dropbox_app_secret'), await sec('dropbox_refresh_token')];
    if (!k || !s || !t) return { state: 'failing', what_broke: 'not configured: a Dropbox app key, secret or refresh token is empty', tried: [] };
    const r = await f('https://api.dropboxapi.com/oauth2/token', { method: 'POST', signal: AbortSignal.timeout(12000),
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: t, client_id: k, client_secret: s }) }).catch(() => null);
    if (!r) return { state: 'not_measured', tried: [] };
    const j = await r.json().catch(() => ({})) as any;
    return r.ok && j.access_token ? { state: 'ok', tried: ['minted a fresh access token from the refresh token'] }
      : { state: 'failing', what_broke: `Dropbox refused the refresh token (HTTP ${r.status}${j.error ? ', ' + j.error : ''})`, tried: ['token refresh'] };
  },
};

/** Run one entry: probe; on failure retry once (the self-fix every entry has), then report. */
export async function runEntry(f: Fetch, key: string, e: Entry, sec: Sec, env: Env, wait = sleep): Promise<Outcome> {
  if (e.probe.kind === 'custom') {
    const c = CUSTOM[e.probe.name || ''];
    if (!c) return { integration: key, state: 'failing', what_broke: 'the registry names a custom probe that does not exist: ' + e.probe.name, tried: [] };
    let o = await c(f, e.probe, sec, env);
    if (o.state === 'failing' && !/^not configured/.test(o.what_broke || '')) {
      await wait(3000);
      const again = await c(f, e.probe, sec, env);
      if (again.state === 'ok') return { integration: key, state: 'fixed', what_broke: o.what_broke, tried: [...o.tried, 'retried after 3 s: passed'] };
      o = { ...again, tried: [...o.tried, 'retried after 3 s: still failing', ...again.tried] };
    }
    return { integration: key, ...o };
  }
  const first = await httpOnce(f, e.probe, sec, env);
  if (!first.broke) return { integration: key, state: 'ok', tried: [] };
  if (first.missing.length) return { integration: key, state: 'failing', what_broke: first.broke, tried: [] };
  await wait(3000);
  const second = await httpOnce(f, e.probe, sec, env);
  if (!second.broke) return { integration: key, state: 'fixed', what_broke: first.broke, tried: ['retried after 3 s: passed'] };
  return { integration: key, state: 'failing', what_broke: second.broke, tried: ['retried after 3 s: still failing'] };
}

/**
 * Whether a failing integration may reach the founder at all (5 Oct 2026, notifications#84149: the keyless
 * DuckDuckGo scrape was sent to him as a DECISION "only its account holder can restore"). A keyless endpoint (an
 * http probe with no auth and no registry secret) has no account holder, so it is always the IT engineer's.
 * Account-backed connections (an auth on the probe, a secret, or a custom probe of a provider account) keep the
 * registry's own opt-outs. Measured on the registry that day: this changes no entry except a keyless one.
 */
export function founderMayBeAsked(e: { secrets?: string[]; notify_founder?: boolean; probe: Probe }): boolean {
  const keyless = !(e.secrets?.length) && e.probe.kind === 'http' && (e.probe.auth ?? 'none') === 'none';
  return !keyless && e.notify_founder !== false && e.probe.notify !== false;
}

/** The settle items for every due entry. Entries not due this beat are CARRIED (held as they stand). */
export async function integrationItems(f: Fetch, sec: Sec, env: Env, now = new Date(), wait = sleep, reg = REGISTRY) {
  const items: Record<string, unknown>[] = [];
  const outcomes: Outcome[] = [];
  const entries = Object.entries(reg.integrations).filter(([, e]) => e.probe.kind === 'http' || e.probe.kind === 'custom');
  await Promise.all(entries.map(async ([key, e]) => {
    const base = { item: key, owner_seat: e.owner_seat, subject: key, blast: e.blast, affected: 1 };
    if (!isDue(e.probe, now)) { items.push({ ...base, title: 'not measured this beat', evidence: {}, carried: true }); return; }
    const o = await runEntry(f, key, e, sec, env, wait).catch((err) =>
      ({ integration: key, state: 'not_measured', tried: [], detail: String((err as Error)?.message || err) }) as Outcome);
    outcomes.push(o);
    if (o.state === 'not_measured') { items.push({ ...base, title: 'not measured this beat', evidence: {}, carried: true }); return; }
    // A SUCCESSFUL RE-PROBE is the only proof of recovery. It is sent as a recovered item (never a failure):
    // fn_it_integration_settle strips it before settling and stamps evidence.recovered = true on the closed
    // finding, which is the one thing allowed to close a known external cause (review of #935).
    if (o.state === 'ok' || o.state === 'fixed') { items.push({ ...base, title: 'answers again', evidence: { recovered: true }, recovered: true }); return; }
    if (o.state === 'failing') {
      items.push({ ...base,
        title: `${key} (${e.what}): ${o.what_broke}. Tried: ${o.tried.length ? o.tried.join('; ') : 'nothing the company can do itself'}. Needs: ${e.action || 'see the registry'}${e.link ? ' ' + e.link : ''}`,
        evidence: { integration: key, what_broke: o.what_broke, tried: o.tried, action: e.action ?? null, reconnect_url: e.link ?? null,
                    notify: founderMayBeAsked(e), notify_why: e.notify_why ?? null, detail: o.detail ?? null } });
    }
  }));
  const fixed = outcomes.filter((o) => o.state === 'fixed').map((o) => ({ integration: o.integration, what_broke: o.what_broke, tried: o.tried }));
  return { items, fixed, outcomes };
}
