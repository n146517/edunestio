-- =============================================================================
-- EduNestIO :: 03_functions.sql
-- Business functions. Convention:
--   * Tenant-scoped functions: fn(p_tenant_id integer, p_payload jsonb) RETURNS jsonb
--   * Return envelope: { "result_code": <int>, "message": <text>, "data": <json> }
--     result_code 0 = success (matches Common.ResultCodes.SUCCESS).
-- All functions validate tenant scope and raise no secrets. Errors are caught and
-- returned as an envelope with a non-zero result_code.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- core.fn_next_document_number
-- Purpose : Race-safe, tenant-scoped sequence allocation (e.g. admission numbers).
-- Inputs  : p_tenant_id, p_payload { "seq_key": text }
-- Returns : { result_code, message, data: { "number": "<prefix><padded>" } }
-- Edge    : creates the sequence row on first use (default prefix '', padding 4).
-- Sample  : select core.fn_next_document_number(1, '{"seq_key":"admission_number"}');
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_next_document_number(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_key     text := p_payload->>'seq_key';
    v_prefix  text;
    v_padding integer;
    v_value   bigint;
    v_number  text;
BEGIN
    IF v_key IS NULL OR length(v_key) = 0 THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'seq_key required', 'data', NULL);
    END IF;

    INSERT INTO core.number_sequence (tenant_id, seq_key)
    VALUES (p_tenant_id, v_key)
    ON CONFLICT (tenant_id, seq_key) DO NOTHING;

    -- Atomic increment under row lock -> race-safe across concurrent callers.
    UPDATE core.number_sequence
       SET next_value = next_value + 1
     WHERE tenant_id = p_tenant_id AND seq_key = v_key
     RETURNING next_value - 1, prefix, padding INTO v_value, v_prefix, v_padding;

    v_number := v_prefix || lpad(v_value::text, v_padding, '0');
    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
                              'data', jsonb_build_object('number', v_number));
END;
$$;

-- -----------------------------------------------------------------------------
-- core.fn_authenticate
-- Purpose : Validate credentials and (on success) return the user's security
--           context. Password verification is done in the application layer
--           (PBKDF2); this function returns the stored hash/salt + profile so the
--           app can verify, then calls core.fn_create_session to mint a token.
-- Inputs  : p_tenant_id (0 = resolve across platform for super admin / by username),
--           p_payload { "username": text }
-- Returns : { result_code, data: { user_id, tenant_id, username, email, full_name,
--             password_hash, password_salt, is_active, locked_until, roles[],
--             permissions[], tenant_name } }
-- NOTE    : Returns hash/salt ONLY to the trusted server process over the DB
--           channel; never exposed to clients. Generic not-found to avoid
--           enumeration is enforced in the app layer.
-- Sample  : select core.fn_authenticate(0, '{"username":"superadmin"}');
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_authenticate(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_username text := p_payload->>'username';
    v_user     core.app_user%ROWTYPE;
    v_roles    jsonb;
    v_perms    jsonb;
    v_tenant_name text;
BEGIN
    IF v_username IS NULL OR length(v_username) = 0 THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'username required', 'data', NULL);
    END IF;

    -- Platform super admins have tenant_id NULL; tenant users match their tenant.
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
            'roles', COALESCE(v_roles, '[]'::jsonb),
            'permissions', COALESCE(v_perms, '[]'::jsonb)
        ));
END;
$$;

-- -----------------------------------------------------------------------------
-- core.fn_create_session  : mint an opaque bearer token with expiry.
-- Inputs : p_tenant_id, p_payload { user_id, token, minutes }
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_create_session(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id bigint := (p_payload->>'user_id')::bigint;
    v_token   text   := p_payload->>'token';
    v_minutes integer := COALESCE((p_payload->>'minutes')::integer, 480);
    v_expires timestamptz := now() + make_interval(mins => v_minutes);
BEGIN
    INSERT INTO core.user_session (user_id, tenant_id, token, expires_at)
    VALUES (v_user_id, NULLIF(p_tenant_id, 0), v_token, v_expires);

    UPDATE core.app_user SET last_login_at = now(), failed_attempts = 0 WHERE user_id = v_user_id;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object('expires_at', v_expires));
