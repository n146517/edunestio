-- =============================================================================
-- EduNestIO :: Module — Fees & Finance (13_fees.sql)
-- Fee heads, fee structures (per class), student fee assignments (invoices/demand),
-- payments (receipts with race-safe numbering), balances, defaulters, collection
-- report. Money is NUMERIC(12,2) (never float). Idempotent; apply after modules 10-12.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS finance;

-- ---- Tables -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS finance.fee_head (
    fee_head_id bigserial    PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name        varchar(120) NOT NULL,            -- e.g. 'Tuition', 'Transport'
    code        varchar(40)  NOT NULL,
    is_active   boolean      NOT NULL DEFAULT true,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NULL,
    CONSTRAINT uq_fee_head_code UNIQUE (tenant_id, code)
);
COMMENT ON TABLE finance.fee_head IS 'A fee category (tuition, transport, lab, ...).';

CREATE TABLE IF NOT EXISTS finance.fee_structure (
    fee_structure_id bigserial  PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    fee_head_id bigint       NOT NULL REFERENCES finance.fee_head(fee_head_id) ON DELETE RESTRICT,
    class_id    bigint       NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,  -- null = all classes
    amount      numeric(12,2) NOT NULL CHECK (amount >= 0),
    period      varchar(20)  NOT NULL DEFAULT 'Annual', -- Annual|Term|Monthly|OneTime
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NULL,
    CONSTRAINT uq_fee_structure UNIQUE (tenant_id, fee_head_id, class_id, period)
);
COMMENT ON TABLE finance.fee_structure IS 'Amount for a fee head, optionally per class.';

-- A student's demand for a fee (invoice line). balance derived = amount - paid.
CREATE TABLE IF NOT EXISTS finance.fee_assignment (
    fee_assignment_id bigserial PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    student_id  bigint       NOT NULL REFERENCES academics.student(student_id) ON DELETE CASCADE,
    fee_head_id bigint       NOT NULL REFERENCES finance.fee_head(fee_head_id) ON DELETE RESTRICT,
    amount      numeric(12,2) NOT NULL CHECK (amount >= 0),
    discount    numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    paid        numeric(12,2) NOT NULL DEFAULT 0 CHECK (paid >= 0),
    due_date    date         NULL,
    status      varchar(20)  NOT NULL DEFAULT 'Pending', -- Pending|Partial|Paid|Waived
    note        varchar(300) NULL,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NULL,
    created_by  bigint       NULL,
    CONSTRAINT ck_fee_assignment_status CHECK (status IN ('Pending','Partial','Paid','Waived'))
);
COMMENT ON TABLE finance.fee_assignment IS 'Per-student fee demand; net payable = amount - discount.';

-- A payment receipt (can cover multiple assignments via allocations).
CREATE TABLE IF NOT EXISTS finance.payment (
    payment_id     bigserial    PRIMARY KEY,
    tenant_id      integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    student_id     bigint       NOT NULL REFERENCES academics.student(student_id) ON DELETE RESTRICT,
    receipt_number varchar(50)  NOT NULL,
    amount         numeric(12,2) NOT NULL CHECK (amount > 0),
    mode           varchar(30)  NOT NULL DEFAULT 'Cash', -- Cash|Card|Online|Cheque|BankTransfer
    reference      varchar(100) NULL,
    paid_at        timestamptz  NOT NULL DEFAULT now(),
    reversed       boolean      NOT NULL DEFAULT false,
    reversed_reason varchar(300) NULL,
    created_by     bigint       NULL,
    CONSTRAINT uq_receipt_number UNIQUE (tenant_id, receipt_number)
);
COMMENT ON TABLE finance.payment IS 'A fee receipt; never store card data (reference text only).';

CREATE TABLE IF NOT EXISTS finance.payment_allocation (
    allocation_id     bigserial PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    payment_id  bigint       NOT NULL REFERENCES finance.payment(payment_id) ON DELETE CASCADE,
    fee_assignment_id bigint  NOT NULL REFERENCES finance.fee_assignment(fee_assignment_id) ON DELETE RESTRICT,
    amount      numeric(12,2) NOT NULL CHECK (amount > 0)
);

