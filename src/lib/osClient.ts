'use client';
import { createClient } from '@supabase/supabase-js';
// The project ref and anon key used to be compiled in, so a preview deployment talked to
// PRODUCTION regardless of what was configured for it - and setting Vercel env vars did nothing,
// because nothing read them. Both now resolve from the environment; the production literals remain
// only as a fallback so an unconfigured production build behaves exactly as before.
//
// Moved to src/lib/supaEnv.ts on 5 Aug 2026: this module had the resolution AND the warning, but
// the customer portal, supplier portal, contact form and chat widget each re-declared the fallback
// inline and inherited neither. Re-exported here so existing importers are unaffected.
export { SUPA_URL, SUPA_ANON, SUPA_FN } from './supaEnv';
import { SUPA_URL, SUPA_ANON } from './supaEnv';

export const supa = createClient(SUPA_URL, SUPA_ANON, { auth: { persistSession: true, autoRefreshToken: true } });
// LLM-backed actions can legitimately take a while (agent reasoning on Opus, question generation,
// knowledge regeneration). Give those a long budget so a working-but-slow call isn't killed at 25s;
// keep plain reads snappy. (The backend agent chain can run 45–120s across model retries.)
const SLOW_ACTION = /secretary_chat|exam_run|knowledge_refresh|knowledge_dispatch|extract_doc|report_pdf/;

// ── CONTROL MODE (3 Aug 2026) ──────────────────────────────────────────────────────────────────
// Phase 1.4 put a Control Mode gate in front of every mutating action in os_api, os_ops and
// refunds_api, and shipped with no way to open one. The console therefore had a large set of
// buttons that could only ever fail.
//
// Worse, they failed DISHONESTLY. Every helper below tested `r.status === 403` BEFORE looking at
// the body, so a refusal that carried a perfectly clear { error: 'control_mode_required', hint }
// was reported to the founder as "Not authorized (admin only)" - which reads as "your account is
// wrong", sends you to check permissions, and never mentions the thing you actually need to do.
//
// Two changes: the gate refusals are recognised by code and given their own error type, and each
// one also fires a window event so the shell can put the Control Mode panel in front of you at the
// moment you needed it. Call sites are untouched - they keep their own .catch and still show a
// message; the panel simply appears alongside it.
export class ControlModeError extends Error {
  code: string; hint?: string; gatedAction?: string;
  constructor(code: string, message: string, hint?: string, gatedAction?: string) {
    super(message);
    this.name = 'ControlModeError';
    this.code = code; this.hint = hint; this.gatedAction = gatedAction;
  }
}

export const CONTROL_MODE_EVENT = 'qd:control-mode-required';
export const CONTROL_MODE_CHANGED = 'qd:control-mode-changed';

const GATE_CODES = new Set([
  'control_mode_required',
  'control_mode_unavailable',
  'action_classification_required',
  'containment_control_mode_required',   // the pre-3-Aug name, still possible from an old deploy
]);

function gateCheck(r: Response, j: any, action: string) {
  const code = String(j?.error || '');
  if (r.status !== 403 || !GATE_CODES.has(code)) return;
  const message =
    code === 'control_mode_unavailable'
      ? 'The Control Mode gate could not be checked, so this change was refused rather than allowed.'
      : code === 'action_classification_required'
      ? 'This action has not been classified as read-only or mutating, so it was refused.'
      : 'This changes something, so it needs Control Mode.';
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent(CONTROL_MODE_EVENT, {
      detail: { code, action, hint: j?.hint || j?.detail || null, message },
    }));
  }
  throw new ControlModeError(code, message, j?.hint || j?.detail || undefined, action);
}

/** Shared response handling so a gate refusal reads the same whichever function produced it. */
function unwrap(r: Response, j: any, action: string) {
  if (r.status === 401) throw new Error('Session expired');
  gateCheck(r, j, action);
  if (r.status === 403) throw new Error(j?.hint || j?.error || 'Not authorized (admin only)');
  if (j?.error) throw new Error(j.error);
  return j.data;
}

export type ControlModeStatus = {
  mode: 'observe' | 'control';
  session_id?: string | null;
  reason?: string;
  opened_at?: string;
  expires_at?: string;
  seconds_remaining?: number;
  actions_used?: number;
  message?: string;
};

