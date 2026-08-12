// boq_fixture_check — grades drawing_boq against a fixture set whose answers come from the
// drawings' own printed schedules.
//
// WHY THIS EXISTS. drawing_boq is a full UAE quantity-surveyor vision pipeline wired into five
// functions and proven by a successful call on 29 Jul, and NOTHING has ever checked whether what it
// produces is correct. KPI 103 (boq_analyst, "BOQ lines extracted correctly", target 95%) reads
// "extraction accuracy against the fixture set" and there was no fixture set, so an employee
// carried a target nobody could score and a protected capability could degrade in silence.
//
// THE RUNNER IS THE POINT, NOT THE TABLE. A fixture table with no runner is a set of expected
// answers nothing ever compares against — the "complete thing addressed to nobody" defect this
// estate keeps producing. The grading itself lives in fn_boq_fixture_score so the rule is one
// auditable place in SQL rather than buried in this file.
//
// It reads the drawing out of storage and posts it to drawing_boq exactly as a real caller would.
// It does NOT reach into the pipeline or stub any part of it: a fixture that exercises a shortcut
// grades the shortcut.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';

// drawing_boq is a vision call over a whole drawing; measured latency on this estate is tens of
// seconds, and the fixture set is small, so one at a time with a generous per-call wall.
const PER_CALL_MS = 120000;
const TIME_BUDGET_MS = 240000;

function b64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let s = '';
  // Chunked: String.fromCharCode(...bytes) blows the argument limit on a multi-hundred-KB drawing.
  for (let i = 0; i < bytes.length; i += 8192) s += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(s);
}

Deno.serve(async (req: Request) => {
  const started = Date.now();
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const auth = await requireInternal(admin, body?.__secret, 'boq_fixture_check');
    if (!auth.ok) return J({ error: 'unauthorized' }, 401);

    const { data: frozen } = await admin.from('app_secrets').select('key,value')
      .in('key', ['cos_frozen', 'ai_kill_switch']);
    if ((frozen || []).some((r: { value: string }) => String(r.value) === 'true')) {
      return J({ ok: true, frozen: true, graded: 0, note: 'AI execution is frozen; no fixture graded.' });
    }

    const { data: fixtures } = await admin.from('boq_fixture')
      .select('id,document_id,label,active').eq('active', true).order('id');
    if (!fixtures?.length) return J({ ok: true, graded: 0, note: 'no active fixtures' });

    const secret = body?.__secret as string;
    const out: unknown[] = [];

    for (const f of fixtures) {
      if (Date.now() - started > TIME_BUDGET_MS) break;
      let actual: Record<string, unknown> | null = null;
      let err = '';
      try {
        const { data: doc } = await admin.from('documents')
          .select('bucket,path,file_name,mime').eq('id', f.document_id).maybeSingle();
        if (!doc) throw new Error('document ' + f.document_id + ' is gone');

        const dl = await admin.storage.from(doc.bucket).download(doc.path);
        if (dl.error || !dl.data) throw new Error('storage: ' + (dl.error?.message ?? 'no file at ' + doc.path));

        const r = await fetch(FN + '/drawing_boq', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, file_b64: b64(await dl.data.arrayBuffer()),
                                 mime: doc.mime, filename: doc.file_name }),
          signal: AbortSignal.timeout(PER_CALL_MS),
        });
        const j = await r.json().catch(() => ({}));
        if (!r.ok) throw new Error('drawing_boq HTTP ' + r.status + ': ' + JSON.stringify(j).slice(0, 200));
        // drawing_boq wraps its analysis one level down: {ok, boq:{drawing_type, category,
        // summary, total_area_sqm, boq:[line items]}}. So `j.boq` is the ANALYSIS OBJECT and the
        // line items are at `j.boq.boq`. Caught on the first real grading run, which reported
        // "returned no boq array" while the pipeline had in fact answered correctly — both
        // summaries named the right built-up area. Unwrap whichever level carries the array.
        const cand = [j?.boq, j?.result, j] as Record<string, unknown>[];
        actual = cand.find((c) => c && Array.isArray((c as Record<string, unknown>)?.boq)) ?? null;
        if (!actual) {
          throw new Error('drawing_boq returned no boq array at j.boq.boq, j.result.boq or j.boq: '
            + JSON.stringify(j).slice(0, 200));
        }
      } catch (e) {
        err = String((e as Error)?.message ?? e).slice(0, 400);
      }

      // A FAILED GRADING IS RECORDED AS ok=false, NOT AS 0%. The KPI averages only ok runs, so an
      // unreachable pipeline reads as "not measured this cycle" rather than as an employee scoring
      // zero. Those are different facts and the difference is the whole point of this file.
      if (err) {
        await admin.from('boq_fixture_run').insert({ fixture_id: f.id, ok: false, error: err });
        out.push({ fixture: f.id, ok: false, error: err });
        continue;
      }

      const { data: scored, error: sErr } = await admin.rpc('fn_boq_fixture_score',
        { p_fixture_id: f.id, p_actual: actual });
      if (sErr) {
        await admin.from('boq_fixture_run').insert({ fixture_id: f.id, ok: false, error: sErr.message, actual });
        out.push({ fixture: f.id, ok: false, error: sErr.message });
        continue;
      }
      const s = scored as Record<string, unknown>;
      await admin.from('boq_fixture_run').insert({
        fixture_id: f.id, ok: true, checked: Number(s.checked ?? 0), matched: Number(s.matched ?? 0),
        score_pct: s.score_pct ?? null, actual, detail: s.detail ?? null });
      out.push({ fixture: f.id, label: f.label, ok: true, score_pct: s.score_pct,
                 checked: s.checked, matched: s.matched, boq_lines: s.boq_lines });
    }

    const graded = out.filter((o) => (o as Record<string, unknown>).ok).length;
    const scores = out.filter((o) => (o as Record<string, unknown>).ok)
      .map((o) => Number((o as Record<string, unknown>).score_pct)).filter((n) => Number.isFinite(n));
    const avg = scores.length ? Math.round((scores.reduce((a, b) => a + b, 0) / scores.length) * 100) / 100 : null;

    await admin.from('agent_runs').insert({
      agent: 'boq_fixture_check',
      status: graded > 0 ? 'ok' : 'error',
      counts: { fixtures: fixtures.length, graded, failed: fixtures.length - graded, avg_score_pct: avg },
      note: graded > 0
        ? 'graded ' + graded + ' of ' + fixtures.length + ' fixture(s), mean accuracy ' + avg + '%'
        : 'NO FIXTURE COULD BE GRADED: ' + String((out[0] as Record<string, unknown>)?.error ?? 'unknown')
          + ' — KPI 103 keeps its previous value rather than reading 0%.',
      started_at: new Date(started).toISOString(), finished_at: new Date().toISOString(),
    });

    return J({ ok: true, graded, avg_score_pct: avg, results: out });
  } catch (e) {
    return J({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
