// @ts-nocheck
'use client';
import { photoToDataUrl } from '@/lib/chatPhoto';
// THE PORTAL SHELL — an application frame, not a page with a menu.
//
// WHAT THIS REPLACES AND WHY. The founder registered as a customer on 13 Aug 2026, opened /en/me,
// and said: "so many tabs that are irrelevant to customers ... the visuals, extremely basic, felt
// so static and super outdated." Rendered at 1280 and 375 (which the previous session did not do),
// the screen was a stack of identical full-width cards under TEN identical grey pill buttons —
// Projects, Approvals, Messages, Documents, Orders, What you may need next, Project room, Account,
// Company profile, Home — in server-ranked order, with no icons, no grouping, no active state, and
// "Home" last. Every module behind those pills is real and most of them are good. The pills were
// the product's navigation and they read as a debug toolbar.
//
// The two structural lessons from the reference designs he supplied, which matter more than the
// palette: a customer belongs INSIDE an application with a persistent sidebar, and the assistant is
// a PRIMARY SURFACE — the widest element on the page — not a bubble in the corner.
//
// THREE THINGS THIS FILE MUST NOT BREAK, all of them earned:
//   1. RTL. Every inline direction here is LOGICAL (ms/me/ps/pe/start/end/border-e). No ml-, no
//      left-, no fixed left/right. Arabic is half the market.
//   2. Bidi isolation. Assistant replies carry +971 numbers, emails and paths; they render through
//      ChatWidget's `render`, which wraps each in <bdi>. Imported, never re-implemented.
//   3. Keyboard and screen-reader access. Every destination is a real <button>; the open one
//      carries aria-current; the mobile overflow carries aria-expanded. The 5 Aug a11y fix in
//      CustomerPortal exists because this exact class of control was once a bare <div onClick>.
import { useEffect, useRef, useState } from 'react';
import {
  LayoutDashboard, FileText, Files, MessagesSquare, FolderKanban,
  Sparkles, Building2, UserCircle, Boxes, Compass, Search, Bell, Menu, X,
  Sun, Moon, LogOut, ChevronRight, Send,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { render } from '@/components/ChatWidget';
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';
import { BrandMark } from '@/components/BrandMark';
import { forgetWidgetConv, readWidgetConv } from '@/lib/widgetConv';
import { lookForStoredAnswer, answerRightAfter, noVerdict, pendingDue, readReply, savedLineDue, waitingOf, PENDING_EVERY_MS, PENDING_FOR_MS } from '@/lib/portalReply';

// THE INFORMATION ARCHITECTURE, WRITTEN DOWN.
//
// The old bar was a flat list of nine modules plus Home, ordered by the server. Flat lists stop
// being navigable at about seven items; this one had ten and no captions, so a customer looking for
// their quotes had to read every label. Grouping is the fix, and the groups are the customer's
// own mental model of a procurement job, not our module boundaries:
//
//   WORK          what they came for — the request, the quotes, the paperwork
//   COLLABORATE   the people and the decisions around it
//   INTELLIGENCE  what the system worked out for them
//   ACCOUNT       who we think they are
//
// `id` values are the SAME ids the existing ModuleWindow already switches on, so this is a
// navigation change and not a rewrite of nine working modules. 'home' is the dashboard itself.
export const NAV_GROUPS = [
  { caption: 'nav_work', items: [
    { id: 'home',      icon: LayoutDashboard, label: 'nav_overview' },
    { id: 'requests',  icon: FileText,        label: 'nav_requests' },
    { id: 'documents', icon: Files,           label: 'mod_documents' },
    { id: 'orders',    icon: Boxes,           label: 'mod_orders' },
  ] },
  { caption: 'nav_collaborate', items: [
    { id: 'messages',  icon: MessagesSquare,  label: 'messages', badge: 'unread' },
    { id: 'projects',  icon: FolderKanban,    label: 'projects' },
    { id: 'spatial',   icon: Compass,         label: 'mod_spatial' },
  ] },
  { caption: 'nav_intelligence', items: [
    { id: 'predict',   icon: Sparkles,        label: 'mod_predict' },
    { id: 'profile',   icon: Building2,       label: 'mod_profile' },
  ] },
  { caption: 'nav_account', items: [
    { id: 'account',   icon: UserCircle,      label: 'mod_account' },
  ] },
];
// EVERY DESTINATION IS A WORD, IN EVERY STATE (founder, 14 Sep 2026: "the side bar for all those
// tabs is not clear enough. i mean from the logo no one will understand, so maybe replacing the
// logo with text is better"). "Logo" there meant the icons. Measured before this change: the
// "Collapse menu" state painted all eleven destinations as a bare 18px icon with the name only in a
// hover tooltip, and the group captions were monospace capitals. The collapsed mode is gone rather
// than relabelled, every item carries its name, and an icon is decoration beside the name, never
// instead of it.
//
// The phone gets the four a thumb reaches for; everything else lives behind More. Chosen by what a
// customer opens, not by group order: the dashboard, their requests, the inbox, the paperwork.
const MOBILE_PRIMARY = ['home', 'requests', 'messages', 'documents'];

// ── THE ASSISTANT, AS A SURFACE ────────────────────────────────────────────────────────────────
// THE SEAT CHANGED ON 9 SEPTEMBER 2026, and the endpoint had to change with it. The founder, asked
// where the chat widget routes: "if its on the home page then the support replies. but if its on
// the customer or supplier portal then its the sales engineer cause he is much stronger
// technically." site_assistant is Customer Support's function — correct for ChatWidget on the
// public site, wrong here. This panel is INSIDE the portal, so it goes to the Sales Engineer.
//
// The token still goes with it, and for the same reason it always did: sales_engineer resolves the
// verified session to the caller's OWN customer row and scopes the answer to it. Passing the token
// is what turns "I can't see your account" into an answer; it is not optional decoration, and the
// function will not accept a party named in the body from a portal caller.
//
// WHAT THE ANSWER IS NOW. There is no model available — every LLM route is held by the founder
// until 2126 — so the Sales Engineer retrieves from its own 1,136-record knowledge body under a
// 0.86 similarity floor corroborated by a lexical match, and REFUSES when nothing clears it. A
// refusal arrives as a normal reply that says so and hands off to Support; the widget needs no
// special case for it.
// THE CUSTOMER'S ONE CONVERSATION (founder ruling 1255): sales_engineer keeps every turn under the account, and the
// website-widget chat they had before signing up (its id in localStorage) is adopted once, by assist_history on mount.
const widgetConv = () => readWidgetConv();
// THE ANSWER STREAMS (27 Oct 2026, customer_support): a status line at once, then each checked sentence as it is
// written (src/lib/portalReply.ts). Measured before: every turn waited 58-150 s in silence and one hit the edge's 150 s
// wall as a 504, whose HTML body made r.json() throw and the panel print its error line. A server that does not stream
// answers JSON, read the same way; nothing here throws.
async function askAssistant(message, history, token, lang, path, images = [], on = {}) {
  try {
    const r = await fetch(fnUrl('sales_engineer'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/x-ndjson, application/json', Authorization: 'Bearer ' + (token || ANON) },
      body: JSON.stringify({ action: 'assist', message, history, path: path || '/me', lang, ...(images.length ? { images } : {}) }),
    });
    return await readReply(r, on);
  } catch (e) {
    return { reply: '', streamed: false, done: null, failed: String((e && e.message) || e) };
  }
}
// A TURN THAT DID NOT REACH THE BROWSER IS LOOKED FOR, NOT REPORTED AS AN ERROR. The server stores every answer under the
// customer's one conversation (ruling 1255) even when the connection dropped, so the panel reads it back from
// assist_history for up to LATE_WAIT_MS before it says, calmly, that the question is saved and the answer will appear here.
const LATE_WAIT_MS = 90_000;
const LATE_EVERY_MS = 6_000;
async function storedAnswer(token, question) {
  return lookForStoredAnswer(async () => {
    const r = await fetch(fnUrl('sales_engineer'), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
      body: JSON.stringify({ action: 'assist_history' }) });
    const j = r.ok ? await r.json() : null;
    return j && j.turns;
  }, question, { waitMs: LATE_WAIT_MS, everyMs: LATE_EVERY_MS });
}

