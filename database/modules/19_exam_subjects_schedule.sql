-- =============================================================================
-- EduNestIO :: Module — Exam subjects (per class, typed) + schedule (19).
-- Adds class_id + subject_type (Theory/Practical) to exam_subject so each class
-- in a multi-class exam has its own subject set. Adds a per-subject schedule
-- (date/time/room). New stored fns to save/list class-subject config + schedule.
-- Idempotent; apply after module 18.
-- =============================================================================

-- ---- exam_subject: per-class + subject type ---------------------------------
ALTER TABLE academics.exam_subject ADD COLUMN IF NOT EXISTS class_id     bigint      NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE;
ALTER TABLE academics.exam_subject ADD COLUMN IF NOT EXISTS subject_type varchar(20) NOT NULL DEFAULT 'Theory';

-- Backfill class_id on legacy rows from the exam's (legacy) class_id.
UPDATE academics.exam_subject es
   SET class_id = e.class_id
  FROM academics.exam e
 WHERE es.exam_id = e.exam_id AND es.class_id IS NULL AND e.class_id IS NOT NULL;

-- Replace the (tenant,exam,subject) uniqueness with (tenant,exam,class,subject)
-- so the same subject can exist for different classes of the same exam.
ALTER TABLE academics.exam_subject DROP CONSTRAINT IF EXISTS uq_exam_subject;
CREATE UNIQUE INDEX IF NOT EXISTS uq_exam_subject_class
    ON academics.exam_subject (tenant_id, exam_id, COALESCE(class_id, 0), subject_id);
CREATE INDEX IF NOT EXISTS ix_exam_subject_exam_class ON academics.exam_subject (tenant_id, exam_id, class_id);

-- ---- Per-subject schedule ----------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.exam_schedule (
    schedule_id     bigserial   PRIMARY KEY,
    tenant_id       integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    exam_subject_id bigint      NOT NULL REFERENCES academics.exam_subject(exam_subject_id) ON DELETE CASCADE,
    exam_date       date        NULL,
    start_time      time        NULL,
    end_time        time        NULL,
    room            varchar(60) NULL,
    CONSTRAINT uq_exam_schedule UNIQUE (exam_subject_id)
);
CREATE INDEX IF NOT EXISTS ix_exam_schedule_tenant ON academics.exam_schedule (tenant_id, exam_subject_id);

-- =============================================================================
-- fn_exam_class_subjects_save : replace the subject set for ONE class of an exam.
-- Payload: { ExamId, ClassId, Subjects:[{ExamSubjectId?, SubjectId, MaxMarks,
--            PassMarks, SubjectType}] }  (rows not present are deleted)
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_class_subjects_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_exam  bigint := (p_payload->>'ExamId')::bigint;
    v_class bigint := (p_payload->>'ClassId')::bigint;
    v_owner integer; v_cowner integer;
    v_row jsonb; v_subj bigint; v_esid bigint; v_keep bigint[] := ARRAY[]::bigint[];
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;
    SELECT tenant_id INTO v_cowner FROM academics.school_class WHERE class_id=v_class;
    IF v_cowner IS DISTINCT FROM p_tenant_id THEN RETURN jsonb_build_object('result_code',3,'message','Invalid class','data',NULL); END IF;
    -- The class must be part of this exam.
    IF NOT EXISTS (SELECT 1 FROM academics.exam_class WHERE exam_id=v_exam AND class_id=v_class) THEN
        RETURN jsonb_build_object('result_code',3,'message','Class is not part of this exam','data',NULL);
    END IF;

    FOR v_row IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'Subjects','[]'::jsonb)) LOOP
        v_subj := (v_row->>'SubjectId')::bigint;
        IF NOT EXISTS (SELECT 1 FROM academics.subject WHERE subject_id=v_subj AND tenant_id=p_tenant_id) THEN
            RETURN jsonb_build_object('result_code',3,'message','Invalid subject for this school','data',NULL);
        END IF;
        INSERT INTO academics.exam_subject (tenant_id, exam_id, class_id, subject_id, max_marks, pass_marks, subject_type)
        VALUES (p_tenant_id, v_exam, v_class, v_subj,
                COALESCE((v_row->>'MaxMarks')::numeric,100), COALESCE((v_row->>'PassMarks')::numeric,33),
                COALESCE(NULLIF(v_row->>'SubjectType',''),'Theory'))
        ON CONFLICT (tenant_id, exam_id, COALESCE(class_id,0), subject_id)
        DO UPDATE SET max_marks=EXCLUDED.max_marks, pass_marks=EXCLUDED.pass_marks, subject_type=EXCLUDED.subject_type
        RETURNING exam_subject_id INTO v_esid;
        v_keep := array_append(v_keep, v_esid);
    END LOOP;

    -- Delete any class-subjects no longer in the submitted set.
    DELETE FROM academics.exam_subject
     WHERE tenant_id=p_tenant_id AND exam_id=v_exam AND class_id=v_class
       AND NOT (exam_subject_id = ANY(v_keep));

    RETURN jsonb_build_object('result_code',0,'message','Saved',
        'data',jsonb_build_object('exam_id',v_exam,'class_id',v_class,'count',array_length(v_keep,1)));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- =============================================================================
