// wa_template_setup - manages the WhatsApp Content template used for document-expiry notices:
// create it, submit it for Meta approval, register the SID in app_secrets, and inspect delivery.
//
// WHY THIS IS A FUNCTION RATHER THAN A SCRIPT: the Twilio API key lives in app_secrets. Running
// server-side means the credential is read and used inside the platform and never leaves it.
// Every response returns status and SIDs only - no secret is ever echoed.
//
// META TEMPLATE RULE LEARNED THE HARD WAY: the first submission was rejected with
//   "Variables can't be at the start or end of the template."
// because the body finished with {{2}}. Both bodies below open AND close with literal text.
// Keep that shape if you edit the copy.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal, secretOk } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { WA_INVITE_BUTTONS, WA_INVITE_SAMPLE_TRADE, WA_INVITE_TEMPLATE_EN } from '../_shared/marketing_send_gate.ts';
import { J } from '../_shared/json_response.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string | undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.

// 3 SEP 2026: one function, several templates. The key is chosen per call (body.key) from this
// catalogue; the default stays the document-expiry notice this function was written for. Every body
// opens AND closes with literal text (the Meta rule in the header), and {{1}} / {{2}} are the same two
// variables send_whatsapp's varsFor() supplies: a short summary and a link.
// 18 SEP 2026 — a template is no longer always a twilio/text UTILITY body. `category` and `types`
// are now decided per catalogue entry so the login code can be submitted as what Meta requires an
// AUTHENTICATION template to be: a body Meta writes and localises itself, one variable (the code),
// a copy-code button and a stated expiry. A UTILITY entry keeps the shape it always had, so nothing
// about the five existing keys changes.
// A UNION, NOT ONE ALL-OPTIONAL BAG (typescript review, 18 Sep 2026). Making every field optional so
// the authentication entry could omit the bodies would have removed the compiler's only protection on
// the five UTILITY entries: a future key missing `en` would submit an EMPTY template body to Meta for
// approval rather than fail to build — precisely the class of mistake this file's header records
// thirteen rejections learning. Each kind now states its own required fields.
type Catalogue =
  | { category?: 'UTILITY'; en: string; ar: string; sample1_en: string; sample1_ar: string;
      url: string; sample2_en?: string; sample2_ar?: string }
  // AUTHENTICATION: Meta owns the body text of an authentication template and renders it in the
  // recipient's own language, so there is nothing to author or translate except the button label.
  | { category: 'AUTHENTICATION'; copy_code_en: string; copy_code_ar: string; expiry_minutes: number }
  // MARKETING (19 Oct 2026): written to suppliers, who are only ever written to in English, so it has no Arabic.
  // 27 Oct 2026: one variable (the trade) and no link (ruling 1301); quick-reply buttons instead of a URL.
  | { category: 'MARKETING'; en: string; sample1_en: string; buttons: readonly { id: string; title: string }[] }
  // UTILITY, ENGLISH ONLY (2 Nov 2026): a notice written only to suppliers, who are only ever written to in English
  // (founder, 28 Sep 2026), so there is no Arabic body to author and an Arabic create is refused.
  | { category?: 'UTILITY'; english_only: true; en: string; sample1_en: string; url: string };
