// Readings for the IT engineer's scheduled duties (9 restore, 10 sender, 11 spend, 13 access) that
// Postgres cannot take. Only the duties fn_it_scheduled_due() names are read. This module measures;
// public.fn_it_duties_scheduled decides (scripts/sql/the_it_engineer_takes_on_seven_more_duties.sql).
// No model call. Nothing returned here is a secret: principals are logins or ids, never keys.
// deno-lint-ignore-file no-explicit-any
type Sec = (key: string) => Promise<string>;
type Admin = { from: (t: string) => any; storage: { from: (b: string) => { download: (p: string) => Promise<{ data: Blob | null; error: { message: string } | null }> } } };

const REPO = 'ahmadmhdnabilalzain-bot/quotesdone';
const SENDING_DOMAINS = ['quotesdone.com'];
const unavailable = (reason: string) => ({ basis: 'unavailable', reason });

async function get(url: string, init: RequestInit = {}) {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(20000) });
    const text = await r.text();
    let json: any = null;
    try { json = JSON.parse(text); } catch { /* the status is the reading */ }
    return { status: r.status, ok: r.ok, json };
  } catch (e) {
    return { status: 0, ok: false, json: null, error: String((e as Error)?.message || e).slice(0, 200) };
  }
}

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');

// Dropbox's content_hash: SHA-256 of the concatenated SHA-256 of each 4 MiB block.
async function dropboxContentHash(bytes: Uint8Array): Promise<string> {
  const B = 4 * 1024 * 1024;
  const parts: Uint8Array[] = [];
  for (let i = 0; i < bytes.length; i += B) parts.push(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes.subarray(i, i + B))));
  const all = new Uint8Array(parts.length * 32);
  parts.forEach((p, i) => all.set(p, i * 32));
  return hex(await crypto.subtle.digest('SHA-256', all));
}

async function dropboxToken(sec: Sec): Promise<string | null> {
  const [key, secret, refresh] = await Promise.all([sec('dropbox_app_key'), sec('dropbox_app_secret'), sec('dropbox_refresh_token')]);
  if (!key || !secret || !refresh) return null;
  const g = await get('https://api.dropboxapi.com/oauth2/token', { method: 'POST',
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refresh, client_id: key, client_secret: secret }) });
  return g.ok ? g.json?.access_token ?? null : null;
}