export async function controlModeStatus(): Promise<ControlModeStatus> {
  return await osApi('control_mode_status');
}
/** Step one: mint a code and send it to the number registered against this admin identity. */
export async function controlModeChallenge(): Promise<{ challenge_id: string; nonce: string; phone_tail: string; expires_at: string; delivered: boolean; message: string }> {
  return await osApi('control_mode_challenge');
}
/** Step two: challenge id + nonce + code + a written reason, all bound to this identity. */
export async function controlModeOpen(p: { reason: string; challenge_id: string; nonce: string; code: string }) {
  const d = await osApi('control_mode_open', p);
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(CONTROL_MODE_CHANGED));
  return d;
}
export async function controlModeClose() {
  const d = await osApi('control_mode_close');
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent(CONTROL_MODE_CHANGED));
  return d;
}
export async function osApi(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), SLOW_ACTION.test(action) ? 120000 : 30000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_api', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) {
    throw new Error(e?.name === 'AbortError' ? 'The agent is taking longer than usual — your work is saved; please retry' : (e?.message || 'Network error'));
  } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
// ── THE FOUNDER COMMAND CENTER (15 Aug 2026) ──────────────────────────────────────────────────
// Phase C built the command channel end to end — deterministic router, atomic task creation, exact
// canonical owners, traces — registered it in both gates, deployed it, and gave it NO CONTROL IN
// THE UI. The founder sent a real command and production recorded nothing at any layer, because
// there was nothing for it to travel through. `src/` did not contain the string `founder_command`.
//
// These four are that missing link. They are thin on purpose: osApi already carries the session
// token, the Control Mode gate handling and the error shapes.
//
// A note on which path an instruction takes. The Console has always spoken to `secretary_chat`,
// which drives an LLM agent — a PAID path, currently held open-circuit. An ORDER now goes to
// `founder_command` first: deterministic, free, and the only path that creates canonical tasks
// against exact employees. Only when the registry has no intent for the text at all does the
// Console fall back to the conversational agent.

export type FounderCommandResult = {
  ok: boolean;
  command_id?: number;
  status?: 'tasks_created' | 'clarification_required' | 'refused' | 'accepted';
  intent?: string;
  outcome?: string;
  interpretation?: string;
  workflow_ids?: string[];
  task_ids?: number[];
  owner?: string;
  primary_owner?: string;
  child_owners?: string[];
  category_overlays_invoked?: string[];
  tasks_created?: number;
  priority?: string;
  due_at?: string;
  founder_approval_required?: boolean;
  founder_initiated_only?: boolean;
  clarification?: string;
  blocker?: string;
  trace_id?: number;
  duplicate_of_idempotency_key?: string;
};

/**
 * Issue a founder command. `idempotencyKey` is what makes a double-tap safe: the same key returns
 * the SAME command rather than a second one. When none is supplied os_api derives one from the
 * message text, so a retried request cannot open two commands either.
 */
export async function founderCommand(message: string, idempotencyKey?: string): Promise<FounderCommandResult> {
  return await osApi('founder_command', { message, ...(idempotencyKey ? { idempotency_key: idempotencyKey } : {}) });
}

/** One command, its plan, its tasks, their owners and blockers. Read-only — no Control Mode. */
export async function founderCommandStatus(ref: string | number) {
  return await osApi('founder_command_status', { ref: String(ref) });
}

/** Cancel, reprioritise, supersede or explain. Mutating. */
export async function founderCommandControl(commandId: number, op: 'cancel' | 'reprioritize' | 'supersede' | 'explain', target?: string | number, value?: string) {
  return await osApi('founder_command_control', { command_id: commandId, op, target: String(target ?? commandId), ...(value ? { value } : {}) });
}

/** What the founder is looking at: recent commands, what is open, blocked, and awaiting his refund decision. */
export async function founderCommandInbox(limit = 25) {
  return await osApi('founder_command_inbox', { limit });
}

/** The founder-facing thread for one command, including every progress note and the completion. */
/** Answer a clarification in the same command thread. One command id; the original message is kept. */
export async function founderCommandClarify(commandId: number, answer: string) {
  return await osApi('founder_command_clarify', { command_id: commandId, answer });
}

export async function founderCommandThread(commandId: number) {
  return await osApi('founder_command_thread', { command_id: commandId });
}

export async function osReportBody(id: number) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/report_body', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ id }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j as { ok: boolean; found: boolean; report?: any; note?: string };
}
export async function osOps(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_ops', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osSettings(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_settings', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osAutomation(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_automation', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osCatalog(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_catalog', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osPages(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 40000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_pages', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osHealth(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_health', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
export async function osIncidents(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_incidents', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  return unwrap(r, j, action);
}
