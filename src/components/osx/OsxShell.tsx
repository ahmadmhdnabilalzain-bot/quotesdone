'use client';
import * as React from 'react';
import { supa, osApi, osOps, osReportBody, osSettings, osAutomation, osCatalog, osPages, osHealth, osIncidents, SUPA_URL } from '@/lib/osClient';
import { cn } from '@/lib/utils';
function ReportViewer({ id }: { id: number }) {
  const [st, setSt] = React.useState<'idle' | 'load' | 'done' | 'err'>('load');
  const [rep, setRep] = React.useState<any>(null);
  const [err, setErr] = React.useState('');
  React.useEffect(() => {
    let alive = true; setRep(null); setErr(''); setSt('load');
    osReportBody(id).then((r) => { if (!alive) return; if (r && r.found && r.report) { setRep(r.report); setSt('done'); } else { setErr((r && r.note) || 'No stored report body for this row.'); setSt('err'); } }).catch((e: any) => { if (alive) { setErr(e?.message || 'Failed to load report'); setSt('err'); } });
    return () => { alive = false; };
  }, [id]);
  const printIt = () => {
    if (!rep) return;
    const esc = (x: any) => String(x == null ? '' : x).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const w = window.open('', '_blank'); if (!w) return;
    w.document.write('<html><head><title>' + esc(rep.title || 'Report') + '</title><style>body{font:14px/1.6 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;padding:32px;color:#111;max-width:820px;margin:auto}h1{font-size:19px;margin:0 0 16px}pre{white-space:pre-wrap;word-wrap:break-word;font:inherit}</style></head><body><h1>' + esc(rep.title || 'Report') + '</h1><pre>' + esc(rep.body || '') + '</pre></body></html>');
    w.document.close(); w.focus(); setTimeout(() => { try { w.print(); } catch (_e) {} }, 300);
  };
  return (<div className='mt-4'>
    {st === 'done' && rep ? <button onClick={printIt} className='inline-flex h-8 items-center rounded-md bg-primary px-3 text-xs font-medium text-primary-foreground hover:opacity-90 mb-2'>Print / Save as PDF</button> : null}
    {st === 'load' ? <div className='text-sm text-muted-foreground'>Loading report…</div> : null}
    {st === 'err' ? <div className='text-sm text-amber-400'>{err}</div> : null}
    {st === 'done' && rep ? <div className='space-y-3'>
      <div className='text-base font-semibold'>{rep.title}</div>
      {rep.kpis && typeof rep.kpis === 'object' && !Array.isArray(rep.kpis) ? <div className='grid grid-cols-2 gap-2 sm:grid-cols-3'>{Object.entries(rep.kpis).map(([k, v]: any) => (<div key={k} className='rounded-md border border-border/50 bg-card/40 px-3 py-2'><div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{titleCaseSafe(k)}</div><div className='text-sm font-medium break-words'>{fmt(v)}</div></div>))}</div> : null}
      <pre className='whitespace-pre-wrap break-words rounded-md border border-border/50 bg-background/60 p-3 text-[13px] leading-relaxed'>{rep.body}</pre>
    </div> : null}
  </div>);
}
function titleCaseSafe(k: string) { return String(k).replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()); }
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { CommandDialog, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem } from '@/components/ui/command';
import { MessageSquare, LayoutDashboard, ArrowLeftRight, Hammer, Users, DollarSign, Sparkles, Settings2, Scale, LogOut, Search, Paperclip, Send, Circle, AlertTriangle, Bell, BookOpen, Calendar, BarChart3, Megaphone, Compass, FileText, Building2, FileBarChart, ShieldAlert, RotateCcw, ScrollText, AudioLines, SlidersHorizontal, Workflow, ListChecks, Newspaper, Activity, LifeBuoy, ArrowUpRight, Minus, Maximize2, Minimize2, ExternalLink, SquareStack, X } from 'lucide-react';

type Mod = { id: string; label: string; icon: any; kind?: string; ws?: string };
const MODULES: Mod[] = [
  { id: 'console', label: 'Command Console', icon: MessageSquare, kind: 'console' },
  { id: 'overview', label: 'Overview', icon: LayoutDashboard, kind: 'overview' },
  { id: 'escalations', label: 'Escalations', icon: AlertTriangle, kind: 'escalations' },
  { id: 'rfqs', label: 'RFQs & Procurement', icon: ArrowLeftRight, ws: 'ws.marketplace' },
  { id: 'suppliers', label: 'Suppliers', icon: Hammer, ws: 'ws.suppliers' },
  { id: 'customers', label: 'Customers', icon: Users, ws: 'ws.customers' },
  { id: 'finance', label: 'Finance', icon: DollarSign, ws: 'ws.finance' },
  { id: 'agents', label: 'Smart Engine', icon: Sparkles, ws: 'ws.agents' },
  { id: 'knowledge', label: 'Knowledge', icon: BookOpen, kind: 'knowledge' },
  { id: 'intake_audio', label: 'Intake Audio', icon: AudioLines, kind: 'intake_audio' },
  { id: 'operations', label: 'Operations', icon: Settings2, ws: 'ws.operations' },
  { id: 'governance', label: 'Governance', icon: Scale, ws: 'ws.governance' },
  { id: 'ea', label: 'Assistant', icon: Calendar, ws: 'ws.ea' },
  { id: 'analytics', label: 'Analytics', icon: BarChart3, ws: 'ws.analytics' },
  { id: 'marketing', label: 'Marketing', icon: Megaphone, ws: 'ws.marketing' },
  { id: 'strategy', label: 'Strategy', icon: Compass, ws: 'ws.strategy' },
  { id: 'documents', label: 'Documents', icon: FileText, ws: 'ws.documents' },
  { id: 'company', label: 'Company', icon: Building2, ws: 'ws.company' },
  { id: 'reports', label: 'Reports', icon: FileBarChart, ws: 'ws.reports' },
  { id: 'fraud', label: 'Fraud', icon: ShieldAlert, ws: 'ws.fraud' },
  { id: 'refunds', label: 'Refunds', icon: RotateCcw, ws: 'ws.refunds' },
  { id: 'audit', label: 'Audit log', icon: ScrollText, kind: 'audit' },
  { id: 'settings', label: 'Settings', icon: SlidersHorizontal, kind: 'settings' },
  { id: 'automation', label: 'Automation', icon: Workflow, kind: 'automation' },
  { id: 'catalog', label: 'Categories', icon: ListChecks, kind: 'catalog' },
  { id: 'content', label: 'Content', icon: Newspaper, kind: 'content' },
  { id: 'health', label: 'System Health', icon: Activity, kind: 'health' },
  { id: 'support', label: 'Support', icon: LifeBuoy, kind: 'support' },
];
const PIPELINE = [ ['sent','New'], ['matched','Matched'], ['quoted','Quoted'], ['revealed','Revealed'], ['completed','Won'] ];

function fmt(v: any): string {
  if (v == null || v === '') return '—';
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  if (typeof v === 'number') return Number.isFinite(v) ? v.toLocaleString() : '—';
  if (typeof v === 'string') {
    const tv = v.trim();
    if ((tv.charAt(0) === '{' && tv.charAt(tv.length - 1) === '}') || (tv.charAt(0) === '[' && tv.charAt(tv.length - 1) === ']')) { try { const pj = JSON.parse(tv); if (pj && typeof pj === 'object') return fmt(pj); } catch (_e) {} }
    if (/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/.test(v)) { const dt = new Date(v); if (!isNaN(dt.getTime())) return dt.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); }
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) { const dt = new Date(v + 'T00:00:00'); if (!isNaN(dt.getTime())) return dt.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }); }
    return v.length > 160 ? v.slice(0, 160) + '…' : v;
  }
  if (Array.isArray(v)) { if (!v.length) return '—'; if (typeof v[0] !== 'object') return v.map((x) => fmt(x)).join(', '); return v.length + (v.length === 1 ? ' item' : ' items'); }
  if (typeof v === 'object') { const parts = Object.entries(v).filter(([, x]) => x != null && x !== '').slice(0, 4).map(([k, x]) => titleCase(k) + ': ' + (x && typeof x === 'object' ? '…' : String(x))); return parts.length ? parts.join('  ·  ') : '—'; }
  return String(v);
}
function ReadableObject({ data }: { data: any }): any {
  if (data == null) return <div className='text-sm text-muted-foreground'>—</div>;
  if (typeof data !== 'object') return <div className='whitespace-pre-wrap break-words text-sm leading-relaxed'>{String(data)}</div>;
  if (Array.isArray(data)) {
    if (!data.length) return <div className='text-sm text-muted-foreground'>Nothing here yet.</div>;
    if (typeof data[0] !== 'object') return <div className='text-sm'>{data.map((x: any) => fmt(x)).join(', ')}</div>;
    return <div className='space-y-3'>{data.map((x: any, i: number) => (<div key={i} className='rounded-md border border-border/40 p-3'><ReadableObject data={x} /></div>))}</div>;
  }
  const entries = Object.entries(data);
  if (!entries.length) return <div className='text-sm text-muted-foreground'>Nothing here yet.</div>;
  return (<div className='space-y-2'>{entries.map(([k, v]) => {
    const isArrObj = Array.isArray(v) && (v as any[]).length && typeof (v as any[])[0] === 'object';
    const isObj = v && typeof v === 'object' && !Array.isArray(v);
    return (<div key={k} className='border-b border-border/40 py-2 last:border-0'>
      <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{titleCase(k)}</div>
      {isObj || isArrObj ? <div className='mt-1 pl-3 border-l border-border/40'><ReadableObject data={v} /></div>
        : <div className='mt-0.5 text-sm break-words whitespace-pre-wrap'>{fmt(v)}</div>}
    </div>);
  })}</div>);
}
function titleCase(s: string) { return String(s).replace(/[_\.]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()); }
function deEnt(s: any) { return String(s == null ? '' : s).replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'"); }

// ── Window Manager — hybrid workspace: pop any module/record into a floating, draggable/resizable window ──
type WinSpec = { id: string; title: string; icon?: any; render: () => React.ReactNode };
type WinState = WinSpec & { x: number; y: number; w: number; h: number; z: number; min: boolean; max: boolean; snap?: 'l' | 'r' | null };
const WinCtx = React.createContext<{ open: (s: WinSpec) => void } | null>(null);
function useWindows() { return React.useContext(WinCtx); }
// Keep floating-window z-indexes in a compact low range (31..~45) so they never cover the Ctrl+K palette (z-50).
function bringToTop(list: WinState[], id: string, patch: Partial<WinState> = {}): WinState[] {
  const others = list.filter((x) => x.id !== id).sort((a, b) => a.z - b.z).map((x, i) => ({ ...x, z: 31 + i }));
  const tgt = list.find((x) => x.id === id); if (!tgt) return list;
  return [...others, { ...tgt, ...patch, z: 31 + others.length }];
}

// Shared module renderer — used by both the tabbed main area and floating windows.
function renderModule(id: string, go: (id: string) => void): React.ReactNode {
  const m = MODULES.find((x) => x.id === id) || MODULES[0];
  return m.kind === 'console' ? <Console /> : m.kind === 'overview' ? <Overview onNav={go} /> : m.kind === 'escalations' ? <Escalations onNav={go} /> : m.kind === 'knowledge' ? <Knowledge /> : m.kind === 'audit' ? <AuditLog /> : m.kind === 'settings' ? <SettingsPanel /> : m.kind === 'automation' ? <AutomationPanel /> : m.kind === 'catalog' ? <CatalogPanel /> : m.kind === 'content' ? <ContentPanel /> : m.kind === 'health' ? <HealthPanel onNav={go} /> : m.kind === 'support' ? <SupportPanel /> : m.kind === 'intake_audio' ? <IntakeAudio /> : m.id === 'suppliers' ? <SuppliersApp /> : m.id === 'rfqs' ? <RfqApp /> : m.id === 'customers' ? <CustomersApp /> : m.id === 'agents' ? <AgentsApp /> : m.id === 'finance' ? <FinanceApp /> : <Workspace mod={m} />;
}

function FloatingWindow({ win, onFocus, onClose, onMin, onMax, onMove, onSize, onSnap }: { win: WinState; onFocus: () => void; onClose: () => void; onMin: () => void; onMax: () => void; onMove: (x: number, y: number) => void; onSize: (w: number, h: number) => void; onSnap: (s: 'l' | 'r' | null) => void }) {
  const Icon = win.icon;
  const startDrag = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).closest('button')) return;
    onFocus(); const sx = e.clientX, sy = e.clientY, ox = win.x, oy = win.y; let snapped: 'l' | 'r' | null = null;
    const vw = window.innerWidth, vh = window.innerHeight;
    const mv = (ev: PointerEvent) => { const nx = ox + ev.clientX - sx, ny = oy + ev.clientY - sy; snapped = ev.clientX < 12 ? 'l' : ev.clientX > vw - 12 ? 'r' : (ev.clientY < 8 ? null : null); onMove(Math.max(-40, nx), Math.max(52, Math.min(vh - 40, ny))); };
    const up = () => { document.removeEventListener('pointermove', mv); document.removeEventListener('pointerup', up); if (snapped) onSnap(snapped); };
    document.addEventListener('pointermove', mv); document.addEventListener('pointerup', up);
  };
  const startResize = (e: React.PointerEvent) => {
    e.stopPropagation(); onFocus(); const sx = e.clientX, sy = e.clientY, ow = win.w, oh = win.h;
    const mv = (ev: PointerEvent) => onSize(Math.max(340, ow + ev.clientX - sx), Math.max(220, oh + ev.clientY - sy));
    const up = () => { document.removeEventListener('pointermove', mv); document.removeEventListener('pointerup', up); };
    document.addEventListener('pointermove', mv); document.addEventListener('pointerup', up);
  };
  if (win.min) return null;
  const style: React.CSSProperties = win.max ? { left: 0, top: 48, width: '100%', height: 'calc(100% - 48px)' }
    : win.snap === 'l' ? { left: 0, top: 48, width: '50%', height: 'calc(100% - 48px)' }
    : win.snap === 'r' ? { right: 0, top: 48, width: '50%', height: 'calc(100% - 48px)' }
    : { left: win.x, top: win.y, width: win.w, height: win.h };
  return (
    <div className='fixed rounded-xl border border-border bg-card shadow-2xl flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-150' style={{ ...style, zIndex: win.z }} onMouseDown={onFocus}>
      <div className='h-9 shrink-0 flex items-center gap-2 px-3 border-b border-border bg-foreground/[0.03] cursor-move select-none' onPointerDown={startDrag} onDoubleClick={onMax}>
        {Icon ? <Icon className='h-3.5 w-3.5 text-primary shrink-0' /> : null}
        <span className='text-xs font-medium truncate'>{win.title}</span>
        <div className='ml-auto flex items-center gap-0.5'>
          <button title='Minimize' onClick={onMin} className='h-6 w-6 grid place-items-center rounded hover:bg-foreground/10 text-muted-foreground'><Minus className='h-3.5 w-3.5' /></button>
          <button title={win.max ? 'Restore' : 'Maximize'} onClick={onMax} className='h-6 w-6 grid place-items-center rounded hover:bg-foreground/10 text-muted-foreground'>{win.max ? <Minimize2 className='h-3 w-3' /> : <Maximize2 className='h-3 w-3' />}</button>
          <button title='Close' onClick={onClose} className='h-6 w-6 grid place-items-center rounded hover:bg-destructive/15 hover:text-destructive text-muted-foreground'><X className='h-3.5 w-3.5' /></button>
        </div>
      </div>
      <div className='flex-1 min-h-0 overflow-auto p-4'>{win.render()}</div>
      {!win.max && !win.snap ? <div onPointerDown={startResize} className='absolute bottom-0 right-0 h-4 w-4 cursor-se-resize opacity-40 hover:opacity-80' style={{ background: 'linear-gradient(135deg, transparent 50%, hsl(var(--muted-foreground)) 50%, hsl(var(--muted-foreground)) 60%, transparent 60%, transparent 70%, hsl(var(--muted-foreground)) 70%, hsl(var(--muted-foreground)) 80%, transparent 80%)' }} /> : null}
    </div>
  );
}

function WindowLayer({ wins, focus, close, min, max, move, size, snap }: { wins: WinState[]; focus: (id: string) => void; close: (id: string) => void; min: (id: string) => void; max: (id: string) => void; move: (id: string, x: number, y: number) => void; size: (id: string, w: number, h: number) => void; snap: (id: string, s: 'l' | 'r' | null) => void }) {
  if (!wins.length) return null;
  return (<>
    {wins.map((w) => <FloatingWindow key={w.id} win={w} onFocus={() => focus(w.id)} onClose={() => close(w.id)} onMin={() => min(w.id)} onMax={() => max(w.id)} onMove={(x, y) => move(w.id, x, y)} onSize={(ww, hh) => size(w.id, ww, hh)} onSnap={(s) => snap(w.id, s)} />)}
    <div className='fixed bottom-0 left-0 right-0 h-9 z-[60] flex items-center gap-1 px-2 border-t border-border bg-card/95 backdrop-blur overflow-x-auto'>
      <SquareStack className='h-3.5 w-3.5 text-muted-foreground shrink-0' />
      {wins.map((w) => { const Ic = w.icon; return (
        <button key={w.id} onClick={() => (w.min ? min(w.id) : focus(w.id))} className={cn('flex items-center gap-1.5 h-6 px-2.5 rounded text-xs shrink-0 transition-colors', w.min ? 'bg-foreground/5 text-muted-foreground hover:bg-foreground/10' : 'bg-primary/15 text-primary')}>
          {Ic ? <Ic className='h-3 w-3' /> : null}<span className='max-w-[140px] truncate'>{w.title}</span>
          <span onClick={(e) => { e.stopPropagation(); close(w.id); }} className='opacity-50 hover:opacity-100 ml-0.5'>×</span>
        </button>); })}
    </div>
  </>);
}

