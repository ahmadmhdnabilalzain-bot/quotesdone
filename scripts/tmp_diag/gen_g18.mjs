import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G18 — the caller was whoever owned the row, and on W14 that is a supplier
--
-- caller_customer_id was answered from v_row_own -- the owner column of whatever relation the run's
-- business object lives in. public.phase_d_context_key_object records that the key names
-- customer_account, and on a W14 run the business object is a quotation, whose owner column is
-- public.quotes.supplier_id. So BR-019, which asks whether a comparison belongs to the CALLING
-- CUSTOMER, was handed a supplier id and refused:
--
--     BR-019: comparison <id> does NOT belong to the calling customer
--
-- It is G08's defect in the one branch G08 did not cover: an answer produced without asking what
-- the key was about. The fix is the same and uses the same registry -- the owner is the answer only
-- when the owner column actually references the customer relation, which is read from pg_constraint
-- rather than assumed. Where it does not, the key falls through to the scenario-reference door,
-- which resolves customer_account from the canonical reference the scenario recorded, and then to
-- the catalogue, and then stays unresolved so BR-019 refuses for a true reason.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let def = r[0].def;
const anchor = `    elsif v_k = 'caller_customer_id' then
      if v_found and v_row_own is not null then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object', v_rel, coalesce(v_owncol,'(none)'));
      end if;`;
if (def.split(anchor).length - 1 !== 1) throw new Error('G18 anchor');
def = def.replace(anchor, `    elsif v_k = 'caller_customer_id' then
      -- G18. THE OWNER IS THE ANSWER ONLY WHEN THE OWNER IS A CUSTOMER.
      -- On a W14 run the business object is a quotation and its owner column is
      -- public.quotes.supplier_id, so this branch handed BR-019 a supplier and BR-019 refused,
      -- correctly, about the wrong party. Whether the owner column reaches the customer relation is
      -- read from the catalog, not assumed from the column's name.
      if v_found and v_row_own is not null and v_owncol is not null
         and exists (select 1
                       from pg_constraint con
                       join lateral unnest(con.conkey) k(attnum) on true
                       join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
                      where con.contype = 'f'
                        and con.conrelid = to_regclass(v_rel)
                        and a.attname = v_owncol
                        and con.confrelid = (select to_regclass(bb.canonical_relation)
                                               from public.phase_d_business_object_binding bb
                                              where bb.object_id = 'customer_account')) then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object, which is a declared foreign key into the customer relation', v_rel, v_owncol);
      end if;`);

writeFileSync('scripts/sql/phase_d_g18_the_caller_was_whoever_owned_the_row.sql', HEAD + '\n' + def + '\n');
console.log('G18 written');
