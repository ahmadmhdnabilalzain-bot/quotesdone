'use client';
// ROW #5 §24 — SETTINGS. Language, notification preferences, and the account facts underneath them.
//
// ── WHAT IS SETTABLE HERE AND WHAT IS DELIBERATELY NOT ──────────────────────────────────────────
// Two preferences post to supplier_api save_settings, which has its own two-column allowlist: locale
// and email_shared. (14 Sep 2026, #322: the WhatsApp alerts switch is gone. It saved wa_optin, which
// nothing that routes WhatsApp reads any more; the WhatsApp question below - same number / a different
// number verified by code / I don't use WhatsApp - is the one control, and 'I don't use WhatsApp' is off.) Everything else on this screen is READ-ONLY and says so, because
// it is not a preference — verification state, approval state and the terms version are facts the
// platform decides, and a settings screen that appeared to let a supplier edit them would be
// offering a control that silently does nothing.
//
// 14 Sep 2026: the interface language saved here now also SWITCHES the interface (it only stored the
// preference, so "Interface language: العربية → Save" left the page in English); the approval and
// registration states render as words instead of raw codes ("action_required", "not_due"); the
// e-mail, phone and dates are LTR-isolated; the hard-coded dark colours are gone so the light theme
// reads; and the fetch is the portal's shared call() rather than a second copy.
import React, { useEffect, useState } from 'react';
import { call } from './api';
import { WhatsAppChoice } from '../WhatsAppChoice';
import type { WaState } from '../whatsappChoiceText';

type Lang = 'en' | 'ar';
type Settings = {
  company_name?: string; locale?: string | null; email_shared?: boolean | null;
  claimed_by?: string | null; phone?: string | null; approval_status?: string | null;
  registration_status?: string | null; owner_email_verified?: boolean | null;
  owner_phone_verified?: boolean | null; accepted_terms_at?: string | null;
  accepted_terms_version?: string | null; license_expiry?: string | null;
};

