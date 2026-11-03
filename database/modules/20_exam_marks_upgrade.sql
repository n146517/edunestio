-- =============================================================================
-- EduNestIO :: Module — Marks entry upgrade (20_exam_marks_upgrade.sql)
-- Makes marks entry work correctly for multi-class exams by rostering on the
-- exam_subject's OWN class_id (not the legacy exam.class_id). Adds a section
-- filter + roll number to the sheet, and a resolver that maps
-- (exam, class, subject) -> exam_subject_id for dropdown-driven UIs.
-- Idempotent; apply after modules 14 and 19.
-- =============================================================================

-- Resolve the exam_subject for a given exam + class + subject (for the marks UI).
-- Payload: { exam_id, class_id, subject_id }
CREATE OR REPLACE FUNCTION academics.fn_exam_subject_resolve(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_class bigint := (p_payload->>'class_id')::bigint;
        v_subj bigint := (p_payload->>'subject_id')::bigint; v_es bigint; v_max numeric; v_pass numeric;
BEGIN
    SELECT exam_subject_id, max_marks, pass_marks INTO v_es, v_max, v_pass
      FROM academics.exam_subject
     WHERE tenant_id=p_tenant_id AND exam_id=v_exam AND class_id=v_class AND subject_id=v_subj;
    IF v_es IS NULL THEN
        RETURN jsonb_build_object('result_code',4,'message','This subject is not configured for the selected exam and class','data',NULL);
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_subject_id',v_es,'max_marks',v_max,'pass_marks',v_pass));
END; $$;

-- Subjects configured for an exam+class (to populate the marks-entry subject dropdown).
-- Payload: { exam_id, class_id }
CREATE OR REPLACE FUNCTION academics.fn_exam_subjects_for_class(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_class bigint := (p_payload->>'class_id')::bigint; v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.subject_name),'[]'::jsonb) INTO v FROM (
        SELECT es.exam_subject_id, es.subject_id, sub.name AS subject_name, sub.code AS subject_code,
               es.max_marks, es.pass_marks, es.subject_type
          FROM academics.exam_subject es JOIN academics.subject sub ON sub.subject_id=es.subject_id
         WHERE es.tenant_id=p_tenant_id AND es.exam_id=v_exam AND es.class_id=v_class) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- =============================================================================
-- fn_exam_marks_sheet (REPLACES): roster uses the exam_subject's OWN class_id,
-- optional section filter, and returns roll_number. Payload:
-- { exam_subject_id, section_id? }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_marks_sheet(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_es bigint := (p_payload->>'exam_subject_id')::bigint; v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_owner integer; v_class bigint; v_max numeric; v_items jsonb;
BEGIN
    SELECT es.tenant_id, COALESCE(es.class_id, e.class_id), es.max_marks
      INTO v_owner, v_class, v_max
      FROM academics.exam_subject es JOIN academics.exam e ON e.exam_id=es.exam_id
     WHERE es.exam_subject_id=v_es;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam subject not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.roll_number NULLS LAST, t.last_name, t.first_name),'[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.admission_number, s.roll_number, s.first_name, s.last_name,
               m.marks, COALESCE(m.is_absent,false) AS is_absent,
               (m.exam_mark_id IS NOT NULL) AS entered
          FROM academics.student s
          LEFT JOIN academics.exam_mark m ON m.student_id=s.student_id AND m.exam_subject_id=v_es AND m.tenant_id=p_tenant_id
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
           AND (v_section IS NULL OR s.section_id=v_section)) t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_subject_id',v_es,'max_marks',v_max,'items',v_items));
END; $$;

-- =============================================================================
-- fn_exam_marks_save (REPLACES): validate against the exam_subject's OWN class.
-- Payload: {exam_subject_id, actor_user_id, entries:[{student_id,marks,is_absent}]}
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_marks_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_es bigint := (p_payload->>'exam_subject_id')::bigint; v_owner integer; v_max numeric;
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_entry jsonb; v_sid bigint; v_marks numeric; v_count int := 0; v_class bigint; v_sowner integer;
BEGIN
    SELECT es.tenant_id, COALESCE(es.class_id, e.class_id), es.max_marks
      INTO v_owner, v_class, v_max
      FROM academics.exam_subject es JOIN academics.exam e ON e.exam_id=es.exam_id
     WHERE es.exam_subject_id=v_es;
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
