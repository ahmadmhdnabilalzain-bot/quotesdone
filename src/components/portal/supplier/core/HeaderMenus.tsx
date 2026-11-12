// @ts-nocheck
'use client';
import { useEffect, useRef, useState } from 'react';
import { ws } from '../workspaceCopy';
import { srvText, itemCopy } from '../serverCopy';
import { Bell } from 'lucide-react';
import { cn } from '@/lib/utils';
import { MAIN_TABS, ACCOUNT_TABS } from './tabs';

// A NATIVE <details> IS A DISCLOSURE, AND A POPOVER IS EXPECTED TO CLOSE (a11y review, 18 Sep 2026).
// `<details>` gives us keyboard operation and a second-press close for free, which is why the bell and
// the Account menu below use it. What it does NOT give is the two things everyone tries on a panel
// floating over the page: Escape, and clicking away from it. The customer portal's own bell has both
// (src/components/me/PortalShell.tsx: a keydown listener and a full-viewport backdrop button); these two
// had neither, so a supplier who opened the Account menu and changed their mind was left with it pinned
// open over the tab strip. Nine lines, once, for both.
function useDismissablePopover() {
  const ref = useRef(null);
  useEffect(() => {
    const shut = () => {
      const d = ref.current;
      if (!d || !d.open) return false;
      d.open = false;
      return true;
    };
    const onKey = (e) => { if (e.key === 'Escape' && shut()) { const s = ref.current.querySelector('summary'); if (s) s.focus(); } };
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) shut(); };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('pointerdown', onDown); };
  }, []);
  return ref;
}
// BOTH PANELS FLOAT OVER THE PAGE AND STAY ON THE SCREEN (12 Nov 2026, customer_support; founder ruling 1645, browser walk finding
// H5). Measured on production at 390 px: opening the bell or the Account menu pushed the company name down 150 px and 154 px, and
// the bell's panel ended at x = 441 of a 390 px screen. `.qd-panel` sets position: relative (globals.css, the sealed panel's own
// rule), which beat the `absolute` on the same element, so each panel was laid out INSIDE the <details> and the page moved under
// it. The panel is now an absolutely positioned wrapper AROUND the .qd-panel. And it is placed against the row that holds both
// menus (Dashboard: `relative` on that row; the <details> themselves are static), not against its own button: the bell sits left
// of the Account menu, so a 320 px panel aligned to the bell's own edge started off the left of a phone screen. Its width is
// min(320 px, the screen less two 16 px gutters). Escape and a tap outside close both, as before; nothing is trapped.
// Prevented by: scripts/checks/the_portal_menus_float_over_the_page.test.mjs.
const PANEL = 'absolute inset-e-0 top-full z-30 mt-2';

