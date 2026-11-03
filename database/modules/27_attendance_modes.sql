-- =============================================================================
-- EduNestIO :: Module — Attendance modes (Daily vs Subject-wise) + section
-- (27_attendance_modes.sql)
-- Each school chooses how it takes attendance:
--   * 'Daily'   — one record per student per day (period column unused)
--   * 'Subject' — one record per student per subject per day (period-wise)
-- Adds section + subject columns to attendance, a per-tenant attendance_mode,
-- and tenant-settings get/set functions. Backward-compatible + idempotent.
-- Apply after modules 12 (attendance) and 10 (academic setup).
-- =============================================================================

-- ---- 1) Per-school attendance mode on the tenant ----------------------------
ALTER TABLE core.tenant ADD COLUMN IF NOT EXISTS attendance_mode varchar(20) NOT NULL DEFAULT 'Daily';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tenant_attendance_mode') THEN
        ALTER TABLE core.tenant
            ADD CONSTRAINT ck_tenant_attendance_mode CHECK (attendance_mode IN ('Daily','Subject'));
    END IF;
END $$;

-- ---- 2) Section + subject on attendance -------------------------------------
ALTER TABLE academics.attendance ADD COLUMN IF NOT EXISTS section_id bigint NULL REFERENCES academics.class_section(section_id) ON DELETE SET NULL;
ALTER TABLE academics.attendance ADD COLUMN IF NOT EXISTS subject_id bigint NULL REFERENCES academics.subject(subject_id) ON DELETE SET NULL;

-- Replace the day-unique constraint with one that includes the subject, so a
-- student can have ONE row per day in Daily mode (subject_id NULL) and one row
-- per subject per day in Subject mode. COALESCE keeps NULL-subject rows unique.
ALTER TABLE academics.attendance DROP CONSTRAINT IF EXISTS uq_attendance;
DROP INDEX IF EXISTS academics.uq_attendance_day_subject;
CREATE UNIQUE INDEX uq_attendance_day_subject
    ON academics.attendance (tenant_id, student_id, attend_date, COALESCE(subject_id, 0));

CREATE INDEX IF NOT EXISTS ix_attendance_section ON academics.attendance (tenant_id, section_id, attend_date);

-- ---- 3) Settings permissions ------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('settings.view',   'Settings', 'View school settings'),
 ('settings.manage', 'Settings', 'Change school settings')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code IN ('settings.view','settings.manage')
ON CONFLICT DO NOTHING;

-- ---- 4) Tenant-settings get / set -------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_tenant_settings_get(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    SELECT jsonb_build_object(
             'tenant_id', t.tenant_id,
             'name', t.name,
             'code', t.code,
             'attendance_mode', t.attendance_mode,
             'locale', t.locale,
             'time_zone', t.time_zone,
             'currency_code', t.currency_code)
      INTO v FROM core.tenant t WHERE t.tenant_id = p_tenant_id;
    IF v IS NULL THEN
        RETURN jsonb_build_object('result_code',4,'message','Tenant not found','data',NULL);
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',v);
END; $$;

CREATE OR REPLACE FUNCTION core.fn_tenant_settings_set(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_mode text := NULLIF(p_payload->>'attendance_mode','');
BEGIN
    IF v_mode IS NOT NULL AND v_mode NOT IN ('Daily','Subject') THEN
        RETURN jsonb_build_object('result_code',3,'message','Invalid attendance mode','data',NULL);
    END IF;
    UPDATE core.tenant
       SET attendance_mode = COALESCE(v_mode, attendance_mode), updated_at = now()
     WHERE tenant_id = p_tenant_id;
    RETURN jsonb_build_object('result_code',0,'message','Settings updated',
        'data', jsonb_build_object('attendance_mode', COALESCE(v_mode, (SELECT attendance_mode FROM core.tenant WHERE tenant_id=p_tenant_id))));
END; $$;

-- ---- 5) Attendance sheet (REPLACE): optional section + subject filter --------
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
               COALESCE(a.status,'Present') AS status, a.remark,
               (a.attendance_id IS NOT NULL) AS marked
          FROM academics.student s
          LEFT JOIN academics.attendance a
            ON a.student_id=s.student_id AND a.tenant_id=p_tenant_id AND a.attend_date=v_date
               AND a.subject_id IS NOT DISTINCT FROM v_subject
         WHERE s.tenant_id=p_tenant_id AND s.class_id=v_class AND s.status='Active'
           AND (v_section IS NULL OR s.section_id=v_section)
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('class_id',v_class,'section_id',v_section,'subject_id',v_subject,
                                  'attend_date',v_date,'items',v_items));
END; $$;

-- ---- 6) Attendance mark (REPLACE): persist section + subject -----------------
-- Payload: { class_id, section_id?, subject_id?, attend_date, actor_user_id,
--            entries:[{student_id,status,remark}] }
CREATE OR REPLACE FUNCTION academics.fn_attendance_mark(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := (p_payload->>'class_id')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_subject bigint := NULLIF(p_payload->>'subject_id','')::bigint;
        v_date date := (p_payload->>'attend_date')::date;
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_entry jsonb; v_sid bigint; v_count int := 0; v_owner integer;
BEGIN
    IF v_date IS NULL THEN RETURN jsonb_build_object('result_code',3,'message','attend_date is required','data',NULL); END IF;

    FOR v_entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload->'entries','[]'::jsonb))
    LOOP
        v_sid := (v_entry->>'student_id')::bigint;
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
        IF v_owner IS DISTINCT FROM p_tenant_id THEN CONTINUE; END IF;

        INSERT INTO academics.attendance (tenant_id, student_id, class_id, section_id, subject_id, attend_date, status, remark, created_by)
        VALUES (p_tenant_id, v_sid, v_class, v_section, v_subject, v_date,
                COALESCE(NULLIF(v_entry->>'status',''),'Present'), NULLIF(v_entry->>'remark',''), v_actor)
        ON CONFLICT (tenant_id, student_id, attend_date, COALESCE(subject_id, 0))
        DO UPDATE SET status=EXCLUDED.status, remark=EXCLUDED.remark,
                      class_id=EXCLUDED.class_id, section_id=EXCLUDED.section_id,
                      updated_at=now(), updated_by=v_actor;
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('marked',v_count));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;
