'use client';
// Spec §5, Project Intelligence Workspace — one project as the organising unit above its RFQs.
// Source: project_api action:'detail' (a public.projects row + its linked inquiries).
//
// WHAT THE SPEC ASKS FOR AND WHAT THE API CAN ACTUALLY ANSWER — read before adding a tile:
//   Budget       -> projects.budget_total.                                              exact.
//   Active RFQs  -> linked inquiries whose status is not completed/cancelled.            exact, and
//                   deliberately the same rule project_summary.rfq_open uses, so this page and the
//                   project card can never disagree about the same project.
//   Materials    -> NOT SERVED. There is no materials/BoQ list on a project. The closest true thing
//                   is the distinct category of each linked RFQ, and it is labelled as exactly that
//                   ("Categories sourced"), never as a materials list.
//   Suppliers    -> NOT SERVED as a matched/invited count. inquiries.hired_supplier_id is the only
//                   supplier field here, so this shows suppliers AWARDED and says so.
//   Timeline %   -> NOT SERVED. No progress, milestone or schedule field exists. What is shown is
//                   elapsed time between created_at and target_open_date, labelled as time, with a
//                   note that it is not work completed — and omitted entirely when no target is set.
//
// The rule this file exists to obey: a figure with nothing behind it renders as "—" plus the reason
// it is empty. It never renders as a confident zero, and it never implies work that did not happen.
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { Skeleton } from '@/components/ui/skeleton';
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';
import { projectApi } from './api';
import {
  aed, deriveStats, elapsedPct, fmtDate, isOpenRfq, rfqValue,
  type Lang, type Project, type ProjectRfq,
} from './model';
import { Notice, Stat } from './parts';
import { errText, statusLabel, tr } from './strings';

/** The minimum an RFQ needs for the link picker. Comes from the caller (customer_api my_inquiries),
 *  because project_api has no "my unlinked RFQs" action. */
export interface LinkableRfq {
  id: string;
  summary?: string | null;
  category?: string | null;
}

export interface ProjectWorkspaceProps {
  /** Customer Supabase JWT. */
  token: string;
  /** public.projects.id (project_summary.project_id on a list card). */
  projectId: string;
  lang?: Lang;
  onBack?: () => void;
  /** Shows an Edit button; receives the loaded project row to hand to ProjectForm. */
  onEdit?: (project: Project) => void;
  /** Shows an Open link on each RFQ row; receives inquiries.id. */
  onOpenRfq?: (inquiryId: string) => void;
  /**
   * RFQs the customer owns that are NOT already in this project. project_api's detail action only
   * returns RFQs already linked, so it cannot supply this — the link control is hidden unless the
   * mounting component passes candidates. Anything already linked here is filtered out.
   */
  linkableRfqs?: LinkableRfq[];
  /** Fired after a link/unlink succeeds, so the caller can refresh its own RFQ lists. */
  onChanged?: () => void;
  className?: string;
}

