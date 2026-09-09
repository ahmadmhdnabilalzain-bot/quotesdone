// ceo_agent — the CEO seat's runtime. The founder's instructions arrive here, and the CEO's
// decisions leave from here.
//
// WHY IT EXISTS. Until now the CEO seat had tools and no runtime: fn_ceo_request_decision,
// fn_ceo_decide_refund, fn_ceo_standing and the rest existed in the database with nothing able to
// call them, and function_owner recorded 0 edge functions owned by 'ceo'. The founder's only way to
// issue a command was os_api's secretary_chat, which belongs to the OS dashboard he has ruled
// irrelevant and which is being deleted. Deleting os_api before this existed would have left him
// with no command channel at all — his WhatsApp fallback already 404s on an agent_brain that is not
// deployed.
//
// Founder, 8 September 2026: "for the new CEO we will build proper tables and edge functions and
// everything. we dont rely on the old structure." So this shares nothing with secretary_act: no
// department dashboards, no ask_agent, no objective routing, no Postiz. Two seats, one website.
//
// NO MODEL CALL, ANYWHERE IN HERE, and that is a design decision rather than a limitation. Every
// route in llm_route_health is open_until 2126 under the founder's own hold, so a model-dependent
// command channel would be a dead one today. More importantly: an instruction from the founder must
// route the same way twice, cost nothing to route, and be explainable by pointing at the row that
// matched. fn_ceo_classify is a pattern table and a rank. The model's judgement belongs in HOW the
// work is done, not in whether he was understood.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// WHO IS ASKING. Three ways in, and each one is named in the record rather than collapsed into a
// single "authenticated" boolean — a command channel whose log cannot say who spoke is a channel
// that cannot be audited later.
//
//   'founder'  the shared/scoped internal credential, or his admin JWT. He may command.
//   'ceo'      the CEO seat acting on its own behalf (deciding, closing its own tasks).
//   null       refused.
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. Until 9 Sep 2026 this read
// `body?.as === 'ceo' ? 'ceo' : 'founder'` — the caller declared which seat it spoke for and was
// believed. Any holder of a credential scoped to ceo_agent could therefore present as the CEO and
// use `decide`, which writes ceo_approval. That is the confused-deputy shape: authentication proved
// the caller was internal, and then the caller was allowed to choose its own authority.
//
// The seat is now derived from internal_credential.context, which the caller cannot influence — it
// is looked up in the database from the secret's hash. An unrecognised context is refused rather
// than defaulted, so minting a new credential does not silently grant a seat: it has to be added
// here deliberately.
const SEAT_BY_CREDENTIAL: Record<string, 'founder' | 'ceo'> = {
  'fn.founder_channel': 'founder', // his WhatsApp, email and API channel
};

async function whoami(req: Request, body: Record<string, unknown>): Promise<'founder' | 'ceo' | null> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'ceo_agent');
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ?? null;
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return allow.includes(email) ? 'founder' : null;
}

