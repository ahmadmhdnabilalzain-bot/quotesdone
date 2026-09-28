-- A CLAIMED COMPANY CANNOT BE REGISTERED TWICE, UNDER ANOTHER SPELLING OR THE SAME LICENCE
-- (24 Sep 2026, sales_engineer)
--
-- WHAT WAS MEASURED. PR #944 (ledger 993) made supplier_api create_company refuse a second account
-- registering the exact name of an already-claimed company (409 company_already_registered). That
-- guard is an application-side ilike on the whole name, so three gaps remain, each read off the code:
--   * "ZZ Demo Steel Co. L.L.C." and "zz demo steel co llc" are different strings, so the second is
--     accepted: a dot, a bracket or a spelling of the legal form registers the same company twice;
--   * nothing compares the trade licence number, so one licence can back two claimed profiles;
--   * the check-then-insert is not atomic (the #944 reviewer's note): two concurrent registrations can
--     both pass the check. Only a unique index closes that.
-- Production, read-only, 24 Sep 2026 (22,269 leads, 2 claimed, 4 carrying a licence number): ZERO
-- duplicates under the name key below among claimed rows, ZERO under the licence key among claimed
-- rows, and also zero under both keys across claimed-or-registration_status rows and across every
-- row carrying a licence. So both indexes are creatable today with no exclusion list.
--
-- HOW CONSERVATIVE THE NAME KEY IS, MEASURED OVER THE WHOLE DIRECTORY (review of #962). The first
-- draft DROPPED trailing legal forms and "trading"/"est"/"co". Run over all 22,269 names it merged
-- differently spelled names (case and spacing aside) under 172 keys, 67 of them across emirates:
-- "AL NOOR CONTRACTING EST" = "AL NOOR CONTRACTING CO", "ACE" = "ACE TRADING FZE", and a free-zone
-- FZCO = a mainland LLC of the same words. Those are separate legal companies, and a false match locks
-- a real one out for good. This key KEEPS the legal form and every word, and folds only how they are
-- SPELT. The same measurement now gives 100 keys, 14 across emirates, and every one read on 24 Sep is
-- a spelling of one company: "CO. L.L.C" = "CO LLC", "&#038;" = "&", "DECOR EST" = "Decor
-- Establishment", "MODERN ELEVATORS CO WLL" = "... COMPANY WLL", "AL-BARIQ" = "AL BARIQ".
--
-- WHAT THIS CHANGES
--   1. public.fn_company_registration_name_key(text) -- IMMUTABLE, deterministic; each rule is
--      explained where it is applied.
--   2. public.fn_trade_licence_key(text) -- IMMUTABLE; upper case, letters and digits only.
--   3. Two partial unique indexes on public.leads, restricted to claimed rows.
--   The edge functions recognise a 23505 naming either index in supabase/functions/_shared/
--   duplicate_company.ts: a registration gets the EXISTING company_already_registered answer (no new
--   copy); a document write sets the clashing licence number aside and asks a human.
--
-- WHY "claimed" AND NOT registration_status / verified. `claimed` is the one flag both registration
-- doors set (create_company inserts claimed = true; claim updates it) and the flag the #944 guard
-- already reads. registration_status is also written on UNCLAIMED demo fixtures (129923, 130110 on
-- 24 Sep), and verified is a later approval step, so neither means "an account holds this company".
-- Unclaimed scraped leads (the 22k directory) are deliberately outside both indexes: the directory
-- legitimately holds near-duplicates, and a scraped row must stay claimable.
--
-- WHY NOT fn_company_name_norm. It already exists (fn_supplier_licence_name_mismatch uses it), but it
-- removes words from ANYWHERE in the name -- 'and', 'the', 'company', 'branch', 'llc', 'fze' -- and
-- joins what is left with no spaces. That is right for a mismatch SIGNAL (a false alarm costs a human
-- review) and wrong for a hard REFUSAL. fn_company_name_norm is not changed.
--
-- IF DUPLICATES APPEAR BEFORE THIS IS APPLIED. Nothing is deleted or merged, ever. Section 3 is a
-- deliberate PRECONDITION that aborts the apply, naming the ids; the fix is then to add
-- `and id not in (<ids>)` to the predicate of the index that failed, with a comment naming the ids and
-- the date, and re-apply. That keeps the existing rows untouched and still refuses every NEW duplicate.
-- (A trigger was rejected: a trigger check is not atomic under concurrency, which is the gap in #944.)
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--   * does not touch any row; no update, no delete, no merge;
--   * does not drop any word, legal form included: "X LLC", "X FZCO", "X EST" and "X" are four keys;
--   * does not equate ش.ذ.م.م (single-owner LLC) with ذ.م.م / LLC: only its spellings are folded;
--   * does not key the licence on its issuing authority: license_authority is free text read off a
--     document ("Dubai DET (fixture)"), so keying on it would let a retyped authority bypass the rule.
--     The cost: two emirates issuing the same number would collide; none do on 24 Sep (4 licences, all
--     distinct), and the refusal names management@ for exactly that case.

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
  with
  -- 1. Arabic: hamza/alef forms, taa marbuta, alef maqsura, tashkeel, tatweel and Arabic digits,
  --    folded by the estate's existing normaliser. 2. Case: lower().
  a as (select lower(public.fn_ar_norm(p)) as s),
  -- 3. HTML ENTITIES. 2,143 of the 22,269 directory names carried one on 24 Sep, scraped from web
  --    pages ("GOLDEN OCEAN ... TRADING &#038; ELEC"). &amp; / &#038; / &#x26; are "&"; the apostrophe
  --    entities are an apostrophe (removed in step 5); any other entity (&#8211; en dash, &nbsp;)
  --    is a separator, like the punctuation it stands for.
  b as (select regexp_replace(
                 regexp_replace(
                   regexp_replace(s, '&(amp|#0*38|#x0*26);', '&', 'g'),
                   '&(apos|rsquo|lsquo|#0*39|#x0*27|#8216|#8217);', '''', 'g'),
                 '&#?[a-z0-9]+;', ' ', 'g') as s from a),
  -- 4. "&" is the word "and": "A & B Glass" = "A and B Glass".
  -- 5. Dots and apostrophes VANISH rather than split: "L.L.C." is "llc", "F.Z.E" is "fze", "Co." is
  --    "co", "Mu'min" is "mumin".
  -- 6. Every other run of non letters/digits (spaces, hyphens, brackets, commas, slashes) is ONE
  --    space: "AL-BARIQ" = "AL BARIQ", "(L.L.C)" = "llc", "FZ-LLC" = "fz llc".
  c as (select btrim(regexp_replace(regexp_replace(replace(s, '&', ' and '), '[.''’‘`]', '', 'g'),
                                    '[^[:alnum:]]+', ' ', 'g')) as s from b),
  -- 7. THE SPELLING OF A LEGAL FORM, KEPT AS PART OF THE KEY (whole words only, \m...\M):
  --      "l l c" -> llc;  "f z e" -> fze;  "f z c o" -> fzco;  "fz llc" / "f z llc" -> fzllc
  --      (after step 6 "FZ-LLC" and "FZ LLC" are both "fz llc", and "FZLLC" is already one word);
  --      "establishment" -> est;  "company" -> co;
  --      Arabic: "ش ذ م م" -> شذمم (single-owner LLC, its own form); "ذ م م" and "ذمم" -> llc,
  --      because ذ.م.م IS the Arabic spelling of L.L.C. The spaced ش form is folded first so its
  --      tail is not read as ذ م م.
  --    Nothing is dropped: "X LLC" and "X FZE" stay two keys.
  d as (select
          regexp_replace(regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(s,
            '\ml l c\M', 'llc', 'g'),
            '\mf z e\M', 'fze', 'g'),
            '\mf z c o\M', 'fzco', 'g'),
            '\mf ?z llc\M', 'fzllc', 'g'),
            '\mestablishment\M', 'est', 'g'),
            '\mcompany\M', 'co', 'g'),
            '\mش ذ م م\M', 'شذمم', 'g'),
            '\mذ م م\M', 'llc', 'g'),
            '\mذمم\M', 'llc', 'g') as s from c)
  -- A name with no letters or digits has no key; NULL never conflicts in a unique index.
  select nullif(btrim(s), '') from d
$fn$;

comment on function public.fn_company_registration_name_key(text) is
  'The key two claimed companies may not share (leads_claimed_company_name_uidx). Folds case, whitespace, punctuation, HTML entities, & = and, Arabic letter forms, and the SPELLING of a legal form (L.L.C = LLC = the Arabic abbreviation of LLC, F.Z.E = FZE, FZ-LLC = FZLLC, Establishment = EST, Company = CO). Drops no word: the legal form stays part of the key, so an FZE and an LLC of the same words are two companies.';

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
-- 3. PRECONDITION: EXISTING DUPLICATES ABORT THE APPLY BY ID -- NOTHING IS EVER DELETED
-- ---------------------------------------------------------------------------------------------
-- A deliberate precondition, NOT a verdict probe: it raises on purpose so the whole file rolls back
-- before an index is attempted, and says which rows to exclude. Zero on 24 Sep 2026. If it raises,
-- read the header: add the named ids to the failing index's predicate.
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
-- Their NAMES are read by supabase/functions/_shared/duplicate_company.ts to recognise a duplicate
-- company among other 23505s; renaming one here without renaming it there turns the refusal into a 500.
-- Not CONCURRENTLY, because this file holds more than one statement: scripts/apply_sql.mjs sends a
-- CONCURRENTLY file on its own, and a second statement in the same query would wrap it in an implicit
-- transaction that Postgres refuses. Splitting it out is not needed: a plain build holds a SHARE lock
-- on leads (reads continue, writes wait) for one scan of ~22k rows, well under a second, and the lock
-- timeout makes a busy table fail the apply instead of queueing every registration behind it.
set local lock_timeout = '5s';

create unique index if not exists leads_claimed_company_name_uidx
  on public.leads (public.fn_company_registration_name_key(company_name))
  where claimed;

create unique index if not exists leads_claimed_trade_licence_uidx
  on public.leads (public.fn_trade_licence_key(trade_license_no))
  where claimed;
