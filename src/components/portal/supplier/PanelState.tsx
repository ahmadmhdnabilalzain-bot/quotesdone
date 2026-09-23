'use client';
// WHAT A SUPPLIER PORTAL PANEL SAYS WHEN IT HAS NOTHING TO SHOW YET, OR COULD NOT GET IT.
//
// Audit 22 Sep 2026 (SP-C-05, SP-C-08, SP-I-01): thirteen panels printed the raw failure — `load_err`,
// `no_company`, and on a 500 the Postgres message itself — straight onto the page, in English, on
// /ar as well as /en, with no way to try again. Seven of them printed nothing at all and stayed on
// "Loading" forever because their private `call` had no catch. One place now owns those three
// states, so a panel is three lines: `if (err) return <PanelError …/>`, `if (!data) return
// <PanelLoading …/>`, then the panel.
//
// `code` comes from supplier/api.ts (`timeout`, `network`, `bad_response`, `load_failed`,
// `session_expired`) or from the server's own stable code. An unknown code falls back to the same
// "could not load" sentence rather than to the server's English — a code this table does not know
// is still not something to show a supplier.
import { Button } from '@/components/ui/button';

export type Lang = 'en' | 'ar';

const COPY: Record<string, { en: string; ar: string }> = {
  load_failed: {
    en: 'We could not load this just now. Please try again.',
    ar: 'تعذّر تحميل هذا القسم الآن. يُرجى المحاولة مرة أخرى.',
  },
  timeout: {
    en: 'This is taking longer than expected. Please check your connection and try again.',
    ar: 'استغرق التحميل وقتًا أطول من المتوقع. يُرجى التحقق من اتصالكم والمحاولة مرة أخرى.',
  },
  network: {
    en: 'We could not reach QuotesDone. Please check your connection and try again.',
    ar: 'تعذّر الوصول إلى QuotesDone. يُرجى التحقق من اتصالكم والمحاولة مرة أخرى.',
  },
  bad_response: {
    en: 'We could not load this just now. Please try again.',
    ar: 'تعذّر تحميل هذا القسم الآن. يُرجى المحاولة مرة أخرى.',
  },
  session_expired: {
    en: 'Your session has ended. Please sign in again to continue.',
    ar: 'انتهت جلستكم. يُرجى تسجيل الدخول مرة أخرى للمتابعة.',
  },
  // submit_quote answers 200/ok:true with accepted:false and one of these three codes. They are
  // refusals with a reason, not load failures, so the generic sentence would lose the reason
  // (SupplierQuoteBuilder, merge of #858 with main's SP-C-04 fix).
  spec_hold: {
    en: 'Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.',
    ar: 'عرضكم معلّق حتى تُذكر التفاصيل المطلوبة بدقة. أكملوها هنا أو ارفعوا عرضًا مُعدّلًا.',
  },
  quote_review_changes: {
    en: 'Your quote needs the changes listed in the review before we can send it to the customer.',
    ar: 'يحتاج عرضكم إلى التعديلات الواردة في المراجعة قبل إرساله إلى العميل.',
  },
  draft_saved: {
    en: 'Your quote was saved as a draft. Add the missing details so we can send it to the customer.',
    ar: 'حُفِظ عرضكم كمسودة. أضيفوا التفاصيل الناقصة لنرسله إلى العميل.',
  },
  no_company: {
    en: 'Your company profile is not complete yet, so there is nothing to show here. Please finish the checklist on the Documents tab.',
    ar: 'لم يكتمل ملف شركتكم بعد، فلا يوجد ما يُعرض هنا. يُرجى إكمال القائمة في تبويب المستندات.',
  },
};

const RETRY = { en: 'Try again', ar: 'إعادة المحاولة' };
const LOADING = { en: 'Loading…', ar: 'جارٍ التحميل…' };

/** The sentence alone, for a panel that already owns its own card and button. */
export function panelErrorText(lang: Lang, code: unknown): string {
  const k = String(code || 'load_failed');
  const e = COPY[k] || COPY.load_failed;
  return lang === 'ar' ? e.ar : e.en;
}

/** True when this failure means the token is gone, not that the read failed. */
export const isExpired = (j: any): boolean => Boolean(j && (j._expired || j._http === 401 || j.code === 'session_expired'));

/** The code a panel should store in its `err` state, given whatever `call` resolved with. */
export const panelErrorCode = (j: any): string =>
  isExpired(j) ? 'session_expired' : String((j && (j.code || j.error)) || 'load_failed');

export function PanelError({ lang = 'en', code, onRetry }: { lang?: Lang; code?: unknown; onRetry?: () => void }) {
  const expired = String(code) === 'session_expired';
  return (
    <div role="alert" className="qd-panel p-5" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <p className="text-[13.5px] leading-relaxed text-foreground">{panelErrorText(lang, code)}</p>
      {/* Signing in again is not a retry: the same call with the same dead token fails the same way. */}
      {onRetry && !expired ? (
        <Button variant="outline" className="mt-3 min-h-11" onClick={onRetry}>{lang === 'ar' ? RETRY.ar : RETRY.en}</Button>
      ) : null}
    </div>
  );
}

export function PanelLoading({ lang = 'en', text }: { lang?: Lang; text?: string }) {
  return (
    <div role="status" aria-busy className="p-4 text-[13px] text-muted-foreground" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      {text || (lang === 'ar' ? LOADING.ar : LOADING.en)}
    </div>
  );
}
