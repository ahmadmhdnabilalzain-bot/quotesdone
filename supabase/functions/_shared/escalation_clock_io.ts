// _shared/escalation_clock_io.ts — the live IO of escalation_clock.ts (customer_support + ceo, agent FOUNDER_CLOCK, 16 Nov 2026).
// The SQL doors (fn_escalation_clocks_due, fn_escalation_clock_ceo_decided / _ceo_failed, fn_escalation_clock_deliver,
// fn_escalation_clock_told) and ai_gateway: the CEO decides on its judgement class, customer_support writes on its reply class.
// The model client is imported only when a model is really asked, as review_request.ts does, so a tick with nothing due loads none.
// prevented by: _shared/escalation_clock.test.ts (the same path with a stub IO)
import { CEO_TASK_CLASS, type ClockIO, type DueClock, SUPPORT_TASK_CLASS } from './escalation_clock.ts';

type Admin = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }> };
const msg = (e: unknown) => String((e as { message?: string } | null)?.message ?? e);

export function liveClockIO(admin: Admin, fn = 'ceo_agent'): ClockIO {
  const ask = async (agent: 'ceo' | 'customer_support', taskClass: string, c: DueClock, system: string, input: string, max: number) => {
    const { makeLlmRich } = await import('./llm.ts');
    const call = makeLlmRich([], { fn, taskClass, agent, max, timeoutMs: 45_000, cacheTtlMin: 0, json: true, temperature: 0 });
    const res = await call(system, input, max, '', { subject: { escalation_clock: c.id, ...(c.channel === 'whatsapp' ? { channel: 'whatsapp' } : {}) } });
    return { content: res.content ?? null, model: res.model ?? null, error: res.error ?? null };
  };
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(name, args);
    if (error) throw new Error(name + ': ' + msg(error));
    return data;
  };
  return {
    due: async (limit) => ((await rpc('fn_escalation_clocks_due', { p_limit: limit })) ?? []) as DueClock[],
    askCeo: (c, system, input) => ask('ceo', CEO_TASK_CLASS, c, system, input, 600),
    decided: (id, d, model) => rpc('fn_escalation_clock_ceo_decided', { p_id: id, p_decision: d.decision, p_outcome: d.outcome, p_reasons: d.reasons,
      p_model: model, p_law: d.law, p_standing: d.standing }),
    ceoFailed: (id, error) => rpc('fn_escalation_clock_ceo_failed', { p_id: id, p_error: error }),
    write: (c, system, input) => ask('customer_support', SUPPORT_TASK_CLASS, c, system, input, 700),
    deliver: async (id, stage, subject, body) => {
      const r = (await rpc('fn_escalation_clock_deliver', { p_id: id, p_stage: stage, p_subject: subject, p_body: body })) as Record<string, unknown> | null;
      return { sent: r?.sent === true, via: (r?.via as string) ?? null, reason: (r?.reason as string) ?? null };
    },
    told: (id, stage, result, text) => rpc('fn_escalation_clock_told', { p_id: id, p_stage: stage, p_result: result, p_text: text }),
  };
}