END;
$$;

-- -----------------------------------------------------------------------------
-- core.fn_validate_session : resolve a token to its security context.
-- Inputs : p_tenant_id (ignored/0), p_payload { token }
-- Returns: data { user_id, tenant_id, username, email, roles[], permissions[] } or not found.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_validate_session(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_token text := p_payload->>'token';
    v_sess  core.user_session%ROWTYPE;
    v_user  core.app_user%ROWTYPE;
    v_roles jsonb;
    v_perms jsonb;
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

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object(
            'user_id', v_user.user_id,
            'tenant_id', v_user.tenant_id,
            'username', v_user.username,
            'email', v_user.email,
            'roles', COALESCE(v_roles,'[]'::jsonb),
            'permissions', COALESCE(v_perms,'[]'::jsonb)
        ));
END;
$$;

-- -----------------------------------------------------------------------------
-- academics.fn_student_save : create or update a student (tenant-scoped).
-- Inputs : p_tenant_id, p_payload (StudentVO fields; student_id null => create)
-- Returns: data { student_id }
-- Edge   : auto-generates admission_number if blank on create; enforces tenant
--          uniqueness; verifies an updated row belongs to the tenant.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_student_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id    bigint := NULLIF(p_payload->>'StudentId','')::bigint;
    v_adm   text   := NULLIF(p_payload->>'AdmissionNumber','');
    v_owner integer;
    v_numenv jsonb;
BEGIN
    IF COALESCE(p_payload->>'FirstName','') = '' OR COALESCE(p_payload->>'LastName','') = '' THEN
        RETURN jsonb_build_object('result_code', 3, 'message', 'First and last name are required', 'data', NULL);
    END IF;

    IF v_id IS NULL THEN
        -- CREATE
        IF v_adm IS NULL THEN
            v_numenv := core.fn_next_document_number(p_tenant_id, '{"seq_key":"admission_number"}');
            v_adm := v_numenv->'data'->>'number';
        END IF;

        IF EXISTS (SELECT 1 FROM academics.student WHERE tenant_id = p_tenant_id AND admission_number = v_adm) THEN
            RETURN jsonb_build_object('result_code', 7, 'message', 'Admission number already exists', 'data', NULL);
        END IF;

        INSERT INTO academics.student (
            tenant_id, admission_number, first_name, middle_name, last_name, gender,
            date_of_birth, email, phone, address_line1, address_line2, city, state,
            postal_code, class_id, section_id, status, created_by)
        VALUES (
            p_tenant_id, v_adm,
            p_payload->>'FirstName', NULLIF(p_payload->>'MiddleName',''), p_payload->>'LastName',
            NULLIF(p_payload->>'Gender',''),
            NULLIF(p_payload->>'DateOfBirth','')::date,
            NULLIF(p_payload->>'Email',''), NULLIF(p_payload->>'Phone',''),
            NULLIF(p_payload->>'AddressLine1',''), NULLIF(p_payload->>'AddressLine2',''),
            NULLIF(p_payload->>'City',''), NULLIF(p_payload->>'State',''),
            NULLIF(p_payload->>'PostalCode',''),
            NULLIF(p_payload->>'ClassId','')::bigint, NULLIF(p_payload->>'SectionId','')::bigint,
            COALESCE(NULLIF(p_payload->>'Status',''),'Active'),
            NULLIF(p_payload->>'ActorUserId','')::bigint)
        RETURNING student_id INTO v_id;

        RETURN jsonb_build_object('result_code', 0, 'message', 'Created',
            'data', jsonb_build_object('student_id', v_id, 'admission_number', v_adm));
    ELSE
        -- UPDATE (verify tenant ownership first -> no cross-tenant writes)
        SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id = v_id;
        IF v_owner IS NULL THEN
            RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
        END IF;
        IF v_owner <> p_tenant_id THEN
            RETURN jsonb_build_object('result_code', 8, 'message', 'Tenant access violation', 'data', NULL);
        END IF;

        UPDATE academics.student SET
            first_name    = p_payload->>'FirstName',
            middle_name   = NULLIF(p_payload->>'MiddleName',''),
            last_name     = p_payload->>'LastName',
            gender        = NULLIF(p_payload->>'Gender',''),
            date_of_birth = NULLIF(p_payload->>'DateOfBirth','')::date,
            email         = NULLIF(p_payload->>'Email',''),
            phone         = NULLIF(p_payload->>'Phone',''),
            address_line1 = NULLIF(p_payload->>'AddressLine1',''),
            address_line2 = NULLIF(p_payload->>'AddressLine2',''),
            city          = NULLIF(p_payload->>'City',''),
            state         = NULLIF(p_payload->>'State',''),
            postal_code   = NULLIF(p_payload->>'PostalCode',''),
            class_id      = NULLIF(p_payload->>'ClassId','')::bigint,
            section_id    = NULLIF(p_payload->>'SectionId','')::bigint,
            status        = COALESCE(NULLIF(p_payload->>'Status',''), status),
            updated_at    = now(),
            updated_by    = NULLIF(p_payload->>'ActorUserId','')::bigint
        WHERE student_id = v_id AND tenant_id = p_tenant_id;

        RETURN jsonb_build_object('result_code', 0, 'message', 'Updated',
            'data', jsonb_build_object('student_id', v_id));
    END IF;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('result_code', 1, 'message', SQLERRM, 'data', NULL);
