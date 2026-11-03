-- =============================================================================
-- EduNestIO :: Module — Student/Guardian read-only academic.view
-- (29_student_academic_view.sql)
-- The student self-service screens (e.g. "My Attendance") need the list of
-- academic years to offer a year filter. That list comes from /academic/years
-- which requires 'academic.view'. Grant Student/Guardian this read-only
-- permission so those pages load. It only exposes setup lists (years/classes/
-- sections) for viewing — not any management action. Idempotent.
-- =============================================================================

INSERT INTO core.role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM core.role r CROSS JOIN core.permission p
 WHERE r.name IN ('Student','Guardian')
   AND p.code = 'academic.view'
ON CONFLICT DO NOTHING;
