'use client';
// SUPPORTING COMPANY DOCUMENTS — free upload beside the required ones (15 Sep 2026, sales_engineer).
//
// Every rule is on the server (supplier_portal supporting_* — see supabase/functions/supplier_portal/
// supporting_documents.ts): ownership, the type list, the 30-document and 25 MB limits, the malware scan,
// where the file is stored and how it reaches Dropbox. This renders the list and sends the four requests
// (list, save = upload / replace, delete, url = download) a mobile client sends the same way.
import { useEffect, useRef, useState } from 'react';
// (useRef also carries the mounted flag below.)
import { FileText, Upload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import DocActions from '../DocActions';
import { call } from './api';
import { ws } from './workspaceCopy';

type Lang = 'en' | 'ar' | string;
type Doc = { id: number; label: string; type: string; file_name: string; uploaded_at: string; url: string | null };
type List = { ok: boolean; documents: Doc[]; types: string[]; limits: { max_documents: number; max_bytes: number } };

const toB64 = (f: File) => new Promise<string>((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1] || ''); r.onerror = () => rej(r.error); r.readAsDataURL(f); });
const errText = (lang: Lang, j: any, max: number) => ws(lang, 'sd_err_' + (['label_required', 'file_required', 'too_large', 'file_refused', 'limit_reached'].includes(j?.error) ? j.error : 'generic'), { max });
const ACCEPT = 'application/pdf,image/*,.doc,.docx,.xls,.xlsx,.ppt,.pptx';

