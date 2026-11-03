-- =============================================================================
-- EduNestIO :: Module — Timetable + Assignments (30_timetable_assignments.sql)
-- Teachers are core.app_user rows holding the 'Teacher'/'ClassTeacher' role.
--   * Timetable: weekly period slots per class+section (day, period, time,
--     subject, teacher). Admin manages; students see their own class timetable.
--   * Assignments: a teacher sets work for a class+section+subject (title,
--     description, due date, max marks); students view and submit; teachers grade.
-- Idempotent. Tenant-scoped throughout. Apply after modules 10, 25.
-- =============================================================================

-- ---- Permissions ------------------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('timetable.view',    'Timetable',  'View timetables'),
 ('timetable.manage',  'Timetable',  'Create/edit the weekly timetable'),
 ('assignment.view',   'Assignment', 'View assignments'),
 ('assignment.manage', 'Assignment', 'Create/edit and grade assignments'),
 ('assignment.submit', 'Assignment', 'Submit own assignment work')
ON CONFLICT (code) DO NOTHING;

-- Staff who build timetables / manage assignments.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code IN ('timetable.view','timetable.manage','assignment.view','assignment.manage')
ON CONFLICT DO NOTHING;

-- Teachers: view timetable, manage (their) assignments.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Teacher','ClassTeacher') AND p.code IN ('timetable.view','timetable.manage','assignment.view','assignment.manage')
ON CONFLICT DO NOTHING;

-- Students/guardians: view timetable + assignments, submit own work.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Student','Guardian') AND p.code IN ('timetable.view','assignment.view','assignment.submit')
ON CONFLICT DO NOTHING;

-- ---- Teacher list: app_users with a teaching role --------------------------
CREATE OR REPLACE FUNCTION core.fn_teacher_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.full_name),'[]'::jsonb) INTO v FROM (
        SELECT DISTINCT u.user_id, COALESCE(u.full_name, u.username) AS full_name, u.username, u.email
          FROM core.app_user u
          JOIN core.user_role ur ON ur.user_id = u.user_id
          JOIN core.role r ON r.role_id = ur.role_id
         WHERE u.tenant_id = p_tenant_id AND u.is_active = true
           AND r.name IN ('Teacher','ClassTeacher','Principal','SchoolAdmin')
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- =============================================================================
-- TIMETABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS academics.timetable_slot (
    slot_id      bigserial    PRIMARY KEY,
    tenant_id    integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    class_id     bigint       NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    section_id   bigint       NULL REFERENCES academics.class_section(section_id) ON DELETE SET NULL,
    day_of_week  smallint     NOT NULL,   -- 1=Mon ... 6=Sat (0=Sun unused)
    period_no    smallint     NOT NULL,
    start_time   time         NULL,
    end_time     time         NULL,
    subject_id   bigint       NULL REFERENCES academics.subject(subject_id) ON DELETE SET NULL,
    teacher_id   bigint       NULL REFERENCES core.app_user(user_id) ON DELETE SET NULL,
    room         varchar(40)  NULL,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    updated_at   timestamptz  NULL,
    CONSTRAINT ck_tt_day CHECK (day_of_week BETWEEN 1 AND 7)
);
CREATE INDEX IF NOT EXISTS ix_tt_class ON academics.timetable_slot (tenant_id, class_id, section_id);

-- One slot per (class, section, day, period). COALESCE handles NULL section, so a
-- table-level UNIQUE won't work here — use a unique index on the expression.
DROP INDEX IF EXISTS academics.uq_tt_slot_idx;
CREATE UNIQUE INDEX uq_tt_slot_idx
  ON academics.timetable_slot (tenant_id, class_id, COALESCE(section_id,0), day_of_week, period_no);

-- Save (insert/update) one slot. Payload: { slot_id?, class_id, section_id?, day_of_week,
--   period_no, start_time?, end_time?, subject_id?, teacher_id?, room? }
CREATE OR REPLACE FUNCTION academics.fn_timetable_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'slot_id','')::bigint;
        v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_day smallint := NULLIF(p_payload->>'day_of_week','')::smallint;
        v_period smallint := NULLIF(p_payload->>'period_no','')::smallint;
        v_owner integer;
