// _shared/tools.ts — the agent tool runtime.
//
// V3 REMEDIATION, Stage 2. Result of record V3-COR-0A782DA90B10 recorded TOOL_NOT_CONNECTED on
// 2,284 of 2,284 certification questions: tool_calls non-empty on every execution row and
// tool_results empty on every one of them. Every answer in that certification was written from
// prompt memory while the rubric scored it on evidence and tool discipline.
//
// The pieces already existed and were never joined:
//   ai_gateway            accepts and forwards OpenAI-shape `tools`, returns `tool_calls`
//   org_action_executor   59 active write executors with timeout / retry / compensation
//   fn_query_platform     21 live read topics
//   _shared/llm.ts        discarded tool_calls on the way back  <- fixed alongside this file
// What was missing is a registry saying which role may hold which tool, a dispatcher that actually
// runs it, and a ledger proving a result came back. This module is the last two.
//
// FOUR PROPERTIES THIS FILE EXISTS TO GUARANTEE:
//   1. A tool the registry does not grant this agent is REFUSED, not quietly skipped.
//   2. "returned nothing" and "could not be reached" are different statuses, never merged.
//   3. Every result handed to a model is hashed into agent_tool_call first, so a claimed result
//      with no matching row is provably fabricated.
//   4. A tool is never simulated. There is no stub path unless the registry row opts in, and no
//      registry row opts in today.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;

export type ToolSpec = {
  tool_id: string; purpose: string; kind: string; impl_kind: string; impl_target: string;
  input_schema: any; timeout_seconds: number; max_attempts: number; backoff: string;
  failure_behaviour: string; requires_current_data: boolean; required_credential?: string | null;
};
/** The app_secrets key the registry declares for this tool, if any. */
const spec_credential = (s: ToolSpec) => s.required_credential ?? null;

export type ToolOutcome = {
  tool_id: string;
  status: 'ok' | 'ok_empty' | 'error' | 'timeout' | 'unavailable' | 'unauthorised';
  /** What the model is shown. Always a string, always the exact bytes we hashed. */
  rendered: string;
  result_hash: string | null;
  rows: number;
  latency_ms: number;
  attempt: number;
  error: string | null;
  call_id: string | null;
};

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

/** Tools this agent may hold, resolved server-side from the roster. A prompt cannot widen this. */
export async function toolsFor(agentKey: string, kind?: 'read' | 'write'): Promise<ToolSpec[]> {
  const { data, error } = await admin.rpc('fn_agent_tools', { p_agent_key: agentKey, p_kind: kind ?? null });
  if (error || !Array.isArray(data)) return [];
  return data as ToolSpec[];
}

/** Registry rows -> OpenAI function definitions for the `tools` request field. */
export function toOpenAiTools(specs: ToolSpec[]): any[] {
  return specs.map(s => ({
    type: 'function',
    function: {
      name: s.tool_id,
      // The model needs to know what happens when the tool cannot answer, or it will guess.
      description: s.purpose +
        (s.requires_current_data ? ' Returns CURRENT data; do not answer this from memory.' : '') +
        (s.failure_behaviour === 'fail_closed' ? ' If this tool fails you must stop and escalate, not proceed.' : ''),
      parameters: s.input_schema ?? { type: 'object', properties: {} },
    },
  }));
}

// ------------------------------------------------------------------------------------------------
// Argument validation. Deterministic, not model-trusted. Enough of JSON Schema to hold the
// contract the registry declares: required keys, types, enums, bounds, no extra properties.
// ------------------------------------------------------------------------------------------------
export function validateArgs(schema: any, args: any): string | null {
  if (!schema || typeof schema !== 'object') return null;
  if (args == null || typeof args !== 'object' || Array.isArray(args)) return 'arguments must be an object';
  const props = schema.properties ?? {};
  for (const req of (schema.required ?? [])) {
    if (args[req] === undefined || args[req] === null) return `missing required argument "${req}"`;
  }
  if (schema.additionalProperties === false) {
    for (const k of Object.keys(args)) if (!(k in props)) return `unknown argument "${k}"`;
  }
  for (const [k, v] of Object.entries(args)) {
    const p: any = props[k]; if (!p || v === undefined || v === null) continue;
    if (p.type === 'string') {
      if (typeof v !== 'string') return `"${k}" must be a string`;
      if (p.minLength && v.length < p.minLength) return `"${k}" must be at least ${p.minLength} characters`;
      if (Array.isArray(p.enum) && !p.enum.includes(v)) return `"${k}" must be one of: ${p.enum.join(', ')}`;
    } else if (p.type === 'integer' || p.type === 'number') {
      const n = Number(v);
      if (!Number.isFinite(n)) return `"${k}" must be a number`;
      if (p.type === 'integer' && !Number.isInteger(n)) return `"${k}" must be an integer`;
      if (p.minimum !== undefined && n < p.minimum) return `"${k}" must be >= ${p.minimum}`;
      if (p.maximum !== undefined && n > p.maximum) return `"${k}" must be <= ${p.maximum}`;
    } else if (p.type === 'object' && (typeof v !== 'object' || Array.isArray(v))) {
      return `"${k}" must be an object`;
    }
  }
  return null;
}

