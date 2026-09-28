// THE INVITATION LANE (24 Sep 2026; Assigned: marketing (campaign) + it_engineer (mail path)).
//
// MEASURED: invitations, sign-up codes (login_otp) and every notice left from the same identity,
// info@quotesdone.com (the_supplier_invitation_is_sent_from_info.sql). A cold campaign's bounces and spam
// complaints would be scored against the domain the sign-up codes depend on.
//
// The lane is a separate sender on its own subdomain (app_secrets.invite_lane_from, seeded
// 'QuotesDone <invite@hello.quotesdone.com>'), behind app_secrets.invite_lane_enabled, seeded 'false'.
//   OFF   the From is exactly what send_outbox used before this file existed (fromSup / fromInfo).
//   ON    supplier_invite and supplier_invite_seed to a supplier leave from the lane. Nothing else ever does:
//         not a sign-up code, not a notice, not a reminder of another type. The Reply-To is not touched.
//   ON but the lane's domain is not verified + sending-enabled in Resend (GET /domains, read-only), or Resend
//         does not answer: the lane's invitations are HELD (holdFor -> 'unverified'), NEVER sent from info@, and
//         one it_engineer finding (LANE_UNVERIFIED_ISSUE) says why. Every other row sends exactly as today.
//         (Review of #963: leads.invited_at is written when the row is QUEUED, so a fallback to info@ would put
//         the cold campaign back on the sign-up codes' identity, and warm the new lane's ramp with info@ sends.)
//   A held row stays 'queued' with not_before moved out (HOLD_UNVERIFIED_MS), so it never takes a claim slot
//   from other mail (the 15 Sep starvation, channels.ts). On the lane at most invite_daily_cap invitations
//   leave per UTC day ('cap'), so a backlog released by verification cannot exceed the ramp's number.
// Warm-up is the existing fn_invite_ramp, scoped to the lane's own sends from its activation stamp
// (scripts/sql/the_invitations_leave_on_their_own_subdomain_so_a_campaign_cannot_cost_the_sign_up_codes.sql).
// Pure apart from the injected fetch and finding writer, so invite_lane.test.ts replays every branch offline.

/** The only notification types the lane carries. Exact match: a prefix would let a new type in unreviewed. */
export const INVITE_LANE_TYPES: readonly string[] = ['supplier_invite', 'supplier_invite_seed'];
export const LANE_UNVERIFIED_ISSUE = 'invite_lane_domain_unverified';

export function isLaneType(type: unknown): boolean {
  return typeof type === 'string' && INVITE_LANE_TYPES.includes(type);
}

/** The domain of a From such as 'QuotesDone <invite@hello.quotesdone.com>', lower-cased; null if unparseable. */
export function laneDomain(from: string | undefined | null): string | null {
  const m = String(from || '').match(/<?[^<>\s@]+@([a-z0-9.-]+\.[a-z]{2,})>?\s*$/i);
  return m ? m[1].toLowerCase() : null;
}

export type Lane = { active: boolean; refused: boolean; from: string; domain: string | null; why: string };
export const LANE_OFF: Lane = { active: false, refused: false, from: '', domain: null, why: 'invite_lane_enabled is not true' };

/** How long a lane invitation held for an unverified domain waits before it is looked at again. */
export const HOLD_UNVERIFIED_MS = 30 * 60_000;

/**
 * Whether this row must be held instead of sent. null = send it (with senderFor's From).
 *   'unverified'  the flag is on and the lane was refused: a lane invitation never leaves from the main sender.
 *   'cap'         the lane is active and today's lane invitations already reached invite_daily_cap.
 * A row that is not a lane invitation to a supplier is never held here, whatever the lane's state.
 */
export function holdFor(o: { lane: Lane; type: unknown; supplierSide: boolean; laneSentToday: number; laneCap: number }): 'unverified' | 'cap' | null {
  if (!o.supplierSide || !isLaneType(o.type)) return null;
  if (o.lane.refused) return 'unverified';
  if (o.lane.active && o.type === 'supplier_invite' && o.laneSentToday >= o.laneCap) return 'cap';
  return null;
}

