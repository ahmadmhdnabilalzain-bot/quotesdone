// THE REGISTRATION'S FIXTURE MOBILE, RECORDED VERIFIED WITHOUT RACING THE FORM (10 Nov 2026, sales_engineer; evidence
// run ea40c830's registration, tag 8120d011, docs/reports/2026-11-10-journey-evidence.md "Harness issues").
//
// A ZZ DEMO supplier's mobile is the reserved fixture block: kyc refuses it before any SMS (isDemoPhone), so the harness
// records it verified in the database, as fixtures.makeDemoSupplier does. The registration form reads that once, on mount
// (ProfileForm loadKyc: kyc 'state', through the supplier portal's call(), which aborts at 20 s and then shows the mobile as
// not verified). evidence_pack.mjs used to HOLD the page's kyc 'state' request with a Playwright route until its own writes
// were done: send_sms, the leads update, whatsapp_choose. In three dry runs those took a few seconds. On the live run the
// harness's send_sms took 33,345 ms at the edge (function_edge_logs, kyc, ending 20:11:20.284Z; whatsapp_choose 514 ms at
// 20:11:23Z), so the held read was released after ~40 s - past the form's 20 s abort, which had already decided "not
// verified, no WhatsApp answer". No kyc 'state' reached the server between 20:11:23Z and 20:16:04Z: the held request had been
// cancelled. Submit then said "Still needed: Verified mobile number, your WhatsApp answer".
//
// Nothing is held now. The writes are made, the server is asked until IT says the mobile is verified and the WhatsApp answer
// given (kyc 'state' with the supplier's own token), and only then is the form loaded again, so its one read is made after
// the truth exists, however long the writes took. The step passes only when the form itself shows "Mobile verified".
// Prevented by: scripts/e2e/fixture_mobile.test.mjs

/** The kyc state that registration needs: a verified mobile and a WhatsApp answer (portal waSignupSettled). */
export const settled = (k) => !!(k && k.phone_verified === true && k.whatsapp && k.whatsapp.opt);

/**
 * deps: sendSms() -> kyc send_sms answer; markVerified() -> the leads write; chooseWhatsapp() -> kyc whatsapp_choose;
 * kycState() -> kyc 'state' (the supplier's token); reloadForm() -> reloads the page and waits for the form;
 * formShowsVerified() -> true when the form reads "Mobile verified"; sleep(ms). Never routes or holds a page request.
 */
export async function recordFixtureMobile(deps, { timeoutMs = 60000, everyMs = 1500 } = {}) {
  const sms = await deps.sendSms();
  const smsRefused = !(sms && sms.ok === true);
  await deps.markVerified();
  await deps.chooseWhatsapp();
  const t0 = Date.now(); let k = null;
  for (;;) {
    k = await deps.kycState().catch(() => null);
    if (settled(k) || Date.now() - t0 > timeoutMs) break;
    await deps.sleep(everyMs);
  }
  if (!settled(k)) return { ok: false, smsRefused, detail: `kyc state never read verified + answered: ${JSON.stringify({ phone_verified: k?.phone_verified ?? null, whatsapp_opt: k?.whatsapp?.opt ?? null })}` };
  await deps.reloadForm();
  const shown = await deps.formShowsVerified();
  return { ok: !!shown, smsRefused, detail: shown ? 'kyc state verified + answered, and the reloaded form shows Mobile verified' : 'kyc state verified, but the reloaded form does not show Mobile verified' };
}
