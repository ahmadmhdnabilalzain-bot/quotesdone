// accountant — the seat itself: health, grants, ledger.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { type ActionCtx, J, admin, run } from '../context.ts';
import { book } from '../lib/books.ts';

export async function seatActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, caller } = c;
    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // Is the seat seated, what does it hold, and what state are the books in. Readiness measured,
    // not asserted: edge_health_probe exists with 0 rows and nothing writes it, so an authenticated
    // round-trip returning this object is the honest liveness signal.
    if (action === 'health') {
      const [agent, grants, edge, owner, routes, journal, expenses] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available,title,manager_key').eq('agent_key', 'accountant').maybeSingle(),
        admin.from('ceo_standing_grant').select('grant_key,action_class,max_amount_aed,active').eq('grantee_role_id', 'accountant'),
        admin.from('org_reporting_edge').select('parent_role_id').eq('child_role_id', 'accountant').maybeSingle(),
        admin.from('function_owner').select('function_slug').eq('owner', 'accountant'),
        admin.from('llm_route_health').select('model_id,open_until'),
        book('gl_journal', 'entry_date'),
        book('expenses', 'expense_date'),
      ]);

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      await run('health', 'ok', { grants: (grants.data || []).length, owns: (owner.data || []).length });
      return J({
        ok: true,
        seat: 'accountant',
        caller: caller.kind,
        seated: agent.data?.active === true && agent.data?.available === true,
        reports_to: edge.data?.parent_role_id ?? null,
        grants: (grants.data || []).map((g: { grant_key: string; action_class: string; max_amount_aed: number | null; active: boolean }) =>
          ({ grant: g.grant_key, class: g.action_class, ceiling_aed: g.max_amount_aed, active: g.active })),
        owns_functions: (owner.data || []).map((r: { function_slug: string }) => r.function_slug).sort(),
        ledger_state: { gl_journal: journal, expenses },
        // Reported because it is true of every seat, not because this one is waiting on it. Nothing
        // in this runtime needs a model.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held. No action in this function calls a model, so nothing here is blocked by it.' }
          : null,
      });
    }

    // ── GRANTS ─────────────────────────────────────────────────────────────────────────────────
    // What may this seat do RIGHT NOW, answered by the database at call time — active state, expiry
    // and the amount ceiling are all evaluated inside fn_agent_may_act, so a revoked grant cannot be
    // used from a cached answer and a ceiling cannot be read past. An uncovered class routes to the
    // CEO and says so; it never routes to the founder.
    if (action === 'grants') {
      const cls = String(body.action_class || '').trim();
      if (cls) {
        const { data, error } = await admin.rpc('fn_agent_may_act', {
          p_grantee_role_id: 'accountant', p_action_class: cls,
          p_amount_aed: body.amount_aed ?? null,
        });
        if (error) return J({ ok: false, refused: error.message }, 400);
        await run('grants', 'ok', { action_class: cls, amount_aed: body.amount_aed ?? null });
        return J({ ok: true, action_class: cls, ...(data as Record<string, unknown>) });
      }
      const { data } = await admin.from('ceo_standing_grant')
        .select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at')
        .eq('grantee_role_id', 'accountant').order('grant_key');
      await run('grants', 'ok', { listed: (data || []).length });
      return J({ ok: true, grants: data || [] });
    }

    // ── LEDGER ─────────────────────────────────────────────────────────────────────────────────
    // Read the books. Four tables, each with its own basis and window — see `book()` above for why
    // a true zero and an unknown must never both print as 0.
    //
    // gl_accounts has no date column: it is the chart of accounts, a catalogue rather than a
    // record of events, so it has a count and honestly no window at all.
    if (action === 'ledger') {
      const books = await Promise.all([
        book('gl_accounts', null),
        book('gl_journal', 'entry_date'),
        book('expenses', 'expense_date'),
        book('ap_bills', 'bill_date'),
      ]);
      const byName = Object.fromEntries(books.map((b) => [String(b.table), b]));
      const unknown = books.filter((b) => b.basis === 'unknown').map((b) => b.table);

      await run('ledger', 'ok', {
        gl_accounts: byName.gl_accounts.rows, gl_journal: byName.gl_journal.rows,
        expenses: byName.expenses.rows, ap_bills: byName.ap_bills.rows,
        unreadable: unknown.length,
      });
      return J({
        ok: true,
        seat: 'accountant',
        caller: caller.kind,
        books: byName,
        unreadable: unknown,
        // Said plainly, because an empty expenses table invites exactly the wrong inference.
        basis: 'Row counts and observed date windows read directly from the four ledger tables at call time. No figure is estimated, no missing figure is defaulted to zero, and no date filter was applied — a window shown here is the observed extent of the data, not a reporting period.',
        note: 'An empty expenses table today means nothing has been filed, NOT that the expenses@mail.quotesdone.com inbox was read and found empty: no handler collects that mailbox yet, so nothing has ever attempted to fill it.',
      });
    }
}
