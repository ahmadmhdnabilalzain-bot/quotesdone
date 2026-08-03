'use client';
// ── CONTROL MODE UI (3 Aug 2026) ───────────────────────────────────────────────────────────────
// Phase 1.4 shipped the Control Mode gate in front of every mutating action in os_api, os_ops and
// refunds_api, and shipped no way to open one. The console had a wall of buttons that could only
// fail, and they failed as "Not authorized (admin only)" - which reads as "your account is wrong".
//
// Three parts, in order of how much they matter:
//
//   1. ControlModeProvider listens for the gate-refusal event that osClient now fires and opens
//      this panel AT THE MOMENT you needed it. You press Approve, it is refused, and the thing
//      that unblocks you appears - instead of an error you have to go and interpret.
//   2. ControlModeIndicator sits in the header. It is the answer to "can I change anything right
//      now", visible without clicking, with a live countdown - because a 15-minute session that
//      expires silently mid-task is its own trap.
//   3. ControlModePanel runs the two-step flow the API already implements: request a code to the
//      registered number, then id + nonce + code + a written reason.
//
// The reason box is not a formality. fn_control_mode_open stores it on the session and every
// action taken under that session is audited against it, so it is the sentence that will explain,
// later, why the change was made. The UI says so rather than labelling it "Reason".
import React from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from '@/components/ui/sheet';
import { ShieldCheck, Eye, Loader2, Phone, X } from 'lucide-react';
import {
  controlModeStatus, controlModeChallenge, controlModeOpen, controlModeClose,
  CONTROL_MODE_EVENT, CONTROL_MODE_CHANGED, type ControlModeStatus,
} from '@/lib/osClient';

type Ctx = {
  status: ControlModeStatus | null;
  refresh: () => void;
  openPanel: (why?: string) => void;
  inControl: boolean;
  secondsLeft: number;
};
const ControlModeCtx = React.createContext<Ctx | null>(null);
export function useControlMode() { return React.useContext(ControlModeCtx); }

function mmss(total: number) {
  const t = Math.max(0, Math.floor(total));
  return String(Math.floor(t / 60)).padStart(2, '0') + ':' + String(t % 60).padStart(2, '0');
}

export function ControlModeProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = React.useState<ControlModeStatus | null>(null);
  const [panel, setPanel] = React.useState(false);
  const [why, setWhy] = React.useState<string>('');
  const [secondsLeft, setSecondsLeft] = React.useState(0);

  const refresh = React.useCallback(() => {
    controlModeStatus()
      .then((s) => { setStatus(s); setSecondsLeft(Number(s?.seconds_remaining || 0)); })
      .catch(() => { /* an unreadable status is Observe Mode as far as the UI is concerned */ });
  }, []);

  React.useEffect(() => { refresh(); }, [refresh]);

  // Poll slowly as a safety net, and tick locally every second so the countdown is smooth without
  // a request per second.
  React.useEffect(() => {
    const poll = setInterval(refresh, 60000);
    const tick = setInterval(() => setSecondsLeft((s) => (s > 0 ? s - 1 : 0)), 1000);
    return () => { clearInterval(poll); clearInterval(tick); };
  }, [refresh]);

  // The session just ran out. Re-read once so the indicator flips to Observe rather than sitting
  // at 00:00 claiming Control.
  React.useEffect(() => {
    if (status?.mode === 'control' && secondsLeft === 0) refresh();
  }, [secondsLeft, status?.mode, refresh]);

  React.useEffect(() => {
    const onRequired = (e: Event) => {
      const d = (e as CustomEvent).detail || {};
      setWhy(d.action ? `“${d.action}” was refused: ${d.message || 'Control Mode is required.'}` : (d.message || ''));
      setPanel(true);
      refresh();
    };
    const onChanged = () => refresh();
    window.addEventListener(CONTROL_MODE_EVENT, onRequired);
    window.addEventListener(CONTROL_MODE_CHANGED, onChanged);
    return () => {
      window.removeEventListener(CONTROL_MODE_EVENT, onRequired);
      window.removeEventListener(CONTROL_MODE_CHANGED, onChanged);
    };
  }, [refresh]);

  const openPanel = React.useCallback((w?: string) => { setWhy(w || ''); setPanel(true); }, []);
  const inControl = status?.mode === 'control' && secondsLeft > 0;

  return (
    <ControlModeCtx.Provider value={{ status, refresh, openPanel, inControl, secondsLeft }}>
      {children}
      <ControlModePanel
        open={panel}
        why={why}
        status={status}
        secondsLeft={secondsLeft}
        onOpenChange={setPanel}
        onDone={refresh}
      />
    </ControlModeCtx.Provider>
  );
}

