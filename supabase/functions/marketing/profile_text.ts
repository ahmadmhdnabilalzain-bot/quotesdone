// ONE COMPANY DESCRIPTION ON EVERY PROFILE (marketing, 23 Sep 2026; founder instruction 920: "WhatsApp profile
// description and any social media profile should all match, within each platform's limit").
//
// profile_text.json holds the canonical sentences (EN + Gulf Arabic) and, per platform field, WHICH sentences make
// the variant. A variant is rendered from canonical sentences only, so it cannot claim anything the canonical text
// does not. violations() is the check (profile_text.test.ts runs it in CI): every part exists, every rendered
// variant fits its limit (counted in code points), and the canonical text carries none of the retired claims.
//
// WHERE AN API CAN WRITE IT, the duty 'profile_text' (once a day, 03:00-03:29 UTC) compares the live text and
// updates only what differs, then reads it back:
//   whatsapp  Twilio Senders v2 POST profile.about / profile.description. Twilio answers 202 and applies it at
//             Meta asynchronously — the earlier update "returned 202 but didn't reach Meta" — so a 202 is NOT
//             success: the duty re-reads the sender and fails (an IT finding for this seat) until the live
//             profile equals the text, and reports any Twilio alert 63115 (sender not ONLINE) with it.
//   facebook  Graph POST /{page} about= (page token); read back with ?fields=about.
//   youtube   channels.update brandingSettings.channel.description with the founder-connected token.
// Everything else (instagram, linkedin, tiktok, x) has no permitted API and is pasted by hand from rendered().
// app_secrets.profile_text_push = 'off' stops every write (the emergency stop); absent means on — the founder's
// instruction 920 is the go.
import data from './profile_text.json' with { type: 'json' };

export interface Variant { platform: string; field: string; limit: number; api: 'twilio' | 'graph' | 'youtube' | 'manual'; join: string; parts: string[]; source: string }
const CANON = data.canonical as Record<'en' | 'ar', Record<string, string>>;
export const VARIANTS = data.variants as Variant[];

const sentence = (id: string) => { const [l, k] = id.split('.'); return CANON[l as 'en' | 'ar']?.[k]; };
export const render = (v: Variant) => v.parts.map(sentence).join(v.join);
export const length = (s: string) => [...s].length;
export const text = (platform: string, field: string) => render(VARIANTS.find((v) => v.platform === platform && v.field === field)!);

// Claims the company corrected and must never make again (the retired copy): licence-activity matching, a blanket
// "free", the "E-Trader" name.
const RETIRED = /licen[cs]e activit|activit(y|ies) on (your|the) licen|نشاط الرخص|free for (all|everyone|ever)|always free|مجاني للجميع|مجانا للجميع|e-?trader|اي ?تريدر/i;

export function violations(): string[] {
  const out: string[] = [];
  for (const [lang, set] of Object.entries(CANON)) for (const [k, s] of Object.entries(set)) if (RETIRED.test(s)) out.push(`canonical ${lang}.${k} makes a retired claim`);
  for (const v of VARIANTS) {
    const id = v.platform + '.' + v.field;
    for (const p of v.parts) if (!sentence(p)) out.push(`${id}: part ${p} is not a canonical sentence`);
    if (!v.parts.length) out.push(`${id}: empty`);
    const n = length(render(v));
    if (n > v.limit) out.push(`${id}: ${n} characters, limit ${v.limit}`);
  }
  return out;
}

// ── the pushes. Each returns what it found and did; a write that does not read back is an error. ─────────
export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export interface PushResult { platform: string; status: 'matches' | 'updated' | 'skipped'; detail?: string }
const same = (a: unknown, b: string) => String(a ?? '').trim() === b.trim();

