// customer_portal — the customer's entry payload. Customer-authed (own customers row).
//
// WHAT THIS FILE SERVES AND WHY EACH PIECE IS HERE (spec file #4, sections 1, 2, 20, 21):
//
//   stats            §4  the six figures the command centre already showed
//   alerts           §1  the recommendation feed. Two kinds existed (edit_window, quotes_ready) and
//                        both are reactive — they describe something the customer already did. §1
//                        asks for price moves, better lead times and approvals due, which are
//                        things the system noticed on the customer's behalf.
//   headline         §1  ONE sentence stating what needs attention today. N cards are not that
//                        sentence; the entry screen was showing cards and no line.
//   twin             §2  the business profile. fn_twin's customer branch existed with ZERO
//                        customer-reachable readers — os_api, the staff console, was the only one.
//   layout           §21 the panel order for THIS customer, and the reason it was chosen.
//
// EVERY FIGURE IS COMPUTED FROM ROWS THAT EXIST. Production holds no customers, so on production
// every list below comes back empty — an empty recommendation feed is the honest output of a
// database with no traffic, and none of these branches invents a number to avoid one.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// A routine that is missing or throws must not take the whole entry screen down with it: the
// customer's dashboard is the first thing they see and half of it is better than an error page.
// The failure is returned, not swallowed — callers put it in `degraded` so the screen can say so.
async function rpc(name: string, args: Record<string, unknown>): Promise<{ data: any; err: string | null }> {
  try {
    const { data, error } = await admin.rpc(name, args);
    return { data, err: error ? error.message : null };
  } catch (e) { return { data: null, err: String((e as Error)?.message || e) }; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return J({ error: 'unauthorized' }, 401);
    const email = (user.email || '').toLowerCase();
    let { data: cust } = await admin.from('customers').select('id,full_name,email,industry').eq('id', user.id).maybeSingle();
    if (!cust && email) { const r = await admin.from('customers').select('id,full_name,email,industry').eq('email', email).maybeSingle(); cust = r.data; }
    if (!cust) return J({ error: 'no_customer', hint: 'no customer profile for this account' }, 400);
    const b = await req.json().catch(() => ({} as any));
    const action = b.action;
    const ar = String(b.lang || 'en') === 'ar';

    if (action === 'overview') {
      const { data: stats, error } = await admin.rpc('fn_customer_stats', { p_customer: cust.id });
      if (error) return J({ error: error.message }, 500);
      const inqs = (stats && stats.inquiries) || [];
      const alerts: any[] = [];
      const degraded: string[] = [];

      const editable = inqs.filter((x: any) => x.editable);
      for (const e of editable) {
        const cat = e.category || (ar ? 'طلبك' : 'your request');
        alerts.push({ kind: 'edit_window', severity: 'medium',
          title: ar ? ('ما زال بإمكانك تعديل «' + cat + '»') : ('You can still edit “' + cat + '”'),
          detail: ar ? ('قابل للتعديل لمدة ' + e.edit_minutes_left + ' دقيقة أخرى، بعدها تُقفل التعديلات ويستمر المورّدون في التسعير على النطاق الأصلي.') : ('Editable for another ' + e.edit_minutes_left + ' minutes. After that, edits are locked and suppliers keep quoting the original scope.'),
          inquiry_id: e.id });
      }
      const toReview = inqs.filter((x: any) => (x.quotes_count || 0) > 0 && !['completed', 'closed', 'cancelled'].includes(String(x.status)));
      for (const t of toReview) {
        const cat = t.category || (ar ? 'طلبك' : 'your request');
        const n = t.quotes_count;
        alerts.push({ kind: 'quotes_ready', severity: 'low',
          title: ar ? (n + ' عرض للمراجعة على «' + cat + '»') : (n + ' quote' + (n > 1 ? 's' : '') + ' to review on “' + cat + '”'),
          detail: ar ? ('قارن العروض جنبًا إلى جنب واكشف عن المورّد الذي تريد.') : ('Compare quotes side by side and reveal the supplier you want.'),
          inquiry_id: t.id });
      }

      // ── §1 PRICE MOVES ────────────────────────────────────────────────────────────────────────
      // "Steel prices increased 3%." The move is REAL or there is no card: category_price_stats
      // holds median/p25/p75 per category over quotes actually received, and the comparison is
      // against what THIS customer last paid in that category. A category the customer has never
      // bought produces nothing, and a category with too few quotes to have a median produces
      // nothing — `n` is printed in the card so the customer can see how thin the sample is.
      const myCats = [...new Set(inqs.map((x: any) => String(x.category || '')).filter(Boolean))].slice(0, 12);
      if (myCats.length) {
        const { data: px } = await admin.from('category_price_stats').select('category,n,median').in('category', myCats);
        const { data: mine } = await admin.from('transactions')
          .select('quote_amount,inquiry_id,inquiries!inner(category)')
          .eq('customer_id', cust.id).eq('fee_status', 'paid').limit(200);
        const lastPaid: Record<string, number> = {};
        for (const t of (mine || []) as any[]) {
          const c = t?.inquiries?.category; const v = Number(t?.quote_amount);
          if (c && Number.isFinite(v) && v > 0 && !(c in lastPaid)) lastPaid[c] = v;
        }
        for (const row of (px || []) as any[]) {
          const paid = lastPaid[row.category]; const med = Number(row.median);
          if (!paid || !Number.isFinite(med) || med <= 0 || Number(row.n) < 3) continue;
          const pct = Math.round(((med - paid) / paid) * 100);
          if (Math.abs(pct) < 3) continue;
          const up = pct > 0;
          alerts.push({ kind: 'price_move', severity: up ? 'medium' : 'low', category: row.category,
            title: ar ? (row.category + ': السوق ' + (up ? 'أعلى' : 'أقل') + ' بنسبة ' + Math.abs(pct) + '%')
                      : (row.category + ' is quoting ' + Math.abs(pct) + '% ' + (up ? 'above' : 'below') + ' what you last paid'),
            detail: ar ? ('الوسيط الحالي ' + Math.round(med) + ' درهم عبر ' + row.n + ' عرضًا، مقابل ' + Math.round(paid) + ' دفعتها آخر مرة.')
                       : ('Median now AED ' + Math.round(med) + ' across ' + row.n + ' quotes, against AED ' + Math.round(paid) + ' you last paid.'),
            move_pct: pct, sample: row.n });
        }
      }

      // ── §1 BETTER LEAD TIMES ──────────────────────────────────────────────────────────────────
      // "5 suppliers have better lead times." Measured against the suppliers this customer's own
      // open RFQs actually reached — a faster supplier the customer never contacted is not news
      // about their procurement, it is an advert.
      const openIds = inqs.filter((x: any) => !['completed', 'closed', 'cancelled'].includes(String(x.status))).map((x: any) => x.id).slice(0, 25);
      if (openIds.length) {
        const { data: matched } = await admin.from('inquiry_matches').select('supplier_id,inquiry_id').in('inquiry_id', openIds).limit(400);
        const supIds = [...new Set((matched || []).map((m: any) => m.supplier_id).filter(Boolean))];
        if (supIds.length) {
          const { data: sc } = await admin.from('supplier_score').select('lead_id,avg_response_hours').in('lead_id', supIds);
          const known = (sc || []).filter((s: any) => Number.isFinite(Number(s.avg_response_hours)));
          if (known.length >= 2) {
            const hrs = known.map((s: any) => Number(s.avg_response_hours)).sort((x, y) => x - y);
            const mid = hrs[Math.floor(hrs.length / 2)];
            const faster = known.filter((s: any) => Number(s.avg_response_hours) < mid).length;
            if (faster > 0) alerts.push({ kind: 'lead_time', severity: 'low',
              title: ar ? (faster + ' مورّد يردّون أسرع من متوسط قائمتك') : (faster + ' supplier' + (faster > 1 ? 's' : '') + ' on your RFQs respond faster than the rest'),
              detail: ar ? ('الوسيط ' + Math.round(mid) + ' ساعة عبر ' + known.length + ' مورّدًا لديهم سجل قياس.')
                         : ('Median response is ' + Math.round(mid) + 'h across the ' + known.length + ' matched suppliers that have a measured record.'),
              faster_count: faster, median_hours: Math.round(mid) });
          }
        }
      }

      // ── §1 APPROVALS DUE ──────────────────────────────────────────────────────────────────────
      // "2 quotes require approval." fn_approval_list already projects every request with its steps
      // for this customer; the entry screen simply had no reader of it.
      const appr = await rpc('fn_approval_list', { p_customer: cust.id });
      if (appr.err) degraded.push('approvals');
      const pending = ((appr.data && appr.data.requests) || []).filter((r: any) => String(r.status || '') === 'pending');
      if (pending.length) alerts.push({ kind: 'approval_due', severity: 'high',
        title: ar ? (pending.length + ' طلب شراء بانتظار موافقة') : (pending.length + ' purchase request' + (pending.length > 1 ? 's' : '') + ' waiting on approval'),
        detail: ar ? ('افتح لوحة الموافقات لمعرفة الخطوة المتوقفة ومن صاحبها.') : ('Open Approvals to see which step is holding and whose it is.'),
        count: pending.length });

      // ── §20 FORECAST ──────────────────────────────────────────────────────────────────────────
      // "You will likely need electrical cables within 45 days." fn_customer_forecast computes it
      // per customer with a horizon; nothing customer-facing called it.
      const fc = await rpc('fn_customer_forecast', { p_customer: cust.id, p_horizon_days: 90 });
      if (fc.err) degraded.push('forecast');
      const preds = (Array.isArray(fc.data) ? fc.data : (fc.data && fc.data.predictions) || []).slice(0, 3);
      for (const p of preds as any[]) {
        const what = p.category || p.item || p.label;
        const days = p.within_days ?? p.horizon_days ?? p.days;
        if (!what) continue;
        alerts.push({ kind: 'forecast_need', severity: 'low', category: what, within_days: days ?? null,
          title: ar ? ('من المرجّح أن تحتاج ' + what + (days ? ' خلال ' + days + ' يومًا' : '')) : ('You will likely need ' + what + (days ? ' within ' + days + ' days' : '')),
          detail: ar ? ('بناءً على وتيرة مشاريعك السابقة. ابدأ طلب عروض الآن لتترك وقتًا للتوريد.') : ('Based on the rhythm of your past projects. Starting the RFQ now leaves room for lead time.') });
      }

      // ── §1 THE HEADLINE ───────────────────────────────────────────────────────────────────────
      // ONE sentence. It names the highest-severity thing outstanding and says how many others
      // there are. With nothing outstanding it says so plainly rather than manufacturing urgency:
      // "your active projects require attention today" printed over an empty feed is the same
      // unconditional-reassurance defect as the empty state this row was opened to fix, inverted.
      const RANK: Record<string, number> = { high: 3, medium: 2, low: 1 };
      const top = alerts.slice().sort((x, y) => (RANK[y.severity] || 0) - (RANK[x.severity] || 0))[0];
      const headline = !alerts.length
        ? (ar ? 'لا شيء يحتاج انتباهك الآن.' : 'Nothing needs your attention right now.')
        : (ar ? (top.title + (alerts.length > 1 ? ' — و' + (alerts.length - 1) + ' بند آخر.' : '.'))
              : (top.title + (alerts.length > 1 ? ' — and ' + (alerts.length - 1) + ' other item' + (alerts.length > 2 ? 's' : '') + '.' : '.')));

      // ── §2 THE TWIN ───────────────────────────────────────────────────────────────────────────
      const tw = await rpc('fn_twin', { p_kind: 'customer', p_id: String(cust.id) });
      if (tw.err) degraded.push('twin');
      const twin = tw.data && !tw.data.error ? tw.data : null;

      // ── §21 THE LAYOUT ────────────────────────────────────────────────────────────────────────
      // Panels ordered by what this customer actually has, most-pressing first, with the reason
      // recorded beside it. A stored layout the customer arranged by hand WINS: a computed order
      // that silently overrides a deliberate choice is worse than no adaptation at all.
      const { data: saved } = await admin.from('customer_layout').select('layout,pinned,reason').eq('customer_id', cust.id).maybeSingle();
      const weight: Record<string, number> = {
        projects: (twin?.projects_active || 0) * 10,
        approvals: pending.length * 40,
        messages: 0,
        documents: 0,
        orders: 0,
        predict: preds.length * 8,
        spatial: (twin?.projects_active || 0) * 4,
        account: -10,
      };
      const computed = Object.keys(weight).sort((x, y) => weight[y] - weight[x]);
      const pinned: string[] = Array.isArray(saved?.pinned) ? saved!.pinned as string[] : [];
      const order = [...pinned, ...computed.filter((k) => !pinned.includes(k))];
      const layout = {
        order,
        pinned,
        source: (saved?.layout && Array.isArray(saved.layout) && (saved.layout as unknown[]).length) ? 'saved' : 'computed',
        reason: saved?.reason || (pending.length ? 'approvals are blocking work' : (twin?.projects_active ? 'ordered by live project activity' : 'default order — no activity to rank on yet')),
      };

      return J({ ok: true, customer: { id: cust.id, name: cust.full_name, industry: cust.industry },
                 stats, alerts, alerts_count: alerts.length, headline, twin, layout,
                 degraded: degraded.length ? degraded : undefined });
    }

    // §21: the customer fixes a panel where they want it. Written straight back so the next
    // overview returns source:'saved' and stops re-ranking underneath them.
    if (action === 'save_layout') {
      const pin = Array.isArray(b.pinned) ? b.pinned.map((s: unknown) => String(s)).slice(0, 12) : [];
      const ord = Array.isArray(b.order) ? b.order.map((s: unknown) => String(s)).slice(0, 24) : [];
      const { error: e } = await admin.from('customer_layout')
        .upsert({ customer_id: cust.id, layout: ord, pinned: pin, reason: 'arranged by the customer', computed_at: new Date().toISOString() }, { onConflict: 'customer_id' });
      if (e) return J({ error: e.message }, 500);
      return J({ ok: true, layout: { order: ord, pinned: pin, source: 'saved' } });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
