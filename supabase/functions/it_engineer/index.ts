// it_engineer — the IT Engineer seat's runtime. The company's FIFTH agent, and the only one that
// does not report to the CEO.
//
// WHY IT EXISTS. The founder, 9 September 2026: "fine then we build the it engineer to monitor
// everything. once their is an issue, he will email me directly so i can open a session with you to
// fix it. about his knowledge, you have to keep him really capable of such tasks. he reports to me
// directly only. however he monitor literally everything in the app and the website"
//
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. ceo_agent shipped on 8 Sep reading `body.as` and
// believing it, which let any holder of an in-scope credential present as the CEO — a real
// confused-deputy defect, fixed the same day. Nothing in this file reads a seat name off the payload.
//
// NO MODEL CALL IN HERE EXCEPT THE WEEKLY SEAT EXAM ('seat_exam', seat_exam.ts, 16 Nov 2026, ledger 1084/1443). Every
// other action is a database read: whether a seat is registered, what its standing grants say, what a routine
// answers when asked. There is no judgement in any of it, which is why none is faked. The exam is the one action
// whose whole purpose is the model's real answer; its calls are fn knowledge_exam (its own gateway credential).
//
// WHAT IS DELIBERATELY ABSENT — THE SEAM, NAMED, so nobody mistakes silence for capability.
// This file holds NO monitoring action. It does not probe the website, does not read health_checks,
// does not walk the scheduled jobs, does not open an incident and does not send the founder anything.
// The monitoring engine, the alerting path and the instrumentation are a separate build, in flight
// alongside this one. THE SEAM IS HERE: a new `action` branch in the switch below, authorised by
// `fn_agent_may_act('it_engineer','monitoring'|'diagnosis'|'escalation')` exactly as `authority`
// below asks it, and attributed with `run(...)` exactly as these three actions are. Everything that
// build needs from the seat — the credential, the grants, the refusal routes, the run log — is live
// and is proved live by `health`.
//
// Naming that absence is cheaper than discovering later that a green `status` meant "nothing is
// wrong" when it meant "nothing looks".
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../_shared/admin_session.ts';
import { recallCases, recallTrace } from '../_shared/case_recall.ts';
import { placementTick } from '../_shared/inbox_placement.ts';
import { applyRule as exoApplyRule, isServiceRole, probe as exoProbe } from './exo_transport_rule.ts';

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

// THE ONLY CREDENTIAL THAT IS THIS SEAT. An unrecognised context is refused rather than defaulted.
const SEAT_BY_CREDENTIAL: Record<string, 'it_engineer'> = {
  'fn.it_engineer': 'it_engineer',
};

type Caller = { kind: 'it_engineer' | 'founder'; context: string | null } | { kind: 'two_step_required'; body: TwoStepBody } | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'it_engineer');
    // ok-but-unrecognised is NOT a fallback to the seat. It is a refusal.
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ? { kind: 'it_engineer', context: r.context } : null;
  }
  // The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An
  // admin whose session has one factor is answered 403 naming the step (security audit 10 Nov 2026, item 1).
  const a = await adminCaller(admin, sec, req.headers.get('Authorization'));
  if (a.kind === 'two_step_required') return { kind: 'two_step_required', body: a.body };
  // The founder is the one human this seat answers to, so he is the one human it answers.
  return a.kind === 'admin' ? { kind: 'founder', context: null } : null;
}

// EVERY CALL LEAVES A ROW. fn_it_detect (D2) reads each subject's own rhythm in agent_runs, so a seat
// that never writes one has no rhythm to watch: its silence is indistinguishable from a seat that is down. For
// the seat whose entire job is telling the difference between "quiet" and "dead", writing its own
// liveness signal is not optional. Best-effort: attribution must never fail the call it attributes.
async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'it_engineer',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

