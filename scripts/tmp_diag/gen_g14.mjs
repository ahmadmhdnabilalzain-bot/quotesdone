import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G14 — sixteen columns a handler must not invent, and nothing committed for eleven of them
--
-- fn_phase_d_fixture_effect_payload already derives the right population: the columns of the
-- effect's target relation that are NOT NULL, have no default, are not generated, and are mapped by
-- the object's write map to a payload key. That is exactly the set fn_phase_d_effect_produce raises
-- 23502 on. It then looks each one up in the committed catalogue at scope EFFECT_PAYLOAD.
--
-- MEASURED: sixteen such keys exist and eleven had no committed fixture at all, so the handler was
-- handed nothing and the write failed. W07 produced no business effect for exactly this reason:
--
--     null value in column "bucket" of relation "documents" violates not-null constraint
--
-- classified pd_effect_payload_incomplete, which is the correct classification of a handler that
-- refused to invent a storage bucket.
--
-- TWO KINDS OF KEY, AND THEY GET DIFFERENT ANSWERS. That distinction is the whole of this file:
--
--   ELEVEN ARE CONTENT -- bucket, path, metric, answer_scope, source_kind, precedence, subject_type,
--   subject_id, stage, author_agent, type. A committed fixture is the right answer for these and is
--   what the founder's section 6 asks for: explicit synthetic content, marked, never invented by
--   the handler. They are added to the catalogue with the marker where the column's own domain
--   permits it, and with a marker_exemption stating why where it does not -- precedence is an
--   enum, and a marker inside it resolves to no enum label.
--
--   FIVE NAME A ROW -- inquiry_id, transaction_id, group_id, field_id, requested_by. A committed
--   constant is the WRONG answer for these, and this session has now corrected that same mistake
--   four separate times: terms_version and terms_hash beating the acceptance record, monetary_state
--   naming no rung of the ladder, artifact_sha256 written as a row id, and seven object keys
--   answered with the run's own row. So fn_phase_d_fixture_effect_payload now asks
--   fn_phase_d_step_context FIRST -- which resolves an object key from the object it names, from a
--   declared foreign key, or from the canonical reference the scenario recorded -- and only falls
--   through to the catalogue for what the context cannot answer.
--
-- AND ONE RESOLVER THAT COULD NOT REACH ITS FALLBACK. G09 gave inquiry_owner a fallback to the
-- accountable role the frozen registry assigns to the workflow that owns the inquiry, for an
-- inquiry no run has claimed. It was placed inside the branch that requires the run's OWN business
-- object row to have been found, and W06's primary object is inquiry_route_set, whose stage
-- contributes a STATE rather than a key -- so the run's object never resolves, the branch never
-- runs, and W06-S01 still refused with "inquiry owner is (unstated)". The fallback now applies
-- whenever nothing else has answered, which is what it was written to do.
--
-- Two anchors, each required to match exactly once, plus eleven catalogue rows.`;

const ROWS = `
insert into public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
values
  ('PDF-4001',1,'','','EFFECT_PAYLOAD','bucket','"zz-phase-d-fixtures"'::jsonb,'text',
   'a storage bucket name; public.documents.bucket is NOT NULL with no default',
   'the document effect writes and the step produces its declared artifact instead of raising 23502',
   'Nothing is uploaded to this bucket by Phase D; the row is written inside a transaction that is aborted.',
   'public.documents.bucket is a storage bucket NAME. A marker inside it names a bucket that does not exist, so the write would fail for the marker rather than for the document.'),
  ('PDF-4002',1,'','','EFFECT_PAYLOAD','path','"zz/phase-d/PHASE_D_FIXTURE_DO_NOT_PUBLISH.pdf"'::jsonb,'text',
   'an object path within the bucket; public.documents.path is NOT NULL with no default',
   'the document effect writes with a path that carries the marker and names no real object',
   'No object exists at this path and none is created; nothing is uploaded or fetched.', null),
  ('PDF-4003',1,'','','EFFECT_PAYLOAD','metric','"phase_d_fixture_metric"'::jsonb,'text',
   'a metric key; public.company_goals.metric is NOT NULL with no default',
   'the company objective effect writes instead of raising 23502',
   'This names no measured metric and no goal is pursued from it.',
   'public.company_goals.metric is a KEY other routines match on. A marker inside it makes the key wrong rather than marked.'),
  ('PDF-4004',1,'','','EFFECT_PAYLOAD','answer_scope','"inquiry_shared"'::jsonb,'text',
   'one of the scopes public.inquiry_answer accepts',
   'the answer effect writes at the shared scope',
   'The answer is fixture content and is never shown to a customer or a supplier.',
   'answer_scope is a closed vocabulary the answer resolver matches on; a marker inside it matches nothing.'),
  ('PDF-4005',1,'','','EFFECT_PAYLOAD','source_kind','"customer"'::jsonb,'text',
   'the origin of an inquiry answer',
   'the answer effect writes with a stated origin',
   'No customer supplied this answer; it is fixture content.',
   'source_kind is a closed vocabulary the evidence ranking matches on; a marker inside it ranks as nothing.'),
  ('PDF-4006',1,'','','EFFECT_PAYLOAD','precedence','"customer_confirmed"'::jsonb,'text',
   'a label of the answer_precedence enum',
   'the answer effect writes at a precedence the enum declares',
   'This asserts nothing about any real answer''s authority.',
   'public.answer_precedence is a PostgreSQL enum. A marker inside the value is not a label of it and the write would fail for the marker.'),
  ('PDF-4007',1,'','','EFFECT_PAYLOAD','subject_type','"phase_d_fixture"'::jsonb,'text',
   'what a review record is about; public.review_chain.subject_type is NOT NULL',
   'the review effect writes against a subject type that names the fixture, not a business object',
   'No real artifact is reviewed and no verdict is published.',
   'subject_type is joined on by the review resolver; a marker inside it resolves to no subject.'),
  ('PDF-4008',1,'','','EFFECT_PAYLOAD','subject_id','"PHASE_D_FIXTURE_DO_NOT_PUBLISH"'::jsonb,'text',
   'the identity of what a review record is about',
   'the review effect writes against a subject that is explicitly the fixture',
   'This names no real artifact.', null),
  ('PDF-4009',1,'','','EFFECT_PAYLOAD','stage','"phase_d_fixture"'::jsonb,'text',
   'the review stage; public.review_chain.stage is NOT NULL',
   'the review effect writes at a stage that names the fixture',
   'No real review stage is entered.',
   'stage is matched against the review chain''s own stage vocabulary; a marker inside it matches nothing.'),
  ('PDF-4010',1,'','','EFFECT_PAYLOAD','author_agent','"customer_onboarding"'::jsonb,'text',
   'the role that authored what is being reviewed; public.review_chain refuses reviewer = author',
   'the review effect writes and BR-002 still decides whether the reviewer is independent of this author',
   'No agent authored anything; this exists so the independence test has two roles to compare.',
   'author_agent must resolve to a canonical role for the independence test to mean anything; a marker inside it resolves to no role.'),
  ('PDF-4011',1,'','','EFFECT_PAYLOAD','type','"phase_d_fixture"'::jsonb,'text',
   'the notification type; public.notifications.type is NOT NULL',
   'the notification effect writes a record of a type no sender routes',
   'No notification of this type is delivered; the row carries the suppression the outbound door forces.',
   'public.notifications.type is matched by fn_invite_status_on_send and the digest policy; a marker inside it would make the type wrong rather than marked.'),
  ('PDF-4012',1,'','','EFFECT_PAYLOAD','requested_by','"PHASE_D_FIXTURE_DO_NOT_PUBLISH"'::jsonb,'text',
   'who requested a refund; public.refunds.requested_by is NOT NULL',
   'the refund case effect writes as REQUESTED and no further: GATE-020 still requires a recorded founder decision and z00_refund_founder_decision_only still refuses execution',
   'No refund is executed by Phase D at any amount. Every refund needs the founder.', null)
