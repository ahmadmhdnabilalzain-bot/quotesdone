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

/** `signupLang` applies ONLY when nobody is registered under these keys yet (the resolver answers null). */
export async function registeredLocale(admin: any, who: { role: string; customerId?: string | null; leadId?: number | null; email?: string | null }, signupLang?: unknown): Promise<Locale> {
  try {
    const { data } = await admin.rpc('fn_registered_locale', { p_role: who.role, p_customer: who.customerId || null, p_lead: who.leadId ?? null, p_email: who.email || null });
    return data == null ? asLocale(signupLang) : asLocale(data);
  } catch (_e) { return asLocale(signupLang); }
}