const CATALOGUE: Record<string, Catalogue> = {
  // 18 SEP 2026 — THE SIGN-IN CODE. Founder authorised this submission. AUTHENTICATION category:
  // Meta refuses to carry a one-time code under UTILITY, and refuses an authentication body written
  // by us — the body, its security line and its expiry line are Meta's own strings, localised per
  // language, with exactly one variable {{1}} that is the code itself. So the "variables can't be at
  // the start or end" rule in this file's header does NOT apply here: there is no body of ours for a
  // variable to sit at the end of.
  //
  // The previous attempt under the key control_mode_code was REJECTED on 7 Sep with
  // "This WhatsApp business account does not have permission to create message template"
  // (OAuthException 10 / 2388185) — a WABA capability refusal, not a content refusal. The WABA has
  // since been verified, so this resubmission is also the measurement of whether that is now open.
  login_code: {
    category: 'AUTHENTICATION',
    copy_code_en: 'Copy code', copy_code_ar: 'نسخ الرمز',
    expiry_minutes: 10,
  },
  // 18 SEP 2026 — the supplier's own account notices: a quote put on hold for missing specs, that
  // hold lifted, and the collaboration warning. send_whatsapp's tmplKey() has mapped six types to
  // this key since 14 Sep with no SID to send them, so every one of them has been sitting queued
  // while only the email twin went. fn_supplier_notice queues the email FIRST and always; this
  // template is the second channel, never the record. UTILITY: a transactional notice about the
  // recipient's own account. {{1}} is the notice subject varsFor() passes, {{2}} the portal link;
  // both are bounded by literal text, which is the rule thirteen rejections were spent learning.
  supplier_account_notice: {
    en: 'QuotesDone update about your supplier account: {{1}}. Please open your supplier portal for the full details and any action needed: {{2}} Thank you.',
    // Arabic reviewed 18 Sep 2026 by a dedicated Arabic pass, not machine-translated. Two calques were
    // removed: `حساب المورّد الخاص بك` (an English possessive hung off a definite idāfa — `حسابك كمورّد`
    // is what a Gulf business writer produces, and approved template #2 already models it with `بوابتك`),
    // and `وأي إجراء مطلوب` (`أي` + indefinite singular is word-for-word "any action needed"; the definite
    // plural carries it idiomatically and keeps the two conjoined objects symmetric).
    // 22 SEP 2026 (documents-language audit, DL-05). The 18 Sep pass still addressed a supplier company
    // in the singular and opened with a preposition an Arabic writer would not use here. The formal
    // plural is what the invitation and the reminders use, and the company is "your supplier account"
    // as one idāfa, not a possessive hung off it. Resubmitted to Meta as UTILITY.
    ar: 'تحديث من QuotesDone بشأن حسابكم كمورّد: {{1}}. يُرجى الدخول إلى بوابة الموردين للاطلاع على التفاصيل والإجراءات المطلوبة: {{2}} وشكرًا لكم.',
    sample1_en: 'New requests to your company are paused on QuotesDone',
    // `استقبال`, not `إيقاف إرسال … إلى شركتك`: nothing stopped being sent, the company stopped receiving.
    // The brand is not repeated — the body it lands in already opens with `تحديث من QuotesDone`.
    // The Arabic passive verb, not the "تمّ + verbal noun" construction a translator reaches for.
    sample1_ar: 'أُوقف استقبال شركتكم للطلبات الجديدة مؤقتًا',
    url: 'https://quotesdone.com/portal',
  },
  // 6 SEP 2026 — the founder's own alert. Founder: "whatsapp token with twilio is with you, fix the
  // template yourself." Until today alert_founder sent him a freeform Body, which WhatsApp never
  // delivers business-initiated: every founder WhatsApp on the account (13-16 Aug) is 'undelivered'
  // 63016. {{1}} is the "[level] event" line, {{2}} the detail; both are literal-bounded. UTILITY:
  // a status notice to the account's own owner, not marketing.
  founder_alert: {
    en: 'QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act.',
    ar: 'تنبيه من QuotesDone: {{1}}. التفاصيل: {{2}}. افتح نظام التشغيل للتصرف.',
    sample1_en: '[high] Backup may have failed or is overdue', sample1_ar: '[high] قد يكون النسخ الاحتياطي قد فشل أو تأخر',
    sample2_en: 'last successful backup 2026-09-05 08:00 UTC; the IT operations engineer owns the check',
    sample2_ar: 'آخر نسخة احتياطية ناجحة 2026-09-05 08:00 UTC؛ مهندس عمليات تقنية المعلومات مسؤول عن الفحص',
    url: 'https://quotesdone.com/os',
  },
  supplier_doc_expiry: {
    en: 'QuotesDone reminder: {{1}}. Please renew it to keep receiving customer requests. You can update it here: {{2}} Thank you.',
    // 22 Sep 2026 (DL-05): formal plural, and a link is entered rather than "updated here".
    ar: 'تذكير من QuotesDone: {{1}}. يُرجى تجديدها لمواصلة استقبال طلبات العملاء، ويمكنكم تحديثها عبر الرابط: {{2}} وشكرًا لكم.',
    sample1_en: 'your trade licence expires on 2026-08-01', sample1_ar: 'تنتهي رخصتكم التجارية في 2026-08-01',
    url: 'https://quotesdone.com/portal',
  },
  // 23 SEP 2026 — a reasoned answer that could not be sent inside the 24-hour window. Under the model hold a
  // question waits in the seat's queue (_shared/think.ts); when it is answered after the customer's window
  // has closed, WhatsApp allows only an approved template. UTILITY: the reply to the customer's own question.
  // {{1}} is their question (shortened), {{2}} the answer; both literal-bounded. Needs submitting to Meta.
  support_reply: {
    en: 'QuotesDone support, about your question "{{1}}": {{2}}. You can reply here with anything else you need.',
    ar: 'فريق دعم QuotesDone، بخصوص استفساركم «{{1}}»: {{2}}. ويسعدنا الرد على أي استفسار آخر عبر هذه المحادثة.',
    sample1_en: 'what depth can my villa pool be', sample1_ar: 'ما العمق المسموح لمسبح الفيلا',
    sample2_en: 'in Dubai a private pool needs a Dubai Municipality permit and a fence of at least 1.2 m',
    sample2_ar: 'في دبي يحتاج المسبح الخاص إلى تصريح من بلدية دبي وسياج لا يقل ارتفاعه عن 1.2 متر',
    url: 'https://quotesdone.com',
  },
  // 19 OCT 2026 (marketing, ruling 1184) — the WhatsApp supplier invitation. MARKETING category: it is a
  // business-initiated invitation to a company that has not opted in, which Meta allows only as MARKETING.
  // The body names the opt-out (STOP), which wa_inbound honours through fn_wa_supplier_invite_opt_out.
  // 27 Oct 2026 (ruling 1301): the text is _shared/marketing_send_gate.ts WA_INVITE_TEMPLATE_EN, the email the
  // founder approved said over WhatsApp: no link, {{1}} the trade only, a "Set up my page" and a "Stop" button.
  // It has NEVER been submitted (no messaging_template row, measured 27 Oct): the campaign is paused (ledger 1312).
  // Suppliers are written to in English only, so the template has no Arabic and an Arabic create is refused.
  // Rows are queued only by fn_wa_supplier_invite_queue, which writes nothing unless wa_supplier_invite_golive AND
  // invite_enabled are 'true', no brake is open, and the lead has opted in to WhatsApp.
  supplier_invite: {
    category: 'MARKETING',
    en: WA_INVITE_TEMPLATE_EN,
    sample1_en: WA_INVITE_SAMPLE_TRADE,
    buttons: WA_INVITE_BUTTONS,
  },
  // 2 NOV 2026 (it_engineer) — the registration reminder. fn_supplier_registration_reminders_due sends the email and
  // fn_wa_fanout queues its WhatsApp twin to the confirmed number; until now send_whatsapp had no template for the type
  // and skipped it (measured: the first reminder, 2 Nov 05:00Z, skipped with "no WhatsApp template mapping"). UTILITY:
  // a notice about the recipient's own started registration. {{1}} is what the registration still needs (or that it
  // has not started), {{2}} the portal - the plain portal link, never a claim link (ruling 1301, "safer to not send
  // links", and the approved supplier_account_notice already carries this one). Both are bounded by literal text.
  // The opt-out is named because the email offers one; wa_inbound honours STOP.
  supplier_registration_reminder: {
    english_only: true,
    en: 'QuotesDone reminder: {{1}}. You can continue your supplier registration here: {{2}} If you would rather not receive these reminders, reply STOP. Thank you.',
    sample1_en: 'your supplier registration still needs the trade licence, the company profile and the signed supplier terms',
    url: 'https://quotesdone.com/portal',
  },
  // 3 NOV 2026 (customer_support) — the customer's account-active confirmation. Founder, 3 Nov 2026: after a customer
  // registers "he gets a confirmation on email and whatsapp that his account is active". fn_customer_account_active_notice
  // queues the email when the customer accepts the terms (the last step of sign-up) and fn_wa_fanout its twin to the
  // confirmed number. UTILITY: a notice about the recipient's own account. {{1}} is the email's subject ("Your QuotesDone
  // account is active", in the customer's language), {{2}} the account page. Both are bounded by literal text.
  customer_account_active: {
    en: 'QuotesDone: {{1}}. You can now post a request and compare quotes from verified suppliers here: {{2}} Thank you.',
    ar: 'QuotesDone: {{1}}. يمكنكم الآن نشر طلبكم ومقارنة عروض الأسعار من موردين موثّقين عبر الرابط: {{2}} وشكرًا لكم.',
    sample1_en: 'Your QuotesDone account is active', sample1_ar: 'أصبح حسابكم على QuotesDone مفعّلًا',
    url: 'https://quotesdone.com/me',
  },
  // 3 NOV 2026 (customer_support) — the invoice for a paid reveal, on WhatsApp. Founder, 3 Nov 2026: "an invoice from our
  // app is shared on email and whatsapp with the customer". The carrier is invoice_ready ("Your invoice is ready", the
  // invoice.issued handoff): reveal_invoice (action 'attach') renders the QuotesDone invoice, attaches it to that email and
  // puts the same PDF reference on its WhatsApp twin; send_whatsapp signs a 7-day link to it as it sends. {{1}} is the
  // notice's subject, {{2}} the invoice link (the account page if no invoice was attached). Both are literal-bounded.
  customer_reveal_invoice: {
    en: 'QuotesDone: {{1}}. You can download the invoice for your payment here: {{2}} Thank you.',
    ar: 'QuotesDone: {{1}}. يمكنكم تنزيل فاتورة دفعتكم عبر الرابط: {{2}} وشكرًا لكم.',
    sample1_en: 'Your invoice is ready', sample1_ar: 'فاتورتكم جاهزة',
    url: 'https://quotesdone.com/me',
  },
  // The supplier's side of a paid reveal (founder, 19 Aug 2026: both parties, both channels).
  supplier_quote_accepted: {
    en: 'QuotesDone: a customer has paid to reveal your quote for {{1}}. Please respond within 5 working days. Open your portal here: {{2}} Thank you.',
    // 22 Sep 2026 (DL-05): the active verb سدّد, not "قام … بالدفع", and the formal plural throughout.
    ar: 'QuotesDone: سدّد أحد العملاء رسوم الاطلاع على عرض سعركم لـ {{1}}. يُرجى الرد خلال 5 أيام عمل عبر بوابتكم: {{2}} وشكرًا لكم.',
    sample1_en: 'supply and install aluminium windows for a villa in Dubai', sample1_ar: 'توريد وتركيب نوافذ ألمنيوم لفيلا في دبي',
    url: 'https://quotesdone.com/portal',
  },
};

