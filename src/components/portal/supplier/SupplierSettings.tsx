'use client';
// ROW #5 §24 — SETTINGS. Language, notification preferences, and the account facts underneath them.
//
// ── WHAT IS SETTABLE HERE AND WHAT IS DELIBERATELY NOT ──────────────────────────────────────────
// Three preferences post to supplier_api save_settings, which has its own three-column allowlist:
// locale, wa_optin, email_shared. Everything else on this screen is READ-ONLY and says so, because
// it is not a preference — verification state, approval state and the terms version are facts the
// platform decides, and a settings screen that appeared to let a supplier edit them would be
// offering a control that silently does nothing.
//
// The account block exists precisely so a supplier can SEE those facts in one place. "Is my e-mail
// verified, is my phone verified, which terms did I accept and when" are questions the portal could
// not answer anywhere before this screen.
import React, { useEffect, useState } from 'react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Settings = {
  company_name?: string; locale?: string | null; wa_optin?: boolean | null; email_shared?: boolean | null;
  claimed_by?: string | null; phone?: string | null; approval_status?: string | null;
  registration_status?: string | null; owner_email_verified?: boolean | null;
  owner_phone_verified?: boolean | null; accepted_terms_at?: string | null;
  accepted_terms_version?: string | null; license_expiry?: string | null;
};

