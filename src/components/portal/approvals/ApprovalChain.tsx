'use client';
/**
 * APPROVALS — customer portal spec §12 (Purchase Approval System) and the §22 "Approvals" module.
 *
 * The spec's own example is the shape this renders:
 *   Purchase Request → Engineer ✓ Approved → Project Manager ✓ Approved → Finance Pending → CEO Waiting
 *
 * WHERE EVERY VALUE COMES FROM. supabase/functions/procurement_api, customer-authed:
 *   action:'approvals' → fn_approval_list(customer) → { organizations[], policies[], requests[] }
 *                        each request carries steps[] already projected by public.v_approval_trace,
 *                        one row per NAMED policy step with step_status
 *                        approved / rejected / pending / waiting / blocked.
 *   action:'decide'    → fn_approval_decide(request, actor, decision, note). The membership and
 *                        role guard lives IN that routine, so this surface never decides who may
 *                        act — it only offers the control on the step the chain is actually on and
 *                        renders whatever the database answers.
 *
 * NOTHING IS DERIVED. The step states are the view's; the step names are the policy's. This file
 * computes exactly two things — how many steps are approved, and whether a decide control belongs
 * on a step — and both are in ./model where model.test.mjs executes them.
 *
 * WHAT A CUSTOMER SEES TODAY. Production holds zero customer organizations and zero policies, so
 * this renders one of three DIFFERENT sentences: no organisation, no policy, or no purchase has
 * needed approval yet. They are different facts and the customer is told which is true. None of
 * them implies that anything was routed, reviewed or approved on their behalf.
 */
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { call } from './api';
import {
  canDecide,
  chainProgress,
  fmtDate,
  numOrNull,
  type ApprovalPolicy,
  type ApprovalRequest,
  type ApprovalStep,
  type ApprovalsPayload,
  type Lang,
} from './model';
import { errText, stepLabel, tr } from './strings';

/* ── pieces ───────────────────────────────────────────────────────────────────────────────── */

