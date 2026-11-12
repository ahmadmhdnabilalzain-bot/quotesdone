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
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';
import { type Lang, type Pending, STORE_KEY, pt, ptList, fmtDate, errorText, keptLines, pendingFrom, livePending, pendingFromStatus, isCode, pdfName, jsonFileText, JSON_TYPE, isAppleTouch } from './privacy';

type Rpc = (fn: string, args: Record<string, unknown>) => Promise<Record<string, any> | null>;
// The PDF copy (12 Nov 2026, founder ledgers 1669 and 1671): my_data_pdf draws it in the document template from the
// person's own export. Injected in tests; in the portal it is the edge function, called with this portal's token.
type PdfFetch = (args: { lang: Lang; role: Role }) => Promise<Response>;
type Role = 'customer' | 'supplier';

const store = {
  get: () => { try { return localStorage.getItem(STORE_KEY); } catch { return null; } },
  set: (p: Pending | null) => { try { if (p) localStorage.setItem(STORE_KEY, JSON.stringify(p)); else localStorage.removeItem(STORE_KEY); } catch { /* private window */ } },
};

// Save a file the browser holds (desktop and Android). The object URL is NOT revoked a second later any more: a viewer
// opened from it needs it while it is shown, so each file's URL lives until the next file of the same kind replaces it
// (`keep` revokes the previous one), sign-out, or leaving the page (the effects below), and it never appears in the
// address bar of the portal itself.
function save(url: string, name: string) {
  const a = document.createElement('a');
  a.href = url; a.download = name; a.rel = 'noopener';
  document.body.appendChild(a); a.click(); a.remove();
}

const Msg = ({ m, err }: { m: string; err: boolean }) => m
  ? <p role={err ? 'alert' : 'status'} className={err ? 'text-[12.5px] text-danger-fg' : 'text-[12.5px] text-muted-foreground'}>{m}</p>
  : null;

