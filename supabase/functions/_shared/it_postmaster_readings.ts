// GMAIL POSTMASTER TOOLS, READ ONCE A DAY FOR THE IT ENGINEER (it_engineer, 24 Sep 2026).
//
// WHAT WAS MEASURED BEFORE WRITING: quotesdone.com is verified in Google Postmaster Tools, and nothing in the
// estate read it. The sender duty (it_scheduled_readings.ts, duty 10) reads DNS, blocklists and Resend's domain
// status; the same-day brake (an_invitation_bounce_or_complaint_spike_stops_the_campaign_the_same_hour.sql, PR #943)
// reads OUR bounce and complaint webhooks. Neither sees what Gmail itself measures: the user-reported spam rate and
// the domain reputation, the two numbers Gmail's bulk-sender rules are enforced on (spam rate under 0.3%, aim
// under 0.1%).
//
// WHICH API VERSION, measured 24 Sep 2026 from Google's discovery directory (googleapis.com/discovery/v1/apis,
// revision 20260922): v1beta1, v1 and v2 are all served, and v2 is the PREFERRED version. This reads v1 on
// purpose: v2's domainStats:query offers SPAM_RATE and AUTH_SUCCESS_RATE but has NO domain reputation metric,
// and domainReputation (HIGH/MEDIUM/LOW/BAD) is half of what this duty is for. v1 is not marked deprecated in its
// discovery document. v1 takes scope postmaster.readonly; v2 does not accept that scope (it wants postmaster or
// postmaster.traffic.readonly), so a move to v2 is also a new consent.
//
// WHAT THIS MODULE DOES: measures, judges and writes the digest line. Deterministic code, no model call.
//   * takePostmasterReading: one token refresh + one GET of v1/domains/<domain>/trafficStats for the last 7 days
//     (the list form of /trafficStats/{YYYYMMDD}: one call instead of seven), newest day wins.
//   * parseTrafficStats: an absent field is null, NEVER zero. Postmaster publishes a day 1-2 days late and
//     publishes nothing below its volume threshold; "no data" is a reading of its own, not a clean result.
//   * judge: spam >= 0.1% is a finding; spam >= 0.3% (Gmail's hard limit) or reputation LOW/BAD also pauses the
//     invitation campaign through the #943 mechanism (public.fn_invite_campaign_pause). The database acts on the
//     verdict; public.fn_it_postmaster_record owns the storing, the finding and the pause.
//   * digestLine: the one sentence the IT daily line to the CEO carries.
//
// CREDENTIAL, the Google pattern this repository already holds (marketing_social_oauth.ts, the YouTube connect):
// app_secrets.google_oauth_client_id and google_oauth_client_secret are the OAuth client; the refresh token for the
// Postmaster scope is app_secrets.google_postmaster_refresh_token, exchanged at oauth2.googleapis.com/token for a
// short-lived access token on every read (the Dropbox reading does the same with dropbox_refresh_token). Nothing
// returned from here is a secret.
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
type Sec = (key: string) => Promise<string | undefined>;

export const POSTMASTER_DOMAIN = 'quotesdone.com';
export const POSTMASTER_SCOPE = 'https://www.googleapis.com/auth/postmaster.readonly';
export const SECRET_KEYS = { id: 'google_oauth_client_id', secret: 'google_oauth_client_secret', refresh: 'google_postmaster_refresh_token' } as const;
// Gmail's bulk-sender guidance: keep the user-reported spam rate under 0.1%, never reach 0.3%.
export const SPAM_FINDING_RATIO = 0.001;
export const SPAM_PAUSE_RATIO = 0.003;
export const PAUSE_REPUTATIONS = ['LOW', 'BAD'] as const;
export const NO_DATA = 'no data (volume below Postmaster threshold or not yet published)';
const LOOKBACK_DAYS = 7;

