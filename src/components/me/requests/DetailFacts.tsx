// @ts-nocheck
'use client';
import { cn } from '@/lib/utils';
import DocActions from '@/components/portal/DocActions';
import { S } from '../styles';

function DetailFacts({ inq, lang }) {
  const rows = [];
  if (inq.budget) rows.push([lang === 'ar' ? 'الميزانية' : 'Budget', String(inq.budget)]);
  if (Array.isArray(inq.trades) && inq.trades.length) rows.push([lang === 'ar' ? 'التخصصات' : 'Trades', inq.trades.join(', ')]);
  if (inq.boq && inq.boq.boq && inq.boq.boq.length) rows.push([lang === 'ar' ? 'عدد البنود' : 'Line items', String(inq.boq.boq.length)]);
  const sp = inq.spec && typeof inq.spec === 'object' ? inq.spec : null;
  if (sp) for (const k of Object.keys(sp)) { const v = sp[k]; if (v && typeof v === 'string' && k !== 'plausibility' && k !== 'provenance') rows.push([k.replace(/_/g, ' '), v]); }
  // What the customer told the sales engineer they want (installation, warranty, materials, date).
  // `display` is written by _shared/intake_requirements.ts in both languages, so this reads it rather
  // than re-deriving the words (docs/contracts/intake_answers.md).
  const req = sp && sp.customer_requirements && sp.customer_requirements.display;
  if (req && Array.isArray(req[lang === 'ar' ? 'ar' : 'en'])) for (const r of req[lang === 'ar' ? 'ar' : 'en']) if (r && r.label && r.value) rows.push([r.label, r.value]);
  // How confident the reader was about the BOQ it pulled off the customer's drawing. The customer
  // is the only person who can tell us it read the drawing wrong, and they were never shown it.
  const conf = Number(inq.boq_confidence);
  if (Number.isFinite(conf) && inq.boq && inq.boq.boq) rows.push([lang === 'ar' ? 'دقة قراءة المخطط' : 'Drawing read confidence', Math.round(conf <= 1 ? conf * 100 : conf) + '%']);
  // my_inquiries signs a URL to the customer's OWN uploaded drawing on every call. Nothing read it,
  // so the one person entitled to that file could not open it — only the suppliers could.
  // The four actions (instruction 524). The drawing was sent to suppliers with the request, so
  // Replace / Remove say so rather than acting: what they quoted on stays what they quoted on.
  const drawing = inq.drawing_file_url
    ? (<div className="mt-1.5">
        <div className={cn(S.sub, 'mb-1')}>{lang === 'ar' ? '📐 المخطط الذي رفعته' : '📐 The drawing you uploaded'}{inq.drawing_file_name ? <> (<bdi>{inq.drawing_file_name}</bdi>)</> : null}</div>
        <DocActions lang={lang} name={inq.drawing_file_name} url={inq.drawing_file_url} sealed="sent_to_suppliers" />
      </div>)
    : null;
  if (!rows.length && !drawing) return null;
  return (<div className="rounded-lg border border-border bg-secondary/20 p-3"><div className={cn(S.sub, 'font-semibold mb-1.5 text-foreground')}>{lang === 'ar' ? 'تفاصيل الطلب' : 'Request details'}</div><div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-1">{rows.slice(0, 14).map((r, i) => (<div key={i} className={S.sub}><span className="capitalize text-muted-foreground">{r[0]}: </span><span className="text-foreground">{r[1]}</span></div>))}</div>{drawing}</div>);
}
export { DetailFacts };