const FN = SUPA_FN;
const ANON = SUPA_ANON;

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'Settings', loading: 'Loading your settings…',
    prefs: 'Preferences', language: 'Interface language', english: 'English', arabic: 'العربية',
    notifications: 'Notifications',
    wa: 'Send me RFQ alerts on WhatsApp',
    waHelp: 'We message the number on your account when a matching request arrives.',
    emailShare: 'Share my e-mail with customers I have quoted',
    emailShareHelp: 'Off by default. When off, customers reach you through the platform only.',
    save: 'Save preferences', saving: 'Saving…', saved: 'Saved.',
    account: 'Account', accountNote: 'These are set by the platform, not here.',
    email: 'E-mail', phone: 'Phone', approval: 'Approval', registration: 'Registration',
    verified: 'verified', unverified: 'not verified', terms: 'Terms accepted', licence: 'Licence expires',
    none: 'not set', never: 'not yet accepted',
  },
  ar: {
    title: 'الإعدادات', loading: 'جارٍ تحميل إعداداتك…',
    prefs: 'التفضيلات', language: 'لغة الواجهة', english: 'English', arabic: 'العربية',
    notifications: 'الإشعارات',
    wa: 'أرسل لي تنبيهات الطلبات على واتساب',
    waHelp: 'نراسل الرقم المسجَّل في حسابك عند وصول طلب مطابق.',
    emailShare: 'شارك بريدي مع العملاء الذين قدّمت لهم عرضًا',
    emailShareHelp: 'مغلق افتراضيًا. عند الإغلاق يتواصل العملاء عبر المنصة فقط.',
    save: 'حفظ التفضيلات', saving: 'جارٍ الحفظ…', saved: 'تم الحفظ.',
    account: 'الحساب', accountNote: 'تُحدَّد من المنصة، وليس من هنا.',
    email: 'البريد', phone: 'الهاتف', approval: 'الاعتماد', registration: 'التسجيل',
    verified: 'موثّق', unverified: 'غير موثّق', terms: 'الشروط المقبولة', licence: 'انتهاء الرخصة',
    none: 'غير محدد', never: 'لم تُقبل بعد',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

function Toggle({ on, onChange, label, help }: { on: boolean; onChange: (v: boolean) => void; label: string; help: string }) {
  return (
    <label className="flex items-start gap-3 cursor-pointer py-2">
      <input
        type="checkbox"
        checked={on}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 h-4 w-4 shrink-0 rounded border-white/25 bg-white/10 accent-sky-400"
      />
      <span className="min-w-0">
        <span className="block text-[13px]">{label}</span>
        <span className="block text-[11px] opacity-45 leading-snug mt-0.5">{help}</span>
      </span>
    </label>
  );
}

// A fact the platform decides. Rendered as text, never as a control.
function Fact({ k, v, tone }: { k: string; v: string; tone?: string }) {
  return (
    <div className="flex justify-between gap-3 py-1.5 border-b border-white/[0.06] last:border-0">
      <span className="text-[12px] opacity-55 shrink-0">{k}</span>
      <span className={'text-[12px] text-end break-words ' + (tone || '')}>{v}</span>
    </div>
  );
}

export default function SupplierSettings({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [s, setS] = useState<Settings | null>(null);
  const [locale, setLocale] = useState('en');
  const [wa, setWa] = useState(false);
  const [share, setShare] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_api', { action: 'settings' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) {
        const x: Settings = j.settings || {};
        setS(x);
        setLocale(x.locale === 'ar' ? 'ar' : 'en');
        setWa(!!x.wa_optin);
        setShare(!!x.email_shared);
      } else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  const save = async () => {
    setBusy(true); setMsg(''); setErr('');
    const j = await call('supplier_api', { action: 'save_settings', locale, wa_optin: wa, email_shared: share }, token);
    setBusy(false);
    if (j && j.ok) setMsg(t(lang, 'saved')); else setErr((j && j.error) || 'save_err');
  };

  if (err && !s) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!s) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const yn = (v?: boolean | null) => (v ? t(lang, 'verified') : t(lang, 'unverified'));
  const tone = (v?: boolean | null) => (v ? 'text-emerald-300/90' : 'text-amber-300/90');

  return (
    <div className="space-y-4 max-w-[560px]">
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'prefs')}</h3>

        <div className="mb-3">
          <label className="block text-[13px] mb-1.5" htmlFor="qd-set-lang">{t(lang, 'language')}</label>
          <select
            id="qd-set-lang"
            value={locale}
            onChange={(e) => setLocale(e.target.value)}
            className="w-full rounded-lg border border-white/10 bg-white/[0.04] px-3 py-2 text-sm outline-none focus:border-white/25"
            style={{ colorScheme: 'dark' }}
          >
            <option value="en" style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>{t(lang, 'english')}</option>
            <option value="ar" style={{ backgroundColor: '#0C2330', color: '#EAF4F2' }}>{t(lang, 'arabic')}</option>
          </select>
        </div>

        <div className="pt-2 border-t border-white/10">
          <div className="text-[11px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'notifications')}</div>
          <Toggle on={wa} onChange={setWa} label={t(lang, 'wa')} help={t(lang, 'waHelp')} />
          <Toggle on={share} onChange={setShare} label={t(lang, 'emailShare')} help={t(lang, 'emailShareHelp')} />
        </div>

        <button
          type="button"
          onClick={save}
          disabled={busy}
          className="w-full mt-3 rounded-lg bg-white/90 px-4 py-2.5 text-sm font-semibold text-slate-900 hover:bg-white disabled:opacity-50"
        >
          {busy ? t(lang, 'saving') : t(lang, 'save')}
        </button>
        {msg && <p className="text-[12px] text-emerald-300/90 mt-2">{msg}</p>}
        {err && <p className="text-[12px] text-rose-300/90 mt-2">{err}</p>}
      </section>

      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-2">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'account')}</h3>
          <span className="text-[10px] opacity-40">{t(lang, 'accountNote')}</span>
        </div>
        <Fact k={t(lang, 'email')} v={(s.claimed_by || t(lang, 'none')) + ' · ' + yn(s.owner_email_verified)} tone={tone(s.owner_email_verified)} />
        <Fact k={t(lang, 'phone')} v={(s.phone || t(lang, 'none')) + ' · ' + yn(s.owner_phone_verified)} tone={tone(s.owner_phone_verified)} />
        <Fact k={t(lang, 'approval')} v={String(s.approval_status || t(lang, 'none'))} />
        <Fact k={t(lang, 'registration')} v={String(s.registration_status || t(lang, 'none'))} />
        <Fact k={t(lang, 'licence')} v={s.license_expiry || t(lang, 'none')} />
        <Fact
          k={t(lang, 'terms')}
          v={s.accepted_terms_at
            ? new Date(s.accepted_terms_at).toISOString().slice(0, 10) + (s.accepted_terms_version ? ' · v' + s.accepted_terms_version : '')
            : t(lang, 'never')}
        />
      </section>
    </div>
  );
}
