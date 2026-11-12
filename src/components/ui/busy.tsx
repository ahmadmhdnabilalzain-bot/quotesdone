'use client';
// ══════════════════════════════════════════════════════════════════════════════════════════
// THE ONE LOADING SYSTEM. Founder instruction, 18 Sep 2026:
//   "wherever you go, wherever you press, when things are loading, there's no sort of an
//    animation that says it's loading… this should be everywhere."
//
// Scattered spinners were NOT the answer: ~140 call sites already had a hand-rolled `busy`
// boolean, each with its own timing (i.e. none), and ~20 had nothing at all. This file is the
// single place the timing rules live, so a call site only has to say WHAT it is doing.
//
// THE FOUR RULES (docs/CONVENTIONS_LOADING.md is the standing convention):
//   1. SHOW_AFTER 150ms  — below that, nothing. A 40ms round trip must not flash a spinner.
//   2. MIN_SHOW  300ms   — once shown, it stays. A 160ms round trip must not strobe.
//   3. Re-triggering is blocked from the FIRST millisecond (`pending`), not from the moment the
//      spinner appears — the double-submit window is the 150ms before it shows.
//   4. A failure RESOLVES the indicator into an error. A spinner that never ends cannot tell
//      "broken" from "idle", which is the failure mode this company already has a lens for.
//
// Accessibility: aria-busy on the control/region, aria-live="polite" on the status text, and the
// ring is static (not absent) under prefers-reduced-motion — see .qd-spin in globals.css.
// RTL: nothing here rotates by direction; the progress bar grows from inset-inline-start, so it
// fills right-to-left in Arabic on its own.
// ══════════════════════════════════════════════════════════════════════════════════════════
import * as React from 'react';
import { cn } from '@/lib/utils';
import { Button, type ButtonProps } from '@/components/ui/button';
import { SHOW_AFTER_MS, MIN_SHOW_MS } from '@/components/ui/busy-timing';

export { SHOW_AFTER_MS, MIN_SHOW_MS };

// A promise that NEVER SETTLES is not covered by rule 4 — `catch` only sees rejection. A dropped
// connection or a backend that hangs would leave the button disabled and spinning for the rest of
// the session, which is precisely the state this whole file exists to make impossible. None of the
// repo's `call()` / `publicSite()` helpers carries an AbortController today, so the ceiling lives
// here. 30s is well past any real round trip and well short of "forever".
export const RUN_CEILING_MS = 30000;

/** The ring. Sized in `em` so it matches whatever text it sits beside. */
export function Spinner({ className, ...rest }: React.HTMLAttributes<HTMLSpanElement>) {
  return <span aria-hidden className={cn('qd-spin', className)} {...rest} />;
}

export type BusyState<K extends string = string> = {
  /** True from the first millisecond. Use for `disabled` — this is the double-press guard. */
  pending: boolean;
  /** True only after SHOW_AFTER_MS, and then for at least MIN_SHOW_MS. Use for the spinner. */
  busy: boolean;
  /** Which keyed action is running (`run('save', …)`), or null. */
  key: K | null;
  /** The last failure, resolved out of the spinner. Cleared when a new run starts. */
  error: string | null;
  setError: (m: string | null) => void;
  /** Runs `fn` under the rules. Returns undefined (and does NOT run) if something is pending. */
  run: <T>(key: K, fn: () => Promise<T>) => Promise<T | undefined>;
};

/**
 * The hook every non-instant action goes through.
 *
 *   const b = useBusy<'save' | 'del'>();
 *   <BusyButton busy={b} act="save" busyLabel={t(lang, 'saving')}
 *               onClick={() => b.run('save', () => api('save_x'))}>{t(lang, 'save')}</BusyButton>
 *
 * Always pass `busyLabel` (or `busyStatus`): it is what a screen reader hears — the ring itself is
 * aria-hidden. Copy this example, not a shorter one.
 *
 * `run` rejects nothing to the caller: it captures the error into `b.error` and returns undefined,
 * so a call site cannot accidentally leave the indicator spinning by forgetting a catch.
 */
