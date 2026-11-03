-- =============================================================================
-- EduNestIO :: Module — Students Enhancement (16_students_enhance.sql)
-- Extends the existing academics.student slice with: roll number, academic year,
-- admission/joining date, guardian details, extra personal fields (nationality,
-- blood group), country, photo reference, and explicit status-change tracking.
-- Adds fn_student_set_status (audited) and fn_student_summary (counts).
-- Backward-compatible + idempotent: all new columns are nullable, existing rows
-- are untouched, and the existing admission-number generation is preserved.
-- Apply after base scripts + module 10 (academic setup).
-- =============================================================================

-- ---- New columns (all nullable -> legacy rows remain valid) -----------------
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS roll_number        varchar(30)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS academic_year_id   bigint       NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS admission_date     date         NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS nationality        varchar(60)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS blood_group        varchar(8)   NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS guardian_name      varchar(200) NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS guardian_relation  varchar(60)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS guardian_phone     varchar(40)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS guardian_alt_phone varchar(40)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS guardian_email     varchar(256) NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS country            varchar(80)  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS photo_url          varchar(500) NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS status_reason      varchar(300) NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS status_changed_at  timestamptz  NULL;
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS status_changed_by  bigint       NULL;

-- FK for academic_year (added only if absent; ON DELETE SET NULL keeps rows safe).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'student_academic_year_id_fkey'
    ) THEN
        ALTER TABLE academics.student
            ADD CONSTRAINT student_academic_year_id_fkey
            FOREIGN KEY (academic_year_id)
            REFERENCES academics.academic_year(academic_year_id) ON DELETE SET NULL;
    END IF;
END $$;

-- Helpful indexes for the new filters (idempotent).
CREATE INDEX IF NOT EXISTS ix_student_tenant_section ON academics.student (tenant_id, section_id);
CREATE INDEX IF NOT EXISTS ix_student_tenant_year    ON academics.student (tenant_id, academic_year_id);
-- Roll number should be unique within a class+section+year (when all are present).
CREATE UNIQUE INDEX IF NOT EXISTS uq_student_roll
    ON academics.student (tenant_id, class_id, section_id, academic_year_id, roll_number)
    WHERE roll_number IS NOT NULL AND class_id IS NOT NULL;

