'use client';
// DocActions — the four actions every document offers: View / Download / Replace / Remove, in that
// order, same words EN + AR, desktop and phone (founder instruction 524, 21 Sep 2026). One component,
// so the supplier's Documents tab, the supporting documents, the inquiries a supplier receives, the
// customer's drawing and the revealed quotation, and every receipt render the SAME row and cannot
// drift into five vocabularies. The words and the sealed reasons live in ./documentActions.ts.
//
//   url / getUrl   View opens it in a new tab (through openDocument, so the tab is opened inside the
//                  click and never dropped as a popup); Download opens the same signed URL with the
//                  attachment parameter, so the browser saves it under its name.
//   onReplace      called with the chosen File. Absent AND not sealed: the button still shows and says
//                  so when pressed — a document is never shown with fewer than four actions.
//   onRemove       two-step (Remove → Confirm remove / Cancel). Returns {ok, message?}; a refusal from
//                  the server is shown as its sentence.
//   sealed         a SealedCode: Replace and Remove show the reason instead of acting.
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { openDocument } from '@/lib/openDocument';
import { downloadUrl, sealedReason, word, type Lang, type SealedCode } from './documentActions';

export type DocActionsProps = {
  lang: Lang;
  name?: string | null;
  url?: string | null;
  getUrl?: () => Promise<string | null>;
  onReplace?: (file: File) => Promise<unknown> | unknown;
  onRemove?: () => Promise<{ ok?: boolean; message?: string } | void | null> | void;
  sealed?: SealedCode | null;
  accept?: string;
  versions?: number;
  className?: string;
  /** For a document held as inline content (a BOQ CSV, say) rather than a URL: View and Download run these instead. */
  onView?: () => void;
  onDownload?: () => void;
};

const ACCEPT = 'application/pdf,image/*,.doc,.docx,.xls,.xlsx,.ppt,.pptx';

export default function DocActions({ lang, name, url, getUrl, onReplace, onRemove, sealed, accept = ACCEPT, versions = 0, className = '', onView, onDownload }: DocActionsProps) {
  const [busy, setBusy] = useState<'' | 'view' | 'download' | 'replace' | 'remove'>('');
  const [confirm, setConfirm] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const ar = lang === 'ar';
  const w = (k: Parameters<typeof word>[1]) => word(lang, k);
  const resolve = async (): Promise<string | null> => url || (getUrl ? await getUrl() : null);
  const notReplaceable = ar ? 'لا يمكن استبدال هذا الملف من هنا.' : 'This file cannot be replaced from here.';
  const notRemovable = ar ? 'لا يمكن إزالة هذا الملف من هنا.' : 'This file cannot be removed from here.';

  const view = async () => {
    if (onView) { setMsg(null); onView(); return; }
    setBusy('view'); setMsg(null);
    const ok = await openDocument(lang, resolve);
    if (!live.current) return;
    setBusy(''); if (!ok) setMsg(w('open_failed'));
  };
  const download = async () => {
    if (onDownload) { setMsg(null); onDownload(); return; }
    setBusy('download'); setMsg(null);
    const ok = await openDocument(lang, async () => downloadUrl(await resolve(), name));
    if (!live.current) return;
    setBusy(''); if (!ok) setMsg(w('open_failed'));
  };
  const replace = async (file: File) => {
    setBusy('replace'); setMsg(null);
    try { await onReplace?.(file); } catch (e) { if (live.current) setMsg(String((e as Error)?.message || e)); }
    if (live.current) setBusy('');
  };
  const remove = async () => {
    setBusy('remove'); setMsg(null);
    let r: { ok?: boolean; message?: string } | void | null = null;
    try { r = await onRemove?.(); } catch (e) { r = { ok: false, message: String((e as Error)?.message || e) }; }
    if (!live.current) return;
    setBusy(''); setConfirm(false);
    if (r && r.ok === false) setMsg(r.message || (ar ? 'تعذّرت الإزالة.' : 'Could not remove.'));
  };
  const reason = sealedReason(lang, sealed);
  const hasFile = !!(url || getUrl || onView || onDownload);
  const btn = 'min-h-11';

  return (
    <div className={'flex flex-col gap-1.5 ' + className}>
      <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label={ar ? 'إجراءات المستند' : 'Document actions'}>
        <Button type="button" size="sm" variant="outline" className={btn} disabled={!hasFile || !!busy} aria-busy={busy === 'view' || undefined} onClick={view}>{busy === 'view' ? w('working') : w('view')}</Button>
        <Button type="button" size="sm" variant="outline" className={btn} disabled={!hasFile || !!busy} aria-busy={busy === 'download' || undefined} onClick={download}>{busy === 'download' ? w('working') : w('download')}</Button>
        {reason || !onReplace
          ? <Button type="button" size="sm" variant="outline" className={btn} aria-disabled="true" onClick={() => setMsg(reason || notReplaceable)}>{w('replace')}</Button>
          : <label className={'inline-flex cursor-pointer items-center rounded-md border border-border px-3 text-[13px] font-medium text-foreground focus-within:ring-2 focus-within:ring-ring hover:bg-muted ' + btn}>
              {busy === 'replace' ? w('working') : w('replace')}
              <input type="file" accept={accept} className="sr-only" disabled={!!busy} aria-label={w('replace') + (name ? ' — ' + name : '')}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) replace(f); e.target.value = ''; }} />
            </label>}
        {reason || !onRemove
          ? <Button type="button" size="sm" variant="ghost" className={btn} aria-disabled="true" onClick={() => setMsg(reason || notRemovable)}>{w('remove')}</Button>
          : confirm
            ? <>
                <Button type="button" size="sm" variant="destructive" className={btn} disabled={!!busy} aria-busy={busy === 'remove' || undefined} onClick={remove}>{busy === 'remove' ? w('working') : w('confirm')}</Button>
                <Button type="button" size="sm" variant="ghost" className={btn} disabled={!!busy} onClick={() => setConfirm(false)}>{w('cancel')}</Button>
              </>
            : <Button type="button" size="sm" variant="ghost" className={btn} disabled={!hasFile || !!busy} onClick={() => { setMsg(null); setConfirm(true); }}>{w('remove')}</Button>}
        {versions > 0 && <span className="text-[11.5px] text-muted-foreground"><bdi dir="ltr">{versions}</bdi> · {w('kept')}</span>}
      </div>
      {msg && <p role="alert" className="text-[12.5px] text-danger-fg">{msg}</p>}
    </div>
  );
}