export function useBusy<K extends string = string>(): BusyState<K> {
  const [pending, setPending] = React.useState(false);
  const [busy, setBusy] = React.useState(false);
  const [key, setKey] = React.useState<K | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const timers = React.useRef<ReturnType<typeof setTimeout>[]>([]);
  const shownAt = React.useRef(0);
  const alive = React.useRef(true);
  const running = React.useRef(false);

  React.useEffect(() => {
    alive.current = true;
    const list = timers.current;
    return () => { alive.current = false; list.forEach(clearTimeout); };
  }, []);

  // `running` is a ref, not `pending`, on purpose: two clicks inside the same React batch both see
  // the OLD `pending` value, so a state-only guard lets the second one through. The ref flips
  // synchronously and closes that window — which is the exact window rule 3 exists for.
  const run = React.useCallback(async <T,>(k: K, fn: () => Promise<T>): Promise<T | undefined> => {
    if (running.current) return undefined;            // rule 3 — one action at a time, from ms 0
    running.current = true;
    setPending(true); setKey(k); setError(null);
    shownAt.current = 0;
    const show = setTimeout(() => {                   // rule 1
      if (!alive.current) return;
      shownAt.current = Date.now();
      setBusy(true);
    }, SHOW_AFTER_MS);
    timers.current.push(show);
    const settle = () => {
      clearTimeout(show);
      const held = shownAt.current ? Math.max(0, MIN_SHOW_MS - (Date.now() - shownAt.current)) : 0;
      const done = () => {
        running.current = false;
        if (!alive.current) return;
        setBusy(false); setPending(false); setKey(null);
      };
      if (held) timers.current.push(setTimeout(done, held)); else done();   // rule 2
    };
    let ceiling: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_, rej) => {
      ceiling = setTimeout(() => rej(new Error('timeout')), RUN_CEILING_MS);
      timers.current.push(ceiling);
    });
    try {
      // rule 4, extended: a promise that never settles loses to the ceiling and becomes an error.
      const out = await Promise.race([fn(), timeout]);
      clearTimeout(ceiling!);
      settle();
      return out as T;
    } catch (e) {                                      // rule 4 — resolve into an error, never spin on
      clearTimeout(ceiling!);
      if (alive.current) setError(e instanceof Error ? e.message : String(e));
      settle();
      return undefined;
    }
  }, []);

  return { pending, busy, key, error, setError, run };
}

/**
 * Rules 1 and 2 applied to a boolean somebody else owns — React's `useTransition().isPending`, or
 * any of the ~140 hand-rolled `busy` flags already in this codebase.
 *
 *   const shown = useDelayedFlag(busy);   // true only after 150ms, then for at least 300ms
 *
 * This is the bridge that lets an existing call site get the timing without being rewritten: keep
 * `busy` for `disabled` (rule 3 wants the immediate value) and render the spinner off `shown`.
 */
export function useDelayedFlag(on: boolean, showAfter = SHOW_AFTER_MS, minShow = MIN_SHOW_MS): boolean {
  const [shown, setShown] = React.useState(false);
  const shownAt = React.useRef(0);
  React.useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    if (on) {
      timer = setTimeout(() => { shownAt.current = Date.now(); setShown(true); }, showAfter);
    } else if (shownAt.current) {
      const held = Math.max(0, minShow - (Date.now() - shownAt.current));
      timer = setTimeout(() => { shownAt.current = 0; setShown(false); }, held);
    } else {
      setShown(false);
    }
    return () => clearTimeout(timer);
  }, [on, showAfter, minShow]);
  return shown;
}

