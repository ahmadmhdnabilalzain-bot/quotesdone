// The blog duty: draft, CEO review, revise (split out of duties.ts, 9 Nov 2026; a pure move).
import { makeLlmRich } from '../../_shared/llm.ts';
import { modelHeld } from '../../_shared/llm_hold.ts';
import { acceptArticle, acceptReview, type Criterion, draftPrompt, type DraftTopic, MAX_REVISE_ROUNDS, revisePrompt, type ReviseRound, reviewPrompt,
  type ReviewRound } from '../../_shared/marketing_articles.ts';
import { sha256 } from './shared.ts';
import type { Duty, DutyContext } from './types.ts';

// ── THE BLOG: A MARKET TOPIC, DRAFTED BY MARKETING, REVIEWED BY THE CEO SEAT UNTIL USEFUL (founder 1058, 1059) ────
// scripts/sql/a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql holds the topic, the rounds and
// the rules. Three model steps in ONE duty (blog_article, one call a beat): article_draft (the open topic -> round 1), article_review (the CEO seat's
// six-criterion decision on a round, routed to a family other than the draft's) and article_revise (a new version
// answering every failed reason -> the next round). The founder is never asked; he is told when one goes live.
//
// ONE PAID CALL PER ATTEMPT, NEVER ONE PER BEAT (release review of #1114). A refused or failed step - the code gate,
// the database (e.g. text_lost_its_script, a supplier named, a reasonless decision) or no answer - is written to
// marketing_model_run BEFORE it is raised, under a subject that is the job's key plus a hash of everything the model
// was given. A key with a failed run today is not called again that Dubai day; the next day's attempt carries every
// earlier refusal, so it is new content with the lesson in it. After 3 refusals of a draft or a revision the topic is
// replaced (fn_marketing_blog_topic_replace) and the next topic carries the lesson: the cycle never spins and never
// stops. Before this, a refused ingest threw before any row existed and every 30-minute beat paid for the same
// ~8k-token redraw (up to ~48 GPT-class calls a day).
// Prevented by: supabase/functions/marketing/duties.test.ts (a refused write: one failed row, ZERO calls next beat).
export interface ModelAnswer { content: string | null; error?: string | null; truncated?: boolean; model?: string | null }
export interface ModelJob {
  step: 'article_draft' | 'article_review' | 'article_revise';
  seat: 'marketing' | 'ceo';
  taskClass: string;
  max: number;
  counterpart?: string | null;   // the model that wrote what this call reviews (ai_gateway routes to another family)
  key: string;                   // the thing the job is about: topic:<id>, round:<id>, revise:<article>:<round>
  label: string;
  content: unknown;              // everything the model is given; with the earlier refusals, the run's subject
  prompt(refused: string[]): string;
  accept(answer: string | null, truncated: boolean): { ok: true; value: unknown } | { ok: false; reason: string };
  write(value: unknown, model: string | null): Promise<{ ok: boolean; reason?: string }>;
  giveUp?(refused: string[]): Promise<void>;
}
export interface FailedRun { subject: string; reason: string | null; run_day: string }
export interface JobIO {
  failedRuns(job: ModelJob): Promise<FailedRun[]>;   // oldest first
  held(): Promise<boolean>;
  callModel(job: ModelJob, prompt: string): Promise<ModelAnswer>;
  recordFailed(job: ModelJob, subject: string, reason: string, model: string | null): Promise<void>;
}
const NO_ANSWER = 'no answer: ';
export const GIVE_UP_AFTER = 3;