// `suggestions` ARE THE OFFER, and they used to be three constants — the same three questions on a
// day-one account with nothing in it and on an account with three quotes waiting to be compared.
// "What is the status of my requests?" offered to someone who has never posted one is a menu, not
// an offer. CustomerPortal derives them from the rows it already holds and passes them down; an
// empty list falls back to the three constants, so a caller that does not compute them is unchanged.
export function AssistantPanel({ token, lang, open, onClose, seed, t, suggestions }) {
  const rtl = lang === 'ar';
  const [msgs, setMsgs] = useState([]);
  const [val, setVal] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');   // the server's status line, or the late notice while the stored answer is looked for
  const [live, setLive] = useState('');       // the checked sentences shown so far, as they are written
  const boxRef = useRef(null);
  const inpRef = useRef(null);
  const fileRef = useRef(null);
  const [photo, setPhoto] = useState('');
  const sentSeed = useRef('');
  // A TURN STILL OWED THE MODEL'S ANSWER (src/lib/portalReply.ts pendingDue; supabase/functions/_shared/reask.ts). Its
  // marker (role 'pending') is UI state: "still working on your answer", or "with your sales engineer" once handed off.
  // It is replaced by the answer when the re-ask fills that turn's row, read back from assist_history every 10 s.
  const watching = useRef(new Set());
  const alive = useRef(true);
  useEffect(() => () => { alive.current = false; }, []);
  const pendingText = (state) => t(state === 'with_team' ? 'asst_with_team' : 'asst_working');
  const watch = (question) => {
    if (!token || watching.current.has(question)) return;
    watching.current.add(question);
    (async () => {
      const until = Date.now() + PENDING_FOR_MS;
      while (alive.current && Date.now() < until) {
        await new Promise((res) => setTimeout(res, PENDING_EVERY_MS));
        try {
          const r = await fetch(fnUrl('sales_engineer'), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
            body: JSON.stringify({ action: 'assist_history' }) });
          const j = r.ok ? await r.json() : null;
          const a = answerRightAfter(j && j.turns, question);
          if (a) {
            setMsgs((m) => m.map((x) => (x.role === 'pending' && x.q === question ? { role: 'assistant', content: a } : x)));
            break;
          }
          const w = waitingOf(j).find((x) => x.message.trim() === question.trim());
          if (w) setMsgs((m) => m.map((x) => (x.role === 'pending' && x.q === question ? { ...x, content: pendingText(w.state) } : x)));
        } catch (_e) { /* asked again on the next tick */ }
      }
      watching.current.delete(question);
    })();
  };
  // redrawn from the database on every visit: a reload, another device or days later shows the whole conversation
  useEffect(() => {
    if (!token) return;
    const wc = widgetConv();   // adopt is sent on this mount after sign-in; the widget id is removed only after it succeeds
    fetch(fnUrl('sales_engineer'), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
      body: JSON.stringify({ action: 'assist_history', ...(wc ? { widget_conv: wc, adopt: true } : {}) }) })
      // the widget id is cleared only once the server answered and nothing is left to adopt (moved now, or already moved)
      .then((r) => (r.ok ? r.json() : null)).then((j) => {
        if (wc && j && !j.error && !j.pending) { forgetWidgetConv(); }
        if (!(Array.isArray(j?.turns) && j.turns.length)) return;
        // a turn still owed its answer gets its pending marker right under the question, and is watched
        const shown = [...j.turns];
        for (const w of waitingOf(j)) {
          let k = -1;
          for (let i = shown.length - 1; i >= 0; i--) if (shown[i].role === 'user' && String(shown[i].content || '').trim() === w.message.trim()) { k = i; break; }
          if (k < 0 || (shown[k + 1] && shown[k + 1].role === 'assistant')) continue;
          shown.splice(k + 1, 0, { role: 'pending', q: w.message, content: pendingText(w.state) });
          watch(w.message);
        }
        setMsgs(shown);
      })
      .catch(() => { /* the next turn still reads the whole conversation on the server */ });
  }, [token]);

  useEffect(() => { if (boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight; }, [msgs, busy, open, live, status]);
  useEffect(() => { if (open) setTimeout(() => inpRef.current && inpRef.current.focus(), 80); }, [open]);

  const send = async (text) => {
    const q = String(text == null ? val : text).trim() || (photo ? (rtl ? '(صورة)' : '(photo)') : '');
    if (!q || busy) return;
    const images = photo ? [photo] : [];
    setPhoto('');
    setVal(''); setBusy(true);
    // a notice is the panel's own line, never a turn of the conversation: it is not sent back as history
    const history = msgs.filter((m) => m.role === 'user' || m.role === 'assistant').map((m) => ({ role: m.role, content: m.content }));
    setMsgs((m) => [...m, { role: 'user', content: q }]);
    setStatus(''); setLive('');
    const j = await askAssistant(q, history, token, lang, '/me', images, { status: setStatus, text: setLive });
    let reply = j.reply;
    // only an answer that never ARRIVED is looked for; a turn the server answered with no reply has nothing stored
    if (!reply && token && noVerdict(j)) {
      setLive(''); setStatus(t('asst_late'));
      reply = await storedAnswer(token, q);
    }
    setLive(''); setStatus('');
    // the saved line only on a transport failure or when OpenRouter was down (1339, savedLineDue); with the model up and
    // nothing sendable, no code-written text is shown
    // a turn filed for the re-ask (model up, every draft refused): the pending state, then the model's answer (never silence)
    setMsgs((m) => reply
      ? [...m, { role: 'assistant', content: reply, scope: j.done && j.done.scope }]
      : pendingDue(j) ? [...m, { role: 'pending', q, content: t('asst_working') }]
      : savedLineDue(j, reply) ? [...m, { role: 'notice', content: t('asst_saved') }] : m);
    setBusy(false);
    if (!reply && pendingDue(j)) watch(q);
  };

  // A question typed into the top bar opens this panel already carrying it, so the widest element
  // on the page is a real entry point and not a decorative box that makes you type twice.
  useEffect(() => {
    if (open && seed && sentSeed.current !== seed) { sentSeed.current = seed; send(seed); }
  }, [open, seed]);

  if (!open) return null;
  return (
    <aside
      role="complementary"
      aria-label={t('asst_title')}
      className={cn(
        // THE MOBILE TAB BAR STAYS TAPPABLE (E2E stage 1, D7, 30 Sep 2026): below md the panel stops above the
        // 56px tab bar instead of covering it (inset-y-0 put it over the menu; 18 nav taps timed out at 375px).
        'fixed top-0 bottom-[var(--qd-tabbar-h,0px)] md:bottom-0 z-40 flex w-full flex-col border-border bg-card shadow-e3',
        // max-w, not w: a fixed 420px panel is 45px wider than a 375px viewport and cannot shrink.
        'end-0 sm:w-full sm:max-w-[420px] sm:border-s',
        'motion-safe:animate-in motion-safe:slide-in-from-bottom-4 sm:motion-safe:slide-in-from-right-4 motion-safe:duration-300',
      )}
    >
      <header className="flex items-center gap-2 border-b border-border px-4 py-3">
        <span className="grid h-8 w-8 place-items-center rounded-lg bg-primary/15 text-primary"><Sparkles className="h-4 w-4" aria-hidden /></span>
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13.5px] font-bold text-foreground">{t('asst_title')}</div>
          <div className="truncate text-[11.5px] text-muted-foreground">{t('asst_sub')}</div>
        </div>
        <Button variant="ghost" size="sm" onClick={onClose} aria-label={t('close')}><X className="h-4 w-4" aria-hidden /></Button>
      </header>

      <div ref={boxRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {!msgs.length && (
          <div className="space-y-3">
            <p className="text-[13.5px] leading-relaxed text-muted-foreground">{t('asst_greet')}</p>
            <div className="flex flex-col gap-1.5">
              {((suggestions && suggestions.length) ? suggestions : ['asst_s1', 'asst_s2', 'asst_s3'].map(t)).map((q) => (
                <button key={q} type="button" onClick={() => send(q)}
                  className="flex items-center gap-2 rounded-lg border border-border bg-secondary/25 px-3 py-2 text-start text-[13px] text-foreground transition-colors hover:border-primary/40 hover:bg-primary/10">
                  <Search className="h-3.5 w-3.5 shrink-0 text-primary" aria-hidden />
                  <span className="min-w-0 flex-1">{q}</span>
                  <ChevronRight className={cn('h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
                </button>
              ))}
            </div>
          </div>
        )}
        {msgs.map((m, i) => (
          <div key={i} className={cn('flex', m.role === 'user' ? 'justify-end' : 'justify-start')}>
            <div className={cn(
              'max-w-[86%] rounded-2xl px-3.5 py-2.5 text-[13.5px] leading-relaxed',
              m.role === 'user' ? 'bg-primary text-primary-foreground' : 'border border-border bg-secondary/30 text-foreground',
            )}>
              {/* Assistant replies carry phone numbers, emails and portal paths. ChatWidget's
                  renderer escapes then wraps each in <bdi>; without it they scramble in Arabic. */}
              {m.role === 'assistant'
                ? <span dangerouslySetInnerHTML={{ __html: render(m.content) }} />
                : m.role === 'notice' ? <span className="italic text-muted-foreground">{m.content}</span>
                : m.role === 'pending' ? (
                  <span className="flex items-center gap-1.5 italic text-muted-foreground" aria-live="polite">
                    {[0, 1, 2].map((d) => (
                      <span key={d} className="h-1.5 w-1.5 rounded-full bg-muted-foreground/70 motion-safe:animate-pulse" style={{ animationDelay: d * 180 + 'ms' }} />
                    ))}
                    <span className="ms-1">{m.content}</span>
                  </span>)
                : m.content}
            </div>
          </div>
        ))}
        {busy && live && (
          <div className="flex justify-start" aria-live="polite">
            <div className="max-w-[86%] rounded-2xl border border-border bg-secondary/30 px-3.5 py-2.5 text-[13.5px] leading-relaxed text-foreground">
              <span dangerouslySetInnerHTML={{ __html: render(live) }} />
            </div>
          </div>
        )}
        {busy && !live && (
          <div className="flex justify-start" aria-live="polite">
            <div className="flex items-center gap-1.5 rounded-2xl border border-border bg-secondary/30 px-3.5 py-3">
              {[0, 1, 2].map((d) => (
                <span key={d} className="h-1.5 w-1.5 rounded-full bg-muted-foreground/70 motion-safe:animate-pulse"
                  style={{ animationDelay: d * 180 + 'ms' }} />
              ))}
              {status
                ? <span className="ms-1 text-[12.5px] italic text-muted-foreground">{status}</span>
                : <span className="sr-only">{t('asst_thinking')}</span>}
            </div>
          </div>
        )}
      </div>

      <form className="flex items-end gap-2 border-t border-border p-3"
        onSubmit={(e) => { e.preventDefault(); send(); }}>
        {/* A photo or drawing with the next message (ruling 1200): resized in the browser, checked again on the server. */}
        <input ref={fileRef} type="file" accept="image/*" hidden onChange={async (e) => { const d = await photoToDataUrl(e.target.files && e.target.files[0]); if (d) setPhoto(d); e.target.value = ''; }} />
        <Button type="button" variant={photo ? 'secondary' : 'outline'} size="sm" className="h-11 px-3" disabled={busy}
          onClick={() => fileRef.current && fileRef.current.click()} aria-label={rtl ? 'أرفق صورة أو مخططًا' : 'Add a photo or drawing'}>
          {photo ? (rtl ? 'تم إرفاق الصورة' : 'Photo attached') : (rtl ? 'صورة' : 'Photo')}
        </Button>
        <input ref={inpRef} value={val} onChange={(e) => setVal(e.target.value)} disabled={busy}
          aria-label={t('asst_ph')} placeholder={t('asst_ph')}
          className="h-11 min-w-0 flex-1 rounded-xl border border-input bg-background px-3.5 text-[13.5px] text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        <Button type="submit" size="sm" className="h-11 px-3.5" disabled={busy || (!val.trim() && !photo)} aria-label={t('asst_send')}>
          <Send className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden />
        </Button>
      </form>
    </aside>
  );
}

// ── STAT TILE ──────────────────────────────────────────────────────────────────────────────────
// The old Kpi was a bare number over a caption in a flat box, six across. This gives each number a
// tinted glyph and an optional one-line meaning, and — the part that matters — an emphatic variant
// so "awaiting your decision" does not look the same as "requests". A zero that is GOOD and a zero
// that means nothing has happened yet are different facts and must not render identically.
export function StatTile({ icon: Icon, label, value, hint, tone = 'default' }) {
  return (
    <Card className={cn(
      'group relative overflow-hidden p-4 shadow-e1 transition-[transform,border-color,box-shadow] duration-300 hover:shadow-e2 motion-safe:hover:-translate-y-0.5 sm:p-5',
      tone === 'accent' && 'border-primary/40',
    )}>
      {/* The kit's lit top edge, on the tile that is asking for a decision. */}
      {tone === 'accent' ? <span aria-hidden className="absolute inset-x-6 top-0 h-px bg-gradient-to-r from-transparent via-primary/80 to-transparent" /> : null}
      <div className="flex items-start justify-between gap-2">
        {/* Wraps, never truncates: "AWAITING YOUR DECISI…" cut the tile's one word that mattered. */}
        <div className="min-w-0 break-words font-mono text-label uppercase tracking-caps text-muted-foreground">{label}</div>
        <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-panel border',
          tone === 'accent' ? 'border-primary/35 bg-primary/12 text-primary' : 'border-border bg-secondary/40 text-muted-foreground')}>
          <Icon className="h-4 w-4" aria-hidden />
        </span>
      </div>
      <div className={cn('tabular mt-3 font-head text-[30px] font-semibold leading-none tracking-snug',
        tone === 'accent' ? 'text-primary' : 'text-foreground')}>{value}</div>
      {hint ? <div className="mt-2 text-[11.5px] leading-snug text-muted-foreground/85">{hint}</div> : null}
    </Card>
  );
}

