-- =============================================================================
-- EduNestIO :: 01_schema.sql
-- Schemas, tables, keys, constraints, defaults, comments.
-- Conventions: snake_case; UTC timestamptz; NUMERIC for money; tenant-scoped
-- uniqueness; created_at/updated_at/created_by/updated_by on mutable tables.
-- Run against the 'edunestio' database.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS core;        -- platform, tenancy, identity, audit
CREATE SCHEMA IF NOT EXISTS academics;   -- academic setup + students

-- -----------------------------------------------------------------------------
-- PLATFORM / TENANCY
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.tenant (
    tenant_id        serial       PRIMARY KEY,
    name             varchar(200) NOT NULL,
    code             varchar(50)  NOT NULL,
    status           varchar(20)  NOT NULL DEFAULT 'Active',  -- Active|Suspended|Trial
    subscription_plan varchar(50) NOT NULL DEFAULT 'Trial',
    trial_ends_at    timestamptz  NULL,
    locale           varchar(20)  NOT NULL DEFAULT 'en-US',
    time_zone        varchar(60)  NOT NULL DEFAULT 'UTC',
    currency_code    varchar(3)   NOT NULL DEFAULT 'USD',
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NULL,
    CONSTRAINT uq_tenant_code UNIQUE (code),
    CONSTRAINT ck_tenant_status CHECK (status IN ('Active','Suspended','Trial'))
);
COMMENT ON TABLE core.tenant IS 'A school tenant on the platform. Root of tenant ownership.';

CREATE TABLE IF NOT EXISTS core.campus (
    campus_id   serial       PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name        varchar(200) NOT NULL,
    code        varchar(50)  NOT NULL,
    address     varchar(500) NULL,
    is_primary  boolean      NOT NULL DEFAULT false,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NULL,
    CONSTRAINT uq_campus_code UNIQUE (tenant_id, code)
);
COMMENT ON TABLE core.campus IS 'A branch/campus belonging to a tenant.';

-- -----------------------------------------------------------------------------
-- IDENTITY: users, roles, permissions, mappings, sessions
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.app_user (
    user_id        bigserial    PRIMARY KEY,
    tenant_id      integer      NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT, -- NULL for platform super admin
    username       varchar(150) NOT NULL,
    email          varchar(256) NULL,
    full_name      varchar(200) NULL,
    password_hash  varchar(500) NOT NULL,   -- PBKDF2 hash (never plaintext)
    password_salt  varchar(200) NOT NULL,
    is_active      boolean      NOT NULL DEFAULT true,
    failed_attempts integer     NOT NULL DEFAULT 0,
    locked_until   timestamptz  NULL,
    last_login_at  timestamptz  NULL,
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NULL,
    created_by     bigint       NULL,
    updated_by     bigint       NULL,
    -- Username unique per tenant; platform admins (tenant_id NULL) unique globally
    CONSTRAINT uq_user_username UNIQUE (tenant_id, username)
);
COMMENT ON TABLE core.app_user IS 'Authenticatable user. tenant_id NULL = platform super admin.';

