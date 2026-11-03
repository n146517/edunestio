-- =============================================================================
-- EduNestIO :: Module — Academic Setup (10_academic_setup.sql)
-- Adds academic years, terms, and subjects. Classes/sections already exist in
-- 01_schema.sql. Idempotent (CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE).
-- Apply after the base scripts (01..07). Safe to re-run.
-- =============================================================================

-- ---- Tables -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.academic_year (
    academic_year_id bigserial    PRIMARY KEY,
    tenant_id        integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name             varchar(60)  NOT NULL,          -- e.g. '2026-2027'
    start_date       date         NOT NULL,
    end_date         date         NOT NULL,
    is_current       boolean      NOT NULL DEFAULT false,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NULL,
    CONSTRAINT uq_ay_name UNIQUE (tenant_id, name),
    CONSTRAINT ck_ay_dates CHECK (end_date > start_date)
);
COMMENT ON TABLE academics.academic_year IS 'Academic year per tenant; one may be current.';

CREATE TABLE IF NOT EXISTS academics.term (
    term_id          bigserial    PRIMARY KEY,
    tenant_id        integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    academic_year_id bigint       NOT NULL REFERENCES academics.academic_year(academic_year_id) ON DELETE CASCADE,
    name             varchar(60)  NOT NULL,          -- e.g. 'Term 1'
    start_date       date         NULL,
    end_date         date         NULL,
    ordinal          integer      NOT NULL DEFAULT 1,
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NULL,
    CONSTRAINT uq_term_name UNIQUE (tenant_id, academic_year_id, name)
);

CREATE TABLE IF NOT EXISTS academics.subject (
    subject_id  bigserial    PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name        varchar(120) NOT NULL,
    code        varchar(30)  NOT NULL,
    is_active   boolean      NOT NULL DEFAULT true,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NULL,
    CONSTRAINT uq_subject_code UNIQUE (tenant_id, code)
);

-- ---- Indexes ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_ay_tenant      ON academics.academic_year (tenant_id, is_current);
CREATE INDEX IF NOT EXISTS ix_term_tenant_ay ON academics.term (tenant_id, academic_year_id, ordinal);
CREATE INDEX IF NOT EXISTS ix_subject_tenant ON academics.subject (tenant_id, is_active);

-- ---- Permissions (seed) -----------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('academic.view',   'Academic', 'View academic setup'),
 ('academic.manage', 'Academic', 'Manage academic years/terms/classes/sections/subjects')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal') AND p.code IN ('academic.view','academic.manage')
ON CONFLICT DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Teacher','ClassTeacher','AdmissionOfficer','Receptionist') AND p.code = 'academic.view'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Functions (jsonb in/out; envelope {result_code,message,data}; 0 = success)
-- =============================================================================

-- ---- Academic Year ----------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_academic_year_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'AcademicYearId','')::bigint; v_owner integer; v_current boolean := COALESCE((p_payload->>'IsCurrent')::boolean,false);
BEGIN
    IF COALESCE(p_payload->>'Name','')='' THEN
        RETURN jsonb_build_object('result_code',3,'message','Name is required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.academic_year (tenant_id,name,start_date,end_date,is_current)
        VALUES (p_tenant_id, p_payload->>'Name', (p_payload->>'StartDate')::date, (p_payload->>'EndDate')::date, v_current)
        RETURNING academic_year_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.academic_year WHERE academic_year_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.academic_year SET name=p_payload->>'Name', start_date=(p_payload->>'StartDate')::date,
               end_date=(p_payload->>'EndDate')::date, is_current=v_current, updated_at=now()
         WHERE academic_year_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    -- Only one current year per tenant.
    IF v_current THEN
        UPDATE academics.academic_year SET is_current=false WHERE tenant_id=p_tenant_id AND academic_year_id<>v_id AND is_current;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('academic_year_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','Academic year name already exists','data',NULL);
WHEN OTHERS THEN
    RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_academic_year_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_items jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.start_date DESC),'[]'::jsonb) INTO v_items
      FROM (SELECT academic_year_id,name,start_date,end_date,is_current FROM academics.academic_year WHERE tenant_id=p_tenant_id) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;

-- ---- Class ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_class_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'ClassId','')::bigint; v_owner integer;
BEGIN
    IF COALESCE(p_payload->>'Name','')='' THEN RETURN jsonb_build_object('result_code',3,'message','Name is required','data',NULL); END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.school_class (tenant_id,name,ordinal)
        VALUES (p_tenant_id, p_payload->>'Name', COALESCE((p_payload->>'Ordinal')::int,0))
        RETURNING class_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.school_class WHERE class_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.school_class SET name=p_payload->>'Name', ordinal=COALESCE((p_payload->>'Ordinal')::int,ordinal), updated_at=now()
         WHERE class_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('class_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','Class name already exists','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_class_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_items jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.ordinal, t.name),'[]'::jsonb) INTO v_items
      FROM (SELECT c.class_id, c.name, c.ordinal,
                   (SELECT count(*) FROM academics.class_section s WHERE s.class_id=c.class_id) AS section_count,
                   (SELECT count(*) FROM academics.student st WHERE st.class_id=c.class_id AND st.status='Active') AS student_count
              FROM academics.school_class c WHERE c.tenant_id=p_tenant_id) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;

-- ---- Section ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_section_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'SectionId','')::bigint; v_class bigint := (p_payload->>'ClassId')::bigint; v_owner integer; v_class_owner integer;
BEGIN
    IF COALESCE(p_payload->>'Name','')='' OR v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','Class and section name are required','data',NULL);
    END IF;
    SELECT tenant_id INTO v_class_owner FROM academics.school_class WHERE class_id=v_class;
    IF v_class_owner IS NULL OR v_class_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid class for tenant','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.class_section (tenant_id,class_id,name) VALUES (p_tenant_id,v_class,p_payload->>'Name')
        RETURNING section_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.class_section WHERE section_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.class_section SET name=p_payload->>'Name', class_id=v_class, updated_at=now()
         WHERE section_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('section_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','Section already exists for this class','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_section_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint; v_items jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.class_name, t.name),'[]'::jsonb) INTO v_items
      FROM (SELECT s.section_id, s.name, s.class_id, c.name AS class_name
              FROM academics.class_section s JOIN academics.school_class c ON c.class_id=s.class_id
             WHERE s.tenant_id=p_tenant_id AND (v_class IS NULL OR s.class_id=v_class)) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;

-- ---- Subject ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION academics.fn_subject_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'SubjectId','')::bigint; v_owner integer;
BEGIN
    IF COALESCE(p_payload->>'Name','')='' OR COALESCE(p_payload->>'Code','')='' THEN
        RETURN jsonb_build_object('result_code',3,'message','Name and code are required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO academics.subject (tenant_id,name,code,is_active)
        VALUES (p_tenant_id,p_payload->>'Name',p_payload->>'Code',COALESCE((p_payload->>'IsActive')::boolean,true))
        RETURNING subject_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.subject WHERE subject_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.subject SET name=p_payload->>'Name', code=p_payload->>'Code',
               is_active=COALESCE((p_payload->>'IsActive')::boolean,is_active), updated_at=now()
         WHERE subject_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('subject_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','Subject code already exists','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_subject_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_items jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.name),'[]'::jsonb) INTO v_items
      FROM (SELECT subject_id,name,code,is_active FROM academics.subject WHERE tenant_id=p_tenant_id) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;
