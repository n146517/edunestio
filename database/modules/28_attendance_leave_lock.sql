-- =============================================================================
-- EduNestIO :: Module — Attendance respects approved leave (28_attendance_leave_lock.sql)
-- When a student has an APPROVED leave covering the attendance date, the sheet
-- flags that row as on_leave + forces status 'Leave'. The UI then locks that row
-- (Present/Absent/Late disabled) so staff can't accidentally mark them present.
-- Also: fn_attendance_mark refuses to overwrite a leave-covered row to anything
-- other than 'Leave' (server-side guard, defence in depth). Idempotent.
-- Apply after module 27 (attendance modes) and 25 (leave).
-- =============================================================================

-- Sheet (REPLACE): add on_leave flag; force status 'Leave' on covered dates.
-- Payload: { class_id, attend_date, section_id?, subject_id? }
CREATE OR REPLACE FUNCTION academics.fn_attendance_sheet(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint;
        v_date date := (p_payload->>'attend_date')::date;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_subject bigint := NULLIF(p_payload->>'subject_id','')::bigint;
        v_items jsonb;
BEGIN
    IF v_class IS NULL OR v_date IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class_id and attend_date are required','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.roll_number NULLS LAST, t.last_name, t.first_name),'[]'::jsonb)
      INTO v_items FROM (
        SELECT s.student_id, s.admission_number, s.roll_number, s.first_name, s.last_name,
               lv.on_leave,
               CASE WHEN lv.on_leave THEN 'Leave' ELSE COALESCE(a.status,'Present') END AS status,
               CASE WHEN lv.on_leave THEN COALESCE(a.remark,'Approved leave') ELSE a.remark END AS remark,
               (a.attendance_id IS NOT NULL) AS marked
          FROM academics.student s
          LEFT JOIN academics.attendance a
            ON a.student_id=s.student_id AND a.tenant_id=p_tenant_id AND a.attend_date=v_date
               AND a.subject_id IS NOT DISTINCT FROM v_subject
          LEFT JOIN LATERAL (
            SELECT EXISTS (
              SELECT 1 FROM academics.leave_request lr
               WHERE lr.tenant_id=p_tenant_id AND lr.student_id=s.student_id
                 AND lr.status='Approved' AND v_date BETWEEN lr.from_date AND lr.to_date
            ) AS on_leave
          ) lv ON true
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
           AND (v_section IS NULL OR s.section_id=v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('class_id',v_class,'section_id',v_section,'subject_id',v_subject,
                                  'attend_date',v_date,'items',v_items));
END; $$;

-- Mark (REPLACE): if a student is on approved leave for the date, force 'Leave'
-- regardless of what the client sent (cannot be marked Present/Absent/Late).
-- Payload: { class_id, section_id?, subject_id?, attend_date, actor_user_id, entries:[...] }
CREATE OR REPLACE FUNCTION academics.fn_attendance_mark(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_subject bigint := NULLIF(p_payload->>'subject_id','')::bigint;
        v_date date := (p_payload->>'attend_date')::date;
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_entry jsonb; v_sid bigint; v_count int := 0; v_owner integer;
        v_status text; v_remark text; v_on_leave boolean;
BEGIN
    IF v_date IS NULL THEN RETURN jsonb_build_object('result_code',3,'message','attend_date is required','data',NULL); END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'entries','[]'::jsonb))
    LOOP
        v_sid := (v_entry->>'student_id')::bigint;
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;

        -- Is this student on approved leave for the date? If so, force 'Leave'.
        SELECT EXISTS (
          SELECT 1 FROM academics.leave_request lr
           WHERE lr.tenant_id=p_tenant_id AND lr.student_id=v_sid
             AND lr.status='Approved' AND v_date BETWEEN lr.from_date AND lr.to_date
        ) INTO v_on_leave;

        IF v_on_leave THEN
            v_status := 'Leave';
            v_remark := COALESCE(NULLIF(v_entry->>'remark',''), 'Approved leave');
        ELSE
            v_status := COALESCE(NULLIF(v_entry->>'status',''),'Present');
            v_remark := NULLIF(v_entry->>'remark','');
        END IF;

        INSERT INTO academics.attendance (tenant_id, student_id, class_id, section_id, subject_id, attend_date, status, remark, created_by)
        VALUES (p_tenant_id, v_sid, v_class, v_section, v_subject, v_date, v_status, v_remark, v_actor)
        ON CONFLICT (tenant_id, student_id, attend_date, COALESCE(subject_id, 0))
        DO UPDATE SET status=EXCLUDED.status, remark=EXCLUDED.remark,
                      class_id=EXCLUDED.class_id, section_id=EXCLUDED.section_id,
                      updated_at=now(), updated_by=v_actor;
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('marked',v_count));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;