export async function pushWhatsapp(f: Fetch, auth: string, from: string, sinceIso: string): Promise<PushResult> {
  const about = text('whatsapp', 'about'), description = text('whatsapp', 'description');
  const find = async () => {
    const r = await f('https://messaging.twilio.com/v2/Channels/Senders?Channel=whatsapp&PageSize=50', { headers: { Authorization: auth } });
    const j = await r.json().catch(() => ({})) as any;
    if (!r.ok) throw new Error('twilio senders HTTP ' + r.status);
    const s = (j.senders || []).find((x: any) => String(x.sender_id || '').replace(/\D/g, '') === from.replace(/\D/g, ''));
    if (!s) throw new Error('twilio senders: our number is not a sender');
    return s;
  };
  const s = await find();
  if (same(s.profile?.about, about) && same(s.profile?.description, description)) return { platform: 'whatsapp', status: 'matches' };
  const u = await f('https://messaging.twilio.com/v2/Channels/Senders/' + s.sid, { method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ profile: { about, description } }) });
  if (!u.ok && u.status !== 202) throw new Error('twilio sender update HTTP ' + u.status + ' (sender status ' + s.status + ')');
  const back = await find();
  if (same(back.profile?.about, about) && same(back.profile?.description, description)) return { platform: 'whatsapp', status: 'updated', detail: 'read back equal' };
  // Accepted but not applied yet. Twilio records the Meta refusal as alert 63115.
  const a = await f('https://monitor.twilio.com/v1/Alerts?PageSize=20&StartDate=' + encodeURIComponent(sinceIso), { headers: { Authorization: auth } });
  const alerts = ((await a.json().catch(() => ({})) as any).alerts || []).filter((x: any) => String(x.error_code) === '63115');
  throw new Error('whatsapp profile update answered ' + u.status + ' but the sender still shows the old text (status ' + back.status + ')'
    + (alerts.length ? '; Twilio alert 63115: the sender is not ONLINE at Meta' : '; will re-check next run'));
}

export async function pushFacebook(f: Fetch, pageId: string, token: string): Promise<PushResult> {
  const want = text('facebook', 'intro');
  const G = 'https://graph.facebook.com/v21.0/' + encodeURIComponent(pageId);
  const read = async () => { const r = await f(G + '?fields=about&access_token=' + encodeURIComponent(token)); const j = await r.json().catch(() => ({})) as any;
    if (!r.ok) throw new Error('facebook page read HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 120)); return j.about; };
  if (same(await read(), want)) return { platform: 'facebook', status: 'matches' };
  const u = await f(G, { method: 'POST', body: new URLSearchParams({ about: want, access_token: token }) });
  const uj = await u.json().catch(() => ({})) as any;
  if (!u.ok) throw new Error('facebook page update HTTP ' + u.status + ': ' + String(uj?.error?.message || '').slice(0, 120));
  if (!same(await read(), want)) throw new Error('facebook page update accepted but the intro reads back different');
  return { platform: 'facebook', status: 'updated', detail: 'read back equal' };
}

export async function pushYoutube(f: Fetch, token: string): Promise<PushResult> {
  const want = text('youtube', 'description');
  const H = { Authorization: 'Bearer ' + token };
  const read = async () => { const r = await f('https://www.googleapis.com/youtube/v3/channels?part=brandingSettings&mine=true', { headers: H });
    const j = await r.json().catch(() => ({})) as any; if (!r.ok || !j.items?.[0]) throw new Error('youtube channel read HTTP ' + r.status); return j.items[0]; };
  const c = await read();
  if (same(c.brandingSettings?.channel?.description, want)) return { platform: 'youtube', status: 'matches' };
  // brandingSettings is replaced as a whole: send back every field it had, with only the description changed.
  const u = await f('https://www.googleapis.com/youtube/v3/channels?part=brandingSettings', { method: 'PUT', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: c.id, brandingSettings: { ...c.brandingSettings, channel: { ...c.brandingSettings?.channel, description: want } } }) });
  if (!u.ok) throw new Error('youtube channel update HTTP ' + u.status);
  if (!same((await read()).brandingSettings?.channel?.description, want)) throw new Error('youtube description accepted but reads back different');
  return { platform: 'youtube', status: 'updated', detail: 'read back equal' };
}