END;
$$;

-- -----------------------------------------------------------------------------
-- academics.fn_student_get : fetch one student, scoped to tenant.
-- Inputs : p_tenant_id, p_payload { student_id }
-- Returns: data = student row (snake_case) joined with class name, or NOT_FOUND.
--          A guessed id from another tenant returns NOT_FOUND (no existence leak).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_student_get(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id   bigint := (p_payload->>'student_id')::bigint;
    v_data jsonb;
BEGIN
    SELECT to_jsonb(s) || jsonb_build_object('class_name', c.name) INTO v_data
      FROM academics.student s
      LEFT JOIN academics.school_class c ON c.class_id = s.class_id
     WHERE s.student_id = v_id AND s.tenant_id = p_tenant_id;

    IF v_data IS NULL THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
    END IF;
    RETURN jsonb_build_object('result_code', 0, 'message', 'Success', 'data', v_data);
END;
$$;

-- -----------------------------------------------------------------------------
-- academics.fn_student_list : paginated, filtered, tenant-scoped list.
-- Inputs : p_tenant_id, p_payload { search, class_id, status, page, page_size, sort_by, sort_dir }
-- Returns: data { items[], page, page_size, total_count }
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_student_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_search   text    := lower(COALESCE(p_payload->>'search',''));
    v_class    bigint  := NULLIF(p_payload->>'class_id','')::bigint;
    v_status   text    := NULLIF(p_payload->>'status','');
    v_page     integer := GREATEST(COALESCE((p_payload->>'page')::integer,1),1);
    v_size     integer := LEAST(GREATEST(COALESCE((p_payload->>'page_size')::integer,20),1),100);
    v_offset   integer := (v_page - 1) * v_size;
    v_total    bigint;
    v_items    jsonb;
BEGIN
    SELECT count(*) INTO v_total
      FROM academics.student s
     WHERE s.tenant_id = p_tenant_id
       AND (v_class IS NULL OR s.class_id = v_class)
       AND (v_status IS NULL OR s.status = v_status)
       AND (v_search = '' OR lower(s.first_name) LIKE '%'||v_search||'%'
                          OR lower(s.last_name)  LIKE '%'||v_search||'%'
                          OR lower(s.admission_number) LIKE '%'||v_search||'%');

    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_items FROM (
        SELECT s.student_id, s.tenant_id, s.admission_number, s.first_name, s.middle_name,
               s.last_name, s.gender, s.date_of_birth, s.email, s.phone, s.city,
               s.class_id, c.name AS class_name, s.section_id, s.status, s.created_at
          FROM academics.student s
          LEFT JOIN academics.school_class c ON c.class_id = s.class_id
         WHERE s.tenant_id = p_tenant_id
           AND (v_class IS NULL OR s.class_id = v_class)
           AND (v_status IS NULL OR s.status = v_status)
           AND (v_search = '' OR lower(s.first_name) LIKE '%'||v_search||'%'
                              OR lower(s.last_name)  LIKE '%'||v_search||'%'
                              OR lower(s.admission_number) LIKE '%'||v_search||'%')
         ORDER BY s.created_at DESC
         LIMIT v_size OFFSET v_offset
    ) t;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object('items', v_items, 'page', v_page,
                                   'page_size', v_size, 'total_count', v_total));