-- ---- Indexes ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_fee_head_tenant       ON finance.fee_head (tenant_id, is_active);
CREATE INDEX IF NOT EXISTS ix_fee_structure_tenant  ON finance.fee_structure (tenant_id, class_id);
CREATE INDEX IF NOT EXISTS ix_fee_assignment_student ON finance.fee_assignment (tenant_id, student_id);
CREATE INDEX IF NOT EXISTS ix_fee_assignment_status ON finance.fee_assignment (tenant_id, status);
CREATE INDEX IF NOT EXISTS ix_payment_tenant_date   ON finance.payment (tenant_id, paid_at DESC);
CREATE INDEX IF NOT EXISTS ix_payment_student       ON finance.payment (tenant_id, student_id);
CREATE INDEX IF NOT EXISTS ix_alloc_payment         ON finance.payment_allocation (tenant_id, payment_id);

-- ---- Receipt numbering sequence seed ---------------------------------------
INSERT INTO core.number_sequence (tenant_id, seq_key, prefix, next_value, padding)
SELECT t.tenant_id, 'receipt_number', 'RCPT-', 1, 5 FROM core.tenant t
ON CONFLICT (tenant_id, seq_key) DO NOTHING;

-- ---- Permissions ------------------------------------------------------------
INSERT INTO core.permission (code, module, description) VALUES
 ('fee.view',    'Fees', 'View fee structures, demands, balances, reports'),
 ('fee.manage',  'Fees', 'Manage fee heads/structures and assign fees'),
 ('fee.collect', 'Fees', 'Record payments / issue receipts'),
 ('fee.reverse', 'Fees', 'Reverse a payment (authorized)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('SchoolAdmin','Principal','Accountant')
   AND p.code IN ('fee.view','fee.manage','fee.collect','fee.reverse')
ON CONFLICT DO NOTHING;

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM core.role r CROSS JOIN core.permission p
 WHERE r.name = 'Receptionist' AND p.code IN ('fee.view','fee.collect')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Functions
-- =============================================================================

-- Fee head save/list
CREATE OR REPLACE FUNCTION finance.fn_fee_head_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'FeeHeadId','')::bigint; v_owner integer;
BEGIN
    IF COALESCE(p_payload->>'Name','')='' OR COALESCE(p_payload->>'Code','')='' THEN
        RETURN jsonb_build_object('result_code',3,'message','Name and code are required','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO finance.fee_head (tenant_id,name,code,is_active)
        VALUES (p_tenant_id,p_payload->>'Name',p_payload->>'Code',COALESCE((p_payload->>'IsActive')::boolean,true))
        RETURNING fee_head_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM finance.fee_head WHERE fee_head_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE finance.fee_head SET name=p_payload->>'Name', code=p_payload->>'Code',
               is_active=COALESCE((p_payload->>'IsActive')::boolean,is_active), updated_at=now()
         WHERE fee_head_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('fee_head_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','Fee head code already exists','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION finance.fn_fee_head_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.name),'[]'::jsonb) INTO v
      FROM (SELECT fee_head_id,name,code,is_active FROM finance.fee_head WHERE tenant_id=p_tenant_id) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Fee structure save/list
CREATE OR REPLACE FUNCTION finance.fn_fee_structure_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'FeeStructureId','')::bigint; v_head bigint := (p_payload->>'FeeHeadId')::bigint;
        v_owner integer; v_head_owner integer;
BEGIN
    IF v_head IS NULL OR NULLIF(p_payload->>'Amount','') IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','Fee head and amount are required','data',NULL);
    END IF;
    SELECT tenant_id INTO v_head_owner FROM finance.fee_head WHERE fee_head_id=v_head;
    IF v_head_owner IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid fee head for tenant','data',NULL);
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO finance.fee_structure (tenant_id,fee_head_id,class_id,amount,period)
        VALUES (p_tenant_id,v_head,NULLIF(p_payload->>'ClassId','')::bigint,(p_payload->>'Amount')::numeric,
                COALESCE(NULLIF(p_payload->>'Period',''),'Annual'))
        RETURNING fee_structure_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM finance.fee_structure WHERE fee_structure_id=v_id;
        IF v_owner IS NULL THEN RETURN jsonb_build_object('result_code',4,'message','Not found','data',NULL); END IF;
        IF v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',8,'message','Tenant access violation','data',NULL); END IF;
        UPDATE finance.fee_structure SET fee_head_id=v_head, class_id=NULLIF(p_payload->>'ClassId','')::bigint,
               amount=(p_payload->>'Amount')::numeric, period=COALESCE(NULLIF(p_payload->>'Period',''),period), updated_at=now()
         WHERE fee_structure_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('fee_structure_id',v_id));
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('result_code',7,'message','Duplicate fee structure','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

CREATE OR REPLACE FUNCTION finance.fn_fee_structure_list(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.fee_head_name, t.class_name),'[]'::jsonb) INTO v FROM (
        SELECT fs.fee_structure_id, fs.fee_head_id, fh.name AS fee_head_name, fs.class_id, c.name AS class_name,
               fs.amount, fs.period
          FROM finance.fee_structure fs
          JOIN finance.fee_head fh ON fh.fee_head_id=fs.fee_head_id
          LEFT JOIN academics.school_class c ON c.class_id=fs.class_id
         WHERE fs.tenant_id=p_tenant_id) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Assign a fee to a student (creates a demand). Payload: {StudentId,FeeHeadId,Amount,Discount,DueDate,Note,ActorUserId}