// `token` is the calling portal's own access token (customer: qd-cust-token, supplier: qd-sup-token), never a
// shared storage key: a fixed key ran a customer's request as the supplier session (review of #1273).
export function PrivacyControls({ token, lang = 'en', party: role = 'customer', rpc: rpcIn, pdf: pdfIn }: { token?: string | null; lang?: Lang; party?: Role; rpc?: Rpc; pdf?: PdfFetch }) {
  const rpc: Rpc = rpcIn ?? ((fn, args) => supaRpcAs(token || '', fn, args));
  const pdf: PdfFetch = pdfIn ?? ((args) => fetch(fnUrl('my_data_pdf'), { method: 'POST', cache: 'no-store',
    headers: { apikey: SUPA_ANON, Authorization: `Bearer ${token || ''}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args) }));
  const ids = useId();
  const [busy, setBusy] = useState('');
  const [exp, setExp] = useState({ m: '', err: false });
  const [json, setJson] = useState({ m: '', err: false });
  // The finished files, held only in this tab's memory as object URLs; cleared on sign-out (token gone) and unmount.
  const [file, setFile] = useState<{ url: string; name: string } | null>(null);
  const fileRef = useRef<string[]>([]);
  const kindRef = useRef<Record<string, string>>({});
  const keep = (kind: 'pdf' | 'json', url: string) => {
    const prev = kindRef.current[kind];
    if (prev) { URL.revokeObjectURL(prev); fileRef.current = fileRef.current.filter((u) => u !== prev); }
    kindRef.current[kind] = url; fileRef.current.push(url); return url;
  };
  // THE IPHONE (review of #1986). iOS Safari does not reliably start a download from a click the code makes after an
  // await (it is no longer the person's own gesture), and in-app browsers ignore `download` altogether. So on an
  // iPhone or iPad nothing is clicked for him: "Open your PDF" appears, focused, and HIS tap opens the PDF in this tab
  // in Safari's own viewer (Share: Save to Files, Print), with no `download` and no new tab (a blob opened in a new
  // tab is what a pop-up blocker stops). Back returns to the portal; the blob dies with the page, so the history entry
  // opens nothing for the next person who picks up the phone.
  const [apple, setApple] = useState(false);
  useEffect(() => { setApple(isAppleTouch(navigator.userAgent, navigator.maxTouchPoints || 0)); }, []);
  useEffect(() => () => { fileRef.current.forEach((u) => URL.revokeObjectURL(u)); fileRef.current = []; }, []);
  useEffect(() => { if (!token) { fileRef.current.forEach((u) => URL.revokeObjectURL(u)); fileRef.current = []; setFile(null); setExp({ m: '', err: false }); setJson({ m: '', err: false }); } }, [token]);
  const openRef = useRef<HTMLAnchorElement>(null);
  // Focus goes to "Open your PDF" when the file is ready (the button it replaces as the next step); the status line
  // beside it is announced. An error keeps focus on the button, which now reads "Try again".
  useEffect(() => { if (file) openRef.current?.focus(); }, [file]);
  const expBtnRef = useRef<HTMLButtonElement>(null);
  // A disabled button drops focus to the page; after a failure it is given back, so Enter retries at once.
  useEffect(() => { if (exp.err && !busy) expBtnRef.current?.focus(); }, [exp.err, busy]);
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
    try { await f(); } catch { (k === 'exp' ? setExp : k === 'json' ? setJson : setDel)({ m: pt(lang, 'e_generic'), err: true }); }
    setBusy('');
  };

  const doExport = () => run('exp', async () => {
    setExp({ m: '', err: false }); setFile(null);
    const r = await pdf({ lang, role });
    if (r.ok && /application\/pdf/.test(r.headers.get('Content-Type') || '')) {
      const blob = await r.blob();
      const url = keep('pdf', URL.createObjectURL(new Blob([blob], { type: 'application/pdf' })));
      const name = pdfName(r.headers.get('Content-Disposition'));
      setFile({ url, name }); if (!apple) save(url, name);
      setExp({ m: pt(lang, apple ? 'exp_tap' : 'exp_done'), err: false });
    } else {
      const j = await r.json().catch(() => null);
      setExp({ m: errorText(lang, j), err: true });
    }
  });
  const doJson = () => run('json', async () => {
    setJson({ m: '', err: false });
    const j = await rpc('pdpl_request_me', { p_kind: 'export' });
    if (j?.ok && j.export) {
      const url = keep('json', URL.createObjectURL(new Blob([jsonFileText(j.export)], { type: JSON_TYPE })));
      save(url, pdfName(null).replace(/\.pdf$/, '.json'));
      setJson({ m: pt(lang, 'json_done'), err: false });
    } else setJson({ m: errorText(lang, j), err: true });
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
        <div><Button ref={expBtnRef} size="sm" variant="outline" className="min-h-11" data-testid="privacy-export" disabled={!!busy} aria-busy={busy === 'exp'} onClick={doExport}>
          {busy === 'exp' ? <><span aria-hidden="true" className="inline-block size-3.5 animate-spin rounded-full border-2 border-current border-e-transparent" />{pt(lang, 'exp_busy')}</> : exp.err ? pt(lang, 'exp_retry') : pt(lang, 'exp_btn')}
        </Button></div>
        {/* The answer's place is held from the start (44px, one line of text and the link beside it), so nothing on
            the page moves when it arrives: layout shift measured 0 on the iPhone, Android and desktop proofs. */}
        <div className="flex min-h-11 flex-wrap items-center gap-x-3" data-testid="privacy-export-result">
          <Msg {...exp} />
          {file && !exp.err ? <a ref={openRef} href={file.url} download={apple ? undefined : file.name} data-testid="privacy-export-open"
            className="inline-flex min-h-11 items-center text-[13px] font-semibold text-primary underline underline-offset-2">{pt(lang, 'exp_open')}</a> : null}
        </div>
        <div className="border-t border-border pt-2.5">
          <p className="text-[12px] text-muted-foreground">{pt(lang, 'json_p')}</p>
          <Button size="sm" variant="ghost" className="min-h-11 px-0 text-[12.5px] font-semibold text-primary underline underline-offset-2 hover:bg-transparent" data-testid="privacy-export-json" disabled={!!busy} aria-busy={busy === 'json'} onClick={doJson}>
            {busy === 'json' ? pt(lang, 'json_busy') : pt(lang, 'json_btn')}
          </Button>
          <div className="min-h-5"><Msg {...json} /></div>
        </div>
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
          <div className="rounded-md bg-muted/50 p-3">
            <div className="text-[12.5px] font-semibold text-foreground">{pt(lang, 'del_warn_h')}</div>
            <ul className="mt-1 list-disc ps-5 text-[12.5px] text-muted-foreground">{ptList(lang, 'del_warn').map((l) => <li key={l}>{l}</li>)}</ul>
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