-- ---- Permission: manage student status --------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('student.status', 'Student', 'Change a student''s enrollment status (graduate/withdraw/reactivate)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code = 'student.status'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- fn_student_save (REPLACES prior version): now persists the new fields, validates
-- section-belongs-to-class and roll-number uniqueness, and NEVER regenerates the
-- admission number on update (Student ID + admission number stay stable).
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id      bigint := NULLIF(p_payload->>'StudentId','')::bigint;
    v_adm     text   := NULLIF(p_payload->>'AdmissionNumber','');
    v_class   bigint := NULLIF(p_payload->>'ClassId','')::bigint;
    v_section bigint := NULLIF(p_payload->>'SectionId','')::bigint;
    v_year    bigint := NULLIF(p_payload->>'AcademicYearId','')::bigint;
    v_roll    text   := NULLIF(p_payload->>'RollNumber','');
    v_owner   integer;
    v_sec_class bigint;
    v_numenv  jsonb;
BEGIN
    IF COALESCE(p_payload->>'FirstName','') = '' OR COALESCE(p_payload->>'LastName','') = '' THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'First and last name are required', 'data', NULL);
    END IF;

    -- Referential checks (tenant-scoped) for optional academic assignments.
    IF v_class IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM academics.school_class WHERE class_id = v_class AND tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid class for this school', 'data', NULL);
    END IF;
    IF v_section IS NOT NULL THEN
        SELECT class_id INTO v_sec_class FROM academics.class_section
          WHERE section_id = v_section AND tenant_id = p_tenant_id;
        IF v_sec_class IS NULL THEN
            RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid section for this school', 'data', NULL);
        END IF;
        IF v_class IS NULL OR v_sec_class <> v_class THEN
            RETURN jsonb_build_object('result_code', 3, 'message', 'Section does not belong to the selected class', 'data', NULL);
        END IF;
    END IF;
    IF v_year IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM academics.academic_year WHERE academic_year_id = v_year AND tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid academic year for this school', 'data', NULL);
    END IF;

    IF v_id IS NULL THEN
        -- CREATE ------------------------------------------------------------
        IF v_adm IS NULL THEN
            v_numenv := core.fn_next_document_number(p_tenant_id, '{"seq_key":"admission_number"}');
            v_adm := v_numenv->'data'->>'number';
        END IF;

        IF EXISTS (SELECT 1 FROM academics.student WHERE tenant_id = p_tenant_id AND admission_number = v_adm) THEN
            RETURN jsonb_build_object('result_code', 7, 'message', 'Admission number already exists', 'data', NULL);
        END IF;

        -- Roll uniqueness within class+section+year (only when roll provided).
        IF v_roll IS NOT NULL AND v_class IS NOT NULL AND EXISTS (
            SELECT 1 FROM academics.student
             WHERE tenant_id = p_tenant_id AND class_id = v_class
               AND section_id IS NOT DISTINCT FROM v_section
               AND academic_year_id IS NOT DISTINCT FROM v_year
               AND roll_number = v_roll) THEN
            RETURN jsonb_build_object('result_code', 7, 'message', 'Roll number already used in this class/section', 'data', NULL);
        END IF;

        INSERT INTO academics.student (
            tenant_id, admission_number, first_name, middle_name, last_name, gender,
            date_of_birth, email, phone, address_line1, address_line2, city, state,
            postal_code, class_id, section_id, status, created_by,
            roll_number, academic_year_id, admission_date, nationality, blood_group,
            guardian_name, guardian_relation, guardian_phone, guardian_alt_phone,
            guardian_email, country, photo_url)
        VALUES (
            p_tenant_id, v_adm,
            p_payload->>'FirstName', NULLIF(p_payload->>'MiddleName',''), p_payload->>'LastName',
            NULLIF(p_payload->>'Gender',''),
            NULLIF(p_payload->>'DateOfBirth','')::date,
            NULLIF(p_payload->>'Email',''), NULLIF(p_payload->>'Phone',''),
            NULLIF(p_payload->>'AddressLine1',''), NULLIF(p_payload->>'AddressLine2',''),
            NULLIF(p_payload->>'City',''), NULLIF(p_payload->>'State',''),
            NULLIF(p_payload->>'PostalCode',''),
            v_class, v_section,
            COALESCE(NULLIF(p_payload->>'Status',''),'Active'),
            NULLIF(p_payload->>'ActorUserId','')::bigint,
            v_roll, v_year, NULLIF(p_payload->>'AdmissionDate','')::date,
            NULLIF(p_payload->>'Nationality',''), NULLIF(p_payload->>'BloodGroup',''),
            NULLIF(p_payload->>'GuardianName',''), NULLIF(p_payload->>'GuardianRelation',''),
            NULLIF(p_payload->>'GuardianPhone',''), NULLIF(p_payload->>'GuardianAltPhone',''),
            NULLIF(p_payload->>'GuardianEmail',''), NULLIF(p_payload->>'Country',''),
            NULLIF(p_payload->>'PhotoUrl',''))
        RETURNING student_id INTO v_id;

        RETURN jsonb_build_object('result_code', 0, 'message', 'Created',
            'data', jsonb_build_object('student_id', v_id, 'admission_number', v_adm));
    ELSE
        -- UPDATE (verify tenant ownership first -> no cross-tenant writes) ----
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id = v_id;
        IF v_owner IS NULL THEN
            RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
        END IF;
        IF v_owner <> p_tenant_id THEN
            RETURN jsonb_build_object('result_code', 8, 'message', 'Tenant access violation', 'data', NULL);
        END IF;

        -- Roll uniqueness within class+section+year (excluding self).
        IF v_roll IS NOT NULL AND v_class IS NOT NULL AND EXISTS (
            SELECT 1 FROM academics.student
             WHERE tenant_id = p_tenant_id AND class_id = v_class
               AND section_id IS NOT DISTINCT FROM v_section
               AND academic_year_id IS NOT DISTINCT FROM v_year
               AND roll_number = v_roll AND student_id <> v_id) THEN
            RETURN jsonb_build_object('result_code', 7, 'message', 'Roll number already used in this class/section', 'data', NULL);
        END IF;

        -- NOTE: admission_number is intentionally NOT updated here (stays stable).
        UPDATE academics.student SET
            first_name    = p_payload->>'FirstName',
            middle_name   = NULLIF(p_payload->>'MiddleName',''),
            last_name     = p_payload->>'LastName',
            gender        = NULLIF(p_payload->>'Gender',''),
            date_of_birth = NULLIF(p_payload->>'DateOfBirth','')::date,
            email         = NULLIF(p_payload->>'Email',''),
            phone         = NULLIF(p_payload->>'Phone',''),
            address_line1 = NULLIF(p_payload->>'AddressLine1',''),
            address_line2 = NULLIF(p_payload->>'AddressLine2',''),
            city          = NULLIF(p_payload->>'City',''),
            state         = NULLIF(p_payload->>'State',''),
            postal_code   = NULLIF(p_payload->>'PostalCode',''),
            class_id      = v_class,
            section_id    = v_section,
            -- status is changed only via fn_student_set_status; keep as-is here.
            status        = COALESCE(NULLIF(p_payload->>'Status',''), status),
            roll_number       = v_roll,
            academic_year_id  = v_year,
            admission_date    = NULLIF(p_payload->>'AdmissionDate','')::date,
            nationality       = NULLIF(p_payload->>'Nationality',''),
            blood_group       = NULLIF(p_payload->>'BloodGroup',''),
            guardian_name     = NULLIF(p_payload->>'GuardianName',''),
            guardian_relation = NULLIF(p_payload->>'GuardianRelation',''),
            guardian_phone    = NULLIF(p_payload->>'GuardianPhone',''),
            guardian_alt_phone= NULLIF(p_payload->>'GuardianAltPhone',''),
            guardian_email    = NULLIF(p_payload->>'GuardianEmail',''),
            country           = NULLIF(p_payload->>'Country',''),
            photo_url         = COALESCE(NULLIF(p_payload->>'PhotoUrl',''), photo_url),
            updated_at    = now(),
            updated_by    = NULLIF(p_payload->>'ActorUserId','')::bigint
        WHERE student_id = v_id AND tenant_id = p_tenant_id;

        RETURN jsonb_build_object('result_code', 0, 'message', 'Updated',
            'data', jsonb_build_object('student_id', v_id));
    END IF;
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code', 7, 'message', 'Duplicate value (admission or roll number)', 'data', NULL);
WHEN OTHERS THEN
    RETURN jsonb_build_object('result_code', 1, 'message', SQLERRM, 'data', NULL);
