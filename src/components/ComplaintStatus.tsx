'use client';
// Public complaint status: ticket number + email -> complaint_status edge function.
// Timers are the Complaints Policy promises: acknowledgement in 2 working days, final response in 10.
import { useEffect, useState } from 'react';
import { useLocale } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';
import { Button } from '@/components/ui/button';

type Status = 'acknowledged' | 'in_review' | 'final_response';
type Ticket = {
  ticket: string; status: Status; created_at: string; acknowledge_due: string; respond_due: string;
  acknowledged_at: string | null; in_review_at: string | null; final_response_at: string | null;
  final_response: string | null; acknowledge_days_left: number; respond_days_left: number;
  // D4: the reference of the final decision and which seat made it; null until a final response exists.
  decision_ref?: string | null; decided_by?: 'customer_support' | 'ceo' | null;
};

const T = {
  en: {
    title: 'Complaint status', intro: 'Enter the ticket number we gave you and the email you used.',
    ticket: 'Ticket number', email: 'Email', check: 'Check status', checking: 'Checking…',
    steps: { acknowledged: 'Acknowledged', in_review: 'In review', final_response: 'Final response' },
    ackDue: 'Acknowledgement due by', ackDays: '(2 working days)',
    resDue: 'Final response due by', resDays: '(10 working days)',
    left: (n: number) => (n === 1 ? '1 working day left' : `${n} working days left`), dueToday: 'due today',
    met: 'met', ourResponse: 'Our final response',
    decisionRef: 'Decision reference', decidedBy: { customer_support: 'Decided by customer support', ceo: 'Decided by our chief executive' },
    escalateTitle: 'Not satisfied with our final response?',
    escalate: 'You can take your complaint further to the consumer authorities:',
    det: 'Dubai DET Consumer Rights', app: 'the Dubai Consumer app (App Store / Google Play)',
    hotline: 'UAE Ministry of Economy consumer hotline', policy: 'Read our Complaints Policy',
    notFound: 'We could not find a ticket with that number and email. Please check both and try again.',
    invalid: 'Please enter a ticket number like QD-C-ABC234 and a valid email.',
    limited: 'Too many lookups. Please wait a few minutes and try again.',
    failed: 'The status service is unavailable right now. Please try again shortly.',
  },
  ar: {
    title: 'حالة الشكوى', intro: 'أدخل رقم التذكرة الذي أرسلناه إليك والبريد الإلكتروني الذي استخدمته.',
    ticket: 'رقم التذكرة', email: 'البريد الإلكتروني', check: 'عرض الحالة', checking: 'جارٍ التحقق…',
    steps: { acknowledged: 'تم الاستلام', in_review: 'قيد المراجعة', final_response: 'الرد النهائي' },
    ackDue: 'موعد تأكيد الاستلام', ackDays: '(يوما عمل)',
    resDue: 'موعد الرد النهائي', resDays: '(10 أيام عمل)',
    left: (n: number) => `متبقٍ ${n} ${n === 1 ? 'يوم عمل' : 'أيام عمل'}`, dueToday: 'مستحق اليوم',
    met: 'تم الوفاء', ourResponse: 'ردّنا النهائي',
    decisionRef: 'مرجع القرار', decidedBy: { customer_support: 'قرّره فريق خدمة العملاء', ceo: 'قرّره رئيسنا التنفيذي' },
    escalateTitle: 'لست راضيًا عن ردّنا النهائي؟',
    escalate: 'يمكنك رفع شكواك إلى جهات حماية المستهلك:',
    det: 'حماية المستهلك - دائرة الاقتصاد والسياحة في دبي', app: 'تطبيق Dubai Consumer (متجر App Store / Google Play)',
    hotline: 'الخط الساخن لحماية المستهلك - وزارة الاقتصاد', policy: 'اطّلع على سياسة الشكاوى',
    notFound: 'لم نعثر على تذكرة بهذا الرقم وهذا البريد الإلكتروني. يرجى التحقق منهما والمحاولة مجددًا.',
    invalid: 'يرجى إدخال رقم تذكرة مثل QD-C-ABC234 وبريد إلكتروني صحيح.',
    limited: 'عدد كبير من محاولات البحث. يرجى الانتظار بضع دقائق ثم المحاولة مجددًا.',
    failed: 'خدمة الحالة غير متاحة حاليًا. يرجى المحاولة بعد قليل.',
  },
};
const ORDER: Status[] = ['acknowledged', 'in_review', 'final_response'];