Deno.serve(observe('wa_template_setup', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'wa_template_setup');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    const acct = await sec('twilio_account_sid');
    const ks = await sec('twilio_api_key_sid');
    const kk = await sec('twilio_api_key_secret');
    if (!ks || !kk) return J({ error: 'twilio_not_configured' }, 503);
    const auth = 'Basic ' + btoa(ks + ':' + kk);
    const action = String(body.action || 'status');
    const KEY = String(body.key || 'supplier_doc_expiry');
    // 6 SEP 2026: only 'create' needs the copy. 'status' reads whatever wa_template_sids registered — the
    // three July keys were created by hand before this catalogue existed, and the ledger must carry
    // Twilio's answer for them too.
    if (action === 'create' && !CATALOGUE[KEY]) return J({ ok: false, error: 'unknown_key', known: Object.keys(CATALOGUE) }, 400);

    // Delivery inspection. Used to confirm where a message actually ended up - an API-level
    // success only means Twilio accepted it, not that anyone received it.
    if (action === 'msg_check') {
      const to = String(body.to || '');
      const url = 'https://api.twilio.com/2010-04-01/Accounts/' + acct + '/Messages.json?To=' + encodeURIComponent('whatsapp:' + to) + '&PageSize=5';
      const r = await timedFetch(url, { headers: { 'Authorization': auth } });
      const j = await r.json().catch(() => ({}));
      const msgs = (j?.messages || []).map((m: any) => ({
        sid: m.sid, to: m.to, status: m.status, error_code: m.error_code, error_message: m.error_message,
        date_sent: m.date_sent, num_segments: m.num_segments, price: m.price }));
      return J({ ok: r.ok, http: r.status, count: msgs.length, messages: msgs });
    }

    if (action === 'delete') {
      const sid = String(body.content_sid || '');
      if (!/^HX[0-9a-f]{32}$/i.test(sid)) return J({ error: 'bad_sid' }, 400);
      const r = await timedFetch('https://content.twilio.com/v1/Content/' + sid, { method: 'DELETE', headers: { 'Authorization': auth } });
      return J({ ok: r.ok, http: r.status, deleted: sid });
    }

    if (action === 'create') {
      const lang = String(body.language || 'en');
      const isAr = lang === 'ar';
      const cat = CATALOGUE[KEY];
      const category = cat.category || 'UTILITY';
      const stamp = Date.now().toString(36);

      // An AUTHENTICATION template carries no body and no variables of ours: Meta writes the text,
      // localises it, and substitutes the single code variable itself. Sending `variables` or a
      // twilio/text body with it is refused. Everything else is the two-variable UTILITY notice this
      // function was written for.
      if ((cat.category === 'MARKETING' || 'english_only' in cat) && isAr) return J({ step: 'create', ok: false, error: 'english_only: suppliers are written to in English only' }, 400);
      const payload = 'english_only' in cat
        ? { variables: { '1': cat.sample1_en, '2': cat.url }, types: { 'twilio/text': { body: cat.en } } }
        : cat.category === 'AUTHENTICATION'
        ? { types: { 'whatsapp/authentication': {
              add_security_recommendation: true,
              code_expiration_minutes: cat.expiry_minutes,
              actions: [{ type: 'COPY_CODE', copy_code_text: isAr ? cat.copy_code_ar : cat.copy_code_en }],
            } } }
        : cat.category === 'MARKETING'
        ? { variables: { '1': cat.sample1_en },
            types: { 'twilio/quick-reply': { body: cat.en, actions: cat.buttons.map((b) => ({ id: b.id, title: b.title })) } } }
        : { variables: { '1': isAr ? cat.sample1_ar : cat.sample1_en,
                         // {{2}} is a link for the customer/supplier notices, a detail for the founder alert
                         '2': (isAr ? cat.sample2_ar : cat.sample2_en) || cat.url },
            types: { 'twilio/text': { body: isAr ? cat.ar : cat.en } } };

      const createRes = await timedFetch('https://content.twilio.com/v1/Content', {
        method: 'POST', headers: { 'Authorization': auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ friendly_name: 'quotesdone_' + KEY + '_' + lang + '_' + stamp, language: lang, ...payload }) });
      const created = await createRes.json().catch(() => ({}));
      if (!createRes.ok) return J({ step: 'create', ok: false, http: createRes.status, error: created?.message || created }, 502);
      const sid = String(created?.sid || '');
      if (!sid) return J({ step: 'create', ok: false, error: 'no sid returned', raw: created }, 502);

      // UTILITY for a transactional notice about the recipient's own account; AUTHENTICATION only for a one-time code (Meta refuses a code under any other category).
      const apprName = ('quotesdone_' + KEY + '_' + lang + '_' + stamp).toLowerCase().replace(/[^a-z0-9_]/g, '_');
      const apprRes = await timedFetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests/whatsapp', {
        method: 'POST', headers: { 'Authorization': auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: apprName, category }) });
      const appr = await apprRes.json().catch(() => ({}));

      let registered = false; let sids: Record<string, any> = {};
      try {
        sids = JSON.parse((await sec('wa_template_sids')) || '{}');
        sids[KEY] = { ...(sids[KEY] || {}), [lang]: sid };
        const { error } = await admin.from('app_secrets').update({ value: JSON.stringify(sids) }).eq('key', 'wa_template_sids');
        registered = !error;
      } catch (_e) { /* reported below */ }

      // 6 SEP 2026: the ledger. messaging_template is what send_whatsapp trusts (only 'approved' is
      // ever sent) and what fn_company_self_knowledge_sync renders, so the approval status is company
      // knowledge from the moment of submission — never a question for the founder.
      const apprStatus = String(appr?.status || appr?.whatsapp?.status || (apprRes.ok ? 'pending' : 'unknown'));
      const nowIso = new Date().toISOString();
      const { error: ledgerErr } = await admin.from('messaging_template').upsert({
        sid, channel: 'whatsapp', template_key: KEY, lang, name: apprName, category, status: apprStatus,
        submitted_at: nowIso, last_checked_at: nowIso, approved_at: apprStatus === 'approved' ? nowIso : null,
        rejection_reason: apprRes.ok ? (appr?.whatsapp?.rejection_reason || null) : String(appr?.message || JSON.stringify(appr)).slice(0, 500),
      }, { onConflict: 'sid' });

      return J({ step: 'create', ok: true, language: lang, content_sid: sid, approval_name: apprName,
        approval_http: apprRes.status, approval_status: apprStatus,
        approval_error: apprRes.ok ? null : (appr?.message || appr),
        registered_in_app_secrets: registered, ledger_written: !ledgerErr, ledger_error: ledgerErr?.message || null,
        template_keys_now: Object.keys(sids) });
    }

    if (action === 'status') {
      const sids = JSON.parse((await sec('wa_template_sids')) || '{}');
      const entry = sids[KEY] || {};
      const out: Record<string, unknown> = {};
      for (const [lang, sid] of Object.entries(entry)) {
        const r = await timedFetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests', { headers: { 'Authorization': auth } });
        const j = await r.json().catch(() => ({}));
        const st = String(j?.whatsapp?.status || j?.status || 'unknown');
        out[lang] = { sid, http: r.status, status: st, rejection_reason: j?.whatsapp?.rejection_reason || null };
        // 6 SEP 2026: Twilio's answer lands in the ledger, so the sender and the self-knowledge read it.
        if (r.ok) {
          const nowIso = new Date().toISOString();
          const { data: cur } = await admin.from('messaging_template').select('approved_at').eq('sid', sid).maybeSingle();
          await admin.from('messaging_template').upsert({
            sid, channel: 'whatsapp', template_key: KEY, lang, status: st, last_checked_at: nowIso,
            name: j?.whatsapp?.name || null, category: j?.whatsapp?.category || null,
            rejection_reason: j?.whatsapp?.rejection_reason || null,
            approved_at: st === 'approved' ? (cur?.approved_at || nowIso) : null,
          }, { onConflict: 'sid' });
        }
      }
      return J({ ok: true, key: KEY, registered_languages: Object.keys(entry), approvals: out });
    }

    return J({ error: 'unknown action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
