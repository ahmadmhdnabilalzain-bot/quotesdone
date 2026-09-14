'use client';
// Public complaint status: ticket number + email -> complaint_status edge function.
// Timers are the Complaints Policy promises: acknowledgement in 2 working days, final response in 10.
import { useEffect, useState } from 'react';
import { useLocale } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SUPA_ANON as ANON, SUPA_FN as FN } from '@/lib/supaEnv';

type Status = 'acknowledged' | 'in_review' | 'final_response';
type Ticket = {
  ticket: string; status: Status; created_at: string; acknowledge_due: string; respond_due: string;
  acknowledged_at: string | null; in_review_at: string | null; final_response_at: string | null;
  final_response: string | null; acknowledge_days_left: number; respond_days_left: number;
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
    <li className="rounded-xl border border-[var(--line)] bg-teal-light/[0.03] px-4 py-3 text-[14.5px]">
      <span>{label} <strong>{fmt(due)}</strong> {days}</span>
      <span className="ms-2 text-muted">
        — {doneAt ? `${t.met} (${fmt(doneAt)})` : left > 0 ? t.left(left) : t.dueToday}
      </span>
    </li>
  );

  const cur = res ? ORDER.indexOf(res.status) : -1;
  const inputCls = 'mt-1.5 w-full rounded-xl border border-[var(--line)] bg-transparent px-4 py-3 text-[15px] outline-none focus:border-[var(--line2)]';

  return (
    <main id="main" className="container-x py-beat-s md:py-beat" dir={ar ? 'rtl' : 'ltr'}>
      <div className="mx-auto max-w-[720px]">
        <h1 className="text-[clamp(28px,4vw,40px)] font-bold">{t.title}</h1>
        <p className="mt-3 text-[16px] leading-relaxed text-muted">{t.intro}</p>

        <form onSubmit={submit} className="mt-8 grid gap-4 sm:grid-cols-2">
          <label className="block text-[14px]">{t.ticket}
            <input className={inputCls} dir="ltr" required value={ticket} onChange={(e) => setTicket(e.target.value.toUpperCase())} placeholder="QD-C-ABC234" autoComplete="off" />
          </label>
          <label className="block text-[14px]">{t.email}
            <input className={inputCls} dir="ltr" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
          </label>
          <div className="sm:col-span-2">
            <button type="submit" disabled={busy} className="btn-key press rounded-full bg-teal px-8 py-3.5 text-[15px] font-bold text-[#04231F] transition-colors duration-200 hover:bg-[#1ED0BC] disabled:opacity-60">
              {busy ? t.checking : t.check}
            </button>
          </div>
        </form>

        {err && <p role="alert" className="mt-6 rounded-xl border border-[var(--line2)] px-4 py-3 text-[14.5px] text-[#ff9a9a]">{err}</p>}

        {res && (
          <section className="mt-10 border-t border-[var(--line)] pt-8" aria-live="polite">
            <p className="font-mono text-[13px] uppercase tracking-[0.12em] text-muted">{t.ticket}: <bdi dir="ltr">{res.ticket}</bdi></p>

            <ol className="mt-5 grid grid-cols-3 gap-2">
              {ORDER.map((s, i) => (
                <li key={s} aria-current={i === cur ? 'step' : undefined}
                  className={'rounded-xl border px-3 py-3 text-center text-[13.5px] font-semibold ' + (i <= cur ? 'border-teal bg-teal/15' : 'border-[var(--line)] text-muted')}>
                  {t.steps[s]}
                </li>
              ))}
            </ol>

            <ul className="mt-6 grid gap-3">
              {timer(t.ackDue, t.ackDays, res.acknowledge_due, res.acknowledged_at, res.acknowledge_days_left)}
              {timer(t.resDue, t.resDays, res.respond_due, res.final_response_at, res.respond_days_left)}
            </ul>

            {res.status === 'final_response' && (
              <>
                {res.final_response && (
                  <div className="mt-8">
                    <h2 className="text-[18px] font-bold">{t.ourResponse}</h2>
                    <p className="mt-3 whitespace-pre-wrap text-[15px] leading-relaxed">{res.final_response}</p>
                  </div>
                )}
                <div className="mt-8 rounded-xl border border-[var(--line2)] bg-teal-light/[0.05] px-5 py-4 text-[14.5px] leading-relaxed">
                  <h2 className="text-[16px] font-bold">{t.escalateTitle}</h2>
                  <p className="mt-2 text-muted">{t.escalate}</p>
                  <ul className="mt-3 list-disc space-y-1.5 ps-5">
                    <li><a className="underline" href="https://consumerrights.ae" target="_blank" rel="noopener noreferrer">{t.det}</a> — <bdi dir="ltr">consumerrights.ae</bdi></li>
                    <li>{t.app}</li>
                    <li>{t.hotline}: <a className="underline" href="tel:8001222"><bdi dir="ltr">800 1222</bdi></a></li>
                  </ul>
                  <p className="mt-3"><Link className="underline" href="/complaints">{t.policy}</Link></p>
                </div>
              </>
            )}
          </section>
        )}
      </div>
    </main>
  );
}
