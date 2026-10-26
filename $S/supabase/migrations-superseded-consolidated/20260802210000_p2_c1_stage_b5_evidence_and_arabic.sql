-- P2-C1 STAGE B.5 (1/4) - evidence-score semantics, Arabic normalisation, hardened scope rule.
-- Applied as p2_c1_stage_b5_evidence_score_semantics,
--            p2_c1_stage_b5_arabic_normalisation_and_scope_hardening,
--            p2_c1_stage_b5_trade_hints_and_arabic_alias_gaps.
--
-- EVIDENCE SCORE, NOT CONFIDENCE. 1.00 / 0.95 / 0.90 / 0.75 / 0.60 / 0.40 are RULE WEIGHTS chosen
-- by hand to order the sources and keep document evidence below the confirmation threshold.
-- Nothing has measured them. Calling the column `confidence` invites someone to read 0.60 as
-- "60% likely to be right", which is a claim nobody has earned.
--
-- THREE ARABIC/SCOPE DEFECTS, all corrected as rules or aliases, none by moving a threshold:
--  (a) The matcher required a non-alphanumeric boundary, so سباكة did not match أعمال السباكة -
--      the ال prefix is alphanumeric. Every Arabic noun in a real sentence carries a proclitic, so
--      the Arabic patterns matched almost nothing outside a bare keyword list.
--  (b) كهربائيه vs كهربائية, إطفاء vs اطفاء: the same word typed by two people.
--  (c) The scope rule fired across a sentence boundary. "Full fit-out of offices. MEP coordination
--      by others." matched `full` and `mep` anywhere and would have activated all three core trades.

drop view if exists public.v_inquiry_trade_status cascade;

alter table public.inquiry_trade_candidate rename column confidence to evidence_score;
alter table public.inquiry_trade_candidate_evidence rename column confidence to evidence_score;

alter table public.inquiry_trade_candidate
  add column if not exists score_basis text not null default 'rule_weight_provisional'
    check (score_basis in ('rule_weight_provisional','calibrated_frequency','measured_probability'));
alter table public.inquiry_trade_candidate_evidence
  add column if not exists score_basis text not null default 'rule_weight_provisional'
    check (score_basis in ('rule_weight_provisional','calibrated_frequency','measured_probability'));
alter table public.inquiry_trade_candidate
  add column if not exists confirmation_factors jsonb;

comment on column public.inquiry_trade_candidate.evidence_score is
  'A rule weight on 0..1, NOT a probability. See score_basis. Provisional until the full 3,324-scenario run calibrates it.';
comment on column public.inquiry_trade_candidate.score_basis is
  'rule_weight_provisional = hand-chosen ordering weight. calibrated_frequency = observed hit rate. measured_probability = a real posterior. Only the first is in use.';
comment on column public.inquiry_trade_candidate.confirmation_factors is
  'The six inputs to the confirm/propose decision: source authority, exactness, alias specificity, ambiguity, runner-up matches, confirmation requirement.';

create table if not exists public.mep_evidence_weight (
  weight_key        text primary key,
  evidence_source   text not null,
  variant           text,
  evidence_score    numeric(4,3) not null,
  score_basis       text not null default 'rule_weight_provisional',
  source_authority  text not null,
  exactness         text not null,
  auto_confirms     boolean not null,
  rationale         text not null
);
alter table public.mep_evidence_weight enable row level security;

insert into public.mep_evidence_weight
  (weight_key, evidence_source, variant, evidence_score, source_authority, exactness, auto_confirms, rationale) values
  ('structured_answer','structured_answer', null, 1.000, 'customer', 'exact_selection', true,
   'The customer picked the trade from a list. There is nothing to infer and nothing to confirm.'),
  ('customer_text.trade_name','customer_text','trade_name', 0.950, 'customer', 'exact_phrase', true,
   'The customer named the trade in their own words. Below structured selection only because free text can carry a passing mention.'),
  ('scope_rule.mep_full_scope','scope_rule','mep_full_scope', 0.900, 'derived_from_customer', 'phrase_rule', true,
   'An MEP anchor with a full-scope modifier, or an explicit full-MEP phrase. Derived from the customer''s words, so it confirms - but it is a rule, which is why it sits below a named trade.'),
  ('alias.unique','alias','unique', 0.750, 'customer', 'catalogue_alias', true,
   'A catalogue alias belonging to exactly one trade appeared in the customer text.'),
  ('document_extraction','document_extraction', null, 0.600, 'document', 'catalogue_alias', false,
   'An approved document contains an alias. NEVER auto-confirms, at any score: a drawing is not an instruction. The weight orders it against other evidence; the confirmation rule is separate and absolute.'),
  ('alias.ambiguous','alias','ambiguous', 0.400, 'customer', 'catalogue_alias', false,
   'The alias belongs to more than one trade, so the evidence does not say which. Proposes and asks.'),
  ('customer_text.trade_hint','customer_text','trade_hint', 0.400, 'customer', 'conventional_term', false,
   'A domain term that conventionally implies a trade without naming it - "mechanical" for HVAC. Strong enough to raise the trade, not to commit a workstream to it.')
