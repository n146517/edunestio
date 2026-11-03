-- =============================================================================
-- EduNestIO :: Module — Student Enrollment History (17_student_enrollment.sql)
-- Option A: ONE student record (stable admission number + student_id) with a
-- per-class ENROLLMENT history. Promotion closes the current enrollment as
-- "Promoted" and opens a new "Active" enrollment in the next class, while the
-- student row itself stays Active and its current class/section/year are updated.
-- Graduate/Withdraw set a terminal enrollment status + student status.
-- Fees/attendance/exam history stay attached to the same student_id.
-- Idempotent; apply after base + modules 10 and 16.
-- =============================================================================

CREATE TABLE IF NOT EXISTS academics.student_enrollment (
    enrollment_id    bigserial   PRIMARY KEY,
    tenant_id        integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    student_id       bigint      NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    class_id         bigint      NULL REFERENCES academics.school_class(class_id) ON DELETE SET NULL,
    section_id       bigint      NULL REFERENCES academics.class_section(section_id) ON DELETE SET NULL,
    academic_year_id bigint      NULL REFERENCES academics.academic_year(academic_year_id) ON DELETE SET NULL,
    roll_number      varchar(30) NULL,
    status           varchar(12) NOT NULL DEFAULT 'Active',  -- Active|Promoted|Graduated|Withdrawn|Inactive
    from_date        date        NOT NULL DEFAULT current_date,
    to_date          date        NULL,
    note             varchar(300) NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    created_by       bigint      NULL,
    CONSTRAINT ck_enrollment_status CHECK (status IN ('Active','Promoted','Graduated','Withdrawn','Inactive'))
);

-- Widen the status constraint on existing installs to include 'Inactive' (idempotent).
DO $$
BEGIN
    ALTER TABLE academics.student_enrollment DROP CONSTRAINT IF EXISTS ck_enrollment_status;
    ALTER TABLE academics.student_enrollment
        ADD CONSTRAINT ck_enrollment_status
        CHECK (status IN ('Active','Promoted','Graduated','Withdrawn','Inactive'));
END $$;
COMMENT ON TABLE academics.student_enrollment IS 'Per-class enrollment history for a student (Option A).';

CREATE INDEX IF NOT EXISTS ix_enrollment_student ON academics.student_enrollment (tenant_id, student_id, from_date DESC);
CREATE INDEX IF NOT EXISTS ix_enrollment_class   ON academics.student_enrollment (tenant_id, class_id, status);
-- At most one Active enrollment per student.
CREATE UNIQUE INDEX IF NOT EXISTS uq_enrollment_active
    ON academics.student_enrollment (tenant_id, student_id) WHERE status = 'Active';

-- Backfill: one Active enrollment per existing student that has none yet.
INSERT INTO academics.student_enrollment (tenant_id, student_id, class_id, section_id, academic_year_id, roll_number, status, from_date, note)
SELECT s.tenant_id, s.student_id, s.class_id, s.section_id, s.academic_year_id, s.roll_number, 'Active',
       COALESCE(s.admission_date, s.created_at::date), 'Backfilled from current record'
  FROM academics.student s
 WHERE s.status = 'Active'
   AND NOT EXISTS (SELECT 1 FROM academics.student_enrollment e
                    WHERE e.student_id = s.student_id AND e.status = 'Active');

-- Permission: promote/graduate/withdraw (academic progression). Reuses the student
-- status actors (SchoolAdmin/Principal).
INSERT INTO core.permission (code, module, description) VALUES
 ('student.promote', 'Student', 'Promote, graduate or withdraw students (academic progression)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code = 'student.promote'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- fn_student_enrollments : class history for one student (most recent first).
-- Payload: { student_id }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_enrollments(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_owner integer; v_items jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id = v_sid;
    IF v_owner IS NULL OR v_owner <> p_tenant_id THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.from_date DESC, t.enrollment_id DESC), '[]'::jsonb)
      INTO v_items FROM (
        SELECT e.enrollment_id, e.class_id, c.name AS class_name, e.section_id, sec.name AS section_name,
               e.academic_year_id, ay.name AS academic_year_name, e.roll_number, e.status,
               e.from_date, e.to_date, e.note
          FROM academics.student_enrollment e
          LEFT JOIN academics.school_class  c   ON c.class_id = e.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id = e.section_id
          LEFT JOIN academics.academic_year ay  ON ay.academic_year_id = e.academic_year_id
         WHERE e.tenant_id = p_tenant_id AND e.student_id = v_sid
    ) t;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object('student_id', v_sid, 'items', v_items));