const T = {
  en: {
    title: 'Settings', loading: 'Loading your settings…', loadErr: 'We could not load your settings. Please reload the page.',
    prefs: 'Preferences', language: 'Interface language', langNote: 'The portal follows your account language. Changing it here updates your account (EN/AR).', english: 'English', arabic: 'العربية',
    notifications: 'Notifications',
    waNumber: 'WhatsApp number',
    waNumberNote: 'Where your WhatsApp messages go. Choose “I do not use WhatsApp” to receive them by email instead.',
    emailShare: 'Share my e-mail with customers I have quoted',
    emailShareHelp: 'Off by default. When off, customers reach you through the platform only.',
    save: 'Save preferences', saving: 'Saving…', saved: 'Saved.', saveErr: 'We could not save your preferences. Please try again.',
    account: 'Account', accountNote: 'These are set by the platform, not here.',
    email: 'E-mail', phone: 'Phone', approval: 'Approval', registration: 'Registration',
    verified: 'verified', unverified: 'not verified', terms: 'Terms accepted', licence: 'Licence expires',
    none: 'not set', never: 'not yet accepted',
  },
  ar: {
    title: 'الإعدادات', loading: 'جارٍ تحميل إعداداتك…', loadErr: 'تعذّر تحميل إعداداتك. يُرجى إعادة تحميل الصفحة.',
    prefs: 'التفضيلات', language: 'لغة الواجهة', langNote: 'تتبع البوابة لغة حسابك، وتغييرها هنا يحدّث لغة الحساب.', english: 'English', arabic: 'العربية',
    notifications: 'الإشعارات',
    waNumber: 'رقم WhatsApp',
    waNumberNote: 'هنا تصل رسائل WhatsApp. اختر «لا أستخدم WhatsApp» لتصلك بالبريد الإلكتروني بدلًا منها.',
    emailShare: 'شارك بريدي مع العملاء الذين قدّمت لهم عرضًا',
    emailShareHelp: 'مغلق افتراضيًا. عند الإغلاق يتواصل العملاء عبر المنصة فقط.',
    save: 'حفظ التفضيلات', saving: 'جارٍ الحفظ…', saved: 'تم الحفظ.', saveErr: 'تعذّر حفظ تفضيلاتك. يُرجى المحاولة مرة أخرى.',
    account: 'الحساب', accountNote: 'تُحدَّد من المنصة، وليس من هنا.',
    email: 'البريد', phone: 'الهاتف', approval: 'الاعتماد', registration: 'التسجيل',
    verified: 'موثّق', unverified: 'غير موثّق', terms: 'الشروط المقبولة', licence: 'انتهاء الرخصة',
    none: 'غير محدد', never: 'لم تُقبل بعد',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// leads.approval_status and leads.registration_status as words (fn_derive_supplier_registration_state
// and the licence gate write these codes).
const STATE: Record<string, [string, string]> = {
  approved: ['Approved', 'معتمد'], pending: ['Pending review', 'قيد المراجعة'], action_required: ['Action required', 'إجراء مطلوب'],
  rejected: ['Not approved', 'غير معتمد'], not_due: ['Nothing to pay', 'لا رسوم مستحقة'], exempt: ['Free — founding supplier', 'مجاني — مورّد مؤسس'],
  due: ['Yearly fee due', 'الرسوم السنوية مستحقة'], paid: ['Paid', 'مدفوعة'], expired: ['Expired', 'منتهية'],
};
const stateLabel = (lang: Lang, s?: string | null) => (s ? (STATE[s] ? STATE[s][lang === 'ar' ? 1 : 0] : (lang === 'ar' ? 'حالة أخرى' : s.replace(/_/g, ' '))) : t(lang, 'none'));
const date = (lang: Lang, d?: string | null) => (d ? new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '');

function Toggle({ on, onChange, label, help }: { on: boolean; onChange: (v: boolean) => void; label: string; help: string }) {
  return (
    <label className="flex items-start gap-3 cursor-pointer py-2">
      <input type="checkbox" checked={on} onChange={(e) => onChange(e.target.checked)} className="mt-0.5 h-4 w-4 shrink-0 rounded accent-primary" />
      <span className="min-w-0">
        <span className="block text-[13px] text-foreground">{label}</span>
        <span className="block text-[11.5px] text-muted-foreground leading-snug mt-0.5">{help}</span>
      </span>
    </label>
  );
}

// A fact the platform decides. Rendered as text, never as a control.
function Fact({ k, children, tone }: { k: string; children: React.ReactNode; tone?: string }) {
  return (
    <div className="flex justify-between gap-3 py-1.5 border-b border-border last:border-0">
      <span className="text-[12px] text-muted-foreground shrink-0">{k}</span>
      <span className={'text-[12px] text-end break-words text-foreground ' + (tone || '')}>{children}</span>
    </div>
  );
}

export default function SupplierSettings({ token, lang = 'en', onLang }: { token?: string | null; lang?: Lang; onLang?: (l: Lang) => void }) {
  const [s, setS] = useState<Settings | null>(null);
  const [locale, setLocale] = useState<Lang>('en');
  const [langTouched, setLangTouched] = useState(false);
  const [share, setShare] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  // The WhatsApp route is kyc's (whatsapp_*); undefined hides the section until kyc serves it.
  const [waState, setWaState] = useState<WaState | undefined>(undefined);
  const loadWa = () => call('kyc', { action: 'state' }, token).then((k) => setWaState(k && k.whatsapp ? k.whatsapp : undefined)).catch(() => {});
  useEffect(() => { loadWa(); }, [token]);

  useEffect(() => {
    let live = true;
    call('supplier_api', { action: 'settings' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) {
        const x: Settings = j.settings || {};
        setS(x);
        setLocale(x.locale === 'ar' ? 'ar' : x.locale === 'en' ? 'en' : lang);
        setShare(!!x.email_shared);
      } else setErr(t(lang, 'loadErr'));
    });
    return () => { live = false; };
  }, [token]);

  const save = async () => {
    setBusy(true); setMsg(''); setErr('');
    const j = await call('supplier_api', { action: 'save_settings', locale, email_shared: share }, token);
    setBusy(false);
    if (!(j && j.ok)) { setErr(t(lang, 'saveErr')); return; }
    // Switch the interface only when the supplier CHANGED the language here. A stored preference that
    // differs from the page (an /ar visitor whose saved locale is en) must not throw them into another
    // language because they saved a WhatsApp toggle — measured on the ZZ DEMO walk, 14 Sep 2026.
    if (langTouched && locale !== lang && onLang) { onLang(locale); return; }
    setMsg(t(lang, 'saved'));
  };

  if (err && !s) return <div className="qd-panel p-5 text-[13px] text-muted-foreground">{err}</div>;
  if (!s) return <div className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy="true">{t(lang, 'loading')}</div>;

  const yn = (v?: boolean | null) => (v ? t(lang, 'verified') : t(lang, 'unverified'));
  const tone = (v?: boolean | null) => (v ? 'text-ok-fg' : 'text-warn-fg');

  return (
    <div className="space-y-4 max-w-[560px]">
      <section className="qd-panel p-5">
        <h3 className="text-xs uppercase tracking-wide text-muted-foreground mb-3">{t(lang, 'prefs')}</h3>

        <div className="mb-3">
          <label className="block text-[13px] mb-1.5 text-foreground" htmlFor="qd-set-lang">{t(lang, 'language')}</label>
          <select id="qd-set-lang" value={locale} onChange={(e) => { setLocale(e.target.value === 'ar' ? 'ar' : 'en'); setLangTouched(true); }}
            className="w-full rounded-md border border-input bg-card text-foreground px-3 py-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring">
            <option value="en">{t(lang, 'english')}</option>
            <option value="ar">{t(lang, 'arabic')}</option>
          </select>
          <p className="mt-1.5 text-[11.5px] text-muted-foreground">{t(lang, 'langNote')}</p>
        </div>

        <div className="pt-2 border-t border-border">
          <div className="text-[11px] uppercase tracking-wide text-muted-foreground mb-1">{t(lang, 'notifications')}</div>
          <Toggle on={share} onChange={setShare} label={t(lang, 'emailShare')} help={t(lang, 'emailShareHelp')} />
        </div>

        <button type="button" onClick={save} disabled={busy}
          className="w-full mt-3 rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground hover:bg-primary/90 disabled:opacity-50">
          {busy ? t(lang, 'saving') : t(lang, 'save')}
        </button>
        {msg && <p role="status" className="text-[12px] text-ok-fg mt-2">{msg}</p>}
        {err && <p role="alert" className="text-[12px] text-danger-fg mt-2">{err}</p>}
      </section>

      {waState && <section className="qd-panel p-5" aria-labelledby="qd-set-wa">
        <h3 id="qd-set-wa" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">{t(lang, 'waNumber')}</h3>
        <p className="mb-3 text-[11.5px] text-muted-foreground">{t(lang, 'waNumberNote')}</p>
        <WhatsAppChoice token={token} lang={lang} mode="settings" current={waState} mobile={s.phone} onDone={loadWa} />
      </section>}

      <section className="qd-panel p-5">
        <div className="flex justify-between items-baseline mb-2">
          <h3 className="text-xs uppercase tracking-wide text-muted-foreground">{t(lang, 'account')}</h3>
          <span className="text-[11px] text-muted-foreground">{t(lang, 'accountNote')}</span>
        </div>
        <Fact k={t(lang, 'email')} tone={tone(s.owner_email_verified)}><bdi dir="ltr">{s.claimed_by || t(lang, 'none')}</bdi> · {yn(s.owner_email_verified)}</Fact>
        <Fact k={t(lang, 'phone')} tone={tone(s.owner_phone_verified)}><bdi dir="ltr">{s.phone || t(lang, 'none')}</bdi> · {yn(s.owner_phone_verified)}</Fact>
        <Fact k={t(lang, 'approval')}>{stateLabel(lang, s.approval_status)}</Fact>
        <Fact k={t(lang, 'registration')}>{stateLabel(lang, s.registration_status)}</Fact>
        <Fact k={t(lang, 'licence')}>{s.license_expiry ? <bdi dir="ltr">{date(lang, s.license_expiry)}</bdi> : t(lang, 'none')}</Fact>
        <Fact k={t(lang, 'terms')}>{s.accepted_terms_at
          ? <><bdi dir="ltr">{date(lang, s.accepted_terms_at)}</bdi>{s.accepted_terms_version ? <> · <bdi dir="ltr">v{String(s.accepted_terms_version).replace(/^v/i, '')}</bdi></> : null}</>
          : t(lang, 'never')}</Fact>
      </section>
    </div>
  );
}
