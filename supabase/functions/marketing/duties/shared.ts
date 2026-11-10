// Shared helpers of the marketing duties (split out of duties.ts, 9 Nov 2026; a pure move): each platform on its
// own (isolated, Skip), a SHA-256 hex, the Graph API version, and the seat's model client.
import { makeLlmRich } from '../../_shared/llm.ts';
import { modelHeld } from '../../_shared/llm_hold.ts';
import type { Deps } from '../../_shared/marketing_judgement.ts';
import type { AskModel } from '../lead_sourcing.ts';
import type { Admin, DutyContext } from './types.ts';

// ── EACH PLATFORM ON ITS OWN ─────────────────────────────────────────────────────────────────────────
// One platform failing never stops the others. A credential failure (missing, expired, refused) SKIPS that
// platform and says so; any other failure is collected and thrown once every step has run, so it becomes the
// seat's IT finding without costing the other platforms their run.
const CREDENTIAL = /\b(401|403|190)\b|token|credential|unauthori[sz]ed|forbidden|expired|oauth|not connected|no .*key/i;
export async function isolated(steps: Record<string, () => Promise<unknown>>) {
  const out: Record<string, unknown> = {}; const skipped: string[] = []; const errors: string[] = [];
  for (const [name, step] of Object.entries(steps)) {
    try { out[name] = await step(); }
    catch (e) {
      const msg = String((e as Error)?.message || e).slice(0, 200);
      if (e instanceof Skip || CREDENTIAL.test(msg)) skipped.push(name + ': ' + msg); else errors.push(name + ': ' + msg);
    }
  }
  return { out, skipped, errors };
}
export class Skip extends Error {}

export async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// THE GRAPH API VERSION IS ONE CONFIG VALUE: app_secrets.meta_graph_version, defaulting to the version the seat's
// other Meta callers use today. Moving versions is one row, not a code search.
const DEFAULT_GRAPH_VERSION = 'v21.0';
export async function graphBase(ctx: DutyContext): Promise<string> {
  const v = String((await ctx.sec('meta_graph_version')) || DEFAULT_GRAPH_VERSION).trim();
  return 'https://graph.facebook.com/' + (/^v\d+\.\d+$/.test(v) ? v : DEFAULT_GRAPH_VERSION);
}

/** The lead sourcing batch's model client (./lead_sourcing.ts, founder 1175): the seat's own callModel on the routine
 *  class, the founder's hold asked first, and the gateway's charge handed back so the batch can hold its USD cap.
 *  Every answer lands in lead_prospect.model_answer. */
export function marketingAsk(admin: Admin): AskModel {
  const deps = marketingDeps({ admin, sec: () => Promise.resolve(undefined), now: new Date() });
  return async (prompt) => {
    if (await deps.held()) return { content: null, cost_usd: 0 };
    const r = await deps.callModel('routine_employee_reasoning', 300, [{ role: 'user', content: prompt }], []);
    return { content: r.content, cost_usd: r.cost_usd ?? 0 };
  };
}

/** The seat's model client: its own class per step, charged to the marketing ceiling. */
export function marketingDeps(ctx: DutyContext): Deps {
  return {
    admin: ctx.admin,
    held: () => modelHeld(ctx.admin),
    callModel: async (taskClass, max, messages, requireCaps) => {
      const llm = makeLlmRich(undefined, { fn: 'marketing', taskClass, dept: 'marketing', agent: 'marketing', max, timeoutMs: 45000, temperature: 0.2 });
      const r = await llm('', '', max, '', { messages, requireCaps });
      return { content: r.content, error: r.error, truncated: r.truncated, model: r.model ?? null, cost_usd: r.cost_usd ?? null };
    },
    download: async (bucket, path) => {
      const { data, error } = await ctx.admin.storage.from(bucket).download(path);
      if (error || !data) throw new Error('download ' + path + ': ' + (error?.message || 'nothing'));
      return new Uint8Array(await data.arrayBuffer());
    },
    signedUrl: async (bucket, path) => {
      const { data } = await ctx.admin.storage.from(bucket).createSignedUrl(path, 3600);
      return data?.signedUrl ?? null;
    },
  };
}
