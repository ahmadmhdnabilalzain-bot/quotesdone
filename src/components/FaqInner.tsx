'use client';
import { useEffect } from 'react';
import { useLocale } from 'next-intl';
import mk from '@/content/marketing.json';
import css from '@/content/marketingCss.json';
import { arDoc } from '@/lib/arabicDoc';
export function FaqInner() {
  const locale = useLocale();
  const entry = (mk as any).faq; const d = entry[locale] || entry.en;
  const html = arDoc(d.html as string, locale); const style = (css as any).faq as string;
  useEffect(() => {
    const q = document.getElementById('q') as HTMLInputElement | null;
    const nm = document.getElementById('nm') as HTMLElement | null;
    if (!q) return;
    const items = Array.from(document.querySelectorAll('details.qa')) as HTMLElement[];
    const secs = Array.from(document.querySelectorAll('.sec')) as HTMLElement[];
    const run = () => {
      const t = q.value.trim().toLowerCase();
      let any = false;
      items.forEach((el) => {
        const show = !t || (el.textContent || '').toLowerCase().includes(t);
        el.style.display = show ? '' : 'none';
        if (show) any = true;
        (el as HTMLDetailsElement).open = !!(t && show);
      });
      secs.forEach((s) => { const vis = Array.from(s.querySelectorAll('details.qa')).some((el: any) => el.style.display !== 'none'); s.style.display = vis ? '' : 'none'; });
      if (nm) nm.style.display = any ? 'none' : 'block';
    };
    q.addEventListener('input', run); run();
    return () => q.removeEventListener('input', run);
  }, [locale]);
  return (<><style dangerouslySetInnerHTML={{ __html: style }} /><style dangerouslySetInnerHTML={{ __html: FAQ_DECK_CSS.replace('FAQ · 150 ANSWERS', locale === 'ar' ? 'الأسئلة الشائعة · 150 إجابة' : 'FAQ · 150 ANSWERS') }} /><main id="main" className="mk mk-faq" dir={locale === 'ar' ? 'rtl' : 'ltr'} dangerouslySetInnerHTML={{ __html: html }} /></>);
}

/* Command-deck polish layered on top of the base FAQ stylesheet — a kicker
   pill above the title (injected via ::before, no HTML change), a teal→gold
   gradient headline, accent-barred section headers, a glowing search focus
   and hover-lift accordions. Style only; the search/filter logic is untouched. */
const FAQ_DECK_CSS = `
.mk-faq .hero{padding-top:70px}
.mk-faq .hero h1{position:relative;background:linear-gradient(96deg,#EAF4F2 0%,#6EE7D4 44%,#EAF4F2 60%,#E3C065 100%);-webkit-background-clip:text;background-clip:text;color:transparent;-webkit-text-fill-color:transparent}
.mk-faq .hero h1::before{content:"FAQ · 150 ANSWERS";display:inline-flex;align-items:center;gap:9px;margin:0 auto 20px;padding:6px 15px;border:1px solid rgba(110,231,212,.19);background:rgba(110,231,212,.05);border-radius:999px;font-family:var(--font-mono),ui-monospace,monospace;font-size:12px;font-weight:700;letter-spacing:.2em;color:#6EE7D4;-webkit-text-fill-color:#6EE7D4;width:max-content}
.mk-faq .hero h1::after{content:"";position:absolute;left:50%;top:-34px;width:6px;height:6px;translate:-50% 0;border-radius:99px;background:#14B8A6;box-shadow:0 0 10px rgba(20,184,166,.95)}
.mk-faq .search input{transition:border-color .22s,box-shadow .22s}
.mk-faq .search input:focus{box-shadow:0 0 0 3px rgba(20,184,166,.16)}
.mk-faq .sec h2{position:relative;padding-inline-start:14px;border-bottom:none}
.mk-faq .sec h2::before{content:"";position:absolute;inset-inline-start:0;top:.05em;height:1em;width:3px;border-radius:2px;background:linear-gradient(180deg,var(--teal),var(--gold))}
.mk-faq details.qa{transition:border-color .28s cubic-bezier(.16,1,.3,1),transform .28s cubic-bezier(.16,1,.3,1)}
@media(hover:hover){.mk-faq details.qa:hover{border-color:rgba(110,231,212,.4);transform:translateY(-2px)}}
.mk-faq details.qa[open]{border-color:rgba(110,231,212,.32)}
.mk-faq details.qa summary:after{transition:transform .25s ease}
.mk-faq details.qa[open] summary:after{transform:translateY(-50%) rotate(45deg)}
@media(prefers-reduced-motion:reduce){.mk-faq details.qa,.mk-faq details.qa summary:after{transition:none}.mk-faq details.qa:hover{transform:none}}
`;
