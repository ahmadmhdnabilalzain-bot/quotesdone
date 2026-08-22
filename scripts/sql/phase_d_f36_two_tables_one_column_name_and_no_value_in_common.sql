-- F36 - two tables, one column name, and not one value in common
--
-- MEASURED. After F32 let the capability provenance through the output contract and F33/F34 supplied
-- the measurement values, all five capability-first workflows -- W11, W21, W23, W25, W29 -- reach
-- the effect write and fail there:
--
--   W11-S01 :: new row for relation "phase_d_effect_ledger" violates check constraint
--              "phase_d_effect_ledger_mode_ck"
--
-- THE TWO VOCABULARIES:
--
--   public.phase_d_capability_result.provider_mode   CHECK (in ('fixture','provider'))
--   public.phase_d_effect_ledger.provider_mode       CHECK (in ('none','mock','disabled'))
--
-- Disjoint. Not one value in common. A capability result can only ever be 'fixture' or 'provider',
-- and the ledger that records the effect resting on it can record neither. So the moment a
-- capability step actually succeeded -- which it never had until this session -- its effect became
-- unwritable. The estate has a name for this shape: two gates, one vocabulary, and nothing keeping
-- them in step.
--
-- WHY 'fixture' IS ADDED AND NOT FOLDED INTO 'mock'. The founder's ruling of 22 Aug 2026 section 4
-- lists CAPABILITY_FIXTURE_RESULT and MOCK_EXTERNAL_EFFECT_RESULT as SEPARATE execution-input
-- classes and section 4 again requires them "reported separately". Writing 'mock' into the ledger
-- for a committed capability fixture would merge exactly the two classes he asked to be told apart,
-- and it would do it in the one table the evidence is read from.
--
-- NOTHING IS WEAKENED, AND ONE THING IS TIGHTENED. 'provider' remains impossible in the ledger, and
-- after this file it is impossible BY NAME rather than by omission: the second constraint below
-- refuses it explicitly and says why, so a future edit that widens the list has to delete a
-- statement that argues against itself. Under the founder's hold the only reachable capability mode
-- is 'fixture' anyway -- fn_phase_d_capability_result_accept refuses provider_mode = 'provider'
-- while the hold stands -- and this file does not touch that refusal.

begin;

alter table public.phase_d_effect_ledger
  drop constraint if exists phase_d_effect_ledger_mode_ck;

alter table public.phase_d_effect_ledger
  add constraint phase_d_effect_ledger_mode_ck
  check (provider_mode = any (array['none'::text, 'mock'::text, 'disabled'::text, 'fixture'::text]));

-- The explicit half. 'provider' is not merely absent from the list above; it is refused here with a
-- constraint whose name states the rule, so the two can never disagree silently and a widening edit
-- has to remove a named prohibition rather than extend an array.
alter table public.phase_d_effect_ledger
  drop constraint if exists phase_d_effect_ledger_never_a_live_provider;

alter table public.phase_d_effect_ledger
  add constraint phase_d_effect_ledger_never_a_live_provider
  check (provider_mode is distinct from 'provider');

comment on constraint phase_d_effect_ledger_mode_ck on public.phase_d_effect_ledger is
  'none, mock, disabled or fixture. fixture was added by F36 because public.phase_d_capability_result '
  'can only ever hold fixture or provider, so an effect resting on a committed capability fixture had '
  'no representable mode and could not be written at all. Folding it into mock was refused: the '
  'founder''s section 4 requires CAPABILITY_FIXTURE_RESULT and MOCK_EXTERNAL_EFFECT_RESULT be reported '
  'apart, and the ledger is where that report is read from.';

comment on constraint phase_d_effect_ledger_never_a_live_provider on public.phase_d_effect_ledger is
  'A live provider result may never be recorded as having produced a Phase D effect. Paid inference '
  'and every external provider are held; this states the prohibition by name rather than leaving it '
  'to the absence of a value from a list.';

commit;
