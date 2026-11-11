// _shared/load_stub.ts — the LOAD-TEST model stub (it_engineer, 11 Nov 2026; founder ruling 1622, ruling 1606).
//
// WHY IT EXISTS. Ruling 1622: "scalable — e.g. 100 customers chatting at the same time must not crash the company."
// A chat turn is mostly the model's 6-10 s, so a load test of the chat path must hold 100 turns open for that long, but
// it may spend nothing (ruling 1606: no paid upgrades, no model money) and may reach no real person. The existing
// no-spend answer (spend_guards: fixture_no_spend, HTTP 503) is the OUTAGE shape: every caller takes its deterministic
// outage path at once, so a load test on it measures a different, much shorter turn. This module answers instead with a
// canned completion after a realistic delay, in the same JSON or SSE shape OpenRouter gives, so the caller's whole happy
// path (the reply checks, the conversation write, the logs) runs, and the gateway's own pre-call work (auth, rate limit,
// FAQ level 0, routing, cache lookup and its embedding) runs before it. The provider is never called.
//
// WHO GETS IT — ALL FOUR, OR NOBODY (loadStubVerdict, pinned by ai_gateway/load_stub.test.ts):
//   1. a PROVEN run tag on this request (e2e_run.ts: the service-role bearer or the internal secret; a bare header is
//      dropped before this code sees it, so a visitor who types the header gets the normal path);
//   2. that tag's OPEN rehearsal_window row (ended_at null, expires_at in the future) that was opened BY 'load_test';
//   3. that window has models_allowed = FALSE — a load window can never be the paid kind (ruling 1260's windows are
//      models_allowed = true and keep reaching the model exactly as before);
//   4. the request names no subject, or names one the database calls a fixture. A real subject, or a fixture check that
//      fails or gives no answer, is REFUSED (503 load_stub_refused) — never stubbed, never sent to the model.
// A real customer's request carries no proven tag (1), so this code returns 'normal' for it before reading anything.
//
// WHAT IT DOES NOT DO. It records no llm_attempt and touches no breaker (llm_route_health): a stub success must never
// close a breaker that is open for real traffic. It writes one fn_llm_log row (model 'load_stub', cost 0) so the run's
// ai_cost_log sum is a measurement (must be 0), not an assumption.

export const LOAD_OPENER = 'load_test';
export const LOAD_MODEL = 'load_stub';
export const DEFAULT_DELAY_MS: [number, number] = [6000, 10000];
const MAX_DELAY_MS = 20000;

export type LoadWindow = {
  opened_by?: string | null; models_allowed?: boolean | null; ended_at?: string | null;
  expires_at?: string | null; note?: string | null;
} | null;
/** What the fixture check said about the request's subject: none named, a fixture, a real one, or no usable answer. */
export type SubjectVerdict = 'none' | 'fixture' | 'real' | 'unknown';
export type LoadVerdict = { mode: 'normal' } | { mode: 'stub'; delay: [number, number] } | { mode: 'refuse'; why: string };

/** The delay range a window asks for in its note ("delay_ms=6000-10000"), clamped; the default otherwise. */
export function delayRange(note: string | null | undefined): [number, number] {
  const m = /delay_ms=(\d{1,5})-(\d{1,5})/.exec(String(note || ''));
  if (!m) return DEFAULT_DELAY_MS;
  const lo = Math.min(Number(m[1]), MAX_DELAY_MS), hi = Math.min(Number(m[2]), MAX_DELAY_MS);
  return lo <= hi ? [lo, hi] : DEFAULT_DELAY_MS;
}

/** Is this window a load-test window that is open now? Pure, so the fence test can pin every clause. */
export function isOpenLoadWindow(w: LoadWindow, now = Date.now()): boolean {
  if (!w || typeof w !== 'object') return false;
  if (w.opened_by !== LOAD_OPENER) return false;
  if (w.models_allowed !== false) return false;          // only an explicit false: null or true is not a load window
  if (w.ended_at) return false;
  const exp = Date.parse(String(w.expires_at || ''));
  return Number.isFinite(exp) && exp > now;
}

