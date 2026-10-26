// THE IT ENGINEER READS EVERY PROVIDER'S STATUS PAGE AND THE SITE'S FIREWALL (24 Sep 2026, it_engineer).
//
// Seat audit of 24 Sep 2026, IT gaps 3 and 5 (founder_instruction 8, 324): nothing polled the status pages of
// Stripe, Resend, Twilio, Vercel, Supabase or Dropbox, so a provider outage could be told apart from our own bug
// only after the fact; and nothing read the Vercel firewall mode or the attack status.
//
// This module MEASURES and public.fn_it_provider_watch DECIDES
// (scripts/sql/the_it_engineer_reads_provider_status_pages_and_the_firewall.sql). No model call. Every reading
// that could not be taken says so ('unavailable' with the reason) rather than reading as healthy.
//
// URLs measured 24 Sep 2026 (curl, 200 with Atlassian Statuspage JSON): stripe = www.stripestatus.com (the
// status.stripe.com path 404s), resend = resend-status.com (status.resend.com 302s). OpenRouter publishes no
// readable status JSON (403) and is left out: its own key is already read every tick by the openrouter step.
// deno-lint-ignore-file no-explicit-any

type Sec = (key: string) => Promise<string>;

export const STATUS_PAGES: Readonly<Record<string, string>> = {
  stripe: 'https://www.stripestatus.com/api/v2/status.json',
  resend: 'https://resend-status.com/api/v2/status.json',
  twilio: 'https://status.twilio.com/api/v2/status.json',
  vercel: 'https://www.vercel-status.com/api/v2/status.json',
  supabase: 'https://status.supabase.com/api/v2/status.json',
  dropbox: 'https://status.dropbox.com/api/v2/status.json',
};

const unavailable = (reason: string) => ({ basis: 'unavailable', reason: reason.slice(0, 200) });

async function get(url: string, init: RequestInit = {}) {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
    const json = await r.json().catch(() => null);
    return { status: r.status, ok: r.ok, json };
  } catch (e) {
    return { status: 0, ok: false, json: null, error: String((e as Error)?.message || e) };
  }
}

/** A Statuspage body -> the reading. The indicator is one of none|minor|major|critical (maintenance too). */
export function statusReading(provider: string, status: number, json: any) {
  const ind = json?.status?.indicator;
  if (status !== 200 || typeof ind !== 'string') return { provider, ...unavailable('status page answered ' + status) };
  return { provider, basis: 'measured', indicator: ind, description: String(json?.status?.description ?? '').slice(0, 200) };
}

/** The Vercel firewall readings -> the facts the SQL judges. Unknown shapes are unavailable, never "fine". */
export function firewallReading(cfg: { status: number; json: any }, attack: { status: number; json: any }) {
  const config = cfg.status === 200 && typeof cfg.json?.firewallEnabled === 'boolean'
    ? { basis: 'measured', enabled: cfg.json.firewallEnabled as boolean }
    : unavailable('Vercel firewall config answered ' + cfg.status);
  const anomalies = attack.json?.anomalies;
  const attackR = attack.status === 200 && attack.json && typeof attack.json === 'object'
    ? { basis: 'measured', under_attack: Array.isArray(anomalies) ? anomalies.length > 0 : !!attack.json?.dosAttackStatus?.active }
    : unavailable('Vercel attack status answered ' + attack.status);
  return { config, attack: attackR };
}

export async function takeProviderReadings(sec: Sec) {
  const providers = await Promise.all(Object.entries(STATUS_PAGES).map(async ([p, url]) => {
    const g = await get(url);
    return statusReading(p, g.status, g.json);
  }));
  const [token, team, prj] = await Promise.all([sec('vercel_token'), sec('vercel_team_id'), sec('vercel_project_id')]);
  let firewall: unknown = unavailable('app_secrets.vercel_token or vercel_project_id is missing');
  if (token && prj) {
    const q = `projectId=${encodeURIComponent(prj)}` + (team ? `&teamId=${encodeURIComponent(team)}` : '');
    const h = { headers: { Authorization: 'Bearer ' + token } };
    const [cfg, att] = await Promise.all([
      get(`https://api.vercel.com/v1/security/firewall/config/active?${q}`, h),
      get(`https://api.vercel.com/v1/security/attack-status?${q}`, h),
    ]);
    firewall = firewallReading(cfg, att);
  }
  return { taken_at: new Date().toISOString(), providers, firewall };
}