END;
$$;

-- =============================================================================
-- fn_student_get (REPLACES): returns the full profile incl. section + academic
-- year names and all new fields; tenant-scoped (cross-tenant id -> NOT_FOUND).
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_get(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id   bigint := (p_payload->>'student_id')::bigint;
    v_data jsonb;
BEGIN
    SELECT to_jsonb(s)
           || jsonb_build_object('class_name', c.name)
           || jsonb_build_object('section_name', sec.name)
           || jsonb_build_object('academic_year_name', ay.name)
      INTO v_data
      FROM academics.student s
      LEFT JOIN academics.school_class  c   ON c.class_id = s.class_id
      LEFT JOIN academics.class_section sec ON sec.section_id = s.section_id
      LEFT JOIN academics.academic_year ay  ON ay.academic_year_id = s.academic_year_id
     WHERE s.student_id = v_id AND s.tenant_id = p_tenant_id;

    IF v_data IS NULL THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
    END IF;
    RETURN jsonb_build_object('result_code', 0, 'message', 'Success', 'data', v_data);
END;
$$;

-- =============================================================================
-- fn_student_list (REPLACES): adds section + academic-year filters, returns
-- section_name/roll_number/guardian_phone/admission_date, and searches admission
-- number, name, roll number and guardian phone.
-- Payload: { search, class_id, section_id, academic_year_id, status,
--            page, page_size, sort_by, sort_dir }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_search   text    := lower(COALESCE(p_payload->>'search',''));
    v_class    bigint  := NULLIF(p_payload->>'class_id','')::bigint;
    v_section  bigint  := NULLIF(p_payload->>'section_id','')::bigint;
    v_year     bigint  := NULLIF(p_payload->>'academic_year_id','')::bigint;
    v_status   text    := NULLIF(p_payload->>'status','');
    v_page     integer := GREATEST(COALESCE((p_payload->>'page')::integer,1),1);
    v_size     integer := LEAST(GREATEST(COALESCE((p_payload->>'page_size')::integer,20),1),100);
    v_offset   integer := (v_page - 1) * v_size;
    v_total    bigint;
    v_items    jsonb;
BEGIN
    SELECT count(*) INTO v_total
      FROM academics.student s
     WHERE s.tenant_id = p_tenant_id
       AND (v_class   IS NULL OR s.class_id = v_class)
       AND (v_section IS NULL OR s.section_id = v_section)
       AND (v_year    IS NULL OR s.academic_year_id = v_year)
       AND (v_status  IS NULL OR s.status = v_status)
       AND (v_search = '' OR lower(s.first_name) LIKE '%'||v_search||'%'
                          OR lower(s.last_name)  LIKE '%'||v_search||'%'
                          OR lower(s.admission_number) LIKE '%'||v_search||'%'
                          OR lower(COALESCE(s.roll_number,''))    LIKE '%'||v_search||'%'
                          OR lower(COALESCE(s.guardian_phone,'')) LIKE '%'||v_search||'%');

    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.tenant_id, s.admission_number, s.first_name, s.middle_name,
               s.last_name, s.gender, s.date_of_birth, s.email, s.phone, s.city,
               s.class_id, c.name AS class_name, s.section_id, sec.name AS section_name,
               s.academic_year_id, s.roll_number, s.guardian_name, s.guardian_phone,
               s.admission_date, s.photo_url, s.status, s.status_reason, s.status_changed_at,
               s.created_at
          FROM academics.student s
          LEFT JOIN academics.school_class  c   ON c.class_id = s.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id = s.section_id
         WHERE s.tenant_id = p_tenant_id
           AND (v_class   IS NULL OR s.class_id = v_class)
           AND (v_section IS NULL OR s.section_id = v_section)
           AND (v_year    IS NULL OR s.academic_year_id = v_year)
           AND (v_status  IS NULL OR s.status = v_status)
           AND (v_search = '' OR lower(s.first_name) LIKE '%'||v_search||'%'
                              OR lower(s.last_name)  LIKE '%'||v_search||'%'
                              OR lower(s.admission_number) LIKE '%'||v_search||'%'
                              OR lower(COALESCE(s.roll_number,''))    LIKE '%'||v_search||'%'
                              OR lower(COALESCE(s.guardian_phone,'')) LIKE '%'||v_search||'%')
         ORDER BY
           CASE WHEN lower(COALESCE(p_payload->>'sort_by','')) = 'name'
                 AND lower(COALESCE(p_payload->>'sort_dir','asc')) = 'asc'  THEN s.last_name END ASC,
           CASE WHEN lower(COALESCE(p_payload->>'sort_by','')) = 'name'
                 AND lower(COALESCE(p_payload->>'sort_dir','asc')) = 'desc' THEN s.last_name END DESC,
           s.created_at DESC
         LIMIT v_size OFFSET v_offset
    ) t;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object('items', v_items, 'page', v_page,
                                   'page_size', v_size, 'total_count', v_total));
