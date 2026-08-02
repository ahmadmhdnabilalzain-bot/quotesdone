-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802175455   name: p2_c1_stage_b5_trade_hints_and_arabic_alias_gaps
-- SHA-256 of the applied SQL: 4447eb268e1ff644ac40840cad1848f65d682b3b2f9ba9b113f454083df19015
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.5 - two defects found by the adversarial half of the language suite.
--
-- DEFECT 1: "Mechanical and electrical works" / "أعمال الميكانيكا والكهرباء" identified electrical
-- only. In UAE MEP usage `mechanical` conventionally means HVAC, so HVAC was a false negative in
-- BOTH languages (parity held; both were wrong).
--
-- The fix is deliberately NOT to add `mechanical` as a trade name. "We need a mechanical engineer"
-- would then confirm an HVAC workstream off one ambiguous word, which is precisely the wrong
-- dispatch this design exists to prevent. Instead a new pattern kind, `trade_hint`, carries the
-- signal at alias-ambiguous strength: it PROPOSES the trade and asks.
--
-- DEFECT 2: "Water piping installation" matched plumbing in English through a catalogue alias, but
-- "تمديدات المياه" matched nothing - a gap in Arabic alias coverage, not a scoring problem.

-- pattern_norm should never have to be remembered by whoever adds a pattern.
create or replace function public.trg_mep_pattern_norm()
returns trigger language plpgsql as $fn$
begin
  new.pattern_norm := public.fn_norm_text(new.pattern);
  return new;
end $fn$;

drop trigger if exists mep_trade_pattern_norm on public.mep_trade_pattern;
create trigger mep_trade_pattern_norm before insert or update on public.mep_trade_pattern
  for each row execute function public.trg_mep_pattern_norm();

alter table public.mep_trade_pattern drop constraint if exists mep_trade_pattern_kind_check;
alter table public.mep_trade_pattern add constraint mep_trade_pattern_kind_check
  check (kind in ('trade_name','trade_hint','mep_anchor','mep_full_phrase','scope_full','scope_only'));

insert into public.mep_evidence_weight
  (weight_key, evidence_source, variant, evidence_score, source_authority, exactness, auto_confirms, rationale) values
  ('customer_text.trade_hint','customer_text','trade_hint', 0.400, 'customer', 'conventional_term', false,
   'A domain term that conventionally implies a trade without naming it - "mechanical" for HVAC. Strong enough to raise the trade, not strong enough to commit a workstream to it. Proposes and asks.')
on conflict (weight_key) do nothing;

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  ('hvac','trade_hint','mechanical','en'),
  ('hvac','trade_hint','ميكانيكا','ar'),
  ('hvac','trade_hint','ميكانيكيه','ar'),
  ('plumbing','trade_name','تمديدات المياه','ar'),
  ('plumbing','trade_name','مواسير المياه','ar'),
  ('plumbing','trade_name','شبكه المياه','ar')
on conflict (kind, pattern, lang) do nothing;

update public.p2c1_lang_case
   set expect_trades = array['electrical','hvac'], expect_status = 'confirmed',
       note = note || ' | CORRECTED 2 Aug 2026: HVAC is now raised from the conventional term '
              || '"mechanical" as a trade_hint, so it is PROPOSED rather than confirmed. Electrical '
              || 'is still confirmed by name. Confirming HVAC off one ambiguous word would be a '
              || 'wrong dispatch waiting to happen.'
 where case_key = 'hard_mech_elec';

update public.p2c1_lang_case
   set note = note || ' | CORRECTED 2 Aug 2026: added Arabic plumbing surface forms. The English '
              || 'side already matched through a catalogue alias; the Arabic alias set had the gap.'
 where case_key = 'hard_water_pipes';
;