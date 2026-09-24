-- A CLAIMED COMPANY CANNOT BE REGISTERED TWICE, UNDER ANOTHER SPELLING OR THE SAME LICENCE
-- (24 Sep 2026, sales_engineer)
--
-- WHAT WAS MEASURED. PR #944 (ledger 993) made supplier_api create_company refuse a second account
-- registering the exact name of an already-claimed company (409 company_already_registered). That
-- guard is an application-side ilike on the whole name, so three gaps remain, each read off the code:
--   * "ZZ Demo Steel Trading L.L.C." and "zz demo steel FZ-LLC" are different strings, so the second
--     is accepted: a legal suffix, a dot or a hyphen is enough to register the same company twice;
--   * nothing compares the trade licence number, so one licence can back two claimed profiles;
--   * the check-then-insert is not atomic (the #944 reviewer's note): two concurrent registrations can
--     both pass the check. Only a unique index closes that.
-- Production, read-only, 24 Sep 2026 (22,269 leads, 2 claimed, 4 carrying a licence number): ZERO
-- duplicates under the name key below among claimed rows, ZERO under the licence key among claimed
-- rows, and also zero under both keys across claimed-or-registration_status rows and across every
-- row carrying a licence. So both indexes are creatable today with no exclusion list.
--
-- WHAT THIS CHANGES
--   1. public.fn_company_registration_name_key(text) -- IMMUTABLE, deterministic; each rule is
--      explained where it is applied.
--   2. public.fn_trade_licence_key(text) -- IMMUTABLE; upper case, letters and digits only.
--   3. Two partial unique indexes on public.leads, restricted to claimed rows.
--   supplier_api maps a 23505 naming either index to the EXISTING company_already_registered answer
--   (supabase/functions/supplier_api/company_already_registered.ts); no new copy.
--
-- WHY "claimed" AND NOT registration_status / verified. `claimed` is the one flag both registration
-- doors set (create_company inserts claimed = true; claim updates it) and the flag the #944 guard
-- already reads. registration_status is also written on UNCLAIMED demo fixtures (129923, 130110 on
-- 24 Sep), and verified is a later approval step, so neither means "an account holds this company".
-- Unclaimed scraped leads (the 22k directory) are deliberately outside both indexes: the directory
-- legitimately holds near-duplicates, and a scraped row must stay claimable.
--
-- WHY NOT fn_company_name_norm. It already exists (fn_supplier_licence_name_mismatch uses it), but it
-- removes words from ANYWHERE in the name -- 'and', 'the', 'company', 'branch', 'sole' -- and joins what
-- is left with no spaces. That is right for a mismatch SIGNAL (a false alarm costs a human review) and
-- wrong for a hard REFUSAL (a false match locks a real company out of the marketplace). This key strips
-- legal-form words from the END only and keeps word boundaries. fn_company_name_norm is not changed.
--
-- IF DUPLICATES APPEAR BEFORE THIS IS APPLIED. Nothing is deleted or merged, ever. Section 3 counts
-- them first and stops the apply with their ids; the fix is then to add `and id not in (<ids>)` to the
-- predicate of the index that failed, with a comment naming the ids and the date, and re-apply. That
-- keeps the existing rows untouched and still refuses every NEW duplicate. (The alternative of a
-- trigger was rejected: a trigger check is not atomic under concurrency, which is the gap in #944.)
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--   * does not touch any row; no update, no delete, no merge;
--   * does not strip Arabic legal words that stand at the START of a name (شركة / مؤسسة): stripping a
--     leading word is how two different companies collide, so only trailing forms are removed;
--   * does not key the licence on its issuing authority: license_authority is free text read off a
--     document ("Dubai DET (fixture)"), so keying on it would let a retyped authority bypass the rule.
--     The cost: two emirates issuing the same number would collide; none do on 24 Sep (4 licences, all
--     distinct), and the refusal names management@ for exactly that case;
--   * does not change the other writers of trade_license_no (wa_inbound, resend_inbound,
--     supplier_portal): on a collision their update is refused by the index like any other.

-- ---------------------------------------------------------------------------------------------
-- 1. THE NAME KEY
-- ---------------------------------------------------------------------------------------------
-- SECURITY INVOKER, no revoke: it reads no table and returns a function of its argument only, the same
-- as fn_ar_norm and fn_company_name_norm. It must stay executable by every role that can write leads,
-- because index maintenance evaluates it on each insert/update of a claimed row.
-- It calls public.fn_ar_norm, which is IMMUTABLE (measured 24 Sep). If fn_ar_norm is ever changed,
-- reindex leads_claimed_company_name_uidx in the same file.
create or replace function public.fn_company_registration_name_key(p text)
returns text
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $fn$
  select nullif(
    -- 6. LEGAL FORM, TRAILING ONLY. One or more of these words at the END are removed, so
    --    "Steel Trading L.L.C." = "Steel FZ-LLC" = "Steel Co. Est." = "Steel". The leading space in
    --    the pattern means the FIRST word is never removed: "LLC" alone stays "llc", never empty.
    --    fz + llc covers FZ-LLC (the hyphen became a space in step 5); ذمم / شذمم are ذ.م.م / ش.ذ.م.م
    --    after step 4, and the spaced forms are written out because the letters stand alone.
    regexp_replace(
      -- 5. Every run of anything that is not a letter or digit (spaces, hyphens, brackets, commas,
      --    slashes) becomes ONE space, then the ends are trimmed: "zz demo  steel (LLC)" is
      --    "zz demo steel llc".
      btrim(regexp_replace(
        -- 4. Dots and apostrophes VANISH rather than split: "L.L.C." is "llc", "F.Z.E" is "fze",
        --    "Mu'min" is "mumin".
        regexp_replace(
          -- 3. "&" is the word "and", so "A & B Glass" = "A and B Glass".
          replace(
            -- 2. Case: lower().
            lower(
              -- 1. Arabic: hamza/alef forms, taa marbuta, alef maqsura, tashkeel, tatweel and Arabic
              --    digits folded by the estate's existing normaliser.
              public.fn_ar_norm(p)),
            '&', ' and '),
          '[.''’‘`]', '', 'g'),
        '[^[:alnum:]]+', ' ', 'g')),
      '( (llc|fze|fzco|fzllc|fz|est|establishment|trading|co|ذمم|شذمم|ذ م م|ش ذ م م))+$', ''),
    '')   -- a name with no letters or digits has no key; NULL never conflicts in a unique index
$fn$;

comment on function public.fn_company_registration_name_key(text) is
  'The key two claimed companies may not share (leads_claimed_company_name_uidx). Case, whitespace, punctuation, Arabic letter forms and TRAILING legal-form words (LLC, L.L.C, FZE, FZCO, FZ-LLC, Est, Establishment, Trading, Co, ذ.م.م, ش.ذ.م.م) are folded. Conservative by design: nothing is removed from the start or middle of a name.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE LICENCE KEY
-- ---------------------------------------------------------------------------------------------
-- Upper case, letters and digits only: "cn-123 4567", "CN1234567" and "CN/123/4567" are one licence.
-- Leading zeros are kept (some authorities print them; stripping them could merge two numbers).
-- SECURITY INVOKER, no revoke, for the same reason as section 1.
create or replace function public.fn_trade_licence_key(p text)
returns text
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $fn$
  select nullif(regexp_replace(upper(coalesce(p, '')), '[^[:alnum:]]+', '', 'g'), '')
$fn$;

comment on function public.fn_trade_licence_key(text) is
  'The key two claimed companies may not share (leads_claimed_trade_licence_uidx): the trade licence number in upper case with every non-alphanumeric character removed.';

-- ---------------------------------------------------------------------------------------------
-- 3. EXISTING DUPLICATES STOP THE APPLY BY ID -- NOTHING IS EVER DELETED
-- ---------------------------------------------------------------------------------------------
-- Zero on 24 Sep 2026. If this raises, read the header: add the named ids to the index predicate.
do $$
declare v_name text; v_lic text;
begin
  select string_agg(ids, '; ') into v_name from (
    select array_agg(id order by id)::text as ids from public.leads
     where claimed and public.fn_company_registration_name_key(company_name) is not null
     group by public.fn_company_registration_name_key(company_name) having count(*) > 1) d;
  select string_agg(ids, '; ') into v_lic from (
    select array_agg(id order by id)::text as ids from public.leads
     where claimed and public.fn_trade_licence_key(trade_license_no) is not null
     group by public.fn_trade_licence_key(trade_license_no) having count(*) > 1) d;
  if v_name is not null or v_lic is not null then
    raise exception 'claimed duplicates exist; exclude them by id in the index predicate, never delete. name: % licence: %',
      coalesce(v_name, 'none'), coalesce(v_lic, 'none');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. THE INDEXES
-- ---------------------------------------------------------------------------------------------
-- Their NAMES are read by supplier_api (company_already_registered.ts) to recognise a duplicate
-- company among other 23505s; renaming one here without renaming it there turns the refusal into a 500.
-- Not CONCURRENTLY: the applier runs the file as one transaction, where CONCURRENTLY is refused. Each
-- build holds a SHARE lock on leads (reads continue, writes wait) for one scan of ~22k rows; the lock
-- timeout makes a busy table fail the apply instead of queueing every registration behind it.
set local lock_timeout = '5s';

create unique index if not exists leads_claimed_company_name_uidx
  on public.leads (public.fn_company_registration_name_key(company_name))
  where claimed;

create unique index if not exists leads_claimed_trade_licence_uidx
  on public.leads (public.fn_trade_licence_key(trade_license_no))
  where claimed;