Deno.serve(observe('ceo_agent', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const who = await whoami(req, body);
    if (!who) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    // ── COMMAND ────────────────────────────────────────────────────────────────────────────────
    // The founder says something; it is classified, recorded, and becomes work if it asks for work.
    // He is never asked to confirm it, and never asked to phrase it differently: an instruction the
    // pattern table does not recognise still creates a task, because unrecognised is a reason for
    // the seat to think rather than a reason to stop.
    if (action === 'command') {
      if (who !== 'founder') return J({ error: 'only the founder issues commands' }, 403);
      const text = String(body.text || body.message || '').trim();
      if (!text) return J({ error: 'empty_instruction' }, 400);
      const channel = ['whatsapp', 'email', 'api', 'console'].includes(String(body.channel))
        ? String(body.channel) : 'api';
      const { data, error } = await admin.rpc('fn_ceo_command_submit', {
        p_channel: channel, p_from: 'founder', p_body: text,
      });
      if (error) return J({ error: error.message }, 500);
      const r = Array.isArray(data) ? data[0] : data;
      return J({ ok: true, command_id: r?.command_id, intent: r?.intent_id, state: r?.state, matched: r?.matched });
    }

    // ── INBOX ──────────────────────────────────────────────────────────────────────────────────
    // What the seat is carrying. Open work, open commands, and the refunds waiting on a decision.
    if (action === 'inbox') {
      const [cmds, tasks, refunds] = await Promise.all([
        admin.from('ceo_command')
          .select('command_id,received_at,channel,body,intent_id,state')
          .not('state', 'in', '("completed","failed","cancelled","superseded","refused")')
          .order('received_at', { ascending: false }).limit(25),
        admin.from('ceo_task')
          .select('task_id,command_id,title,state,blocked_reason,created_at')
          .in('state', ['open', 'working', 'blocked'])
          .order('created_at', { ascending: true }).limit(50),
        admin.from('refunds')
          .select('id,amount_fils,reason_code,requested_by,requested_at,within_auto_window')
          .eq('status', 'requested').order('requested_at', { ascending: true }).limit(25),
      ]);
      return J({
        ok: true,
        commands: cmds.data || [],
        tasks: tasks.data || [],
        refunds_awaiting_decision: refunds.data || [],
      });
    }

    // ── TASK ───────────────────────────────────────────────────────────────────────────────────
    // The database refuses a task marked done without evidence, or blocked without a reason. That
    // refusal is not caught and smoothed over here: it is returned verbatim, because the whole point
    // of the constraint is that the seat cannot quietly close its own work.
    if (action === 'task') {
      const id = Number(body.task_id);
      if (!Number.isFinite(id)) return J({ error: 'task_id_required' }, 400);
      const patch: Record<string, unknown> = {};
      if (body.state) patch.state = String(body.state);
      if (body.evidence !== undefined) patch.evidence = String(body.evidence || '');
      if (body.blocked_reason !== undefined) patch.blocked_reason = String(body.blocked_reason || '');
      if (patch.state === 'done' || patch.state === 'abandoned') patch.closed_at = new Date().toISOString();
      if (!Object.keys(patch).length) return J({ error: 'nothing_to_change' }, 400);
      const { data, error } = await admin.from('ceo_task').update(patch).eq('task_id', id)
        .select('task_id,state,evidence,blocked_reason').maybeSingle();
      if (error) return J({ ok: false, refused: error.message }, 400);
      return J({ ok: true, task: data });
    }

    // ── DECIDE ─────────────────────────────────────────────────────────────────────────────────
    // Founder ruling, 8 September 2026: "all approvals are from CEO. nothing goes to me." So this is
    // the CEO deciding, not the founder being asked. The decision is written to ceo_approval and, for
    // a refund, the refund row is pointed at it — the guards on public.refunds refuse the money
    // moving any other way, so this endpoint cannot approve a payment by itself even if it wanted to.
    if (action === 'decide') {
      const kind = String(body.subject_kind || 'refund');
      const subject = String(body.subject_id || '').trim();
      const decision = String(body.decision || '').trim();
      const rationale = String(body.rationale || '').trim();
      if (!subject) return J({ error: 'subject_id_required' }, 400);
      if (decision !== 'approved' && decision !== 'refused') return J({ error: 'decision_must_be_approved_or_refused' }, 400);
      // A decision with no reasoning is a rubber stamp, and a register full of rubber stamps cannot
      // be reviewed later. The database does not enforce a MINIMUM, so the seat enforces one here.
      if (rationale.length < 12) return J({ error: 'rationale_required', detail: 'say why, in a sentence' }, 400);

      const { data: dec, error: decErr } = await admin.from('ceo_approval').insert({
        subject_kind: kind, subject_id: subject, decision, decided_by: 'ceo',
        amount_aed: body.amount_aed ?? null, rationale,
      }).select('decision_id').maybeSingle();
      if (decErr) return J({ ok: false, refused: decErr.message }, 400);

      let refundLinked: unknown = null;
      if (kind === 'refund' && decision === 'approved' && body.refund_id) {
        const { data: rf, error: rfErr } = await admin.from('refunds')
          .update({ refund_decision_id: dec?.decision_id, decided_by: 'ceo', decided_at: new Date().toISOString() })
          .eq('id', Number(body.refund_id)).select('id,status,refund_decision_id').maybeSingle();
        // Surfaced, never swallowed: if the refund guards refuse the link, the decision still stands
        // as a record and the caller is told exactly what refused it.
        refundLinked = rfErr ? { refused: rfErr.message } : rf;
      }
      return J({ ok: true, decision_id: dec?.decision_id, refund: refundLinked });
    }

    return J({ error: 'unknown_action', actions: ['command', 'inbox', 'task', 'decide'] }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));