/** The header pill. Answers "can I change anything right now" without a click. */
export function ControlModeIndicator() {
  const cm = useControlMode();
  if (!cm) return null;
  const { inControl, secondsLeft, openPanel } = cm;
  const low = inControl && secondsLeft <= 120;
  return (
    <button
      onClick={() => openPanel()}
      title={inControl
        ? 'Control Mode is open. Click to see the reason on record, or to close it now.'
        : 'Observe Mode — everything is readable, nothing can be changed. Click to open Control Mode.'}
      className={
        'flex items-center gap-1.5 rounded-md border px-2 py-1 text-xs transition-colors ' +
        (inControl
          ? (low ? 'border-amber-500/60 bg-amber-500/10 text-amber-600 dark:text-amber-400'
                 : 'border-emerald-500/60 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400')
          : 'border-border bg-muted/40 text-muted-foreground hover:text-foreground')
      }
    >
      {inControl ? <ShieldCheck className='h-3.5 w-3.5' /> : <Eye className='h-3.5 w-3.5' />}
      <span className='hidden sm:inline'>{inControl ? 'Control' : 'Observe'}</span>
      {inControl ? <span className='font-mono tabular-nums'>{mmss(secondsLeft)}</span> : null}
    </button>
  );
}

function ControlModePanel({ open, why, status, secondsLeft, onOpenChange, onDone }: {
  open: boolean; why: string; status: ControlModeStatus | null; secondsLeft: number;
  onOpenChange: (v: boolean) => void; onDone: () => void;
}) {
  const [step, setStep] = React.useState<'idle' | 'sent'>('idle');
  const [busy, setBusy] = React.useState(false);
  const [err, setErr] = React.useState('');
  const [note, setNote] = React.useState('');
  const [reason, setReason] = React.useState('');
  const [code, setCode] = React.useState('');
  const [ch, setCh] = React.useState<{ challenge_id: string; nonce: string; phone_tail: string } | null>(null);
  const inControl = status?.mode === 'control' && secondsLeft > 0;

  React.useEffect(() => {
    if (!open) { setStep('idle'); setErr(''); setNote(''); setCode(''); setCh(null); }
  }, [open]);

  const sendCode = async () => {
    setBusy(true); setErr(''); setNote('');
    try {
      const d = await controlModeChallenge();
      setCh({ challenge_id: d.challenge_id, nonce: d.nonce, phone_tail: d.phone_tail });
      setStep('sent');
      setNote(d.message || `Code sent to the number ending ${d.phone_tail}.`);
      // A challenge that exists but was not delivered is the confusing case: the code is valid,
      // it just never arrived. Say that plainly instead of showing a success message.
      if (!d.delivered) setErr('The code was created but could not be delivered. Check WhatsApp sending before retrying.');
    } catch (e: any) { setErr(e?.message || 'Could not send the code.'); }
    finally { setBusy(false); }
  };

  const doOpen = async () => {
    if (reason.trim().length < 8) { setErr('Please write why you are making this change — at least a short sentence.'); return; }
    if (!/^\d{6}$/.test(code.trim())) { setErr('Enter the six-digit code from your phone.'); return; }
    if (!ch) { setErr('Request a code first.'); return; }
    setBusy(true); setErr(''); setNote('');
    try {
      await controlModeOpen({ reason: reason.trim(), challenge_id: ch.challenge_id, nonce: ch.nonce, code: code.trim() });
      setNote('Control Mode is open.');
      setCode(''); setCh(null); setStep('idle');
      onDone();
      onOpenChange(false);
    } catch (e: any) { setErr(e?.message || 'Could not open Control Mode.'); }
    finally { setBusy(false); }
  };

  const doClose = async () => {
    setBusy(true); setErr(''); setNote('');
    try { await controlModeClose(); setNote('Control Mode closed.'); onDone(); }
    catch (e: any) { setErr(e?.message || 'Could not close Control Mode.'); }
    finally { setBusy(false); }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side='right' className='w-full sm:max-w-md overflow-y-auto'>
        <SheetHeader>
          <SheetTitle className='flex items-center gap-2'>
            {inControl ? <ShieldCheck className='h-4 w-4 text-emerald-600' /> : <Eye className='h-4 w-4' />}
            {inControl ? 'Control Mode is open' : 'Observe Mode'}
          </SheetTitle>
          <SheetDescription>
            {inControl
              ? 'Changes are allowed until this session expires. Everything you do is recorded against the reason below.'
              : 'Everything is readable and nothing can be changed. Opening Control Mode needs a code sent to your registered phone and a written reason.'}
          </SheetDescription>
        </SheetHeader>

        {why ? (
          <div className='mt-4 rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-xs leading-relaxed text-amber-700 dark:text-amber-300'>
            {why}
          </div>
        ) : null}

        {inControl ? (
          <div className='mt-5 space-y-4'>
            <div className='rounded-md border border-border p-3 space-y-2 text-sm'>
              <div className='flex items-center justify-between'>
                <span className='text-muted-foreground text-xs uppercase tracking-wide'>Time remaining</span>
                <span className='font-mono tabular-nums text-base'>{mmss(secondsLeft)}</span>
              </div>
              <div>
                <div className='text-muted-foreground text-xs uppercase tracking-wide'>Reason on record</div>
                <div className='mt-0.5 break-words'>{status?.reason || '—'}</div>
              </div>
              <div className='flex items-center gap-2 text-xs text-muted-foreground'>
                <Badge variant='secondary'>{status?.actions_used ?? 0} action{(status?.actions_used ?? 0) === 1 ? '' : 's'} used</Badge>
                {status?.expires_at ? <span>Expires {new Date(status.expires_at).toLocaleTimeString()}</span> : null}
              </div>
            </div>
            <Button variant='outline' className='w-full' onClick={doClose} disabled={busy}>
              {busy ? <Loader2 className='h-4 w-4 animate-spin mr-2' /> : <X className='h-4 w-4 mr-2' />}
              Close Control Mode now
            </Button>
            <p className='text-xs text-muted-foreground leading-relaxed'>
              Closing early is the safe habit — the session ends by itself, but until it does, anyone
              with this browser open can make changes as you.
            </p>
          </div>
        ) : (
          <div className='mt-5 space-y-4'>
            <div>
              <label className='text-xs uppercase tracking-wide text-muted-foreground'>Why are you making this change?</label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={3}
                placeholder='e.g. Approving Al Noor Electromechanical after checking their trade licence expiry'
                className='mt-1 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2'
              />
              <p className='mt-1 text-xs text-muted-foreground leading-relaxed'>
                Stored on the session, and every action you take is recorded against it. This is the
                sentence that will explain the change in six months.
              </p>
            </div>

            {step === 'idle' ? (
              <Button className='w-full' onClick={sendCode} disabled={busy}>
                {busy ? <Loader2 className='h-4 w-4 animate-spin mr-2' /> : <Phone className='h-4 w-4 mr-2' />}
                Send a code to my phone
              </Button>
            ) : (
              <div className='space-y-3'>
                <div>
                  <label className='text-xs uppercase tracking-wide text-muted-foreground'>
                    Six-digit code{ch?.phone_tail ? ` — sent to the number ending ${ch.phone_tail}` : ''}
                  </label>
                  <Input
                    value={code}
                    onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    inputMode='numeric'
                    autoComplete='one-time-code'
                    placeholder='000000'
                    className='mt-1 font-mono tracking-[0.4em] text-center text-lg'
                    onKeyDown={(e) => { if (e.key === 'Enter') doOpen(); }}
                  />
                </div>
                <Button className='w-full' onClick={doOpen} disabled={busy}>
                  {busy ? <Loader2 className='h-4 w-4 animate-spin mr-2' /> : <ShieldCheck className='h-4 w-4 mr-2' />}
                  Open Control Mode
                </Button>
                <button onClick={sendCode} disabled={busy} className='w-full text-xs text-muted-foreground hover:text-foreground'>
                  Send a new code
                </button>
              </div>
            )}

            <p className='text-xs text-muted-foreground leading-relaxed'>
              The code goes to the number registered against your admin identity — it is never taken
              from this page, so nobody can point their own code at a different phone.
            </p>
          </div>
        )}

        {note ? <div className='mt-4 rounded-md border border-emerald-500/40 bg-emerald-500/10 p-3 text-xs text-emerald-700 dark:text-emerald-300'>{note}</div> : null}
        {err ? <div className='mt-3 rounded-md border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive'>{err}</div> : null}
      </SheetContent>
    </Sheet>
  );
}