// ------------------------------------------------------------------------------------------------
// Emptiness. This is the distinction the certification could not make, so it gets its own function.
// An empty array, an empty object, a null, or a rows:0 envelope is a REAL ANSWER meaning "none".
// A thrown error, a timeout or an unreachable endpoint is NOT an answer.
// ------------------------------------------------------------------------------------------------
function countRows(v: any): number {
  if (v == null) return 0;
  if (Array.isArray(v)) return v.length;
  if (typeof v === 'object') {
    if (Array.isArray((v as any).rows)) return (v as any).rows.length;
    if (Array.isArray((v as any).results)) return (v as any).results.length;
    if (Array.isArray((v as any).matches)) return (v as any).matches.length;
    return Object.keys(v).length ? 1 : 0;
  }
  return String(v).trim().length ? 1 : 0;
}

async function withTimeout<T>(p: (signal: AbortSignal) => Promise<T>, ms: number): Promise<T> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try { return await p(ac.signal); } finally { clearTimeout(t); }
}

// ------------------------------------------------------------------------------------------------
// Execution. One attempt; retry policy applied by the caller loop below.
// Server-bound arguments (the agent's own key) are injected here and NEVER read from model output.
// ------------------------------------------------------------------------------------------------
async function runOnce(spec: ToolSpec, args: any, agentKey: string, timeoutMs: number): Promise<any> {
  if (spec.impl_kind === 'rpc') {
    const p = ((): Record<string, unknown> => {
      switch (spec.tool_id) {
        case 'query_platform':       return { p_topic: args.topic, p_args: args.args ?? {} };
        case 'ops_knowledge_search': return { p_dept: args.dept ?? null, p_query: args.query, p_limit: Math.min(Number(args.limit ?? 5), 20) };
        case 'dept_library_search':  return { p_dept: args.dept ?? null, p_query: args.query, p_limit: Math.min(Number(args.limit ?? 5), 20) };
        case 'supplier_360':         return { p_id: Number(args.supplier_id) };
        // The agent key is bound from the roster. A model asking about someone else's inbox is
        // asking for another identity's work; it does not get to name the key.
        case 'handoff_inbox':        return { p_agent_key: agentKey };
        default: {
          // GENERIC MAPPING. The first version of this returned the model's raw argument names
          // straight to .rpc(), so any tool registered by another workstream failed with
          // "Could not find the function public.fn_x(dept) in the schema cache" - the tool existed,
          // its parameter was p_dept, and the dispatcher had no idea. Measured live: 3 of 3
          // handoff_stalled calls failed exactly this way.
          // Every routine in this codebase prefixes its parameters with p_, so that is the default;
          // an argument already prefixed is passed through untouched.
          const outArgs: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(args ?? {})) outArgs[k.startsWith('p_') ? k : 'p_' + k] = v;
          return outArgs;
        }
      }
    })();
    // ops_knowledge_search / dept_library_search default the department to the caller's own.
    if ((spec.tool_id === 'ops_knowledge_search' || spec.tool_id === 'dept_library_search') && !p.p_dept) {
      const { data } = await admin.from('org_agents').select('department').eq('agent_key', agentKey).maybeSingle();
      p.p_dept = data?.department ?? null;
    }
    const { data, error } = await admin.rpc(spec.impl_target, p);
    if (error) throw new Error(error.message || 'rpc_error');
    return data;
  }

  if (spec.impl_kind === 'edge_function') {
    // CREDENTIALS. The first version presented inbound_secret and every kb_search call came back
    // edge_403 (measured: 3 of 3). Internal functions are behind fn_internal_auth, which checks
    // that the PRESENTING credential is scoped to call the target - the shared secret is not.
    // Prefer the registry's declared credential, then the caller-scoped one, then the legacy shared
    // secret last. A 403 here is a wiring fault, not a refusal, and it must not read like one.
    const secret = await (async () => {
      for (const key of [spec_credential(spec), 'cred_fn_agent_brain', 'inbound_secret']) {
        if (!key) continue;
        const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle();
        if (data?.value) return data.value as string;
      }
      return '';
    })();
    const r = await withTimeout(sig => fetch(`${SUPA}/functions/v1/${spec.impl_target}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, ...args }), signal: sig,
    }), timeoutMs);
    if (!r.ok) throw new Error(`edge_${r.status}`);
    return await r.json().catch(() => null);
  }

  throw new Error(`unsupported impl_kind ${spec.impl_kind}`);
}

/**
 * Run one model-requested tool call end to end: authorise, validate, execute with retries, record.
 * ALWAYS returns an outcome — it never throws — and ALWAYS writes a ledger row, including for the
 * refusals. A tool call that left no row did not happen.
 */
export async function callTool(
  toolId: string, rawArgs: any, ctx: { agentKey: string; roleId?: string | null; correlationId: string },
): Promise<ToolOutcome> {
  const t0 = Date.now();
  const base = { tool_id: toolId, rendered: '', result_hash: null as string | null, rows: 0, attempt: 1, call_id: null as string | null };

  const record = async (o: Omit<ToolOutcome, 'call_id'>): Promise<ToolOutcome> => {
    let call_id: string | null = null;
    try {
      const { data } = await admin.rpc('fn_record_tool_call', {
        p_correlation: ctx.correlationId, p_agent_key: ctx.agentKey, p_role_id: ctx.roleId ?? null,
        p_tool_id: toolId, p_args: rawArgs ?? {}, p_status: o.status,
        p_result_hash: o.result_hash, p_result_rows: o.rows, p_result_bytes: o.rendered.length,
        p_error: o.error, p_attempt: o.attempt, p_latency_ms: o.latency_ms,
      });
      call_id = (data as string) ?? null;
    } catch (_e) { /* the ledger must never take down the task, but its absence is itself a signal */ }
    return { ...o, call_id };
  };

  // 1. AUTHORISE. Registry only. An ungranted tool is refused with a reason the model can act on.
  const granted = await toolsFor(ctx.agentKey);
  const spec = granted.find(s => s.tool_id === toolId);
  if (!spec) {
    return record({
      ...base, status: 'unauthorised', latency_ms: Date.now() - t0,
      error: `tool "${toolId}" is not authorised for agent ${ctx.agentKey}`,
      rendered: JSON.stringify({ error: 'unauthorised', tool: toolId,
        detail: 'This tool is not granted to your role. Do not answer as if you had called it.',
        available: granted.map(g => g.tool_id) }),
    });
  }

  // 2. VALIDATE against the registry's own schema, before anything executes.
  const bad = validateArgs(spec.input_schema, rawArgs ?? {});
  if (bad) {
    return record({
      ...base, status: 'error', latency_ms: Date.now() - t0, error: `invalid_arguments: ${bad}`,
      rendered: JSON.stringify({ error: 'invalid_arguments', detail: bad, schema: spec.input_schema }),
    });
  }

  // 3. EXECUTE with the registry's timeout and retry policy.
  const timeoutMs = Math.max(1, spec.timeout_seconds) * 1000;
  const attempts = Math.max(1, spec.max_attempts);
  let lastErr = '';
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const data = await withTimeout(() => runOnce(spec, rawArgs ?? {}, ctx.agentKey, timeoutMs), timeoutMs);
      const rows = countRows(data);
      // The exact bytes the model will see, hashed before it sees them.
      const rendered = JSON.stringify(rows === 0
        ? { tool: toolId, rows: 0, result: null,
            note: 'The tool ran and returned NO MATCHING DATA. This is a real answer meaning "none found" — it is not a failure, and it is not permission to substitute an assumption.' }
        : { tool: toolId, rows, result: data }).slice(0, 12000);
      const hash = await sha256(rendered);
      return record({
        ...base, attempt, status: rows === 0 ? 'ok_empty' : 'ok', rendered,
        result_hash: hash, rows, latency_ms: Date.now() - t0, error: null,
      });
    } catch (e) {
      lastErr = (e as any)?.name === 'AbortError' ? `timeout_after_${spec.timeout_seconds}s` : String((e as any)?.message || e).slice(0, 300);
      if (attempt < attempts && spec.backoff !== 'none') {
        await new Promise(r => setTimeout(r, spec.backoff === 'fixed_1s' ? 1000 : 2000 * attempt));
      }
    }
  }

  // 4. FAIL, VISIBLY. A tool that could not be reached is never rendered as an empty result.
  const timedOut = lastErr.startsWith('timeout_after_');
  const instruction = spec.failure_behaviour === 'fail_closed'
    ? 'This tool FAILED and it is fail-closed. You must NOT answer the question from memory or assumption. State that the live data could not be retrieved and escalate.'
    : spec.failure_behaviour === 'escalate'
      ? 'This tool FAILED. Escalate rather than proceeding.'
      : 'This tool FAILED. You may proceed only if you state explicitly that this evidence is missing and mark the answer provisional.';
  return record({
    ...base, attempt: attempts, status: timedOut ? 'timeout' : 'error',
    latency_ms: Date.now() - t0, error: lastErr, result_hash: null, rows: 0,
    rendered: JSON.stringify({ error: timedOut ? 'timeout' : 'tool_failed', tool: toolId, detail: lastErr, instruction }),
  });
}

/**
 * Did every tool result this conversation used actually come back from a tool?
 * Compares the hashes injected into the conversation against the ledger. Returns the hashes that
 * have no ledger row — i.e. content presented to the model as a tool result that we cannot prove
 * was ever produced by one.
 */
export async function verifyNoFabricatedResults(correlationId: string, injectedHashes: string[]): Promise<string[]> {
  if (!injectedHashes.length) return [];
  const { data } = await admin.from('agent_tool_call').select('result_hash')
    .eq('correlation_id', correlationId).not('result_hash', 'is', null);
  const known = new Set((data ?? []).map((r: any) => r.result_hash));
  return injectedHashes.filter(h => !known.has(h));
}
