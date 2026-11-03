-- =============================================================================
-- EduNestIO :: Module — Exams & Report Cards (14_exams.sql)
-- Exam setup, per-exam subjects (max/pass marks), bulk marks entry, grading scheme,
-- result calculation (percentage + grade + pass/fail), publish gate, report card.
-- Reuses academics.school_class / subject / student. Idempotent; apply after 10-13.
-- =============================================================================

CREATE TABLE IF NOT EXISTS academics.exam (
    exam_id    bigserial    PRIMARY KEY,
    tenant_id  integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name       varchar(120) NOT NULL,            -- e.g. 'Term 1 Exam'
    class_id   bigint       NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    exam_date  date         NULL,
    is_published boolean    NOT NULL DEFAULT false,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NULL,
    CONSTRAINT uq_exam UNIQUE (tenant_id, class_id, name)
);
COMMENT ON TABLE academics.exam IS 'An exam for a class; results hidden until published.';

CREATE TABLE IF NOT EXISTS academics.exam_subject (
    exam_subject_id bigserial PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    exam_id     bigint       NOT NULL REFERENCES academics.exam(exam_id) ON DELETE CASCADE,
    subject_id  bigint       NOT NULL REFERENCES academics.subject(subject_id) ON DELETE RESTRICT,
    max_marks   numeric(6,2) NOT NULL DEFAULT 100 CHECK (max_marks > 0),
    pass_marks  numeric(6,2) NOT NULL DEFAULT 33  CHECK (pass_marks >= 0),
    CONSTRAINT uq_exam_subject UNIQUE (tenant_id, exam_id, subject_id)
);

CREATE TABLE IF NOT EXISTS academics.exam_mark (
    exam_mark_id bigserial   PRIMARY KEY,
    tenant_id    integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    exam_subject_id bigint   NOT NULL REFERENCES academics.exam_subject(exam_subject_id) ON DELETE CASCADE,
    student_id   bigint      NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    marks        numeric(6,2) NULL,              -- null = not entered
    is_absent    boolean     NOT NULL DEFAULT false,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   bigint      NULL,
    CONSTRAINT uq_exam_mark UNIQUE (tenant_id, exam_subject_id, student_id)
);

-- Grading scheme (per tenant). min_percent..max_percent -> grade label.
CREATE TABLE IF NOT EXISTS academics.grade_scheme (
    grade_id    bigserial    PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    grade       varchar(5)   NOT NULL,
    min_percent numeric(5,2) NOT NULL,
    max_percent numeric(5,2) NOT NULL,
    CONSTRAINT uq_grade UNIQUE (tenant_id, grade),
    CONSTRAINT ck_grade_range CHECK (max_percent >= min_percent)
);

CREATE INDEX IF NOT EXISTS ix_exam_tenant_class   ON academics.exam (tenant_id, class_id);
CREATE INDEX IF NOT EXISTS ix_exam_subject_exam   ON academics.exam_subject (tenant_id, exam_id);
CREATE INDEX IF NOT EXISTS ix_exam_mark_subject   ON academics.exam_mark (tenant_id, exam_subject_id);
CREATE INDEX IF NOT EXISTS ix_exam_mark_student   ON academics.exam_mark (tenant_id, student_id);

-- Default grade scheme for demo tenants (idempotent).
INSERT INTO academics.grade_scheme (tenant_id, grade, min_percent, max_percent)
SELECT t.tenant_id, g.grade, g.lo, g.hi FROM core.tenant t
CROSS JOIN (VALUES ('A+',90,100),('A',80,89.99),('B',70,79.99),('C',60,69.99),
                   ('D',40,59.99),('F',0,39.99)) AS g(grade,lo,hi)
ON CONFLICT (tenant_id, grade) DO NOTHING;

-- Demo subjects for every tenant so Exams has data to work with (idempotent).
INSERT INTO academics.subject (tenant_id, name, code)
SELECT t.tenant_id, s.name, s.code FROM core.tenant t
CROSS JOIN (VALUES ('Mathematics','MATH'),('English','ENG'),('Science','SCI'),
                   ('Social Studies','SOC')) AS s(name,code)
ON CONFLICT (tenant_id, code) DO NOTHING;

-- Permissions
INSERT INTO core.permission (code, module, description) VALUES
 ('exam.view',    'Exams', 'View exams and results'),
 ('exam.manage',  'Exams', 'Create exams, subjects, grading scheme'),
 ('exam.marks',   'Exams', 'Enter/moderate marks'),
 ('exam.publish', 'Exams', 'Publish results')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code IN ('exam.view','exam.manage','exam.marks','exam.publish')