// ── STATUS PILL ────────────────────────────────────────────────────────────────────────────────
// The five stages of OUR lifecycle. A marketplace has no "Shipped" and no "Processing"; it has a
// request that is being matched, then quoted, then decided, then revealed, then closed. Colour
// carries meaning and is never the ONLY carrier — the word is always present.
export const RFQ_STATE = {
  matching:  { key: 'st_matching',  cls: 'bg-info/12 text-info-fg border-info/25',           variant: 'info' },
  quoting:   { key: 'st_quoting',   cls: 'bg-warn/12 text-warn-fg border-warn/25',           variant: 'warn' },
  quotes_in: { key: 'st_quotes_in', cls: 'bg-primary/12 text-primary border-primary/30',     variant: 'default' },
  revealed:  { key: 'st_revealed',  cls: 'bg-ok/12 text-ok-fg border-ok/25',                 variant: 'ok' },
  closed:    { key: 'st_closed',    cls: 'bg-secondary/60 text-muted-foreground border-border', variant: 'outline' },
};
// Derived from facts the row already carries, never from the clock.
export function rfqState(inq, quotes) {
  const n = (quotes || []).length;
  if (['completed', 'closed', 'cancelled'].includes(String(inq && inq.status))) return 'closed';
  if ((quotes || []).some((q) => q.revealed) || (inq && inq.hired_supplier_id)) return 'revealed';
  if (n >= 2) return 'quotes_in';
  if (n >= 1) return 'quoting';
  return 'matching';
}
export function StatusPill({ state, t }) {
  const s = RFQ_STATE[state] || RFQ_STATE.matching;
  return (
    // The kit Badge with its status light; `closed` keeps the muted token so it reads in both themes.
    <Badge variant={s.variant} dot className={cn('shrink-0 font-semibold', state === 'closed' && 'text-muted-foreground')}>
      {t(s.key)}
    </Badge>
  );
}

