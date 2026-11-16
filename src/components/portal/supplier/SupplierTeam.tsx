'use client';
// TEAM AND ACCOUNT (16 Nov 2026, customer_support + sales_engineer; agent SUPPLIER_W2; SUPPLIER holes 4 and 6). A company was one
// e-mail: the estimator could not quote from his own address and the invitation screen promised "ask them to add you" with no way to
// do it. The owner now adds estimators (they may quote) and viewers (they read), removes them, and can hand the company to a member
// with a code sent to his own address. A member sees his role, confirms his WhatsApp number with a code, and can leave. The owner can
// close the account: he chooses whether his quotations with customers are withdrawn or kept, is told what the law keeps and until
// when, and confirms; he can reopen it. English only: everything the platform writes to a supplier is English.
// Every press is one supplier_api action (actions/team.ts) and every refusal is the server's own sentence.
// 16 Nov 2026 (W3_PEOPLE; wave-3 items 2 and 4): every member can show the company's own referral link (he sends it, we write to
// nobody); a member whose owner has LEFT can ask to take the company over (the sales engineer decides; the owner is told and keeps
// three days), and the owner sees that ask with "Keep ownership".
import React, { useEffect, useState } from 'react';
import { call } from './api';

type Member = { email: string; name: string; role: 'estimator' | 'viewer'; status: string; phone_tail?: string; phone_confirmed?: boolean };
type Claim = { id: number; state: 'open' | 'waiting_claimant' | 'approved_waiting'; claimant_email: string; effective_at: string | null };
type Team = { me: { role: 'owner' | 'estimator' | 'viewer'; email: string }; owner: { email: string; company_name: string | null }; members: Member[]; transfer: { to_email: string } | null; claim?: Claim | null };
type Law = { kept_until?: string; kept?: string[]; law?: string; legal_hold?: boolean };

const btn = 'min-h-11 rounded-md bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary/90 disabled:opacity-50';
const ghost = 'min-h-11 rounded-md border border-input px-4 py-2 text-sm text-foreground hover:bg-muted disabled:opacity-50';
const field = 'w-full rounded-md border border-input bg-card text-foreground px-3 py-2 text-sm outline-hidden focus-visible:ring-1 focus-visible:ring-ring pointer-coarse:text-[16px] pointer-coarse:min-h-11';
const ROLE = { estimator: 'Estimator: reads requests and sends quotations', viewer: 'Viewer: reads requests and quotations' } as const;