on conflict (weight_key) do nothing;

comment on table public.mep_evidence_weight is
  'The rule weights, and why each is where it is. auto_confirms is NOT derived from the score: document evidence would never confirm even at 0.99, because the rule is about authority, not strength.';

create or replace function public.fn_norm_text(p_text text)
returns text language sql immutable as $fn$
  select translate(
           regexp_replace(
             lower(btrim(regexp_replace(coalesce(p_text,''), '\s+', ' ', 'g'))),
             '[ًٌٍَُِّْـٰ]', '', 'g'),
           'أإآٱىة', 'اااايه');
$fn$;

comment on function public.fn_norm_text(text) is
  'Lower-cases, collapses whitespace, strips Arabic diacritics and tatweel, folds alef forms (أإآٱ→ا), alef maqsura (ى→ي) and ta marbuta (ة→ه). Applied to both sides of every comparison. Harmless on Latin text.';

create or replace function public.fn_term_matches(
  p_text_norm text, p_pattern_norm text, p_lang text default 'en')
returns boolean language sql immutable as $fn$
  select case when p_lang = 'ar'
    then p_text_norm ~ ('(^|[^[:alnum:]])(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
                        || p_pattern_norm || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])')
    else p_text_norm ~ ('(^|[^[:alnum:]])' || p_pattern_norm || '($|[^[:alnum:]])')
  end;
$fn$;

create or replace function public.fn_text_matches_pattern(p_text text, p_pattern text)
returns boolean language sql immutable as $fn$
  select public.fn_term_matches(public.fn_norm_text(p_text), public.fn_norm_text(p_pattern), 'en');
$fn$;

-- pattern_norm should never have to be remembered by whoever adds a pattern.
create or replace function public.trg_mep_pattern_norm()
returns trigger language plpgsql as $fn$
begin
  new.pattern_norm := public.fn_norm_text(new.pattern);
  return new;
end $fn$;

alter table public.mep_trade_pattern add column if not exists pattern_norm text;

drop trigger if exists mep_trade_pattern_norm on public.mep_trade_pattern;
create trigger mep_trade_pattern_norm before insert or update on public.mep_trade_pattern
  for each row execute function public.trg_mep_pattern_norm();

-- Drop the old constraint FIRST, then reclassify, then tighten.
--   trade_name      - names a trade outright
--   trade_hint      - conventionally implies a trade; proposes, never confirms
--   mep_anchor      - MEP / electromechanical umbrella. NOT sufficient alone.
--   mep_full_phrase - an explicit full-MEP phrase, sufficient on its own
--   scope_full      - a generic full-scope modifier. Powerless without an anchor beside it.
--   scope_only      - exclusivity qualifier; suppresses the scope rule
alter table public.mep_trade_pattern drop constraint if exists mep_trade_pattern_kind_check;
update public.mep_trade_pattern set kind = 'mep_anchor' where kind = 'umbrella';
delete from public.mep_trade_pattern where kind = 'scope_full' and pattern in ('all trades','all disciplines');

insert into public.mep_trade_pattern (trade_key, kind, pattern, lang) values
  (null,'mep_full_phrase','mep package','en'),
  (null,'mep_full_phrase','full mep','en'),
  (null,'mep_full_phrase','complete mep','en'),
  (null,'mep_full_phrase','entire mep','en'),
  (null,'mep_full_phrase','whole mep','en'),
  (null,'mep_full_phrase','turnkey mep','en'),
  (null,'mep_full_phrase','full electromechanical','en'),
  (null,'mep_full_phrase','complete electromechanical','en'),
  (null,'mep_anchor','mep works','en'),
  (null,'mep_anchor','كهروميكانيكي','ar'),
  (null,'mep_anchor','كهروميكانيكيه','ar'),
  (null,'mep_full_phrase','اعمال كهروميكانيكيه كامله','ar'),
  (null,'scope_full','كامله','ar'),
  (null,'scope_full','شامله','ar'),
  (null,'scope_full','بالكامل','ar'),
  ('hvac','trade_name','تكييف','ar'), ('hvac','trade_name','مكيف','ar'),
  ('hvac','trade_name','تبريد','ar'), ('hvac','trade_name','تهويه','ar'),
  ('hvac','trade_name','تكييف مركزي','ar'),
  ('electrical','trade_name','كهربائيه','ar'), ('electrical','trade_name','كهربائي','ar'),
  ('electrical','trade_name','لوحات كهربائيه','ar'), ('electrical','trade_name','تمديدات كهربائيه','ar'),
  ('plumbing','trade_name','سباكه','ar'), ('plumbing','trade_name','صحيه','ar'),
  ('plumbing','trade_name','صرف صحي','ar'), ('plumbing','trade_name','ادوات صحيه','ar'),
  ('plumbing','trade_name','تمديدات المياه','ar'), ('plumbing','trade_name','مواسير المياه','ar'),
  ('plumbing','trade_name','شبكه المياه','ar'),
  ('fire','trade_name','مكافحه الحريق','ar'), ('fire','trade_name','انذار الحريق','ar'),
  ('fire','trade_name','اطفاء','ar'), ('fire','trade_name','رشاشات','ar'),
  ('elv','trade_name','تيار خفيف','ar'), ('elv','trade_name','انظمه امنيه','ar'),
  ('elv','trade_name','كاميرات مراقبه','ar'),
  -- Conventional terms. "mechanical" means HVAC in UAE MEP usage, but confirming a workstream off
  -- one ambiguous word is exactly the wrong dispatch this design exists to prevent.
  ('hvac','trade_hint','mechanical','en'),
  ('hvac','trade_hint','ميكانيكا','ar'),
  ('hvac','trade_hint','ميكانيكيه','ar')
