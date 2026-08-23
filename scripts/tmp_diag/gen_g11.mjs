import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G11 — the object whose canonical relation is the outbound queue, and the answer with no group
--
-- Two of the five objects G10 left without a fixture stage, each for its own reason.
--
-- 1. notification. Its canonical relation is public.notifications -- the outbound queue itself. The
--    scenario factory asserts, after every stage, that the table has not gained a row, and aborts
--    the whole build if it has. That assertion is right and stays: it was built because a canonical
--    write to some OTHER object queued a message as a side effect, and that is the property the
--    Phase D hold depends on.
--
--    What it could not distinguish is the one stage whose declared object IS the notification. So
--    the assertion is narrowed by derivation, not by exception: a stage may write into a relation
--    that is its own object's canonical relation, and only if every row it wrote carries the
--    suppression the outbound door declares for that relation. Any other stage writing there still
--    aborts the build, and so does this one if the row is not suppressed.
--
--    THE SUPPRESSION IS THE PRODUCT'S OWN COLUMN, as with the two doors already registered.
--    public.notifications.status is what every sender selects on -- send_sms and send_whatsapp read
--    'queued', alert_founder writes 'queued', the digest trigger writes 'digest', the demo guard
--    writes 'held'. A row at 'suppressed' is selected by none of them. It is written that way by
--    fn_phase_d_object_write's existing outbound-door loop, which runs in verified fixture context
--    only and does not let a caller opt out, so the fixture cannot ask for anything else.
--
--    The four triggers on the relation were read before this was written, not after: fn_wa_fanout
--    returns unchanged unless to_role is supplier or customer AND that party has wa_optin;
--    fn_notifications_digest returns unchanged unless to_role is admin, founder or owner;
--    fn_invite_status_on_send requires type 'supplier_invite' at status 'sent';
--    zzz_notifications_demo_guard is inert unless decision_policy.demo_rehearsal_active is true.
--    The stage's row is to_role 'phase_d_fixture', type 'phase_d_fixture', channel 'none', and the
--    recipient is the committed catalogue's reserved .invalid address.
--
-- 2. inquiry_answer. Its stage has existed since D9c and has never once created its object,
--    reporting BLOCKED_NO_REFERENCE_DATA because public.inquiry_workstream_group holds 0 rows and
--    "this factory does not create business reference data". That rule is right about suppliers,
--    customers and field definitions -- rows the estate shares. A workstream group is not one of
--    those: it is a structural child of ONE inquiry, it carries an inquiry_id foreign key and a
--    defaulted rfq_mode and nothing else, and the inquiry in question is the one this scenario
--    created four stages earlier. Creating a group FOR THE SCENARIO'S OWN INQUIRY is the same act
--    as creating any other child of it, and it is rolled back with the rest.
--
--    The reference_relation guard is left in place on the row so that a group belonging to some
--    other inquiry is still never invented; what changes is that the stage now creates its own.
--
-- ROLLBACK: delete the two phase_d_fixture_stage rows and the notification write map and outbound
-- door rows; re-apply the previous fn_phase_d_fixture_scenario body. Nothing here is DDL.
--
-- Two anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const ROWS = `
insert into public.phase_d_object_write_map
  (object_id, target_relation, operation, key_column, owner_column, column_map, quarantine_note)
values ('notification','public.notifications','INSERT_ONLY','id','to_role',
        jsonb_build_object('type','type','to_role','owner_ref','to_email','to_email',
                           'subject','subject','body','body','status','state','channel','channel'),
        'The canonical relation of this object IS the outbound queue. Every Phase D write to it is forced to the suppression public.phase_d_outbound_door declares, in verified fixture context only, and the scenario factory aborts if a row is written here by any stage whose object is not this one.')
on conflict (object_id) do nothing;

insert into public.phase_d_outbound_door
  (relation, trigger_name, function_name, endpoint, disposition, guard_column, suppression_sql,
   unreachable_because_column, guard_condition, note)
values ('public.notifications','(the senders, not a trigger)','send_outbox / send_sms / send_whatsapp',
        'the outbound queue itself','SUPPRESSED_BY_ITS_OWN_GUARD','status','to_jsonb(''suppressed''::text)',
        null,
        'Not a trigger: the senders SELECT on public.notifications.status. send_sms and send_whatsapp read status = queued; alert_founder and ai_health write queued; fn_notifications_digest writes digest; zzz_notifications_demo_guard writes held. No sender selects suppressed.',
        'MEASURED BY READING EVERY SENDER: the four triggers on this relation are each inert for the row the fixture writes (fn_wa_fanout needs to_role supplier/customer with wa_optin; fn_notifications_digest needs to_role admin/founder/owner; fn_invite_status_on_send needs type supplier_invite at status sent; zzz_notifications_demo_guard needs decision_policy.demo_rehearsal_active). The suppression is on the status column because that is what the SENDERS read, and a suppressed row is selected by none of them.')
on conflict do nothing;

insert into public.phase_d_fixture_stage
  (stage_no, stage_key, object_id, requires_stages, contributes_ref, reference_relation, note,
   working_state, working_state_evidence, contributes_kind, working_payload, working_payload_evidence)
values
  (400,'notification','notification','{}',null,null,
   'W13. The notification record itself. Its canonical relation is the outbound queue, so the row is written at the suppression public.phase_d_outbound_door declares and no sender selects it.',
   'suppressed','MEASURED, not declared: public.notifications has no CHECK on status, and every sender selects on that column -- send_sms and send_whatsapp on queued, the digest trigger writing digest, the demo guard writing held. suppressed is selected by none of them. The APPEND_ONLY family contract declares open/recorded/accepted/selected/logged; none of those five is a value the senders ignore, and a state that leaves the row deliverable would make this stage an outbound effect.',
   'RESULT_KEY','{}'::jsonb,
   'public.notifications.to_email is the committed catalogue recipient PDF-0052, a reserved .invalid address, and channel is none. The row is written by fn_phase_d_object_write, whose outbound-door loop overwrites status in verified fixture context and does not let a caller opt out.')
on conflict (stage_key) do nothing;

update public.phase_d_fixture_stage
   set reference_relation = null,
       note = 'W05-S07. An answer recorded against one workstream group of the scenario''s OWN inquiry. The group is created by this stage: it carries an inquiry_id foreign key and a defaulted rfq_mode and nothing else, so it is a structural child of one inquiry rather than reference data the estate shares.'
 where stage_key = 'inquiry_answer';
`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

