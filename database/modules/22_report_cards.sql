-- =============================================================================
-- EduNestIO :: Module — Report cards (22_report_cards.sql)
-- 1) FIX fn_exam_report_card for multi-class exams: only include the exam_subjects
--    of the STUDENT'S OWN class (previously it summed every class's subjects,
--    double-counting). Also returns student + exam header info for a printable card.
-- 2) NEW fn_report_card_class_list: class/section roster with per-student
--    percentage/grade/result + published flag for the class-wise report screen.
-- Idempotent; apply after modules 14, 16, 18-21.
-- =============================================================================

-- Report card for a student+exam. Payload: { exam_id, student_id, require_published? }
CREATE OR REPLACE FUNCTION academics.fn_exam_report_card(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_exam bigint := (p_payload->>'exam_id')::bigint; v_student bigint := (p_payload->>'student_id')::bigint;
    v_require_pub boolean := COALESCE((p_payload->>'require_published')::boolean,false);
    v_owner integer; v_pub boolean; v_items jsonb; v_total numeric := 0; v_max_total numeric := 0;
    v_pct numeric; v_grade text; v_failed int; v_subj_count int; v_class bigint; v_student_json jsonb; v_exam_json jsonb;
BEGIN
    SELECT tenant_id, is_published INTO v_owner, v_pub FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;
    IF v_require_pub AND NOT v_pub THEN RETURN jsonb_build_object('result_code',6,'message','Results not published yet','data',NULL); END IF;

    -- The student's current class drives which exam_subjects count.
    SELECT class_id INTO v_class FROM academics.student WHERE student_id=v_student AND tenant_id=p_tenant_id;
    IF v_class IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Student not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.subject_name),'[]'::jsonb),
           COALESCE(sum(t.marks) FILTER (WHERE NOT t.is_absent),0),
           COALESCE(sum(t.max_marks),0),
           count(*) FILTER (WHERE t.passed = false),
           count(*)
      INTO v_items, v_total, v_max_total, v_failed, v_subj_count
      FROM (
        SELECT sub.name AS subject_name, es.subject_type, es.max_marks, es.pass_marks,
               m.marks, COALESCE(m.is_absent,false) AS is_absent,
               (COALESCE(m.marks,0) >= es.pass_marks AND NOT COALESCE(m.is_absent,false)) AS passed
          FROM academics.exam_subject es
          JOIN academics.subject sub ON sub.subject_id=es.subject_id
          LEFT JOIN academics.exam_mark m ON m.exam_subject_id=es.exam_subject_id AND m.student_id=v_student AND m.tenant_id=p_tenant_id
         WHERE es.exam_id=v_exam AND es.tenant_id=p_tenant_id AND es.class_id=v_class) t;

    v_pct := CASE WHEN v_max_total > 0 THEN round(v_total / v_max_total * 100, 2) ELSE 0 END;
    SELECT grade INTO v_grade FROM academics.grade_scheme
     WHERE tenant_id=p_tenant_id AND v_pct BETWEEN min_percent AND max_percent LIMIT 1;

    -- Header info for a printable card.
    SELECT to_jsonb(x) INTO v_student_json FROM (
        SELECT s.student_id, s.admission_number, s.roll_number, s.first_name, s.last_name,
               s.photo_url, c.name AS class_name, sec.name AS section_name
          FROM academics.student s
          LEFT JOIN academics.school_class c ON c.class_id=s.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=s.section_id
         WHERE s.student_id=v_student AND s.tenant_id=p_tenant_id) x;

    SELECT to_jsonb(y) INTO v_exam_json FROM (
        SELECT e.exam_id, e.name AS exam_name, e.exam_type, ay.name AS academic_year_name,
               t.name AS school_name
          FROM academics.exam e
          LEFT JOIN academics.academic_year ay ON ay.academic_year_id=e.academic_year_id
          JOIN core.tenant t ON t.tenant_id=e.tenant_id
         WHERE e.exam_id=v_exam) y;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_id',v_exam,'student_id',v_student,'is_published',v_pub,
            'student',v_student_json,'exam',v_exam_json,
            'subjects',v_items,'obtained',v_total,'max_total',v_max_total,'percentage',v_pct,
            'grade',CASE WHEN v_max_total = 0 THEN 'N/A' ELSE COALESCE(v_grade,'N/A') END,
            'result',CASE WHEN v_max_total = 0 THEN 'N/A' WHEN v_failed = 0 THEN 'Pass' ELSE 'Fail' END));
