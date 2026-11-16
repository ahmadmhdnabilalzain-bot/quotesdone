// @ts-nocheck
'use client';
import { photoToDataUrl } from '@/lib/chatPhoto';
import { useEffect, useRef, useState } from 'react';
import { Sparkles, Search, X, ChevronRight, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { render } from '@/lib/chatRender';
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';
import { forgetWidgetConv, readWidgetConv } from '@/lib/widgetConv';
import { take } from '../prefetch';
import { lookForStoredAnswer, lookForStoredQuestion, answerRightAfter, noVerdict, pendingDue, readReply, savedLineDue, waitingOf, PENDING_EVERY_MS, PENDING_FOR_MS } from '@/lib/portalReply';
import { stillWorking } from '@/lib/stillWorking';

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
export const widgetConv = () => readWidgetConv();
// THE ANSWER STREAMS (27 Oct 2026, customer_support): a status line at once, then each checked sentence as it is
// written (src/lib/portalReply.ts). Measured before: every turn waited 58-150 s in silence and one hit the edge's 150 s
// wall as a 504, whose HTML body made r.json() throw and the panel print its error line. A server that does not stream
// answers JSON, read the same way; nothing here throws.
export async function askAssistant(message, history, token, lang, path, images = [], on = {}) {
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
export const LATE_WAIT_MS = 90_000;
export const LATE_EVERY_MS = 6_000;
export async function storedAnswer(token, question) {
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
    const ask = () => fetch(fnUrl('sales_engineer'), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
      body: JSON.stringify({ action: 'assist_history', ...(wc ? { widget_conv: wc, adopt: true } : {}) }) }).then((r) => (r.ok ? r.json() : null));
    // A plain read takes the one BootPrefetch / warmDashboard already started (prefetch.ts take: once, same token only);
    // an adopt is always asked here, because it is a write and was never prefetched.
    (wc ? ask() : take(token, 'assist', ask))
      // the widget id is cleared only once the server answered and nothing is left to adopt (moved now, or already moved)
      .then((j) => {
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
    // ruling 1636: past STILL_WORKING_MS with no word of the answer (or on the server's keep-alive), the panel says it is still working
    const sw = stillWorking(setStatus, t('asst_still'));
    const j = await askAssistant(q, history, token, lang, '/me', images, { status: sw.status, text: setLive, working: sw.working });
    sw.stop();
    let reply = j.reply;
    // only an answer that never ARRIVED is looked for; a turn the server answered with no reply has nothing stored
    if (!reply && token && noVerdict(j)) {
      setLive(''); setStatus(t('asst_late'));
      reply = await storedAnswer(token, q);
    }
    setLive(''); setStatus('');
    // "SAVED" IS SAID ONLY OF A QUESTION THAT IS SAVED (browser proof, 2 Nov 2026: an Arabic turn failed before the server logged it
    // and the panel still said "your question is saved"; after a reload it was gone). The stored conversation is asked; a question
    // that is not in it is given back to the box with the plain truth.
    let stored = true;
    if (!reply && token && !pendingDue(j) && savedLineDue(j, reply)) {
      stored = await lookForStoredQuestion(async () => {
        const r = await fetch(fnUrl('sales_engineer'), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
          body: JSON.stringify({ action: 'assist_history' }) });
        const x = r.ok ? await r.json() : null;
        return x && x.turns;
      }, q);
      if (!stored) setVal(q);
    }
    // the saved line only on a transport failure or when OpenRouter was down (1339, savedLineDue); with the model up and
    // nothing sendable, no code-written text is shown
    // a turn filed for the re-ask (model up, every draft refused): the pending state, then the model's answer (never silence)
    setMsgs((m) => reply
      ? [...m, { role: 'assistant', content: reply, scope: j.done && j.done.scope }]
      // an outage turn is filed too (16 Nov 2026): it says the answer will come here, never "send it again"
      : pendingDue(j) ? [...m, { role: 'pending', q, content: t(j.done && j.done.outage ? 'asst_queued' : 'asst_working') }]
      : savedLineDue(j, reply) ? [...m, { role: 'notice', content: t(stored ? 'asst_saved' : 'asst_not_sent') }] : m);
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
      // oxlint-disable-next-line jsx-a11y/no-redundant-roles -- explicit landmark role kept on purpose, removing it would change the markup
      role="complementary"
      aria-label={t('asst_title')}
      className={cn(
        // THE MOBILE TAB BAR STAYS TAPPABLE (E2E stage 1, D7, 30 Sep 2026): below md the panel stops above the
        // 56px tab bar instead of covering it (inset-y-0 put it over the menu; 18 nav taps timed out at 375px).
        'fixed top-0 bottom-(--qd-tabbar-h,0px) md:bottom-0 z-40 flex w-full flex-col border-border bg-card shadow-e3',
        // max-w, not w: a fixed 420px panel is 45px wider than a 375px viewport and cannot shrink.
        'inset-e-0 sm:w-full sm:max-w-[420px] sm:border-s',
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
          className="h-11 min-w-0 flex-1 rounded-xl border border-input bg-background px-3.5 text-[13.5px] text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring" />
        <Button type="submit" size="sm" className="h-11 px-3.5" disabled={busy || (!val.trim() && !photo)} aria-label={t('asst_send')}>
          <Send className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden />
        </Button>
      </form>
    </aside>
  );
}