CREATE OR REPLACE FUNCTION finance.fn_fee_assign(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_student bigint := (p_payload->>'StudentId')::bigint; v_head bigint := (p_payload->>'FeeHeadId')::bigint;
        v_sowner integer; v_howner integer; v_id bigint;
BEGIN
    IF v_student IS NULL OR v_head IS NULL OR NULLIF(p_payload->>'Amount','') IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','Student, fee head and amount are required','data',NULL);
    END IF;
    SELECT tenant_id INTO v_sowner FROM academics.student WHERE student_id=v_student;
    SELECT tenant_id INTO v_howner FROM finance.fee_head WHERE fee_head_id=v_head;
    IF v_sowner IS DISTINCT FROM p_tenant_id OR v_howner IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid student or fee head for tenant','data',NULL);
    END IF;
    INSERT INTO finance.fee_assignment (tenant_id,student_id,fee_head_id,amount,discount,due_date,note,created_by)
    VALUES (p_tenant_id,v_student,v_head,(p_payload->>'Amount')::numeric,COALESCE((p_payload->>'Discount')::numeric,0),
            NULLIF(p_payload->>'DueDate','')::date,NULLIF(p_payload->>'Note',''),NULLIF(p_payload->>'ActorUserId','')::bigint)
    RETURNING fee_assignment_id INTO v_id;
    RETURN jsonb_build_object('result_code',0,'message','Assigned','data',jsonb_build_object('fee_assignment_id',v_id));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Student fee ledger: assignments with net/paid/balance + totals.
CREATE OR REPLACE FUNCTION finance.fn_fee_ledger(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_student bigint := (p_payload->>'student_id')::bigint; v_owner integer; v_items jsonb;
        v_total numeric(12,2); v_paid numeric(12,2); v_balance numeric(12,2);
BEGIN
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_student;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',4,'message','Student not found','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at),'[]'::jsonb) INTO v_items FROM (
        SELECT fa.fee_assignment_id, fh.name AS fee_head_name, fa.amount, fa.discount, fa.paid,
               (fa.amount - fa.discount - fa.paid) AS balance, fa.due_date, fa.status, fa.created_at
          FROM finance.fee_assignment fa JOIN finance.fee_head fh ON fh.fee_head_id=fa.fee_head_id
         WHERE fa.tenant_id=p_tenant_id AND fa.student_id=v_student) t;

    SELECT COALESCE(sum(amount-discount),0), COALESCE(sum(paid),0), COALESCE(sum(amount-discount-paid),0)
      INTO v_total, v_paid, v_balance
      FROM finance.fee_assignment WHERE tenant_id=p_tenant_id AND student_id=v_student;

    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('items',v_items,'net_total',v_total,'paid_total',v_paid,'balance',v_balance));