export default function SupplierSupportingDocuments({ token, lang }: { token: string; lang: Lang }) {
  const [list, setList] = useState<List | null>(null);
  const [label, setLabel] = useState(''); const [type, setType] = useState('certificate'); const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState<string>(''); const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const max = list?.limits.max_documents ?? 30;
  // A tab switch unmounts this; an answer arriving afterwards must not write state.
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const load = () => call('supplier_portal', { action: 'supporting_documents' }, token).then((j) => { if (live.current) setList(j && j.ok ? j : { ok: false, documents: [], types: [], limits: { max_documents: 30, max_bytes: 26214400 } }); });
  useEffect(() => { load(); }, [token]);

  const save = async (req: Record<string, unknown>, f: File | null, key: string) => {
    setBusy(key); setNote(null);
    if (f && list && f.size > list.limits.max_bytes) { setBusy(''); setNote({ ok: false, text: ws(lang, 'sd_err_too_large') }); return false; }
    const b64 = f ? await toB64(f).catch(() => '') : '';
    const j = await call('supplier_portal', { action: 'supporting_document_save', ...req, ...(f ? { original_b64: b64, filename: f.name, mime: f.type } : {}) }, token).catch(() => null);
    if (!live.current) return false;
    setBusy('');
    if (j && j.ok) { setNote({ ok: true, text: ws(lang, 'sd_saved') }); load(); return true; }
    setNote({ ok: false, text: errText(lang, j, max) }); return false;
  };
  const add = async () => {
    if (!label.trim()) return setNote({ ok: false, text: ws(lang, 'sd_err_label_required') });
    if (!file) return setNote({ ok: false, text: ws(lang, 'sd_err_file_required') });
    if (await save({ label, type }, file, 'new')) { setLabel(''); setFile(null); if (fileRef.current) fileRef.current.value = ''; }
  };
  const remove = async (id: number) => {
    setBusy('rm' + id); setNote(null);
    const j = await call('supplier_portal', { action: 'supporting_document_delete', id }, token).catch(() => null);
    if (!live.current) return { ok: false as const };
    setBusy('');
    setNote(j && j.ok ? { ok: true, text: ws(lang, 'sd_removed') } : { ok: false, text: errText(lang, j, max) }); load();
    return { ok: !!(j && j.ok), message: j && j.ok ? undefined : errText(lang, j, max) };
  };
  // A fresh URL each time: the one in the list expires after an hour. That round trip said nothing
  // (18 Sep 2026) — the press looked ignored until the tab opened — so it takes the same keyed `busy`
  // the replace and remove buttons already use.
  const freshUrl = async (id: number): Promise<string | null> => {
    const j = await call('supplier_portal', { action: 'supporting_document_url', id }, token).catch(() => null);
    return j && j.ok && j.url ? String(j.url) : null;
  };
  const docs = list?.documents || [];
  const types = list?.types?.length ? list.types : ['certificate', 'other'];
  const full = docs.length >= max;

  return (
    <section aria-labelledby="qd-sd-h" className="qd-panel p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 id="qd-sd-h" className="text-[15.5px] font-bold text-foreground">{ws(lang, 'sd_title')}</h2>
          <p className="mt-1 max-w-[68ch] text-[13px] leading-[1.65] text-muted-foreground">{ws(lang, 'sd_sub')}</p>
        </div>
        {list && <span className="font-mono text-[12px] text-muted-foreground"><bdi dir="ltr">{ws(lang, 'sd_count', { n: docs.length, max })}</bdi></span>}
      </div>

      <form className="mt-4 grid gap-3 rounded-md border border-border p-3.5 sm:grid-cols-[1.4fr_1fr_1.2fr_auto] sm:items-end" onSubmit={(e) => { e.preventDefault(); add(); }}>
        <label className="flex min-w-0 flex-col gap-1.5 text-[12.5px] font-semibold text-muted-foreground">{ws(lang, 'sd_label')}
          <Input dir="auto" maxLength={120} value={label} placeholder={ws(lang, 'sd_label_ph')} onChange={(e) => setLabel(e.target.value)} disabled={full} />
        </label>
        <label className="flex min-w-0 flex-col gap-1.5 text-[12.5px] font-semibold text-muted-foreground">{ws(lang, 'sd_type')}
          <select value={type} onChange={(e) => setType(e.target.value)} disabled={full}
            className="h-10 rounded-md border border-input bg-background px-2.5 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            {types.map((t) => <option key={t} value={t}>{ws(lang, 'sd_t_' + t)}</option>)}
          </select>
        </label>
        <label className="flex min-w-0 flex-col gap-1.5 text-[12.5px] font-semibold text-muted-foreground">{ws(lang, 'sd_file')}
          <input ref={fileRef} type="file" accept={ACCEPT} disabled={full} onChange={(e) => setFile(e.target.files?.[0] || null)}
            className="min-h-10 text-sm text-muted-foreground file:me-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-secondary-foreground" />
        </label>
        <Button type="submit" className="min-h-11" disabled={full || busy === 'new'}><Upload aria-hidden className="h-4 w-4" />{busy === 'new' ? ws(lang, 'sd_uploading') : ws(lang, 'sd_add')}</Button>
        <p className="text-[11.5px] text-muted-foreground sm:col-span-4">{full ? ws(lang, 'sd_err_limit_reached', { max }) : ws(lang, 'sd_limits')}</p>
      </form>
      {note && <p role={note.ok ? 'status' : 'alert'} className={note.ok ? 'mt-3 text-[13px] text-ok-fg' : 'mt-3 text-[13px] text-danger-fg'}>{note.text}</p>}

      {!list ? <p className="mt-4 text-[13px] text-muted-foreground" aria-busy="true">…</p>
        : !docs.length ? <p className="mt-4 text-[13px] text-muted-foreground">{ws(lang, 'sd_empty')}</p>
        : <ul className="mt-4 flex flex-col gap-2.5">
          {docs.map((d) => (
            <li key={d.id} className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border px-3.5 py-3">
              <div className="flex min-w-0 items-start gap-3">
                <FileText aria-hidden className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2"><b dir="auto" className="text-[13.5px] text-foreground">{d.label}</b><Badge variant="secondary">{ws(lang, 'sd_t_' + d.type)}</Badge></div>
                  <div className="mt-0.5 text-[12px] text-muted-foreground"><bdi>{d.file_name}</bdi> · {ws(lang, 'sd_uploaded', { date: new Date(d.uploaded_at).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) })}</div>
                </div>
              </div>
              {/* The four actions every document offers (instruction 524): View / Download / Replace / Remove, from
                  the one shared row. A fresh URL each press — the one in the list expires after an hour. */}
              <DocActions lang={lang} name={d.file_name} accept={ACCEPT} getUrl={() => freshUrl(d.id)}
                onReplace={(f: File) => save({ id: d.id }, f, 'r' + d.id)}
                onRemove={() => remove(d.id)} />
            </li>
          ))}
        </ul>}
    </section>
  );
}