/** The whole rule (header comment). `tag` is e2eRunTag(), which is non-null only for a PROVEN tag. */
export function loadStubVerdict(tag: string | null, w: LoadWindow, windowErr: unknown, subject: SubjectVerdict, now = Date.now()): LoadVerdict {
  if (!tag) return { mode: 'normal' };
  if (windowErr || !isOpenLoadWindow(w, now)) return { mode: 'normal' };
  if (subject === 'real') return { mode: 'refuse', why: 'a load-test run named a subject that is not a fixture' };
  if (subject === 'unknown') return { mode: 'refuse', why: 'a load-test run named a subject the fixture check could not answer for' };
  return { mode: 'stub', delay: delayRange(w!.note) };
}

/** fixtureVerdict-shaped data -> SubjectVerdict. Fails closed: anything but an explicit yes/no is 'unknown'. */
export function subjectVerdictOf(named: boolean, data: unknown, error: unknown): SubjectVerdict {
  if (!named) return 'none';
  if (error || !data || typeof data !== 'object') return 'unknown';
  const f = (data as { fixture?: unknown }).fixture;
  return f === true ? 'fixture' : f === false ? 'real' : 'unknown';
}

export const pickDelay = ([lo, hi]: [number, number], rnd = Math.random) => Math.round(lo + (hi - lo) * rnd());

// The canned words. No money figure, no rate, no supplier, nothing a reply check refuses (brief_answer.ts problems()),
// so the caller's happy path runs to the end. A caller that asked for JSON gets a JSON object it can parse.
export const CANNED_TEXT = 'Thank you, this is a sandbox load-test reply. A real answer would be written here. Is there anything else about the job you can tell me?';
// IN THE CONVERSATION'S LANGUAGE (it_engineer, 11 Nov 2026). The first stubbed chat run (01:26-01:30 UTC) answered every
// turn in English, so each Arabic conversation (one of the driver's eight questions) failed the widget's language check
// on every draft and walked the whole model ladder: 14 of its 139 turns were HTTP 503 no_answer after 35-54 s. That
// measured the stub, not the chat path: a model asked to "Reply in Arabic" answers in Arabic. The stub now does too.
export const CANNED_TEXT_AR = 'شكرًا لك، هذا رد تجريبي من اختبار التحميل. هنا تُكتب الإجابة الحقيقية. هل هناك أي شيء آخر عن العمل يمكنك إخباري به؟';
/** The reply language a caller asked for: its rules' "Reply in …" line, else the script of the latest user message. */
export function cannedLang(sys: string, input: unknown): 'en' | 'ar' {
  const s = String(sys || '');
  if (/\bReply in Arabic\b/i.test(s)) return 'ar';
  if (/\bReply in (?:UAE )?English\b/i.test(s)) return 'en';
  const msgs = Array.isArray(input) ? input as { role?: unknown; content?: unknown }[] : [];
  const last = [...msgs].reverse().find((m) => m?.role === 'user');
  const t = typeof last?.content === 'string' ? last.content : '';
  const ar = (t.match(/[؀-ۿ]/g) ?? []).length, la = (t.match(/[A-Za-z]/g) ?? []).length;
  return ar > la ? 'ar' : 'en';
}
export function cannedContent(wantsJson: boolean, lang: 'en' | 'ar' = 'en'): string {
  const text = lang === 'ar' ? CANNED_TEXT_AR : CANNED_TEXT;
  return wantsJson ? JSON.stringify({ load_stub: true, answer: text, reply: text }) : text;
}