on conflict (kind, pattern, lang) do nothing;

alter table public.mep_trade_pattern add constraint mep_trade_pattern_kind_check
  check (kind in ('trade_name','trade_hint','mep_anchor','mep_full_phrase','scope_full','scope_only'));

update public.mep_trade_pattern set pattern_norm = public.fn_norm_text(pattern) where pattern_norm is null;
alter table public.mep_trade_pattern alter column pattern_norm set not null;

-- THE HARDENED SCOPE RULE. Full core-MEP activation requires ONE of:
--   1. an explicit full-MEP phrase ("MEP package", "complete MEP", "اعمال كهروميكانيكيه كامله");
--   2. a full-scope modifier within two words of an MEP anchor, in the same clause;
--   3. all three core trades named explicitly (handled by the trade_name path);
--   4. structured selection of all three (handled by the structured path).
-- A bare anchor is never enough. A bare modifier is never enough.
create or replace function public.fn_mep_full_scope(p_text_norm text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare r record; v_re text;
begin
  for r in select pattern_norm, lang from public.mep_trade_pattern where kind = 'mep_full_phrase' loop
    if public.fn_term_matches(p_text_norm, r.pattern_norm, r.lang) then
      return jsonb_build_object('matched', true, 'basis', 'explicit_full_mep_phrase',
                                'anchor', r.pattern_norm, 'modifier', null);
    end if;
  end loop;

  for r in
    select a.pattern_norm as anchor, m.pattern_norm as modifier, a.lang
      from public.mep_trade_pattern a
      join public.mep_trade_pattern m on m.kind = 'scope_full'
     where a.kind = 'mep_anchor'
  loop
    v_re := '(^|[^[:alnum:]])' || r.anchor || '([^[:alnum:]]+[^[:space:].;،؛]+){0,2}[^[:alnum:]]+'
            || r.modifier || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
    v_re := '(^|[^[:alnum:]])' || r.modifier || '([^[:alnum:]]+[^[:space:].;،؛]+){0,2}[^[:alnum:]]+'
            || r.anchor || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                'anchor', r.anchor, 'modifier', r.modifier);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'basis', null);
end $fn$;

comment on function public.fn_mep_full_scope(text) is
  'The only path by which generic words like full/complete/package reach the three core trades. They must sit within two words of an MEP anchor in the same clause, or the text must carry an explicit full-MEP phrase.';

create view public.v_inquiry_trade_status as
select c.group_id, c.trade_key, t.label_en, t.is_core, c.status, c.evidence_source,
       c.evidence_score, c.score_basis, c.confirmation_factors,
       c.requires_confirmation, c.match_reason,
       c.proposed_at, c.confirmed_at, c.confirmed_by, c.rejected_at, c.rejection_reason,
       c.inactivated_at, c.activated_at, c.workstream_id,
       w.active as workstream_active,
       (select count(*) from public.inquiry_trade_candidate_evidence e where e.candidate_id = c.id) as evidence_rows,
       (c.status = 'confirmed' and w.active) as counts_toward_dispatch
  from public.inquiry_trade_candidate c
  join public.mep_trade t on t.trade_key = c.trade_key
  left join public.inquiry_workstream w on w.id = c.workstream_id;

revoke all on function public.fn_norm_text(text) from public, anon, authenticated;
revoke all on function public.fn_term_matches(text, text, text) from public, anon, authenticated;
revoke all on function public.fn_mep_full_scope(text) from public, anon, authenticated;