END; $$;

-- =============================================================================
-- fn_report_card_class_list : class/section roster with result summary + published.
-- Payload: { exam_id, class_id, section_id? }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_report_card_class_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'exam_id')::bigint; v_class bigint := (p_payload->>'class_id')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint; v_owner integer; v_pub boolean; v jsonb;
BEGIN
    SELECT tenant_id, is_published INTO v_owner, v_pub FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.roll_number NULLS LAST, t.last_name, t.first_name),'[]'::jsonb) INTO v FROM (
        SELECT s.student_id, s.admission_number, s.roll_number, s.first_name, s.last_name,
               agg.obtained, agg.max_total, agg.percentage,
               (SELECT grade FROM academics.grade_scheme g
                 WHERE g.tenant_id=p_tenant_id AND agg.percentage BETWEEN g.min_percent AND g.max_percent LIMIT 1) AS grade,
               CASE WHEN agg.subj = 0 OR agg.marked < agg.subj THEN 'Incomplete'
                    WHEN agg.failed = 0 THEN 'Pass' ELSE 'Fail' END AS result
          FROM academics.student s
          CROSS JOIN LATERAL (
            SELECT COALESCE(sum(CASE WHEN NOT COALESCE(m.is_absent,false) THEN m.marks ELSE 0 END),0) AS obtained,
                   COALESCE(sum(es.max_marks),0) AS max_total,
                   CASE WHEN COALESCE(sum(es.max_marks),0)>0
                        THEN round(COALESCE(sum(CASE WHEN NOT COALESCE(m.is_absent,false) THEN m.marks ELSE 0 END),0)/sum(es.max_marks)*100,2)
                        ELSE 0 END AS percentage,
                   count(*) AS subj,
                   count(m.exam_mark_id) FILTER (WHERE m.marks IS NOT NULL OR COALESCE(m.is_absent,false)) AS marked,
                   count(*) FILTER (WHERE COALESCE(m.is_absent,false) OR COALESCE(m.marks,0) < es.pass_marks) AS failed
              FROM academics.exam_subject es
              LEFT JOIN academics.exam_mark m ON m.exam_subject_id=es.exam_subject_id AND m.student_id=s.student_id AND m.tenant_id=p_tenant_id
             WHERE es.tenant_id=p_tenant_id AND es.exam_id=v_exam AND es.class_id=v_class
          ) agg
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
           AND (v_section IS NULL OR s.section_id=v_section)
    ) t;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('exam_id',v_exam,'class_id',v_class,'is_published',v_pub,'items',v));
END; $$;

-- =============================================================================
-- Patch legacy fn_exam_subject_add to populate exam_subject.class_id from the
-- exam's (legacy) class_id, so single-subject-add stays consistent with the
-- per-class model used by report cards / results. Payload: {ExamId,SubjectId,MaxMarks,PassMarks}
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_subject_add(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'ExamId')::bigint; v_subj bigint := (p_payload->>'SubjectId')::bigint;
        v_eowner integer; v_sowner integer; v_id bigint; v_class bigint;
BEGIN
    SELECT tenant_id, class_id INTO v_eowner, v_class FROM academics.exam WHERE exam_id=v_exam;
    SELECT tenant_id INTO v_sowner FROM academics.subject WHERE subject_id=v_subj;
    IF v_eowner IS DISTINCT FROM p_tenant_id OR v_sowner IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid exam or subject for tenant','data',NULL);
    END IF;
    -- Fall back to the exam's first class if the legacy class_id is null.
    IF v_class IS NULL THEN
        SELECT class_id INTO v_class FROM academics.exam_class WHERE exam_id=v_exam ORDER BY class_id LIMIT 1;
    END IF;
    INSERT INTO academics.exam_subject (tenant_id,exam_id,class_id,subject_id,max_marks,pass_marks,subject_type)
    VALUES (p_tenant_id,v_exam,v_class,v_subj,
            COALESCE((p_payload->>'MaxMarks')::numeric,100),COALESCE((p_payload->>'PassMarks')::numeric,33),'Theory')
    RETURNING exam_subject_id INTO v_id;
    RETURN jsonb_build_object('result_code',0,'message','Added','data',jsonb_build_object('exam_subject_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','Subject already in exam','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;