END; $$;

-- =============================================================================
-- fn_student_promote : bulk promote to a target class. For each student:
--   - close the current Active enrollment as 'Promoted' (to_date = today),
--   - open a new 'Active' enrollment in the target class/section/year,
--   - update the student row's current class/section/year (student stays Active).
-- Payload: { student_ids:[...], to_class_id, to_section_id?, academic_year_id?, note?, ActorUserId }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_promote(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_to_class  bigint := NULLIF(p_payload->>'to_class_id','')::bigint;
    v_to_sec    bigint := NULLIF(p_payload->>'to_section_id','')::bigint;
    v_year      bigint := NULLIF(p_payload->>'academic_year_id','')::bigint;
    v_note      text   := NULLIF(p_payload->>'note','');
    v_actor     bigint := NULLIF(p_payload->>'ActorUserId','')::bigint;
    v_sec_class bigint;
    v_sid       bigint;
    v_owner     integer;
    v_count     int := 0;
BEGIN
    IF v_to_class IS NULL THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Target class is required', 'data', NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM academics.school_class WHERE class_id = v_to_class AND tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid target class', 'data', NULL);
    END IF;
    IF v_to_sec IS NOT NULL THEN
        SELECT class_id INTO v_sec_class FROM academics.class_section
          WHERE section_id = v_to_sec AND tenant_id = p_tenant_id;
        IF v_sec_class IS NULL OR v_sec_class <> v_to_class THEN
            RETURN jsonb_build_object('result_code', 3, 'message', 'Section does not belong to target class', 'data', NULL);
        END IF;
    END IF;
    IF v_year IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM academics.academic_year WHERE academic_year_id = v_year AND tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid academic year', 'data', NULL);
    END IF;

    FOR v_sid IN SELECT (jsonb_array_elements_text(COALESCE(p_payload->'student_ids','[]'::jsonb)))::bigint
    LOOP
        -- Only promote students who are currently Active (not Inactive/Graduated/Withdrawn).
        SELECT tenant_id INTO v_owner FROM academics.student
          WHERE student_id = v_sid AND status = 'Active';
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;   -- skip foreign/unknown/non-active

        -- Don't promote into the same class the student is already in.
        IF EXISTS (SELECT 1 FROM academics.student WHERE student_id = v_sid AND class_id = v_to_class) THEN
            CONTINUE;
        END IF;

        -- Close current Active enrollment as Promoted.
        UPDATE academics.student_enrollment
           SET status = 'Promoted', to_date = current_date,
               note = COALESCE(v_note, note)
         WHERE tenant_id = p_tenant_id AND student_id = v_sid AND status = 'Active';

        -- Open the new Active enrollment in the target class.
        INSERT INTO academics.student_enrollment
            (tenant_id, student_id, class_id, section_id, academic_year_id, status, from_date, note, created_by)
        VALUES (p_tenant_id, v_sid, v_to_class, v_to_sec, v_year, 'Active', current_date, v_note, v_actor);

        -- Reflect the current placement on the student row (student stays Active).
        UPDATE academics.student
           SET class_id = v_to_class, section_id = v_to_sec,
               academic_year_id = COALESCE(v_year, academic_year_id),
               roll_number = NULL,  -- roll re-assigned in the new class
               updated_at = now(), updated_by = v_actor
         WHERE student_id = v_sid AND tenant_id = p_tenant_id;

        v_count := v_count + 1;
    END LOOP;

    BEGIN
        PERFORM core.fn_write_audit(p_tenant_id, jsonb_build_object(
            'actor_user_id', v_actor, 'entity', 'student', 'action', 'promote',
            'detail', jsonb_build_object('to_class_id', v_to_class, 'count', v_count)));
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Promoted',
        'data', jsonb_build_object('promoted', v_count));
END; $$;

