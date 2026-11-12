'use client';
// "Your data" on both portals' account pages (sales_engineer with it_engineer, 7 Oct 2026). The routines
// pdpl_request_me / pdpl_confirm_me / pdpl_cancel_me (#1237) existed and privacy policy 1.6 promises
// self-service, but nothing a signed-in person could press called them. Contract and copy: ./privacy.ts.
// Suppliers render with lang="en" only (standing rule: suppliers are English on every channel).
import { useEffect, useId, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { supaRpcAs } from '@/lib/supaClient';
import { type Lang, type Pending, STORE_KEY, pt, ptList, fmtDate, errorText, keptLines, pendingFrom, livePending, pendingFromStatus, isCode } from './privacy';

type Rpc = (fn: string, args: Record<string, unknown>) => Promise<Record<string, any> | null>;

const store = {
  get: () => { try { return localStorage.getItem(STORE_KEY); } catch { return null; } },
  set: (p: Pending | null) => { try { if (p) localStorage.setItem(STORE_KEY, JSON.stringify(p)); else localStorage.removeItem(STORE_KEY); } catch { /* private window */ } },
};

function download(data: unknown) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `quotesdone-my-data-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

const Msg = ({ m, err }: { m: string; err: boolean }) => m
  ? <p role={err ? 'alert' : 'status'} className={err ? 'text-[12.5px] text-danger-fg' : 'text-[12.5px] text-muted-foreground'}>{m}</p>
  : null;

// `token` is the calling portal's own access token (customer: qd-cust-token, supplier: qd-sup-token), never a
// shared storage key: a fixed key ran a customer's request as the supplier session (review of #1273).
export function PrivacyControls({ token, lang = 'en', rpc: rpcIn }: { token?: string | null; lang?: Lang; rpc?: Rpc }) {
  const rpc: Rpc = rpcIn ?? ((fn, args) => supaRpcAs(token || '', fn, args));
  const ids = useId();
  const [busy, setBusy] = useState('');
  const [exp, setExp] = useState({ m: '', err: false });
  const [ack, setAck] = useState(false);
  const [req, setReq] = useState<{ id: string; email: string } | null>(null);
  const [code, setCode] = useState('');
  const [pending, setPending] = useState<Pending | null>(null);
  const [del, setDel] = useState({ m: '', err: false });
  const codeRef = useRef<HTMLInputElement>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);

  // The server's answer wins (any device); the browser's memory is only the fallback if the routine cannot answer.
  useEffect(() => {
    setPending(livePending(store.get()));
    if (!token) return;
    let live = true;
    rpc('pdpl_status_me', {}).then((j) => { const p = pendingFromStatus(j); if (live && p !== undefined) { store.set(p); setPending(p); } }).catch(() => {});
    return () => { live = false; };
  }, [token]); // oxlint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (req) codeRef.current?.focus(); }, [req]);

  const run = async (k: string, f: () => Promise<void>) => {
    setBusy(k);
    try { await f(); } catch { (k === 'exp' ? setExp : setDel)({ m: pt(lang, 'e_generic'), err: true }); }
    setBusy('');
  };

  const doExport = () => run('exp', async () => {
    setExp({ m: '', err: false });
    const j = await rpc('pdpl_request_me', { p_kind: 'export' });
    if (j?.ok && j.export) { download(j.export); setExp({ m: pt(lang, 'exp_done'), err: false }); }
    else setExp({ m: errorText(lang, j), err: true });
  });
  const askCode = () => run('ask', async () => {
    setDel({ m: '', err: false });
    const j = await rpc('pdpl_request_me', { p_kind: 'delete' });
    if (j?.ok && j.request_id) { setCode(''); setReq({ id: String(j.request_id), email: String(j.code_sent_to || '') }); }
    else setDel({ m: errorText(lang, j), err: true });
  });
  const confirm = () => run('confirm', async () => {
    if (!req || !isCode(code)) return;
    const j = await rpc('pdpl_confirm_me', { p_request: req.id, p_code: code.trim() });
    const p = pendingFrom(req.id, j);
    if (p) { store.set(p); setPending(p); setReq(null); setDel({ m: '', err: false }); setTimeout(() => cancelRef.current?.focus(), 0); }
    else {
      setDel({ m: errorText(lang, j), err: true });
      if (j && /spent|no open request/.test(String(j.error || ''))) setReq(null);
    }
  });
  const cancel = () => run('cancel', async () => {
    if (!pending) return;
    const j = await rpc('pdpl_cancel_me', { p_request: pending.id });
    if (j?.ok) { store.set(null); setPending(null); setAck(false); setDel({ m: pt(lang, 'cancelled'), err: false }); }
    else { setDel({ m: errorText(lang, j), err: true }); if (/cooling-off window/.test(String(j?.error || ''))) { store.set(null); setPending(null); } }
  });

  return (
    <section aria-labelledby={ids + 'h'} className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <div>
        <h3 id={ids + 'h'} className="text-[15px] font-semibold text-foreground">{pt(lang, 'h')}</h3>
        <p className="text-[12.5px] text-muted-foreground">{pt(lang, 'sub')}</p>
        {/* Inside the portals the only legal link was the terms at sign-up (website audit 10 Nov 2026). */}
        <a href={lang === 'ar' ? '/ar/privacy' : '/privacy'} target="_blank" rel="noopener" className="inline-flex min-h-11 items-center text-[12.5px] font-semibold text-primary underline underline-offset-2">{pt(lang, 'policy')}</a>
      </div>

      <Card className="flex flex-col gap-2 p-4">
        <h4 className="text-[13.5px] font-semibold text-foreground">{pt(lang, 'exp_h')}</h4>
        <p className="text-[12.5px] text-muted-foreground">{pt(lang, 'exp_p')}</p>
        <div><Button size="sm" variant="outline" className="min-h-11" data-testid="privacy-export" disabled={!!busy} aria-busy={busy === 'exp'} onClick={doExport}>
          {busy === 'exp' ? pt(lang, 'exp_busy') : pt(lang, 'exp_btn')}
        </Button></div>
        <Msg {...exp} />
      </Card>

      <Card className="flex flex-col gap-2.5 p-4 border-danger/30">
        <h4 className="text-[13.5px] font-semibold text-foreground">{pt(lang, 'del_h')}</h4>
        {pending ? (
          <div className="flex flex-col gap-2.5" data-testid="privacy-erase-scheduled">
            <p role="status" className="text-[13px] font-medium text-foreground">{pt(lang, 'sched', { date: fmtDate(lang, pending.confirm_after) })}</p>
            {pending.deferred.length ? <div>
              <div className="text-[12.5px] font-semibold text-foreground">{pt(lang, 'kept_h')}</div>
              <ul className="mt-1 list-disc ps-5 text-[12.5px] text-muted-foreground">{keptLines(lang, pending.deferred).map((l, i) => <li key={i}>{l}</li>)}</ul>
            </div> : null}
            <div><Button ref={cancelRef} size="sm" className="min-h-11" data-testid="privacy-erase-cancel" disabled={!!busy} onClick={cancel}>
              {busy === 'cancel' ? pt(lang, 'cancel_busy') : pt(lang, 'cancel_btn')}
            </Button></div>
          </div>
        ) : (<>
          {/* READABLE BEFORE HE DECIDES (walk of 12 Nov 2026, S2): muted 12.5 px grey on the muted panel measured 2.6:1 (pixel-sampled);
              the warning is now the page's own text colour at 14 px, which is the body contrast (well over 4.5:1) in both themes. */}
          <div className="rounded-md border border-border p-3" data-testid="privacy-erase-warning">
            <div className="text-[14px] font-semibold text-foreground">{pt(lang, 'del_warn_h')}</div>
            <ul className="mt-1 list-disc ps-5 text-[14px] leading-snug text-foreground">{ptList(lang, 'del_warn').map((l) => <li key={l}>{l}</li>)}</ul>
          </div>
          {!req ? <>
            <label className="flex min-h-11 items-center gap-2 text-[12.5px] text-foreground">
              <input type="checkbox" data-testid="privacy-erase-ack" checked={ack} onChange={(e) => setAck(e.target.checked)} />
              {pt(lang, 'del_ack')}
            </label>
            <div><Button size="sm" variant="destructive" className="min-h-11" data-testid="privacy-erase" disabled={!ack || !!busy} onClick={askCode}>
              {busy === 'ask' ? pt(lang, 'del_busy') : pt(lang, 'del_btn')}
            </Button></div>
          </> : (
            <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); confirm(); }}>
              <p role="status" className="text-[12.5px] text-muted-foreground">{pt(lang, 'code_sent', { email: '⁨' + req.email + '⁩' })}</p>
              <label htmlFor={ids + 'c'} className="text-[12.5px] font-medium text-foreground">{pt(lang, 'code_label')}</label>
              <div className="flex flex-wrap gap-2">
                <Input id={ids + 'c'} ref={codeRef} data-testid="privacy-code" className="h-11 w-40" dir="ltr" inputMode="numeric" autoComplete="one-time-code"
                  maxLength={6} pattern="\d{6}" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} />
                <Button type="submit" size="sm" variant="destructive" className="min-h-11" data-testid="privacy-erase-confirm" disabled={!isCode(code) || !!busy}>
                  {busy === 'confirm' ? pt(lang, 'confirm_busy') : pt(lang, 'confirm_btn')}
                </Button>
                {/* A WAY BACK FROM THE CODE STEP (walk of 12 Nov 2026, S1): only "Confirm deletion" was offered once the code was sent.
                    Nothing is erased without the code, so going back only closes this step; the e-mailed code lapses in 24 hours. */}
                <Button type="button" size="sm" variant="outline" className="min-h-11" data-testid="privacy-erase-back" disabled={busy === 'confirm'}
                  onClick={() => { setReq(null); setCode(''); setAck(false); setDel({ m: pt(lang, 'cancelled'), err: false }); }}>
                  {pt(lang, 'cancel_btn')}
                </Button>
              </div>
            </form>
          )}
        </>)}
        <Msg {...del} />
      </Card>
    </section>
  );
}

export default PrivacyControls;