// ── THE SHELL ──────────────────────────────────────────────────────────────────────────────────
// §21's per-customer panel ranking, kept and moved. customer_portal returns layout.order ranked by
// what this customer actually has outstanding, and it used to reorder a flat bar of ten pills. It
// now reorders items WITHIN their group, so the ranking still surfaces what is waiting on them
// without shuffling "Account" into the middle of their work.
//
// CSS `order`, not array order — the same reason the original bar used it: `order` moves the
// painted position and leaves the DOM alone, so a server-side ranking can never reorder a keyboard
// user's tab sequence. Unranked items sort last because indexOf returns -1.
// THE SPINE IS NOT A PANEL. Overview and My requests are the two destinations the portal is FOR;
// the server's ranking is over the §22 module panels and does not mention them, so they scored 99
// and the first render put "Documents, Orders, Overview, My requests" in the Work group — the
// dashboard third in its own menu. They are pinned ahead of the ranking rather than inside it.
const PINNED = { home: -2, requests: -1 };
const rankOf = (id, order) => {
  if (id in PINNED) return PINNED[id];
  const ids = Array.isArray(order) ? order.map(String) : [];
  const i = ids.indexOf(id);
  return i < 0 ? 99 : i;
};

export function PortalShell({
  lang, t, theme, onSwapTheme, onSetLang, onSignOut,
  view, onView, customerName, unread = 0, alerts = 0, alertList = [], onAlert, token, order, suggestions, children,
}) {
  const rtl = lang === 'ar';
  const [moreOpen, setMoreOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [asstOpen, setAsstOpen] = useState(false);
  const [seed, setSeed] = useState('');
  const [q, setQ] = useState('');
  const searchRef = useRef(null);

  // FOCUS COMES BACK TO THE CONTROL THAT OPENED THE PANEL (a11y review, 18 Sep 2026).
  // Choosing a destination in the More sheet, or an alert in the bell list, or closing the
  // assistant, unmounts the very element that holds focus — `go()` sets moreOpen false and the
  // whole `{moreOpen && …}` block goes with it. A browser then drops focus on <body>, so a
  // keyboard user's next Tab restarts at the top of the document instead of continuing from the
  // control they were on (WCAG 2.4.3). One place, because all three close down several paths:
  // Escape, the backdrop, and the choice itself.
  const moreBtn = useRef(null);
  // THE TAB BAR PUBLISHES ITS REAL HEIGHT (E2E stage 1 D7 follow-up, 30 Sep 2026): it measured 69px on production
  // at 375px, not the 56 the panel assumed, so the panel covered its top 13px. offsetHeight includes the
  // safe-area padding, and is 0 when the bar is hidden (md and up), where panels sit on the bottom edge.
  // A callback ref, not an effect: the bar mounts after the shell's first render (measured: an effect on [] saw null).
  const tabBarObs = useRef<ResizeObserver | null>(null);
  const tabBar = useRef((el: HTMLElement | null) => {
    tabBarObs.current?.disconnect(); tabBarObs.current = null;
    const root = document.documentElement.style;
    if (!el) { root.removeProperty('--qd-tabbar-h'); return; }
    const set = () => root.setProperty('--qd-tabbar-h', el.offsetHeight + 'px');
    // border-box: the safe-area inset is PADDING, which a content-box observer never reports (measured: 57px kept after +34px).
    set(); tabBarObs.current = new ResizeObserver(set); tabBarObs.current.observe(el, { box: 'border-box' });
  }).current;   // one stable callback, so React does not detach and re-attach it on every render
  const bellBtn = useRef(null);
  const wasOpen = useRef({ more: false, bell: false, asst: false });
  useEffect(() => {
    const back = (was, now, el) => {
      if (was && !now && el && (document.activeElement === document.body || !document.activeElement)) el.focus();
      return now;
    };
    wasOpen.current = {
      more: back(wasOpen.current.more, moreOpen, moreBtn.current),
      bell: back(wasOpen.current.bell, bellOpen, bellBtn.current),
      asst: back(wasOpen.current.asst, asstOpen, searchRef.current),
    };
  }, [moreOpen, bellOpen, asstOpen]);

  // A placeholder that says what the field can do is the point of the field — and at 375px
  // "Ask about your requests, quotes or documents…" renders as "Ask about your", which says
  // nothing and looks broken. A placeholder cannot be set per breakpoint in CSS, so it is set here.
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    // The retired collapse preference is cleared so a stale '1' left in a browser means nothing.
    try { localStorage.removeItem('qd-nav-collapsed'); } catch (_e) {}
    const mq = window.matchMedia('(max-width: 639px)');
    const sync = () => setNarrow(mq.matches);
    sync(); mq.addEventListener('change', sync);
    return () => mq.removeEventListener('change', sync);
  }, []);
  // Cmd/Ctrl+K puts the cursor in the assistant field. The shortcut exists because the field is the
  // primary way to use the portal, not a search box bolted onto one.
  useEffect(() => {
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && String(e.key).toLowerCase() === 'k') { e.preventDefault(); searchRef.current && searchRef.current.focus(); }
      if (e.key === 'Escape') { setMoreOpen(false); setBellOpen(false); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const go = (id) => { setMoreOpen(false); onView(id); };
  const submitAsk = (e) => {
    e.preventDefault();
    const text = q.trim(); if (!text) { setAsstOpen(true); return; }
    setSeed(text); setQ(''); setAsstOpen(true);
  };

  const isActive = (id) => view === id || (id === 'home' && (view === '' || view === 'home'));
  // The name wraps rather than truncates: "What you may need next" cut to "What you may ne…" is
  // the same unreadable navigation this change exists to remove, just shorter.
  const NavButton = ({ item }) => {
    const Icon = item.icon;
    const active = isActive(item.id);
    return (
      <button
        type="button"
        data-nav-id={item.id}
        onClick={() => go(item.id)}
        aria-current={active ? 'page' : undefined}
        style={{ order: rankOf(item.id, order) }}
        className={cn(
          'group relative flex min-h-11 w-full items-center gap-2.5 rounded-xl px-3 py-2 text-[14px] font-medium transition-colors duration-200',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          active ? 'bg-primary/14 font-semibold text-primary' : 'text-foreground/80 hover:bg-secondary/50 hover:text-foreground',
        )}
      >
        {/* The active marker is on the INLINE START edge so it lands on the correct side in Arabic. */}
        {active ? <span className="absolute inset-y-1.5 start-0 w-[3px] rounded-full bg-primary" aria-hidden /> : null}
        <Icon className="h-4 w-4 shrink-0 opacity-70" aria-hidden />
        <span className="min-w-0 flex-1 break-words text-start leading-snug">{t(item.label)}</span>
        {item.badge === 'unread' && unread > 0
          ? <span className="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground tabular-nums">{unread}</span>
          : null}
      </button>
    );
  };

  const mobileItems = NAV_GROUPS.flatMap((g) => g.items).filter((i) => MOBILE_PRIMARY.includes(i.id));
  const overflowGroups = NAV_GROUPS
    .map((g) => ({ ...g, items: g.items.filter((i) => !MOBILE_PRIMARY.includes(i.id)) }))
    .filter((g) => g.items.length);

  return (
    <div className="flex min-h-screen w-full">
      {/* ── SIDEBAR (desktop) ─────────────────────────────────────────────────────────────── */}
      {/* One width, always labelled. 240px at tablet leaves the 768px main column 528px; 264px
          from 1024 up. There is no icon-only state to fall into. */}
      <nav
        aria-label={t('nav_main')}
        className="sticky top-0 hidden h-screen w-[240px] shrink-0 flex-col border-e border-border bg-card/80 md:flex lg:w-[264px]"
      >
        <div className="flex items-center gap-2 px-4 py-4">
          <BrandMark className="h-9 w-9 shrink-0" />
          <div className="min-w-0">
            <div className="truncate font-head text-[15px] font-extrabold leading-tight text-foreground">QuotesDone</div>
            <div className="truncate text-[11px] text-muted-foreground">{t('brand_sub')}</div>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-4">
          {NAV_GROUPS.map((g) => (
            <div key={g.caption} role="group" aria-labelledby={'qd-nav-' + g.caption} className="mb-4">
              {/* A heading in plain words and sentence case — not monospace capitals. */}
              <div id={'qd-nav-' + g.caption} className="px-3 pb-1 text-[12.5px] font-semibold text-muted-foreground">{t(g.caption)}</div>
              <div className="flex flex-col gap-0.5">
                {g.items.map((item) => <NavButton key={item.id} item={item} />)}
              </div>
            </div>
          ))}
        </div>
      </nav>

      {/* ── MAIN COLUMN ───────────────────────────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 border-b border-border bg-background/95 shadow-e1">
          <div className="flex items-center gap-2 px-3 py-2.5 sm:gap-3 sm:px-5">
            <BrandMark className="h-9 w-9 shrink-0 md:hidden" />

            {/* THE ASSISTANT FIELD — the widest element on the page, by design. In the reference
                the founder supplied, AI search is the primary surface; ours was a bubble in a
                corner, which is half of why he called it a chat bot. */}
            <form onSubmit={submitAsk} className="min-w-0 flex-1" role="search">
              <label className="sr-only" htmlFor="qd-ask">{t('ask_ph')}</label>
              <div className="group relative flex items-center">
                <Sparkles className="pointer-events-none absolute start-3.5 h-4 w-4 text-primary" aria-hidden />
                <input
                  id="qd-ask" ref={searchRef} value={q} onChange={(e) => setQ(e.target.value)}
                  placeholder={narrow ? t('ask_ph_short') : t('ask_ph')} autoComplete="off"
                  className={cn(
                    'h-11 w-full rounded-btn border border-input bg-card ps-11 pe-3 sm:pe-16 text-[13.5px] text-foreground shadow-e1',
                    'placeholder:text-muted-foreground focus-visible:outline-none',
                    'focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-primary/25',
                    'transition-[border-color,box-shadow] duration-200',
                  )}
                />
                <kbd className="pointer-events-none absolute end-3 hidden rounded border border-border bg-secondary/60 px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:block">⌘K</kbd>
              </div>
            </form>

            {/* A BELL MUST SHOW WHAT IT COUNTS. customer_portal returns the alerts themselves, not
                only alerts_count, so the dot has a list behind it. A notification control that
                opens something other than the notifications is the same defect this codebase keeps
                finding: an instrument reporting on a different subject to the one it names. */}
            <div className="relative shrink-0">
              <button type="button" ref={bellBtn} onClick={() => setBellOpen((v) => !v)}
                aria-label={t('alerts_label')} aria-expanded={bellOpen}
                className="relative grid h-10 w-10 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                <Bell className="h-[18px] w-[18px]" aria-hidden />
                {alerts > 0 ? <span className="absolute end-2 top-2 h-2 w-2 rounded-full bg-primary ring-2 ring-background" aria-hidden /> : null}
              </button>
              {bellOpen && (
                <>
                  <button type="button" aria-label={t('close')} onClick={() => setBellOpen(false)} className="fixed inset-0 z-40 cursor-default" />
                  <div className="absolute end-0 z-50 mt-2 w-[min(360px,calc(100vw-24px))] overflow-hidden rounded-xl border border-border bg-card shadow-lg motion-safe:animate-in motion-safe:fade-in motion-safe:slide-in-from-top-1 motion-safe:duration-200">
                    <div className="border-b border-border px-4 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-muted-foreground/70">{t('alerts_label')}</div>
                    {!alertList.length ? (
                      <p className="px-4 py-4 text-[13px] text-muted-foreground">{t('attention_none')}</p>
                    ) : (
                      <ul className="max-h-[60vh] divide-y divide-border overflow-y-auto">
                        {/* Each notification opens what it is about — the request it names —
                            through the same onAlert the Overview's alert cards use. */}
                        {alertList.map((a, i) => (
                          <li key={i}>
                            <button type="button" onClick={() => { setBellOpen(false); if (onAlert) onAlert(a); }}
                              className="flex w-full items-start gap-3 px-4 py-3 text-start transition-colors hover:bg-secondary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring">
                              <span className={cn('mt-1.5 h-2 w-2 shrink-0 rounded-full',
                                a.severity === 'high' ? 'bg-danger' : a.severity === 'medium' ? 'bg-warn' : 'bg-primary')} aria-hidden />
                              <span className="min-w-0 flex-1">
                                <span className="block text-[13px] font-semibold text-foreground">{a.title}</span>
                                {a.detail ? <span className="mt-0.5 block text-[12px] leading-relaxed text-muted-foreground">{a.detail}</span> : null}
                              </span>
                              <ChevronRight className={cn('mt-1 h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
                            </button>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                </>
              )}
            </div>

            {/* Its name is the customer's INITIAL below lg, where the name span is hidden — one
                letter, for a control that opens Account (a11y review, 18 Sep 2026). */}
            <button type="button" onClick={() => go('account')} aria-label={t('mod_account')}
              className="flex min-h-11 shrink-0 items-center gap-2 rounded-xl py-1 ps-1 pe-2 transition-colors hover:bg-secondary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              <span className="grid h-8 w-8 place-items-center rounded-full bg-primary/15 text-[12px] font-bold text-primary">
                {String(customerName || '?').trim().charAt(0).toUpperCase()}
              </span>
              <span dir="auto" className="hidden max-w-[140px] truncate text-start text-[13px] font-semibold text-foreground lg:block">{customerName || ''}</span>
            </button>

            <div className="hidden shrink-0 items-center gap-1 sm:flex">
              {/* h-11 w-11: 44px, the minimum tap target. size="sm" made these 32px (CP-13). */}
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={() => onSetLang(rtl ? 'en' : 'ar')} aria-label={rtl ? 'English' : 'العربية'} title={t('lang_note')}>{rtl ? 'EN' : 'ع'}</Button>
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={onSwapTheme}
                aria-label={theme === 'dark' ? t('theme_light') : t('theme_dark')}>
                {theme === 'dark' ? <Sun className="h-4 w-4" aria-hidden /> : <Moon className="h-4 w-4" aria-hidden />}
              </Button>
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={onSignOut} aria-label={t('signout')}><LogOut className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden /></Button>
            </div>
          </div>
        </header>

        {/* id="main" — the layout's skip link targets #main; without it the first focusable element
            on the signed-in customer portal did nothing (measured 18 Sep 2026). */}
        <main id="main" className="min-w-0 flex-1 pb-[calc(6rem+env(safe-area-inset-bottom))] md:pb-8">{children}</main>
      </div>

      {/* ── MOBILE TAB BAR ────────────────────────────────────────────────────────────────── */}
      {/* Its own name, not the sidebar's. Only one of the two is in the accessibility tree at a
          time (the other is display:none), but two landmarks that answer to "Portal navigation"
          is one CSS regression away from being a real defect (a11y review, 18 Sep 2026). */}
      <nav ref={tabBar} aria-label={t('nav_main_bar')}
        className="fixed inset-x-0 bottom-0 z-30 flex items-stretch border-t border-border bg-card pb-[env(safe-area-inset-bottom)] shadow-e2 md:hidden">
        {mobileItems.map((item) => {
          const Icon = item.icon;
          const active = isActive(item.id);
          return (
            <button key={item.id} type="button" onClick={() => go(item.id)} aria-current={active ? 'page' : undefined}
              className={cn('relative flex min-h-[56px] min-w-0 flex-1 flex-col items-center justify-center gap-1 px-0.5 py-2 text-[11.5px] font-semibold leading-tight transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
                active ? 'text-primary' : 'text-foreground/75')}>
              <Icon className="h-[18px] w-[18px]" aria-hidden />
              {/* Wraps to a second line before it would ever be cut. */}
              <span className="max-w-full break-words text-center">{t(item.label)}</span>
              {/* The dot is decoration; the COUNT is the information, and the sidebar says it out
                  loud (line above). A phone must not tell a screen-reader user less than a desktop
                  does about the same state (a11y review, 18 Sep 2026). */}
              {item.badge === 'unread' && unread > 0 ? <>
                <span className="absolute end-[22%] top-1.5 h-2 w-2 rounded-full bg-primary" aria-hidden />
                <span className="sr-only">{unread}</span>
              </> : null}
              {active ? <span className="absolute inset-x-5 top-0 h-[2px] rounded-full bg-primary" aria-hidden /> : null}
            </button>
          );
        })}
        <button type="button" ref={moreBtn} onClick={() => setMoreOpen((v) => !v)} aria-expanded={moreOpen} aria-controls="qd-nav-more"
          className={cn('flex min-h-[56px] min-w-0 flex-1 flex-col items-center justify-center gap-1 px-0.5 py-2 text-[11.5px] font-semibold leading-tight transition-colors',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
            moreOpen ? 'text-primary' : 'text-foreground/75')}>
          {moreOpen ? <X className="h-[19px] w-[19px]" aria-hidden /> : <Menu className="h-[19px] w-[19px]" aria-hidden />}
          <span>{t('nav_more')}</span>
        </button>
      </nav>

      {moreOpen && (
        <>
          <button type="button" aria-label={t('close')} onClick={() => setMoreOpen(false)}
            className="fixed inset-0 z-30 bg-background/80 md:hidden" />
          {/* THE SHEET GIVES FULL NAMES, one per row: a two-column grid cut "What you may need
              next" at 375px. */}
          <nav id="qd-nav-more" aria-label={t('nav_more_title')}
            className="fixed inset-x-0 bottom-[var(--qd-tabbar-h,0px)] z-40 max-h-[70vh] overflow-y-auto rounded-t-2xl border-t border-border bg-card p-4 motion-safe:animate-in motion-safe:slide-in-from-bottom-6 motion-safe:duration-300 md:hidden">
            {overflowGroups.map((g) => (
              <div key={g.caption} role="group" aria-labelledby={'qd-more-' + g.caption} className="mb-3">
                <div id={'qd-more-' + g.caption} className="px-1 pb-1 text-[12.5px] font-semibold text-muted-foreground">{t(g.caption)}</div>
                <div className="flex flex-col gap-1">
                  {g.items.map((item) => {
                    const Icon = item.icon;
                    const active = isActive(item.id);
                    return (
                      <button key={item.id} type="button" onClick={() => go(item.id)} aria-current={active ? 'page' : undefined}
                        className={cn('flex min-h-11 items-center gap-2.5 rounded-xl border px-3 py-2 text-start text-[14px] font-medium',
                          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                          active ? 'border-primary/40 bg-primary/12 text-primary' : 'border-border bg-secondary/25 text-foreground')}>
                        <Icon className="h-4 w-4 shrink-0 opacity-70" aria-hidden />
                        <span className="min-w-0 flex-1 break-words leading-snug">{t(item.label)}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="mt-1 flex items-center gap-2 border-t border-border pt-3">
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={() => onSetLang(rtl ? 'en' : 'ar')}>{rtl ? 'English' : 'العربية'}</Button>
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={onSwapTheme}>{theme === 'dark' ? t('theme_light') : t('theme_dark')}</Button>
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={onSignOut}>{t('signout')}</Button>
            </div>
            <p className="pt-1 text-[11.5px] leading-snug text-muted-foreground">{t('lang_note')}</p>
          </nav>
        </>
      )}

      <AssistantPanel token={token} lang={lang} open={asstOpen} seed={seed} t={t} suggestions={suggestions}
        onClose={() => { setAsstOpen(false); setSeed(''); }} />
    </div>
  );
}
