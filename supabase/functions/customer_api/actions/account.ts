// customer_api — the account: me, accept_terms, preferences, save_preferences, set_locale.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { currentCustomerTermsVersion } from '../../_shared/customer_terms.ts';
import { type ActionCtx, J, admin, getSecret } from '../context.ts';

export async function accountActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, cust, recordTermsAcceptance } = c;
    if (action === 'me') return J({ customer: cust, terms_current_version: await currentCustomerTermsVersion(getSecret) });
    if (action === 'accept_terms') {
      if (!cust?.tos_accepted_at) return J({ error: 'finish_signup_first', code: 'finish_signup_first' }, 400);
      const ok = await recordTermsAcceptance();
      return ok ? J({ ok: true, version: await currentCustomerTermsVersion(getSecret) }) : J({ error: 'could not record the acceptance', code: 'terms_not_recorded' }, 500);
    }

    // ── §17 CUSTOMER AI MEMORY: SEE, AND CORRECT ────────────────────────────────────────────────
    // customer_preference, fn_customer_preference_learn and the learning trigger were all green,
    // and the store had ZERO customer-authed readers — the only consumer was os_api. The customer
    // could not see what had been inferred about them, and had no way to say it was wrong. Both
    // verbs are served here; `learned` and `stated` are kept apart on the wire so the customer can
    // tell what they told us from what we guessed.
    if (action === 'preferences') {
      const { data: pref } = await admin.from('customer_preference').select('preferences,consented_at,updated_at').eq('customer_id', cust.id).maybeSingle();
      const p = (pref?.preferences && typeof pref.preferences === 'object') ? pref.preferences as Record<string, unknown> : {};
      return J({ ok: true,
        preferences: p,
        // The store's own two halves, kept apart on the wire under the names it uses. `learned` is
        // an alias for `inferred` because that is the word the customer reads; both are emitted so
        // a client written against either keeps working.
        stated: (p as any).stated ?? {},
        inferred: (p as any).inferred ?? {},
        learned: (p as any).inferred ?? {},
        consented_at: pref?.consented_at ?? null, updated_at: pref?.updated_at ?? null,
        note: 'Learned values come from your past requests. Anything you state here overrides them.' });
    }

    if (action === 'save_preferences') {
      const stated = (body.stated && typeof body.stated === 'object' && !Array.isArray(body.stated)) ? body.stated : null;
      if (!stated) return J({ error: 'stated_object_required' }, 400);
      // fn_customer_preference_learn merges the stated block over the learned one and stamps
      // updated_at — the same routine the trigger uses, so a correction the customer types and a
      // value the system infers can never be written by two different rules.
      const { error: pe } = await admin.rpc('fn_customer_preference_learn', { p_customer_id: cust.id, p_stated: stated });
      if (pe) return J({ error: pe.message }, 500);
      const { data: pref } = await admin.from('customer_preference').select('preferences,consented_at,updated_at').eq('customer_id', cust.id).maybeSingle();
      return J({ ok: true, preferences: pref?.preferences ?? {}, updated_at: pref?.updated_at ?? null });
    }

    // THE LANGUAGE THE PORTAL APOLOGISED FOR NOT SAVING.
    //
    // customers.locale has been read for months — my_inquiries serves it and the portal applies it
    // on a device that has no stored choice — and NOTHING has ever written it. The Account screen
    // said so out loud: "We have no settings endpoint that writes them back to your profile yet,
    // so nothing here is saved to your account." An Arabic customer therefore set their language
    // once per device, forever. This is that endpoint; the apology goes with it.
    //
    // Deliberately narrow: two values, validated against the same pair i18n/routing declares, and
    // it touches one column. A generic profile-patch action here would be a way to write full_name
    // and phone without passing kyc's checks — the phone one now clears phone_verified, and this
    // must not become a route around it.
    if (action === 'set_locale') {
      const loc = String(body.locale || '').toLowerCase();
      if (loc !== 'en' && loc !== 'ar') return J({ error: 'locale must be en or ar' }, 400);
      const { error: le } = await admin.from('customers').update({ locale: loc }).eq('id', cust.id);
      if (le) return J({ error: le.message }, 500);
      return J({ ok: true, locale: loc });
    }
}