splice(`  v_notif_before bigint; v_notif_after bigint;`,
  `  v_notif_before bigint; v_notif_after bigint;
  v_notif_id_before bigint;              -- G11: the high-water mark, so new rows are identifiable`,
  'G11 declaration');

// 1. the inquiry_answer stage creates its own workstream group, and the notification stage its row
splice(`    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id';
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence', 1,
        'value', to_jsonb('ZZ DEMO — fixture answer'::text),
        'field_id', (select id from public.field_definition order by id limit 1),
        'group_id', (select id from public.inquiry_workstream_group order by id limit 1));`,
`    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id';
      -- G11. THE GROUP IS A CHILD OF THIS SCENARIO'S OWN INQUIRY, so this stage creates it.
      -- public.inquiry_workstream_group holds 0 rows on production and this stage reported
      -- BLOCKED_NO_REFERENCE_DATA on every build since D9c. A group carries an inquiry_id foreign
      -- key and a defaulted rfq_mode and nothing else -- it is structure belonging to one inquiry,
      -- not a supplier or a field definition the estate shares. It is created for the inquiry this
      -- scenario created and rolled back with it.
      insert into public.inquiry_workstream_group (inquiry_id)
      values ((v_refs->>'inquiry_id')::uuid)
      on conflict do nothing;
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence', 1,
        'value', to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture answer'::text),
        'field_id', (select id from public.field_definition order by id limit 1),
        'group_id', (select g.id from public.inquiry_workstream_group g
                      where g.inquiry_id = (v_refs->>'inquiry_id')::uuid
                      order by g.id desc limit 1));

    elsif st.stage_key = 'notification' then
      -- G11. The recipient is the committed catalogue's reserved .invalid address and the channel
      -- is none. status is NOT set here: fn_phase_d_object_write's outbound-door loop overwrites it
      -- with the declared suppression in verified fixture context and does not let a caller opt out,
      -- which is exactly the D19 property -- a generated payload must not be able to re-arm a door.
      v_owner := 'phase_d_fixture';
      v_pay := v_pay || jsonb_build_object(
        'type', 'phase_d_fixture',
        'channel', 'none',
        'to_email', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                      where c.scope='EFFECT_PAYLOAD' and c.field_key='recipient'),
        'subject', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D fixture notification record',
        'body', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture notification. It is written at the suppression the outbound door declares, no sender selects it, and it is created inside a transaction that is aborted.');`,
  'G11 stage arms');

// 2. the assertion narrows to the stage whose own object is the queue
splice(`    select count(*) into v_notif_before from public.notifications;
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;`,
`    select count(*) into v_notif_before from public.notifications;
    select coalesce(max(id),0) into v_notif_id_before from public.notifications;  -- G11
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;`,
  'G11 high-water mark');

splice(`      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
          st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
      end if;`,
`      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        -- G11. A STAGE MAY WRITE INTO ITS OWN OBJECT'S CANONICAL RELATION, AND ONLY SUPPRESSED.
        -- The assertion exists because a canonical write to some OTHER object queued a message as a
        -- side effect, and that property is what the Phase D hold rests on. It could not tell that
        -- apart from the one stage whose DECLARED object is the notification. Narrowed by
        -- derivation, never by naming a stage: the relation must be this object's own canonical
        -- relation, and every row written must carry the suppression the outbound door declares for
        -- it. A stage writing here for any other object still aborts the build, and so does this one
        -- if the row it wrote is deliverable.
        if not exists (select 1 from public.phase_d_object_write_map wm2
                        where wm2.object_id = st.object_id
                          and wm2.target_relation = 'public.notifications')
           -- and every row this stage wrote must carry the state the stage declares, which is the
           -- value the outbound door forces and no sender selects. A row at any other status is a
           -- deliverable message and aborts the build exactly as before.
           or exists (select 1 from public.notifications n
                       where n.id > v_notif_id_before
                         and n.status is distinct from st.working_state)
        then
          raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
            st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
        end if;
      end if;`,
  'G11 assertion');

writeFileSync('scripts/sql/phase_d_g11_the_object_whose_canonical_relation_is_the_outbound_queue.sql',
  HEAD + '\n' + ROWS + '\n' + def + '\n');
console.log('G11 written');