/** Runs the first job that may run: at most ONE model call. */
export async function runOneJob(jobs: ModelJob[], today: string, io: JobIO): Promise<Record<string, unknown>> {
  if (!jobs.length) return { due: false };
  const waiting: string[] = [];
  for (const job of jobs) {
    const failed = await io.failedRuns(job);
    if (failed.some((f) => f.run_day === today)) { waiting.push(job.label); continue; }   // one failed attempt a Dubai day
    const refused = failed.map((f) => f.reason || '').filter((r) => r && !r.startsWith(NO_ANSWER));
    if (job.giveUp && refused.length >= GIVE_UP_AFTER) {
      await job.giveUp(refused);
      return { due: true, step: job.step, gave_up: job.label, refused: refused.length };
    }
    if (await io.held()) return { due: true, held: true, step: job.step, job: job.label, reason: 'the founder\'s model hold: it waits' };
    const subject = job.key + '#' + (await sha256(JSON.stringify([job.content, refused]))).slice(0, 16);
    let a: ModelAnswer;
    try { a = await io.callModel(job, job.prompt(refused)); } catch (e) { a = { content: null, error: String((e as Error)?.message || e) }; }
    const model = a.model ?? null;
    let reason: string | null = a.error ? NO_ANSWER + a.error : null;
    if (!reason) {
      const r = job.accept(a.content, !!a.truncated);
      if (!r.ok) reason = r.reason;
      else {
        const w = await job.write(r.value, model);
        if (!w.ok) reason = 'refused when written: ' + (w.reason || 'no reason given');
      }
    }
    if (!reason) return { due: true, step: job.step, done: job.label, model };
    await io.recordFailed(job, subject, reason, model);   // before the raise: the next beat reads it and does not call
    throw new Error(job.step + ' "' + job.label + '" failed: ' + reason);
  }
  return { due: true, waiting, reason: 'each was refused today; the next attempt, with its refusal, is tomorrow' };
}

const dubaiDay = (now: Date) => new Date(now.getTime() + 4 * 3600_000).toISOString().slice(0, 10);
function jobIO(ctx: DutyContext): JobIO {
  const today = dubaiDay(ctx.now);
  return {
    failedRuns: async (job) => {
      const { data, error } = await ctx.admin.from('marketing_model_run').select('subject, reason, run_day')
        .eq('step', job.step).eq('outcome', 'failed').like('subject', job.key + '#%').order('id', { ascending: true }).limit(200);
      if (error) throw new Error('marketing_model_run: ' + error.message);   // unreadable: never call the model blind
      return (data || []) as FailedRun[];
    },
    held: () => modelHeld(ctx.admin),
    callModel: async (job, prompt) => {
      // never past the beat's budget (index.ts runDuties MARKETING_BEAT_BUDGET_MS, review of 12 Nov 2026); 45 s otherwise, as before
      const timeoutMs = ctx.deadline ? Math.max(1_000, Math.min(45000, ctx.deadline - Date.now())) : 45000;
      const llm = makeLlmRich(undefined, { fn: 'marketing', taskClass: job.taskClass, dept: 'marketing', agent: job.seat, max: job.max, timeoutMs, temperature: 0.2 });
      const r = await llm('', '', job.max, '', { messages: [{ role: 'user', content: prompt }], ...(job.counterpart ? { counterpartModel: job.counterpart } : {}) });
      return { content: r.content, error: r.error, truncated: r.truncated, model: r.model ?? null };
    },
    recordFailed: async (job, subject, reason, model) => {
      const { error } = await ctx.admin.from('marketing_model_run').insert({ step: job.step, subject, seat: job.seat,
        task_class: job.taskClass, outcome: 'failed', reason: reason.slice(0, 1000), model, run_day: today });
      if (error) throw new Error('the refused step could not be recorded (' + error.message + '): ' + reason);
    },
  };
}
async function rpcOk(ctx: DutyContext, fn: string, args: Record<string, unknown>): Promise<{ ok: boolean; reason?: string }> {
  const w = await ctx.admin.rpc(fn, args);
  const out = w.data as { ok?: boolean; error?: string; detail?: string } | null;
  return w.error || !out?.ok ? { ok: false, reason: fn + ': ' + (w.error?.message || [out?.error, out?.detail].filter(Boolean).join(' - ') || JSON.stringify(out)) } : { ok: true };
}
async function due<T>(ctx: DutyContext, fn: string): Promise<T[]> {
  const { data, error } = await ctx.admin.rpc(fn);
  if (error) throw new Error(fn + ': ' + error.message);
  return (data || []) as T[];
}
const replaceTopic = async (ctx: DutyContext, topicId: number, why: string) => {
  const { data, error } = await ctx.admin.rpc('fn_marketing_blog_topic_replace', { p_topic_id: topicId, p_reason: why.slice(0, 1900) });
  if (error || (data as { replaced?: boolean } | null)?.replaced !== true) {
    throw new Error('fn_marketing_blog_topic_replace: topic ' + topicId + ' was not replaced: ' + (error?.message || JSON.stringify(data)));
  }
};
type Gated = Extract<ReturnType<typeof acceptArticle>, { ok: true }>;

