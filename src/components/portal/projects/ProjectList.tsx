'use client';
// The customer's projects, from project_api action:'list' (public.project_summary).
//
// Nothing here is derived or guessed: every figure on a card is a column of that view. The one
// computed value, budget commitment, is pipeline_value / budget_total and is only drawn when
// budget_total is actually set.
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { projectApi } from './api';
import { aed, fmtDate, type Lang, type ProjectSummary } from './model';
import { Bar, ListSkeleton, Notice } from './parts';
import { errText, statusLabel, tr } from './strings';

export interface ProjectListProps {
  /** Customer Supabase JWT — the same token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Called with project_summary.project_id when a card is activated. */
  onOpen?: (projectId: string) => void;
  /** Shows the "New project" button when provided. */
  onCreate?: () => void;
  /** Change this value to force a refetch (e.g. after a create or an edit elsewhere). */
  refreshKey?: number;
  className?: string;
}

export function ProjectList({ token, lang = 'en', onOpen, onCreate, refreshKey = 0, className }: ProjectListProps) {
  const [projects, setProjects] = React.useState<ProjectSummary[] | null>(null);
  const [error, setError] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    let live = true;
    setProjects(null);
    setError('');
    projectApi<{ projects: ProjectSummary[] }>(token, { action: 'list' }).then((res) => {
      if (!live) return;
      if (!res.ok) {
        setError(errText(lang, res.error));
        setProjects([]);
        return;
      }
      setProjects(Array.isArray(res.data.projects) ? res.data.projects : []);
    });
    return () => {
      live = false;
    };
  }, [token, lang, refreshKey, reloads]);

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          {/* ModuleWindow already renders "Projects" as the h1. See the note in OrdersList. */}
          <p className="text-[13px] text-muted-foreground">{tr(lang, 'projects_sub')}</p>
        </div>
        {onCreate ? (
          <Button type="button" onClick={onCreate}>
            {tr(lang, 'new_project')}
          </Button>
        ) : null}
      </header>

      {error ? (
        <Notice
          tone="error"
          action={
            <Button type="button" size="sm" variant="outline" onClick={() => setReloads((n) => n + 1)}>
              {tr(lang, 'retry')}
            </Button>
          }
        >
          {tr(lang, 'err_load')} {error}
        </Notice>
      ) : null}

      {projects === null ? (
        <>
          <p className="sr-only" role="status">
            {tr(lang, 'loading_projects')}
          </p>
          <ListSkeleton />
        </>
      ) : projects.length === 0 && !error ? (
        // PRODUCTION HAS ZERO PROJECTS. This says exactly that and what a project is for. It must
        // never imply that anything has been organised, matched or started on the customer's behalf.
        <div className="rounded-lg border border-dashed border-border bg-white/2 px-5 py-8 text-center">
          <h3 className="text-[15px] font-bold text-foreground">{tr(lang, 'empty_title')}</h3>
          <p className="mx-auto mt-2 max-w-[52ch] text-[13px] leading-relaxed text-muted-foreground">{tr(lang, 'empty_body')}</p>
          {onCreate ? (
            <Button type="button" className="mt-4" onClick={onCreate}>
              {tr(lang, 'create_project')}
            </Button>
          ) : null}
        </div>
      ) : (
        <ul className="grid list-none gap-3 p-0 sm:grid-cols-2">
          {projects.map((p) => (
            <li key={p.project_id}>
              <ProjectCard project={p} lang={lang} onOpen={onOpen} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function ProjectCard({ project: p, lang, onOpen }: { project: ProjectSummary; lang: Lang; onOpen?: (id: string) => void }) {
  const budget = Number(p.budget_total) || 0;
  const pipeline = Number(p.pipeline_value) || 0;
  const rfqCount = Number(p.rfq_count) || 0;
  const committedPct = budget > 0 ? Math.round((pipeline / budget) * 100) : null;

  const body = (
    <>
      <div className="flex items-start justify-between gap-3">
        <h3 className="text-[15px] font-bold leading-snug text-foreground">{p.name}</h3>
        <Badge variant={p.status === 'completed' ? 'ok' : p.status === 'archived' ? 'secondary' : 'default'}>
          {statusLabel(lang, p.status)}
        </Badge>
      </div>

      <p className="mt-1 text-[12px] text-muted-foreground">
        {p.target_open_date
          ? `${tr(lang, 'target_date')}: ${fmtDate(p.target_open_date, lang)}`
          : tr(lang, 'no_target_date')}
      </p>

      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-[13px]">
        <div>
          <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{tr(lang, 'k_active_rfqs')}</dt>
          <dd className="font-bold text-foreground">
            {rfqCount === 0 ? <span className="font-medium text-muted-foreground">{tr(lang, 'not_from_rfqs')}</span> : Number(p.rfq_open) || 0}
          </dd>
        </div>
        <div>
          <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{tr(lang, 'k_awarded')}</dt>
          <dd className="font-bold text-foreground">
            {rfqCount === 0 ? <span className="font-medium text-muted-foreground">—</span> : `${Number(p.rfq_awarded) || 0} / ${rfqCount}`}
          </dd>
        </div>
        <div>
          <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{tr(lang, 'k_budget')}</dt>
          <dd className="font-bold text-foreground">
            {budget > 0 ? aed(budget) : <span className="font-medium text-muted-foreground">{tr(lang, 'budget_not_set')}</span>}
          </dd>
        </div>
        <div>
          <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{tr(lang, 'k_pipeline')}</dt>
          <dd className="font-bold text-foreground">
            {rfqCount === 0 ? <span className="font-medium text-muted-foreground">—</span> : aed(pipeline)}
          </dd>
        </div>
      </dl>

      {committedPct !== null && rfqCount > 0 ? (
        <div className="mt-3">
          <Bar pct={committedPct} />
          <p className={cn('mt-1.5 text-[11px]', committedPct > 100 ? 'text-destructive' : 'text-muted-foreground')}>
            {committedPct > 100
              ? `${committedPct - 100}% ${tr(lang, 'budget_over')}`
              : `${committedPct}% ${tr(lang, 'budget_used')}`}
          </p>
        </div>
      ) : null}
    </>
  );

  const shell = 'rounded-lg border border-border bg-card p-5 shadow-xs h-full';

  if (!onOpen) return <div className={shell}>{body}</div>;
  return (
    <button
      type="button"
      onClick={() => onOpen(p.project_id)}
      className={cn(
        shell,
        'w-full cursor-pointer text-start transition-colors hover:border-primary/45 hover:bg-white/5',
        'focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
      )}
    >
      {body}
    </button>
  );
}
