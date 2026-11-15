// supplier_api — the profile and its terms: save_settings, accept_terms, settings, set_availability,
// save_profile, pay_registration, dispute_charge.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { clearerCopyAsk } from '../../_shared/clearer_copy.ts';
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { arDays } from '../../_shared/ar_days.ts';
import { isDemoEmail, isFixtureLead } from '../../_shared/demo_identity.ts';
import { mandatorySixMissing, sixInWords } from '../../_shared/supplier_registration.ts';
import { SERVICES_UNCONFIRMED, servicesHoldMail, pendingFounderSubject } from '../../_shared/services_hold_copy.ts';
import { FULL_NAME_REQUIRED, acceptanceNeedsName, clientIp, supplierAcceptanceStands, supplierTermsRecord } from '../../_shared/supplier_terms.ts';
import { recordAcceptance, TERMS_NOT_RECORDED } from '../../_shared/recorded_write.ts';
import { annotate, maskContact } from '../../_shared/observe.ts';
import { type ActionCtx, J, SUPA_URL, admin, cors, failed, logged, secretVal, tellItSeat } from '../context.ts';
import { PROFILE_COLS, clip, personName } from '../lib/fields.ts';
import { phoneWrite } from '../lib/phone_change.ts';
import { emirateList, leadColumnsFor, whereHeWorksWrite } from '../../_shared/where_he_works.ts';
import { notify } from '../lib/quote_acceptance.ts';
import { priorCrossCheck, recordServicesCrossCheck } from '../lib/services_check.ts';

