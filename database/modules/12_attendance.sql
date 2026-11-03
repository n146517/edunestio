-- =============================================================================
-- EduNestIO :: Module — Attendance (12_attendance.sql)
-- Daily, class-wise student attendance. Statuses Present/Absent/Late/Leave.
-- Bulk marking (upsert), monthly register, per-student history, class summary.
-- Idempotent; apply after base + modules 10,11.
-- =============================================================================

CREATE TABLE IF NOT EXISTS academics.attendance (
    attendance_id bigserial   PRIMARY KEY,
    tenant_id     integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    student_id    bigint      NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    class_id      bigint      NULL REFERENCES academics.school_class(class_id) ON DELETE SET NULL,
    attend_date   date        NOT NULL,
    status        varchar(10) NOT NULL DEFAULT 'Present',   -- Present|Absent|Late|Leave
    remark        varchar(300) NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NULL,
    created_by    bigint      NULL,
    updated_by    bigint      NULL,
    -- One record per student per day (tenant-scoped) -> enables upsert.
    CONSTRAINT uq_attendance UNIQUE (tenant_id, student_id, attend_date),
    CONSTRAINT ck_attendance_status CHECK (status IN ('Present','Absent','Late','Leave'))
);
COMMENT ON TABLE academics.attendance IS 'Per-student daily attendance, tenant-owned.';

CREATE INDEX IF NOT EXISTS ix_attendance_tenant_date  ON academics.attendance (tenant_id, attend_date);
CREATE INDEX IF NOT EXISTS ix_attendance_student      ON academics.attendance (tenant_id, student_id, attend_date DESC);
CREATE INDEX IF NOT EXISTS ix_attendance_class_date   ON academics.attendance (tenant_id, class_id, attend_date);

-- Permissions
INSERT INTO core.permission (code, module, description) VALUES
 ('attendance.view', 'Attendance', 'View attendance registers and history'),
 ('attendance.mark', 'Attendance', 'Mark/correct attendance')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal','ClassTeacher','Teacher')
   AND p.code IN ('attendance.view','attendance.mark')
ON CONFLICT DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Accountant','Receptionist') AND p.code = 'attendance.view'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Functions
-- =============================================================================

-- Returns the class roster for a date with each student's existing status (if any).
-- Payload: { class_id, attend_date }
CREATE OR REPLACE FUNCTION academics.fn_attendance_sheet(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint; v_date date := (p_payload->>'attend_date')::date; v_items jsonb;
BEGIN
    IF v_class IS NULL OR v_date IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class_id and attend_date are required','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.last_name, t.first_name),'[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.admission_number, s.first_name, s.last_name,
               COALESCE(a.status,'Present') AS status, a.remark,
               (a.attendance_id IS NOT NULL) AS marked
          FROM academics.student s
          LEFT JOIN academics.attendance a
            ON a.student_id=s.student_id AND a.tenant_id=p_tenant_id AND a.attend_date=v_date
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('class_id',v_class,'attend_date',v_date,'items',v_items));
END; $$;

-- Bulk upsert attendance for a class+date. Payload:
-- { class_id, attend_date, actor_user_id, entries:[{student_id,status,remark}] }
CREATE OR REPLACE FUNCTION academics.fn_attendance_mark(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint; v_date date := (p_payload->>'attend_date')::date;
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint; v_entry jsonb; v_sid bigint; v_count int := 0; v_owner integer;
BEGIN
    IF v_date IS NULL THEN RETURN jsonb_build_object('result_code',3,'message','attend_date is required','data',NULL); END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'entries','[]'::jsonb))
    LOOP
        v_sid := (v_entry->>'student_id')::bigint;
        -- Verify the student belongs to this tenant (never trust client ids).
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;

        INSERT INTO academics.attendance (tenant_id, student_id, class_id, attend_date, status, remark, created_by)
        VALUES (p_tenant_id, v_sid, v_class, v_date,
                COALESCE(NULLIF(v_entry->>'status',''),'Present'), NULLIF(v_entry->>'remark',''), v_actor)
        ON CONFLICT (tenant_id, student_id, attend_date)
        DO UPDATE SET status=EXCLUDED.status, remark=EXCLUDED.remark, class_id=EXCLUDED.class_id,
                      updated_at=now(), updated_by=v_actor;
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('marked',v_count));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Monthly register for a class. Payload: { class_id, year, month }
-- Returns per-student daily status map + totals.
CREATE OR REPLACE FUNCTION academics.fn_attendance_register(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint; v_year int := (p_payload->>'year')::int; v_month int := (p_payload->>'month')::int;
        v_start date; v_end date; v_items jsonb;
BEGIN
    IF v_class IS NULL OR v_year IS NULL OR v_month IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class_id, year and month are required','data',NULL);
    END IF;
    v_start := make_date(v_year, v_month, 1);
    v_end := (v_start + interval '1 month')::date;

    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.last_name, t.first_name),'[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.admission_number, s.first_name, s.last_name,
               COALESCE((SELECT jsonb_object_agg(extract(day from a.attend_date)::text, a.status)
                           FROM academics.attendance a
                          WHERE a.tenant_id=p_tenant_id AND a.student_id=s.student_id
                            AND a.attend_date >= v_start AND a.attend_date < v_end), '{}'::jsonb) AS days,
               (SELECT count(*) FROM academics.attendance a WHERE a.tenant_id=p_tenant_id AND a.student_id=s.student_id
                  AND a.attend_date>=v_start AND a.attend_date<v_end AND a.status='Present') AS present_count,
               (SELECT count(*) FROM academics.attendance a WHERE a.tenant_id=p_tenant_id AND a.student_id=s.student_id
                  AND a.attend_date>=v_start AND a.attend_date<v_end AND a.status='Absent') AS absent_count
          FROM academics.student s
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
    ) t;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('class_id',v_class,'year',v_year,'month',v_month,'items',v_items));
END; $$;

-- Per-student history (most recent first). Payload: { student_id, limit }
CREATE OR REPLACE FUNCTION academics.fn_attendance_history(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_limit int := LEAST(COALESCE((p_payload->>'limit')::int,60),365);
        v_owner integer; v_items jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Student not found','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.attend_date DESC),'[]'::jsonb) INTO v_items
      FROM (SELECT attend_date, status, remark FROM academics.attendance
             WHERE tenant_id=p_tenant_id AND student_id=v_sid ORDER BY attend_date DESC LIMIT v_limit) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;

-- Today's summary for dashboards. Payload: { attend_date? } (defaults today)
CREATE OR REPLACE FUNCTION academics.fn_attendance_today_summary(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_date date := COALESCE(NULLIF(p_payload->>'attend_date','')::date, current_date); v jsonb; v_active bigint;
BEGIN
    SELECT count(*) INTO v_active FROM academics.student WHERE tenant_id=p_tenant_id AND status='Active';
    SELECT COALESCE(jsonb_object_agg(status,cnt),'{}'::jsonb) INTO v
      FROM (SELECT status, count(*) cnt FROM academics.attendance
             WHERE tenant_id=p_tenant_id AND attend_date=v_date GROUP BY status) s;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('attend_date',v_date,'active_students',v_active,'by_status',v));
END; $$;
