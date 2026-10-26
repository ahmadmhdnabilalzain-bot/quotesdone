-- THE OBSERVE / CONTROL MODE DRAWER IS GONE; ITS FOUR ACTIONS LEAVE THE REGISTRY WITH IT.
--
-- Founder, 10 Aug 2026: "no need for that observe mode … Remove the gate." The OS shell still carried the
-- header pill ("Control Mode is switched off …") and the "Observe Mode — send a code to my phone" drawer
-- on 6 Sep 2026. Both were removed from src/components/osx (ControlMode.tsx deleted, OsxShell no longer
-- mounts the provider) and os_api no longer dispatches control_mode_status / _challenge / _open / _close.
-- control_mode_action is the database half of the action classification gate; a row for an action the
-- code no longer dispatches is a stale registration, so the four rows go. The gate itself (every OTHER
-- action classified read_only / mutating / founder_gated, unclassified refused) is untouched.
--
--   node scripts/apply_sql.mjs scripts/sql/observe_mode_drawer_removed.sql --apply --ddl
begin;
delete from public.control_mode_action
 where action in ('control_mode_status', 'control_mode_challenge', 'control_mode_open', 'control_mode_close');
commit;
