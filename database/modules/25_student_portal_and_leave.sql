-- =============================================================================
-- EduNestIO :: Module — Student self-service portal + Leave management
-- (25_student_portal_and_leave.sql)
-- 1) Links a login (core.app_user) to a student record (academics.student.user_id)
--    so the backend can resolve "which student is this logged-in user".
-- 2) Surfaces student_id through core.fn_authenticate / core.fn_validate_session.
-- 3) Adds a leave-request workflow (apply / cancel / list / decide) with its own
--    permissions, and grants Student/Guardian the self-service permissions.
-- Idempotent. Apply after modules 16 (students) and 24.
-- =============================================================================

-- ---- 1) Link column: student -> app_user ------------------------------------
ALTER TABLE academics.student ADD COLUMN IF NOT EXISTS user_id bigint NULL;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'student_user_id_fkey') THEN
        ALTER TABLE academics.student
            ADD CONSTRAINT student_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES core.app_user(user_id) ON DELETE SET NULL;
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS ix_student_user ON academics.student (tenant_id, user_id);

-- ---- 2) Permissions ---------------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('leave.apply',  'Leave', 'Apply for and cancel own leave requests'),
 ('leave.manage', 'Leave', 'Review, approve or reject leave requests'),
 ('portal.self',  'Portal','Access own student self-service portal')
ON CONFLICT (code) DO NOTHING;

-- Student + Guardian: self portal + apply leave + view own profile.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Student','Guardian')
   AND p.code IN ('portal.self','leave.apply','student.view')
ON CONFLICT DO NOTHING;

-- Admin / Principal / ClassTeacher: manage (approve/reject) leave.
INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal','ClassTeacher')
   AND p.code = 'leave.manage'
ON CONFLICT DO NOTHING;

-- ---- 3) Leave request table -------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.leave_request (
    leave_id      bigserial    PRIMARY KEY,
    tenant_id     integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    student_id    bigint       NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    from_date     date         NOT NULL,
    to_date       date         NOT NULL,
    leave_type    varchar(40)  NULL,          -- Sick | Casual | Other
    reason        varchar(500) NOT NULL,
    status        varchar(20)  NOT NULL DEFAULT 'Pending',  -- Pending|Approved|Rejected|Cancelled
    applied_by    bigint       NULL,           -- app_user who applied
    decided_by    bigint       NULL,           -- app_user who approved/rejected
    decided_at    timestamptz  NULL,
    decision_note varchar(500) NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NULL,
    CONSTRAINT ck_leave_status CHECK (status IN ('Pending','Approved','Rejected','Cancelled')),
    CONSTRAINT ck_leave_dates  CHECK (to_date >= from_date)
);
CREATE INDEX IF NOT EXISTS ix_leave_tenant_status ON academics.leave_request (tenant_id, status);
CREATE INDEX IF NOT EXISTS ix_leave_student       ON academics.leave_request (tenant_id, student_id, created_at DESC);

-- ---- 4) Leave functions -----------------------------------------------------