export type Reputation = 'HIGH' | 'MEDIUM' | 'LOW' | 'BAD';
export interface Verdict { finding: boolean; pause: boolean; reasons: string[] }
export interface PostmasterReading {
  domain: string;
  basis: 'measured' | 'no_data' | 'unavailable';
  stats_day: string | null;            // YYYY-MM-DD the numbers belong to (Postmaster's day, not the read day)
  spam_ratio: number | null;           // userReportedSpamRatio; the midpoint when bounds are present
  spam_lower: number | null;           // userReportedSpamRatioLowerBound
  spam_upper: number | null;           // userReportedSpamRatioUpperBound
  reputation: Reputation | null;       // domainReputation; UNSPECIFIED is null
  spf: number | null; dkim: number | null; dmarc: number | null;   // success ratios, 0..1
  reason: string | null;               // why it is no_data or unavailable
  verdict: Verdict;
  line: string;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const REPS = new Set(['HIGH', 'MEDIUM', 'LOW', 'BAD']);
const rep = (v: unknown): Reputation | null => (typeof v === 'string' && REPS.has(v) ? v as Reputation : null);

// 'domains/quotesdone.com/trafficStats/20260922' -> '2026-09-22'
export function statsDay(name: unknown): string | null {
  const m = String(name ?? '').match(/\/trafficStats\/(\d{4})(\d{2})(\d{2})$/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

type Measured = Omit<PostmasterReading, 'verdict' | 'line'>;
const empty = (domain: string, basis: 'no_data' | 'unavailable', reason: string, stats_day: string | null = null): Measured =>
  ({ domain, basis, stats_day, spam_ratio: null, spam_lower: null, spam_upper: null, reputation: null,
     spf: null, dkim: null, dmarc: null, reason });

/** The newest day in a v1 ListTrafficStatsResponse (or a single TrafficStats from /trafficStats/{day}). */
export function parseTrafficStats(domain: string, json: unknown): Measured {
  const j = (json ?? {}) as Record<string, unknown>;
  const rows = (Array.isArray(j.trafficStats) ? j.trafficStats : (j.name ? [j] : [])) as Record<string, unknown>[];
  const dated = rows.map((r) => ({ r, day: statsDay(r.name) })).filter((x) => x.day)
    .sort((a, b) => String(b.day).localeCompare(String(a.day)));
  if (!dated.length) return empty(domain, 'no_data', NO_DATA);
  const { r, day } = dated[0];
  const m: Measured = {
    domain, basis: 'measured', stats_day: day, reason: null,
    spam_ratio: num(r.userReportedSpamRatio), spam_lower: num(r.userReportedSpamRatioLowerBound),
    spam_upper: num(r.userReportedSpamRatioUpperBound), reputation: rep(r.domainReputation),
    spf: num(r.spfSuccessRatio), dkim: num(r.dkimSuccessRatio), dmarc: num(r.dmarcSuccessRatio),
  };
  // A day row that carries none of the numbers this duty reads is the below-threshold shape, not a clean day.
  if ([m.spam_ratio, m.reputation, m.spf, m.dkim, m.dmarc].every((v) => v === null)) return empty(domain, 'no_data', NO_DATA, day);
  return m;
}

export function judge(m: Measured): Verdict {
  const reasons: string[] = [];
  if (m.basis !== 'measured') return { finding: false, pause: false, reasons };
  let finding = false, pause = false;
  if (m.spam_ratio !== null && m.spam_ratio >= SPAM_FINDING_RATIO) {
    finding = true;
    if (m.spam_ratio >= SPAM_PAUSE_RATIO) {
      pause = true;
      reasons.push(`Gmail user-reported spam rate ${pct(m.spam_ratio, 2)} is at or over the 0.3% bulk-sender limit`);
    } else reasons.push(`Gmail user-reported spam rate ${pct(m.spam_ratio, 2)} is at or over 0.1%`);
  }
  if (m.reputation && (PAUSE_REPUTATIONS as readonly string[]).includes(m.reputation)) {
    finding = true; pause = true;
    reasons.push(`Gmail domain reputation is ${m.reputation}`);
  }
  return { finding, pause, reasons };
}

const pct = (x: number, d: number) => (x * 100).toFixed(d) + '%';
const orNoData = (x: number | null, d: number) => (x === null ? 'no data' : pct(x, d));

export function digestLine(m: Measured, v: Verdict): string {
  const head = `Gmail Postmaster ${m.domain}`;
  if (m.basis === 'unavailable') return `${head}: not read (${m.reason ?? 'unknown reason'})`;
  if (m.basis === 'no_data') return `${head}${m.stats_day ? ' ' + m.stats_day : ''}: ${NO_DATA}`;
  const spam = m.spam_ratio === null ? 'no data'
    : pct(m.spam_ratio, 2) + (m.spam_lower !== null && m.spam_upper !== null ? ` (${pct(m.spam_lower, 2)}-${pct(m.spam_upper, 2)})` : '');
  const act = v.pause ? '; invitations paused' : v.finding ? '; finding filed' : '';
  return `${head} ${m.stats_day}: spam ${spam}, reputation ${m.reputation ?? 'no data'}, `
    + `SPF ${orNoData(m.spf, 1)}, DKIM ${orNoData(m.dkim, 1)}, DMARC ${orNoData(m.dmarc, 1)}${act}`;
}

export function finish(m: Measured): PostmasterReading {
  const verdict = judge(m);
  return { ...m, verdict, line: digestLine(m, verdict) };
}

/** A fresh access token from the stored refresh token, or the reason there is none. */
export async function postmasterAccessToken(f: Fetch, sec: Sec): Promise<{ token: string } | { error: string }> {
  const [id, secret, refresh] = await Promise.all([sec(SECRET_KEYS.id), sec(SECRET_KEYS.secret), sec(SECRET_KEYS.refresh)]);
  if (!refresh) return { error: `app_secrets.${SECRET_KEYS.refresh} is not set (the founder's Postmaster consent is pending)` };
  if (!id || !secret) return { error: `app_secrets.${SECRET_KEYS.id} or ${SECRET_KEYS.secret} is not set` };
  const r = await f('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refresh, client_id: id, client_secret: secret }).toString(),
    signal: AbortSignal.timeout(20000),
  });
  const j = await r.json().catch(() => ({})) as Record<string, unknown>;
  if (!r.ok || typeof j.access_token !== 'string') {
    return { error: `Google refused the Postmaster refresh token (HTTP ${r.status} ${String(j.error ?? '').slice(0, 60)})` };
  }
  return { token: j.access_token };
}

export function trafficStatsUrl(domain: string, now: Date): string {
  const end = new Date(now.getTime() + 86400e3);                      // endDate is exclusive: include today
  const start = new Date(now.getTime() - LOOKBACK_DAYS * 86400e3);
  const p = (k: string, d: Date) => `${k}.year=${d.getUTCFullYear()}&${k}.month=${d.getUTCMonth() + 1}&${k}.day=${d.getUTCDate()}`;
  return `https://gmailpostmastertools.googleapis.com/v1/domains/${encodeURIComponent(domain)}/trafficStats?`
    + `${p('startDate', start)}&${p('endDate', end)}&pageSize=${LOOKBACK_DAYS + 2}`;
}

export async function takePostmasterReading(f: Fetch, sec: Sec, now = new Date(), domain = POSTMASTER_DOMAIN): Promise<PostmasterReading> {
  try {
    const t = await postmasterAccessToken(f, sec);
    if ('error' in t) return finish(empty(domain, 'unavailable', t.error));
    const r = await f(trafficStatsUrl(domain, now), { headers: { Authorization: 'Bearer ' + t.token }, signal: AbortSignal.timeout(20000) });
    const j = await r.json().catch(() => null) as Record<string, unknown> | null;
    if (!r.ok) {
      const msg = String((j?.error as Record<string, unknown> | undefined)?.message ?? '').slice(0, 120);
      const why = r.status === 403 || r.status === 404
        ? `Postmaster answered ${r.status}: the consenting Google account cannot read ${domain} in Postmaster Tools${msg ? ' (' + msg + ')' : ''}`
        : `Postmaster answered ${r.status}${msg ? ': ' + msg : ''}`;
      return finish(empty(domain, 'unavailable', why));
    }
    return finish(parseTrafficStats(domain, j ?? {}));
  } catch (e) {
    return finish(empty(domain, 'unavailable', 'Postmaster could not be reached: ' + String((e as Error)?.message || e).slice(0, 160)));
  }
}