export function ComplaintStatus() {
  const locale = useLocale();
  const ar = locale === 'ar';
  const t = ar ? T.ar : T.en;
  const [ticket, setTicket] = useState('');
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [res, setRes] = useState<Ticket | null>(null);

  useEffect(() => {
    const q = new URLSearchParams(window.location.search).get('t');
    if (q) setTicket(q.toUpperCase().slice(0, 20));
  }, []);

  const fmt = (iso: string) => new Date(iso).toLocaleDateString(ar ? 'ar-AE' : 'en-AE', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Dubai' });

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(''); setRes(null); setBusy(true);
    try {
      const r = await fetch(FN + '/complaint_status', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: ANON, Authorization: 'Bearer ' + ANON }, body: JSON.stringify({ ticket: ticket.trim(), email: email.trim() }) });
      const j = await r.json().catch(() => ({} as any));
      if (r.ok && j.ok) setRes(j as Ticket);
      else setErr(j.error === 'not_found' ? t.notFound : j.error === 'invalid_input' ? t.invalid : j.error === 'rate_limited' ? t.limited : t.failed);
    } catch { setErr(t.failed); }
    setBusy(false);
  }

  const timer = (label: string, days: string, due: string, doneAt: string | null, left: number) => (
    <li className="qd-row !gap-x-4 !px-5 !py-4 sm:!grid-cols-[1fr_auto]">
      <span className="text-body text-paper">{label} <strong className="text-white">{fmt(due)}</strong> <span className="text-faint">{days}</span></span>
      <span className={'font-mono text-label ' + (doneAt ? 'text-teal-light' : left > 0 ? 'text-muted' : 'text-warn-fg')}>
        {doneAt ? `${t.met} (${fmt(doneAt)})` : left > 0 ? t.left(left) : t.dueToday}
      </span>
    </li>
  );

  const cur = res ? ORDER.indexOf(res.status) : -1;
  const inputCls = 'mt-2 h-12 w-full rounded-btn border border-line2 bg-navy-deep/60 px-4 font-mono text-copy text-paper shadow-key outline-none transition-[border-color,box-shadow] duration-base placeholder:text-faint focus:border-teal focus:shadow-ring';

  return (
    <main id="main" dir={ar ? 'rtl' : 'ltr'}>
      <section className="qd-keylight relative overflow-hidden border-b border-line">
        <span className="grid-tech" aria-hidden />
        <div className="container-x relative pb-12 pt-16 md:pb-16 md:pt-24">
          <span className="qd-kicker">{ar ? 'الشكاوى' : 'Complaints'}</span>
          <h1 className="mt-6 font-head text-display-sm text-white">{t.title}</h1>
          <p className="mt-5 max-w-[56ch] text-lead text-muted">{t.intro}</p>
        </div>
      </section>
      <div className="container-x py-12 md:py-16">
      <div className="mx-auto max-w-[760px]">
        <form onSubmit={submit} className="qd-panel qd-grain grid gap-5 p-6 sm:grid-cols-2 md:p-8">
          <label className="block text-small font-medium text-muted">{t.ticket}
            <input className={inputCls} dir="ltr" required value={ticket} onChange={(e) => setTicket(e.target.value.toUpperCase())} placeholder="QD-C-ABC234" autoComplete="off" />
          </label>
          <label className="block text-small font-medium text-muted">{t.email}
            <input className={inputCls} dir="ltr" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
          </label>
          <div className="sm:col-span-2">
            <Button type="submit" size="lg" disabled={busy} className="w-full sm:w-auto">
              {busy ? t.checking : t.check}
            </Button>
          </div>
        </form>

        {err && <p role="alert" className="mt-6 rounded-panel border border-danger/40 bg-danger/10 px-4 py-3 text-body text-danger-fg">{err}</p>}

        {res && (
          <section className="qd-frame mt-10" aria-live="polite">
            <div className="qd-frame-bar"><i /><i /><i /><span className="ms-2 font-mono text-label text-muted">{t.ticket}: <bdi dir="ltr" className="text-paper">{res.ticket}</bdi></span></div>

            <ol className="grid grid-cols-3 border-b border-line">
              {ORDER.map((s, i) => (
                <li key={s} aria-current={i === cur ? 'step' : undefined}
                  className={'relative flex flex-col items-center gap-2.5 px-2 py-5 text-center text-small font-semibold ' + (i <= cur ? 'text-white' : 'text-faint')}>
                  <span aria-hidden className={'grid h-7 w-7 place-items-center rounded-full border font-mono text-label ' + (i < cur ? 'border-teal bg-teal/20 text-teal-light' : i === cur ? 'border-teal bg-teal/20 text-teal-light shadow-glow-teal' : 'border-line2 text-faint')}>
                    {i < cur ? '✓' : String(i + 1).padStart(2, '0')}
                  </span>
                  {t.steps[s]}
                  <span aria-hidden className={'absolute inset-x-0 bottom-0 h-0.5 ' + (i <= cur ? 'bg-teal' : 'bg-transparent')} />
                </li>
              ))}
            </ol>

            <ul>
              {timer(t.ackDue, t.ackDays, res.acknowledge_due, res.acknowledged_at, res.acknowledge_days_left)}
              {timer(t.resDue, t.resDays, res.respond_due, res.final_response_at, res.respond_days_left)}
            </ul>

            {res.status === 'final_response' && (
              <div className="border-t border-line p-6 md:p-7">
                {res.final_response && (
                  <div>
                    <h2 className="font-head text-h3 text-white">{t.ourResponse}</h2>
                    <p className="mt-3 whitespace-pre-wrap text-copy text-paper/90">{res.final_response}</p>
                    {res.decision_ref && (
                      <p className="mt-3 text-small text-muted">
                        {t.decisionRef}: <bdi dir="ltr" className="font-mono">{res.decision_ref}</bdi>
                        {res.decided_by ? <> · {t.decidedBy[res.decided_by]}</> : null}
                      </p>
                    )}
                  </div>
                )}
                <div className="qd-panel mt-8 px-5 py-5 text-body">
                  <h2 className="font-head text-[16px] font-semibold text-white">{t.escalateTitle}</h2>
                  <p className="mt-2 text-muted">{t.escalate}</p>
                  <ul className="mt-3 list-disc space-y-1.5 ps-5">
                    <li><a className="underline" href="https://consumerrights.ae" target="_blank" rel="noopener noreferrer">{t.det}</a> — <bdi dir="ltr">consumerrights.ae</bdi></li>
                    <li>{t.app}</li>
                    <li>{t.hotline}: <a className="underline" href="tel:8001222"><bdi dir="ltr">800 1222</bdi></a></li>
                  </ul>
                  <p className="mt-3"><Link className="text-teal-light underline underline-offset-2 hover:text-white" href="/complaints">{t.policy}</Link></p>
                </div>
              </div>
            )}
          </section>
        )}
      </div>
      </div>
    </main>
  );
}