BEGIN
    IF v_class IS NULL OR v_day IS NULL OR v_period IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class, day and period are required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.timetable_slot
            (tenant_id, class_id, section_id, day_of_week, period_no, start_time, end_time, subject_id, teacher_id, room)
        VALUES (p_tenant_id, v_class, v_section, v_day, v_period,
                NULLIF(p_payload->>'start_time','')::time, NULLIF(p_payload->>'end_time','')::time,
                NULLIF(p_payload->>'subject_id','')::bigint, NULLIF(p_payload->>'teacher_id','')::bigint,
                NULLIF(p_payload->>'room',''))
        ON CONFLICT (tenant_id, class_id, COALESCE(section_id,0), day_of_week, period_no)
        DO UPDATE SET start_time=EXCLUDED.start_time, end_time=EXCLUDED.end_time,
                      subject_id=EXCLUDED.subject_id, teacher_id=EXCLUDED.teacher_id,
                      room=EXCLUDED.room, updated_at=now()
        RETURNING slot_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.timetable_slot WHERE slot_id=v_id;
        IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
            RETURN jsonb_build_object('result_code',4,'message','Slot not found','data',NULL);
        END IF;
        UPDATE academics.timetable_slot SET
            class_id=v_class, section_id=v_section, day_of_week=v_day, period_no=v_period,
            start_time=NULLIF(p_payload->>'start_time','')::time, end_time=NULLIF(p_payload->>'end_time','')::time,
            subject_id=NULLIF(p_payload->>'subject_id','')::bigint, teacher_id=NULLIF(p_payload->>'teacher_id','')::bigint,
            room=NULLIF(p_payload->>'room',''), updated_at=now()
         WHERE slot_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('slot_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','That day + period already has a slot for this class/section','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- List slots for a class (optional section). Payload: { class_id, section_id? }
CREATE OR REPLACE FUNCTION academics.fn_timetable_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v jsonb;
BEGIN
    IF v_class IS NULL THEN RETURN jsonb_build_object('result_code',3,'message','class_id required','data',NULL); END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.day_of_week, t.period_no),'[]'::jsonb) INTO v FROM (
        SELECT ts.slot_id, ts.class_id, c.name AS class_name, ts.section_id, sec.name AS section_name,
               ts.day_of_week, ts.period_no, ts.start_time::text AS start_time, ts.end_time::text AS end_time,
               ts.subject_id, sub.name AS subject_name,
               ts.teacher_id, COALESCE(u.full_name, u.username) AS teacher_name, ts.room
          FROM academics.timetable_slot ts
          LEFT JOIN academics.school_class  c   ON c.class_id=ts.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=ts.section_id
          LEFT JOIN academics.subject       sub ON sub.subject_id=ts.subject_id
          LEFT JOIN core.app_user           u   ON u.user_id=ts.teacher_id
         WHERE ts.tenant_id=p_tenant_id AND ts.class_id=v_class
           AND (v_section IS NULL OR ts.section_id IS NOT DISTINCT FROM v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- A student's own timetable (resolves class/section from student_id). Payload: { student_id }
CREATE OR REPLACE FUNCTION academics.fn_timetable_for_student(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_class bigint; v_section bigint; v jsonb;
BEGIN
    SELECT class_id, section_id INTO v_class, v_section
      FROM academics.student WHERE student_id=v_sid AND tenant_id=p_tenant_id;
    IF v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',0,'message','No class',
            'data',jsonb_build_object('items','[]'::jsonb));
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.day_of_week, t.period_no),'[]'::jsonb) INTO v FROM (
        SELECT ts.slot_id, ts.day_of_week, ts.period_no,
               ts.start_time::text AS start_time, ts.end_time::text AS end_time,
               sub.name AS subject_name, COALESCE(u.full_name,u.username) AS teacher_name, ts.room
          FROM academics.timetable_slot ts
          LEFT JOIN academics.subject sub ON sub.subject_id=ts.subject_id
          LEFT JOIN core.app_user u ON u.user_id=ts.teacher_id
         WHERE ts.tenant_id=p_tenant_id AND ts.class_id=v_class
           AND (ts.section_id IS NULL OR ts.section_id = v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Delete a slot. Payload: { slot_id }
CREATE OR REPLACE FUNCTION academics.fn_timetable_delete(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'slot_id')::bigint; v_owner integer;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.timetable_slot WHERE slot_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Slot not found','data',NULL);
    END IF;
    DELETE FROM academics.timetable_slot WHERE slot_id=v_id AND tenant_id=p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message','Deleted','data',jsonb_build_object('slot_id',v_id));
END; $$;

-- =============================================================================
-- ASSIGNMENTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS academics.assignment (
    assignment_id bigserial   PRIMARY KEY,
    tenant_id     integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    class_id      bigint      NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    section_id    bigint      NULL REFERENCES academics.class_section(section_id) ON DELETE SET NULL,
    subject_id    bigint      NULL REFERENCES academics.subject(subject_id) ON DELETE SET NULL,
    teacher_id    bigint      NULL REFERENCES core.app_user(user_id) ON DELETE SET NULL,
    title         varchar(200) NOT NULL,
    description   text         NULL,
    due_date      date         NULL,
    max_marks     numeric(6,2) NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NULL
);
CREATE INDEX IF NOT EXISTS ix_assignment_class ON academics.assignment (tenant_id, class_id, section_id, due_date DESC);

CREATE TABLE IF NOT EXISTS academics.assignment_submission (
    submission_id bigserial   PRIMARY KEY,
    tenant_id     integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    assignment_id bigint      NOT NULL REFERENCES academics.assignment(assignment_id) ON DELETE CASCADE,
    student_id    bigint      NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    content       text         NULL,          -- student's answer / note / link
    status        varchar(20) NOT NULL DEFAULT 'Submitted', -- Submitted | Graded
    marks         numeric(6,2) NULL,
    feedback      varchar(500) NULL,
    submitted_at  timestamptz NOT NULL DEFAULT now(),
    graded_at     timestamptz NULL,
    graded_by     bigint      NULL,
    CONSTRAINT uq_submission UNIQUE (tenant_id, assignment_id, student_id)
);
CREATE INDEX IF NOT EXISTS ix_submission_assignment ON academics.assignment_submission (tenant_id, assignment_id);

-- Create/update an assignment. Payload: { assignment_id?, class_id, section_id?, subject_id?,
--   teacher_id?, title, description?, due_date?, max_marks? }
CREATE OR REPLACE FUNCTION academics.fn_assignment_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'assignment_id','')::bigint;
        v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_title text := NULLIF(p_payload->>'title','');
        v_owner integer;
BEGIN
    IF v_class IS NULL OR v_title IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','Class and title are required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.assignment
            (tenant_id, class_id, section_id, subject_id, teacher_id, title, description, due_date, max_marks)
        VALUES (p_tenant_id, v_class, NULLIF(p_payload->>'section_id','')::bigint,
                NULLIF(p_payload->>'subject_id','')::bigint, NULLIF(p_payload->>'teacher_id','')::bigint,
                v_title, NULLIF(p_payload->>'description',''), NULLIF(p_payload->>'due_date','')::date,
                NULLIF(p_payload->>'max_marks','')::numeric)
        RETURNING assignment_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.assignment WHERE assignment_id=v_id;
        IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
            RETURN jsonb_build_object('result_code',4,'message','Assignment not found','data',NULL);
        END IF;
        UPDATE academics.assignment SET
            class_id=v_class, section_id=NULLIF(p_payload->>'section_id','')::bigint,
            subject_id=NULLIF(p_payload->>'subject_id','')::bigint,
            teacher_id=NULLIF(p_payload->>'teacher_id','')::bigint,
            title=v_title, description=NULLIF(p_payload->>'description',''),
            due_date=NULLIF(p_payload->>'due_date','')::date, max_marks=NULLIF(p_payload->>'max_marks','')::numeric,
            updated_at=now()
         WHERE assignment_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('assignment_id',v_id));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Staff list with filters + submission counts. Payload: { class_id?, section_id?, subject_id? }