ON CONFLICT DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Teacher','ClassTeacher') AND p.code IN ('exam.view','exam.marks')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Functions
-- =============================================================================

CREATE OR REPLACE FUNCTION academics.fn_exam_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'ExamId','')::bigint; v_class bigint := (p_payload->>'ClassId')::bigint;
        v_owner integer; v_cowner integer;
BEGIN
    IF COALESCE(p_payload->>'Name','')='' OR v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','Name and class are required','data',NULL);
    END IF;
    SELECT tenant_id INTO v_cowner FROM academics.school_class WHERE class_id=v_class;
    IF v_cowner IS DISTINCT FROM p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Invalid class for tenant','data',NULL); END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.exam (tenant_id,name,class_id,exam_date)
        VALUES (p_tenant_id,p_payload->>'Name',v_class,NULLIF(p_payload->>'ExamDate','')::date)
        RETURNING exam_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.exam SET name=p_payload->>'Name', class_id=v_class,
               exam_date=NULLIF(p_payload->>'ExamDate','')::date, updated_at=now()
         WHERE exam_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('exam_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','Exam already exists for this class','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_exam_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint; v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.exam_date DESC NULLS LAST, t.name),'[]'::jsonb) INTO v FROM (
        SELECT e.exam_id, e.name, e.class_id, c.name AS class_name, e.exam_date, e.is_published,
               (SELECT count(*) FROM academics.exam_subject es WHERE es.exam_id=e.exam_id) AS subject_count
          FROM academics.exam e JOIN academics.school_class c ON c.class_id=e.class_id
         WHERE e.tenant_id=p_tenant_id AND (v_class IS NULL OR e.class_id=v_class)) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Add a subject to an exam. Payload: {ExamId, SubjectId, MaxMarks, PassMarks}
CREATE OR REPLACE FUNCTION academics.fn_exam_subject_add(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'ExamId')::bigint; v_subj bigint := (p_payload->>'SubjectId')::bigint;
        v_eowner integer; v_sowner integer; v_id bigint;
BEGIN
    SELECT tenant_id INTO v_eowner FROM academics.exam WHERE exam_id=v_exam;
    SELECT tenant_id INTO v_sowner FROM academics.subject WHERE subject_id=v_subj;
    IF v_eowner IS DISTINCT FROM p_tenant_id OR v_sowner IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid exam or subject for tenant','data',NULL);
    END IF;
    INSERT INTO academics.exam_subject (tenant_id,exam_id,subject_id,max_marks,pass_marks)
    VALUES (p_tenant_id,v_exam,v_subj,COALESCE((p_payload->>'MaxMarks')::numeric,100),COALESCE((p_payload->>'PassMarks')::numeric,33))
    RETURNING exam_subject_id INTO v_id;
    RETURN jsonb_build_object('result_code',0,'message','Added','data',jsonb_build_object('exam_subject_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','Subject already in exam','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Marks entry sheet for an exam subject (roster of the exam's class). Payload: {exam_subject_id}
CREATE OR REPLACE FUNCTION academics.fn_exam_marks_sheet(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_es bigint := (p_payload->>'exam_subject_id')::bigint; v_owner integer; v_class bigint; v_max numeric; v_items jsonb;
BEGIN
    SELECT es.tenant_id, e.class_id, es.max_marks INTO v_owner, v_class, v_max
      FROM academics.exam_subject es JOIN academics.exam e ON e.exam_id=es.exam_id WHERE es.exam_subject_id=v_es;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam subject not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.last_name, t.first_name),'[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.admission_number, s.first_name, s.last_name,
               m.marks, COALESCE(m.is_absent,false) AS is_absent
          FROM academics.student s
          LEFT JOIN academics.exam_mark m ON m.student_id=s.student_id AND m.exam_subject_id=v_es AND m.tenant_id=p_tenant_id
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active') t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_subject_id',v_es,'max_marks',v_max,'items',v_items));
END; $$;