END;
$$;

-- -----------------------------------------------------------------------------
-- academics.fn_student_delete : soft-delete (status=Inactive), tenant-scoped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_student_delete(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id bigint := (p_payload->>'student_id')::bigint;
    v_rows integer;
BEGIN
    UPDATE academics.student
       SET status = 'Inactive', updated_at = now(),
           updated_by = NULLIF(p_payload->>'ActorUserId','')::bigint
     WHERE student_id = v_id AND tenant_id = p_tenant_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RETURN jsonb_build_object('result_code', 4, 'message', 'Student not found', 'data', NULL);
    END IF;
    RETURN jsonb_build_object('result_code', 0, 'message', 'Deactivated',
        'data', jsonb_build_object('student_id', v_id));
END;
$$;

-- -----------------------------------------------------------------------------
-- core.fn_write_audit : append an audit record.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_write_audit(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO core.audit_log (tenant_id, actor_user_id, action, entity, entity_id, correlation_id, changes)
    VALUES (NULLIF(p_tenant_id,0),
            NULLIF(p_payload->>'actor_user_id','')::bigint,
            p_payload->>'action', p_payload->>'entity', p_payload->>'entity_id',
            p_payload->>'correlation_id', p_payload->'changes');
    RETURN jsonb_build_object('result_code', 0, 'message', 'Success', 'data', NULL);
END;
$$;

-- -----------------------------------------------------------------------------
-- core.fn_upsert_user : idempotent user creation for dev seeding.
-- Inputs : p_tenant_id (0 -> NULL tenant for platform admin),
--          p_payload { username, email, full_name, password_hash, password_salt, roles[] }
-- Returns: data { user_id, created:boolean }
-- Idempotent: if the (tenant, username) exists, returns it without changing the
-- password. Role names in roles[] are mapped to core.role and assigned.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fn_upsert_user(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_tenant   integer := NULLIF(p_tenant_id, 0);
    v_username text := p_payload->>'username';
    v_user_id  bigint;
    v_created  boolean := false;
    v_role     text;
BEGIN
    SELECT user_id INTO v_user_id
      FROM core.app_user
     WHERE lower(username) = lower(v_username)
       AND tenant_id IS NOT DISTINCT FROM v_tenant;

    IF v_user_id IS NULL THEN
        INSERT INTO core.app_user (tenant_id, username, email, full_name, password_hash, password_salt, is_active)
        VALUES (v_tenant, v_username, NULLIF(p_payload->>'email',''), NULLIF(p_payload->>'full_name',''),
                p_payload->>'password_hash', p_payload->>'password_salt', true)
        RETURNING user_id INTO v_user_id;
        v_created := true;
    END IF;

    -- (Re)assign roles
    FOR v_role IN SELECT jsonb_array_elements_text(COALESCE(p_payload->'roles','[]'::jsonb))
    LOOP
        INSERT INTO core.user_role (user_id, role_id)
        SELECT v_user_id, r.role_id FROM core.role r WHERE r.name = v_role
        ON CONFLICT DO NOTHING;
    END LOOP;

    RETURN jsonb_build_object('result_code', 0, 'message', 'Success',
        'data', jsonb_build_object('user_id', v_user_id, 'created', v_created));
END;
$$;