export function ProjectWorkspace({
  token, projectId, lang = 'en', onBack, onEdit, onOpenRfq, linkableRfqs, onChanged, className,
}: ProjectWorkspaceProps) {
  const [project, setProject] = React.useState<Project | null>(null);
  const [rfqs, setRfqs] = React.useState<ProjectRfq[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState('');
  const [busyId, setBusyId] = React.useState('');
  const [reloads, setReloads] = React.useState(0);
  const reload = React.useCallback(() => setReloads((n) => n + 1), []);

  React.useEffect(() => {
    let live = true;
    setLoading(true);
    setError('');
    projectApi<{ project: Project; rfqs: ProjectRfq[] }>(token, { action: 'detail', id: projectId }).then((res) => {
      if (!live) return;
      setLoading(false);
      if (!res.ok) {
        setError(errText(lang, res.error));
        return;
      }
      setProject(res.data.project ?? null);
      setRfqs(Array.isArray(res.data.rfqs) ? res.data.rfqs : []);
    });
    return () => {
      live = false;
    };
  }, [token, projectId, lang, reloads]);

  async function mutate(action: 'link' | 'unlink', inquiryId: string) {
    setBusyId(inquiryId);
    const res = await projectApi<Record<string, never>>(token, { action, inquiry_id: inquiryId, project_id: projectId });
    setBusyId('');
    if (!res.ok) {
      setError(errText(lang, res.error));
      return;
    }
    onChanged?.();
    reload();
  }

  const backBtn = onBack ? (
    <Button type="button" variant="ghost" size="sm" onClick={onBack}>
      {tr(lang, 'back')}
    </Button>
  ) : null;

  if (loading) {
    return (
      <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
        {backBtn}
        <p className="sr-only" role="status">
          {tr(lang, 'loading_project')}
        </p>
        <Skeleton className="h-8 w-1/2" aria-hidden="true" />
        <Skeleton className="h-[132px] w-full rounded-lg" aria-hidden="true" />
        <Skeleton className="h-[220px] w-full rounded-lg" aria-hidden="true" />
      </section>
    );
  }

  if (!project) {
    return (
      <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
        {backBtn}
        <Notice
          tone="error"
          action={
            <Button type="button" size="sm" variant="outline" onClick={reload}>
              {tr(lang, 'retry')}
            </Button>
          }
        >
          {error || tr(lang, 'err_not_found')}
        </Notice>
      </section>
    );
  }

  const s = deriveStats(rfqs);
  const hasRfqs = s.rfqCount > 0;
  const budget = Number(project.budget_total) || 0;
  const committedPct = budget > 0 ? Math.round((s.pipeline / budget) * 100) : null;
  const elapsed = elapsedPct(project.created_at, project.target_open_date);

  return (
    <section className={cn('flex flex-col gap-5', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      {backBtn}

      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2.5">
            <h2 className="text-xl font-extrabold text-foreground">{project.name}</h2>
            <Badge variant={project.status === 'completed' ? 'ok' : project.status === 'archived' ? 'secondary' : 'default'}>
              {statusLabel(lang, project.status)}
            </Badge>
          </div>
          <p className="mt-1 text-[12px] text-muted-foreground">
            {tr(lang, 'created')}: {fmtDate(project.created_at, lang)}
            {' · '}
            {project.target_open_date
              ? `${tr(lang, 'target_date')}: ${fmtDate(project.target_open_date, lang)}`
              : tr(lang, 'no_target_date')}
          </p>
          {project.description ? (
            <p className="mt-2 max-w-[70ch] text-[13px] leading-relaxed text-muted-foreground">{project.description}</p>
          ) : null}
        </div>
        {onEdit ? (
          <Button type="button" variant="outline" onClick={() => onEdit(project)}>
            {tr(lang, 'edit_project')}
          </Button>
        ) : null}
      </header>

      {error ? (
        <Notice
          tone="error"
          action={
            <Button type="button" size="sm" variant="outline" onClick={reload}>
              {tr(lang, 'retry')}
            </Button>
          }
        >
          {error}
        </Notice>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <Stat
          label={tr(lang, 'k_budget')}
          value={budget > 0 ? aed(budget) : undefined}
          empty={tr(lang, 'budget_not_set')}
          hint={committedPct !== null && hasRfqs ? `${committedPct}% ${tr(lang, committedPct > 100 ? 'budget_over' : 'budget_used')}` : undefined}
        />
        <Stat
          label={tr(lang, 'k_pipeline')}
          value={hasRfqs ? aed(s.pipeline) : undefined}
          empty={tr(lang, 'not_from_rfqs')}
          hint={tr(lang, 'pipeline_note')}
        />
        <Stat
          label={tr(lang, 'k_active_rfqs')}
          value={hasRfqs ? s.open : undefined}
          empty={tr(lang, 'not_from_rfqs')}
          hint={`${s.awarded} / ${s.rfqCount} ${tr(lang, 'k_awarded').toLowerCase()}`}
        />
        <Stat
          label={tr(lang, 'k_categories')}
          value={s.categories.length > 0 ? s.categories.length : undefined}
          empty={hasRfqs ? tr(lang, 'no_categories_yet') : tr(lang, 'not_from_rfqs')}
          hint={tr(lang, 'categories_note')}
        />
        <Stat
          label={tr(lang, 'k_suppliers')}
          value={s.awardedSupplierCount > 0 ? s.awardedSupplierCount : undefined}
          empty={hasRfqs ? tr(lang, 'no_suppliers_yet') : tr(lang, 'not_from_rfqs')}
          hint={tr(lang, 'suppliers_note')}
        />
        <Stat
          label={tr(lang, 'k_timeline')}
          value={elapsed !== null ? `${elapsed}%` : undefined}
          empty={tr(lang, 'no_target_date')}
          hint={tr(lang, 'elapsed_note')}
        />
      </div>

      {elapsed !== null ? (
        <Progress value={elapsed} aria-label={tr(lang, 'k_timeline')} />
      ) : null}

      {s.categories.length > 0 ? (
        <div>
          <h3 className="text-[13px] font-bold text-foreground">{tr(lang, 'k_categories')}</h3>
          <ul className="mt-2 flex list-none flex-wrap gap-2 p-0">
            {s.categories.map((c) => (
              <li key={c}>
                <Badge variant="secondary">{c}</Badge>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h3 className="text-[15px] font-bold text-foreground">
            {tr(lang, 'linked_rfqs')} {hasRfqs ? `(${s.rfqCount})` : ''}
          </h3>
        </div>

        {hasRfqs ? (
          <div className="mt-2.5 overflow-x-auto rounded-lg border border-border">
            <Table>
              <TableCaption className="sr-only">{tr(lang, 'rfq_table_caption')}</TableCaption>
              <TableHeader>
                <TableRow>
                  <TableHead scope="col">{tr(lang, 'th_rfq')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_category')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_emirate')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_value')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_status')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_created')}</TableHead>
                  <TableHead scope="col">{tr(lang, 'th_actions')}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rfqs.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="max-w-[280px]">
                      <span className="block truncate text-foreground">{r.summary || tr(lang, 'untitled_rfq')}</span>
                    </TableCell>
                    <TableCell>{r.category || '—'}</TableCell>
                    <TableCell>{r.emirate || '—'}</TableCell>
                    <TableCell>{rfqValue(r) != null ? aed(rfqValue(r)) : '—'}</TableCell>
                    <TableCell>
                      <span className="flex flex-wrap items-center gap-1.5">
                        <Badge variant={isOpenRfq(r) ? 'default' : 'secondary'}>{r.status || '—'}</Badge>
                        {r.hired_supplier_id ? <Badge variant="ok">{tr(lang, 'awarded_badge')}</Badge> : null}
                      </span>
                    </TableCell>
                    <TableCell className="whitespace-nowrap">{fmtDate(r.created_at, lang)}</TableCell>
                    <TableCell>
                      <span className="flex flex-wrap gap-1.5">
                        {onOpenRfq ? (
                          <Button type="button" size="sm" variant="ghost" onClick={() => onOpenRfq(r.id)}>
                            {tr(lang, 'open_rfq')}
                          </Button>
                        ) : null}
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          disabled={busyId === r.id}
                          onClick={() => mutate('unlink', r.id)}
                        >
                          {busyId === r.id ? tr(lang, 'unlinking') : tr(lang, 'unlink')}
                        </Button>
                      </span>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        ) : (
          // Zero linked RFQs. Say that, and say that it is why the figures above are blank — this is
          // the exact place a portal is tempted to imply progress that never happened.
          <div className="mt-2.5 rounded-lg border border-dashed border-border bg-white/[0.02] px-5 py-7 text-center">
            <h4 className="text-[14px] font-bold text-foreground">{tr(lang, 'no_rfqs_title')}</h4>
            <p className="mx-auto mt-2 max-w-[54ch] text-[13px] leading-relaxed text-muted-foreground">{tr(lang, 'no_rfqs_body')}</p>
          </div>
        )}
      </div>

      <LinkPicker
        lang={lang}
        candidates={(linkableRfqs || []).filter((c) => !rfqs.some((r) => r.id === c.id))}
        show={Array.isArray(linkableRfqs)}
        busy={Boolean(busyId)}
        onLink={(id) => mutate('link', id)}
      />
    </section>
  );
}

function LinkPicker({
  lang, candidates, show, busy, onLink,
}: {
  lang: Lang;
  candidates: LinkableRfq[];
  show: boolean;
  busy: boolean;
  onLink: (id: string) => void;
}) {
  const [choice, setChoice] = React.useState('');
  const selectId = React.useId();
  if (!show) return null;
  return (
    <div className="rounded-lg border border-border bg-white/[0.03] p-4">
      <h3 className="text-[13px] font-bold text-foreground">{tr(lang, 'link_rfq')}</h3>
      {candidates.length === 0 ? (
        <p className="mt-1.5 text-[13px] text-muted-foreground">{tr(lang, 'no_linkable')}</p>
      ) : (
        <div className="mt-2 flex flex-wrap items-end gap-2.5">
          <div className="min-w-[240px] flex-1">
            <label className="text-[12px] font-semibold text-muted-foreground" htmlFor={selectId}>
              {tr(lang, 'choose_rfq')}
            </label>
            <select
              id={selectId}
              value={choice}
              onChange={(e) => setChoice(e.target.value)}
              className="mt-1.5 h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="" className="bg-background text-foreground">
                —
              </option>
              {candidates.map((c) => (
                <option key={c.id} value={c.id} className="bg-background text-foreground">
                  {(c.summary || tr(lang, 'untitled_rfq')).slice(0, 70)}
                  {c.category ? ` · ${c.category}` : ''}
                </option>
              ))}
            </select>
          </div>
          <Button type="button" disabled={!choice || busy} onClick={() => onLink(choice)}>
            {busy ? tr(lang, 'linking') : tr(lang, 'link')}
          </Button>
        </div>
      )}
    </div>
  );
}