/** The SSE body OpenRouter would stream: one delta per sentence spread over the delay, then usage at cost 0, then [DONE]. */
export function cannedStream(text: string, delayMs: number): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  // the Arabic question mark ends a sentence too: without it the Arabic reply's last sentence was never streamed
  const parts = text.match(/[^.?!؟]+(?:[.?!؟]+\s*|$)/g)?.filter((p) => p.trim()) ?? [text];
  const gap = Math.max(0, Math.floor(delayMs / (parts.length + 1)));
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  return new ReadableStream<Uint8Array>({
    async start(c) {
      await sleep(gap);                                   // the time to the first token
      for (const p of parts) {
        c.enqueue(enc.encode('data: ' + JSON.stringify({ id: 'gen-load-stub', choices: [{ index: 0, delta: { content: p } }] }) + '\n\n'));
        await sleep(gap);
      }
      c.enqueue(enc.encode('data: ' + JSON.stringify({ id: 'gen-load-stub', choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
        usage: { prompt_tokens: 0, completion_tokens: 0, cost: 0 } }) + '\n\n'));
      c.enqueue(enc.encode('data: [DONE]\n\n'));
      c.close();
    },
  });
}

/**
 * The limiter scope of a widget turn (site_assistant). A load run's buckets live under 'load:<tag>:', so its traffic
 * never spends the real visitors' per-address buckets or the global daily ceiling; everyone else is unchanged.
 */
// A LOAD RUN'S VIRTUAL USER IS ONE PERSON TO THE LIMITER (it_engineer, 11 Nov 2026, load test round 4). The per-address
// buckets are keyed by the address the PLATFORM saw (the first x-forwarded-for entry is the real client address, not the
// one a client sends): the 04:28 UTC run's rl_hits keys read 'site_assistant_ipconv:load:<tag>:160.79.106.x', the session's
// 39 egress addresses, although the driver sent 198.18.0.<vu>. So 100 virtual users shared ~35 addresses, each met the real
// 10-new-conversations-an-hour cap, and 30 first turns (11.9%) were refused, 20 of them by users on their very first
// conversation. Inside a PROVEN load run only (loadTag is non-null only for a proven tag and an open load window), the
// driver's per-user label (x-qd-load-vu) is added to the key, so each virtual user spends its own buckets, as one visitor
// would. Untagged traffic never reads the header, so a real visitor's buckets are exactly as before.
// prevented by: _shared/load_stub.test.ts (limiterScope)
const VU_LABEL = /^[a-z0-9-]{1,32}$/;
export function limiterScope(ip: string, loadTag: string | null, vu: string | null = null): { ip: string; globalKey: string } {
  if (!loadTag) return { ip, globalKey: 'site_assistant_global_day' };
  const who = vu && VU_LABEL.test(vu) ? ip + ':' + vu : ip;
  return { ip: 'load:' + loadTag + ':' + who, globalKey: 'load:' + loadTag + ':site_assistant_global_day' };
}
/** Every rl_hits key a load run spends: the bucket name comes FIRST ('site_assistant_ipconv:load:<tag>:...'), so a
 *  'load:<tag>:%' pattern found only the global bucket and every run before 11 Nov 2026 04:30 UTC left the rest behind
 *  (486, 469, 788 and 1,347 rows for the four runs that day). The teardown and its leftover count use this one pattern. */
export const loadLimiterKeys = (tag: string): string => '%load:' + tag + ':%';

// deno-lint-ignore no-explicit-any
type Admin = { from: (t: string) => any };
/** The newest open window row for a run tag; read only after the tag is proven. */
export async function loadWindowOf(admin: Admin, tag: string): Promise<{ data: LoadWindow; error: unknown }> {
  try {
    const { data, error } = await admin.from('rehearsal_window')
      .select('opened_by,models_allowed,ended_at,expires_at,note')
      .eq('run_tag', 'qd_run:' + tag).is('ended_at', null)
      .order('id', { ascending: false }).limit(1).maybeSingle();
    return { data: (data ?? null) as LoadWindow, error };
  } catch (e) { return { data: null, error: e }; }
}

/** For a caller other than the gateway (site_assistant's own limiter): is this proven tag an open load run? */
export async function isLoadRun(admin: Admin, tag: string | null): Promise<boolean> {
  if (!tag) return false;
  const { data, error } = await loadWindowOf(admin, tag);
  return !error && isOpenLoadWindow(data);
}