-- fn_exam_class_subjects_list : subject config for one class of an exam.
-- Payload: { exam_id, class_id }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_class_subjects_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_owner integer; v jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.subject_name),'[]'::jsonb) INTO v FROM (
        SELECT es.exam_subject_id, es.class_id, c.name AS class_name, es.subject_id, sub.name AS subject_name,
               sub.code AS subject_code, es.max_marks, es.pass_marks, es.subject_type
          FROM academics.exam_subject es
          JOIN academics.subject sub ON sub.subject_id=es.subject_id
          LEFT JOIN academics.school_class c ON c.class_id=es.class_id
         WHERE es.tenant_id=p_tenant_id AND es.exam_id=v_exam
           AND (v_class IS NULL OR es.class_id=v_class)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- =============================================================================
-- fn_exam_schedule_save : upsert schedule for a list of exam subjects.
-- Payload: { ExamId, Items:[{ExamSubjectId, ExamDate, StartTime, EndTime, Room}] }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_schedule_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'ExamId')::bigint; v_owner integer; v_row jsonb; v_es bigint; v_eowner integer; v_count int := 0;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    FOR v_row IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'Items','[]'::jsonb)) LOOP
        v_es := (v_row->>'ExamSubjectId')::bigint;
        SELECT tenant_id INTO v_eowner FROM academics.exam_subject WHERE exam_subject_id=v_es AND exam_id=v_exam;
        IF v_eowner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;  -- skip foreign
        INSERT INTO academics.exam_schedule (tenant_id, exam_subject_id, exam_date, start_time, end_time, room)
        VALUES (p_tenant_id, v_es, NULLIF(v_row->>'ExamDate','')::date,
                NULLIF(v_row->>'StartTime','')::time, NULLIF(v_row->>'EndTime','')::time, NULLIF(v_row->>'Room',''))
        ON CONFLICT (exam_subject_id)
        DO UPDATE SET exam_date=EXCLUDED.exam_date, start_time=EXCLUDED.start_time,
                      end_time=EXCLUDED.end_time, room=EXCLUDED.room;
        v_count := v_count + 1;
    END LOOP;
    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('saved',v_count));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- =============================================================================
-- fn_exam_schedule_list : schedule rows for an exam (optionally one class).
-- Payload: { exam_id, class_id? }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_schedule_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_owner integer; v jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.exam_date NULLS LAST, t.start_time NULLS LAST, t.subject_name),'[]'::jsonb) INTO v FROM (
        SELECT es.exam_subject_id, es.class_id, c.name AS class_name, sub.name AS subject_name, sub.code AS subject_code,
               es.subject_type, sch.exam_date, sch.start_time, sch.end_time, sch.room
          FROM academics.exam_subject es
          JOIN academics.subject sub ON sub.subject_id=es.subject_id
          LEFT JOIN academics.school_class c ON c.class_id=es.class_id
          LEFT JOIN academics.exam_schedule sch ON sch.exam_subject_id=es.exam_subject_id
         WHERE es.tenant_id=p_tenant_id AND es.exam_id=v_exam
           AND (v_class IS NULL OR es.class_id=v_class)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;
