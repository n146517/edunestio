-- =============================================================================
-- EduNestIO :: Module — Admissions & Enquiry CRM (11_admissions.sql)
-- Enquiries, follow-ups, and conversion of an accepted enquiry into a Student
-- (reusing academics.fn_student_save). Idempotent; apply after base + module 10.
-- =============================================================================

CREATE TABLE IF NOT EXISTS academics.enquiry (
    enquiry_id     bigserial    PRIMARY KEY,
    tenant_id      integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    enquiry_number varchar(50)  NOT NULL,
    applicant_name varchar(200) NOT NULL,
    guardian_name  varchar(200) NULL,
    phone          varchar(40)  NULL,
    email          varchar(256) NULL,
    source         varchar(60)  NULL,              -- Walk-in|Phone|Website|Referral|Other
    desired_class_id bigint     NULL REFERENCES academics.school_class(class_id) ON DELETE SET NULL,
    stage          varchar(30)  NOT NULL DEFAULT 'New', -- New|Contacted|Application|Accepted|Admitted|Rejected|Lost
    notes          varchar(1000) NULL,
    next_followup_at date       NULL,
    converted_student_id bigint NULL REFERENCES academics.student(student_id) ON DELETE SET NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NULL,
    created_by     bigint       NULL,
    updated_by     bigint       NULL,
    CONSTRAINT uq_enquiry_number UNIQUE (tenant_id, enquiry_number),
    CONSTRAINT ck_enquiry_stage CHECK (stage IN ('New','Contacted','Application','Accepted','Admitted','Rejected','Lost'))
);
COMMENT ON TABLE academics.enquiry IS 'Admission enquiry/lead, tenant-owned; converts to a student.';

CREATE TABLE IF NOT EXISTS academics.enquiry_followup (
    followup_id bigserial   PRIMARY KEY,
    tenant_id   integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    enquiry_id  bigint      NOT NULL REFERENCES academics.enquiry(enquiry_id) ON DELETE CASCADE,
    note        varchar(1000) NOT NULL,
    outcome     varchar(60) NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    created_by  bigint      NULL
);

