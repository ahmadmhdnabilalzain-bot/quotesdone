'use client';
// Create or edit a project — project_api action:'create' and action:'update'.
//
// The fields are exactly the four the API writes (name, description, target_open_date,
// budget_total) plus status, which action:'update' accepts and action:'create' does not. Limits
// mirror the server's own (name 160, description 4000) so the customer is told before the server
// silently truncates. Date entry is the native <input type="date"> — it already produces the
// YYYY-MM-DD the API's regex demands.
import * as React from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { projectApi } from './api';
import { PROJECT_STATUSES, type Lang, type Project } from './model';
import { Notice } from './parts';
import { errText, statusLabel, tr } from './strings';
import { BUDGET_MAX_AED, parseBudget } from '../../../../supabase/functions/_shared/project_budget';

export interface ProjectFormProps {
  /** Customer Supabase JWT. */
  token: string;
  lang?: Lang;
  /** Omit (or null) to create a new project. Pass a project row to edit that project. */
  project?: Project | null;
  /**
   * Fired after a successful save. On create the new public.projects row is passed (note it carries
   * `id`, not the list view's `project_id`). On update the API returns only { ok: true }, so the
   * locally-updated row is passed instead — refetch if you need server truth.
   */
  onSaved?: (project: Project) => void;
  onCancel?: () => void;
  className?: string;
}

const num = (v: number | null | undefined): string => (v === null || v === undefined ? '' : String(v));

export function ProjectForm({ token, lang = 'en', project = null, onSaved, onCancel, className }: ProjectFormProps) {
  const editing = Boolean(project);
  const [name, setName] = React.useState(project?.name ?? '');
  const [description, setDescription] = React.useState(project?.description ?? '');
  const [targetDate, setTargetDate] = React.useState(project?.target_open_date ?? '');
  const [budget, setBudget] = React.useState(num(project?.budget_total));
  const [status, setStatus] = React.useState(project?.status ?? 'active');
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState('');
  const nameId = React.useId();
  const descId = React.useId();
  const dateId = React.useId();
  const budgetId = React.useId();
  const statusId = React.useId();

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError(tr(lang, 'f_name_required'));
      return;
    }
    // The server's own rule (project_api refuses the same input): said here so the customer is told
    // before a round trip. min/max on the input alone were never a bound — typed text and pasted
    // negatives went straight through (audit 21 Sep 2026).
    const checked = parseBudget(budget);
    if (!checked.ok) {
      setError(lang === 'ar' ? checked.ar : checked.en);
      return;
    }
    setBusy(true);
    setError('');
    const shared = {
      name: trimmed.slice(0, 160),
      description: description.slice(0, 4000),
      target_open_date: targetDate,
      budget_total: budget.trim(),
    };

    if (editing && project) {
      const res = await projectApi<Record<string, never>>(token, { action: 'update', id: project.id, ...shared, status });
      setBusy(false);
      if (!res.ok) {
        setError(errText(lang, res.error));
        return;
      }
      onSaved?.({
        ...project,
        name: shared.name,
        description: shared.description || null,
        status,
        target_open_date: /^\d{4}-\d{2}-\d{2}$/.test(targetDate) ? targetDate : null,
        budget_total: checked.value,
      });
      return;
    }

    const res = await projectApi<{ project: Project }>(token, { action: 'create', ...shared });
    setBusy(false);
    if (!res.ok) {
      setError(errText(lang, res.error));
      return;
    }
    if (!res.data.project) {
      setError(tr(lang, 'err_save'));
      return;
    }
    onSaved?.(res.data.project);
  }

  const field = 'mt-1.5 h-[42px] w-full';
  const labelCls = 'text-[13px] font-semibold text-foreground';

  return (
    <form
      onSubmit={submit}
      dir={lang === 'ar' ? 'rtl' : 'ltr'}
      className={cn('flex flex-col gap-4 rounded-lg border border-border bg-card p-5 shadow-xs', className)}
    >
      <h2 className="text-[17px] font-extrabold text-foreground">{tr(lang, editing ? 'edit_project' : 'create_project')}</h2>

      <div>
        <label className={labelCls} htmlFor={nameId}>
          {tr(lang, 'f_name')}
        </label>
        <Input
          id={nameId}
          className={field}
          value={name}
          maxLength={160}
          required
          autoComplete="off"
          placeholder={tr(lang, 'f_name_ph')}
          onChange={(e) => setName(e.target.value)}
        />
      </div>

      <div>
        <label className={labelCls} htmlFor={descId}>
          {tr(lang, 'f_description')}
        </label>
        <textarea
          id={descId}
          rows={4}
          maxLength={4000}
          value={description}
          placeholder={tr(lang, 'f_description_ph')}
          onChange={(e) => setDescription(e.target.value)}
          className="mt-1.5 w-full resize-y rounded-md border border-input bg-transparent px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring"
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={labelCls} htmlFor={dateId}>
            {tr(lang, 'f_target')}
          </label>
          <Input id={dateId} className={field} type="date" value={targetDate} onChange={(e) => setTargetDate(e.target.value)} />
        </div>
        <div>
          <label className={labelCls} htmlFor={budgetId}>
            {tr(lang, 'f_budget')}
          </label>
          <Input
            id={budgetId}
            className={field}
            type="number"
            inputMode="decimal"
            min={0.01}
            max={BUDGET_MAX_AED}
            step="0.01"
            value={budget}
            onChange={(e) => setBudget(e.target.value)}
          />
        </div>
      </div>

      {editing ? (
        <div>
          <label className={labelCls} htmlFor={statusId}>
            {tr(lang, 'f_status')}
          </label>
          <select
            id={statusId}
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            className="mt-1.5 h-[42px] w-full rounded-md border border-input bg-transparent px-3 text-sm text-foreground focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring"
          >
            {PROJECT_STATUSES.map((s) => (
              <option key={s} value={s} className="bg-background text-foreground">
                {statusLabel(lang, s)}
              </option>
            ))}
          </select>
        </div>
      ) : null}

      {error ? <Notice tone="error">{error}</Notice> : null}

      <div className="flex flex-wrap gap-2.5">
        <Button type="submit" disabled={busy}>
          {busy ? tr(lang, 'saving') : tr(lang, editing ? 'save_changes' : 'create_project')}
        </Button>
        {onCancel ? (
          <Button type="button" variant="outline" onClick={onCancel} disabled={busy}>
            {tr(lang, 'cancel')}
          </Button>
        ) : null}
      </div>
    </form>
  );
}