END; $$;

-- Record a payment. Auto-generates receipt number; allocates to given assignments
-- (or oldest-first if none specified). Updates each assignment's paid/status.
-- Payload: {StudentId, Amount, Mode, Reference, Allocations:[{FeeAssignmentId,Amount}], ActorUserId}
CREATE OR REPLACE FUNCTION finance.fn_payment_record(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_student bigint := (p_payload->>'StudentId')::bigint; v_amount numeric(12,2) := (p_payload->>'Amount')::numeric;
        v_owner integer; v_num text; v_numenv jsonb; v_payment_id bigint; v_alloc jsonb; v_remaining numeric(12,2);
        v_fa finance.fee_assignment%ROWTYPE; v_take numeric(12,2); v_assign_id bigint; v_assign_bal numeric(12,2);
BEGIN
    IF v_student IS NULL OR v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('result_code',3,'message','Student and positive amount are required','data',NULL);
    END IF;
    SELECT tenant_id INTO v_owner FROM academics.student WHERE student_id=v_student;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
        RETURN jsonb_build_object('result_code',8,'message','Invalid student for tenant','data',NULL);
    END IF;

    v_numenv := core.fn_next_document_number(p_tenant_id, '{"seq_key":"receipt_number"}');
    v_num := v_numenv->'data'->>'number';

    INSERT INTO finance.payment (tenant_id,student_id,receipt_number,amount,mode,reference,created_by)
    VALUES (p_tenant_id,v_student,v_num,v_amount,COALESCE(NULLIF(p_payload->>'Mode',''),'Cash'),
            NULLIF(p_payload->>'Reference',''),NULLIF(p_payload->>'ActorUserId','')::bigint)
    RETURNING payment_id INTO v_payment_id;

    v_remaining := v_amount;

    IF jsonb_typeof(p_payload->'Allocations') = 'array' AND jsonb_array_length(p_payload->'Allocations') > 0 THEN
        -- Explicit allocations.
        FOR v_alloc IN SELECT * FROM jsonb_array_elements(p_payload->'Allocations') LOOP
            v_assign_id := (v_alloc->>'FeeAssignmentId')::bigint;
            SELECT * INTO v_fa FROM finance.fee_assignment WHERE fee_assignment_id=v_assign_id AND tenant_id=p_tenant_id AND student_id=v_student;
            IF NOT FOUND THEN CONTINUE; END IF;
            v_assign_bal := v_fa.amount - v_fa.discount - v_fa.paid;
            v_take := LEAST((v_alloc->>'Amount')::numeric, v_assign_bal, v_remaining);
            IF v_take <= 0 THEN CONTINUE; END IF;
            INSERT INTO finance.payment_allocation (tenant_id,payment_id,fee_assignment_id,amount)
            VALUES (p_tenant_id,v_payment_id,v_assign_id,v_take);
            UPDATE finance.fee_assignment SET paid=paid+v_take,
                   status = CASE WHEN paid+v_take >= amount-discount THEN 'Paid' ELSE 'Partial' END, updated_at=now()
             WHERE fee_assignment_id=v_assign_id;
            v_remaining := v_remaining - v_take;
        END LOOP;
    ELSE
        -- Auto-allocate oldest unpaid first.
        FOR v_fa IN SELECT * FROM finance.fee_assignment
                     WHERE tenant_id=p_tenant_id AND student_id=v_student AND status IN ('Pending','Partial')
                     ORDER BY created_at LOOP
            EXIT WHEN v_remaining <= 0;
            v_assign_bal := v_fa.amount - v_fa.discount - v_fa.paid;
            v_take := LEAST(v_assign_bal, v_remaining);
            IF v_take <= 0 THEN CONTINUE; END IF;
            INSERT INTO finance.payment_allocation (tenant_id,payment_id,fee_assignment_id,amount)
            VALUES (p_tenant_id,v_payment_id,v_fa.fee_assignment_id,v_take);
            UPDATE finance.fee_assignment SET paid=paid+v_take,
                   status = CASE WHEN paid+v_take >= amount-discount THEN 'Paid' ELSE 'Partial' END, updated_at=now()
             WHERE fee_assignment_id=v_fa.fee_assignment_id;
            v_remaining := v_remaining - v_take;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('result_code',0,'message','Payment recorded',
        'data',jsonb_build_object('payment_id',v_payment_id,'receipt_number',v_num,
                                  'allocated',v_amount - v_remaining,'unallocated',v_remaining));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- Defaulter list (students with outstanding balance). Payload: {class_id?}
CREATE OR REPLACE FUNCTION finance.fn_fee_defaulters(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint; v jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.balance DESC),'[]'::jsonb) INTO v FROM (
        SELECT s.student_id, s.admission_number, s.first_name, s.last_name, c.name AS class_name,
               sum(fa.amount-fa.discount-fa.paid) AS balance
          FROM finance.fee_assignment fa
          JOIN academics.student s ON s.student_id=fa.student_id
          LEFT JOIN academics.school_class c ON c.class_id=s.class_id
         WHERE fa.tenant_id=p_tenant_id AND fa.status IN ('Pending','Partial')
           AND (v_class IS NULL OR s.class_id=v_class)
         GROUP BY s.student_id, s.admission_number, s.first_name, s.last_name, c.name
        HAVING sum(fa.amount-fa.discount-fa.paid) > 0) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- Collection report between dates. Payload: {from, to}
