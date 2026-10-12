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
// 12 Oct 2026 (founder ruling 1008, suppliers are always English): the interface-language select is
// gone and save_settings no longer sends a locale; supplier_api stores 'en' whatever arrives.
// Prevented by scripts/checks/the_supplier_portal_is_always_english.test.mjs.
//
// 14 Sep 2026: the interface language saved here now also SWITCHES the interface (it only stored the
// preference, so "Interface language: العربية → Save" left the page in English); the approval and
// registration states render as words instead of raw codes ("action_required", "not_due"); the
// e-mail, phone and dates are LTR-isolated; the hard-coded dark colours are gone so the light theme
// reads; and the fetch is the portal's shared call() rather than a second copy.
import React, { useEffect, useState } from 'react';
import { call } from './api';
import { PrivacyControls } from '../PrivacyControls';
import { firstRead } from './tabPrefetch';
import { WhatsAppChoice } from '../WhatsAppChoice';
import type { WaState } from '../whatsappChoiceText';
import { Ltr } from '@/lib/Ltr';
import SupplierAvailability, { type Availability } from './SupplierAvailability';

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
    // "Please reload the page" was the only way out while this failure could not resolve. It now
    // resolves into this message WITH a retry, so the copy names the button instead of the browser.
    title: 'Settings', loading: 'Loading your settings…', loadErr: 'We could not load your settings.', retry: 'Try again',
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
    title: 'الإعدادات', loading: 'جارٍ تحميل إعداداتكم…', loadErr: 'تعذّر تحميل إعداداتكم.', retry: 'إعادة المحاولة',
    prefs: 'التفضيلات', language: 'لغة الواجهة', langNote: 'تعتمد البوابة لغة حسابكم، وتغييرها هنا يحدّث لغة الحساب.', english: 'English', arabic: 'العربية',
    notifications: 'الإشعارات',
    waNumber: 'رقم WhatsApp',
    waNumberNote: 'على هذا الرقم تصلكم رسائل WhatsApp. اختاروا «لا أستخدم WhatsApp» لتصلكم عبر البريد الإلكتروني بدلًا منها.',
    emailShare: 'مشاركة بريدي الإلكتروني مع العملاء الذين قدّمتُ لهم عرض سعر',
    emailShareHelp: 'مغلق افتراضيًا. عند الإغلاق يتواصل العملاء عبر المنصة فقط.',
    save: 'حفظ التفضيلات', saving: 'جارٍ الحفظ…', saved: 'حُفظت التفضيلات.', saveErr: 'تعذّر حفظ تفضيلاتكم. يُرجى المحاولة مرة أخرى.',
    account: 'الحساب', accountNote: 'تحدّدها المنصة، ولا تُعدَّل من هنا.',
    email: 'البريد الإلكتروني', phone: 'الهاتف', approval: 'الاعتماد', registration: 'التسجيل',
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

