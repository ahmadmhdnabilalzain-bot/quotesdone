// @ts-nocheck
'use client';
import { Card } from '@/components/ui/card';
// Cold-first-load fix (14 Sep 2026, en-desktop p50 10.8s / p95 13.2s against a 2.5s bar): shellMs
// (time to the nav being visible, before any API call) was 6.2-7.4s cold vs 1.2-3.3s seconds later
// against the same warm deployment. /me is prerendered static HTML (next build: "me" -> SSG), so
// this is not a Vercel function cold start — it's 1.45 MB raw / ~430 KB gzip of client JS across 16
// chunks that must download, parse and execute before hydration makes the nav visible. Measured on
// quotesdone.com: under normal traffic Vercel's edge cache serves every /me chunk as X-Vercel-Cache
// HIT in <0.25s each; these chunks are portal-only (no marketing page imports them), so after a real
// idle gap with no visitor to /me they fall out of the edge cache and the first request pays a
// cold-cascade refetch across all 16. Fewer, smaller chunks in the critical path shrinks that penalty
// regardless of cache state, and they miss the cache less often once they are only fetched on the
// tab click that needs them instead of on every /me load.
// recharts is the heaviest thing on /me and this chart sits below the fold, so it loads on its own
// after the portal is on screen (website audit 14 Sep 2026: 1.37 MB portal first load).
import dynamic from 'next/dynamic';
import { t } from '../portalText';

const SpendingIntelligence = dynamic(() => import('@/components/portal/intelligence/SpendingIntelligence').then((m) => m.SpendingIntelligence), { ssr: false });
// Every dynamic() below needs a `loading:` fallback: without one, next/dynamic renders NOTHING for
// the one round trip its chunk takes, so a tab panel opened blank (independent review, 14 Sep 2026). ModuleLoading
// is the same Card/pulse skeleton the stat tiles already use (~line 727), so it needs no new pattern,
// and it is defined once and reused rather than repeated at each call site. It reads
// document.documentElement.lang (already set by applyDocumentLocale before any of these can mount,
// and these are ssr:false so this only ever runs in the browser) instead of taking a `lang` prop,
// because next/dynamic's `loading` component is instantiated once per dynamic() call, outside
// CustomerPortal's own render, so it cannot close over this component's `lang` state. A column flex
// of fixed-height boxes plus one centred line of text has nothing left/right-anchored, so it reads
// correctly in both directions without a separate RTL variant.
const ModuleLoading = () => {
  const lang = typeof document !== 'undefined' && document.documentElement.lang === 'ar' ? 'ar' : 'en';
  return (<div className="flex flex-col gap-3 py-2" aria-hidden>
    <Card className="h-24 motion-safe:animate-pulse bg-secondary/25" />
    <Card className="h-40 motion-safe:animate-pulse bg-secondary/25" />
    <div className="text-center text-xs text-muted-foreground">{t(lang, 'loading')}</div>
  </div>);
};
// Spec §22 modules that were written and never mounted, and the five module-agent surfaces below:
// every one of them renders ONLY behind `id === '<tab>'` (see ~line 1505) inside a panel the
// customer opens by clicking a tab — never
// on the initial /me paint — so none of them belongs in the bundle that has to parse before the nav
// is visible. CompanyTwin and DecisionSupport are NOT in this group: independent review (14 Sep
// 2026) found they also render on the default 'home' overview, every signed-in customer's landing
// screen — see the import below and its comment at ~line 145.
const ProjectsModule = dynamic(() => import('@/components/portal/projects').then((m) => m.ProjectsModule), { ssr: false, loading: ModuleLoading });
// The five surfaces the module agents exported and nothing mounted. Each fetches its own endpoint
// and owns its own empty state; the portal supplies only the token, the language and — where the
// surface can use them — rows it already holds, so nothing is fetched twice.
const SpatialModule = dynamic(() => import('@/components/portal/spatial').then((m) => m.SpatialModule), { ssr: false, loading: ModuleLoading });
const DocumentVault = dynamic(() => import('@/components/portal/documents').then((m) => m.DocumentVault), { ssr: false, loading: ModuleLoading });
const CommunicationCenter = dynamic(() => import('@/components/portal/comms').then((m) => m.CommunicationCenter), { ssr: false, loading: ModuleLoading });
const OrdersList = dynamic(() => import('@/components/portal/approvals').then((m) => m.OrdersList), { ssr: false, loading: ModuleLoading });
const PredictiveIntelligence = dynamic(() => import('@/components/portal/predict').then((m) => m.PredictiveIntelligence), { ssr: false, loading: ModuleLoading });
const SupplierDiscovery = dynamic(() => import('@/components/portal/twin').then((m) => m.SupplierDiscovery), { ssr: false, loading: ModuleLoading });
const CustomerMemory = dynamic(() => import('@/components/portal/twin').then((m) => m.CustomerMemory), { ssr: false, loading: ModuleLoading });
// The request composer (754 lines, speech, BOQ, markup) opens only when the customer clicks "new
// request" (showNew starts false), so it is not part of the /me first load (28 Sep 2026).
const NewRequest = dynamic(() => import('../NewRequest').then((mod) => mod.NewRequest), { ssr: false, loading: ModuleLoading });
export { SpendingIntelligence, ProjectsModule, SpatialModule, DocumentVault, CommunicationCenter, OrdersList, PredictiveIntelligence, SupplierDiscovery, CustomerMemory, NewRequest };