CREATE OR REPLACE FUNCTION finance.fn_fee_collection(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_from date := COALESCE(NULLIF(p_payload->>'from','')::date, date_trunc('month',current_date)::date);
        v_to date := COALESCE(NULLIF(p_payload->>'to','')::date, current_date);
        v_total numeric(12,2); v_by_mode jsonb; v_count bigint;
BEGIN
    SELECT COALESCE(sum(amount),0), count(*) INTO v_total, v_count
      FROM finance.payment WHERE tenant_id=p_tenant_id AND reversed=false
        AND paid_at::date BETWEEN v_from AND v_to;
    SELECT COALESCE(jsonb_object_agg(mode,amt),'{}'::jsonb) INTO v_by_mode FROM (
        SELECT mode, sum(amount) amt FROM finance.payment
         WHERE tenant_id=p_tenant_id AND reversed=false AND paid_at::date BETWEEN v_from AND v_to
         GROUP BY mode) s;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('from',v_from,'to',v_to,'total_collected',v_total,'payment_count',v_count,'by_mode',v_by_mode));
END; $$;

-- Reverse a payment (authorized). Payload: {PaymentId, Reason, ActorUserId}
CREATE OR REPLACE FUNCTION finance.fn_payment_reverse(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_pid bigint := (p_payload->>'PaymentId')::bigint; v_owner integer; v_alloc finance.payment_allocation%ROWTYPE;
BEGIN
    SELECT tenant_id INTO v_owner FROM finance.payment WHERE payment_id=v_pid;
    IF v_owner IS NULL OR v_owner<>p_tenant_id THEN RETURN jsonb_build_object('result_code',4,'message','Payment not found','data',NULL); END IF;
    IF (SELECT reversed FROM finance.payment WHERE payment_id=v_pid) THEN
        RETURN jsonb_build_object('result_code',7,'message','Already reversed','data',NULL);
    END IF;

    -- Roll back allocations from the assignments.
    FOR v_alloc IN SELECT * FROM finance.payment_allocation WHERE payment_id=v_pid AND tenant_id=p_tenant_id LOOP
        UPDATE finance.fee_assignment
           SET paid = GREATEST(paid - v_alloc.amount, 0),
               status = CASE WHEN paid - v_alloc.amount <= 0 THEN 'Pending'
                             WHEN paid - v_alloc.amount < amount-discount THEN 'Partial' ELSE 'Paid' END,
               updated_at=now()
         WHERE fee_assignment_id=v_alloc.fee_assignment_id AND tenant_id=p_tenant_id;
    END LOOP;

    UPDATE finance.payment SET reversed=true, reversed_reason=NULLIF(p_payload->>'Reason','') WHERE payment_id=v_pid;
    RETURN jsonb_build_object('result_code',0,'message','Reversed','data',jsonb_build_object('payment_id',v_pid));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;
