'use client';
import * as React from 'react';
import { supa, osApi, osOps, osReportBody, osSettings, osAutomation, osCatalog, osPages, osHealth, osIncidents, SUPA_URL, founderCommand, founderCommandThread } from '@/lib/osClient';
import { cn } from '@/lib/utils';
function ReportViewer({ id }: { id: number }) {
  const [st, setSt] = React.useState<'idle' | 'load' | 'done' | 'err'>('load');
  const [rep, setRep] = React.useState<any>(null);
  // Clicking a figure asks the drilldown routine why it moved, against what target, and who
  // contributed — the three things the requirement names.
  const [drillData, setDrillData] = React.useState<any>(null);
  const [approving, setApproving] = React.useState<number | null>(null); const [approved, setApproved] = React.useState<number[]>([]);
  // Approve a recommended action from inside the report, which is where the founder is reading it.
  const approveRec = async (i: number) => { setApproving(i); try { await osApi('report_recommend_approve', { report_id: id, index: i, source: rep?.report_type === 'exec_reports' ? 'exec_reports' : 'exec_reports' }); setApproved((a) => [...a, i]); } catch (_e) {} setApproving(null); };
  const drill = async (metric: string) => { try { setDrillData(await osApi('drilldown', { metric, days: 60 })); } catch (_e) { setDrillData(null); } };
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
      {rep.kpis && typeof rep.kpis === 'object' && !Array.isArray(rep.kpis) ? <div className='grid grid-cols-2 gap-2 sm:grid-cols-3'>{Object.entries(rep.kpis).map(([k, v]: any) => (<button key={k} onClick={() => drill(k)} className='text-left rounded-md border border-border/50 bg-card/40 px-3 py-2 hover:bg-foreground/5 transition-colors'><div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{titleCaseSafe(k)}</div><div className='text-sm font-medium break-words'>{fmt(v)}</div><div className='text-[10px] text-muted-foreground'>click to drill in</div></button>))}</div> : null}
      {drillData ? <div className='rounded-md border border-border/50 p-3'><div className='flex items-center justify-between'><div className='text-sm font-semibold'>Why {titleCaseSafe(String(drillData.metric))} moved</div><button onClick={() => setDrillData(null)} className='text-[11px] text-muted-foreground hover:text-foreground'>close</button></div><div className='mt-1 text-[12px]'>{drillData.readings} reading(s) in {drillData.window_days}d · latest {fmt(drillData.latest)}{drillData.change != null ? ' · change ' + (Number(drillData.change) >= 0 ? '+' : '') + fmt(drillData.change) : ''}</div>{drillData.target ? <div className='mt-1 text-[12px] text-muted-foreground'>Target {fmt(drillData.target.target_value)} {drillData.target.horizon} · actual {fmt(drillData.target.actual_value)} · gap {fmt(drillData.target.gap)} ({drillData.target.status})</div> : null}{drillData.index ? <div className='mt-1 text-[12px] text-muted-foreground'>Index {drillData.index.index_name} {fmt(drillData.index.score)} ({drillData.index.band}) measured {drillData.index.measured_on}</div> : null}{(drillData.contributors || []).length ? <div className='mt-2'><div className='text-[11px] uppercase tracking-wide text-muted-foreground'>Who contributed</div>{(drillData.contributors as any[]).map((c: any, i: number) => (<div key={i} className='text-[12px]'>{c.actor}{c.os ? ' (' + c.os + ' OS)' : ''} — {c.decision} · {fmt(c.at)}</div>))}</div> : <div className='mt-2 text-[11px] text-muted-foreground'>No decision in the window names this figure.</div>}</div> : null}
      {Array.isArray(rep.recommendations) && rep.recommendations.length ? <div className='rounded-md border border-border/50 p-3'><div className='text-sm font-semibold'>Recommended actions</div><div className='mt-1 divide-y divide-border'>{(rep.recommendations as any[]).map((rc: any, i: number) => (<div key={i} className='py-2 flex items-start gap-2 text-[13px]'><div className='min-w-0 flex-1'>{rc.title || rc.recommendation || fmt(rc)}</div><Button className='h-7 text-xs shrink-0' variant='outline' disabled={approving === i || approved.includes(i)} onClick={() => approveRec(i)}>{approved.includes(i) ? 'Approved' : approving === i ? '…' : 'Approve'}</Button></div>))}</div></div> : null}
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
import { MessageSquare, LayoutDashboard, ArrowLeftRight, Hammer, Users, DollarSign, Sparkles, Settings2, Scale, LogOut, Search, Paperclip, Send, Circle, AlertTriangle, Bell, BookOpen, Calendar, BarChart3, Megaphone, Compass, FileText, Building2, FileBarChart, ShieldAlert, RotateCcw, ScrollText, AudioLines, SlidersHorizontal, Workflow, ListChecks, Newspaper, Activity, LifeBuoy, ArrowUpRight, Minus, Maximize2, Minimize2, ExternalLink, SquareStack, X, ChevronRight, Check, Brain, Network } from 'lucide-react';
import { CompanyGraphField } from '@/components/NodeField';
import { ControlModeProvider, ControlModeIndicator } from '@/components/osx/ControlMode';

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
  { id: 'intelligence', label: 'Intelligence', icon: Brain, kind: 'intelligence' },
  { id: 'company_os', label: 'Operating System & map', icon: Network, kind: 'company_os' },
  { id: 'memory', label: 'Company memory', icon: ScrollText, kind: 'memory' },
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
  return m.kind === 'console' ? <Console /> : m.kind === 'overview' ? <Overview onNav={go} /> : m.kind === 'escalations' ? <Escalations onNav={go} /> : m.kind === 'intelligence' ? <IntelligenceApp /> : m.kind === 'company_os' ? <CompanyOsApp /> : m.kind === 'memory' ? <CompanyMemoryApp /> : m.kind === 'knowledge' ? <Knowledge /> : m.kind === 'audit' ? <AuditLog /> : m.kind === 'settings' ? <SettingsPanel /> : m.kind === 'automation' ? <AutomationPanel /> : m.kind === 'catalog' ? <CatalogPanel /> : m.kind === 'content' ? <ContentPanel /> : m.kind === 'health' ? <HealthPanel onNav={go} /> : m.kind === 'support' ? <SupportPanel /> : m.kind === 'intake_audio' ? <IntakeAudio /> : m.id === 'suppliers' ? <SuppliersApp /> : m.id === 'rfqs' ? <RfqApp /> : m.id === 'customers' ? <CustomersApp /> : m.id === 'agents' ? <AgentsApp /> : m.id === 'finance' ? <FinanceApp /> : m.id === 'marketing' ? <MarketingApp /> : m.id === 'fraud' ? <FraudApp /> : m.id === 'refunds' ? <RefundsApp /> : m.id === 'operations' ? <OperationsApp /> : m.id === 'analytics' ? <AnalyticsApp /> : m.id === 'strategy' ? <StrategyApp /> : m.id === 'governance' ? <GovernanceApp /> : m.id === 'company' ? <CompanyApp /> : m.id === 'ea' ? <AssistantApp /> : m.id === 'documents' ? <DocumentsApp /> : m.id === 'reports' ? <ReportsApp /> : <Workspace mod={m} />;
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
  // The palette searches ENTITIES, not just module labels: what the founder types goes to
  // fn_os_search across all nine corpora, debounced, and the hits sit above the actions.
  const [paletteQ, setPaletteQ] = React.useState(''); const [paletteHits, setPaletteHits] = React.useState<any[]>([]);
  React.useEffect(() => {
    const term = paletteQ.trim(); if (!paletteOpen || term.length < 2) { setPaletteHits([]); return; }
    let alive = true;
    const t = setTimeout(() => {
      osApi('search', { q: term }).then((d: any) => {
        if (!alive) return;
        const GROUPS: [string, string, string][] = [['suppliers', 'Supplier', 'suppliers'], ['rfqs', 'RFQ', 'rfqs'],
          ['customers', 'Customer', 'customers'], ['knowledge', 'Knowledge', 'knowledge'], ['lessons', 'Lesson', 'memory'],
          ['decisions', 'Decision', 'memory'], ['documents', 'Document', 'documents']];
        setPaletteHits(GROUPS.flatMap(([k, label, mod]) => ((d && d[k]) || []).slice(0, 4)
          .map((r: any) => ({ name: r.name || r.headline || r.title, group: label, mod }))).slice(0, 12));
      }).catch(() => {});
    }, 220);
    return () => { alive = false; clearTimeout(t); };
  }, [paletteQ, paletteOpen]);
  const [live, setLive] = React.useState(0);
  // A twin that refreshes is not a counter that ticks. Bumping this key remounts the open
  // workspace, so every panel re-fetches when the database pushes a change.
  const [twinKey, setTwinKey] = React.useState(0);
  const reload = React.useCallback(() => setTwinKey((k) => k + 1), []);
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
    // BUILD MODE (15 Aug 2026). The founder: "whoever enters with my link, let him enter… there's
    // no access for me now, there doesn't require. That's how it should be." The backend already
    // answers without a session while public.fn_os_open_access() is true; this stops the SHELL
    // demanding a sign-in the API no longer wants. Asking the API rather than a build flag matters:
    // one switch closes both, so "activate the credentials" cannot half-close the door.
    supa.auth.getSession().then(async ({ data }) => {
      const signedIn = data.session?.user?.email || '';
      if (signedIn) { setEmail(signedIn); setReady(true); return; }
      // osApi() unwraps to j.data and `ping` carries no data field, so the RETURN VALUE says
      // nothing. What answers the question is whether it threw: a closed door is a 401 and
      // unwrap() raises on it. Reading r.user here would have been undefined every time and the
      // shell would have shown the sign-in screen for ever.
      try { await osApi('ping'); setEmail('build-mode@quotesdone.local'); }
      catch (_e) { setEmail(''); }   // door closed: the sign-in screen is correct
      setReady(true);
    });
    sub = supa.auth.onAuthStateChange((_e, s) => { if (s?.user?.email) setEmail(s.user.email); }).data.subscription;
    const onKey = (e: KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setPaletteOpen((o) => !o); } };
    window.addEventListener('keydown', onKey);
    return () => { try { sub?.unsubscribe(); } catch (_e) {} window.removeEventListener('keydown', onKey); };
  }, []);

  // ── THE TWIN, LIVE ────────────────────────────────────────────────────────────────────────
  // Every one of the thirteen twin object classes, subscribed. This only works because each is
  // now in the supabase_realtime publication AND carries an owner/admin select policy — before
  // that the publication was empty, so a subscription here delivered nothing at all and the
  // channel below was watching two tables it could never receive.
  // Each change reloads the surface rather than only bumping a counter: a number that ticks is
  // not a twin that refreshes.
  React.useEffect(() => {
    if (!email) return;
    const bump = () => { setLive((n) => n + 1); reload(); };
    const ch = supa.channel('osx-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'customers' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'leads' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'org_agents' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kb_chunks' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'inquiries' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transactions' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'gl_journal' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ai_cost_log' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'workflow' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'edge_health_probe' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'risk_register' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'expenses' }, bump)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'vision_horizon' }, bump)
      .subscribe();
    return () => { try { supa.removeChannel(ch); } catch (_e) {} };
  }, [email]);

  if (!ready) return <div className='osx dark min-h-screen grid place-items-center text-muted-foreground'>Loading…</div>;
  if (!email) return <LoginCard onDone={(e) => setEmail(e)} />;

  const go = (id: string) => { setTabs((t) => t.includes(id) ? t : [...t, id]); setCur(id); };
  const closeTab = (id: string) => { setTabs((t) => { const nt = t.filter((x) => x !== id); if (!nt.length) return ['console']; if (id === cur) setCur(nt[nt.length - 1]); return nt; }); };
  const popOut = (id: string) => { const m = MODULES.find((x) => x.id === id) || MODULES[0]; openWindow({ id: 'mod:' + id, title: m.label, icon: m.icon, render: () => renderModule(id, go) }); };
  return (
    // ControlModeProvider wraps the whole shell, not just the header. It listens for the gate
    // refusal that osClient fires from ANY module, so pressing a blocked button anywhere brings up
    // the panel that unblocks it. Before this, Phase 1.4's gate had no UI at all.
    <ControlModeProvider>
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
          <ControlModeIndicator />
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
            <div key={id + ':' + twinKey} className={id === cur ? '' : 'hidden'}>
              {renderModule(id, go)}
            </div>
          ); })}
        </main>
      </div>

      <CommandDialog open={paletteOpen} onOpenChange={setPaletteOpen}>
        <CommandInput placeholder='Jump to a module, find a supplier, RFQ, lesson or decision…' value={paletteQ} onValueChange={setPaletteQ} />
        <CommandList>
          <CommandEmpty>No matches.</CommandEmpty>
          <CommandGroup heading='Modules'>
            {MODULES.map((m) => (<CommandItem key={m.id} onSelect={() => { setCur(m.id); setPaletteOpen(false); }}><m.icon className='h-4 w-4' />{m.label}</CommandItem>))}
          </CommandGroup>
          {/* Entities, searched live across all nine corpora rather than listed. */}
          {paletteHits.length ? <CommandGroup heading='Entities'>
            {paletteHits.map((h: any, i: number) => (<CommandItem key={'e' + i} onSelect={() => { setCur(h.mod); setPaletteOpen(false); }}><Search className='h-4 w-4' />{h.name}<span className='ml-2 text-[11px] text-muted-foreground'>{h.group}</span></CommandItem>))}
          </CommandGroup> : null}
          <CommandGroup heading='Actions'>
            <CommandItem onSelect={() => { osApi('search', { q: paletteQ }).then((d: any) => setPaletteHits(((d && d.suppliers) || []).map((r: any) => ({ name: r.name, group: 'Supplier', mod: 'suppliers' })))).catch(() => {}); }}><Search className='h-4 w-4' />Search everything the company knows</CommandItem>
            <CommandItem onSelect={() => { setCur('console'); setPaletteOpen(false); }}><MessageSquare className='h-4 w-4' />Ask the Secretary for status</CommandItem>
            <CommandItem onSelect={() => { setCur('agents'); setPaletteOpen(false); }}><Sparkles className='h-4 w-4' />Show matching / agent activity</CommandItem>
            <CommandItem onSelect={() => { setCur('operations'); setPaletteOpen(false); }}><Check className='h-4 w-4' />Approve a pending decision</CommandItem>
            <CommandItem onSelect={() => { setCur('agents'); setPaletteOpen(false); }}><RotateCcw className='h-4 w-4' />Restart AI agents</CommandItem>
            <CommandItem onSelect={() => { setCur('intelligence'); setPaletteOpen(false); }}><BarChart3 className='h-4 w-4' />Forecast</CommandItem>
            <CommandItem onSelect={() => { setCur('finance'); setPaletteOpen(false); }}><DollarSign className='h-4 w-4' />Cash Flow</CommandItem>
          </CommandGroup>
        </CommandList>
      </CommandDialog>
      <WindowLayer wins={wins} focus={focusWin} close={closeWin} min={minWin} max={maxWin} move={moveWin} size={sizeWin} snap={snapWin} />
    </div>
    </WinCtx.Provider>
    </ControlModeProvider>
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

