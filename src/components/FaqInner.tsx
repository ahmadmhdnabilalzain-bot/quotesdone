'use client';
import { useEffect, type CSSProperties } from 'react';
import { useLocale } from 'next-intl';
import mk from '@/content/marketing.json';
import { arDoc } from '@/lib/arabicDoc';

// Styles: globals.css §9 (.mk-faq). The kicker above the title is CSS content, so its text is
// passed per locale as the --kicker custom property instead of string-patching a stylesheet.
const KICKER = { en: '"FAQ · 150 ANSWERS"', ar: '"الأسئلة الشائعة · 150 إجابة"' };
export function FaqInner() {
  const locale = useLocale();
  const entry = (mk as any).faq; const d = entry[locale] || entry.en;
  const html = arDoc(d.html as string, locale);
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
  return <main id="main" className="mk mk-faq" dir={locale === 'ar' ? 'rtl' : 'ltr'} style={{ '--kicker': KICKER[locale === 'ar' ? 'ar' : 'en'] } as CSSProperties} dangerouslySetInnerHTML={{ __html: html }} />;
}