CREATE TABLE IF NOT EXISTS core.role (
    role_id     serial       PRIMARY KEY,
    name        varchar(80)  NOT NULL,
    description varchar(300) NULL,
    is_system   boolean      NOT NULL DEFAULT true,
    CONSTRAINT uq_role_name UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS core.permission (
    permission_id serial       PRIMARY KEY,
    code          varchar(120) NOT NULL,   -- e.g. 'student.create'
    module        varchar(80)  NOT NULL,
    description   varchar(300) NULL,
    CONSTRAINT uq_permission_code UNIQUE (code)
);

CREATE TABLE IF NOT EXISTS core.role_permission (
    role_id       integer NOT NULL REFERENCES core.role(role_id) ON DELETE CASCADE,
    permission_id integer NOT NULL REFERENCES core.permission(permission_id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS core.user_role (
    user_id integer NULL,   -- bigint cast handled in functions
    role_id integer NOT NULL REFERENCES core.role(role_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);
COMMENT ON TABLE core.user_role IS 'Assigns roles to users. user_id references core.app_user.user_id.';

CREATE TABLE IF NOT EXISTS core.user_session (
    session_id   bigserial    PRIMARY KEY,
    user_id      bigint       NOT NULL REFERENCES core.app_user(user_id) ON DELETE CASCADE,
    tenant_id    integer      NULL,
    token        varchar(128) NOT NULL,
    expires_at   timestamptz  NOT NULL,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    revoked_at   timestamptz  NULL,
    CONSTRAINT uq_session_token UNIQUE (token)
);
COMMENT ON TABLE core.user_session IS 'Opaque bearer session tokens with expiry (server-side validated).';

-- -----------------------------------------------------------------------------
-- AUDIT (append-only)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.audit_log (
    audit_id       bigserial    PRIMARY KEY,
    tenant_id      integer      NULL,
    actor_user_id  bigint       NULL,
    action         varchar(80)  NOT NULL,
    entity         varchar(80)  NOT NULL,
    entity_id      varchar(80)  NULL,
    correlation_id varchar(64)  NULL,
    changes        jsonb        NULL,       -- safe before/after, no secrets
    created_at     timestamptz  NOT NULL DEFAULT now()
);
COMMENT ON TABLE core.audit_log IS 'Append-only audit trail of sensitive actions.';

-- -----------------------------------------------------------------------------
-- ACADEMIC SETUP (minimal: needed to reference classes/sections from students)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.school_class (
    class_id   bigserial    PRIMARY KEY,
    tenant_id  integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    name       varchar(100) NOT NULL,       -- e.g. 'Grade 1'
    ordinal    integer      NOT NULL DEFAULT 0,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NULL,
    CONSTRAINT uq_class_name UNIQUE (tenant_id, name)
);

CREATE TABLE IF NOT EXISTS academics.class_section (
    section_id bigserial    PRIMARY KEY,
    tenant_id  integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    class_id   bigint       NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    name       varchar(50)  NOT NULL,       -- e.g. 'A'
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NULL,
    CONSTRAINT uq_section_name UNIQUE (tenant_id, class_id, name)
);

-- -----------------------------------------------------------------------------
-- STUDENT RECORDS (vertical slice)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS academics.student (
    student_id       bigserial    PRIMARY KEY,
    tenant_id        integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    admission_number varchar(50)  NOT NULL,
    first_name       varchar(100) NOT NULL,
    middle_name      varchar(100) NULL,
    last_name        varchar(100) NOT NULL,
    gender           varchar(20)  NULL,
    date_of_birth    date         NULL,
    email            varchar(256) NULL,
    phone            varchar(40)  NULL,
    address_line1    varchar(200) NULL,
    address_line2    varchar(200) NULL,
    city             varchar(100) NULL,
    state            varchar(100) NULL,
    postal_code      varchar(20)  NULL,
    class_id         bigint       NULL REFERENCES academics.school_class(class_id) ON DELETE SET NULL,
    section_id       bigint       NULL REFERENCES academics.class_section(section_id) ON DELETE SET NULL,
    status           varchar(20)  NOT NULL DEFAULT 'Active',  -- Active|Inactive|Withdrawn|Graduated
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NULL,
    created_by       bigint       NULL,
    updated_by       bigint       NULL,
    -- Admission number unique WITHIN a tenant (tenant-scoped uniqueness)
    CONSTRAINT uq_student_admission UNIQUE (tenant_id, admission_number),
    CONSTRAINT ck_student_status CHECK (status IN ('Active','Inactive','Withdrawn','Graduated'))
);
COMMENT ON TABLE academics.student IS 'Student master record, tenant-owned.';

-- Document-numbering counters (race-safe via function, see 03_functions.sql)
CREATE TABLE IF NOT EXISTS core.number_sequence (
    tenant_id   integer     NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE CASCADE,
    seq_key     varchar(60) NOT NULL,     -- e.g. 'admission_number'
    prefix      varchar(20) NOT NULL DEFAULT '',
    next_value  bigint      NOT NULL DEFAULT 1,
    padding     integer     NOT NULL DEFAULT 4,
    PRIMARY KEY (tenant_id, seq_key)
);
COMMENT ON TABLE core.number_sequence IS 'Per-tenant counters for race-safe document numbering.';