// THE BELL (15 Sep 2026). One list of what is waiting for this supplier, fed by what the dashboard call
// already carries: unread customer messages, quotes held for exact details, and the overview alerts
// (new RFQs, draft quotes, expiring documents). Each item opens the tab where it is dealt with. A native
// <details> is the popover: it opens with the keyboard and closes on a second press with no script.
function NotificationBell({ ov, lang, go }) {
  const ar = lang === 'ar'; const n = ov.notifications || {};
  const msgs = n.unread_messages || 0; const holds = n.spec_holds || 0; const alerts = ov.alerts || [];
  const items = [
    msgs ? { k: 'm', tab: 'messages', text: ar ? `${msgs} ${msgs === 1 ? 'رسالة غير مقروءة' : 'رسائل غير مقروءة'} من العملاء` : `${msgs} unread customer message${msgs > 1 ? 's' : ''}` } : null,
    holds ? { k: 'h', tab: 'quotes', text: ar ? `${holds} ${holds === 1 ? 'عرض محجوز' : 'عروض محجوزة'} بانتظار تفاصيل دقيقة` : `${holds} quote${holds > 1 ? 's' : ''} held for exact details` } : null,
    ...alerts.map((a, i) => ({ k: 'a' + i, tab: a.action === 'documents' ? 'documents' : a.kind === 'draft_quote' ? 'quotes' : 'rfqs', text: itemCopy(lang, a).title })),
  ].filter(Boolean);
  // WHAT THE ESTATE TOLD THIS SUPPLIER (audit 21 Sep 2026, finding 6): a customer revealing this
  // supplier's quote changed nothing on the bell. Every notice carries a SUPPLIER-portal tab, never a
  // URL (finding 5: the only link a supplier had was the e-mail's, which opened the customer portal),
  // and a notice counts on the badge until the bell is opened once (the newest id seen is remembered).
  const notices = (n.notices || []).filter((x) => MAIN_TABS.includes(x.tab)).slice(0, 8);
  // THIS BADGE IS PER-DEVICE, AND THAT IS ALL IT CAN BE TODAY (audit 22 Sep 2026, SP-A-04).
  //
  // `qd-sup-notice-seen` is the newest notice id this BROWSER has seen. A notice read on a phone is
  // still bold on the laptop, and clearing site data makes every notice new again. Checked 22 Sep
  // 2026 before writing this: there is no server-side read state to persist it to —
  // public.notifications has no read_at/seen_at/dismissed_at column (supabase/schema/full_schema.sql),
  // RLS is enabled on it with no policy so no client may write it at all, and supplier_portal's
  // `notifications` action only READS (overview.ts buildNotifications). The one read-state write in
  // the estate is messages_api setting messages.read_by_supplier as a side effect of opening a
  // thread, which does nothing for this list. Making the badge authoritative needs a column and an
  // action in supplier_portal — the edge functions are not this seat's to change — so until then it
  // is a per-device convenience and must not be described as anything more.
  const [seen, setSeen] = useState(() => { try { return Number(localStorage.getItem('qd-sup-notice-seen') || 0); } catch (_e) { return 0; } });
  const fresh = notices.filter((x) => x.id > seen).length;
  const markSeen = () => { const top = notices.length ? notices[0].id : 0; if (top > seen) { setSeen(top); try { localStorage.setItem('qd-sup-notice-seen', String(top)); } catch (_e) {} } };
  const badge = items.length + fresh;
  const label = ar ? `الإشعارات (${badge})` : `Notifications (${badge})`;
  const ref = useDismissablePopover();
  const when = (at) => { try { return new Date(at).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short' }); } catch (_e) { return ''; } };
  return (
    <details ref={ref} onToggle={(e) => { if (e.currentTarget.open) markSeen(); }}>
      <summary aria-label={label} title={label} className="relative inline-flex min-h-11 min-w-11 cursor-pointer list-none items-center justify-center rounded-md border border-border text-muted-foreground hover:text-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring [&::-webkit-details-marker]:hidden">
        <Bell aria-hidden className="h-[18px] w-[18px]" />
        {badge ? <span aria-hidden className="absolute -top-1 -inset-e-1 rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold leading-none text-primary-foreground tabular-nums">{badge}</span> : null}
      </summary>
      <div className={cn(PANEL, 'w-[min(320px,calc(100vw-32px))]')}><div className="qd-panel max-h-[min(70vh,520px)] overflow-y-auto bg-popover! p-1.5 shadow-e3!">
        {items.length ? <ul>{items.map((it) => (
          <li key={it.k}><button type="button" className="flex min-h-11 w-full items-center rounded-md px-3 py-2.5 text-start text-[13px] text-foreground hover:bg-muted focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
            onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(it.tab); }}>{it.text}</button></li>))}</ul>
          : (fresh ? null : <div className="px-3 py-2.5 text-[13px] text-muted-foreground">{ar ? 'لا شيء جديد.' : 'Nothing new.'}</div>)}
        {notices.length ? <div className="mt-1 border-t border-border pt-1">
          <div className="px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{ar ? 'آخر الإشعارات' : 'Recent notices'}</div>
          <ul>{notices.map((x) => (
            <li key={'n' + x.id}><button type="button" className="flex min-h-11 w-full items-center justify-between gap-3 rounded-md px-3 py-2 text-start text-[13px] text-foreground hover:bg-muted focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
              onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(x.tab); }}>
              <span className={x.id > seen ? 'font-semibold' : ''}>{srvText(lang, 'notice_' + x.type, {}, srvText(lang, 'notice_quote', {}, ''))}</span>
              <span className="shrink-0 text-[11px] text-muted-foreground">{when(x.at)}</span></button></li>))}</ul>
        </div> : null}
      </div></div>
    </details>
  );
}
// THE ACCOUNT MENU (15 Sep 2026): Profile, Billing and Settings, out of the main tabs. A native
// <details>, like the bell: keyboard-operable and closed by a second press with no script.
function AccountMenu({ tab, labels, lang, go }) {
  const on = ACCOUNT_TABS.includes(tab);
  const ref = useDismissablePopover();
  return (
    <details ref={ref}>
      {/* L7 (12 Nov 2026, browser walk): "Account · Profile ▾" broke onto two baselines at 390 px; it stays on one line and the
          current page's name gives way first (truncate), so the button never wraps. */}
      <summary className={cn('inline-flex min-h-11 max-w-[min(15rem,calc(100vw-96px))] cursor-pointer list-none items-center gap-1.5 whitespace-nowrap rounded-md border border-border px-3 text-[13px] font-semibold focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring [&::-webkit-details-marker]:hidden', on ? 'text-primary' : 'text-muted-foreground hover:text-foreground')}>
        <span className="shrink-0">{ws(lang, 'account_menu')}</span>{on ? <span className="min-w-0 truncate font-normal">· {labels[tab]}</span> : null}<span aria-hidden className="shrink-0">▾</span>
      </summary>
      <div className={cn(PANEL, 'w-48')}><ul className="qd-panel bg-popover! p-1.5 shadow-e3!">
        {ACCOUNT_TABS.map((k) => (
          <li key={k}><button type="button" aria-current={tab === k ? 'page' : undefined}
            className={cn('flex min-h-11 w-full items-center rounded-md px-3 text-start text-[13px] hover:bg-muted focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring', tab === k ? 'font-semibold text-primary' : 'text-foreground')}
            onClick={(e) => { const d = e.currentTarget.closest('details'); if (d) d.open = false; go(k); }}>{labels[k]}</button></li>
        ))}
      </ul></div>
    </details>
  );
}
export { NotificationBell, AccountMenu };