-- Bulk save marks. Payload: {exam_subject_id, actor_user_id, entries:[{student_id,marks,is_absent}]}
CREATE OR REPLACE FUNCTION academics.fn_exam_marks_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_es bigint := (p_payload->>'exam_subject_id')::bigint; v_owner integer; v_max numeric; v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_entry jsonb; v_sid bigint; v_marks numeric; v_count int := 0; v_class bigint; v_sowner integer;
BEGIN
    SELECT es.tenant_id, e.class_id, es.max_marks INTO v_owner, v_class, v_max
      FROM academics.exam_subject es JOIN academics.exam e ON e.exam_id=es.exam_id WHERE es.exam_subject_id=v_es;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam subject not found','data',NULL); END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'entries','[]'::jsonb)) LOOP
        v_sid := (v_entry->>'student_id')::bigint;
        SELECT tenant_id INTO v_sowner FROM academics.student WHERE student_id=v_sid AND class_id=v_class;
        IF v_sowner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;  -- skip foreign/other-class
        v_marks := NULLIF(v_entry->>'marks','')::numeric;
        IF v_marks IS NOT NULL AND (v_marks < 0 OR v_marks > v_max) THEN
            RETURN jsonb_build_object('result_code',3,'message','Marks out of range (0..'||v_max||')','data',NULL);
        END IF;
        INSERT INTO academics.exam_mark (tenant_id,exam_subject_id,student_id,marks,is_absent,updated_by)
        VALUES (p_tenant_id,v_es,v_sid,v_marks,COALESCE((v_entry->>'is_absent')::boolean,false),v_actor)
        ON CONFLICT (tenant_id,exam_subject_id,student_id)
        DO UPDATE SET marks=EXCLUDED.marks, is_absent=EXCLUDED.is_absent, updated_at=now(), updated_by=v_actor;
        v_count := v_count + 1;
    END LOOP;
    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('saved',v_count));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_exam_publish(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'ExamId')::bigint; v_owner integer; v_pub boolean := COALESCE((p_payload->>'Publish')::boolean,true);
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;
    UPDATE academics.exam SET is_published=v_pub, updated_at=now() WHERE exam_id=v_exam AND tenant_id=p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message',CASE WHEN v_pub THEN 'Published' ELSE 'Unpublished' END,
        'data',jsonb_build_object('exam_id',v_exam,'is_published',v_pub));
END; $$;

-- Report card for a student+exam: per-subject marks + totals + percentage + grade + result.
-- Payload: {exam_id, student_id, require_published?}  (portal callers pass require_published=true)
CREATE OR REPLACE FUNCTION academics.fn_exam_report_card(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_student bigint := (p_payload->>'student_id')::bigint;
        v_require_pub boolean := COALESCE((p_payload->>'require_published')::boolean,false);
        v_owner integer; v_pub boolean; v_items jsonb; v_total numeric := 0; v_max_total numeric := 0;
        v_pct numeric; v_grade text; v_failed int;
BEGIN
    SELECT tenant_id, is_published INTO v_owner, v_pub FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;
    IF v_require_pub AND NOT v_pub THEN RETURN jsonb_build_object('result_code',6,'message','Results not published yet','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.subject_name),'[]'::jsonb),
           COALESCE(sum(t.marks),0), COALESCE(sum(t.max_marks),0),
           count(*) FILTER (WHERE t.passed = false)
      INTO v_items, v_total, v_max_total, v_failed
      FROM (
        SELECT sub.name AS subject_name, es.max_marks, es.pass_marks,
               m.marks, COALESCE(m.is_absent,false) AS is_absent,
               (COALESCE(m.marks,0) >= es.pass_marks AND NOT COALESCE(m.is_absent,false)) AS passed
          FROM academics.exam_subject es
          JOIN academics.subject sub ON sub.subject_id=es.subject_id
          LEFT JOIN academics.exam_mark m ON m.exam_subject_id=es.exam_subject_id AND m.student_id=v_student AND m.tenant_id=p_tenant_id
         WHERE es.exam_id=v_exam AND es.tenant_id=p_tenant_id) t;

    v_pct := CASE WHEN v_max_total > 0 THEN round(v_total / v_max_total * 100, 2) ELSE 0 END;
    SELECT grade INTO v_grade FROM academics.grade_scheme
     WHERE tenant_id=p_tenant_id AND v_pct BETWEEN min_percent AND max_percent LIMIT 1;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_id',v_exam,'student_id',v_student,'is_published',v_pub,
            'subjects',v_items,'obtained',v_total,'max_total',v_max_total,'percentage',v_pct,
            'grade',CASE WHEN v_max_total = 0 THEN 'N/A' ELSE COALESCE(v_grade,'N/A') END,
            'result',CASE WHEN v_max_total = 0 THEN 'N/A' WHEN v_failed = 0 THEN 'Pass' ELSE 'Fail' END));
END; $$;
