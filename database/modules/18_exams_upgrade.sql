-- =============================================================================
-- EduNestIO :: Module — Exams upgrade (18_exams_upgrade.sql)
-- Upgrades the Exams module to match the product design:
--   * exam_type, academic_year, start/end dates, description on the exam
--   * MULTI-CLASS exams via academics.exam_class (an exam can span many classes)
--   * derived lifecycle status (Upcoming / Ongoing / Completed / Published)
-- Backward-compatible + idempotent. Keeps the legacy exam.class_id (now nullable)
-- and backfills exam_class from it. Apply after modules 10 and 14.
-- =============================================================================

-- ---- New columns on exam (all nullable / defaulted -> legacy rows stay valid) --
ALTER TABLE academics.exam ADD COLUMN IF NOT EXISTS exam_type        varchar(40)  NULL;
ALTER TABLE academics.exam ADD COLUMN IF NOT EXISTS academic_year_id bigint       NULL;
ALTER TABLE academics.exam ADD COLUMN IF NOT EXISTS start_date       date         NULL;
ALTER TABLE academics.exam ADD COLUMN IF NOT EXISTS end_date         date         NULL;
ALTER TABLE academics.exam ADD COLUMN IF NOT EXISTS description      varchar(500) NULL;

-- Legacy single class becomes optional (multi-class is the new model).
ALTER TABLE academics.exam ALTER COLUMN class_id DROP NOT NULL;

-- Seed start_date from the old exam_date where present (one-time, safe).
UPDATE academics.exam SET start_date = exam_date WHERE start_date IS NULL AND exam_date IS NOT NULL;

-- FK for academic_year (added once).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exam_academic_year_id_fkey') THEN
        ALTER TABLE academics.exam
            ADD CONSTRAINT exam_academic_year_id_fkey
            FOREIGN KEY (academic_year_id) REFERENCES academics.academic_year(academic_year_id) ON DELETE SET NULL;
    END IF;
END $$;

-- Replace the old (tenant,class,name) uniqueness with (tenant,name,year):
-- an exam name is unique within a tenant+academic year, regardless of classes.
ALTER TABLE academics.exam DROP CONSTRAINT IF EXISTS uq_exam;
CREATE UNIQUE INDEX IF NOT EXISTS uq_exam_name_year
    ON academics.exam (tenant_id, lower(name), COALESCE(academic_year_id, 0));

-- ---- Multi-class join ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.exam_class (
    exam_class_id bigserial PRIMARY KEY,
    tenant_id     integer   NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    exam_id       bigint    NOT NULL REFERENCES academics.exam(exam_id) ON DELETE CASCADE,
    class_id      bigint    NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    CONSTRAINT uq_exam_class UNIQUE (exam_id, class_id)
);
CREATE INDEX IF NOT EXISTS ix_exam_class_exam ON academics.exam_class (tenant_id, exam_id);

-- Backfill: every legacy exam with a class_id gets an exam_class row.
INSERT INTO academics.exam_class (tenant_id, exam_id, class_id)
SELECT e.tenant_id, e.exam_id, e.class_id FROM academics.exam e
 WHERE e.class_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM academics.exam_class ec WHERE ec.exam_id = e.exam_id AND ec.class_id = e.class_id);

-- =============================================================================
-- fn_exam_save (REPLACES): multi-class + new fields.
-- Payload: { ExamId?, Name, ExamType, AcademicYearId?, StartDate?, EndDate?,
--            Description?, ClassIds:[...] }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_id    bigint := NULLIF(p_payload->>'ExamId','')::bigint;
    v_year  bigint := NULLIF(p_payload->>'AcademicYearId','')::bigint;
    v_owner integer;
    v_cls   bigint;
    v_first bigint;