-- Apply. Payload: { student_id, from_date, to_date, leave_type?, reason, actor_user_id }
CREATE OR REPLACE FUNCTION academics.fn_leave_apply(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint;
        v_from date := NULLIF(p_payload->>'from_date','')::date;
        v_to   date := NULLIF(p_payload->>'to_date','')::date;
        v_reason text := NULLIF(p_payload->>'reason','');
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_owner integer; v_id bigint;
BEGIN
    IF v_sid IS NULL OR v_from IS NULL OR v_to IS NULL OR v_reason IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','student, dates and reason are required','data',NULL);
    END IF;
    IF v_to < v_from THEN
        RETURN jsonb_build_object('result_code',3,'message','To date cannot be before From date','data',NULL);
    END IF;
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Student not found','data',NULL);
    END IF;

    INSERT INTO academics.leave_request (tenant_id, student_id, from_date, to_date, leave_type, reason, status, applied_by)
    VALUES (p_tenant_id, v_sid, v_from, v_to, NULLIF(p_payload->>'leave_type',''), v_reason, 'Pending', v_actor)
    RETURNING leave_id INTO v_id;

    RETURN jsonb_build_object('result_code',0,'message','Leave applied','data',jsonb_build_object('leave_id',v_id));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- List a single student's leaves. Payload: { student_id }
CREATE OR REPLACE FUNCTION academics.fn_leave_mine(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_owner integer; v jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_sid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Student not found','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
        SELECT leave_id, student_id, from_date, to_date, leave_type, reason, status,
               decided_at, decision_note, created_at
          FROM academics.leave_request
         WHERE tenant_id=p_tenant_id AND student_id=v_sid) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Admin list with filters. Payload: { status?, class_id?, search? }
CREATE OR REPLACE FUNCTION academics.fn_leave_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_status text := NULLIF(p_payload->>'status','');
        v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_search text := lower(COALESCE(p_payload->>'search',''));
        v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v FROM (
        SELECT lr.leave_id, lr.student_id, s.admission_number, s.first_name, s.last_name,
               c.name AS class_name, sec.name AS section_name,
               lr.from_date, lr.to_date, lr.leave_type, lr.reason, lr.status,
               lr.decided_at, lr.decision_note, lr.created_at
          FROM academics.leave_request lr
          JOIN academics.student s ON s.student_id=lr.student_id
          LEFT JOIN academics.school_class  c   ON c.class_id=s.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=s.section_id
         WHERE lr.tenant_id=p_tenant_id
           AND (v_status IS NULL OR lr.status=v_status)
           AND (v_class  IS NULL OR s.class_id=v_class)
           AND (v_search='' OR lower(s.first_name) LIKE '%'||v_search||'%'
                            OR lower(s.last_name)  LIKE '%'||v_search||'%'
                            OR lower(s.admission_number) LIKE '%'||v_search||'%')
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Cancel own pending leave. Payload: { leave_id, student_id }
CREATE OR REPLACE FUNCTION academics.fn_leave_cancel(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'leave_id')::bigint;
        v_sid bigint := NULLIF(p_payload->>'student_id','')::bigint;
        v_owner integer; v_cur_student bigint; v_status text;
BEGIN
    SELECT tenant_id, student_id, status INTO v_owner, v_cur_student, v_status
      FROM academics.leave_request WHERE leave_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Leave not found','data',NULL);
    END IF;
    -- If a student_id is supplied (self-service), it must own the leave.
    IF v_sid IS NOT NULL AND v_cur_student <> v_sid THEN
        RETURN jsonb_build_object('result_code',6,'message','Not your leave request','data',NULL);
    END IF;
    IF v_status <> 'Pending' THEN
        RETURN jsonb_build_object('result_code',3,'message','Only pending leaves can be cancelled','data',NULL);
    END IF;
    UPDATE academics.leave_request SET status='Cancelled', updated_at=now() WHERE leave_id=v_id;
    RETURN jsonb_build_object('result_code',0,'message','Cancelled','data',jsonb_build_object('leave_id',v_id));
END; $$;

-- Approve/Reject. Payload: { leave_id, decision (Approved|Rejected), note?, actor_user_id }
CREATE OR REPLACE FUNCTION academics.fn_leave_decide(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'leave_id')::bigint;
        v_decision text := NULLIF(p_payload->>'decision','');
        v_note text := NULLIF(p_payload->>'note','');
        v_actor bigint := NULLIF(p_payload->>'actor_user_id','')::bigint;
        v_owner integer; v_status text; v_sid bigint; v_from date; v_to date;
BEGIN
    IF v_decision NOT IN ('Approved','Rejected') THEN
        RETURN jsonb_build_object('result_code',3,'message','Invalid decision','data',NULL);
    END IF;
    SELECT tenant_id, status, student_id, from_date, to_date
      INTO v_owner, v_status, v_sid, v_from, v_to
      FROM academics.leave_request WHERE leave_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Leave not found','data',NULL);
    END IF;
    IF v_status <> 'Pending' THEN
        RETURN jsonb_build_object('result_code',3,'message','Leave already '||v_status,'data',NULL);
    END IF;

    UPDATE academics.leave_request
       SET status=v_decision, decided_by=v_actor, decided_at=now(), decision_note=v_note, updated_at=now()
     WHERE leave_id=v_id;

    -- On approval, reflect the leave in attendance for each day in range (best effort).
    IF v_decision = 'Approved' THEN
        INSERT INTO academics.attendance (tenant_id, student_id, class_id, attend_date, status, remark, created_by)
        SELECT p_tenant_id, v_sid, s.class_id, d::date, 'Leave', 'Approved leave', v_actor
          FROM academics.student s, generate_series(v_from, v_to, interval '1 day') d
         WHERE s.student_id = v_sid
        ON CONFLICT (tenant_id, student_id, attend_date)
        DO UPDATE SET status='Leave', remark='Approved leave', updated_at=now(), updated_by=v_actor;
    END IF;

    RETURN jsonb_build_object('result_code',0,'message',v_decision,'data',jsonb_build_object('leave_id',v_id,'status',v_decision));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- ---- 5) Surface student_id in auth (REPLACE both functions) -----------------
CREATE OR REPLACE FUNCTION core.fn_authenticate(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_username text := p_payload->>'username';
    v_user     core.app_user%ROWTYPE;
    v_roles    jsonb;
    v_perms    jsonb;
    v_tenant_name text;
    v_student_id bigint;
BEGIN
    IF v_username IS NULL OR length(v_username) = 0 THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'username required', 'data', NULL);
    END IF;

    SELECT * INTO v_user
      FROM core.app_user u
     WHERE lower(u.username) = lower(v_username)
       AND (p_tenant_id = 0 OR u.tenant_id = p_tenant_id OR u.tenant_id IS NULL)
     ORDER BY u.tenant_id NULLS FIRST
     LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Not found', 'data', NULL);
    END IF;

    SELECT jsonb_agg(r.name) INTO v_roles
      FROM core.user_role ur JOIN core.role r ON r.role_id = ur.role_id
     WHERE ur.user_id = v_user.user_id;

    SELECT jsonb_agg(DISTINCT p.code) INTO v_perms
      FROM core.user_role ur
      JOIN core.role_permission rp ON rp.role_id = ur.role_id
      JOIN core.permission p ON p.permission_id = rp.permission_id
     WHERE ur.user_id = v_user.user_id;

    SELECT name INTO v_tenant_name FROM core.tenant WHERE tenant_id = v_user.tenant_id;

    -- The student this login represents (if any).
    SELECT student_id INTO v_student_id
      FROM academics.student WHERE user_id = v_user.user_id AND tenant_id = v_user.tenant_id LIMIT 1;

    RETURN jsonb_build_object(
        'result_code', 0, 'message', 'Success',
        'data', jsonb_build_object(
            'user_id', v_user.user_id,
            'tenant_id', v_user.tenant_id,
            'username', v_user.username,
            'email', v_user.email,
            'full_name', v_user.full_name,
            'password_hash', v_user.password_hash,
            'password_salt', v_user.password_salt,
            'is_active', v_user.is_active,
            'locked_until', v_user.locked_until,
            'tenant_name', v_tenant_name,
            'student_id', v_student_id,
            'roles', COALESCE(v_roles, '[]'::jsonb),
            'permissions', COALESCE(v_perms, '[]'::jsonb)
        ));
END;
$$;

CREATE OR REPLACE FUNCTION core.fn_validate_session(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_token text := p_payload->>'token';
    v_sess  core.user_session%ROWTYPE;
    v_user  core.app_user%ROWTYPE;
    v_roles jsonb;
    v_perms jsonb;
    v_student_id bigint;
BEGIN
    SELECT * INTO v_sess FROM core.user_session
     WHERE token = v_token AND revoked_at IS NULL AND expires_at > now();
    IF NOT FOUND THEN
        RETURN jsonb_build_object('result_code', 5, 'message', 'Invalid or expired token', 'data', NULL);
    END IF;

    SELECT * INTO v_user FROM core.app_user WHERE user_id = v_sess.user_id AND is_active = true;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('result_code', 5, 'message', 'User inactive', 'data', NULL);
    END IF;

    SELECT jsonb_agg(r.name) INTO v_roles
      FROM core.user_role ur JOIN core.role r ON r.role_id = ur.role_id WHERE ur.user_id = v_user.user_id;
    SELECT jsonb_agg(DISTINCT p.code) INTO v_perms
      FROM core.user_role ur
      JOIN core.role_permission rp ON rp.role_id = ur.role_id
      JOIN core.permission p ON p.permission_id = rp.permission_id
     WHERE ur.user_id = v_user.user_id;

    SELECT student_id INTO v_student_id
      FROM academics.student WHERE user_id = v_user.user_id AND tenant_id = v_user.tenant_id LIMIT 1;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object(
            'user_id', v_user.user_id,
            'tenant_id', v_user.tenant_id,
            'username', v_user.username,
            'email', v_user.email,
            'student_id', v_student_id,
            'roles', COALESCE(v_roles,'[]'::jsonb),
            'permissions', COALESCE(v_perms,'[]'::jsonb)
        ));
END;
$$;

-- ---- 6) Link the demo student user to Pramod (RVD-1014) ---------------------
-- Runs only if the demo user exists (created by the dev seeder on API startup).
UPDATE academics.student s
   SET user_id = u.user_id, updated_at = now()
  FROM core.app_user u
 WHERE u.username = 'riverdale.student' AND u.tenant_id = 1
   AND s.tenant_id = 1 AND s.admission_number = 'RVD-1014';
