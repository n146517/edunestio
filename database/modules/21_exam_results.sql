-- =============================================================================
-- EduNestIO :: Module — Exam result preview + publish guard (21_exam_results.sql)
-- Class-wide result calculation for review before publishing: per-student totals,
-- percentage, grade (from grade_scheme), pass/fail, and a Ready/Missing status
-- (Missing = at least one configured subject has no marks and is not marked absent).
-- fn_exam_publish gains a missing-marks guard (blocked unless Force=true).
-- Results are computed against the exam_subjects of the STUDENT'S OWN class only.
-- Idempotent; apply after modules 14, 18, 19, 20.
-- =============================================================================

-- Payload: { exam_id, class_id, section_id? }
CREATE OR REPLACE FUNCTION academics.fn_exam_result_preview(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_exam    bigint := (p_payload->>'exam_id')::bigint;
    v_class   bigint := (p_payload->>'class_id')::bigint;
    v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
    v_owner   integer;
    v_subj_count int;
    v_items   jsonb;
    v_total_students int := 0; v_completed int := 0; v_missing int := 0;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    -- Subjects configured for this exam + class.
    SELECT count(*) INTO v_subj_count
      FROM academics.exam_subject WHERE tenant_id=p_tenant_id AND exam_id=v_exam AND class_id=v_class;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.roll_number NULLS LAST, t.last_name, t.first_name),'[]'::jsonb),
           count(*)::int,
           count(*) FILTER (WHERE t.status = 'Ready')::int,
           count(*) FILTER (WHERE t.status = 'Missing')::int
      INTO v_items, v_total_students, v_completed, v_missing
      FROM (
        SELECT s.student_id, s.admission_number, s.roll_number, s.first_name, s.last_name,
               agg.obtained, agg.max_total, agg.percentage, agg.marked_count, agg.failed,
               CASE WHEN v_subj_count = 0 THEN 'Missing'
                    WHEN agg.marked_count < v_subj_count THEN 'Missing'
                    ELSE 'Ready' END AS status,
               (SELECT grade FROM academics.grade_scheme g
                 WHERE g.tenant_id=p_tenant_id AND agg.percentage BETWEEN g.min_percent AND g.max_percent LIMIT 1) AS grade,
               CASE WHEN v_subj_count = 0 OR agg.marked_count < v_subj_count THEN 'Incomplete'
                    WHEN agg.failed = 0 THEN 'Pass' ELSE 'Fail' END AS result
          FROM academics.student s
          CROSS JOIN LATERAL (
            SELECT
              COALESCE(sum(CASE WHEN NOT COALESCE(m.is_absent,false) THEN m.marks ELSE 0 END),0) AS obtained,
              COALESCE(sum(es.max_marks),0) AS max_total,
              CASE WHEN COALESCE(sum(es.max_marks),0) > 0
                   THEN round(COALESCE(sum(CASE WHEN NOT COALESCE(m.is_absent,false) THEN m.marks ELSE 0 END),0)
                              / sum(es.max_marks) * 100, 2) ELSE 0 END AS percentage,
              count(m.exam_mark_id) FILTER (WHERE m.marks IS NOT NULL OR COALESCE(m.is_absent,false)) AS marked_count,
              count(*) FILTER (WHERE COALESCE(m.is_absent,false)
                                  OR COALESCE(m.marks,0) < es.pass_marks) AS failed
            FROM academics.exam_subject es
            LEFT JOIN academics.exam_mark m
              ON m.exam_subject_id=es.exam_subject_id AND m.student_id=s.student_id AND m.tenant_id=p_tenant_id
           WHERE es.tenant_id=p_tenant_id AND es.exam_id=v_exam AND es.class_id=v_class
          ) agg
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
           AND (v_section IS NULL OR s.section_id=v_section)
      ) t;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object(
            'exam_id',v_exam,'class_id',v_class,'subject_count',v_subj_count,
            'total_students',v_total_students,'completed',v_completed,'missing',v_missing,
            'ready_to_publish',(v_missing = 0 AND v_total_students > 0),
            'items',v_items));
END; $$;

-- =============================================================================
-- fn_exam_publish (REPLACES): adds a missing-marks guard across ALL classes of
-- the exam. Blocked (result_code 3) when any student is missing marks, unless
-- the payload sets Force=true. Payload: { ExamId, Publish, Force? }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_publish(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_exam bigint := (p_payload->>'ExamId')::bigint; v_owner integer;
        v_pub boolean := COALESCE((p_payload->>'Publish')::boolean,true);
        v_force boolean := COALESCE((p_payload->>'Force')::boolean,false);
        v_missing int;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_exam;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;

    -- Guard only applies when publishing (not when unpublishing).
    IF v_pub AND NOT v_force THEN
        -- Count active students (across the exam's classes) who are missing at least
        -- one subject's marks for their class.
        SELECT count(*) INTO v_missing
          FROM academics.exam_class ec
          JOIN academics.student s ON s.class_id=ec.class_id AND s.tenant_id=p_tenant_id AND s.status='Active'
         WHERE ec.exam_id=v_exam AND ec.tenant_id=p_tenant_id
           AND (
             SELECT count(*) FROM academics.exam_subject es
              WHERE es.exam_id=v_exam AND es.class_id=ec.class_id AND es.tenant_id=p_tenant_id
           ) <> (
             SELECT count(*) FROM academics.exam_subject es
              JOIN academics.exam_mark m ON m.exam_subject_id=es.exam_subject_id
                   AND m.student_id=s.student_id AND m.tenant_id=p_tenant_id
                   AND (m.marks IS NOT NULL OR m.is_absent)
              WHERE es.exam_id=v_exam AND es.class_id=ec.class_id AND es.tenant_id=p_tenant_id
           );

        IF v_missing > 0 THEN
            RETURN jsonb_build_object('result_code',3,
                'message', v_missing || ' student(s) have missing marks. Complete marks entry or publish with override.',
                'data', jsonb_build_object('missing', v_missing));
        END IF;
    END IF;

    UPDATE academics.exam SET is_published=v_pub, updated_at=now() WHERE exam_id=v_exam AND tenant_id=p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message',CASE WHEN v_pub THEN 'Published' ELSE 'Unpublished' END,
        'data',jsonb_build_object('exam_id',v_exam,'is_published',v_pub));
END; $$;