BEGIN
    IF COALESCE(p_payload->>'Name','') = '' THEN
        RETURN jsonb_build_object('result_code',3,'message','Exam name is required','data',NULL);
    END IF;
    IF v_year IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM academics.academic_year WHERE academic_year_id=v_year AND tenant_id=p_tenant_id) THEN
        RETURN jsonb_build_object('result_code',3,'message','Invalid academic year','data',NULL);
    END IF;

    -- Validate every class belongs to the tenant; capture the first as legacy class_id.
    FOR v_cls IN SELECT (jsonb_array_elements_text(COALESCE(p_payload->'ClassIds','[]'::jsonb)))::bigint LOOP
        IF NOT EXISTS (SELECT 1 FROM academics.school_class WHERE class_id=v_cls AND tenant_id=p_tenant_id) THEN
            RETURN jsonb_build_object('result_code',3,'message','Invalid class for this school','data',NULL);
        END IF;
        IF v_first IS NULL THEN v_first := v_cls; END IF;
    END LOOP;

    IF v_id IS NULL THEN
        INSERT INTO academics.exam (tenant_id, name, class_id, exam_type, academic_year_id, start_date, end_date, description)
        VALUES (p_tenant_id, p_payload->>'Name', v_first, NULLIF(p_payload->>'ExamType',''), v_year,
                NULLIF(p_payload->>'StartDate','')::date, NULLIF(p_payload->>'EndDate','')::date,
                NULLIF(p_payload->>'Description',''))
        RETURNING exam_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE academics.exam SET name=p_payload->>'Name', class_id=v_first,
               exam_type=NULLIF(p_payload->>'ExamType',''), academic_year_id=v_year,
               start_date=NULLIF(p_payload->>'StartDate','')::date, end_date=NULLIF(p_payload->>'EndDate','')::date,
               description=NULLIF(p_payload->>'Description',''), updated_at=now()
         WHERE exam_id=v_id AND tenant_id=p_tenant_id;
    END IF;

    -- Re-sync the exam_class set to exactly the supplied ClassIds (if provided).
    IF p_payload ? 'ClassIds' THEN
        DELETE FROM academics.exam_class WHERE exam_id=v_id AND tenant_id=p_tenant_id;
        INSERT INTO academics.exam_class (tenant_id, exam_id, class_id)
        SELECT p_tenant_id, v_id, (jsonb_array_elements_text(p_payload->'ClassIds'))::bigint
        ON CONFLICT (exam_id, class_id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('exam_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','An exam with this name already exists for the year','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- =============================================================================
-- fn_exam_list (REPLACES): rich list with derived status + filters.
-- Payload: { search?, class_id?, academic_year_id?, status?, exam_type? }
-- status in {Upcoming, Ongoing, Completed, Published}
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_search text   := lower(COALESCE(p_payload->>'search',''));
    v_class  bigint := NULLIF(p_payload->>'class_id','')::bigint;
    v_year   bigint := NULLIF(p_payload->>'academic_year_id','')::bigint;
    v_status text   := NULLIF(p_payload->>'status','');
    v_type   text   := NULLIF(p_payload->>'exam_type','');
    v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.start_date DESC NULLS LAST, t.name),'[]'::jsonb) INTO v FROM (
        SELECT e.exam_id, e.name, e.exam_type, e.academic_year_id, ay.name AS academic_year_name,
               e.start_date, e.end_date, e.description, e.is_published,
               -- Multi-class summary.
               (SELECT COALESCE(jsonb_agg(jsonb_build_object('class_id',c.class_id,'name',c.name) ORDER BY c.name),'[]'::jsonb)
                  FROM academics.exam_class ec JOIN academics.school_class c ON c.class_id=ec.class_id
                 WHERE ec.exam_id=e.exam_id) AS classes,
               (SELECT count(*) FROM academics.exam_class ec WHERE ec.exam_id=e.exam_id) AS class_count,
               -- Derived lifecycle status.
               CASE
                 WHEN e.is_published THEN 'Published'
                 WHEN e.end_date IS NOT NULL AND e.end_date < current_date THEN 'Completed'
                 WHEN e.start_date IS NOT NULL AND e.start_date <= current_date
                      AND (e.end_date IS NULL OR e.end_date >= current_date) THEN 'Ongoing'
                 ELSE 'Upcoming'
               END AS status
          FROM academics.exam e
          LEFT JOIN academics.academic_year ay ON ay.academic_year_id=e.academic_year_id
         WHERE e.tenant_id=p_tenant_id
           AND (v_year IS NULL OR e.academic_year_id=v_year)
           AND (v_type IS NULL OR e.exam_type=v_type)
           AND (v_search='' OR lower(e.name) LIKE '%'||v_search||'%')
           AND (v_class IS NULL OR EXISTS (SELECT 1 FROM academics.exam_class ec WHERE ec.exam_id=e.exam_id AND ec.class_id=v_class))
    ) t
    WHERE (v_status IS NULL OR t.status = v_status);
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- =============================================================================
-- fn_exam_get : one exam with its classes (for edit / wizard).
-- Payload: { exam_id }
-- =============================================================================
CREATE OR REPLACE FUNCTION academics.fn_exam_get(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := (p_payload->>'exam_id')::bigint; v_owner integer; v jsonb;
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.exam WHERE exam_id=v_id;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Exam not found','data',NULL);
    END IF;
    SELECT to_jsonb(x) INTO v FROM (
        SELECT e.exam_id, e.name, e.exam_type, e.academic_year_id, ay.name AS academic_year_name,
               e.start_date, e.end_date, e.description, e.is_published,
               (SELECT COALESCE(jsonb_agg(ec.class_id ORDER BY ec.class_id),'[]'::jsonb)
                  FROM academics.exam_class ec WHERE ec.exam_id=e.exam_id) AS class_ids,
               (SELECT COALESCE(jsonb_agg(jsonb_build_object('class_id',c.class_id,'name',c.name) ORDER BY c.name),'[]'::jsonb)
                  FROM academics.exam_class ec JOIN academics.school_class c ON c.class_id=ec.class_id
                 WHERE ec.exam_id=e.exam_id) AS classes
          FROM academics.exam e
          LEFT JOIN academics.academic_year ay ON ay.academic_year_id=e.academic_year_id
         WHERE e.exam_id=v_id AND e.tenant_id=p_tenant_id
    ) x;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',v);
END; $$;