// ── 9. Restore drill: open a random sample from Dropbox and from Supabase storage ─────────────────
async function restore(admin: Admin, sec: Sec, n: number) {
  const { data, error } = await admin.from('doc_backups')
    .select('id, bucket, path, dropbox_path').eq('status', 'done').not('dropbox_path', 'is', null).limit(500);
  if (error) return unavailable('doc_backups unreadable: ' + error.message);
  const pool = (data ?? []) as any[];
  if (!pool.length) return unavailable('no backed-up file to sample yet');
  const sample = pool.sort(() => Math.random() - 0.5).slice(0, n);
  const token = await dropboxToken(sec);
  const samples = [];
  for (const d of sample) {
    let dropbox: any = unavailable('no Dropbox token');
    if (token) {
      try {
        const r = await fetch('https://content.dropboxapi.com/2/files/download', { method: 'POST',
          headers: { Authorization: `Bearer ${token}`, 'Dropbox-API-Arg': JSON.stringify({ path: d.dropbox_path }) },
          signal: AbortSignal.timeout(60000) });
        const bytes = new Uint8Array(await r.arrayBuffer());
        dropbox = r.ok ? { ok: true, size: bytes.length, content_hash: await dropboxContentHash(bytes) }
                       : { ok: false, status: r.status };
      } catch (e) { dropbox = { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
    }
    let storage: any = { ok: null, reason: 'this backup has no storage source' };
    if (d.bucket && d.path) {
      const s = await admin.storage.from(d.bucket).download(d.path);
      storage = s.error || !s.data ? { ok: false, error: s.error?.message ?? 'no data' } : { ok: true, size: s.data.size };
    }
    samples.push({ doc_backup_id: d.id, dropbox, storage });
  }
  return { basis: 'measured', samples };
}

// ── 10. Sender health ────────────────────────────────────────────────────────────────────────────
async function txt(name: string): Promise<string[] | null> {
  const g = await get(`https://dns.google/resolve?name=${encodeURIComponent(name)}&type=TXT`);
  if (!g.ok || g.json?.Status === undefined) return null;
  return (g.json.Answer ?? []).map((a: any) => String(a.data).replace(/"/g, ''));
}
// A DNS blocklist answers 127.0.0.x for a listed name. Spamhaus refuses public resolvers and answers
// 127.255.255.x instead, which is reported as unavailable rather than as listed or clean.
async function dnsbl(list: string, target: string) {
  const g = await get(`https://dns.google/resolve?name=${encodeURIComponent(target + '.' + list)}&type=A`);
  if (!g.ok) return { list, target, ...unavailable('DNS-over-HTTPS answered ' + (g.status || g.error)) };
  const ips = (g.json?.Answer ?? []).map((a: any) => String(a.data));
  if (ips.some((ip: string) => ip.startsWith('127.255.255.'))) return { list, target, ...unavailable('the list refuses public resolvers') };
  return { list, target, basis: 'measured', listed: ips.some((ip: string) => ip.startsWith('127.0.0.')), answers: ips };
}

async function sender(sec: Sec) {
  const dns: Record<string, unknown> = {};
  for (const d of SENDING_DOMAINS) {
    const [root, dmarc, dkim] = await Promise.all([txt(d), txt('_dmarc.' + d), txt('resend._domainkey.' + d)]);
    dns[d] = root === null ? unavailable('DNS lookup failed') : {
      basis: 'measured',
      spf: root.some((t) => t.startsWith('v=spf1') && /include:|a:|mx/.test(t)),
      dmarc: (dmarc ?? []).some((t) => t.startsWith('v=DMARC1')),
      dkim: (dkim ?? []).some((t) => t.includes('p=')),
    };
  }
  const blocklists = await Promise.all(SENDING_DOMAINS.flatMap((d) => [dnsbl('dbl.spamhaus.org', d), dnsbl('multi.uribl.com', d)]));
  const [rk, rdom] = await Promise.all([sec('resend_api_key'), sec('resend_domain_id')]);
  let resend: any = unavailable('resend_api_key or resend_domain_id missing');
  if (rk && rdom) {
    const g = await get(`https://api.resend.com/domains/${rdom}`, { headers: { Authorization: `Bearer ${rk}` } });
    resend = g.ok ? { basis: 'measured', status: g.json?.status, records: (g.json?.records ?? []).map((r: any) => ({ record: r.record, status: r.status })) }
                  : unavailable('Resend answered ' + (g.status || g.error));
  }
  const [ks, kk, from, map] = await Promise.all([sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('twilio_wa_from'), sec('wa_template_sids')]);
  const auth = ks && kk ? 'Basic ' + btoa(`${ks}:${kk}`) : '';
  let whatsapp: any = unavailable('Twilio key or twilio_wa_from missing');
  if (auth && from) {
    const g = await get('https://messaging.twilio.com/v2/Channels/Senders?Channel=whatsapp&PageSize=50', { headers: { Authorization: auth } });
    const s = (g.json?.senders ?? []).find((x: any) => String(x.sender_id ?? '').replace(/\D/g, '') === from.replace(/\D/g, ''));
    whatsapp = g.ok && s ? { basis: 'measured', status: s.status, quality: s.properties?.quality_rating ?? 'UNKNOWN' }
                         : unavailable('Twilio Senders answered ' + (g.status || g.error) + (g.ok ? ' without our number' : ''));
  }
  const templates: unknown[] = [];
  let parsed: Record<string, any> = {};
  try { parsed = JSON.parse(map || '{}'); } catch { parsed = {}; }
  for (const [name, v] of Object.entries(parsed)) {
    const sid = typeof v === 'string' ? v : v?.sid;
    if (!auth || !sid) { templates.push({ name, ...unavailable('no Twilio key or template sid') }); continue; }
    const g = await get(`https://content.twilio.com/v1/Content/${sid}/ApprovalRequests`, { headers: { Authorization: auth } });
    templates.push(g.ok ? { name, basis: 'measured', status: g.json?.whatsapp?.status ?? 'unknown' }
                        : { name, ...unavailable('Twilio Content answered ' + (g.status || g.error)) });
  }
  return { dns, blocklists, resend, whatsapp, templates };
}

// ── 11. Spend: yesterday per provider we can read ─────────────────────────────────────────────────
async function spend(sec: Sec) {
  const y = new Date(Date.now() - 86400e3).toISOString().slice(0, 10);
  const out: unknown[] = [];
  const [sid, ks, kk, sk] = await Promise.all([sec('twilio_account_sid'), sec('twilio_api_key_sid'), sec('twilio_api_key_secret'), sec('stripe_secret_key')]);
  if (sid && ks && kk) {
    const g = await get(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Usage/Records/Yesterday.json?Category=totalprice`,
      { headers: { Authorization: 'Basic ' + btoa(`${ks}:${kk}`) } });
    const r = g.json?.usage_records?.[0];
    out.push(g.ok && r ? { source: 'twilio', day: y, amount_minor: Math.round(Number(r.price) * 100), currency: String(r.price_unit || 'usd').toUpperCase(), basis: 'measured' }
                       : { source: 'twilio', ...unavailable('Twilio usage answered ' + (g.status || g.error)) });
  } else out.push({ source: 'twilio', ...unavailable('Twilio credentials missing') });
  if (sk) {
    const from = Math.floor(Date.parse(y + 'T00:00:00Z') / 1000);
    const g = await get(`https://api.stripe.com/v1/balance_transactions?limit=100&created[gte]=${from}&created[lt]=${from + 86400}`,
      { headers: { Authorization: `Bearer ${sk}` } });
    out.push(g.ok ? { source: 'stripe_fees', day: y, amount_minor: (g.json?.data ?? []).reduce((a: number, t: any) => a + (t.fee || 0), 0),
                      currency: 'AED', basis: 'measured' }
                  : { source: 'stripe_fees', ...unavailable('Stripe answered ' + (g.status || g.error)) });
  }
  out.push({ source: 'supabase', ...unavailable('the bill needs a management token; not held by the edge') });
  out.push({ source: 'vercel', ...unavailable('app_secrets.vercel_token has no billing scope') });
  out.push({ source: 'dropbox', ...unavailable('a flat plan with no daily usage cost') });
  return out;
}

// ── 13. Access review ─────────────────────────────────────────────────────────────────────────────
async function access(sec: Sec) {
  const [gh, vt, team, dk, ds, dr] = await Promise.all([sec('github_token'), sec('vercel_token'), sec('vercel_team_id'),
    sec('dropbox_app_key'), sec('dropbox_app_secret'), sec('dropbox_refresh_token')]);
  const out: Record<string, unknown> = {};
  if (gh) {
    const h = { headers: { Authorization: `Bearer ${gh}`, Accept: 'application/vnd.github+json' } };
    const [c, k] = await Promise.all([get(`https://api.github.com/repos/${REPO}/collaborators?per_page=100`, h),
                                      get(`https://api.github.com/repos/${REPO}/keys?per_page=100`, h)]);
    out.github = c.ok && k.ok ? { basis: 'measured', principals: [
      ...(c.json ?? []).map((u: any) => ({ principal: u.login, role: u.role_name ?? 'collaborator' })),
      ...(k.json ?? []).map((d: any) => ({ principal: 'deploy_key:' + d.id + ':' + d.title, role: d.read_only ? 'deploy key (read)' : 'deploy key (write)' }))] }
      : unavailable(`GitHub answered collaborators ${c.status}, keys ${k.status}`);
  } else out.github = unavailable('github_token missing');
  if (vt && team) {
    const g = await get(`https://api.vercel.com/v2/teams/${team}/members?limit=100`, { headers: { Authorization: `Bearer ${vt}` } });
    out.vercel = g.ok ? { basis: 'measured', principals: (g.json?.members ?? []).map((m: any) => ({ principal: m.username ?? m.uid, role: m.role })) }
                      : unavailable('Vercel answered ' + (g.status || g.error));
  } else out.vercel = unavailable('vercel_token or vercel_team_id missing');
  const token = dk && ds && dr ? await dropboxToken(sec) : null;
  if (token) {
    const g = await get('https://api.dropboxapi.com/2/users/get_current_account', { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
    out.dropbox = g.ok ? { basis: 'measured', principals: [{ principal: g.json?.account_id, role: 'account owner' }] }
                       : unavailable('Dropbox answered ' + (g.status || g.error));
  } else out.dropbox = unavailable('Dropbox credentials missing or refused');
  out.stripe = unavailable('Stripe publishes no team-member API');
  return out;
}

export async function takeScheduledReadings(admin: Admin, sec: Sec, due: string[], restoreSample: number) {
  const r: Record<string, unknown> = { taken_at: new Date().toISOString() };
  if (due.includes('restore')) r.restore = await restore(admin, sec, restoreSample);
  if (due.includes('sender')) r.sender = await sender(sec);
  if (due.includes('spend')) r.spend = await spend(sec);
  if (due.includes('access')) r.access = await access(sec);
  return r;
}
