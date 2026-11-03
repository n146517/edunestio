-- =============================================================================
-- EduNestIO :: 05_views.sql
-- Tenant-safe reporting views. Views are always filtered by tenant_id at the
-- query site (the application always passes the authenticated tenant); they never
-- expose cross-tenant data by themselves.
-- =============================================================================

-- Per-tenant student counts by status (dashboard KPI source).
CREATE OR REPLACE VIEW academics.vw_student_counts AS
SELECT tenant_id,
       count(*)                                        AS total_students,
       count(*) FILTER (WHERE status = 'Active')       AS active_students,
       count(*) FILTER (WHERE status = 'Inactive')     AS inactive_students,
       count(*) FILTER (WHERE status = 'Withdrawn')    AS withdrawn_students
  FROM academics.student
 GROUP BY tenant_id;

-- Per-tenant class roster sizes.
CREATE OR REPLACE VIEW academics.vw_class_strength AS
SELECT s.tenant_id, c.class_id, c.name AS class_name, count(s.student_id) AS student_count
  FROM academics.school_class c
  LEFT JOIN academics.student s ON s.class_id = c.class_id AND s.status = 'Active'
 GROUP BY s.tenant_id, c.class_id, c.name;
