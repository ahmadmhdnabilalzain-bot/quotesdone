'use client';

// "DESCRIBE YOUR JOB" ON THE FIRST SCREEN, WITH NO SIGN-IN.
//
// Website audit §1 findings 16, 22, 30: a visitor could not touch the engine until ~11 sign-up
// steps later. This box runs public_site route_brief — the bilingual router, the ordered interview
// and the trade's compliance checklist, all deterministic — and shows what the engine understood.
// Then it hands the draft to the customer portal in exactly the shape /me?draft=1 consumes
// (localStorage 'qd-draft-brief' = {text, category, emirate, ts}). The supplier count appears only
// when the matcher found someone; zero is never printed.
import { useId, useState } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { useRouter } from '@/i18n/routing';
import { publicSite, saveDraft } from '@/lib/publicSite';

type Result = {
  ok: boolean; recognised?: boolean; category?: string; label?: string; emirate?: string | null;
  questions?: { key: string; question: string }[]; documents?: { item: string; authority: string | null }[];
  supplier_count?: number | null; clarification?: string | null; rate_limited?: boolean;
};

export function BriefBox() {
  const t = useTranslations('brief');
  const locale = useLocale();
  const router = useRouter();
  const id = useId();
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<Result | null>(null);
  const [err, setErr] = useState('');
  const examples = t.raw('examples') as string[];

  async function check(v = text) {
    const q = v.trim();
    if (q.length < 3 || busy) return;
    setBusy(true); setErr(''); setRes(null);
    try {
      const j = await publicSite<Result>('route_brief', { text: q, lang: /[؀-ۿ]/.test(q) ? 'ar' : locale });
      if (j.rate_limited) setErr(t('limited'));
      else if (!j.ok) setErr(t('error'));
      else setRes(j as Result);
    } catch (_e) { setErr(t('error')); }
    finally { setBusy(false); }
  }

  function proceed() {
    saveDraft({ text: text.trim(), category: res?.category ?? null, emirate: res?.emirate ?? null });
    router.push('/me?draft=1');
  }

  return (
    <div className="glass depth relative overflow-hidden rounded-[22px] text-start">
      <span className="grid-tech grid-tech-sm opacity-50" aria-hidden />
      {/* method="post": handled in JS (preventDefault); the attribute keeps a no-JS submit from
          putting the job description in a GET query string. */}
      <form
        method="post"
        className="relative p-5 sm:p-6"
        onSubmit={(e) => { e.preventDefault(); check(); }}
      >
        <div className="flex items-center gap-2.5">
          <span className="node-dot" aria-hidden />
          <h2 className="font-head text-[18px] font-semibold tracking-[-0.02em] text-white">{t('title')}</h2>
        </div>
        <p className="mt-1.5 text-[13px] leading-relaxed text-muted">{t('sub')}</p>
        <label htmlFor={id} className="sr-only">{t('label')}</label>
        <textarea
          id={id}
          dir="auto"
          rows={3}
          value={text}
          maxLength={1000}
          onChange={(e) => setText(e.target.value)}
          placeholder={t('ph')}
          className="mt-4 w-full resize-none rounded-[14px] border border-[var(--line2)] bg-navy-deep/60 px-4 py-3 text-[14.5px] leading-relaxed text-paper shadow-[var(--key)] outline-none transition-colors placeholder:text-faint focus-visible:border-teal focus-visible:ring-2 focus-visible:ring-teal/30"
        />
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="submit"
            disabled={busy || text.trim().length < 3}
            className="btn-key press rounded-full bg-teal px-5 py-2.5 text-[14px] font-bold text-[#04231F] transition-colors hover:bg-[#1ED0BC] disabled:opacity-50"
          >
            {busy ? t('busy') : t('submit')}
          </button>
          {examples.map((ex) => (
            <button
              key={ex}
              type="button"
              dir="auto"
              onClick={() => { setText(ex); check(ex); }}
              className="rounded-full border border-[var(--line)] bg-teal-light/[0.03] px-3 py-1.5 text-[12px] text-muted transition-colors hover:border-teal/50 hover:text-white"
            >
              {ex}
            </button>
          ))}
        </div>
      </form>

      <div aria-live="polite" className="relative">
        {err && <p className="border-t border-[var(--line)] px-6 py-4 text-[13px] text-gold">{err}</p>}
        {res && !res.recognised && (
          <div className="border-t border-[var(--line)] px-6 py-4 text-[13.5px] leading-relaxed text-muted">
            <p>{t('unknown')}</p>
            {res.clarification && <p className="mt-2 text-paper" dir="auto">{t('clarify')} {res.clarification}</p>}
          </div>
        )}
        {res && res.recognised && (
          <div className="border-t border-[var(--line)] bg-navy-deep/40 px-5 py-5 sm:px-6">
            <dl className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-[12px] border border-[var(--line2)] bg-teal/[0.05] px-3.5 py-2.5">
                <dt className="font-mono text-[12px] uppercase tracking-[0.16em] text-faint rtl:tracking-normal">{t('recognised')}</dt>
                <dd className="mt-1 font-head text-[15px] font-semibold text-white">{res.label}</dd>
              </div>
              <div className="rounded-[12px] border border-[var(--line)] px-3.5 py-2.5">
                <dt className="font-mono text-[12px] uppercase tracking-[0.16em] text-faint rtl:tracking-normal">{t('emirate')}</dt>
                <dd className="mt-1 text-[14px] text-paper">{res.emirate || t('noEmirate')}</dd>
              </div>
            </dl>
            {!!res.questions?.length && (
              <div className="mt-4">
                <h3 className="text-[12.5px] font-semibold text-teal-light">{t('questions')}</h3>
                <ol className="mt-2 space-y-1.5">
                  {res.questions.map((q, i) => (
                    <li key={q.key || i} dir="auto" className="flex gap-2.5 text-[13.5px] leading-relaxed text-paper">
                      <span className="mt-[3px] flex h-4 w-4 shrink-0 items-center justify-center rounded-full border border-teal/50 font-mono text-[12px] text-teal-light">{i + 1}</span>
                      {q.question}
                    </li>
                  ))}
                </ol>
              </div>
            )}
            <div className="mt-4">
              <h3 className="text-[12.5px] font-semibold text-teal-light">{t('docs')}</h3>
              {res.documents?.length ? (
                <ul className="mt-2 space-y-1">
                  {res.documents.map((d) => (
                    <li key={d.item} className="text-[13px] leading-relaxed text-muted">
                      <span className="text-paper" dir="auto">{d.item}</span>
                      {d.authority && <span dir="auto"> — {d.authority}</span>}
                    </li>
                  ))}
                </ul>
              ) : <p className="mt-1.5 text-[13px] text-faint">{t('noDocs')}</p>}
            </div>
            {typeof res.supplier_count === 'number' && res.supplier_count > 0 && (
              <p className="mt-4 text-[13px] text-teal-light">{t('suppliers', { count: res.supplier_count })}</p>
            )}
            <button
              type="button"
              onClick={proceed}
              className="btn-key press mt-5 w-full rounded-full bg-teal px-5 py-3 text-[14.5px] font-bold text-[#04231F] transition-colors hover:bg-[#1ED0BC] sm:w-auto"
            >
              {t('continue')}
            </button>
            <p className="mt-2 text-[12px] text-faint">{t('continueNote')}</p>
          </div>
        )}
      </div>
    </div>
  );
}