export default function OsxShell() {
  const [ready, setReady] = React.useState(false);
  const [email, setEmail] = React.useState('');
  const [cur, setCur] = React.useState('console');
  const [tabs, setTabs] = React.useState<string[]>(['console']);
  const [paletteOpen, setPaletteOpen] = React.useState(false);
  const [live, setLive] = React.useState(0);
  const [wins, setWins] = React.useState<WinState[]>([]);
  const openWindow = React.useCallback((s: WinSpec) => {
    setWins((w) => { const ex = w.find((x) => x.id === s.id); if (ex) return bringToTop(w, s.id, { min: false }); const n = w.length; const withNew = [...w, { ...s, x: 90 + (n % 6) * 30, y: 96 + (n % 6) * 30, w: 760, h: 500, z: 0, min: false, max: false, snap: null }]; return bringToTop(withNew, s.id); });
  }, []);
  const focusWin = React.useCallback((id: string) => setWins((w) => bringToTop(w, id, { min: false })), []);
  const closeWin = React.useCallback((id: string) => setWins((w) => w.filter((x) => x.id !== id)), []);
  const minWin = React.useCallback((id: string) => setWins((w) => w.map((x) => x.id === id ? { ...x, min: !x.min } : x)), []);
  const maxWin = React.useCallback((id: string) => setWins((w) => { const t = w.find((x) => x.id === id); return bringToTop(w, id, { max: !t?.max, snap: null }); }), []);
  const moveWin = React.useCallback((id: string, x: number, y: number) => setWins((w) => w.map((k) => k.id === id ? { ...k, x, y, snap: null, max: false } : k)), []);
  const sizeWin = React.useCallback((id: string, ww: number, hh: number) => setWins((w) => w.map((k) => k.id === id ? { ...k, w: ww, h: hh } : k)), []);
  const snapWin = React.useCallback((id: string, s: 'l' | 'r' | null) => setWins((w) => bringToTop(w, id, { snap: s, max: false })), []);

  React.useEffect(() => {
    let sub: any;
    supa.auth.getSession().then(({ data }) => { setEmail(data.session?.user?.email || ''); setReady(true); });
    sub = supa.auth.onAuthStateChange((_e, s) => setEmail(s?.user?.email || '')).data.subscription;
    const onKey = (e: KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setPaletteOpen((o) => !o); } };
    window.addEventListener('keydown', onKey);
    return () => { try { sub?.unsubscribe(); } catch (_e) {} window.removeEventListener('keydown', onKey); };
  }, []);

  // Supabase Realtime: live activity indicator
  React.useEffect(() => {
    if (!email) return;
    const ch = supa.channel('osx-live')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'inquiries' }, () => setLive((n) => n + 1))
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => setLive((n) => n + 1))
      .subscribe();
    return () => { try { supa.removeChannel(ch); } catch (_e) {} };
  }, [email]);

  if (!ready) return <div className='osx dark min-h-screen grid place-items-center text-muted-foreground'>Loading…</div>;
  if (!email) return <LoginCard onDone={(e) => setEmail(e)} />;

  const go = (id: string) => { setTabs((t) => t.includes(id) ? t : [...t, id]); setCur(id); };
  const closeTab = (id: string) => { setTabs((t) => { const nt = t.filter((x) => x !== id); if (!nt.length) return ['console']; if (id === cur) setCur(nt[nt.length - 1]); return nt; }); };
  const popOut = (id: string) => { const m = MODULES.find((x) => x.id === id) || MODULES[0]; openWindow({ id: 'mod:' + id, title: m.label, icon: m.icon, render: () => renderModule(id, go) }); };
  return (
    <WinCtx.Provider value={{ open: openWindow }}>
    <div className='osx dark min-h-screen flex text-foreground'>
      <aside className='w-60 shrink-0 border-r border-border bg-card/40 hidden md:flex md:flex-col'>
        <div className='h-14 flex items-center gap-2 px-4 border-b border-border'>
          <div className='h-7 w-7 rounded-lg bg-primary text-primary-foreground grid place-items-center font-extrabold'>Q</div>
          <div className='font-bold'>QuotesDone <span className='text-muted-foreground font-normal text-xs'>OS</span></div>
        </div>
        <nav className='flex-1 overflow-auto p-2 space-y-0.5'>
          {MODULES.map((m) => { const I = m.icon; return (
            <button key={m.id} onClick={() => go(m.id)} className={cn('w-full flex items-center gap-2.5 rounded-md px-3 py-2 text-sm transition-colors', m.id === cur ? 'bg-primary/15 text-primary' : 'text-foreground/80 hover:bg-foreground/5')}>
              <I className='h-4 w-4' /><span>{m.label}</span>
            </button>
          ); })}
        </nav>
        <div className='p-2 border-t border-border'>
          <button onClick={async () => { try { await supa.auth.signOut(); } catch (_e) {} setEmail(''); }} className='w-full flex items-center gap-2.5 rounded-md px-3 py-2 text-sm text-foreground/70 hover:bg-foreground/5'><LogOut className='h-4 w-4' />Sign out</button>
        </div>
      </aside>

      <div className='flex-1 min-w-0 flex flex-col'>
        <header className='h-14 shrink-0 border-b border-border flex items-center gap-3 px-4'>
          <PipelineTracker onNav={go} />
          <button onClick={() => setPaletteOpen(true)} className='ml-auto flex items-center gap-2 rounded-md border border-border px-3 h-9 text-sm text-muted-foreground hover:bg-foreground/5'>
            <Search className='h-4 w-4' /><span className='hidden sm:inline'>Search or run a command</span><kbd className='hidden sm:inline text-[10px] bg-foreground/10 rounded px-1.5 py-0.5'>⌘K</kbd>
          </button>
          <AgentStatus onOpen={() => go('agents')} />
          <NotificationsBell pulse={live} onNav={go} />
          <div className='flex items-center gap-1.5 text-xs text-muted-foreground' title='Live activity'><Circle className={cn('h-2.5 w-2.5', live ? 'fill-emerald-400 text-emerald-400' : 'fill-muted text-muted')} />{live > 0 ? live + ' live' : 'idle'}</div>
        </header>
        <div className='h-10 shrink-0 border-b border-border flex items-stretch gap-1 px-2 overflow-x-auto'>
          {tabs.map((id) => { const m = MODULES.find((x) => x.id === id) || MODULES[0]; const I = m.icon; return (
            <div key={id} onClick={() => setCur(id)} title='Double-click title or use ⧉ to pop out to a floating window' className={cn('group flex items-center gap-1.5 px-3 text-xs cursor-pointer border-b-2', id === cur ? 'border-primary text-primary bg-foreground/5' : 'border-transparent text-muted-foreground hover:text-foreground')}>
              <I className='h-3.5 w-3.5' /><span>{m.label}</span>
              <button title='Pop out to floating window' onClick={(e) => { e.stopPropagation(); popOut(id); }} className='opacity-0 group-hover:opacity-70 hover:!opacity-100 ml-0.5'><ExternalLink className='h-3 w-3' /></button>
              {tabs.length > 1 ? <button onClick={(e) => { e.stopPropagation(); closeTab(id); }} className='opacity-40 group-hover:opacity-100 hover:text-foreground ml-0.5 text-sm leading-none'>×</button> : null}
            </div>
          ); })}
        </div>
        <main className='flex-1 min-h-0 overflow-y-scroll p-4 md:p-6'>
          {tabs.map((id) => { const m = MODULES.find((x) => x.id === id) || MODULES[0]; return (
            <div key={id} className={id === cur ? '' : 'hidden'}>
              {renderModule(id, go)}
            </div>
          ); })}
        </main>
      </div>

      <CommandDialog open={paletteOpen} onOpenChange={setPaletteOpen}>
        <CommandInput placeholder='Jump to a module, or type: status, RFQ #302…' />
        <CommandList>
          <CommandEmpty>No matches.</CommandEmpty>
          <CommandGroup heading='Modules'>
            {MODULES.map((m) => (<CommandItem key={m.id} onSelect={() => { setCur(m.id); setPaletteOpen(false); }}><m.icon className='h-4 w-4' />{m.label}</CommandItem>))}
          </CommandGroup>
          <CommandGroup heading='Actions'>
            <CommandItem onSelect={() => { setCur('console'); setPaletteOpen(false); }}><MessageSquare className='h-4 w-4' />Ask the Secretary for status</CommandItem>
            <CommandItem onSelect={() => { setCur('agents'); setPaletteOpen(false); }}><Sparkles className='h-4 w-4' />Show matching / agent activity</CommandItem>
          </CommandGroup>
        </CommandList>
      </CommandDialog>
      <WindowLayer wins={wins} focus={focusWin} close={closeWin} min={minWin} max={maxWin} move={moveWin} size={sizeWin} snap={snapWin} />
    </div>
    </WinCtx.Provider>
  );
}

function prettyErr(r: any): string {
  const e = r?.error || 'invalid';
  const map: any = { must_be_a_number: 'Must be a number', must_be_a_whole_number: 'Must be a whole number', below_minimum: 'Below the minimum (' + r?.min + ')', above_maximum: 'Above the maximum (' + r?.max + ')', must_be_true_or_false: 'Must be on or off', not_an_email: 'Not a valid email address', too_long: 'Too long (max ' + r?.maxlen + ' characters)', key_not_editable: 'This setting is locked and cannot be changed here', no_history_to_revert: 'No previous value to revert to' };
  return map[e] || e;
}

function SettingRow({ s, onSaved }: { s: any; onSaved: (key: string, val: string) => void }) {
  const [val, setVal] = React.useState<string>(String(s.value ?? ''));
  const [busy, setBusy] = React.useState(false);
  const [msg, setMsg] = React.useState('');
  const [err, setErr] = React.useState('');
  const [hist, setHist] = React.useState<any[] | null>(null);
  React.useEffect(() => { setVal(String(s.value ?? '')); }, [s.value]);
  const dirty = String(s.value ?? '') !== val;
  const save = async (confirm?: boolean) => {
    setBusy(true); setErr(''); setMsg('');
    try {
      const r: any = await osSettings('set', { key: s.key, value: val, confirm: !!confirm });
      if (r && r.needs_confirm) {
        setBusy(false);
        if (typeof window !== 'undefined' && window.confirm('“' + (r.label || s.label) + '” is a sensitive switch. Apply it now?')) { await save(true); }
        return;
      }
      if (r && r.ok === false) { setErr(prettyErr(r)); setBusy(false); return; }
      onSaved(s.key, r?.new ?? val); setMsg('Saved'); setTimeout(() => setMsg(''), 1500);
    } catch (e: any) { setErr(e?.message || 'Failed'); }
    setBusy(false);
  };
  const revert = async () => {
    setBusy(true); setErr(''); setMsg('');
    try { const r: any = await osSettings('revert', { key: s.key }); if (r && r.ok === false) { setErr(prettyErr(r)); } else { onSaved(s.key, r?.new ?? val); setVal(String(r?.new ?? val)); setMsg('Reverted'); setTimeout(() => setMsg(''), 1500); } }
    catch (e: any) { setErr(e?.message || 'Failed'); }
    setBusy(false);
  };
  const loadHist = async () => { try { const r: any = await osSettings('history', { key: s.key }); setHist(r?.history || []); } catch (_e) { setHist([]); } };
  const isBool = s.type === 'bool';
  const isBig = s.type === 'textarea' || s.type === 'html';
  return (
    <div className='py-3 border-b border-border/40 last:border-0'>
      <div className='flex flex-col md:flex-row items-start gap-4'>
        <div className='w-full md:w-64 shrink-0'>
          <div className='text-sm font-medium flex items-center gap-1.5'>{s.label}{s.dangerous ? <span title='Sensitive switch' className='text-amber-400'>●</span> : null}</div>
          {s.help ? <div className='text-xs text-muted-foreground mt-0.5'>{s.help}</div> : null}
          <div className='text-[10px] text-muted-foreground/60 mt-0.5 font-mono'>{s.key}</div>
        </div>
        <div className='flex-1 min-w-0 w-full'>
          {isBool ? (
            <button type='button' onClick={() => setVal(val === 'true' ? 'false' : 'true')} className={cn('inline-flex h-6 items-center rounded-full px-0.5 w-11 transition-colors', val === 'true' ? 'bg-primary' : 'bg-muted')}><span className={cn('h-5 w-5 rounded-full bg-white shadow transition-transform', val === 'true' ? 'translate-x-5' : 'translate-x-0')} /></button>
          ) : isBig ? (
            <textarea value={val} onChange={(e) => setVal(e.target.value)} rows={s.type === 'html' ? 8 : 4} className='w-full rounded-md border border-border bg-background/60 p-2 text-sm font-mono' />
          ) : (
            <Input value={val} onChange={(e) => setVal(e.target.value)} type={s.type === 'money' || s.type === 'int' || s.type === 'number' ? 'number' : 'text'} className='max-w-md' />
          )}
          <div className='flex items-center gap-3 mt-2'>
            <Button className='h-7 text-xs' disabled={busy || !dirty} onClick={() => save(false)}>{busy ? 'Saving…' : 'Save'}</Button>
            {dirty ? <button type='button' className='text-xs text-muted-foreground underline' onClick={() => setVal(String(s.value ?? ''))}>Cancel</button> : null}
            <button type='button' className='text-xs text-muted-foreground underline ml-auto' onClick={() => { if (hist === null) loadHist(); else setHist(null); }}>{hist === null ? 'History' : 'Hide'}</button>
            <button type='button' className='text-xs text-muted-foreground underline' onClick={revert} disabled={busy}>Revert</button>
          </div>
          {msg ? <div className='text-xs text-emerald-400 mt-1'>{msg}</div> : null}
          {err ? <div className='text-xs text-destructive mt-1'>{err}</div> : null}
          {hist && hist.length ? <div className='mt-2 text-xs text-muted-foreground space-y-1'>{hist.map((h: any, i: number) => (<div key={i} className='flex flex-wrap gap-2'><span className='opacity-60'>{h.at ? new Date(h.at).toLocaleString() : ''}</span><span>{h.actor}</span><span className='opacity-80'>“{h.old}” → “{h.new}”</span></div>))}</div> : null}
          {hist && !hist.length ? <div className='mt-2 text-xs text-muted-foreground'>No changes recorded yet.</div> : null}
        </div>
      </div>
    </div>
  );
}

