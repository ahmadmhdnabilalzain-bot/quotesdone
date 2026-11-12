// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { srvMsg, emirateLabel } from '../serverCopy';
import { call } from '../api';
import { firstRead } from '../tabPrefetch';
import { aed } from '../money';
import { panelErrorText } from '../PanelState';
import { categoryLabel } from '@/lib/categoryLabel';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { Ltr } from '@/lib/Ltr';
import { wentExpired, fmtDate } from './helpers';
import { t } from './copy';
import { S } from './styles';

// A revealed job: the customer paid to know this supplier. The signed Supplier Agreement (v9, cl. 11
// and 33) gives the supplier 5 working days to respond, and QuotesDone chases at 3. The customer's
// contact is shown here because this list is built from the supplier's own transactions rows — the
// reveal itself — so it cannot appear before one.
function Projects({ token, lang, openChat, onExpired }) {
  const ar = lang === 'ar';
  const [data, setData] = useState(null); const [busy, setBusy] = useState(''); const [msg, setMsg] = useState('');
  // A 401 has no `error` field of its own, so `data.error` below was false and the list rendered
  // empty: "No won projects yet" to a supplier with revealed jobs and a 5-working-day clock running
  // on each of them (SP-C-08).
  const first = useRef(true);
  const load = () => { const f = first.current; first.current = false; return (f ? firstRead(token, 'sup_tab:projects') : call('supplier_api', { action: 'projects' }, token)).then((j) => { if (wentExpired(j, onExpired, (c) => setData({ ok: false, code: c }))) return; setData(j); }); };
  useEffect(() => { load(); }, [token]);
  const ack = async (id) => {
    setBusy(id); setMsg('');
    const j = await call('supplier_api', { action: 'ack_contact', transaction_id: id }, token);
    setBusy('');
    if (j && j.ok) load(); else setMsg(srvMsg(lang, j, ar ? 'تعذّر تسجيل ذلك. يُرجى المحاولة مرة أخرى.' : 'We could not record that. Please try again.'));
  };
  if (!data) return <Card className="qd-panel p-5" aria-busy="true">{t(lang, 'loading')}</Card>;
  if (data.code === 'session_expired') return <Card role="alert" className="qd-panel p-5">{panelErrorText(lang, 'session_expired')}</Card>;
  if (data.error || data.ok !== true) return <Card role="alert" className="qd-panel p-5">{srvMsg(lang, data, t(lang, 'err_generic'))}</Card>;
  const list = data.projects || [];
  const rule = ar
    ? 'عندما يكشف العميل عن عرضكم يجب أن تتواصلوا معه خلال 5 أيام عمل من تاريخ الكشف. وإن لم تتواصلوا خلال 3 أيام عمل نتابع معكم ونُشرك العميل في المراسلة، وإن لم يصل منكم أي رد يُردّ إلى العميل كل ما دفعه، وتُستحق عليكم رسوم عدم الاستجابة: المبلغ الذي رُدّ إلى العميل بالضبط (رسوم الكشف البالغة 3%)، ورسوم مزوّد خدمة الدفع عليه التي لم نتمكن من استردادها، ورسم إداري قدره 500 درهم، وفائدة بسيطة بنسبة 12% سنويًا (أو الحد الأقصى الذي يسمح به القانون) من تاريخ الاستحقاق؛ وإن بقي دون سداد، فالرسوم الرسمية لتحصيله أيضًا. ويُحتسب الكشف الذي تم قبل قبولكم الإصدار v14 من اتفاقية المورّد وفقًا للإصدار الذي كنتم قد قبلتموه آنذاك (البند 33).'
    : 'When a customer reveals your quote you must respond to them within 5 working days of the reveal. If you have not responded within 3 working days we chase you with the customer copied; if you stay silent everything the customer paid is refunded and the non-response charge applies: the exact amount refunded (the 3% reveal fee), the payment processor fee on it that we could not recover, an AED 500 administrative fee, and simple interest at 12% a year (or the maximum lawful rate) from the due date; if it stays unpaid, the official fees of recovering it too. A reveal made before you accepted Supplier Agreement v14 is charged under the version you had accepted then (clause 33).';
  if (!list.length) return <Card className="qd-panel p-5"><div className={S.h2}>{t(lang, 'no_projects_h')}</div><div className={S.sub}>{t(lang, 'no_projects_sub')}</div><div className={cn(S.sub, 'mt-2')}>{rule}</div></Card>;
  const now = Date.now();
  return <div className={S.list}>
    <Card className="qd-panel p-4"><div className={S.sub}>{rule}</div>{msg && <div role="alert" className={S.err}>{msg}</div>}</Card>
    {list.map((p) => {
      const c = p.customer || {};
      const late = !p.acknowledged_at && p.respond_by && new Date(p.respond_by).getTime() < now;
      const chased = !p.acknowledged_at && p.chase_at && new Date(p.chase_at).getTime() < now;
      return <Card key={p.id} className="qd-panel p-5">
        <div className="flex justify-between items-start gap-3 flex-wrap">
          <div className="min-w-0">
            <div className="font-semibold text-foreground">{categoryLabel(p.category || '', lang) || t(lang, 'project_w')} · {emirateLabel(lang, p.emirate || '')}</div>
            {p.summary ? <div className={cn(S.sub, 'mt-0.5')}>{p.summary}</div> : null}
          </div>
          <div className="text-end shrink-0"><b className="tabular-nums text-foreground"><Ltr>{aed(lang, p.amount)}</Ltr></b><div className={S.sub}>{(ar ? 'كُشف في ' : 'Revealed ')}<Ltr>{fmtDate(p.revealed_at, lang)}</Ltr></div></div>
        </div>
        <div className="mt-3 rounded-md border border-border px-3.5 py-3">
          <div className="font-mono text-label uppercase tracking-caps text-muted-foreground">{ar ? 'العميل' : 'Customer'}</div>
          <div className="mt-1 text-[14px] font-semibold text-foreground"><bdi>{c.name || (ar ? 'العميل' : 'Customer')}</bdi></div>
          {/* 44 PX TO A FINGER (walk of 12 Nov 2026, S8): the customer's phone and e-mail, what he paid the reveal for, were 21 px tall. */}
          <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-[14px]">
            {c.phone ? <a className="inline-flex min-h-11 items-center text-primary font-semibold underline-offset-2 hover:underline" href={'tel:' + String(c.phone).replace(/[^\d+]/g, '')}><Ltr>{c.phone}</Ltr></a> : null}
            {c.email ? <a className="inline-flex min-h-11 items-center text-primary font-semibold underline-offset-2 hover:underline" href={'mailto:' + c.email}><Ltr>{c.email}</Ltr></a> : null}
            {!c.phone && !c.email ? <span className={S.sub}>{ar ? 'يمكنكم التواصل معه عبر الرسائل أدناه.' : 'Use the messages below to reach them.'}</span> : null}
          </div>
        </div>
        {/* The customer's post-job review (T2). Suppliers read English only (ruling 28 Sep 2026). */}
        {p.review ? <div className="mt-3 rounded-md border border-border px-3.5 py-3" dir="ltr" lang="en">
          <div className="font-mono text-label uppercase tracking-caps text-muted-foreground">Customer review</div>
          <div className="mt-1 text-[14px] font-semibold text-foreground"><span className="text-amber-500" aria-hidden="true">{'★'.repeat(p.review.rating)}{'☆'.repeat(Math.max(0, 5 - p.review.rating))}</span> <span className="sr-only">{p.review.rating} of 5 stars</span></div>
          {p.review.comment ? <p className="mt-1 text-[13px] text-foreground break-words"><bdi>{p.review.comment}</bdi></p> : null}
          {(p.review.photo_urls || []).length ? <div className="mt-2 flex flex-wrap gap-2">{p.review.photo_urls.map((u: string, i: number) => <a key={u} href={u} target="_blank" rel="noopener noreferrer"><img src={u} alt={'Customer job photo ' + (i + 1)} width={80} height={80} loading="lazy" className="size-20 rounded-md border border-border object-cover" /></a>)}</div> : null}
        </div> : null}
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <div className="text-[13px]">
            {p.acknowledged_at
              ? <Badge variant="ok">{ar ? 'سجّلتم التواصل' : 'You confirmed contact'} · <Ltr>{fmtDate(p.acknowledged_at, lang, false)}</Ltr></Badge>
              : <Badge variant={late ? 'destructive' : chased ? 'warn' : 'secondary'}>{(late ? (ar ? 'تجاوزتم مهلة الرد — ' : 'Response overdue — ') : (ar ? 'الرد قبل ' : 'Respond by '))}<Ltr>{fmtDate(p.respond_by, lang)}</Ltr></Badge>}
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => openChat(p.inquiry_id)}>{ar ? 'مراسلة العميل' : 'Message the customer'}</Button>
            {!p.acknowledged_at && <Button size="sm" disabled={busy === p.id} onClick={() => ack(p.id)}>{busy === p.id ? (ar ? 'جارٍ التسجيل…' : 'Saving…') : (ar ? 'تأكيد التواصل مع العميل' : 'I have contacted the customer')}</Button>}
          </div>
        </div>
      </Card>;
    })}
  </div>;
}
export { Projects };
