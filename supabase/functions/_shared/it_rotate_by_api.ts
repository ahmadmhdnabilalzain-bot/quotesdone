// A PROVIDER KEY THAT CAN BE ROTATED BY API IS ROTATED BY THE IT ENGINEER, AND EVERY ROTATION IS RECORDED
// (IT duty 15, 28 Sep 2026, it_engineer). Measured that morning: public.it_credential_rotation had 0 rows. The
// daily duty ran every day (agent_runs 'duty:rotation', rotated 0) because the 89 internal credentials are all
// younger than credential_rotate_days (90; the first falls due 1 Nov 2026), and no third-party key was rotated at
// all - docs/security/THIRD_PARTY_KEY_ROTATION.md left each one to the founder's dashboard.
//
// Which third-party keys the estate can rotate itself, measured against what app_secrets holds:
//   * Twilio API key (twilio_api_key_sid / twilio_api_key_secret): YES. The account SID and auth token are held,
//     and Twilio's REST API creates and deletes Standard API keys with them. Every Verify/SMS caller reads the
//     pair from app_secrets at call time (kyc caches it for at most a minute), so a new pair reaches them all.
//   * The Twilio auth token, Stripe, Meta, Dropbox app secret, Vercel, GitHub: NO - none of them can mint its
//     own replacement through an API with what we hold. They stay on the key-age reminder (fn_it_key_age_refresh).
//   ponytail: Resend can rotate by API only with a full-access key; add it here once the held key is proved to be one.
//
// The order never leaves a caller without a working key: create the new key, PROVE it authenticates, store it and
// record the rotation in one database call (fn_it_provider_rotation_record), and delete the old key at Twilio only
// after the overlap (fn_it_provider_rotation_retire_due). A new key that does not authenticate, or a store that
// fails, deletes the new key and leaves the old one in place. No secret is ever returned, logged or recorded:
// the result carries key SIDs (identifiers) only.

export type RotateDeps = {
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<unknown>;
  sec: (k: string) => Promise<string>;
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  sleep?: (ms: number) => Promise<void>;
};

const API = 'https://api.twilio.com/2010-04-01/Accounts/';
const basic = (u: string, p: string) => 'Basic ' + btoa(u + ':' + p);

async function deleteKey(d: RotateDeps, ac: string, token: string, sid: string): Promise<boolean> {
  const r = await d.fetch(`${API}${ac}/Keys/${sid}.json`, { method: 'DELETE', headers: { Authorization: basic(ac, token) } });
  return r.status === 204 || r.status === 404; // 404: already gone, which is what retiring wants
}

export async function rotateTwilioKey(d: RotateDeps): Promise<Record<string, unknown>> {
  const sleep = d.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  const [ac, token] = await Promise.all([d.sec('twilio_account_sid'), d.sec('twilio_auth_token')]);
  if (!ac || !token) return { ok: false, error: 'twilio_account_sid or twilio_auth_token is not in app_secrets' };
  const out: Record<string, unknown> = { ok: true, provider: 'twilio' };

  // 1. Retire: an old key whose overlap is over is deleted at Twilio, then its row is closed.
  const due = ((await d.rpc('fn_it_provider_rotation_retire_due', { p_provider: 'twilio' })) ?? []) as { id: number; old_ref: string }[];
  const retired: string[] = [];
  for (const r of due) {
    if (await deleteKey(d, ac, token, r.old_ref)) {
      await d.rpc('fn_it_provider_rotation_retired', { p_id: r.id, p_note: 'old Twilio API key ' + r.old_ref + ' deleted at Twilio after the overlap' });
      retired.push(r.old_ref);
    } else {
      out.ok = false;
      out.error = 'Twilio refused to delete the old key ' + r.old_ref + '; it stays in overlap and is retried next run';
    }
  }
  out.retired = retired;

  // 2. Rotate, when the database says it is due (and claims the run, so two ticks cannot both rotate).
  const claim = (await d.rpc('fn_it_provider_rotation_claim', { p_provider: 'twilio' })) as { due?: boolean; reason?: string } | null;
  if (!claim?.due) return { ...out, rotated: false, reason: claim?.reason ?? 'not due' };
  const oldSid = await d.sec('twilio_api_key_sid');
  const cr = await d.fetch(`${API}${ac}/Keys.json`, {
    method: 'POST',
    headers: { Authorization: basic(ac, token), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ FriendlyName: 'quotesdone it_engineer ' + new Date().toISOString().slice(0, 10) }).toString(),
  });
  const nk = (await cr.json().catch(() => ({}))) as { sid?: string; secret?: string };
  if (!cr.ok || !nk.sid || !nk.secret) return { ...out, ok: false, rotated: false, error: 'Twilio did not create a key (HTTP ' + cr.status + ')' };

  // A new key can take a moment to propagate: three tries, two seconds apart.
  let works = false;
  for (let i = 0; i < 3 && !works; i++) {
    if (i) await sleep(2000);
    const v = await d.fetch(`${API}${ac}.json`, { method: 'GET', headers: { Authorization: basic(nk.sid, nk.secret) } });
    works = v.ok;
  }
  if (!works) {
    await deleteKey(d, ac, token, nk.sid);
    return { ...out, ok: false, rotated: false, error: 'the new key ' + nk.sid + ' did not authenticate, so it was deleted and the old key kept' };
  }
  try {
    await d.rpc('fn_it_provider_rotation_record', { p_provider: 'twilio', p_old_ref: oldSid || null, p_new_ref: nk.sid, p_new_secret: nk.secret });
  } catch (e) {
    await deleteKey(d, ac, token, nk.sid);
    return { ...out, ok: false, rotated: false, error: 'the new key could not be stored, so it was deleted and the old key kept: ' + String((e as Error)?.message || e).slice(0, 200) };
  }
  return { ...out, rotated: true, old_ref: oldSid || null, new_ref: nk.sid };
}