function SettingsPanel() {
  const [d, setD] = React.useState<any[] | null>(null);
  const [err, setErr] = React.useState('');
  const load = React.useCallback(() => { setD(null); setErr(''); osSettings('list').then((r: any) => setD(r?.settings || [])).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const onSaved = (key: string, val: string) => { setD((prev) => (prev ? prev.map((x) => (x.key === key ? { ...x, value: val } : x)) : prev)); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load settings: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading settings…</div>;
  const groups: string[] = [];
  d.forEach((s) => { if (!groups.includes(s.grp)) groups.push(s.grp); });
  return (
    <div className='space-y-5'>
      <div className='flex flex-wrap items-center gap-2'><SlidersHorizontal className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Settings</h1><span className='text-xs text-muted-foreground md:ml-2'>Business configuration. API keys and secrets are managed separately and never appear here. Every change is audit-logged and reversible.</span></div>
      {groups.map((g) => (
        <Card key={g} className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>{g}</div>
          <div className='px-4'>
            {d.filter((s) => s.grp === g).map((s) => (<SettingRow key={s.key} s={s} onSaved={onSaved} />))}
          </div>
        </Card>
      ))}
    </div>
  );
}

function fmtCron(s: string): string {
  const map: any = { '* * * * *': 'every minute', '*/2 * * * *': 'every 2 min', '*/5 * * * *': 'every 5 min', '*/10 * * * *': 'every 10 min', '*/15 * * * *': 'every 15 min', '*/20 * * * *': 'every 20 min', '*/30 * * * *': 'every 30 min', '0 * * * *': 'hourly' };
  return map[s] || s;
}

function JobRow({ j, onChanged }: { j: any; onChanged: () => void }) {
  const [sched, setSched] = React.useState<string>(String(j.schedule || ''));
  const [busy, setBusy] = React.useState('');
  const [msg, setMsg] = React.useState('');
  const [err, setErr] = React.useState('');
  React.useEffect(() => { setSched(String(j.schedule || '')); }, [j.schedule]);
  const schedDirty = String(j.schedule || '') !== sched;
  const act = async (fn: () => Promise<any>, tag: string) => { setBusy(tag); setErr(''); setMsg(''); try { const r: any = await fn(); if (r && r.ok === false) setErr(r.error || 'Failed'); else { setMsg('Done'); setTimeout(() => setMsg(''), 1200); onChanged(); } } catch (e: any) { setErr(e?.message || 'Failed'); } setBusy(''); };
  const toggle = () => act(() => osAutomation('set_active', { jobid: j.jobid, active: !j.active }), 'toggle');
  const runNow = () => { if (typeof window !== 'undefined' && !window.confirm('Run “' + j.human_name + '” right now? This executes the job immediately.')) return; act(() => osAutomation('run', { jobid: j.jobid }), 'run'); };
  const saveSched = () => act(() => osAutomation('reschedule', { jobid: j.jobid, schedule: sched }), 'sched');
  const stColor = j.last_status === 'succeeded' ? 'text-emerald-400' : j.last_status === 'failed' ? 'text-destructive' : 'text-muted-foreground';
  return (
    <div className='py-2.5 border-b border-border/40 last:border-0 flex flex-col md:flex-row md:items-center gap-3'>
      <div className='md:w-72 shrink-0'>
        <div className='text-sm font-medium flex items-center gap-2'>{j.human_name}{!j.active ? <Badge variant='secondary' className='text-[10px]'>paused</Badge> : null}</div>
        <div className='text-[10px] text-muted-foreground/60 font-mono'>{j.jobname}</div>
      </div>
      <div className='flex items-center gap-2'>
        <Input value={sched} onChange={(e) => setSched(e.target.value)} className='h-7 w-36 text-xs font-mono' />
        {schedDirty ? <Button className='h-7 text-xs' disabled={busy === 'sched'} onClick={saveSched}>Set</Button> : <span className='text-[11px] text-muted-foreground w-20'>{fmtCron(j.schedule)}</span>}
      </div>
      <div className={cn('text-xs flex items-center gap-1.5 md:w-52 min-w-0', stColor)}>
        <Circle className='h-2 w-2 fill-current shrink-0' /><span className='truncate'>{j.last_status || 'no runs'}{j.last_start ? ' · ' + new Date(j.last_start).toLocaleString() : ''}</span>
      </div>
      <div className='flex items-center gap-2 md:ml-auto'>
        <Button variant='outline' className='h-7 text-xs' disabled={busy === 'run'} onClick={runNow}>{busy === 'run' ? 'Running…' : 'Run now'}</Button>
        <button type='button' onClick={toggle} disabled={busy === 'toggle'} className={cn('inline-flex h-6 items-center rounded-full px-0.5 w-11 transition-colors', j.active ? 'bg-primary' : 'bg-muted')}><span className={cn('h-5 w-5 rounded-full bg-white shadow transition-transform', j.active ? 'translate-x-5' : 'translate-x-0')} /></button>
      </div>
      {(msg || err) ? <div className={cn('text-xs md:w-full', err ? 'text-destructive' : 'text-emerald-400')}>{err || msg}</div> : null}
    </div>
  );
}

function AutomationPanel() {
  const [d, setD] = React.useState<any[] | null>(null);
  const [err, setErr] = React.useState('');
  const load = React.useCallback(() => { setErr(''); osAutomation('list').then((r: any) => setD(r?.jobs || [])).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { load(); }, [load]);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load automation: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading automation…</div>;
  const groups: string[] = [];
  d.forEach((j) => { if (!groups.includes(j.category)) groups.push(j.category); });
  groups.sort();
  const active = d.filter((j) => j.active).length;
  return (
    <div className='space-y-5'>
      <div className='flex flex-wrap items-center gap-2'><Workflow className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Automation</h1><span className='text-xs text-muted-foreground md:ml-2'>{active} of {d.length} scheduled jobs running. Pause, re-time, or run any job. Every change is audit-logged.</span></div>
      {groups.map((g) => (
        <Card key={g} className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>{g}<Badge variant='secondary'>{d.filter((j) => j.category === g).length}</Badge></div>
          <div className='px-4'>
            {d.filter((j) => j.category === g).map((j) => (<JobRow key={j.jobid} j={j} onChanged={load} />))}
          </div>
        </Card>
      ))}
    </div>
  );
}

function catSlug(s: string): string { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40); }

function CatalogPanel() {
  const [cats, setCats] = React.useState<any[] | null>(null);
  const [q, setQ] = React.useState('');
  const [sel, setSel] = React.useState<string>('');
  const [label, setLabel] = React.useState('');
  const [grp, setGrp] = React.useState('');
  const [fields, setFields] = React.useState<any[]>([]);
  const [specs, setSpecs] = React.useState<any[]>([]);
  const [sample, setSample] = React.useState('');
  const [test, setTest] = React.useState<any>(null);
  const [busy, setBusy] = React.useState('');
  const [msg, setMsg] = React.useState('');
  const [err, setErr] = React.useState('');
  const loadCats = React.useCallback(() => { osCatalog('list').then((r: any) => setCats(r?.categories || [])).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { loadCats(); }, [loadCats]);
  const open = async (c: string) => { setSel(c); setErr(''); setMsg(''); setTest(null); setSample(''); try { const d: any = await osCatalog('get', { category: c }); setLabel(d?.label || c); setGrp(d?.spec_group || ''); setFields(Array.isArray(d?.fields) ? d.fields.map((f: any) => ({ ...f })) : []); setSpecs(Array.isArray(d?.specs) ? d.specs.map((s: any) => ({ ...s })) : []); } catch (e: any) { setErr(e.message); } };
  const saveFields = async () => { setBusy('fields'); setErr(''); setMsg(''); try { const clean = fields.map((f) => ({ key: f.key || catSlug(f.question), type: f.type || 'text', options: Array.isArray(f.options) ? f.options : [], question: f.question || '', required: !!f.required })); const r: any = await osCatalog('save_fields', { category: sel, fields: clean }); if (r && r.ok === false) setErr(r.error); else { setMsg('Questions saved'); setTimeout(() => setMsg(''), 1500); loadCats(); } } catch (e: any) { setErr(e.message); } setBusy(''); };
  const saveSpec = async (s: any, i: number) => { setBusy('spec' + i); setErr(''); try { const r: any = await osCatalog('spec_upsert', { id: s.id || null, spec_group: grp, aspect: s.aspect || catSlug(s.label), label: s.label, match_regex: s.match_regex, mandatory: !!s.mandatory, note: s.note || '' }); if (r && r.ok === false) setErr(r.error); else { setMsg('Check saved'); setTimeout(() => setMsg(''), 1200); const d: any = await osCatalog('get', { category: sel }); setSpecs(Array.isArray(d?.specs) ? d.specs.map((x: any) => ({ ...x })) : []); loadCats(); } } catch (e: any) { setErr(e.message); } setBusy(''); };
  const delSpec = async (s: any) => { if (!s.id) { setSpecs((arr) => arr.filter((x) => x !== s)); return; } if (typeof window !== 'undefined' && !window.confirm('Delete this gate check?')) return; setBusy('del' + s.id); try { await osCatalog('spec_delete', { id: s.id }); setSpecs((arr) => arr.filter((x) => x.id !== s.id)); loadCats(); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const runTest = async () => { setBusy('test'); setErr(''); try { const r: any = await osCatalog('test_gate', { category: sel, sample }); setTest(r); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const filtered = (cats || []).filter((c) => !q || (c.label + ' ' + c.category).toLowerCase().includes(q.toLowerCase()));
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'><ListChecks className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Categories</h1><span className='text-xs text-muted-foreground md:ml-2'>Edit the questions customers answer and the checks a supplier quote must pass. Test the gate live — no code needed. Changes are audit-logged.</span></div>
      <div className='grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-4'>
        <Card className='overflow-hidden'>
          <div className='p-2 border-b border-border'><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder='Search categories…' className='h-8 text-sm' /></div>
          <div className='overflow-auto max-h-[640px]'>
            {!cats ? <div className='p-3 text-sm text-muted-foreground'>Loading…</div> : filtered.map((c) => (
              <button key={c.category} type='button' onClick={() => open(c.category)} className={cn('w-full text-left px-3 py-2 border-b border-border/40 hover:bg-foreground/5', sel === c.category ? 'bg-primary/10' : '')}>
                <div className='text-sm font-medium'>{c.label}</div>
                <div className='text-[11px] text-muted-foreground'>{c.n_fields} questions · {c.n_specs} gate checks</div>
              </button>
            ))}
          </div>
        </Card>
        <div className='min-w-0 space-y-4'>
          {!sel ? <Card className='p-6 text-sm text-muted-foreground'>Select a category to edit its intake questions and quote-gate checks.</Card> : (<>
            {(msg || err) ? <div className={cn('text-xs', err ? 'text-destructive' : 'text-emerald-400')}>{err || msg}</div> : null}
            <Card className='overflow-hidden'>
              <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between gap-2'><span>Intake questions — {label}</span><Button className='h-7 text-xs' disabled={busy === 'fields'} onClick={saveFields}>{busy === 'fields' ? 'Saving…' : 'Save questions'}</Button></div>
              <div className='p-3 space-y-2'>
                {fields.map((f, i) => (
                  <div key={i} className='flex flex-wrap items-center gap-2 border-b border-border/40 pb-2'>
                    <Input value={f.question || ''} onChange={(e) => setFields((a) => a.map((x, j) => j === i ? { ...x, question: e.target.value } : x))} placeholder='Question' className='h-8 text-sm flex-1 min-w-[220px]' />
                    <select value={f.type || 'text'} onChange={(e) => setFields((a) => a.map((x, j) => j === i ? { ...x, type: e.target.value } : x))} className='h-8 rounded-md border border-border bg-background text-xs px-2'>
                      <option value='text'>text</option><option value='select'>select</option><option value='multiselect'>multiselect</option><option value='number'>number</option>
                    </select>
                    <label className='text-xs flex items-center gap-1'><input type='checkbox' checked={!!f.required} onChange={(e) => setFields((a) => a.map((x, j) => j === i ? { ...x, required: e.target.checked } : x))} />required</label>
                    <button type='button' className='text-xs text-destructive underline' onClick={() => setFields((a) => a.filter((_, j) => j !== i))}>remove</button>
                    {(f.type === 'select' || f.type === 'multiselect') ? <Input value={(Array.isArray(f.options) ? f.options.join(', ') : '')} onChange={(e) => setFields((a) => a.map((x, j) => j === i ? { ...x, options: e.target.value.split(',').map((o: string) => o.trim()).filter(Boolean) } : x))} placeholder='Options, comma-separated' className='h-8 text-xs w-full' /> : null}
                  </div>
                ))}
                <button type='button' className='text-xs text-primary underline' onClick={() => setFields((a) => [...a, { key: '', type: 'text', options: [], question: '', required: false }])}>+ Add question</button>
              </div>
            </Card>
            <Card className='overflow-hidden'>
              <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Quote-gate checks <span className='text-xs text-muted-foreground font-normal'>· group: {grp}</span></div>
              <div className='p-3 space-y-2'>
                {specs.map((s, i) => (
                  <div key={s.id || ('new' + i)} className='flex flex-wrap items-center gap-2 border-b border-border/40 pb-2'>
                    <Input value={s.label || ''} onChange={(e) => setSpecs((a) => a.map((x, j) => j === i ? { ...x, label: e.target.value } : x))} placeholder='What to check (e.g. Camera resolution)' className='h-8 text-sm flex-1 min-w-[200px]' />
                    <Input value={s.match_regex || ''} onChange={(e) => setSpecs((a) => a.map((x, j) => j === i ? { ...x, match_regex: e.target.value } : x))} placeholder='pattern (regex)' className='h-8 text-xs font-mono flex-1 min-w-[200px]' />
                    <label className='text-xs flex items-center gap-1'><input type='checkbox' checked={!!s.mandatory} onChange={(e) => setSpecs((a) => a.map((x, j) => j === i ? { ...x, mandatory: e.target.checked } : x))} />must-have</label>
                    <Button className='h-7 text-xs' disabled={busy === 'spec' + i} onClick={() => saveSpec(s, i)}>Save</Button>
                    <button type='button' className='text-xs text-destructive underline' onClick={() => delSpec(s)}>delete</button>
                  </div>
                ))}
                <button type='button' className='text-xs text-primary underline' onClick={() => setSpecs((a) => [...a, { id: null, label: '', match_regex: '', mandatory: false, aspect: '' }])}>+ Add check</button>
              </div>
            </Card>
            <Card className='overflow-hidden'>
              <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Test the gate</div>
              <div className='p-3 space-y-2'>
                <textarea value={sample} onChange={(e) => setSample(e.target.value)} rows={4} placeholder='Paste a sample supplier quote here to see which checks it passes…' className='w-full rounded-md border border-border bg-background/60 p-2 text-sm' />
                <Button className='h-7 text-xs' disabled={busy === 'test' || !sample} onClick={runTest}>{busy === 'test' ? 'Testing…' : 'Test against this category'}</Button>
                {test ? <div className='mt-1 space-y-1'>
                  <div className={cn('text-sm font-medium', test.passes ? 'text-emerald-400' : 'text-amber-400')}>{test.passes ? 'Passes the mandatory checks' : 'Would be blocked — missing must-haves'} · {test.matched_count}/{test.total} checks matched</div>
                  {(test.aspects || []).map((a: any, i: number) => (<div key={i} className='text-xs flex items-center gap-2'><span className={a.matched ? 'text-emerald-400' : 'text-muted-foreground'}>{a.matched ? '✓' : '✗'}</span><span>{a.label}</span>{a.mandatory ? <Badge variant='secondary' className='text-[9px]'>must</Badge> : null}</div>))}
                </div> : null}
              </div>
            </Card>
          </>)}
        </div>
      </div>
    </div>
  );
}

function ContentPanel() {
  const [pages, setPages] = React.useState<any[] | null>(null);
  const [services, setServices] = React.useState<any[] | null>(null);
  const [doc, setDoc] = React.useState<any>(null);
  const [locale, setLocale] = React.useState<'en' | 'ar'>('en');
  const [busy, setBusy] = React.useState('');
  const [msg, setMsg] = React.useState('');
  const [err, setErr] = React.useState('');
  const [newSvc, setNewSvc] = React.useState('');
  const load = React.useCallback(() => { osPages('pages_list').then((r: any) => setPages(r?.rows || [])).catch((e: any) => setErr(e.message)); osPages('service_list').then((r: any) => setServices(r?.rows || [])).catch(() => { }); }, []);
  React.useEffect(() => { load(); }, [load]);
  const openPage = async (source: string, slug: string, loc: 'en' | 'ar') => { setBusy('open'); setErr(''); setMsg(''); try { const d: any = await osPages('page_get', { source, slug, locale: loc }); setDoc({ source, slug, title: d?.title || '', html: d?.html || '' }); setLocale(loc); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const savePage = async () => { if (!doc) return; setBusy('save'); setErr(''); try { await osPages('page_save', { source: doc.source, slug: doc.slug, locale, title: doc.title, html: doc.html }); setMsg('Saved as draft — click Publish to go live'); setTimeout(() => setMsg(''), 2500); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const translate = async () => { if (!doc) return; setBusy('tr'); setErr(''); try { await osPages('translate', { source: doc.source, slug: doc.slug }); setMsg('Arabic regenerated from English — open the AR tab to review'); setTimeout(() => setMsg(''), 3000); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const genService = async () => { if (!newSvc.trim()) return; setBusy('gen'); setErr(''); try { const r: any = await osPages('service_generate', { name: newSvc.trim() }); setMsg(r?.note || 'Queued — it will appear shortly'); setNewSvc(''); setTimeout(load, 5000); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const delService = async (slug: string) => { if (typeof window !== 'undefined' && !window.confirm('Delete service page "' + slug + '"?')) return; setBusy('del' + slug); try { await osPages('service_delete', { slug }); load(); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const publish = async () => { if (typeof window !== 'undefined' && !window.confirm('Publish all saved content changes to the LIVE site now?')) return; setBusy('pub'); setErr(''); try { await osPages('publish'); setMsg('Publishing to the live site — this can take a minute'); setTimeout(() => setMsg(''), 4000); } catch (e: any) { setErr(e.message); } setBusy(''); };
  if (doc) {
    return (
      <div className='space-y-4'>
        <div className='flex flex-wrap items-center gap-2'>
          <button type='button' className='text-xs text-primary underline' onClick={() => setDoc(null)}>← Back</button>
          <Newspaper className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>{doc.source} · {doc.slug}</h1>
          <div className='ml-auto flex items-center gap-1'>
            <button type='button' onClick={() => openPage(doc.source, doc.slug, 'en')} className={cn('h-7 px-3 text-xs rounded-md', locale === 'en' ? 'bg-primary text-primary-foreground' : 'bg-muted')}>EN</button>
            <button type='button' onClick={() => openPage(doc.source, doc.slug, 'ar')} className={cn('h-7 px-3 text-xs rounded-md', locale === 'ar' ? 'bg-primary text-primary-foreground' : 'bg-muted')}>AR</button>
          </div>
        </div>
        {(msg || err) ? <div className={cn('text-xs', err ? 'text-destructive' : 'text-emerald-400')}>{err || msg}</div> : null}
        <Card className='p-3 space-y-2'>
          <Input value={doc.title} onChange={(e) => setDoc({ ...doc, title: e.target.value })} placeholder='Page title' className='text-sm' />
          <textarea value={doc.html} onChange={(e) => setDoc({ ...doc, html: e.target.value })} rows={20} dir={locale === 'ar' ? 'rtl' : 'ltr'} className='w-full rounded-md border border-border bg-background/60 p-2 text-sm font-mono' />
          <div className='flex items-center gap-2'>
            <Button className='h-8 text-xs' disabled={busy === 'save'} onClick={savePage}>{busy === 'save' ? 'Saving…' : 'Save draft'}</Button>
            {locale === 'en' ? <Button variant='outline' className='h-8 text-xs' disabled={busy === 'tr'} onClick={translate}>{busy === 'tr' ? 'Translating…' : 'Regenerate Arabic'}</Button> : null}
            <Button variant='outline' className='h-8 text-xs ml-auto' disabled={busy === 'pub'} onClick={publish}>{busy === 'pub' ? 'Publishing…' : 'Publish to live site'}</Button>
          </div>
        </Card>
      </div>
    );
  }
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'><Newspaper className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Content</h1><span className='text-xs text-muted-foreground md:ml-2'>Edit site pages and service landing pages, then publish to the live site. Changes are audit-logged.</span>
        <Button className='h-8 text-xs ml-auto' disabled={busy === 'pub'} onClick={publish}>{busy === 'pub' ? 'Publishing…' : 'Publish to live site'}</Button>
      </div>
      {(msg || err) ? <div className={cn('text-xs', err ? 'text-destructive' : 'text-emerald-400')}>{err || msg}</div> : null}
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Site pages</div>
        <div className='overflow-auto max-h-[360px]'>
          {!pages ? <div className='p-3 text-sm text-muted-foreground'>Loading…</div> : pages.length === 0 ? <div className='p-3 text-sm text-muted-foreground'>No editable pages.</div> : pages.map((p: any, i: number) => (
            <div key={i} className='flex items-center gap-2 px-4 py-2 border-b border-border/40'>
              <div className='flex-1 min-w-0'><div className='text-sm font-medium truncate'>{deEnt(p.title)}</div><div className='text-[11px] text-muted-foreground'>{p.source} · {p.slug}{p.has_ar ? ' · EN+AR' : ' · EN only'}</div></div>
              <Button variant='outline' className='h-7 text-xs' onClick={() => openPage(p.source, p.slug, 'en')}>Edit</Button>
            </div>
          ))}
        </div>
      </Card>
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex flex-wrap items-center gap-2'>Service pages
          <div className='ml-auto flex items-center gap-2'><Input value={newSvc} onChange={(e) => setNewSvc(e.target.value)} placeholder='New service name…' className='h-7 w-48 text-xs' /><Button className='h-7 text-xs' disabled={busy === 'gen' || !newSvc.trim()} onClick={genService}>{busy === 'gen' ? 'Generating…' : 'Generate'}</Button></div>
        </div>
        <div className='overflow-auto max-h-[360px]'>
          {!services ? <div className='p-3 text-sm text-muted-foreground'>Loading…</div> : services.length === 0 ? <div className='p-3 text-sm text-muted-foreground'>No service pages yet.</div> : services.map((s: any, i: number) => (
            <div key={i} className='flex items-center gap-2 px-4 py-2 border-b border-border/40'>
              <div className='flex-1 min-w-0'><div className='text-sm font-medium truncate'>{deEnt(s.title)}</div><div className='text-[11px] text-muted-foreground'>{s.slug}{s.has_ar ? ' · EN+AR' : ' · EN only'}</div></div>
              <button type='button' className='text-xs text-destructive underline' disabled={busy === 'del' + s.slug} onClick={() => delService(s.slug)}>delete</button>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

function HealthPanel({ onNav }: { onNav: (id: string) => void }) {
  const [h, setH] = React.useState<any>(null);
  const [rec, setRec] = React.useState<any>(null);
  const [err, setErr] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const load = React.useCallback(() => { setBusy(true); setErr(''); Promise.all([osHealth('health'), osHealth('reconcile')]).then(([a, b]: any) => { setH(a); setRec(b); }).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  if (err && !h) return <Card className='p-6 text-sm text-destructive'>Could not load system health: {err}</Card>;
  if (!h) return <div className='text-muted-foreground text-sm'>Loading system health…</div>;
  const ok = h.overall === 'healthy';
  const kv = (label: string, val: any, nav?: string) => (<div onClick={nav ? () => onNav(nav) : undefined} className={cn('flex justify-between text-sm py-1 border-b border-border/30', nav && 'cursor-pointer hover:text-primary')}><span className='text-muted-foreground'>{label}</span><span className='font-medium inline-flex items-center gap-1'>{val}{nav ? <ArrowUpRight className='h-3 w-3 opacity-50' /> : null}</span></div>);
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'><Activity className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>System Health</h1>
        <Badge className={cn('ml-1', ok ? 'bg-emerald-500/20 text-emerald-400' : 'bg-amber-500/20 text-amber-400')}>{ok ? 'All healthy' : 'Needs attention'}</Badge>
        <Button variant='outline' className='h-8 text-xs ml-auto' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button>
      </div>
      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Operations</div>
          <div className='p-4'>
            {kv('Failing scheduled jobs (24h)', (h.failing_crons || []).length, 'automation')}
            {kv('Agent errors (24h)', h.agent_errors_24h, 'agents')}
            {kv('Health-check failures (24h)', h.health_check_fails_24h)}
            {kv('AI health failures', h.ai_health_fails)}
            {(h.failing_crons || []).length ? <div className='mt-3 space-y-1'>{(h.failing_crons || []).map((c: any, i: number) => (<button key={i} onClick={() => onNav('automation')} title='Manage in Automation' className='block w-full text-left text-xs text-destructive hover:underline'>{c.job}: {c.message || c.status}</button>))}</div> : null}
            {(h.top_error_agents || []).length ? <div className='mt-3'><div className='text-xs text-muted-foreground mb-1'>Top error sources (24h)</div>{(h.top_error_agents || []).map((a: any, i: number) => (<div key={i} className='text-xs flex justify-between'><span>{a.agent}</span><span className='text-muted-foreground'>{a.errors}</span></div>))}</div> : null}
          </div>
        </Card>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Money reconciliation</div>
          <div className='p-4'>
            {rec ? (<>
              {kv('Reveal transactions', rec.transactions_total)}
              {kv('Revenue — reveal fees (AED)', rec.revenue_reveal_fees_aed)}
              {kv('Refunds pending', rec.refunds_pending, 'refunds')}
              {kv('Refunds resolved', rec.refunds_resolved)}
              {kv('Stripe events recorded', rec.stripe_events_total)}
              {kv('Stripe paid checkouts', rec.stripe_paid_checkouts)}
              {kv('Ledger balanced', rec.gl_balanced === null ? 'n/a' : (rec.gl_balanced ? 'Yes' : 'NO — review'))}
            </>) : <div className='text-sm text-muted-foreground'>Loading…</div>}
          </div>
        </Card>
      </div>
      <div className='text-[11px] text-muted-foreground'>Snapshot at {h.generated_at ? new Date(h.generated_at).toLocaleString() : ''}. Read-only.</div>
    </div>
  );
}

function SupportPanel() {
  const [tab, setTab] = React.useState<'help' | 'incidents' | 'runbooks'>('help');
  const [incidents, setIncidents] = React.useState<any[] | null>(null);
  const [runbooks, setRunbooks] = React.useState<any[] | null>(null);
  const [openRb, setOpenRb] = React.useState<string>('');
  const [form, setForm] = React.useState<any>({ title: '', kind: 'bug', severity: 'medium', description: '' });
  const [busy, setBusy] = React.useState('');
  const [msg, setMsg] = React.useState('');
  const [err, setErr] = React.useState('');
  const loadInc = React.useCallback(() => { osIncidents('list').then((r: any) => setIncidents(r?.incidents || [])).catch((e: any) => setErr(e.message)); }, []);
  const loadRb = React.useCallback(() => { osIncidents('runbooks').then((r: any) => setRunbooks(r?.runbooks || [])).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { loadInc(); loadRb(); }, [loadInc, loadRb]);
  const submit = async () => { if (!form.title.trim()) { setErr('Please add a short title'); return; } setBusy('open'); setErr(''); setMsg(''); try { const r: any = await osIncidents('open', form); if (r && r.ok === false) setErr(r.error); else { setMsg('Reported — the founder has been notified. Reference #' + (r?.id || '')); setForm({ title: '', kind: 'bug', severity: 'medium', description: '' }); loadInc(); setTab('incidents'); } } catch (e: any) { setErr(e.message); } setBusy(''); };
  const resolve = async (id: number) => { const res = typeof window !== 'undefined' ? window.prompt('Resolution note (optional):', '') : ''; if (res === null) return; setBusy('res' + id); try { await osIncidents('resolve', { id, resolution: res || '' }); loadInc(); } catch (e: any) { setErr(e.message); } setBusy(''); };
  const openInc = (incidents || []).filter((x) => x.status === 'open').length;
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'><LifeBuoy className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Support</h1><span className='text-xs text-muted-foreground md:ml-2'>Report a problem, track incidents, and follow a runbook when something goes wrong.</span></div>
      <div className='flex items-center gap-1'>
        {(['help', 'incidents', 'runbooks'] as const).map((t) => (<button key={t} type='button' onClick={() => setTab(t)} className={cn('h-8 px-3 text-xs rounded-md', tab === t ? 'bg-primary text-primary-foreground' : 'bg-muted')}>{t === 'help' ? 'Get help' : t === 'incidents' ? ('Incidents' + (openInc ? ' (' + openInc + ')' : '')) : 'Runbooks'}</button>))}
      </div>
      {(msg || err) ? <div className={cn('text-xs', err ? 'text-destructive' : 'text-emerald-400')}>{err || msg}</div> : null}
      {tab === 'help' ? (
        <Card className='p-4 space-y-3 max-w-2xl'>
          <div className='text-sm text-muted-foreground'>Describe what went wrong. This opens an incident and notifies the founder right away. For common problems, check Runbooks first — many can be fixed from the OS without help.</div>
          <Input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder='Short title (e.g. Checkout not working)' className='text-sm' />
          <div className='flex flex-wrap gap-2'>
            <select value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })} className='h-9 rounded-md border border-border bg-background text-xs px-2'><option value='bug'>Something is broken</option><option value='payment'>Payment / money</option><option value='data'>Data looks wrong</option><option value='access'>Access / login</option><option value='other'>Other</option></select>
            <select value={form.severity} onChange={(e) => setForm({ ...form, severity: e.target.value })} className='h-9 rounded-md border border-border bg-background text-xs px-2'><option value='low'>Low</option><option value='medium'>Medium</option><option value='high'>High / urgent</option></select>
          </div>
          <textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={5} placeholder='What happened? Include any reference numbers, names, or error messages you saw.' className='w-full rounded-md border border-border bg-background/60 p-2 text-sm' />
          <Button className='h-9 text-sm' disabled={busy === 'open'} onClick={submit}>{busy === 'open' ? 'Reporting…' : 'Report & notify founder'}</Button>
        </Card>
      ) : null}
      {tab === 'incidents' ? (
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Incidents</div>
          <div className='overflow-auto max-h-[560px]'>
            {!incidents ? <div className='p-3 text-sm text-muted-foreground'>Loading…</div> : incidents.length === 0 ? <div className='p-4 text-sm text-muted-foreground'>No incidents. Everything is running smoothly.</div> : incidents.map((x: any) => (
              <div key={x.id} className='px-4 py-3 border-b border-border/40'>
                <div className='flex flex-wrap items-center gap-2'>
                  <Badge variant='secondary' className={cn('text-[10px]', x.severity === 'high' ? 'bg-destructive/20 text-destructive' : '')}>{x.severity}</Badge>
                  <span className='text-sm font-medium'>#{x.id} {x.title}</span>
                  <Badge variant='secondary' className={cn('text-[10px] ml-1', x.status === 'open' ? 'bg-amber-500/20 text-amber-400' : 'bg-emerald-500/20 text-emerald-400')}>{x.status}</Badge>
                  {x.status === 'open' ? <button type='button' className='text-xs text-primary underline ml-auto' disabled={busy === 'res' + x.id} onClick={() => resolve(x.id)}>Mark resolved</button> : null}
                </div>
                {x.description ? <div className='text-xs text-muted-foreground mt-1'>{x.description}</div> : null}
                <div className='text-[10px] text-muted-foreground/60 mt-1'>{x.kind} · by {x.opened_by} · {x.opened_at ? new Date(x.opened_at).toLocaleString() : ''}{x.resolution ? ' · resolved: ' + x.resolution : ''}</div>
              </div>
            ))}
          </div>
        </Card>
      ) : null}
      {tab === 'runbooks' ? (
        <div className='space-y-2'>
          {!runbooks ? <div className='text-sm text-muted-foreground'>Loading…</div> : runbooks.map((r: any) => (
            <Card key={r.slug} className='overflow-hidden'>
              <button type='button' className='w-full text-left px-4 py-3 flex items-center gap-2' onClick={() => setOpenRb(openRb === r.slug ? '' : r.slug)}>
                <Badge variant='secondary' className='text-[10px]'>{r.category}</Badge><span className='text-sm font-medium'>{r.title}</span><span className='ml-auto text-muted-foreground text-xs'>{openRb === r.slug ? '−' : '+'}</span>
              </button>
              {openRb === r.slug ? <div className='px-4 pb-3 space-y-2'><div className='text-xs text-muted-foreground'><span className='font-medium text-foreground'>When: </span>{r.when_to_use}</div><div className='text-sm whitespace-pre-line'>{r.steps}</div></div> : null}
            </Card>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function LoginCard({ onDone }: { onDone: (e: string) => void }) {
  const [em, setEm] = React.useState(''); const [code, setCode] = React.useState(''); const [sent, setSent] = React.useState(false); const [busy, setBusy] = React.useState(false); const [err, setErr] = React.useState('');
  const send = async () => { setBusy(true); setErr(''); const { error } = await supa.auth.signInWithOtp({ email: em.trim().toLowerCase(), options: { shouldCreateUser: false } }); setBusy(false); if (error) setErr(error.message); else setSent(true); };
  const verify = async () => { setBusy(true); setErr(''); const { data, error } = await supa.auth.verifyOtp({ email: em.trim().toLowerCase(), token: code.trim(), type: 'email' }); setBusy(false); if (error) setErr(error.message); else onDone(data.user?.email || em); };
  return (
    <div className='osx dark min-h-screen grid place-items-center p-4'>
      <Card className='w-full max-w-sm p-6'>
        <div className='flex items-center gap-2 mb-4'><div className='h-8 w-8 rounded-lg bg-primary text-primary-foreground grid place-items-center font-extrabold'>Q</div><div className='font-bold text-lg'>QuotesDone OS</div></div>
        <p className='text-sm text-muted-foreground mb-4'>Admin sign-in. We email you a one-time code.</p>
        {!sent ? (<>
          <Input placeholder='you@quotesdone.com' value={em} onChange={(e) => setEm(e.target.value)} />
          <Button className='w-full mt-3' disabled={busy || !em} onClick={send}>{busy ? 'Sending…' : 'Send code'}</Button>
        </>) : (<>
          <Input placeholder='6-digit code' value={code} onChange={(e) => setCode(e.target.value)} />
          <Button className='w-full mt-3' disabled={busy || !code} onClick={verify}>{busy ? 'Verifying…' : 'Verify & enter'}</Button>
          <button className='text-xs text-muted-foreground mt-3 underline' onClick={() => setSent(false)}>Use a different email</button>
        </>)}
        {err ? <div className='text-sm text-destructive mt-3'>{err}</div> : null}
      </Card>
    </div>
  );
}

const INTAKE_SAMPLE = {
  url: 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/demo-assets/intake-sample.mp3',
  file: 'Recording (2).m4a',
  channel: 'Customer intake — voice note',
  duration: 19.8,
  lang: 'ar',
  transcript_ar: 'أوكي، أنا محتاج أسوّي صوفة تكون تفصيل. الصوفة تكون معمولة من الأكريليك وفيها فرش بعد. تقدر تسويها؟',
  transcript_en: 'Okay, I need a custom-made sofa. The sofa should be made of acrylic and it has upholstery too. Can you make it?',
  brief: {
    category: 'custom-furniture',
    trades: ['custom-furniture', 'acrylic', 'upholstery'],
    urgency: 'normal',
    status: 'ready',
    readiness: 68,
    summary: 'Custom-made acrylic sofa with upholstered seating',
    scope: 'Design and fabricate one bespoke sofa with an acrylic (plexiglass) frame and upholstered cushions.',
    quantity: '1 sofa',
    emirate: '',
    timeline: '',
    budget: '',
    details: { item: 'sofa', material: 'acrylic', upholstery: true, custom_made: true },
    missing: ['emirate', 'dimensions', 'fabric / colour', 'budget', 'timeline'],
    provenance: { item: 'stated', material: 'stated', upholstery: 'stated', custom_made: 'stated' },
  },
};

function IntakeAudio() {
  const S = INTAKE_SAMPLE;
  const audioRef = React.useRef<HTMLAudioElement | null>(null);
  const canvasRef = React.useRef<HTMLCanvasElement | null>(null);
  const peaksRef = React.useRef<number[] | null>(null);
  const [playing, setPlaying] = React.useState(false);
  const [cur, setCur] = React.useState(0);
  const [dur, setDur] = React.useState(S.duration || 0);
  const [wfErr, setWfErr] = React.useState('');
  const [copied, setCopied] = React.useState(false);
  const draw = React.useCallback(() => {
    const cv = canvasRef.current; if (!cv) return; const ctx = cv.getContext('2d'); if (!ctx) return;
    const w = cv.width, h = cv.height; ctx.clearRect(0, 0, w, h);
    const css = getComputedStyle(document.documentElement);
    const prim = 'hsl(' + ((css.getPropertyValue('--primary') || '173 80% 40%').trim()) + ')';
    const mut = 'hsl(' + ((css.getPropertyValue('--muted-foreground') || '215 16% 47%').trim()) + ')';
    const peaks = peaksRef.current; const ratio = dur > 0 ? cur / dur : 0;
    if (!peaks) { ctx.fillStyle = mut; ctx.globalAlpha = 0.3; ctx.fillRect(0, h / 2 - 1, w, 2); ctx.globalAlpha = 1; return; }
    const n = peaks.length; const bw = w / n;
    for (let i = 0; i < n; i++) { const p = Math.max(0.03, peaks[i]); const bh = p * (h * 0.9); const x = i * bw; const y = (h - bh) / 2; ctx.fillStyle = (i / n) <= ratio ? prim : mut; ctx.globalAlpha = (i / n) <= ratio ? 1 : 0.35; ctx.fillRect(x, y, Math.max(1, bw * 0.6), bh); }
    ctx.globalAlpha = 1;
  }, [cur, dur]);
  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const resp = await fetch(S.url); const ab = await resp.arrayBuffer();
        const AC: any = (window as any).AudioContext || (window as any).webkitAudioContext; const acx = new AC();
        const buf = await acx.decodeAudioData(ab.slice(0));
        const ch = buf.getChannelData(0); const N = 120; const block = Math.floor(ch.length / N) || 1; const peaks: number[] = []; let max = 0.0001;
        for (let i = 0; i < N; i++) { let s = 0; for (let j = 0; j < block; j++) { const v = ch[i * block + j] || 0; s += v * v; } const rms = Math.sqrt(s / block); peaks.push(rms); if (rms > max) max = rms; }
        const norm = peaks.map((p) => p / max);
        if (!cancelled) { peaksRef.current = norm; setDur(buf.duration || S.duration); draw(); }
        try { acx.close(); } catch (_e) { /* */ }
      } catch (_e) { if (!cancelled) setWfErr('waveform_unavailable'); }
    })();
    return () => { cancelled = true; };
  }, []);
  React.useEffect(() => { draw(); }, [cur, dur, draw]);
  const toggle = () => { const a = audioRef.current; if (!a) return; if (a.paused) { a.play(); setPlaying(true); } else { a.pause(); setPlaying(false); } };
  const onSeek = (e: any) => { const cv = canvasRef.current, a = audioRef.current; if (!cv || !a || !dur) return; const rect = cv.getBoundingClientRect(); const r = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)); a.currentTime = r * dur; setCur(r * dur); };
  const mmss = (t: number) => { t = Math.max(0, Math.floor(t || 0)); return Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0'); };
  const copyJson = async () => { try { await navigator.clipboard.writeText(JSON.stringify(S.brief, null, 2)); setCopied(true); setTimeout(() => setCopied(false), 1500); } catch (_e) { /* */ } };
  return (<div className='space-y-4'>
    <div className='flex items-center justify-between flex-wrap gap-2'>
      <div><div className='text-lg font-semibold'>Intake Audio Inspector</div><div className='text-xs text-muted-foreground'>Voice intake — waveform, transcript and the structured brief the engine extracted.</div></div>
      <span className='text-[11px] px-2 py-0.5 rounded-full bg-secondary text-muted-foreground'>Demo sample</span>
    </div>
    <Card className='p-4'>
      <div className='flex items-center justify-between flex-wrap gap-2 mb-3'>
        <div className='text-sm font-medium flex items-center gap-2'><AudioLines className='h-4 w-4 text-primary' />{S.file}</div>
        <div className='flex items-center gap-2 text-xs text-muted-foreground'><span>{S.channel}</span><span className='px-1.5 py-0.5 rounded bg-secondary uppercase'>{S.lang}</span></div>
      </div>
      <div className='flex items-center gap-3'>
        <Button size='sm' variant='secondary' onClick={toggle} className='shrink-0'>{playing ? 'Pause' : 'Play'}</Button>
        <canvas ref={canvasRef} width={900} height={72} onClick={onSeek} className='w-full h-[72px] rounded-md bg-secondary/40 cursor-pointer' />
      </div>
      <div className='flex justify-between text-[11px] text-muted-foreground mt-1'><span>{mmss(cur)}</span>{wfErr ? <span>Waveform unavailable — playback still works</span> : <span />}<span>{mmss(dur)}</span></div>
      <audio ref={audioRef} src={S.url} preload='metadata' onTimeUpdate={(e: any) => setCur(e.target.currentTime)} onEnded={() => setPlaying(false)} onLoadedMetadata={(e: any) => setDur(e.target.duration || S.duration)} className='hidden' />
    </Card>
    <div className='grid md:grid-cols-2 gap-4'>
      <Card className='p-4'>
        <div className='text-sm font-semibold mb-2'>Transcript</div>
        <div dir='rtl' className='text-sm leading-7 mb-3'>{S.transcript_ar}</div>
        <div className='text-xs text-muted-foreground leading-6 border-t border-border pt-2'>{S.transcript_en}</div>
      </Card>
      <Card className='p-4'>
        <div className='flex items-center justify-between mb-2'><div className='text-sm font-semibold'>Extracted brief (JSON)</div><Button size='sm' variant='ghost' className='h-7 text-xs' onClick={copyJson}>{copied ? 'Copied' : 'Copy'}</Button></div>
        <pre className='text-[11px] leading-5 overflow-auto max-h-72 bg-secondary/40 rounded-md p-3'>{JSON.stringify(S.brief, null, 2)}</pre>
      </Card>
    </div>
    <Card className='p-4'>
      <div className='text-sm font-semibold mb-2'>Summary</div>
      <div className='grid sm:grid-cols-2 gap-x-6 gap-y-1 text-sm'>
        <div className='flex justify-between border-b border-border/60 py-1'><span className='text-muted-foreground'>Category</span><span className='capitalize'>{S.brief.category}</span></div>
        <div className='flex justify-between border-b border-border/60 py-1'><span className='text-muted-foreground'>Trades</span><span>{S.brief.trades.join(', ')}</span></div>
        <div className='flex justify-between border-b border-border/60 py-1'><span className='text-muted-foreground'>Urgency</span><span className='capitalize'>{S.brief.urgency}</span></div>
        <div className='flex justify-between border-b border-border/60 py-1'><span className='text-muted-foreground'>Readiness</span><span>{S.brief.readiness}%</span></div>
        <div className='flex justify-between border-b border-border/60 py-1 sm:col-span-2'><span className='text-muted-foreground'>Still missing</span><span className='text-right'>{S.brief.missing.join(', ')}</span></div>
      </div>
    </Card>
  </div>);
}

function AuditLog() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState('');
  React.useEffect(() => { osOps('audit_log', { limit: 200 }).then(setD).catch((e) => setErr(e.message)); }, []);
  if (err) return <Card className='p-6 text-sm text-destructive'>Could not load audit log: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading audit log…</div>;
  const rows = d.rows || [];
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'><ScrollText className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Audit log</h1></div>
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Recent actions<Badge variant='secondary'>{rows.length}</Badge></div>
        <div className='overflow-auto max-h-[620px]'>
          <table className='w-full text-sm'>
            <thead><tr className='text-left text-xs text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>When</th><th className='px-4 py-2 font-medium'>Actor</th><th className='px-4 py-2 font-medium'>Action</th><th className='px-4 py-2 font-medium'>Entity</th><th className='px-4 py-2 font-medium'>Detail</th></tr></thead>
            <tbody>{rows.map((r: any, i: number) => (<tr key={i} className='border-b border-border/40'><td className='px-4 py-2 whitespace-nowrap text-xs text-muted-foreground'>{r.at ? new Date(r.at).toLocaleString() : ''}</td><td className='px-4 py-2'>{r.actor}</td><td className='px-4 py-2'>{r.action}</td><td className='px-4 py-2 text-xs'>{r.entity}{r.entity_id ? ' #' + r.entity_id : ''}</td><td className='px-4 py-2 text-xs text-muted-foreground max-w-md truncate'>{fmt(r.detail)}</td></tr>))}</tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}

function Knowledge() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState('');
  const load = React.useCallback(() => { setD(null); osApi('ws.knowledge').then(setD).catch((e) => setErr(e.message)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const fill = async (cat: string, label: string) => { setBusy(cat); setErr(''); try { const { data: { session } } = await supa.auth.getSession(); const r = await fetch(SUPA_URL + '/functions/v1/kb_fill_gap', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (session?.access_token || '') }, body: JSON.stringify({ category: cat, label }) }); const jd = await r.json().catch(() => ({})); if (!r.ok || jd?.error) throw new Error(jd?.error || ('HTTP ' + r.status)); load(); } catch (e: any) { setErr('Fill failed: ' + (e?.message || '')); } setBusy(''); };
  const genReport = async () => { setBusy('__report'); setErr(''); try { const { data: { session } } = await supa.auth.getSession(); const r = await fetch(SUPA_URL + '/functions/v1/agent_learnings_report', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (session?.access_token || '') }, body: JSON.stringify({}) }); const jd = await r.json().catch(() => ({})); if (!r.ok || jd?.error || !jd?.url) throw new Error(jd?.error || ('HTTP ' + r.status)); window.open(jd.url, '_blank'); } catch (e: any) { setErr('Report failed: ' + (e?.message || '')); } setBusy(''); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load knowledge: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading knowledge…</div>;
  const ck = d.coverage_kpis || {}; const rows = d.coverage || [];
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'><BookOpen className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Knowledge coverage</h1><Button className='h-8 text-xs ml-auto' variant='outline' disabled={busy === '__report'} onClick={genReport}>{busy === '__report' ? 'Generating…' : 'Weekly learnings PDF'}</Button></div>
      {err ? <div className='text-xs text-destructive'>{err}</div> : null}
      <div className='grid grid-cols-2 md:grid-cols-4 gap-3'>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Covered</div><div className='text-2xl font-bold mt-1 text-emerald-300'>{fmt(ck.covered ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Thin</div><div className='text-2xl font-bold mt-1 text-amber-300'>{fmt(ck.thin ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Gaps</div><div className='text-2xl font-bold mt-1 text-red-300'>{fmt(ck.gaps ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Service categories</div><div className='text-2xl font-bold mt-1'>{fmt(ck.total ?? 0)}</div></Card>
      </div>
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Coverage by category<Badge variant='secondary'>{rows.length}</Badge></div>
        <div className='overflow-auto max-h-[560px]'>
          <table className='w-full text-sm'>
            <thead><tr className='text-left text-xs text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Category</th><th className='px-4 py-2 font-medium'>Chunks</th><th className='px-4 py-2 font-medium'>Status</th><th className='px-4 py-2 font-medium'></th></tr></thead>
            <tbody>{rows.map((r: any) => (
              <tr key={r.category} className='border-b border-border/40'>
                <td className='px-4 py-2.5'>{r.label || titleCase(r.category)}</td>
                <td className='px-4 py-2.5'>{fmt(r.chunks)}</td>
                <td className='px-4 py-2.5'><Badge variant={r.status === 'covered' ? 'outline' : 'secondary'}>{r.status}</Badge></td>
                <td className='px-4 py-2.5 text-right'>{r.status !== 'covered' ? <Button className='h-7 text-xs' disabled={busy === r.category} onClick={() => fill(r.category, r.label || r.category)}>{busy === r.category ? 'Generating…' : 'Fill gap'}</Button> : null}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      </Card>
      <div className='text-xs text-muted-foreground'>The curator generates UAE-specific trade knowledge (scope, regulations, pricing, red flags) and ingests it; embeddings compute automatically within a minute.</div>
    </div>
  );
}

function NotificationsBell({ pulse, onNav }: { pulse: number; onNav: (id: string) => void }) {
  const [items, setItems] = React.useState<any[]>([]); const [open, setOpen] = React.useState(false);
  React.useEffect(() => { let alive = true; osApi('ws.exec').then((d: any) => { if (alive) setItems(((d && d.notifications) || []).slice(0, 30)); }).catch(() => {}); return () => { alive = false; }; }, [pulse]);
  const routeFor = (t: string) => { const s = String(t); return /finance|payment|invoice/.test(s) ? 'finance' : /uptime|site|governance|security/.test(s) ? 'governance' : /ops|error|operation/.test(s) ? 'operations' : 'escalations'; };
  const count = items.length;
  return (
    <>
      <button onClick={() => setOpen(true)} title='Notifications' className='relative flex items-center justify-center h-9 w-9 rounded-md border border-border hover:bg-foreground/5'>
        <Bell className='h-4 w-4' />
        {count ? <span className='absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-bold grid place-items-center'>{count > 99 ? '99+' : count}</span> : null}
      </button>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent className='osx dark w-full sm:max-w-md overflow-y-auto'>
          <SheetHeader><SheetTitle>Notifications</SheetTitle><SheetDescription>Recent founder alerts & reminders</SheetDescription></SheetHeader>
          <div className='mt-4 divide-y divide-border'>
            {items.length ? items.map((n: any, i: number) => (
              <button key={i} onClick={() => { setOpen(false); onNav(routeFor(n.type)); }} className='w-full text-left py-3 hover:bg-foreground/5 transition-colors flex items-start gap-3'>
                <span className='mt-1 h-2 w-2 rounded-full bg-primary shrink-0'></span>
                <div className='min-w-0'><div className='text-sm font-medium'>{n.subject || titleCase(String(n.type || 'notification'))}</div><div className='text-xs text-muted-foreground'>{titleCase(String(n.type || ''))} · {new Date(n.created_at).toLocaleString()}</div></div>
              </button>
            )) : <div className='py-6 text-sm text-muted-foreground'>No notifications right now.</div>}
          </div>
        </SheetContent>
      </Sheet>
    </>
  );
}

function AgentStatus({ onOpen }: { onOpen: () => void }) {
  const [k, setK] = React.useState<any>(null);
  React.useEffect(() => {
    let alive = true;
    const load = () => osApi('ws.agents').then((d: any) => { if (alive) setK((d && d.kpis) || null); }).catch(() => {});
    load(); const t = setInterval(load, 60000);
    return () => { alive = false; clearInterval(t); };
  }, []);
  if (!k) return null;
  return (
    <button onClick={onOpen} title='Open Smart Engine' className='hidden md:flex items-center gap-2 rounded-md border border-border px-3 h-9 text-xs hover:bg-foreground/5'>
      <span className='relative flex h-2 w-2'><span className='animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-60'></span><span className='relative inline-flex rounded-full h-2 w-2 bg-primary'></span></span>
      <span className='font-semibold'>{fmt(k.agents ?? 0)}</span><span className='text-muted-foreground'>agents</span>
      <span className='text-muted-foreground'>·</span>
      <span className='font-semibold'>{fmt(k.runs_24h ?? 0)}</span><span className='text-muted-foreground'>runs/24h</span>
    </button>
  );
}

function PipelineTracker({ onNav }: { onNav: (id: string) => void }) {
  const [counts, setCounts] = React.useState<Record<string, number>>({});
  React.useEffect(() => { osApi('dashboard').then((d: any) => { const p = d?.pipeline || d?.stages || d?.command?.pipeline || {}; setCounts(p || {}); }).catch(() => {}); }, []);
  return (
    <div className='hidden lg:flex items-center'>
      {PIPELINE.map(([key, label], i) => (
        <div key={key} className='flex items-center'>
          <button onClick={() => onNav('rfqs')} title={'View ' + label + ' RFQs'} className='flex items-center gap-1.5 rounded-md px-2.5 py-1 bg-foreground/5 text-xs hover:bg-foreground/10 transition-colors'>
            <span className='text-muted-foreground'>{label}</span>
            <span className='font-semibold text-foreground'>{counts[key] ?? 0}</span>
          </button>
          {i < PIPELINE.length - 1 ? <span className='mx-1 text-muted-foreground/50'>›</span> : null}
        </div>
      ))}
    </div>
  );
}

function Console() {
  const [msgs, setMsgs] = React.useState<{ role: string; content: string }[]>([]);
  const [text, setText] = React.useState(''); const [atts, setAtts] = React.useState<{ name: string; text: string }[]>([]); const [busy, setBusy] = React.useState(false); const [confirm, setConfirm] = React.useState<{ token: string; reply: string } | null>(null);
  const endRef = React.useRef<HTMLDivElement>(null);
  React.useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [msgs, busy]);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const onFile = async (f: File) => { const rd = new FileReader(); rd.onload = async () => { try { const d = await osApi('extract_doc', { filename: f.name, mime: f.type, b64: String(rd.result || '') }); if (d?.ok && d.text) setAtts((a) => [...a, { name: f.name, text: d.text }]); } catch (_e) {} }; rd.readAsDataURL(f); };
  const send = async () => {
    const t = text.trim(); const a = atts.slice(); if (!t && !a.length) return; setText(''); setAtts([]); setConfirm(null);
    const shown = t + (a.length ? '  [' + a.map((x) => x.name).join(', ') + ']' : '');
    setMsgs((m) => [...m, { role: 'user', content: shown }]); setBusy(true);
    try {
      const hist = [...msgs].slice(-8);
      const d = await osApi('secretary_chat', { message: t || 'Please handle the attached document.', history: hist, attachments: a });
      setMsgs((m) => [...m, { role: 'assistant', content: d?.reply || 'Done.' }]);
      if (d?.needs_confirmation && d?.confirm_token) setConfirm({ token: d.confirm_token, reply: d.reply || '' });
    } catch (e: any) { setMsgs((m) => [...m, { role: 'assistant', content: 'Error: ' + (e?.message || 'could not reach the Secretary') }]); }
    setBusy(false);
  };
  const decide = async (decision: string) => { if (!confirm) return; const tok = confirm.token; setConfirm(null); setBusy(true); try { const d = await osApi('secretary_chat', { confirm_token: tok, decision }); setMsgs((m) => [...m, { role: 'assistant', content: d?.reply || (decision === 'confirm' ? 'Done.' : 'Cancelled.') }]); } catch (_e) { setMsgs((m) => [...m, { role: 'assistant', content: 'Could not complete that.' }]); } setBusy(false); };
  return (
    <Card className='flex flex-col h-[calc(100vh-140px)]'>
      <div className='px-5 py-3 border-b border-border flex items-center gap-2'><div className='h-8 w-8 rounded-lg bg-primary text-primary-foreground grid place-items-center font-bold'>✦</div><div><div className='font-semibold text-sm'>Command Console</div><div className='text-xs text-muted-foreground'>Instruct the Secretary — it acts across the team.</div></div></div>
      <div className='flex-1 overflow-auto p-4 space-y-3'>
        {!msgs.length ? <div className='text-sm text-muted-foreground'>Ask for a status, approve a supplier, draft content, log a finance entry, or attach an invoice and tell me what to do with it.</div> : null}
        {msgs.map((m, i) => (<div key={i} className={cn('max-w-[80%] rounded-xl px-3.5 py-2.5 text-sm whitespace-pre-wrap', m.role === 'user' ? 'ml-auto bg-primary text-primary-foreground' : 'bg-foreground/5')}>{m.content}</div>))}
        {busy ? <div className='text-sm text-muted-foreground'>…</div> : null}
        {confirm ? <div className='flex gap-2'><Button size='sm' onClick={() => decide('confirm')}>Confirm</Button><Button size='sm' variant='outline' onClick={() => decide('cancel')}>Cancel</Button></div> : null}
        <div ref={endRef} />
      </div>
      {atts.length ? <div className='px-4 flex flex-wrap gap-1.5'>{atts.map((a, i) => (<Badge key={i} variant='secondary' className='cursor-pointer' onClick={() => setAtts((x) => x.filter((_, j) => j !== i))}>📄 {a.name} ✕</Badge>))}</div> : null}
      <div className='p-3 border-t border-border flex items-end gap-2'>
        <input ref={fileRef} type='file' accept='image/*,application/pdf' className='hidden' onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f); e.currentTarget.value = ''; }} />
        <Button variant='outline' size='icon' onClick={() => fileRef.current?.click()}><Paperclip className='h-4 w-4' /></Button>
        <textarea value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); send(); } }} rows={2} placeholder='Type an instruction… (⌘+Enter to send)' className='flex-1 resize-none rounded-md border border-input bg-transparent px-3 py-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' />
        <Button onClick={send} disabled={busy}><Send className='h-4 w-4' /></Button>
      </div>
    </Card>
  );
}

// ── Lightweight SVG charts (dependency-free) ──────────────────────────
const CHART_COLORS = ['hsl(173 80% 36%)', 'hsl(210 90% 56%)', 'hsl(38 92% 50%)', 'hsl(261 60% 58%)', 'hsl(340 72% 55%)', 'hsl(150 55% 42%)', 'hsl(200 80% 45%)', 'hsl(20 85% 55%)', 'hsl(280 55% 55%)'];
function HBars({ rows, onBar }: { rows: { label: string; n: number }[]; onBar?: (r: any) => void }) {
  const max = Math.max(1, ...rows.map((r) => r.n));
  if (!rows.length) return <div className='text-xs text-muted-foreground'>No data yet.</div>;
  return (<div className='space-y-2.5'>{rows.map((r, i) => (
    <div key={i} onClick={onBar ? () => onBar(r) : undefined} className={cn('group', onBar && 'cursor-pointer')}>
      <div className='flex items-center justify-between text-xs mb-1'><span className='truncate capitalize text-foreground/80'>{r.label}</span><span className='tabular-nums text-muted-foreground ml-2'>{r.n.toLocaleString()}</span></div>
      <div className='h-2.5 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full transition-all group-hover:brightness-110' style={{ width: Math.max(2, (r.n / max) * 100) + '%', background: CHART_COLORS[i % CHART_COLORS.length] }} /></div>
    </div>))}</div>);
}
function Funnel({ rows, onStage }: { rows: { stage: string; n: number }[]; onStage?: (r: any) => void }) {
  const max = Math.max(1, ...rows.map((r) => r.n));
  return (<div className='space-y-1.5'>{rows.map((r, i) => { const w = Math.max(4, (r.n / max) * 100); const prev = i > 0 ? rows[i - 1].n : r.n; const conv = prev > 0 ? Math.round((r.n / prev) * 100) : 0; return (
    <div key={i} onClick={onStage ? () => onStage(r) : undefined} className={cn('flex items-center gap-3', onStage && 'cursor-pointer')}>
      <div className='w-20 sm:w-24 shrink-0 text-xs text-foreground/80 text-right'>{r.stage}</div>
      <div className='flex-1 h-7 rounded-md bg-foreground/[0.06] overflow-hidden'>
        <div className='h-full rounded-md flex items-center px-2 text-[11px] font-semibold text-white transition-all min-w-[2.5rem]' style={{ width: w + '%', background: CHART_COLORS[0], opacity: 1 - i * 0.09 }}>{r.n.toLocaleString()}</div>
      </div>
      <div className='w-9 shrink-0 text-[11px] text-muted-foreground text-right tabular-nums'>{i > 0 ? conv + '%' : ''}</div>
    </div>); })}</div>);
}
function AreaSpark({ data, height = 72 }: { data: { d: string; n: number }[]; height?: number }) {
  const w = 600, h = height, pad = 8; const max = Math.max(1, ...data.map((p) => p.n)); const n = data.length || 1;
  const x = (i: number) => pad + (i * (w - 2 * pad)) / Math.max(1, n - 1);
  const y = (v: number) => h - pad - (v / max) * (h - 2 * pad);
  const line = data.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.n).toFixed(1)}`).join(' ');
  const area = `${line} L${x(n - 1).toFixed(1)},${h - pad} L${x(0).toFixed(1)},${h - pad} Z`;
  const peak = data.reduce((a, p, i) => (p.n > data[a].n ? i : a), 0);
  return (<div>
    <svg viewBox={`0 0 ${w} ${h}`} className='w-full' style={{ height }} preserveAspectRatio='none'>
      <defs><linearGradient id='ag' x1='0' y1='0' x2='0' y2='1'><stop offset='0%' stopColor={CHART_COLORS[0]} stopOpacity='0.35' /><stop offset='100%' stopColor={CHART_COLORS[0]} stopOpacity='0' /></linearGradient></defs>
      <path d={area} fill='url(#ag)' />
      <path d={line} fill='none' stroke={CHART_COLORS[0]} strokeWidth='2' vectorEffect='non-scaling-stroke' />
    </svg>
    <div className='flex justify-between text-[10px] text-muted-foreground mt-1'>{data.filter((_, i) => i % Math.ceil(n / 5) === 0 || i === n - 1).map((p, i) => <span key={i}>{p.d}</span>)}</div>
    {data[peak] && data[peak].n > 0 ? <div className='text-[11px] text-muted-foreground mt-1'>Peak: <span className='text-foreground font-medium'>{data[peak].n}</span> on {data[peak].d}</div> : null}
  </div>);
}
function StatTile({ label, value, hint, onClick }: { label: string; value: any; hint?: string; onClick?: () => void }) {
  return (<Card onClick={onClick} className={cn('p-4', onClick && 'cursor-pointer hover:border-primary/60 transition-colors')}>
    <div className='text-xs text-muted-foreground flex items-center gap-1'>{label}{onClick ? <ArrowUpRight className='h-3 w-3 opacity-40' /> : null}</div>
    <div className='text-2xl font-bold mt-1 tabular-nums'>{fmt(value)}</div>
    {hint ? <div className='text-[11px] text-muted-foreground mt-0.5'>{hint}</div> : null}
  </Card>);
}

function Overview({ onNav }: { onNav: (id: string) => void }) {
  const [v, setV] = React.useState<any>(null); const [health, setHealth] = React.useState<any>({}); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const load = React.useCallback(() => { setBusy(true); setErr(''); Promise.all([osApi('viz'), osApi('ws.exec').catch(() => null)]).then(([viz, exec]: any) => { setV(viz); setHealth((exec && exec.command && exec.command.health) || {}); }).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  if (err && !v) return <Card className='p-6 text-sm text-destructive'>Could not load command center: {err}</Card>;
  if (!v) return <div className='text-muted-foreground text-sm'>Loading command center…</div>;
  const H = v.headline || {}; const band = String(health.band || 'unknown');
  const bandColor = /crit|down|bad|fail/.test(band) ? 'border-red-500/40 text-red-600' : /attention|warn|risk|watch/.test(band) ? 'border-amber-500/40 text-amber-600' : /ok|good|healthy|strong/.test(band) ? 'border-emerald-500/40 text-emerald-600' : 'border-border text-muted-foreground';
  const pipeline = (v.pipeline || []) as { stage: string; n: number }[]; const pipelineLive = pipeline.some((p) => p.n > 0);
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'>
        <LayoutDashboard className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Command Center</h1>
        <span className='text-xs text-muted-foreground ml-1'>Live business picture</span>
        <Button variant='outline' className='h-8 text-xs ml-auto' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button>
      </div>

      <Card onClick={() => onNav('health')} className={cn('p-4 flex items-center justify-between gap-4 border cursor-pointer hover:brightness-[1.02] transition-all', bandColor)}>
        <div><div className='text-[11px] uppercase tracking-wide opacity-70'>Business health</div><div className='text-2xl font-bold mt-0.5'>{health.index ?? '—'}<span className='text-sm font-normal opacity-70'> / 100 · {titleCase(band)}</span></div></div>
        <div className='flex items-center gap-2 max-w-md'><div className='text-xs opacity-80 text-right'>{health.note || 'Live signals across revenue, uptime, disputes and activity.'}</div><ArrowUpRight className='h-4 w-4 shrink-0 opacity-60' /></div>
      </Card>

      <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3'>
        <StatTile label='Suppliers sourced' value={H.suppliers_total} onClick={() => onNav('suppliers')} />
        <StatTile label='Invited' value={H.invited_total} hint='invite campaign' onClick={() => onNav('suppliers')} />
        <StatTile label='Registered' value={H.registered_total} onClick={() => onNav('suppliers')} />
        <StatTile label='Verified' value={H.verified_total} onClick={() => onNav('suppliers')} />
        <StatTile label='Agents active (24h)' value={H.agents_active_24h} onClick={() => onNav('agents')} />
        <StatTile label='Agent runs (24h)' value={H.runs_24h} onClick={() => onNav('agents')} />
      </div>

      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Supplier onboarding funnel<span className='text-[11px] font-normal text-muted-foreground'>sourced → approved</span></div>
          <div className='p-4'><Funnel rows={v.funnel || []} onStage={() => onNav('suppliers')} /></div>
        </Card>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Supplier invites — last 14 days</div>
          <div className='p-4'><AreaSpark data={v.invites_14d || []} /><div className='text-[11px] text-muted-foreground mt-2'>Campaign is currently <span className='font-medium text-amber-600'>paused</span>. {H.invited_total || 0} suppliers invited in total.</div></div>
        </Card>
      </div>

      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Suppliers by sector</div>
          <div className='p-4'><HBars rows={(v.by_sector || []).slice(0, 8)} onBar={() => onNav('suppliers')} /></div>
        </Card>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Suppliers by emirate</div>
          <div className='p-4'><HBars rows={(v.by_emirate || []).slice(0, 8)} onBar={() => onNav('suppliers')} /></div>
        </Card>
      </div>

      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Busiest agents — last 24h{H.runs_failed_24h ? <span className='text-[11px] font-normal text-amber-600'>{H.runs_failed_24h} failed run{H.runs_failed_24h === 1 ? '' : 's'}</span> : <span className='text-[11px] font-normal text-muted-foreground'>{H.runs_24h || 0} runs across {H.agents_active_24h || 0} agents</span>}</div>
        <div className='p-4'><HBars rows={(v.agents_24h || []).slice(0, 8)} onBar={() => onNav('agents')} /></div>
      </Card>

      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Marketplace pipeline<span className='text-[11px] font-normal text-muted-foreground'>RFQ → won</span></div>
        <div className='p-4'>{pipelineLive ? <Funnel rows={pipeline} onStage={() => onNav('rfqs')} /> : <div className='text-sm text-muted-foreground'>No client requests yet — this pipeline fills once buyers start posting RFQs. Suppliers are being onboarded first.</div>}</div>
      </Card>

      <Card className='p-4'>
        <div className='text-sm font-semibold mb-3'>Quick access</div>
        <div className='grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2'>
          {([['rfqs', 'RFQs & Procurement', ArrowLeftRight], ['suppliers', 'Suppliers', Hammer], ['customers', 'Customers', Users], ['finance', 'Finance', DollarSign], ['escalations', 'Escalations', AlertTriangle], ['reports', 'Reports', FileBarChart], ['documents', 'Documents', FileText], ['health', 'System Health', Activity]] as [string, string, any][]).map(([id, label, Ic]) => (
            <button key={id} onClick={() => onNav(id)} className='flex items-center gap-2 rounded-md border border-border bg-card px-3 py-2.5 text-sm text-left hover:border-primary/60 hover:bg-foreground/5 transition-colors'>
              <Ic className='h-4 w-4 text-primary shrink-0' /><span className='truncate'>{label}</span>
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}

function Escalations({ onNav }: { onNav: (id: string) => void }) {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [sel, setSel] = React.useState<any>(null); const [draft, setDraft] = React.useState(''); const [busy, setBusy] = React.useState(false); const [msg, setMsg] = React.useState('');
  const load = React.useCallback(() => { setD(null); Promise.all([osApi('inbox').catch(() => null), osApi('ws.exec').catch(() => null)]).then(([inbox, exec]) => setD({ inbox, attention: (exec && exec.command && exec.command.attention) || [] })).catch((e) => setErr(e.message)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const openItem = (it: any) => { setSel(it); setDraft(it.draft || ''); setMsg(''); };
  const send = async () => { if (!sel) return; setBusy(true); setMsg(''); try { await osApi('inbox_send', { id: sel.id, body: draft }); setSel(null); load(); } catch (e: any) { setMsg('Could not send: ' + (e?.message || 'error')); } setBusy(false); };
  if (err) return <Card className='p-6 text-sm text-destructive'>Could not load escalations: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading escalations…</div>;
  const kpis = (d.inbox && d.inbox.kpis) || {}; const rows = (d.inbox && d.inbox.rows) || []; const attention = d.attention || [];
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'><AlertTriangle className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Escalations</h1></div>
      <div className='grid grid-cols-2 md:grid-cols-4 gap-3'>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Needs Review</div><div className='text-2xl font-bold mt-1'>{fmt(kpis.needs_review ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Untriaged</div><div className='text-2xl font-bold mt-1'>{fmt(kpis.untriaged ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Replied (7d)</div><div className='text-2xl font-bold mt-1'>{fmt(kpis.replied_7d ?? 0)}</div></Card>
        <Card className='p-4'><div className='text-xs text-muted-foreground'>Agent Holds</div><div className='text-2xl font-bold mt-1'>{fmt(attention.length)}</div></Card>
      </div>
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Inbox — awaiting your reply<Badge variant='secondary'>{rows.length}</Badge></div>
        {rows.length ? <div className='divide-y divide-border'>{rows.map((it: any) => (
          <button key={it.id} onClick={() => openItem(it)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors'>
            <div className='flex items-center justify-between gap-3'>
              <div className='min-w-0'><div className='text-sm font-medium truncate'>{it.subject || '(no subject)'}</div><div className='text-xs text-muted-foreground truncate'>{it.from_email} · {it.summary || ''}</div></div>
              {it.draft ? <Badge variant='secondary'>Draft ready</Badge> : <Badge variant='outline'>New</Badge>}
            </div>
          </button>
        ))}</div> : <div className='px-4 py-6 text-sm text-muted-foreground'>Nothing awaiting a reply right now.</div>}
      </Card>
      {attention.length ? <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Agent decisions held for review<Badge variant='secondary'>{attention.length}</Badge></div>
        <div className='divide-y divide-border'>{attention.map((a: any) => (
          <button key={a.id} onClick={() => onNav('agents')} title='Review in Smart Engine' className='w-full text-left px-4 py-3 flex items-center justify-between gap-3 hover:bg-foreground/5 transition-colors'>
            <div className='min-w-0'><div className='text-sm truncate'>{titleCase(String(a.kind || 'decision'))} · <span className='text-muted-foreground'>{a.actor}</span></div><div className='text-xs text-muted-foreground'>{a.decision} → {a.route_to}</div></div>
            <Badge variant='outline'>held</Badge>
          </button>
        ))}</div>
      </Card> : null}
      <Sheet open={!!sel} onOpenChange={(o) => { if (!o) setSel(null); }}>
        <SheetContent className='osx dark w-full sm:max-w-lg overflow-y-auto'>
          <SheetHeader><SheetTitle>{sel?.subject || 'Message'}</SheetTitle><SheetDescription>{sel?.from_email}</SheetDescription></SheetHeader>
          <div className='mt-4 space-y-4'>
            <div><div className='text-xs font-semibold text-muted-foreground mb-1'>Their message</div><div className='text-sm whitespace-pre-wrap rounded-md border border-border p-3 bg-foreground/5'>{sel?.body}</div></div>
            <div><div className='text-xs font-semibold text-muted-foreground mb-1'>Your reply (Smart Engine draft — edit before sending)</div><textarea value={draft} onChange={(e) => setDraft(e.target.value)} rows={8} className='w-full resize-none rounded-md border border-border bg-transparent p-3 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' /></div>
            {msg ? <div className='text-xs text-destructive'>{msg}</div> : null}
            <div className='flex gap-2'>
              <Button onClick={send} disabled={busy || !draft.trim()}><Send className='h-4 w-4 mr-1' />{busy ? 'Sending…' : 'Send reply'}</Button>
              <Button variant='outline' onClick={() => setSel(null)}>Cancel</Button>
            </div>
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}

// ── Zoho/Odoo-style navigable record drawer ─────────────────────────────
const REL_ENTITY: Record<string, string> = { quotes: 'quote', quote: 'quote', inquiries: 'rfq', rfqs: 'rfq', inquiry: 'rfq', customers: 'customer', customer: 'customer', suppliers: 'supplier', supplier: 'supplier', leads: 'supplier', tasks: 'task', task: 'task', agent_actions: 'agent_action', agent_action: 'agent_action' };
const WS_ENTITY: Record<string, string> = { supplier: 'ws.supplier', customer: 'ws.customer', rfq: 'ws.rfq' };
// Scalar foreign-key fields → the entity they point at (Zoho-style click-through on any *_id field).
const FK_ENTITY: Record<string, string> = { supplier_id: 'supplier', lead_id: 'supplier', supplier: 'supplier', customer_id: 'customer', customer: 'customer', buyer_id: 'customer', inquiry_id: 'rfq', rfq_id: 'rfq', inquiry: 'rfq', quote_id: 'quote', quote: 'quote', agent_action_id: 'agent_action', task_id: 'task' };
function singularWord(s: string) { return String(s).replace(/ies$/i, 'y').replace(/s$/i, ''); }

// Odoo-style "chatter": activity timeline + comments + AI ask, on real events.
function ActivityPanel({ entity, id }: { entity: string; id: any }) {
  const [items, setItems] = React.useState<any[] | null>(null);
  const [body, setBody] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const [ai, setAi] = React.useState(''); const [aiBusy, setAiBusy] = React.useState(false); const [aiOut, setAiOut] = React.useState('');
  const load = React.useCallback(() => { osApi('activity', { entity, id }).then((d: any) => setItems(Array.isArray(d) ? d : [])).catch(() => setItems([])); }, [entity, id]);
  React.useEffect(() => { load(); }, [load]);
  const addComment = async () => { const t = body.trim(); if (!t) return; setBusy(true); try { await osApi('comment_add', { entity, id, body: t }); setBody(''); load(); } catch (_e) { } setBusy(false); };
  const askAI = async () => { const q = ai.trim(); if (!q) return; setAiBusy(true); setAiOut(''); try { const d: any = await osApi('secretary_chat', { message: q + ' (regarding ' + entity + ' #' + id + ')' }); setAiOut(d?.reply || 'No response.'); } catch (e: any) { setAiOut('Error: ' + (e?.message || 'could not reach the assistant')); } setAiBusy(false); };
  const iconFor = (k: string) => k === 'comment' ? MessageSquare : k === 'agent' ? Sparkles : k === 'audit' ? ScrollText : Circle;
  return (
    <Card className='mt-4 overflow-hidden'>
      <div className='px-4 py-2.5 border-b border-border text-sm font-semibold flex items-center gap-2'><Activity className='h-4 w-4 text-primary' />Activity</div>
      <div className='p-4 space-y-4'>
        <div className='flex gap-2'>
          <textarea value={body} onChange={(e) => setBody(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) addComment(); }} rows={2} placeholder='Add a note… (⌘+Enter to post)' className='flex-1 resize-none rounded-md border border-border bg-transparent p-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' />
          <Button className='h-8 text-xs self-end' disabled={busy || !body.trim()} onClick={addComment}>{busy ? '…' : 'Post'}</Button>
        </div>
        <div className='rounded-md border border-primary/30 bg-primary/[0.04] p-2'>
          <div className='flex items-center gap-2'><Sparkles className='h-4 w-4 text-primary shrink-0' /><input value={ai} onChange={(e) => setAi(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') askAI(); }} placeholder='Ask AI about this record…' className='flex-1 bg-transparent text-sm outline-none' /><Button className='h-8 text-xs' variant='outline' disabled={aiBusy || !ai.trim()} onClick={askAI}>{aiBusy ? '…' : 'Ask'}</Button></div>
          {aiOut ? <div className='text-xs whitespace-pre-wrap mt-2 border-t border-border/50 pt-2'>{aiOut}</div> : null}
        </div>
        {items === null ? <div className='text-xs text-muted-foreground'>Loading activity…</div> : !items.length ? <div className='text-xs text-muted-foreground'>No activity recorded yet.</div> : (
          <div>{items.map((it: any, i: number) => { const I = iconFor(it.kind); return (
            <div key={i} className='flex gap-3 pb-3 last:pb-0'>
              <div className='flex flex-col items-center'><div className={cn('h-6 w-6 rounded-full grid place-items-center shrink-0', it.kind === 'comment' ? 'bg-primary/15 text-primary' : it.kind === 'agent' ? 'bg-violet-500/15 text-violet-600' : it.kind === 'milestone' ? 'bg-emerald-500/15 text-emerald-600' : 'bg-foreground/5 text-muted-foreground')}><I className='h-3 w-3' /></div>{i < items.length - 1 ? <div className='w-px flex-1 bg-border my-1' /> : null}</div>
              <div className='min-w-0 flex-1 -mt-0.5'>
                <div className='text-sm flex items-center gap-1.5 flex-wrap'><span className='font-medium capitalize'>{titleCase(String(it.title || it.kind))}</span>{it.status ? <Badge variant='outline' className='text-[10px]'>{it.status}</Badge> : null}</div>
                {it.body ? <div className='text-sm text-foreground/80 mt-0.5 whitespace-pre-wrap'>{it.body}</div> : null}
                <div className='text-[11px] text-muted-foreground mt-0.5'>{it.actor || 'system'} · {fmt(it.at)}</div>
              </div>
            </div>); })}</div>
        )}
      </div>
    </Card>
  );
}

function RecordDrawer({ frame0, actions, extra, reportId, onClose }: { frame0: any; actions?: any; extra?: any; reportId?: number; onClose: () => void }) {
  const [stack, setStack] = React.useState<any[]>([frame0]);
  const key0 = (frame0 && (String(frame0.entity) + ':' + String(frame0.id) + ':' + String(frame0.row && frame0.row.id))) || '';
  React.useEffect(() => { setStack([frame0]); }, [key0]); // eslint-disable-line react-hooks/exhaustive-deps
  const top = stack[stack.length - 1];
  const [data, setData] = React.useState<any>(null);
  const [files, setFiles] = React.useState<any[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [busyDoc, setBusyDoc] = React.useState('');
  React.useEffect(() => {
    let alive = true; setData(top.row || null); setFiles([]);
    const ent = top.entity, id = top.id;
    if (!ent || id == null) { setLoading(false); return; }
    setLoading(true);
    (async () => {
      const ws = WS_ENTITY[ent];
      const pP = ws ? osApi(ws, { id }).catch(() => null) : osApi('record', { entity: ent, id }).then((r: any) => (r && r.record !== undefined ? r.record : r)).catch(() => null);
      const fP = (ent === 'supplier' || ent === 'customer' || ent === 'rfq') ? osApi('files', { entity: ent, id }).catch(() => [] as any) : Promise.resolve([] as any);
      const [pd, fd] = await Promise.all([pP, fP]);
      if (!alive) return;
      setData(pd || top.row || null);
      setFiles(Array.isArray(fd) ? fd : (fd && Array.isArray(fd.data) ? fd.data : []));
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [top.entity, top.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const openDoc = async (doc: any) => { const dkey = doc.path || doc.url || doc.name || ''; setBusyDoc(dkey); try { let url = doc.url; if (!url && doc.path) { const r: any = await osApi('file', { bucket: doc.bucket || 'supplier-docs', path: doc.path }); url = r && r.url; } if (url && typeof window !== 'undefined') window.open(url, '_blank', 'noopener'); } catch (_e) { } setBusyDoc(''); };
  const openRelated = (k: string, r: any) => { const ent = REL_ENTITY[String(k).toLowerCase()]; const id = r.id ?? r.rfq_id ?? r.inquiry_id ?? r.quote_id ?? r.supplier_id ?? r.customer_id; setStack((s) => [...s, { entity: ent, id: ent ? id : undefined, title: singularWord(titleCase(k)) + (id != null ? ' #' + id : ''), row: r }]); };
  const openRef = (ent: string, id: any) => { if (!ent || id == null || id === '') return; setStack((s) => [...s, { entity: ent, id, title: singularWord(titleCase(ent)) + ' #' + id }]); };
  const rec = data && typeof data === 'object' && data.record !== undefined && data.record ? data.record : data;
  const scal: [string, any][] = []; const arrs: [string, any[]][] = [];
  const collect = (o: any) => { if (!o || typeof o !== 'object') return; for (const [k, v] of Object.entries(o)) { if (Array.isArray(v)) { if (v.length && typeof v[0] === 'object') arrs.push([k, v as any[]]); } else if (v && typeof v === 'object') { collect(v); } else scal.push([k, v]); } };
  collect(rec);
  // Zoho/Odoo-style: show only populated, meaningful fields — hide nulls, internal/vector/token columns, and huge blobs.
  const HIDE_KEY = /(^|_)(embedding|embedding_gte|body|claim_token|token|place_id|maps_url|emirates_id|owner_dob|password|secret|ip)$|embedding|_token$|_ip$/i;
  const scalShow = scal.filter(([k, v]) => v != null && v !== '' && !HIDE_KEY.test(String(k)) && !(typeof v === 'string' && v.length > 400) && !(typeof v === 'string' && /^\[\s*-?\d/.test(v.trim())));
  const grpFiles: Record<string, any[]> = {}; (files || []).forEach((f: any) => { const g = (f && f.group) || 'Documents'; (grpFiles[g] = grpFiles[g] || []).push(f); });
  return (
    <Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}>
      <SheetContent side='right' className='w-full sm:max-w-2xl overflow-y-auto'>
        <SheetHeader>
          {stack.length > 1 ? <div className='flex items-center gap-1.5 text-xs text-muted-foreground mb-1 flex-wrap'>{stack.map((f, i) => (<React.Fragment key={i}>{i > 0 ? <span>/</span> : null}<button type='button' className={cn(i === stack.length - 1 ? 'text-foreground font-medium' : 'hover:text-foreground underline')} onClick={() => setStack((s) => s.slice(0, i + 1))}>{f.title}</button></React.Fragment>))}</div> : null}
          <SheetTitle>{top.title}</SheetTitle>
          <SheetDescription>{(rec && (rec.company_name || rec.email || rec.summary || (rec.id != null ? 'ID ' + rec.id : ''))) || ''}</SheetDescription>
        </SheetHeader>
        {stack.length === 1 && actions ? <div className='mt-3 flex flex-wrap gap-2'>{actions}</div> : null}
        {stack.length === 1 && reportId ? <ReportViewer id={reportId} /> : null}
        {Object.keys(grpFiles).length ? <div className='mt-4 space-y-3'>{Object.entries(grpFiles).map(([g, fs]) => (
          <Card key={g} className='overflow-hidden'><div className='px-4 py-2.5 border-b border-border text-sm font-semibold flex items-center gap-2'><FileText className='h-4 w-4 text-primary' />{g}<Badge variant='secondary' className='ml-auto'>{fs.length}</Badge></div>
            <div className='p-2'>{fs.map((f: any, i: number) => (<div key={i} className='flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-foreground/5'><FileText className='h-4 w-4 text-muted-foreground shrink-0' /><span className='text-sm min-w-0 truncate'>{f.type || f.name}</span><Button className='h-7 text-xs ml-auto' variant='outline' disabled={busyDoc === (f.path || f.url || f.name)} onClick={() => openDoc(f)}>{busyDoc === (f.path || f.url || f.name) ? 'Opening…' : 'Open'}</Button></div>))}</div>
          </Card>))}</div> : null}
        {loading ? <div className='mt-4 text-sm text-muted-foreground'>Loading record…</div> : null}
        {scalShow.length ? <Card className='mt-4 overflow-hidden'><div className='px-4 py-2.5 border-b border-border text-sm font-semibold'>Details</div><div className='p-4 grid grid-cols-1 sm:grid-cols-2 gap-x-6'>{scalShow.map(([k, v], i) => { const fk = FK_ENTITY[String(k).toLowerCase()]; const linkable = !!fk && v != null && v !== '' && (typeof v === 'number' || typeof v === 'string') && !(fk === top.entity && String(v) === String(top.id)); return (<div key={k + i} className='flex flex-col py-1.5 border-b border-border/40 min-w-0'><span className='text-[11px] text-muted-foreground'>{titleCase(k)}</span>{linkable ? <button type='button' onClick={() => openRef(fk, v)} className='text-sm break-words text-primary hover:underline text-left inline-flex items-center gap-1'>{fmt(v)}<ArrowUpRight className='h-3 w-3 opacity-60' /></button> : <span className='text-sm break-words'>{fmt(v)}</span>}</div>); })}</div></Card> : null}
        {arrs.map(([k, rows], ai) => { const cols = Object.keys(rows[0]).filter((c) => !/^(id|uuid)$/i.test(c) && typeof (rows[0] as any)[c] !== 'object').slice(0, 4); return (
          <Card key={k + ai} className='mt-4 overflow-hidden'>
            <div className='px-4 py-2.5 border-b border-border text-sm font-semibold flex items-center justify-between'>{titleCase(k)}<Badge variant='secondary'>{rows.length}</Badge></div>
            <div className='overflow-auto max-h-72'><table className='w-full text-sm'><thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border'>{cols.map((c) => <th key={c} className='px-3 py-1.5 font-medium'>{titleCase(c)}</th>)}</tr></thead>
              <tbody>{rows.slice(0, 100).map((r: any, i: number) => (<tr key={i} onClick={() => openRelated(k, r)} className='border-b border-border/40 hover:bg-foreground/5 cursor-pointer'>{cols.map((c) => <td key={c} className='px-3 py-2'>{fmt(r[c])}</td>)}</tr>))}</tbody></table></div>
          </Card>); })}
        {stack.length === 1 && extra ? <div className='mt-4'>{extra}</div> : null}
        {top.entity && top.id != null && top.id !== '' ? <ActivityPanel entity={top.entity} id={top.id} /> : null}
        {!loading && !scalShow.length && !arrs.length && !Object.keys(grpFiles).length ? <div className='mt-4 text-sm text-muted-foreground'>No further detail available.</div> : null}
      </SheetContent>
    </Sheet>
  );
}

// ── Suppliers flagship: Odoo-style list + kanban board ────────────────
const SECTOR_PALETTE = ['#0d9488', '#3b82f6', '#f59e0b', '#8b5cf6', '#ef4444', '#10b981', '#0ea5e9', '#f97316', '#a855f7', '#14b8a6', '#e11d48', '#6366f1'];
function sectorColor(s: string) { const str = String(s || ''); let h = 0; for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) >>> 0; return SECTOR_PALETTE[h % SECTOR_PALETTE.length]; }
function Stars({ v }: { v: any }) { const r = Number(v) || 0; if (!r) return <span className='text-[11px] text-muted-foreground'>No rating</span>; const full = Math.round(r); return (<span className='inline-flex items-center gap-0.5 text-amber-500 text-xs' title={r.toFixed(1)}>{Array.from({ length: 5 }).map((_, i) => <span key={i} className={i < full ? '' : 'opacity-25'}>★</span>)}<span className='text-[11px] text-muted-foreground ml-1'>{r.toFixed(1)}</span></span>); }
function SectorPill({ s }: { s: string }) { const c = sectorColor(s); return (<span className='inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-full capitalize' style={{ background: c + '22', color: c }}><span className='h-1.5 w-1.5 rounded-full' style={{ background: c }} />{s}</span>); }
function StatusChips({ c }: { c: any }) { return (<>{c.approved ? <Badge className='bg-emerald-500/15 text-emerald-600 hover:bg-emerald-500/15 border-0 text-[10px]'>Approved</Badge> : null}{c.verified ? <Badge className='bg-blue-500/15 text-blue-600 hover:bg-blue-500/15 border-0 text-[10px]'>Verified</Badge> : null}{c.banned ? <Badge variant='destructive' className='text-[10px]'>Banned</Badge> : null}</>); }
const STAGE_COLOR: Record<string, string> = { sourced: '#64748b', contacted: '#3b82f6', invited: '#f59e0b', registered: '#8b5cf6', verified: '#14b8a6', approved: '#10b981' };
function initials(s: string) { const w = String(s || '?').replace(/[^A-Za-z؀-ۿ ]/g, '').trim().split(/\s+/); return ((w[0]?.[0] || '') + (w[1]?.[0] || '')).toUpperCase() || '#'; }

function SuppliersApp() {
  const [view, setView] = React.useState<'kanban' | 'list'>('kanban');
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const [q, setQ] = React.useState(''); const [sector, setSector] = React.useState('');
  const [row, setRow] = React.useState<any>(null); const [dbusy, setDbusy] = React.useState(false);
  const load = React.useCallback((search: string, sec: string) => { setBusy(true); setErr(''); osApi('suppliers_board', { search, sector: sec, limit: 80 }).then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load('', ''); }, [load]);
  const doSearch = () => load(q, sector);
  const pickSector = (s: string) => { const ns = sector === s ? '' : s; setSector(ns); load(q, ns); };
  const decide = async (id: any, op: string) => { setDbusy(true); try { await osOps('supplier_decide', { id, op, note: op === 'reject' ? 'Rejected from OS' : undefined }); setRow(null); load(q, sector); } catch (_e) { } setDbusy(false); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load suppliers: {err}</Card>;
  const stages = (d?.stages || []) as any[]; const rows = (d?.rows || []) as any[]; const sectors = (d?.sectors || []) as any[];
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'>
        <Hammer className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Suppliers</h1>
        <Badge variant='secondary'>{(d?.total ?? 0).toLocaleString()}</Badge>
        {busy ? <span className='text-[11px] text-muted-foreground'>updating…</span> : null}
        <div className='flex items-center gap-2 ml-auto'>
          <div className='relative'>
            <Search className='h-3.5 w-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none' />
            <Input value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') doSearch(); }} placeholder='Search company, sector, emirate…' className='h-9 w-64 pl-8' />
          </div>
          <div className='inline-flex rounded-md border border-border overflow-hidden'>
            <button title='Kanban board' onClick={() => setView('kanban')} className={cn('h-9 px-2.5 grid place-items-center', view === 'kanban' ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}><LayoutDashboard className='h-4 w-4' /></button>
            <button title='List' onClick={() => setView('list')} className={cn('h-9 px-2.5 grid place-items-center border-l border-border', view === 'list' ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}><ListChecks className='h-4 w-4' /></button>
          </div>
        </div>
      </div>
      {sectors.length ? <div className='flex flex-wrap gap-1.5'>{sectors.map((s: any) => (<button key={s.label} onClick={() => pickSector(s.label)} className={cn('text-[11px] px-2 py-1 rounded-full border transition-colors capitalize', sector === s.label ? 'bg-primary text-primary-foreground border-primary' : 'border-border hover:bg-foreground/5')}>{s.label} <span className='opacity-60'>{s.n}</span></button>))}</div> : null}

      {!d ? <div className='grid grid-cols-2 md:grid-cols-6 gap-3'>{Array.from({ length: 6 }).map((_, i) => <div key={i} className='h-48 rounded-lg bg-foreground/5 animate-pulse' />)}</div> : view === 'kanban' ? (
        <div className='flex gap-3 overflow-x-auto pb-2'>
          {stages.map((st: any) => (
            <div key={st.key} className='w-72 shrink-0 flex flex-col rounded-lg bg-foreground/[0.03] border border-border' style={{ borderTop: `3px solid ${STAGE_COLOR[st.key]}` }}>
              <div className='px-3 py-2 border-b border-border flex items-center justify-between'><span className='text-sm font-semibold'>{st.label}</span><Badge variant='secondary'>{st.count.toLocaleString()}</Badge></div>
              <div className='flex-1 overflow-y-auto p-2 space-y-2 max-h-[62vh] min-h-[120px]'>
                {(st.cards || []).map((c: any) => (
                  <button key={c.id} onClick={() => setRow(c)} className='w-full text-left bg-card rounded-lg border border-border p-3 hover:shadow-md hover:border-primary/40 transition-all'>
                    <div className='text-sm font-semibold leading-snug line-clamp-2'>{c.company_name}</div>
                    <div className='flex items-center gap-1.5 mt-1.5 flex-wrap'><SectorPill s={c.sector} /><span className='text-[11px] text-muted-foreground'>{c.emirate}</span></div>
                    <div className='flex items-center justify-between mt-2 gap-2'><Stars v={c.rating} /><div className='flex gap-1 flex-wrap justify-end'><StatusChips c={c} /></div></div>
                  </button>
                ))}
                {st.count > (st.cards?.length || 0) ? <div className='text-[11px] text-muted-foreground text-center py-1'>+{(st.count - (st.cards?.length || 0)).toLocaleString()} more</div> : null}
                {!st.cards?.length ? <div className='text-[11px] text-muted-foreground text-center py-6'>Empty</div> : null}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <Card className='overflow-hidden'>
          <div className='overflow-auto max-h-[70vh]'>
            <table className='w-full text-sm'>
              <thead><tr className='text-left text-xs text-muted-foreground border-b border-border sticky top-0 bg-card z-10'><th className='px-4 py-2.5 font-medium'>Company</th><th className='px-3 py-2.5 font-medium'>Sector</th><th className='px-3 py-2.5 font-medium'>Emirate</th><th className='px-3 py-2.5 font-medium'>Rating</th><th className='px-3 py-2.5 font-medium'>Stage</th><th className='px-3 py-2.5 font-medium'>Status</th></tr></thead>
              <tbody>{rows.map((c: any) => (
                <tr key={c.id} onClick={() => setRow(c)} className='border-b border-border/50 hover:bg-foreground/5 cursor-pointer'>
                  <td className='px-4 py-2.5'><div className='flex items-center gap-2.5'><div className='h-7 w-7 shrink-0 rounded-full grid place-items-center text-[10px] font-bold text-white' style={{ background: sectorColor(c.sector) }}>{initials(c.company_name)}</div><span className='font-medium line-clamp-1'>{c.company_name}</span></div></td>
                  <td className='px-3 py-2.5'><SectorPill s={c.sector} /></td>
                  <td className='px-3 py-2.5 text-muted-foreground whitespace-nowrap'>{c.emirate}</td>
                  <td className='px-3 py-2.5 whitespace-nowrap'><Stars v={c.rating} /></td>
                  <td className='px-3 py-2.5'><span className='inline-flex items-center gap-1.5 text-xs capitalize whitespace-nowrap'><span className='h-2 w-2 rounded-full' style={{ background: STAGE_COLOR[c.stage] }} />{c.stage}</span></td>
                  <td className='px-3 py-2.5'><div className='flex gap-1 flex-wrap'><StatusChips c={c} /></div></td>
                </tr>))}</tbody>
            </table>
          </div>
          {rows.length >= 80 ? <div className='px-4 py-2 text-[11px] text-muted-foreground border-t border-border'>Showing the most recent 80 of {(d?.total ?? 0).toLocaleString()} — search or pick a sector to narrow.</div> : null}
        </Card>
      )}

      {row ? <RecordDrawer frame0={{ entity: 'supplier', id: row.id, title: 'Supplier #' + row.id, row }}
        actions={<>
          <Button className='h-8 text-xs' variant='outline' disabled={dbusy} onClick={() => decide(row.id, 'approve')}>Approve</Button>
          <Button className='h-8 text-xs' variant='outline' disabled={dbusy} onClick={() => decide(row.id, 'reject')}>Reject</Button>
          <Button className='h-8 text-xs' variant='outline' disabled={dbusy} onClick={() => decide(row.id, row.banned ? 'unban' : 'ban')}>{row.banned ? 'Unban' : 'Ban'}</Button>
        </>}
        onClose={() => setRow(null)} /> : null}
    </div>
  );
}

// ── Generic board primitives (shared by RFQs / Customers / Smart Engine) ──
function KanbanBoard({ stages, colors, onCard, renderCard }: { stages: any[]; colors?: Record<string, string>; onCard: (c: any) => void; renderCard: (c: any) => React.ReactNode }) {
  return (<div className='flex gap-3 overflow-x-auto pb-2'>{(stages || []).map((st: any) => (
    <div key={st.key} className='w-72 shrink-0 flex flex-col rounded-lg bg-foreground/[0.03] border border-border' style={colors?.[st.key] ? { borderTop: '3px solid ' + colors[st.key] } : undefined}>
      <div className='px-3 py-2 border-b border-border flex items-center justify-between'><span className='text-sm font-semibold'>{st.label}</span><Badge variant='secondary'>{Number(st.count || 0).toLocaleString()}</Badge></div>
      <div className='flex-1 overflow-y-auto p-2 space-y-2 max-h-[62vh] min-h-[120px]'>
        {(st.cards || []).map((c: any, i: number) => (<button key={c.id ?? i} onClick={() => onCard(c)} className='w-full text-left bg-card rounded-lg border border-border p-3 hover:shadow-md hover:border-primary/40 transition-all'>{renderCard(c)}</button>))}
        {Number(st.count || 0) > (st.cards || []).length ? <div className='text-[11px] text-muted-foreground text-center py-1'>+{(Number(st.count) - (st.cards || []).length).toLocaleString()} more</div> : null}
        {!(st.cards || []).length ? <div className='text-[11px] text-muted-foreground text-center py-6'>Empty</div> : null}
      </div>
    </div>))}</div>);
}
function RichList({ rows, columns, onRow, footer }: { rows: any[]; columns: { key: string; label: string; render: (r: any) => React.ReactNode }[]; onRow: (r: any) => void; footer?: React.ReactNode }) {
  if (!rows.length) return <Card className='p-8 text-center text-sm text-muted-foreground'>Nothing to show yet.</Card>;
  return (<Card className='overflow-hidden'><div className='overflow-auto max-h-[70vh]'><table className='w-full text-sm'>
    <thead><tr className='text-left text-xs text-muted-foreground border-b border-border sticky top-0 bg-card z-10'>{columns.map((c) => (<th key={c.key} className='px-3 py-2.5 font-medium'>{c.label}</th>))}</tr></thead>
    <tbody>{rows.map((r, i) => (<tr key={r.id ?? i} onClick={() => onRow(r)} className='border-b border-border/50 hover:bg-foreground/5 cursor-pointer'>{columns.map((c) => (<td key={c.key} className='px-3 py-2.5'>{c.render(r)}</td>))}</tr>))}</tbody>
  </table></div>{footer}</Card>);
}
function BoardHeader({ icon: Icon, title, total, sub, view, setView, q, setQ, onSearch, right }: any) {
  return (<div className='flex flex-wrap items-center gap-2'>
    <Icon className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>{title}</h1>
    <Badge variant='secondary'>{Number(total || 0).toLocaleString()}</Badge>{sub ? <span className='text-[11px] text-muted-foreground'>{sub}</span> : null}
    <div className='flex items-center gap-2 ml-auto'>
      {onSearch ? <div className='relative'><Search className='h-3.5 w-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none' /><Input value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') onSearch(); }} placeholder='Search…' className='h-9 w-56 pl-8' /></div> : null}
      {view ? <div className='inline-flex rounded-md border border-border overflow-hidden'><button title='Board' onClick={() => setView('kanban')} className={cn('h-9 px-2.5 grid place-items-center', view === 'kanban' ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}><LayoutDashboard className='h-4 w-4' /></button><button title='List' onClick={() => setView('list')} className={cn('h-9 px-2.5 grid place-items-center border-l border-border', view === 'list' ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}><ListChecks className='h-4 w-4' /></button></div> : null}
      {right}
    </div>
  </div>);
}

const RFQ_COLOR: Record<string, string> = { new: '#64748b', matched: '#3b82f6', quoted: '#f59e0b', revealed: '#8b5cf6', won: '#10b981' };
function RfqApp() {
  const [view, setView] = React.useState<'kanban' | 'list'>('kanban'); const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [q, setQ] = React.useState(''); const [row, setRow] = React.useState<any>(null);
  const load = React.useCallback((s: string) => { osApi('rfq_board', { search: s, limit: 80 }).then(setD).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { load(''); }, [load]);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load RFQs: {err}</Card>;
  const card = (c: any) => (<><div className='text-sm font-semibold capitalize'>{c.category}</div>{c.summary ? <div className='text-xs text-muted-foreground line-clamp-2 mt-0.5'>{c.summary}</div> : null}<div className='flex items-center justify-between mt-2'><span className='text-[11px] text-muted-foreground'>{c.emirate}</span>{c.value ? <span className='text-xs font-medium'>AED {Number(c.value).toLocaleString()}</span> : c.budget ? <span className='text-[11px] text-muted-foreground'>{c.budget}</span> : null}</div></>);
  const columns = [{ key: 'category', label: 'Category', render: (r: any) => <span className='font-medium capitalize'>{r.category}</span> }, { key: 'summary', label: 'Summary', render: (r: any) => <span className='text-muted-foreground line-clamp-1'>{r.summary || '—'}</span> }, { key: 'emirate', label: 'Emirate', render: (r: any) => r.emirate }, { key: 'value', label: 'Value', render: (r: any) => r.value ? 'AED ' + Number(r.value).toLocaleString() : (r.budget || '—') }, { key: 'stage', label: 'Stage', render: (r: any) => <span className='capitalize'>{r.stage}</span> }];
  return (<div className='space-y-4'>
    <BoardHeader icon={ArrowLeftRight} title='RFQs & Procurement' total={d?.total} view={view} setView={setView} q={q} setQ={setQ} onSearch={() => load(q)} />
    {!d ? <div className='text-sm text-muted-foreground'>Loading…</div> : d.total === 0 ? (
      <Card className='p-6'><div className='text-center mb-4'><ArrowLeftRight className='h-8 w-8 text-muted-foreground/40 mx-auto mb-2' /><div className='text-sm font-medium'>No client requests yet</div><div className='text-xs text-muted-foreground mt-1'>The pipeline fills as buyers post RFQs — suppliers are being onboarded first. The stages below are ready.</div></div><KanbanBoard stages={d.stages || []} colors={RFQ_COLOR} onCard={() => { }} renderCard={() => null} /></Card>
    ) : view === 'kanban' ? <KanbanBoard stages={d.stages || []} colors={RFQ_COLOR} onCard={setRow} renderCard={card} /> : <RichList rows={d.rows || []} columns={columns} onRow={setRow} />}
    {row ? <RecordDrawer frame0={{ entity: 'rfq', id: row.id, title: 'RFQ #' + row.id, row }} onClose={() => setRow(null)} /> : null}
  </div>);
}

const CUST_COLOR: Record<string, string> = { new: '#64748b', verified: '#10b981', banned: '#ef4444' };
function CustomersApp() {
  const [view, setView] = React.useState<'kanban' | 'list'>('list'); const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [q, setQ] = React.useState(''); const [row, setRow] = React.useState<any>(null);
  const load = React.useCallback((s: string) => { osApi('customers_board', { search: s, limit: 80 }).then(setD).catch((e: any) => setErr(e.message)); }, []);
  React.useEffect(() => { load(''); }, [load]);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load customers: {err}</Card>;
  const card = (c: any) => (<><div className='text-sm font-semibold'>{c.full_name}</div><div className='text-xs text-muted-foreground truncate'>{c.email || c.phone || '—'}</div><div className='flex gap-1 mt-2'>{c.email_verified ? <Badge className='bg-emerald-500/15 text-emerald-600 hover:bg-emerald-500/15 border-0 text-[10px]'>Verified</Badge> : null}{c.banned ? <Badge variant='destructive' className='text-[10px]'>Banned</Badge> : null}</div></>);
  const columns = [{ key: 'full_name', label: 'Name', render: (r: any) => <span className='font-medium'>{r.full_name}</span> }, { key: 'email', label: 'Email', render: (r: any) => <span className='text-muted-foreground'>{r.email || '—'}</span> }, { key: 'phone', label: 'Phone', render: (r: any) => r.phone || '—' }, { key: 'email_verified', label: 'Verified', render: (r: any) => r.email_verified ? 'Yes' : 'No' }, { key: 'stage', label: 'Stage', render: (r: any) => <span className='capitalize'>{r.stage}</span> }];
  return (<div className='space-y-4'>
    <BoardHeader icon={Users} title='Customers' total={d?.total} view={view} setView={setView} q={q} setQ={setQ} onSearch={() => load(q)} />
    {!d ? <div className='text-sm text-muted-foreground'>Loading…</div> : d.total === 0 ? (
      <Card className='p-8 text-center'><Users className='h-8 w-8 text-muted-foreground/40 mx-auto mb-2' /><div className='text-sm font-medium'>No customers yet</div><div className='text-xs text-muted-foreground mt-1'>Buyers appear here once they sign up and post requests.</div></Card>
    ) : view === 'kanban' ? <KanbanBoard stages={d.stages || []} colors={CUST_COLOR} onCard={setRow} renderCard={card} /> : <RichList rows={d.rows || []} columns={columns} onRow={setRow} />}
    {row ? <RecordDrawer frame0={{ entity: 'customer', id: row.id, title: 'Customer ' + row.id, row }} onClose={() => setRow(null)} /> : null}
  </div>);
}

function AgentDrawer({ agent, onClose }: { agent: any; onClose: () => void }) {
  const [ops, setOps] = React.useState<any>(null);
  React.useEffect(() => { osApi('ws.agent', { key: agent.agent_key }).then(setOps).catch(() => setOps({})); }, [agent.agent_key]);
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-xl overflow-y-auto'>
    <SheetHeader><SheetTitle className='capitalize'>{titleCase(String(agent.agent_key))}</SheetTitle><SheetDescription>{agent.role || agent.department}</SheetDescription></SheetHeader>
    <div className='mt-3 grid grid-cols-3 gap-2'><StatTile label='Runs 24h' value={agent.runs24} /><StatTile label='Failures 24h' value={agent.fails24} /><StatTile label='Last status' value={agent.last_status || '—'} /></div>
    {ops === null ? <div className='mt-4 text-sm text-muted-foreground'>Loading agent operations…</div> : <Card className='mt-4 p-4'><ReadableObject data={ops || {}} /></Card>}
  </SheetContent></Sheet>);
}
function AgentsApp() {
  const [view, setView] = React.useState<'kanban' | 'list'>('kanban'); const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [sel, setSel] = React.useState<any>(null);
  React.useEffect(() => { osApi('agents_board').then(setD).catch((e: any) => setErr(e.message)); }, []);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Smart Engine: {err}</Card>;
  const card = (c: any) => (<><div className='flex items-center gap-1.5'><span className={cn('h-2 w-2 rounded-full', c.active ? 'bg-emerald-500' : 'bg-muted')} /><span className='text-sm font-semibold capitalize'>{titleCase(String(c.agent_key))}</span></div>{c.role ? <div className='text-xs text-muted-foreground line-clamp-2 mt-0.5'>{c.role}</div> : null}<div className='flex items-center gap-2 mt-2 flex-wrap'><span className='text-[11px] text-muted-foreground'>{c.runs24} runs/24h</span>{c.last_status ? <Badge variant='outline' className='text-[10px]'>{c.last_status}</Badge> : null}{c.fails24 > 0 ? <Badge variant='destructive' className='text-[10px]'>{c.fails24} failed</Badge> : null}</div></>);
  const columns = [{ key: 'agent_key', label: 'Agent', render: (r: any) => <span className='font-medium capitalize'>{titleCase(String(r.agent_key))}</span> }, { key: 'department', label: 'Dept', render: (r: any) => <span className='capitalize'>{r.department}</span> }, { key: 'role', label: 'Role', render: (r: any) => <span className='text-muted-foreground line-clamp-1'>{r.role || '—'}</span> }, { key: 'runs24', label: 'Runs 24h', render: (r: any) => r.runs24 }, { key: 'last_status', label: 'Last', render: (r: any) => r.last_status || '—' }];
  return (<div className='space-y-4'>
    <BoardHeader icon={Sparkles} title='Smart Engine' total={d?.total} sub={d ? (Number(d.runs24 || 0).toLocaleString() + ' runs/24h') : ''} view={view} setView={setView} />
    {!d ? <div className='text-sm text-muted-foreground'>Loading agents…</div> : view === 'kanban' ? <KanbanBoard stages={d.departments || []} onCard={setSel} renderCard={card} /> : <RichList rows={d.rows || []} columns={columns} onRow={setSel} />}
    {sel ? <AgentDrawer agent={sel} onClose={() => setSel(null)} /> : null}
  </div>);
}

// ── Finance — NetSuite-style portfolio ────────────────────────────────
function MiniLine({ data }: { data: { label: string; v: number }[] }) {
  const vals = data.map((p) => p.v); const min = Math.min(0, ...vals), max = Math.max(0, ...vals); const range = (max - min) || 1;
  const w = 600, h = 80, pad = 8; const n = data.length || 1;
  const x = (i: number) => pad + (i * (w - 2 * pad)) / Math.max(1, n - 1);
  const y = (v: number) => h - pad - ((v - min) / range) * (h - 2 * pad);
  const line = data.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ');
  const zeroY = y(0);
  return (<svg viewBox={`0 0 ${w} ${h}`} className='w-full' style={{ height: 80 }} preserveAspectRatio='none'>
    <line x1={pad} y1={zeroY} x2={w - pad} y2={zeroY} stroke='hsl(var(--border))' strokeWidth='1' vectorEffect='non-scaling-stroke' strokeDasharray='3 3' />
    <path d={line} fill='none' stroke={CHART_COLORS[0]} strokeWidth='2' vectorEffect='non-scaling-stroke' />
  </svg>);
}
const aed = (v: any) => { const n = Number(v); if (!isFinite(n)) return '—'; return (n < 0 ? '-' : '') + 'AED ' + Math.abs(n).toLocaleString(undefined, { maximumFractionDigits: 0 }); };
function FinanceApp() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const [glOpen, setGlOpen] = React.useState(false); const [glLines, setGlLines] = React.useState<any[]>([{ account: '', debit: '', credit: '', memo: '' }, { account: '', debit: '', credit: '', memo: '' }]); const [glMemo, setGlMemo] = React.useState(''); const [glDate, setGlDate] = React.useState(''); const [glMsg, setGlMsg] = React.useState(''); const [glBusy, setGlBusy] = React.useState(false);
  const [invOpen, setInvOpen] = React.useState(false); const [invBusy, setInvBusy] = React.useState(false); const [invMsg, setInvMsg] = React.useState('');
  const load = React.useCallback(() => { setBusy(true); setErr(''); osApi('ws.finance').then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const glTotals = () => glLines.reduce((a: any, l: any) => ({ dr: a.dr + (Number(l.debit) || 0), cr: a.cr + (Number(l.credit) || 0) }), { dr: 0, cr: 0 });
  const postGl = async () => { const lines = glLines.map((l: any) => ({ account: String(l.account || '').trim(), debit: Number(l.debit) || 0, credit: Number(l.credit) || 0, memo: l.memo || undefined })).filter((l: any) => l.account && (l.debit || l.credit)); const t = lines.reduce((a: any, l: any) => ({ dr: a.dr + l.debit, cr: a.cr + l.credit }), { dr: 0, cr: 0 }); if (lines.length < 2) { setGlMsg('Need at least two lines.'); return; } if (Math.round((t.dr - t.cr) * 100) !== 0) { setGlMsg('Out of balance: debits ' + t.dr + ' vs credits ' + t.cr); return; } setGlBusy(true); setGlMsg(''); try { await osOps('gl_post', { memo: glMemo || 'OS entry', date: glDate || undefined, lines }); setGlOpen(false); setGlLines([{ account: '', debit: '', credit: '', memo: '' }, { account: '', debit: '', credit: '', memo: '' }]); setGlMemo(''); setGlDate(''); load(); } catch (e: any) { setGlMsg('Post failed: ' + (e?.message || '')); } setGlBusy(false); };
  const onInvFile = async (f: File) => { setInvBusy(true); setInvMsg('Uploading & reading…'); try { const b64: string = await new Promise((res, rej) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result || '')); rd.onerror = rej; rd.readAsDataURL(f); }); const { data: { session } } = await supa.auth.getSession(); const r = await fetch(SUPA_URL + '/functions/v1/finance_doc', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (session?.access_token || '') }, body: JSON.stringify({ filename: f.name, mime: f.type, b64 }) }); const jd = await r.json().catch(() => ({})); if (!r.ok || jd?.error) throw new Error(jd?.error || ('HTTP ' + r.status)); if (jd.logged && jd.logged.ok) { setInvMsg('Logged: ' + (jd.parsed?.vendor || '') + ' — ' + (jd.parsed?.currency || 'AED') + ' ' + (jd.parsed?.amount || '') + '.'); load(); } else { setInvMsg('Stored the original; auto-posting skipped (amount unclear).'); } } catch (e: any) { setInvMsg('Failed: ' + (e?.message || '')); } setInvBusy(false); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load finance: {err}</Card>;
  const k = (d?.ai?.kpis) || {}; const pnl = (d?.pnl) || {}; const accounts = (d?.cash?.accounts) || []; const cashflow = (d?.cashflow) || []; const exp = (d?.expense_breakdown) || []; const trend = (d?.ai?.trend) || []; const horizons = (d?.ai?.forecast?.horizons) || [];
  const kv = (label: string, val: any, tone?: string) => (<div className='flex justify-between text-sm py-1.5 border-b border-border/40 last:border-0'><span className='text-muted-foreground'>{label}</span><span className={cn('font-medium tabular-nums', tone)}>{val}</span></div>);
  return (
    <div className='space-y-4'>
      <div className='flex flex-wrap items-center gap-2'>
        <DollarSign className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Finance</h1>
        <Badge className={cn('border-0', (d?.ai?.health ?? 0) >= 60 ? 'bg-emerald-500/15 text-emerald-600' : 'bg-amber-500/15 text-amber-600')}>Health {Math.round(Number(d?.ai?.health || 0))}/100</Badge>
        <div className='ml-auto flex gap-2'>
          <Button className='h-8 text-xs' variant='outline' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button>
          <Button className='h-8 text-xs' variant='outline' onClick={() => { setInvOpen(true); setInvMsg(''); }}>Log invoice (PDF)</Button>
          <Button className='h-8 text-xs' onClick={() => { setGlOpen(true); setGlMsg(''); }}>New journal entry</Button>
        </div>
      </div>

      {!d ? <div className='grid grid-cols-2 md:grid-cols-6 gap-3'>{Array.from({ length: 6 }).map((_, i) => <div key={i} className='h-20 rounded-lg bg-foreground/5 animate-pulse' />)}</div> : <>
        <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3'>
          <StatTile label='Cash position' value={aed(k.cash)} />
          <StatTile label='Net income (total)' value={aed(pnl.net_income)} />
          <StatTile label='Revenue (total)' value={aed(k.revenue_total)} />
          <StatTile label='Expenses (total)' value={aed(k.expense_total)} />
          <StatTile label='Monthly burn' value={aed(k.monthly_burn)} />
          <StatTile label='Runway' value={k.runway_months == null ? '—' : k.runway_months + ' mo'} />
        </div>

        <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
          <Card className='overflow-hidden'>
            <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Cash trend — last 14 days</div>
            <div className='p-4'>{trend.length ? <><MiniLine data={trend.map((p: any) => ({ label: p.d, v: Number(p.cash) }))} /><div className='flex justify-between text-[10px] text-muted-foreground mt-1'><span>{trend[0]?.d}</span><span>{trend[trend.length - 1]?.d}</span></div></> : <div className='text-xs text-muted-foreground'>No trend yet.</div>}</div>
          </Card>
          <Card className='overflow-hidden'>
            <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Cash forecast</div>
            <div className='p-4 grid grid-cols-3 gap-2'>{horizons.length ? horizons.map((h: any) => (<div key={h.days} className='rounded-md border border-border p-2.5'><div className='text-[11px] text-muted-foreground'>{h.days} days</div><div className={cn('text-base font-bold mt-0.5 tabular-nums', Number(h.projected_cash) < 0 ? 'text-amber-600' : '')}>{aed(h.projected_cash)}</div></div>)) : <div className='text-xs text-muted-foreground col-span-3'>No forecast.</div>}</div>
          </Card>
        </div>

        <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
          <Card className='overflow-hidden'>
            <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Chart of accounts</div>
            <div className='p-4'>{accounts.map((a: any) => kv(a.code + ' · ' + a.name, aed(a.balance), Number(a.balance) < 0 ? 'text-amber-600' : undefined))}</div>
          </Card>
          <Card className='overflow-hidden'>
            <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Expense breakdown</div>
            <div className='p-4'>{exp.length ? <HBars rows={exp.map((e: any) => ({ label: e.name, n: Number(e.amount) }))} /> : <div className='text-xs text-muted-foreground'>No expenses recorded.</div>}</div>
          </Card>
        </div>

        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Monthly cash flow</div>
          <div className='overflow-auto'><table className='w-full text-sm'><thead><tr className='text-left text-xs text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Month</th><th className='px-4 py-2 font-medium text-right'>Inflow</th><th className='px-4 py-2 font-medium text-right'>Outflow</th><th className='px-4 py-2 font-medium text-right'>Net</th></tr></thead>
            <tbody>{cashflow.map((c: any) => (<tr key={c.month} className='border-b border-border/40'><td className='px-4 py-2'>{c.month}</td><td className='px-4 py-2 text-right tabular-nums text-emerald-600'>{aed(c.inflow)}</td><td className='px-4 py-2 text-right tabular-nums'>{aed(c.outflow)}</td><td className={cn('px-4 py-2 text-right tabular-nums font-medium', Number(c.net) < 0 ? 'text-amber-600' : 'text-emerald-600')}>{aed(c.net)}</td></tr>))}</tbody></table></div>
        </Card>
      </>}

      <Sheet open={invOpen} onOpenChange={setInvOpen}><SheetContent side='right' className='w-full sm:max-w-md overflow-y-auto'><SheetHeader><SheetTitle>Log invoice from PDF</SheetTitle><SheetDescription>Stored, extracted, and posted to finance.</SheetDescription></SheetHeader><div className='mt-4 space-y-3'><input type='file' accept='.pdf,.png,.jpg,.jpeg,application/pdf,image/*' disabled={invBusy} onChange={(e) => { const f = e.target.files?.[0]; if (f) onInvFile(f); }} className='block w-full text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-primary file:text-primary-foreground file:px-3 file:py-1.5 file:text-xs' />{invMsg ? <div className='text-xs text-foreground/80 whitespace-pre-wrap'>{invMsg}</div> : null}</div></SheetContent></Sheet>
      <Sheet open={glOpen} onOpenChange={setGlOpen}><SheetContent side='right' className='w-full sm:max-w-lg overflow-y-auto'><SheetHeader><SheetTitle>New journal entry</SheetTitle><SheetDescription>Double-entry — debits must equal credits.</SheetDescription></SheetHeader><div className='mt-4 space-y-3'>
        <div className='flex gap-2'><input type='date' value={glDate} onChange={(e) => setGlDate(e.target.value)} className='rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Memo' value={glMemo} onChange={(e) => setGlMemo(e.target.value)} className='flex-1 rounded-md border border-border bg-transparent p-2 text-sm' /></div>
        <div className='space-y-2'>{glLines.map((l: any, i: number) => (<div key={i} className='flex gap-2'><input placeholder='Account code' value={l.account} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], account: e.target.value }; setGlLines(n); }} className='flex-1 rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Debit' inputMode='decimal' value={l.debit} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], debit: e.target.value }; setGlLines(n); }} className='w-24 rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Credit' inputMode='decimal' value={l.credit} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], credit: e.target.value }; setGlLines(n); }} className='w-24 rounded-md border border-border bg-transparent p-2 text-sm' /></div>))}</div>
        <div className='flex items-center justify-between text-xs text-muted-foreground'><button onClick={() => setGlLines([...glLines, { account: '', debit: '', credit: '', memo: '' }])} className='hover:text-foreground'>+ Add line</button><span>Debits {glTotals().dr.toFixed(2)} · Credits {glTotals().cr.toFixed(2)}</span></div>
        {glMsg ? <div className='text-xs text-destructive'>{glMsg}</div> : null}
        <div className='flex gap-2'><Button className='h-8 text-xs' disabled={glBusy} onClick={postGl}>{glBusy ? 'Posting…' : 'Post entry'}</Button><Button className='h-8 text-xs' variant='outline' onClick={() => setGlOpen(false)}>Cancel</Button></div>
      </div></SheetContent></Sheet>
    </div>
  );
}

function Workspace({ mod }: { mod: Mod }) {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [row, setRow] = React.useState<any>(null); const [rowTitle, setRowTitle] = React.useState(''); const [detail, setDetail] = React.useState<any>(null); const [dbusy, setDbusy] = React.useState(false); const [edit, setEdit] = React.useState<any>(null); const [editType, setEditType] = React.useState(''); const [ebusy, setEbusy] = React.useState(false); const [emsg, setEmsg] = React.useState(''); const [glOpen, setGlOpen] = React.useState(false); const [glLines, setGlLines] = React.useState<any[]>([{ account: '', debit: '', credit: '', memo: '' }, { account: '', debit: '', credit: '', memo: '' }]); const [glMemo, setGlMemo] = React.useState(''); const [glDate, setGlDate] = React.useState(''); const [glMsg, setGlMsg] = React.useState(''); const [glBusy, setGlBusy] = React.useState(false); const [invOpen, setInvOpen] = React.useState(false); const [invBusy, setInvBusy] = React.useState(false); const [invMsg, setInvMsg] = React.useState('');
  const reload = React.useCallback(() => { setD(null); setErr(''); osApi(mod.ws as string, mod.ws === 'ws.suppliers' ? { params: {} } : {}).then(setD).catch((e) => setErr(e.message)); }, [mod.ws]);
  React.useEffect(() => { reload(); }, [reload]);
  const decide = async (action: string, params: Record<string, any>) => { setDbusy(true); try { await osOps(action, params); setRow(null); setDetail(null); reload(); } catch (e: any) { setDetail({ error: e?.message || 'failed' }); } setDbusy(false); };
  const decideApi = async (action: string, params: Record<string, any>) => { setDbusy(true); try { await osApi(action, params); setRow(null); setDetail(null); reload(); } catch (e: any) { setDetail({ error: e?.message || 'failed' }); } setDbusy(false); };
  const editableType = (): string | null => { const r: any = row; if (!r) return null; if (r.agent && (r.recommendation !== undefined || r.escalation_reason !== undefined)) return 'agent_issue'; if (mod.id === 'reports') { if (r.body !== undefined) return 'board_report'; if (r.officer !== undefined) return 'exec_report'; if (r.summary !== undefined) return 'finance_report'; } if (r.severity !== undefined && r.subject !== undefined) return 'security_event'; return null; };
  const openEdit = async (type: string) => { setEbusy(true); setEmsg(''); try { const dd = await osOps('content_get', { type, id: (row as any).id }); setEditType(type); setEdit(dd); } catch (e: any) { setEmsg('Load failed: ' + (e?.message || '')); } setEbusy(false); };
  const saveEdit = async () => { if (!edit) return; setEbusy(true); setEmsg(''); try { const vals: any = { ...edit }; delete vals.id; await osOps('content_save', { type: editType, id: edit.id, values: vals }); setEdit(null); setRow(null); reload(); } catch (e: any) { setEmsg('Save failed: ' + (e?.message || '')); } setEbusy(false); };
  const glTotals = () => glLines.reduce((a: any, l: any) => ({ dr: a.dr + (Number(l.debit) || 0), cr: a.cr + (Number(l.credit) || 0) }), { dr: 0, cr: 0 });
  const postGl = async () => { const lines = glLines.map((l: any) => ({ account: String(l.account || '').trim(), debit: Number(l.debit) || 0, credit: Number(l.credit) || 0, memo: l.memo || undefined })).filter((l: any) => l.account && (l.debit || l.credit)); const t = lines.reduce((a: any, l: any) => ({ dr: a.dr + l.debit, cr: a.cr + l.credit }), { dr: 0, cr: 0 }); if (lines.length < 2) { setGlMsg('Need at least two lines.'); return; } if (Math.round((t.dr - t.cr) * 100) !== 0) { setGlMsg('Out of balance: debits ' + t.dr + ' vs credits ' + t.cr); return; } setGlBusy(true); setGlMsg(''); try { await osOps('gl_post', { memo: glMemo || 'OS entry', date: glDate || undefined, lines }); setGlOpen(false); setGlLines([{ account: '', debit: '', credit: '', memo: '' }, { account: '', debit: '', credit: '', memo: '' }]); setGlMemo(''); setGlDate(''); reload(); } catch (e: any) { setGlMsg('Post failed: ' + (e?.message || '')); } setGlBusy(false); };
  const onInvFile = async (f: File) => { setInvBusy(true); setInvMsg('Uploading & reading…'); try { const b64: string = await new Promise((res, rej) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result || '')); rd.onerror = rej; rd.readAsDataURL(f); }); const { data: { session } } = await supa.auth.getSession(); const r = await fetch(SUPA_URL + '/functions/v1/finance_doc', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (session?.access_token || '') }, body: JSON.stringify({ filename: f.name, mime: f.type, b64 }) }); const jd = await r.json().catch(() => ({})); if (!r.ok || jd?.error) throw new Error(jd?.error || ('HTTP ' + r.status)); if (jd.logged && jd.logged.ok) { setInvMsg('Logged: ' + (jd.parsed?.vendor || '') + ' — ' + (jd.parsed?.currency || 'AED') + ' ' + (jd.parsed?.amount || '') + '. Original stored & queued for Dropbox backup.'); reload(); } else if (jd.parsed) { setInvMsg('Stored & extracted, but auto-posting was skipped because the amount was unclear. What I read: ' + Object.entries(jd.parsed || {}).filter(([, x]: any) => x != null && x !== '' && typeof x !== 'object').map(([k, x]: any) => String(k).replace(/_/g, ' ') + ': ' + String(x)).join(', ')); } else { setInvMsg('Stored the original (' + (jd.extracted_chars || 0) + ' chars extracted); could not auto-parse a finance entry.'); } } catch (e: any) { setInvMsg('Failed: ' + (e?.message || '')); } setInvBusy(false); };
  if (err) return <Card className='p-6 text-sm text-destructive'>Could not load {mod.label}: {err}</Card>;
  if (!d) return (<div className='space-y-4'><div className='flex items-center gap-2'><mod.icon className='h-5 w-5 text-primary/40' /><div className='h-6 w-40 bg-foreground/5 rounded animate-pulse' /></div><div className='grid grid-cols-2 md:grid-cols-4 gap-3'>{Array.from({ length: 4 }).map((_, i) => <div key={i} className='h-20 rounded-lg bg-foreground/5 animate-pulse' />)}</div><div className='h-64 rounded-lg bg-foreground/5 animate-pulse' /></div>);
  const tables: [string, any[]][] = [];
  const scalars: [string, any][] = [];
  const charts: [string, { label: string; n: number }[]][] = [];
  const isCountArr = (rows: any[]): { label: string; n: number }[] | null => {
    if (!rows.length || rows.length > 24) return null;
    const keys = Object.keys(rows[0]); if (keys.length > 3) return null;
    const labelK = keys.find((kk) => /^(key|label|name|category|kind|sector|emirate|month|department|stage|title)$/i.test(kk));
    const numK = keys.find((kk) => /^(count|n|amount|value|total|balance|runs|c|score)$/i.test(kk));
    if (!labelK || !numK || !rows.every((r) => typeof r[numK] === 'number')) return null;
    return rows.map((r) => ({ label: String(r[labelK]), n: Number(r[numK]) }));
  };
  const scan = (o: any) => { if (!o || typeof o !== 'object') return; for (const [k, v] of Object.entries(o)) { if (Array.isArray(v)) { if (v.length && typeof v[0] === 'object') { const ch = isCountArr(v as any[]); if (ch) charts.push([k, ch]); else tables.push([k, v as any[]]); } } else if (v && typeof v === 'object') { scan(v); } else if (typeof v === 'number' || typeof v === 'string') scalars.push([k, v]); } };
  scan(d);
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'><mod.icon className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>{mod.label}</h1>{mod.id === 'finance' ? <div className='ml-auto flex gap-2'><Button className='h-8 text-xs' variant='outline' onClick={() => { setInvOpen(true); setInvMsg(''); }}>Log invoice (PDF)</Button><Button className='h-8 text-xs' onClick={() => { setGlOpen(true); setGlMsg(''); }}>New journal entry</Button></div> : null}</div>
      {scalars.length ? <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3'>{scalars.slice(0, 12).map(([k, v]) => (<Card key={k} className='p-4'><div className='text-xs text-muted-foreground'>{titleCase(k)}</div><div className='text-xl font-bold mt-1 tabular-nums'>{fmt(v)}</div></Card>))}</div> : null}
      {charts.length ? <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>{charts.map(([name, rows]) => (<Card key={name} className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>{titleCase(name)}</div><div className='p-4'><HBars rows={rows.slice(0, 10)} /></div></Card>))}</div> : null}
      {tables.map(([name, rows]) => { const isUuidV = (x: any) => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x); const cols = (Object.keys(rows[0]).filter((k) => !((k === 'id' || k === 'uuid' || /_id$/.test(k)) && isUuidV((rows[0] as any)[k]))).slice(0, 6)); return (
        <Card key={name} className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>{titleCase(name)}<Badge variant='secondary'>{rows.length}</Badge></div>
          <div className='overflow-auto max-h-[420px]'>
            <table className='w-full text-sm'>
              <thead><tr className='text-left text-xs text-muted-foreground border-b border-border'>{cols.map((c) => (<th key={c} className='px-4 py-2 font-medium'>{titleCase(c)}</th>))}</tr></thead>
              <tbody>{rows.slice(0, 200).map((r, i) => (<tr key={i} onClick={() => { setRow(r); setRowTitle(titleCase(name)); }} className='border-b border-border/50 hover:bg-foreground/5 cursor-pointer'>{cols.map((c) => (<td key={c} className='px-4 py-2.5'>{fmt((r as any)[c])}</td>))}</tr>))}</tbody>
            </table>
          </div>
        </Card>
      ); })}
      {!tables.length && !scalars.length && !charts.length ? <Card className='p-4'><ReadableObject data={d} /></Card> : null}

      <Sheet open={invOpen} onOpenChange={setInvOpen}>
        <SheetContent side='right' className='osx dark w-full sm:max-w-md overflow-y-auto'>
          <SheetHeader><SheetTitle>Log invoice from PDF</SheetTitle><SheetDescription>The original is stored, Smart Engine-extracted, posted to finance, and queued for Dropbox backup.</SheetDescription></SheetHeader>
          <div className='mt-4 space-y-3'>
            <input type='file' accept='.pdf,.png,.jpg,.jpeg,application/pdf,image/*' disabled={invBusy} onChange={(e) => { const f = e.target.files?.[0]; if (f) onInvFile(f); }} className='block w-full text-sm text-muted-foreground file:mr-3 file:rounded-md file:border-0 file:bg-primary file:text-primary-foreground file:px-3 file:py-1.5 file:text-xs' />
            {invBusy ? <div className='text-xs text-muted-foreground'>Working…</div> : null}
            {invMsg ? <div className='text-xs text-foreground/80 whitespace-pre-wrap'>{invMsg}</div> : null}
          </div>
        </SheetContent>
      </Sheet>
      <Sheet open={glOpen} onOpenChange={setGlOpen}>
        <SheetContent side='right' className='osx dark w-full sm:max-w-lg overflow-y-auto'>
          <SheetHeader><SheetTitle>New journal entry</SheetTitle><SheetDescription>Double-entry — debits must equal credits.</SheetDescription></SheetHeader>
          <div className='mt-4 space-y-3'>
            <div className='flex gap-2'><input type='date' value={glDate} onChange={(e) => setGlDate(e.target.value)} className='rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Memo' value={glMemo} onChange={(e) => setGlMemo(e.target.value)} className='flex-1 rounded-md border border-border bg-transparent p-2 text-sm' /></div>
            <div className='space-y-2'>{glLines.map((l: any, i: number) => (<div key={i} className='flex gap-2'><input placeholder='Account code' value={l.account} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], account: e.target.value }; setGlLines(n); }} className='flex-1 rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Debit' inputMode='decimal' value={l.debit} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], debit: e.target.value }; setGlLines(n); }} className='w-24 rounded-md border border-border bg-transparent p-2 text-sm' /><input placeholder='Credit' inputMode='decimal' value={l.credit} onChange={(e) => { const n = glLines.slice(); n[i] = { ...n[i], credit: e.target.value }; setGlLines(n); }} className='w-24 rounded-md border border-border bg-transparent p-2 text-sm' /></div>))}</div>
            <div className='flex items-center justify-between text-xs text-muted-foreground'><button onClick={() => setGlLines([...glLines, { account: '', debit: '', credit: '', memo: '' }])} className='hover:text-foreground'>+ Add line</button><span>Debits {glTotals().dr.toFixed(2)} · Credits {glTotals().cr.toFixed(2)}</span></div>
            {glMsg ? <div className='text-xs text-destructive'>{glMsg}</div> : null}
            <div className='flex gap-2'><Button className='h-8 text-xs' disabled={glBusy} onClick={postGl}>{glBusy ? 'Posting…' : 'Post entry'}</Button><Button className='h-8 text-xs' variant='outline' onClick={() => setGlOpen(false)}>Cancel</Button></div>
          </div>
        </SheetContent>
      </Sheet>
      {row ? (() => {
        const ent = mod.id === 'suppliers' ? 'supplier' : mod.id === 'customers' ? 'customer' : mod.id === 'rfqs' ? 'rfq' : undefined;
        const idv = (row as any).id ?? (row as any).rfq_id ?? (row as any).inquiry_id;
        const acts = (() => { const r: any = row; const btn = (label: string, action: string, params: any) => <Button key={label} className='h-8 text-xs' variant='outline' disabled={dbusy} onClick={() => decide(action, params)}>{label}</Button>; const btnApi = (label: string, action: string, params: any) => <Button key={label} className='h-8 text-xs' variant='outline' disabled={dbusy} onClick={() => decideApi(action, params)}>{label}</Button>; const out: any[] = [];
          if (mod.id === 'suppliers') { out.push(btn('Approve','supplier_decide',{id:r.id,op:'approve'}), btn('Reject','supplier_decide',{id:r.id,op:'reject',note:'Rejected from OS'}), btn(r.banned?'Unban':'Ban','supplier_decide',{id:r.id,op:r.banned?'unban':'ban'})); }
          else if (mod.id === 'customers') { out.push(btn(r.banned?'Unban':'Ban','customer_decide',{id:r.id,op:r.banned?'unban':'ban'})); }
          else if (mod.id === 'rfqs') { out.push(btn('Mark won','rfq_outcome',{inquiry:r.id,outcome:'won'}), btn('Mark lost','rfq_outcome',{inquiry:r.id,outcome:'lost'})); }
          else if (mod.id === 'fraud') { if (r.subject_type && r.subject_id != null) { out.push(btnApi('Dismiss','fraud_resolve',{subject_type:r.subject_type,subject_id:String(r.subject_id),op:'dismiss'}), btnApi('Ban','fraud_resolve',{subject_type:r.subject_type,subject_id:String(r.subject_id),op:'ban'})); } else if (r.kind && r.subject_id != null && r.reason !== undefined) { out.push(btnApi('Unban','fraud_resolve',{subject_type:r.kind,subject_id:String(r.subject_id),op:'unban'})); } }
          else if (mod.id === 'refunds') { const tid = r.transaction_id ?? r.id; if (tid != null && r.refund_status !== undefined) { out.push(btnApi('Approve refund','refund_resolve',{transaction_id:String(tid),op:'approve'}), btnApi('Reject refund','refund_resolve',{transaction_id:String(tid),op:'reject'})); } }
          if (r && r.agent && (r.status === 'pending' || r.status === 'needs_review')) { out.push(btn('Approve','action_decide',{id:r.id,op:'approve'}), btn('Reject','action_decide',{id:r.id,op:'reject'})); }
          return out;
        })();
        const actions = <>{acts}{editableType() ? <Button className='h-8 text-xs' variant='outline' disabled={ebusy} onClick={() => openEdit(editableType()!)}>Edit</Button> : null}<Button className='h-8 text-xs' variant='outline' onClick={() => { try { navigator.clipboard?.writeText(JSON.stringify(row, null, 2)); } catch (_e) {} }}>Copy details</Button></>;
        const extra = edit ? <div className='rounded-md border border-border p-3 space-y-3'><div className='text-xs font-semibold text-muted-foreground'>Edit content</div>{Object.keys(edit).filter((k) => k !== 'id').map((k) => (<div key={k}><div className='text-[11px] text-muted-foreground mb-1'>{titleCase(k)}</div><textarea value={edit[k] ?? ''} onChange={(e) => setEdit({ ...edit, [k]: e.target.value })} rows={String(edit[k] || '').length > 80 ? 5 : 2} className='w-full resize-none rounded-md border border-border bg-transparent p-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' /></div>))}{emsg ? <div className='text-xs text-destructive'>{emsg}</div> : null}<div className='flex gap-2'><Button className='h-8 text-xs' disabled={ebusy} onClick={saveEdit}>{ebusy ? 'Saving…' : 'Save'}</Button><Button className='h-8 text-xs' variant='outline' onClick={() => setEdit(null)}>Cancel</Button></div></div> : null;
        const niceLabel = ent ? ({ supplier: 'Supplier', customer: 'Customer', rfq: 'RFQ' } as Record<string, string>)[ent] || titleCase(ent) : singularWord(rowTitle);
        return <RecordDrawer frame0={{ entity: ent, id: idv, title: niceLabel + (idv != null ? ' #' + idv : ''), row }} actions={actions} extra={extra} reportId={(row as any).report_type && (row as any).id ? Number((row as any).id) : undefined} onClose={() => { setRow(null); setDetail(null); setEdit(null); }} />;
      })() : null}
    </div>
  );
}