on conflict (fixture_id) do nothing;
`;

const r = await sql(`select p.proname, pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname in ('fn_phase_d_fixture_effect_payload','fn_phase_d_step_context')`);
const get = (n) => r.find((x) => x.proname === n).def;

// ---- fn_phase_d_step_context: the fallback escapes its guard --------------------------------
let ctx = get('fn_phase_d_step_context');
const aCtx = `        if v_val is null then
          select to_jsonb(w2.accountable_role_id) into v_val
            from public.phase_b_workflow w2
           where w2.primary_object = 'inquiry' order by w2.workflow_id limit 1;
          v_src := 'phase_b_workflow.accountable_role_id of the workflow whose primary object is '
                || 'the inquiry -- no workflow run has claimed this inquiry, so accountability is '
                || 'where the frozen registry puts it and has not moved';
        end if;
      end if;`;
if (ctx.split(aCtx).length - 1 !== 1) throw new Error('G14 ctx anchor');
ctx = ctx.replace(aCtx, `      end if;
      -- G14. THE FALLBACK WAS INSIDE THE BRANCH THAT NEEDS THE RUN'S OWN ROW, AND W06 HAS NONE.
      -- W06's primary object is inquiry_route_set, whose fixture stage contributes a STATE rather
      -- than a key, so the run's business object never resolves and the branch above never ran.
      -- W06-S01 kept refusing with "inquiry owner is (unstated)" after G09 had supposedly answered
      -- it. The fallback belongs wherever nothing else has answered, which is here.
      if v_val is null then
        select to_jsonb(w2.accountable_role_id) into v_val
          from public.phase_b_workflow w2
         where w2.primary_object = 'inquiry' order by w2.workflow_id limit 1;
        v_src := 'phase_b_workflow.accountable_role_id of the workflow whose primary object is '
              || 'the inquiry -- no workflow run has claimed this inquiry, so accountability is '
              || 'where the frozen registry puts it and has not moved';
      end if;`);

// ---- fn_phase_d_fixture_effect_payload: the context answers before the catalogue -------------
let fx = get('fn_phase_d_fixture_effect_payload');
const aFx = `      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then
        v_out := v_out || jsonb_build_object(r.src, fi.value);
      end if;
    end loop;`;
if (fx.split(aFx).length - 1 !== 1) throw new Error('G14 fx anchor');
fx = fx.replace(aFx, `      -- G14. A KEY THAT NAMES A ROW IS ANSWERED FROM THE ROW, NOT FROM A CONSTANT.
      -- Five of the sixteen keys in this population name something: inquiry_id, transaction_id,
      -- group_id, field_id, requested_by. fn_phase_d_step_context resolves an object key from the
      -- object it names, from a declared foreign key on the run's own relation, or from the
      -- canonical reference the scenario recorded -- so it is asked first, and the committed
      -- catalogue answers only what it could not. Handing a committed constant to a key that names
      -- a row is the mistake this estate has now corrected four times in one session.
      v_ctx_val := (public.fn_phase_d_step_context(p_step_run_id))->'context'->(r.src);
      if v_ctx_val is not null and v_ctx_val <> 'null'::jsonb then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then
        v_out := v_out || jsonb_build_object(r.src, fi.value);
      end if;
    end loop;`);
const aDecl = `  fi    record;`;
if (fx.split(aDecl).length - 1 !== 1) throw new Error('G14 fx decl anchor');
fx = fx.replace(aDecl, `  fi    record;
  v_ctx_val jsonb;   -- G14: what the step context already resolved for this key`);

writeFileSync('scripts/sql/phase_d_g14_sixteen_columns_a_handler_must_not_invent.sql',
  HEAD + '\n' + ROWS + '\n' + ctx + '\n\n' + fx + '\n');
console.log('G14 written');