// Omit 'busy': Button's own boolean (ui/button.tsx, 12 Nov 2026) is what this component drives, under another name.
export interface BusyButtonProps<K extends string = string> extends Omit<ButtonProps, 'busy'> {
  /** The shared state from `useBusy()`. */
  busy: BusyState<K>;
  /** Which key of that state this button owns. Omit when the state has a single action. */
  act?: K;
  /** Shown in place of the children while working. Defaults to the children. */
  busyLabel?: React.ReactNode;
  /** Announced to screen readers while working. Defaults to `busyLabel`, then to "Working…". */
  busyStatus?: string;
}

/**
 * A button that cannot be pressed twice and says so.
 *
 * IT DOES NOT USE THE NATIVE `disabled` ATTRIBUTE while busy, and that is deliberate. `pending` is
 * set synchronously at ms 0, so a native `disabled` lands on the element the user is standing on:
 * the browser pulls it out of the accessibility tree and the tab order immediately, focus falls to
 * <body>, and the person who just pressed it hears nothing and loses their place. `aria-disabled`
 * plus `pointer-events-none` keeps focus exactly where it was, so the status below IS announced —
 * and `run()` already refuses a second call on its own ref, so a stray activation is harmless.
 * The caller's own `disabled` (an empty field, an ineligible action) stays native: that state is
 * not something the user just caused, and it should leave the tab order.
 */
export function BusyButton<K extends string = string>(
  { busy, act, busyLabel, busyStatus, children, disabled, className, ...rest }: BusyButtonProps<K>,
) {
  const mine = act === undefined || busy.key === act;
  const isBusy = busy.busy && mine;
  const status = busyStatus ?? (typeof busyLabel === 'string' ? busyLabel : 'Working…');
  return (
    <Button
      {...rest}
      aria-busy={isBusy || undefined}
      aria-disabled={busy.pending || undefined}
      disabled={disabled}
      className={cn(busy.pending && 'pointer-events-none cursor-progress opacity-45', className)}
    >
      {isBusy ? <Spinner /> : null}
      {isBusy && busyLabel !== undefined ? busyLabel : children}
      {/* The ring is aria-hidden, so this is the only thing a screen reader can hear. It is
          unconditional — a BusyButton written without `busyLabel` must not be silently inaccessible. */}
      <span className="sr-only" aria-live="polite">{isBusy ? status : busy.error && mine ? busy.error : ''}</span>
    </Button>
  );
}

/**
 * A content area that is fetching. Renders `fallback` (redaction bars — the brand's loading state,
 * see .redact in globals.css) while `busy`, and resolves into `error` rather than an endless bar.
 */
export function BusyRegion(
  { busy, error, onRetry, retryLabel = 'Retry', busyStatus = 'Loading…', fallback, children, className, ...rest }:
  { busy: boolean; error?: string | null; onRetry?: () => void; retryLabel?: string; busyStatus?: string;
    fallback: React.ReactNode; children: React.ReactNode } & React.HTMLAttributes<HTMLDivElement>,
) {
  return (
    // aria-live is NOT on this container. Skeletons are aria-hidden, so a live region wrapped round
    // the content would announce nothing while loading and then read the WHOLE arriving subtree —
    // a card list or a table — in one unrequested dump. The short status node below is the live
    // region; it is always mounted, so the announcement actually fires when its text changes.
    <div aria-busy={busy || undefined} className={className} {...rest}>
      <span className="sr-only" role="status" aria-live="polite">{busy ? busyStatus : error || ''}</span>
      {error ? (
        <div className="text-small text-danger-fg">
          {error}
          {onRetry ? <button type="button" onClick={onRetry} className="ms-2 underline">{retryLabel}</button> : null}
        </div>
      ) : busy ? fallback : children}
    </div>
  );
}

/**
 * Inline "…is working" status. Screen readers hear it because of aria-live; sighted users see the
 * ring. Use beside a control whose own label must not change.
 */
export function BusyNote({ busy, children, className }: { busy: boolean; children: React.ReactNode; className?: string }) {
  return (
    <span aria-live="polite" className={cn('inline-flex items-center gap-2 text-small text-muted', className)}>
      {busy ? <><Spinner /><span>{children}</span></> : null}
    </span>
  );
}
