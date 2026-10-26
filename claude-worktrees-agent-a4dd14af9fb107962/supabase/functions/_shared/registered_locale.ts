// THE LANGUAGE A PERSON REGISTERED IN (14 Sep 2026, agent: customer_support).
//
// Founder, 14 Sep 2026: "if someone registered while the language was arabic then arabic follows
// through the whole workflow till the reveal. and if english then all english." The answer lives in
// ONE place - public.fn_registered_locale, which reads customers.locale / leads.locale - and every edge
// function asks it through here. Never decide a recipient's language from the request body, the URL,
// the browser, or the language of the text they typed.
//
// `asLocale` is only for the moment BEFORE a registered row exists (the sign-up itself), when the page
// language the person chose is exactly what is being registered.
// deno-lint-ignore-file no-explicit-any
export type Locale = 'en' | 'ar';
export const asLocale = (v: unknown): Locale => (/^ar/i.test(String(v || '')) ? 'ar' : 'en');

// A DOCUMENT the person asks for by language (customer audit, 21 Sep 2026, finding 4). "Both always
// on offer" (founder, 14 Sep 2026): the registered language is the default copy, and the portal's
// "النسخة العربية" / "English copy" button is the person asking for the other one. Only 'en' or 'ar'
// is honoured; anything else falls back to the registered language. Messages never use this.
export const documentLocale = (requested: unknown, registered: unknown): Locale =>
  requested === 'ar' || requested === 'en' ? requested : asLocale(registered);

export const LOOKUP_FAILED_ISSUE = 'language:registered_locale_lookup_failed';

// A FAILED LOOKUP IS NEVER SILENT (review of PR #629, 14 Sep 2026). The message still goes, in the
// sign-up language or English, because withholding a sign-in code over a lookup fault would lock the
// person out. But an Arabic-registered person may just have been written to in English, so the fault is
// recorded as an agent_runs warning and opened as an IT engineer finding (founder, 14 Sep: "nothing
// literally should ever be a one way communication"). Only the recipient KIND and the database's error
// text are recorded; never an address or an id.
async function reportLookupFailure(admin: any, role: string, reason: string) {
  const note = 'fn_registered_locale could not be read for a ' + role + ', so this message used the sign-up language or English. '
    + 'An Arabic-registered ' + role + ' may have been written to in English. Reason: ' + reason.slice(0, 200);
  try {
    await admin.from('agent_runs').insert({ agent: 'customer_support', status: 'warn', counts: { fn: 'registered_locale', role, lookup_failed: 1 },
      note, started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
  } catch (e) { console.error('registered_locale: agent_runs warning could not be written -', String((e as Error)?.message || e)); }
  try {
    const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: LOOKUP_FAILED_ISSUE,
      p_title: 'The registered-language lookup failed; messages may have gone out in the wrong language',
      p_where: 'public.fn_registered_locale, called from supabase/functions/_shared/registered_locale.ts',
      p_blast: 'monitor', p_affected: 1,
      p_evidence: { role, reason: reason.slice(0, 200) },
      p_raised_by: 'customer_support' });
    if (error) console.error('registered_locale: IT engineer finding could not be opened -', error.message);
  } catch (e) { console.error('registered_locale: IT engineer finding could not be opened -', String((e as Error)?.message || e)); }
}

/** `signupLang` applies ONLY when nobody is registered under these keys yet (the resolver answers null). */
export async function registeredLocale(admin: any, who: { role: string; customerId?: string | null; leadId?: number | null; email?: string | null }, signupLang?: unknown): Promise<Locale> {
  try {
    const { data, error } = await admin.rpc('fn_registered_locale', { p_role: who.role, p_customer: who.customerId || null, p_lead: who.leadId ?? null, p_email: who.email || null });
    if (error) { await reportLookupFailure(admin, who.role, String(error.message || error)); return asLocale(signupLang); }
    return data == null ? asLocale(signupLang) : asLocale(data);
  } catch (e) {
    await reportLookupFailure(admin, who.role, String((e as Error)?.message || e));
    return asLocale(signupLang);
  }
}
