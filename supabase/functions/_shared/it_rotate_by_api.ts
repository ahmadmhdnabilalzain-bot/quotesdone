// A PROVIDER KEY THAT CAN BE ROTATED BY API IS ROTATED BY THE IT ENGINEER, AND EVERY ROTATION IS RECORDED
// (IT duty 15, 28 Sep 2026, it_engineer). Measured that morning: public.it_credential_rotation had 0 rows. The
// daily duty ran every day (agent_runs 'duty:rotation', rotated 0) because the 89 internal credentials are all
// younger than credential_rotate_days (90; the first falls due 1 Nov 2026), and no third-party key was rotated at
// all - docs/security/THIRD_PARTY_KEY_ROTATION.md left each one to the founder's dashboard.
//
// Which third-party keys the estate can rotate itself, measured against what app_secrets holds:
//   * Twilio API key (twilio_api_key_sid / twilio_api_key_secret): YES. The account SID and auth token are held,
//     and Twilio's REST API creates and deletes Standard API keys with them. Every Verify/SMS caller reads the
//     pair from app_secrets at call time (kyc caches it for at most a minute and re-reads it on a Twilio 401), so a
//     new pair reaches them all, and the old key outlives every cache by the overlap (at least 24 hours).
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

  // 1. Retire: an old key whose overlap is over is deleted at Twilio, then its row is closed. The key the estate
  //    is using NOW is never deleted, whatever a row says.
  const due = ((await d.rpc('fn_it_provider_rotation_retire_due', { p_provider: 'twilio' })) ?? []) as { id: number; old_ref: string }[];
  const retired: string[] = [];
  const inUse = await d.sec('twilio_api_key_sid');
  for (const r of due) {
    if (r.old_ref === inUse) {
      out.ok = false;
      out.error = 'rotation row ' + r.id + ' offers the key in use (' + r.old_ref + ') for deletion; it was not deleted';
      continue;
    }
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
  const claim = (await d.rpc('fn_it_provider_rotation_claim', { p_provider: 'twilio' })) as
    { due?: boolean; reason?: string; baseline_needed?: boolean } | null;
  if (claim?.baseline_needed) {
    // No row yet: the schedule counts from when the CURRENT key was created at Twilio, never from "never
    // rotated". Read that date and record it; nothing is rotated on this run.
    if (!inUse) return { ...out, ok: false, rotated: false, error: 'twilio_api_key_sid is not in app_secrets, so no baseline can be read' };
    const kr = await d.fetch(`${API}${ac}/Keys/${inUse}.json`, { method: 'GET', headers: { Authorization: basic(ac, token) } });
    const kj = (await kr.json().catch(() => ({}))) as { date_created?: string };
    const created = kj.date_created ? new Date(kj.date_created) : null;
    if (!kr.ok || !created || isNaN(created.getTime())) {
      return { ...out, ok: false, rotated: false, error: 'could not read the current key creation date from Twilio (HTTP ' + kr.status + '); no baseline, no rotation' };
    }
    await d.rpc('fn_it_provider_rotation_baseline', { p_provider: 'twilio', p_ref: inUse, p_created_at: created.toISOString() });
    return { ...out, rotated: false, baseline: { ref: inUse, created_at: created.toISOString() } };
  }
  if (!claim?.due) return { ...out, rotated: false, reason: claim?.reason ?? 'not due' };
  const oldSid = await d.sec('twilio_api_key_sid');
  const cr = await d.fetch(`${API}${ac}/Keys.json`, {
    method: 'POST',
    headers: { Authorization: basic(ac, token), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ FriendlyName: 'quotesdone it_engineer ' + new Date().toISOString().slice(0, 10) }).toString(),
  });
  const nk = (await cr.json().catch(() => ({}))) as { sid?: string; secret?: string };
  if (!cr.ok || !nk.sid || !nk.secret) return { ...out, ok: false, rotated: false, error: 'Twilio did not create a key (HTTP ' + cr.status + ')' };

  // PROVE THE NEW KEY on a call a Standard API key is allowed to make. GET /Accounts/{AC}.json answers a Standard
  // key with 401/20003 (only the auth token or a Main key may read the account resource), so proving the key there
  // refused every good key and deleted it (review of #1038, 29 Sep 2026). /Accounts/{AC}/Balance.json is the call
  // _shared/it_duty_readings.ts already makes with this very key in production. A new key can take a moment to
  // propagate: three tries, two seconds apart.
  let works = false;
  for (let i = 0; i < 3 && !works; i++) {
    if (i) await sleep(2000);
    const v = await d.fetch(`${API}${ac}/Balance.json`, { method: 'GET', headers: { Authorization: basic(nk.sid, nk.secret) } });
    works = v.ok;
    await v.body?.cancel().catch(() => {});
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

// THE STEP, SETTLED (review of #1038). A failed rotation used to come back only in the heartbeat's step output, which
// raises nothing: the duty would have retried daily with nobody told. Every run now settles duty 'rotate_by_api'
// through fn_it_duty_settle - a failure (returned or thrown) is an open finding duty:rotate_by_api:twilio, and the
// next run that does not fail closes it. The evidence carries key SIDs at most, never a secret.
export async function rotateAndSettle(d: RotateDeps): Promise<Record<string, unknown>> {
  let r: Record<string, unknown>;
  try { r = await rotateTwilioKey(d); } catch (e) { r = { ok: false, rotated: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
  const items = r.ok === false ? [{
    item: 'twilio', owner_seat: 'it_engineer', subject: 'twilio_api_key', blast: 'security', affected: 1,
    title: 'The Twilio API key rotation failed: ' + String(r.error ?? 'no reason given').slice(0, 200),
    evidence: { error: r.error ?? null, rotated: r.rotated ?? false, retired: r.retired ?? [] },
  }] : [];
  return { ...r, settle: await d.rpc('fn_it_duty_settle', { p_duty: 'rotate_by_api', p_items: items }) };
}