CREATE INDEX IF NOT EXISTS ix_enquiry_tenant       ON academics.enquiry (tenant_id, stage, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_enquiry_followup_enq ON academics.enquiry_followup (tenant_id, enquiry_id, created_at DESC);

-- Numbering sequence default for enquiries (per tenant). Seed a sane default for demo tenants.
INSERT INTO core.number_sequence (tenant_id, seq_key, prefix, next_value, padding)
SELECT t.tenant_id, 'enquiry_number', 'ENQ-', 1, 4 FROM core.tenant t
ON CONFLICT (tenant_id, seq_key) DO NOTHING;

-- Permissions
INSERT INTO core.permission (code, module, description) VALUES
 ('admission.view',    'Admissions', 'View enquiries/admissions'),
 ('admission.manage',  'Admissions', 'Create/update enquiries and follow-ups'),
 ('admission.convert', 'Admissions', 'Convert an accepted enquiry into a student')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal','AdmissionOfficer')
   AND p.code IN ('admission.view','admission.manage','admission.convert')
ON CONFLICT DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name = 'Receptionist' AND p.code IN ('admission.view','admission.manage')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Functions
-- =============================================================================

-- Create/update an enquiry (auto-generates enquiry_number on create).
CREATE OR REPLACE FUNCTION academics.fn_enquiry_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'EnquiryId','')::bigint; v_owner integer; v_num text; v_numenv jsonb;
BEGIN
    IF COALESCE(p_payload->>'ApplicantName','')='' THEN
        RETURN jsonb_build_object('result_code',3,'message','Applicant name is required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        v_numenv := core.fn_next_document_number(p_tenant_id, '{"seq_key":"enquiry_number"}');
        v_num := v_numenv->'data'->>'number';
        INSERT INTO academics.enquiry (tenant_id, enquiry_number, applicant_name, guardian_name, phone, email,
                    source, desired_class_id, stage, notes, next_followup_at, created_by)
        VALUES (p_tenant_id, v_num, p_payload->>'ApplicantName', NULLIF(p_payload->>'GuardianName',''),
                NULLIF(p_payload->>'Phone',''), NULLIF(p_payload->>'Email',''), NULLIF(p_payload->>'Source',''),
                NULLIF(p_payload->>'DesiredClassId','')::bigint, COALESCE(NULLIF(p_payload->>'Stage',''),'New'),
                NULLIF(p_payload->>'Notes',''), NULLIF(p_payload->>'NextFollowupAt','')::date,
                NULLIF(p_payload->>'ActorUserId','')::bigint)
        RETURNING enquiry_id INTO v_id;
        RETURN jsonb_build_object('result_code',0,'message','Created','data',jsonb_build_object('enquiry_id',v_id,'enquiry_number',v_num));
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.enquiry WHERE enquiry_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Enquiry not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.enquiry SET
            applicant_name=p_payload->>'ApplicantName', guardian_name=NULLIF(p_payload->>'GuardianName',''),
            phone=NULLIF(p_payload->>'Phone',''), email=NULLIF(p_payload->>'Email',''),
            source=NULLIF(p_payload->>'Source',''), desired_class_id=NULLIF(p_payload->>'DesiredClassId','')::bigint,
            stage=COALESCE(NULLIF(p_payload->>'Stage',''),stage), notes=NULLIF(p_payload->>'Notes',''),
            next_followup_at=NULLIF(p_payload->>'NextFollowupAt','')::date, updated_at=now(),
            updated_by=NULLIF(p_payload->>'ActorUserId','')::bigint
         WHERE enquiry_id=v_id AND tenant_id=p_tenant_id;
        RETURN jsonb_build_object('result_code',0,'message','Updated','data',jsonb_build_object('enquiry_id',v_id));
    END IF;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Paginated/filtered enquiry list.
CREATE OR REPLACE FUNCTION academics.fn_enquiry_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_search text := lower(COALESCE(p_payload->>'search','')); v_stage text := NULLIF(p_payload->>'stage','');
        v_page int := GREATEST(COALESCE((p_payload->>'page')::int,1),1);
        v_size int := LEAST(GREATEST(COALESCE((p_payload->>'page_size')::int,20),1),100);
        v_total bigint; v_items jsonb;
BEGIN
    SELECT count(*) INTO v_total FROM academics.enquiry e
     WHERE e.tenant_id=p_tenant_id AND (v_stage IS NULL OR e.stage=v_stage)
       AND (v_search='' OR lower(e.applicant_name) LIKE '%'||v_search||'%' OR lower(e.enquiry_number) LIKE '%'||v_search||'%');

    SELECT COALESCE(jsonb_agg(row_to_json(t)),'[]'::jsonb) INTO v_items FROM (
        SELECT e.enquiry_id, e.enquiry_number, e.applicant_name, e.guardian_name, e.phone, e.email, e.source,
               e.stage, e.desired_class_id, c.name AS desired_class_name, e.next_followup_at,
               e.converted_student_id, e.created_at
          FROM academics.enquiry e LEFT JOIN academics.school_class c ON c.class_id=e.desired_class_id
         WHERE e.tenant_id=p_tenant_id AND (v_stage IS NULL OR e.stage=v_stage)
           AND (v_search='' OR lower(e.applicant_name) LIKE '%'||v_search||'%' OR lower(e.enquiry_number) LIKE '%'||v_search||'%')
         ORDER BY e.created_at DESC LIMIT v_size OFFSET (v_page-1)*v_size) t;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('items',v_items,'page',v_page,'page_size',v_size,'total_count',v_total));
END; $$;