export default function SupplierSettings({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [s, setS] = useState<Settings | null>(null);
  const [avail, setAvail] = useState<Availability | null>(null);
  const [share, setShare] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  // The WhatsApp route is kyc's (whatsapp_*); undefined hides the section until kyc serves it.
  const [waState, setWaState] = useState<WaState | undefined>(undefined);
  // A tab switch unmounts this; an answer arriving afterwards must not write state. Declared here,
  // above the first fetch that reads it, so the order on the page is the order it is used in.
  const live = React.useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const loadWa = () => call('kyc', { action: 'state' }, token).then((k) => { if (live.current) setWaState(k && k.whatsapp ? k.whatsapp : undefined); }).catch(() => {});
  useEffect(() => { loadWa(); }, [token]);   // eslint-disable-line react-hooks/exhaustive-deps

  // A TAB THAT COULD LOAD FOR EVER. The `else` below looked total because `call()` answers a
  // refusal as { ok:false } at HTTP 200 — but a dropped connection REJECTS instead, and with no
  // catch neither `s` nor `err` was ever set, so the `if (!s)` return further down kept rendering
  // its aria-busy panel with nothing left that could ever resolve it.
  //
  // #736 rule 4 (docs/CONVENTIONS_LOADING.md): a failure resolves the indicator into a visible
  // error. Its 30 s ceiling does NOT cover this and was never going to — the ceiling lives inside
  // useBusy().run(), which guards a PRESS. This is a first-load region fetch that never goes
  // through run(), which is exactly how a tab reached "still busy" past a 30 s ceiling.
  // The live-ref shape is SupplierInsightsSummary.tsx's, so the two read the same way.
  const first = React.useRef(true);
  const load = React.useCallback(() => {
    setErr('');
    const f = first.current; first.current = false;
    return (f ? firstRead(token, 'sup_tab:settings') : call('supplier_api', { action: 'settings' }, token)).then((j) => {
      if (!live.current) return;
      if (j && j.ok) {
        const x: Settings = j.settings || {};
        setS(x);
        setAvail(j.availability ?? null);
        setShare(!!x.email_shared);
      } else setErr(t(lang, 'loadErr'));
    }).catch(() => { if (live.current) setErr(t(lang, 'loadErr')); });
  }, [token, lang]);
  // `load` is deliberately NOT a dependency here: it changes identity when `lang` does, and a
  // language switch must not refetch the settings — `lang` only picks which error string to show.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, [token]);

  const save = async () => {
    setBusy(true); setMsg(''); setErr('');
    const j = await call('supplier_api', { action: 'save_settings', email_shared: share }, token);
    setBusy(false);
    if (!(j && j.ok)) { setErr(t(lang, 'saveErr')); return; }
    setMsg(t(lang, 'saved'));
  };

  // The resolved state of the load above. It carries a retry because the failure it now catches is
  // usually transient — without one the only way out of a dropped connection is a full reload.
  if (err && !s) return (
    <div className="qd-panel p-5 text-[13px] text-muted-foreground" role="alert">
      {err}
      <button type="button" onClick={load}
        className="ms-2 inline-flex min-h-11 min-w-11 items-center underline rounded outline-none focus-visible:ring-1 focus-visible:ring-ring">{t(lang, 'retry')}</button>
    </div>
  );
  if (!s) return <div className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy="true">{t(lang, 'loading')}</div>;

  const yn = (v?: boolean | null) => (v ? t(lang, 'verified') : t(lang, 'unverified'));
  const tone = (v?: boolean | null) => (v ? 'text-ok-fg' : 'text-warn-fg');

  return (
    <div className="space-y-4 max-w-[560px]">
      <SupplierAvailability token={token} initial={avail} />
      <section className="qd-panel p-5">
        <h3 className="text-xs uppercase tracking-wide text-muted-foreground mb-3">{t(lang, 'prefs')}</h3>

        <div className="pt-2 border-t border-border">
          <div className="text-[11px] uppercase tracking-wide text-muted-foreground mb-1">{t(lang, 'notifications')}</div>
          <Toggle on={share} onChange={setShare} label={t(lang, 'emailShare')} help={t(lang, 'emailShareHelp')} />
        </div>

        <button type="button" onClick={save} disabled={busy}
          className="w-full min-h-11 mt-3 rounded-md bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground hover:bg-primary/90 disabled:opacity-50">
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
        <Fact k={t(lang, 'licence')}>{s.license_expiry ? <Ltr>{date(lang, s.license_expiry)}</Ltr> : t(lang, 'none')}</Fact>
        <Fact k={t(lang, 'terms')}>{s.accepted_terms_at
          ? <><Ltr>{date(lang, s.accepted_terms_at)}</Ltr>{s.accepted_terms_version ? <> · <bdi dir="ltr">v{String(s.accepted_terms_version).replace(/^v/i, '')}</bdi></> : null}</>
          : t(lang, 'never')}</Fact>
      </section>
      {/* Suppliers are English only on every channel (standing rule), whatever the interface language. */}
      <PrivacyControls token={token} lang="en" />
    </div>
  );
}