export function draftJob(ctx: DutyContext, t: DraftTopic): ModelJob {
  return {
    step: 'article_draft', seat: 'marketing', taskClass: 'marketing_article_draft', max: 8000,
    key: 'topic:' + t.topic_id, label: t.title, content: t,
    prompt: (r) => draftPrompt(t, r),
    accept: (ans, tr) => { const x = acceptArticle({ sources: t.sources, prior: null, failed: [] }, ans, tr); return x.ok ? { ok: true, value: x } : x; },
    write: (v, model) => { const g = v as Gated; return rpcOk(ctx, 'fn_marketing_blog_submit', { p: { topic_id: t.topic_id, slug: g.slug, en: g.article.en, ar: g.article.ar, post: g.post, model } }); },
    giveUp: (r) => replaceTopic(ctx, t.topic_id, `${GIVE_UP_AFTER} drafts were refused: ` + r.join(' | ')),
  };
}
export function reviewJob(ctx: DutyContext, r: ReviewRound & { article_id: number }): ModelJob {
  return {
    step: 'article_review', seat: 'ceo', taskClass: 'ceo_article_review', max: 4000, counterpart: r.drafted_by_model,
    key: 'round:' + r.round_id, label: r.slug + ' round ' + r.round, content: r,
    prompt: (x) => reviewPrompt(r, x),
    accept: (ans, tr) => { const x = acceptReview(ans, tr, r.revise_rounds < MAX_REVISE_ROUNDS); return x.ok ? { ok: true, value: x } : x; },
    write: (v, model) => {
      const d = v as Extract<ReturnType<typeof acceptReview>, { ok: true }>;
      return rpcOk(ctx, 'fn_marketing_blog_review', { p_round_id: r.round_id, p_decision: d.decision, p_reasons: d.reasons, p_model: model });
    },
  };
}
export function reviseJob(ctx: DutyContext, d: ReviseRound): ModelJob {
  const failed = (Object.keys(d.reasons || {}) as Criterion[]).filter((k) => d.reasons[k]?.verdict === 'fail');
  return {
    step: 'article_revise', seat: 'marketing', taskClass: 'marketing_article_revise', max: 8000,
    key: `revise:${d.article_id}:${d.round}`, label: d.slug + ' after round ' + d.round, content: d,
    prompt: (r) => revisePrompt(d, r),
    accept: (ans, tr) => { const x = acceptArticle({ sources: d.sources, prior: d.version, failed, slug: d.slug }, ans, tr); return x.ok ? { ok: true, value: x } : x; },
    write: (v, model) => {
      const g = v as Gated;
      return rpcOk(ctx, 'fn_marketing_blog_submit', { p: { topic_id: d.topic_id, en: g.article.en, ar: g.article.ar, post: g.post, changes: g.changes, model } });
    },
    giveUp: (r) => replaceTopic(ctx, d.topic_id, `${GIVE_UP_AFTER} revisions after round ${d.round} were refused: ` + r.join(' | ')),
  };
}

// ONE blog duty, so a beat makes at most ONE of these calls (each up to 45 s; the 55 s heartbeat must not be outrun):
// the CEO's review of a waiting round first, then a revision, then a new draft - work in flight finishes before new
// work starts. The CEO seat's review runs on the marketing seat's beat, as seat_deliberation runs a reviewer on
// resilience_ping's: the call is made as agent 'ceo' and charged to marketing, whose work it reviews.
export const blogArticle: Duty = {
  name: 'blog_article', owner_seat: 'marketing',
  async run(ctx) {
    const jobs = [
      ...(await due<ReviewRound & { article_id: number }>(ctx, 'fn_marketing_blog_review_due')).map((r) => reviewJob(ctx, r)),
      ...(await due<ReviseRound>(ctx, 'fn_marketing_blog_revise_due')).map((d) => reviseJob(ctx, d)),
      ...(await due<DraftTopic>(ctx, 'fn_marketing_blog_draft_due')).map((t) => draftJob(ctx, t)),
    ];
    return runOneJob(jobs, dubaiDay(ctx.now), jobIO(ctx));
  },
};
