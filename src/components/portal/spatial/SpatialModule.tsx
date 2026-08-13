'use client';
// Spec §6 + §19, mounted as one surface: the Project Room (3D model + click-through) and the
// Supply Chain Map, over three endpoints that already exist and are already customer-authed.
//
// This is the only file that fetches. It deliberately does NOT swap the page for a project: the
// project chips sit above the room and the room re-renders under them, because §21 asks the portal
// to be a workspace rather than a set of pages, and a full-surface early return keyed on navigation
// state is exactly the shape that turns one into the other.
import { useCallback, useEffect, useState } from 'react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { ProjectRoom } from './ProjectRoom';
import { SupplyChainMap } from './SupplyChainMap';
import { fetchDocuments, fetchOrders, fetchProjectDetail, fetchProjectList } from './api';
import { NO_INQUIRIES } from './model';
import type { CustomerOrder, Lang, PortalInquiry, SpatialProject, SpatialRfq, VaultDoc } from './model';
import { tx } from './strings';

export interface SpatialModuleProps {
  token: string;
  lang?: Lang;
  /** Open this project first. Omit and the customer picks from their own list. */
  projectId?: string;
  /**
   * The my_inquiries rows CustomerPortal already holds. Passed rather than re-fetched — the same
   * shape ProjectsModule is given as `linkableRfqs`. Used ONLY for quote counts and revealed
   * supplier names; without it the room says so instead of implying zero quotes.
   */
  inquiries?: PortalInquiry[];
  /** Bubbles a click on a package or a shipment back to the portal's own RFQ surface. */
  onOpenRfq?: (rfqId: string) => void;
}

type Pick = { project_id: string; name: string; status: string; rfq_count: number };

export function SpatialModule({ token, lang = 'en', projectId, inquiries = NO_INQUIRIES, onOpenRfq }: SpatialModuleProps) {
  const [picks, setPicks] = useState<Pick[] | null>(null);
  const [current, setCurrent] = useState<string | null>(projectId || null);
  const [project, setProject] = useState<SpatialProject | null>(null);
  const [rfqs, setRfqs] = useState<SpatialRfq[]>([]);
  const [orders, setOrders] = useState<CustomerOrder[]>([]);
  const [documents, setDocuments] = useState<VaultDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState('');

  // Orders and the vault are per-customer, not per-project, so they load once beside the list.
  const loadShared = useCallback(async () => {
    const [o, d] = await Promise.all([fetchOrders(token), fetchDocuments(token)]);
    if (o.ok) setOrders(o.data.orders || []);
    if (d.ok) setDocuments(d.data.documents || []);
  }, [token]);

  const loadList = useCallback(async () => {
    setErr('');
    const r = await fetchProjectList(token);
    if (!r.ok) { setErr(r.error); setLoading(false); return; }
    const rows = r.data.projects || [];
    setPicks(rows);
    setCurrent((c) => c || (rows[0] ? rows[0].project_id : null));
    setLoading(false);
  }, [token]);

  useEffect(() => { setLoading(true); loadList(); loadShared(); }, [loadList, loadShared]);

  useEffect(() => {
    if (!current) { setProject(null); setRfqs([]); return; }
    let live = true;
    fetchProjectDetail(token, current).then((r) => {
      if (!live) return;
      if (!r.ok) { setErr(r.error); return; }
      setProject(r.data.project || null);
      setRfqs(r.data.rfqs || []);
    });
    return () => { live = false; };
  }, [token, current]);

  if (loading) return <div className="p-5 text-[13px] text-muted-foreground">{tx(lang, 'loading')}</div>;

  if (err && !project) {
    return (
      <Card className="p-5">
        <div className="text-[13px] text-muted-foreground">{tx(lang, 'err_load')} <span className="text-foreground/70">({err})</span></div>
        <Button className="mt-3" size="sm" onClick={() => { setLoading(true); loadList(); }}>{tx(lang, 'retry')}</Button>
      </Card>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        {/* ModuleWindow already renders "Project room" as the h1. See the note in OrdersList. */}
        <div className="text-[13px] text-muted-foreground">{tx(lang, 'room_sub')}</div>
      </div>

      {picks && picks.length === 0 ? (
        <Card className="p-5"><div className="text-[13px] leading-relaxed text-muted-foreground">{tx(lang, 'no_projects')}</div></Card>
      ) : (
        <>
          {picks && picks.length > 1 ? (
            <div className="flex flex-wrap gap-1.5" role="group" aria-label={tx(lang, 'pick_project')}>
              {picks.map((p) => (
                <button
                  key={p.project_id}
                  onClick={() => setCurrent(p.project_id)}
                  aria-pressed={current === p.project_id}
                  className={cn(
                    'rounded-full border px-3 py-1.5 text-[12.5px] font-semibold transition-colors duration-150',
                    current === p.project_id ? 'border-primary bg-primary/15 text-primary' : 'border-border bg-secondary/30 text-muted-foreground hover:bg-secondary/50',
                  )}
                >
                  {p.name}
                </button>
              ))}
            </div>
          ) : null}

          <ProjectRoom
            project={project}
            rfqs={rfqs}
            orders={orders}
            documents={documents}
            inquiries={inquiries}
            lang={lang}
            onOpenRfq={onOpenRfq}
          />
        </>
      )}

      <SupplyChainMap orders={orders} lang={lang} onOpenRfq={onOpenRfq} />
    </div>
  );
}
