'use client';
import { useEffect } from 'react';
import { useLocale } from 'next-intl';
import mk from '@/content/marketing.json';
import css from '@/content/marketingCss.json';
import { SERVICES_CSS } from '@/content/servicesCss';
// See supaEnv: the contact form posted to whatever this inline fallback resolved to, which on an
// unconfigured preview deployment was production.
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
export function ContactInner() {
  const locale = useLocale();
  const entry = (mk as any).contact; const d = entry[locale] || entry.en;
  const html = d.html as string; const style = ((css as any).contact as string) || SERVICES_CSS;
  useEffect(() => {
    const F = document.getElementById('cform') as HTMLFormElement | null;
    const Mg = document.getElementById('cmsg') as HTMLElement | null;
    if (!F) return;
    const onsub = async (e: Event) => {
      e.preventDefault();
      if (Mg) { Mg.style.color = 'var(--mut,#9DB2B2)'; Mg.textContent = locale === 'ar' ? 'جارٍ الإرسال…' : 'Sending…'; }
      const data: any = {}; new FormData(F).forEach((v, k) => { data[k] = v; });
      try {
        const r = await fetch(FN + '/contact_submit', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: 'Bearer ' + ANON }, body: JSON.stringify(data) });
        const j = await r.json().catch(() => ({} as any));
        if (r.ok && j && j.ok !== false) { if (Mg) { Mg.style.color = '#6EE7D4'; Mg.textContent = (j && j.message) || (locale === 'ar' ? 'شكرًا — سنتواصل معك قريبًا.' : 'Thanks — we will be in touch shortly.'); } F.reset(); }
        else { if (Mg) { Mg.style.color = '#ff9a9a'; Mg.textContent = (j && j.error) || (locale === 'ar' ? 'تعذّر الإرسال. يرجى مراسلتنا على management@quotesdone.com.' : 'Could not send. Please email management@quotesdone.com.'); } }
      } catch (_e) { if (Mg) { Mg.style.color = '#ff9a9a'; Mg.textContent = locale === 'ar' ? 'تعذّر الإرسال. يرجى مراسلتنا على management@quotesdone.com.' : 'Could not send. Please email management@quotesdone.com.'; } }
    };
    F.addEventListener('submit', onsub);
    return () => F.removeEventListener('submit', onsub);
  }, [locale]);
  return (<><style dangerouslySetInnerHTML={{ __html: style }} /><main id="main" className="mk" dir={locale === 'ar' ? 'rtl' : 'ltr'} dangerouslySetInnerHTML={{ __html: html }} /></>);
}
