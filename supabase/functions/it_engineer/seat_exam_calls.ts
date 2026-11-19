// THE WEEKLY SEAT EXAM'S TWO MODEL CALLS (it_engineer, 19 Nov 2026), moved out of index.ts so a test can send them through the
// real ai_gateway handler (the_judge_names_the_answering_model.test.ts). Both are fn knowledge_exam, the exam's own gateway
// credential, agent it_engineer, JSON, 15 s, an internal duty:
//   reword  task routine_employee_reasoning, temperature 0.9: a fresh wording of the question (seat_exam.ts REWORD_SYSTEM).
//   judge   task knowledge_validation, temperature 0, naming the model that wrote the answer as counterpart_model.
// WHY THE JUDGE NAMES THE AUTHOR. knowledge_validation is a review class (model_policy.reviews_class is non-empty), and
// ai_gateway/handle.ts refuses a review without the author's model (400 review_needs_counterpart) before choosing one: with
// it, fn_ai_route_review_for picks a reviewer outside the author's family from the class's own pair (qwen/qwen3.8-flash,
// then anthropic/claude-sonnet-5.5, then the review pool). Run 1 (15 Nov) sent it without one: 18 wording calls, 0 judge
// calls in the run window, and 13 right answers in other words were marked misses by the exact-phrase check alone.
import type { makeLlmRich as MakeLlmRich } from '../_shared/llm.ts';

export function examModelCalls(makeLlmRich: typeof MakeLlmRich) {
  const call = (taskClass: string, temperature: number) => makeLlmRich([], { fn: 'knowledge_exam', agent: 'it_engineer', taskClass,
    max: 400, timeoutMs: 15_000, json: true, temperature, internalDuty: true });
  const reworder = call('routine_employee_reasoning', 0.9);
  const judger = call('knowledge_validation', 0);
  return {
    reword: async (system: string, input: string) => {
      const r = await reworder(system, input, 400); return { content: r.content, error: r.error };
    },
    judge: async (system: string, input: string, authorModel: string) => {
      const r = await judger(system, input, 400, '', { counterpartModel: authorModel }); return { content: r.content, error: r.error };
    },
  };
}
