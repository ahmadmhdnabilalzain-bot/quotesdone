// THE LIVE REQUEST TRACKER (T2, owned by sales_engineer, 5 Oct 2026).
//
// One request, seven stages: Posted -> Specs complete (or held for specs) -> Sent to matching
// suppliers -> Quotes received -> Compare -> Revealed -> Job done / Reviewed. Every stage is read
// from a field customer_api my_inquiries already serves (supabase/functions/customer_api/index.ts,
// mapRow): status, rfq_ready, matched_suppliers (a COUNT, never names), quotes[].revealed /
// revealed_at / rated, hired_supplier_id, pipeline_stage and stage_changed_at. Nothing is guessed:
// a timestamp is shown only where the server recorded one, and a stage is lit only on its own fact.
//
// Pure and in its own file so it can be executed: node --test scripts/checks/the_request_tracker_reads_the_stage_from_the_servers_fields.test.mjs

export type TrackerQuote = { revealed?: boolean | null; revealed_at?: string | null; rated?: boolean | null };
export type TrackerInquiry = {
  status?: string | null; rfq_ready?: boolean | null; matched_suppliers?: number | null;
  hired_supplier_id?: string | null; pipeline_stage?: string | null; stage_changed_at?: string | null;
  created_at?: string | null;
};
export type StageKey = 'posted' | 'specs' | 'sent' | 'quotes' | 'compare' | 'revealed' | 'done';
export type TrackerStage = { key: StageKey; label: string; done: boolean; current: boolean; at: string | null };
export type Tracker = { stages: TrackerStage[]; current: number; held: boolean; closed: boolean; next: string };

const KEYS: StageKey[] = ['posted', 'specs', 'sent', 'quotes', 'compare', 'revealed', 'done'];
const CLOSED = ['cancelled', 'closed', 'lost'];

const L = {
  en: {
    posted: 'Posted', specs: 'Specs complete', held: 'Held for specs', sent: 'Sent to matching suppliers',
    sentN: (n: number) => `Sent to ${n} matching supplier${n === 1 ? '' : 's'}`,
    quotes: 'Quotes received', quotesN: (n: number) => `Quotes received (${n})`, compare: 'Compare',
    revealed: 'Revealed', done: 'Job done', reviewed: 'Job done · Reviewed',
    next: {
      specs: 'Next: add the missing details below so your request can go to suppliers.',
      sent: 'Next: we send your request to the suppliers who match it exactly.',
      quotes: 'Next: matching suppliers send their quotes. You will be notified as each one arrives.',
      compare: 'Next: a second quote lets you compare them side by side.',
      revealed: 'Next: compare the quotes and reveal the supplier you choose.',
      done: 'Next: once the job is done, rate the supplier you hired.',
      reviewed: 'Next: rate the supplier you hired.',
      complete: 'Complete. Thank you for your review.',
      closed: 'This request is closed.',
    },
  },
  ar: {
    posted: 'نُشر', specs: 'المواصفات مكتملة', held: 'بانتظار المواصفات', sent: 'أُرسل إلى الموردين المطابقين',
    sentN: (n: number) => `أُرسل إلى ${n} من الموردين المطابقين`,
    quotes: 'وردت العروض', quotesN: (n: number) => `وردت العروض (${n})`, compare: 'المقارنة',
    revealed: 'تم الكشف', done: 'اكتمل العمل', reviewed: 'اكتمل العمل · تم التقييم',
    next: {
      specs: 'التالي: أضف التفاصيل الناقصة أدناه ليُرسل طلبك إلى الموردين.',
      sent: 'التالي: نرسل طلبك إلى الموردين المطابقين له تمامًا.',
      quotes: 'التالي: يرسل الموردون المطابقون عروضهم، وسنُعلمك عند وصول كل عرض.',
      compare: 'التالي: عرض ثانٍ يتيح لك مقارنة العروض جنبًا إلى جنب.',
      revealed: 'التالي: قارن العروض واكشف المورّد الذي تختاره.',
      done: 'التالي: بعد إنجاز العمل، قيّم المورّد الذي تعاقدت معه.',
      reviewed: 'التالي: قيّم المورّد الذي تعاقدت معه.',
      complete: 'اكتمل. شكرًا على تقييمك.',
      closed: 'هذا الطلب مغلق.',
    },
  },
};

export function trackerOf(inq: TrackerInquiry | null | undefined, quotes: TrackerQuote[] | null | undefined, lang: string): Tracker {
  const s = lang === 'ar' ? L.ar : L.en;
  const i = inq || {};
  const qs = quotes || [];
  const status = String(i.status || '');
  const ps = String(i.pipeline_stage || '');
  const closed = CLOSED.includes(ps) || CLOSED.includes(status);
  const held = i.rfq_ready === false && !closed && status !== 'completed';
  const n = qs.length;
  const matched = Number(i.matched_suppliers) || 0;
  const revealedQs = qs.filter((q) => q && q.revealed);
  const isRevealed = revealedQs.length > 0 || ps === 'revealed' || ps === 'won';
  const isDone = status === 'completed' || !!i.hired_supplier_id || ps === 'won';
  const reviewed = isDone && qs.some((q) => q && q.rated);

  const reached: Record<StageKey, boolean> = {
    posted: true,
    specs: !held,
    sent: !held && status !== 'draft',
    quotes: n >= 1,
    compare: n >= 2,
    revealed: isRevealed,
    done: isDone,
  };
  // A stage counts only when every stage before it does, so a later fact never paints over a gap.
  let current = KEYS.length; // all reached
  for (let k = 0; k < KEYS.length; k++) if (!reached[KEYS[k]]) { current = k; break; }

  const revealAt = revealedQs.map((q) => q.revealed_at).filter(Boolean).sort()[0] || null;
  const psStage: StageKey | null = ps === 'revealed' ? 'revealed' : ps === 'won' ? 'done' : null;
  const atOf = (k: StageKey): string | null => {
    if (k === 'posted') return i.created_at || null;
    if (k === 'revealed' && revealAt) return revealAt;
    return psStage === k ? (i.stage_changed_at || null) : null;
  };
  const labelOf = (k: StageKey): string => {
    if (k === 'specs') return held ? s.held : s.specs;
    if (k === 'sent') return matched > 0 ? s.sentN(matched) : s.sent;
    if (k === 'quotes') return n > 0 ? s.quotesN(n) : s.quotes;
    if (k === 'done') return reviewed ? s.reviewed : s.done;
    return s[k];
  };
  const stages = KEYS.map((k, idx) => ({ key: k, label: labelOf(k), done: idx < current, current: idx === current, at: idx <= current ? atOf(k) : null }));
  const next = closed ? s.next.closed
    : current >= KEYS.length ? (reviewed ? s.next.complete : s.next.reviewed)
    : s.next[KEYS[current] as keyof typeof s.next];
  return { stages, current, held, closed, next };
}
