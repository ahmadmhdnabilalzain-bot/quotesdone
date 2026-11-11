// supplier_api — the account and its company: me, search, create_company, claim, support_rating(_due).
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { searchResult, SEARCH_COLUMNS, type LeadHit } from '../search_result.ts';
import { createCompany, listingClosedToClaims, sessionOpenedByCode } from '../create_company.ts';
import { SANCTIONED_REGISTRATION_REFUSAL, sanctionedLead, sanctionedLeads } from '../../_shared/sanctioned.ts';
import { registrationRefusal } from '../../_shared/duplicate_company.ts';
import { type ActionCtx, J, admin, secretVal } from '../context.ts';
import { UUID_RE } from '../lib/fields.ts';
import { emailProven, recordFirstTouch, setRegistration } from '../lib/registration.ts';
import { supplierOf } from '../lib/me_row.ts';

export async function accountActions(c: ActionCtx): Promise<Response | undefined> {
  const { jwt, email, body, action } = c;
    // claimed_by is the account e-mail. Registration SHOWS it with its verification state rather
    // than asking for it — the supplier signed in with it, so a field here could only ever be
    // answered with the value we already hold.
    if (action === 'me') return J({ supplier: await supplierOf(admin, email, secretVal) });   // lib/me_row.ts: one wave of reads, and create_company answers with the same row
    if (action === 'search') { const q = String(body.q || '').slice(0, 60); if (q.length < 2) return J({ results: [] }); const { data } = await admin.from('leads').select(SEARCH_COLUMNS).ilike('company_name', '%' + q + '%').order('reviews', { ascending: false, nullsFirst: false }).limit(8); const rows = (data || []) as LeadHit[]; /* a sanctioned party is never shown to anybody — founder instruction 516, 18 Sep 2026 */ const barred = await sanctionedLeads(admin, rows.map((r) => r.id)); return J({ results: rows.filter((r) => !barred.has(String(r.id))).map((r) => searchResult(r, email)) }); } // search_result.ts: claimed_by is read, never returned
    // THE INVITED COMPANY IS CLAIMED, NEVER REGISTERED A SECOND TIME (28 Oct 2026, ledger 1401 audit S7): ./create_company.ts.
    if (action === 'create_company') { const r = await createCompany(admin, email, body, { emailProven, sessionByCode: sessionOpenedByCode(jwt), sanctionedLead: (id: number) => sanctionedLead(admin, id), setRegistration: (id: number) => setRegistration(id), recordFirstTouch, readSupplier: () => supplierOf(admin, email, secretVal), locale: SUPPLIER_LOCALE }); return J(r.body, r.status); }
    // TAKEOVER FIX 27 Jul 2026 -----------------------------------------------------------------
    // 'claim' resolved the listing from body.leads_id - the sequential primary key - and never
    // looked at claim_token. claim_lookup v2 was rewritten on 19 Jul 2026 to accept ONLY the
    // unguessable token precisely because ids are walkable (see claim_lookup/index.ts header:
    // walking id = 1,2,3... dumped all 20,470 leads). This endpoint left the other half of that
    // hole open: anyone with any supplier login could POST leads_id = N and take ownership of any
    // of the 20,464 unclaimed listings - name, licence, inbox and all - one id at a time. The
    // token is the proof of invitation, so the token is now the LOOKUP KEY. leads_id is accepted
    // only as a cross-check: if it is sent and disagrees with the row the token resolves to, the
    // call is rejected rather than silently trusting either one.
    if (action === 'claim') { const token = String(body.claim_token || body.token || body.t || '').trim(); if (!UUID_RE.test(token)) return J({ error: 'invalid_link', message: 'This claim link is not valid. Please use the link from your invitation, or contact management@quotesdone.com.' }, 400); /* The token's row, this account's current company and the e-mail proof are independent reads: issued together (28 Sep 2026, it_engineer — the claim was a chain of seven round trips, 3.3-4.1 s measured). */ const [{ data: row }, { data: existing }, proven] = await Promise.all([admin.from('leads').select('id,claimed,claimed_by,permanently_closed,banned').eq('claim_token', token).maybeSingle(), admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(), emailProven(email)]); if (!row) return J({ error: 'not found' }, 404); /* WHAT THE PAGE CALLS GONE IS GONE (10 Nov 2026, customer_support): claim_lookup answers not_found for an erased (PDPL) or banned listing, and this door attached it anyway. A row already this account's is not taken from it (a dues ban must still reach supplier_pay). */ if (listingClosedToClaims(row) && row.claimed_by !== email) return J({ error: 'not found', code: 'not_found' }, 404); const id = Number(row.id); const askedId = Number(body.leads_id); if (body.leads_id != null && isFinite(askedId) && askedId !== id) return J({ error: 'invalid_link', message: 'This claim link does not match the company you selected. Please use the link from your invitation.' }, 400); if (row.claimed && row.claimed_by !== email) return J({ error: 'This company is already claimed by another account.' }, 409); if (existing && existing.id !== id) return J({ error: 'Your account already manages another company.' }, 409); /* A SANCTIONED LISTING IS NEVER CLAIMED (28 Oct 2026, review of #1712): fn_sanctioned_identity excludes the row's own id, so the a01 trigger does not stop a claim of the banned row itself. */ if (await sanctionedLead(admin, id)) return J(SANCTIONED_REGISTRATION_REFUSAL, 403); /* ONE WINNER (review of #1712): the write lands only on a row still unclaimed, or already this account's - the guard create_company.ts claims under - so a website sign-up and a token claim racing for one listing cannot both win; the loser reads 0 rows and is told so. */ const owned = row.claimed_by != null && String(row.claimed_by).trim() !== ''; const claimWrite = admin.from('leads').update({ claimed: true, claimed_by: email, portal_updated_at: new Date().toISOString(), ...(proven ? { owner_email_verified: true } : {}) }).eq('id', id); const { data: won, error: claimErr } = await (owned ? claimWrite.eq('claimed_by', email) : claimWrite.is('claimed_by', null)).select('id'); /* 24 Sep 2026 (#962): a claim the database refused (duplicate-company indexes) gets the same answer as create_company. */ if (claimErr) { console.error('claim: leads update failed —', claimErr.message); const r = registrationRefusal(claimErr); return J(r.body, r.status); } if (!won || !won.length) return J({ error: 'This company is already claimed by another account.' }, 409); /* that update already touched the row, so the registration trigger has run: read the state, and record the first touch beside it */ const [reg] = await Promise.all([setRegistration(id, false), recordFirstTouch(id, body.first_touch)]); return J({ ok: true, id, registration: reg }); }

    // A closed support case asks the supplier for its rating inside the portal (CSAT 1-5, CES 1-7; customer_support
    // #1036). The portal is the sales engineer's, so it asks here and never calls Support's widget. The party is the
    // company this session claimed, never an id from the client, and fn_support_portal_rate refuses a case that is
    // not that company's. A sanctioned session never reaches this line (refused above).
    if (action === 'support_rating_due' || action === 'support_rating') {
      const { data: mine } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (action === 'support_rating_due') {
        if (!mine) return J({ ok: true, due: [] });
        const { data, error } = await admin.rpc('fn_support_rating_due', { p_party_kind: 'supplier', p_party_id: String(mine.id) });
        return error ? J({ error: 'rating_due_failed' }, 400) : J({ ok: true, due: data || [] });
      }
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company' }, 400);
      const { data, error } = await admin.rpc('fn_support_portal_rate', {
        p_party_kind: 'supplier', p_party_id: String(mine.id), p_case_ref: String(body.case_ref || ''),
        p_csat: body.csat == null ? null : Number(body.csat), p_ces: body.ces == null ? null : Number(body.ces),
        p_comment: body.comment ? String(body.comment).slice(0, 2000) : null });
      return error ? J({ error: 'rating_failed' }, 400) : J(data);
    }
}
