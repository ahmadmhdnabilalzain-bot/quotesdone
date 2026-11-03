'use client';

// "DESCRIBE YOUR JOB" ON THE FIRST SCREEN, WITH NO SIGN-IN.
//
// Website audit §1 findings 16, 22, 30: a visitor could not touch the engine until ~11 sign-up
// steps later. This box runs public_site route_brief — the bilingual router, the ordered interview
// and the trade's compliance checklist, all deterministic — and shows what the engine understood.
// Then it hands the draft to the customer portal in exactly the shape /me?draft=1 consumes
// (localStorage 'qd-draft-brief' = {text, category, emirate, ts}). The supplier count appears only
// when the matcher found someone; zero is never printed.
//
// Presented as a command bar (Sealed homepage): the field, its examples and the submit sit in one
// machined surface; Enter submits, Shift+Enter breaks a line.
import { useId, useRef, useState, useTransition } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { useRouter } from '@/i18n/routing';
import { publicSite, saveDraft } from '@/lib/publicSite';
import s from '@/components/home/sealed.module.css';
import { Spinner, useDelayedFlag } from '@/components/ui/busy';
import { startRouteProgress } from '@/components/ui/route-progress';

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
  const field = useRef<HTMLTextAreaElement>(null);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<Result | null>(null);
  const [err, setErr] = useState('');
  const examples = t.raw('examples') as string[];

  async function check(v = text) {
    const q = v.trim();
    if (busy) return;
    // The button always looks and works like the primary action; with nothing typed yet it takes
    // the visitor to the field instead of doing nothing.
    if (q.length < 3) { field.current?.focus(); return; }
    setBusy(true); setErr(''); setRes(null);
    try {
      const j = await publicSite<Result>('route_brief', { text: q, lang: /[؀-ۿ]/.test(q) ? 'ar' : locale });
      if (j.rate_limited) setErr(t('limited'));
      else if (!j.ok) setErr(t('error'));
      else setRes(j as Result);
    } catch (_e) { setErr(t('error')); }
    finally { setBusy(false); }
  }

  // The router call itself is the slow part (it pulls the customer-portal bundle), so the busy
  // state has to live on the transition, not on saveDraft.
  const [going, startGoing] = useTransition();
  const goingShown = useDelayedFlag(going);
  const busyShown = useDelayedFlag(busy);

  function proceed() {
    saveDraft({ text: text.trim(), category: res?.category ?? null, emirate: res?.emirate ?? null });
    startRouteProgress();
    startGoing(() => router.push('/me?draft=1'));
  }

  return (
    <div className={`${s.shell} text-start`}>
      {/* bg-surf under the panel's translucent gradient: the hero scene sits behind this box and must
          never show through the field or its examples. */}
      <div className={`qd-panel rounded-[22px] overflow-hidden bg-surf!`}>
        {/* method="post": handled in JS (preventDefault); the attribute keeps a no-JS submit from
            putting the job description in a GET query string. */}
        <form method="post" onSubmit={(e) => { e.preventDefault(); check(); }}>
          <div className="flex flex-col gap-0.5 px-5 pt-4">
            <h2 className="font-head text-[15px] font-semibold tracking-[-0.01em] text-white rtl:tracking-normal">{t('title')}</h2>
            <span className="text-[12px] text-faint">{t('sub')}</span>
          </div>
          <label htmlFor={id} className="sr-only">{t('label')}</label>
          <textarea
            id={id}
            ref={field}
            // dir=auto on an EMPTY textarea let the browser lay the Arabic placeholder out around
            // "SPC" left-to-right (public audit 21 Sep 2026, item 26); the page locale decides
            // until there is text to decide from.
            dir={text ? 'auto' : locale === 'ar' ? 'rtl' : 'ltr'}
            rows={2}
            value={text}
            maxLength={1000}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); check(); }
            }}
            placeholder={t('ph')}
            className="block w-full resize-none bg-transparent px-5 pb-2 pt-3 text-[16px] leading-relaxed text-paper outline-hidden placeholder:text-faint/90 focus-visible:placeholder:text-faint/60"
          />
          <div className="flex flex-col gap-3 border-t border-(--line) px-3 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex flex-wrap items-center gap-1.5 px-2 sm:px-0 sm:ps-2">
              {/* Labelled as examples so three chips never read as the list of what we do. */}
              <span className="text-[12px] text-faint">{t('eg')}</span>
              {examples.map((ex) => (
                <button
                  key={ex}
                  type="button"
                  dir="auto"
                  disabled={busy}
                  onClick={() => { setText(ex); check(ex); }}
                  className="rounded-full px-3 py-1.5 text-[12px] text-muted shadow-[inset_0_0_0_1px_rgba(110,231,212,.14)] transition-[color,box-shadow] duration-300 hover:text-white hover:shadow-[inset_0_0_0_1px_rgba(110,231,212,.4)] disabled:cursor-progress disabled:opacity-50"
                >
                  {/* An example in the other language is tagged, so it reads as the bilingual router it
                      demonstrates. The tag follows the page direction and the example is isolated in
                      <bdi>, so the two never interleave (dir="auto" on the button put the tag inside
                      the Arabic phrase on the English page). */}
                  {/[؀-ۿ]/.test(ex) !== (locale === 'ar') ? (
                    <span dir={locale === 'ar' ? 'rtl' : 'ltr'}>
                      <span className="me-2 font-semibold text-teal-light">{t('otherLang')}</span>
                      <bdi>{ex}</bdi>
                    </span>
                  ) : ex}
                </button>
              ))}
            </div>
            <button
              type="submit"
              disabled={busy}
              aria-busy={busyShown || undefined}
              className="press inline-flex shrink-0 items-center justify-center gap-2 rounded-full bg-teal px-5 py-2.5 text-[14px] font-bold text-[#04231F] shadow-[0_14px_36px_-16px_rgba(20,184,166,.85)] transition-colors hover:bg-[#1ED0BC] disabled:cursor-progress"
            >
              {busyShown ? <Spinner /> : null}
              {busy ? t('busy') : t('submit')}
            </button>
          </div>
        </form>

        <div aria-live="polite">
          {err && <p className="border-t border-(--line) px-5 py-4 text-[13px] text-gold">{err}</p>}
          {res && !res.recognised && (
            <div className="border-t border-(--line) px-5 py-4 text-[13.5px] leading-relaxed text-muted">
              <p>{t('unknown')}</p>
              {res.clarification && <p className="mt-2 text-paper" dir="auto">{t('clarify')} {res.clarification}</p>}
            </div>
          )}
          {res && res.recognised && (
            <div className="border-t border-(--line) bg-navy-deep/40 px-5 py-5">
              <dl className="grid gap-3 sm:grid-cols-2">
                <div className="rounded-panel bg-teal/6 px-3.5 py-2.5 shadow-[inset_0_0_0_1px_rgba(110,231,212,.2)]">
                  <dt className="font-mono text-[12px] uppercase tracking-[0.16em] text-faint rtl:font-sans rtl:tracking-normal">{t('recognised')}</dt>
                  <dd className="mt-1 font-head text-[15px] font-semibold text-white">{res.label}</dd>
                </div>
                <div className="rounded-panel px-3.5 py-2.5 shadow-[inset_0_0_0_1px_rgba(110,231,212,.1)]">
                  <dt className="font-mono text-[12px] uppercase tracking-[0.16em] text-faint rtl:font-sans rtl:tracking-normal">{t('emirate')}</dt>
                  <dd className="mt-1 text-[14px] text-paper">{res.emirate || t('noEmirate')}</dd>
                </div>
              </dl>
              {!!res.questions?.length && (
                <div className="mt-4">
                  <h3 className="text-[12.5px] font-semibold text-teal-light">{t('questions')}</h3>
                  <ol className="mt-2 space-y-1.5">
                    {res.questions.map((q, i) => (
                      <li key={q.key || i} dir="auto" className="flex gap-2.5 text-[13.5px] leading-relaxed text-paper">
                        <span className="mt-[3px] flex h-4 w-4 shrink-0 items-center justify-center rounded-full font-mono text-[11px] text-teal-light shadow-[inset_0_0_0_1px_rgba(20,184,166,.5)]">{i + 1}</span>
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
                disabled={going}
                aria-busy={goingShown || undefined}
                className="press mt-5 inline-flex w-full items-center justify-center gap-2 rounded-full bg-teal px-5 py-3 text-[14.5px] font-bold text-[#04231F] transition-colors hover:bg-[#1ED0BC] disabled:cursor-progress sm:w-auto"
              >
                {goingShown ? <Spinner /> : null}
                {t('continue')}
              </button>
              <p className="mt-2 text-[12px] text-faint">{t('continueNote')}</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