/** When a held row is next due: 30 minutes on for 'unverified'; 06:00 UTC (10:00 Dubai) tomorrow for 'cap'. */
export function heldUntil(why: 'unverified' | 'cap', now: Date): Date {
  if (why === 'unverified') return new Date(now.getTime() + HOLD_UNVERIFIED_MS);
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1, 6, 0, 0));
}

/** The From for one row. With the lane inactive this is, byte for byte, the expression it replaced. */
export function senderFor(o: { type: unknown; supplierSide: boolean; fromSup: string; fromInfo: string; lane: Lane }): string {
  if (o.lane.active && o.supplierSide && isLaneType(o.type)) return o.lane.from;
  return o.supplierSide ? o.fromSup : o.fromInfo;
}

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type DomainCheck = { verified: boolean; status: string };

/** Resend's own word on the domain: listed, status 'verified', and sending not disabled. Read-only GET. */
export async function resendDomainVerified(fetchFn: Fetch, apiKey: string, domain: string): Promise<DomainCheck> {
  let r: Response;
  try { r = await fetchFn('https://api.resend.com/domains', { method: 'GET', headers: { Authorization: `Bearer ${apiKey}` } }); }
  catch (e) { return { verified: false, status: 'Resend /domains did not answer: ' + String((e as Error)?.message || e).slice(0, 120) }; }
  if (!r.ok) return { verified: false, status: `Resend /domains answered HTTP ${r.status}` };
  let j: { data?: Array<{ name?: string; status?: string; capabilities?: { sending?: string } }> };
  try { j = await r.json(); } catch { return { verified: false, status: 'Resend /domains answered without JSON' }; }
  const d = (j.data || []).find((x) => String(x.name || '').toLowerCase() === domain);
  if (!d) return { verified: false, status: `${domain} is not a domain in this Resend account` };
  const sending = d.capabilities?.sending;
  if (d.status !== 'verified') return { verified: false, status: `${domain} is '${d.status}' in Resend, not 'verified'` };
  if (sending !== undefined && sending !== 'enabled') return { verified: false, status: `${domain} is verified but sending is '${sending}'` };
  return { verified: true, status: 'verified' };
}

export type FileFinding = (args: Record<string, unknown>) => Promise<unknown>;

/**
 * Decide the lane for one send_outbox run. Asks Resend only when the flag is on AND the batch holds a row
 * the lane would carry, so a normal 2-minute poll with the flag off makes no extra call.
 */
export async function resolveLane(o: {
  enabled: string | undefined; from: string | undefined; apiKey: string; needed: boolean; fetchFn: Fetch; fileFinding: FileFinding;
}): Promise<Lane> {
  if (String(o.enabled || '').trim().toLowerCase() !== 'true') return LANE_OFF;
  if (!o.needed) return { ...LANE_OFF, why: 'no invitation in this batch' };
  const from = String(o.from || '').trim();
  const domain = laneDomain(from);
  const refuse = async (status: string): Promise<Lane> => {
    try {
      await o.fileFinding({
        p_issue_key: LANE_UNVERIFIED_ISSUE,
        p_title: 'The invitation lane is switched on but its sending domain is not verified in Resend; supplier invitations are held until it is',
        p_where: 'edge function send_outbox (send_outbox/invite_lane.ts)', p_blast: 'internal', p_affected: 1,
        p_evidence: { invite_lane_from: from, domain, resend: status, effect: 'supplier_invite and supplier_invite_seed held (queued, not_before moved on); all other mail unaffected' },
        p_ruled_out: [], p_undetermined: [], p_raised_by: 'it_engineer',
      });
    } catch (_e) { /* the fallback send goes on; the refusal is also in the returned why */ }
    return { active: false, refused: true, from: '', domain, why: 'refused: ' + status };
  };
  if (!domain) return await refuse(`invite_lane_from '${from}' has no parseable address`);
  const chk = await resendDomainVerified(o.fetchFn, o.apiKey, domain);
  if (!chk.verified) return await refuse(chk.status);
  return { active: true, refused: false, from, domain, why: 'verified' };
}