CREATE OR REPLACE FUNCTION academics.fn_assignment_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_subject bigint := NULLIF(p_payload->>'subject_id','')::bigint;
        v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.due_date DESC NULLS LAST, t.created_at DESC),'[]'::jsonb) INTO v FROM (
        SELECT a.assignment_id, a.class_id, c.name AS class_name, a.section_id, sec.name AS section_name,
               a.subject_id, sub.name AS subject_name, a.teacher_id, COALESCE(u.full_name,u.username) AS teacher_name,
               a.title, a.description, a.due_date, a.max_marks, a.created_at,
               (SELECT count(*) FROM academics.assignment_submission s WHERE s.assignment_id=a.assignment_id) AS submission_count
          FROM academics.assignment a
          LEFT JOIN academics.school_class  c   ON c.class_id=a.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=a.section_id
          LEFT JOIN academics.subject       sub ON sub.subject_id=a.subject_id
          LEFT JOIN core.app_user           u   ON u.user_id=a.teacher_id
         WHERE a.tenant_id=p_tenant_id
           AND (v_class IS NULL OR a.class_id=v_class)
           AND (v_section IS NULL OR a.section_id IS NOT DISTINCT FROM v_section)
           AND (v_subject IS NULL OR a.subject_id=v_subject)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- A student's assignments (their class/section) incl. their own submission state.
-- Payload: { student_id }
CREATE OR REPLACE FUNCTION academics.fn_assignment_for_student(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_class bigint; v_section bigint; v jsonb;
BEGIN
    SELECT class_id, section_id INTO v_class, v_section
      FROM academics.student WHERE student_id=v_sid AND tenant_id=p_tenant_id;
    IF v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',0,'message','No class','data',jsonb_build_object('items','[]'::jsonb));
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.due_date DESC NULLS LAST, t.created_at DESC),'[]'::jsonb) INTO v FROM (
        SELECT a.assignment_id, sub.name AS subject_name, COALESCE(u.full_name,u.username) AS teacher_name,
               a.title, a.description, a.due_date, a.max_marks, a.created_at,
               s.submission_id, s.content AS my_content, s.status AS my_status, s.marks AS my_marks,
               s.feedback AS my_feedback, s.submitted_at AS my_submitted_at
          FROM academics.assignment a
          LEFT JOIN academics.subject sub ON sub.subject_id=a.subject_id
          LEFT JOIN core.app_user u ON u.user_id=a.teacher_id
          LEFT JOIN academics.assignment_submission s
                 ON s.assignment_id=a.assignment_id AND s.student_id=v_sid AND s.tenant_id=p_tenant_id
         WHERE a.tenant_id=p_tenant_id AND a.class_id=v_class
           AND (a.section_id IS NULL OR a.section_id=v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Submissions for one assignment (teacher review). Payload: { assignment_id }
CREATE OR REPLACE FUNCTION academics.fn_assignment_submissions(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_aid bigint := (p_payload->>'assignment_id')::bigint; v_owner integer; v_class bigint; v_section bigint; v jsonb;
BEGIN
    SELECT tenant_id, class_id, section_id INTO v_owner, v_class, v_section
      FROM academics.assignment WHERE assignment_id=v_aid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Assignment not found','data',NULL);
    END IF;
    -- One row per student in the class/section, with their submission if any.
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.roll_number NULLS LAST, t.last_name),'[]'::jsonb) INTO v FROM (
        SELECT st.student_id, st.admission_number, st.roll_number, st.first_name, st.last_name,
               s.submission_id, s.content, s.status, s.marks, s.feedback, s.submitted_at, s.graded_at
          FROM academics.student st
          LEFT JOIN academics.assignment_submission s
                 ON s.student_id=st.student_id AND s.assignment_id=v_aid AND s.tenant_id=p_tenant_id
         WHERE st.tenant_id=p_tenant_id AND st.class_id=v_class AND st.status='Active'
           AND (v_section IS NULL OR st.section_id=v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Student submits (or re-submits before grading). Payload: { assignment_id, student_id, content }
CREATE OR REPLACE FUNCTION academics.fn_assignment_submit(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_aid bigint := (p_payload->>'assignment_id')::bigint;
        v_sid bigint := (p_payload->>'student_id')::bigint;
        v_content text := NULLIF(p_payload->>'content','');
        v_owner integer; v_id bigint; v_status text;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.assignment WHERE assignment_id=v_aid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Assignment not found','data',NULL);
    END IF;
    SELECT submission_id, status INTO v_id, v_status
      FROM academics.assignment_submission WHERE assignment_id=v_aid AND student_id=v_sid AND tenant_id=p_tenant_id;
    IF v_id IS NOT NULL AND v_status='Graded' THEN
        RETURN jsonb_build_object('result_code',3,'message','Already graded — cannot change','data',NULL);
    END IF;
    INSERT INTO academics.assignment_submission (tenant_id, assignment_id, student_id, content, status, submitted_at)
    VALUES (p_tenant_id, v_aid, v_sid, v_content, 'Submitted', now())
    ON CONFLICT (tenant_id, assignment_id, student_id)
    DO UPDATE SET content=EXCLUDED.content, status='Submitted', submitted_at=now()
    RETURNING submission_id INTO v_id;
    RETURN jsonb_build_object('result_code',0,'message','Submitted','data',jsonb_build_object('submission_id',v_id));
END; $$;

-- Teacher grades a submission. Payload: { submission_id, marks?, feedback?, actor_user_id }
CREATE OR REPLACE FUNCTION academics.fn_assignment_grade(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'submission_id')::bigint;
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint; v_owner integer;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.assignment_submission WHERE submission_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Submission not found','data',NULL);
    END IF;
    UPDATE academics.assignment_submission SET
        marks=NULLIF(p_payload->>'marks','')::numeric, feedback=NULLIF(p_payload->>'feedback',''),
        status='Graded', graded_at=now(), graded_by=v_actor
     WHERE submission_id=v_id AND tenant_id=p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message','Graded','data',jsonb_build_object('submission_id',v_id));
END; $$;

-- Delete an assignment. Payload: { assignment_id }
CREATE OR REPLACE FUNCTION academics.fn_assignment_delete(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'assignment_id')::bigint; v_owner integer;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.assignment WHERE assignment_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Assignment not found','data',NULL);
    END IF;
    DELETE FROM academics.assignment WHERE assignment_id=v_id AND tenant_id=p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message','Deleted','data',jsonb_build_object('assignment_id',v_id));
END; $$;