-- =============================================================================
-- fn_student_graduate : bulk graduate (terminal). Closes Active enrollment as
-- 'Graduated' and sets the student status to 'Graduated'.
-- Payload: { student_ids:[...], note?, ActorUserId }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_graduate(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_note text := NULLIF(p_payload->>'note',''); v_actor bigint := NULLIF(p_payload->>'ActorUserId','')::bigint;
        v_sid bigint; v_owner integer; v_count int := 0;
BEGIN
    FOR v_sid IN SELECT (jsonb_array_elements_text(COALESCE(p_payload->'student_ids','[]'::jsonb)))::bigint
    LOOP
        -- Only Active students can be graduated.
        SELECT tenant_id INTO v_owner FROM academics.student
          WHERE student_id = v_sid AND status = 'Active';
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;

        UPDATE academics.student_enrollment
           SET status = 'Graduated', to_date = current_date, note = COALESCE(v_note, note)
         WHERE tenant_id = p_tenant_id AND student_id = v_sid AND status = 'Active';

        UPDATE academics.student
           SET status = 'Graduated', status_reason = COALESCE(v_note, 'Graduated'),
               status_changed_at = now(), status_changed_by = v_actor,
               updated_at = now(), updated_by = v_actor
         WHERE student_id = v_sid AND tenant_id = p_tenant_id;

        v_count := v_count + 1;
    END LOOP;

    BEGIN
        PERFORM core.fn_write_audit(p_tenant_id, jsonb_build_object(
            'actor_user_id', v_actor, 'entity', 'student', 'action', 'graduate',
            'detail', jsonb_build_object('count', v_count)));
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Graduated',
        'data', jsonb_build_object('graduated', v_count));
END; $$;

-- =============================================================================
-- fn_student_withdraw : bulk withdraw (terminal). Closes Active enrollment as
-- 'Withdrawn' and sets the student status to 'Withdrawn'.
-- Payload: { student_ids:[...], reason?, ActorUserId }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_withdraw(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_reason text := NULLIF(p_payload->>'reason',''); v_actor bigint := NULLIF(p_payload->>'ActorUserId','')::bigint;
        v_sid bigint; v_owner integer; v_count int := 0;
BEGIN
    FOR v_sid IN SELECT (jsonb_array_elements_text(COALESCE(p_payload->'student_ids','[]'::jsonb)))::bigint
    LOOP
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id = v_sid;
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;

        UPDATE academics.student_enrollment
           SET status = 'Withdrawn', to_date = current_date, note = COALESCE(v_reason, note)
         WHERE tenant_id = p_tenant_id AND student_id = v_sid AND status = 'Active';

        UPDATE academics.student
           SET status = 'Withdrawn', status_reason = COALESCE(v_reason, 'Withdrawn'),
               status_changed_at = now(), status_changed_by = v_actor,
               updated_at = now(), updated_by = v_actor
         WHERE student_id = v_sid AND tenant_id = p_tenant_id;

        v_count := v_count + 1;
    END LOOP;

    BEGIN
        PERFORM core.fn_write_audit(p_tenant_id, jsonb_build_object(
            'actor_user_id', v_actor, 'entity', 'student', 'action', 'withdraw',
            'detail', jsonb_build_object('count', v_count)));
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Withdrawn',
        'data', jsonb_build_object('withdrawn', v_count));
END; $$;

-- =============================================================================
-- Auto-create the first Active enrollment whenever a student is created.
-- Keeps all enrollment logic in this module (no change needed to fn_student_save),
-- so every new student has a class history from day one.
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_enrollment_on_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'Active' THEN
        INSERT INTO academics.student_enrollment
            (tenant_id, student_id, class_id, section_id, academic_year_id, roll_number, status, from_date, created_by)
        VALUES (NEW.tenant_id, NEW.student_id, NEW.class_id, NEW.section_id, NEW.academic_year_id,
                NEW.roll_number, 'Active', COALESCE(NEW.admission_date, current_date), NEW.created_by);
    END IF;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_student_enrollment_on_insert ON academics.student;
CREATE TRIGGER trg_student_enrollment_on_insert
    AFTER INSERT ON academics.student
    FOR EACH ROW EXECUTE FUNCTION academics.fn_student_enrollment_on_insert();