END;
$$;

-- =============================================================================
-- fn_student_set_status : explicit, audited status change. Distinguishes
-- graduate/withdraw/inactive/active. Records who/when/why; writes an audit entry.
-- Payload: { student_id, status, reason, ActorUserId }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_set_status(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id     bigint := (p_payload->>'student_id')::bigint;
    v_status text   := NULLIF(p_payload->>'status','');
    v_reason text   := NULLIF(p_payload->>'reason','');
    v_actor  bigint := NULLIF(p_payload->>'ActorUserId','')::bigint;
    v_owner  integer;
    v_old    text;
BEGIN
    IF v_status IS NULL OR v_status NOT IN ('Active','Inactive','Withdrawn','Graduated') THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'Invalid status', 'data', NULL);
    END IF;

    SELECT tenant_id, status INTO v_owner, v_old FROM academics.student WHERE student_id = v_id;
    IF v_owner IS NULL THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
    END IF;
    IF v_owner <> p_tenant_id THEN
        RETURN jsonb_build_object('result_code', 8, 'message', 'Tenant access violation', 'data', NULL);
    END IF;

    UPDATE academics.student
       SET status = v_status, status_reason = v_reason,
           status_changed_at = now(), status_changed_by = v_actor,
           updated_at = now(), updated_by = v_actor
     WHERE student_id = v_id AND tenant_id = p_tenant_id;

    -- Keep the current enrollment row in sync (so Class history reflects the change).
    -- Guarded: the student_enrollment table is created in module 17.
    IF to_regclass('academics.student_enrollment') IS NOT NULL THEN
        IF v_status IN ('Inactive','Graduated','Withdrawn') THEN
            -- Close the current Active enrollment with the new status + reason.
            UPDATE academics.student_enrollment
               SET status = v_status, to_date = current_date, note = COALESCE(v_reason, note)
             WHERE tenant_id = p_tenant_id AND student_id = v_id AND status = 'Active';
        ELSIF v_status = 'Active' THEN
            -- Reactivating: if there is no Active enrollment, reopen the most recent one
            -- (or create one from the student's current class) so the timeline is consistent.
            IF NOT EXISTS (SELECT 1 FROM academics.student_enrollment
                            WHERE tenant_id = p_tenant_id AND student_id = v_id AND status = 'Active') THEN
                UPDATE academics.student_enrollment
                   SET status = 'Active', to_date = NULL, note = COALESCE(v_reason, note)
                 WHERE enrollment_id = (
                        SELECT enrollment_id FROM academics.student_enrollment
                         WHERE tenant_id = p_tenant_id AND student_id = v_id
                         ORDER BY from_date DESC, enrollment_id DESC LIMIT 1);

                IF NOT FOUND THEN
                    INSERT INTO academics.student_enrollment
                        (tenant_id, student_id, class_id, section_id, academic_year_id, roll_number, status, from_date, note, created_by)
                    SELECT p_tenant_id, v_id, class_id, section_id, academic_year_id, roll_number, 'Active',
                           current_date, v_reason, v_actor
                      FROM academics.student WHERE student_id = v_id;
                END IF;
            END IF;
        END IF;
    END IF;

    -- Best-effort audit (non-fatal if the audit fn signature differs).
    BEGIN
        PERFORM core.fn_write_audit(p_tenant_id, jsonb_build_object(
            'actor_user_id', v_actor, 'entity', 'student', 'entity_id', v_id,
            'action', 'status_change',
            'detail', jsonb_build_object('from', v_old, 'to', v_status, 'reason', v_reason)));
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Status updated',
        'data', jsonb_build_object('student_id', v_id, 'status', v_status, 'previous_status', v_old));
END;
$$;

-- =============================================================================
-- fn_student_summary : tenant-scoped counts by status for dashboard cards.
-- Payload: { } (none needed). Returns total + per-status counts.
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_student_summary(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE v_by jsonb; v_total bigint;
BEGIN
    SELECT count(*) INTO v_total FROM academics.student WHERE tenant_id = p_tenant_id;
    SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb) INTO v_by
      FROM (SELECT status, count(*) cnt FROM academics.student
             WHERE tenant_id = p_tenant_id GROUP BY status) s;
    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object(
            'total',     v_total,
            'active',    COALESCE((v_by->>'Active')::bigint, 0),
            'inactive',  COALESCE((v_by->>'Inactive')::bigint, 0),
            'graduated', COALESCE((v_by->>'Graduated')::bigint, 0),
            'withdrawn', COALESCE((v_by->>'Withdrawn')::bigint, 0),
            'by_status', v_by));
END;
$$;
