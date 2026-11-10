// resilience_ping ticks owned by the it_engineer seat: the 15-minute integrations tick, the morning inbox placement check and the Microsoft 365 reply readers. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { timedFetch } from '../../../_shared/timed_fetch.ts';
import { integrationItems } from '../../../_shared/integration_watch.ts';
import { placementTick } from '../../../_shared/inbox_placement.ts';
import { pollReplyInbox, pollTenantMailboxes, PROOF_LABEL, type SenderKind } from '../../../_shared/m365_reply_inbox.ts';
import { FN, admin, sec } from '../../shared.ts';

// EVERY EXTERNAL INTEGRATION, EVERY 15 MINUTES (it_engineer, 24 Sep 2026, founder instruction 979). The list is
// _shared/integration_registry.json; _shared/integration_watch.ts probes each due entry, retries once and makes
// the fixes it can (a Stripe webhook Stripe disabled is re-enabled), and fn_it_integration_settle files one
// finding per integration, closes it by its exact key on recovery, mails the founder only what the company could
// not fix, and counts what it did fix for the IT daily line. Only counts come back: this endpoint is public.
// THE MORNING INBOX PLACEMENT CHECK (24 Sep 2026, it_engineer). Rides on this step because it is the IT
// engineer's 15-minute step (resilience_step every 15 min) and needs no new schedule row
// (every_tick_step_is_scheduled.mjs), as PR #961's Postmaster reading rides on itlater. On a sending day the
// database queues one seed from 04:30 UTC; the next beats read its folder in the Gmail and Microsoft 365 seed
// inboxes (until 08:00 UTC) and fn_invite_placement_record decides. The batch waits for a verdict and goes only on
// Inbox + Inbox (the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql). Outside that
// window it is one indexed read. The answer is counts and verdicts only: this endpoint is public.
async function inboxPlacement(): Promise<Record<string, unknown>> {
  try {
    // The rotated Graph refresh token is stored here; the result's {error} goes back to the reader, which records the
    // message (never the token) in the reading's evidence.
    return await placementTick((fn, args) => admin.rpc(fn, args) as never, fetch, sec,
      async (k, v) => await admin.from('app_secrets').update({ value: v }).eq('key', k));
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

export async function itIntegrationsTick(): Promise<unknown> {
  // TWO INDEPENDENT PATHS, run side by side (review of #966): an integration settle that errors must not skip the
  // morning's placement reading, and a placement error must not hide the integration result.
  const integrations = (async (): Promise<Record<string, unknown>> => {
    try {
      const { items, fixed, outcomes } = await integrationItems(fetch, sec, (k) => Deno.env.get(k));
      const { data, error } = await admin.rpc('fn_it_integration_settle', { p_duty: 'integration', p_items: items, p_fixed: fixed });
      if (error) return { ok: false, error: 'fn_it_integration_settle: ' + error.message };
      return { ok: true, probed: outcomes.length, failing: items.filter((i) => !i.carried && !i.recovered).length, fixed: fixed.length,
               settled: (data as Record<string, unknown> | null)?.failing ?? null };
    } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
  })();
  const replies = m365Replies();   // a third independent path (6 Oct 2026): replies to the Microsoft 365 mailbox
  // a fourth (2 Nov 2026): every other mailbox of the tenant, after supplier@, so one message addressed to both is taken once
  const tenantMail = replies.then(() => m365TenantMail());
  const [integ, placement] = await Promise.all([integrations, inboxPlacement()]);
  const inbox = await replies;
  const tenantInbox = await tenantMail;
  // Either path failing is this step's failure (duty:heartbeat:itintegrations), so it reaches the IT engineer's loop
  // the same beat. The batch is held by the gate regardless. placement carries counts and verdicts only (public).
  const errors = [integ.ok === false ? String(integ.error) : null, placement.ok === false ? 'inbox placement: ' + String(placement.error) : null,
    inbox.ok === false ? 'm365 reply inbox: ' + String(inbox.why) : null,
    tenantInbox.ok === false ? 'm365 tenant mailboxes: ' + String(tenantInbox.why) : null].filter(Boolean);
  return { ...integ, ok: errors.length === 0, ...(errors.length ? { error: errors.join('; ') } : {}), inbox_placement: placement, m365_reply_inbox: inbox, m365_tenant_mailboxes: tenantInbox };
}

// REPLIES TO supplier@quotesdone.com (6 Oct 2026, it_engineer + customer_support; _shared/m365_reply_inbox.ts).
// The invitation lane sends without a Reply-To once this reader is proven, so a supplier's answer lands in that
// mailbox; this reads it and hands every new message to resend_inbound, the handler every other reply goes through.
const m365OnFile = async (ids: string[]) => {
  const { data, error } = await admin.from('inbound_messages').select('provider_email_id').in('provider_email_id', ids);
  if (error) throw new Error('inbound_messages: ' + error.message);
  return new Set((data || []).map((r) => String(r.provider_email_id)));
};
const m365MessageOnFile = async (ids: string[]) => {
  const { data, error } = await admin.from('inbound_messages').select('message_id:raw->>message_id').in('raw->>message_id', ids);
  if (error) throw new Error('inbound_messages: ' + error.message);
  return new Set((data || []).map((r) => String((r as { message_id: unknown }).message_id)));
};
// Who wrote, read only: the founder or staff; a lead (leads.email or claimed_by) or a customer; else a stranger.
async function m365Sender(address: string): Promise<SenderKind> {
  const [own, rel] = await Promise.all([admin.rpc('fn_is_founder_own_inbox', { p_addr: address }), admin.rpc('fn_mail_sender_known', { p_email: address })]);
  if (own.error || rel.error) throw new Error('sender lookup failed');
  if (own.data === true || rel.data === 'staff') return 'founder';
  if (rel.data) return 'known';
  const { data, error } = await admin.from('leads').select('id').ilike('claimed_by', address.replace(/[\\%_]/g, '\\$&')).limit(1);
  if (error) throw new Error('sender lookup failed');
  return data?.length ? 'known' : null;
}
async function m365TenantMail(): Promise<Record<string, unknown>> {
  try {
    return await pollTenantMailboxes({
      fetchFn: (u, i) => timedFetch(u, i || {}, 25_000), env: (k) => Deno.env.get(k),
      inviteMailbox: await sec('invite_m365_mailbox'), listedMailboxes: await sec('m365_tenant_mailboxes'),
      strangersFrom: await sec('m365_tenant_strangers_from'), financialDomains: await sec('m365_financial_domains'), messageOnFile: m365MessageOnFile,
      inboundToken: await sec('resend_inbound_token'), signingSecret: await sec('resend_inbound_signing_secret'), inboundUrl: FN + '/resend_inbound',
      onFile: m365OnFile, sender: m365Sender,
      // counts.m365_tenant and never counts.m365_inbox: send_outbox's proof read cannot select this row.
      record: async (status, counts, note) => {
        await admin.from('agent_runs').insert({ agent: PROOF_LABEL, status, counts, note: note.slice(0, 500),
          started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
      },
    });
  } catch (e) { return { ok: false, why: String((e as Error)?.message || e).slice(0, 200) }; }
}
async function m365Replies(): Promise<Record<string, unknown>> {
  try {
    return await pollReplyInbox({
      fetchFn: (u, i) => timedFetch(u, i || {}, 25_000), env: (k) => Deno.env.get(k),
      mailbox: await sec('invite_m365_mailbox'), inboundToken: await sec('resend_inbound_token'),
      signingSecret: await sec('resend_inbound_signing_secret'), inboundUrl: FN + '/resend_inbound',
      onFile: m365OnFile, sender: m365Sender, messageOnFile: m365MessageOnFile,
      fileFinding: async (args) => { const { error } = await admin.rpc('fn_it_engineer_finding_upsert', args); if (error) throw error; },
      record: async (status, counts, note) => {
        await admin.from('agent_runs').insert({ agent: PROOF_LABEL, status, counts, note: note.slice(0, 500),
          started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
      },
    });
  } catch (e) { return { ok: false, why: String((e as Error)?.message || e).slice(0, 200) }; }
}
