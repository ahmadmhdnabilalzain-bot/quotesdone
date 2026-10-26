'use client';
// SPEC §2 — THE COMPANY DIGITAL TWIN, ON THE CUSTOMER'S OWN SCREEN.
//
// PROVENANCE, FIELD BY FIELD. Everything here comes from ONE payload: customer_portal
// action='overview' returns `twin`, which is public.fn_twin('customer', <id>) run server-side. This
// component fetches nothing else and computes nothing of its own — if a figure is not in that
// payload it is not on this screen.
//
//   industry             customers.industry
//   projects_active      count of the customer's projects not closed/cancelled/completed
//   preferred_suppliers  distinct suppliers this customer has PAID to reveal — a preference they
//                        demonstrated, not one they were asked to declare
//   preferred_categories their categories ordered by how often they actually buy them, with counts
//   understanding_pct    the share of eight profile facts the system actually holds
//
// WHY THIS EXISTED AND NOBODY COULD SEE IT. fn_twin, fn_ws_customer_360, v_digital_twin and
// customer_score were all built and all four had exactly one reader between them: os_api, the staff
// console. Section 2 of the spec is about what the CUSTOMER sees, and the customer saw none of it.
//
// NOTHING IS INVENTED. The spec illustrates "AI Understanding: 96%" — that is a mock-up, and a
// constant would be a decoration. understanding_pct counts facts held; a new account reads in the
// thirties and says which facts are missing.
import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';

export type Twin = {
  kind?: string;
  industry?: string | null;
  rfqs?: number; deals?: number; spend_aed?: number;
  projects_active?: number; projects_total?: number;
  preferred_suppliers?: number;
  preferred_categories?: Array<{ category: string; rfqs: number }> | null;
  understanding_pct?: number | null;
  last_active?: string | null;
};

const L = (lang: string, en: string, ar: string) => (lang === 'ar' ? ar : en);
const S = {
  label: 'text-[11px] uppercase tracking-wide text-muted-foreground',
  value: 'text-[17px] font-extrabold text-foreground',
  sub: 'text-[12.5px] text-muted-foreground',
};

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <div className={S.label}>{label}</div>
      <div className={cn(S.value, 'truncate')}>{children}</div>
    </div>
  );
}

export function CompanyTwin({ twin, lang = 'en' }: { twin: Twin | null; lang?: string }) {
  // An absent twin is an absent twin. The overview says so in `degraded`, and printing zeros here
  // would claim this customer has no projects and no preferred suppliers, which is a different and
  // false statement.
  if (!twin) {
    return (
      <Card className="p-3.5">
        <div className={S.label}>{L(lang, 'What we have learned about your buying', 'ما تعلّمناه عن مشترياتك')}</div>
        <div className={cn(S.sub, 'mt-1')}>
          {L(lang, 'Nothing yet. This fills in from your own requests, starting with your first one.',
                   'لا شيء بعد. تُبنى هذه المعلومات من طلباتك، بدءًا من أول طلب.')}
        </div>
      </Card>
    );
  }

  // Number(null) is 0, so an unmeasured figure rendered as "0%" (seen live 14 Sep 2026). Null stays null.
  const pct = twin.understanding_pct == null || !Number.isFinite(Number(twin.understanding_pct)) ? null : Number(twin.understanding_pct);
  const cats = Array.isArray(twin.preferred_categories) ? twin.preferred_categories : [];

  return (
    <Card className="p-3.5">
      <div className="flex items-baseline justify-between gap-2">
        <div className={S.label}>{L(lang, 'What we have learned about your buying', 'ما تعلّمناه عن مشترياتك')}</div>
        {pct !== null ? (
          <div className={S.sub} title={L(lang, 'How much of your profile we actually hold — it is a count of known facts, not a rating of you.',
                                                'نسبة ما نعرفه فعلًا عن ملفك، وهي عدٌّ لمعلومات مؤكدة لا تقييم لك.')}>
            {L(lang, 'AI understanding', 'فهم النظام')} <span className="font-bold text-foreground">{pct}%</span>
          </div>
        ) : null}
      </div>

      <div className="mt-2.5 grid grid-cols-2 gap-x-3 gap-y-2.5 sm:grid-cols-4">
        <Fact label={L(lang, 'Industry', 'القطاع')}>
          {twin.industry || <span className={S.sub}>{L(lang, 'not set', 'غير محدّد')}</span>}
        </Fact>
        <Fact label={L(lang, 'Active projects', 'مشاريع نشطة')}>{twin.projects_active ?? 0}</Fact>
        <Fact label={L(lang, 'Preferred suppliers', 'مورّدون مفضّلون')}>{twin.preferred_suppliers ?? 0}</Fact>
        <Fact label={L(lang, 'Requests', 'الطلبات')}>{twin.rfqs ?? 0}</Fact>
      </div>

      {cats.length ? (
        <div className="mt-3">
          <div className={S.label}>{L(lang, 'Buying patterns', 'أنماط الشراء')}</div>
          <div className="mt-1 flex flex-wrap gap-1.5">
            {cats.slice(0, 6).map((c) => (
              <span key={c.category} className="rounded-full border border-border bg-secondary/25 px-2 py-0.5 text-[12px] text-foreground">
                {categoryLabel(c.category, lang)} <span className="text-muted-foreground">×{c.rfqs}</span>
              </span>
            ))}
          </div>
        </div>
      ) : null}


      {pct !== null && pct < 100 ? (
        <div className={cn(S.sub, 'mt-2.5')}>
          {/* THIS SENTENCE POINTED AT A SCREEN THAT DOES NOT EXIST. There is no Settings in the
              customer portal - the standing preferences it means are the block directly below on
              this same window, and sending a customer looking for a Settings page they will never
              find is worse than saying nothing. */}
          {L(lang, 'Set your standing preferences below and every new request carries them to the suppliers we match.',
                   'حدّد تفضيلاتك الثابتة أدناه، وسينقلها كل طلب جديد إلى المورّدين الذين نطابقهم.')}
        </div>
      ) : null}
    </Card>
  );
}
