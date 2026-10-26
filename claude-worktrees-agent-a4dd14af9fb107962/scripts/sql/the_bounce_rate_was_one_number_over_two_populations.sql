-- THE BOUNCE RATE WAS ONE NUMBER OVER TWO POPULATIONS
--
-- The founder pushed back on my calling the 10.3% bounce rate a decision for him, and he was right:
-- verifying a mailing list is engineering, not a founder call. So I measured it properly instead of
-- escalating it, and the number turns out to be measuring something other than what its name says —
-- the fourth instance of that this session.
--
-- Split by address type, every send this company has ever made:
--
--     role addresses (info@, support@, sales@ …)   58 sent   5 bounced   8.6%
--     named humans                                 13 sent   0 bounced   0.0%
--
-- And by date: EVERY bounce came from a role address sent on or before 6 Aug. The nine invitations
-- sent on the night of 12 Aug were all named humans and all nine were delivered. The role-last
-- ordering shipped between those two dates.
--
-- So the 10.3% seven-day rate that now holds the cap at its floor is a rate over a population the
-- ramp has largely stopped sending to, mixed with one it has barely started sending to. It is not
-- wrong arithmetic; it is one number over two populations that behave nothing like each other, and
-- it will keep the ramp at 10/day — 19,841 uncontacted leads, five years at that rate — on the
-- strength of mailboxes we are no longer aiming at.
--
-- WHAT THIS CHANGE DOES NOT DO. It does not touch the throttle. The obvious move is to compute the
-- rate over named humans only, which would read 0% and let the ramp warm up tonight — and that
-- would be weakening a brake on a 13-send sample, which is the exact mistake the 11 Aug comment in
-- this function already warns about: "A sample too small to justify HALVING is not a sample that
-- licenses DOUBLING." Thirteen sends and no bounces is not evidence that the list is clean. It is
-- an absence of evidence that it is dirty.
--
-- WHAT IT DOES. It makes the number explain itself, in the row the function writes every morning:
-- both populations, both rates, and their sample sizes, so that the next person to read "10.3%"
-- can see in the same sentence that 5 of 5 bounces are role addresses and the named-human column
-- reads 0 of 13. That is what turns this from a founder decision into an engineering one — which is
-- what he said it was.
--
-- WHAT COMES NEXT, and it needs one more measurement, not a judgement: once ~20 named-human sends
-- have accumulated (13 now, 10/day cap, so within a day) their rate is worth acting on. If it holds
-- near zero, the throttle should read the segment being sent rather than the blended figure, WITH a
-- minimum-sample floor for warming up that the current code does not have. Do not make that change
-- on 13 sends.
do $$
declare v_def text; v_new text; v_oid oid; a1 text; b1 text; a2 text; b2 text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_invite_ramp' and p.pronargs = 0;
  if v_oid is null then raise exception 'fn_invite_ramp() not found'; end if;
  v_def := pg_get_functiondef(v_oid);

  -- 1. four more locals, and the split measured beside the blended rate it explains
  a1 := $q$  v_rate := v_bounced7::numeric / greatest(v_sent7,1);$q$;
  b1 := $q$  v_rate := v_bounced7::numeric / greatest(v_sent7,1);

  -- THE SAME WINDOW, SPLIT BY WHO WE WROTE TO. A shared inbox and a named person are not one
  -- population: measured over every invitation ever sent, role addresses bounce at 8.6% (5/58) and
  -- named humans at 0% (0/13), and every bounce on record predates the role-last ordering.
  select count(*) filter (where not r), count(*) filter (where not r and b),
         count(*) filter (where r),     count(*) filter (where r and b)
    into v_named7, v_named_b7, v_role7, v_role_b7
    from (select (split_part(email,'@',1) ~* '^(info|support|sales|admin|contact|enquiry|enquiries|inquiry|office|mail|hello|team|general|reception|marketing|accounts|hr)$') as r,
                 (invite_status = 'bounced') as b
            from leads where invited_at > now() - interval '7 days') z;$q$;

  -- 2. carry both populations into the row it writes every morning
  a2 := $q$'sent_7d',v_sent7,'bounced_7d',v_bounced7,$q$;
  b2 := $q$'sent_7d',v_sent7,'bounced_7d',v_bounced7,
                              'named_sent_7d',v_named7,'named_bounced_7d',v_named_b7,
                              'role_sent_7d',v_role7,'role_bounced_7d',v_role_b7,
                              'named_bounce_pct_7d',round((v_named_b7::numeric/greatest(v_named7,1))*100,1),
                              'role_bounce_pct_7d',round((v_role_b7::numeric/greatest(v_role7,1))*100,1),$q$;

  if (length(v_def) - length(replace(v_def, a1, ''))) / nullif(length(a1),0) <> 1 then
    raise exception 'anchor 1 (v_rate assignment) not found exactly once'; end if;
  if (length(v_def) - length(replace(v_def, a2, ''))) / nullif(length(a2),0) <> 1 then
    raise exception 'anchor 2 (counts object) not found exactly once'; end if;

  v_new := replace(replace(v_def, a1, b1), a2, b2);
  -- the four locals have to exist before the body that assigns them
  v_new := replace(v_new,
    $q$  v_uncontacted int; v_max_rate numeric; v_at_floor boolean := false;$q$,
    $q$  v_uncontacted int; v_max_rate numeric; v_at_floor boolean := false;
  v_named7 int := 0; v_named_b7 int := 0; v_role7 int := 0; v_role_b7 int := 0;$q$);
  -- and the note has to say it, because a jsonb column is not what anyone reads at 6am
  v_new := replace(v_new,
    $q$           coalesce(v_note,''), now());$q$,
    $q$           coalesce(v_note,'')||' | SPLIT 7d: named '||v_named_b7||'/'||v_named7
             ||' ('||round((v_named_b7::numeric/greatest(v_named7,1))*100,1)||'%), role '
             ||v_role_b7||'/'||v_role7||' ('||round((v_role_b7::numeric/greatest(v_role7,1))*100,1)
             ||'%) - a shared inbox and a named person are not one population.', now());$q$);
  if v_new = v_def then raise exception 'the replacements changed nothing'; end if;
  execute v_new;
end $$;
