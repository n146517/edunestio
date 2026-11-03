-- =============================================================================
-- EduNestIO :: 02_indexes.sql
-- Indexes for foreign keys, tenant filtering, search and reporting.
-- Tenant-scoped indexes lead with tenant_id so every tenant query is covered.
-- =============================================================================

-- Identity
CREATE INDEX IF NOT EXISTS ix_app_user_tenant       ON core.app_user (tenant_id);
CREATE INDEX IF NOT EXISTS ix_app_user_email        ON core.app_user (lower(email));
CREATE INDEX IF NOT EXISTS ix_user_role_user        ON core.user_role (user_id);
CREATE INDEX IF NOT EXISTS ix_role_permission_role  ON core.role_permission (role_id);
CREATE INDEX IF NOT EXISTS ix_user_session_user     ON core.user_session (user_id);
CREATE INDEX IF NOT EXISTS ix_user_session_expires  ON core.user_session (expires_at);

-- Campus
CREATE INDEX IF NOT EXISTS ix_campus_tenant         ON core.campus (tenant_id);

-- Audit (tenant + time for reporting)
CREATE INDEX IF NOT EXISTS ix_audit_tenant_time     ON core.audit_log (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_entity          ON core.audit_log (tenant_id, entity, entity_id);

-- Academic setup
CREATE INDEX IF NOT EXISTS ix_class_tenant          ON academics.school_class (tenant_id, ordinal);
CREATE INDEX IF NOT EXISTS ix_section_tenant_class  ON academics.class_section (tenant_id, class_id);

-- Students: tenant-scoped list + search + filter
CREATE INDEX IF NOT EXISTS ix_student_tenant        ON academics.student (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_student_tenant_class  ON academics.student (tenant_id, class_id);
CREATE INDEX IF NOT EXISTS ix_student_tenant_status ON academics.student (tenant_id, status);
-- Name/admission search (trigram-friendly if pg_trgm available; btree lower() otherwise)
CREATE INDEX IF NOT EXISTS ix_student_name_lower    ON academics.student (tenant_id, lower(last_name), lower(first_name));
CREATE INDEX IF NOT EXISTS ix_student_admission     ON academics.student (tenant_id, admission_number);
