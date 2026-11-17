// A virtual clock for the redaction's timing tests (moved out of a_drawing_is_checked_inside_its_request.test.ts on 17 Nov
// 2026, when every_page_is_verified_in_time.test.ts needed it too). sleep(ms) waits on the clock; run() moves the clock to
// the next timer once every waiting call has registered, so minutes of edge time run in milliseconds, the same way each run.
export function virtualClock(t0 = 0) {
  let t = t0; const timers: { at: number; go: () => void }[] = [];
  const sleep = (ms: number) => new Promise<void>((go) => timers.push({ at: t + ms, go }));
  async function run<T>(p: Promise<T>): Promise<T> {
    let done = false, val: T | undefined, err: unknown = null;
    p.then((v) => { done = true; val = v; }, (e) => { done = true; err = e; });
    while (!done) {
      await new Promise((r) => setTimeout(r, 0));
      if (done || !timers.length) continue;
      const at = Math.min(...timers.map((x) => x.at)); t = at;
      for (const x of timers.filter((y) => y.at === at)) { timers.splice(timers.indexOf(x), 1); x.go(); }
    }
    if (err) throw err;
    return val as T;
  }
  return { now: () => t, sleep, run };
}
export type VirtualClock = ReturnType<typeof virtualClock>;