// THE FIVE CLASSES THIS SEAT IS DEFINED BY — three it holds, two it must be refused. They are asked
// of fn_agent_may_act at call time rather than read from a cached list, so a grant revoked a minute
// ago cannot be used from a stale answer, and a grant quietly widened shows up here immediately.
// 'deploy' is asked precisely BECAUSE there is no grant for it: a refusal that is never exercised is
// a refusal nobody has seen work.
const CLASSES = ['monitoring', 'diagnosis', 'escalation', 'job_rerun', 'deploy'] as const;

async function mayAct(cls: string, amountAed: number | null = null) {
  const { data, error } = await admin.rpc('fn_agent_may_act', {
    p_grantee_role_id: 'it_engineer', p_action_class: cls, p_amount_aed: amountAed,
  });
  if (error) return { may_act: null, error: error.message };
  return (data || {}) as Record<string, unknown>;
}

// WHERE A REFUSAL'S ROUTE COMES FROM, AND WHY IT IS NOT IN THIS FILE.
//
// fn_agent_may_act is the general authority rule and it is shared with every other seat. On a
// refusal it names route 'ceo_case_decision', which is correct for the four seats that report to the
// CEO and is NOT correct for this one: the founder ruled on 9 Sep 2026 that the IT engineer "reports
// to me directly only", and for a deploy or a configuration change the route is a session he opens,
// not a CEO decision. Forking fn_agent_may_act to say so would create a second authority rule to
// keep in step, and the one that drifted would be this one.
//
// So the general rule is returned VERBATIM and untouched, and the seat's own route is read out of
// public.org_role.forbidden_decisions — one row, in the database, written by the seat's own SQL file.
// The TypeScript holds no policy: every line there is TAGGED with the action class it refuses, as
// '[deploy] …', and this looks the line up by that exact tag. If no line carries the tag it returns
// null rather than inventing a route.
//
// IT USED TO GUESS, AND THE PROBE CAUGHT IT. The first draft matched the class name against the
// prose as a substring — 'deploy' appears in "DEPLOYING AN EDGE FUNCTION" and worked, 'job_rerun'
// does not appear in "RE-RUNNING A SCHEDULED JOB" and came back null. A refusal with no route is
// the one thing this function must never produce, and a heuristic that is right on the case it was
// written against is how you ship one. The tag is in the database, and the match is exact.
function routeFor(cls: string, forbidden: string[]): string | null {
  const tag = '[' + cls + '] ';
  return forbidden.find((f) => f.startsWith(tag)) ?? null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));

    // ── EXCHANGE ONLINE (exo_transport_rule.ts) ───────────────────────────────────────────────────────
    // SERVICE_ROLE ONLY, decided before whoami: the seat credential and the founder's session are both refused
    // here, because one of these actions writes tenant mail-flow configuration. verify_jwt = true (config.toml)
    // has already checked the bearer's signature. exo_roles is read-only; exo_transport_rule_apply is the write,
    // a separate action so a probe can never create anything. Neither response carries a token or a secret.
    const exoAction = String(body.action || '').trim();
    if (exoAction === 'exo_roles' || exoAction === 'exo_transport_rule_apply') {
      if (!isServiceRole(req.headers.get('Authorization'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'))) {
        return J({ error: 'unauthorized', note: exoAction + ' answers the service_role only' }, 401);
      }
      const env = (k: string) => Deno.env.get(k);
      if (exoAction === 'exo_roles') {
        const p = await exoProbe(env, fetch);
        await run('exo_roles', p.ok ? 'ok' : 'error', { verdict: p.verdict, graph_roles: p.graph.roles, exchange_roles: p.exchange.roles });
        return J({ seat: 'it_engineer', ...p });
      }
      const a = await exoApplyRule(env, fetch);
      await run('exo_transport_rule_apply', a.ok ? 'ok' : 'error', { outcome: a.outcome }, a.why);
      return J({ seat: 'it_engineer', ...a }, a.outcome === 'refused' ? 409 : 200);
    }

    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);
    if (caller.kind === 'two_step_required') return J(caller.body, 403);   // an admin with one factor: name the step

    const action = String(body.action || '').trim();

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // IS THE SEAT REAL — asked of the database, never asserted. Three questions:
    //   what it IS      (org_agents / org_role, and the deliberate absence of a reporting edge)
    //   what it MAY DO  (fn_agent_may_act on all five classes, permits and refusals alike)
    //   what it REACHES (the credential's own scope, and the functions it owns)
    // plus whether the one route the founder asked for — mail that reaches him directly — is open,
    // measured rather than assumed.
    if (action === 'health' || action === 'status') {
      const [agent, role, edge, grants, cred, owner, mailPolicy, routes, lastRuns] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available,title,routing_tier,department,manager_key').eq('agent_key', 'it_engineer').maybeSingle(),
        admin.from('org_role').select('role_id,display_name,status,authority_level,runtime_mode,runtime_agent_key,responsibilities,owned_decisions,forbidden_decisions,handoff_targets,escalation_targets,manager_role_id').eq('role_id', 'it_engineer').maybeSingle(),
        admin.from('org_reporting_edge').select('child_role_id,parent_role_id').eq('child_role_id', 'it_engineer'),
        admin.from('ceo_standing_grant').select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at').eq('grantee_role_id', 'it_engineer').order('grant_key'),
        admin.from('internal_credential').select('context,scope,active,use_count,last_used_at').eq('context', 'fn.it_engineer').maybeSingle(),
        admin.from('function_owner').select('function_slug').eq('owner', 'it_engineer'),
        admin.from('founder_mail_policy').select('kind,allowed_to_email,owner_role,reason'),
        admin.from('llm_route_health').select('model_id,open_until'),
        admin.from('agent_runs').select('id,status,finished_at,counts').eq('agent', 'it_engineer').order('id', { ascending: false }).limit(5),
      ]);

      const forbidden = (role.data?.forbidden_decisions || []) as string[];
      const authority: Record<string, unknown> = {};
      for (const cls of CLASSES) {
        const m = await mayAct(cls);
        authority[cls] = m.may_act === true
          ? { may_act: true, grant: m.grant ?? null, scope: m.scope ?? null, limit: m.limit ?? null }
          // THE REFUSAL NAMES THE ROUTE, exactly as the accountant's refunds do — but this seat's
          // route is the founder, not the CEO, so both are returned and neither is invented.
          // `authority_rule` is fn_agent_may_act's own answer, unedited.
          : { may_act: m.may_act ?? null, authority_rule: m, route: routeFor(cls, forbidden),
              route_owner: 'founder', error: m.error ?? null };
      }

      // THE ONE ROUTE THE FOUNDER ASKED FOR, MEASURED. He said this seat emails him directly, so
      // whether any founder-facing mail class is OWNED by this seat is a fact worth reading rather
      // than assuming. It is 0 today and that is reported as 0 WITH ITS MEANING: founder_mail_policy
      // still carries kinds owned by 'it_operations_engineer', 'cto' and 'cybersecurity_engineer' —
      // roles the founder deleted on 7 Sep — so those rows are unowned by any live seat, not absent.
      // Re-owning them belongs to the alerting build. Reporting the number without saying that would
      // be a zero that reads as "nothing reaches him", which is a different and false statement.
      const policy = (mailPolicy.data || []) as Array<{ kind: string; allowed_to_email: boolean; owner_role: string; reason: string }>;
      const ownedByThisSeat = policy.filter((p) => p.owner_role === 'it_engineer');
      const deadOwners = ['it_operations_engineer', 'cto', 'cybersecurity_engineer'];
      const orphanedOps = policy.filter((p) => deadOwners.includes(p.owner_role));
      const founderRoute = {
        kinds_owned_by_this_seat: ownedByThisSeat.length,
        kinds_owned_by_this_seat_that_reach_him: ownedByThisSeat.filter((p) => p.allowed_to_email).length,
        // These already reach him today and would carry an outage report the moment something emits
        // one, whoever owns the row.
        outage_kinds_that_already_reach_him: policy
          .filter((p) => p.allowed_to_email && deadOwners.includes(p.owner_role))
          .map((p) => p.kind).sort(),
        ops_kinds_owned_by_a_role_that_no_longer_exists: orphanedOps.length,
        basis: 'Read from public.founder_mail_policy at call time. A count of 0 owned kinds means this '
          + 'seat has not yet been made the owner of any founder-facing mail class — NOT that no mail '
          + 'reaches the founder. Re-owning the operations kinds is part of the alerting build, not of '
          + 'this file.',
      };

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      const seated = agent.data?.active === true && agent.data?.available === true
        && role.data?.status === 'active';
      const edges = (edge.data || []).length;

      const facts = {
        ok: true,
        seat: 'it_engineer',
        caller: caller.kind,
        authenticated_by: caller.context ?? 'founder jwt (app_secrets.admin_emails)',
        seated,
        agent: agent.data ?? null,
        role: role.data ?? null,
        // NOT NULL BY ACCIDENT. The founder, 9 Sep 2026: "he reports to me directly only." The
        // founder is a human, not a row in org_role, and org_reporting_edge's parent is a foreign key
        // to org_role — so writing this edge would mean inventing a 'founder' role and putting a
        // person into the org chart. The absence IS the statement, and 0 is asserted, not observed.
        reports_to: null,
        reporting_edges: edges,
        reports_to_founder: (role.data?.escalation_targets || []).includes('founder') && edges === 0,
        reporting_note: edges === 0
          ? 'No row in org_reporting_edge, deliberately. The founder ruled on 9 Sep 2026 that this seat reports to him directly only; org_reporting_edge.parent_role_id is a foreign key to org_role, and the founder is not a role. Escalation leaves the company instead of landing on the CEO.'
          : 'DEFECT: this seat has ' + edges + ' reporting edge(s). The founder ruled it reports to him directly only.',
        authority,
        grants: (grants.data || []).map((g: Record<string, unknown>) => ({
          grant: g.grant_key, class: g.action_class, active: g.active,
          ceiling_aed: g.max_amount_aed, expires_at: g.expires_at,
          scope: g.scope_note, limit: g.limit_note,
        })),
        // Every line here names its own route in words. The runtime does not paraphrase them.
        refuses: forbidden,
        reaches: {
          credential: cred.data?.context ?? null,
          may_call: cred.data?.scope ?? [],
          credential_active: cred.data?.active ?? null,
          use_count: cred.data?.use_count ?? null,
          last_used_at: cred.data?.last_used_at ?? null,
          note: 'internal_credential.scope is the exhaustive list of edge functions this credential '
            + 'authenticates to. It names only this seat\'s own runtime because this seat calls '
            + 'nothing else yet; widening it is a decision somebody has to write down.',
        },
        owns_functions: ((owner.data || []) as Array<{ function_slug: string }>).map((r) => r.function_slug).sort(),
        founder_route: founderRoute,
        recent_runs: lastRuns.data ?? [],
        // Reported because it is true of every seat, not because this one is waiting on it.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held. No action in this function calls a model, so nothing here is blocked by it.' }
          : null,
        watching: {
          // WHAT IT IS CHARTERED TO WATCH, read from the grant rather than restated here, so the
          // charter cannot drift from the authority that carries it.
          charter: (grants.data || []).find((g: Record<string, unknown>) => g.action_class === 'monitoring')?.scope_note ?? null,
          readings: null,
          basis: 'NOTHING WAS MEASURED ABOUT THE ESTATE ON THIS CALL. readings is null rather than an '
            + 'empty object or a row of zeros, because a zero here would be indistinguishable from a '
            + 'healthy estate. The monitoring engine that takes these readings is a separate build; '
            + 'its seam is a new action branch in supabase/functions/it_engineer/index.ts, authorised '
            + 'by fn_agent_may_act(\'it_engineer\',\'monitoring\'), which this response shows is live.',
        },
      };

      if (action === 'health') {
        await run('health', seated && edges === 0 ? 'ok' : 'error', {
          seated, edges, grants: (grants.data || []).length,
          active_grants: (grants.data || []).filter((g: { active: boolean }) => g.active).length,
          owns: (owner.data || []).length,
        }, seated && edges === 0 ? undefined
          : 'The IT Engineer seat is not correctly established: seated=' + seated + ' reporting_edges=' + edges);
        return J(facts);
      }

      // ── STATUS ───────────────────────────────────────────────────────────────────────────────
      // The same facts, plus one paragraph a human can read without unpacking JSON. Every sentence
      // is assembled from a value above; none is a template that would still read well if the
      // measurement had failed.
      const permitted = CLASSES.filter((c) => (authority[c] as Record<string, unknown>)?.may_act === true);
      const refused = CLASSES.filter((c) => (authority[c] as Record<string, unknown>)?.may_act === false);
      const summary = [
        `IT Engineer — ${seated ? 'seated and available' : 'NOT PROPERLY SEATED'}.`,
        edges === 0
          ? 'Reports to the founder directly; it holds no reporting edge to the CEO, which is the founder\'s ruling of 9 Sep 2026 and not an omission.'
          : `DEFECT: it holds ${edges} reporting edge(s) and should hold none.`,
        `It may ${permitted.length ? permitted.join(', ') : 'do nothing at all — every class was refused, which means the seat is seated and blind'}.`,
        `It is refused ${refused.length ? refused.join(', ') : 'nothing, which should be impossible — deploy has no grant'}; each refusal names the founder as the route.`,
        `Its credential ${cred.data?.active ? 'is active' : 'is NOT active'} and authenticates to ${(cred.data?.scope || []).length} function(s). It owns ${(owner.data || []).length} function(s).`,
        `${founderRoute.kinds_owned_by_this_seat} founder-mail class(es) are owned by this seat; `
          + `${founderRoute.ops_kinds_owned_by_a_role_that_no_longer_exists} operations class(es) are still owned by roles the founder deleted on 7 Sep, `
          + `of which ${founderRoute.outage_kinds_that_already_reach_him.length} already reach him. Re-owning them is the alerting build's.`,
        'NOTHING ABOUT THE ESTATE WAS MEASURED ON THIS CALL. This seat is established and authorised; the engine that takes the readings is a separate build.',
      ].join(' ');

      await run('status', seated && edges === 0 ? 'ok' : 'error', {
        seated, edges, permitted: permitted.length, refused: refused.length,
        founder_mail_kinds_owned: founderRoute.kinds_owned_by_this_seat,
      });
      return J({ ...facts, summary });
    }

    // ── AUTHORITY ──────────────────────────────────────────────────────────────────────────────
    // "May I do X?" for any class, answered by the database at call time. This is the door the
    // monitoring engine knocks on before it acts, and the reason it exists separately from `health`
    // is that the engine will ask about one class, not five.
    //
    // The refusal is the interesting half. fn_agent_may_act's answer is returned VERBATIM under
    // `authority_rule` — it is the same rule every seat is judged by and it is not reshaped here —
    // and this seat's own route is read from org_role.forbidden_decisions. An unknown class is
    // refused with route null rather than with an invented one.
    // ── ASSIST ─────────────────────────────────────────────────────────────────────────────────
    // THE SEAT COULD NOT READ ITS OWN KNOWLEDGE, OR THE COMPANY'S. Measured 9 Sep 2026: this file
    // called exactly one routine, fn_agent_may_act, and nothing else. public.it_engineer_knowledge
    // held 79 records written for this seat and fn_it_engineer_assist existed to retrieve them, and
    // no deployed code had ever called either. Founder, the same day: "the company knowledge is
    // literally connected to every seat automatically. Any seat that we made, the company knowledge
    // should be there. Otherwise, those agents wouldn't know where they work or what they do or what
    // is our company about."
    //
    // fn_it_engineer_assist now pins public.fn_company_context() onto EVERY return path, refusals
    // included, so this one call is both halves: what the seat knows about its trade, and what the
    // company is. The embedding is optional and is not computed here -- with none the routine falls
    // back to the stricter lexical-only bar, which is the honest behaviour rather than a silent
    // widening of what counts as a match.
    // ── INCIDENT PDF ───────────────────────────────────────────────────────────────────────────
    // Duty 18: an incident record rendered for an external auditor, EN only, from the fixed template
    // in fn_it_incident_pdf_blocks. pdf_native draws it and stores it; the path goes on the record.
    if (action === 'incident_pdf') {
      const id = Number(body.incident_id);
      if (!Number.isInteger(id) || id <= 0) return J({ error: 'incident_id_required' }, 400);
      const { data: doc, error } = await admin.rpc('fn_it_incident_pdf_blocks', { p_id: id });
      if (error) { await run('incident_pdf', 'error', { incident_id: id }, error.message); return J({ error: error.message }, 404); }
      const d = doc as { title: string; blocks: unknown[] };
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/pdf_native', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        // options.letterhead: the issuer and licence line an auditor reads first (audit of every document
        // we issue, 22 Sep 2026, finding 5: the incident record rendered without it).
        body: JSON.stringify({ __secret: await sec('cred_fn_to_pdf_native'), title: d.title, blocks: d.blocks, options: { letterhead: true },
                               bucket: 'agent-docs', folder: 'it_engineer/incidents', name: 'incident_' + id }),
        signal: AbortSignal.timeout(60000),
      });
      const out = await r.json().catch(() => null) as { path?: string; url?: string } | null;
      if (!r.ok || !out?.path) {
        await run('incident_pdf', 'error', { incident_id: id, status: r.status }, 'pdf_native answered ' + r.status);
        return J({ error: 'pdf_failed', status: r.status }, 502);
      }
      const { error: upErr } = await admin.from('it_incident').update({ pdf_path: out.path, updated_at: new Date().toISOString() }).eq('id', id);
      if (upErr) { await run('incident_pdf', 'error', { incident_id: id }, upErr.message); return J({ error: upErr.message }, 500); }
      await run('incident_pdf', 'ok', { incident_id: id });
      return J({ ok: true, incident_id: id, path: out.path, url: out.url ?? null });
    }

    if (action === 'assist') {
      const text = String(body.text || body.question || '').trim();
      if (!text) return J({ error: 'text_required' }, 400);
      const { data, error } = await admin.rpc('fn_it_engineer_assist', {
        p_text: text,
        p_embedding: (body.embedding as number[] | undefined) ?? null,
      });
      if (error) {
        await run('assist', 'error', { chars: text.length }, error.message);
        return J({ error: error.message }, 500);
      }
      const r = (data || {}) as Record<string, unknown>;
      // Past findings like this one (23 Sep 2026): what fixed it last time, and did the fix hold?
      const memory = await recallCases(admin, { seat: 'it_engineer', path: 'assist', situation: text,
        ...(Array.isArray(body.embedding) ? { embedding: body.embedding as number[] } : {}) });
      await run('assist', 'ok', {
        answered: r.answered ?? null,
        cited: Array.isArray(r.cited) ? r.cited.length : 0,
        company_block: (r.company as Record<string, unknown> | undefined)?.chars ?? 0,
        precedent: recallTrace(memory),
      });
      return J({ ok: true, seat: 'it_engineer', ...r, precedent: memory });
    }

    // TRIAGE ONE FINDING (23 Sep 2026). Before the seat works an open finding it asks: have we closed
    // one like this before, what was the fix, and was it reopened? Exact issue_key dedup cannot see a
    // repeat that arrives under a different key; meaning can.
    if (action === 'triage') {
      const key = String(body.issue_key || '').trim();
      if (!key) return J({ error: 'issue_key_required' }, 400);
      const { data: f } = await admin.from('it_engineer_finding').select('issue_key,title,where_it_is,blast').eq('issue_key', key).maybeSingle();
      if (!f) return J({ error: 'finding_not_found' }, 404);
      const memory = await recallCases(admin, { seat: 'it_engineer', path: 'triage', caseKind: 'it_finding', otherSeats: false,
        situation: `${f.title} | where: ${f.where_it_is} | blast: ${f.blast}`, exclude: { table: 'it_engineer_finding', id: key } });
      await run('triage', 'ok', { issue_key: key, precedent: recallTrace(memory) });
      return J({ ok: true, seat: 'it_engineer', issue_key: key, precedent: memory });
    }

    // ── INBOX PLACEMENT ──────────────────────────────────────────────────────────────────────────────
    // The morning seed check through the seam named above, on demand (resilience_ping's itintegrations step
    // runs the same placementTick every 15 min). The database decides whether to queue, read or settle, so
    // a call outside 04:30-08:00 UTC on a sending day only answers 'idle'. Monitoring class, asked live.
    if (action === 'inbox_placement') {
      const m = await mayAct('monitoring');
      if (m.may_act !== true) return J({ ok: false, error: 'not_authorised', authority_rule: m }, 403);
      const out = await placementTick((fn, args) => admin.rpc(fn, args) as never, fetch, sec,
        async (k, v) => await admin.from('app_secrets').update({ value: v }).eq('key', k));
      await run('inbox_placement', out.ok === false ? 'error' : 'ok', { result: out });
      return J({ seat: 'it_engineer', ...out });
    }

    // ── THE WEEKLY SEAT EXAM (seat_exam.ts) ───────────────────────────────────────────────────────────
    // Posted by the duty it_engineer.seat_exam (scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql) with the run's
    // id until every planned item is asked. The database chooses the items and holds the week's AED cap; this asks.
    if (action === 'seat_exam') {
      const runId = Number(body.run_id);
      if (!Number.isInteger(runId) || runId <= 0) return J({ error: 'run_id_required' }, 400);
      const { runExamBatch } = await import('./seat_exam.ts');
      const { think, defaultDeps } = await import('../_shared/think.ts');
      const { makeLlmRich } = await import('../_shared/llm.ts');
      const { embedLine } = await import('../_shared/gte_embed.ts');
      const live = defaultDeps(admin as never, 'knowledge_exam');
      const call = (taskClass: string, temperature: number) => makeLlmRich([], { fn: 'knowledge_exam', agent: 'it_engineer', taskClass,
        max: 400, timeoutMs: 30_000, json: true, temperature, internalDuty: true });
      const ask = async (c: ReturnType<typeof call>, system: string, input: string) => {
        const r = await c(system, input, 400); return { content: r.content, error: r.error };
      };
      const result = await runExamBatch({
        next: async (id, n) => {
          const { data, error } = await admin.rpc('fn_seat_exam_next', { p_run_id: id, p_n: n });
          if (error) return { items: [], stop: 'next_failed: ' + error.message };
          const d = (data || {}) as { items?: unknown[]; stop?: string | null };
          return { items: (d.items ?? []) as never, stop: d.stop ?? null };
        },
        reword: (system, input) => ask(call('routine_employee_reasoning', 0.9), system, input),
        judge: (system, input) => ask(call('knowledge_validation', 0), system, input),
        answer: async (seat, wording, itemId) => {
          try {
            const r = await think(live as never, { seat: seat as never, surface: 'think.answer', question: wording,
              context: { audience: 'internal' } as never, subject: { seat_exam_item: itemId } as never,
              internalDuty: true, queueWhenHeld: false } as never) as { status: string; answer?: string; model?: string | null; reason?: string | null };
            return { status: r.status, answer: r.answer ?? '', model: r.model ?? null, reason: r.reason ?? null };
          } catch (e) { return { status: 'error', answer: '', model: null, reason: (e as Error).message }; }
        },
        record: async (r) => {
          const { data, error } = await admin.rpc('fn_seat_exam_record', { p_run_id: r.run_id, p_item_id: r.item_id, p_seat: r.seat,
            p_wording: r.wording, p_answer: r.answer, p_model: r.model, p_status: r.status, p_pass: r.pass, p_graded_by: r.graded_by,
            p_missing: r.missing });
          if (error) return { asked_id: 0, fix_id: null, lesson_needed: false, error: error.message };
          const d = (data || {}) as { asked_id: number; fix_id: number | null; lesson_needed: boolean };
          return { asked_id: d.asked_id, fix_id: d.fix_id ?? null, lesson_needed: d.lesson_needed === true, error: null };
        },
        lesson: async (fixId) => {
          const { data, error } = await admin.rpc('fn_seat_exam_fix_lesson', { p_fix_id: fixId });
          if (error) return { knowledge_id: null, error: error.message };
          const d = (data || {}) as { knowledge_id?: number; content?: string };
          // the vector the seat's retrieval ranks by (fn_reason_retrieve reads agent_knowledge.embedding_gte); a lesson
          // without one is still recorded and still closes nothing until a pass, so a failed embed is reported, not hidden
          const v = d.content ? await embedLine(d.content).catch(() => null) : null;
          if (d.knowledge_id && v) await admin.from('agent_knowledge').update({ embedding_gte: JSON.stringify(v) }).eq('id', d.knowledge_id);
          return { knowledge_id: d.knowledge_id ?? null, error: d.knowledge_id ? (v ? null : 'written without a vector') : 'no row' };
        },
        now: () => Date.now(),
      }, runId, { budgetMs: 110_000, max: 4 });
      // a batch that could not read or record is a failed post (502): the duty counts it and closes the run after three
      const broken = !!(result.stop?.startsWith('record_failed') || result.stop?.startsWith('next_failed'));
      await run('seat_exam', broken ? 'error' : 'ok',
        { run_id: runId, asked: result.asked, passed: result.passed, missed: result.missed, no_wording: result.no_wording,
          lessons: result.lessons, stop: result.stop });
      return J({ ok: !broken, seat: 'it_engineer', run_id: runId, ...result }, broken ? 502 : 200);
    }

    if (action === 'authority') {
      const cls = String(body.action_class || '').trim();
      if (!cls) return J({ error: 'action_class_required', classes: CLASSES }, 400);
      const amount = Number.isFinite(Number(body.amount_aed)) ? Number(body.amount_aed) : null;
      const m = await mayAct(cls, amount);
      const { data: role } = await admin.from('org_role')
        .select('forbidden_decisions,escalation_targets').eq('role_id', 'it_engineer').maybeSingle();
      const forbidden = (role?.forbidden_decisions || []) as string[];
      await run('authority', 'ok', { action_class: cls, amount_aed: amount, may_act: m.may_act ?? null });
      if (m.may_act === true) {
        return J({ ok: true, seat: 'it_engineer', action_class: cls, may_act: true, ...m });
      }
      return J({
        ok: true, seat: 'it_engineer', action_class: cls, may_act: m.may_act ?? null,
        authority_rule: m,
        route: routeFor(cls, forbidden),
        route_owner: (role?.escalation_targets || []).includes('founder') ? 'founder' : null,
        basis: 'may_act comes from public.fn_agent_may_act, the one authority rule every seat is '
          + 'judged by, and is returned unedited. `route` is the matching line of '
          + 'public.org_role.forbidden_decisions for this seat — the founder ruled on 9 Sep 2026 that '
          + 'this seat reports to him directly, so its route is a session he opens, not the CEO '
          + 'decision fn_agent_may_act names by default for the four seats that do report to the CEO. '
          + 'A class with no matching line returns route null rather than an invented one.',
      });
    }

    return J({ error: 'unknown_action', action, actions: ['health', 'status', 'authority', 'assist', 'triage', 'incident_pdf', 'inbox_placement', 'seat_exam', 'exo_roles (service_role)', 'exo_transport_rule_apply (service_role)'],
      note: 'The monitoring, diagnosis and escalation actions are a separate build. See the seam '
        + 'described at the top of supabase/functions/it_engineer/index.ts.' }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
});