-- Add a follow-up note (optionally advancing the stage).
CREATE OR REPLACE FUNCTION academics.fn_enquiry_followup_add(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_enq bigint := (p_payload->>'EnquiryId')::bigint; v_owner integer;
BEGIN
    IF COALESCE(p_payload->>'Note','')='' THEN RETURN jsonb_build_object('result_code',3,'message','Note is required','data',NULL); END IF;
    SELECT tenant_id INTO v_owner FROM academics.enquiry WHERE enquiry_id=v_enq;
    IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Enquiry not found','data',NULL); END IF;
    IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;

    INSERT INTO academics.enquiry_followup (tenant_id, enquiry_id, note, outcome, created_by)
    VALUES (p_tenant_id, v_enq, p_payload->>'Note', NULLIF(p_payload->>'Outcome',''), NULLIF(p_payload->>'ActorUserId','')::bigint);

    IF COALESCE(p_payload->>'Stage','') <> '' THEN
        UPDATE academics.enquiry SET stage=p_payload->>'Stage', updated_at=now() WHERE enquiry_id=v_enq AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION academics.fn_enquiry_followups(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_enq bigint := (p_payload->>'enquiry_id')::bigint; v_items jsonb; v_owner integer;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.enquiry WHERE enquiry_id=v_enq;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Enquiry not found','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC),'[]'::jsonb) INTO v_items
      FROM (SELECT followup_id, note, outcome, created_at FROM academics.enquiry_followup
             WHERE tenant_id=p_tenant_id AND enquiry_id=v_enq) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v_items));
END; $$;

-- Convert an enquiry into a Student (reuses fn_student_save). Idempotent-ish:
-- refuses if already converted. Sets stage=Admitted and links the new student.
CREATE OR REPLACE FUNCTION academics.fn_enquiry_convert(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_enq bigint := (p_payload->>'EnquiryId')::bigint; e academics.enquiry%ROWTYPE;
        v_firstname text; v_lastname text; v_student_payload jsonb; v_save jsonb; v_student_id bigint;
BEGIN
    SELECT * INTO e FROM academics.enquiry WHERE enquiry_id=v_enq AND tenant_id=p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('result_code',4,'message','Enquiry not found','data',NULL); END IF;
    IF e.converted_student_id IS NOT NULL THEN
        RETURN jsonb_build_object('result_code',7,'message','Enquiry already converted','data',jsonb_build_object('student_id',e.converted_student_id));
    END IF;

    -- Split applicant_name into first/last (best-effort); allow override via payload.
    v_firstname := COALESCE(NULLIF(p_payload->>'FirstName',''), split_part(e.applicant_name,' ',1));
    v_lastname  := COALESCE(NULLIF(p_payload->>'LastName',''),
                            NULLIF(trim(substring(e.applicant_name from position(' ' in e.applicant_name))),''),
                            v_firstname);

    v_student_payload := jsonb_build_object(
        'FirstName', v_firstname, 'LastName', v_lastname,
        'Email', e.email, 'Phone', e.phone, 'ClassId', e.desired_class_id,
        'ActorUserId', p_payload->>'ActorUserId');

    v_save := academics.fn_student_save(p_tenant_id, v_student_payload);
    IF (v_save->>'result_code')::int <> 0 THEN
        RETURN v_save; -- propagate the student-save error envelope
    END IF;
    v_student_id := (v_save->'data'->>'student_id')::bigint;

    UPDATE academics.enquiry SET stage='Admitted', converted_student_id=v_student_id, updated_at=now()
     WHERE enquiry_id=v_enq AND tenant_id=p_tenant_id;

    RETURN jsonb_build_object('result_code',0,'message','Converted',
        'data',jsonb_build_object('enquiry_id',v_enq,'student_id',v_student_id,
                                  'admission_number', v_save->'data'->>'admission_number'));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Simple funnel aggregate for dashboards.
CREATE OR REPLACE FUNCTION academics.fn_admission_funnel(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    SELECT COALESCE(jsonb_object_agg(stage, cnt),'{}'::jsonb) INTO v
      FROM (SELECT stage, count(*) cnt FROM academics.enquiry WHERE tenant_id=p_tenant_id GROUP BY stage) s;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',v);
END; $$;
