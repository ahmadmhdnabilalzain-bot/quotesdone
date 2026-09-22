'use client';
import { useEffect } from 'react';
import { useLocale } from 'next-intl';
import mk from '@/content/marketing.json';
// See supaEnv: the contact form posted to whatever this inline fallback resolved to, which on an
// unconfigured preview deployment was production.
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
import { arDoc } from '@/lib/arabicDoc';
import { CompanyIdentity } from '@/components/CompanyIdentity';
import { PageHero, splitHero } from '@/components/DocFrame';
export function ContactInner() {
  const locale = useLocale();
  const entry = (mk as any).contact; const d = entry[locale] || entry.en;
  const html = arDoc(d.html as string, locale); // styles: globals.css §9 (.mk)
  useEffect(() => {
    const F = document.getElementById('cform') as HTMLFormElement | null;
    const Mg = document.getElementById('cmsg') as HTMLElement | null;
    if (!F) return;
    // The form's markup comes from marketing.json, so the busy state is applied imperatively here.
    // It follows the same rules as ui/busy.tsx: the submit is locked from the first millisecond
    // (this form had NO guard at all — a second press filed a second ticket), the ring appears
    // only after 150ms, and a failure resolves it into the error message below.
    const Sub = F.querySelector<HTMLButtonElement | HTMLInputElement>('[type="submit"]');
    let sending = false; let showTimer: ReturnType<typeof setTimeout>;
    const setBusy = (on: boolean) => {
      sending = on;
      clearTimeout(showTimer);
      if (Sub) Sub.disabled = on;
      F.setAttribute('aria-busy', on ? 'true' : 'false');
      if (on) showTimer = setTimeout(() => { if (Mg && sending) Mg.prepend(Object.assign(document.createElement('span'), { className: 'qd-spin me-2' })); }, 150);
    };
    const onsub = async (e: Event) => {
      e.preventDefault();
      if (sending) return;
      setBusy(true);
      if (Mg) { Mg.style.color = 'var(--mut,#9DB2B2)'; Mg.textContent = locale === 'ar' ? 'جارٍ الإرسال…' : 'Sending…'; }
      const data: any = {}; new FormData(F).forEach((v, k) => { data[k] = v; });
      try {
        const r = await fetch(FN + '/contact_submit', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: 'Bearer ' + ANON }, body: JSON.stringify(data) });
        const j = await r.json().catch(() => ({} as any));
        const ar = locale === 'ar';
        if (r.ok && j && j.ok !== false) {
          if (Mg) {
            Mg.style.color = '#6EE7D4';
            if (j.ticket) {
              // A complaint: show the ticket number and the way to watch it (built with DOM nodes, not html).
              Mg.textContent = ar ? 'تم استلام شكواك. رقم التذكرة: ' : 'Complaint received. Ticket number: ';
              const b = document.createElement('bdi'); b.dir = 'ltr'; b.textContent = String(j.ticket); Mg.append(b);
              Mg.append(ar ? ' — نؤكّد الاستلام خلال يومَي عمل، ونوافيكم بالرد خلال 10 أيام عمل. ' : ' — we acknowledge within 2 working days and respond within 10 working days. ');
              const a = document.createElement('a'); a.href = (ar ? '/ar' : '') + '/complaints/status?t=' + encodeURIComponent(String(j.ticket));
              a.textContent = ar ? 'تابع حالة الشكوى' : 'Track its status'; a.style.textDecoration = 'underline'; Mg.append(a);
            } else Mg.textContent = ar ? 'شكرًا — سنتواصل معك قريبًا.' : 'Thanks — we will be in touch shortly.';
          }
          F.reset();
        }
        else { if (Mg) { Mg.style.color = '#ff9a9a'; Mg.textContent = ar ? 'تعذّر الإرسال. يُرجى مراسلتنا على management@quotesdone.com.' : ((j && j.error) || 'Could not send. Please email management@quotesdone.com.'); } }
      } catch (_e) { if (Mg) { Mg.style.color = '#ff9a9a'; Mg.textContent = locale === 'ar' ? 'تعذّر الإرسال. يُرجى مراسلتنا على management@quotesdone.com.' : 'Could not send. Please email management@quotesdone.com.'; } }
      finally { setBusy(false); }
    };
    F.addEventListener('submit', onsub);
    return () => { clearTimeout(showTimer); F.removeEventListener('submit', onsub); };
  }, [locale]);
  const hero = splitHero(html);
  return (
    <>
      <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <PageHero
          kicker={hero.kicker ? <span className="[&_a]:text-inherit [&_a:hover]:text-white" dangerouslySetInnerHTML={{ __html: hero.kicker }} /> : undefined}
          title={<span dangerouslySetInnerHTML={{ __html: hero.title ?? d.title }} />}
          lead={hero.lead ? <span dangerouslySetInnerHTML={{ __html: hero.lead }} /> : undefined}
        />
        {/* the two cards (direct lines, the form) keep their ids; .mk styles them, the frame sets the grid */}
        <div className="mk mk-contact py-6 md:py-10 [&_.step]:!p-7 [&_.steps]:!grid [&_.steps]:!gap-5 md:[&_.steps]:!grid-cols-[.8fr_1.2fr]" dangerouslySetInnerHTML={{ __html: hero.rest }} />
      </main>
      <div className="container-x pb-beat-s"><CompanyIdentity locale={locale} /></div>
    </>
  );
}