function Empty({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-lg border border-dashed border-border bg-white/[0.02] px-5 py-8 text-center">
      <h3 className="text-[15px] font-bold text-foreground">{title}</h3>
      <p className="mx-auto mt-2 max-w-[62ch] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

const TONE: Record<string, 'ok' | 'destructive' | 'warn' | 'secondary'> = {
  approved: 'ok',
  rejected: 'destructive',
  pending: 'warn',
  waiting: 'secondary',
  blocked: 'secondary',
};

/** One named step of the chain, with its own state and — when it is the live step — its control. */
function StepRow({
  step,
  lang,
  actable,
  busy,
  onDecide,
}: {
  step: ApprovalStep;
  lang: Lang;
  actable: boolean;
  busy: boolean;
  onDecide?: (decision: 'approved' | 'rejected', note: string) => void;
}) {
  const [note, setNote] = React.useState('');
  const live = step.status === 'pending';

  return (
    <li
      className={cn(
        'rounded-lg border px-3.5 py-3 transition-colors',
        live ? 'border-accent/40 bg-accent/[0.06]' : 'border-border bg-white/[0.02]',
        step.status === 'waiting' || step.status === 'blocked' ? 'opacity-70' : null,
      )}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-baseline gap-2">
          <span className="text-[11px] font-bold tabular-nums text-muted-foreground">{step.step}</span>
          <span className="text-[13.5px] font-bold text-foreground">{step.label}</span>
          {step.role ? <span className="text-[11.5px] text-muted-foreground">({step.role})</span> : null}
        </div>
        <Badge variant={TONE[step.status] ?? 'secondary'}>{stepLabel(lang, step.status)}</Badge>
      </div>

      {step.decided_at ? (
        <p className="mt-1 text-[11.5px] text-muted-foreground">
          {tr(lang, 'decided_at')} {fmtDate(step.decided_at, lang)}
          {step.note ? ` — ${step.note}` : ''}
        </p>
      ) : null}

      {live && onDecide ? (
        actable ? (
          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <Input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder={tr(lang, 'decide_note_ph')}
              aria-label={tr(lang, 'decide_note_ph')}
              className="h-8 max-w-[280px] flex-1 text-[12.5px]"
            />
            <Button type="button" size="sm" disabled={busy} onClick={() => onDecide('approved', note)}>
              {busy ? tr(lang, 'decide_busy') : tr(lang, 'decide_approve')}
            </Button>
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => {
                if (typeof window !== 'undefined' && !window.confirm(tr(lang, 'decide_confirm_reject'))) return;
                onDecide('rejected', note);
              }}
            >
              {tr(lang, 'decide_reject')}
            </Button>
          </div>
        ) : (
          <p className="mt-2 text-[11.5px] text-muted-foreground">{tr(lang, 'decide_not_yours')}</p>
        )
      ) : null}
    </li>
  );
}

/** A configured chain that nothing has run through yet — the policy itself, named step by step. */
function PolicyCard({ policy, lang }: { policy: ApprovalPolicy; lang: Lang }) {
  const steps = Array.isArray(policy.steps) ? policy.steps : [];
  const cond = (policy.conditions || {}) as Record<string, unknown>;
  const min = numOrNull(cond.min_amount);
  const cats = Array.isArray(cond.categories) ? (cond.categories as string[]) : null;
  const emirates = Array.isArray(cond.emirates) ? (cond.emirates as string[]) : null;
  const rules = [
    min !== null ? `≥ AED ${min.toLocaleString('en-AE')}` : null,
    cats?.length ? cats.join(', ') : null,
    emirates?.length ? emirates.join(', ') : null,
  ].filter(Boolean) as string[];

  return (
    <Card className="p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-[14px] font-bold text-foreground">{policy.name || policy.id}</h4>
        {policy.active === false ? <Badge variant="secondary">{tr(lang, 'policy_inactive')}</Badge> : null}
      </div>
      <p className="mt-1 text-[12px] text-muted-foreground">
        {rules.length ? `${tr(lang, 'policy_threshold')}: ${rules.join(' · ')}` : tr(lang, 'policy_no_conditions')}
      </p>
      {steps.length ? (
        <ol className="mt-2.5 flex list-none flex-wrap gap-1.5 p-0">
          {steps.map((s, i) => (
            <li key={`${policy.id}:${i}`} className="rounded-md border border-border bg-white/[0.03] px-2.5 py-1 text-[12px] text-foreground">
              <span className="tabular-nums text-muted-foreground">{i + 1}. </span>
              {s.label || s.key || `Step ${i + 1}`}
              {s.role ? <span className="text-muted-foreground"> · {s.role}</span> : null}
            </li>
          ))}
        </ol>
      ) : (
        <p className="mt-2 text-[12px] text-muted-foreground">{tr(lang, 'policy_no_steps')}</p>
      )}
    </Card>
  );
}

/* ── the surface the integrator mounts ────────────────────────────────────────────────────── */

export interface ApprovalChainProps {
  /** Customer Supabase JWT — the token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Called with inquiries.id when a request's awarded RFQ is opened. Omit to hide the control. */
  onOpenRfq?: (inquiryId: string) => void;
  className?: string;
}

export function ApprovalChain({ token, lang = 'en', onOpenRfq, className }: ApprovalChainProps) {
  const [data, setData] = React.useState<ApprovalsPayload | null>(null);
  // TWO ERRORS, KEPT APART ON PURPOSE. A failed LOAD means the chain below cannot be trusted, so
  // nothing is drawn under it. A failed DECISION means the chain is still exactly what was fetched
  // and the customer needs to keep looking at it — blanking the surface they just acted on would
  // lose the state they were reading.
  const [error, setError] = React.useState('');
  const [actionError, setActionError] = React.useState('');
  const [deciding, setDeciding] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    let live = true;
    setData(null);
    setError('');
    setActionError('');
    call('procurement_api', { action: 'approvals' }, token).then((res) => {
      if (!live) return;
      if (!res.ok) {
        setError(errText(lang, res.error));
        setData({ organizations: [], policies: [], requests: [] });
        return;
      }
      // The one cast, at the wire boundary. ./model is the transcription of what fn_approval_list
      // actually emits; nothing below re-derives a field it does not serve.
      const payload = res.data as unknown as ApprovalsPayload;
      setData({
        organizations: payload.organizations || [],
        policies: payload.policies || [],
        requests: payload.requests || [],
      });
    });
    return () => {
      live = false;
    };
  }, [token, lang, reloads]);

  const decide = async (request: ApprovalRequest, decision: 'approved' | 'rejected', note: string) => {
    setDeciding(request.id);
    setActionError('');
    const res = await call('procurement_api', { action: 'decide', request_id: request.id, decision, note: note || null }, token);
    setDeciding('');
    if (!res.ok) {
      // fn_approval_decide refuses a non-member and a step whose policy names another role. Its
      // message is shown as it came — the customer is entitled to know which rule stopped them.
      setActionError(`${tr(lang, 'err_decide')} ${errText(lang, res.error)}`);
      return;
    }
    setReloads((n) => n + 1);
  };

  const requests = data?.requests ?? [];
  const policies = data?.policies ?? [];
  const orgs = data?.organizations ?? [];

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'} aria-labelledby="qd-approvals">
      <header>
        {/* ModuleWindow already renders "Approvals" as the h1. See the note in OrdersList. */}
        <p id="qd-approvals" className="text-[13px] text-muted-foreground">{tr(lang, 'approvals_sub')}</p>
      </header>

      {error ? (
        <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-3.5 py-2.5 text-[13px] text-destructive">
          <span className="font-semibold">
            {tr(lang, 'err_load')} {error}
          </span>
          <Button type="button" size="sm" variant="outline" onClick={() => setReloads((n) => n + 1)}>
            {tr(lang, 'retry')}
          </Button>
        </div>
      ) : null}

      {actionError ? (
        <div role="alert" className="rounded-lg border border-destructive/40 bg-destructive/10 px-3.5 py-2.5 text-[13px] font-semibold text-destructive">
          {actionError}
        </div>
      ) : null}

      {/* THE `error ? null` ARM IS LOAD-BEARING. Without it a failed load falls through to
          "No purchase has needed approval yet" — an empty state printed over a failure, which is
          the one defect class this portal has already shipped once. A failure shows the alert
          above and nothing else. */}
      {data === null ? (
        <>
          <p className="sr-only" role="status">
            {tr(lang, 'loading_approvals')}
          </p>
          <Skeleton className="h-[168px] w-full rounded-lg" aria-hidden="true" />
        </>
      ) : error ? null : orgs.length === 0 ? (
        <Empty title={tr(lang, 'empty_no_org_title')} body={tr(lang, 'empty_no_org_body')} />
      ) : policies.length === 0 && requests.length === 0 ? (
        <Empty title={tr(lang, 'empty_no_policy_title')} body={tr(lang, 'empty_no_policy_body')} />
      ) : (
        <>
          {requests.length === 0 ? (
            <Empty title={tr(lang, 'empty_no_requests_title')} body={tr(lang, 'empty_no_requests_body')} />
          ) : (
            <ul className="flex list-none flex-col gap-3 p-0">
              {requests.map((r) => {
                const prog = chainProgress(r.steps);
                return (
                  <li key={r.id}>
                    <Card className="p-4">
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div>
                          <h3 className="text-[15px] font-bold text-foreground">{tr(lang, 'req_title')}</h3>
                          <p className="mt-0.5 text-[12px] text-muted-foreground">
                            {tr(lang, 'req_for')} {fmtDate(r.created_at, lang)} ·{' '}
                            {tr(lang, 'req_step_of')(r.current_step, prog.total)} ·{' '}
                            {tr(lang, 'req_progress')(prog.approved, prog.total)}
                          </p>
                        </div>
                        <Badge variant={TONE[r.status] ?? 'secondary'}>{stepLabel(lang, r.status)}</Badge>
                      </div>

                      <p className="mt-1.5 text-[12px] text-muted-foreground">
                        {r.status === 'approved'
                          ? tr(lang, 'req_finished')
                          : r.status === 'rejected'
                            ? tr(lang, 'req_stopped')
                            : prog.pending
                              ? `${tr(lang, 'req_waiting_on')}: ${prog.pending.label}`
                              : ''}
                      </p>

                      {onOpenRfq && r.entity_type === 'inquiry' && r.entity_id ? (
                        <Button
                          type="button"
                          size="sm"
                          variant="outline"
                          className="mt-2"
                          onClick={() => onOpenRfq(String(r.entity_id))}
                        >
                          {tr(lang, 'open_rfq')}
                        </Button>
                      ) : null}

                      <ol className="mt-3 flex list-none flex-col gap-2 p-0">
                        {(r.steps || []).map((s) => (
                          <StepRow
                            key={`${r.id}:${s.step}`}
                            step={s}
                            lang={lang}
                            actable={canDecide(r, s)}
                            busy={deciding === r.id}
                            onDecide={(decision, note) => void decide(r, decision, note)}
                          />
                        ))}
                      </ol>
                    </Card>
                  </li>
                );
              })}
            </ul>
          )}

          {policies.length ? (
            <div className="flex flex-col gap-2.5">
              <div>
                <h3 className="text-[15px] font-bold text-foreground">{tr(lang, 'policies_title')}</h3>
                <p className="mt-0.5 text-[12px] text-muted-foreground">{tr(lang, 'policies_note')}</p>
              </div>
              {policies.map((p) => (
                <PolicyCard key={p.id} policy={p} lang={lang} />
              ))}
            </div>
          ) : null}
        </>
      )}
    </section>
  );
}

export default ApprovalChain;