export default function SupplierTeam({ token }: { token?: string | null }) {
  const [team, setTeam] = useState<Team | null>(null);
  const [err, setErr] = useState(''); const [msg, setMsg] = useState(''); const [busy, setBusy] = useState(false);
  const [inv, setInv] = useState({ email: '', name: '', role: 'estimator', phone: '' });
  const [code, setCode] = useState(''); const [phoneCode, setPhoneCode] = useState<{ code: string; tail: string } | null>(null);
  const [closeQ, setCloseQ] = useState<'withdraw' | 'keep'>('withdraw'); const [reason, setReason] = useState('');
  const [proposal, setProposal] = useState<{ live: number; law: Law } | null>(null); const [closed, setClosed] = useState(false);
  const [ownerLeft, setOwnerLeft] = useState(''); const [refLink, setRefLink] = useState<{ url?: string; why?: string } | null>(null);

  const load = async () => {
    const j = await call('supplier_api', { action: 'team' }, token);
    if (j?.ok) setTeam(j as Team); else setErr(j?.error || 'We could not load your team. Please try again.');
    const c = await call('supplier_api', { action: 'account_closure' }, token);
    setClosed(c?.closure?.state === 'closed');
  };
  useEffect(() => { load(); }, [token]);
  const act = async (body: Record<string, unknown>, ok: (j: any) => string | void) => {
    setBusy(true); setErr(''); setMsg('');
    const j = await call('supplier_api', body, token);
    setBusy(false);
    if (!j?.ok) { setErr(j?.error || 'That did not work. Please try again.'); return null; }
    const m = ok(j); if (m) setMsg(m);
    await load();
    return j;
  };
  if (!team) return <section className="qd-panel p-5 text-[13px] text-muted-foreground" aria-busy={!err}>{err || 'Loading your team…'}</section>;
  const owner = team.me.role === 'owner';
  const active = team.members.filter((m) => m.status === 'active');

  return (
    <div className="space-y-4" dir="ltr" lang="en">
      <section className="qd-panel p-5" aria-labelledby="qd-team-title">
        <h3 id="qd-team-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Team</h3>
        <p className="text-[12px] text-muted-foreground mb-3">Owner: <bdi dir="ltr">{team.owner.email}</bdi>{owner ? ' (you)' : ''}. Every member signs in with his own e-mail code and is checked like the owner.</p>
        <ul className="space-y-2 mb-3">
          {team.members.length === 0 && <li className="text-[12.5px] text-muted-foreground">No members yet.</li>}
          {team.members.map((m) => (
            <li key={m.email} className="flex flex-wrap items-center justify-between gap-2 text-[13px]">
              <span className="min-w-0"><strong>{m.name}</strong> · <bdi dir="ltr">{m.email}</bdi> · {m.role}{m.status !== 'active' ? ` · ${m.status === 'invited' ? 'invitation sent' : 'being checked'}` : ''}{m.phone_confirmed ? ` · WhatsApp …${m.phone_tail}` : ''}</span>
              {(owner || m.email === team.me.email) && <button type="button" className={ghost} disabled={busy} onClick={() => act({ action: 'member_remove', email: m.email }, () => (owner ? `${m.name} was removed.` : 'You have left the company.'))}>{owner ? 'Remove' : 'Leave'}</button>}
            </li>
          ))}
        </ul>
        {owner && (
          <form className="grid gap-2" onSubmit={(e) => { e.preventDefault(); act({ action: 'member_invite', ...inv }, () => `Invitation sent to ${inv.email}. He accepts after signing in with that address.`).then((j) => { if (j) setInv({ email: '', name: '', role: 'estimator', phone: '' }); }); }}>
            <label className="text-[13px]" htmlFor="qd-inv-name">Full name (as on his ID)</label>
            <input id="qd-inv-name" className={field} required value={inv.name} onChange={(e) => setInv({ ...inv, name: e.target.value })} />
            <label className="text-[13px]" htmlFor="qd-inv-email">His work e-mail</label>
            <input id="qd-inv-email" type="email" className={field} required value={inv.email} onChange={(e) => setInv({ ...inv, email: e.target.value })} />
            <label className="text-[13px]" htmlFor="qd-inv-phone">His WhatsApp number (optional)</label>
            <input id="qd-inv-phone" type="tel" className={field} value={inv.phone} onChange={(e) => setInv({ ...inv, phone: e.target.value })} />
            <fieldset className="space-y-1"><legend className="text-[13px]">Role</legend>
              {(['estimator', 'viewer'] as const).map((r) => (
                <label key={r} className="flex items-center gap-2 text-[12.5px]"><input type="radio" name="qd-inv-role" checked={inv.role === r} onChange={() => setInv({ ...inv, role: r })} className="h-4 w-4 accent-primary" />{ROLE[r]}</label>
              ))}
            </fieldset>
            <button type="submit" className={btn} disabled={busy}>Add to the team</button>
          </form>
        )}
        {!owner && team.me.role && (
          <div className="mt-2 space-y-2">
            <p className="text-[12.5px]">You are {team.me.role === 'estimator' ? 'an estimator' : 'a viewer'} of {team.owner.company_name || 'this company'}.</p>
            <button type="button" className={ghost} disabled={busy} onClick={() => act({ action: 'member_phone_code' }, (j) => { setPhoneCode({ code: j.code_to_send, tail: j.phone_tail }); })}>Use my WhatsApp number for this company</button>
            {phoneCode && <p role="status" className="text-[12.5px]">From your WhatsApp number ending {phoneCode.tail}, send <strong><bdi dir="ltr">{phoneCode.code}</bdi></strong> to our WhatsApp within 30 minutes.</p>}
          </div>
        )}
      </section>

      <section className="qd-panel p-5" aria-labelledby="qd-refer-title">
        <h3 id="qd-refer-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Invite another company</h3>
        <p className="text-[12px] text-muted-foreground mb-2">Send your company's own link to companies you know in your trade. We do not write to them; when one registers through it, it is recorded that you referred it. Registration is free, and nobody can pay to rank higher.</p>
        {!refLink ? (
          <button type="button" className={ghost} disabled={busy} onClick={async () => { setBusy(true); const j = await call('supplier_api', { action: 'referral_link' }, token); setBusy(false); setRefLink(j?.ok ? { url: j.url } : { why: j?.why || j?.error || 'Your link could not be read just now. Please try again.' }); }}>Show my referral link</button>
        ) : refLink.url ? (
          <div className="flex flex-wrap items-center gap-2">
            <input readOnly aria-label="Your referral link" className={field} value={refLink.url} onFocus={(e) => e.currentTarget.select()} />
            <button type="button" className={ghost} onClick={() => { try { navigator.clipboard?.writeText(refLink.url || ''); setMsg('Link copied.'); } catch (_e) { /* the field stays selectable */ } }}>Copy</button>
          </div>
        ) : <p className="text-[12.5px]">{refLink.why}</p>}
      </section>

      {owner && team.claim && (
        <section className="qd-panel p-5" aria-labelledby="qd-claim-owner-title">
          <h3 id="qd-claim-owner-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">A member asks to take over the company</h3>
          <p className="text-[12.5px] mb-2"><bdi dir="ltr">{team.claim.claimant_email}</bdi> told us you have left the company and asked to become its owner.{team.claim.state === 'approved_waiting' && team.claim.effective_at ? ` It was approved and takes effect on ${new Date(team.claim.effective_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}.` : ' Our sales engineer is looking into it.'} If you are still the owner, keep it: nothing changes.</p>
          <button type="button" className={btn} disabled={busy} onClick={() => act({ action: 'ownership_claim_object' }, () => 'You keep the company. We told the member.')}>Keep ownership</button>
        </section>
      )}

      {!owner && (
        <section className="qd-panel p-5" aria-labelledby="qd-claim-title">
          <h3 id="qd-claim-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">The owner has left the company?</h3>
          {team.claim ? (
            <p className="text-[12.5px]">{team.claim.state === 'approved_waiting' ? `Approved: the company passes to ${team.claim.claimant_email} on ${team.claim.effective_at ? new Date(team.claim.effective_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : 'the date we wrote'} unless the owner keeps it.` : team.claim.state === 'waiting_claimant' ? 'Our sales engineer asked for one more thing by e-mail. Answer it there, or below.' : 'Our sales engineer is looking into the request. The owner has been told.'}</p>
          ) : (
            <p className="text-[12px] text-muted-foreground mb-2">If the owner has left and cannot hand the company over himself, tell us what happened. Our sales engineer reads the company's record and decides; the owner is told and can keep it.</p>
          )}
          {(!team.claim || team.claim.state !== 'approved_waiting') && (
            <form className="grid gap-2 mt-2" onSubmit={(e) => { e.preventDefault(); act({ action: 'ownership_claim', reason: ownerLeft }, () => 'Received. Our sales engineer will decide within two working days, and we told the owner.').then((j) => { if (j) setOwnerLeft(''); }); }}>
              <label className="text-[13px]" htmlFor="qd-owner-left">What happened to the owner?</label>
              <textarea id="qd-owner-left" className={field} rows={3} required value={ownerLeft} onChange={(e) => setOwnerLeft(e.target.value)} />
              <button type="submit" className={ghost} disabled={busy || !ownerLeft.trim()}>{team.claim ? 'Send this to the sales engineer' : 'Ask to take over the company'}</button>
            </form>
          )}
        </section>
      )}

      {owner && active.length > 0 && (
        <section className="qd-panel p-5" aria-labelledby="qd-transfer-title">
          <h3 id="qd-transfer-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Hand the company to a member</h3>
          {!team.transfer ? (
            <div className="flex flex-wrap gap-2">{active.map((m) => <button key={m.email} type="button" className={ghost} disabled={busy} onClick={() => act({ action: 'transfer_start', to: m.email }, () => `We e-mailed a code to ${team.owner.email}. Enter it below to make ${m.name} the owner.`)}>Make {m.name} the owner</button>)}</div>
          ) : (
            <form className="grid gap-2" onSubmit={(e) => { e.preventDefault(); act({ action: 'transfer_confirm', code }, () => `${team.transfer?.to_email} is now the owner. You stay as an estimator.`); }}>
              <label className="text-[13px]" htmlFor="qd-transfer-code">The code we e-mailed to you</label>
              <input id="qd-transfer-code" inputMode="numeric" maxLength={6} className={field} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} />
              <button type="submit" className={btn} disabled={busy || code.length !== 6}>Confirm the hand-over to {team.transfer.to_email}</button>
            </form>
          )}
        </section>
      )}

      {owner && (
        <section className="qd-panel p-5" aria-labelledby="qd-close-title">
          <h3 id="qd-close-title" className="text-xs uppercase tracking-wide text-muted-foreground mb-1">Close the account</h3>
          {closed ? (
            <>
              <p className="text-[12.5px] mb-2">Your account is closed: no job requests reach you.</p>
              <button type="button" className={btn} disabled={busy} onClick={() => act({ action: 'reopen_account' }, () => 'Your account is open again.')}>Reopen my account</button>
            </>
          ) : !proposal ? (
            <div className="space-y-2">
              <p className="text-[12px] text-muted-foreground">Closing stops all new job requests. Choose what happens to your quotations that are still with customers.</p>
              {(['withdraw', 'keep'] as const).map((q) => (
                <label key={q} className="flex items-center gap-2 text-[12.5px]"><input type="radio" name="qd-close-q" checked={closeQ === q} onChange={() => setCloseQ(q)} className="h-4 w-4 accent-primary" />{q === 'withdraw' ? 'Withdraw them' : 'Keep them (a customer may still reveal you, and you are bound by them)'}</label>
              ))}
              <label className="text-[13px]" htmlFor="qd-close-why">Why are you leaving? (optional)</label>
              <input id="qd-close-why" className={field} value={reason} onChange={(e) => setReason(e.target.value)} />
              <button type="button" className={ghost} disabled={busy} onClick={() => act({ action: 'close_account', quotes: closeQ, reason }, (j) => { setProposal({ live: Number(j.live_quotes) || 0, law: j.law || {} }); })}>Continue</button>
            </div>
          ) : (
            <div className="space-y-2">
              <p className="text-[12.5px]">{proposal.live ? `${proposal.live} quotation${proposal.live === 1 ? '' : 's'} will be ${closeQ === 'withdraw' ? 'withdrawn' : 'kept'}. ` : ''}The law requires us to keep, until {proposal.law.kept_until}:</p>
              <ul className="list-disc ps-5 text-[12px] text-muted-foreground">{(proposal.law.kept || []).map((k) => <li key={k}>{k}</li>)}</ul>
              <p className="text-[11.5px] text-muted-foreground">{proposal.law.law}. Nothing is used for marketing. You can ask for a copy of your data at any time.</p>
              <div className="flex flex-wrap gap-2">
                <button type="button" className={btn} disabled={busy} onClick={() => act({ action: 'close_account', quotes: closeQ, reason, confirm: true }, () => 'Your account is closed. We e-mailed you a written confirmation.').then(() => setProposal(null))}>Close my account</button>
                <button type="button" className={ghost} disabled={busy} onClick={() => setProposal(null)}>Keep my account</button>
              </div>
            </div>
          )}
        </section>
      )}
      {msg && <p role="status" className="text-[12px] text-ok-fg">{msg}</p>}
      {err && <p role="alert" className="text-[12px] text-warn-fg">{err}</p>}
    </div>
  );
}