// WHAT THE OS HAS LEARNED ABOUT HOW THE FOUNDER DECIDES.
// Every habit carries its sample size, and one below the evidence floor is labelled an observation
// rather than presented as a preference — n=1 dressed as "he always does this" is the same defect
// as a scorer reporting 100% on a file it could not read. Presentation adapts to these; governance
// does not, and nothing here changes an authority or a gate.
function FounderHabits() {
  const [d, setD] = React.useState<any>(null);
  React.useEffect(() => { osApi('founder_habits').then(setD).catch(() => {}); }, []);
  const rows = (d?.rows || []) as any[];
  if (!d) return null;
  return (<Card className='p-4 space-y-2'>
    <div className='flex flex-wrap items-baseline gap-2'>
      <h2 className='text-sm font-semibold'>What the OS has learned about how you decide</h2>
      <span className='text-[11px] text-muted-foreground'>
        {d.habits_confident ?? 0} of {d.habits_total ?? 0} clear the {d.evidence_floor ?? 3}-observation floor
        {d.learned_at ? ' · learned ' + String(d.learned_at).slice(0, 10) : ''}
      </span>
    </div>
    {rows.length ? <div className='divide-y divide-border'>{rows.map((h: any, i: number) => (
      <div key={i} className='py-2 text-sm flex items-start gap-3'>
        <div className='min-w-0 flex-1'>
          <div>{h.text}</div>
          <div className='text-[11px] text-muted-foreground'>{h.habit_key} · {h.sample_n} observation(s)</div>
        </div>
        <Chip label={h.confident ? 'Habit' : 'Not enough evidence yet'} tone={h.confident ? 'slate' : 'amber'} />
      </div>))}</div>
      : <div className='text-sm text-muted-foreground'>Nothing observed yet.</div>}
    <div className='text-[11px] text-muted-foreground'>{d.note}</div>
  </Card>);
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
      <FounderHabits />
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
  const [aiq, setAiq] = React.useState<any>(null);
  // ai_quality_snapshots has been written nightly since 10 Jul and had ZERO readers in src/ —
  // 1,219 rows the founder could not see. Fetched alongside health rather than as its own screen:
  // "are my agents being overruled" is a system-health question, and a number nobody passes on the
  // way to something else is a number nobody reads. It fails to null on its own without taking
  // health down with it — this panel already loads two independent things.
  const load = React.useCallback(() => {
    setBusy(true); setErr('');
    osHealth('ai_quality').then((q: any) => setAiq(q)).catch(() => setAiq(null));
    Promise.all([osHealth('health'), osHealth('reconcile')]).then(([a, b]: any) => { setH(a); setRec(b); }).catch((e: any) => setErr(e.message)).finally(() => setBusy(false));
  }, []);
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
      {/* WHERE YOUR AGENTS ARE BEING OVERRULED. Written nightly since 10 Jul, read by nothing until
          now. Sorted worst-first by override rate, then by volume — an agent rejected 100% of the
          time on 2 actions and one rejected 30% on 400 are different problems, and the count is on
          the row so they can be told apart. Agents nobody has overruled are not listed: a table of
          37 zeroes hides the one row that matters. */}
      {aiq && aiq.rows && aiq.rows.length ? (
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border flex flex-wrap items-baseline gap-x-2 gap-y-1'>
            <span className='text-sm font-semibold'>AI decision quality</span>
            <span className='text-xs text-muted-foreground'>
              {aiq.override_pct_overall != null ? aiq.override_pct_overall + '% of ' : ''}
              {aiq.actions_30d_total} proposed action(s) in 30 days were overruled by a human · {aiq.agents} agents · {aiq.nights_held} nights held
            </span>
          </div>
          <div className='p-4'>
            <p className='text-xs text-muted-foreground mb-3 max-w-[80ch]'>{aiq.meaning}</p>
            {(() => {
              const overruled = (aiq.rows || []).filter((r: any) => Number(r.override_pct) > 0);
              if (!overruled.length) {
                return <div className='text-sm text-muted-foreground'>No agent had a suggestion overruled in the last 30 days. {aiq.agents} agents proposed {aiq.actions_30d_total} action(s).</div>;
              }
              return (
                <div className='space-y-1.5'>
                  {overruled
                    .slice()
                    .sort((a: any, b: any) => (Number(b.override_pct) - Number(a.override_pct)) || (Number(b.actions_30d) - Number(a.actions_30d)))
                    .map((r: any) => (
                      <div key={r.agent} className='flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5 text-sm border-b border-border/30 py-1'>
                        <span className='font-medium'>{r.agent}</span>
                        <span className='inline-flex items-baseline gap-2'>
                          <span className={cn('font-semibold tabular-nums', Number(r.override_pct) >= 50 ? 'text-destructive' : 'text-amber-400')}>{r.override_pct}%</span>
                          <span className='text-xs text-muted-foreground tabular-nums'>of {r.actions_30d}</span>
                          {/* A delta is only stated when there IS history to compare with. */}
                          {r.delta != null && Number(r.delta) !== 0 ? (
                            <span className={cn('text-xs tabular-nums', Number(r.delta) > 0 ? 'text-destructive' : 'text-emerald-400')}>
                              {Number(r.delta) > 0 ? '+' : ''}{r.delta} vs {r.nights_of_history}-night avg
                            </span>
                          ) : r.nights_of_history === 0 ? <span className='text-xs text-muted-foreground'>first night</span> : null}
                        </span>
                      </div>
                    ))}
                </div>
              );
            })()}
          </div>
        </Card>
      ) : null}
      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold'>Operations</div>
          <div className='p-4'>
            {/* CAN A REQUEST REACH ANYONE? The most suppliers the structured matcher can shortlist
                for any request. It sits at the top of Operations because when it is 1, nothing
                below it matters — a green cron board on a marketplace that cannot dispatch is the
                definition of an instrument reporting on the wrong subject. */}
            {h.supplier_reach ? (
              <div className='mb-3 rounded-md border border-border/60 bg-secondary/20 px-3 py-2' title={h.supplier_reach.meaning}>
                <div className='flex items-baseline justify-between gap-3'>
                  <span className='text-xs text-muted-foreground'>Suppliers an RFQ can reach</span>
                  <span className={cn('text-sm font-bold tabular-nums',
                    Number(h.supplier_reach.matchable_now) < 5 ? 'text-destructive' : 'text-foreground')}>
                    {h.supplier_reach.matchable_now}
                  </span>
                </div>
                <div className='mt-0.5 text-[11px] leading-snug text-muted-foreground'>
                  {h.supplier_reach.with_capability} supplier(s) hold capability data and {h.supplier_reach.confirmed} {Number(h.supplier_reach.confirmed) === 1 ? 'has' : 'have'} confirmed their own scope, which is what matching requires. The shortage is confirmations, not suppliers.
                </div>
              </div>
            ) : null}
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

// MOBILE NUMBER + VERIFICATION, which is what the founder asked for and what the estate could
// already do everywhere except here. login_otp has carried a Twilio Verify SMS path and a
// mintSession() that returns a real Supabase session for months; the customer and supplier portals
// both use it. This screen called supa.auth.signInWithOtp({ email }) and nothing else, so the one
// person who runs the company was the only one who could not sign in by phone.
//
// The credentials were never the blocker: twilio_api_key_sid/_secret and
// twilio_verify_service_sid are all provisioned and authenticate against Verify service
// "QuotesDone" (HTTP 200, auth_ok true, checked 10 Aug 2026). The blocker was that
// resolveEmailByPhone knew only 'supplier' and 'customer', so an admin number resolved to nobody.
// That is fixed in login_otp; this is the other half.
//
// Email stays. It is the fallback for the day Twilio is down, and removing a working sign-in path
// to make a new one look finished is not an upgrade.
const isPhoneish = (s: string) => /^[+0-9][0-9\s().-]{7,}$/.test(s.trim());

function LoginCard({ onDone }: { onDone: (e: string) => void }) {
  const [em, setEm] = React.useState(''); const [code, setCode] = React.useState(''); const [sent, setSent] = React.useState(false); const [busy, setBusy] = React.useState(false); const [err, setErr] = React.useState('');
  const [channel, setChannel] = React.useState<'email' | 'sms'>('email');
  const id = em.trim();
  const byPhone = isPhoneish(id);

  const otp = async (action: 'send' | 'verify') => {
    const r = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/login_otp`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      // 'admin', not 'customer' (13 Aug 2026). This screen claimed to be a customer so that the
      // shared phone resolver would reach app_secrets.admin_mfa_phone. It worked, and it made
      // every CUSTOMER signing in by SMS from that same number land on the admin's account —
      // the founder's own /me showed him management@quotesdone.com. login_otp now has a third
      // kind and only this one consults admin_mfa_phone.
      body: JSON.stringify({ action, identifier: id, user_kind: 'admin', ...(action === 'verify' ? { code: code.trim() } : {}) }),
    });
    return { r, j: await r.json().catch(() => ({})) } as { r: Response; j: Record<string, unknown> };
  };

  const send = async () => {
    setBusy(true); setErr('');
    try {
      if (byPhone) {
        const { j } = await otp('send');
        if (!j.ok) { setErr(String(j.error || 'Could not send the code.')); return; }
        setChannel('sms'); setSent(true);
      } else {
        const { error } = await supa.auth.signInWithOtp({ email: id.toLowerCase(), options: { shouldCreateUser: false } });
        if (error) { setErr(error.message); return; }
        setChannel('email'); setSent(true);
      }
    } finally { setBusy(false); }
  };

  const verify = async () => {
    setBusy(true); setErr('');
    try {
      if (channel === 'sms') {
        const { j } = await otp('verify');
        const at = j.access_token as string | undefined, rt = j.refresh_token as string | undefined;
        if (!at || !rt) { setErr(String(j.error || 'That code did not work.')); return; }
        const { data, error } = await supa.auth.setSession({ access_token: at, refresh_token: rt });
        if (error) { setErr(error.message); return; }
        onDone(data.user?.email || String(j.email || id));
      } else {
        const { data, error } = await supa.auth.verifyOtp({ email: id.toLowerCase(), token: code.trim(), type: 'email' });
        if (error) { setErr(error.message); return; }
        onDone(data.user?.email || id);
      }
    } finally { setBusy(false); }
  };

  return (
    <div className='osx dark min-h-screen grid place-items-center p-4'>
      <Card className='w-full max-w-sm p-6'>
        <div className='flex items-center gap-2 mb-4'><div className='h-8 w-8 rounded-lg bg-primary text-primary-foreground grid place-items-center font-extrabold'>Q</div><div className='font-bold text-lg'>QuotesDone OS</div></div>
        <p className='text-sm text-muted-foreground mb-4'>Admin sign-in. Enter your mobile number or your email and we send you a one-time code.</p>
        {!sent ? (<>
          <Input placeholder='+971 50 000 0000  or  you@quotesdone.com' inputMode='text' autoComplete='username'
                 value={em} onChange={(e) => setEm(e.target.value)} />
          <div className='text-xs text-muted-foreground mt-2'>{id ? (byPhone ? 'We will text you a code.' : 'We will email you a code.') : ' '}</div>
          <Button className='w-full mt-3' disabled={busy || !id} onClick={send}>{busy ? 'Sending…' : 'Send code'}</Button>
        </>) : (<>
          <Input placeholder='6-digit code' inputMode='numeric' autoComplete='one-time-code'
                 value={code} onChange={(e) => setCode(e.target.value)} />
          <div className='text-xs text-muted-foreground mt-2'>Sent by {channel === 'sms' ? 'SMS' : 'email'} to {id}.</div>
          <Button className='w-full mt-3' disabled={busy || !code} onClick={verify}>{busy ? 'Verifying…' : 'Verify & enter'}</Button>
          <button className='text-xs text-muted-foreground mt-3 underline' onClick={() => { setSent(false); setCode(''); }}>Use a different number or email</button>
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
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [subject, setSubject] = React.useState('');
  React.useEffect(() => { osOps('audit_log', { limit: 200 }).then(setD).catch((e) => setErr(e.message)); }, []);
  if (err) return <Card className='p-6 text-sm text-destructive'>Could not load audit log: {err}</Card>;
  if (!d) return <div className='text-muted-foreground text-sm'>Loading audit log…</div>;
  // "When did AI change pricing?" is a SUBJECT question, and the log answered only "what happened
  // most recently". The filter narrows the same dated stream to one subject.
  const allRows = d.rows || [];
  const rows = subject.trim()
    ? allRows.filter((r: any) => JSON.stringify(r).toLowerCase().includes(subject.trim().toLowerCase()))
    : allRows;
  return (
    <div className='space-y-5'>
      <div className='flex items-center gap-2'><ScrollText className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Audit log</h1>
        <Input value={subject} onChange={(e) => setSubject(e.target.value)} placeholder='Filter by subject — pricing, model_policy, prompts…' className='ml-auto h-8 w-72 text-xs' /></div>
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Recent actions<Badge variant='secondary'>{rows.length}{subject.trim() ? ' of ' + allRows.length : ''}</Badge></div>
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
      {(() => { const tot = Number(ck.total ?? rows.length) || 1; const covPct = Math.round((Number(ck.covered ?? 0) / tot) * 100); return (
        <Card className='p-4'>
          <div className='flex items-center justify-between mb-2'><div className='text-sm font-semibold'>Overall coverage</div><div className='text-sm font-bold tabular-nums'>{covPct}%</div></div>
          <div className='h-2.5 rounded-full bg-foreground/[0.06] overflow-hidden flex'><div className='h-full bg-emerald-500' style={{ width: (Number(ck.covered ?? 0) / tot * 100) + '%' }} /><div className='h-full bg-amber-500' style={{ width: (Number(ck.thin ?? 0) / tot * 100) + '%' }} /><div className='h-full bg-red-500' style={{ width: (Number(ck.gaps ?? 0) / tot * 100) + '%' }} /></div>
          <div className='flex flex-wrap gap-x-5 gap-y-1 mt-2 text-xs'><span className='inline-flex items-center gap-1.5'><span className='h-2 w-2 rounded-full bg-emerald-500' />Covered <b>{fmt(ck.covered ?? 0)}</b></span><span className='inline-flex items-center gap-1.5'><span className='h-2 w-2 rounded-full bg-amber-500' />Thin <b>{fmt(ck.thin ?? 0)}</b></span><span className='inline-flex items-center gap-1.5'><span className='h-2 w-2 rounded-full bg-red-500' />Gaps <b>{fmt(ck.gaps ?? 0)}</b></span><span className='text-muted-foreground ml-auto'>{fmt(ck.total ?? 0)} service categories</span></div>
        </Card>); })()}
      {/* WHICH KNOWLEDGE WAS ACTUALLY USED. agent_brain has been writing kb_usage_log on every
          retrieval and nothing had ever read it back — 78 rows from 11 agents with zero readers
          anywhere in the database. Coverage says what the company knows; this says what it reached
          for. An empty list is a real answer and reads as one. */}
      {(() => { const uk = d.used_kpis || {}; const used = d.used || []; return (
        <Card className='overflow-hidden'>
          <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Knowledge actually used
            <span className='text-xs font-normal text-muted-foreground'>{fmt(uk.lookups_7d ?? 0)} lookup(s) · {fmt(uk.agents_7d ?? 0)} employee(s) · 7d</span></div>
          {used.length ? <div className='divide-y divide-border'>{used.map((u: any, i: number) => (
            <div key={i} className='px-4 py-2.5'>
              <div className='text-sm truncate flex items-center gap-2'><span className='text-muted-foreground'>{u.agent}</span>{u.category ? <Chip label={String(u.category)} tone='slate' /> : null}</div>
              <div className='text-xs text-muted-foreground truncate'>{u.query}</div>
            </div>
          ))}</div> : <div className='px-4 py-6 text-sm text-muted-foreground'>No knowledge lookups recorded yet.</div>}
        </Card>); })()}
      <Card className='overflow-hidden'>
        <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Coverage by category<Badge variant='secondary'>{rows.length}</Badge></div>
        <div className='overflow-auto max-h-[560px]'>
          <table className='w-full text-sm'>
            <thead><tr className='text-left text-xs text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Category</th><th className='px-4 py-2 font-medium w-40'>Chunks</th><th className='px-4 py-2 font-medium'>Status</th><th className='px-4 py-2 font-medium text-right'>Action</th></tr></thead>
            <tbody>{rows.map((r: any) => { const chunks = Number(r.chunks) || 0; const pct = Math.min(100, (chunks / 8) * 100); return (
              <tr key={r.category} className='border-b border-border/40 hover:bg-foreground/5'>
                <td className='px-4 py-2.5 font-medium'>{r.label || titleCase(r.category)}</td>
                <td className='px-4 py-2.5'><div className='flex items-center gap-2'><div className='w-20 h-1.5 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full' style={{ width: Math.max(2, pct) + '%', background: chunks === 0 ? 'hsl(0 72% 55%)' : chunks < 3 ? 'hsl(38 92% 50%)' : 'hsl(160 60% 42%)' }} /></div><span className='text-[11px] text-muted-foreground tabular-nums'>{chunks}</span></div></td>
                <td className='px-4 py-2.5'><Chip label={r.status} tone={statusTone(String(r.status))} /></td>
                <td className='px-4 py-2.5 text-right'>{r.status !== 'covered' ? <Button className='h-7 text-xs' disabled={busy === r.category} onClick={() => fill(r.category, r.label || r.category)}>{busy === r.category ? 'Generating…' : 'Fill gap'}</Button> : <Check className='h-4 w-4 text-emerald-600 inline' />}</td>
              </tr>
            ); })}</tbody>
          </table>
        </div>
      </Card>
      <div className='text-xs text-muted-foreground'>The curator generates UAE-specific trade knowledge (scope, regulations, pricing, red flags) and ingests it; embeddings compute automatically within a minute.</div>
    </div>
  );
}

function NotificationsBell({ pulse, onNav }: { pulse: number; onNav: (id: string) => void }) {
  const [items, setItems] = React.useState<any[]>([]); const [open, setOpen] = React.useState(false);
  const [tiers, setTiers] = React.useState<any>(null);
  React.useEffect(() => { let alive = true; osApi('ws.exec').then((d: any) => { if (alive) setItems(((d && d.notifications) || []).slice(0, 30)); }).catch(() => {}); return () => { alive = false; }; }, [pulse]);
  // Four named tiers with counts, and the share the AI cleared without the founder — the two things
  // screen 14 asks for and the bell never showed.
  React.useEffect(() => { let alive = true; osApi('ws.notifications').then((d: any) => { if (alive) setTiers(d); }).catch(() => {}); return () => { alive = false; }; }, [pulse]);
  const routeFor = (t: string) => { const s = String(t); return /finance|payment|invoice/.test(s) ? 'finance' : /uptime|site|governance|security/.test(s) ? 'governance' : /ops|error|operation/.test(s) ? 'operations' : 'escalations'; };
  const TIERS: [string, string, string][] = [['critical', 'Critical', 'escalations'], ['important', 'Important', 'operations'],
    ['suggested', 'Suggested', 'intelligence'], ['completed_today', 'Completed Today', 'audit']];
  const count = (tiers?.critical?.count ?? 0) + (tiers?.important?.count ?? 0) || items.length;
  return (
    <>
      <button onClick={() => setOpen(true)} title='Notifications' className='relative flex items-center justify-center h-9 w-9 rounded-md border border-border hover:bg-foreground/5'>
        <Bell className='h-4 w-4' />
        {count ? <span className='absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-bold grid place-items-center'>{count > 99 ? '99+' : count}</span> : null}
      </button>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent className='osx dark w-full sm:max-w-md overflow-y-auto'>
          <SheetHeader><SheetTitle>Notifications</SheetTitle><SheetDescription>Recent founder alerts &amp; reminders</SheetDescription></SheetHeader>
          {tiers ? <div className='mt-3 space-y-3'>
            <div className='grid grid-cols-2 gap-2'>{TIERS.map(([k, label, mod]) => (
              <button key={k} onClick={() => { setOpen(false); onNav(mod); }}
                className={cn('rounded-md border px-3 py-2 text-left hover:bg-foreground/5',
                  k === 'critical' && (tiers[k]?.count ?? 0) > 0 ? 'border-red-500/50' : 'border-border')}>
                <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{label}</div>
                <div className='text-lg font-semibold tabular-nums'>{tiers[k]?.count ?? 0}</div>
              </button>))}</div>
            <div className='text-[11px] text-muted-foreground'>
              The AI auto-cleared <b className='text-foreground'>{tiers.auto_cleared_24h ?? '—'}%</b> of {tiers.actions_24h ?? 0} actions in the last 24h
              {' '}· <b className='text-foreground'>{tiers.auto_handled_30d ?? '—'}%</b> of {tiers.actions_30d ?? 0} over 30 days, without the founder.
            </div>
            {TIERS.map(([k, label]) => ((tiers[k]?.rows || []).length ? <div key={'r' + k}>
              <div className='text-[11px] uppercase tracking-wide text-muted-foreground mt-2'>{label}</div>
              <div className='divide-y divide-border rounded-md border border-border mt-1'>{(tiers[k].rows as any[]).slice(0, 5).map((r: any, i: number) => (
                <div key={i} className='px-3 py-2 text-sm'><div className='truncate'>{r.title}</div>
                  {r.detail ? <div className='text-[11px] text-muted-foreground truncate'>{r.detail}</div> : null}</div>))}</div>
            </div> : null))}
          </div> : null}
          <div className='mt-4 divide-y divide-border'>
            {items.length ? items.map((n: any, i: number) => (
              <button key={i} onClick={() => { setOpen(false); onNav(routeFor(n.type)); }} className='w-full text-left py-3 hover:bg-foreground/5 transition-colors flex items-start gap-3'>
                <span className='mt-1 h-2 w-2 rounded-full bg-primary shrink-0'></span>
                <div className='min-w-0'><div className='text-sm font-medium'>{n.subject || n.type_label || titleCase(String(n.type || 'notification'))}</div><div className='text-xs text-muted-foreground'>{n.type_label || titleCase(String(n.type || ''))} · {new Date(n.created_at).toLocaleString()}</div></div>
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

// THE DECISIONS WAITING ON HIM, RANKED OLDEST FIRST.
//
// Every figure comes from ws.founder_queue -> fn_founder_queue, which counts agent_actions joined
// to agent_action_kind_policy where policy = 'founder'. Nothing is computed here and nothing is
// estimated: an item is on this list because a named agent raised it and the policy table says
// only he can answer it.
//
// It renders NOTHING when the queue is empty, so a cleared queue gives the console its clean
// canvas back rather than a heading over a green tick. The age is the point of the whole panel -
// the oldest item had been sitting for 36 days when this was written - so it is the one figure
// given emphasis, and anything past a week is called out rather than left as a number to compare.
function FounderQueue() {
  const [q, setQ] = React.useState<any>(null);
  const [state, setState] = React.useState<'loading' | 'ok' | 'failed'>('loading');
  React.useEffect(() => {
    let on = true;
    osApi('ws.founder_queue', { p_limit: 8 })
      .then((d: any) => { if (on) { setQ(d || {}); setState('ok'); } })
      .catch(() => { if (on) setState('failed'); });
    return () => { on = false; };
  }, []);

  if (state === 'loading') return null;
  if (state === 'failed') {
    return <div className='text-sm text-muted-foreground'>Your decision queue could not be read just now. Ask for a status, approve a supplier, draft content, or attach an invoice and tell me what to do with it.</div>;
  }
  const items: any[] = Array.isArray(q?.waiting_on_you) ? q.waiting_on_you : [];
  const total = Number(q?.waiting_on_you_total) || 0;
  const oldest = Number(q?.oldest_days) || 0;
  const machine = Number(q?.machine_is_working_on) || 0;
  if (!total) {
    return <div className='text-sm text-muted-foreground'>Nothing is waiting on you. Ask for a status, approve a supplier, draft content, log a finance entry, or attach an invoice and tell me what to do with it.</div>;
  }
  return (
    <div className='space-y-3'>
      <div className='flex items-baseline gap-2 flex-wrap'>
        <span className='text-sm font-semibold text-foreground'>{total} {total === 1 ? 'decision is' : 'decisions are'} waiting on you</span>
        {oldest > 0 ? <span className={cn('text-xs', oldest >= 7 ? 'text-destructive font-semibold' : 'text-muted-foreground')}>oldest {oldest} days</span> : null}
        {machine > 0 ? <span className='text-xs text-muted-foreground'>· the machine is working on {machine} of its own</span> : null}
      </div>
      <div className='divide-y divide-border/40 rounded-lg border border-border/60'>
        {items.map((it: any) => (
          <div key={String(it.id)} className='px-3 py-2 flex items-start justify-between gap-3'>
            <div className='min-w-0'>
              {/* `kind` is the routing key, `kind_label` is English. This line used to print
                  String(kind).replace(/_/g,' '), which is how the founder's decision queue came to
                  read "legal · legal flag" and "security · security incident". The label is
                  resolved once in the database (fn_ui_label) so the bell, this queue and the
                  escalations page cannot drift into three different wordings. */}
              <div className='text-[13px] text-foreground'>{it.title || it.kind_label || it.kind}</div>
              <div className='text-[11px] text-muted-foreground'>{it.from ? String(it.from) : 'unattributed'} · {it.kind_label || String(it.kind || '').replace(/_/g, ' ')}</div>
            </div>
            <span className={cn('text-[11px] shrink-0 tabular-nums', Number(it.age_days) >= 7 ? 'text-destructive' : 'text-muted-foreground')}>
              {Number(it.age_days) || 0}d
            </span>
          </div>
        ))}
      </div>
      {total > items.length ? <div className='text-[11px] text-muted-foreground'>and {total - items.length} more — Escalations has the full list.</div> : null}
      <div className='text-xs text-muted-foreground pt-1'>Or instruct me directly: ask for a status, approve a supplier, draft content, log a finance entry, or attach an invoice.</div>
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
  // ── AN ORDER GOES TO THE COMMAND ROUTER, NOT TO THE CHAT AGENT (15 Aug 2026) ────────────────
  // This box has always sent everything to `secretary_chat`, which drives an LLM agent. Phase C
  // built the canonical command channel — deterministic router, atomic task creation against exact
  // canonical employees, traces — and shipped it with no control in the UI. The founder sent a real
  // command and production recorded NOTHING, at any layer, because there was nothing to send it
  // through. This is that control.
  //
  // The order matters and is deliberate:
  //
  //   1. `founder_command` first. Deterministic, free, and the only path that creates real work
  //      owned by named employees. If the registry recognises the instruction, that IS the answer.
  //   2. Only when the registry has no intent for the text at all (confidence 0, no matched rule)
  //      does it fall through to the conversational agent — which is a PAID path and currently
  //      held open-circuit, so it will say so rather than pretend.
  //
  // A clarification or a refusal from the router is shown as-is. Neither creates work, and neither
  // is retried against the agent: "I can route this but not safely yet" is an answer, not a failure.
  const [plans, setPlans] = React.useState<Record<number, any>>({});
  const renderPlan = (d: any) => {
    if (d?.status === 'clarification_required') return d.clarification || 'I need one more detail before I can route that.';
    if (d?.status === 'refused') return (d.blocker || 'That instruction is refused.') + '\n\nNothing was created.';
    // A control command — status, cancel, reprioritise, explain — asks a question or moves an
    // existing command. It creates no work by design, and saying "0 task(s) created, owned by ."
    // reads as a failure. Caught the first time this was used through the browser.
    if (d?.control_command) {
      return [`Understood as ${d?.intent}.`,
              'Nothing was created — this asks about work that already exists.',
              `Command ${d?.command_id}.`].join('\n');
    }
    const wf = (d?.workflow_ids || []).join(', ');
    const owners: string[] = [d?.primary_owner, ...(d?.child_owners || [])].filter(Boolean);
    const lines = [
      `Understood as ${d?.intent}${wf ? ' → ' + wf : ''}.`,
      owners.length
        ? `${d?.tasks_created} task(s) created, owned by ${owners.join(', ')}.`
        : `${d?.tasks_created} task(s) created.`,
      d?.priority ? `Priority ${d.priority}${d?.due_at ? ', due ' + new Date(d.due_at).toLocaleDateString() : ''}.` : '',
      (d?.category_overlays_invoked || []).length ? `Category overlay consulted: ${d.category_overlays_invoked.join(', ')}.` : '',
      d?.founder_approval_required ? 'This one needs your decision — it is in your inbox.' : '',
      d?.founder_initiated_only ? 'Founder-reserved: the work is research and a proposal, not a commitment.' : '',
      `Command ${d?.command_id}. I will report progress here.`,
    ].filter(Boolean);
    return lines.join('\n');
  };
  const send = async () => {
    const t = text.trim(); const a = atts.slice(); if (!t && !a.length) return; setText(''); setAtts([]); setConfirm(null);
    const shown = t + (a.length ? '  [' + a.map((x) => x.name).join(', ') + ']' : '');
    setMsgs((m) => [...m, { role: 'user', content: shown }]); setBusy(true);
    try {
      // An instruction with no text is a document hand-off, which is the agent's job, not an order.
      if (t) {
        const d: any = await founderCommand(t);
        if (d?.command_id) {
          setPlans((p) => ({ ...p, [d.command_id]: d }));
          setMsgs((m) => [...m, { role: 'assistant', content: renderPlan(d) }]);
          setBusy(false); return;
        }
        // intent AMBIGUOUS with no matched rule = the registry has never heard of this. Fall
        // through to the conversational agent rather than answering with a shrug.
      }
      const hist = [...msgs].slice(-8);
      const d = await osApi('secretary_chat', { message: t || 'Please handle the attached document.', history: hist, attachments: a });
      setMsgs((m) => [...m, { role: 'assistant', content: d?.reply || 'Done.' }]);
      if (d?.needs_confirmation && d?.confirm_token) setConfirm({ token: d.confirm_token, reply: d.reply || '' });
    } catch (e: any) {
      // A Control Mode refusal already opens the panel via the window event in osClient; the text
      // here has to say what to do rather than read as "your account is wrong".
      const msg = e?.name === 'ControlModeError'
        ? 'Giving an order changes something, so it needs Control Mode open. The panel is on screen — open it and send this again.'
        : 'Error: ' + (e?.message || 'could not reach the Command Center');
      setMsgs((m) => [...m, { role: 'assistant', content: msg }]);
    }
    setBusy(false);
  };
  const decide = async (decision: string) => { if (!confirm) return; const tok = confirm.token; setConfirm(null); setBusy(true); try { const d = await osApi('secretary_chat', { confirm_token: tok, decision }); setMsgs((m) => [...m, { role: 'assistant', content: d?.reply || (decision === 'confirm' ? 'Done.' : 'Cancelled.') }]); } catch (_e) { setMsgs((m) => [...m, { role: 'assistant', content: 'Could not complete that.' }]); } setBusy(false); };
  // ── VOICE. The founder speaks to the OS. ────────────────────────────────────────────────────
  // The microphone existed in this product — in the CUSTOMER portal — and nowhere in the founder's
  // console. The recorded clip goes to the transcribe edge function and the text lands in the same
  // box the keyboard fills, so speech is an input to the Secretary, not a separate feature.
  const [rec, setRec] = React.useState(false); const recRef = React.useRef<MediaRecorder | null>(null);
  const [speak, setSpeak] = React.useState(false);
  const listen = async () => {
    if (rec) { recRef.current?.stop(); setRec(false); return; }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mr = new MediaRecorder(stream); recRef.current = mr; const chunks: BlobPart[] = [];
      mr.ondataavailable = (e) => chunks.push(e.data);
      mr.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunks, { type: mr.mimeType || 'audio/webm' });
        const b64: string = await new Promise((res) => { const rd = new FileReader(); rd.onload = () => res(String(rd.result || '')); rd.readAsDataURL(blob); });
        try { const d: any = await osApi('transcribe', { b64, mime: blob.type }); if (d?.text) setText((t) => (t ? t + ' ' : '') + d.text); }
        catch (_e) { setMsgs((m) => [...m, { role: 'assistant', content: 'Could not transcribe that.' }]); }
      };
      mr.start(); setRec(true);
    } catch (_e) { setMsgs((m) => [...m, { role: 'assistant', content: 'Microphone unavailable.' }]); }
  };
  // "Good morning" — the overnight brief, read out. speechSynthesis is the browser's own voice.
  const sayBrief = async () => {
    setSpeak(true);
    try {
      const d: any = await osApi('ws.exec_home');
      const brief = 'Good morning. Company health ' + (d?.health_index ?? 'unknown') + ', mood ' + (d?.mood ?? 'unknown') + '. '
        + 'Revenue today ' + (d?.revenue_today ?? 0) + ' dirhams, ' + (d?.revenue_30d ?? 0) + ' over thirty days. '
        + (d?.suppliers_active ?? 0) + ' active suppliers, ' + (d?.customers_active ?? 0) + ' active customers. '
        + (d?.employees_working ?? 0) + ' of ' + (d?.employees ?? 0) + ' AI employees worked overnight. '
        + 'Monthly goal progress ' + (d?.goal_progress_pct ?? 0) + ' percent. '
        + ((d?.bottlenecks || []).length ? (d.bottlenecks.length + ' departments are over capacity.') : 'No department is over capacity.');
      setMsgs((m) => [...m, { role: 'assistant', content: brief }]);
      const u = new SpeechSynthesisUtterance(brief); u.onend = () => setSpeak(false); window.speechSynthesis.speak(u);
    } catch (_e) { setSpeak(false); }
  };
  // Landing on the console should still land on a live company, not on an empty text box. The same
  // figures the Command Center shows, one line, refreshed on the same 30s beat.
  const [eh, setEh] = React.useState<any>({});
  const loadHome = React.useCallback(() => { osApi('ws.exec_home').then(setEh).catch(() => {}); }, []);
  React.useEffect(() => { loadHome(); const t = setInterval(loadHome, 30000); return () => clearInterval(t); }, [loadHome]);

  // The return leg, on the same 30s beat as everything else on this screen. Only commands issued
  // in THIS session are followed — the full history lives in the founder inbox, and repeating it
  // here would turn a conversation into a log.
  const [threads, setThreads] = React.useState<Record<number, any>>({});
  const loadThreads = React.useCallback(() => {
    const ids = Object.keys(plans).map(Number);
    if (!ids.length) return;
    Promise.all(ids.map((id) => founderCommandThread(id).catch(() => null)))
      .then((rows) => {
        const next: Record<number, any> = {};
        for (const th of rows) if (th && (th as any).command_id) next[(th as any).command_id] = th;
        setThreads(next);
      });
  }, [plans]);
  React.useEffect(() => { loadThreads(); const t = setInterval(loadThreads, 30000); return () => clearInterval(t); }, [loadThreads]);
  return (
    <Card className='flex flex-col h-[calc(100vh-140px)]'>
      <div className='px-5 py-3 border-b border-border flex items-center gap-2'><div className='h-8 w-8 rounded-lg bg-primary text-primary-foreground grid place-items-center font-bold'>✦</div><div><div className='font-semibold text-sm'>Command Console</div><div className='text-xs text-muted-foreground'>Instruct the Secretary — it acts across the team.</div></div></div>
      {/* THREE TIERS, NOT TEN EQUAL FIGURES (14 Aug 2026).
          This strip was ten <span>s of identical size and colour wrapped into one line, and the
          founder's objection to it was exact: "Revenue today AED 0 has the same visual weight as
          Knowledge growth 1747 revisions". It did — same 11px, same muted label, same bold value —
          so the eye had no way to find the number the company exists to move, and the biggest digit
          on the row belonged to the least consequential measure.

          The order is what the company is FOR, then the market it serves, then the machine:
            1. money and mission   — revenue, goal, health. Largest, full contrast.
            2. the marketplace     — customers, suppliers, employees actually working.
            3. the machine         — workflow, handoffs, knowledge, uptime. Ambient by design:
                                     these are healthy-by-default and only worth the founder's eye
                                     when they are not.
          AED 0 is deliberately shown at the top weight rather than softened. Zero revenue on a
          pre-revenue day is the most important true fact on the screen, and shrinking it to spare
          the look of the dashboard would be the interface telling him a comfortable story. */}
      <div className='px-5 py-2.5 border-b border-border/60 space-y-1.5'>
        <div className='flex flex-wrap items-baseline gap-x-6 gap-y-1'>
          <span className='text-muted-foreground text-[11px]'>Revenue today{' '}
            <b className='text-foreground tabular-nums text-base font-semibold'>{eh.revenue_today != null ? aed(eh.revenue_today) : '—'}</b>
            {eh.revenue_30d != null ? <span className='text-muted-foreground'> · {aed(eh.revenue_30d)} over 30d</span> : null}</span>
          {/* THE DENOMINATOR TRAVELS WITH THE PERCENTAGE (16 Aug 2026).
              His words about this strip: "I don't know actually from where they're getting the
              figures". For these two he was right to ask, and the answer was already in the same
              payload and thrown away one line before rendering. 49.1% is 49.1% across 22 MEASURED
              goals of 61 — 39 goals this month have a target and no measurement at all — and
              fn_ws_exec_home has returned goal_measured and goal_count all along, carrying the rule
              in its own comment: "no surface publishes a percentage without the coverage it rests
              on". The database obeyed it; the screen did not. */}
          <span className='text-muted-foreground text-[11px]'>Monthly goal{' '}
            <b className='text-foreground tabular-nums text-base font-semibold'>{eh.goal_progress_pct != null ? eh.goal_progress_pct + '%' : '—'}</b>
            {eh.goal_count != null ? <span className='text-muted-foreground'> · {eh.goal_measured ?? 0} of {eh.goal_count} goals measured</span> : null}</span>
          <span className='text-muted-foreground text-[11px]'>Company health{' '}
            <b className='text-foreground tabular-nums text-base font-semibold'>{eh.health_index ?? '—'}</b>
            {eh.mood ? <span className='text-muted-foreground'> · {titleCase(String(eh.mood))}</span> : null}</span>
        </div>
        {/* And the sentence that explains the health figure, which fn_health_index computes, returns
            as `health_note`, and the screen discarded. He was told the company needs attention and
            not told what or why, when the cause and its magnitude were in the same response. */}
        {eh.health_note ? <div className='text-[11px] text-muted-foreground'>{eh.health_note}</div> : null}
        <div className='flex flex-wrap items-baseline gap-x-5 gap-y-1 text-xs'>
          <span className='text-muted-foreground'>Active customers <b className='text-foreground tabular-nums'>{eh.customers_active ?? '—'}</b></span>
          <span className='text-muted-foreground'>Active suppliers <b className='text-foreground tabular-nums'>{eh.suppliers_active ?? '—'}</b></span>
          <span className='text-muted-foreground'>AI employees working <b className='text-foreground tabular-nums'>{eh.employees_working ?? '—'}</b> / {eh.employees ?? '—'}</span>
        </div>
        {/* The four boards the command centre measured constantly and showed nowhere. Kept on this
            screen, because the point of a command centre is that they are on ONE screen — six
            boards across six modules is a sidebar — but sized as the telemetry they are. */}
        <div className='flex flex-wrap items-baseline gap-x-4 gap-y-1 text-[11px] text-muted-foreground'>
          <span>Live workflow <b className='tabular-nums'>{eh.workflow_runs_24h ?? '—'}</b> runs/24h</span>
          {/* "AI collaboration 26 handoffs/24h" WAS EVENT DELIVERIES (fixed in SQL, 16 Aug 2026).
              A handoff is one employee formally accepting accountable work from another — packet,
              acceptance criteria, return owner. Real handoff runs: 0. The 26 were rows on the
              message bus. Both are shown, each under its own name; the handoff figure reading 0 is
              the honest state of the runtime, not a regression. */}
          <span>Handoffs <b className='tabular-nums'>{eh.handoffs_24h ?? '—'}</b>/24h</span>
          <span>Events delivered <b className='tabular-nums'>{eh.events_delivered_24h ?? '—'}</b>/24h</span>
          <span>Knowledge growth <b className='tabular-nums'>{eh.knowledge_revisions_7d ?? '—'}</b> revisions/7d</span>
          <span>Infrastructure uptime <b className='tabular-nums'>{eh.uptime_pct_24h != null ? eh.uptime_pct_24h + '%' : '—'}</b></span>
        </div>
      </div>
      <div className='flex-1 overflow-auto p-4 space-y-3'>
        {/* WHAT NEEDS HIM, ON THE SCREEN HE ACTUALLY OPENS.
            The console's empty state was one line of instructions and ~650px of void, on the one
            screen the founder opens to run the company - which is what "the dashboard is still
            basic" means. Measured at the same moment from fn_founder_queue: 27 decisions waiting
            on him, the oldest 36 days, including "Core legal documents missing", "Customers have
            not accepted current terms", "Auth hardening review" and "Open fraud flags".
            fn_founder_queue's own comment had already named the gap - "Nothing surfaces them. Not
            the OS dashboard, not an email, not the command channel" - and it since reached the
            WhatsApp channel and nothing else. No new figures are computed here; this renders the
            answer that already existed. It replaces the instruction line only when there is
            something to show, so an empty queue returns the console to a clean canvas. */}
        {!msgs.length ? <FounderQueue /> : null}
        {msgs.map((m, i) => (<div key={i} className={cn('max-w-[80%] rounded-xl px-3.5 py-2.5 text-sm whitespace-pre-wrap', m.role === 'user' ? 'ml-auto bg-primary text-primary-foreground' : 'bg-foreground/5')}>{m.content}</div>))}
        {busy ? <div className='text-sm text-muted-foreground'>…</div> : null}
        {confirm ? <div className='flex gap-2'><Button size='sm' onClick={() => decide('confirm')}>Confirm</Button><Button size='sm' variant='outline' onClick={() => decide('cancel')}>Cancel</Button></div> : null}
        {/* PROGRESS AND COMPLETION RETURN TO THE FOUNDER — the last link of the chain.
            A command used to reach `tasks_created` and stay there for ever: nothing moved it when
            an employee started, got stuck or finished. The state is now derived from its tasks at
            the moment a task moves, so it cannot lag and cannot silently stop, and this is where
            the founder reads it — in the same thread he gave the order in, not on another screen. */}
        {Object.keys(threads).length ? (
          <div className='space-y-2 pt-1'>
            {Object.values(threads).map((th: any) => (
              <div key={th.command_id} className='rounded-xl border border-border bg-background/60 px-3.5 py-2.5 text-sm'>
                <div className='flex items-center justify-between gap-3'>
                  <span className='font-medium'>Command {th.command_id}</span>
                  <Badge variant={th.state === 'completed' ? 'default' : th.state === 'partially_blocked' ? 'destructive' : 'secondary'}>
                    {String(th.state || '').replace(/_/g, ' ')}
                  </Badge>
                </div>
                {(th.workflows || []).length ? <div className='text-xs text-muted-foreground pt-0.5'>{th.workflows.join(' · ')}</div> : null}
                <div className='pt-1.5 space-y-1'>
                  {(th.tasks || []).map((t: any) => (
                    <div key={t.task_id} className='flex items-baseline justify-between gap-3 text-xs'>
                      <span className='text-muted-foreground'>
                        <b className='text-foreground'>{t.owner_name || t.owner}</b>
                        {t.department ? ' · ' + t.department : ''}
                        {t.blocker ? <span className='text-destructive'> — blocked: {t.blocker}</span> : null}
                      </span>
                      <span className='tabular-nums text-muted-foreground'>{String(t.state || '').replace(/_/g, ' ')}</span>
                    </div>
                  ))}
                </div>
                {(th.progress || []).length ? (
                  <div className='pt-2 space-y-1 border-t border-border/60 mt-2'>
                    {th.progress.map((n: any) => (
                      <div key={n.note_id} className='text-xs text-muted-foreground'>
                        <b className='text-foreground'>{n.by_name || n.by}</b>: {n.note}
                      </div>
                    ))}
                  </div>
                ) : null}
                {th.completion?.summary
                  ? <div className='pt-2 mt-2 border-t border-border/60 text-xs'>{th.completion.summary}</div>
                  : null}
              </div>
            ))}
          </div>
        ) : null}
        <div ref={endRef} />
      </div>
      {atts.length ? <div className='px-4 flex flex-wrap gap-1.5'>{atts.map((a, i) => (<Badge key={i} variant='secondary' className='cursor-pointer' onClick={() => setAtts((x) => x.filter((_, j) => j !== i))}>📄 {a.name} ✕</Badge>))}</div> : null}
      <div className='p-3 border-t border-border flex items-end gap-2'>
        <input ref={fileRef} type='file' accept='image/*,application/pdf' className='hidden' onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f); e.currentTarget.value = ''; }} />
        <Button variant='outline' size='icon' onClick={() => fileRef.current?.click()}><Paperclip className='h-4 w-4' /></Button>
        <Button variant={rec ? 'default' : 'outline'} size='icon' title={rec ? 'Stop and transcribe' : 'Speak to the OS'} onClick={listen}><AudioLines className='h-4 w-4' /></Button>
        <Button variant='outline' size='icon' title='Good morning — speak the overnight brief' disabled={speak} onClick={sayBrief}><Megaphone className='h-4 w-4' /></Button>
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
  const [eh, setEh] = React.useState<any>({});
  const load = React.useCallback(() => { setBusy(true); setErr(''); Promise.all([osApi('viz'), osApi('ws.exec').catch(() => null), osApi('ws.exec_home').catch(() => null)]).then(([viz, exec, home]: any) => { setV(viz); setHealth((exec && exec.command && exec.command.health) || {}); setEh(home || {}); }).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  // The lobby refreshes itself. Revenue, customers and suppliers move without a reload, which is
  // what "live company state" means — a landing screen you have to refresh is a report.
  React.useEffect(() => { const t = setInterval(load, 30000); return () => clearInterval(t); }, [load]);
  if (err && !v) return <Card className='p-6 text-sm text-destructive'>Could not load command center: {err}</Card>;
  if (!v) return <div className='text-muted-foreground text-sm'>Loading command center…</div>;
  const bottlenecks = (eh.bottlenecks || []) as any[]; const departments = (eh.departments || []) as any[];
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

      {/* ── THE LIVE COMPANY STATE ────────────────────────────────────────────────────────────
          Nine figures the company already computes every night and never showed anyone. Each is
          taken from the routine that owns it, so this strip can never disagree with the module it
          links to. It re-reads itself every 30 seconds. */}
      <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-3'>
        <StatTile label='Company health' value={eh.health_index != null ? eh.health_index + ' / 100' : '—'} hint={eh.mood ? titleCase(String(eh.mood)) : undefined} onClick={() => onNav('health')} />
        <StatTile label='Revenue today (AED)' value={eh.revenue_today != null ? aed(eh.revenue_today) : '—'} onClick={() => onNav('finance')} />
        <StatTile label='Revenue this month (AED)' value={eh.revenue_30d != null ? aed(eh.revenue_30d) : '—'} hint='rolling 30 days' onClick={() => onNav('finance')} />
        {/* The hint said "61 monthly targets", which reads as 61 things being tracked. 39 of them
            have no measurement at all, so the percentage rests on 22. Say which. */}
        <StatTile label={'Monthly goal progress'} value={eh.goal_progress_pct != null ? eh.goal_progress_pct + '%' : '—'} hint={eh.goal_count ? (eh.goal_measured ?? 0) + ' of ' + eh.goal_count + ' ' + String(eh.goal_horizon || '') + ' goals measured' : undefined} onClick={() => onNav('company')} />
        <StatTile label='Active customers' value={eh.customers_active} onClick={() => onNav('customers')} />
        <StatTile label='Active suppliers' value={eh.suppliers_active} hint='quoting in 30 days' onClick={() => onNav('suppliers')} />
        <StatTile label='AI employees working' value={(eh.employees_working ?? '—') + ' / ' + (eh.employees ?? '—')} hint='ran in the last 24 hours' onClick={() => onNav('agents')} />
        <StatTile label='Company mood' value={eh.mood ? titleCase(String(eh.mood)) : '—'} hint='business health band' onClick={() => onNav('health')} />
        <StatTile label='Bottlenecks' value={bottlenecks.length} hint='departments over capacity' onClick={() => onNav('operations')} />
      </div>

      {/* ── THE COMPANY AT WORK ───────────────────────────────────────────────────────────────
          Seven of the nine tiles above can only be non-zero once the marketplace transacts, and
          on 10 Aug 2026 seven of them were: revenue 0, customers 0, suppliers 0, pipeline empty.
          The founder opened this screen and said it "looks extremely basic still" — and he was
          right, because it was showing him the company he does not have yet instead of the one
          that is already running: 746 agent runs and 180 events in a day, 20,470 leads, 1,754
          knowledge revisions in a week.

          FOUR OF THESE WERE ALREADY IN THE API AND RENDERED NOWHERE. fn_ws_exec_home added
          workflow_runs_24h, handoffs_24h, knowledge_revisions_7d and uptime_pct_24h under a
          comment reading "FOUR BOARDS THAT WERE MEASURED CONSTANTLY AND SHOWN NOWHERE" — and then
          this component never read them. That is the exact defect the Row #3 spec exists to
          catch, one layer further up: computed, returned over the API, still not on a screen. */}
      <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-3'>
        <StatTile label='Leads sourced' value={eh.leads_total != null ? Number(eh.leads_total).toLocaleString() : '—'} hint='suppliers found, not yet registered' onClick={() => onNav('suppliers')} />
        <StatTile label='Agent runs today' value={eh.agent_runs_24h != null ? Number(eh.agent_runs_24h).toLocaleString() : '—'} hint='last 24 hours' onClick={() => onNav('agents')} />
        <StatTile label='Workflows run today' value={eh.workflow_runs_24h ?? '—'} hint='last 24 hours' onClick={() => onNav('operations')} />
        <StatTile label='Events on the bus' value={eh.events_24h != null ? Number(eh.events_24h).toLocaleString() : '—'} hint='last 24 hours' onClick={() => onNav('company_os')} />
        {/* Was 'Handoffs delivered' reading event_delivery — a tile whose label and whose source
            were about different things. Now each is itself: 'Events on the bus' above is company
            events, this is the message bus, and a handoff is counted only when one employee
            formally accepts accountable work from another. */}
        <StatTile label='Events delivered' value={eh.events_delivered_24h != null ? Number(eh.events_delivered_24h).toLocaleString() : '—'} hint='message bus, last 24 hours' onClick={() => onNav('operations')} />
        <StatTile label='Handoffs between employees' value={eh.handoffs_24h != null ? Number(eh.handoffs_24h).toLocaleString() : '—'} hint='accepted work, last 24 hours' onClick={() => onNav('operations')} />
        <StatTile label='Decisions waiting' value={eh.decisions_open ?? '—'} hint='review queue' onClick={() => onNav('escalations')} />
        <StatTile label='Open tasks' value={eh.tasks_open ?? '—'} hint='across every department' onClick={() => onNav('operations')} />
        <StatTile label='Knowledge updated' value={eh.knowledge_revisions_7d != null ? Number(eh.knowledge_revisions_7d).toLocaleString() : '—'} hint='revisions in 7 days' onClick={() => onNav('knowledge')} />
        <StatTile label='Uptime' value={eh.uptime_pct_24h != null ? eh.uptime_pct_24h + '%' : '—'} hint='edge probes, last 24 hours' onClick={() => onNav('health')} />
      </div>

      {bottlenecks.length ? <SectionCard title='Where the company is blocked right now' count={bottlenecks.length}>
        <div className='divide-y divide-border'>{bottlenecks.map((b: any, i: number) => (
          <div key={i} className='px-4 py-2.5 flex items-center gap-3 text-sm'>
            <Chip label={String(b.state)} tone={b.state === 'HALT' ? 'red' : 'amber'} />
            <div className='min-w-0 flex-1'><span className='font-medium'>{b.resource}</span>
              <span className='text-muted-foreground'> — {titleCase(String(b.department))}</span></div>
            <span className='tabular-nums text-muted-foreground shrink-0'>{b.committed}/{b.capacity} {b.unit} · {b.used_pct}%</span>
          </div>))}</div>
      </SectionCard> : null}

      {departments.length ? <SectionCard title='Departments' count={departments.length}
        right={<span className='text-[11px] text-muted-foreground'>agent runs in the last 24 hours</span>}>
        <div className='p-4 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2'>{departments.map((d: any, i: number) => (
          <button key={i} onClick={() => onNav('agents')} className={cn('rounded-md border px-3 py-2 text-left transition-colors hover:bg-foreground/5', d.busy ? 'border-emerald-500/40 bg-emerald-500/[0.06]' : 'border-border')}>
            <div className='text-sm font-medium truncate'>{d.department}</div>
            <div className='text-[11px] text-muted-foreground flex items-center gap-1.5'>
              <span className={cn('inline-block h-1.5 w-1.5 rounded-full', d.busy ? 'bg-emerald-500 animate-pulse' : 'bg-foreground/20')} />
              {d.runs} run{d.runs === 1 ? '' : 's'}{d.health != null ? ' · health ' + d.health : ''}
            </div>
          </button>))}</div>
      </SectionCard> : null}

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
  const [row, setRow] = React.useState<any>(null);
  const load = React.useCallback(() => { setD(null); Promise.all([osApi('inbox').catch(() => null), osApi('ws.exec').catch(() => null)]).then(([inbox, exec]) => setD({ inbox, attention: (exec && exec.command && exec.command.attention) || [] })).catch((e) => setErr(e.message)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const openItem = (it: any) => { setSel(it); setDraft(it.draft || ''); setMsg(''); };
  const send = async () => { if (!sel) return; setBusy(true); setMsg(''); try { await osApi('inbox_send', { id: sel.id, body: draft }); setSel(null); load(); } catch (e: any) { setMsg('Could not send: ' + (e?.message || 'error')); } setBusy(false); };
  const [dbusy, setDbusy] = React.useState<string | null>(null);
  const decide = async (id: any, op: string) => { setDbusy(String(id) + op); try { await osOps('action_decide', { id, op }); load(); } catch (_e) { } setDbusy(null); };
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
          <div key={a.id} onClick={() => setRow({ entity: 'agent_action', id: a.id, title: (a.kind_label || titleCase(String(a.kind || 'decision'))), row: a })} className='px-4 py-3 flex items-center justify-between gap-3 hover:bg-foreground/5 transition-colors cursor-pointer'>
            {/* Every action explains itself: which OS owned it, why, and what happened after —
                and clicking it opens the full record, which is where the explanation lives. */}
            <div className='min-w-0'><div className='text-sm truncate flex items-center gap-2'>{(a.kind_label || titleCase(String(a.kind || 'decision')))} · <span className='text-muted-foreground'>{a.actor}</span>{a.os ? <Chip label={titleCase(String(a.os)) + ' OS'} tone='slate' /> : null}{a.risk ? <Chip label={a.risk} tone={riskTone(String(a.risk))} /> : null}</div>
              <div className='text-xs text-muted-foreground truncate'>{a.title || a.decision} → {a.route_to}</div>
              {Array.isArray(a.reasons) && a.reasons.length ? <div className='text-[11px] text-muted-foreground truncate'>Why: {a.reasons.join(' · ')}</div> : null}
              {a.outcome ? <div className='text-[11px] text-muted-foreground truncate'>After: {a.outcome}</div> : null}
              {/* Under which rule. action_autonomy decides whether the sweep may clear this kind
                  or the founder must see it; confidence_min is the floor this action's own
                  confidence was measured against. Both come from decision_policy as stored. */}
              {Array.isArray(a.policies) && a.policies.length ? <div className='text-[11px] text-muted-foreground'>Policies: {a.policies.join(' · ')}</div> : null}
              {/* The score the acting agent assigned to its own action. It was already being sent
                  here and drawn nowhere, so the founder was told which floor the action was measured
                  against and never the measurement. Null stays absent rather than rendering a 0%:
                  an agent that reported no confidence has not reported low confidence. */}
              {a.confidence != null ? <div className='text-[11px] text-muted-foreground'>Confidence: {Math.round(Number(a.confidence) * 100)}%</div> : null}
              {/* What else the gate could have done. Two options, the taken one marked — an action
                  gated before 6 Aug carries none, because no evaluation was recorded for it, and an
                  absent line is the honest rendering of that. */}
              {Array.isArray(a.alternatives) && a.alternatives.length ? <div className='text-[11px] text-muted-foreground truncate'>Alternatives: {a.alternatives.map((o: any) => String(o?.option || '') + (o?.selected ? ' (taken)' : '')).join(' · ')}</div> : null}</div>
            <div className='flex items-center gap-1.5 shrink-0' onClick={(e) => e.stopPropagation()}>
              <Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'approve'} onClick={() => decide(a.id, 'approve')}>{dbusy === String(a.id) + 'approve' ? '…' : 'Approve'}</Button>
              <Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'reject'} onClick={() => decide(a.id, 'reject')}>{dbusy === String(a.id) + 'reject' ? '…' : 'Reject'}</Button>
              <button onClick={() => onNav('agents')} title='Review in Smart Engine' className='text-muted-foreground hover:text-foreground'><ArrowUpRight className='h-4 w-4' /></button>
            </div>
          </div>
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
      {row ? <RecordDrawer frame0={{ entity: 'agent_action', id: row.id, title: row.title, row: row.row }} onClose={() => setRow(null)} /> : null}
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

// ── Smart table cell: colored status/priority/risk chips, progress bars, money — Odoo/NetSuite-style ──
const CHIP_TONE: Record<string, string> = { green: 'bg-emerald-500/15 text-emerald-600', amber: 'bg-amber-500/15 text-amber-600', red: 'bg-red-500/15 text-red-600', blue: 'bg-blue-500/15 text-blue-600', slate: 'bg-foreground/[0.07] text-muted-foreground', violet: 'bg-violet-500/15 text-violet-600' };
function Chip({ label, tone }: { label: string; tone: string }) { return <span className={cn('inline-flex items-center text-[11px] px-1.5 py-0.5 rounded-full font-medium capitalize whitespace-nowrap', CHIP_TONE[tone] || CHIP_TONE.slate)}>{label}</span>; }
function statusTone(v: string): string { const s = String(v).toLowerCase(); if (/(done|resolved|approved|success|active|healthy|passed|paid|won|live|verified|closed|covered|complete|granted|ok\b)/.test(s)) return 'green'; if (/(error|fail|banned|rejected|critical|urgent|overdue|lost|blocked|gap|down|breach|denied)/.test(s)) return 'red'; if (/(pending|open|held|review|untriaged|draft|queued|waiting|matched|thin|warn|attention|hold|new\b)/.test(s)) return 'amber'; if (/(low|info|quoted|revealed|sent|sourced|contacted|invited|closed)/.test(s)) return 'slate'; return 'blue'; }
function priorityTone(v: string): string { const s = String(v).toLowerCase(); if (/(urgent|critical|p0|p1)/.test(s)) return 'red'; if (/high/.test(s)) return 'amber'; if (/(normal|medium|p2)/.test(s)) return 'blue'; return 'slate'; }
function riskTone(v: string): string { const s = String(v).toLowerCase(); if (/(critical|severe|high)/.test(s)) return 'red'; if (/(medium|moderate|warn)/.test(s)) return 'amber'; if (/(low|info|minimal)/.test(s)) return 'slate'; return 'blue'; }
function SmartCell({ col, value }: { col: string; value: any }) {
  const c = col.toLowerCase();
  if (value == null || value === '') return <span className='text-muted-foreground'>—</span>;
  if (typeof value === 'boolean') return <Chip label={value ? 'Yes' : 'No'} tone={value ? 'green' : 'slate'} />;
  if (typeof value !== 'object') {
    if (/(^|_)(status|state|outcome|decision|band|verdict)$/.test(c)) return <Chip label={titleCase(String(value))} tone={statusTone(String(value))} />;
    if (/priority/.test(c)) return <Chip label={titleCase(String(value))} tone={priorityTone(String(value))} />;
    if (/(risk|severity)/.test(c)) return <Chip label={titleCase(String(value))} tone={riskTone(String(value))} />;
    if (/(pct|percent|coverage|rate|progress)$/.test(c) && typeof value === 'number') { const pct = value <= 1 ? value * 100 : value; return <div className='flex items-center gap-2 min-w-[96px]'><div className='flex-1 h-1.5 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-primary' style={{ width: Math.max(2, Math.min(100, pct)) + '%' }} /></div><span className='text-[11px] text-muted-foreground tabular-nums'>{Math.round(pct)}%</span></div>; }
    if (/(source|actor|route_to|department|kind|type|agent|channel)$/.test(c) && typeof value === 'string' && value.length < 40) return <span className='inline-flex items-center text-[11px] px-1.5 py-0.5 rounded bg-foreground/[0.05] text-foreground/70 whitespace-nowrap'>{value}</span>;
    if (/(amount|value|balance|revenue|expense|cash|fee|budget|price|total|confidence|score)$/.test(c) && typeof value === 'number') return <span className='tabular-nums'>{value.toLocaleString()}</span>;
  }
  return <span className='break-words'>{fmt(value)}</span>;
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

// ── RFQ 360 detail — request · matched suppliers · quotes side-by-side · procurement · actions ──
function RfqDetailDrawer({ id, title, onClose, onChanged }: { id: any; title: string; onClose: () => void; onChanged: () => void }) {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState('');
  const [stages, setStages] = React.useState<any[]>([]); const [busy, setBusy] = React.useState('');
  const [docBusy, setDocBusy] = React.useState('');
  const load = React.useCallback(() => { setD(null); osApi('ws.rfq', { id }).then((r: any) => setD(r && r.error ? null : r)).catch((e: any) => setErr(e.message)); }, [id]);
  React.useEffect(() => { load(); osOps('stages_list').then((s: any) => setStages(Array.isArray(s) ? s : [])).catch(() => {}); }, [load]);
  const act = async (fn: () => Promise<any>) => { try { await fn(); load(); onChanged(); } catch (_e) {} setBusy(''); };
  const setStage = (stage: string) => { setBusy('stage'); act(() => osOps('rfq_stage', { inquiry: id, stage })); };
  const setOutcome = (outcome: string) => { setBusy(outcome); act(() => osOps('rfq_outcome', { inquiry: id, outcome })); };
  const award = (qt: any) => { setBusy('award' + qt.id); act(async () => { await osOps('note_add', { entity: 'rfq', id, body: 'Awarded to ' + (qt.company_name || 'supplier #' + qt.supplier_id) + ' — AED ' + Number(qt.amount || 0).toLocaleString() }); await osOps('rfq_outcome', { inquiry: id, outcome: 'won' }); }); };
  const openDoc = async (doc: any) => { const key = doc.path || doc.name; setDocBusy(key); try { const r: any = await osApi('file', { bucket: 'inquiry-docs', path: doc.path }); if (r && r.url) window.open(r.url, '_blank', 'noopener'); } catch (_e) {} setDocBusy(''); };
  const req = d?.requirements || {}; const st = d?.status || {}; const aiq = d?.ai_qualification || {}; const matching = d?.matching || []; const quotes = d?.quotes || []; const clar = d?.clarifications || []; const timeline = d?.timeline || []; const docs = d?.documents || []; const sel = d?.selected_supplier; const proc = d?.procurement;
  const lowest = quotes.length ? Math.min(...quotes.filter((q: any) => q.amount != null).map((q: any) => Number(q.amount))) : null;
  const compl = Number(aiq.completeness) || 0; const complPct = compl <= 1 ? compl * 100 : compl;
  const sub = (label: string) => (<div className='px-4 py-2.5 border-b border-border text-sm font-semibold flex items-center justify-between'>{label}</div>);
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-2xl overflow-y-auto'>
    <SheetHeader>
      <div className='flex items-center gap-2 flex-wrap'>{req.category ? <span className='inline-flex items-center text-[11px] px-1.5 py-0.5 rounded-full bg-foreground/[0.06] text-foreground/70 capitalize'>{req.category}</span> : null}{st.status ? <Chip label={titleCase(String(st.status))} tone={statusTone(String(st.status))} /> : null}{st.pipeline_stage ? <Chip label={titleCase(String(st.pipeline_stage))} tone='blue' /> : null}{st.outcome ? <Chip label={titleCase(String(st.outcome))} tone={statusTone(String(st.outcome))} /> : null}</div>
      <SheetTitle className='mt-1'>{title}</SheetTitle>
      <SheetDescription>{[req.emirate, req.role_needed, st.expected_value ? 'AED ' + Number(st.expected_value).toLocaleString() : null].filter(Boolean).join(' · ')}</SheetDescription>
    </SheetHeader>
    {!d && !err ? <div className='mt-4 text-sm text-muted-foreground'>Loading RFQ…</div> : err ? <div className='mt-4 text-sm text-destructive'>{err}</div> : <>
      <div className='mt-3 flex flex-wrap items-center gap-2'>
        {stages.length ? <select value={st.pipeline_stage || ''} disabled={busy === 'stage'} onChange={(e) => setStage(e.target.value)} className='h-8 rounded-md border border-border bg-transparent px-2 text-xs'><option value=''>Set stage…</option>{stages.map((s: any) => <option key={s.key} value={s.key}>{s.label}</option>)}</select> : null}
        <Button className='h-8 text-xs' variant='outline' disabled={!!busy} onClick={() => setOutcome('won')}>Mark won</Button>
        <Button className='h-8 text-xs' variant='outline' disabled={!!busy} onClick={() => setOutcome('lost')}>Mark lost</Button>
      </div>
      {sel ? <Card className='mt-4 p-3 border-emerald-500/30 bg-emerald-500/[0.04]'><div className='text-[11px] uppercase tracking-wide text-emerald-600 mb-0.5'>Selected supplier</div><div className='text-sm font-semibold'>{sel.company_name || 'Supplier #' + sel.id}</div></Card> : null}

      {quotes.length ? <Card className='mt-4 overflow-hidden'>{sub('Quotes · side by side (' + quotes.length + ')')}
        <div className='p-3 flex gap-3 overflow-x-auto'>{quotes.map((qt: any) => { const isLow = lowest != null && Number(qt.amount) === lowest; return (
          <div key={qt.id} className={cn('w-56 shrink-0 rounded-lg border p-3', isLow ? 'border-emerald-500/50 bg-emerald-500/[0.04]' : 'border-border')}>
            <div className='flex items-center justify-between'><span className='text-sm font-semibold line-clamp-1'>{qt.company_name || 'Supplier #' + qt.supplier_id}</span>{isLow ? <Chip label='Lowest' tone='green' /> : null}</div>
            <div className='text-xl font-bold tabular-nums mt-1'>{qt.amount != null ? 'AED ' + Number(qt.amount).toLocaleString() : '—'}</div>
            <div className='mt-2 space-y-1 text-[11px] text-muted-foreground'>{qt.lead_time ? <div>Lead time: <span className='text-foreground'>{qt.lead_time}</span></div> : null}{qt.quality ? <div>Quality: <span className='text-foreground'>{qt.quality}</span></div> : null}{qt.status ? <div className='pt-0.5'><Chip label={titleCase(String(qt.status))} tone={statusTone(String(qt.status))} /></div> : null}</div>
            <Button className='h-7 text-xs w-full mt-2' variant='outline' disabled={!!busy} onClick={() => award(qt)}>{busy === 'award' + qt.id ? '…' : 'Award'}</Button>
          </div>); })}</div></Card> : null}

      <Card className='mt-4 overflow-hidden'>{sub('Requirements')}<div className='p-4 grid grid-cols-1 sm:grid-cols-2 gap-x-6'>{([['Summary', req.summary], ['Scope', req.scope_type], ['Budget', req.budget], ['Trades', Array.isArray(req.trades) ? req.trades.join(', ') : req.trades], ['BoQ confidence', req.boq_confidence], ['Keywords', Array.isArray(req.keywords) ? req.keywords.join(', ') : req.keywords]] as [string, any][]).filter(([, v]) => v != null && v !== '').map(([k, v]) => (<div key={k} className='flex flex-col py-1.5 border-b border-border/40'><span className='text-[11px] text-muted-foreground'>{k}</span><span className='text-sm break-words'>{fmt(v)}</span></div>))}</div>{req.spec ? <div className='px-4 pb-4'><div className='text-[11px] text-muted-foreground mb-1'>Spec</div><div className='text-sm whitespace-pre-wrap'>{fmt(req.spec)}</div></div> : null}</Card>

      <Card className='mt-4 overflow-hidden'>{sub('AI qualification')}<div className='p-4 space-y-2'>
        <div className='flex items-center gap-2'><span className='text-xs text-muted-foreground w-24'>Completeness</span><div className='flex-1 h-2 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-primary' style={{ width: Math.max(2, Math.min(100, complPct)) + '%' }} /></div><span className='text-[11px] tabular-nums text-muted-foreground'>{Math.round(complPct)}%</span></div>
        <div className='flex flex-wrap gap-2 text-xs'>{aiq.rfq_ready != null ? <Chip label={aiq.rfq_ready ? 'RFQ ready' : 'Not ready'} tone={aiq.rfq_ready ? 'green' : 'amber'} /> : null}{aiq.routing ? <span className='text-muted-foreground'>Routing: {fmt(aiq.routing)}</span> : null}{aiq.brief_source ? <span className='text-muted-foreground'>Source: {aiq.brief_source}</span> : null}</div>
      </div></Card>

      {matching.length ? <Card className='mt-4 overflow-hidden'>{sub('Matched suppliers (' + matching.length + ')')}<div className='divide-y divide-border'>{matching.map((m: any, i: number) => { const sim = Number(m.similarity) || 0; const simPct = sim <= 1 ? sim * 100 : sim; return (
        <div key={i} className='px-4 py-2.5'><div className='flex items-center justify-between gap-2'><span className='text-sm font-medium line-clamp-1'>{m.company_name || 'Supplier #' + m.supplier_id}</span><span className='text-[11px] text-muted-foreground tabular-nums'>{Math.round(simPct)}% match</span></div><div className='h-1.5 rounded-full bg-foreground/[0.06] overflow-hidden mt-1'><div className='h-full rounded-full bg-primary' style={{ width: Math.max(2, Math.min(100, simPct)) + '%' }} /></div>{m.match_reason ? <div className='text-[11px] text-muted-foreground mt-1 line-clamp-2'>{m.match_reason}</div> : null}</div>); })}</div></Card> : null}

      {docs.length ? <Card className='mt-4 overflow-hidden'>{sub('Documents')}<div className='p-2'>{docs.map((f: any, i: number) => (<div key={i} className='flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-foreground/5'><FileText className='h-4 w-4 text-muted-foreground shrink-0' /><span className='text-sm min-w-0 truncate'>{f.type || f.name}</span><Button className='h-7 text-xs ml-auto' variant='outline' disabled={docBusy === (f.path || f.name)} onClick={() => openDoc(f)}>{docBusy === (f.path || f.name) ? 'Opening…' : 'Open'}</Button></div>))}</div></Card> : null}

      {proc && (typeof proc !== 'object' || Object.keys(proc).length) ? <Card className='mt-4 overflow-hidden'>{sub('Procurement analysis')}<div className='p-4'><ReadableObject data={proc} /></div></Card> : null}

      {clar.length ? <Card className='mt-4 overflow-hidden'>{sub('Clarifications (' + clar.length + ')')}<div className='divide-y divide-border'>{clar.map((c: any, i: number) => (<div key={i} className='px-4 py-2.5'><div className='text-sm'>{c.question}</div>{c.answer ? <div className='text-sm text-muted-foreground mt-0.5'>↳ {c.answer}</div> : <div className='text-[11px] text-amber-600 mt-0.5'>Awaiting answer</div>}<div className='text-[11px] text-muted-foreground mt-0.5'>{fmt(c.asked_at)}</div></div>))}</div></Card> : null}

      {timeline.length ? <Card className='mt-4 overflow-hidden'>{sub('Timeline')}<div className='p-4'>{timeline.map((t: any, i: number) => (<div key={i} className='flex gap-3 pb-3 last:pb-0'><div className='flex flex-col items-center'><div className='h-2 w-2 rounded-full bg-primary mt-1.5' />{i < timeline.length - 1 ? <div className='w-px flex-1 bg-border my-1' /> : null}</div><div className='min-w-0 flex-1'><div className='text-sm'>{t.event}</div><div className='text-[11px] text-muted-foreground'>{fmt(t.at)}</div></div></div>))}</div></Card> : null}

      <ActivityPanel entity='rfq' id={id} />
    </>}
  </SheetContent></Sheet>);
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
    {row ? <RfqDetailDrawer id={row.id} title={titleCase(String(row.category || 'RFQ')) + ' · ' + (row.emirate || '')} onChanged={() => load(q)} onClose={() => setRow(null)} /> : null}
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
  const [ops, setOps] = React.useState<any>(null); const [dbusy, setDbusy] = React.useState('');
  const load = React.useCallback(() => { osApi('ws.agent', { key: agent.agent_key }).then(setOps).catch(() => setOps({})); }, [agent.agent_key]);
  React.useEffect(() => { load(); }, [load]);
  const decide = async (id: any, op: string) => { setDbusy(String(id) + op); try { await osOps('action_decide', { id, op }); load(); } catch (_e) {} setDbusy(''); };
  const goal = ops?.goal || {}; const tasks = ops?.tasks || {}; const decisions = ops?.decisions || []; const confidence = ops?.confidence || {}; const workload = ops?.workload || {}; const plans = ops?.plans || []; const knowledge = ops?.knowledge || {};
  const id = ops?.identity || {}; const h = ops?.health || {}; const perf = ops?.performance || {}; const queue = ops?.queue || []; const runs = ops?.recent_runs || []; const kn = ops?.knowledge || {}; const mem = ops?.memory || {}; const convos = ops?.conversations || []; const recs = ops?.recommendations || [];
  // IS THIS EMPLOYEE GETTING BETTER? The drawer showed goal, tasks, decisions, confidence, workload,
  // plans, knowledge, health, performance, queue, runs, memory, conversations and recommendations —
  // everything except that. knowledge_exam_results (576 graded answers over 98 employees) and
  // skills_matrix (695 rows) had no browser-reachable reader at all: the company examines its staff
  // every four hours and could not show one of them their own curve.
  const learn = ops?.learning || {};
  const curriculum = ops?.curriculum || {};
  const kpiTrend: any[] = Array.isArray(ops?.kpi_trend) ? ops.kpi_trend : [];
  const healthTone = /healthy/.test(String(h.status)) ? 'green' : /degraded|error|fail/.test(String(h.status)) ? 'red' : /stale/.test(String(h.status)) ? 'amber' : 'slate';
  const sub = (label: string, extra?: any) => (<div className='px-4 py-2.5 border-b border-border text-sm font-semibold flex items-center justify-between'>{label}{extra}</div>);
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-2xl overflow-y-auto'>
    <SheetHeader>
      <SheetTitle className='flex items-center gap-2'>{id.emoji ? <span>{id.emoji}</span> : null}{id.name || titleCase(String(agent.agent_key))}<Chip label={titleCase(String(h.status || 'idle'))} tone={healthTone} /></SheetTitle>
      <SheetDescription>{[agent.department, id.prompt_desc || agent.role, id.prompt_version ? 'prompt v' + id.prompt_version : null].filter(Boolean).join(' · ')}</SheetDescription>
    </SheetHeader>
    {ops === null ? <div className='mt-4 text-sm text-muted-foreground'>Loading agent operations…</div> : <>
      {/* ── WHAT THIS EMPLOYEE IS ACTUALLY DOING ────────────────────────────────────────────────
          Goal, tasks, decisions, confidence, workload and plans. All six were computed elsewhere in
          the estate and reached no screen; the drawer showed identity, health and run counts only. */}
      <Card className='mt-4 p-4'>
        <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>Current goal</div>
        <div className='text-sm font-medium mt-0.5'>{goal.objective || '—'}</div>
        <div className='text-[11px] text-muted-foreground mt-1 flex flex-wrap items-center gap-x-2'>
          {goal.horizon ? <span>{titleCase(String(goal.horizon))}</span> : null}
          {goal.metric ? <span>· {goal.metric}{goal.target_value != null ? ' target ' + goal.target_value + (goal.unit || '') : ''}</span> : null}
          <span>· from {titleCase(String(goal.goal_source || 'none'))}</span>
        </div>
      </Card>

      <div className='mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2'>
        <StatTile label='Runs 24h' value={perf.runs_24h ?? agent.runs24} />
        <StatTile label='Runs 7d' value={perf.runs_7d} />
        <StatTile label='OK rate' value={perf.ok_rate != null ? perf.ok_rate + '%' : '—'} />
        <StatTile label='Avg run' value={perf.avg_duration_ms ? Math.round(Number(perf.avg_duration_ms)) + ' ms' : '—'} />
      </div>

      {/* PERFORMANCE AS A TREND, NOT A POINT. Every tile above is a single current value, so this
          drawer could say how the employee is doing and never whether it is getting better or
          worse. employee_kpi_history writes one row per KPI per UTC day — a unique index makes a
          fabricated trend impossible — and until now nothing read it. The empty state says which
          of the two reasons applies rather than drawing a flat line on one point, because a line
          through a single observation is a picture of a trend that does not exist yet. */}
      <Card className='mt-3 p-4'>
        <div className='flex items-center justify-between'>
          <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>KPI attainment trend</div>
          {kpiTrend.length ? <span className='text-[11px] text-muted-foreground'>
            {kpiTrend.length} day{kpiTrend.length === 1 ? '' : 's'} · {kpiTrend[kpiTrend.length - 1]?.kpis ?? 0} KPI(s) · latest {kpiTrend[kpiTrend.length - 1]?.v ?? '—'}%
          </span> : null}
        </div>
        {kpiTrend.length > 1
          ? <div className='mt-2'>
              <MiniLine data={kpiTrend.map((p: any) => ({ label: String(p.label), v: Number(p.v) || 0 }))} />
              <div className='mt-1 flex justify-between text-[11px] text-muted-foreground'>
                <span>{kpiTrend[0]?.label}</span><span>{kpiTrend[kpiTrend.length - 1]?.label}</span>
              </div>
            </div>
          : <div className='mt-1 text-sm text-muted-foreground'>
              {kpiTrend.length === 1
                ? 'One measurement so far (' + kpiTrend[0].label + ', ' + kpiTrend[0].v + '%). A trend needs a second; KPIs are measured daily at 03:30 UTC.'
                : 'No measured KPI history for this employee yet.'}
            </div>}
      </Card>

      <div className='mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2'>
        <StatTile label='Workload' value={workload.workload_pct != null ? workload.workload_pct + '%' : '—'} hint={'capacity ' + (workload.capacity ?? '—') + ' · ' + titleCase(String(workload.state || ''))} />
        <StatTile label='Open tasks assigned' value={workload.open_tasks} hint={'queue ' + (workload.queue_depth ?? 0)} />
        <StatTile label='Confidence (reputation)' value={confidence.reputation_score != null ? confidence.reputation_score : '—'} hint={confidence.tier ? titleCase(String(confidence.tier)) : undefined} />
        <StatTile label='Confidence when deciding' value={confidence.avg_decided != null ? confidence.avg_decided : '—'} hint={(confidence.decided_with_confidence ?? 0) + ' scored decision(s)'} />
      </div>

      {(tasks.rows || []).length ? <Card className='mt-4 overflow-hidden'>{sub('Tasks assigned to ' + titleCase(String(tasks.department || 'this team')), <Badge variant='secondary'>{tasks.department_open}</Badge>)}
        <div className='divide-y divide-border'>{(tasks.rows as any[]).map((t: any) => (<div key={t.id} className='px-4 py-2.5 flex items-center gap-2 text-sm'>
          <div className='min-w-0 flex-1'><div className='truncate'>{t.title}</div>
            <div className='text-[11px] text-muted-foreground'>{titleCase(String(t.status))}{t.tier ? ' · ' + t.tier : ''}{t.needs_founder ? ' · needs founder' : ''}</div></div>
          <span className='text-[11px] text-muted-foreground shrink-0'>{fmt(t.created_at)}</span>
        </div>))}</div></Card> : null}

      {decisions.length ? <Card className='mt-4 overflow-hidden'>{sub('Recent decisions', <Badge variant='secondary'>{decisions.length}</Badge>)}
        <div className='divide-y divide-border'>{(decisions as any[]).map((x: any) => (<div key={x.id} className='px-4 py-2.5 text-sm'>
          <div className='flex items-center gap-2 flex-wrap'><span className='font-medium'>{titleCase(String(x.decision || x.kind))}</span>
            {x.confidence != null ? <Chip label={'confidence ' + x.confidence} tone={Number(x.confidence) >= 0.7 ? 'green' : Number(x.confidence) >= 0.4 ? 'amber' : 'red'} /> : null}
            {x.route_to ? <span className='text-[11px] text-muted-foreground'>→ {x.route_to}</span> : null}
            <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(x.at)}</span></div>
          {Array.isArray(x.reasons) && x.reasons.length ? <div className='text-[11px] text-muted-foreground mt-0.5'>{x.reasons.join(' · ')}</div> : null}
        </div>))}</div></Card> : null}

      {plans.length ? <Card className='mt-4 overflow-hidden'>{sub('Upcoming plans', <Badge variant='secondary'>{plans.length}</Badge>)}
        <div className='divide-y divide-border'>{(plans as any[]).map((p: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm flex items-center gap-2'>
          <div className='min-w-0 flex-1'>{p.objective}{p.measure ? <span className='text-[11px] text-muted-foreground'> — {p.measure}</span> : null}</div>
          <Chip label={String(p.scope === 'operating_system' ? 'OS' : 'Dept')} tone='slate' />
          {p.horizon ? <span className='text-[11px] text-muted-foreground shrink-0'>{titleCase(String(p.horizon))}</span> : null}
        </div>))}</div></Card> : null}

      {/* Learning progress. The trend is per DAY, oldest first, because "improving" is only visible
          as a curve — a single aggregate score cannot say whether it went up. An employee with one
          exam day shows the score and says so rather than drawing a one-point line as if it were a
          trend. */}
      <Card className='mt-4 overflow-hidden'>{sub('Learning progress', <Badge variant='secondary'>{learn.exam_results_total ?? 0} exam{(learn.exam_results_total ?? 0) === 1 ? '' : 's'}</Badge>)}
        <div className='p-3 space-y-2'>
          <div className='grid grid-cols-3 gap-2 text-xs'>
            <div><div className='opacity-60'>Exam score</div><div className='text-sm'>{learn.exam_score_pct == null ? 'not examined yet' : `${learn.exam_score_pct}%`}</div></div>
            <div><div className='opacity-60'>Gaps found</div><div className='text-sm'>{learn.knowledge_gaps_found ?? 0}</div></div>
            <div><div className='opacity-60'>Gaps filled</div><div className='text-sm'>{learn.knowledge_gaps_filled ?? 0}</div></div>
          </div>
          {(learn.exam_trend || []).length > 1
            ? <div className='space-y-1'>{(learn.exam_trend || []).map((p: any, i: number) => (
                <div key={i} className='text-xs flex items-center justify-between gap-2'>
                  <span className='opacity-60'>{p.day}</span>
                  <span>{p.score_pct == null ? '—' : `${p.score_pct}%`} <span className='opacity-50'>({p.asked})</span></span>
                </div>))}</div>
            : <div className='text-xs opacity-60'>{(learn.exam_days ?? 0) === 0
                ? 'No exam sat yet — the examiner works through the roster and has not reached this employee.'
                : 'One exam day so far, so there is no curve yet. A trend needs a second sitting.'}</div>}
          {(learn.skills || []).length ? <div className='pt-1 space-y-1'>{(learn.skills || []).map((s: any, i: number) => (
            <div key={i} className='text-xs flex items-center justify-between gap-2'><span className='truncate'>{s.skill}</span><Badge variant='secondary'>{s.rating}</Badge></div>))}</div> : null}
        </div>
      </Card>
      {(knowledge.topics || []).length ? <Card className='mt-4 overflow-hidden'>{sub('Knowledge held', <Badge variant='secondary'>{knowledge.count}</Badge>)}
        <div className='p-4 flex flex-wrap gap-1.5'>{(knowledge.topics as any[]).slice(0, 24).map((t: any, i: number) => (<Chip key={i} label={String(t)} tone='slate' />))}</div>
      </Card> : null}
      {/* WHAT THEY ARE SUPPOSED TO KNOW, next to what has been written for them. employee_knowledge
          holds 900 rows over 66 employees — the domains each is expected to cover and at what depth
          — and had no browser-reachable reader at all, so this drawer could look full while the
          employee covered one of twenty-four domains they are meant to hold. `Knowledge held` above
          is agent_knowledge, a different table: what was authored FOR them, not what is expected OF
          them. Depth is the employee_knowledge value verbatim; nothing here is inferred. */}
      {Number(curriculum.domains || 0) > 0 ? <Card className='mt-4 overflow-hidden'>{sub('Expected to know', <Badge variant='secondary'>{curriculum.domains} domain{Number(curriculum.domains) === 1 ? '' : 's'}</Badge>)}
        <div className='px-4 pt-3 flex flex-wrap gap-1.5'>{Object.entries(curriculum.by_depth || {}).map(([d, n]: any) => (<Chip key={d} label={`${d} · ${n}`} tone={d === 'expert' ? 'green' : d === 'working' ? 'amber' : 'slate'} />))}</div>
        <div className='p-4 grid gap-1'>{(curriculum.rows || []).slice(0, 40).map((r: any, i: number) => (
          <div key={i} className='text-xs flex items-center justify-between gap-2'>
            <span className='truncate text-muted-foreground'>{String(r.domain || '').replace(/^cat:/, '')}</span>
            <span className='flex items-center gap-1.5 shrink-0'>{r.layer != null ? <span className='text-[10px] text-muted-foreground tabular-nums'>layer {r.layer}</span> : null}<Chip label={String(r.depth || '—')} tone={r.depth === 'expert' ? 'green' : r.depth === 'working' ? 'amber' : 'slate'} /></span>
          </div>))}</div>
      </Card> : null}
      {queue.length ? <Card className='mt-4 overflow-hidden'>{sub('Decisions held for review', <Badge variant='secondary'>{queue.length}</Badge>)}
        <div className='divide-y divide-border'>{queue.map((a: any) => (<div key={a.id} className='px-4 py-3'>
          <div className='flex items-center justify-between gap-2'><div className='min-w-0'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{titleCase(String(a.title || a.kind || 'decision'))}{a.risk ? <Chip label={String(a.risk)} tone={riskTone(String(a.risk))} /> : null}<Chip label={titleCase(String(a.status))} tone={statusTone(String(a.status))} /></div>{a.recommendation ? <div className='text-xs text-muted-foreground mt-0.5 line-clamp-2'>{a.recommendation}</div> : null}</div></div>
          <div className='flex gap-1.5 mt-2'><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'approve'} onClick={() => decide(a.id, 'approve')}>{dbusy === String(a.id) + 'approve' ? '…' : 'Approve'}</Button><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'reject'} onClick={() => decide(a.id, 'reject')}>{dbusy === String(a.id) + 'reject' ? '…' : 'Reject'}</Button></div>
        </div>))}</div></Card> : null}
      {recs.length ? <Card className='mt-4 overflow-hidden'>{sub('Recommendations')}<div className='divide-y divide-border'>{recs.map((r: any, i: number) => (<div key={i} className='px-4 py-2.5'><div className='text-sm font-medium flex items-center gap-1.5'>{r.title}{r.risk ? <Chip label={String(r.risk)} tone={riskTone(String(r.risk))} /> : null}</div>{r.recommendation ? <div className='text-xs text-muted-foreground mt-0.5'>{r.recommendation}</div> : null}<div className='text-[11px] text-muted-foreground mt-0.5'>{fmt(r.at)}</div></div>))}</div></Card> : null}
      {runs.length ? <Card className='mt-4 overflow-hidden'>{sub('Recent runs')}<div className='divide-y divide-border'>{runs.map((r: any) => (<div key={r.id} className='px-4 py-2 flex items-center justify-between gap-2'><div className='min-w-0'><div className='text-sm flex items-center gap-1.5'><Chip label={titleCase(String(r.status))} tone={statusTone(String(r.status))} />{r.note ? <span className='text-muted-foreground line-clamp-1'>{r.note}</span> : null}</div></div><span className='text-[11px] text-muted-foreground whitespace-nowrap'>{fmt(r.started_at)}</span></div>))}</div></Card> : null}
      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4'>
        {(kn.recent || []).length ? <Card className='overflow-hidden'>{sub('Knowledge', <Badge variant='secondary'>{kn.count ?? (kn.recent || []).length}</Badge>)}<div className='p-3 space-y-1.5'>{(kn.recent || []).map((x: any, i: number) => (<div key={i} className='text-xs flex items-center justify-between gap-2'><span className='truncate'>{x.topic || '—'}</span>{x.priority ? <Chip label={String(x.priority)} tone={priorityTone(String(x.priority))} /> : null}</div>))}</div></Card> : null}
        {(mem.recent || []).length ? <Card className='overflow-hidden'>{sub('Memory', <Badge variant='secondary'>{mem.count ?? (mem.recent || []).length}</Badge>)}<div className='p-3 space-y-1.5'>{(mem.recent || []).map((x: any, i: number) => (<div key={i} className='text-xs'><span className='text-muted-foreground'>{x.kind}:</span> {x.content}</div>))}</div></Card> : null}
      </div>
      {convos.length ? <Card className='mt-4 overflow-hidden'>{sub('Recent conversations')}<div className='p-3 space-y-2'>{convos.map((c: any, i: number) => (<div key={i} className='text-xs'><span className={cn('font-medium', c.role === 'assistant' ? 'text-primary' : 'text-foreground/70')}>{titleCase(String(c.role))}:</span> <span className='text-foreground/80'>{c.content}</span></div>))}</div></Card> : null}
    </>}
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
    {/* ── THE ORG CHART ────────────────────────────────────────────────────────────────────
        A real reporting hierarchy drawn as nodes, and clicking a person opens their workspace.
        The kanban and the list both open the drawer already; neither is a chart, and "clicking
        any PERSON on the chart" is what screen 4 asks for. */}
    {d ? <SectionCard title='Org chart' count={(d.rows || []).length}
      right={<span className='text-[11px] text-muted-foreground'>click a person to open their workspace</span>}>
      <div className='p-4 overflow-auto'>
        <svg viewBox={'0 0 900 ' + Math.max(220, 60 + (d.departments || []).length * 74)} className='w-full' style={{ minWidth: 720 }}>
          <text x={20} y={26} className='fill-muted-foreground' fontSize={12}>Company</text>
          {(d.departments || []).map((dep: any, di: number) => {
            const y = 60 + di * 74;
            const people = ((d.rows || []) as any[]).filter((r: any) => r.department === dep.key).slice(0, 9);
            return (<g key={dep.key}>
              <line x1={30} y1={30} x2={30} y2={y} stroke='currentColor' strokeOpacity={0.2} />
              <line x1={30} y1={y} x2={64} y2={y} stroke='currentColor' strokeOpacity={0.2} />
              <text x={70} y={y + 4} fontSize={12} className='fill-foreground' fontWeight={600}>{dep.label || dep.key}</text>
              <text x={70} y={y + 20} fontSize={10} className='fill-muted-foreground'>{dep.runs ?? 0} runs/24h · {people.length} people</text>
              {people.map((p: any, pi: number) => (
                <g key={p.agent_key} onClick={() => setSel(p)} style={{ cursor: 'pointer' }}>
                  <circle cx={300 + pi * 66} cy={y} r={9} className={p.active ? 'fill-emerald-500' : 'fill-muted'} />
                  <title>{titleCase(String(p.agent_key))} — open workspace</title>
                  <text x={300 + pi * 66} y={y + 26} fontSize={9} textAnchor='middle' className='fill-muted-foreground'>{String(p.agent_key).slice(0, 10)}</text>
                </g>))}
            </g>);
          })}
        </svg>
      </div>
    </SectionCard> : null}
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

// ── Marketing — deep social/content studio (insights · review · social · blog) ──
const CH_LABEL: Record<string, string> = { instagram: 'Instagram', linkedin: 'LinkedIn', x: 'X', facebook: 'Facebook', tiktok: 'TikTok', youtube: 'YouTube', threads: 'Threads' };
function ChannelPills({ channels }: { channels: any }) {
  const list: string[] = Array.isArray(channels) ? channels : (channels ? [String(channels)] : []);
  if (!list.length) return null;
  return (<div className='flex flex-wrap gap-1'>{list.map((c, i) => (<span key={i} className='inline-flex items-center text-[10px] px-1.5 py-0.5 rounded bg-foreground/[0.06] text-foreground/70 capitalize'>{CH_LABEL[String(c).toLowerCase()] || c}</span>))}</div>);
}
function PostThumb({ url, className }: { url?: string; className?: string }) {
  if (!url) return (<div className={cn('grid place-items-center bg-foreground/[0.05] text-muted-foreground', className)}><Megaphone className='h-6 w-6 opacity-30' /></div>);
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={url} alt='' loading='lazy' className={cn('object-cover bg-foreground/[0.05]', className)} onError={(e) => { (e.currentTarget as HTMLImageElement).style.visibility = 'hidden'; }} />;
}

function SocialPostDrawer({ post, onClose }: { post: any; onClose: () => void }) {
  const chan = Array.isArray(post.channels) ? post.channels : [];
  const live = String(post.status || '').toLowerCase() === 'sent' || String(post.status || '').toLowerCase() === 'published';
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-xl overflow-y-auto'>
    <SheetHeader>
      <SheetTitle className='flex items-center gap-2'>Social post{live ? <Chip label='Live' tone='green' /> : <Chip label={titleCase(String(post.status || post.mode || 'draft'))} tone={statusTone(String(post.status || post.mode || 'draft'))} />}</SheetTitle>
      <SheetDescription>{post.created_at ? 'Created ' + fmt(post.created_at) : ''}</SheetDescription>
    </SheetHeader>
    <div className='mt-4 space-y-4'>
      {post.image_url ? <div className='rounded-lg overflow-hidden border border-border'><PostThumb url={post.image_url} className='w-full max-h-96' /></div> : null}
      <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Caption</div><div className='text-sm whitespace-pre-wrap leading-relaxed'>{post.text || <span className='text-muted-foreground'>No caption.</span>}</div></Card>
      <div className='grid grid-cols-2 gap-3'>
        <Card className='p-3'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Channels</div>{chan.length ? <ChannelPills channels={chan} /> : <span className='text-sm text-muted-foreground'>—</span>}</Card>
        <Card className='p-3'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Status</div><Chip label={titleCase(String(post.status || post.mode || 'draft'))} tone={statusTone(String(post.status || post.mode || 'draft'))} />{post.error ? <div className='text-[11px] text-red-600 mt-1.5 whitespace-pre-wrap'>{post.error}</div> : null}</Card>
      </div>
      {post.image_url ? <a href={post.image_url} target='_blank' rel='noopener noreferrer' className='inline-flex items-center gap-1 text-xs text-primary hover:underline'>Open full image<ExternalLink className='h-3 w-3' /></a> : null}
    </div>
    <ActivityPanel entity='social_post' id={post.id} />
  </SheetContent></Sheet>);
}

function BlogDrawer({ post, onChanged, onClose }: { post: any; onChanged: (id: any, published: boolean) => void; onClose: () => void }) {
  const [pub, setPub] = React.useState(!!post.published);
  const [busy, setBusy] = React.useState(false); const [msg, setMsg] = React.useState('');
  const toggle = async () => { const next = !pub; setBusy(true); setMsg(''); try { await osApi('blog_publish', { id: post.id, published: next }); setPub(next); onChanged(post.id, next); setMsg(next ? 'Published — live on the site.' : 'Unpublished — hidden from the site.'); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); } setBusy(false); };
  const liveUrl = 'https://quotesdone.com/blog/' + (post.slug || '');
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-2xl overflow-y-auto'>
    <SheetHeader>
      <div className='flex items-center gap-2 flex-wrap'>{post.category ? <span className='inline-flex items-center text-[11px] px-1.5 py-0.5 rounded-full bg-foreground/[0.06] text-foreground/70 capitalize'>{post.category}</span> : null}<Chip label={pub ? 'Published' : 'Draft'} tone={pub ? 'green' : 'amber'} /></div>
      <SheetTitle className='mt-1'>{post.title}</SheetTitle>
      <SheetDescription>{post.published_at ? 'Published ' + fmt(post.published_at) : 'Not published yet'}{post.slug ? ' · /blog/' + post.slug : ''}</SheetDescription>
    </SheetHeader>
    <div className='mt-3 flex flex-wrap items-center gap-2'>
      <Button className='h-8 text-xs' variant={pub ? 'outline' : 'default'} disabled={busy} onClick={toggle}>{busy ? '…' : pub ? 'Unpublish' : 'Publish'}</Button>
      {pub && post.slug ? <a href={liveUrl} target='_blank' rel='noopener noreferrer' className='inline-flex items-center gap-1 h-8 px-3 rounded-md border border-border text-xs hover:bg-foreground/5'>View live<ExternalLink className='h-3 w-3' /></a> : null}
      {msg ? <span className='text-[11px] text-muted-foreground'>{msg}</span> : null}
    </div>
    {post.excerpt ? <div className='mt-4 text-sm text-muted-foreground italic border-l-2 border-border pl-3'>{post.excerpt}</div> : null}
    {post.body_html ? <div className='osx-prose mt-4 text-sm leading-relaxed [&_h1]:text-lg [&_h1]:font-bold [&_h1]:mt-4 [&_h1]:mb-2 [&_h2]:text-base [&_h2]:font-semibold [&_h2]:mt-4 [&_h2]:mb-2 [&_h3]:font-semibold [&_h3]:mt-3 [&_h3]:mb-1.5 [&_p]:mb-3 [&_ul]:list-disc [&_ul]:pl-5 [&_ul]:mb-3 [&_ol]:list-decimal [&_ol]:pl-5 [&_ol]:mb-3 [&_li]:mb-1 [&_a]:text-primary [&_a]:underline [&_strong]:font-semibold [&_img]:rounded-md [&_img]:my-3' dangerouslySetInnerHTML={{ __html: String(post.body_html) }} /> : <div className='mt-4 text-sm text-muted-foreground'>No body content stored for this post.</div>}
    <ActivityPanel entity='blog_post' id={post.id} />
  </SheetContent></Sheet>);
}

function ReviewDrawer({ item, onDone, onClose }: { item: any; onDone: () => void; onClose: () => void }) {
  const [busy, setBusy] = React.useState(''); const [comment, setComment] = React.useState(''); const [msg, setMsg] = React.useState('');
  const decide = async (decision: string) => { setBusy(decision); setMsg(''); try { await osApi('review_decide', { kind: item.__kind || 'marketing_post', ref_id: item.id ?? item.ref_id, decision, comment }); onDone(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); setBusy(''); } };
  const img = item.image_url || item.image;
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-xl overflow-y-auto'>
    <SheetHeader><SheetTitle className='flex items-center gap-2'>Review draft<Chip label='Pending' tone='amber' /></SheetTitle><SheetDescription>{titleCase(String(item.__kind || 'marketing post'))}{item.channel ? ' · ' + item.channel : ''}</SheetDescription></SheetHeader>
    <div className='mt-4 space-y-4'>
      {img ? <div className='rounded-lg overflow-hidden border border-border'><PostThumb url={img} className='w-full max-h-96' /></div> : null}
      {item.title ? <div className='text-base font-semibold'>{item.title}</div> : null}
      {(item.body || item.text) ? <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Content</div><div className='text-sm whitespace-pre-wrap leading-relaxed'>{item.body || item.text}</div></Card> : null}
      {item.channels ? <ChannelPills channels={item.channels} /> : null}
      <div><div className='text-xs font-semibold text-muted-foreground mb-1'>Note (optional)</div><textarea value={comment} onChange={(e) => setComment(e.target.value)} rows={2} placeholder='Add a note for the record…' className='w-full resize-none rounded-md border border-border bg-transparent p-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' /></div>
      {msg ? <div className='text-xs text-red-600'>{msg}</div> : null}
      <div className='flex gap-2'>
        <Button className='h-9 text-xs' disabled={!!busy} onClick={() => decide('approve')}><Check className='h-4 w-4 mr-1' />{busy === 'approve' ? 'Publishing…' : 'Approve & publish'}</Button>
        <Button className='h-9 text-xs' variant='outline' disabled={!!busy} onClick={() => decide('reject')}>{busy === 'reject' ? 'Rejecting…' : 'Reject'}</Button>
      </div>
    </div>
  </SheetContent></Sheet>);
}

const MK_TABS = [['insights', 'Insights'], ['review', 'Review'], ['social', 'Social'], ['blog', 'Blog']] as [string, string][];
function MarketingApp() {
  const [tab, setTab] = React.useState('insights');
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const [social, setSocial] = React.useState<any>(null); const [blog, setBlog] = React.useState<any>(null); const [review, setReview] = React.useState<any>(null);
  const [blogQ, setBlogQ] = React.useState(''); const [blogFilter, setBlogFilter] = React.useState<'all' | 'published' | 'draft'>('all');
  const load = React.useCallback(() => { setBusy(true); setErr(''); osApi('marketing_studio').then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const onBlogChanged = (id: any, published: boolean) => { setD((prev: any) => prev ? { ...prev, blog: (prev.blog || []).map((b: any) => b.id === id ? { ...b, published } : b) } : prev); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Marketing: {err}</Card>;
  const k = (d?.kpis) || {}; const trend = (d?.trend) || []; const socials = (d?.social) || []; const blogs = (d?.blog) || [];
  const rv = (d?.review) || {}; const reviewItems: any[] = [
    ...((rv.marketing_posts || []).map((x: any) => ({ ...x, __kind: 'marketing_post' }))),
    ...((rv.boost_budgets || []).map((x: any) => ({ ...x, __kind: 'boost_budget' }))),
  ];
  const leadsTrend = trend.map((p: any) => ({ d: p.d, n: Number(p.leads) || 0 }));
  const contentTrend = trend.map((p: any) => ({ d: p.d, n: (Number(p.blog) || 0) + (Number(p.social) || 0) }));
  const chBreak: Record<string, number> = {}; socials.forEach((s: any) => (Array.isArray(s.channels) ? s.channels : []).forEach((c: string) => { chBreak[c] = (chBreak[c] || 0) + 1; }));
  const chRows = Object.entries(chBreak).map(([label, n]) => ({ label: CH_LABEL[label] || label, n })).sort((a, b) => b.n - a.n);
  const publishedCount = blogs.filter((b: any) => b.published).length;
  const visibleBlogs = blogs.filter((b: any) => (blogFilter === 'all' || (blogFilter === 'published' ? b.published : !b.published)) && (!blogQ || String(b.title || '').toLowerCase().includes(blogQ.toLowerCase()) || String(b.category || '').toLowerCase().includes(blogQ.toLowerCase())));
  return (<div className='space-y-4'>
    <div className='flex flex-wrap items-center gap-2'>
      <Megaphone className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Marketing</h1>
      {reviewItems.length ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{reviewItems.length} to review</Badge> : null}
      {busy ? <span className='text-[11px] text-muted-foreground'>updating…</span> : null}
      <Button className='h-8 text-xs ml-auto' variant='outline' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button>
    </div>
    <div className='inline-flex rounded-lg border border-border bg-foreground/[0.02] p-0.5'>
      {MK_TABS.map(([id, label]) => (<button key={id} onClick={() => setTab(id)} className={cn('relative h-8 px-3 rounded-md text-xs font-medium transition-colors', tab === id ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground')}>{label}{id === 'review' && reviewItems.length ? <span className='ml-1.5 inline-flex items-center justify-center h-4 min-w-4 px-1 rounded-full bg-amber-500 text-white text-[10px]'>{reviewItems.length}</span> : null}</button>))}
    </div>

    {!d ? <div className='grid grid-cols-2 md:grid-cols-6 gap-3'>{Array.from({ length: 6 }).map((_, i) => <div key={i} className='h-20 rounded-lg bg-foreground/5 animate-pulse' />)}</div> : tab === 'insights' ? (<div className='space-y-4'>
      <div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3'>
        <StatTile label='Total leads' value={k.leads_total} onClick={() => setTab('insights')} />
        <StatTile label='Blog published' value={k.blog_published} hint={(k.blog_total || 0) + ' total'} onClick={() => setTab('blog')} />
        <StatTile label='Social live' value={k.social_published} hint={socials.length + ' posts'} onClick={() => setTab('social')} />
        <StatTile label='SEO pages' value={k.seo_pages} />
        <StatTile label='Outreach sent' value={k.outreach_sent} />
        <StatTile label='Awaiting review' value={reviewItems.length} onClick={() => setTab('review')} />
      </div>
      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Leads growth<span className='text-[11px] font-normal text-muted-foreground'>last {leadsTrend.length} snapshots</span></div><div className='p-4'>{leadsTrend.length ? <AreaSpark data={leadsTrend} /> : <div className='text-xs text-muted-foreground'>No trend yet.</div>}</div></Card>
        <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>Content produced (blog + social)</div><div className='p-4'>{contentTrend.length ? <AreaSpark data={contentTrend} /> : <div className='text-xs text-muted-foreground'>No trend yet.</div>}</div></Card>
      </div>
      <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
        <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>Marketing funnel</div><div className='p-4'><Funnel rows={[{ stage: 'SEO pages', n: Number(k.seo_pages) || 0 }, { stage: 'Content', n: (Number(k.blog_published) || 0) + (Number(k.social_published) || 0) }, { stage: 'Outreach', n: Number(k.outreach_sent) || 0 }, { stage: 'Leads', n: Number(k.leads_total) || 0 }]} /></div></Card>
        <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>Social reach by channel</div><div className='p-4'>{chRows.length ? <HBars rows={chRows} onBar={() => setTab('social')} /> : <div className='text-xs text-muted-foreground'>No social posts yet.</div>}</div></Card>
      </div>
    </div>) : tab === 'review' ? (<div className='space-y-3'>
      {reviewItems.length ? <div className='grid grid-cols-1 md:grid-cols-2 gap-3'>{reviewItems.map((it: any, i: number) => (
        <button key={i} onClick={() => setReview(it)} className='text-left bg-card rounded-lg border border-border overflow-hidden hover:shadow-md hover:border-primary/40 transition-all'>
          {(it.image_url || it.image) ? <PostThumb url={it.image_url || it.image} className='w-full h-40' /> : null}
          <div className='p-3'><div className='flex items-center gap-2 mb-1'><Chip label={titleCase(String(it.__kind))} tone='amber' />{it.channel ? <span className='text-[11px] text-muted-foreground'>{it.channel}</span> : null}</div><div className='text-sm font-medium line-clamp-1'>{it.title || 'Draft'}</div><div className='text-xs text-muted-foreground line-clamp-2 mt-0.5'>{it.body || it.text || '—'}</div></div>
        </button>))}</div> : (
        <Card className='p-10 text-center'><Check className='h-8 w-8 text-emerald-500/50 mx-auto mb-2' /><div className='text-sm font-medium'>Nothing awaiting review</div><div className='text-xs text-muted-foreground mt-1'>Draft posts created by the team appear here. Open one to see its image and copy, then approve to publish or reject.</div></Card>
      )}
    </div>) : tab === 'social' ? (<div>
      {socials.length ? <div className='grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3'>{socials.map((s: any) => { const live = /sent|published/i.test(String(s.status || '')); return (
        <button key={s.id} onClick={() => setSocial(s)} className='text-left bg-card rounded-lg border border-border overflow-hidden hover:shadow-md hover:border-primary/40 transition-all group'>
          <div className='relative'><PostThumb url={s.image_url} className='w-full h-44 group-hover:brightness-105 transition-all' /><div className='absolute top-2 right-2'>{live ? <Chip label='Live' tone='green' /> : <Chip label={titleCase(String(s.status || s.mode || 'draft'))} tone={statusTone(String(s.status || s.mode || 'draft'))} />}</div></div>
          <div className='p-3'><div className='text-sm line-clamp-2 leading-snug'>{s.text || <span className='text-muted-foreground'>No caption</span>}</div><div className='flex items-center justify-between mt-2 gap-2'><ChannelPills channels={s.channels} /><span className='text-[10px] text-muted-foreground whitespace-nowrap'>{s.created_at ? new Date(s.created_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : ''}</span></div></div>
        </button>); })}</div> : (
        <Card className='p-10 text-center'><Megaphone className='h-8 w-8 text-muted-foreground/40 mx-auto mb-2' /><div className='text-sm font-medium'>No social posts yet</div><div className='text-xs text-muted-foreground mt-1'>Posts published through Postiz appear here with their image and copy.</div></Card>
      )}
    </div>) : (<div className='space-y-3'>
      <div className='flex flex-wrap items-center gap-2'>
        <div className='relative'><Search className='h-3.5 w-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none' /><Input value={blogQ} onChange={(e) => setBlogQ(e.target.value)} placeholder='Search posts…' className='h-9 w-56 pl-8' /></div>
        <div className='inline-flex rounded-md border border-border overflow-hidden text-xs'>{([['all', 'All ' + blogs.length], ['published', 'Published ' + publishedCount], ['draft', 'Drafts ' + (blogs.length - publishedCount)]] as [any, string][]).map(([f, lbl]) => (<button key={f} onClick={() => setBlogFilter(f)} className={cn('h-9 px-3 border-l first:border-l-0 border-border', blogFilter === f ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}>{lbl}</button>))}</div>
      </div>
      {visibleBlogs.length ? <Card className='overflow-hidden'><div className='divide-y divide-border'>{visibleBlogs.map((b: any) => (
        <button key={b.id} onClick={() => setBlog(b)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
          <div className='min-w-0 flex-1'><div className='text-sm font-medium line-clamp-1'>{b.title}</div><div className='text-xs text-muted-foreground line-clamp-1 mt-0.5'>{b.excerpt || b.slug}</div></div>
          {b.category ? <span className='hidden sm:inline-flex items-center text-[11px] px-1.5 py-0.5 rounded-full bg-foreground/[0.06] text-foreground/70 capitalize shrink-0'>{b.category}</span> : null}
          <Chip label={b.published ? 'Published' : 'Draft'} tone={b.published ? 'green' : 'amber'} />
          <ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' />
        </button>))}</div></Card> : <Card className='p-8 text-center text-sm text-muted-foreground'>No posts match.</Card>}
    </div>)}

    {social ? <SocialPostDrawer post={social} onClose={() => setSocial(null)} /> : null}
    {blog ? <BlogDrawer post={blog} onChanged={onBlogChanged} onClose={() => setBlog(null)} /> : null}
    {review ? <ReviewDrawer item={review} onDone={() => { setReview(null); load(); }} onClose={() => setReview(null)} /> : null}
  </div>);
}

// ── Fraud — risk case queue with case detail + resolve actions ──
function FraudCaseDrawer({ flag, onResolved, onClose }: { flag: any; onResolved: () => void; onClose: () => void }) {
  const [busy, setBusy] = React.useState(''); const [msg, setMsg] = React.useState(''); const [sub, setSub] = React.useState<any>(null);
  const det = flag.detail || {};
  const resolve = async (op: string) => { setBusy(op); setMsg(''); try { await osApi('fraud_resolve', { subject_type: flag.subject_type, subject_id: String(flag.subject_id), op }); onResolved(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); setBusy(''); } };
  const amount = Number(det.amount); const median = Number(det.median); const hasCompare = isFinite(amount) && isFinite(median) && median > 0;
  const ratio = hasCompare ? amount / median : 1; const maxv = Math.max(amount, median) || 1;
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-xl overflow-y-auto'>
    <SheetHeader>
      <div className='flex items-center gap-2 flex-wrap'><Chip label={titleCase(String(flag.kind || 'flag'))} tone='slate' /><Chip label={titleCase(String(flag.severity || 'medium'))} tone={riskTone(String(flag.severity))} /><Chip label={titleCase(String(flag.status || 'open'))} tone={statusTone(String(flag.status))} /></div>
      <SheetTitle className='mt-1'>{titleCase(String(flag.kind || 'Risk flag'))}</SheetTitle>
      <SheetDescription>{titleCase(String(flag.subject_type))} · {String(flag.subject_id)} · flagged {fmt(flag.created)}</SheetDescription>
    </SheetHeader>
    <div className='mt-4 space-y-4'>
      {hasCompare ? <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-2'>Price vs category median{det.band ? ' · ' + titleCase(String(det.band)) : ''}</div>
        <div className='space-y-2'>
          <div><div className='flex justify-between text-xs mb-1'><span>This {flag.subject_type}</span><span className='tabular-nums font-medium'>AED {amount.toLocaleString()}</span></div><div className='h-2.5 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-red-500' style={{ width: Math.max(3, (amount / maxv) * 100) + '%' }} /></div></div>
          <div><div className='flex justify-between text-xs mb-1'><span>Category median{det.category ? ' (' + det.category + ')' : ''}</span><span className='tabular-nums text-muted-foreground'>AED {median.toLocaleString()}</span></div><div className='h-2.5 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-foreground/40' style={{ width: Math.max(3, (median / maxv) * 100) + '%' }} /></div></div>
        </div>
        <div className='text-[11px] text-muted-foreground mt-2'>{ratio >= 1 ? (ratio).toFixed(1) + '× above' : (1 / ratio).toFixed(1) + '× below'} the category median.</div>
      </Card> : null}
      <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Detail</div><ReadableObject data={det} /></Card>
      {flag.subject_type === 'supplier' ? <Button className='h-8 text-xs' variant='outline' onClick={() => setSub({ entity: 'supplier', id: flag.subject_id })}>Open supplier record</Button> : null}
      {msg ? <div className='text-xs text-red-600'>{msg}</div> : null}
      <div className='flex gap-2 border-t border-border pt-3'>
        <Button className='h-9 text-xs' variant='outline' disabled={!!busy} onClick={() => resolve('dismiss')}>{busy === 'dismiss' ? '…' : 'Dismiss (false positive)'}</Button>
        <Button className='h-9 text-xs' variant='outline' disabled={!!busy} onClick={() => resolve('ban')}>{busy === 'ban' ? '…' : 'Ban actor'}</Button>
      </div>
    </div>
    {flag.subject_type && flag.subject_id != null ? <ActivityPanel entity={flag.subject_type} id={flag.subject_id} /> : null}
    {sub ? <RecordDrawer frame0={{ entity: sub.entity, id: sub.id, title: 'Supplier #' + sub.id }} onClose={() => setSub(null)} /> : null}
  </SheetContent></Sheet>);
}
function FraudApp() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false); const [sel, setSel] = React.useState<any>(null);
  const load = React.useCallback(() => { setBusy(true); setErr(''); osApi('ws.fraud').then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Fraud: {err}</Card>;
  const k = d?.kpis || {}; const flags = d?.open_flags || []; const banned = d?.banned || [];
  const sevRank = (s: string) => /high|critical|severe/.test(String(s)) ? 0 : /medium|moderate/.test(String(s)) ? 1 : 2;
  const sorted = [...flags].sort((a: any, b: any) => sevRank(a.severity) - sevRank(b.severity));
  return (<div className='space-y-4'>
    <div className='flex flex-wrap items-center gap-2'><ShieldAlert className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Fraud &amp; Risk</h1>{k.high_severity ? <Badge className='bg-red-500/15 text-red-600 border-0'>{k.high_severity} high severity</Badge> : null}<Button className='h-8 text-xs ml-auto' variant='outline' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button></div>
    <div className='grid grid-cols-2 md:grid-cols-4 gap-3'>
      <StatTile label='Open flags' value={k.open_flags} />
      <StatTile label='High severity' value={k.high_severity} />
      <StatTile label='Flags (7d)' value={k.flags_7d} />
      <StatTile label='Banned actors' value={k.banned_actors} />
    </div>
    <Card className='overflow-hidden'>
      <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Open risk flags<Badge variant='secondary'>{flags.length}</Badge></div>
      {sorted.length ? <div className='divide-y divide-border'>{sorted.map((f: any, i: number) => (
        <button key={i} onClick={() => setSel(f)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
          <div className='min-w-0 flex-1'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{titleCase(String(f.kind))}<Chip label={titleCase(String(f.severity))} tone={riskTone(String(f.severity))} /></div><div className='text-xs text-muted-foreground mt-0.5'>{titleCase(String(f.subject_type))} · {f.detail?.category ? f.detail.category + ' · ' : ''}{f.detail?.amount ? 'AED ' + Number(f.detail.amount).toLocaleString() : (f.detail?.note || '')}</div></div>
          <span className='text-[11px] text-muted-foreground whitespace-nowrap'>{fmt(f.created)}</span><ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' />
        </button>))}</div> : <div className='px-4 py-8 text-center text-sm text-muted-foreground'>No open risk flags. The engine is watching prices, licences and duplicate accounts.</div>}
    </Card>
    {banned.length ? <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>Banned actors</div><div className='divide-y divide-border'>{banned.map((b: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm flex items-center justify-between'><span>{b.name || b.subject_id}</span><Chip label='Banned' tone='red' /></div>))}</div></Card> : null}
    {sel ? <FraudCaseDrawer flag={sel} onResolved={() => { setSel(null); load(); }} onClose={() => setSel(null)} /> : null}
  </div>);
}

// ── Refunds — dispute queue with case detail + resolve ──
function RefundDrawer({ item, onResolved, onClose }: { item: any; onResolved: () => void; onClose: () => void }) {
  const [busy, setBusy] = React.useState(''); const [note, setNote] = React.useState(''); const [msg, setMsg] = React.useState('');
  const tid = item.transaction_id ?? item.id;
  const resolve = async (op: string) => { setBusy(op); setMsg(''); try { await osApi('refund_resolve', { transaction_id: String(tid), op, note }); onResolved(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); setBusy(''); } };
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-xl overflow-y-auto'>
    <SheetHeader>
      <div className='flex items-center gap-2 flex-wrap'>{item.refund_status ? <Chip label={titleCase(String(item.refund_status))} tone={statusTone(String(item.refund_status))} /> : <Chip label='Pending' tone='amber' />}{item.within_window != null ? <Chip label={item.within_window ? 'Within window' : 'Out of window'} tone={item.within_window ? 'green' : 'red'} /> : null}</div>
      <SheetTitle className='mt-1'>Refund · {item.amount != null ? 'AED ' + Number(item.amount).toLocaleString() : 'Transaction ' + tid}</SheetTitle>
      <SheetDescription>{[item.customer_name || item.customer, item.created_at ? fmt(item.created_at) : null].filter(Boolean).join(' · ')}</SheetDescription>
    </SheetHeader>
    <div className='mt-4 space-y-4'>
      {item.reason ? <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Reason</div><div className='text-sm whitespace-pre-wrap'>{item.reason}</div></Card> : null}
      <Card className='p-4'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5'>Transaction</div><ReadableObject data={item} /></Card>
      <div><div className='text-xs font-semibold text-muted-foreground mb-1'>Decision note (optional)</div><textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} className='w-full resize-none rounded-md border border-border bg-transparent p-2 text-sm outline-none focus-visible:ring-1 focus-visible:ring-ring' /></div>
      {msg ? <div className='text-xs text-red-600'>{msg}</div> : null}
      <div className='flex gap-2 border-t border-border pt-3'>
        <Button className='h-9 text-xs' disabled={!!busy} onClick={() => resolve('approve')}>{busy === 'approve' ? '…' : 'Approve refund'}</Button>
        <Button className='h-9 text-xs' variant='outline' disabled={!!busy} onClick={() => resolve('reject')}>{busy === 'reject' ? '…' : 'Reject'}</Button>
      </div>
    </div>
  </SheetContent></Sheet>);
}
function RefundsApp() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false); const [sel, setSel] = React.useState<any>(null);
  const load = React.useCallback(() => { setBusy(true); setErr(''); osApi('ws.refunds').then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Refunds: {err}</Card>;
  const k = d?.kpis || {}; const pending = d?.pending || []; const resolved = d?.recent_resolved || [];
  return (<div className='space-y-4'>
    <div className='flex flex-wrap items-center gap-2'><RotateCcw className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>Refunds</h1>{k.pending ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{k.pending} pending</Badge> : null}<Button className='h-8 text-xs ml-auto' variant='outline' disabled={busy} onClick={load}>{busy ? 'Refreshing…' : 'Refresh'}</Button></div>
    <div className='grid grid-cols-2 md:grid-cols-3 gap-3'>
      <StatTile label='Pending' value={k.pending} />
      <StatTile label='Resolved (30d)' value={k.resolved_30d} />
      <StatTile label='Within window' value={k.within_window} />
    </div>
    <Card className='overflow-hidden'>
      <div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between'>Pending refund requests<Badge variant='secondary'>{pending.length}</Badge></div>
      {pending.length ? <div className='divide-y divide-border'>{pending.map((r: any, i: number) => (
        <button key={i} onClick={() => setSel(r)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
          <div className='min-w-0 flex-1'><div className='text-sm font-medium'>{r.amount != null ? 'AED ' + Number(r.amount).toLocaleString() : 'Transaction ' + (r.transaction_id ?? r.id)}</div><div className='text-xs text-muted-foreground line-clamp-1 mt-0.5'>{r.customer_name || r.customer || ''}{r.reason ? ' · ' + r.reason : ''}</div></div>
          <ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' />
        </button>))}</div> : <div className='px-4 py-8 text-center text-sm text-muted-foreground'>No pending refund requests. Approved payments with disputes will appear here for review.</div>}
    </Card>
    {resolved.length ? <Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold'>Recently resolved</div><div className='divide-y divide-border'>{resolved.map((r: any, i: number) => (<div key={i} className='px-4 py-2.5 flex items-center justify-between gap-2'><span className='text-sm'>{r.amount != null ? 'AED ' + Number(r.amount).toLocaleString() : (r.transaction_id ?? r.id)}</span>{r.refund_status ? <Chip label={titleCase(String(r.refund_status))} tone={statusTone(String(r.refund_status))} /> : null}</div>))}</div></Card> : null}
    {sel ? <RefundDrawer item={sel} onResolved={() => { setSel(null); load(); }} onClose={() => setSel(null)} /> : null}
  </div>);
}

// ── Shared section primitives for the dashboard apps ──
function SectionCard({ title, count, children, right }: { title: string; count?: any; children: any; right?: any }) {
  return (<Card className='overflow-hidden'><div className='px-4 py-3 border-b border-border text-sm font-semibold flex items-center justify-between gap-2'><span className='flex items-center gap-2'>{title}{count != null ? <Badge variant='secondary'>{count}</Badge> : null}</span>{right}</div>{children}</Card>);
}
function KpiRow({ items }: { items: [string, any, string?][] }) {
  return (<div className='grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3'>{items.map(([label, value, hint], i) => (<StatTile key={i} label={label} value={value} hint={hint} />))}</div>);
}
function AppHeader({ icon: Icon, title, badge, onRefresh, busy }: any) {
  return (<div className='flex flex-wrap items-center gap-2'><Icon className='h-5 w-5 text-primary' /><h1 className='text-lg font-bold'>{title}</h1>{badge}{onRefresh ? <Button className='h-8 text-xs ml-auto' variant='outline' disabled={busy} onClick={onRefresh}>{busy ? 'Refreshing…' : 'Refresh'}</Button> : null}</div>);
}
function useWs(action: string) {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const load = React.useCallback(() => { setBusy(true); setErr(''); osApi(action).then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, [action]);
  React.useEffect(() => { load(); }, [load]);
  return { d, err, busy, load, setD };
}

function OperationsApp() {
  const { d, err, busy, load } = useWs('ws.operations'); const [dbusy, setDbusy] = React.useState('');
  const [row, setRow] = React.useState<any>(null);
  const decide = async (id: any, op: string) => { setDbusy(String(id) + op); try { await osOps('action_decide', { id, op }); load(); } catch (_e) {} setDbusy(''); };
  const taskDone = async (id: any) => { setDbusy('t' + id); try { await osOps('task_done', { id, op: 'done' }); load(); } catch (_e) {} setDbusy(''); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Operations: {err}</Card>;
  const k = d?.kpis || {}; const tasks = d?.tasks || []; const decisions = d?.decisions || []; const approvals = d?.approvals || []; const sec = d?.security || {};
  const held = decisions.filter((x: any) => /held|review|pending|proposed|open/.test(String(x.decision || x.status)));
  return (<div className='space-y-4'>
    <AppHeader icon={Settings2} title='Operations' onRefresh={load} busy={busy} badge={k.high_risk ? <Badge className='bg-red-500/15 text-red-600 border-0'>{k.high_risk} high risk</Badge> : null} />
    <KpiRow items={[['Open tasks', k.tasks_open], ['Decisions 24h', k.decisions_24h], ['Approvals pending', k.approvals_pending], ['Disputes', k.disputes], ['High risk', k.high_risk], ['Held for review', held.length]]} />
    {held.length ? <SectionCard title='Decisions held for review' count={held.length}><div className='divide-y divide-border'>{held.map((a: any) => (<div key={a.id} className='px-4 py-3 flex items-center justify-between gap-3'><div className='min-w-0'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{(a.kind_label || titleCase(String(a.kind || 'decision')))}<span className='text-muted-foreground text-xs'>{a.actor}</span><Chip label={titleCase(String(a.decision))} tone={statusTone(String(a.decision))} /></div><div className='text-xs text-muted-foreground'>→ {a.route_to} · {fmt(a.created_at)}</div></div><div className='flex gap-1.5 shrink-0'><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'approve'} onClick={() => decide(a.id, 'approve')}>Approve</Button><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(a.id) + 'reject'} onClick={() => decide(a.id, 'reject')}>Reject</Button></div></div>))}</div></SectionCard> : null}
    <SectionCard title='Open tasks' count={tasks.length}>{tasks.length ? <div className='divide-y divide-border'>{tasks.map((t: any) => (<div key={t.id} className='px-4 py-2.5 flex items-center justify-between gap-3'><div className='min-w-0'><div className='text-sm flex items-center gap-1.5'>{t.priority ? <Chip label={String(t.priority)} tone={priorityTone(String(t.priority))} /> : null}<span className='line-clamp-1'>{t.title}</span></div><div className='text-[11px] text-muted-foreground'>{t.source}{t.due ? ' · due ' + fmt(t.due) : ''}</div></div><Button className='h-7 text-xs shrink-0' variant='outline' disabled={dbusy === 't' + t.id} onClick={() => taskDone(t.id)}>{dbusy === 't' + t.id ? '…' : 'Done'}</Button></div>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No open tasks.</div>}</SectionCard>
    {approvals.length ? <SectionCard title='Approvals pending' count={approvals.length}><div className='p-4'><div className='mb-2 flex flex-wrap gap-1.5'>{(approvals as any[]).map((a: any, i: number) => (<button key={i} onClick={() => setRow({ id: a.id ?? i, title: String(a.title || 'Action'), row: a })} className='text-[11px] rounded border border-border px-1.5 py-0.5 hover:bg-foreground/5'>Open #{a.id ?? i}</button>))}</div><ReadableObject data={approvals} /></div></SectionCard> : null}
    {row ? <RecordDrawer frame0={{ entity: 'agent_action', id: row.id, title: row.title, row: row.row }} onClose={() => setRow(null)} /> : null}
    {Object.keys(sec).length ? <SectionCard title='Security posture'><div className='p-4'><ReadableObject data={sec} /></div></SectionCard> : null}
  </div>);
}

function AnalyticsApp() {
  const { d, err, busy, load } = useWs('ws.analytics');
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Analytics: {err}</Card>;
  const mp = d?.marketplace || {}; const sectors = d?.top_sectors || []; const emirates = d?.top_emirates || []; const fn = d?.supplier_funnel || {};
  const funnelRows = [['directory', 'Directory'], ['submitted', 'Submitted'], ['registered', 'Registered'], ['claimed', 'Claimed'], ['approved', 'Approved']].map(([k, l]) => ({ stage: l, n: Number(fn[k]) || 0 })).filter((r) => r.n > 0 || r.stage === 'Directory');
  return (<div className='space-y-4'>
    <AppHeader icon={BarChart3} title='Analytics' onRefresh={load} busy={busy} />
    <KpiRow items={[['RFQs today', mp.rfqs_today], ['RFQs 7d', mp.rfqs_7d], ['RFQs 30d', mp.rfqs_30d], ['Active suppliers 30d', mp.active_suppliers_30d], ['Response rate', mp.response_rate_pct != null ? mp.response_rate_pct + '%' : '—'], ['Avg savings', mp.avg_savings_pct != null ? mp.avg_savings_pct + '%' : '—']]} />
    <SectionCard title='Supplier acquisition funnel'><div className='p-4'>{funnelRows.length ? <Funnel rows={funnelRows} /> : <div className='text-xs text-muted-foreground'>No funnel data.</div>}</div></SectionCard>
    <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
      <SectionCard title='Top sectors'><div className='p-4'>{sectors.length ? <HBars rows={sectors.slice(0, 10).map((s: any) => ({ label: s.key, n: Number(s.count) }))} /> : <div className='text-xs text-muted-foreground'>No data.</div>}</div></SectionCard>
      <SectionCard title='Top emirates'><div className='p-4'>{emirates.length ? <HBars rows={emirates.slice(0, 10).map((s: any) => ({ label: s.key, n: Number(s.count) }))} /> : <div className='text-xs text-muted-foreground'>No data.</div>}</div></SectionCard>
    </div>
    {(mp.category_growth || []).length || (mp.competitive_categories || []).length ? <SectionCard title='Category signals'><div className='p-4'><ReadableObject data={{ category_growth: mp.category_growth, competitive_categories: mp.competitive_categories }} /></div></SectionCard> : null}
  </div>);
}

// ── COMPANY MEMORY ─────────────────────────────────────────────────────────────────────────────
// Screen 12: one search box over everything the company knows, and four questions it must answer —
// every decision about a topic, why something was rejected, when a thing changed, and the lessons
// from a period. fn_os_search reached three operational tables and none of the company's memory;
// fn_os_memory is the subject-and-period reader that did not exist at all.
function CompanyMemoryApp() {
  const [q, setQ] = React.useState(''); const [topic, setTopic] = React.useState('');
  const [from, setFrom] = React.useState(''); const [to, setTo] = React.useState('');
  const [found, setFound] = React.useState<any>(null); const [mem, setMem] = React.useState<any>(null);
  const [busy, setBusy] = React.useState(false); const [err, setErr] = React.useState('');

  const runSearch = React.useCallback(async () => {
    setBusy(true); setErr('');
    try { setFound(await osApi('search', { q })); } catch (e: any) { setErr(e?.message || 'search failed'); }
    setBusy(false);
  }, [q]);
  // The subject and the period both travel to the query — this is what makes "show every decision
  // about Marketing" and "find lessons from February" askable at all.
  const runMemory = React.useCallback(async () => {
    setBusy(true); setErr('');
    try { const subject = topic.trim(); setMem(await osApi('memory', { topic: subject, subject, from: from || null, to: to || null })); }
    catch (e: any) { setErr(e?.message || 'memory query failed'); }
    setBusy(false);
  }, [topic, from, to]);
  React.useEffect(() => { runMemory(); }, []);   // eslint-disable-line react-hooks/exhaustive-deps

  const CORPORA: [string, string][] = [['knowledge', 'Knowledge base'], ['lessons', 'Lessons'],
    ['decisions', 'Decisions'], ['org_memory', 'Organisational memory'], ['agent_memory', 'Employee memory'],
    ['documents', 'Documents'], ['suppliers', 'Suppliers'], ['rfqs', 'RFQs'], ['customers', 'Customers']];
  const decisions = (mem?.decisions || []) as any[];
  const rejection_reason = (mem?.rejection_reason || []) as any[];
  const changes = (mem?.changes || []) as any[];
  const lessons = (mem?.lessons || []) as any[];

  return (<div className='space-y-4'>
    <AppHeader icon={BookOpen} title='Company memory' onRefresh={runMemory} busy={busy} />
    {err ? <Card className='p-3 text-sm text-destructive'>{err}</Card> : null}

    <SectionCard title='Search everything the company knows'>
      <div className='p-4 space-y-3'>
        <div className='flex gap-2'>
          <Input value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') runSearch(); }}
            placeholder='Search suppliers, RFQs, knowledge, lessons, decisions, documents, memory…' className='flex-1' />
          <Button onClick={runSearch} disabled={busy}>Search</Button>
        </div>
        {found ? <div className='space-y-2'>{CORPORA.map(([k, label]) => {
          const rows = (found[k] || []) as any[]; if (!rows.length) return null;
          return (<div key={k}>
            <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{label} · {rows.length}</div>
            <div className='divide-y divide-border rounded-md border border-border mt-1'>{rows.map((r: any, i: number) => (
              <div key={i} className='px-3 py-2 text-sm'><div className='font-medium truncate'>{r.name || r.headline}</div>
                {r.sub ? <div className='text-[11px] text-muted-foreground truncate'>{r.sub}</div> : null}</div>))}</div>
          </div>);
        })}{CORPORA.every(([k]) => !((found[k] || []) as any[]).length) ? <div className='text-sm text-muted-foreground'>Nothing matched.</div> : null}</div> : null}
      </div>
    </SectionCard>

    <SectionCard title='Ask the memory a question'
      right={<span className='text-[11px] text-muted-foreground'>a subject, a period, or both</span>}>
      <div className='p-4 flex flex-wrap items-end gap-2'>
        <div><div className='text-[11px] text-muted-foreground mb-1'>Subject / topic</div>
          <Input value={topic} onChange={(e) => setTopic(e.target.value)} placeholder='e.g. Marketing, pricing, Supplier X' className='w-64' /></div>
        <div><div className='text-[11px] text-muted-foreground mb-1'>From</div>
          <Input type='date' value={from} onChange={(e) => setFrom(e.target.value)} className='w-40' /></div>
        <div><div className='text-[11px] text-muted-foreground mb-1'>To</div>
          <Input type='date' value={to} onChange={(e) => setTo(e.target.value)} className='w-40' /></div>
        <Button onClick={runMemory} disabled={busy}>{busy ? 'Asking…' : 'Ask'}</Button>
      </div>
    </SectionCard>

    {decisions.length ? <SectionCard title={'Decisions' + (mem?.subject ? ' about ' + mem.subject : '')} count={decisions.length}>
      <div className='divide-y divide-border max-h-96 overflow-auto'>{decisions.map((x: any) => (
        <div key={x.id} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
          <span className='font-medium'>{titleCase(String(x.decision || x.kind))}</span>
          <span className='text-[11px] text-muted-foreground'>{x.actor}</span>
          {x.confidence != null ? <Chip label={'confidence ' + x.confidence} tone='slate' /> : null}
          <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(x.at)}</span></div>
          {Array.isArray(x.reasons) && x.reasons.length ? <div className='text-[11px] text-muted-foreground mt-0.5'>{x.reasons.join(' · ')}</div> : null}</div>))}</div>
    </SectionCard> : null}

    {rejection_reason.length ? <SectionCard title='Why it was rejected' count={rejection_reason.length}>
      <div className='divide-y divide-border'>{rejection_reason.map((r: any) => (
        <div key={r.id} className='px-4 py-2.5 text-sm'>
          <div className='flex items-center gap-2 flex-wrap'><span className='font-medium'>{r.problem}</span>
            <Chip label={titleCase(String(r.status || 'recorded'))} tone={statusTone(String(r.status))} />
            <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(r.at)}</span></div>
          <div className='text-[12px] mt-0.5'>{r.recommendation}</div>
          {r.risks ? <div className='text-[11px] text-amber-600 mt-0.5'>Risks: {fmt(r.risks)}</div> : null}
          {r.actual_outcome ? <div className='text-[11px] text-muted-foreground mt-0.5'>Outcome: {r.actual_outcome}</div> : null}
        </div>))}</div>
    </SectionCard> : null}

    {changes.length ? <SectionCard title='What changed, and when' count={changes.length}
      right={<div className='flex flex-wrap gap-1'>{((mem?.change_subjects || []) as any[]).slice(0, 6).map((s: any) => (
        <button key={s.table_name} onClick={() => { setTopic(s.table_name); }} className='text-[10px] rounded border border-border px-1.5 py-0.5 hover:bg-foreground/5'>{s.table_name} {s.n}</button>))}</div>}>
      <div className='divide-y divide-border max-h-80 overflow-auto'>{changes.map((c: any) => (
        <div key={c.id} className='px-4 py-2 text-sm flex items-center gap-2'>
          <Chip label={String(c.op)} tone={c.op === 'DELETE' ? 'red' : c.op === 'INSERT' ? 'green' : 'slate'} />
          <span className='font-medium'>{c.table_name}</span>
          <span className='text-[11px] text-muted-foreground'>#{c.row_id} · {c.actor || 'system'}</span>
          <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(c.at)}</span></div>))}</div>
    </SectionCard> : null}

    {lessons.length ? <SectionCard title='Lessons' count={lessons.length}
      right={mem?.from || mem?.to ? <span className='text-[11px] text-muted-foreground'>{mem.from || '…'} → {mem.to || '…'}</span> : null}>
      <div className='divide-y divide-border max-h-96 overflow-auto'>{lessons.map((l: any) => (
        <div key={l.id} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
          <span className='font-medium'>{l.headline}</span>{l.outcome ? <Chip label={String(l.outcome)} tone='slate' /> : null}
          <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(l.occurred_at)}</span></div>
          <div className='text-[12px] text-muted-foreground mt-0.5'>{l.detail}</div></div>))}</div>
    </SectionCard> : null}
  </div>);
}

// ── THE OPERATING SYSTEM & COMPANY MAP ─────────────────────────────────────────────────────────
// Mission Control and the company knowledge graph on one screen. Eighteen stores feed this and
// every one of them reached no surface at all before it existed — graph_nodes and graph_edges are
// rebuilt nightly and had ZERO readers anywhere in the product.
// INFORMATION FLOWING BETWEEN THE TEN OPERATING SYSTEMS, DRAWN AND MOVING.
//
// The ten systems exchanged 932 events in the last seven days and no surface had ever drawn one of
// those connections. The edges come from what was actually DELIVERED — event_delivery gives the
// receiving system, company_event.actor resolved through its department gives the sending one —
// because os_interface's declared outputs and inputs are disjoint sets that join to zero cross-OS
// edges. That is a real fact about the contract table, not a rendering problem, so it is reported
// in the footer rather than papered over.
//
// The dash animation is BOUND TO VOLUME: an edge carrying 78 events a week cycles in about a
// second, one carrying 3 takes three. A line that moves at a constant rate would be decoration.
function OsFlowMap({ flow }: { flow: any }) {
  const nodes = (flow?.nodes || []) as any[]; const edges = (flow?.edges || []) as any[];
  const [hot, setHot] = React.useState<string>('');
  if (!nodes.length || !edges.length) return null;
  const max = Math.max(...edges.map((e: any) => Number(e.n) || 0), 1);
  const R = 118, CX = 150, CY = 140;
  const pos = (i: number) => ({ x: CX + R * Math.cos((i / nodes.length) * 2 * Math.PI - Math.PI / 2), y: CY + R * Math.sin((i / nodes.length) * 2 * Math.PI - Math.PI / 2) });
  const at = (k: string) => nodes.findIndex((n: any) => String(n.os_key) === String(k));
  const cross = edges.filter((e: any) => String(e.from_os) !== String(e.to_os));
  const lit = (e: any) => !hot || String(e.from_os) === hot || String(e.to_os) === hot;
  return (<SectionCard title='Information flow between operating systems' count={cross.length}
    right={<span className='text-[11px] text-muted-foreground'>{flow.deliveries} deliver{Number(flow.deliveries) === 1 ? 'y' : 'ies'} over {flow.window_days}d</span>}>
    <div className='p-4 grid gap-5 lg:grid-cols-[300px_1fr]'>
      <svg viewBox='0 0 300 285' className='w-full max-w-[300px] mx-auto' role='img' aria-label={'Information flow between ' + nodes.length + ' operating systems'}>
        {cross.map((e: any, i: number) => {
          const a = at(e.from_os), b = at(e.to_os); if (a < 0 || b < 0) return null;
          const p = pos(a), q = pos(b); const share = Number(e.n) / max;
          return (<line key={i} x1={p.x} y1={p.y} x2={q.x} y2={q.y} strokeLinecap='round'
            stroke='currentColor' strokeWidth={0.6 + 2.4 * share} strokeDasharray='5 7'
            className={cn('transition-opacity duration-300', lit(e) ? 'text-primary/45' : 'text-primary/10')}>
            <animate attributeName='stroke-dashoffset' from='12' to='0' dur={(2.8 - 1.9 * share).toFixed(2) + 's'} repeatCount='indefinite' />
          </line>);
        })}
        {nodes.map((n: any, i: number) => { const p = pos(i); const k = String(n.os_key); const on = !hot || hot === k;
          return (<g key={k} onMouseEnter={() => setHot(k)} onMouseLeave={() => setHot('')} className='cursor-pointer'>
            <circle cx={p.x} cy={p.y} r={5 + Math.min(5, Math.sqrt(Number(n.received) || 0) / 3)}
              className={cn('transition-all duration-300', on ? 'fill-primary' : 'fill-primary/25')} />
            <text x={p.x} y={p.y + (p.y < CY ? -10 : 16)} textAnchor='middle'
              className={cn('text-[8px] transition-opacity duration-300', on ? 'fill-foreground' : 'fill-muted-foreground/50')}>{String(n.name || k).replace(/ OS$/, '')}</text>
          </g>); })}
      </svg>
      <div className='min-w-0'>
        <div className='text-xs font-semibold mb-2'>Busiest connections</div>
        <div className='space-y-1'>{cross.slice(0, 8).map((e: any, i: number) => (
          <div key={i} onMouseEnter={() => setHot(String(e.from_os))} onMouseLeave={() => setHot('')}
            className='text-xs flex items-center gap-2 rounded px-1.5 py-1 hover:bg-foreground/5 transition-colors'>
            <span className='truncate flex-1'>{titleCase(String(e.from_os))} <span className='text-muted-foreground'>&rarr;</span> {titleCase(String(e.to_os))}</span>
            <span className='text-[11px] text-muted-foreground truncate max-w-[9rem]'>{(e.kinds || []).join(', ')}</span>
            <span className='tabular-nums font-medium'>{e.n}</span>
          </div>))}</div>
        <div className='text-[11px] text-muted-foreground mt-3 leading-relaxed'>
          {flow.attributed} of {flow.deliveries} deliveries resolve to a sending system; {flow.unattributed} were emitted by machinery rather than an operating system, and {flow.unroutable} could not be routed at all.
          The connections are drawn from what was delivered — the declared os_interface outputs and inputs are disjoint, so they join to no cross-system edge.
        </div>
      </div>
    </div>
  </SectionCard>);
}
function CompanyOsApp() {
  const { d, err, busy, load } = useWs('ws.company_os');
  const [sel, setSel] = React.useState<any>(null);
  const [tab, setTab] = React.useState<'os' | 'map' | 'live' | 'board' | 'strategy' | 'resilience' | 'manual'>('os');
  const L = useWs('ws.live_company');
  const goal_path = (L.d?.goal_path || []) as any[]; const handoff_chain = (L.d?.handoff_chain || []) as any[];
  const handoff_stages = (L.d?.handoff_stages || []) as any[]; const risk_register = (L.d?.risk_register || []) as any[];
  const department_health = (L.d?.department_health || []) as any[];
  const onNode = React.useCallback((n: any) => setSel(n), []);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load the Operating System: {err}</Card>;

  const systems = (d?.operating_systems || []) as any[];
  const graph = d?.graph || {}; const graph_nodes = (graph.nodes || []) as any[]; const graph_edges = (graph.edges || []) as any[];
  const board = d?.board || {}; const indices = (d?.indices || []) as any[];
  const replay = d?.replay || {}; const reputation = d?.reputation || {};
  const evolution_proposal = (d?.evolution_proposals || []) as any[];
  const challenge_record = (d?.challenge_record || []) as any[];
  const opportunity = (d?.opportunity || []) as any[]; const queues = d?.strategic_queues || {};
  const institutional = d?.institutional_memory || {}; const resilience = d?.resilience || {};
  const operating_manual = d?.operating_manual || {}; const events = d?.events || {};
  // WHAT THE COMPANY'S PROCESSES ACTUALLY PRODUCED. Until this reader existed, the only routines
  // touching workflow_step_run.output were the two that write it — so every deliverable an employee
  // produced performing a company process was stored and read by nobody.
  const process_work = (d?.process_work || []) as any[];
  // THE ENGINE HAD NO SCREEN. 238 runs and the only surface was a "Workflows run today" count, so
  // where each process is parked and who it waits on were nowhere. in_flight is the oldest-waiting
  // 25; ready_now is the true total, so the card never implies the list is the whole queue.
  const wf = (d?.workflow_state || {}) as any;
  const wfStatus = (wf.by_status || {}) as Record<string, number>;
  const wfFlight = (wf.in_flight || []) as any[];
  const TABS: [any, string][] = [['os', 'Mission control'], ['map', 'Company map'], ['live', 'Live company'], ['board', 'Board'],
    ['strategy', 'Strategic queue'], ['resilience', 'Resilience'], ['manual', 'Operating manual']];

  return (<div className='space-y-4'>
    <AppHeader icon={Network} title='Operating System' onRefresh={load} busy={busy}
      badge={<Badge className='bg-primary/15 text-primary border-0'>{systems.length} systems · {graph.node_count} nodes</Badge>} />
    <KpiRow items={[
      ['Operating systems', systems.length],
      ['Graph nodes', graph.node_count], ['Graph edges', graph.edge_count],
      ['Events 7d', events.last_7d], ['Lessons on file', institutional.lessons],
      ['Runbooks', operating_manual.runbooks], ['Process work 14d', process_work.length],
    ]} />

    {(wfFlight.length || wfStatus.done) ? <SectionCard title='Processes in flight' count={Number(wf.ready_now ?? 0)}
      right={<span className='text-[11px] text-muted-foreground'>
        {(wfStatus.done ?? 0)} done · {(wfStatus.running ?? 0)} running · {(wfStatus.failed ?? 0)} failed · {Number(wf.steps_delivered ?? 0)} step(s) delivered by an employee
      </span>}>
      <div className='divide-y divide-border'>{wfFlight.map((p: any, i: number) => {
        const hrs = Number(p.hours_waiting) || 0;
        return (<div key={i} className='px-4 py-2.5 text-sm flex items-center gap-2'>
          <div className='min-w-0 flex-1'>
            <div className='truncate'><span className='font-medium'>{p.workflow}</span>
              <span className='text-muted-foreground'> · step {p.step_no}: {p.step}</span></div>
            <div className='text-[11px] text-muted-foreground'>
              waiting on {p.waiting_on ? titleCase(String(p.waiting_on)) : 'nobody it can name'}
              {p.addressed_as && p.addressed_as !== p.waiting_on ? ' (named “' + p.addressed_as + '” by the process)' : ''}
              {p.gate ? ' · gate: ' + p.gate : ''}
            </div>
          </div>
          {/* Hours, not a colour alone: 144 hours parked is the fact, and it reads the same to
              anyone who cannot distinguish the tones. */}
          <Chip label={hrs >= 24 ? Math.round(hrs / 24) + 'd waiting' : hrs + 'h waiting'}
                tone={hrs >= 72 ? 'red' : hrs >= 24 ? 'amber' : 'slate'} />
        </div>);
      })}</div>
      {Number(wf.ready_now ?? 0) > wfFlight.length
        ? <div className='px-4 py-2 text-[11px] text-muted-foreground border-t border-border'>
            Showing the {wfFlight.length} longest-waiting of {Number(wf.ready_now)} ready step(s).
          </div> : null}
    </SectionCard> : null}

    {process_work.length ? <SectionCard title='What the company’s processes produced' count={process_work.length}
      right={<span className='text-[11px] text-muted-foreground'>step(s) an employee completed in 14 days — the outcome each closed on</span>}>
      <div className='divide-y divide-border'>{process_work.slice(0, 12).map((p: any, i: number) => (
        <div key={i} className='px-4 py-3 text-sm'>
          <div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{p.workflow}</span>
            <span className='text-[11px] text-muted-foreground'>step {p.step_no} · {p.step}</span>
            <Chip label={titleCase(String(p.employee || ''))} tone='slate' />
            {p.confidence != null
              ? <Chip label={'confidence ' + p.confidence}
                      tone={Number(p.confidence) >= 0.7 ? 'green' : Number(p.confidence) >= 0.4 ? 'amber' : 'red'} />
              : null}
            <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(p.at)}</span>
          </div>
          <div className='mt-1'>{p.outcome || '—'}</div>
          <div className='text-[11px] text-muted-foreground mt-0.5'>
            {p.chars ? p.chars.toLocaleString() + ' characters of working' : null}
            {p.mode === 'advisory' ? ' · advisory: a determination, not a side effect' : null}
          </div>
        </div>))}</div>
    </SectionCard> : null}
    <div className='inline-flex rounded-md border border-border overflow-hidden text-xs'>{TABS.map(([k, lbl]) => (
      <button key={k} onClick={() => setTab(k)} className={cn('h-7 px-3 border-l first:border-l-0 border-border', tab === k ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}>{lbl}</button>))}</div>

    {tab === 'os' ? <div className='grid grid-cols-1 md:grid-cols-2 gap-3'>{systems.map((s: any) => (
      <Card key={s.os_key} className='p-4 cursor-pointer hover:brightness-[1.03] transition-all' onClick={() => setSel(s)}>
        <div className='flex items-center gap-2'>
          <span className={cn('inline-block h-2 w-2 rounded-full', Number(s.health_score) >= 80 ? 'bg-emerald-500 animate-pulse' : Number(s.health_score) >= 60 ? 'bg-amber-500' : 'bg-red-500')} />
          <span className='text-sm font-semibold'>{s.name}</span>
          <span className='text-[11px] text-muted-foreground'>{s.os_key}</span>
          <Chip label={'health ' + (s.health_score ?? '—')} tone={Number(s.health_score) >= 80 ? 'green' : Number(s.health_score) >= 60 ? 'amber' : 'red'} />
        </div>
        <div className='text-[12px] text-muted-foreground mt-1.5 line-clamp-2'>{s.mission}</div>
        <div className='text-[11px] text-muted-foreground mt-2 flex flex-wrap gap-x-3'>
          <span>owner {s.owner_agent}</span><span>{(s.objectives || []).length} objective(s)</span>
          <span>{(s.responsibilities || []).length} responsibilit(ies)</span>
          {(s.owned_departments || []).length ? <span>{s.staff_in_owned_departments} staff in {(s.owned_departments || []).join(', ')}</span> : null}
        </div>
      </Card>))}</div> : null}

    {tab === 'map' ? <OsFlowMap flow={d?.flow} /> : null}
    {tab === 'map' ? <SectionCard title='Company map' count={graph.node_count}
      right={<span className='text-[11px] text-muted-foreground'>{graph.edge_count} edges · rebuilt {fmt(graph.rebuilt_at)} · scroll to zoom, drag to pan, click a node</span>}>
      <div className='p-2'>
        <div className='flex flex-wrap gap-1.5 px-2 pb-2'>{(graph.node_kinds || []).map((k: any) => (
          <Chip key={k.kind} label={titleCase(String(k.kind)) + ' ' + k.n} tone='slate' />))}</div>
        <CompanyGraphField nodes={graph_nodes as any} edges={graph_edges as any} onSelect={onNode} />
      </div>
    </SectionCard> : null}

    {tab === 'live' ? <div className='space-y-3'>
      {/* WORK PASSING BETWEEN DEPARTMENTS, hop by hop. review_chain holds 1,093 of these and no
          screen had ever drawn the sequence. */}
      <SectionCard title='Work passing between departments' count={L.d?.handoffs_total}
        right={<div className='flex flex-wrap gap-1'>{handoff_stages.slice(0, 6).map((s: any) => (<Chip key={s.hop} label={titleCase(String(s.hop)) + ' ' + s.n} tone='slate' />))}</div>}>
        <div className='divide-y divide-border max-h-96 overflow-auto'>{handoff_chain.map((c: any) => (
          <div key={c.id} className='px-4 py-2.5 text-sm'>
            <div className='flex items-center gap-2 flex-wrap'>
              <Chip label={titleCase(String(c.from_dept || '—'))} tone='slate' />
              <ChevronRight className='h-3.5 w-3.5 text-muted-foreground' />
              <Chip label={titleCase(String(c.hop))} tone='blue' />
              <ChevronRight className='h-3.5 w-3.5 text-muted-foreground' />
              <Chip label={titleCase(String(c.to_dept || c.reviewer_agent || '—'))} tone='slate' />
              <Chip label={titleCase(String(c.decision))} tone={statusTone(String(c.decision))} />
              <span className='text-[11px] text-muted-foreground ml-auto'>{fmt(c.at)}</span>
            </div>
            {c.reason ? <div className='text-[11px] text-muted-foreground mt-0.5 line-clamp-2'>{c.reason}</div> : null}
            {c.delegated_from ? <div className='text-[11px] text-muted-foreground'>delegated from {c.delegated_from}</div> : null}
          </div>))}</div>
      </SectionCard>

      {goal_path.length ? <SectionCard title='Where the company is going, and the path to it' count={goal_path.length}>
        <div className='p-4 space-y-4'>{goal_path.map((m: any) => (
          <div key={m.year_no} className='border-l-2 border-primary/40 pl-3'>
            <div className='text-sm font-semibold'>{m.milestone}<span className='text-[11px] text-muted-foreground font-normal'> — {m.statement}</span></div>
            <div className='mt-1 space-y-1'>{(m.steps || []).map((s: any, i: number) => (
              <div key={i} className='text-[12px] flex items-center gap-2'>
                <span className='text-muted-foreground tabular-nums'>{i + 1}.</span>
                <span className='min-w-0 flex-1 truncate'>{s.step}</span>
                <span className='text-[11px] text-muted-foreground shrink-0 tabular-nums'>{s.actual ?? '—'} / {s.target} {s.unit}</span>
              </div>))}{!(m.steps || []).length ? <div className='text-[11px] text-muted-foreground'>No steps recorded for this milestone.</div> : null}</div>
          </div>))}</div>
      </SectionCard> : null}

      {risk_register.length ? <SectionCard title='Risk register' count={risk_register.length}>
        <div className='divide-y divide-border max-h-80 overflow-auto'>{risk_register.map((r: any) => (
          <div key={r.id} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{r.risk}</span>
            {r.category ? <Chip label={String(r.category)} tone='slate' /> : null}
            {r.impact ? <Chip label={'impact ' + r.impact} tone='amber' /> : null}
            {r.probability ? <Chip label={'probability ' + r.probability} tone='slate' /> : null}
            <span className='text-[11px] text-muted-foreground ml-auto'>{r.dept_key} · {r.owner_agent}</span></div>
            {r.mitigation ? <div className='text-[11px] text-muted-foreground mt-0.5'>{r.mitigation}</div> : null}</div>))}</div>
      </SectionCard> : null}

      {department_health.length ? <SectionCard title='Department health' count={department_health.length}>
        <div className='p-4 grid grid-cols-1 sm:grid-cols-2 gap-2'>{department_health.map((h: any) => (
          <div key={h.dept_key} className='rounded-md border border-border px-3 py-2'>
            <div className='text-sm font-medium flex items-center gap-2'>{h.department}<Chip label={String(h.score)} tone={Number(h.score) >= 80 ? 'green' : Number(h.score) >= 60 ? 'amber' : 'red'} /></div>
            <div className='text-[11px] text-muted-foreground'>{h.basis}</div></div>))}</div>
      </SectionCard> : null}
    </div> : null}

    {tab === 'board' ? <div className='space-y-3'>
      <SectionCard title='The board' count={(board.advisors || []).length}>
        <div className='divide-y divide-border'>{(board.advisors || []).map((a: any) => (
          <div key={a.advisor_key} className='px-4 py-2.5 text-sm'><span className='font-medium'>{a.name}</span>
            <span className='text-[11px] text-muted-foreground'> · {a.lens} · weight {a.weight}</span>
            {a.asks ? <div className='text-[11px] text-muted-foreground mt-0.5'>{a.asks}</div> : null}</div>))}</div>
      </SectionCard>
      {(board.opinions || []).length ? <SectionCard title='Recent opinions' count={board.opinion_count}>
        <div className='divide-y divide-border'>{(board.opinions || []).map((o: any, i: number) => (
          <div key={i} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{o.subject}</span><Chip label={String(o.advisor_key)} tone='slate' />
            {o.confidence != null ? <Chip label={'confidence ' + o.confidence} tone={Number(o.confidence) >= 0.7 ? 'green' : 'amber'} /> : null}</div>
            <div className='text-[12px] mt-0.5'>{o.recommendation}</div>
            <div className='text-[11px] text-muted-foreground mt-0.5 line-clamp-2'>{o.rationale}</div></div>))}</div>
      </SectionCard> : null}
      <SectionCard title='Company indices' count={indices.length}>
        <div className='p-4 grid grid-cols-1 sm:grid-cols-3 gap-3'>{indices.map((ix: any) => (
          <div key={ix.index_name} className='rounded-md border border-border p-3'>
            <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>{titleCase(String(ix.index_name))}</div>
            <div className='text-xl font-semibold tabular-nums'>{ix.score}<span className='text-xs font-normal text-muted-foreground'> · {ix.band}</span></div>
            <div className='text-[11px] text-muted-foreground'>measured {ix.measured_on}</div>
            {ix.dimensions ? <div className='mt-2 space-y-1'>{Object.entries(ix.dimensions).slice(0, 6).map(([k, v]: any) => (
              <div key={k} className='flex items-center justify-between text-[11px]'><span className='text-muted-foreground truncate'>{titleCase(k)}</span><span className='tabular-nums'>{fmt(v)}</span></div>))}</div> : null}
          </div>))}</div>
      </SectionCard>
      <SectionCard title='Replay' count={replay.days_on_file}
        right={<span className='text-[11px] text-muted-foreground'>newest {replay.newest}</span>}>
        <div className='p-4 flex flex-wrap gap-1.5'>{(replay.company_snapshot || []).map((s: any, i: number) => (
          <button key={i} onClick={() => setSel(s)} className='rounded-md border border-border px-2 py-1 text-[11px] hover:bg-foreground/5'>{s.snapshot_on}</button>))}</div>
        {/* The six tracks of the day the card is showing. A track reading zero is a real answer —
            it says nothing of that kind happened — so it is rendered rather than hidden. */}
        {replay.tracks ? <div className='px-4 pb-4'>
          <div className='text-xs font-semibold mb-2'>What happened on {String(replay.tracks.day)}</div>
          <div className='grid grid-cols-3 sm:grid-cols-6 gap-2'>{([['decisions', 'Decisions'], ['conversations', 'Conversations'], ['approvals', 'Approvals'], ['workflows', 'Workflow steps'], ['kpis', 'KPI readings'], ['outcomes', 'Outcomes']] as [string, string][]).map(([key, label]) => {
            const n = Number(replay.tracks[key] ?? 0);
            return (<div key={key} className={cn('rounded-md border p-2', n > 0 ? 'border-border' : 'border-amber-500/30 bg-amber-500/[0.03]')}>
              <div className='text-base font-bold tabular-nums'>{n}</div>
              <div className='text-[10px] text-muted-foreground leading-tight'>{label}</div>
            </div>);
          })}</div>
        </div> : null}
      </SectionCard>
    </div> : null}

    {tab === 'strategy' ? <div className='space-y-3'>
      {/* The four strategic queues against the operational one. The spec's whole point: what the
          founder is shown should be strategic decisions, not the pending-task queue. */}
      <KpiRow items={[
        ['Structural proposals', queues.evolution_proposal],
        ['Open challenges', queues.challenge_record],
        ['Open opportunities', queues.opportunity],
        ['Board opinions', queues.board_opinion],
        ['Operational queue', queues.operational_pending],
      ]} />
      {opportunity.length ? <SectionCard title='Open opportunities' count={queues.opportunity}>
        <div className='divide-y divide-border'>{opportunity.map((o: any) => (
          <div key={o.id} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{o.title}</span><Chip label={titleCase(String(o.kind))} tone='slate' />
            {o.effort ? <Chip label={titleCase(String(o.effort)) + ' effort'} tone={o.effort === 'low' ? 'green' : 'amber'} /> : null}
            <Chip label={'value ' + Math.round(Number(o.value_score) || 0)} tone={Number(o.value_score) >= 60 ? 'green' : 'slate'} /></div>
            <div className='text-[12px] text-muted-foreground mt-0.5'>{o.detail}</div></div>))}</div>
      </SectionCard> : null}
      {challenge_record.length ? <SectionCard title='Where the AI disagreed' count={challenge_record.length}>
        <div className='divide-y divide-border'>{challenge_record.map((c: any) => (
          <div key={c.id} className='px-4 py-3 text-sm'>
            <div className='flex items-center gap-2 flex-wrap'><Chip label={titleCase(String(c.stance))} tone={c.stance === 'recommend_against' ? 'red' : 'amber'} />
              <span className='font-medium'>{c.proposal}</span>
              <span className='text-[11px] text-muted-foreground'>challenged by {c.challenged_by}</span>
              {c.confidence != null ? <Chip label={'confidence ' + c.confidence} tone='slate' /> : null}</div>
            <div className='text-[12px] text-muted-foreground mt-1'>{c.reasoning}</div>
            {(c.alternatives || []).length ? <div className='mt-1.5'>
              <div className='text-[11px] uppercase tracking-wide text-muted-foreground'>Alternatives offered</div>
              <ul className='list-disc pl-5 text-[12px]'>{(c.alternatives as any[]).map((a: any, j: number) => (<li key={j}>{String(a)}</li>))}</ul></div> : null}
            {c.violates_principle ? <div className='text-[11px] text-amber-600 mt-1'>Violates: {c.violates_principle} (rank {c.violates_rank})</div> : null}
            <div className='text-[11px] text-muted-foreground mt-1'>{c.responded_at ? 'Answered ' + fmt(c.responded_at) : 'Awaiting the founder'}</div>
          </div>))}</div>
      </SectionCard> : null}
      {evolution_proposal.length ? <SectionCard title='Structural proposals' count={evolution_proposal.length}>
        <div className='divide-y divide-border'>{evolution_proposal.map((p: any) => (
          <div key={p.id} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{p.subject}</span><Chip label={String(p.change_class || p.trigger_kind)} tone='slate' />
            <Chip label={titleCase(String(p.status))} tone={statusTone(String(p.status))} /></div>
            <div className='text-[12px] text-muted-foreground mt-0.5'>{p.observation}</div>
            <div className='text-[12px] mt-0.5'>{p.proposal}</div></div>))}</div>
      </SectionCard> : null}
      {(institutional.rows || []).length ? <SectionCard title='Lessons the company has learned' count={institutional.lessons}>
        <div className='divide-y divide-border'>{(institutional.rows || []).map((m: any, i: number) => (
          <div key={i} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{m.headline}</span>{m.outcome ? <Chip label={String(m.outcome)} tone='slate' /> : null}
            {m.os_key ? <span className='text-[11px] text-muted-foreground'>{m.os_key}</span> : null}</div>
            <div className='text-[12px] text-muted-foreground mt-0.5'>{m.lesson}</div></div>))}</div>
      </SectionCard> : null}
      <SectionCard title='Employee reputation' count={reputation.graded}
        right={<div className='flex gap-1'>{(reputation.by_tier || []).map((t: any) => (<Chip key={t.tier} label={t.n + ' ' + t.tier} tone={t.tier === 'probation' ? 'amber' : 'green'} />))}</div>}>
        <div className='overflow-auto max-h-72'><table className='w-full text-sm'>
          <thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border sticky top-0 bg-card'><th className='px-4 py-2 font-medium'>Employee</th><th className='px-4 py-2 font-medium'>Score</th><th className='px-4 py-2 font-medium'>Tier</th><th className='px-4 py-2 font-medium'>Learning</th></tr></thead>
          <tbody>{(reputation.rows || []).map((r: any) => (<tr key={r.agent_key} className='border-b border-border/40'>
            <td className='px-4 py-2 font-medium'>{r.agent_key}</td><td className='px-4 py-2 tabular-nums'>{r.score ?? '—'}</td>
            <td className='px-4 py-2'><Chip label={String(r.tier || '—')} tone={r.tier === 'probation' ? 'amber' : 'green'} /></td>
            <td className='px-4 py-2 tabular-nums'>{r.learning_speed ?? '—'}</td></tr>))}</tbody></table></div>
      </SectionCard>
    </div> : null}

    {tab === 'resilience' ? <div className='space-y-3'>
      <SectionCard title='Critical capabilities' count={(resilience.critical_capability || []).length}>
        <div className='divide-y divide-border'>{(resilience.critical_capability || []).map((c: any) => (
          <div key={c.capability_key} className='px-4 py-2.5 text-sm flex items-center gap-3'>
            <div className='min-w-0 flex-1'><div className='font-medium'>{c.capability}</div>
              <div className='text-[11px] text-muted-foreground'>{c.owner_dept} · {c.test_kind}</div></div>
            <Chip label={String(c.last_verdict || 'never tested')} tone={c.last_verdict === 'pass' ? 'green' : c.last_verdict ? 'red' : 'amber'} />
            <span className='text-[11px] text-muted-foreground shrink-0'>{c.last_checked ? fmt(c.last_checked) : '—'}</span>
          </div>))}</div>
      </SectionCard>
      <SectionCard title='Continuity plans' count={(resilience.continuity_plan || []).length}>
        <div className='divide-y divide-border'>{(resilience.continuity_plan || []).map((p: any, i: number) => (
          <div key={i} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
            <span className='font-medium'>{p.service}</span><Chip label={String(p.criticality)} tone={p.criticality === 'high' ? 'red' : 'amber'} />
            {p.rto_minutes != null ? <span className='text-[11px] text-muted-foreground'>RTO {p.rto_minutes}m</span> : null}
            <span className='text-[11px] text-muted-foreground'>{p.last_tested ? 'tested ' + fmt(p.last_tested) : 'never tested'}</span></div>
            <div className='text-[12px] text-muted-foreground mt-0.5'>{p.failure_mode} → {p.fallback}</div></div>))}</div>
      </SectionCard>
    </div> : null}

    {tab === 'manual' ? <SectionCard title='Operating manual' count={operating_manual.runbooks}
      right={<div className='flex flex-wrap gap-1'>{(operating_manual.by_category || []).slice(0, 6).map((c: any) => (<Chip key={c.category} label={c.category + ' ' + c.n} tone='slate' />))}</div>}>
      <div className='divide-y divide-border'>{(operating_manual.rows || []).map((r: any) => (
        <div key={r.slug} className='px-4 py-2.5 text-sm'><div className='flex items-center gap-2 flex-wrap'>
          <span className='font-medium'>{r.title}</span><Chip label={String(r.category || 'general')} tone='slate' />
          {r.os_key ? <span className='text-[11px] text-muted-foreground'>{r.os_key}</span> : null}</div>
          <div className='text-[12px] text-muted-foreground mt-0.5'>{r.when_to_use}</div></div>))}</div>
    </SectionCard> : null}

    {sel ? <Sheet open={true} onOpenChange={(o) => { if (!o) setSel(null); }}><SheetContent side='right' className='w-full sm:max-w-lg overflow-y-auto'>
      <SheetHeader><SheetTitle>{sel.name || sel.label || sel.snapshot_on || 'Detail'}</SheetTitle>
        <SheetDescription>{sel.os_key || sel.kind || ''}</SheetDescription></SheetHeader>
      <Card className='mt-4 p-4'><ReadableObject data={sel} /></Card></SheetContent></Sheet> : null}
  </div>);
}

// ── INTELLIGENCE CENTRE ────────────────────────────────────────────────────────────────────────
// One screen that reads three workspaces the browser already routes and renders only what those
// payloads actually contain. Every panel below was executed against production before it was
// written and carries live rows; nothing here is a placeholder waiting for a backend. Panels are
// added to this screen only when the routine feeding them returns data — an empty panel on an
// intelligence screen is worse than an absent one, because it reads as "the company knows nothing"
// rather than "this is not wired yet".
function IntelligenceApp() {
  const S = useWs('ws.strategy'); const F = useWs('ws.finance'); const A = useWs('ws.analytics');
  const I = useWs('ws.intelligence');
  // CUSTOMER BEHAVIOUR was the one of the nine intelligence items with no route to this screen.
  // customer_health carries engagement, satisfaction and a risk tier per customer; fn_ws_customers
  // named the view but returned only identity columns, so none of it ever reached a component.
  const CB = useWs('ws.customer_behavior');
  const [sel, setSel] = React.useState<any>(null);
  const [scenario, setScenario] = React.useState(''); const [simResult, setSimResult] = React.useState<any>(null); const [simBusy, setSimBusy] = React.useState(false);
  const runScenario = async () => { setSimBusy(true); try { setSimResult(await osApi('simulate', { question: scenario, scenario })); } catch (e: any) { setSimResult({ error: e?.message || 'simulation failed' }); } setSimBusy(false); };
  // Approving a simulation records it in the same ledger every other approval lands in, pointing
  // back at the simulations row it came from.
  const approveSimulation = async () => { setSimBusy(true); try { await osApi('simulation_approve', { scenario, result: simResult }); } catch (_e) {} setSimBusy(false); };
  const busy = S.busy || F.busy || A.busy || I.busy || CB.busy;
  const reloadAll = React.useCallback(() => { S.load(); F.load(); A.load(); I.load(); CB.load(); }, [S.load, F.load, A.load, I.load, CB.load]);
  const err = S.err || F.err || A.err || I.err;
  if (err && !S.d && !F.d && !A.d && !I.d) return <Card className='p-6 text-sm text-destructive'>Could not load Intelligence: {err}</Card>;

  const opp = I.d?.opportunities || {}; const oppRows = (opp.rows || []) as any[];
  const comp = I.d?.competitors || {}; const compRows = (comp.rows || []) as any[];
  const spend = I.d?.ai_spending || {}; const byModel = (spend.by_model || []) as any[];
  const growth_probability = I.d?.growth_probability || {};
  const k = S.d?.kpis || {};
  const risks = [...(S.d?.risks || [])].sort((a: any, b: any) => (Number(b.score) || 0) - (Number(a.score) || 0));
  const predictions = (S.d?.recent_simulations || []) as any[];
  const forecast = F.d?.ai?.forecast || {};
  const horizons = (forecast.horizons || []) as any[];
  // Supply-side coverage: the categories with live demand and too few suppliers behind them.
  const coverage_gaps = (S.d?.under_supplied || []) as any[];
  const mk = A.d?.marketplace || {};
  // customer_health: engagement, satisfaction and risk tier per customer. `customers` travels with
  // the averages on purpose — an average over two people is not a trend, and the screen must not
  // let it read as one. churn_rate_pct is null by design; the note says why.
  const cb = CB.d || {}; const cbRows = (cb.rows || []) as any[];

  return (<div className='space-y-4'>
    <AppHeader icon={Brain} title='Intelligence' onRefresh={reloadAll} busy={busy}
      badge={k.top_risk_score ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>Top risk {k.top_risk_score}</Badge> : null} />
    <KpiRow items={[
      ['Cash', k.cash != null ? aed(k.cash) : '—'],
      ['Monthly burn', k.monthly_burn != null ? aed(k.monthly_burn) : '—'],
      ['Open risks', k.open_risks],
      ['Coverage gaps', coverage_gaps.length],
      ['Suppliers 30d', mk.active_suppliers_30d],
      ['Capacity avg', mk.supplier_capacity_avg],
      ['Open leads', opp.open],
      ['Rivals tracked', comp.total],
      ['AI spend 30d', spend.total_aed != null ? aed(spend.total_aed) : '—'],
      ['Growth in 30d', growth_probability.growth_probability_pct != null ? growth_probability.growth_probability_pct + '%' : '—'],
    ]} />

    {/* CUSTOMER BEHAVIOUR. The averages carry their sample size in the header, because an average
        over two customers is not a trend and this screen must not let it read as one. Churn is
        shown as "not measured" with the reason, never as 0% — no customer is old enough to have
        lapsed, and a 0% churn rate would be the most flattering possible lie about that. */}
    <SectionCard title='Customer behaviour' count={cbRows.length}
      right={<span className='text-[11px] text-muted-foreground'>
        health {cb.avg_health ?? '—'} · engagement {cb.avg_engagement ?? '—'} · satisfaction {cb.avg_satisfaction ?? '—'}
        {cb.customers ? ' (mean of ' + cb.customers + ')' : ''} · churn {cb.churn_rate_pct != null ? cb.churn_rate_pct + '%' : 'not measured'}
      </span>}>
      {cbRows.length ? <div className='divide-y divide-border'>{cbRows.map((c: any, i: number) => (
        <div key={i} className='px-4 py-2.5 text-sm flex items-center gap-3'>
          <div className='min-w-0 flex-1'>
            <div className='truncate font-medium'>{c.name || c.email || 'customer'}</div>
            <div className='text-[11px] text-muted-foreground'>
              {c.total_inq ?? 0} RFQ(s), {c.active_inq ?? 0} active, {c.stalled_inq ?? 0} stalled
              {c.last_activity ? ' · last active ' + String(c.last_activity).slice(0, 10) : ' · no activity recorded'}
            </div>
          </div>
          <div className='flex items-center gap-2 shrink-0'>
            {c.dormant ? <Chip label='Dormant' tone='amber' /> : null}
            {c.risk_tier ? <Chip label={titleCase(String(c.risk_tier))} tone={statusTone(String(c.risk_tier))} /> : null}
            <Chip label={'Health ' + (c.health ?? '—')} tone='slate' />
          </div>
        </div>))}</div>
        : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>{cb.churn_note || 'No customers on the book yet.'}</div>}
    </SectionCard>

    <SectionCard title='Top risks' count={risks.length}>{risks.length ? <div className='divide-y divide-border'>{risks.map((r: any, i: number) => (
      <button key={i} onClick={() => setSel(r)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
        <div className='min-w-0 flex-1'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{r.title}{r.category ? <span className='text-[11px] text-muted-foreground'>{r.category}</span> : null}<Chip label={titleCase(String(r.status))} tone={statusTone(String(r.status))} /></div><div className='text-[11px] text-muted-foreground mt-0.5'>Impact {r.impact}/5 · Likelihood {r.likelihood}/5</div></div>
        <div className='flex items-center gap-2 shrink-0'><Chip label={'Score ' + r.score} tone={Number(r.score) >= 15 ? 'red' : Number(r.score) >= 8 ? 'amber' : 'slate'} /><ChevronRight className='h-4 w-4 text-muted-foreground' /></div>
      </button>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No open risks.</div>}</SectionCard>

    {horizons.length ? <SectionCard title='Cash forecast' count={horizons.length}
      right={<span className='text-[11px] text-muted-foreground'>from {aed(forecast.cash_now)} today</span>}>
      <div className='overflow-auto'><table className='w-full text-sm'>
        <thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Horizon</th><th className='px-4 py-2 font-medium'>Projected cash</th><th className='px-4 py-2 font-medium'>Expected in</th><th className='px-4 py-2 font-medium'>Expected out</th></tr></thead>
        <tbody>{horizons.map((h: any, i: number) => (<tr key={i} className='border-b border-border/40 last:border-0'>
          <td className='px-4 py-2 whitespace-nowrap'>{h.days}d</td>
          <td className={cn('px-4 py-2 tabular-nums font-medium', Number(h.projected_cash) < 0 ? 'text-red-500' : 'text-emerald-500')}>{aed(h.projected_cash)}</td>
          <td className='px-4 py-2 tabular-nums text-muted-foreground'>{aed(h.expected_inflows)}</td>
          <td className='px-4 py-2 tabular-nums text-muted-foreground'>{aed(h.expected_outflows)}</td>
        </tr>))}</tbody></table></div>
      <div className='px-4 py-2 text-[11px] text-muted-foreground border-t border-border/40'>Run rate assumption — out {aed(forecast?.assumptions?.expense_run_rate_30d)}/30d, in {aed(forecast?.assumptions?.revenue_run_rate_30d)}/30d.</div>
    </SectionCard> : null}

    {/* ── SCREEN 16 — "WHAT IF?" ──────────────────────────────────────────────────────────────
        A natural-language scenario, run against the company's own numbers. fn_what_if existed and
        nothing could reach it: there was no simulation action in os_api and no scenario input
        anywhere in the console. */}
    <SectionCard title='What if?' right={<span className='text-[11px] text-muted-foreground'>a scenario in plain language, run against the live numbers</span>}>
      <div className='p-4 space-y-3'>
        <div className='flex gap-2'>
          <Input value={scenario} onChange={(e) => setScenario(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') runScenario(); }}
            placeholder='e.g. What if we raised supplier fees 20%? What if we doubled marketing spend?' className='flex-1' />
          <Button onClick={runScenario} disabled={simBusy || !scenario.trim()}>{simBusy ? 'Simulating…' : 'Simulate'}</Button>
        </div>
        {simResult ? <div className='rounded-md border border-border p-3'>
          <div className='text-sm font-medium'>{simResult.scenario || scenario}</div>
          {simResult.confidence != null ? <Chip label={'confidence ' + simResult.confidence} tone={Number(simResult.confidence) >= 0.7 ? 'green' : 'amber'} /> : null}
          {/* Approve the simulated action from the simulation itself, not from somewhere else. */}
          {!simResult.error ? <Button className='h-7 text-xs mt-1' variant='outline' disabled={simBusy} onClick={() => approveSimulation()}>Approve this simulated action</Button> : null}
          <div className='mt-2'><ReadableObject data={simResult} /></div>
        </div> : null}
      </div>
    </SectionCard>

    {predictions.length ? <SectionCard title='Predictions' count={predictions.length}
      right={k.last_simulation_at ? <span className='text-[11px] text-muted-foreground'>last run {fmt(k.last_simulation_at)}</span> : null}>
      <div className='divide-y divide-border'>{predictions.map((p: any, i: number) => (
        <div key={i} className='px-4 py-2.5 text-sm flex items-center gap-3'><div className='min-w-0 flex-1'>{p.title || fmt(p)}</div>
          {p.created ? <span className='text-[11px] text-muted-foreground shrink-0'>{p.created}</span> : null}</div>))}</div>
    </SectionCard> : null}

    <SectionCard title='Supply coverage' count={coverage_gaps.length}
      right={<span className='text-[11px] text-muted-foreground'>{mk.rfqs_30d ?? '—'} RFQs/30d · avg first quote {mk.avg_first_quote_hours ?? '—'}h</span>}>
      {coverage_gaps.length ? <div className='overflow-auto'><table className='w-full text-sm'>
        <thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Category</th><th className='px-4 py-2 font-medium'>Live RFQs</th><th className='px-4 py-2 font-medium'>Suppliers behind it</th></tr></thead>
        <tbody>{coverage_gaps.map((u: any, i: number) => (<tr key={i} className='border-b border-border/40 last:border-0'>
          <td className='px-4 py-2 font-medium'>{titleCase(String(u.category || u.key || u.label || '—'))}</td>
          <td className='px-4 py-2 tabular-nums'>{u.rfqs ?? u.gap ?? '—'}</td>
          <td className='px-4 py-2'><Chip label={String(u.active_suppliers ?? 0)} tone={Number(u.active_suppliers ?? 0) < 2 ? 'red' : Number(u.active_suppliers ?? 0) < 4 ? 'amber' : 'green'} /></td>
        </tr>))}</tbody></table></div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>Every category with live demand has suppliers behind it.</div>}
      {(mk.category_growth || []).length ? <div className='p-4 border-t border-border/40'><div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-2'>Demand by category, 30d vs prior</div>
        <HBars rows={(mk.category_growth as any[]).map((c: any) => ({ label: titleCase(String(c.category)), n: Number(c.this_30d || 0) }))} /></div> : null}
    </SectionCard>

    {oppRows.length ? <SectionCard title='Top openings' count={opp.open}
      right={opp.newest ? <span className='text-[11px] text-muted-foreground'>newest {fmt(opp.newest)}</span> : null}>
      <div className='divide-y divide-border'>{oppRows.map((o: any) => (
        <button key={o.id} onClick={() => setSel(o)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
          <div className='min-w-0 flex-1'>
            <div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{o.title}<Chip label={titleCase(String(o.kind))} tone='slate' /></div>
            <div className='text-[11px] text-muted-foreground mt-0.5 line-clamp-1'>{o.detail}</div>
          </div>
          <div className='flex items-center gap-2 shrink-0'>
            {o.effort ? <Chip label={titleCase(String(o.effort)) + ' effort'} tone={o.effort === 'low' ? 'green' : o.effort === 'high' ? 'red' : 'amber'} /> : null}
            <Chip label={'Value ' + Math.round(Number(o.value_score) || 0)} tone={Number(o.value_score) >= 60 ? 'green' : 'slate'} />
            <ChevronRight className='h-4 w-4 text-muted-foreground' />
          </div>
        </button>))}</div>
    </SectionCard> : null}

    {compRows.length ? <SectionCard title='Competitors' count={comp.total}
      right={<div className='flex items-center gap-1'>{(comp.by_threat || []).map((t: any) => (
        <Chip key={t.level} label={t.n + ' ' + t.level} tone={t.level === 'high' ? 'red' : t.level === 'medium' ? 'amber' : 'slate'} />))}</div>}>
      <div className='divide-y divide-border max-h-96 overflow-auto'>{compRows.map((c: any) => (
        <button key={c.id} onClick={() => setSel(c)} className='w-full text-left px-4 py-2.5 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
          <div className='min-w-0 flex-1'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{c.name}{c.kind ? <span className='text-[11px] text-muted-foreground'>{c.kind}</span> : null}</div>
            <div className='text-[11px] text-muted-foreground mt-0.5 line-clamp-1'>{c.overlap}</div></div>
          <Chip label={titleCase(String(c.threat_level || 'unrated'))} tone={c.threat_level === 'high' ? 'red' : c.threat_level === 'medium' ? 'amber' : 'slate'} />
          <ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' />
        </button>))}</div>
      {(comp.positions || []).length ? <div className='p-4 border-t border-border/40'>
        <div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-2'>Where we stand, by dimension</div>
        <div className='space-y-1.5'>{(comp.positions as any[]).map((p: any, i: number) => (
          <div key={i} className='text-sm'><span className='font-medium'>{p.dimension}</span>
            <span className='text-muted-foreground'> — us: {p.quotesdone} · market: {p.market_norm}</span></div>))}</div>
      </div> : null}
    </SectionCard> : null}

    {byModel.length ? <SectionCard title='AI spending' count={spend.calls_30d}
      right={<span className='text-[11px] text-muted-foreground'>{aed(spend.total_aed)} over {spend.window_days}d · {spend.cache_hits_30d} cached · {spend.failed_30d} failed</span>}>
      <div className='overflow-auto'><table className='w-full text-sm'>
        <thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border'><th className='px-4 py-2 font-medium'>Model</th><th className='px-4 py-2 font-medium'>Calls</th><th className='px-4 py-2 font-medium'>Spend</th><th className='px-4 py-2 font-medium'>Share</th></tr></thead>
        <tbody>{byModel.map((m: any, i: number) => { const share = Number(spend.total_aed) > 0 ? (100 * Number(m.aed) / Number(spend.total_aed)) : 0;
          return (<tr key={i} className='border-b border-border/40 last:border-0'>
            <td className='px-4 py-2 font-medium break-all'>{m.model}</td>
            <td className='px-4 py-2 tabular-nums'>{m.calls}</td>
            <td className='px-4 py-2 tabular-nums'>{aed(m.aed)}</td>
            <td className='px-4 py-2'><div className='flex items-center gap-2'><div className='h-1.5 w-20 rounded-full bg-foreground/[0.08] overflow-hidden'><div className='h-full rounded-full bg-primary' style={{ width: Math.max(1, share) + '%' }} /></div><span className='text-[11px] tabular-nums text-muted-foreground'>{share.toFixed(0)}%</span></div></td>
          </tr>); })}</tbody></table></div>
      {(spend.by_dept || []).length ? <div className='p-4 border-t border-border/40'>
        <div className='text-[11px] uppercase tracking-wide text-muted-foreground mb-2'>By department</div>
        <HBars rows={(spend.by_dept as any[]).map((d: any) => ({ label: titleCase(String(d.dept)), n: Number(d.aed) }))} />
      </div> : null}
    </SectionCard> : null}

    {growth_probability.growth_probability_pct != null ? <SectionCard title='Growth probability'
      right={<span className='text-[11px] text-muted-foreground'>{growth_probability.observations} daily observations, {growth_probability.window_from} → {growth_probability.window_to}</span>}>
      <div className='p-4 space-y-3'>
        <div className='flex items-baseline gap-3'>
          <div className={cn('text-3xl font-semibold tabular-nums', Number(growth_probability.growth_probability_pct) >= 60 ? 'text-emerald-500' : Number(growth_probability.growth_probability_pct) >= 40 ? 'text-amber-500' : 'text-red-500')}>{growth_probability.growth_probability_pct}%</div>
          <div className='text-sm text-muted-foreground'>that maturity is higher in {growth_probability.horizon_days} days than today</div>
        </div>
        <div className='grid grid-cols-2 md:grid-cols-4 gap-2'>
          <StatTile label='Index now' value={growth_probability.index_now} />
          <StatTile label={'Index ' + growth_probability.window_from} value={growth_probability.index_first} />
          <StatTile label='Drift / day' value={growth_probability.drift_per_day} />
          <StatTile label='Volatility / day' value={growth_probability.volatility_per_day} />
        </div>
        <div className='text-[11px] text-muted-foreground'>{growth_probability.method}. A {growth_probability.observations}-point sample — read the drift and volatility beside the figure, not the figure alone.</div>
      </div>
    </SectionCard> : null}

    {sel ? <Sheet open={true} onOpenChange={(o) => { if (!o) setSel(null); }}><SheetContent side='right' className='w-full sm:max-w-lg overflow-y-auto'><SheetHeader><div className='flex items-center gap-2'>{sel.score != null ? <Chip label={'Score ' + sel.score} tone={Number(sel.score) >= 15 ? 'red' : Number(sel.score) >= 8 ? 'amber' : 'slate'} /> : null}{sel.status ? <Chip label={titleCase(String(sel.status))} tone={statusTone(String(sel.status))} /> : null}{sel.threat_level ? <Chip label={titleCase(String(sel.threat_level)) + ' threat'} tone={sel.threat_level === 'high' ? 'red' : sel.threat_level === 'medium' ? 'amber' : 'slate'} /> : null}</div><SheetTitle className='mt-1'>{sel.title || sel.name}</SheetTitle><SheetDescription>{sel.category ? titleCase(String(sel.category)) + ' risk' : sel.kind ? titleCase(String(sel.kind)) : 'Detail'}</SheetDescription></SheetHeader>{sel.impact != null ? <div className='mt-4 grid grid-cols-3 gap-2'><StatTile label='Impact' value={sel.impact + '/5'} /><StatTile label='Likelihood' value={sel.likelihood + '/5'} /><StatTile label='Score' value={sel.score} /></div> : null}<Card className='mt-4 p-4'><ReadableObject data={sel} /></Card></SheetContent></Sheet> : null}
  </div>);
}

function StrategyApp() {
  const { d, err, busy, load } = useWs('ws.strategy'); const [sel, setSel] = React.useState<any>(null);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Strategy: {err}</Card>;
  const k = d?.kpis || {}; const risks = d?.risks || []; const under = d?.under_supplied || []; const recs = d?.recommendations || []; const intel = d?.market_intel || []; const sims = d?.recent_simulations || [];
  const sortedRisks = [...risks].sort((a: any, b: any) => (Number(b.score) || 0) - (Number(a.score) || 0));
  return (<div className='space-y-4'>
    <AppHeader icon={Compass} title='Strategy' onRefresh={load} busy={busy} badge={k.open_risks ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{k.open_risks} open risks</Badge> : null} />
    <KpiRow items={[['Cash', k.cash != null ? aed(k.cash) : '—'], ['Monthly burn', k.monthly_burn != null ? aed(k.monthly_burn) : '—'], ['Runway', k.runway_months != null ? k.runway_months + ' mo' : '—'], ['Open risks', k.open_risks], ['Under-supplied', k.under_supplied_categories], ['Top supplier share', k.top_supplier_share_pct != null ? k.top_supplier_share_pct + '%' : '—']]} />
    <SectionCard title='Risk register' count={risks.length}>{sortedRisks.length ? <div className='divide-y divide-border'>{sortedRisks.map((r: any, i: number) => (
      <button key={i} onClick={() => setSel(r)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'>
        <div className='min-w-0 flex-1'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{r.title}{r.category ? <span className='text-[11px] text-muted-foreground'>{r.category}</span> : null}<Chip label={titleCase(String(r.status))} tone={statusTone(String(r.status))} /></div><div className='text-[11px] text-muted-foreground mt-0.5'>Impact {r.impact}/5 · Likelihood {r.likelihood}/5</div></div>
        <div className='flex items-center gap-2 shrink-0'><Chip label={'Score ' + r.score} tone={Number(r.score) >= 15 ? 'red' : Number(r.score) >= 8 ? 'amber' : 'slate'} /><ChevronRight className='h-4 w-4 text-muted-foreground' /></div>
      </button>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No open risks.</div>}</SectionCard>
    {under.length ? <SectionCard title='Under-supplied categories' count={under.length}><div className='p-4'><HBars rows={under.slice(0, 10).map((u: any) => ({ label: u.category || u.key || u.label, n: Number(u.gap ?? u.count ?? u.n ?? 0) }))} /></div></SectionCard> : null}
    {recs.length ? <SectionCard title='Recommendations' count={recs.length}><div className='divide-y divide-border'>{recs.map((r: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm'>{r.title || r.recommendation || fmt(r)}</div>))}</div></SectionCard> : null}
    {intel.length ? <SectionCard title='Market intel' count={intel.length}><div className='p-4'><ReadableObject data={intel} /></div></SectionCard> : null}
    {sims.length ? <SectionCard title='Recent simulations' count={sims.length}><div className='p-4'><ReadableObject data={sims} /></div></SectionCard> : null}
    {sel ? <Sheet open={true} onOpenChange={(o) => { if (!o) setSel(null); }}><SheetContent side='right' className='w-full sm:max-w-lg overflow-y-auto'><SheetHeader><div className='flex items-center gap-2'><Chip label={'Score ' + sel.score} tone={Number(sel.score) >= 15 ? 'red' : Number(sel.score) >= 8 ? 'amber' : 'slate'} /><Chip label={titleCase(String(sel.status))} tone={statusTone(String(sel.status))} /></div><SheetTitle className='mt-1'>{sel.title}</SheetTitle><SheetDescription>{sel.category ? titleCase(String(sel.category)) + ' risk' : 'Risk'}</SheetDescription></SheetHeader><div className='mt-4 grid grid-cols-3 gap-2'><StatTile label='Impact' value={sel.impact + '/5'} /><StatTile label='Likelihood' value={sel.likelihood + '/5'} /><StatTile label='Score' value={sel.score} /></div><Card className='mt-4 p-4'><ReadableObject data={sel} /></Card></SheetContent></Sheet> : null}
  </div>);
}

const KGAP_TONE: Record<string, string> = { ok: 'green', thin: 'amber', stale: 'amber', missing: 'red' };
function ExamPanel() {
  const [d, setD] = React.useState<any>(null); const [busy, setBusy] = React.useState(false); const [msg, setMsg] = React.useState('');
  const load = React.useCallback(() => { osApi('exam_summary').then(setD).catch(() => {}); }, []);
  React.useEffect(() => { load(); }, [load]);
  const run = async () => { setBusy(true); setMsg('Examining the next agent (generating questions, grading, auto-filling verified gaps)…'); try { const r: any = await osApi('exam_run', {}); setMsg('Examined ' + (r?.label || r?.agent || 'agent') + ': ' + (r?.score ?? '—') + '% · ' + (r?.gaps ?? 0) + ' gap(s), ' + (r?.filled ?? 0) + ' auto-filled, ' + (r?.conflicts ?? 0) + ' withheld.'); load(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); } setBusy(false); };
  const o = d?.overall || {}; const agents = (d?.agents || []) as any[];
  return (<SectionCard title='Auto-learning exam' right={<div className='flex items-center gap-2'>{msg ? <span className='text-[11px] text-muted-foreground max-w-md truncate'>{msg}</span> : null}<Button className='h-7 text-xs' variant='outline' disabled={busy} onClick={run}>{busy ? 'Examining…' : 'Run exam now'}</Button></div>}>
    <div className='p-4 space-y-3'>
      <div className='grid grid-cols-2 md:grid-cols-4 gap-2'>
        <StatTile label='Avg score (30d)' value={o.avg_score != null ? o.avg_score + '%' : '—'} />
        <StatTile label='Exams (30d)' value={o.exams_30d} />
        <StatTile label='Gaps filled (30d)' value={o.gaps_filled_30d} />
        <StatTile label='Question bank' value={o.question_bank} />
      </div>
      <div className='text-[11px] text-muted-foreground'>An examiner writes domain questions, each agent answers from its own knowledge, an independent grader judges, and a verified correction is auto-written only when two independent models agree and it passes the poison-lint. Runs every 4h.</div>
      {agents.length ? <div className='overflow-auto max-h-64 rounded-md border border-border'><table className='w-full text-sm'><thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border sticky top-0 bg-card'><th className='px-3 py-2 font-medium'>Agent</th><th className='px-3 py-2 font-medium'>Score</th><th className='px-3 py-2 font-medium'>Examined</th><th className='px-3 py-2 font-medium'>Gaps</th><th className='px-3 py-2 font-medium'>Filled</th></tr></thead>
        <tbody>{agents.map((a) => (<tr key={a.agent_key} className='border-b border-border/40'><td className='px-3 py-2 font-medium'>{a.agent_key}</td><td className='px-3 py-2'><Chip label={(a.score_pct ?? 0) + '%'} tone={Number(a.score_pct) >= 80 ? 'green' : Number(a.score_pct) >= 50 ? 'amber' : 'red'} /></td><td className='px-3 py-2 tabular-nums'>{a.examined}</td><td className='px-3 py-2 tabular-nums'>{a.gaps}</td><td className='px-3 py-2 tabular-nums'>{a.filled}</td></tr>))}</tbody></table></div> : <div className='text-xs text-muted-foreground'>No exams yet — click Run exam now, or wait for the 4-hourly cycle.</div>}
    </div>
  </SectionCard>);
}
function KnowledgeHealthCard() {
  const [d, setD] = React.useState<any>(null); const [err, setErr] = React.useState(''); const [busy, setBusy] = React.useState(false);
  const [rbusy, setRbusy] = React.useState(''); const [msg, setMsg] = React.useState(''); const [show, setShow] = React.useState<'gaps' | 'all'>('gaps');
  const load = React.useCallback(() => { setBusy(true); osApi('knowledge_gaps').then(setD).catch((e: any) => setErr(e.message)).finally(() => setBusy(false)); }, []);
  React.useEffect(() => { load(); }, [load]);
  const refresh = async (slug: string) => { setRbusy(slug); setMsg(''); try { await osApi('knowledge_refresh', { slug }); setMsg('Refreshed ' + slug + ' — knowledge regenerated.'); load(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); } setRbusy(''); };
  const exportKb = async (slug?: string) => { setRbusy('export' + (slug || 'all')); setMsg('Building export…'); try { const r: any = await osApi('knowledge_export', slug ? { agent_key: slug } : {}); const blob = new Blob([r.markdown], { type: 'text/markdown' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = r.filename; a.click(); URL.revokeObjectURL(url); setMsg('Exported ' + r.count + ' item(s) → ' + r.filename); } catch (e: any) { setMsg('Export failed: ' + (e?.message || 'error')); } setRbusy(''); };
  const sweep = async () => { setBusy(true); setMsg(''); try { const r: any = await osApi('knowledge_dispatch'); setMsg('Gap sweep run — ' + (r?.gaps_found ?? 0) + ' open task(s) for lagging agents.'); load(); } catch (e: any) { setMsg('Failed: ' + (e?.message || 'error')); } setBusy(false); };
  if (err && !d) return <Card className='p-4 text-sm text-destructive'>Could not load knowledge health: {err}</Card>;
  const s = d?.summary || {}; const agents = (d?.agents || []) as any[];
  const shown = show === 'gaps' ? agents.filter((a) => a.status !== 'ok') : agents;
  const cov = Number(s.coverage_pct) || 0;
  return (
    <SectionCard title='Agent knowledge health' count={s.total} right={<div className='flex items-center gap-2'>{msg ? <span className='text-[11px] text-muted-foreground max-w-xs truncate'>{msg}</span> : null}<Button className='h-7 text-xs' variant='outline' disabled={rbusy === 'exportall'} onClick={() => exportKb()}>{rbusy === 'exportall' ? '…' : 'Export all (.md)'}</Button><Button className='h-7 text-xs' variant='outline' disabled={busy} onClick={sweep}>{busy ? '…' : 'Run gap sweep'}</Button></div>}>
      <div className='p-4 space-y-3'>
        <div className='flex items-center gap-2'><span className='text-xs text-muted-foreground w-24'>Fresh coverage</span><div className='flex-1 h-2 rounded-full bg-foreground/[0.06] overflow-hidden'><div className={cn('h-full rounded-full', cov >= 70 ? 'bg-emerald-500' : cov >= 40 ? 'bg-amber-500' : 'bg-red-500')} style={{ width: Math.max(2, cov) + '%' }} /></div><span className='text-[11px] tabular-nums text-muted-foreground'>{cov}%</span></div>
        <div className='flex flex-wrap gap-2 text-[11px]'>{s.ok ? <Chip label={s.ok + ' fresh'} tone='green' /> : null}{s.stale ? <Chip label={s.stale + ' stale'} tone='amber' /> : null}{s.thin ? <Chip label={s.thin + ' thin'} tone='amber' /> : null}{s.missing ? <Chip label={s.missing + ' missing'} tone='red' /> : null}<span className='text-muted-foreground ml-auto'>Chief of Staff opens an auto-closing task per lagging agent daily; the curator refreshes the stalest.</span></div>
        <div className='inline-flex rounded-md border border-border overflow-hidden text-xs'>{([['gaps', 'Needs refresh ' + agents.filter((a) => a.status !== 'ok').length], ['all', 'All ' + agents.length]] as [any, string][]).map(([f, lbl]) => (<button key={f} onClick={() => setShow(f)} className={cn('h-7 px-2.5 border-l first:border-l-0 border-border', show === f ? 'bg-primary text-primary-foreground' : 'hover:bg-foreground/5')}>{lbl}</button>))}</div>
        <div className='overflow-auto max-h-80 rounded-md border border-border'>
          <table className='w-full text-sm'><thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border sticky top-0 bg-card'><th className='px-3 py-2 font-medium'>Agent</th><th className='px-3 py-2 font-medium'>Items</th><th className='px-3 py-2 font-medium'>Last refresh</th><th className='px-3 py-2 font-medium'>Status</th><th className='px-3 py-2' /></tr></thead>
            <tbody>{shown.map((a) => (<tr key={a.slug} className='border-b border-border/40'>
              <td className='px-3 py-2 font-medium'>{a.emoji ? a.emoji + ' ' : ''}{a.name}</td>
              <td className='px-3 py-2 tabular-nums'>{a.items}</td>
              <td className='px-3 py-2 text-muted-foreground whitespace-nowrap'>{a.days_stale == null ? 'never' : a.days_stale + 'd ago'}</td>
              <td className='px-3 py-2'><Chip label={titleCase(String(a.status))} tone={KGAP_TONE[a.status] || 'slate'} /></td>
              <td className='px-3 py-2 text-right whitespace-nowrap'><Button className='h-7 text-xs mr-1' variant='ghost' disabled={rbusy === 'export' + a.slug} onClick={() => exportKb(a.slug)} title='Export this agent’s knowledge as Markdown'>{rbusy === 'export' + a.slug ? '…' : 'Export'}</Button><Button className='h-7 text-xs' variant='outline' disabled={rbusy === a.slug} onClick={() => refresh(a.slug)}>{rbusy === a.slug ? 'Refreshing…' : 'Refresh'}</Button></td>
            </tr>))}{!shown.length ? <tr><td colSpan={5} className='px-3 py-6 text-center text-sm text-muted-foreground'>All agents are fresh.</td></tr> : null}</tbody>
          </table>
        </div>
      </div>
    </SectionCard>
  );
}
function GovernanceApp() {
  const { d, err, busy, load } = useWs('ws.governance');
  const [row, setRow] = React.useState<any>(null);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Governance: {err}</Card>;
  const k = d?.kpis || {}; const cov = d?.agent_coverage || []; const rules = d?.universal_rules || []; const esc = d?.recent_escalations || [];
  const personaPct = k.active_agents ? Math.round(100 * (k.agents_with_persona || 0) / k.active_agents) : 0;
  const auditPct = k.active_agents ? Math.round(100 * (k.agents_with_audit_trail || 0) / k.active_agents) : 0;
  return (<div className='space-y-4'>
    <AppHeader icon={Scale} title='Governance' onRefresh={load} busy={busy} badge={k.open_for_review ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{k.open_for_review} awaiting review</Badge> : null} />
    <KpiRow items={[['Active agents', k.active_agents], ['Global rules', k.global_rules], ['Decisions 30d', k.decisions_30d], ['Escalated 30d', k.escalated_30d], ['Avg confidence', k.avg_confidence != null ? Math.round(k.avg_confidence * 100) + '%' : '—'], ['Knowledge items', k.knowledge_items]]} />
    <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
      <SectionCard title='Governance coverage'><div className='p-4 space-y-3'>
        <div><div className='flex justify-between text-xs mb-1'><span>Agents with persona</span><span className='tabular-nums text-muted-foreground'>{k.agents_with_persona}/{k.active_agents}</span></div><div className='h-2 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-emerald-500' style={{ width: personaPct + '%' }} /></div></div>
        <div><div className='flex justify-between text-xs mb-1'><span>Agents with audit trail</span><span className='tabular-nums text-muted-foreground'>{k.agents_with_audit_trail}/{k.active_agents}</span></div><div className='h-2 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-blue-500' style={{ width: auditPct + '%' }} /></div></div>
      </div></SectionCard>
      <SectionCard title='Universal rules' count={rules.length}><div className='p-4 space-y-1.5 max-h-64 overflow-y-auto'>{rules.map((r: any, i: number) => (<div key={i} className='text-xs flex gap-2'><Check className='h-3.5 w-3.5 text-emerald-500 shrink-0 mt-0.5' /><span>{typeof r === 'string' ? r : (r.rule || r.title || fmt(r))}</span></div>))}</div></SectionCard>
    </div>
    <SectionCard title='Recent escalations' count={esc.length}>{esc.length ? <div className='divide-y divide-border'>{esc.map((e: any, i: number) => (<div key={i} onClick={() => setRow({ id: e.id ?? i, title: String(e.title || 'Escalation'), row: e })} className='px-4 py-2.5 cursor-pointer hover:bg-foreground/5 transition-colors'><div className='text-sm font-medium flex items-center gap-1.5 flex-wrap'>{e.title}<span className='text-[11px] text-muted-foreground'>{e.agent}</span>{e.os ? <Chip label={titleCase(String(e.os)) + ' OS'} tone='slate' /> : null}{e.confidence != null ? <Chip label={Math.round(e.confidence * 100) + '%'} tone='blue' /> : null}</div><div className='text-xs text-muted-foreground mt-0.5'>{e.reason} · {fmt(e.created)}</div>{e.outcome ? <div className='text-[11px] text-muted-foreground'>After: {e.outcome}</div> : null}{Array.isArray(e.policies) && e.policies.length ? <div className='text-[11px] text-muted-foreground'>Policies: {e.policies.join(' · ')}</div> : null}{Array.isArray(e.alternatives) && e.alternatives.length ? <div className='text-[11px] text-muted-foreground'>Alternatives: {e.alternatives.map((o: any) => String(o?.option || '') + (o?.selected ? ' (taken)' : '')).join(' · ')}</div> : null}</div>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No recent escalations.</div>}</SectionCard>
    {row ? <RecordDrawer frame0={{ entity: 'agent_action', id: row.id, title: row.title, row: row.row }} onClose={() => setRow(null)} /> : null}
    <KnowledgeHealthCard />
    <ExamPanel />
    {(cov || []).length ? <SectionCard title='Agent coverage' count={cov.length}><div className='overflow-auto max-h-72'><table className='w-full text-sm'><thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border sticky top-0 bg-card'><th className='px-4 py-2 font-medium'>Agent</th><th className='px-3 py-2 font-medium'>Persona</th><th className='px-3 py-2 font-medium'>Knowledge</th><th className='px-3 py-2 font-medium'>Audit items</th></tr></thead><tbody>{cov.map((c: any, i: number) => (<tr key={i} className='border-b border-border/40'><td className='px-4 py-2'>{c.agent}</td><td className='px-3 py-2'>{c.has_persona ? <Check className='h-4 w-4 text-emerald-500' /> : <Minus className='h-4 w-4 text-muted-foreground/40' />}</td><td className='px-3 py-2'>{c.has_knowledge ? <Check className='h-4 w-4 text-emerald-500' /> : <Minus className='h-4 w-4 text-muted-foreground/40' />}</td><td className='px-3 py-2 tabular-nums'>{c.audit_items}</td></tr>))}</tbody></table></div></SectionCard> : null}
  </div>);
}

function CompanyApp() {
  const { d, err, busy, load } = useWs('ws.company');
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Company: {err}</Card>;
  const depts = d?.departments || []; const runs = d?.runs || []; const evals = d?.evals || []; const legal = d?.legal || {};
  const ev = (evals[0] && evals[0].kpis) || {}; const lk = legal.kpis || {}; const lflags = legal.flags || []; const missing = legal.missing_docs || [];
  return (<div className='space-y-4'>
    <AppHeader icon={Building2} title='Company' onRefresh={load} busy={busy} badge={legal.health != null ? <Badge className={cn('border-0', legal.health >= 70 ? 'bg-emerald-500/15 text-emerald-600' : 'bg-amber-500/15 text-amber-600')}>Legal health {Math.round(legal.health)}/100</Badge> : null} />
    <KpiRow items={[['Runs 30d', ev.runs_30d], ['Run success', ev.run_success_pct != null ? ev.run_success_pct + '%' : '—'], ['QA pass', ev.qa_pass_pct != null ? ev.qa_pass_pct + '%' : '—'], ['Errors 30d', ev.errors_30d], ['Open escalations', ev.open_escalations], ['Escalation rate', ev.escalation_rate_pct != null ? ev.escalation_rate_pct + '%' : '—']]} />
    <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
      <SectionCard title='Departments' count={depts.length}><div className='p-4'><HBars rows={depts.map((x: any) => ({ label: titleCase(String(x.agent)), n: Number(x.actions) || 0 }))} /></div></SectionCard>
      <SectionCard title='Legal posture'><div className='p-4 space-y-2'>
        <div className='flex items-center gap-2'><span className='text-xs text-muted-foreground w-28'>Doc coverage</span><div className='flex-1 h-2 rounded-full bg-foreground/[0.06] overflow-hidden'><div className='h-full rounded-full bg-primary' style={{ width: Math.max(2, Math.min(100, Number(lk.coverage_pct) || 0)) + '%' }} /></div><span className='text-[11px] tabular-nums text-muted-foreground'>{Math.round(Number(lk.coverage_pct) || 0)}%</span></div>
        <div className='flex flex-wrap gap-2 text-[11px]'>{lk.critical_missing ? <Chip label={lk.critical_missing + ' critical missing'} tone='red' /> : null}{lk.required_missing ? <Chip label={lk.required_missing + ' required missing'} tone='amber' /> : null}{lk.policies_published ? <Chip label={lk.policies_published + ' policies live'} tone='green' /> : null}{lk.open_legal_flags ? <Chip label={lk.open_legal_flags + ' open flags'} tone='amber' /> : null}</div>
      </div></SectionCard>
    </div>
    {lflags.length ? <SectionCard title='Legal flags' count={lflags.length}><div className='divide-y divide-border'>{lflags.map((f: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm flex items-center gap-2'><Chip label={titleCase(String(f.risk))} tone={riskTone(String(f.risk))} /><span>{f.title}</span></div>))}</div></SectionCard> : null}
    {missing.length ? <SectionCard title='Missing legal documents' count={missing.length}><div className='divide-y divide-border'>{missing.map((m: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm flex items-center justify-between gap-2'><span>{m.requirement}</span><div className='flex items-center gap-2 shrink-0'><span className='text-[11px] text-muted-foreground'>{m.applies_to}</span><Chip label={'P' + m.priority} tone={m.priority === 1 ? 'red' : m.priority === 2 ? 'amber' : 'slate'} /></div></div>))}</div></SectionCard> : null}
    <SectionCard title='Recent agent runs' count={runs.length}><div className='divide-y divide-border max-h-72 overflow-y-auto'>{runs.map((r: any, i: number) => (<div key={i} className='px-4 py-2 flex items-center justify-between gap-2'><div className='min-w-0'><div className='text-sm flex items-center gap-1.5'><Chip label={titleCase(String(r.status))} tone={statusTone(String(r.status))} /><span className='font-medium'>{titleCase(String(r.agent))}</span></div>{r.note ? <div className='text-[11px] text-muted-foreground line-clamp-1'>{r.note}</div> : null}</div><span className='text-[11px] text-muted-foreground whitespace-nowrap'>{fmt(r.started_at)}</span></div>))}</div></SectionCard>
  </div>);
}

function AssistantApp() {
  const { d, err, busy, load } = useWs('ws.ea'); const [dbusy, setDbusy] = React.useState('');
  const [row, setRow] = React.useState<any>(null);
  const taskDone = async (id: any) => { setDbusy('t' + id); try { await osOps('task_done', { id, op: 'done' }); load(); } catch (_e) {} setDbusy(''); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Assistant: {err}</Card>;
  const tasks = d?.open_tasks || []; const today = d?.today_events || []; const upcoming = d?.upcoming_events || []; const reminders = d?.reminders_due || []; const approvals = d?.approvals_top || []; const meetings = d?.recent_meetings || [];
  return (<div className='space-y-4'>
    <AppHeader icon={Calendar} title='Assistant' onRefresh={load} busy={busy} badge={d?.overdue_tasks ? <Badge className='bg-red-500/15 text-red-600 border-0'>{d.overdue_tasks} overdue</Badge> : null} />
    <KpiRow items={[['Open tasks', tasks.length], ['Overdue', d?.overdue_tasks], ['Approvals', d?.approvals_total], ['High-risk approvals', d?.approvals_high_risk], ['Today', today.length], ['Reminders due', reminders.length]]} />
    {(today.length || upcoming.length) ? <div className='grid grid-cols-1 lg:grid-cols-2 gap-4'>
      <SectionCard title='Today' count={today.length}>{today.length ? <div className='divide-y divide-border'>{today.map((e: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm'><div className='font-medium'>{e.title || e.summary}</div><div className='text-[11px] text-muted-foreground'>{fmt(e.start || e.at || e.when)}</div></div>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>Nothing today.</div>}</SectionCard>
      <SectionCard title='Upcoming' count={upcoming.length}>{upcoming.length ? <div className='divide-y divide-border'>{upcoming.map((e: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm'><div className='font-medium'>{e.title || e.summary}</div><div className='text-[11px] text-muted-foreground'>{fmt(e.start || e.at || e.when)}</div></div>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>Nothing scheduled.</div>}</SectionCard>
    </div> : null}
    <SectionCard title='Open tasks' count={tasks.length}>{tasks.length ? <div className='divide-y divide-border'>{tasks.map((t: any) => (<div key={t.id} className='px-4 py-2.5 flex items-center justify-between gap-3'><div className='min-w-0'><div className='text-sm flex items-center gap-1.5'>{t.priority ? <Chip label={String(t.priority)} tone={priorityTone(String(t.priority))} /> : null}<span className='line-clamp-1'>{t.title}</span></div><div className='text-[11px] text-muted-foreground'>{t.source}{t.due ? ' · due ' + fmt(t.due) : ''}</div></div><Button className='h-7 text-xs shrink-0' variant='outline' disabled={dbusy === 't' + t.id} onClick={() => taskDone(t.id)}>{dbusy === 't' + t.id ? '…' : 'Done'}</Button></div>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No open tasks.</div>}</SectionCard>
    {approvals.length ? <SectionCard title='Approvals awaiting you' count={d?.approvals_total ?? approvals.length}><div className='p-4'><div className='mb-2 flex flex-wrap gap-1.5'>{(approvals as any[]).map((a: any, i: number) => (<button key={i} onClick={() => setRow({ id: a.id ?? i, title: String(a.title || 'Action'), row: a })} className='text-[11px] rounded border border-border px-1.5 py-0.5 hover:bg-foreground/5'>Open #{a.id ?? i}</button>))}</div><ReadableObject data={approvals} /></div></SectionCard> : null}
    {row ? <RecordDrawer frame0={{ entity: 'agent_action', id: row.id, title: row.title, row: row.row }} onClose={() => setRow(null)} /> : null}
    {reminders.length ? <SectionCard title='Reminders due' count={reminders.length}><div className='p-4'><ReadableObject data={reminders} /></div></SectionCard> : null}
    {meetings.length ? <SectionCard title='Recent meetings' count={meetings.length}><div className='p-4'><ReadableObject data={meetings} /></div></SectionCard> : null}
  </div>);
}

function DocumentsApp() {
  const { d, err, busy, load } = useWs('ws.documents'); const [sel, setSel] = React.useState<any>(null); const [dbusy, setDbusy] = React.useState('');
  const reviewDecide = async (id: any, op: string) => { setDbusy(String(id) + op); try { await osOps('doc_review_decide', { id, op }); load(); } catch (_e) {} setDbusy(''); };
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Documents: {err}</Card>;
  const k = d?.kpis || {}; const kinds = d?.kinds || []; const docs = d?.documents || []; const reviews = d?.reviews || [];
  return (<div className='space-y-4'>
    <AppHeader icon={FileText} title='Documents' onRefresh={load} busy={busy} badge={k.reviews_pending ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{k.reviews_pending} to review</Badge> : null} />
    <KpiRow items={[['Documents', k.documents], ['Indexed', k.indexed], ['Versions', k.versions], ['Dropbox files', k.dropbox_files], ['Inventory total', k.inventory_total], ['Reviews pending', k.reviews_pending]]} />
    {reviews.length ? <SectionCard title='Reviews pending' count={reviews.length}><div className='divide-y divide-border'>{reviews.map((r: any) => (<div key={r.id} className='px-4 py-2.5 flex items-center justify-between gap-3'><div className='min-w-0'><div className='text-sm font-medium line-clamp-1'>{r.title || r.file_name || 'Document #' + r.id}</div><div className='text-[11px] text-muted-foreground'>{r.kind} · {fmt(r.created_at || r.at)}</div></div><div className='flex gap-1.5 shrink-0'><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(r.id) + 'approve'} onClick={() => reviewDecide(r.id, 'approve')}>Approve</Button><Button className='h-7 text-xs' variant='outline' disabled={dbusy === String(r.id) + 'reject'} onClick={() => reviewDecide(r.id, 'reject')}>Reject</Button></div></div>))}</div></SectionCard> : null}
    {kinds.length ? <SectionCard title='By document type'><div className='p-4'><HBars rows={kinds.map((x: any) => ({ label: titleCase(String(x.key)), n: Number(x.count) }))} /></div></SectionCard> : null}
    <SectionCard title='Document inventory' count={docs.length}>{docs.length ? <div className='overflow-auto max-h-[60vh]'><table className='w-full text-sm'><thead><tr className='text-left text-[11px] text-muted-foreground border-b border-border sticky top-0 bg-card'><th className='px-4 py-2 font-medium'>File</th><th className='px-3 py-2 font-medium'>Kind</th><th className='px-3 py-2 font-medium'>Status</th><th className='px-3 py-2 font-medium'>Indexed</th><th className='px-3 py-2 font-medium'>Created</th><th className='w-8' /></tr></thead><tbody>{docs.map((doc: any) => (<tr key={doc.id} onClick={() => setSel(doc)} className='group border-b border-border/40 hover:bg-foreground/5 cursor-pointer'><td className='px-4 py-2.5 font-medium'><span className='inline-flex items-center gap-2'><FileText className='h-4 w-4 text-muted-foreground shrink-0' />{doc.file_name || 'Document #' + doc.id}</span></td><td className='px-3 py-2.5'>{doc.kind ? <Chip label={titleCase(String(doc.kind))} tone='slate' /> : '—'}</td><td className='px-3 py-2.5'><Chip label={titleCase(String(doc.status))} tone={statusTone(String(doc.status))} /></td><td className='px-3 py-2.5'>{doc.indexed ? <Check className='h-4 w-4 text-emerald-500' /> : <Minus className='h-4 w-4 text-muted-foreground/40' />}</td><td className='px-3 py-2.5 text-muted-foreground whitespace-nowrap'>{fmt(doc.created_at)}</td><td className='pr-2 text-right'><ChevronRight className='h-3.5 w-3.5 inline text-muted-foreground/0 group-hover:text-muted-foreground/50' /></td></tr>))}</tbody></table></div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No documents.</div>}</SectionCard>
    {sel ? <RecordDrawer frame0={{ entity: sel.ref_table === 'leads' ? 'supplier' : undefined, id: sel.ref_table === 'leads' ? sel.ref_id : undefined, title: sel.file_name || 'Document #' + sel.id, row: sel }} onClose={() => setSel(null)} /> : null}
  </div>);
}

function ReportViewerDrawer({ report, onClose }: { report: any; onClose: () => void }) {
  return (<Sheet open={true} onOpenChange={(o) => { if (!o) onClose(); }}><SheetContent side='right' className='w-full sm:max-w-2xl overflow-y-auto'>
    <SheetHeader>
      <div className='flex items-center gap-2 flex-wrap'>{report.report_type ? <Chip label={titleCase(String(report.report_type))} tone='blue' /> : null}{report.period ? <span className='text-[11px] text-muted-foreground'>{report.period}</span> : null}</div>
      <SheetTitle className='mt-1'>{report.title}</SheetTitle>
      <SheetDescription>{report.source ? titleCase(String(report.source)) + ' · ' : ''}{fmt(report.created)}</SheetDescription>
    </SheetHeader>
    <ReportViewer id={Number(report.id)} />
  </SheetContent></Sheet>);
}
// THE WEEKLY EXECUTIVE MEETING, REPLAYED IN THE ORDER IT HAPPENED.
// exec_reports.findings is the ordered transcript — ten officers plus the company-level items — and
// report_registry only ever projected the title, period and id, so the body of the meeting reached
// nothing the browser could run. fn_ws_reports carries it now: the contributions in sequence, the
// ranked priorities the meeting agreed, and the challenges recorded inside its own window.
//
// Contributions written before 9 Aug 2026 carry item/owner/health/finding/drivers and none of the
// six agenda sections, so every section is rendered only when it is actually present. An older
// meeting shows what it has rather than six empty rows.
function MeetingReplay({ meeting }: { meeting: any }) {
  const SECTIONS: [string, string][] = [['wins', 'Wins'], ['problems', 'Problems'], ['kpis', 'KPIs'], ['risks', 'Risks'], ['opportunities', 'Opportunities'], ['requests', 'Requests']];
  const contributions = meeting?.contributions || []; const priorities = meeting?.priorities || []; const challenges = meeting?.challenges || [];
  const [open, setOpen] = React.useState<number | null>(0);
  if (!contributions.length && !priorities.length) return null;
  const stanceTone = (s: string) => /against/.test(s) ? 'red' : /concern/.test(s) ? 'amber' : 'green';
  return (<SectionCard title={'Executive meeting' + (meeting.period ? ' — ' + String(meeting.period) : '')} count={contributions.length} right={<span className='text-[11px] text-muted-foreground'>{fmt(meeting.at)}</span>}>
    {meeting.summary ? <div className='px-4 py-2.5 text-xs text-muted-foreground border-b border-border'>{meeting.summary}</div> : null}
    {priorities.length ? <div className='px-4 py-3 border-b border-border'><div className='text-xs font-semibold mb-2'>Agreed priorities</div><ol className='space-y-1'>{priorities.map((p: any, i: number) => (<li key={i} className='text-xs flex items-center gap-2'><span className='tabular-nums text-muted-foreground w-4 shrink-0'>{(p && typeof p === 'object' ? p.rank : null) ?? i + 1}</span><span className='flex-1'>{p && typeof p === 'object' ? String(p.title || p.why || '') : String(p)}</span>{p && typeof p === 'object' && p.owner ? <Chip label={String(p.owner)} tone='slate' /> : null}{p && typeof p === 'object' && p.priority ? <Chip label={String(p.priority)} tone={CHIP_TONE[String(p.priority)] ? String(p.priority) : statusTone(String(p.priority))} /> : null}</li>))}</ol></div> : null}
    <div className='divide-y divide-border'>{contributions.map((c: any, i: number) => (<div key={i}>
      <button onClick={() => setOpen(open === i ? null : i)} className='w-full text-left px-4 py-2.5 hover:bg-foreground/5 transition-colors flex items-center gap-2'><span className='tabular-nums text-[11px] text-muted-foreground w-5 shrink-0'>{i + 1}</span><span className='flex-1 text-sm font-medium line-clamp-1'>{c.item}</span>{c.owner ? <Chip label={String(c.owner)} tone='slate' /> : null}{c.health ? <Chip label={String(c.health)} tone={CHIP_TONE[String(c.health)] ? String(c.health) : 'slate'} /> : null}<ChevronRight className={cn('h-4 w-4 text-muted-foreground shrink-0 transition-transform', open === i ? 'rotate-90' : '')} /></button>
      {open === i ? <div className='px-4 pb-3 pl-11 space-y-1.5'>{SECTIONS.map(([key, label]) => { const v = c[key]; if (v == null || v === '') return null; const body = typeof v === 'object' ? Object.entries(v).map(([kk, vv]) => String(kk).replace(/_/g, ' ') + ' ' + String(vv ?? '—')).join(', ') : String(v); return (<div key={key} className='text-xs'><span className='text-muted-foreground'>{label}: </span>{body}</div>); })}{c.drivers ? <div className='text-[11px] text-muted-foreground pt-0.5'>{String(c.drivers)}</div> : null}</div> : null}
    </div>))}</div>
    {challenges.length ? <div className='px-4 py-3 border-t border-border'><div className='text-xs font-semibold mb-2'>Challenged in the meeting</div><div className='space-y-1.5'>{challenges.map((ch: any, i: number) => (<div key={i} className='text-xs flex items-start gap-2'><Chip label={String(ch.stance || '')} tone={stanceTone(String(ch.stance || ''))} /><span className='flex-1'><span className='text-muted-foreground'>{String(ch.by || '')} on {String(ch.of || '')}: </span>{String(ch.reasoning || '')}</span></div>))}</div></div> : null}
  </SectionCard>);
}
function ReportsApp() {
  const { d, err, busy, load } = useWs('ws.reports'); const [sel, setSel] = React.useState<any>(null);
  if (err && !d) return <Card className='p-6 text-sm text-destructive'>Could not load Reports: {err}</Card>;
  const k = d?.kpis || {}; const recent = d?.recent || []; const byType = d?.by_type || []; const flags = d?.flags || []; const meeting = d?.meeting || null;
  const TYPES = ['daily', 'weekly', 'monthly', 'quarterly', 'finance', 'exec', 'customer', 'supplier', 'department', 'ai'];
  const fresh = TYPES.filter((t) => k[t + '_at']).map((t) => ({ type: t, at: k[t + '_at'], fresh: k[t + '_fresh'] }));
  return (<div className='space-y-4'>
    <AppHeader icon={FileBarChart} title='Reports' onRefresh={load} busy={busy} badge={k.stale_count ? <Badge className='bg-amber-500/15 text-amber-600 border-0'>{k.stale_count} stale</Badge> : null} />
    <KpiRow items={[['Total reports', k.total_reports], ['Reports 30d', k.reports_30d], ['Report types', k.report_types], ['Stale', k.stale_count]]} />
    {meeting ? <MeetingReplay meeting={meeting} /> : null}
    {fresh.length ? <SectionCard title='Report freshness'><div className='p-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2'>{fresh.map((f) => (<div key={f.type} className={cn('rounded-md border p-2.5', f.fresh ? 'border-emerald-500/30 bg-emerald-500/[0.03]' : 'border-amber-500/30 bg-amber-500/[0.03]')}><div className='flex items-center justify-between'><span className='text-xs font-medium capitalize'>{f.type}</span>{f.fresh ? <Check className='h-3.5 w-3.5 text-emerald-500' /> : <AlertTriangle className='h-3.5 w-3.5 text-amber-500' />}</div><div className='text-[10px] text-muted-foreground mt-1'>{fmt(f.at)}</div></div>))}</div></SectionCard> : null}
    {flags.length ? <SectionCard title='Report flags' count={flags.length}><div className='divide-y divide-border'>{flags.map((f: any, i: number) => (<div key={i} className='px-4 py-2.5 text-sm flex items-center gap-2'><Chip label={titleCase(String(f.risk))} tone={riskTone(String(f.risk))} /><span className='flex-1'>{f.title}</span>{f.status ? <Chip label={titleCase(String(f.status))} tone={statusTone(String(f.status))} /> : null}</div>))}</div></SectionCard> : null}
    <SectionCard title='Recent reports' count={recent.length}>{recent.length ? <div className='divide-y divide-border'>{recent.map((r: any) => (<button key={r.id} onClick={() => setSel(r)} className='w-full text-left px-4 py-3 hover:bg-foreground/5 transition-colors flex items-center gap-3'><div className='min-w-0 flex-1'><div className='text-sm font-medium line-clamp-1'>{r.title}</div><div className='text-[11px] text-muted-foreground'>{r.source ? titleCase(String(r.source)) + ' · ' : ''}{fmt(r.created)}</div></div>{r.report_type ? <Chip label={titleCase(String(r.report_type))} tone='blue' /> : null}<ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' /></button>))}</div> : <div className='px-4 py-6 text-center text-sm text-muted-foreground'>No reports yet.</div>}</SectionCard>
    {byType.length ? <SectionCard title='Latest by type' count={byType.length}><div className='divide-y divide-border'>{byType.map((r: any) => (<button key={r.id} onClick={() => setSel(r)} className='w-full text-left px-4 py-2.5 hover:bg-foreground/5 transition-colors flex items-center gap-2'><span className='flex-1 text-sm line-clamp-1'>{r.title}</span><Chip label={titleCase(String(r.report_type))} tone='blue' /><ChevronRight className='h-4 w-4 text-muted-foreground shrink-0' /></button>))}</div></SectionCard> : null}
    {sel ? <ReportViewerDrawer report={sel} onClose={() => setSel(null)} /> : null}
  </div>);
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
              <thead><tr className='text-left text-xs text-muted-foreground border-b border-border'>{cols.map((c) => (<th key={c} className='px-4 py-2 font-medium'>{titleCase(c)}</th>))}<th className='w-8' /></tr></thead>
              <tbody>{rows.slice(0, 200).map((r, i) => (<tr key={i} onClick={() => { setRow(r); setRowTitle(singularWord(titleCase(name))); }} className='group border-b border-border/50 hover:bg-foreground/5 cursor-pointer'>{cols.map((c, ci) => (<td key={c} className={cn('px-4 py-2.5', ci === 0 && 'font-medium')}><SmartCell col={c} value={(r as any)[c]} /></td>))}<td className='pr-2 text-right'><ChevronRight className='h-3.5 w-3.5 inline text-muted-foreground/0 group-hover:text-muted-foreground/50 transition-colors' /></td></tr>))}</tbody>
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