export async function profileActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, email, body, action } = c;
    // ROW #5 §24 — SETTINGS. Language and notification preferences, on their own narrow allowlist.
    //
    // These are deliberately NOT added to PROFILE_COLS. That list carries the emirates ID, the
    // trade licence number and the licence expiry — fields whose writes are what
    // the licence gate and the approval flow are built around. Letting a preferences screen post
    // into the same allowlist would mean a change of interface language travelled through the same
    // door as a change of trade licence number. One column (locale, always 'en'), named here, and nothing else is settable.
    if (action === 'save_settings') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      // Suppliers are always English (founder ruling 1008): whatever locale an old page sends, 'en' is
      // stored. Prevented by scripts/checks/the_supplier_portal_is_always_english.test.mjs.
      if ('locale' in body) upd.locale = SUPPLIER_LOCALE;
      // No e-mail sharing (12 Nov 2026, founder ruling 1668: suppliers stay anonymous until the paid reveal). The
      // e-mail sharing switch and its column are no longer accepted; an old page that still sends one is ignored.
      // Prevented by scripts/checks/nothing_a_supplier_sets_shares_their_contact_with_a_customer.test.mjs.
      const { error } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (error) return failed(String(action), error);
      return J({ ok: true, saved: Object.keys(upd).filter((k) => k !== 'portal_updated_at') });
    }

    // RE-ACCEPTANCE OF A NEW AGREEMENT VERSION (14 Sep 2026, agent: sales_engineer). The founder approved
    // Supplier Agreement v11; clause 23 asks a supplier to re-confirm acceptance of a material change, and
    // the portal now asks on the next sign-in (SupplierPortal ReacceptTerms). This records exactly what
    // save_profile's accept_terms records — when, WHICH version (read server-side from terms_version, never
    // from the browser), the client IP, and the SHA-256 of the exact text accepted (null, never the wrong
    // hash, while the live version is not the one supplier_agreement.ts was exported for).
    // THE AGREEMENT IS ACCEPTED AT ITS OWN STEP, BEFORE THE DOCUMENTS (12 Nov 2026, sales_engineer, built by it_engineer; founder ruling
    // 1672: "directly accepts the terms and conditions. We get the copy of that with the IP address"). Registration accepts here, with
    // `full_name`: the person accepting for the company, the one name typed in sign-up, because a certificate of acceptance names who
    // accepted (his own certificate showed a first name as "Full name" and "Authorised signatory"). The record is unchanged and
    // entirely the server's: the time (supplierTermsRecord's own clock), the IP (clientIp of THIS request), the device (its user-agent
    // header), the version (app_secrets) and the SHA-256 of the exact text; nothing of it is taken from the body. The acceptance fires
    // z21_sign_supplier_on_acceptance, which asks compliance_archive for the certificate. An acceptance of the current version already
    // on file is not written twice (one acceptance, one certificate). The re-acceptance of a new version (Agreement.tsx) sends no name
    // and is unchanged.
    if (action === 'accept_terms') {
      const { data: sup } = await admin.from('leads').select('id,accepted_terms_at,accepted_terms_version,contact_name,signatory_name').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const fullName = body.full_name === undefined ? null : personName(body.full_name);
      if (body.full_name !== undefined && !fullName) return J({ error: 'Please enter your full name: your first name and your family name.', code: 'full_name_required' }, 400);
      const stands = !!sup.accepted_terms_at && await supplierAcceptanceStands(secretVal, sup.accepted_terms_version);
      // A FIRST ACCEPTANCE IS NEVER RECORDED NAMELESS (review of #1987, S5): an older page, or a call made by hand, that sends no full name
      // is refused in plain words. A supplier who accepted before (a new version to re-accept) keeps his stored signatory and is not stopped.
      if (!stands && acceptanceNeedsName(sup, fullName)) return J({ ...FULL_NAME_REQUIRED }, 400);
      // The name is written only with a NEW acceptance: once one stands, a later call never changes who accepted (a re-issued certificate
      // prints the name he accepted under). The person who accepts becomes the contact only where none is on file (ruling 1672: one name
      // typed in registration); a re-acceptance by a supplier whose contact is someone else leaves that contact as it is (second review, R3).
      const names: Record<string, unknown> = {};
      if (fullName && !stands) { names.signatory_name = fullName; if (!String(sup.contact_name ?? '').trim()) names.contact_name = fullName; }
      const rec = stands ? {} : await supplierTermsRecord(secretVal, clientIp(req), req.headers.get('user-agent') || '');
      if (!rec) return J({ error: 'the current agreement version is not set', code: 'no_terms_version' }, 500);
      const upd = { ...names, ...rec };
      // RECORDED OR SAID (13 Nov 2026, review): a lock blip on this write answered a generic 500. It now goes through the same
      // read-back and retry as kyc's (_shared/recorded_write.ts: the same values each try, within the page's 18 s budget), and a
      // write that did not land answers the plain retryable sentence; the portal keeps him on the step (Agreement.tsx: err_generic).
      if (Object.keys(upd).length) {
        const w = await recordAcceptance(() => admin.from('leads').update(upd).eq('id', sup.id).select('id'));
        if (!w.ok) {
          // ...AND A SEAT IS TOLD (15 Nov 2026, review 2 item 6): the same background finding kyc files, keyed on this door.
          tellItSeat('terms_not_recorded:supplier_portal', "supplier_api accept_terms could not record a supplier's acceptance of the agreement",
            'edge function supplier_api, action accept_terms', { kind: 'supplier', lead_id: sup.id, attempts: w.attempts, reason: maskContact(String(w.reason ?? '')).slice(0, 300),
              fixture: isDemoEmail(email), told: 'the person was told it was not recorded and to press again (terms_not_recorded); nothing was let through' });
          return annotate(J({ ...TERMS_NOT_RECORDED }, w.blip ? 503 : 500), { terms_not_recorded: 1, cause_where: 'accept_terms', cause: maskContact(String(w.reason ?? '')).slice(0, 200) });
        }
      }
      return J({ ok: true, accepted_terms_version: (rec as { accepted_terms_version?: string }).accepted_terms_version ?? sup.accepted_terms_version, text_hash_stored: stands ? undefined : !!(rec as { accepted_terms_sha256?: string }).accepted_terms_sha256, already_accepted: stands || undefined });
    }

    if (action === 'settings') {
      const { data: sup } = await admin.from('leads')
        .select('id,company_name,locale,claimed_by,phone,approval_status,registration_status,owner_email_verified,owner_phone_verified,accepted_terms_at,accepted_terms_version,license_expiry')
        .eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // Availability as matching reads it (a busy date that has come reads as available): one definition, in SQL.
      const { data: availability } = await admin.rpc('fn_supplier_availability_of', { p_supplier_id: sup.id });
      return J({ ok: true, settings: sup, availability: availability ?? null });
    }

    // AVAILABILITY (29 Sep 2026, sales_engineer, ledger 1033). Available, busy until a date, or paused: matching
    // (fn_match_capability) skips a busy or paused supplier, and a busy date expires on its day. The only writer is
    // fn_supplier_set_availability, which refuses anything but those three states and a busy date after today.
    if (action === 'set_availability') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const until = body.busy_until == null || body.busy_until === '' ? null : String(body.busy_until);
      if (until !== null && !/^\d{4}-\d{2}-\d{2}$/.test(until)) return J({ ok: false, code: 'busy_date_not_future', error: 'Choose the date you are available again.' }, 400);
      const { data, error } = await admin.rpc('fn_supplier_set_availability', {
        p_supplier_id: sup.id, p_state: String(body.state ?? ''), p_busy_until: until, p_by: 'supplier (portal)',
      });
      if (error) return failed(String(action), error);
      return J(data, data?.ok ? 200 : 400);
    }

    if (action === 'save_profile') {
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,approval_status,registration_submitted_at,locale,accepted_terms_at,accepted_terms_version,phone,owner_phone_verified').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const upd: Record<string, unknown> = { portal_updated_at: new Date().toISOString() };
      for (const c of PROFILE_COLS) if (body[c] !== undefined) upd[c] = body[c];
      // WHO ACCEPTED IS PART OF THE SIGNED RECORD (second review of #1987, R3): once an acceptance is on file, a save never changes the
      // signatory (a direct call could, through PROFILE_COLS); a first acceptance through this older path still records it.
      if (sup.accepted_terms_at) delete upd.signatory_name;
      // leads_trading_name_len allows 160; an empty box clears it (ruling 1672: optional)
      if (upd.trading_name !== undefined) upd.trading_name = (clip(upd.trading_name, 160) ?? '').trim() || null;
      // A verified mobile stays verified only while it is the number that was verified (H1, 9 Nov 2026), and a verified number
      // stays in force until a new one is verified by its code (B2, walk of 12 Nov 2026): see lib/phone_change.ts.
      // Prevented by supplier_api/phone_change.test.ts.
      const phoneDecision = phoneWrite(sup.phone, sup.owner_phone_verified, upd.phone);
      if (phoneDecision === 'kept') delete upd.phone;
      if (phoneDecision === 'unverified') upd.owner_phone_verified = false;
      // WHERE HE WORKS IS ONE LIST (walk of 12 Nov 2026, B1; _shared/where_he_works.ts). The emirates are written to the profile
      // AND, below once the profile is saved, to the capability's coverage_emirates, so the matcher's union is this one list. The
      // home emirate follows as it did (15 Sep 2026, #702): the first chosen one, when none is on file or the one on file is no
      // longer chosen; only one of the seven, never an arbitrary string from the body.
      const workList = Array.isArray(body.service_emirates) ? emirateList(body.service_emirates) : null;
      if (workList) Object.assign(upd, leadColumnsFor(workList, sup.emirate));
      // THE SUPPLIER'S OWN WORDS STAND (15 Sep 2026, sales_engineer). Since 29 Jul this replaced the
      // typed services with the last extraction whenever one existed, so a supplier correcting what their
      // documents were read as could never make the correction stick. The typed text is written as typed;
      // the extraction is still compared with it and the comparison recorded, which is what the double
      // confirmation asked for.
      let servicesCheck: Record<string, unknown> | null = null;
      if (upd.services !== undefined) {
        const prior = await priorCrossCheck(sup.id);
        if (prior.extracted.length) {
          const declared = clip(upd.services, 2000);
          const cc = await recordServicesCrossCheck(sup.id, sup.company_name, prior.extracted, declared);
          servicesCheck = { verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, note: cc.note, extracted_services: prior.extracted, declared_services: declared };
        }
      }
      // TERMS ARE ACCEPTED ONLY WHEN THE FLAG IS EXACTLY TRUE (15 Sep 2026). A bare truthiness test on the
      // flag took any truthy value — "false" as a string, 1, {} — as a legal acceptance. The record (version read
      // server-side, IP, SHA-256 of the exact text) is built in _shared/supplier_terms.ts, the same row
      // accept_terms below and kyc write. Accepting asks compliance_archive for the signed certificate
      // (z21_sign_supplier_on_acceptance); the certificate is the signed-terms item of the six.
      // A save repeating an acceptance already on file for the current version records nothing new: a second
      // record would move the acceptance time and ask for a second certificate (kyc's rule too).
      const accepting = body.accept_terms === true
        && !(sup.accepted_terms_at && await supplierAcceptanceStands(secretVal, sup.accepted_terms_version));
      // the older page's acceptance at Submit: a first acceptance needs the accepting person's name on file (review of #1987, S5)
      if (accepting) {
        const { data: who } = await admin.from('leads').select('signatory_name').eq('id', sup.id).maybeSingle();
        if (acceptanceNeedsName({ accepted_terms_at: sup.accepted_terms_at, signatory_name: who?.signatory_name ?? upd.signatory_name }, null)) return J({ ...FULL_NAME_REQUIRED }, 400);
      }
      if (accepting) {
        const rec = await supplierTermsRecord(secretVal, clientIp(req), req.headers.get('user-agent') || '');
        if (!rec) return J({ error: 'the current agreement version is not set', code: 'no_terms_version' }, 500);
        Object.assign(upd, rec);
      }
      // PROMOTIONAL MESSAGES ARE OPT-IN (19 Oct 2026, founder, legal finding 2; seat: ceo): the separate, unticked
      // box. Exactly true only, never required, written on its own so a missing column cannot fail the save.
      if (body.marketing_consent === true) await admin.from('leads').update({ marketing_consent: true, marketing_consent_at: new Date().toISOString(), marketing_consent_source: 'registration' }).eq('id', sup.id).then(() => null, () => null);
      const wasApproved = String(sup.approval_status || '') === 'approved';
      // The WhatsApp question is answered in sign-up (founder, 15 Sep 2026). Checked beside the six, not
      // added to them, and before anything is written, as it was. Read on its own so a read error cannot
      // null `sup` above (kyc's rule for these columns).
      if (!wasApproved) {
        const { data: wa } = await admin.from('leads').select('whatsapp_opt').eq('id', sup.id).maybeSingle();
        if (!wa?.whatsapp_opt) {
          let six: string[];
          try { six = (await mandatorySixMissing(admin, sup.id)).filter((c) => !(accepting && c === 'reg_terms') && c !== 'reg_name'); }   // ruling 1672: never asked to type a name
          catch (e) { console.error('save_profile:', (e as Error).message); return J({ error: 'check_failed', code: 'check_failed', message: 'We could not check your registration. Please try again.' }, 502); }
          const missing = [...six];
          missing.push('reg_whatsapp');
          return J({ error: 'missing_required', code: 'missing_required', params: { missing }, message: 'Still needed to register: ' + missing.join(', ') + '.' }, 400);
        }
      }
      const firstSubmit = !sup.registration_submitted_at;
      if (firstSubmit) upd.registration_submitted_at = new Date().toISOString();
      // 5 Aug 2026: this write's result was once discarded and a failed save reported success.
      const { error: updErr } = await admin.from('leads').update(upd).eq('id', sup.id);
      if (updErr) {
        console.error('save_profile: leads update failed —', updErr.message);
        return J({ error: 'save_failed', code: 'save_failed', message: 'We could not save your profile. Please try again.' }, 502);
      }
      if (workList) {
        const covErr = await whereHeWorksWrite(admin, sup.id, workList, 'capability');
        if (covErr) {
          console.error('save_profile: coverage_emirates update failed —', covErr);
          return J({ error: 'save_failed', code: 'save_failed', message: 'We could not save where you work. Please try again.' }, 502);
        }
      }
      // The certificate is rendered by compliance_archive after the trigger above posts to it. Give it a
      // few seconds so a supplier who accepts and submits in one go is verified on the signed copy; if it
      // is slower, z20_leads_mandatory_item_landed_reverifies verifies them the moment it lands.
      // THE SUPPLIER NO LONGER WAITS FOR THE RENDER (E2E stage 1, D8, 30 Sep 2026: terms + Save took 4.7-6.0 s, of
      // which up to 4.5 s was this loop polling for the PDF). The acceptance itself is already written above
      // (accepted_terms_at, version, IP, text hash) and is what makes the terms recorded; the certificate is
      // attached when it lands, and z20_leads_mandatory_item_landed_reverifies (fires on signed_terms_path)
      // verifies the supplier at that moment. One read, no sleep.
      let certificatePending = false;
      // The acceptance on file is what Submit needs; its certificate is rendered after it (z21), and since ruling 1672 a supplier accepts
      // at the agreement step, before Submit, so an acceptance made THEN whose certificate has not landed is pending too, never missing.
      const acceptedAt = accepting ? String(upd.accepted_terms_at) : (sup.accepted_terms_at ? String(sup.accepted_terms_at) : '');
      if (acceptedAt) {
        const { data: s } = await admin.from('leads').select('signed_terms_at').eq('id', sup.id).maybeSingle();
        certificatePending = !(s?.signed_terms_at && String(s.signed_terms_at) >= acceptedAt);
      }
      // THE SALES ENGINEER VERIFIES (15 Sep 2026). The approval used to be decided here, from the licence
      // alone; public.fn_sales_engineer_verifies_supplier now decides from the six plus the licence expiry,
      // records the decision, and a trigger refuses any approval the six do not support. pricing_config.
      // auto_approve_suppliers keeps its meaning: off leaves a complete supplier pending for the sales engineer.
      const { data: vd, error: vErr } = await admin.rpc('fn_sales_engineer_verifies_supplier', { p_lead_id: sup.id, p_source: 'save_profile' });
      if (vErr || !(vd as { ok?: boolean })?.ok) {
        console.error('save_profile: verification failed —', vErr?.message || JSON.stringify(vd));
        return J({ error: 'verification_failed', code: 'verification_failed', message: 'Your profile was saved, but we could not check your registration. Please try again.' }, 502);
      }
      const v = vd as { approval_status: string; missing: string[]; reason: string | null; licence_expired: boolean };
      const decision = String(v.approval_status || 'pending');
      // A certificate on its way is not something the supplier still has to do.
      // 'reg_name' is never asked of him: a blank name is his licence being read, unread or another company's, each said in its own words
      // below (ruling 1672; the gate holds it the same way, scripts/sql/a_supplier_is_named_by_his_trade_licence_not_by_typing.sql).
      const stillNeeded = (v.missing || []).filter((c) => !(certificatePending && c === 'reg_terms') && c !== 'reg_name');
      if (v.licence_expired && !stillNeeded.length && decision === 'action_required') stillNeeded.push('licence_expired');
      const { data: full } = await admin.from('leads').select('*').eq('id', sup.id).maybeSingle();
      if (firstSubmit) {
        // A company its licence has not named yet has company_name '' (ruling 1672, create_company.ts): it is "your company" here, never
        // an empty name in "Thank you for registering ." (the founder's record below names the account instead).
        const named = String(full?.company_name || sup.company_name || '').trim();
        const name = named || 'your company';
        const ar = (SUPPLIER_LOCALE as string) === 'ar';   // always false: suppliers are written in English (founder, 28 Sep 2026)
        const mgmt = (await secretVal('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
        const licInfo = full?.trade_license_no ? ` Licence ${full.trade_license_no}${full.license_city ? ', ' + full.license_city : ''}${full.license_expiry ? ', expires ' + full.license_expiry : ''}.` : '';
        const needEn = sixInWords(stillNeeded.filter((c) => c !== 'licence_expired'), 'en') + (stillNeeded.includes('licence_expired') ? (stillNeeded.length > 1 ? ', ' : '') + 'a trade licence that is in date' : '');
        const needAr = sixInWords(stillNeeded.filter((c) => c !== 'licence_expired'), 'ar') + (stillNeeded.includes('licence_expired') ? (stillNeeded.length > 1 ? '، ' : '') + 'رخصة تجارية سارية المفعول' : '');
        const days = 14;
        // A LICENCE NOBODY COULD READ IS NOT "NOTHING NEEDED" (13 Oct 2026, ruling 1230 walk, it_engineer). With only the
        // certificate outstanding at Save, a supplier whose licence name, number or expiry could not be read was told
        // "your account activates automatically ... Nothing is needed from you", and the gate then held them (pending,
        // licence_unreadable / _number_unread / _expiry_unread) with no further notice. Measured on production with an
        // Arabic-only and a blank licence. They are told what could not be read and asked for a clearer copy instead.
        const licUnread = [!full?.licence_legal_name && 'the company name', !full?.trade_license_no && 'the licence number', !full?.license_expiry && 'the expiry date', !full?.license_authority && 'the issuing authority'].filter(Boolean) as string[];
        // OUR READER FAILED, NOT THE FILE (10 Nov 2026, customer_support; _shared/licence_read_state.ts): such a supplier is told
        // it is on our side and asked for nothing; the sweep reads the licence again and the gate holds it as licence_being_read.
        const licBeingRead = licUnread.length > 0 && full?.licence_read_state === 'ours_failed';
        const licUnreadEn = licUnread.length && !licBeingRead ? `Thank you for registering ${name}. We could not read ${licUnread.join(', ').replace(/, ([^,]*)$/, ' and $1')} on the trade licence you uploaded, so your registration is on hold. ${clearerCopyAsk('supplier', 'en', 'your trade licence')} Upload it in the Documents tab of your supplier portal: https://quotesdone.com/portal` : '';
        // Sent only for a decision short of approved (an approval is confirmed by supplier_approved, below): the unread
        // licence is said first, with whatever else is still missing.
        const supplierMail = full?.licence_gate_reason === 'licence_authority_not_uae'
          ? { subject: 'Your QuotesDone registration: please send your UAE trade licence', body: `Thank you for registering ${name}. The trade licence you uploaded was not issued by a UAE authority, and QuotesDone registers companies licensed in the UAE, so your registration is on hold. Please upload your current UAE trade licence in the Documents tab of your supplier portal: https://quotesdone.com/portal` }
          : licUnreadEn
          ? { subject: 'Your QuotesDone registration: please send a clearer trade licence', body: licUnreadEn + (stillNeeded.length ? ` We also still need: ${needEn}.` : '') }
          : licBeingRead
          ? { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name}. Our document reader has not finished reading the trade licence you uploaded. That is on our side, not yours: we read it again automatically and e-mail you if anything is needed.` + (stillNeeded.length ? ` We do still need: ${needEn}.` : ' Nothing else is needed from you for now.') }
          : decision === 'pending' && v.reason === SERVICES_UNCONFIRMED
          ? servicesHoldMail(name)
          : decision === 'pending'
          ? (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name}. اكتملت البنود الستة المطلوبة، ويتولّى مهندس المبيعات مراجعة طلب التسجيل حاليًا، وسنوافيكم برسالة فور اعتماده.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name}. All six required items are in, and our sales engineer is reviewing your registration now. We will e-mail you as soon as it is approved.` })
          : !stillNeeded.length
          // Only the certificate is outstanding and it is on its way: nothing is asked of the supplier.
          ? (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name}. نعمل حاليًا على إصدار شهادة موافقتكم الموقّعة على شروط المورّد، وسيُفعَّل حسابكم تلقائيًا فور صدورها، دون أن يلزمكم أي إجراء.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name}. We are issuing the signed certificate of your acceptance of the supplier terms; your account activates automatically as soon as it is ready. Nothing is needed from you.` })
          : (ar ? { subject: 'استلمنا طلب تسجيلكم لدى QuotesDone', body: `نشكركم على تسجيل ${name} لدى QuotesDone.\n\nلم يُفعَّل حسابكم بعد، إذ لا يزال ينقصه ما يلي: ${needAr}.\n\nيُرجى تسجيل الدخول إلى بوابة المورّد واستكمال ذلك، وسيُفعَّل حسابكم تلقائيًا فور اكتمال البنود الستة، دون قائمة انتظار أو مراجعة يدوية.\n\nنرجو استكمال ذلك خلال ${arDays(days)}؛ إذ يُغلق طلب التسجيل بعدها تلقائيًا، ويسعدنا تسجيلكم من جديد في أي وقت.` }
                : { subject: 'Thanks for registering with QuotesDone', body: `Thank you for registering ${name} with QuotesDone.\n\nYour account is not active yet because it still needs: ${needEn}.\n\nPlease sign in to your supplier portal and complete it. Your account activates automatically as soon as all six required items are in — there is no waiting list and no manual queue.\n\nPlease do this within ${days} days. After that this registration closes automatically, and you are welcome to start again at any time.` });
        // A FIXTURE FILES NO ADMIN RECORD (13 Oct 2026, customer_support): the supplier_registered notice became a
        // delivery.request handoff and a routed org_task on every walk run. The walk's own registration_received
        // (to its @example.invalid address, captured) still goes, so the walk keeps proving the supplier is told.
        const fixture = isFixtureLead(full ?? sup);
        await notify([
          ...(fixture ? [] : [{ type: 'supplier_registered', to_email: mgmt, to_role: 'admin', lead_id: sup.id,
            subject: decision === 'approved' ? 'New supplier approved by the sales engineer' : decision === 'pending' ? pendingFounderSubject(v.reason) : 'Supplier registration incomplete',
            body: `New supplier "${named || '(not yet named by its trade licence) ' + email}"${full?.emirate ? ' (' + full.emirate + ')' : ''} registered. Decision: ${decision}${stillNeeded.length ? ' — still needs: ' + needEn : (certificatePending ? ' — the signed terms certificate is being issued' : '')}. No action needed; this is a record.${licInfo}` }]),
          // ONE CONFIRMATION, NOT TWO (3 Nov 2026, customer_support). An approved first save used to send this "Your QuotesDone
          // supplier account is active" notice AND, from the same approval, trg_sales_engineer_tells_the_supplier_he_is_approved's
          // supplier_approved notice ("You are verified on QuotesDone"), each with its WhatsApp twin: two emails and two
          // WhatsApp messages for one event. The approval trigger fires on every path that approves a supplier (this save, the
          // certificate landing, the sales engineer), so it is the one confirmation; this notice goes only while the
          // registration is not yet active. prevented by: supplier_api/one_confirmation_per_activation.test.ts
          ...(decision === 'approved' ? [] : [{ type: 'registration_received', to_email: email, to_role: 'supplier', lead_id: sup.id, lang: ar ? 'ar' : 'en', ...supplierMail }]),
        ]);
      }
      if (!wasApproved && decision !== 'approved' && stillNeeded.length) {
        return J({ error: 'missing_required', code: 'missing_required', saved: true, approval_status: decision, params: { missing: stillNeeded }, message: 'Saved. Still needed to register: ' + stillNeeded.join(', ') + '.', services_crosscheck: servicesCheck }, 400);
      }
      return J({ ok: true, approval_status: decision, terms_certificate: certificatePending ? 'pending' : undefined, services_crosscheck: servicesCheck, phone_kept: phoneDecision === 'kept' || undefined });
    }
    // Registration fee - creates a Stripe Checkout Session and nothing else.
    //
    // This endpoint previously wrote registration_status:'paid' and registration_fee_due:0
    // directly, with no payment taken, no Stripe call and no webhook. Any supplier holding a
    // valid JWT could clear their own AED 1,000 fee with a single POST. It is dormant today
    // only because every supplier is inside the free tier; it would have become a live revenue
    // hole the day the 1,000th supplier registered.
    //
    // supplier_pay already carried the correct discipline for supplier_dues - "this endpoint
    // only CREATES a Checkout Session, it never marks anything paid". Registration was the one
    // money path that never got it. registration_status is now written solely by stripe_webhook
    // on a signature-verified checkout.session.completed event.
    // PAYMENTS ARE THE ACCOUNTANT'S (founder, 14 Sep 2026). The registration checkout that lived here
    // moved to supplier_pay, which the accountant owns; this action is a pass-through with the
    // supplier's own session token so an older portal build keeps working. It creates nothing itself.
    if (action === 'pay_registration') {
      const pr = await fetch(`${SUPA_URL}/functions/v1/supplier_pay`, { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: req.headers.get('Authorization') || '' },
        body: JSON.stringify({ action: 'registration', return_url: body.return_url }) });
      return new Response(await pr.text(), { status: pr.status, headers: cors });
    }
    // A SUPPLIER DISPUTES A CHARGE. The portal is the sales engineer's voice, the figures are the
    // accountant's: the dispute is handed over (charge.disputed), the accountant recomputes the charge
    // from the refund record, and the answer comes back to the supplier in the sales engineer's words.
    if (action === 'dispute_charge') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const { data: due } = await admin.from('supplier_dues').select('id,supplier_id').eq('id', Number(body.due_id)).maybeSingle();
      if (!due || Number(due.supplier_id) !== Number(sup.id)) return J({ error: 'not_found' }, 404);
      // ONE OPEN DISPUTE PER CHARGE, AND NEVER AN EMPTY ONE (12 Nov 2026, sales_engineer, built by it_engineer; second review of the walk
      // fixes, R3). The handoff is keyed on the charge and the clock, so a retry after a lost answer (the portal stops waiting at 20 s
      // and said "not sent") filed a second dispute with the accountant. A dispute already open for this charge is answered as recorded,
      // with no second handoff; a closed one ('done') lets a new dispute through. The reason is required here as well as in the form.
      const reason = String(body.reason || '').trim().slice(0, 1000);
      if (!reason) return J({ error: 'reason_required', code: 'reason_required', message: 'Please say what is wrong with the charge.' }, 400);
      const { data: open, error: oErr } = await admin.from('agent_actions').select('id').eq('kind', 'handoff').eq('agent', 'accountant')
        .like('target_id', 'charge.disputed:' + String(due.id) + ':%').not('status', 'in', '(done,failed)').limit(1).maybeSingle();
      if (oErr) { logged('dispute open read', oErr); return J({ error: 'dispute_not_recorded' }, 503); }
      if (open) return J({ ok: true, handoff_id: open.id, already_recorded: true, message: 'We have your query. We are checking the charge against the payment record and will write back to you.' });
      const { data: hid, error: hErr } = await admin.rpc('fn_seat_handoff', {
        p_from: 'sales_engineer', p_to: 'accountant', p_type: 'charge.disputed', p_subject_table: 'supplier_dues',
        p_subject_id: String(due.id) + ':' + Date.now(),
        p_payload: { supplier_id: sup.id, due_id: due.id, reason } });
      if (hErr) { logged('dispute handoff', hErr); return J({ error: 'dispute_not_recorded' }, 503); }
      return J({ ok: true, handoff_id: hid, message: 'We have your query. We are checking the charge against the payment record and will write back to you.' });
    }
}
